# Claude Code Configuration

Personal Claude Code configurations including commands, skills, rules, and agents.

## Installation

```bash
git clone https://github.com/michael-freling/claude-code-plugins.git
cd claude-code-plugins
make install
```

This creates symlinks in `~/.claude/` pointing to this repository.

To uninstall:

```bash
make uninstall
```

## Repository Structure

This repository is a Claude Code plugin marketplace. The marketplace manifest
stays at the repo root, and the plugin itself lives under `plugins/michael-config/`:

```
.claude-plugin/
└── marketplace.json          # marketplace manifest (repo root)
plugins/
└── michael-config/
    ├── .claude-plugin/
    │   └── plugin.json        # plugin manifest
    ├── agents/
    ├── commands/
    ├── skills/
    ├── rules/
    └── templates/
```

## What's Included

### Commands

Slash commands for common workflows:

| Command | Purpose |
|---------|---------|
| `/write-product-spec` | Write product requirements and user stories |
| `/design-ux` | Create UI flows and wireframes |
| `/design-system-architecture` | Design API, database, and security |
| `/design-frontend-details` | Design frontend implementation |
| `/design-backend-details` | Design backend implementation |
| `/document-guideline` | Analyze codebase and create project guidelines |
| `/document-guideline-monorepo` | Create project guidelines for monorepo setups |
| `/pr-review` | Review a pull request for code quality |
| `/pr-feedback` | Address PR review feedback and fix issues |

### Skills

Reusable guidance for specific tasks:

| Skill | Purpose |
|-------|---------|
| `troubleshoot` | General diagnostic principles |
| `github-actions-troubleshoot` | Fix GitHub Actions CI errors |
| `kubernetes-troubleshoot` | Diagnose K8s pod failures, ArgoCD sync issues |
| `kubernetes-manifests` | K8s manifest best practices |
| `pr-feedback` | Address PR review feedback |
| `github-pr-link` | Link issues to PRs with closing keywords |
| `github-sub-issues` | Create parent-child issue relationships |
| `git-branch` | Create a git branch (only on explicit request) |
| `github-pr` | Implement PR-bound work, then create or update the branch's PR (new PRs only on explicit request) |
| `subagent-routing` | Route a task to the subagent that owns it, then dispatch and wait |

### Rules

Coding guidelines applied to all projects:

| Rule | Purpose |
|------|---------|
| `coding-guidelines` | General coding principles (simplicity, readability, testing) |
| `design-workflow` | Design phase ordering conventions |
| `system-operations` | System operations guidelines |
| `github-actions` | CI workflow best practices (quiet flags) |
| `docker-commands` | Docker command best practices |
| `golang` | Go-specific guidelines |
| `typescript` | TypeScript-specific guidelines |
| `protobuf` | Protocol Buffers conventions |

### Agents

Specialized agents for different tasks:

**Design Agents:**
- `product-manager` - Product requirements
- `ux-designer` - UI flows and wireframes
- `software-architect` - System architecture
- `frontend-design-engineer` / `backend-design-engineer` - Implementation design

**Review Agents:**
- `architecture-reviewer` - Review system designs
- `product-spec-reviewer` - Review product specs
- `ux-design-reviewer` - Review UX designs
- `frontend-design-reviewer` / `backend-design-reviewer` - Review implementation designs
- `code-reviewer` - Review code changes

**Implementation Agents:**
- `code-developer` - Implement code changes
- `github-actions-workflow-engineer` - Create/fix GitHub Actions workflows
- `kubernetes-engineer` - Create/troubleshoot K8s resources

## Design Workflow

For larger features, follow this sequence:

```
1. /write-product-spec        → Product requirements (WHAT and WHY)
         ↓
2. /design-ux                 → User flows and wireframes
         ↓
3. /design-system-architecture → API, database, security design
         ↓
4. /design-frontend-details   → Frontend implementation design
   /design-backend-details    → Backend implementation design
         ↓
5. github-pr skill            → Implementation + PR
```

## Implementation Workflow

The `github-pr` skill loads automatically for PR-bound work and follows this
workflow:

1. **Resolve the branch's PR** - `gh pr list --head <branch>` decides create vs update
2. **Establish the PR's worktree** - One worktree per PR; re-enter an existing one by path
3. **Understand** - Clarify requirements, identify change type (feature/fix/refactor)
4. **Explore** - Analyze codebase, find root cause (for fixes), evaluate options
5. **Present Plan** - Show plan and wait for user approval
6. **Implement** - Dispatch a subagent and wait for its result
7. **Verify** - Run tests, linters, manual verification
8. **Commit** - Group related changes into logical commits
9. **Generate title and description** - From the `origin/main...HEAD` diff, for both paths
10. **Create or update the PR** - Push and `gh pr edit` an open PR, or `gh pr create` when there is none
11. **Fix CI Until Green** - Monitor CI, dispatch fixes, repeat until passing
12. **Clean up the worktree** - Remove it once the PR is merged, keep it while the PR is open

## Delegation and Worktrees

The plugin ships a `SessionStart` hook (`hooks/hooks.json`) that injects the
worktree rule for PR-bound work into every session, because a repo-root
`CLAUDE.md` is not distributed to plugin installers and a plugin-root
`CLAUDE.md` is never loaded as context.

The `subagent-routing` skill holds the task-type → agent table and the
dispatch → wait → report protocol. In this repository, a `PreToolUse` hook in
`.claude/settings.json` additionally denies main-thread `Edit`/`Write` so the
work has to go through a subagent; it keys on the hook input's `agent_id`,
which is present only for subagent calls, so subagents are unaffected.
