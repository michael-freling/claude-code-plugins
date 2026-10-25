---
name: define-verification
description: Write or update .claude/verification.yaml, the step-by-step workflow that proves a change in this repo actually works (build/test/lint and any deploy/runtime check). Use when that file doesn't exist yet, when the require-verification hook blocks completion or PR creation because no recipe is defined, or when the user wants to change how changes get verified here.
allowed-tools: [Read, Write, Bash, AskUserQuestion]
---

# Define Verification

`.claude/verification.yaml` is this repo's one-time declaration of what
"this change works" means. The `require-verification` hook
(`.claude/settings.json`) blocks completion and `gh pr create` until that
recipe has been run against the current commit and passed — so getting this
file right matters more than getting it fast.

Format reference: `.claude/VERIFICATION.md`. Read it before writing or
editing the file — it has the exact field names, the three step types
(`run`/`poll`/`cleanup`) and their semantics, and the YAML subset the runner
actually parses.

## If `.claude/verification.yaml` already exists

1. Read it and show it to the user as-is.
2. Ask what they want to change — add a step, adjust a timeout, fix a
   command — rather than starting over.
3. Edit it, following the format in `.claude/VERIFICATION.md`.
4. Show the updated file and offer to run
   `.claude/scripts/run-verification.sh` to confirm it still works.

Do not re-ask the open-ended question below when a file already exists.

## If it doesn't exist yet

Ask with `AskUserQuestion`. The real answer is almost always a free-text
paragraph describing several steps, not a pick from a short list, so:

- Phrase the question to explicitly invite a multi-step, free-text answer,
  e.g.: "Describe, in your own words, everything that has to happen for you
  to trust that a change to this repo actually works — build, tests, lint,
  type-checking, AND any deploy or runtime verification (watching CI checks
  go green, deploying somewhere and smoke-testing it, etc.). It's fine, and
  expected, to list multiple steps, including anything that must always be
  cleaned up afterward regardless of pass or fail."
- Offer a few short options as a starting point (e.g. "Build + unit tests
  only", "Build + tests + wait for CI", "Build + tests + deploy + smoke
  test"), but make clear picking one is just a starting point — the user's
  own typed description is what actually gets used, and multi-step answers
  are the expected case, not an edge case. Don't let the options read as the
  only acceptable answers.
- If the free-text answer is thin (e.g. only mentions one step, or skips
  build/test/lint entirely), ask a short follow-up rather than filling in
  the gaps yourself — don't invent steps the user didn't describe.

## Translating the answer into YAML

Map what the user described onto the three step types honestly — don't
collapse everything into `run` steps just because it's simpler:

- A single pass/fail command (build, unit tests, lint, typecheck, a
  one-shot integration test) → a `run` step.
- Anything phrased as "wait for", "poll until", "keep checking until it's
  green/ready/healthy/synced" → a `poll` step. If the user didn't give an
  interval or timeout, ask, or propose a default (e.g. `interval_seconds:
  30`, `timeout_seconds: 1800`) and say in your reply that you picked it —
  don't silently guess and move on.
- Anything phrased as "always undo", "revert it afterward", "clean up no
  matter what", "regardless of pass or fail" → a `cleanup` step.
- Use the user's own commands verbatim wherever they gave one. Ask a
  clarifying follow-up for a step they described but didn't give a concrete
  command for — don't invent a command on their behalf.
- Give each step a short, specific `name` (used to identify it in failure
  output) — not "step 1".

Write the file with a short comment header pointing at
`.claude/VERIFICATION.md` for the full format, then the steps.

## After writing

Show the user the generated `.claude/verification.yaml` in full and ask them
to confirm it actually matches what they described before relying on it.
Mention they can run `.claude/scripts/run-verification.sh` now to try it, and
that re-running this skill at any time edits the file in place rather than
starting over.
