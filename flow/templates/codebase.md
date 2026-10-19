# Codebase: <KEY>

Scouted: <YYYY-MM-DD> in <host tool>. Scope: <backend | frontend | fullstack>

## Repos
| Service | Path | Current branch | Why in scope | Conventions read |
|---|---|---|---|---|

## Intake
| Service | Conventions read | Repo lessons applied | completed.md entries used |
|---|---|---|---|

Workflow lessons applied: <[lesson: …] or "none relevant">

## Existing work on this ticket
- <service>: branch `<name>` / commits `<sha> <msg>` touching <files>, or "none found"

## Sibling (mandatory)
- <service>: <feature> (why it's the closest: same business, same layer, same shape)
- Backend chain: route `<path:line>` → controller `<path:line>` → service `<path:line>` → errors `<path:line>` → tests `<path>`
- Frontend chain: route `<path:line>` → view `<path>` → components `<…>` → API `<path:line>` → mock `<path:line>` → types `<path>` → tests `<path>`
- Behaviours it defines: sort <>, pagination <>, loading/empty/error <>, actions <>, validation <>, errors <>

## Reusable inventory
| Need | Existing piece | Path | Source (completed.md / search) | Fit (as is / configure / extend / none) |
|---|---|---|---|---|

Absence evidence (for every "none"): <need>: grep `<terms>` in `<dirs>`; completed.md checked: <result>

## Key facts
- <fact> [code: <service>:<path>:<line>]

## Code map
### <service>
- Routes: <path:line, ...>
- Validation: <>
- Errors: catalogue `<path>`, HTTP mapping `<path:line>`
- Data: models `<>`, migrations `<>`, constraints `<>`
- Transactions / locking: <>
- Scoping / auth: <>
- Tests: <paths>, fixtures `<>`

## Question triage
| OQ | Outcome | Evidence |
|---|---|---|
| OQ1 | code fact → RC1 / convention → RC2 / contradiction / siblings disagree / business-only | [code: …] |

## Files read
- <service>:<path>
