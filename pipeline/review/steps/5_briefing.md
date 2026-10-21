### 5. Fusion, briefing, cockpit

**1. Fusion.** `review.sh findings <slug>` : il fusionne les trois fichiers en `findings.json` (F1, F2…,
critiques en tête, doublons retirés) et signale les remarques incomplètes. Pour chaque remarque
critique, vérifie toi-même sa preuve en une commande (`git grep`, le fichier à la ligne) ; une preuve
qui ne tient pas se signale à Thibault au tri (« F4 : je n'ai pas retrouvé … »), elle ne se supprime pas.

**2. Le briefing**, dans `<dossier de la revue>/briefing.md` : un écran, **aucun verdict, aucune
remarque** — du contexte. Il comprend :

1. **Pourquoi cette MR** — titre, auteur, ticket, le besoin en une ou deux phrases (`context.md`).
   Description vide : écrit noir sur blanc.
2. **Résumé technique** — 3 à 5 lignes : ce que le code fait, et **ce qui existait déjà sur la cible
   vs ce que la MR ajoute réellement**.
3. **L'arbre du changement** — `python3 ~/.claude/scripts/change_tree.py <merge-base> -C <worktree>`
   le mesure : fichiers groupés par package et couche, volume, fichiers générés, et part de reformatage
   (« ⚠ 4 changements réels, le reste = reformat »). Tu ajoutes le **rôle** de chaque fichier en une ligne (ce que le changement y fait), à la place de `<rôle>` ; ne recalcule ni les volumes ni le reformatage, le script les a mesurés. Dans l'ordre de lecture de
   l'impact s'il existe :

   ```
   data/       not_reachable_device_data_source.dart   +33/-2    query GraphQL `esls`
   presentation/
               device_details_page.dart                +91/-115  ⚠ 1 ligne ESL, le reste = reformat
   ```

4. **Le flux** — un diagramme Mermaid (bloc ` ```mermaid `) du chemin que parcourt la donnée ou
   l'utilisateur à travers ce que la MR touche : où la valeur naît, où elle est consommée. Deux chemins
   qui alimentent le même écran depuis deux sources : côte à côte.
5. **Ce qui a été vérifié** — le verdict brut du gauntlet (`[OK]` / `[WARN]` / `[FAIL]`) et surtout ce
   qui n'a pas tourné ; l'impact graphify s'il a tourné ; la QA de Maëlle, scénario par scénario, avec
   **comment** il a été prouvé (device, test existant rejoué, test jetable) et pourquoi le device n'a
   pas servi s'il n'a pas servi ; un agent en échec.
6. **Impact** — seulement si calculé : les consommateurs hors package non touchés, une ligne chacun
   (`package · symbole · via · fichier:ligne`), sans verdict.
7. **Les remarques** — le compte par gravité et par agent (« 2 critiques (Corentin 1, Alice 1),
   4 suggestions, 1 question »), et la grille de maintenabilité d'Alice et Corentin en une ligne par
   item `ko`.

Puis `review.sh pass <slug> briefing`.

**3. Le cockpit.** `review.sh say <slug> "Trie les <n> remarques : commenter ou écarter, et retouche
le texte si besoin"`, puis « Rafraîchir » (`~/.claude/pipeline/review/cockpit.md`). Dans la session :
le lien du cockpit (`#<clé>`), les 7 points du briefing résumés en 8 lignes maximum, et l'annonce du
tri.
