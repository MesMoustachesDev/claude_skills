import { atom, read, update } from 'claude-code'
import type { Engine, Register } from 'claude-code'

import type { ChangedFile, PipelineWorktree, SelectedDiff } from '../types'

const PANE = 'worktree-diff'
// Pipeline records and generated files: the tree shows the code a run wrote.
const HIDDEN_PREFIXES = ['.claude/']

const worktrees = atom({ plugin: 'worktree-diff', key: 'worktrees' } as const, [])
const selectedWorktree = atom({ plugin: 'worktree-diff', key: 'selectedWorktree' } as const, '')
const collapsed = atom({ plugin: 'worktree-diff', key: 'collapsed' } as const, [])
const diff = atom({ plugin: 'worktree-diff', key: 'diff' } as const, null)
const areTestsShown = atom({ plugin: 'worktree-diff', key: 'areTestsShown' } as const, false)

const TEST_FOLDERS = ['test', 'tests', 'integration_test', 'test_driver', '__tests__', 'maestro']

function isTest(path: string) {
  const parts = path.split('/')
  const name = parts.at(-1) ?? ''
  return (
    parts.slice(0, -1).some(part => TEST_FOLDERS.includes(part)) ||
    name.endsWith('_test.dart') ||
    /\.(test|spec)\.[a-z]+$/.test(name)
  )
}

async function git($: Engine, dir: string, args: string[]) {
  return $.process.run(['git', ...args], { cwd: dir })
}

async function readJson($: Engine, path: string): Promise<Record<string, unknown> | null> {
  if (!(await $.fs.exists(path))) return null
  return JSON.parse(await $.fs.read(path)) as Record<string, unknown>
}

// The base a run measures its diff against: pipeline.json → base, fix.json → base_sha.
async function baseOf($: Engine, dir: string, entry: string): Promise<string | null> {
  if (entry.startsWith('feature-')) {
    const pipeline = await readJson($, `${dir}/.claude/features/${entry.slice('feature-'.length)}/pipeline.json`)
    return typeof pipeline?.base === 'string' ? pipeline.base : null
  }
  if (entry.startsWith('fix-')) {
    const fix = await readJson($, `${dir}/.claude/fixes/${entry.slice('fix-'.length)}/fix.json`)
    return typeof fix?.base_sha === 'string' ? fix.base_sha : null
  }
  return null
}

async function mergeBaseOf($: Engine, dir: string, base: string): Promise<string | null> {
  for (const ref of [base, `origin/${base}`]) {
    const { exitCode, stdout } = await git($, dir, ['merge-base', 'HEAD', ref])
    if (exitCode === 0) return stdout.trim()
  }
  return null
}

function isShown(path: string) {
  return !HIDDEN_PREFIXES.some(prefix => path.startsWith(prefix))
}

// Committed and uncommitted changes since the merge-base, untracked files included.
async function changedFiles($: Engine, dir: string, mergeBase: string): Promise<ChangedFile[]> {
  const statuses = await git($, dir, ['diff', '--name-status', '-M', mergeBase])
  const counts = await git($, dir, ['diff', '--numstat', '-M', mergeBase])
  const untracked = await git($, dir, ['ls-files', '--others', '--exclude-standard'])

  const byPath = new Map<string, ChangedFile>()
  for (const line of statuses.stdout.split('\n').filter(Boolean)) {
    const [status, ...paths] = line.split('\t')
    const path = paths.at(-1) ?? ''
    byPath.set(path, { path, status: status.charAt(0), added: 0, deleted: 0 })
  }
  for (const line of counts.stdout.split('\n').filter(Boolean)) {
    const [added, deleted, ...rest] = line.split('\t')
    // A rename reads "old => new" or "dir/{old => new}"; the new name is what --name-status keys.
    const raw = rest.join('\t')
    const path = raw.includes('=>') ? raw.replace(/\{[^}]*=> ([^}]*)\}/, '$1').replace(/.* => /, '') : raw
    const file = byPath.get(path)
    if (file) {
      file.added = Number(added) || 0
      file.deleted = Number(deleted) || 0
    }
  }
  for (const path of untracked.stdout.split('\n').filter(Boolean)) {
    if (!byPath.has(path)) byPath.set(path, { path, status: '?', added: 0, deleted: 0 })
  }

  return [...byPath.values()].filter(file => isShown(file.path)).sort((a, b) => (a.path < b.path ? -1 : 1))
}

// /feature and /fix runs live in <main checkout>/.claude/worktrees; the common git dir
// names the main checkout even from inside one of those worktrees.
async function worktreesRoot($: Engine): Promise<string | null> {
  const { exitCode, stdout } = await $.process.run(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'])
  if (exitCode !== 0) return null
  return `${stdout.trim().replace(/\/\.git$/, '')}/.claude/worktrees`
}

async function scan($: Engine): Promise<PipelineWorktree[]> {
  const WORKTREES = await worktreesRoot($)
  if (WORKTREES === null || !(await $.fs.exists(WORKTREES))) return []
  const found: PipelineWorktree[] = []
  for (const entry of await $.fs.list(WORKTREES)) {
    if (entry.kind !== 'dir') continue
    if (!entry.name.startsWith('feature-') && !entry.name.startsWith('fix-')) continue
    const dir = `${WORKTREES}/${entry.name}`
    const base = await baseOf($, dir, entry.name)
    if (base === null) continue
    const mergeBase = await mergeBaseOf($, dir, base)
    if (mergeBase === null) {
      found.push({ name: entry.name, dir, base, mergeBase: '', files: [], error: `base ${base} introuvable` })
      continue
    }
    found.push({ name: entry.name, dir, base, mergeBase, files: await changedFiles($, dir, mergeBase), error: '' })
  }
  return found
}

async function refresh($: Engine) {
  const found = await scan($)
  await update($, worktrees, () => found)
  const current = await read($, selectedWorktree)
  if (!found.some(worktree => worktree.name === current)) {
    await update($, selectedWorktree, () => found[0]?.name ?? '')
  }
}

async function showDiff($: Engine, worktree: PipelineWorktree, file: ChangedFile) {
  const args =
    file.status === '?'
      ? ['diff', '--no-index', '--', '/dev/null', file.path]
      : ['diff', '-M', worktree.mergeBase, '--', file.path]
  const { stdout } = await git($, worktree.dir, args)
  const selected: SelectedDiff = { worktree: worktree.name, path: file.path, source: stdout || '(aucun diff textuel)' }
  await update($, diff, () => selected)
}

type DirNode = { name: string; path: string; dirs: DirNode[]; files: ChangedFile[]; count: number }

type Row =
  | { kind: 'dir'; guide: string; node: DirNode }
  | { kind: 'file'; guide: string; file: ChangedFile; name: string }

function buildTree(files: ChangedFile[]): DirNode {
  const root: DirNode = { name: '', path: '', dirs: [], files: [], count: 0 }
  for (const file of files) {
    const parts = file.path.split('/')
    let node = root
    for (const part of parts.slice(0, -1)) {
      const path = node.path ? `${node.path}/${part}` : part
      let child = node.dirs.find(dir => dir.path === path)
      if (!child) {
        child = { name: part, path, dirs: [], files: [], count: 0 }
        node.dirs.push(child)
      }
      node = child
    }
    node.files.push(file)
  }
  return compress(root)
}

// A folder holding one folder and no file merges with it, as in VS Code: a/b/c on one row.
function compress(node: DirNode): DirNode {
  node.dirs = node.dirs.map(dir => {
    let merged = dir
    while (merged.files.length === 0 && merged.dirs.length === 1) {
      const only = merged.dirs[0]
      merged = { ...only, name: `${merged.name}/${only.name}` }
    }
    return compress(merged)
  })
  node.count = node.files.length + node.dirs.reduce((sum, dir) => sum + dir.count, 0)
  return node
}

// Folders before files, each with its guide (├─ └─ │), skipping what a folded folder holds.
function treeRows(node: DirNode, folded: string[], prefix = ''): Row[] {
  const children = [
    ...node.dirs.map(dir => ({ kind: 'dir' as const, dir })),
    ...node.files.map(file => ({ kind: 'file' as const, file })),
  ]
  const rows: Row[] = []
  children.forEach((child, index) => {
    const isLast = index === children.length - 1
    // Non-breaking spaces: the desktop collapses ordinary leading whitespace.
    const guide = `${prefix}${isLast ? '└─ ' : '├─ '}`
    if (child.kind === 'dir') {
      rows.push({ kind: 'dir', guide, node: child.dir })
      if (!folded.includes(child.dir.path)) {
        rows.push(...treeRows(child.dir, folded, `${prefix}${isLast ? '   ' : '│  '}`))
      }
    } else {
      rows.push({ kind: 'file', guide, file: child.file, name: child.file.path.split('/').at(-1) ?? child.file.path })
    }
  })
  return rows
}

function statusColor(status: string) {
  if (status === 'A') return 'success'
  if (status === 'D') return 'error'
  if (status === '?') return 'inactive'
  return 'warning'
}

const REFRESH_MS = 30_000
let isStarted = false

// Opens the pane and starts the timer once per load: on a new session from
// session.start, after a hot reload from the first turn end (session.start
// does not run again then).
async function start($: Engine) {
  if (isStarted) return
  isStarted = true
  await refresh($)
  await $.ui.open({ id: PANE, title: 'Worktrees' })
  $.clock.every(REFRESH_MS, () => {
    void refresh($)
  })
}

export const register: Register = on => {
  isStarted = false

  on('session.start', async ($, e, next) => {
    await start($)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    await start($)
    await refresh($)
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Code, Text } = $.ui.resolve(e)
    const all = await read($, worktrees)
    const selectedName = await read($, selectedWorktree)
    const folded = await read($, collapsed)
    const shownDiff = await read($, diff)
    const worktree = all.find(one => one.name === selectedName)
    const isDiffShown = shownDiff !== null && shownDiff.worktree === worktree?.name
    const testsShown = await read($, areTestsShown)
    const testCount = worktree?.files.filter(file => isTest(file.path)).length ?? 0
    const visibleFiles = (worktree?.files ?? []).filter(file => testsShown || !isTest(file.path))

    if (all.length === 0) {
      return <Text dimColor>Aucun worktree /feature ou /fix actif.</Text>
    }

    return (
      <Box flexDirection="column" gap={1}>
        <Box flexDirection="row" flexWrap="wrap" gap={1}>
          {all.map(one => (
            <Button
              key={`wt-${one.name}`}
              label={`${one.name} (${one.files.length})`}
              variant={one.name === selectedName ? 'primary' : 'secondary'}
              onPress={() => update($, selectedWorktree, () => one.name)}
            />
          ))}
          <Button key="refresh" label="Rafraîchir" plain onPress={() => refresh($)} />
          <Button
            key="tests"
            plain
            label={testsShown ? 'Tests affichés' : `Tests masqués (${testCount})`}
            onPress={() => update($, areTestsShown, shown => !shown)}
          />
        </Box>

        {/* Tree and diff side by side: below a long tree the diff falls out of the pane's rows. */}
        <Box flexDirection="row" gap={2}>
        {worktree && (
          <Box flexDirection="column" width={isDiffShown ? '35%' : '100%'} flexShrink={0}>
            <Text dimColor>
              base {worktree.base} · {worktree.mergeBase.slice(0, 9)}
            </Text>
            {worktree.error && <Text color="red">{worktree.error}</Text>}
            {treeRows(buildTree(visibleFiles), folded).map(row =>
              row.kind === 'dir' ? (
                <Box key={`dir-${worktree.name}-${row.node.path}`} flexDirection="row">
                  <Text mono dimColor>{row.guide}</Text>
                  <Button
                    key={`dirbtn-${worktree.name}-${row.node.path}`}
                    plain
                    label={`${folded.includes(row.node.path) ? '▸' : '▾'} ${row.node.name}/`}
                    onPress={() =>
                      update($, collapsed, list =>
                        list.includes(row.node.path)
                          ? list.filter(one => one !== row.node.path)
                          : [...list, row.node.path],
                      )
                    }
                  />
                  <Text dimColor> {row.node.count}</Text>
                </Box>
              ) : (
                <Box key={`file-${worktree.name}-${row.file.path}`} flexDirection="row">
                  <Text mono dimColor>{row.guide}</Text>
                  <Text mono color={statusColor(row.file.status)}>{row.file.status} </Text>
                  <Button
                    key={`filebtn-${worktree.name}-${row.file.path}`}
                    plain
                    dimColor={!(isDiffShown && shownDiff?.path === row.file.path)}
                    label={`${isDiffShown && shownDiff?.path === row.file.path ? '● ' : ''}${row.name}`}
                    onPress={() => showDiff($, worktree, row.file)}
                  />
                  <Text color="diffAdded"> +{row.file.added}</Text>
                  <Text color="diffRemoved"> −{row.file.deleted}</Text>
                </Box>
              ),
            )}
          </Box>
        )}

        {isDiffShown && shownDiff && (
          <Box flexDirection="column" flexGrow={1} flexShrink={1}>
            <Box flexDirection="row" gap={1}>
              <Text bold wrap="truncate-start">{shownDiff.path}</Text>
              <Button key="close-diff" label="Fermer" plain onPress={() => update($, diff, () => null)} />
            </Box>
            <Code source={shownDiff.source} format="diff" path={shownDiff.path} />
          </Box>
        )}
        </Box>
      </Box>
    )
  })
}
