# Local run and test settings (Postman and browser tests)

Used by `flow/playbooks/postman.md` and `flow/playbooks/browser-test.md`. Tests run against **local services on the feature branch**, using the DB and Redis that each repo's own `.env` points to (usually the shared dev DB).

Never read or print `.env` values. Only the variable **names** below are used.

## Services when running locally
| Service | Start (in the repo) | Default PORT | Path prefix | Run with override |
|---|---|---|---|---|
| ws1closio | `npm run dev` | 3000 | none: routes at `/api/...` (`src/app.js:88` mounts at root; confirmed 2026-10-23, SCRUM-530) | `WS2*_BASE_URL` → local ws2 (see below); local Redis (see Infra) |
| ws2closio | `npm run dev` | 3002 | none: routes at `/api/...` (`APP_PATH_PREFIX` only names log files; confirmed 2026-10-22, SCRUM-529) | none |
| ws2targetsales | `RUN_MODE=api npm run dev` | 3001 | `/ws2targetsales` | `PORT=3011` if another 3001 service runs |
| ws2notification | `RUN_MODE=api npm run dev` | 3001 | `/ws2notification` | `PORT=3012` if another 3001 service runs |
| ws2pricingengine | `npm run dev` | 3001 | `/ws2pricingengine` | `PORT=3013` if another 3001 service runs |
| closio-web-v2 | see `browser-test.md` | 3000 (`VITE_PORT`) | n/a | `VITE_PORT=5173` (3000 clashes with ws1) |

- The prefixes and ports come from each repo's `.env` variable names (`PORT`, `APP_PATH_PREFIX`). If a value turns out different on first run, correct this table and note it in `status.md`.
- **Overrides go in the process environment of the start command** (e.g. `PORT=3011 RUN_MODE=api npm run dev`). Never edit `.env`.
- **ws1 → local ws2**: start ws1 with the matching upstream variable pointing at the local ws2, e.g. `WS2TARGETSALES_BASE_URL=http://localhost:3011/ws2targetsales`. The upstream variable names are `WS2CLOSIO_BASE_URL`, `WS2TARGETSALES_BASE_URL`, `WS2NOTIF_BASE_URL` / `WS2NOTIFICATIONS_BASE_URL` and `WS2PRICINGENGINE_BASE_URL`. Check how ws1 builds the URL from the variable (`nodejs-ws1closio:src/utils/axiosInstances.js`) before the first run, so the path prefix isn't doubled.
- **Readiness**: there is no shared health route. A service is up when an HTTP request to `http://localhost:<port><prefix>/` gets any HTTP status, e.g. `curl -s -o /dev/null -w '%{http_code}' …`. Wait up to 60 s, then show the last 30 log lines and ask.
- **Infra**: ws1 needs Redis (sessions). Before the first local ws1 run, check that ws1 can reach Redis (its log shows `Redis Client …: Connected`, not `connect ETIMEDOUT`). The committed ws1 code always connects with `rediss://` to the `.env` host; if that's unreachable, ask the user how they run Redis locally (e.g. their own local-Redis tweaks plus `REDIS_HOST=localhost REDIS_PORT=6379` in the process env). Never commit such tweaks. ws2 services need Postgres; ws2closio also needs Redis and Oracle, and ws2targetsales needs Redis/BullMQ. If a service can't start because a dependency is unreachable, stop and ask. Don't fake it.

## Auth
| Layer | Headers / cookie | Collection variables |
|---|---|---|
| ws2 direct | `x-client-id`, `x-client-secret` (must match an entry in that service's `SERVICE_CREDENTIALS` / client-id config), `X-Partner-Id`, `X-User-Id` where the route needs it | `client_id`, `client_secret`, `partner_id`, `user_id` |
| ws1 proxy | Session cookie `closio_session_local` (name from `SESSION_NAME`), plus `X-Secure-Transmission-Type: x` on **every** request (dev only), optional `Accept-Language` | `ws1_session_cookie`, `partner_id` |

- **Secrets come from the user's shell, by name only:**
  - `AIFLOW_WS2_CLIENT_ID`, `AIFLOW_WS2_CLIENT_SECRET`: the ws2 service credentials
  - `AIFLOW_WS1_SESSION_COOKIE`: the user logs in locally (web login + OTP) and copies the cookie value
  - `AIFLOW_PARTNER_ID`, `AIFLOW_USER_ID`: not secret, but test-account specific. The partner must equal the session's `closioV1Data.partnerId`, otherwise every ws1 call returns 404 → 597.

  They are passed to newman with `--env-var name=$VAR`, and never written to any file.
- **The ws1 session is rolling**: newman resends the cookie even when a case leaves it out. "No session" cases must clear the cookie jar for that URL in a pre-request script (`pm.cookies.jar().clear(pm.variables.replaceIn(url))`) [lesson source: `nodejs-ws2targetsales:lessons.md`].
- **ws1 rewrites every 404 to 597**, with the original status in `details.upstream_status`. Bubbled ws2 errors get a re-translated top-level `message`, with the original body under `details.upstream_*`. Assert on those, not on byte-identical passthrough.

## Test data (seed and cleanup)
Write cases may seed and clean up data in the DB the local services use, **with safeguards**:
1. **Pre-check query first**: it must return 0 rows for the planned fixtures (unique ids, periods, constraints such as active-overlap `EXCLUDE`s). If not, pick other values.
2. **Fixtures are unmistakable**: far-future periods (e.g. year 2035+), fixed UUIDs with a ticket prefix (e.g. `a5190000-…` for SCRUM-519), names prefixed `AIFLOW <KEY>`.
3. **Show the pre-check, seed and cleanup SQL to the user** and run them only on an explicit yes. Use the user's DB client or `psql` with connection settings the user provides in their own shell. The workflow never reads `.env` to build a connection string.
4. **Cleanup always runs**, even after a failed or aborted newman run, and data created by the API itself (POST cases) is cleaned up too: cleanup deletes by the fixture prefix or the ids captured in the run.
5. If a run is interrupted before cleanup, record "cleanup pending" in `status.md` → Notes and run it first on resume.

## Runner
- `npx newman` (not installed globally; ask before the first install). Use `newman-reporter-htmlextra` only if it's already available. Otherwise use the `cli` and `json` reporters.
- If newman can't be used at all, use the curl fallback in `flow/playbooks/postman.md`.
