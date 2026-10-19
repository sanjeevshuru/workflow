<!-- STATUS: DONE | BLOCKED (questions below) -->
# Deploy to dev: <KEY> (backend)

<one or two lines: what this ticket changes, in plain words>

| Repo | MR | Branch | Pushed commit |
|---|---|---|---|
| <service> | <url> | `<branch>` | `<hash>` |

## 1. Before you deploy
- [ ] The MRs above are merged into `develop`.
- [ ] <dependency on another ticket or schema task, e.g. "SCRUM-xxx (ar_ageing tables) is deployed to dev first", or "none">
- [ ] <new npm dependency: none | `<package>@<version>` in <service> (installed by the image build)>

## 2. Config / env vars
<!-- "None." if the ticket adds none. Names only; never values. -->
| Name | Service | What it's for | Required | Example (`.env.example`) | Value |
|---|---|---|---|---|---|
| `<NAME>` | <service> | <> | yes / no (default <>) | <non-secret example or "none"> | set by deployer |

## 3. Database
<!-- "No migrations." if none. -->
Run in **<service>** after its code is deployed: `npm run migrate`

| # | Migration | What it does | Reversible |
|---|---|---|---|
| 1 | `<file>` | <creates table / adds column / adds constraint …> | yes / no: <what to do instead> |

- Seeds: <none | `npm run seed` in <service>: <what it inserts>>
- Watch out: <locks, long backfill, existing data that could violate a new constraint, or "nothing special">

## 4. Deploy (in this order)
1. **<ws2 service>**: deploy, then run the migrations (section 3). Restart: <`api` | `api`, `worker` | …> <(new queue/worker/cron: …)>
2. **ws1closio**: deploy. <new or changed routes: …>

How to deploy on dev: <from config/deployment.md, or "TODO: ask <owner>">

## 5. Verify on dev
Base URLs: <ws2 dev URL>, <ws1 dev URL> (from `config/deployment.md`)

| # | Request | Headers (names) | Expect |
|---|---|---|---|
| 1 | `POST <ws2 path>` with <short body> | `x-client-id`, `x-client-secret`, `X-Partner-Id` | `201`, <key fields> |
| 2 | `POST <ws1 path>` (same body) | session cookie, `X-Secure-Transmission-Type` | `201` |
| 3 | <the most telling error> | | `<status>` `<error_code>` |

Logs to watch: <service / RUN_MODE deployment, and the log line or error to look for>

## 6. Rollback
1. Redeploy the previous image of <ws1closio first, then the ws2 service> (reverse order).
2. In <service>: `npm run migrate:undo` <n> times, newest first: `<file n>`, …, `<file 1>`. <or the non-reversible note>
3. <anything else, e.g. remove data created by seeds>

## Open items
- <deferred decisions, known gaps from the reports, `TODO: ask` lines, notes for staging or prod later; or "none">

## Questions (only if BLOCKED)
- <question, why it matters>

<details><summary>Sources</summary>

- <deployment-facts.md § <repo>>, <backend-plan.md § …>, <postman/collection.json folder …>, <config/deployment.md row …>
</details>
