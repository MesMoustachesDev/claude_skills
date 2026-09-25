---
description: Analyze uncommitted changes and create small, atomic, compilable commits grouped by logical unit. Use when there are multiple unrelated changes to commit.
---

# Create Commits

Split uncommitted changes into small, atomic, reviewable commits. Each commit must compile independently and be easy to revert.

## 1. ANALYZE

Gather the full picture of uncommitted work:

```bash
git status
git diff --stat
git diff
git diff --cached --stat
git diff --cached
```

Also check for untracked files that belong to a change:
```bash
git ls-files --others --exclude-standard
```

Read every modified/added file to understand the full context of changes.

## 2. CLASSIFY

For each changed file (or hunk within a file), determine:
- **What it does**: bug fix, feature, refactor, config change, dependency update, localization, test, etc.
- **What it belongs to**: which feature/module/component is affected
- **Dependencies**: does this change require another change to compile?

Group changes into **logical units** — a logical unit is the smallest set of changes that:
1. Makes sense together (single purpose)
2. Compiles on its own (no broken intermediate state)
3. Can be reverted without breaking other commits in the batch

### Grouping rules

- **Cross-layer changes** (e.g., model + repository + bloc + UI for the same feature) → same commit
- **Barrel file exports** → same commit as the code they export
- **Generated files** (`.g.dart`, `.freezed.dart`, lockfiles) → same commit as their source
- **Localization keys** (ARB files) → same commit as the UI that uses them
- **pubspec.yaml dependency adds** → same commit as the code using that dependency
- **Pure refactors** (renames, moves, extract method) → separate commit, never mixed with behavior changes
- **Formatting-only changes** → separate commit or skip if trivial
- **Multiple independent bug fixes** → one commit per fix
- **Config/CI changes** → separate commit unless tightly coupled to a code change

### Compile-safety checks

Before finalizing groups, verify:
- No commit removes an import/export that another file in a *later* commit still needs
- No commit adds code that references a symbol introduced in a *later* commit
- If unsure about ordering, read the imports of each file in the group

## 3. ORDER

Sort commits in dependency order:
1. Infrastructure/config changes first (pubspec, build config, CI)
2. Core/shared code (models, utilities, extensions)
3. Data layer (repositories, data sources, mappers)
4. Domain layer (use cases, entities)
5. Presentation layer (blocs, UI)
6. Tests last (they depend on everything else)

Within the same layer, independent changes can go in any order.

## 4. PLAN

Present the commit plan to the user as a numbered list:

```
Commit plan (N commits):

1. fix: prevent null crash in report download
   - features/download_report/lib/src/data/...
   - features/download_report/lib/src/domain/...

2. feat: add surface area validation
   - features/surface_areas/lib/src/...
   - features/l10n/lib/src/arb/intl_*.arb

3. chore: bump dio to 5.4.0
   - pubspec.yaml
   - pubspec.lock
```

For each commit, indicate:
- The proposed commit message (conventional commit format: `type: description`)
- The files included
- If partial staging (hunk-level) is needed, mention it

**Wait for user approval before proceeding.** The user may reorder, merge, split, or rename commits.

## 5. EXECUTE

For each commit in order:

### Stage precisely
- Use `git add <file>` for whole-file changes
- Use `git add -p <file>` for partial file staging (when a file contains changes belonging to different commits). In that case, use a temporary approach:
  1. Save the current file content
  2. Edit the file to contain only the changes for this commit
  3. `git add <file>`
  4. Restore the full file content
  This avoids interactive `git add -p` which doesn't work in non-interactive mode.

### Verify before committing
```bash
# Check that only the intended files are staged
git diff --cached --stat

# Quick compile check if the project supports it
# For Flutter: fvm flutter analyze (only if fast enough, skip for large projects)
```

### Commit
Use conventional commit format. Message rules:
- Lowercase after the type prefix
- No period at the end
- Imperative mood ("add", "fix", "remove", not "added", "fixes", "removed")
- Under 72 characters for the subject line
- Add body only if the "why" isn't obvious from the subject
- Do NOT add "Co-Authored-By" or "Generated with Claude Code" lines

```bash
git commit -m "$(cat <<'EOF'
type: subject line

Optional body explaining why, not what.
EOF
)"
```

### Verify after committing
```bash
git log --oneline -1
git status
```

## 6. SUMMARY

After all commits are created, show:
```bash
git log --oneline -N  # where N = number of commits created
```

And confirm remaining working tree status:
```bash
git status
```

## Edge cases

- **Single logical change**: If all changes belong together, create one commit. Don't split artificially.
- **Merge conflicts with self**: If partial staging would cause issues, keep the changes in one commit and explain why.
- **Huge diff in one file**: If a single file has multiple unrelated changes (e.g., a fix + a feature), prefer committing them together with a broader message rather than risking a broken intermediate state.
- **Uncommitted changes + staged changes**: Handle both. Respect anything already staged — ask if the user wants to keep that staging or re-sort everything.
- **Stashed changes**: Ignore stash unless user asks.
- **Untracked files**: Include in analysis. They often belong to a new feature commit.
- **Generated files out of sync**: If `.g.dart` files are modified but their source isn't (or vice versa), flag this to the user — it may indicate a missing build_runner step.
