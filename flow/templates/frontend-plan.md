<!-- STATUS: BLOCKED goes here, followed by the questions, if the plan cannot be completed -->
# Frontend plan: <KEY> (closio-web-v2)

## Summary
<2–4 lines. Say if designs came from exports instead of the Figma MCP.>

## Conventions applied
- <rule> [code: closio-web-v2:.claude/CLAUDE.md]

## Reuse table and design-system mapping
| Figma Node / Layer | Identified UI Element | Matched Reusable Component (path) | How | Props / Slots / Pinia State / Validation |
|---|---|---|---|---|
| | | | as is / configure: <props> / extend: <what> / new: <searches> | |

## Deviations from sibling
- <none | what differs, why, source [AC/Q/doc]>

## Flow
| Step | Node | Route / component | Enters from | Leaves to (on action) | State passed |
|---|---|---|---|---|---|
| 1 | F1 | `/orders` → `closio-web-v2:src/...` | menu | F2 on row click | orderId |

## Nodes
### F1: <frame name> ([figma](<link>), notes: `runs/<KEY>/figma/<nodeId>.md`)
- Route / file: `closio-web-v2:<path>` (<new | modify>)
- Reuses: <existing component> [code: ...] | New: <component> (reason)
- Data / API: <call> [backend-plan: API contract | code: ...]
- States: empty <>, loading <>, error <>, success <>
- Validation and messages: "<verbatim text>" [figma: F1]
- Permissions: <> [cite]

## API usage
| Call | Used by | Contract source |
|---|---|---|

## Feature flags / i18n / mocks
- <>

## Tasks
1. <task>. Files: `closio-web-v2:<path>` (<new | modify>). Mirrors: `<sibling file:lines>`. Reuses: <inventory items> [cite]

## Tests
- <spec path>: <cases> → AC<n>

## AC × node matrix
| AC | F1 | F2 | F3 | Tests |
|---|---|---|---|---|

## Risks and notes
- <>

## Plan changelog
<!-- After approval, the plan stays live until the ticket is implemented. Every later change gets a row; approved content is never silently rewritten. -->
| Date | Change | Reason (Q<n> / RC<n> / finding) | Re-approved |
|---|---|---|---|

## Files opened
- closio-web-v2:<path>

## Figma calls made
- <n> total: <breakdown>
