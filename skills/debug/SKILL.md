---
description: Systematic debugging protocol. Use when investigating bugs, unexpected behavior, or failed features. Forces log-first approach instead of guessing.
disable-model-invocation: true
---

# Debug

Follow this strict protocol. Do NOT skip steps.

## 1. UNDERSTAND
- Read the relevant code paths end-to-end (UI → BLoC/notifier → usecase → repository → data source)
- Identify the exact expected vs actual behavior

## 2. DIAGNOSE
- Add targeted log statements at every relevant point in the data flow
- Log input values, intermediate transformations, and output values
- Run the app/tests and share the ACTUAL output

## 3. HYPOTHESIZE
- Based on real log output (not guesses), state:
  - What value is wrong
  - Where exactly it diverges from expected
  - Why it diverges
- If uncertain, add MORE logs. Never guess.

## 4. PROPOSE
- Describe the minimal fix in plain English
- Do NOT write code yet
- Wait for user approval

## 5. IMPLEMENT
- Apply the minimal fix — change as little as possible
- Run the app/tests again to verify the fix works
- Share the verification output

## 6. CLEAN UP
- Remove diagnostic logs (unless user wants to keep them)
- Run the analyzer/linter to confirm no regressions
