<!-- STATUS: BLOCKED goes here, followed by the questions, if the doc cannot be completed -->
# Postman Testing Document: <feature name> (<KEY>)

<1–3 lines: which endpoints, implemented in which ws2 service, proxied by ws1closio at which path.>

## Environment / pre-conditions
| Layer | Base URL variable | Local value | Auth |
|---|---|---|---|
| <ws2 service> (direct) | `{{ws2_base_url}}` | `http://localhost:<port>/<prefix>` | `x-client-id: {{client_id}}`, `x-client-secret: {{client_secret}}`, `X-Partner-Id: {{partner_id}}`<, `X-User-Id: {{user_id}}`> |
| ws1closio (proxy) | `{{ws1_base_url}}` | `http://localhost:3000/ws1closio` | session cookie `closio_session_local` = `{{ws1_session_cookie}}` (its partner must equal `{{partner_id}}`), `X-Secure-Transmission-Type: x` |

- Secrets are supplied at run time from the shell: `AIFLOW_WS2_CLIENT_ID`, `AIFLOW_WS2_CLIENT_SECRET`, `AIFLOW_WS1_SESSION_COOKIE`, `AIFLOW_PARTNER_ID`, `AIFLOW_USER_ID`. They're never stored here.
- Services: <start commands with overrides, from config/postman.md>
- Migrations needed before the run: <none | list>

## Seed data
> Run the pre-check first. It must return 0 rows.

```sql
-- PRE-CHECK
```
```sql
-- SEED (also in seed.sql)
BEGIN;
COMMIT;
```
```sql
-- CLEANUP (also in cleanup.sql): always run, deletes fixtures and anything the run created
```

## Cases
| TC | Cat | Layer | Request | Expected status | error_code / key assertions | Source |
|---|---|---|---|---|---|---|
| TC1 | POS | ws2 | `GET {{ws2_base_url}}/api/…` | 200 | <fields> | [AC1] [backend-plan: Tier 1] |
| TC2 | NEG | ws1 | `GET {{ws1_base_url}}/api/…/<unknown id>` | 597 | `details.upstream_status: 404` | [backend-plan: Tier 2] |

Counts: POS <n> · NEG <n> · EDGE <n> · ws2 <n> · ws1 <n> (budget per endpoint: ws2 ≤ 12, ws1 ≤ 5)
<Over budget: TC<n>: reason, one line per extra case. Omit if within budget.>

### Coverage check
| AC / error_code | Postman TC | or unit test (`spec → test`) |
|---|---|---|

## Run
```bash
npx newman run runs/<KEY>/postman/collection.json -e runs/<KEY>/postman/environment.json \
  --env-var "client_id=$AIFLOW_WS2_CLIENT_ID" --env-var "client_secret=$AIFLOW_WS2_CLIENT_SECRET" \
  --env-var "ws1_session_cookie=$AIFLOW_WS1_SESSION_COOKIE" \
  --env-var "partner_id=$AIFLOW_PARTNER_ID" --env-var "user_id=$AIFLOW_USER_ID" \
  --folder "1 · ws2 direct" --folder "2 · ws1 proxy"
```
Folder order: <…>

## Changes
| Date | Case | Change | Reason (source) |
|---|---|---|---|
