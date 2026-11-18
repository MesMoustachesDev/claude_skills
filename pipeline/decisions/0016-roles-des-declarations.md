# 0016 — Chaque déclaration réutilisable porte un rôle d'un vocabulaire fermé, et l'index des rôles est lu avant d'écrire

Statut : acceptée (2026-11-17), amendée le 2026-11-17 (vocabulaire sous `.claude/rules/`, variantes statiques), puis le 2026-11-18 (marqueurs en anglais)
Où elle vit : `scripts/gauntlet/dart_tools/bin/dup_check.dart` (`--roles`, `--roles-index`, `--roles-check`,
candidats par rôle) · `stacks/flutter/checks_maintain.sh` (`roles_index`, `roles`) ·
`scripts/gauntlet/profiles.sh` (`roles` dans `MAINTAIN_FIXABLE`, donc au gate `clean`) ·
`hooks/pipeline-restrict-writes.sh` (Nina écrit le vocabulaire) · `pipeline/feature/steps/0b_cadrage.md`,
`1c_contracts_draft.md`, `5_clean.md` · `agents/feature-specifier.md`, `feature-architect.md`,
`feature-cleaner.md` · `stacks/flutter/templates/feature_pipeline.md` (`roles.file`) ·
`pipeline/feature/init.md` (5d) et `stacks/flutter/roles_init.py` (`/feature init roles`)

## Contexte

`dup_check` rapproche les déclarations par le nom (tokens pondérés IDF) et par le corps (clones de
type 2). Ce qui lui échappe, ce sont les doublons de responsabilité aux noms différents :
`HomeEmptyContent` refait `DesignEmptyState`. Denis les rattrape en lisant tout le catalogue du design
system, après coup, quand le code est déjà posé.

Deux études de 2026 mesurent le problème chez les agents : ils produisent environ 1,9 fois plus de
doublons sémantiques que les humains (arXiv 2601.21276), et ils explorent de moins en moins le dépôt
au fil des tours, avec de la logique dupliquée dans 51 % des chaînes au 5ᵉ tour alors que les tests
passent toujours (RepoReuse, arXiv 2609.35357). Un agent ne cherche pas ce qu'il ne sait pas exister :
il faut le mettre dans son contexte avant qu'il écrive, pas seulement le détecter après.

## Décision

- **Vocabulaire fermé, par projet** : `.claude/rules/roles.md` (`roles.file`), une ligne
  « - `<mot>` : description » par rôle. Le nom du rôle dit ce que la déclaration rend ou calcule
  (`empty-state`, `price-format`), pas où elle vit. Les mots sont en anglais, comme le reste du code.
- **Le marqueur** : une ligne `role: <word>` dans la doc (`/// role: empty-state`). C'est un commentaire,
  pas une annotation Dart : rien à importer, lisible par grep, et la même syntaxe sert à d'autres langages.
- **Avant d'écrire** : `gauntlet.sh roles_index` produit en 0b `roles_index.md`, les déclarations du
  workspace par rôle et celles des packages partagés qui n'en ont pas encore. Sophie (exploration, §8)
  et Arthur (brouillon de contrats) le lisent avant de poser quoi que ce soit.
- **Pendant la dédup** : une déclaration qui porte un rôle a pour candidates toutes celles du même
  rôle, quel que soit leur nom (`match: "rôle"` dans `dedup_candidates.json`).
- **En fin de feature** : le check `roles` du gate `clean` exige un rôle du vocabulaire sur chaque
  déclaration réutilisable du périmètre (widget public de la présentation ou du design system,
  fonction, membre d'extension, statique). Nina les pose ; un mot nouveau, elle l'ajoute au vocabulaire,
  et l'orchestrateur le montre à Thibault : le script vérifie, Thibault garde le vocabulaire fermé.
- **Mise en route par projet** : `/feature init roles`. Le modèle lit le code et propose un vocabulaire
  et un rôle par déclaration, en JSON ; `roles_init.py` le décode strictement (mots bornés, chaque
  déclaration attribuée une et une seule fois, aucune inconnue), le montre à blanc, et n'écrit qu'après
  le oui de Thibault. Le modèle traduit, le script décide.
- **Opt-in** : sans `.claude/rules/roles.md`, `roles` est non applicable et l'index ne liste que les
  déclarations sans rôle des packages partagés.

## Conséquences

- L'index grandit à chaque feature, sans passe dédiée : la feature N+1 voit ce que la feature N a posé.
- Un projet qui adopte les rôles marque d'abord son design system et ses packages partagés
  (`/feature init roles`) : sans ça, l'index est vide et seule la feature en cours est contrainte.
- Une ligne de doc de plus par déclaration réutilisable ; un aller-retour avec Thibault quand le
  vocabulaire grandit.

## Hors champ

- Android (`kotlin_dedup.py`) : pas encore ; `roles` y est non applicable faute de check.
- Les classes non-widget (services, repositories) et les types de l'architecture (`_archSuffix`) : leur
  rôle est leur suffixe.
- `/fix` et `/reviewPR` : le profil `pr` ne porte pas `roles` ; une PR hors pipeline n'est pas tenue
  de marquer.

## Amendement du 2026-11-17 : premier passage sur un vrai projet

- **Le vocabulaire vit dans `.claude/rules/roles.md`**, pas `.claude/roles.md` : les projets ignorent
  `.claude/*` sauf quelques dossiers, dont `rules/`, versionné partout comme `feature_pipeline.md`. Il est
  donc aussi chargé dans chaque session du projet, ce qui ne coûte qu'une quarantaine de lignes.
- **Un statique d'un widget n'a pas de rôle propre** (`VerticalSpacer.xs`, `DesignFilledButton.small`) :
  c'est une variante du widget, qui porte le rôle. 32 lignes de bruit sur 186 au premier passage.
- **`roles_init.py` respecte le code autour** : sans doc, le rôle se pose au-dessus des `// ignore:` qui
  précèdent la déclaration (sinon l'ignore ne s'applique plus), avec une ligne vide quand la déclaration
  précédente est collée (ce que `dart format` exigerait). Vérifié par `analyze` et `dart format`
  identiques avant et après.

## Amendement du 2026-11-18 : marqueurs en anglais

Le premier vocabulaire posé dans un projet était en français (`/// rôle: accès-contexte`), au milieu d'une
doc de code écrite en anglais. Le marqueur devient `/// role: <word>` et les mots sont en anglais :
`roles_init.py` refuse un mot qui n'est pas en minuscules ASCII avec tirets, et Nina ajoute ses mots en
anglais. `dup_check.dart` lit encore `rôle:` pour les projets pas encore migrés. Seules les descriptions
du vocabulaire, lues par les agents, restent en français.
