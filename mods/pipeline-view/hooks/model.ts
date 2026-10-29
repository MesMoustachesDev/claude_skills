import type { ActiveAgent, PipelineSnapshot, PipelineStage } from '../types'

// Ordre d'affichage, tiré des tableaux d'étapes de ~/.claude/commands/feature.md et fix.md.
// Une clé inconnue de pipeline.json s'affiche après, dans l'ordre du fichier.
const FEATURE_ORDER: [string, string][] = [
  ['contracts', 'contrats'],
  ['dedup', 'dedup contrats'],
  ['spec', 'spec'],
  ['spec_review', 'critique spec'],
  ['red', 'tests (rouge)'],
  ['tests_review', 'revue tests'],
  ['green', 'impl (vert)'],
  ['clean', 'clean'],
  ['dedup_clean', 'dedup clean'],
  ['review', 'review'],
  ['harden', 'mutation'],
  ['qa', 'QA'],
  ['polish', 'polish'],
  ['evidence', 'evidence'],
]

const FIX_ORDER: [string, string][] = [
  ['red', 'repro (rouge)'],
  ['repro_report', 'arbitrage'],
  ['green', 'fix (vert)'],
  ['review', 'review'],
  ['review_report', 'rapport review'],
  ['evidence', 'evidence'],
]

export const PERSONAS: Record<string, string> = {
  'feature-architect': 'Arthur',
  'feature-specifier': 'Sophie',
  'feature-spec-critic': 'Camille',
  'feature-test-writer': 'Théo',
  'feature-test-reviewer': 'Gaëlle',
  'feature-implementer': 'Ivan',
  'feature-cleaner': 'Nina',
  'feature-dedup': 'Denis',
  'feature-reviewer': 'Romain',
  'feature-hardener': 'Hugo',
  'feature-qa': 'Quentin',
  'feature-polisher': 'Pauline',
  'fix-reproducer': 'Bastien',
  'fix-implementer': 'Fanny',
  'fix-reviewer': 'Victor',
  'review-architect': 'Alice',
  'review-code': 'Corentin',
  'review-qa': 'Maëlle',
}

export const isPipelineAgent = (type: string): boolean => type in PERSONAS

type Raw = {
  package?: unknown
  phase?: unknown
  max_attempts?: unknown
  stages?: Record<string, { status?: unknown; at?: unknown }>
  attempts?: Record<string, unknown>
}

/** Construit la vue d'un pipeline.json ou fix.json. Rend null si le JSON est illisible. */
export const parseState = (
  kind: 'feature' | 'fix',
  name: string,
  text: string,
  defaultMax: number,
): PipelineSnapshot | null => {
  let raw: Raw
  try {
    raw = JSON.parse(text) as Raw
  } catch {
    return null
  }
  const stages = raw.stages ?? {}
  const attempts = raw.attempts ?? {}
  const order = kind === 'feature' ? FEATURE_ORDER : FIX_ORDER
  const known = new Set(order.map(([key]) => key))
  const keys = [
    ...order.filter(([key]) => key in stages || key in attempts),
    ...Object.keys(stages)
      .filter(key => !known.has(key))
      .map(key => [key, key] as [string, string]),
  ]
  const list: PipelineStage[] = keys.map(([key, label]) => ({
    key,
    label,
    status: String(stages[key]?.status ?? 'PENDING'),
    attempts: Number(attempts[key] ?? 0) || 0,
    at: typeof stages[key]?.at === 'string' ? (stages[key]?.at as string) : '',
  }))

  return {
    kind,
    name,
    pkg: typeof raw.package === 'string' ? raw.package : '',
    phase: typeof raw.phase === 'string' ? raw.phase : '',
    maxAttempts: Number(raw.max_attempts ?? defaultMax) || defaultMax,
    stages: list,
    decisions: 0,
  }
}

/** Nom du fix ou de la feature d'après la branche (fix/<nom>, feature/<nom>). */
export const fromBranch = (
  branch: string,
): { kind: 'feature' | 'fix'; name: string } | null => {
  const match = /^(feature|fix)\/(.+)$/.exec(branch.trim())

  return match ? { kind: match[1] as 'feature' | 'fix', name: match[2] ?? '' } : null
}

/** pipeline.max_attempts du bloc ini de .claude/rules/feature_pipeline.md. */
export const maxAttemptsFromConfig = (text: string): number => {
  const match = /^\s*pipeline\.max_attempts\s*=\s*(\d+)/m.exec(text)

  return match ? Number(match[1]) : 5
}

const MARK: Record<string, string> = {
  PASSED: '✓',
  SKIPPED: '–',
  RED: '✗',
  FAILED: '✗',
  PENDING: '·',
}

export const mark = (status: string): string => MARK[status] ?? '?'

/** L'étape en cours : celle que les hooks ont écrite en dernier (`at` le plus récent). */
export const focusStage = (snap: PipelineSnapshot): PipelineStage | undefined =>
  snap.stages
    .filter(s => s.at !== '')
    .reduce<PipelineStage | undefined>(
      (best, s) => (best === undefined || Date.parse(s.at) > Date.parse(best.at) ? s : best),
      undefined,
    )

export const sameSnapshot = (
  a: PipelineSnapshot | null,
  b: PipelineSnapshot | null,
): boolean => JSON.stringify(a) === JSON.stringify(b)

// ---------------------------------------------------------------------------
// Activité des agents (repris de l'idée de mission-control, vue « Who »)
// ---------------------------------------------------------------------------

const MAX_FILES = 5
const MAX_DONE = 4
const INTERNAL = new Set(['TodoWrite', 'TaskCreate', 'TaskUpdate', 'TaskList', 'TaskGet', 'ToolSearch'])

/** Le chemin vu depuis la racine du repo, ou ses deux derniers segments s'il est ailleurs. */
export const shortPath = (file: string, root: string): string => {
  if (root && file.startsWith(`${root}/`)) return file.slice(root.length + 1)
  const parts = file.split('/')

  return parts.length > 3 ? `…/${parts.slice(-2).join('/')}` : file
}

/** Une étiquette lisible pour un appel d'outil : `Edit lib/a.dart`, `Bash fvm flutter test…`. */
export const toolLabel = (tool: string, args: Record<string, unknown>, root: string): string => {
  const file = args.file_path ?? args.notebook_path
  if (typeof file === 'string') return `${tool} ${shortPath(file, root)}`
  if (typeof args.command === 'string') {
    const cmd = args.command.replace(/\s+/g, ' ').trim()

    return `${tool} ${cmd.length > 50 ? `${cmd.slice(0, 50)}…` : cmd}`
  }
  if (typeof args.pattern === 'string') return `${tool} ${args.pattern}`

  return tool
}

export const isTracked = (tool: string): boolean => tool !== 'Agent' && !INTERNAL.has(tool)

/** Un appel commence : l'agent affiche cet outil. */
export const callStarted = (agent: ActiveAgent, label: string): ActiveAgent => ({ ...agent, current: label })

/** Un appel se termine : compteurs, refus, fichier modifié. */
export const callEnded = (
  agent: ActiveAgent,
  outcome: { isDenied: boolean; editedFile?: string },
): ActiveAgent => ({
  ...agent,
  current: '',
  calls: agent.calls + 1,
  denied: agent.denied + (outcome.isDenied ? 1 : 0),
  files: outcome.editedFile
    ? [...agent.files.filter(f => f !== outcome.editedFile), outcome.editedFile].slice(-MAX_FILES)
    : agent.files,
})

/** L'agent a fini : on le garde pour le récap, en ne conservant que les derniers terminés. */
export const agentEnded = (list: ActiveAgent[], id: string, at: number): ActiveAgent[] => {
  const ended = list.map(a => (a.id === id && a.end === 0 ? { ...a, end: at, current: '' } : a))
  const running = ended.filter(a => a.end === 0)
  const done = ended.filter(a => a.end !== 0).slice(-MAX_DONE)

  return [...done, ...running]
}

/** 3m07, 45s. */
export const duration = (ms: number): string => {
  const s = Math.max(0, Math.round(ms / 1000))

  return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m${String(s % 60).padStart(2, '0')}`
}
