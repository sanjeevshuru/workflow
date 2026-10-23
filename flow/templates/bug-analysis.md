<!-- STATUS: BLOCKED goes here, followed by the questions, if the analysis cannot be completed -->
# Bug analysis: <KEY>

- Scope: <backend | frontend | fullstack> · repos: <...>
- Related ticket: <ORIG, run at runs/<ORIG>/ | none found>
- Root cause: <confirmed | likely | unconfirmed>

## Summary
<2–3 lines: what's wrong, where, why>

## Expected behaviour
- <expected> [AC1] [AC of <ORIG> | Q<n> | src: … | convention: <sibling path:lines>]

## Reproduction
### Trace
1. <user action or request> → `<service>:<path>:<line>`: <what happens>
2. …
n. **Here the result goes wrong**: `<service>:<path>:<line>`: <what the code does vs what it should>

### Requests / steps for verification
- `<METHOD> <ws1 path>` body `<…>` → today: `<status, body/error_code>`; expected: `<…>` [AC<n>]
- Browser: <page path> → <visible labels, in order> → today: <…>; expected: <…>

### Live check
- <none needed | what would confirm a "likely" cause: query, request or log line>
- Live result: <not run | date, what happened, run by orchestrator>

## Root cause
<what's wrong and why, cited>

## Introduced by
- <hash, subject, date, ticket / MR | not found: commands run>

## Existing work on this bug
- <branches, commits | none: commands run>

## Blast radius
| Location | Same defect? | In this fix? |
|---|---|---|
| `<service>:<path>:<line>` | yes / no / unsure | yes / follow-up / Q<n> |

Searches: <grep terms, directories>

## Fix plan
### Options
<only if more than one fix is reasonable: each with trade-offs; none marked recommended without a source>

### Contract and data changes
- <none | response field / error_code / migration / data fix for existing rows, each cited>

### Tasks
#### <repo>
1. <task>. Files: `<repo>:<path>` (<new | modify>). Mirrors: `<sibling or convention path:lines>`. Serves: AC<n> [cite]

### Tests
- `<spec path>`: <case> → AC<n>. Fails today because: <reason>

### AC coverage
| AC | Tasks | Tests |
|---|---|---|

## Follow-ups (not in this fix)
- <>

## Open questions
| id | Question | Why it matters | Options | Checked in code |
|---|---|---|---|---|

## Plan changelog
<!-- After Gate B the fix plan stays live. Every later change gets a row; approved content is never silently rewritten. -->
| Date | Change | Reason (Q<n> / finding / QA reopen round) | Re-approved |
|---|---|---|---|

## Files opened
- <repo>:<path>

<!-- On a QA reopen, append: "## Round <n>: <date>" with what the earlier fix missed and why, then the new trace, root cause and fix plan rows. -->
