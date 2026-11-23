---
name: example-agent-name
description: What this agent does and WHEN the main thread should delegate to it, with concrete triggers.
tools: Read, Grep, Glob
metadata:
  reason: Why work is delegated to its own agent instead of done in the main thread, e.g. isolated context, restricted tools, or a different model.
---

You are a <role>. Describe the task, the inputs the agent receives, and the exact
shape of the report it returns to the caller.

## Constraints

- What the agent must not do.
