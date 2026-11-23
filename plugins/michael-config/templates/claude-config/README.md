# Claude Code config templates

Starting points for a new skill, rule, agent, command or hook. Each template has a
`metadata.reason` field (a header comment for hooks, which have no frontmatter) saying
**why the config was created**, so a later review can judge whether it is still needed.

| To add a | Copy | To |
| --- | --- | --- |
| skill | `skill/SKILL.md` | `skills/<name>/SKILL.md` |
| rule | `rule.md` | `rules/<name>.md` |
| agent | `agent.md` | `agents/<name>.md` |
| command | `command.md` | `commands/<name>.md` |
| hook | `hook.sh` | `hooks/<name>.sh`, then register it in `hooks/hooks.json` or `settings.json` |

## `reason`

The problem or repeated mistake the config prevents, in one or two sentences. Say what
went wrong without it, not what it contains. Nothing else is recorded: the date and
author are in git history, and the PR that added the file is the place for evidence.

Skills use the `metadata` map that the Agent Skills format provides for custom keys.
The other types reuse the same key so one search covers all of them. Claude Code
ignores keys it does not know. The templates live under `templates/`, which
`claude plugin validate` does not scan, so run it again once a config is copied into
`skills/`, `rules/`, `agents/` or `commands/`.

## Choosing the type

- It must hold even if Claude forgets: a **hook**.
- It applies on most turns, or to files matching a path: a **rule** (loaded every time, so keep it short).
- It is guidance for a kind of task, loaded when relevant: a **skill**.
- It runs only when the user types it: a **command**.
- It needs its own context, tools or model: an **agent**.

If a rule is long or only matters for one task, make it a skill.

## Reviewing

To review a config, read its `reason` and ask whether that problem still happens. If it
does not, or the config never triggers, delete it: an unused config costs context and
misleads. List every reason with `grep -rn "reason:" plugins/`.
