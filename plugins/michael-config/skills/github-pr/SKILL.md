---
name: github-pr
description: Implement work that is headed for a pull request, then create or update that branch's PR and its title and description. Use when implementing or committing a change meant to land in a PR, pushing follow-up commits to a branch that already has one, rewriting a PR title or body, or fixing CI on an open PR.
allowed-tools: [Read, Glob, Grep, Bash, Agent, EnterWorktree, ExitWorktree]
---

# GitHub PR Skill

Carry a change from implementation to a green pull request. This skill owns
three jobs that used to be separate: implementing the work, deciding whether to
create or update the PR, and generating the PR title and description.

The implementing itself is **delegated to a subagent**. This skill resolves the
PR, establishes the worktree, dispatches the work, waits, verifies, commits,
pushes, and drives CI to green.

## Rules

- **NEVER create a new GitHub PR unless the user explicitly asks for one.**
- **What counts as "explicit"**: the user says something like "make a PR", "open
  a pull request", or "push this for review". Anything ambiguous is NOT
  explicit.
- Clarify ambiguous requests with the user instead of assuming. Do not create a
  PR "to be helpful".
- Loading this skill is **not** an instruction to create a PR. The skill loads
  automatically whenever PR-bound work is happening so that the create-vs-update
  decision below is made correctly — the guardrail above still gates `gh pr
  create`.
- Updating a PR that already exists is not creating one. Pushing follow-up
  commits and refreshing the title and body of the current branch's open PR is
  the normal way to continue work on it.
- **Never open a second PR for a branch that already has an open one.**
- **Never open a second worktree for a PR that already has one.**
- **Do not implement in the main thread.** Dispatch a subagent and wait for its
  result. Use the `subagent-routing` skill to pick the agent.

## Step 1: Resolve the Branch and Its PR

Do this **before** pushing anything, and before creating any worktree. It
determines the whole rest of the flow.

```bash
# Current branch
git branch --show-current

# Any PR that already exists for it
gh pr list --head "<branch-name>" --json number,state,url
```

Pick the path from the result:

| `gh pr list` result | Path | Action |
|---------------------|------|--------|
| A PR with state `OPEN` | **Update** | Commit, push to the same branch, then `gh pr edit <N>`. Do **NOT** run `gh pr create`. |
| Empty (no PR at all) | **Create** | Push and `gh pr create` — only if the user explicitly asked for a PR. |
| Only `CLOSED` or `MERGED` PRs | **Create** | A new PR is the correct outcome here. A closed or merged PR cannot be reopened for new work, so do not try to edit it — create a new PR (subject to the same explicit-request rule). |

Notes:

- `gh pr list --head` is the reliable lookup. It returns every PR for the
  branch, including closed and merged ones, which is what makes the three cases
  above distinguishable.
- To read a single field from the current branch's PR, the correct form is
  `gh pr view --json number --jq .number`. `-q`/`--jq` takes a jq *expression*,
  so never write `--json number -q` with no expression after it.

## Step 2: Establish the PR's Worktree

One worktree per PR. Enter it **before** implementing and before dispatching
any subagent, so the subagent inherits it as its working directory.

First, look for a worktree this PR already has:

```bash
git worktree list
```

Then pick one of three cases:

| Situation | What to do |
|-----------|------------|
| A worktree for this PR already exists in `git worktree list` | Re-enter it: `EnterWorktree` with `path` set to that directory. Never create a second one. |
| No worktree, and **no** branch to preserve (new work) | `EnterWorktree` with `name` set to the branch name you intend to push. |
| No worktree, but an **existing branch** with an open PR | `git worktree add .claude/worktrees/pr-<number> <existing-branch>`, then `EnterWorktree` with `path` set to that directory. |

Naming: `pr-<number>` once the PR exists, otherwise the branch name you intend
to push. Rename nothing afterwards — the directory is how the next session finds
this PR's worktree.

> **Why the third case matters.** `EnterWorktree` with `name` creates a *new*
> branch, and its base ref follows the `worktree.baseRef` setting, which
> defaults to `fresh` — branching from `origin/<default-branch>`. Using `name`
> to continue an existing PR would strand that PR's branch. Add the worktree on
> the existing branch with `git worktree add` and enter it by `path` instead.

## Step 3: Understand

Clarify what the user wants:

- Identify the type of change (feature, fix, flaky test fix, or refactor)
- Ask clarifying questions if requirements are ambiguous
- Understand scope and success criteria
- For fixes: identify reproduction steps and expected vs actual behavior
- For flaky test fixes: identify which test(s) are flaky and their failure
  patterns

| Type | Goal | Key Constraint |
|------|------|----------------|
| **Feature** | Add new functionality | - |
| **Fix** | Fix broken behavior | Must reproduce bug first |
| **Flaky Test Fix** | Eliminate test non-determinism | Must run tests multiple times to verify stability |
| **Refactor** | Improve structure, same behavior | Must preserve existing behavior |

## Step 4: Explore

Investigate the codebase. Reading and searching in the main thread is fine; this
is the context the implementing subagent will be handed.

- Analyze existing structure and patterns
- For features: identify implementation approaches and trade-offs
- For fixes: reproduce the error and find root cause
- For flaky test fixes: identify the source of non-determinism (timing,
  ordering, shared state, external dependencies, race conditions)
- For refactors: identify code smells and improvement opportunities

## Step 5: Present Plan

**IMPORTANT**: Present the plan to the user before coding:

- Analysis findings (root cause for fixes, options for features)
- Proposed approach
- Files to modify or create
- Potential risks or side effects
- Which subagent will implement it

Wait for user approval before proceeding.

## Step 6: Implement — Dispatch a Subagent and Wait

Once approved, **dispatch** the implementation. Do not write the code in the
main thread.

Pick the agent by what is being changed (full table in the `subagent-routing`
skill):

| Change | Agent |
|--------|-------|
| Application code, tests, config, docs | `michael-config:code-developer` |
| GitHub Actions workflow | `michael-config:github-actions-workflow-engineer` |
| Kubernetes manifests, Kustomize, Helm | `michael-config:kubernetes-engineer` |

The subagent's prompt is the only context it gets. Hand it the change type, the
findings from Step 4, the approved plan from Step 5, the exact files in scope,
and the per-type procedure below.

**For fixes:**

1. Write a failing test that reproduces the bug
2. Implement the fix
3. Verify the test passes

**For features:**

1. Implement the feature
2. Write tests for new functionality

**For flaky test fixes:**

1. Run the flaky test multiple times (5-10 runs) to confirm flakiness and
   understand failure rate
2. Identify the root cause of non-determinism
3. Implement the fix (e.g. add proper synchronization, remove timing
   dependencies, isolate shared state)
4. Run the test multiple times (at least 10 runs) to verify it's now stable

**For refactors:**

1. Ensure existing tests pass before changes
2. Make structural changes
3. Verify tests still pass after changes

Tell the subagent to follow testing guidelines from the coding guidelines skill.

Then **wait** for its result. Do not implement the same change in parallel, and
do not redo its work afterwards. Relay what it reports — the user does not see
the subagent's own report.

## Step 7: Verify

Confirm the implementation is correct. The subagent verifies its own work; this
step is the independent check.

- Run all tests and ensure they pass
- Run linters and fix any issues
- Manually verify the change works as expected
- Check for regressions

**For flaky test fixes - additional verification:**

- Run the previously flaky test at least 10 consecutive times
- All runs must pass to confirm the fix is stable
- Example verification commands:
  - Go: `for i in {1..10}; do go test -v -run TestName ./path/... || exit 1; done`
  - Jest: `for i in {1..10}; do npx jest --testNamePattern="test name" || exit 1; done`
  - pytest: `for i in {1..10}; do pytest -v test_file.py::test_name || exit 1; done`
- If any run fails, the fix is incomplete - investigate further

If verification fails, **re-dispatch** to the same subagent with the failure
output. Do not patch it up in the main thread.

## Step 8: Commit

Group related changes into logical commits:

- Write clear commit messages describing the "why"
- Separate refactoring from feature/fix changes when possible

## Step 9: Generate the Title and Description

This step feeds **both** the create path and the update path — the PR body is
regenerated from the branch's full diff every time, not just when the PR is
first opened.

```bash
# Fetch latest from remote
git fetch origin main

# All commits in this branch
git log origin/main..HEAD --oneline

# The full diff
git diff origin/main...HEAD --stat
```

**Title format:**

- For single-purpose PRs: `<type>: <concise description>`
- Types: `feat`, `fix`, `refactor`, `docs`, `chore`, `test`
- Keep it under 72 characters

**Body format:**

```markdown
## Summary
- 2-4 bullet points describing the main changes

## Test Plan
- How the change was verified (tests run, linters, manual checks)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Guidelines:

- Read all commits to understand the full scope of changes
- Group related changes together in the description
- Focus on the "why" not just the "what"
- Include breaking changes prominently if any
- Always include the
  `🤖 Generated with [Claude Code](https://claude.com/claude-code)` trailer
- To link and auto-close associated issues, use the github-pr-link skill

## Step 10a: Update Path (an OPEN PR already exists)

Push to the same branch — the PR picks up the new commits by itself — then
refresh the title and body with the text from Step 9:

```bash
git push

gh pr edit <PR_NUMBER> --title "<type>: concise description" --body "$(cat <<'EOF'
## Summary
- Description of changes

## Test Plan
- How the change was verified

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Do not run `gh pr create` on this path. Pushing is all it takes to update the
PR's diff; `gh pr edit` only refreshes the metadata.

## Step 10b: Create Path (no PR, or only closed/merged ones)

Only when the user explicitly asked for a new PR.

```bash
git push -u origin <branch-name>

gh pr create --title "<type>: concise description" --body "$(cat <<'EOF'
## Summary
- Description of changes

## Test Plan
- How the change was verified

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

If the user has not explicitly asked for a PR, stop after pushing (or after
committing, if pushing was not requested either) and tell them the branch is
ready.

Once the PR number exists, this worktree is that PR's worktree for the rest of
its life. Keep using it.

## Step 11: Fix CI Until Green

Once the PR exists (either path), monitor and fix CI:

```bash
gh pr checks <PR_NUMBER>
```

1. Wait for CI to complete (at least 1 minute for jobs to start)
2. Check CI status every 5 minutes until complete
3. If CI fails:
   - Analyze the errors (see the github-actions-troubleshoot skill)
   - **Dispatch** the fix to a subagent — `code-developer` when application code
     or tests are at fault, `github-actions-workflow-engineer` when the workflow
     file is — and wait for its result
   - Push the new commits to the same branch
   - Repeat until all checks pass
4. Never leave the PR with failing checks

A CI fix is follow-up work on an existing PR, so it always takes the update
path in Step 10a, in this PR's existing worktree. Never create a new PR, and
never a new worktree, to fix CI.

## Step 12: Clean Up the Worktree

Cleanup is decided by the **PR's** state, not by the session ending.

| PR state | Working tree | Action |
|----------|--------------|--------|
| Merged (or closed and abandoned) | Clean, nothing unpushed | `ExitWorktree` with `action: "remove"` — deletes the directory and its branch |
| Open | Anything | `ExitWorktree` with `action: "keep"` — the next session re-enters it by `path` in Step 2 |
| Any | Uncommitted or unpushed work | `ExitWorktree` with `action: "keep"` |

`ExitWorktree` refuses `remove` when there are uncommitted changes or unmerged
commits. That refusal is correct — it means the work is not actually finished.
**Never** pass `discard_changes: true` to force past it unless the user has said
to discard that specific work.

If the session ends while still inside the worktree, the user is prompted to
keep or remove it. Answer from the table above.

Stale worktrees — a directory deleted by hand, or a repository that moved — are
cleaned up with:

```bash
git worktree list          # what is registered, and what is 'prunable'
git worktree prune -n -v   # what pruning would drop
git worktree prune         # drop registrations whose directory is gone
```

`git worktree prune` only removes registrations, never a live worktree's files.
A leftover branch from a merged PR can then be deleted with
`git branch -d <branch>`; use `-D` only when the branch is genuinely unwanted,
since it discards unmerged commits.

## Guidelines

- Follow coding guidelines (DRY, simplicity, explicit over implicit)
- Adhere to project-specific guidelines if available
- Maintain or increase test coverage
- For fixes: always reproduce first, understand root cause
- For flaky test fixes: always verify stability with multiple runs (minimum 10)
- For refactors: never change behavior, only structure
- The main thread resolves, routes, commits, pushes, and reports. Subagents
  implement.
