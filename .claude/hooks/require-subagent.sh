#!/bin/bash
# PreToolUse hook: deny Edit/Write/NotebookEdit in the MAIN thread only.
#
# Why this is safe for subagents: a PreToolUse hook fires for subagent tool
# calls too, but the hook input carries `agent_id` only when the call comes
# from a subagent or an in-process teammate. A main-thread call has no
# `agent_id` key at all. Keying on `agent_id` is what keeps this hook from
# blocking the very subagents that are supposed to do the work.
#
# `agent_type` is NOT a safe discriminator: it is also set on the main thread
# when the session was started with `--agent`.
#
# Verified against Claude Code 2.1.283.
set -uo pipefail

input=$(cat)

if command -v jq >/dev/null 2>&1; then
  agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null || true)
  tool_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)
else
  # Fail open rather than deadlock the repo if jq is unavailable.
  printf '%s' "$input" | grep -q '"agent_id"' && exit 0
  agent_id=""
  tool_path=""
fi

# Subagent or in-process teammate: let it work. This is the whole point.
[ -n "$agent_id" ] && exit 0

# Main thread. Name the agent that owns this kind of file.
case "$tool_path" in
  */.github/workflows/*) agent="michael-config:github-actions-workflow-engineer" ;;
  */k8s/*|*/kubernetes/*|*/manifests/*|*/overlays/*|*/base/*)
                         agent="michael-config:kubernetes-engineer" ;;
  *)                     agent="michael-config:code-developer" ;;
esac

reason="Main-thread edits are blocked in this repo (CLAUDE.md: only subagents can work on a task).
Dispatch the work with the Agent tool instead, then wait for its result and report it.
Suggested agent for this file: ${agent}
Load the subagent-routing skill if another agent owns this task type."

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}' 2>/dev/null || printf '%s\n' \
  '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Main-thread edits are blocked (CLAUDE.md). Dispatch a subagent with the Agent tool."}}'

exit 0
