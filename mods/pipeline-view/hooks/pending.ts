import type { PendingDoc } from '../types'

// L'encart « à lire » : selon l'étape courante, les documents que Thibault lit pour valider (spec,
// contrats, revue…). L'étape d'une feature vient de `pipeline.sh next --json` ; celle d'un fix est
// calculée ici, comme `steps()` de ~/.claude/scripts/fix_cockpit.py.

/** `@contracts` : les fichiers de contrats ; `@fix_plan` : repro.json → fix_plan. Sinon un fichier du dossier. */
type Source = [source: string, label: string]

const FEATURE_DOCS: Record<string, Source[]> = {
  cadrage: [['cadrage.md', 'cadrage'], ['discussion.md', 'discussion'], ['exploration.md', 'exploration']],
  contracts_draft: [['@contracts', 'contrats']],
  dedup: [['dedup.md', 'doublons'], ['@contracts', 'contrats']],
  'hg.contracts': [['@contracts', 'contrats'], ['dedup.md', 'doublons']],
  spec: [['spec.md', 'spec'], ['spec_review.md', 'critique'], ['spec.diff', 'diff spec']],
  contracts: [['spec.md', 'spec']],
  test_plan: [['tests_plan.json', 'liste des tests'], ['spec.md', 'spec']],
  test_plan_review: [['tests_review.md', 'revue de la liste'], ['tests_plan.json', 'liste des tests']],
  red: [['tests_plan.json', 'liste des tests'], ['spec.md', 'spec']],
  'hg.tests': [['tests_review.md', 'revue des tests'], ['tests.md', 'tests'], ['spec.md', 'spec']],
  green: [['spec.md', 'spec'], ['tests.md', 'tests']],
  clean: [['spec.md', 'spec']],
  dedup_clean: [['dedup.md', 'doublons']],
  review: [['review.md', 'revue']],
  'hg.suggestions': [['review.md', 'revue']],
  harden: [['mutants.md', 'mutants'], ['review.md', 'revue']],
  qa: [['qa.md', 'QA']],
  'hg.tour': [['review.md', 'visite guidée'], ['qa.md', 'QA']],
  'hg.polish': [['polish.md', 'polish'], ['qa.md', 'QA']],
  evidence: [['evidence.md', 'evidence'], ['mr.md', 'MR']],
  done: [['evidence.md', 'evidence'], ['mr.md', 'MR']],
}

const FIX_DOCS: Record<string, Source[]> = {
  red: [['diagnosis.md', 'diagnostic']],
  'hg.repro': [['diagnosis.md', 'diagnostic'], ['@fix_plan', 'plan']],
  green: [['@fix_plan', 'plan'], ['diagnosis.md', 'diagnostic']],
  review: [['review.md', 'revue'], ['@fix_plan', 'plan']],
  'hg.ui': [['review.md', 'revue']],
  evidence: [['evidence.md', 'evidence'], ['mr.md', 'MR']],
  done: [['evidence.md', 'evidence'], ['mr.md', 'MR']],
}

/** Les documents à lire pour une étape ; une étape inconnue montre la spec (feature) ou le diagnostic (fix). */
export const sourcesFor = (kind: 'feature' | 'fix', key: string): Source[] =>
  kind === 'feature' ? (FEATURE_DOCS[key] ?? [['spec.md', 'spec']]) : (FIX_DOCS[key] ?? [['diagnosis.md', 'diagnostic']])

type FixRaw = {
  kind?: unknown
  stages?: Record<string, { status?: unknown } | string>
  human_gates?: Record<string, unknown>
}

const FIX_STEPS: [key: string, title: string][] = [
  ['red', 'Reproduction (Bastien)'],
  ['hg.repro', 'Ton arrêt : diagnostic, test rouge, plan'],
  ['green', 'Correction (Fanny)'],
  ['review', 'Revue (Victor)'],
  ['hg.ui', 'Captures avant / après'],
  ['evidence', 'Evidence, commits'],
]

/** La première étape d'un fix ni passée ni sautée. `isUi` : repro.json → kind vaut `ui`. */
export const fixNextStep = (text: string, isUi: boolean): { key: string; title: string } => {
  let raw: FixRaw
  try {
    raw = JSON.parse(text) as FixRaw
  } catch {
    return { key: '', title: '' }
  }
  const ui = isUi || raw.kind === 'ui'
  const passed = (key: string): boolean => {
    if (key.startsWith('hg.')) return Boolean(raw.human_gates?.[key.slice(3)])
    const st = raw.stages?.[key]
    const status = typeof st === 'object' && st !== null ? st.status : st

    return status === 'PASSED' || status === 'SKIPPED'
  }
  const found = FIX_STEPS.filter(([key]) => key !== 'hg.ui' || ui).find(([key]) => !passed(key))

  return found ? { key: found[0], title: found[1] } : { key: 'done', title: 'Fix terminé' }
}

/** cockpit.waiting de pipeline.json ou fix.json : ce que l'orchestrateur attend de Thibault. */
export const waitingOf = (text: string): string => {
  try {
    const waiting = (JSON.parse(text) as { cockpit?: { waiting?: unknown } }).cockpit?.waiting

    return typeof waiting === 'string' ? waiting : ''
  } catch {
    return ''
  }
}

/** pipeline.json → contracts.files, chemins depuis la racine. */
export const contractFiles = (text: string): string[] => {
  try {
    const files = (JSON.parse(text) as { contracts?: { files?: unknown } }).contracts?.files

    return Array.isArray(files) ? files.filter((f): f is string => typeof f === 'string') : []
  } catch {
    return []
  }
}

/** repro.json → fix_plan, en markdown. Vide sans plan. */
export const fixPlanMarkdown = (text: string): string => {
  let plan: Record<string, unknown> | undefined
  try {
    plan = (JSON.parse(text) as { fix_plan?: Record<string, unknown> }).fix_plan
  } catch {
    return ''
  }
  if (!plan || typeof plan !== 'object') return ''
  const str = (v: unknown): string => (typeof v === 'string' ? v : v === undefined || v === null ? '' : JSON.stringify(v))
  const files = Array.isArray(plan.files) ? plan.files.map(f => `- \`${str(f)}\``).join('\n') : str(plan.files)
  const parts = [
    plan.layer !== undefined ? `**Couche** : ${str(plan.layer)}` : '',
    plan.approach !== undefined ? `**Approche** : ${str(plan.approach)}` : '',
    files ? `**Fichiers**\n\n${files}` : '',
    plan.rejected !== undefined ? `**Alternative écartée** : ${str(plan.rejected)}` : '',
  ]

  return parts.filter(Boolean).join('\n\n')
}

const LANG: Record<string, string> = {
  dart: 'dart',
  ts: 'typescript',
  tsx: 'tsx',
  js: 'javascript',
  json: 'json',
  py: 'python',
  kt: 'kotlin',
  swift: 'swift',
  diff: 'diff',
  yaml: 'yaml',
  yml: 'yaml',
}

// Un Markdown dessine 100 000 caractères en tout par dessin : chaque document est borné.
export const MAX_DOC = 40_000

/** Un document de l'encart : markdown rendu pour un .md, code coloré pour le reste. */
export const toDoc = (label: string, path: string, text: string): PendingDoc => {
  const ext = path.slice(path.lastIndexOf('.') + 1).toLowerCase()
  const isCut = text.length > MAX_DOC
  const body = isCut ? text.slice(0, MAX_DOC) : text

  return {
    label,
    path,
    format: ext === 'md' ? 'markdown' : 'code',
    language: LANG[ext] ?? '',
    text: body,
    cut: isCut ? text.length : 0,
  }
}
