---
description: Pre-flight checklist and deployment execution. Use when deploying to any environment (Appwrite, Netlify, Firebase, CI/CD).
disable-model-invocation: true
---

# Deploy

Execute this mandatory pre-flight checklist before ANY deployment command:

## 1. SNAPSHOT
- Run `git status` and `git log --oneline -3`
- Identify the current deployed version/state
- Write down the exact rollback command (git revert, function redeploy, etc.)

## 2. DEPENDENCY CHECK
- Check runtime version requirements (package.json engines, SDK constraints)
- Verify all dependencies are compatible with the target runtime
- Flag any native modules or SDK version mismatches

## 3. ENV VALIDATION
- List every environment variable the code references
- Verify each one exists in the target environment (.env files, console config, CI secrets)
- Flag any missing or placeholder values

## 4. TARGET VERIFICATION
- Double-check the deployment target ID/URL against project config files
- Confirm you are deploying to the CORRECT environment (staging vs production)
- Use the project's existing deploy tooling (Makefile, Fastlane, scripts) — not ad-hoc commands

## 5. DRY RUN (if possible)
- Build locally or run in test mode
- Capture and share output

## 6. DEPLOY
Present the full pre-flight results and WAIT for user GO before executing.

## 7. VERIFY
- Check logs or hit the deployed endpoint to confirm it's working
- If broken, execute rollback immediately and report

---

## Platform-specific commands

### Appwrite CLI (v12+)
- `appwrite deploy` is removed → use `appwrite push function`
- Deploy one function: `echo "YES" | appwrite push function --function-id <id>`
- No `--yes` flag — must pipe `echo "YES"` for non-interactive
- NEVER use `appwrite functions delete` — it wipes all deployment history, env vars, and config.
- Runtime mismatch warning is just a confirmation prompt, not a blocker. `echo "YES"` accepts the change. That's it.
