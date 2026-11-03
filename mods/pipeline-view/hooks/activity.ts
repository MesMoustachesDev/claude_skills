import type { SessionActivity } from '../types'

// Ce que fait chaque session, publié par la session elle-même : le mod tourne dans chacune, il écrit
// son état dans ~/.claude/activity/<session>.json à chaque changement (prompt envoyé, permission
// demandée, tour fini) avec la part du contexte remplie. Un fichier, pas un canal : une session finie
// pendant que personne ne lit reste lisible au passage suivant.

/** Au-delà, un état n'est plus montré : la session a pu mourir sans écrire sa fin. */
export const STALE_MS = 12 * 3600_000
/** « Au travail » sans nouvelles depuis aussi longtemps : dit comme tel. */
export const SILENT_MS = 30 * 60_000

export const parseActivity = (text: string): SessionActivity | null => {
  try {
    const raw = JSON.parse(text) as Partial<SessionActivity>
    if (typeof raw.session !== 'string' || typeof raw.at !== 'number') return null
    if (raw.state !== 'working' && raw.state !== 'waiting' && raw.state !== 'idle') return null

    return {
      session: raw.session,
      cwd: typeof raw.cwd === 'string' ? raw.cwd : '',
      title: typeof raw.title === 'string' ? raw.title : '',
      state: raw.state,
      at: raw.at,
      percent: typeof raw.percent === 'number' ? raw.percent : -1,
      waitingOn: typeof raw.waitingOn === 'string' ? raw.waitingOn : '',
    }
  } catch {
    return null
  }
}

/** Les sessions d'un worktree : lancées dedans, ou dont le transcript y a écrit. Les plus récentes d'abord. */
export const activityOf = (
  all: SessionActivity[],
  worktree: string,
  writers: string[],
  at: number,
): SessionActivity[] =>
  all
    .filter(a => at - a.at < STALE_MS)
    .filter(a => a.cwd === worktree || a.cwd.startsWith(`${worktree}/`) || writers.includes(a.session))
    .sort((a, b) => b.at - a.at)

/** Une ligne par session : « ▸ titre · au travail · contexte 72 % ». */
export const describeActivity = (a: SessionActivity, at: number): string => {
  const name = a.title || a.session.slice(0, 8)
  const ago = Math.round((at - a.at) / 60_000)
  const state =
    a.state === 'waiting'
      ? `attend ta réponse${a.waitingOn ? ` (${a.waitingOn})` : ''}`
      : a.state === 'working'
        ? at - a.at > SILENT_MS
          ? `au travail, sans nouvelles depuis ${ago} min`
          : 'au travail'
        : `au repos depuis ${ago < 60 ? `${ago} min` : `${Math.round(ago / 60)} h`}`
  const context = a.percent >= 0 ? ` · contexte ${a.percent} %` : ''

  return `${a.state === 'waiting' ? '!' : a.state === 'working' ? '▸' : '·'} ${name} · ${state}${context}`
}
