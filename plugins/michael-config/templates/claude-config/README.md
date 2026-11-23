# Claude Code config templates

Starting points for a new skill, rule, agent, command or hook. Each template carries
the same `metadata` block (a header comment for hooks, which have no frontmatter) so
every config records **why it exists** and **how to tell whether it works**. That is
what makes it possible to review it later and keep, fix or delete it on evidence.

| To add a | Copy | To |
| --- | --- | --- |
| skill | `skill/SKILL.md` | `skills/<name>/SKILL.md` |
| rule | `rule.md` | `rules/<name>.md` |
| agent | `agent.md` | `agents/<name>.md` |
| command | `command.md` | `commands/<name>.md` |
| hook | `hook.sh` | `hooks/<name>.sh`, then register it in `hooks/hooks.json` or `settings.json` |

## The metadata block

| Field | What to write |
| --- | --- |
| `reason` | The problem or repeated mistake this prevents. Not what it contains. |
| `evidence` | Where the problem was seen: a PR, issue or session link, or how often it happened. |
| `success_criteria` | An observable signal that it works. Something you could check later. |
| `created` | `YYYY-MM-DD`. |
| `review_by` | `YYYY-MM-DD`, usually 1-3 months out. |
| `status` | `active`, or `deprecated` once replaced (keep the file only while something still references it). |

Skills use the `metadata` map that the Agent Skills format provides for custom keys.
The other types reuse the same key so one search covers all of them. Claude Code
ignores keys it does not know; run `claude plugin validate` on the plugin after adding
one to confirm.

## Choosing the type

- It must hold even if Claude forgets: a **hook**.
- It applies on most turns, or to files matching a path: a **rule** (loaded every time, so keep it short).
- It is guidance for a kind of task, loaded when relevant: a **skill**.
- It runs only when the user types it: a **command**.
- It needs its own context, tools or model: an **agent**.

If a rule is long or only matters for one task, make it a skill.

## Reviewing

On or after `review_by`, check `success_criteria` against the `evidence`. Then:

- **Keep** it and set a new `review_by` if the signal shows it works.
- **Revise** it if the problem persists, because the wording or trigger is wrong.
- **Delete** it if the problem stopped without it or it never triggers. An unused config
  still costs context and misleads.

To list what is due, search for the dates: `grep -rn "review_by:" plugins/`.
