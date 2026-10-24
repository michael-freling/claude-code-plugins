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
