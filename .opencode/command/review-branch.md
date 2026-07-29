---
description: Staff engineer code review of current branch vs base (default=main)
---

Perform a comprehensive staff engineer code review.

## Configuration

- **Base branch argument**: "$ARGUMENTS"
- **Current branch**: !`git rev-parse --abbrev-ref HEAD`

If the base branch argument above is empty, use "main" as the default base branch.

## Base Ref Resolution

Resolve a usable base ref before running any diffs:

1. Try the base argument (or default `main`) as-is.
2. If that ref does not exist and it does not start with `origin/`, try `origin/<base>`.
3. If neither ref exists, stop and return a clear error explaining which refs were attempted.

Use the resolved value as `<resolved-base>` in all commands below.

## Branch Diff Stats

First, run `git diff <resolved-base>...HEAD --stat` using the resolved base ref.

## Changed Files

Run `git diff <resolved-base>...HEAD --name-only` to list changed files.

## Review Process

Create one shared diff file in a repo-local temp directory (gitignored):

- **Diff directory**: `tmp/opencode/review-branch/`
- **Diff file**: `tmp/opencode/review-branch/<branch-name>-<YYYY-MM-DD-HHMMSS>.diff`

Generate the shared diff once using the resolved base ref:

`mkdir -p tmp/opencode/review-branch`

`git diff <resolved-base>...HEAD -- . ':(exclude).opencode/**' ':(exclude)**/PLAN.md' ':(exclude)**/PROGRESS.md' > <diff-file>`

Run the following seven reviews IN PARALLEL using subagents, providing `<diff-file>` to each one:

1. @security-sentinel - Analyze for security vulnerabilities
2. @performance-oracle - Analyze for performance issues
3. @architecture-strategist - Analyze architecture and boundaries
4. @pattern-recognition-specialist - Analyze design patterns and anti-patterns
5. @typescript-reviewer - Analyze TypeScript quality and maintainability
6. @code-simplicity-reviewer - Analyze simplicity and YAGNI violations
7. @react-reviewer - Analyze React patterns using the React best-practices skill

For each subagent:

- Read the diff from `<diff-file>`.
- Do NOT use `/tmp` or other system temp locations.
- Return only actionable findings.

When collecting subagent results, keep only actionable findings that require a fix or explicit risk acceptance. Exclude informational or pass-only items (for example: `[info]`, `INFO`, `no issue`, `no findings`, validation-only confirmations).

## Final Output

After all seven subagent reviews complete, include only actionable findings into a single file. Create the `.opencode/reviews/` directory if it doesn't exist, then save the review to `.opencode/reviews/<branch-name>-<YYYY-MM-DD-HHMMSS>.md` with this structure:

Each finding should include:

1. A description of the issue with location (file:line)
2. A **Recommended Remediation** section with a concrete fix or code suggestion
3. Two markdown list checkboxes on separate lines:

```
   - [ ] Plan to fix
   - [ ] Fixed
```

If a section has no actionable findings, write `No actionable findings.` for that section.

```markdown
# Code Review: <branch-name>

**Reviewed**: <timestamp> **Base**: <resolved-base> **Files Changed**: <count>

## Summary

<2-3 sentence overview of the changes and overall assessment>

## Detailed Findings

### Security

<findings from security-sentinel subagent>

### Performance

<findings from performance-oracle subagent>

### Architecture

<findings from architecture-strategist subagent>

### Patterns & Anti-Patterns

<findings from pattern-recognition-specialist subagent>

### TypeScript Quality

<findings from typescript-reviewer subagent>

### Simplicity & YAGNI

<findings from code-simplicity-reviewer subagent>

### React

<findings from react-reviewer subagent>
```
