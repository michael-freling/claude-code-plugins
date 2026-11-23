---
name: example-skill-name
description: What this skill covers and WHEN Claude should load it, with concrete triggers (task types, file types, commands). This is the only text Claude sees when deciding to load it, so make the trigger specific.
metadata:
  reason: The problem or repeated mistake this exists to prevent, in one or two sentences. Say what went wrong without it, not what the skill contains.
---

# Example skill title

Guidance Claude follows once the skill is loaded. Write instructions, not history:
put the reason in `metadata.reason` and keep only the rule here.

## When to use

- The situation that triggers this skill, restated more precisely than the description.

## What to do

1. The steps or rules, in the order they apply.

## What not to do

- The mistakes this skill exists to prevent.
