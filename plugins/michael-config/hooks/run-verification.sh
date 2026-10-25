#!/bin/bash
# Generic workflow runner for a consuming project's .claude/verification.yaml.
#
# This script has no knowledge of any project's build, test, lint, or deploy
# tooling. It understands exactly three step `type`s and otherwise just
# executes whatever `command` string a step declares, via `bash -c`:
#
#   run     - one-shot command; must exit 0 or the whole workflow fails.
#   poll    - repeats `command` every `interval_seconds` until it exits 0,
#             or fails once `timeout_seconds` has elapsed.
#   cleanup - always runs, in declaration order, after the run/poll steps
#             above finish -- whether they passed, failed, or timed out.
#             Same idea as a shell `trap ... EXIT`.
#
# The full .claude/verification.yaml format, and the
# .claude/.verification-result.json contract this script writes, are
# documented in this plugin's skills/define-verification/references/format.md.
# Read that before changing either shape -- the define-verification skill and
# the require-verification hook both depend on it exactly.
#
# Usage:  "$CLAUDE_PLUGIN_ROOT"/hooks/run-verification.sh
#         (run from, or with CLAUDE_PROJECT_DIR pointed at, the project that
#         declared .claude/verification.yaml)
# Exit:   0 if the workflow passed, 1 if it failed, 2 on a setup error
#         (missing verification.yaml, malformed YAML, missing jq/python3).
#         On a setup error, no result file is written at all -- the hook
#         treats a missing result file as "nothing recorded" either way.
# The authoritative pass/fail record always lands in
# .claude/.verification-result.json in the consuming project; the hook reads
# that file, not this script's exit code.

set -uo pipefail

project_dir="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
yaml_file="$project_dir/.claude/verification.yaml"
result_file="$project_dir/.claude/.verification-result.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "run-verification: jq is required but was not found in PATH." >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "run-verification: python3 is required but was not found in PATH." >&2
  exit 2
fi

if [ ! -f "$yaml_file" ]; then
  echo "run-verification: $yaml_file does not exist." >&2
  echo "Run the define-verification skill to describe this project's verification workflow first." >&2
  exit 2
fi

cd "$project_dir" || exit 2

# --- Parse the restricted YAML subset into a JSON array of steps. ---------
# See skills/define-verification/references/format.md in this plugin for
# exactly what subset of YAML is supported.
steps_json=$(python3 - "$yaml_file" <<'PYEOF'
import sys, json, re

def unquote(s):
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ('"', "'"):
        return s[1:-1]
    return s

def parse(path):
    with open(path) as f:
        lines = f.readlines()
    steps = []
    current = None
    i, n = 0, len(lines)
    while i < n:
        line = lines[i].rstrip("\n")
        stripped = line.strip()
        if stripped == "" or stripped.startswith("#"):
            i += 1
            continue
        m = re.match(r'^- name:\s*(.*)$', line)
        if m:
            if current is not None:
                steps.append(current)
            current = {"name": unquote(m.group(1))}
            i += 1
            continue
        if current is None:
            sys.stderr.write("run-verification: %s:%d: expected a step starting with '- name:'\n" % (path, i + 1))
            sys.exit(2)
        m = re.match(r'^\s+type:\s*(.*)$', line)
        if m:
            current["type"] = unquote(m.group(1))
            i += 1
            continue
        m = re.match(r'^\s+interval_seconds:\s*(.*)$', line)
        if m:
            current["interval_seconds"] = int(unquote(m.group(1)))
            i += 1
            continue
        m = re.match(r'^\s+timeout_seconds:\s*(.*)$', line)
        if m:
            current["timeout_seconds"] = int(unquote(m.group(1)))
            i += 1
            continue
        m = re.match(r'^\s+command:\s*(\|[-+0-9]*)\s*$', line)
        if m:
            block_indent = None
            body = []
            i += 1
            while i < n:
                bl = lines[i].rstrip("\n")
                if bl.strip() == "":
                    body.append("")
                    i += 1
                    continue
                indent = len(bl) - len(bl.lstrip(" "))
                if block_indent is None:
                    block_indent = indent
                if indent < block_indent:
                    break
                body.append(bl[block_indent:])
                i += 1
            while body and body[-1] == "":
                body.pop()
            current["command"] = "\n".join(body)
            continue
        m = re.match(r'^\s+command:\s*(.*)$', line)
        if m:
            current["command"] = unquote(m.group(1))
            i += 1
            continue
        i += 1
    if current is not None:
        steps.append(current)
    return steps

steps = parse(sys.argv[1])
for idx, s in enumerate(steps):
    if "name" not in s or "type" not in s or "command" not in s:
        sys.stderr.write("run-verification: step %d is missing name/type/command\n" % (idx + 1))
        sys.exit(2)
    if s["type"] not in ("run", "poll", "cleanup"):
        sys.stderr.write("run-verification: step '%s' has unknown type '%s'\n" % (s["name"], s["type"]))
        sys.exit(2)
    if s["type"] == "poll" and ("interval_seconds" not in s or "timeout_seconds" not in s):
        sys.stderr.write("run-verification: poll step '%s' needs interval_seconds and timeout_seconds\n" % s["name"])
        sys.exit(2)
print(json.dumps(steps))
PYEOF
)
parse_status=$?
if [ "$parse_status" -ne 0 ] || [ -z "$steps_json" ]; then
  exit 2
fi

step_count=$(printf '%s' "$steps_json" | jq 'length')

passed=true
failed_step=""
failed_output=""

# --- Phase 1: run/poll steps, in declaration order, stop at first failure.
for ((idx = 0; idx < step_count; idx++)); do
  step_json=$(printf '%s' "$steps_json" | jq -c ".[$idx]")
  step_name=$(printf '%s' "$step_json" | jq -r '.name')
  step_type=$(printf '%s' "$step_json" | jq -r '.type')
  step_command=$(printf '%s' "$step_json" | jq -r '.command')

  case "$step_type" in
  cleanup)
    continue # cleanup steps run in phase 2, regardless of position
    ;;
  run)
    echo "run-verification: [run] $step_name" >&2
    step_output=$(bash -c "$step_command" 2>&1)
    step_status=$?
    if [ "$step_status" -ne 0 ]; then
      passed=false
      failed_step="$step_name"
      failed_output="$step_output"
      echo "run-verification: FAILED at '$step_name' (exit $step_status)" >&2
      break
    fi
    ;;
  poll)
    step_interval=$(printf '%s' "$step_json" | jq -r '.interval_seconds')
    step_timeout=$(printf '%s' "$step_json" | jq -r '.timeout_seconds')
    echo "run-verification: [poll] $step_name (every ${step_interval}s, timeout ${step_timeout}s)" >&2
    start_time=$(date +%s)
    poll_ok=false
    step_output=""
    while true; do
      step_output=$(bash -c "$step_command" 2>&1)
      if [ $? -eq 0 ]; then
        poll_ok=true
        break
      fi
      now_time=$(date +%s)
      if [ $((now_time - start_time)) -ge "$step_timeout" ]; then
        break
      fi
      sleep "$step_interval"
    done
    if [ "$poll_ok" != "true" ]; then
      passed=false
      failed_step="$step_name"
      failed_output="$step_output"
      echo "run-verification: TIMED OUT at '$step_name' (after ${step_timeout}s)" >&2
      break
    fi
    ;;
  esac
done

# --- Phase 2: cleanup steps, always, in declaration order, best-effort. ---
for ((idx = 0; idx < step_count; idx++)); do
  step_json=$(printf '%s' "$steps_json" | jq -c ".[$idx]")
  step_type=$(printf '%s' "$step_json" | jq -r '.type')
  [ "$step_type" = "cleanup" ] || continue
  step_name=$(printf '%s' "$step_json" | jq -r '.name')
  step_command=$(printf '%s' "$step_json" | jq -r '.command')
  echo "run-verification: [cleanup] $step_name" >&2
  cleanup_output=$(bash -c "$step_command" 2>&1)
  cleanup_status=$?
  if [ "$cleanup_status" -ne 0 ]; then
    echo "run-verification: cleanup step '$step_name' exited $cleanup_status (continuing; cleanup failures do not flip the result):" >&2
    echo "$cleanup_output" >&2
  fi
done

# --- Write the result file. ------------------------------------------------
sha=$(git -C "$project_dir" rev-parse HEAD 2>/dev/null || echo "unknown")
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ "$passed" = "true" ]; then
  jq -n --arg sha "$sha" --arg ts "$timestamp" \
    '{sha: $sha, timestamp: $ts, passed: true}' >"$result_file"
  echo "run-verification: PASSED" >&2
  exit 0
else
  jq -n --arg sha "$sha" --arg ts "$timestamp" --arg step "$failed_step" --arg out "$failed_output" \
    '{sha: $sha, timestamp: $ts, passed: false, failed_step: $step, output: $out}' >"$result_file"
  echo "run-verification: FAILED" >&2
  exit 1
fi
