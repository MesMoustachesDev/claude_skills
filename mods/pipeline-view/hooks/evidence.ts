// Ce qui prouve un scénario : son test (bdd_widget_test, dans le rapport JSON de `flutter test` que le
// gauntlet garde dans .gauntlet/test_report.jsonl) et son flow Maestro (qa/<plateforme>/<run>/, un
// dossier de captures par scénario, nommé par son titre, et report.xml).

export type TestState = 'passed' | 'failed' | 'skipped'

/** `flutter test --reporter json` → nom complet du test → résultat. Un test rejoué garde son dernier. */
export const parseTestReport = (jsonl: string): Map<string, TestState> => {
  const names = new Map<number, string>()
  const results = new Map<string, TestState>()
  for (const line of jsonl.split('\n')) {
    if (!line.startsWith('{')) continue
    let event: { type?: string; test?: { id?: number; name?: string }; testID?: number; result?: string; skipped?: boolean; hidden?: boolean }
    try {
      event = JSON.parse(line) as typeof event
    } catch {
      continue
    }
    if (event.type === 'testStart' && typeof event.test?.id === 'number') names.set(event.test.id, event.test.name ?? '')
    if (event.type !== 'testDone' || event.hidden || typeof event.testID !== 'number') continue
    const name = names.get(event.testID)
    if (!name) continue
    results.set(name, event.skipped ? 'skipped' : event.result === 'success' ? 'passed' : 'failed')
  }

  return results
}

/**
 * L'état du test d'un scénario : bdd_widget_test le nomme « <Feature> <Scénario> » (un plan de
 * scénario, une fois par exemple, suivi de ses valeurs). Un exemple rouge rend le scénario rouge.
 */
export const testStateOf = (results: Map<string, TestState>, feature: string, title: string): TestState | '' => {
  // bdd_widget_test préfixe un plan de scénario d'« Outline: » et suffixe chaque exemple de ses valeurs.
  const names = [title, `Outline: ${title}`].map(t => (feature ? `${feature} ${t}` : t))
  const states = [...results]
    .filter(([name]) => names.some(exact => name === exact || name.startsWith(`${exact} `)))
    .map(([, s]) => s)
  if (states.length === 0) return ''
  if (states.includes('failed')) return 'failed'

  return states.every(s => s === 'skipped') ? 'skipped' : 'passed'
}

/** report.xml de Maestro (JUnit) → nom du flow → SUCCESS / ERROR / … */
export const parseMaestroReport = (xml: string): Map<string, string> => {
  const found = new Map<string, string>()
  for (const match of xml.matchAll(/<testcase\b([^>]*)>/g)) {
    const attrs = match[1] ?? ''
    const name = /\bname="([^"]*)"/.exec(attrs)?.[1]
    if (!name) continue
    const status = /\bstatus="([^"]*)"/.exec(attrs)?.[1] ?? (/<failure/.test(xml.slice(match.index, match.index + 2000)) ? 'ERROR' : 'SUCCESS')
    found.set(unescapeXml(name), status)
  }

  return found
}

const unescapeXml = (text: string): string =>
  text.replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')

/** Le dernier run d'une plateforme : le plus récent des dossiers datés (`2026-10-29_230258`). */
export const latestRun = (names: string[]): string =>
  names.filter(n => /^\d{4}-\d{2}-\d{2}_\d{6}$/.test(n)).sort().at(-1) ?? ''

/** Un nom lisible pour une capture : `03_undoes_…_cleared.png` → `cleared`, la première → `début`. */
export const shotLabel = (file: string, flowPrefix: string): string => {
  const base = file.replace(/\.png$/i, '')
  const rest = flowPrefix && base.startsWith(flowPrefix) ? base.slice(flowPrefix.length).replace(/^_+/, '') : base

  return rest === '' ? 'début' : rest.replace(/_/g, ' ')
}

/** Le préfixe commun de captures d'un même flow (`03_undoes__redoes_…`), vide s'il n'y en a pas. */
export const commonPrefix = (files: string[]): string => {
  const bases = files.map(f => f.replace(/\.png$/i, ''))
  if (bases.length === 0) return ''
  const shortest = bases.reduce((a, b) => (a.length <= b.length ? a : b))

  return bases.every(b => b.startsWith(shortest)) ? shortest : ''
}
