<!-- STATUS: BLOCKED goes here, followed by the questions, if the doc cannot be completed -->
# Browser Testing Document: <feature name> (<KEY>)

<1–3 lines: which screens and flow, and the route(s).>

## Environment / pre-conditions
- App: closio-web-v2 on branch `<branch>`, `http://localhost:5173/`
- Backend: <chosen at run time: local ws1 | dev proxy | staging proxy | mocks>
- User: <role or permissions needed; partner/business (B1/B2)>. The user logs in themselves; no credentials here.
- Feature flags: <VITE_ENABLE_… = true>
- Data: <what must exist; seed and cleanup SQL below, or "existing dev data: <what>">

## Seed data (only if needed)
```sql
-- PRE-CHECK / SEED / CLEANUP
```

## Cases
### UI1 [FLOW] <title> (node F1 → F2)
- Pre-conditions: <>
- Steps:
  1. Open menu "<label>" → "<label>".
  2. Click "<button label>".
- Expected:
  - <visible text, verbatim> [figma: F1]
  - <element state / table values / route> [AC2]

### UI2 [STATE] …

Counts: FLOW <n> · STATE <n> · VALID <n> · PERM <n> · DATA <n> · NAV <n> (budget: ≤ 15, or ≤ 25 for a multi-screen flow)
<Over budget: UI<n>: reason, one line per extra case. Omit if within budget.>

## AC × case
| AC | Cases |
|---|---|

## Changes
| Date | Case | Change | Reason (source) |
|---|---|---|---|
