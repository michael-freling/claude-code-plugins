#!/bin/bash
# SessionStart hook: ship this plugin's project-level instructions to every
# session, including sessions in repositories that installed the plugin.
#
# Why a hook and not a file: a `CLAUDE.md` at the repo root is not distributed
# to installers, and a `CLAUDE.md` at the plugin root is explicitly not loaded
# as context (`claude plugin validate` warns about one). A `rules/*.md` file is
# not a plugin component, so nothing loads it either. A SessionStart hook's
# `additionalContext` is the only distributed channel that reaches the model as
# a project instruction at session start, which is also what the EnterWorktree
# tool requires before it will create a worktree.
set -uo pipefail

cat >/dev/null 2>&1 || true   # drain hook input; this hook needs none of it

# Worktrees are a git concept. Stay silent outside a git repository.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

ctx=$(cat <<'TXT'
Project instruction (michael-config plugin) — git worktrees for pull-request work:

- Work headed for a pull request happens in a git worktree. One worktree per
  PR, never two.
- Enter the worktree BEFORE implementing, and before dispatching any
  implementing subagent, so the subagent inherits it. Use the EnterWorktree
  tool with `name` set to `pr-<number>` when the PR already exists, otherwise
  to the branch name you intend to push.
- Returning to an existing PR re-enters THAT PR's worktree rather than creating
  a second one. Find it with `git worktree list` and pass its path to
  EnterWorktree as `path`.
- Cleanup is decided by the PR, not by the session. PR merged and nothing
  uncommitted: ExitWorktree with action "remove". PR still open, or any work
  uncommitted or unpushed: ExitWorktree with action "keep". Never pass
  `discard_changes: true` unless the user says to discard that work.
- `git worktree prune` clears registrations whose directory is gone; it never
  deletes a live worktree.
- This instruction does not authorize creating a pull request. New PRs still
  require an explicit request from the user — see the github-pr skill.

Project instruction (michael-config plugin) — writing for humans:

- Chat replies, commit messages, PR descriptions and review comments lead with
  the answer, then say what changed and why.
- Do not re-list what the reader can already see in the diff or on screen: no
  inventories, no status tables, no per-file enumeration unless asked, and no
  pasted command, validator, or test output beyond the line that matters.
- Prose over tables for explanation. Flag what the reader must act on and cut
  the rest. Length follows the size of the change.
- Subagent reports to the main thread follow the same rule, because that report
  becomes the user-facing summary.
TXT
)

if command -v jq >/dev/null 2>&1; then
  jq -n --arg c "$ctx" '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: $c
    }
  }'
else
  # SessionStart also accepts plain stdout as context.
  printf '%s\n' "$ctx"
fi

exit 0
