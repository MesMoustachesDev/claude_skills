import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { ActiveAgent, PipelineSnapshot, PlanBranch, PlanView, QaRun, ScenarioEvidence, ScenarioFile, SessionActivity, Thumb } from '../types'
import {
  PERSONAS,
  agentEnded,
  callEnded,
  callStarted,
  duration,
  focusStage,
  fromBranch,
  isPipelineAgent,
  isTracked,
  mark,
  maxAttemptsFromConfig,
  parseState,
  roleOf,
  sameSnapshot,
  shortPath,
  stageOwner,
  toolLabel,
} from './model'
import {
  describeBranch,
  emptyBranch,
  isOpen,
  isToolingBranch,
  itemState,
  parseEpic,
  parsePlanMarkdown,
  parseWorktrees,
  summarize,
} from './plan'
import { type Scenario, type Step, parseScenarios } from './gherkin'
import { commonPrefix, latestRun, parseMaestroReport, parseTestReport, shotLabel, testStateOf } from './evidence'
import { activityOf, busyIn, describeActivity, parseActivity, pipelineTarget } from './activity'
import { AREA_LABEL, AREA_ORDER, attribute, parseNameStatus, parsePorcelain, parseWrites, sessionOfTranscript } from './attribution'

const PANE = 'pipeline-view'
const REFRESH_MS = 5000
// Les plans coûtent quelques appels git par branche liée : relus moins souvent que le pipeline.
const PLAN_REFRESH_MS = 30000
const DECISION = 'DÉCISION (Thibault)'
const FOLDER = { feature: 'features', fix: 'fixes' } as const
const PLAN_MARK = { done: '✓', active: '▸', yours: '!', todo: '·' } as const
const STEP_COLOR = { given: 'suggestion', when: 'warning', then: 'success' } as const
const TEST_LABEL = { passed: '✓ test vert', failed: '✗ test rouge', skipped: '– test ignoré' } as const
// Miniature des captures : assez petite pour tenir dans un Svg (131 072 caractères) en JPEG base64.
const THUMB_PX = 360
const THUMB_DIR = '/tmp/claude-pipeline-view-thumbs'
const MAX_SHOTS = 6

const snapshot = atom({ plugin: 'pipeline-view', key: 'snapshot' } as const, null, {
  shape: 'snapshot-1',
})
const agents = atom({ plugin: 'pipeline-view', key: 'agents' } as const, [], {
  shape: 'agents-2',
})
const isAsking = atom({ plugin: 'pipeline-view', key: 'isAsking' } as const, false)
const now = atom({ plugin: 'pipeline-view', key: 'now' } as const, 0)
const scenarios = atom({ plugin: 'pipeline-view', key: 'scenarios' } as const, [])
const selectedScenario = atom({ plugin: 'pipeline-view', key: 'selectedScenario' } as const, '')
const showSource = atom({ plugin: 'pipeline-view', key: 'showSource' } as const, false)
const evidence = atom({ plugin: 'pipeline-view', key: 'evidence' } as const, [])
const thumbs = atom({ plugin: 'pipeline-view', key: 'thumbs' } as const, [])
const plans = atom({ plugin: 'pipeline-view', key: 'plans' } as const, [])
const strays = atom({ plugin: 'pipeline-view', key: 'strays' } as const, [])
const openBranches = atom({ plugin: 'pipeline-view', key: 'openBranches' } as const, [])

// Racine du repo, pour raccourcir les chemins affichés. Recalculée à chaque rafraîchissement.
let root = ''

const git = async ($: EngineInterface, args: string[], cwd?: string): Promise<string> => {
  const run = await $.process.run(['git', ...args], { cwd, timeoutMs: 5000 }).catch(() => undefined)

  return run?.exitCode === 0 ? run.stdout.trim() : ''
}

/** Sortie brute, pour les formats `-z` dont le premier caractère compte. */
const gitRaw = async ($: EngineInterface, args: string[], cwd: string): Promise<string> => {
  const run = await $.process.run(['git', ...args], { cwd, timeoutMs: 5000 }).catch(() => undefined)

  return run?.exitCode === 0 ? run.stdout : ''
}

// Les transcripts des sessions récentes, lus une fois puis seulement ce qui s'y ajoute.
const TRANSCRIPT_DAYS = 14
const WRITE_PATTERN = '"name":"(Edit|Write|MultiEdit|NotebookEdit)","input":\\{"(file_path|notebook_path)":"([^"\\\\]|\\\\.)*"'
const transcriptRead = new Map<string, number>()
const written = new Map<string, Set<string>>()

const noteWrites = (session: string, chunk: string) => {
  for (const path of parseWrites(chunk)) {
    const by = written.get(path) ?? new Set<string>()
    by.add(session)
    written.set(path, by)
  }
}

/** Qui a écrit quel fichier, d'après les transcripts de ~/.claude/projects (sous-agents compris). */
const scanTranscripts = async ($: EngineInterface): Promise<void> => {
  const listed = await $.process
    .run(['/bin/sh', '-c', `find "$HOME/.claude/projects" -name '*.jsonl' -mtime -${TRANSCRIPT_DAYS} -size +0 -exec stat -f '%z %N' {} +`], {
      timeoutMs: 15000,
    })
    .catch(() => undefined)
  const fresh: string[] = []
  for (const line of (listed?.stdout ?? '').split('\n')) {
    const space = line.indexOf(' ')
    if (space <= 0) continue
    const size = Number(line.slice(0, space))
    const path = line.slice(space + 1)
    const from = transcriptRead.get(path) ?? 0
    if (size === from) continue
    transcriptRead.set(path, size)
    // Un transcript plus court qu'à la dernière lecture a été réécrit : relu en entier.
    if (from === 0 || size < from) {
      fresh.push(path)
      continue
    }
    const tail = await $.process
      .run(['/bin/sh', '-c', 'tail -c +"$2" "$1" | grep -oE "$3"', 'sh', path, String(from + 1), WRITE_PATTERN], { timeoutMs: 15000 })
      .catch(() => undefined)
    noteWrites(sessionOfTranscript(path), tail?.stdout ?? '')
  }
  // Première lecture : un seul grep pour tous, chaque ligne préfixée de son fichier.
  for (let i = 0; i < fresh.length; i += 100) {
    const batch = fresh.slice(i, i + 100)
    const out = await $.process.run(['grep', '-oHE', WRITE_PATTERN, ...batch], { timeoutMs: 60000 }).catch(() => undefined)
    for (const line of (out?.stdout ?? '').split('\n')) {
      const at = line.indexOf('.jsonl:')
      if (at > 0) noteWrites(sessionOfTranscript(line.slice(0, at + 6)), line.slice(at + 7))
    }
  }
}

// Une reprise refusée parce qu'une autre session tourne dans le worktree, et quand.
const CONFIRM_MS = 120_000
let confirmed = { key: '', at: 0 }

// L'état de cette session, publié pour les autres (~/.claude/activity/<session>.json).
let home = ''
let mine: SessionActivity | null = null
const activityDir = () => `${home}/.claude/activity`

const titleOf = ($: EngineInterface, session: string): Promise<string> =>
  $.process
    .run(['/bin/sh', '-c', 'cat "$HOME"/.claude/projects/*/"$1"/custom-title.json 2>/dev/null', 'sh', session], { timeoutMs: 5000 })
    .then(
      run => {
        try {
          return String((JSON.parse(run.stdout.split('\n')[0] ?? '') as { customTitle?: unknown }).customTitle ?? '')
        } catch {
          return ''
        }
      },
      () => '',
    )

/** Écrit l'état de la session ; ne réécrit pas un état inchangé, sauf pour rafraîchir le contexte. */
const publish = async ($: EngineInterface, state: SessionActivity['state'], waitingOn = '', isForced = false): Promise<void> => {
  if (!mine || !home) return
  if (!isForced && mine.state === state && mine.waitingOn === waitingOn) return
  const percent = await $.session.usage().then(
    u => u.context.percent ?? -1,
    () => -1,
  )
  mine = { ...mine, state, waitingOn, percent, at: await $.clock.now() }
  await $.fs.write(`${activityDir()}/${mine.session}.json`, JSON.stringify(mine)).catch(() => undefined)
}

/** Les états publiés par toutes les sessions. */
const readActivity = async ($: EngineInterface): Promise<SessionActivity[]> => {
  if (!home) return []
  const found: SessionActivity[] = []
  for (const name of await listNames($, activityDir(), 'file')) {
    if (!name.endsWith('.json')) continue
    const a = parseActivity(await readText($, `${activityDir()}/${name}`))
    if (a) found.push(a)
  }

  return found
}

const readText = ($: EngineInterface, path: string): Promise<string> =>
  $.fs.read(path).then(
    text => (typeof text === 'string' ? text : ''),
    () => '',
  )

/** Feature ou fix courant : branche feature/<nom> ou fix/<nom>, sinon les fichiers .current. */
const locate = async ($: EngineInterface, root: string) => {
  const byBranch = fromBranch(await git($, ['branch', '--show-current'], root))
  if (byBranch) return byBranch
  for (const kind of ['fix', 'feature'] as const) {
    const name = (await readText($, `${root}/.claude/${FOLDER[kind]}/.current`)).trim()
    if (name) return { kind, name }
  }

  return null
}

const SCENARIO = /^\s*(Scenario|Scenario Outline|Scenario Template|Scénario|Plan du scénario)\s*:/gm

/** Base du diff : pipeline.json → base pour une feature, fix.json → base_sha pour un fix. */
const baseOf = (text: string, kind: 'feature' | 'fix'): string => {
  try {
    const raw = JSON.parse(text) as Record<string, unknown>
    const base = raw[kind === 'feature' ? 'base' : 'base_sha']

    return typeof base === 'string' ? base : ''
  } catch {
    return ''
  }
}

/** Les .feature que le pipeline a ajoutés ou modifiés dans son package depuis sa base, lus en entier. */
const loadScenarios = async ($: EngineInterface, pkg: string, base: string): Promise<ScenarioFile[]> => {
  if (!pkg || !base) return []
  const mergeBase =
    (await git($, ['merge-base', 'HEAD', base], root)) || (await git($, ['merge-base', 'HEAD', `origin/${base}`], root))
  if (!mergeBase) return []
  const changed = await git($, ['diff', '--name-status', '--diff-filter=AMR', mergeBase, '--', pkg], root)
  const untracked = await git($, ['ls-files', '--others', '--exclude-standard', '--', pkg], root)
  const byPath = new Map<string, string>()
  for (const line of changed.split('\n').filter(Boolean)) {
    const [status, ...paths] = line.split('\t')
    byPath.set(paths.at(-1) ?? '', (status ?? '').charAt(0) === 'A' ? 'ajouté' : 'modifié')
  }
  for (const path of untracked.split('\n').filter(Boolean)) byPath.set(path, 'ajouté')
  const found: ScenarioFile[] = []
  for (const [path, status] of [...byPath].sort(([a], [b]) => (a < b ? -1 : 1))) {
    if (!path.endsWith('.feature')) continue
    const source = await readText($, `${root}/${path}`)
    found.push({ path, status, source, count: source.match(SCENARIO)?.length ?? 0 })
  }

  return found
}

// Le rapport de tests fait plusieurs centaines de Ko : relu seulement quand il change.
let testCache = { path: '', mtime: -1, results: new Map<string, 'passed' | 'failed' | 'skipped'>() }

const mtimeOf = ($: EngineInterface, path: string): Promise<number> =>
  $.fs.stat(path).then(
    s => (s.kind === 'other' ? -1 : s.mtimeMs),
    () => -1,
  )

const listNames = ($: EngineInterface, path: string, kind: 'file' | 'dir'): Promise<string[]> =>
  $.fs.list(path).then(
    entries => entries.filter(e => e.kind === kind).map(e => e.name).sort(),
    () => [],
  )

/** Le test et le flow Maestro de chaque scénario des fichiers montrés, depuis le dossier du run. */
const loadEvidence = async ($: EngineInterface, dir: string, files: ScenarioFile[]): Promise<ScenarioEvidence[]> => {
  const all = files.flatMap(parseScenarios)
  if (all.length === 0) return []
  const report = `${dir}/.gauntlet/test_report.jsonl`
  const mtime = await mtimeOf($, report)
  if (report !== testCache.path || mtime !== testCache.mtime) {
    testCache = { path: report, mtime, results: mtime === -1 ? new Map() : parseTestReport(await readText($, report)) }
  }
  const runs: { platform: string; run: string; statuses: Map<string, string> }[] = []
  for (const platform of await listNames($, `${dir}/qa`, 'dir')) {
    const run = latestRun(await listNames($, `${dir}/qa/${platform}`, 'dir'))
    // report.xml est dans le run, ou (gauntlet actuel) à côté des runs, celui du dernier.
    const xml = (await readText($, `${dir}/qa/${platform}/${run}/report.xml`)) || (await readText($, `${dir}/qa/${platform}/report.xml`))
    if (run) runs.push({ platform, run, statuses: parseMaestroReport(xml) })
  }
  const found: ScenarioEvidence[] = []
  for (const s of all) {
    const qa: QaRun[] = []
    for (const r of runs) {
      const flow = `${dir}/qa/${r.platform}/${r.run}/${s.title}`
      const pngs = (await listNames($, `${flow}/takeScreenshot`, 'file')).filter(n => n.toLowerCase().endsWith('.png'))
      const status = r.statuses.get(s.title) ?? ''
      if (pngs.length === 0 && !status) continue
      const prefix = commonPrefix(pngs)
      qa.push({
        platform: r.platform,
        run: r.run,
        status,
        shots: pngs.map(n => ({ path: `${flow}/takeScreenshot/${n}`, label: shotLabel(n, prefix) })),
      })
    }
    found.push({ id: s.id, test: testStateOf(testCache.results, s.feature, s.title), qa })
  }

  return found
}

const thumbCache = new Map<string, Thumb>()

/** Une capture réduite en JPEG par sips (macOS), gardée tant que la capture ne change pas. */
const thumbOf = async ($: EngineInterface, path: string): Promise<Thumb | undefined> => {
  const mtime = await mtimeOf($, path)
  const cacheKey = `${path}@${mtime}`
  const cached = thumbCache.get(cacheKey)
  if (cached) return cached
  const out = `${THUMB_DIR}/${hashOf(cacheKey)}.jpg`
  await $.process.run(['mkdir', '-p', THUMB_DIR], { timeoutMs: 5000 }).catch(() => undefined)
  const made = await $.process
    .run(['sips', '-Z', String(THUMB_PX), '-s', 'format', 'jpeg', '-s', 'formatOptions', '55', path, '--out', out], {
      timeoutMs: 15000,
    })
    .catch(() => undefined)
  if (made?.exitCode !== 0) return undefined
  const size = await $.process.run(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', out], { timeoutMs: 5000 }).catch(() => undefined)
  const width = Number(/pixelWidth: (\d+)/.exec(size?.stdout ?? '')?.[1]) || THUMB_PX
  const height = Number(/pixelHeight: (\d+)/.exec(size?.stdout ?? '')?.[1]) || THUMB_PX
  const read = await $.fs.read(out, { as: 'bytes' }).catch(() => undefined)
  if (!read) return undefined
  const thumb = { path, data: read.base64, width, height }
  thumbCache.set(cacheKey, thumb)

  return thumb
}

const hashOf = (text: string): string => {
  let h = 5381
  for (let i = 0; i < text.length; i++) h = ((h << 5) + h + text.charCodeAt(i)) | 0

  return (h >>> 0).toString(16)
}

/** Les miniatures du scénario affiché, refaites quand on change de scénario ou qu'une capture change. */
const refreshThumbs = async ($: EngineInterface): Promise<void> => {
  const files = await read($, scenarios)
  const all = files.flatMap(parseScenarios)
  const wanted = await read($, selectedScenario)
  const shown = all.find(s => s.id === wanted || s.path === wanted) ?? all[0]
  const proof = (await read($, evidence)).find(e => e.id === shown?.id)
  const paths = (proof?.qa ?? []).flatMap(r => r.shots.map(s => s.path)).slice(0, MAX_SHOTS)
  const made: Thumb[] = []
  for (const path of paths) {
    const thumb = await thumbOf($, path)
    if (thumb) made.push(thumb)
  }
  const before = await read($, thumbs)
  if (JSON.stringify(made.map(t => `${t.path}:${t.data.length}`)) !== JSON.stringify(before.map(t => `${t.path}:${t.data.length}`))) {
    await update($, thumbs, () => made)
  }
}

const load = async ($: EngineInterface): Promise<PipelineSnapshot | null> => {
  root = await git($, ['rev-parse', '--show-toplevel'])
  if (!root) return null
  const where = await locate($, root)
  if (!where) return null
  const dir = `${root}/.claude/${FOLDER[where.kind]}/${where.name}`
  const file = `${dir}/${where.kind === 'feature' ? 'pipeline.json' : 'fix.json'}`
  const config = await readText($, `${root}/.claude/rules/feature_pipeline.md`)
  const text = await readText($, file)
  const snap = parseState(where.kind, where.name, text, maxAttemptsFromConfig(config))
  const found = snap ? await loadScenarios($, snap.pkg, baseOf(text, where.kind)) : []
  if (JSON.stringify(found) !== JSON.stringify(await read($, scenarios))) await update($, scenarios, () => found)
  const proofs = await loadEvidence($, dir, found)
  if (JSON.stringify(proofs) !== JSON.stringify(await read($, evidence))) await update($, evidence, () => proofs)
  await refreshThumbs($)
  if (!snap || !snap.pkg) return snap
  const grep = await git($, ['grep', '--untracked', '-I', '-F', '-c', DECISION, '--', snap.pkg], root)
  const decisions = grep
    .split('\n')
    .map(line => Number(line.slice(line.lastIndexOf(':') + 1)) || 0)
    .reduce((sum, n) => sum + n, 0)

  return { ...snap, decisions }
}

/** Ce que git sait d'une branche citée par un plan : worktree, commits, poussée, fichiers, étape du pipeline. */
const fillBranch = async (
  $: EngineInterface,
  b: PlanBranch,
  base: string,
  worktrees: Map<string, string>,
  main: string,
  sessions: SessionActivity[] = [],
  at = 0,
): Promise<PlanBranch> => {
  if (!(await git($, ['rev-parse', '--verify', '--quiet', `refs/heads/${b.branch}`], main))) return { ...b, exists: false }
  const worktree = worktrees.get(b.branch) ?? ''
  const ahead = Number(await git($, ['rev-list', '--count', `${base}..${b.branch}`], main)) || 0
  const up = await git($, ['rev-list', '--count', `${b.branch}@{upstream}..${b.branch}`], main)
  const dirty = worktree ? (await git($, ['status', '--porcelain'], worktree)).split('\n').filter(Boolean).length : 0
  const changed = worktree ? parsePorcelain(await gitRaw($, ['status', '--porcelain=v1', '-z'], worktree)) : []
  const mergeBase = ahead > 0 ? await git($, ['merge-base', base, b.branch], main) : ''
  const committed = mergeBase ? parseNameStatus(await gitRaw($, ['diff', '--name-status', '-z', mergeBase, b.branch], main)) : []
  const owned = worktree ? attribute(worktree, [...changed, ...committed], written) : { files: [], writers: 0, sessions: [] }
  const activity = worktree ? activityOf(sessions, worktree, owned.sessions, at) : []
  const filled = {
    ...b,
    exists: true,
    worktree,
    ahead,
    unpushed: up === '' ? -1 : Number(up) || 0,
    dirty,
    files: owned.files,
    writers: owned.writers,
    activity,
  }
  const where = fromBranch(b.branch)
  if (!worktree || !where) return filled
  const file = `${worktree}/.claude/${FOLDER[where.kind]}/${where.name}/${where.kind === 'feature' ? 'pipeline.json' : 'fix.json'}`
  const snap = parseState(where.kind, where.name, await readText($, file), 5)
  const focus = snap ? focusStage(snap) : undefined
  if (!snap || !focus) return filled
  const tries = focus.attempts > 0 ? ` ${focus.attempts}/${snap.maxAttempts}` : ''

  return { ...filled, stage: `${mark(focus.status)} ${focus.label}${tries}`, stageStatus: focus.status }
}

/** Les plans ouverts du checkout principal (.claude/plans/*.md, epics des worktrees) et les worktrees hors plan. */
const loadPlans = async ($: EngineInterface): Promise<{ plans: PlanView[]; strays: PlanBranch[] }> => {
  const common = await git($, ['rev-parse', '--path-format=absolute', '--git-common-dir'])
  if (!common) return { plans: [], strays: [] }
  const main = common.replace(/\/\.git\/?$/, '')
  const worktrees = parseWorktrees(await git($, ['worktree', 'list', '--porcelain'], main))
  const config = await readText($, `${main}/.claude/rules/feature_pipeline.md`)
  const base = /^\s*base_branch\s*=\s*(\S+)/m.exec(config)?.[1] ?? 'develop'
  const found: PlanView[] = []
  const cited = new Set<string>()
  if (worktrees.size > 0) await scanTranscripts($)
  const sessions = await readActivity($)
  const at = await $.clock.now().catch(() => 0)
  const fill = (b: PlanBranch, from: string) => fillBranch($, b, from, worktrees, main, sessions, at)
  const entries = await $.fs.list(`${main}/.claude/plans`).catch(() => [])
  for (const entry of [...entries].sort((a, b) => (a.name < b.name ? -1 : 1))) {
    if (entry.kind !== 'file' || !entry.name.endsWith('.md')) continue
    const source = `.claude/plans/${entry.name}`
    const parsed = parsePlanMarkdown(await readText($, `${main}/${source}`))
    for (const phase of parsed.phases) {
      for (const item of phase.items) {
        item.branches.forEach(b => cited.add(b.branch))
        item.branches = await Promise.all(item.branches.map(b => fill(b, base)))
      }
    }
    found.push({ kind: 'plan', title: parsed.title || entry.name.replace(/\.md$/, ''), source, phases: parsed.phases })
  }
  for (const [branch, path] of worktrees) {
    const where = fromBranch(branch)
    if (where?.kind !== 'feature') continue
    const source = `.claude/features/${where.name}/pipeline.json`
    const epic = parseEpic(where.name, await readText($, `${path}/${source}`))
    if (!epic) continue
    cited.add(branch)
    for (const item of epic.phases[0]?.items ?? []) {
      item.branches.forEach(b => cited.add(b.branch))
      item.branches = await Promise.all(item.branches.map(b => fill(b, epic.bases[b.branch] ?? branch)))
    }
    found.push({ kind: 'epic', title: epic.title, source: `${path.slice(main.length + 1) || '.'}/${source}`, phases: epic.phases })
  }
  const open = found.filter(isOpen)
  if (open.length === 0) return { plans: [], strays: [] }
  const loose: PlanBranch[] = []
  for (const [branch, path] of worktrees) {
    if (path === main || isToolingBranch(branch) || cited.has(branch)) continue
    loose.push(await fill(emptyBranch(branch), base))
  }

  return { plans: open, strays: loose }
}

let isPlanning = false

const refreshPlans = async ($: EngineInterface): Promise<void> => {
  if (isPlanning) return
  isPlanning = true
  try {
    const next = await loadPlans($)
    if (JSON.stringify(next.plans) !== JSON.stringify(await read($, plans))) await update($, plans, () => next.plans)
    if (JSON.stringify(next.strays) !== JSON.stringify(await read($, strays))) await update($, strays, () => next.strays)
    if (next.plans.length > 0 && !autoOpenedPlans) {
      autoOpenedPlans = true
      await $.ui.open({ id: PANE, title: 'Pipeline' })
    }
  } finally {
    isPlanning = false
  }
}

// Ouvert une fois par session quand un plan ouvert existe dans le repo.
let autoOpenedPlans = false

const refresh = async ($: EngineInterface): Promise<void> => {
  if ((await read($, agents)).some(a => a.end === 0)) {
    const at = await $.clock.now()
    await update($, now, () => at)
  }
  const next = await load($)
  if (!sameSnapshot(next, await read($, snapshot))) {
    await update($, snapshot, () => next)
  }
  await autoOpen($, next)
}

// Ouvert une fois par pipeline détecté : fermé à la main, il ne se rouvre qu'au pipeline suivant.
let autoOpenedFor = ''

const autoOpen = async ($: EngineInterface, next: PipelineSnapshot | null): Promise<void> => {
  const key = next ? `${next.kind}:${next.name}` : ''
  if (key === autoOpenedFor) return
  autoOpenedFor = key
  if (!next) return
  const opened = await $.ui.open({ id: PANE, title: 'Pipeline' })
  if (!opened.isPlaced) $.ui.log(`pipeline-view : panneau non placé (${opened.reason})`)
}

const describe = (
  snap: PipelineSnapshot,
  list: ActiveAgent[],
  asking: boolean,
  at: number,
  percent: number,
): string => {
  const parts = [`${snap.kind} ${snap.name}`]
  const stage = focusStage(snap)
  for (const a of list.filter(a => a.end === 0)) {
    const refusals = a.denied > 0 ? `, ${a.denied} refus` : ''
    parts.push(`${a.persona}${roleOf(a.type) ? ` (${roleOf(a.type)})` : ''} au travail ${duration(at - a.start)}${refusals}`)
  }
  if (stage) {
    const tries = stage.attempts > 0 ? ` ${stage.attempts}/${snap.maxAttempts}` : ''
    parts.push(`${mark(stage.status)} ${stage.label}${tries}`)
  }
  if (snap.phase) parts.push(`phase ${snap.phase}`)
  if (snap.decisions > 0) parts.push(`${snap.decisions} ${DECISION}`)
  if (asking) parts.push('attend ta réponse')
  if (percent >= 0) parts.push(`contexte ${percent} %`)

  return parts.join(' · ')
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    home = (await $.env.get('HOME').catch(() => undefined)) ?? ''
    const session = await $.session.id().catch(() => '')
    if (home && session) {
      await $.process.run(['mkdir', '-p', activityDir()], { timeoutMs: 5000 }).catch(() => undefined)
      mine = { session, cwd: e.cwd, title: await titleOf($, session), state: 'idle', at: 0, percent: -1, waitingOn: '' }
      await publish($, 'idle', '', true)
    }
    await $.command.register({
      name: 'pipeline',
      description: "Ouvre le panneau d'état du pipeline /feature ou /fix en cours",
    })
    await update($, agents, () => [])
    await refresh($)
    await refreshPlans($)
    $.clock.every(REFRESH_MS, () => refresh($))
    $.clock.every(PLAN_REFRESH_MS, () => refreshPlans($))

    return started
  })

  on('command.run', { command: 'pipeline' }, async $ => {
    await refresh($)
    await refreshPlans($)
    await $.ui.open({ id: PANE, title: 'Pipeline' })

    return { text: 'Panneau Pipeline ouvert.' }
  })

  on('agent.spawn', async ($, e, next) => {
    const spawned = await next(e)
    if (spawned.agentId && isPipelineAgent(e.subagentType)) {
      const at = await $.clock.now()
      const agent: ActiveAgent = {
        id: spawned.agentId,
        type: e.subagentType,
        persona: PERSONAS[e.subagentType] ?? e.subagentType,
        start: at,
        end: 0,
        calls: 0,
        denied: 0,
        current: '',
        files: [],
      }
      await update($, agents, list => [...list.filter(a => a.id !== agent.id), agent])
      await update($, now, () => at)
    }

    return spawned
  })

  // Deux sessions dans le même worktree écrivent dans les mêmes fichiers : la reprise d'un /feature ou
  // d'un /fix qu'une autre session fait tourner est arrêtée une fois ; la même commande renvoyée dans
  // les deux minutes passe.
  on('prompt.submit', async ($, e, next) => {
    const target = e.command ? pipelineTarget(e.command.name, e.command.args) : null
    if (target && mine) {
      const common = await git($, ['rev-parse', '--path-format=absolute', '--git-common-dir'])
      const main = common.replace(/\/\.git\/?$/, '')
      const worktree = `${main}/.claude/worktrees/${target.kind}-${target.name}`
      const at = await $.clock.now()
      const busy = main ? busyIn(await readActivity($), worktree, mine.session, at) : []
      const key = `${target.kind}:${target.name}`
      if (busy.length > 0 && !(confirmed.key === key && at - confirmed.at < CONFIRM_MS)) {
        confirmed = { key, at }
        const who = busy.map(a => describeActivity(a, at).slice(2)).join(' ; ')

        return {
          drop: `Une autre session travaille déjà dans ${worktree.slice(main.length + 1)} : ${who}. Deux sessions y écriraient dans les mêmes fichiers. Renvoie la même commande dans les 2 minutes pour la lancer quand même.`,
        }
      }
    }
    const sent = await next(e)
    await publish($, 'working')

    return sent
  })

  // Une permission que Thibault doit donner, dans la boucle principale ou celle d'un sous-agent.
  on('tool.check', async ($, e, next) => {
    const verdict = await next(e)
    if (e.tool_use_id && verdict.decision === 'ask' && e.approver === 'person') await publish($, 'waiting', e.tool)

    return verdict
  })

  on('session.end', async ($, e, next) => {
    const ended = await next(e)
    if (mine && home) await $.process.run(['rm', '-f', `${activityDir()}/${mine.session}.json`], { timeoutMs: 5000 }).catch(() => undefined)

    return ended
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (!e.agentId && mine) {
      mine = { ...mine, title: (await titleOf($, mine.session)) || mine.title }
      await publish($, 'idle', '', true)
    }
    if (e.agentId) {
      const at = await $.clock.now()
      await update($, agents, list => agentEnded(list, e.agentId ?? '', at))
      await update($, now, () => at)
    }
    await refresh($)

    return done
  })

  // Lecture seule : l'appel passe tel quel, on ne fait que compter. Seuls les agents du pipeline
  // sont suivis ; un refus (hook restrict-writes, permission) est compté à part.
  on('tool.call', async ($, e, next) => {
    // L'outil dont la permission attendait a tourné : elle est donnée (ou refusée), le tour reprend.
    const settled = async (ran: Awaited<ReturnType<typeof next>>) => {
      if (mine?.state === 'waiting' && mine.waitingOn === String(e.tool)) await publish($, 'working')

      return ran
    }
    const id = e.agentId
    if (!id || !isTracked(String(e.tool))) return settled(await next(e))
    const isOurs = (await read($, agents)).some(a => a.id === id && a.end === 0)
    if (!isOurs) return settled(await next(e))
    const args = e as unknown as Record<string, unknown>
    const label = toolLabel(String(e.tool), args, root)
    await update($, agents, list => list.map(a => (a.id === id ? callStarted(a, label) : a)))
    let isDenied = false
    let isError = true
    try {
      const ran = await next(e)
      isDenied = ran.deny !== undefined
      isError = isDenied || ran.isError === true
      return await settled(ran)
    } finally {
      const file = typeof args.file_path === 'string' ? args.file_path : undefined
      const isWrite = ['Edit', 'Write', 'MultiEdit'].includes(String(e.tool))
      const editedFile = file && isWrite && !isError ? shortPath(file, root) : undefined
      await update($, agents, list =>
        list.map(a => (a.id === id ? callEnded(a, { isDenied, editedFile }) : a)),
      )
    }
  })

  on('tool.call', { tool: 'AskUserQuestion' }, async ($, e, next) => {
    if (e.agentId) return next(e)
    await update($, isAsking, () => true)
    await publish($, 'waiting', 'question')
    try {
      return await next(e)
    } finally {
      await update($, isAsking, () => false)
      await publish($, 'working')
    }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const snap = await read($, snapshot)
    if (e.props.hasSurvey) return next(e)
    if (snap === null) {
      const open = await read($, plans)
      const first = open[0]
      if (!first) return next(e)
      const { Text } = $.ui.resolve(e)
      const more = open.length > 1 ? ` · +${open.length - 1} plan${open.length > 2 ? 's' : ''}` : ''
      const waiting = new Set(
        open
          .flatMap(p => p.phases.flatMap(ph => ph.items.flatMap(i => i.branches.flatMap(b => b.activity))))
          .filter(a => a.state === 'waiting' && a.session !== mine?.session)
          .map(a => a.session),
      ).size
      const asks = waiting > 0 ? ` · ${waiting} session${waiting > 1 ? 's attendent' : ' attend'} ta réponse` : ''

      return (
        <Text dimColor wrap="truncate-end">
          {summarize(first)}
          {more}
          {asks}
        </Text>
      )
    }
    const { Text } = $.ui.resolve(e)
    const line = describe(snap, await read($, agents), await read($, isAsking), await read($, now), mine?.percent ?? -1)
    const stage = focusStage(snap)
    const isRed = stage?.status === 'RED' || stage?.status === 'FAILED'

    return (
      <Text color={isRed ? 'error' : undefined} dimColor={!isRed} wrap="truncate-end">
        {line}
      </Text>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const ui = $.ui.resolve(e)
    const { Box, Button, Code, Text } = ui
    const snap = await read($, snapshot)
    const openPlans = await read($, plans)
    const loose = await read($, strays)
    const cites = new Map<string, number>()
    for (const plan of openPlans) {
      for (const item of plan.phases.flatMap(p => p.items)) {
        for (const b of item.branches) cites.set(b.branch, (cites.get(b.branch) ?? 0) + 1)
      }
    }
    const unfolded = await read($, openBranches)
    const hasActivity = [...openPlans.flatMap(p => p.phases.flatMap(ph => ph.items.flatMap(i => i.branches))), ...loose].some(
      b => b.activity.length > 0,
    )
    const at = hasActivity ? await $.clock.now() : 0
    const branchFiles = (b: PlanBranch) =>
      AREA_ORDER.map(area => {
        const rows = b.files.filter(f => f.area === area)
        if (rows.length === 0) return null

        return (
          <Box flexDirection="column">
            <Text dimColor>
              {'      '}
              {AREA_LABEL[area]} ({rows.length})
            </Text>
            {rows.slice(0, 50).map(f => (
              <Text color={f.isAttributed ? undefined : 'warning'} dimColor={f.isAttributed} wrap="truncate-start">
                {'        '}
                {f.status} {f.path}
                {f.isAttributed ? '' : '  ?'}
              </Text>
            ))}
            {rows.length > 50 && (
              <Text dimColor>
                {'        '}… et {rows.length - 50} autres
              </Text>
            )}
          </Box>
        )
      })
    const branchLine = (b: PlanBranch) => {
      const isOpen = unfolded.includes(b.branch)

      return (
        <Box flexDirection="column">
          <Box flexDirection="row" gap={1}>
            <Text
              color={b.stageStatus === 'RED' || b.stageStatus === 'FAILED' ? 'error' : !b.exists ? 'warning' : undefined}
              dimColor={b.exists && b.stageStatus !== 'RED' && b.stageStatus !== 'FAILED'}
              wrap="truncate-end"
            >
              {'    '}
              {describeBranch(b)}
              {(cites.get(b.branch) ?? 0) > 1 ? ` · citée par ${cites.get(b.branch)} points` : ''}
            </Text>
            {b.files.length > 0 && (
              <Button
                key={`files-${b.branch}`}
                plain
                dimColor
                label={isOpen ? 'masquer' : 'fichiers'}
                onPress={() =>
                  update($, openBranches, list => (isOpen ? list.filter(x => x !== b.branch) : [...list, b.branch]))
                }
              />
            )}
          </Box>
          {b.activity.slice(0, 3).map(a => (
            <Text color={a.state === 'waiting' ? 'warning' : undefined} dimColor={a.state === 'idle'} wrap="truncate-end">
              {'      '}
              {describeActivity(a, at)}
            </Text>
          ))}
          {isOpen && branchFiles(b)}
          {isOpen && b.files.some(f => !f.isAttributed) && (
            <Text dimColor>
              {'      '}? : aucun transcript ne nomme ce fichier (commande, autre session ou toi)
            </Text>
          )}
        </Box>
      )
    }
    const stepLine = (s: Step, isDim: boolean) => (
      <Box flexDirection="column">
        <Text dimColor={isDim}>
          <Text color={STEP_COLOR[s.kind]} bold={!s.isContinuation} dimColor={s.isContinuation}>
            {s.isContinuation ? `  ${s.keyword}` : s.keyword}
          </Text>{' '}
          {s.parts.map(part => (part.isParam ? <Text bold color="claude">{part.text}</Text> : part.text))}
        </Text>
        {s.extra.map(line => (
          <Text dimColor mono>
            {'    '}
            {line}
          </Text>
        ))}
      </Box>
    )
    const proofs = await read($, evidence)
    const pictures = await read($, thumbs)
    const proofLine = (s: Scenario) => {
      const proof = proofs.find(p => p.id === s.id)
      if (!proof || (proof.test === '' && proof.qa.length === 0)) return null

      return (
        <Box flexDirection="row" flexWrap="wrap" columnGap={2}>
          {proof.test !== '' && (
            <Text color={proof.test === 'passed' ? 'success' : proof.test === 'failed' ? 'error' : undefined} dimColor={proof.test === 'skipped'}>
              {TEST_LABEL[proof.test]}
            </Text>
          )}
          {proof.qa.map(r => (
            <Text color={r.status === 'SUCCESS' ? 'success' : r.status === '' ? undefined : 'error'} dimColor={r.status === ''}>
              {r.status === 'SUCCESS' ? '✓' : r.status === '' ? '·' : '✗'} Maestro {r.platform}
              {r.shots.length > 0 ? ` · ${r.shots.length} capture${r.shots.length > 1 ? 's' : ''}` : ''}
            </Text>
          ))}
        </Box>
      )
    }
    const picture = (shot: { path: string; label: string }) => {
      const thumb = pictures.find(t => t.path === shot.path)
      // La table d'éléments répond pour chaque nom : seule la surface dit qui sait dessiner quoi.
      if (e.surface === 'terminal' && 'Image' in ui) {
        const { Image } = ui

        return <Image source={{ file: shot.path, format: 'png' }} columns={18} rows={16} alt={shot.label} />
      }
      if (!thumb || e.surface === 'terminal' || !('Svg' in ui)) return <Text dimColor>(miniature en cours)</Text>
      const { Svg } = ui
      const width = 120
      const height = Math.round((thumb.height / thumb.width) * width)

      return (
        <Svg
          source={`<svg xmlns="http://www.w3.org/2000/svg" width="${thumb.width}" height="${thumb.height}" viewBox="0 0 ${thumb.width} ${thumb.height}"><image href="data:image/jpeg;base64,${thumb.data}" width="${thumb.width}" height="${thumb.height}"/></svg>`}
          alt={shot.label}
          width={width}
          height={height}
        />
      )
    }
    const shotsOf = (s: Scenario) => {
      const runs = (proofs.find(p => p.id === s.id)?.qa ?? []).filter(r => r.shots.length > 0)
      if (runs.length === 0) return null
      let left = MAX_SHOTS

      return (
        <Box flexDirection="column" marginTop={1}>
          {runs.map(r => {
            const shots = r.shots.slice(0, Math.max(0, left))
            left -= shots.length

            return (
              <Box flexDirection="column">
                <Text dimColor>
                  Captures {r.platform} · run {r.run}
                  {r.shots.length > shots.length ? ` · ${shots.length} sur ${r.shots.length}` : ''}
                </Text>
                <Box flexDirection="row" flexWrap="wrap" gap={1}>
                  {shots.map(shot => (
                    <Box flexDirection="column" key={`shot-${shot.path}`}>
                      {picture(shot)}
                      <Button
                        key={`open-${shot.path}`}
                        plain
                        dimColor
                        label={shot.label}
                        onPress={() => void $.process.run(['open', shot.path], { timeoutMs: 5000 }).catch(() => undefined)}
                      />
                    </Box>
                  ))}
                </Box>
              </Box>
            )
          })}
        </Box>
      )
    }
    const scenarioCard = (s: Scenario) => (
      <Box flexDirection="column" borderStyle="round" borderDimColor paddingX={1}>
        {s.feature !== '' && <Text dimColor>{s.feature}</Text>}
        <Text bold>
          {s.isOutline ? 'Plan · ' : ''}
          {s.title}
        </Text>
        {s.tags.length > 0 && <Text color="suggestion">{s.tags.join(' ')}</Text>}
        {proofLine(s)}
        {s.background.length > 0 && (
          <Box flexDirection="column" marginTop={1}>
            <Text dimColor>Contexte</Text>
            {s.background.map(b => stepLine(b, true))}
          </Box>
        )}
        <Box flexDirection="column" marginTop={1}>
          {s.steps.length === 0 && <Text dimColor>Aucune étape.</Text>}
          {s.steps.map(b => stepLine(b, false))}
        </Box>
        {s.examples.length > 0 && (
          <Box flexDirection="column" marginTop={1}>
            <Text dimColor>Exemples</Text>
            {s.examples.map(line => (
              <Text mono>{line}</Text>
            ))}
          </Box>
        )}
        {shotsOf(s)}
      </Box>
    )
    const planSection =
      openPlans.length === 0 ? null : (
        <Box flexDirection="column">
          <Text> </Text>
          <Text bold>Plan</Text>
          {openPlans.map(plan => (
            <Box flexDirection="column">
              <Text bold>{summarize(plan)}</Text>
              <Text dimColor wrap="truncate-start">
                {plan.source}
              </Text>
              {plan.phases.map(phase => (
                <Box flexDirection="column">
                  <Text dimColor>{phase.title}</Text>
                  {phase.items.map(item => {
                    const state = itemState(item)
                    const extra = [item.owner, item.note].filter(Boolean).join(' · ')

                    return (
                      <Box flexDirection="column">
                        <Text
                          color={state === 'done' ? 'success' : state === 'yours' ? 'warning' : undefined}
                          dimColor={state === 'done' || state === 'todo'}
                          bold={state === 'active'}
                          wrap="truncate-end"
                        >
                          {PLAN_MARK[state]} {item.id}. {item.title}
                          {extra !== '' ? ` · ${extra}` : ''}
                          {state === 'yours' ? ' · décision à toi' : ''}
                        </Text>
                        {state !== 'done' && item.branches.map(branchLine)}
                      </Box>
                    )
                  })}
                </Box>
              ))}
            </Box>
          ))}
          {loose.length > 0 && (
            <Box flexDirection="column">
              <Text> </Text>
              <Text bold>Worktrees cités par aucun plan</Text>
              {loose.map(branchLine)}
            </Box>
          )}
        </Box>
      )
    if (snap === null) {
      return (
        <Box flexDirection="column">
          <Text dimColor>Aucun /feature ni /fix en cours dans ce dépôt.</Text>
          {planSection}
        </Box>
      )
    }
    const list = await read($, agents)
    const shownAt = await read($, now)
    const asking = await read($, isAsking)
    const current = focusStage(snap)
    const files = await read($, scenarios)
    const wanted = await read($, selectedScenario)
    const all = files.flatMap(parseScenarios)
    // L'ancien choix était un chemin de fichier : on retombe sur son premier scénario.
    const found = all.findIndex(s => s.id === wanted || s.path === wanted)
    const index = found === -1 ? 0 : found
    const shown = all[index]
    const isSource = await read($, showSource)
    const sourceOf = (path: string) => files.find(f => f.path === path)?.source ?? ''
    const step = (delta: number) => all[(index + delta + all.length) % all.length]?.id ?? ''

    return (
      <Box flexDirection="column">
        <Text bold>
          {snap.kind} {snap.name}
        </Text>
        {snap.pkg !== '' && <Text dimColor>{snap.pkg}</Text>}
        {snap.phase !== '' && <Text>phase : {snap.phase}</Text>}
        <Text> </Text>
        {snap.stages.map(stage => (
          <Text
            color={
              stage.status === 'PASSED'
                ? 'success'
                : stage.status === 'RED' || stage.status === 'FAILED'
                  ? 'error'
                  : undefined
            }
            dimColor={stage.status === 'PENDING' || stage.status === 'SKIPPED'}
            bold={stage.key === current?.key}
          >
            {mark(stage.status)} {stage.label}
            {stageOwner(snap.kind, stage.key) !== '' ? ` · ${stageOwner(snap.kind, stage.key)}` : ''}
            {stage.attempts > 0 ? `  ${stage.attempts}/${snap.maxAttempts}` : ''}
          </Text>
        ))}
        <Text> </Text>
        {list.length === 0 && <Text dimColor>Aucun agent du pipeline dans cette session.</Text>}
        {list.map(a => {
          const isRunning = a.end === 0
          const stats = `${duration((isRunning ? shownAt : a.end) - a.start)} · ${a.calls} appel(s)`

          return (
            <Box flexDirection="column">
              <Text bold={isRunning} dimColor={!isRunning}>
                {isRunning ? '▸' : '✓'} {a.persona}
                {roleOf(a.type) !== '' ? ` (${roleOf(a.type)})` : ''} · {stats}
              </Text>
              {a.denied > 0 && (
                <Text color="warning">  {a.denied} écriture(s) ou appel(s) refusé(s)</Text>
              )}
              {isRunning && a.current !== '' && <Text>  en cours : {a.current}</Text>}
              {isRunning &&
                a.files.map(file => <Text dimColor>  modifié : {file}</Text>)}
            </Box>
          )
        })}
        {snap.decisions > 0 && (
          <Text color="warning">
            {snap.decisions} marqueur(s) {DECISION} dans le package
          </Text>
        )}
        {asking && <Text color="warning">Une question attend ta réponse.</Text>}
        <Text> </Text>
        <Text bold>Scénarios</Text>
        {files.length === 0 && (
          <Text dimColor>Pas encore de .feature ajouté ou modifié dans {snap.pkg || 'le package'}.</Text>
        )}
        {shown && (
          <Box flexDirection="column">
            <Box flexDirection="row" gap={1} alignItems="center">
              <Button key="scenario-prev" label="‹" onPress={async () => {
                  await update($, selectedScenario, () => step(-1))
                  await refreshThumbs($)
                }} />
              <Text>
                {index + 1} / {all.length}
              </Text>
              <Button key="scenario-next" label="›" onPress={async () => {
                  await update($, selectedScenario, () => step(1))
                  await refreshThumbs($)
                }} />
              <Button
                key="scenario-source"
                label={isSource ? 'Carte' : 'Fichier brut'}
                variant={isSource ? 'primary' : 'secondary'}
                onPress={() => update($, showSource, v => !v)}
              />
              <Text dimColor wrap="truncate-end">
                {shown.file} · {shown.status}
              </Text>
            </Box>
            {all.length > 1 && all.length <= 40 && <Text dimColor>{all.map((_, i) => (i === index ? '●' : '○')).join('')}</Text>}
            {isSource ? (
              <Code source={sourceOf(shown.path)} language="gherkin" path={shown.path} startLine={1} />
            ) : (
              scenarioCard(shown)
            )}
          </Box>
        )}
        {planSection}
      </Box>
    )
  })
}
