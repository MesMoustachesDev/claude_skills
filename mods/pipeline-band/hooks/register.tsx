import { atom, read, update } from 'claude-code'
import type { Engine, Register } from 'claude-code'

import type { PipelineSnapshot } from '../types'

const snapshot = atom({ plugin: 'pipeline-band', key: 'snapshot' } as const, null)
const isHidden = atom({ plugin: 'pipeline-band', key: 'isHidden' } as const, false)

type Stage = { status?: string; at?: string }
type Pipeline = {
  feature?: string
  stages?: Record<string, Stage>
  cockpit?: { waiting?: string }
}

// /feature runs live in <main checkout>/.claude/worktrees; the common git dir
// names the main checkout even from inside one of those worktrees.
async function worktreesRoot($: Engine): Promise<string | null> {
  const { exitCode, stdout } = await $.process.run(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'])
  if (exitCode !== 0) return null
  return `${stdout.trim().replace(/\/\.git$/, '')}/.claude/worktrees`
}

// The feature whose pipeline.json changed last, with its latest stage.
async function latestPipeline($: Engine): Promise<PipelineSnapshot | null> {
  const worktrees = await worktreesRoot($)
  if (worktrees === null || !(await $.fs.exists(worktrees))) return null
  let newest: { path: string; mtimeMs: number } | null = null
  for (const worktree of await $.fs.list(worktrees)) {
    if (worktree.kind !== 'dir') continue
    const features = `${worktrees}/${worktree.name}/.claude/features`
    if (!(await $.fs.exists(features))) continue
    for (const feature of await $.fs.list(features)) {
      if (feature.kind !== 'dir') continue
      const path = `${features}/${feature.name}/pipeline.json`
      if (!(await $.fs.exists(path))) continue
      const { mtimeMs } = await $.fs.stat(path)
      if (newest === null || mtimeMs > newest.mtimeMs) newest = { path, mtimeMs }
    }
  }
  if (newest === null) return null

  const pipeline = JSON.parse(await $.fs.read(newest.path)) as Pipeline
  const stages = Object.entries(pipeline.stages ?? {})
  // ISO timestamps sort as plain strings; the mod runtime has no localeCompare.
  const byDate = ([, a]: [string, Stage], [, b]: [string, Stage]) => ((a.at ?? '') < (b.at ?? '') ? -1 : 1)
  const [key, stage] = stages.sort(byDate).at(-1) ?? []

  return {
    feature: pipeline.feature ?? '?',
    step: key ? `${key} ${stage?.status ?? ''}`.trim() : 'cadrage',
    waiting: pipeline.cockpit?.waiting ?? '',
  }
}

function describe(current: PipelineSnapshot): string {
  const waiting = current.waiting ? ` · en attente : ${current.waiting}` : ''
  return `${current.feature} · ${current.step}${waiting}`
}

export const register: Register = on => {
  // Refreshes at each turn end: session.start does not run again on a hot reload.
  on('turn.complete', async ($, e, next) => {
    const found = await latestPipeline($)
    await update($, snapshot, () => found)
    $.ui.status(found ? describe(found) : undefined)
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const current = await read($, snapshot)
    if (e.props.hasSurvey || current === null || (await read($, isHidden))) {
      return next(e)
    }

    const { Box, Button, Text } = $.ui.resolve(e)

    return (
      <Box>
        <Text dimColor>{describe(current)} </Text>
        <Button key="hide" label="Masquer" onPress={() => update($, isHidden, () => true)} />
      </Box>
    )
  })
}
