### 8. Synthèse finale, puis suppression du worktree

Écris `<dossier de la revue>/synthesis.md` et affiche-la dans la session :

---

## 🔍 Code Review — `<cible>`

### Résumé
_Le briefing (pourquoi, résumé technique, existait déjà vs nouveau, arbre du changement, flux)._

### 📋 Ce qui a été vérifié
_Gauntlet par package (✓/✗ et lignes en cause), checks PR, impact graphify, QA de Maëlle (scénarios,
plateforme, captures) ; et ce qui n'a pas tourné. Chemins des rapports._

### 🚨 Problèmes critiques · ⚠️ Améliorations suggérées · 💬 Questions
_Chaque remarque retenue : agent, fichier et ligne, problème, suggestion, et **publiée / non publiée**._

### Écarté au tri
_Une ligne par remarque écartée, avec la raison de Thibault s'il l'a donnée._

### 🧭 Maintenabilité
_La grille d'Alice et Corentin, point par point : `ok` / `ko` / `na` avec une ligne de justification._

### 📋 Règles projet vérifiées
_Si `pr_rules.md` existe : chaque règle ✅ / ❌ / ➖._

### Verdict
_Une ligne : mergeable / mergeable après corrections (lesquelles) / à reprendre._

---

Puis **`review.sh cleanup <slug>`** : il supprime le worktree de la revue (jamais rien hors du dossier
temporaire) et passe l'étape. Les rapports, remarques, flows et captures restent. `review.sh say
<slug> ""`.

Termine par 3 lignes : verdict, nombre de commentaires publiés, chemin de `synthesis.md`.

**Fin : la page de la revue.** Après `review.sh cleanup` : « Rafraîchir » une dernière fois — la carte
de l'accueil passe dans « Terminées », avec le verdict et le nombre de commentaires publiés. Puis un
seul `AskUserQuestion` : « Supprimer la page de cette revue ? » — « Garder (utile si la MR revient après
correction) » / « Supprimer ». **Supprimer** → `Artifact` `delete` avec l'URL de la page (l'outil lui
demande confirmation ; c'est définitif), puis `review.sh page-deleted <slug>`, puis `review.sh
cockpit-push` et le seul `batch` de `hub_writes` sur l'accueil : la carte reste, marquée « Page
supprimée ». Ne supprime jamais la page sans cette question, ni l'accueil, jamais.
