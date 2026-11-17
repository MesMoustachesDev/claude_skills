import type { PipelineSnapshot, Recap } from '../types'
import { mark, stageOwner } from './model'

// L'encart « Reprendre le fil » : en revenant sur une feature après une autre, Thibault y relit en un coup d'œil
// le but, l'étape, ce qui a bougé et ce qui a été tranché. Les lignes de jugement viennent de `pipeline.sh recap`
// (bornées, validées) ou, à défaut, de discussion.md ; les lignes factuelles sont calculées ici.

const LINE = 80
const LISTS = { decided: 5, open: 3, aside: 3 } as const
const MAX_SINCE = 3

const isLine = (v: unknown): v is string => typeof v === 'string' && v.trim() !== '' && !/[\r\n]/.test(v) && v.length <= LINE

/** pipeline.json → recap, revalidé : une donnée hors bornes ne s'affiche pas. */
export const parseRecap = (text: string): Recap | null => {
  let raw: Record<string, unknown> | undefined
  try {
    raw = (JSON.parse(text) as { recap?: Record<string, unknown> }).recap
  } catch {
    return null
  }
  if (!raw || typeof raw !== 'object' || !isLine(raw.goal)) return null
  const list = (key: keyof typeof LISTS): string[] | null => {
    const v = raw?.[key] ?? []

    return Array.isArray(v) && v.length <= LISTS[key] && v.every(isLine) ? v : null
  }
  const [decided, open, aside] = [list('decided'), list('open'), list('aside')]
  if (!decided || !open || !aside) return null

  return { goal: raw.goal, decided, open, aside, stage: typeof raw.stage === 'string' ? raw.stage : '', source: 'recap' }
}

const cut = (s: string): string => (s.length > LINE ? `${s.slice(0, LINE - 1)}…` : s)

/** Les puces `- …` d'une section `## <titre>` (leurs lignes de suite ignorées). */
const bullets = (md: string, title: string): string[] => {
  const out: string[] = []
  let isIn = false
  for (const line of md.split('\n')) {
    if (line.startsWith('## ')) isIn = line.slice(3).trim() === title
    else if (isIn && line.startsWith('- ')) out.push(line.slice(2).trim())
  }

  return out.filter(Boolean)
}

/** Sans résumé écrit : les premières décisions et les questions non résolues de discussion.md. */
export const discussionFallback = (md: string): Recap => ({
  goal: '',
  decided: bullets(md, 'Décisions').slice(0, LISTS.decided).map(cut),
  open: bullets(md, 'Questions ouvertes')
    .filter(q => !q.startsWith('RÉSOLU'))
    .slice(0, LISTS.open)
    .map(cut),
  aside: [],
  stage: '',
  source: 'discussion',
})

/** Les étapes écrites après le dernier passage (toutes sans passage connu), les plus récentes d'abord. */
export const sinceLines = (snap: PipelineSnapshot, seenAt: number | null): string[] =>
  snap.stages
    .map(s => ({ s, at: Date.parse(s.at) }))
    .filter(({ at }) => !Number.isNaN(at) && (seenAt === null || at > seenAt))
    .sort((a, b) => b.at - a.at)
    .slice(0, MAX_SINCE)
    .map(({ s }) => {
      const owner = stageOwner(snap.kind, s.key)

      return `${s.label} ${mark(s.status)}${owner ? ` (${owner})` : ''}`
    })

/** « 7/15 » : étapes passées sur étapes non sautées. */
export const progress = (snap: PipelineSnapshot): string => {
  const counted = snap.stages.filter(s => s.status !== 'SKIPPED')

  return `${counted.filter(s => s.status === 'PASSED').length}/${counted.length}`
}

/** « il y a 5 min », « il y a 3 h », « il y a 2 j ». */
export const ago = (ms: number): string => {
  const min = Math.max(0, Math.round(ms / 60_000))
  if (min < 60) return `il y a ${min} min`
  const h = Math.round(min / 60)

  return h < 24 ? `il y a ${h} h` : `il y a ${Math.round(h / 24)} j`
}
