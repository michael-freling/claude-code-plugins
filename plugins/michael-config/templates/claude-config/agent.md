---
name: example-agent-name
description: What this agent does and WHEN the main thread should delegate to it, with concrete triggers.
tools: Read, Grep, Glob
metadata:
  reason: Why work is delegated to its own agent instead of done in the main thread, e.g. isolated context, restricted tools, or a different model.
  evidence: Where the need was observed - a PR, issue, or session link.
  success_criteria: The observable signal that delegating helps, e.g. "reviews catch X without the main thread reading the whole diff".
  created: YYYY-MM-DD
  review_by: YYYY-MM-DD
  status: active
---

You are a <role>. Describe the task, the inputs the agent receives, and the exact
shape of the report it returns to the caller.

## Constraints

- What the agent must not do.
