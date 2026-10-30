import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { ActiveAgent, PipelineSnapshot } from '../types'
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

const PANE = 'pipeline-view'
const REFRESH_MS = 5000
const DECISION = 'DÉCISION (Thibault)'
const FOLDER = { feature: 'features', fix: 'fixes' } as const

const snapshot = atom({ plugin: 'pipeline-view', key: 'snapshot' } as const, null, {
  shape: 'snapshot-1',
})
const agents = atom({ plugin: 'pipeline-view', key: 'agents' } as const, [], {
  shape: 'agents-2',
})
const isAsking = atom({ plugin: 'pipeline-view', key: 'isAsking' } as const, false)
const now = atom({ plugin: 'pipeline-view', key: 'now' } as const, 0)

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

const load = async ($: EngineInterface): Promise<PipelineSnapshot | null> => {
  root = await git($, ['rev-parse', '--show-toplevel'])
  if (!root) return null
  const where = await locate($, root)
  if (!where) return null
  const dir = `${root}/.claude/${FOLDER[where.kind]}/${where.name}`
  const file = `${dir}/${where.kind === 'feature' ? 'pipeline.json' : 'fix.json'}`
  const config = await readText($, `${root}/.claude/rules/feature_pipeline.md`)
  const snap = parseState(where.kind, where.name, await readText($, file), maxAttemptsFromConfig(config))
  if (!snap || !snap.pkg) return snap
  const grep = await git($, ['grep', '--untracked', '-I', '-F', '-c', DECISION, '--', snap.pkg], root)
  const decisions = grep
    .split('\n')
    .map(line => Number(line.slice(line.lastIndexOf(':') + 1)) || 0)
    .reduce((sum, n) => sum + n, 0)

  return { ...snap, decisions }
}

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
    $.clock.every(REFRESH_MS, () => refresh($))

    return started
  })

  on('command.run', { command: 'pipeline' }, async $ => {
    await refresh($)
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
    if (snap === null || e.props.hasSurvey) return next(e)
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
    const { Box, Text } = $.ui.resolve(e)
    const snap = await read($, snapshot)
    if (snap === null) {
      return <Text dimColor>Aucun /feature ni /fix en cours dans ce dépôt.</Text>
    }
    const list = await read($, agents)
    const at = await read($, now)
    const asking = await read($, isAsking)
    const current = focusStage(snap)

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
      </Box>
    )
  })
}
