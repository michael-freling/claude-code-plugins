# Verification Format

This plugin gates two things on proof, not on a self-report: an agent saying
"I tested it" is not enough to stop or to open a PR in a project that opts
in. Completion and PR creation are mechanically blocked (see the
`require-verification` hook in this plugin's `hooks/hooks.json`) unless a
declared verification workflow was actually run against the current code and
passed.

Three pieces make this work:

- `.claude/verification.yaml`, in the consuming project — **what** proves a
  change there works. Written once per project, by a human answering the
  `define-verification` skill's question in their own words. Absent until
  someone does that; see below.
- `hooks/run-verification.sh`, in this plugin — runs that recipe. Generic: it
  has no idea what `command` strings mean, it just executes them and
  interprets `type`. Invoke it as `"$CLAUDE_PLUGIN_ROOT"/hooks/run-verification.sh`.
- `.claude/.verification-result.json`, in the consuming project — the
  runner's output: proof the recipe ran, against which commit, and whether it
  passed. Local, gitignored, read by the hook.

## Writing `.claude/verification.yaml`

Run the `define-verification` skill. It asks what proves a change here
works — build, test, lint, and any deploy/runtime check — and writes this
file for you. Don't hand-write it from scratch unless you're comfortable with
the format below; the skill exists so you don't have to.

## The YAML format

A list of steps, each a mapping:

| Field | Required | Meaning |
|---|---|---|
| `name` | always | Short, human-readable. Identifies the step in the result file on failure. Must be the step's first key. |
| `type` | always | One of `run`, `poll`, `cleanup`. |
| `command` | always | A shell command string, run with `bash -c`. Plain scalar, or a `\|` block scalar for multiple lines. |
| `interval_seconds` | `poll` only | How often to retry `command`. |
| `timeout_seconds` | `poll` only | How long to keep retrying before giving up. |

Step semantics:

- **`run`** — one-shot. Must exit `0`. A non-zero exit fails the whole
  workflow and skips straight to the `cleanup` steps.
- **`poll`** — retries `command` every `interval_seconds` until it exits `0`.
  If `timeout_seconds` elapses first, that's a failure — same as a failed
  `run` step, skip to `cleanup`. Use this for anything that isn't a one-shot
  check: waiting for CI checks to go green, waiting for a deployment to
  report synced and healthy at a specific revision, and so on.
- **`cleanup`** — always runs, regardless of whether the `run`/`poll` steps
  passed, failed, or timed out — the same idea as a shell `trap ... EXIT`.
  All `cleanup` steps run, in the order they're declared, after the
  `run`/`poll` steps finish, regardless of where they sit in the file. Use
  this for anything that must be undone no matter what: reverting a patched
  Kubernetes/ArgoCD resource back to its original value, tearing down a
  scratch environment, deleting a temporary branch.

  A `cleanup` step's own exit code is logged but does **not** flip the
  recorded `passed` result — cleanup is teardown, not a correctness check.
  If a cleanup step fails, later cleanup steps still run.

Supported YAML is a deliberately restricted subset, parsed by a small
dependency-free script rather than a full YAML library:

- Top level is a list; each item starts with `- name: <value>`.
- `type`, `command`, `interval_seconds`, `timeout_seconds` are indented
  under `name`, in any order.
- `command` is either a plain scalar on the same line, or introduced with
  `|` (or `|-`) for a multi-line block, indented under it.
- Plain scalars may be bare, `'single'`, or `"double"` quoted.
- Comments (`# ...`) are only recognized on their own line — not trailing
  after a value, since `#` can legitimately appear inside a command (URLs,
  jsonpath expressions, etc.).
- No anchors, aliases, flow collections (`{}`/`[]`), or nested mappings
  beyond this shape.

### Illustrative example

Not a real recipe — just the shape, echoing the two cases that motivated
having `poll` and `cleanup` at all (a CI-check wait, and an ArgoCD-style
deploy-then-always-revert):

```yaml
- name: build and unit test
  type: run
  command: make test

- name: wait for CI checks
  type: poll
  command: gh pr checks --json state -q 'all(.[]; .state == "SUCCESS")' 2>/dev/null
  interval_seconds: 30
  timeout_seconds: 1800

- name: point review app at this revision
  type: run
  command: kubectl patch application my-app --type merge -p '{"spec":{"source":{"targetRevision":"'"$(git rev-parse HEAD)"'"}}}'

- name: wait for synced and healthy at this revision
  type: poll
  command: |
    kubectl get application my-app -o json | \
      jq -e --arg sha "$(git rev-parse HEAD)" \
        '.status.sync.revision == $sha and .status.sync.status == "Synced" and .status.health.status == "Healthy"'
  interval_seconds: 15
  timeout_seconds: 600

- name: smoke test the live endpoint
  type: run
  command: curl -fsS https://my-app.review.example.com/healthz

- name: revert the review app to its original revision
  type: cleanup
  command: kubectl patch application my-app --type merge -p '{"spec":{"source":{"targetRevision":"main"}}}'
```

## The result file

`.claude/.verification-result.json`, in the consuming project, written by the
runner on every run, never committed (it belongs in that project's
`.gitignore`):

```json
{"sha": "<git rev-parse HEAD at run time>", "timestamp": "<UTC ISO-8601>", "passed": true}
```

or, on failure:

```json
{
  "sha": "<git rev-parse HEAD at run time>",
  "timestamp": "<UTC ISO-8601>",
  "passed": false,
  "failed_step": "<the step's name>",
  "output": "<that step's captured stdout+stderr>"
}
```

## The gate

This plugin's `hooks/require-verification.sh`, wired to `Stop` and to
`PreToolUse` on `Bash` calls shaped like `gh pr create`, blocks unless **all**
of:

1. `.claude/.verification-result.json` exists in the consuming project.
2. its `sha` equals the current `git rev-parse HEAD`.
3. `git status --porcelain` is empty (a dirty tree means the recorded pass
   predates uncommitted changes, so it's stale).
4. its `passed` is `true`.

If the consuming project has no `.claude/verification.yaml` yet, the hook
allows unconditionally instead — there's nothing declared yet to run or gate
against. Write it with the `define-verification` skill to turn the gate on.

When blocked, the reason names which condition failed and, if the last run
actually failed, the `failed_step` and its captured `output` — concrete
signal to act on, not just "try again." Run
`"$CLAUDE_PLUGIN_ROOT"/hooks/run-verification.sh` to produce a fresh result.
