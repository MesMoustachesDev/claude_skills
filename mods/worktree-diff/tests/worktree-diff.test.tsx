import { expect, test } from 'claude-code/testing'

const GHERKIN = {
  plugin: 'worktree-diff',
  component: 'Pane',
  requestId: 'worktree-gherkin',
  props: {
    title: 'Scénarios',
    isFocused: false,
    bodyColumns: 80,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 30 },
    view: {},
  },
} as const

const FEATURE = 'Feature: Éditeur\n\n  Scenario: Ajouter un calque\n    Given un dessin\n\n  Scenario: Retirer un calque\n    Given un calque\n'

const seeded: Record<string, unknown> = {
  selectedWorktree: 'feature-svg_layer',
  worktrees: [
    {
      name: 'feature-svg_layer',
      dir: '/wt/feature-svg_layer',
      base: 'develop',
      mergeBase: 'abc',
      branch: 'feature/svg_layer',
      files: [{ path: 'app/test/editor.feature', status: 'A', added: 7, deleted: 0 }],
      features: [{ path: 'app/test/editor.feature', status: 'A', source: FEATURE, scenarios: 2 }],
      error: '',
    },
    { name: 'feature-empty', dir: '/wt/e', base: 'develop', mergeBase: 'abc', branch: '', files: [], features: [], error: '' },
  ],
}

test('the scenarios pane shows the Gherkin of the selected worktree', async ($, on) => {
  on('state.get', (_, e) => (e.key in seeded ? { value: { value: seeded[e.key], version: 1 } } : { value: { value: undefined, version: 0 } }))

  const ui = await $.ui.mount({ ...GHERKIN, surface: 'desktop' })

  const button = await ui.find({ type: 'Button', key: 'feature-feature-svg_layer-app/test/editor.feature' })
  expect(button?.props.label).toBe('editor.feature · A · 2 scénarios')
  expect((await ui.find({ type: 'Code' }))?.props.source).toBe(FEATURE)
  await ui.unmount()
})

test('a worktree without Gherkin says so', async ($, on) => {
  const empty: Record<string, unknown> = { ...seeded, selectedWorktree: 'feature-empty' }
  on('state.get', (_, e) => (e.key in empty ? { value: { value: empty[e.key], version: 1 } } : { value: { value: undefined, version: 0 } }))

  const ui = await $.ui.mount({ ...GHERKIN, surface: 'desktop' })

  expect((await ui.find({ type: 'Text' }))?.text).toBe('Aucun .feature modifié dans feature-empty.')
  await ui.unmount()
})
