import { expect, test } from 'claude-code/testing'

const PANE = {
  plugin: 'worktree-diff',
  component: 'Pane',
  requestId: 'worktree-diff',
  props: {
    title: 'Worktrees',
    isFocused: false,
    bodyColumns: 100,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 30 },
    view: {},
  },
} as const

const WORKTREES = '/repo/.claude/worktrees'

type On = Parameters<Parameters<typeof test>[1]>[1]

// files: the worktree's files by path relative to it, each read in turn (the last one stays).
const engine = (on: On, toplevel: string, files: Record<string, string[]> = {}) => {
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('ui.status', () => ({ value: undefined }))
  on('clock.every', () => ({ value: undefined }))
  on('ui.panes', () => ({ value: [] }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('fs.exists', () => ({ value: true }))
  on('fs.list', () => ({
    value: [
      { name: 'feature-library_feature', kind: 'dir', size: 0, mtimeMs: 0, isLink: false },
      { name: 'feature-layer_feature', kind: 'dir', size: 0, mtimeMs: 0, isLink: false },
    ],
  }))
  on('fs.read', (_, e) => {
    const relative = Object.keys(files).find(path => e.path.endsWith(`/${path}`))
    if (!relative) return { value: JSON.stringify({ base: 'develop' }) }
    const versions = files[relative] ?? []
    return { value: (versions.length > 1 ? versions.shift() : versions[0]) ?? '' }
  })
  on('process.run', (_, e) => {
    const argv = e.argv.join(' ')
    const stdout = argv.includes('--git-common-dir')
      ? '/repo/.git'
      : argv.includes('--show-toplevel')
        ? toplevel
        : argv.includes('--abbrev-ref')
          ? 'feature/x'
          : argv.includes('merge-base')
            ? 'abc'
            : argv.includes('--name-status')
              ? Object.keys(files).map(path => `M\t${path}`).join('\n')
              : ''

    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
}

test('depuis un worktree de pipeline, le panneau ne montre que lui', async ($, on) => {
  engine(on, `${WORKTREES}/feature-layer_feature`)
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })

  expect(await ui.find({ type: 'Button', key: 'wt-feature-library_feature' })).toBeUndefined()
  expect(await ui.find({ type: 'Button', key: 'wt-feature-layer_feature' })).toBeUndefined()
  expect((await ui.find({ type: 'Text', text: /base develop/ }))?.text).toContain('base develop')
  await ui.unmount()
})

test('depuis le checkout principal, le panneau montre tous les worktrees', async ($, on) => {
  engine(on, '/repo')
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })

  expect(await ui.find({ type: 'Button', key: 'wt-feature-library_feature' })).toBeDefined()
  expect(await ui.find({ type: 'Button', key: 'wt-feature-layer_feature' })).toBeDefined()
  await ui.unmount()
})

const FILE = 'lib/a.dart'
const LAYER = `${WORKTREES}/feature-layer_feature`

async function openDiff($: Parameters<Parameters<typeof test>[1]>[0], surface: 'desktop' | 'mobile') {
  await $.session.start({ cwd: '/', surface, isInteractive: true })
  const ui = await $.ui.mount({ ...PANE, surface })
  await ui.press({ key: `filebtn-feature-layer_feature-${FILE}` })
  return ui
}

test('le fichier choisi s’édite et s’enregistre dans son worktree', async ($, on) => {
  engine(on, LAYER, { [FILE]: ['avant\n'] })
  const writes: { path: string; text: string }[] = []
  on('fs.write', (_, e) => {
    writes.push(e)
    return { value: undefined }
  })
  const ui = await openDiff($, 'desktop')

  await ui.press({ key: 'edit' })
  expect((await ui.find({ type: 'Input' }))?.props.value).toBe('avant\n')
  await ui.input({ key: `editor-feature-layer_feature-${FILE}`, text: 'après\n', kind: 'change' })
  await ui.press({ key: 'save' })

  expect(writes).toEqual([{ path: `${LAYER}/${FILE}`, text: 'après\n' }])
  expect(await ui.find({ type: 'Input' })).toBeUndefined()
  await ui.unmount()
})

test('un fichier changé sur le disque pendant l’édition n’est pas écrasé', async ($, on) => {
  engine(on, LAYER, { [FILE]: ['avant\n', 'écrit par un agent\n'] })
  const writes: unknown[] = []
  on('fs.write', (_, e) => {
    writes.push(e)
    return { value: undefined }
  })
  const ui = await openDiff($, 'desktop')

  await ui.press({ key: 'edit' })
  await ui.input({ key: `editor-feature-layer_feature-${FILE}`, text: 'après\n', kind: 'change' })
  await ui.press({ key: 'save' })

  expect(writes).toEqual([])
  expect((await ui.find({ type: 'Input' }))?.props.value).toBe('écrit par un agent\n')
  expect(await ui.find({ type: 'Text', text: /changé sur le disque/ })).toBeDefined()
  await ui.unmount()
})

test('sur mobile, sans champ de saisie, le panneau reste en lecture', async ($, on) => {
  engine(on, LAYER, { [FILE]: ['avant\n'] })
  const ui = await openDiff($, 'mobile')

  expect(await ui.find({ type: 'Button', key: 'edit' })).toBeUndefined()
  expect(await ui.find({ type: 'Code' })).toBeDefined()
  await ui.unmount()
})
