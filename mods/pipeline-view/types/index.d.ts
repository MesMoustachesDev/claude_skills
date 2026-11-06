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

export type QaRun = {
  /** `ios` ou `android`. */
  platform: string
  /** Le dossier daté du dernier run (`2026-10-29_230258`). */
  run: string
  /** Statut Maestro du flow (`SUCCESS`, `ERROR`…), vide si report.xml ne le cite pas. */
  status: string
  /** Les captures du flow, dans l'ordre des noms, chemin absolu et libellé court. */
  shots: { path: string; label: string }[]
}

export type ScenarioEvidence = {
  /** L'id du scénario (`<chemin>#<n>`). */
  id: string
  /** Dernier résultat du test bdd_widget_test, vide s'il n'a pas tourné. */
  test: '' | 'passed' | 'failed' | 'skipped'
  qa: QaRun[]
}

export type Thumb = {
  path: string
  /** JPEG réduit, base64. */
  data: string
  width: number
  height: number
}

export type PlanBranch = {
  branch: string
  /** Chemin du worktree qui porte la branche, vide sans worktree. */
  worktree: string
  /** La branche existe en local. */
  exists: boolean
  /** Commits au-dessus de la base du plan (develop, ou la branche de l'epic). */
  ahead: number
  /** Commits pas encore poussés, -1 sans upstream. */
  unpushed: number
  /** Fichiers modifiés ou non suivis dans le worktree. */
  dirty: number
  /** Étape du pipeline du worktree (« ✗ impl (vert) 2/5 »), vide hors pipeline. */
  stage: string
  stageStatus: string
  /** Fichiers du worktree et des commits de la branche, chacun attribué ou non à une session. */
  files: BranchFile[]
  /** Sessions dont un transcript a écrit dans ce worktree. */
  writers: number
  /** Les sessions de ce worktree et ce qu'elles font, les plus récentes d'abord. */
  activity: SessionActivity[]
}

export type SessionActivity = {
  session: string
  /** Dossier de lancement de la session. */
  cwd: string
  /** Titre de la session dans l'app, vide sans titre. */
  title: string
  state: 'working' | 'waiting' | 'idle'
  /** Dernier changement d'état, ms depuis l'epoch. */
  at: number
  /** Part de la fenêtre de contexte remplie, -1 avant la première réponse. */
  percent: number
  /** L'outil dont la permission ou la question attend Thibault. */
  waitingOn: string
}

export type FileArea = 'conflict' | 'staged' | 'unstaged' | 'untracked' | 'committed'

export type BranchFile = {
  /** Depuis la racine du worktree. */
  path: string
  /** Lettre git : M A D R C T U ?. */
  status: string
  area: FileArea
  /** Un transcript de session nomme ce fichier parmi ceux que ses outils d'édition ont écrits. */
  isAttributed: boolean
}

export type PlanItem = {
  /** Numéro du point dans le plan. */
  id: string
  title: string
  /** `moi`, `toi`, `moi et toi`, ou vide. */
  owner: string
  done: boolean
  /** Pour un epic : statut, MR, dépendances. */
  note: string
  branches: PlanBranch[]
}

export type PlanPhase = { title: string; items: PlanItem[] }

export type PlanView = {
  kind: 'plan' | 'epic'
  title: string
  /** Fichier lu, depuis la racine du checkout principal. */
  source: string
  phases: PlanPhase[]
}

export type PendingDoc = {
  /** Libellé de l'onglet (`spec`, `critique`, `contrats`…). */
  label: string
  /** Chemin depuis la racine du repo. */
  path: string
  format: 'markdown' | 'code'
  /** Langage du bloc de code, vide pour du markdown ou une extension inconnue. */
  language: string
  text: string
  /** Taille d'origine quand le texte a été coupé, 0 sinon. */
  cut: number
  /** Diff unifié du fichier depuis la base du pipeline (contrats), vide sinon. */
  diff: string
  /** Le même diff avec tout le fichier en contexte : le fichier entier, changements marqués. */
  fullDiff: string
}

export type PendingView = {
  /** Clé de l'étape courante (`spec`, `hg.tests`, `review`…), `done` en fin de pipeline. */
  key: string
  /** « 1 — Spec, critique, point d'étape « spec » ». */
  title: string
  /** cockpit.waiting : ce que l'orchestrateur attend de Thibault, vide sinon. */
  waiting: string
  docs: PendingDoc[]
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
      /** Le panneau Scénarios montre le .feature brut au lieu de la carte. */
      showSource: boolean
      /** Test et flow Maestro de chaque scénario. */
      evidence: ScenarioEvidence[]
      /** Miniatures des captures du scénario affiché. */
      thumbs: Thumb[]
      /** Les plans ouverts du repo : .claude/plans/*.md et les epics, avec l'état de chaque branche liée. */
      plans: PlanView[]
      /** Les worktrees du repo qu'aucun point d'aucun plan ne cite. */
      strays: PlanBranch[]
      /** Branches dont le panneau déplie la liste de fichiers. */
      openBranches: string[]
      /** L'encart « à lire » : les documents de l'étape courante (spec, contrats, revue…). */
      pending: PendingView | null
      /** Le chemin du document affiché dans l'encart, vide pour le premier. */
      selectedDoc: string
      /** L'encart montre le fichier entier au lieu de son diff. */
      showFullDoc: boolean
    }
  }
}
