<!-- STATUS: BLOCKED goes here, followed by the questions, if the plan cannot be completed -->
# Backend plan: <KEY>

## Summary
<2–4 lines>

## Services (implementation order)
1. <service>: <why> [cite]

## Conventions applied
- <service>: <rule> [code: <service>:CLAUDE.md]

## Reuse table
| Need | Existing piece (path) | How | Mirrors (sibling path:lines) |
|---|---|---|---|
| | | as is / configure: <props> / extend: <what> / new: <searches> | |

## Deviations from sibling
- <none | what differs, why, source [AC/Q/doc]>

## API contract (3-Tier Spec)
### <METHOD> <path via ws1closio> → <METHOD> <path on ws2 service>
- **Tier 1 (ws2 Microservice)**: path, headers (`X-Partner-Id`, `X-User-Id`), validation schema, internal Sequelize response shape [cite]
- **Tier 2 (ws1closio Gateway)**: proxy route, session extraction (`req.session.closioData`), explicit header building, `asyncHandler`, i18n namespace keys, error mapping (`404` → `597` with original status in `details.upstream_status`) [cite]
- **Tier 3 (Client Envelope)**: JSON contract structure consumed by clients [cite]
- Backward compatible: <yes/no, why>

## Data & Performance Audit
- **Schema & Migrations**: <table/column/index>, migration `<service>:<path> (new)`, up/down, backfill [cite]
- **Security & Scoping**: `partner_id` scoping verified on all queries [cite]
- **Performance Checklist**: N+1 query check (using `pgDbUtils` or eager includes) [cite]

## Tasks
### <service>
1. <task>. Files: `<service>:<path>` (<new | modify>). Mirrors: `<service>:<sibling file:lines>`. Reuses: <inventory items> [cite]

## Async / config / flags
- <queues, crons, env var names, feature flags or "none">

## Tests
- <test file path>: <cases> → AC<n>

## AC coverage
| AC | Tasks | Tests |
|---|---|---|

## Risks and notes
- <>

## Plan changelog
<!-- After approval, the plan stays live until the ticket is implemented. Every later change gets a row; approved content is never silently rewritten. -->
| Date | Change | Reason (Q<n> / RC<n> / finding) | Re-approved |
|---|---|---|---|

## Files opened
- <service>:<path>
