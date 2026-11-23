#!/usr/bin/env bash
# Hooks are registered in settings.json or hooks/hooks.json, which have no comments
# and no frontmatter, so the same metadata lives in this header instead.
#
# name: example-hook
# event: PreToolUse (matcher: Bash)
# reason: The mistake this blocks or the context it adds, in one or two sentences.
#         Say why a hook is needed rather than an instruction in a skill or rule:
#         a hook is the only option when the behaviour must not depend on Claude
#         remembering it.
#
# Contract: the hook payload arrives as JSON on stdin. Exit 0 to allow, exit 2 to
# block and show stderr to Claude. Allow when the payload cannot be parsed: a hook
# bug must not break a legitimate tool call.

set -euo pipefail

payload="$(cat)"
command="$(printf '%s' "$payload" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))
except Exception:
    pass')"

if [[ "$command" == *"forbidden-example"* ]]; then
  echo "BLOCKED by example-hook: explain what was blocked and what to do instead." >&2
  exit 2
fi

exit 0
