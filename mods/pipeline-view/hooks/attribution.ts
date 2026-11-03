import type { BranchFile, FileArea } from '../types'

// Qui a écrit quoi dans un worktree. `git status` dit qu'un fichier a changé, jamais qui l'a changé ;
// les transcripts des sessions (~/.claude/projects/**/*.jsonl) nomment les fichiers que leurs outils
// d'édition ont écrits. Un fichier qu'aucun transcript ne nomme est « non attribué » : une commande
// (sed, formateur, build_runner), une autre session ou Thibault a pu l'écrire. Il n'est jamais
// attribué à une session au hasard.

const WRITE = /"name":"(?:Edit|Write|MultiEdit|NotebookEdit)","input":\{"(?:file_path|notebook_path)":"((?:[^"\\]|\\.)*)"/g

/** Les chemins absolus écrits par Edit / Write / MultiEdit / NotebookEdit dans un morceau de transcript. */
export const parseWrites = (chunk: string): string[] => {
  const found: string[] = []
  for (const match of chunk.matchAll(WRITE)) {
    try {
      found.push(JSON.parse(`"${match[1] ?? ''}"`) as string)
    } catch {
      // Un échappement coupé en fin de morceau : la ligne sera relue entière au passage suivant.
    }
  }

  return found
}

/**
 * La session d'un transcript : `<projet>/<session>.jsonl`, ou un sous-agent de cette session,
 * `<projet>/<session>/subagents/agent-<id>.jsonl`, compté pour elle.
 */
export const sessionOfTranscript = (path: string): string => {
  const parts = path.split('/')
  const sub = parts.lastIndexOf('subagents')
  if (sub > 0) return parts[sub - 1] ?? ''

  return (parts.at(-1) ?? '').replace(/\.jsonl$/, '')
}

const CONFLICT = new Set(['DD', 'AU', 'UD', 'UA', 'DU', 'AA', 'UU'])

/** `git status --porcelain=v1 -z` → fichiers, un `MM` dans Indexés et dans Non indexés. */
export const parsePorcelain = (z: string): { path: string; status: string; area: FileArea }[] => {
  const entries = z.split('\0')
  const found: { path: string; status: string; area: FileArea }[] = []
  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i] ?? ''
    if (entry.length < 4) continue
    const xy = entry.slice(0, 2)
    const path = entry.slice(3)
    // Un renommage ou une copie indexés sont suivis de leur chemin d'origine.
    if (xy[0] === 'R' || xy[0] === 'C') i++
    if (xy === '??') found.push({ path, status: '?', area: 'untracked' })
    else if (CONFLICT.has(xy)) found.push({ path, status: 'U', area: 'conflict' })
    else {
      if (xy[0] !== ' ') found.push({ path, status: xy[0] ?? '', area: 'staged' })
      if (xy[1] !== ' ') found.push({ path, status: xy[1] ?? '', area: 'unstaged' })
    }
  }

  return found
}

/** `git diff --name-status -z <base> <branche>` → fichiers changés par les commits de la branche. */
export const parseNameStatus = (z: string): { path: string; status: string; area: FileArea }[] => {
  const entries = z.split('\0').filter(Boolean)
  const found: { path: string; status: string; area: FileArea }[] = []
  for (let i = 0; i < entries.length; i++) {
    const status = (entries[i] ?? '').charAt(0)
    if (status === 'R' || status === 'C') {
      found.push({ path: entries[i + 2] ?? '', status, area: 'committed' })
      i += 2
    } else {
      found.push({ path: entries[i + 1] ?? '', status, area: 'committed' })
      i += 1
    }
  }

  return found.filter(f => f.path !== '')
}

/**
 * Chaque fichier du worktree, attribué ou non : il l'est quand un transcript nomme son chemin absolu.
 * `writers` : les sessions qui ont écrit dans ce worktree.
 */
export const attribute = (
  worktree: string,
  files: { path: string; status: string; area: FileArea }[],
  writes: Map<string, Set<string>>,
): { files: BranchFile[]; writers: number; sessions: string[] } => {
  const sessions = new Set<string>()
  const prefix = `${worktree}/`
  for (const [path, by] of writes) {
    if (path.startsWith(prefix)) by.forEach(s => sessions.add(s))
  }

  return {
    files: files.map(f => ({ ...f, isAttributed: (writes.get(`${prefix}${f.path}`)?.size ?? 0) > 0 })),
    writers: sessions.size,
    sessions: [...sessions],
  }
}

export const AREA_LABEL: Record<FileArea, string> = {
  conflict: 'Conflits',
  staged: 'Indexés',
  unstaged: 'Non indexés',
  untracked: 'Non suivis',
  committed: 'Commités sur la branche',
}

export const AREA_ORDER: FileArea[] = ['conflict', 'staged', 'unstaged', 'untracked', 'committed']
