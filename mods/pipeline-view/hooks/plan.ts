import type { PlanBranch, PlanItem, PlanPhase, PlanView } from '../types'

// Un plan du repo : `.claude/plans/<nom>.md` du checkout principal (points numérotés sous des titres
// `##` / `###`), ou le `split` d'un epic (pipeline.json `size: L`). Un point est relié à son travail par
// une ligne `→ <branche>` : la session qui prend le point l'écrit dans le plan.

const TAGS = /\[(moi|toi|fait)\]/g
const ARROW = /→\s*((?:`[^`]+`|[\w./-]+)(?:\s*(?:,|et)\s*(?:`[^`]+`|[\w./-]+))*)/g
const ITEM = /^(\d+)\.\s+(.*)$/
const HEADING = /^#{2,3}\s+(.+?)\s*$/

/** Les branches citées après une flèche, dans l'ordre, sans doublon. */
export const branchesOf = (text: string): string[] => {
  const found: string[] = []
  for (const match of text.matchAll(ARROW)) {
    for (const part of (match[1] ?? '').split(/\s*(?:,|\bet\b)\s*/)) {
      const name = part.replace(/`/g, '').trim()
      if (name && !found.includes(name)) found.push(name)
    }
  }

  return found
}

/** Titre d'un point : le texte en gras de sa première ligne, sinon la ligne sans ses étiquettes. */
const titleOf = (line: string): string => {
  const bold = /\*\*(.+?)\*\*/.exec(line)
  const raw = (bold ? bold[1] ?? '' : line.replace(TAGS, '')).replace(/[.:]\s*$/, '').trim()

  return raw.length > 90 ? `${raw.slice(0, 89)}…` : raw
}

/** Les phases et les points numérotés d'un plan Markdown ; un point sans phase va dans « Plan ». */
export const parsePlanMarkdown = (text: string): { title: string; phases: PlanPhase[] } => {
  const lines = text.split('\n')
  const title = (lines.find(l => /^#\s+/.test(l)) ?? '').replace(/^#\s+/, '').trim()
  const phases: PlanPhase[] = []
  let phase: PlanPhase | undefined
  let item: { id: string; first: string; body: string[] } | undefined
  const close = () => {
    if (!item) return
    const tags = [...item.first.matchAll(TAGS)].map(m => m[1] ?? '')
    const owner = tags.filter(t => t !== 'fait').join(' et ')
    const next: PlanItem = {
      id: item.id,
      title: titleOf(item.first),
      owner,
      done: tags.includes('fait'),
      note: '',
      branches: branchesOf([item.first, ...item.body].join('\n')).map(branch => emptyBranch(branch)),
    }
    if (!phase) {
      phase = { title: 'Plan', items: [] }
      phases.push(phase)
    }
    phase.items.push(next)
    item = undefined
  }
  for (const line of lines) {
    const heading = HEADING.exec(line)
    if (heading) {
      close()
      phase = { title: heading[1] ?? '', items: [] }
      phases.push(phase)
      continue
    }
    const start = ITEM.exec(line)
    if (start) {
      close()
      item = { id: start[1] ?? '', first: start[2] ?? '', body: [] }
      continue
    }
    if (item && (line.startsWith(' ') || line.trim() === '')) item.body.push(line)
    else close()
  }
  close()

  return { title, phases: phases.filter(p => p.items.length > 0) }
}

const CLOSED = new Set(['mergé', 'abandonné'])

type Split = {
  name?: unknown
  status?: unknown
  branch?: unknown
  base?: unknown
  depends_on?: unknown
  mr?: { ref?: unknown } | null
}

/** Le découpage d'un epic, ou null si ce pipeline.json n'en est pas un. Les bases vont avec chaque branche. */
export const parseEpic = (
  name: string,
  text: string,
): { title: string; phases: PlanPhase[]; bases: Record<string, string> } | null => {
  let raw: { size?: unknown; split?: unknown }
  try {
    raw = JSON.parse(text) as typeof raw
  } catch {
    return null
  }
  if (raw.size !== 'L' || !Array.isArray(raw.split) || raw.split.length === 0) return null
  const bases: Record<string, string> = {}
  const items = (raw.split as Split[]).map((sub, i): PlanItem => {
    const sub_name = typeof sub.name === 'string' ? sub.name : `#${i + 1}`
    const branch = typeof sub.branch === 'string' && sub.branch ? sub.branch : `feature/${sub_name}`
    bases[branch] = typeof sub.base === 'string' && sub.base ? sub.base : `feature/${name}`
    const status = typeof sub.status === 'string' ? sub.status : ''
    const deps = Array.isArray(sub.depends_on) ? sub.depends_on.filter(d => typeof d === 'string') : []
    const mr = typeof sub.mr?.ref === 'string' ? sub.mr.ref : ''

    return {
      id: String(i + 1),
      title: sub_name,
      owner: '',
      done: CLOSED.has(status),
      note: [status, mr, deps.length > 0 ? `après ${deps.join(', ')}` : ''].filter(Boolean).join(' · '),
      branches: [emptyBranch(branch)],
    }
  })

  return { title: `epic ${name}`, phases: [{ title: 'Sous-features', items }], bases }
}

export const emptyBranch = (branch: string): PlanBranch => ({
  branch,
  worktree: '',
  exists: false,
  ahead: 0,
  unpushed: -1,
  dirty: 0,
  stage: '',
  stageStatus: '',
  files: [],
  writers: 0,
})

/** `git worktree list --porcelain` → branche → chemin du worktree. */
export const parseWorktrees = (porcelain: string): Map<string, string> => {
  const byBranch = new Map<string, string>()
  let path = ''
  for (const line of porcelain.split('\n')) {
    if (line.startsWith('worktree ')) path = line.slice('worktree '.length)
    else if (line.startsWith('branch refs/heads/')) byBranch.set(line.slice('branch refs/heads/'.length), path)
  }

  return byBranch
}

/** Branches d'outillage, jamais du travail d'un plan (worktrees du pont de l'app). */
export const isToolingBranch = (branch: string): boolean => branch.startsWith('worktree-bridge-')

/** L'état d'un point, en un mot, pour la marque de la ligne. */
export const itemState = (item: PlanItem): 'done' | 'active' | 'todo' | 'yours' => {
  if (item.done) return 'done'
  if (item.branches.some(b => b.exists)) return 'active'
  if (item.owner === 'toi') return 'yours'

  return 'todo'
}

/** Ce qu'on sait d'une branche, en une ligne. */
export const describeBranch = (b: PlanBranch): string => {
  if (!b.exists) return `${b.branch} · branche introuvable (supprimée après merge ?)`
  const parts = [b.branch]
  parts.push(b.worktree ? b.worktree.split('/').at(-1) ?? b.worktree : 'sans worktree')
  if (b.stage) parts.push(b.stage)
  if (b.ahead === 0) parts.push(b.worktree ? 'aucun commit' : 'intégrée à la base')
  else parts.push(`${b.ahead} commit${b.ahead > 1 ? 's' : ''}`)
  if (b.unpushed === -1 && b.ahead > 0) parts.push('jamais poussée')
  else if (b.unpushed > 0) parts.push(`${b.unpushed} non poussé${b.unpushed > 1 ? 's' : ''}`)
  if (b.dirty > 0) parts.push(`${b.dirty} fichier${b.dirty > 1 ? 's' : ''} non commité${b.dirty > 1 ? 's' : ''}`)
  // Un fichier compte une fois, même indexé et modifié encore (MM).
  const unattributed = new Set(b.files.filter(f => !f.isAttributed).map(f => f.path)).size
  if (unattributed > 0) parts.push(`${unattributed} non attribué${unattributed > 1 ? 's' : ''}`)
  if (b.writers > 1) parts.push(`écrite par ${b.writers} sessions`)

  return parts.join(' · ')
}

/** Résumé d'un plan pour la bande : « plan X : 3/18 faits · 4 en cours · 2 décisions à toi ». */
export const summarize = (plan: PlanView): string => {
  const items = plan.phases.flatMap(p => p.items)
  const count = (state: ReturnType<typeof itemState>) => items.filter(i => itemState(i) === state).length
  const parts = [`${plan.title} : ${count('done')}/${items.length} faits`]
  if (count('active') > 0) parts.push(`${count('active')} en cours`)
  if (count('yours') > 0) parts.push(`${count('yours')} décision${count('yours') > 1 ? 's' : ''} à toi`)

  return parts.join(' · ')
}

/** Un plan est ouvert tant qu'un de ses points n'est pas fait. */
export const isOpen = (plan: PlanView): boolean => plan.phases.some(p => p.items.some(i => !i.done))
