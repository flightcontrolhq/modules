---
description: Comprehensive planning for complex features. Result is kanban of ai tasks.
---

Your task is come up with a comprehensive plan for this project:

# Project

$ARGUMENTS

# Instructions

1. Use the @research subagent to analyze the current state of the relevant codebase. Pass along relevant documentation files and information. Do not ask for suggested changes.
2. Write all that information to <repo_root>/.opencode/plans/PLAN.md
3. Make a comprehensive plan of all changes needed, broken down by isolated tasks. Make sure to cover frontend, backend, UI, functionality, and any background processing.
4. Save all tasks in the PLAN.md with a todo/done checkbox for progress tracking
5. Update each task with a) tests that should be added and b) acceptance criteria

# Notes

- When faced with a key decision, use your best judgement to decide, then document the question, the options, and your reasoning as a numbered decision, all in the PLAN.md.
- Do not give timeline estimates
