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
<slug> ""` puis « Rafraîchir » une dernière fois : le cockpit montre la revue terminée.

Termine par 3 lignes : verdict, nombre de commentaires publiés, chemin de `synthesis.md`.
