# CLAUDE.md

## Delegation

- Only subagents can work on each task.
- Never implement in the main thread: no `Edit`, no `Write`, and no
  file-mutating `Bash` from the main agent.
- The protocol is **dispatch → wait → report**:
  1. **Dispatch** one subagent with the `Agent` tool. The prompt is the only
     context it gets, so state the goal, the files worth reading, what you have
     already ruled out, and the scope boundary.
  2. **Wait** for its result. Do not do the same work in parallel, and do not
     redo it afterwards.
  3. **Report** the subagent's result to the user, naming the agent that ran.
- Pick the agent from the task-type table in the `subagent-routing` skill. Load
  that skill before dispatching whenever the owning agent is not obvious.
- Reading, searching, and planning in the main thread are fine. Implementing is
  what gets delegated.
- A `PreToolUse` hook in `.claude/settings.json` denies main-thread `Edit` and
  `Write`. Being blocked by it means the dispatch step was skipped — dispatch,
  do not look for a way around the hook.

## Worktrees

- PR-bound work happens in a git worktree. One worktree per PR, never two.
- Enter the worktree **before** implementing and before dispatching the
  implementing subagent, so the subagent inherits it:
  `EnterWorktree` with `name` set to `pr-<number>` when the PR already exists,
  otherwise to the branch name you intend to push.
- Returning to an existing PR re-enters **that PR's** worktree. Find it with
  `git worktree list` and pass its path to `EnterWorktree` as `path`. Never
  create a second worktree for a PR that already has one.
- Removal is decided by the PR, not by the session:
  - PR merged, nothing uncommitted → `ExitWorktree` with `action: "remove"`.
  - PR still open, or any work uncommitted or unpushed → `ExitWorktree` with
    `action: "keep"`.
- Never pass `discard_changes: true` unless the user says to discard that work.
- `git worktree prune` clears registrations whose directory is gone. It is safe
  and never deletes a live worktree.

## Distribution

- This repo *is* a Claude Code plugin marketplace. Any capability added here —
  skill, agent, command, or hook — must ship through the plugin (top-level
  `agents/`, `commands/`, `skills/`, `hooks/hooks.json`), not as project-local
  `.claude/` config. Project-local `.claude/` only governs sessions working
  directly in this repo's own checkout; it never reaches a project that
  installs the plugin.
- Reference the plugin's own bundled files with `$CLAUDE_PLUGIN_ROOT`, not
  `$CLAUDE_PROJECT_DIR` or a path relative to this repo's root — the latter
  breaks once the plugin is installed somewhere else.
- A capability's own code/definition lives in the plugin's distributable
  paths. Per-project state it needs at runtime (e.g. a declared recipe file,
  a result file) still belongs in whatever project the capability runs in,
  under that project's own `.claude/` — written there by the skill or hook
  when it runs, not shipped as part of the plugin.
- Before opening a PR that touches `.claude-plugin/`, `agents/`, `commands/`,
  `skills/`, or `hooks/`, run the `validate-plugin` skill.

## Writing for humans

- Everything a human reads — chat replies, commit messages, PR descriptions,
  review comments — leads with the answer or the conclusion. No preamble, no
  restating the request.
- Say what changed and why. Never re-list what the reader already has on screen,
  in the diff, or in the file they just opened.
- No inventories, no status tables, no per-file enumeration unless asked for one.
- Quote the one line of command, validator, or test output that matters. Paste
  nothing else.
- Prose for explanation. A table only for a real lookup with repeated keys.
- Flag what the reader must act on, and cut the rest.
- Length follows the change: a one-line fix gets one line. Routine work does not
  earn headings.
- No praise sections, no "what went well", no restating the plan back as a
  summary.
- This applies to subagent reports to the main thread. That report becomes the
  user-facing summary, so padding in it reaches the user.
