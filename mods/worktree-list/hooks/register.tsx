import { atom, read, update } from 'claude-code'
import type { EngineInterface as Engine, Register } from 'claude-code'

import type { Worktree } from '../types'

const PANE = 'worktree-list'
const REFRESH_MS = 30_000

// Change the tag when a Worktree's fields change: it declines what an earlier
// version stored, which outlives a reload.
const worktrees = atom({ plugin: 'worktree-list', key: 'worktrees' } as const, [], { shape: 'worktrees-1' })
const root = atom({ plugin: 'worktree-list', key: 'root' } as const, '')

// `git worktree list --porcelain`: one block per worktree, blank-line separated.
function parse(porcelain: string, current: string): Worktree[] {
  return porcelain
    .split('\n\n')
    .filter(block => block.trim())
    .map(block => {
      const lines = block.split('\n')
      const value = (key: string) => lines.find(line => line.startsWith(`${key} `))?.slice(key.length + 1) ?? ''
      const path = value('worktree')
      const branch = value('branch').replace(/^refs\/heads\//, '')
      return {
        path,
        branch: branch || (lines.includes('bare') ? '(bare)' : ''),
        sha: value('HEAD').slice(0, 8),
        isLocked: lines.some(line => line === 'locked' || line.startsWith('locked ')),
        isPrunable: lines.some(line => line === 'prunable' || line.startsWith('prunable ')),
        isCurrent: path === current,
      }
    })
}

async function refresh($: Engine) {
  const top = await $.process.run(['git', 'rev-parse', '--show-toplevel'])
  if (top.exitCode !== 0) {
    await update($, root, () => '')
    await update($, worktrees, () => [])
    return
  }
  const current = top.stdout.trim()
  const list = await $.process.run(['git', 'worktree', 'list', '--porcelain'])
  const found = list.exitCode === 0 ? parse(list.stdout, current) : []
  // The first entry is always the main checkout: other paths read relative to it.
  await update($, root, () => found[0]?.path ?? current)
  await update($, worktrees, () => found)
}

function shortPath(path: string, main: string) {
  if (path === main) return '. (principal)'
  return path.startsWith(`${main}/`) ? path.slice(main.length + 1) : path
}

function asText(list: Worktree[], main: string) {
  if (list.length === 0) return 'Pas de dépôt git dans le dossier courant.'
  return list
    .map(one => {
      const branch = one.branch || `détachée @ ${one.sha}`
      const flags = [one.isLocked && 'verrouillé', one.isPrunable && 'à nettoyer'].filter(Boolean).join(', ')
      return `${one.isCurrent ? '●' : '○'} ${shortPath(one.path, main)} → ${branch}${flags ? ` (${flags})` : ''}`
    })
    .join('\n')
}

let isStarted = false

// Once per load: on a new session from session.start, after a hot reload from
// the first turn end (session.start does not run again then).
async function start($: Engine) {
  if (isStarted) return
  isStarted = true
  await refresh($)
  const opened = await $.ui.open({ id: PANE, title: 'Worktrees du dépôt' })
  if (!opened.isPlaced) $.ui.status(`worktree-list : pane non placé (${opened.reason}), tape /worktrees`)
  $.clock.every(REFRESH_MS, () => void refresh($))
}

export const register: Register = on => {
  isStarted = false

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'worktrees',
      description: 'Liste les worktrees du dépôt courant et la branche de chacun',
    })
    await start($)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    await start($)
    await refresh($)
    return next(e)
  })

  on('command.run', { command: 'worktrees' }, async $ => {
    await refresh($)
    const opened = await $.ui.open({ id: PANE, title: 'Worktrees du dépôt' })
    const text = asText(await read($, worktrees), await read($, root))
    return { text: opened.isPlaced ? text : `${text}\n\nPane non placé : ${opened.reason}` }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const list = await read($, worktrees)
    const main = await read($, root)

    if (list.length === 0) {
      return <Text dimColor>Pas de dépôt git dans le dossier courant.</Text>
    }

    return (
      <Box flexDirection="column" gap={1}>
        <Box flexDirection="row" gap={1}>
          <Text dimColor>{main}</Text>
          <Button key="refresh" label="Rafraîchir" plain onPress={() => refresh($)} />
        </Box>
        <Box flexDirection="column">
          {list.map(one => (
            <Box key={`wt-${one.path}`} flexDirection="row" gap={1}>
              <Text color={one.isCurrent ? 'success' : 'inactive'}>{one.isCurrent ? '●' : '○'}</Text>
              <Text bold={one.isCurrent}>{shortPath(one.path, main)}</Text>
              <Text dimColor>→</Text>
              {one.branch ? (
                <Text color="suggestion">{one.branch}</Text>
              ) : (
                <Text color="warning">détachée @ {one.sha}</Text>
              )}
              {one.isLocked && <Text dimColor>verrouillé</Text>}
              {one.isPrunable && <Text color="error">à nettoyer</Text>}
            </Box>
          ))}
        </Box>
      </Box>
    )
  })
}
