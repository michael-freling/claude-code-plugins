---
name: subagent-routing
description: Decide which specialized subagent owns a task, then dispatch it and wait. Use when about to implement, design, or review anything and the owning agent is not obvious, or when a project requires that subagents do the work rather than the main thread.
allowed-tools: [Read, Glob, Grep, Bash, Agent]
---

# Subagent Routing

The main thread decides *who* does the work. It does not do the work.

## Delegate-and-Wait Protocol

1. **Pick the agent** from the routing table below.
2. **Dispatch** one subagent with the `Agent` tool. Its prompt is the only
   context it will ever have, so include:
   - the goal, stated as an outcome
   - the files and docs worth reading, by path
   - what has already been ruled out
   - the scope boundary — what it must not touch
3. **Wait** for the result. Do not do the same work in the main thread in
   parallel, and do not redo it afterwards.
4. **Report** the result to the user, naming the agent that ran. The subagent's
   final report is not shown to the user, so relay what matters.

Reading, searching, and planning in the main thread are fine. Implementing,
designing, and reviewing are delegated.

Dispatch one agent per coherent task. Several agents at once only when their
tasks are genuinely independent.

## Routing Table

Agent names are namespaced: `michael-config:<name>`.

| Task type | Agent |
|-----------|-------|
| Product requirements, user stories, success metrics (WHAT and WHY, no tech) | `product-manager` |
| Review a product spec, requirements doc, or user stories | `product-spec-reviewer` |
| User flow diagrams, wireframes, screen layouts | `ux-designer` |
| Review a UX design or wireframes (usability, accessibility) | `ux-design-reviewer` |
| System architecture, HTTP/gRPC API schema, database table schema, security architecture | `software-architect` |
| Review requirements analysis, architecture, an API spec, or a DB schema | `architecture-reviewer` |
| Frontend implementation design — components, state, data flow, no code | `frontend-design-engineer` |
| Review a frontend implementation design | `frontend-design-reviewer` |
| Backend implementation design — modules, data flow, error handling, no code | `backend-design-engineer` |
| Review a backend implementation design | `backend-design-reviewer` |
| Write or change code — features, bug fixes, refactors, tests, config, docs | `code-developer` |
| Review code changes for correctness, quality, and architecture | `code-reviewer` |
| Create, modify, verify, or debug a GitHub Actions workflow | `github-actions-workflow-engineer` |
| Kubernetes manifests, Kustomize, Helm, pod failures, ArgoCD sync issues | `kubernetes-engineer` |

## Tie-Breakers

- **CI is red.** The workflow file itself is wrong →
  `github-actions-workflow-engineer`. The workflow is fine and the application
  code or tests fail → `code-developer`.
- **A design agent must not write code.** `software-architect`,
  `product-manager`, `ux-designer`, and the two `*-design-engineer` agents
  produce documents. Once a design is approved, the implementation goes to
  `code-developer`.
- **A reviewer must not implement.** Take the reviewer's findings and dispatch
  the matching engineer agent to act on them.
- **Design review pairs.** Each design stage has one designer and one reviewer;
  `rules/design-workflow.md` holds the stage ordering and the output directory
  convention.
- **Nothing fits.** Use `code-developer` for anything that edits files, and
  state in the prompt that the task is outside its usual scope.

## Prompt Template

```
Goal: <outcome, not a list of steps>

Context already established (do not re-research):
- <finding>
- <finding>

Read these:
- <path> — <why>

Scope: change only <paths>. Do not touch <paths>.

Report back: <what the main thread needs to relay to the user>
```
