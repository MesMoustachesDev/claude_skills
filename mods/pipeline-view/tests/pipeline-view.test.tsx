import { expect, test } from 'claude-code/testing'

const ROOT = '/repo'
const PIPELINE = JSON.stringify({
  feature: 'two_factor_login',
  package: 'flutter_app/features/login',
  stages: {
    contracts: { status: 'PASSED', at: '2026-10-05T09:03:25Z' },
    red: { status: 'PASSED', at: '2026-10-05T10:00:00Z' },
    green: { status: 'RED', at: '2026-10-13T12:10:15Z' },
  },
  attempts: { contracts: 0, red: 0, green: 2 },
})

const BAND = {
  plugin: 'pipeline-view',
  component: 'AbovePrompt',
  props: { hasSurvey: false, bodyColumns: 120 },
} as const

const PANE = {
  plugin: 'pipeline-view',
  component: 'Pane',
  requestId: 'pipeline-view',
  props: {
    title: 'Pipeline',
    isFocused: false,
    bodyColumns: 60,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 30 },
    view: {},
  },
} as const

const engine = (on: Parameters<Parameters<typeof test>[1]>[1], branch: string, opens: string[] = []) => {
  on('command.register', () => ({ value: { command: 'pipeline' } }))
  on('ui.open', (_, e) => {
    opens.push(e.id)
    return { value: { isPlaced: true } }
  })
  on('clock.every', () => ({ value: undefined }))
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine</Text>
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('process.run', (_, e) => {
    const argv = e.argv.join(' ')
    const out = argv.includes('rev-parse')
      ? ROOT
      : argv.includes('branch')
        ? branch
        : argv.includes('grep')
          ? 'flutter_app/features/login/lib/a.dart:2\nflutter_app/features/login/lib/b.dart:1'
          : ''

    return { value: { exitCode: 0, stdout: out, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('fs.read', (_, e) =>
    e.path === `${ROOT}/.claude/features/two_factor_login/pipeline.json`
      ? { value: PIPELINE }
      : { deny: 'ENOENT' },
  )
}

test('la bande montre la feature, l’étape rouge et ses tentatives', async ($, on) => {
  engine(on, 'feature/two_factor_login')
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    const line = await ui.find({ type: 'Text', text: /two_factor_login/ })
    expect(line?.text).toBe(
      'feature two_factor_login · ✗ impl (vert) 2/5 · 3 DÉCISION (Thibault)',
    )
    await ui.unmount()
  }
})

test('le panneau liste les étapes dans l’ordre du pipeline', async ($, on) => {
  engine(on, 'feature/two_factor_login')
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /contrats/ }))?.text).toBe('✓ contrats · Arthur, puis Thibault')
  expect((await ui.find({ type: 'Text', text: /impl/ }))?.text).toBe('✗ impl (vert) · Ivan  2/5')
  await ui.unmount()
})

test('hors pipeline, la bande laisse la place', async ($, on) => {
  engine(on, 'develop')
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /feature/ })).toBeUndefined()
  await ui.unmount()
})

test('le panneau s’ouvre seul, une fois, quand un pipeline est en cours', async ($, on) => {
  const opens: string[] = []
  engine(on, 'feature/two_factor_login', opens)
  await $.session.start({ cwd: ROOT, surface: 'desktop', isInteractive: true })
  await $.command.run({ command: 'pipeline' })

  expect(opens).toEqual(['pipeline-view', 'pipeline-scenarios', 'pipeline-view', 'pipeline-scenarios'])
})

test('hors pipeline, le panneau ne s’ouvre pas seul', async ($, on) => {
  const opens: string[] = []
  engine(on, 'develop', opens)
  await $.session.start({ cwd: ROOT, surface: 'desktop', isInteractive: true })

  expect(opens).toEqual([])
})

test('le panneau suit Ivan : durée, appels, refus et fichiers modifiés', async ($, on) => {
  engine(on, 'feature/two_factor_login')
  let clock = 1_000_000
  on('clock.now', () => ({ value: clock }))
  on('agent.spawn', () => ({ model: 'opus', agentId: 'ivan-1' }))
  on('tool.call', (_, e) =>
    String(e.file_path ?? '').includes('/test/')
      ? { deny: 'pipeline-restrict-writes : feature-implementer ne touche pas aux tests' }
      : { result: {} },
  )
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })

  await $.agent.spawn({ prompt: 'impl', subagentType: 'feature-implementer' })
  await $.tool.call({
    tool: 'Edit',
    file_path: `${ROOT}/flutter_app/features/login/test/a_test.dart`,
    old_string: 'a',
    new_string: 'b',
    agentId: 'ivan-1',
  })
  await $.tool.call({
    tool: 'Edit',
    file_path: `${ROOT}/flutter_app/features/login/lib/a.dart`,
    old_string: 'a',
    new_string: 'b',
    agentId: 'ivan-1',
  })
  clock += 187_000
  await $.tool.call({ tool: 'Bash', command: 'git status', agentId: 'ivan-1' })

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /▸ Ivan/ }))?.text).toBe('▸ Ivan (implémentation) · 3m07 · 3 appel(s)')
    expect((await ui.find({ type: 'Text', text: /refusé/ }))?.text).toBe(
      '  1 écriture(s) ou appel(s) refusé(s)',
    )
    expect((await ui.find({ type: 'Text', text: /modifié/ }))?.text).toBe(
      '  modifié : flutter_app/features/login/lib/a.dart',
    )
    await ui.unmount()
  }

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await band.find({ type: 'Text', text: /Ivan/ }))?.text).toContain(
    'Ivan (implémentation) au travail 3m07, 1 refus',
  )
  await band.unmount()
})

const SCENARIOS_PANE = { ...PANE, requestId: 'pipeline-scenarios', props: { ...PANE.props, title: 'Scénarios' } } as const
const GHERKIN = 'Feature: Login\n\n  Scenario: Code juste\n    Given un code\n\n  Scénario: Code faux\n    Given un code\n'

const seed = (on: Parameters<Parameters<typeof test>[1]>[1], values: Record<string, unknown>) =>
  on('state.get', (_, e) => (e.key in values ? { value: { value: values[e.key], version: 1 } } : { value: { value: undefined, version: 0 } }))

test('le panneau Scénarios montre le Gherkin que le pipeline a changé', async ($, on) => {
  seed(on, {
    snapshot: { shape: 'snapshot-1', value: { kind: 'feature', name: 'two_factor_login', pkg: 'app/login', phase: '', maxAttempts: 5, stages: [], decisions: 0 } },
    scenarios: [{ path: 'app/login/test/login.feature', status: 'ajouté', source: GHERKIN, count: 2 }],
  })

  const ui = await $.ui.mount({ ...SCENARIOS_PANE, surface: 'desktop' })

  expect((await ui.find({ type: 'Button', key: 'scenario-app/login/test/login.feature' }))?.props.label).toBe(
    'login.feature · ajouté · 2 scénarios',
  )
  expect((await ui.find({ type: 'Code' }))?.props.source).toBe(GHERKIN)
  await ui.unmount()
})

test('le panneau Scénarios attend le premier .feature', async ($, on) => {
  seed(on, {
    snapshot: { shape: 'snapshot-1', value: { kind: 'feature', name: 'svg_layer', pkg: 'app/editor', phase: '', maxAttempts: 5, stages: [], decisions: 0 } },
  })

  const ui = await $.ui.mount({ ...SCENARIOS_PANE, surface: 'desktop' })

  expect((await ui.find({ type: 'Text' }))?.text).toBe('Pas encore de .feature ajouté ou modifié dans app/editor.')
  await ui.unmount()
})
