import type { ScenarioFile } from '../types'

// Un .feature découpé pour l'afficher scénario par scénario : le contexte (Background) commun, puis
// chaque scénario avec ses étiquettes, ses étapes et ses tableaux. Les paramètres bdd_widget_test
// `{'texte'}` / `{3}` sont isolés pour être mis en valeur.

export type StepKind = 'given' | 'when' | 'then'

export type Step = {
  keyword: string
  kind: StepKind
  /** `And` / `Et` / `But` / `Mais` / `*` : même famille que l'étape d'avant. */
  isContinuation: boolean
  /** Texte en morceaux : les paramètres `{…}` à part, sans accolades ni guillemets. */
  parts: { text: string; isParam: boolean }[]
  /** Lignes de tableau ou de docstring qui suivent l'étape, telles quelles. */
  extra: string[]
}

export type Scenario = {
  /** `<chemin>#<n>`, stable tant que le fichier garde ses scénarios dans le même ordre. */
  id: string
  path: string
  status: string
  file: string
  feature: string
  title: string
  isOutline: boolean
  tags: string[]
  background: Step[]
  steps: Step[]
  /** Tableau(x) Examples d'un plan de scénario, lignes telles quelles. */
  examples: string[]
}

const KEYWORDS: [RegExp, StepKind | 'and'][] = [
  [/^(Given|Étant donné que|Étant donné qu'|Étant donnée?s?|Soit|Sachant que|Sachant qu')(?:\s+|(?<=')\s*)/, 'given'],
  [/^(When|Quand|Lorsque|Lorsqu')(?:\s+|(?<=')\s*)/, 'when'],
  [/^(Then|Alors|Donc)(?:\s+|$)/, 'then'],
  [/^(And|But|Et que|Et qu'|Et|Mais que|Mais qu'|Mais|\*)(?:\s+|(?<=')\s*)/, 'and'],
]
const FEATURE = /^(Feature|Fonctionnalité)\s*:\s*(.*)$/
const BACKGROUND = /^(Background|Contexte)\s*:/
const SCENARIO = /^(Scenario Outline|Scenario Template|Plan du scénario|Scenario|Example|Scénario|Exemple)\s*:\s*(.*)$/
const EXAMPLES = /^(Examples|Scenarios|Exemples)\s*:/

/** Le texte d'une étape en morceaux, les paramètres `{'a'}` / `{3}` à part. */
export const splitParams = (text: string): Step['parts'] => {
  const parts: Step['parts'] = []
  let last = 0
  for (const match of text.matchAll(/\{([^{}]*)\}/g)) {
    if (match.index > last) parts.push({ text: text.slice(last, match.index), isParam: false })
    parts.push({ text: (match[1] ?? '').trim().replace(/^'(.*)'$/, '$1'), isParam: true })
    last = match.index + match[0].length
  }
  if (last < text.length) parts.push({ text: text.slice(last), isParam: false })

  return parts
}

const stepOf = (line: string, previous: StepKind): Step | null => {
  for (const [pattern, kind] of KEYWORDS) {
    const match = pattern.exec(line)
    if (!match) continue

    return {
      keyword: (match[1] ?? '').trim(),
      kind: kind === 'and' ? previous : kind,
      isContinuation: kind === 'and',
      parts: splitParams(line.slice(match[0].length)),
      extra: [],
    }
  }

  return null
}

/** Les scénarios d'un fichier, dans l'ordre. */
export const parseScenarios = (file: ScenarioFile): Scenario[] => {
  const name = file.path.split('/').at(-1) ?? file.path
  let feature = ''
  let background: Step[] = []
  const found: Scenario[] = []
  let current: Scenario | undefined
  let target: Step[] | undefined
  let tags: string[] = []
  let inExamples = false
  let inDocstring = false
  let previous: StepKind = 'given'
  for (const raw of file.source.split('\n')) {
    const line = raw.trim()
    if (inDocstring || line.startsWith('"""') || line.startsWith('```')) {
      target?.at(-1)?.extra.push(raw.replace(/^\s{0,6}/, ''))
      if (line.startsWith('"""') || line.startsWith('```')) inDocstring = !inDocstring
      continue
    }
    if (line === '' || line.startsWith('#')) continue
    if (line.startsWith('@')) {
      tags.push(...line.split(/\s+/).filter(t => t.startsWith('@')))
      continue
    }
    const featureMatch = FEATURE.exec(line)
    if (featureMatch) {
      feature = (featureMatch[2] ?? '').trim()
      tags = []
      continue
    }
    if (BACKGROUND.test(line)) {
      background = []
      target = background
      current = undefined
      inExamples = false
      previous = 'given'
      continue
    }
    const scenarioMatch = SCENARIO.exec(line)
    if (scenarioMatch) {
      const keyword = scenarioMatch[1] ?? ''
      current = {
        id: `${file.path}#${found.length + 1}`,
        path: file.path,
        status: file.status,
        file: name,
        feature,
        title: (scenarioMatch[2] ?? '').trim(),
        isOutline: /Outline|Template|Plan du/.test(keyword),
        tags,
        background,
        steps: [],
        examples: [],
      }
      found.push(current)
      target = current.steps
      tags = []
      inExamples = false
      previous = 'given'
      continue
    }
    if (EXAMPLES.test(line)) {
      inExamples = true
      continue
    }
    if (inExamples && current) {
      if (line.startsWith('|')) current.examples.push(line)
      continue
    }
    if (line.startsWith('|')) {
      target?.at(-1)?.extra.push(line)
      continue
    }
    const step = stepOf(line, previous)
    if (step && target) {
      target.push(step)
      previous = step.kind
    }
  }

  return found
}
