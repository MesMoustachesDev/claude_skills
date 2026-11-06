import { expect, test } from 'claude-code/testing'

import { activityOf, describeActivity, parseActivity, pipelineTarget } from '../hooks/activity'
import { attribute, parseNameStatus, parsePorcelain, parseWrites, sessionOfTranscript } from '../hooks/attribution'
import { commonPrefix, latestRun, parseMaestroReport, parseTestReport, shotLabel, testStateOf } from '../hooks/evidence'
import { MAX_DOC, contractFiles, fixNextStep, fixPlanMarkdown, sourcesFor, toDoc, waitingOf } from '../hooks/pending'

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

  expect(opens).toEqual(['pipeline-view', 'pipeline-view'])
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

const GHERKIN = `Feature: Login

  Background:
    Given the login page is displayed

  @smoke
  Scenario: Code juste
    Given un code {'123456'}
    When I tap the {'login_submit_button'} button
    And I wait {2} seconds
    Then I am on the home page

  Scénario: Code faux
    Étant donné un code faux
    Alors je vois une erreur
`

const seed = (on: Parameters<Parameters<typeof test>[1]>[1], values: Record<string, unknown>) =>
  on('state.get', (_, e) => (e.key in values ? { value: { value: values[e.key], version: 1 } } : { value: { value: undefined, version: 0 } }))

const SNAP = { shape: 'snapshot-1', value: { kind: 'feature', name: 'two_factor_login', pkg: 'app/login', phase: '', maxAttempts: 5, stages: [], decisions: 0 } }
const FILES = [
  { path: 'app/login/test/login.feature', status: 'ajouté', source: GHERKIN, count: 2 },
  { path: 'app/login/test/otp.feature', status: 'modifié', source: 'Feature: OTP\n  Scenario: Renvoi\n    Then le code part\n', count: 1 },
]

test('le panneau Pipeline montre un scénario à la fois, en carte', async ($, on) => {
  seed(on, { snapshot: SNAP, scenarios: FILES })

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })

  expect((await ui.find({ type: 'Text', text: /^1 \/ 3$/ }))?.text).toBe('1 / 3')
  expect((await ui.find({ type: 'Text', text: /login\.feature/ }))?.text).toBe('login.feature · ajouté')
  expect((await ui.find({ type: 'Text', text: /^Code juste$/ }))?.text).toBe('Code juste')
  expect((await ui.find({ type: 'Text', text: /^@smoke$/ }))?.text).toBe('@smoke')
  expect((await ui.find({ type: 'Text', text: /login page/ }))?.text).toBe('Given the login page is displayed')
  expect((await ui.find({ type: 'Text', text: /seconds/ }))?.text).toBe('  And I wait 2 seconds')
  expect((await ui.find({ type: 'Text', text: /^123456$/ }))?.props.bold).toBe(true)
  expect((await ui.find({ type: 'Text', text: /^●○○$/ }))?.text).toBe('●○○')
  expect(await ui.find({ type: 'Button', key: 'scenario-next' })).toBeDefined()
  await ui.unmount()
})

test('le carousel montre le scénario choisi', async ($, on) => {
  seed(on, { snapshot: SNAP, scenarios: FILES, selectedScenario: 'app/login/test/login.feature#2' })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /^2 \/ 3$/ }))?.text).toBe('2 / 3')
  expect((await ui.find({ type: 'Text', text: /erreur/ }))?.text).toBe('Alors je vois une erreur')
  await ui.unmount()
})

test('un ancien choix de fichier ouvre son premier scénario', async ($, on) => {
  seed(on, { snapshot: SNAP, scenarios: FILES, selectedScenario: 'app/login/test/otp.feature' })
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /^Renvoi$/ }))?.text).toBe('Renvoi')
  await ui.unmount()
})

test('la carte montre le test, le flow Maestro et ses captures', async ($, on) => {
  const shot = '/r/qa/ios/2026-10-29_230258/Code juste/takeScreenshot/01_code_juste_done.png'
  const evidence = [
    { id: 'app/login/test/login.feature#1', test: 'passed', qa: [{ platform: 'ios', run: '2026-10-29_230258', status: 'SUCCESS', shots: [{ path: shot, label: 'done' }] }] },
    { id: 'app/login/test/login.feature#2', test: 'failed', qa: [] },
  ]
  seed(on, { snapshot: SNAP, scenarios: FILES, evidence, thumbs: [{ path: shot, data: 'AAAA', width: 165, height: 360 }] })

  const desk = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await desk.find({ type: 'Text', text: /test vert/ }))?.text).toBe('✓ test vert')
  expect((await desk.find({ type: 'Text', text: /Maestro/ }))?.text).toBe('✓ Maestro ios · 1 capture')
  expect((await desk.find({ type: 'Svg' }))?.props.source).toContain('data:image/jpeg;base64,AAAA')
  expect((await desk.find({ type: 'Button', key: `open-${shot}` }))?.props.label).toBe('done')
  await desk.unmount()

  const term = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await term.find({ type: 'Image' }))?.props.source).toEqual({ file: shot, format: 'png' })
  await term.unmount()
})

test('le bouton Fichier brut montre le .feature entier', async ($, on) => {
  seed(on, { snapshot: SNAP, scenarios: FILES, showSource: true })
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Code' }))?.props.source).toBe(GHERKIN)
  expect((await ui.find({ type: 'Button', key: 'scenario-source' }))?.props.label).toBe('Carte')
  await ui.unmount()
})

test('les rapports de tests et de Maestro se lisent par scénario', () => {
  const jsonl = [
    '{"test":{"id":1,"name":"Login Code juste"},"type":"testStart"}',
    '{"testID":1,"result":"success","hidden":false,"type":"testDone"}',
    `{"test":{"id":2,"name":"Login Outline: Code faux ('a')"},"type":"testStart"}`,
    '{"testID":2,"result":"failure","hidden":false,"type":"testDone"}',
    `{"test":{"id":3,"name":"Login Outline: Code faux ('b')"},"type":"testStart"}`,
    '{"testID":3,"result":"success","hidden":false,"type":"testDone"}',
  ].join('\n')
  const results = parseTestReport(jsonl)
  expect(testStateOf(results, 'Login', 'Code juste')).toBe('passed')
  expect(testStateOf(results, 'Login', 'Code faux')).toBe('failed')
  expect(testStateOf(results, 'Login', 'Autre')).toBe('')
  const xml = '<testsuite><testcase name="Code &quot;juste&quot;" status="SUCCESS"/><testcase name="Faux" status="ERROR"/></testsuite>'
  expect([...parseMaestroReport(xml)]).toEqual([['Code "juste"', 'SUCCESS'], ['Faux', 'ERROR']])
  expect(latestRun(['_runs', '2026-10-29_223213', '2026-10-29_230258', 'report.xml'])).toBe('2026-10-29_230258')
  expect(shotLabel('03_undoes_cleared.png', commonPrefix(['03_undoes.png', '03_undoes_cleared.png']))).toBe('cleared')
  expect(shotLabel('03_undoes.png', '03_undoes')).toBe('début')
})

test('le panneau Pipeline attend le premier .feature', async ($, on) => {
  seed(on, {
    snapshot: { shape: 'snapshot-1', value: { kind: 'feature', name: 'svg_layer', pkg: 'app/editor', phase: '', maxAttempts: 5, stages: [], decisions: 0 } },
  })

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })

  expect((await ui.find({ type: 'Text', text: /Pas encore de \.feature/ }))?.text).toBe('Pas encore de .feature ajouté ou modifié dans app/editor.')
  await ui.unmount()
})

const PLAN_MD = `# Plan — paywall

## Les chantiers

### Phase 1 — Trial

1. **Écran de fin de trial.** [moi]
   - Quand : une fois.
   → \`feature/trial_end_screen\`

2. **Plafonner la pub.** [toi]
   - À décider.

3. **Primer qui nomme la recette** : codé et mergé. [fait]
`

const WT = '/repo/.claude/worktrees/feature-trial_end_screen'
const STRAY = '/repo/.claude/worktrees/trial-end-screen-6c4fb4'
const TRANSCRIPT = '/home/.claude/projects/-repo--claude-worktrees-feature-trial-end-screen/s1.jsonl'
const WROTE = `${TRANSCRIPT}:"name":"Edit","input":{"file_path":"${WT}/lib/a.dart"`

const NOW = 1_800_000_000_000
const ACTIVITY = JSON.stringify({ session: 's2', cwd: WT, title: 'Trial', state: 'waiting', at: NOW - 60_000, percent: 72, waitingOn: 'Bash' })

const planEngine = (on: Parameters<Parameters<typeof test>[1]>[1], writes: string[] = []) => {
  on('command.register', () => ({ value: { command: 'pipeline' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('clock.every', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('clock.now', () => ({ value: NOW }))
  on('env.get', () => ({ value: '/home' }))
  on('session.id', () => ({ value: 's1' }))
  on('session.usage', () => ({ value: { startedAt: 0, context: { window: 200000, tokens: 80000, percent: 40 }, rateLimits: [] } }))
  on('fs.write', (_, e) => {
    writes.push(e.path)
    return { value: undefined }
  })
  on('process.run', (_, e) => {
    const argv = e.argv.join(' ')
    const out = argv.includes("find \"$HOME/.claude/projects\"")
      ? `120 ${TRANSCRIPT}`
      : argv.startsWith('grep -oHE')
        ? WROTE
        : argv.includes('status --porcelain=v1 -z')
          ? e.init?.cwd === WT ? ' M lib/a.dart\0?? lib/b.dart\0' : ''
          : argv.includes('merge-base develop feature/trial_end_screen')
            ? 'mb1'
            : argv.includes('diff --name-status -z mb1 feature/trial_end_screen')
              ? 'M\0lib/a.dart\0A\0lib/c.dart\0'
              : argv.includes('--git-common-dir')
      ? '/repo/.git'
      : argv.includes('--show-toplevel')
        ? ROOT
        : argv.includes('branch --show-current')
          ? 'main'
          : argv.includes('worktree list')
            ? `worktree /repo\nbranch refs/heads/main\n\nworktree ${WT}\nbranch refs/heads/feature/trial_end_screen\n\nworktree ${STRAY}\nbranch refs/heads/claude/trial-end-screen-6c4fb4\n`
            : argv.includes('--verify')
              ? 'abc123'
              : argv.includes('@{upstream}')
                ? ''
                : argv.includes('develop..feature/trial_end_screen')
                  ? '3'
                  : argv.includes('rev-list')
                    ? '0'
                    : argv.includes('status --porcelain') && e.init?.cwd === WT
                      ? ' M lib/a.dart\n?? lib/b.dart'
                      : ''

    return { value: { exitCode: 0, stdout: out, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('fs.list', (_, e) =>
    e.path === '/repo/.claude/plans'
      ? { value: [{ name: 'paywall.md', kind: 'file', size: 1, mtimeMs: 1, isLink: false }] }
      : e.path === '/home/.claude/activity'
        ? { value: [{ name: 's2.json', kind: 'file', size: 1, mtimeMs: 1, isLink: false }] }
        : { deny: 'ENOENT' },
  )
  on('fs.read', (_, e) =>
    e.path === '/repo/.claude/plans/paywall.md'
      ? { value: PLAN_MD }
      : e.path === '/home/.claude/activity/s2.json'
        ? { value: ACTIVITY }
      : e.path === `${WT}/.claude/features/trial_end_screen/pipeline.json`
        ? { value: JSON.stringify({ stages: { green: { status: 'RED', at: '2026-11-03T10:00:00Z' } }, attempts: { green: 2 } }) }
        : { deny: 'ENOENT' },
  )
}

test('le panneau montre le plan du repo, ses branches et les worktrees hors plan', async ($, on) => {
  const writes: string[] = []
  planEngine(on, writes)
  await $.session.start({ cwd: ROOT, surface: 'desktop', isInteractive: true })
  expect(writes).toContain('/home/.claude/activity/s1.json')

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /faits/ }))?.text).toBe('Plan — paywall : 1/3 faits · 1 en cours · 1 décision à toi')
  expect((await ui.find({ type: 'Text', text: /1\. Écran/ }))?.text).toBe('▸ 1. Écran de fin de trial · moi')
  expect((await ui.find({ type: 'Text', text: /feature\/trial_end_screen ·/ }))?.text).toBe(
    '    feature/trial_end_screen · feature-trial_end_screen · ✗ impl (vert) 2/5 · 3 commits · jamais poussée · 2 fichiers non commités · 2 non attribués',
  )
  expect((await ui.find({ type: 'Text', text: /Trial ·/ }))?.text).toBe('      ! Trial · attend ta réponse (Bash) · contexte 72 %')
  await ui.press({ key: 'files-feature/trial_end_screen' })
  expect((await ui.find({ type: 'Text', text: /Non suivis/ }))?.text).toBe('      Non suivis (1)')
  expect((await ui.find({ type: 'Text', text: /lib\/b\.dart/ }))?.text).toBe('        ? lib/b.dart  ?')
  expect((await ui.find({ type: 'Text', text: /M lib\/a\.dart/ }))?.text).toBe('        M lib/a.dart')
  expect((await ui.find({ type: 'Text', text: /Commités sur la branche/ }))?.text).toBe('      Commités sur la branche (2)')
  expect((await ui.find({ type: 'Text', text: /A lib\/c\.dart/ }))?.text).toBe('        A lib/c.dart  ?')
  expect((await ui.find({ type: 'Text', text: /2\. Plafonner/ }))?.text).toBe('! 2. Plafonner la pub · toi · décision à toi')
  expect((await ui.find({ type: 'Text', text: /claude\/trial-end-screen/ }))?.text).toBe(
    '    claude/trial-end-screen-6c4fb4 · trial-end-screen-6c4fb4 · aucun commit',
  )
  await ui.unmount()

  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await band.find({ type: 'Text', text: /faits/ }))?.text).toBe(
    'Plan — paywall : 1/3 faits · 1 en cours · 1 décision à toi · 1 session attend ta réponse',
  )
  await band.unmount()
})

test('attribution : transcripts, status -z et diff -z', async () => {
  expect(parseWrites('x"name":"Write","input":{"file_path":"/w/a \\"b\\".md"y"name":"Read","input":{"file_path":"/w/r"')).toEqual(['/w/a "b".md'])
  expect(sessionOfTranscript('/p/proj/s1.jsonl')).toBe('s1')
  expect(sessionOfTranscript('/p/proj/s1/subagents/agent-9.jsonl')).toBe('s1')
  expect(parsePorcelain('MM a\0R  new\0old\0UU c\0?? d\0')).toEqual([
    { path: 'a', status: 'M', area: 'staged' },
    { path: 'a', status: 'M', area: 'unstaged' },
    { path: 'new', status: 'R', area: 'staged' },
    { path: 'c', status: 'U', area: 'conflict' },
    { path: 'd', status: '?', area: 'untracked' },
  ])
  expect(parseNameStatus('M\0a\0R087\0old\0new\0D\0z\0')).toEqual([
    { path: 'a', status: 'M', area: 'committed' },
    { path: 'new', status: 'R', area: 'committed' },
    { path: 'z', status: 'D', area: 'committed' },
  ])
  const writes = new Map([
    ['/w/a', new Set(['s1'])],
    ['/w/b', new Set(['s2'])],
    ['/other/a', new Set(['s3'])],
  ])
  const owned = attribute('/w', [{ path: 'a', status: 'M', area: 'unstaged' }, { path: 'c', status: '?', area: 'untracked' }], writes)
  expect(owned.writers).toBe(2)
  expect(owned.files.map(f => f.isAttributed)).toEqual([true, false])
})

test('activité : lue, filtrée par worktree, dite en une ligne', async () => {
  const a = parseActivity(ACTIVITY)
  expect(a?.state).toBe('waiting')
  expect(parseActivity('{"session":"x","at":1,"state":"bof"}')).toBe(null)
  const idle = { ...(a as NonNullable<typeof a>), session: 's3', cwd: '/ailleurs', state: 'idle' as const, at: NOW - 2 * 3600_000, percent: -1, title: '' }
  const old = { ...idle, session: 's4', at: NOW - 13 * 3600_000 }
  expect(activityOf([idle, old, a as NonNullable<typeof a>], WT, ['s3', 's4'], NOW).map(x => x.session)).toEqual(['s2', 's3'])
  expect(describeActivity(idle, NOW)).toBe('· s3 · au repos depuis 2 h')
  expect(describeActivity({ ...idle, state: 'working', at: NOW - 40 * 60_000 }, NOW)).toBe('▸ s3 · au travail, sans nouvelles depuis 40 min')
})

test('la reprise d’un /feature qu’une autre session fait tourner est arrêtée une fois', async ($, on) => {
  planEngine(on)
  on('prompt.submit', (_, e) => ({ text: e.text }))
  await $.session.start({ cwd: ROOT, surface: 'desktop', isInteractive: true })
  const line = { text: '/feature trial_end_screen', command: { name: 'feature', args: 'trial_end_screen' } }
  const first = await $.prompt.submit(line)
  expect(String((first as { drop?: string }).drop)).toContain('Une autre session travaille déjà dans .claude/worktrees/feature-trial_end_screen : Trial · attend ta réponse (Bash)')
  const again = await $.prompt.submit(line)
  expect((again as { drop?: string }).drop).toBe(undefined)
  const other = await $.prompt.submit({ text: '/feature autre', command: { name: 'feature', args: 'autre' } })
  expect((other as { drop?: string }).drop).toBe(undefined)
  expect(pipelineTarget('fix', 'help')).toBe(null)
  expect(pipelineTarget('fix', 'crash_upload --from-mr 12')).toEqual({ kind: 'fix', name: 'crash_upload' })
})

// ---------------------------------------------------------------------------
// Encart « à lire » : les documents de l'étape courante
// ---------------------------------------------------------------------------

const SPEC_DIR = `${ROOT}/.claude/features/two_factor_login`
const WAITING = JSON.stringify({ ...JSON.parse(PIPELINE), cockpit: { waiting: 'Valide la spec' } })
const NEXT = JSON.stringify({ key: 'spec', step: '1', title: 'Spec, critique, point d’étape « spec »' })

const readingEngine = (on: Parameters<Parameters<typeof test>[1]>[1], files: Record<string, string>) => {
  on('command.register', () => ({ value: { command: 'pipeline' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('clock.every', () => ({ value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('process.run', (_, e) => {
    const argv = e.argv.join(' ')
    const out = argv.includes('pipeline.sh')
      ? NEXT
      : argv.includes('rev-parse')
        ? ROOT
        : argv.includes('branch')
          ? 'feature/two_factor_login'
          : ''

    return { value: { exitCode: 0, stdout: out, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('fs.read', (_, e) => (e.path in files ? { value: files[e.path] } : { deny: 'ENOENT' }))
}

test('l’encart montre la spec et sa critique quand la spec attend Thibault', async ($, on) => {
  readingEngine(on, {
    [`${SPEC_DIR}/pipeline.json`]: WAITING,
    [`${SPEC_DIR}/spec.md`]: '# Spec\n\nLe code arrive par SMS.',
    [`${SPEC_DIR}/spec_review.md`]: '# Critique\n\nLe délai d’expiration manque.',
  })
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /^À toi/ }))?.text).toBe('À toi : Valide la spec')
  expect((await ui.find({ type: 'Button', key: `doc-.claude/features/two_factor_login/spec.md` }))?.props.label).toBe('spec')
  expect(await ui.find({ type: 'Button', key: `doc-.claude/features/two_factor_login/spec_review.md` })).toBeDefined()
  expect((await ui.find({ type: 'Markdown' }))?.text).toBe('# Spec\n\nLe code arrive par SMS.')
  await ui.press({ type: 'Button', key: `doc-.claude/features/two_factor_login/spec_review.md` })
  expect((await ui.find({ type: 'Markdown' }))?.text).toBe('# Critique\n\nLe délai d’expiration manque.')
  await ui.unmount()
})

test('à lire : documents par étape, étape d’un fix, plan de correction', () => {
  expect(sourcesFor('feature', 'hg.suggestions').map(([, label]) => label)).toEqual(['revue'])
  expect(sourcesFor('feature', 'hg.contracts')[0]?.[0]).toBe('@contracts')
  expect(sourcesFor('feature', 'inconnue')).toEqual([['spec.md', 'spec']])
  const fix = (o: object) => JSON.stringify(o)
  expect(fixNextStep(fix({ stages: {} }), false).key).toBe('red')
  expect(fixNextStep(fix({ stages: { red: { status: 'PASSED' } } }), false).key).toBe('hg.repro')
  const reviewed = { stages: { red: { status: 'PASSED' }, green: 'PASSED', review: { status: 'PASSED' } }, human_gates: { repro: { at: 'x' } } }
  expect(fixNextStep(fix(reviewed), false).key).toBe('evidence')
  expect(fixNextStep(fix(reviewed), true).key).toBe('hg.ui')
  expect(fixNextStep('pas du json', false).key).toBe('')
  const plan = fixPlanMarkdown(fix({ fix_plan: { layer: 'data', approach: 'remonter l’erreur', files: ['lib/a.dart'], rejected: 'try/catch dans la vue' } }))
  expect(plan).toBe('**Couche** : data\n\n**Approche** : remonter l’erreur\n\n**Fichiers**\n\n- `lib/a.dart`\n\n**Alternative écartée** : try/catch dans la vue')
  expect(waitingOf(WAITING)).toBe('Valide la spec')
  expect(contractFiles(fix({ contracts: { files: ['a.dart', 3] } }))).toEqual(['a.dart'])
  const long = toDoc('spec', 'x/spec.md', 'a'.repeat(MAX_DOC + 10))
  expect([long.format, long.text.length, long.cut]).toEqual(['markdown', MAX_DOC, MAX_DOC + 10])
  expect(toDoc('a.dart', 'lib/a.dart', 'x').language).toBe('dart')
})
