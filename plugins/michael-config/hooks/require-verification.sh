#!/bin/bash
# PreToolUse + Stop hook: block completion / PR creation unless the consuming
# project's declared verification workflow (.claude/verification.yaml) was run
# against the CURRENT code and passed. Full contract:
# skills/define-verification/references/format.md in this plugin.
#
# Wired twice in hooks/hooks.json:
#   - Stop: fires whenever the agent is about to finish responding.
#   - PreToolUse, matcher "Bash": fires on every Bash call. The `matcher`
#     field only matches tool name, not command content (same constraint
#     require-subagent.sh works around), so this script itself filters down
#     to PR-creation-shaped commands (e.g. `gh pr create`) and is a silent
#     no-op for every other Bash call.
#
# Event discrimination: this script is wired to exactly those two events, so
# it tells them apart by payload shape rather than by trusting a field name
# to exist: a PreToolUse-Bash call's JSON has `.tool_name == "Bash"`; a Stop
# call's does not.
#
# Gate condition (the real check) -- block unless ALL of:
#   1. <project>/.claude/.verification-result.json exists
#   2. its `sha` equals the current `git rev-parse HEAD`
#   3. `git status --porcelain` is empty (a dirty tree means the recorded
#      pass predates uncommitted changes, so it is stale)
#   4. its `passed` field is `true`
#
# Deliberate scope narrowing: if the consuming project has no
# .claude/verification.yaml, this hook allows unconditionally instead of
# blocking. A project opts into the gate by declaring a recipe (the
# define-verification skill writes that file); until it does, there is
# nothing to run and nothing to gate against, and blocking every Stop event
# unconditionally -- including turns with no code change at all -- would
# make every installing project unusable rather than enforce anything. See
# skills/define-verification/references/format.md.
#
# stop_hook_active (present on Stop events only) is deliberately NOT used as
# a bypass here. That field lets soft "reminder" hooks avoid re-blocking
# forever, but this is a hard gate: the condition above is re-checked on
# every Stop regardless, and Claude Code's own built-in safety valve (it
# overrides a hook that blocks 8 consecutive times with no intervening tool
# call) is what prevents a genuine infinite loop. Treating stop_hook_active
# as "just let it stop" would let an agent bypass verification by simply
# retrying the stop.
#
# Verified against Claude Code 2.1.283.
set -uo pipefail

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  # Fail open rather than deadlock the project if jq is unavailable.
  exit 0
fi

project_dir="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
yaml_file="$project_dir/.claude/verification.yaml"
result_file="$project_dir/.claude/.verification-result.json"
runner="${CLAUDE_PLUGIN_ROOT}/hooks/run-verification.sh"

# Not declared yet: nothing to gate against.
if [ ! -f "$yaml_file" ]; then
  exit 0
fi

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)

build_block_reason() {
  local current_sha dirty result_sha passed failed_step output reason

  current_sha=$(git -C "$project_dir" rev-parse HEAD 2>/dev/null)
  dirty=$(git -C "$project_dir" status --porcelain 2>/dev/null)

  if [ ! -f "$result_file" ]; then
    printf '%s' "No verification result found at .claude/.verification-result.json. Run ${runner} and get it passing before completing."
    return
  fi

  result_sha=$(jq -r '.sha // empty' "$result_file" 2>/dev/null)
  passed=$(jq -r '.passed // false' "$result_file" 2>/dev/null)
  failed_step=$(jq -r '.failed_step // empty' "$result_file" 2>/dev/null)
  output=$(jq -r '.output // empty' "$result_file" 2>/dev/null)

  if [ -n "$dirty" ]; then
    printf '%s' "The working tree has uncommitted changes since the last verification run, so that recorded pass is stale. Run ${runner} again against the current code before completing."
    return
  fi

  if [ "$result_sha" != "$current_sha" ]; then
    printf '%s' "The recorded verification result is for commit ${result_sha:-<none>}, but HEAD is now ${current_sha}. Run ${runner} again against the current code before completing."
    return
  fi

  if [ "$passed" != "true" ]; then
    reason="The last verification run failed"
    [ -n "$failed_step" ] && reason="${reason} at step '${failed_step}'"
    reason="${reason}. Run ${runner}, fix the problem, and get it passing before completing."
    if [ -n "$output" ]; then
      reason="${reason}
Captured output from the failing step:
${output}"
    fi
    printf '%s' "$reason"
    return
  fi
}

if [ "$tool_name" = "Bash" ]; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
  if ! [[ "$cmd" =~ gh[[:space:]]+pr[[:space:]]+create ]]; then
    exit 0
  fi
  reason=$(build_block_reason)
  if [ -n "$reason" ]; then
    reason="Blocking PR creation: ${reason}"
    jq -n --arg r "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $r
      }
    }'
  fi
  exit 0
fi

# Stop event.
reason=$(build_block_reason)
if [ -n "$reason" ]; then
  jq -n --arg r "$reason" '{decision: "block", reason: $r}'
fi
exit 0
