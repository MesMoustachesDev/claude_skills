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

const engine = (on: Parameters<Parameters<typeof test>[1]>[1], toplevel: string) => {
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
  on('fs.read', () => ({ value: JSON.stringify({ base: 'develop' }) }))
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
