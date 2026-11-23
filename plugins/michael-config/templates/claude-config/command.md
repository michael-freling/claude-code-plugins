---
description: One line shown in the slash-command menu saying what the command does.
argument-hint: "[argument]"
metadata:
  reason: The workflow this packages and why it is a command instead of a skill, i.e. it should only run when the user types it.
  evidence: Where the need was observed - a PR, issue, or session link, or how often the steps are repeated by hand.
  success_criteria: The observable signal that it is used and works, e.g. "used at least weekly and the output needs no rework".
  created: YYYY-MM-DD
  review_by: YYYY-MM-DD
  status: active
---

The prompt that runs when the user types the command. Use `$ARGUMENTS` for what they
passed after the command name.
