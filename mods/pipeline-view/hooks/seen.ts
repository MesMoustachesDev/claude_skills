// Le dernier passage de Thibault sur une feature, pour la ligne « Depuis » de l'encart « Reprendre le fil ».
// Lié à la feature, pas à la session : une feature reprise dans une autre session, après un /clear ou un
// redémarrage de l'app, garde son passage. Un fichier par repo et par feature, hors du repo.
//
// Compte : un message de Thibault (tapé, ou depuis son téléphone), sa réponse à une question, une permission
// qu'il donne. Ne compte pas : les réveils planifiés (watchdog), les messages d'autres sessions, les
// notifications de fin d'agent, les prompts d'un mod. Dans l'app desktop, un message tapé arrive en `human`
// (relevé dans les transcripts), un sous-agent ou une autre session en `peer`, un réveil en `task-notification` ;
// `sdk` n'est pas la preuve que Thibault a écrit.

const BY_THIBAULT = new Set(['composer', 'bridge', 'human'])

export const isThibaultPrompt = (e: { origin?: { kind: string }; isMeta?: true }): boolean =>
  e.isMeta !== true && e.origin !== undefined && BY_THIBAULT.has(e.origin.kind)

export const seenFile = (activityDir: string, mainRepo: string, feature: string): string =>
  `${activityDir}/seen/${mainRepo.replace(/[^A-Za-z0-9]/g, '_')}__${feature}.json`

/** `{"at": <ms>}` ; tout autre contenu vaut « aucun passage ». */
export const parseSeen = (text: string): number | null => {
  try {
    const at = (JSON.parse(text) as { at?: unknown }).at

    return typeof at === 'number' && Number.isFinite(at) ? at : null
  } catch {
    return null
  }
}
