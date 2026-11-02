export type PipelineStage = {
  key: string
  label: string
  status: 'PASSED' | 'RED' | 'FAILED' | 'SKIPPED' | 'PENDING' | string
  attempts: number
  /** Horodatage ISO écrit par le hook de gate, vide si l'étape n'a pas tourné. */
  at: string
}

export type PipelineSnapshot = {
  kind: 'feature' | 'fix'
  name: string
  /** Package de la feature ou du fix, relatif à la racine du repo. */
  pkg: string
  /** fix.json → phase (repro, impl, arbitrate…), vide pour une feature. */
  phase: string
  maxAttempts: number
  stages: PipelineStage[]
  /** Marqueurs `DÉCISION (Thibault)` encore présents dans le package. */
  decisions: number
}

export type ActiveAgent = {
  id: string
  type: string
  persona: string
  /** Début de l'agent, en ms depuis l'époque. */
  start: number
  /** Fin de l'agent, 0 tant qu'il tourne. */
  end: number
  /** Appels d'outils terminés. */
  calls: number
  /** Appels refusés (hooks restrict-writes, permissions). */
  denied: number
  /** L'outil en cours, vide entre deux appels. */
  current: string
  /** Les derniers fichiers modifiés (Edit, Write), du plus ancien au plus récent. */
  files: string[]
}

export type ScenarioFile = {
  /** Chemin depuis la racine du repo. */
  path: string
  /** `ajouté` ou `modifié` depuis la base du pipeline. */
  status: string
  /** Le fichier Gherkin entier. */
  source: string
  /** Nombre de Scenario / Scénario / Plan du scénario. */
  count: number
}

declare module 'claude-code' {
  interface PluginState {
    'pipeline-view': {
      snapshot: Shaped<PipelineSnapshot | null>
      agents: Shaped<ActiveAgent[]>
      isAsking: boolean
      /** Horloge de l'affichage, avancée par le rafraîchissement pendant qu'un agent tourne. */
      now: number
      /** Les .feature du package ajoutés ou modifiés depuis la base, pour le panneau Scénarios. */
      scenarios: ScenarioFile[]
      selectedScenario: string
    }
  }
}
