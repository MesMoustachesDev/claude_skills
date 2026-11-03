import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { ActiveAgent, PipelineSnapshot, PlanBranch, PlanView, ScenarioFile } from '../types'
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

const PANE = 'pipeline-view'
const REFRESH_MS = 5000
// Les plans coûtent quelques appels git par branche liée : relus moins souvent que le pipeline.
const PLAN_REFRESH_MS = 30000
const DECISION = 'DÉCISION (Thibault)'
const FOLDER = { feature: 'features', fix: 'fixes' } as const
const PLAN_MARK = { done: '✓', active: '▸', yours: '!', todo: '·' } as const
const STEP_COLOR = { given: 'suggestion', when: 'warning', then: 'success' } as const

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
const plans = atom({ plugin: 'pipeline-view', key: 'plans' } as const, [])
const strays = atom({ plugin: 'pipeline-view', key: 'strays' } as const, [])

// Racine du repo, pour raccourcir les chemins affichés. Recalculée à chaque rafraîchissement.
let root = ''

const git = async ($: EngineInterface, args: string[], cwd?: string): Promise<string> => {
  const run = await $.process.run(['git', ...args], { cwd, timeoutMs: 5000 }).catch(() => undefined)

  return run?.exitCode === 0 ? run.stdout.trim() : ''
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
): Promise<PlanBranch> => {
  if (!(await git($, ['rev-parse', '--verify', '--quiet', `refs/heads/${b.branch}`], main))) return { ...b, exists: false }
  const worktree = worktrees.get(b.branch) ?? ''
  const ahead = Number(await git($, ['rev-list', '--count', `${base}..${b.branch}`], main)) || 0
  const up = await git($, ['rev-list', '--count', `${b.branch}@{upstream}..${b.branch}`], main)
  const dirty = worktree ? (await git($, ['status', '--porcelain'], worktree)).split('\n').filter(Boolean).length : 0
  const filled = { ...b, exists: true, worktree, ahead, unpushed: up === '' ? -1 : Number(up) || 0, dirty }
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
  const entries = await $.fs.list(`${main}/.claude/plans`).catch(() => [])
  for (const entry of [...entries].sort((a, b) => (a.name < b.name ? -1 : 1))) {
    if (entry.kind !== 'file' || !entry.name.endsWith('.md')) continue
    const source = `.claude/plans/${entry.name}`
    const parsed = parsePlanMarkdown(await readText($, `${main}/${source}`))
    for (const phase of parsed.phases) {
      for (const item of phase.items) {
        item.branches.forEach(b => cited.add(b.branch))
        item.branches = await Promise.all(item.branches.map(b => fillBranch($, b, base, worktrees, main)))
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
      item.branches = await Promise.all(
        item.branches.map(b => fillBranch($, b, epic.bases[b.branch] ?? branch, worktrees, main)),
      )
    }
    found.push({ kind: 'epic', title: epic.title, source: `${path.slice(main.length + 1) || '.'}/${source}`, phases: epic.phases })
  }
  const open = found.filter(isOpen)
  if (open.length === 0) return { plans: [], strays: [] }
  const loose: PlanBranch[] = []
  for (const [branch, path] of worktrees) {
    if (path === main || isToolingBranch(branch) || cited.has(branch)) continue
    loose.push(await fillBranch($, emptyBranch(branch), base, worktrees, main))
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

  return parts.join(' · ')
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
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

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
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
    const id = e.agentId
    if (!id || !isTracked(String(e.tool))) return next(e)
    const isOurs = (await read($, agents)).some(a => a.id === id && a.end === 0)
    if (!isOurs) return next(e)
    const args = e as unknown as Record<string, unknown>
    const label = toolLabel(String(e.tool), args, root)
    await update($, agents, list => list.map(a => (a.id === id ? callStarted(a, label) : a)))
    let isDenied = false
    let isError = true
    try {
      const ran = await next(e)
      isDenied = ran.deny !== undefined
      isError = isDenied || ran.isError === true
      return ran
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
    try {
      return await next(e)
    } finally {
      await update($, isAsking, () => false)
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

      return (
        <Text dimColor wrap="truncate-end">
          {summarize(first)}
          {more}
        </Text>
      )
    }
    const { Text } = $.ui.resolve(e)
    const line = describe(snap, await read($, agents), await read($, isAsking), await read($, now))
    const stage = focusStage(snap)
    const isRed = stage?.status === 'RED' || stage?.status === 'FAILED'

    return (
      <Text color={isRed ? 'error' : undefined} dimColor={!isRed} wrap="truncate-end">
        {line}
      </Text>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const snap = await read($, snapshot)
    const openPlans = await read($, plans)
    const loose = await read($, strays)
    const cites = new Map<string, number>()
    for (const plan of openPlans) {
      for (const item of plan.phases.flatMap(p => p.items)) {
        for (const b of item.branches) cites.set(b.branch, (cites.get(b.branch) ?? 0) + 1)
      }
    }
    const branchLine = (b: PlanBranch) => (
      <Text
        color={b.stageStatus === 'RED' || b.stageStatus === 'FAILED' ? 'error' : !b.exists ? 'warning' : undefined}
        dimColor={b.exists && b.stageStatus !== 'RED' && b.stageStatus !== 'FAILED'}
        wrap="truncate-end"
      >
        {'    '}
        {describeBranch(b)}
        {(cites.get(b.branch) ?? 0) > 1 ? ` · citée par ${cites.get(b.branch)} points` : ''}
      </Text>
    )
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
    const scenarioCard = (s: Scenario) => (
      <Box flexDirection="column" borderStyle="round" borderDimColor paddingX={1}>
        {s.feature !== '' && <Text dimColor>{s.feature}</Text>}
        <Text bold>
          {s.isOutline ? 'Plan · ' : ''}
          {s.title}
        </Text>
        {s.tags.length > 0 && <Text color="suggestion">{s.tags.join(' ')}</Text>}
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
    const at = await read($, now)
    const asking = await read($, isAsking)
    const current = focusStage(snap)
    const files = await read($, scenarios)
    const wanted = await read($, selectedScenario)
    const all = files.flatMap(parseScenarios)
    // L'ancien choix était un chemin de fichier : on retombe sur son premier scénario.
    const found = all.findIndex(s => s.id === wanted || s.path === wanted)
    const index = found === -1 ? 0 : found
    const shown = all[index]
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
          const stats = `${duration((isRunning ? at : a.end) - a.start)} · ${a.calls} appel(s)`

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
              <Button key="scenario-prev" label="‹" onPress={() => update($, selectedScenario, () => step(-1))} />
              <Text>
                {index + 1} / {all.length}
              </Text>
              <Button key="scenario-next" label="›" onPress={() => update($, selectedScenario, () => step(1))} />
              <Text dimColor wrap="truncate-end">
                {shown.file} · {shown.status}
              </Text>
            </Box>
            {all.length > 1 && all.length <= 40 && <Text dimColor>{all.map((_, i) => (i === index ? '●' : '○')).join('')}</Text>}
            {scenarioCard(shown)}
          </Box>
        )}
        {planSection}
      </Box>
    )
  })
}
