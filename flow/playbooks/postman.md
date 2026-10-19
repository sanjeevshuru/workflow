# Playbook: Postman testing doc, collection and run (step 03, backend)

Two parts:
- **Generate**: role `api-tester`, writes files only.
- **Run**: the orchestrator, because it needs the user for secrets, seed approval and service start-up.

All artefacts live in `runs/<KEY>/postman/`. They are never committed to the service repos. Settings are in `config/postman.md`.

The format follows the team's Postman testing documents:
- `nodejs-ws2targetsales:AGENTS.md` §9
- `nodejs-ws2targetsales:project_docs/Postman Testing Document - Payout Config Detail API.md`
- `nodejs-ws2targetsales:project_docs/postman/SCRUM-495 Payout Config Detail.postman_collection.json`

Read the example doc and collection before writing the first case.

## Part 1: Generate (api-tester)

### 1. List the endpoints
From `backend-plan.md` → API contract (3-Tier Spec), list every endpoint added or changed. For each one, take:
- method + path, from Tier 1 (ws2) and Tier 2 (ws1)
- the headers and auth
- the request schema, required fields and limits
- the response shape (Tier 3), and the error codes and statuses from Tier 1 and from Tier 2 after mapping (404 → 597)

Cross-check against the code that was written (`implementation.md` → Backend → Files changed). If the code and the plan differ, write `STATUS: BLOCKED` with the difference. Don't test against either one silently.

### 2. Derive the cases (lean)
Postman proves the endpoint works **end to end**: real DB, real auth, the ws1 proxy, and the transaction. It does **not** re-run the unit tests. Field-by-field validation (each field missing, each wrong type, each ±1 boundary, each format variant) belongs to the unit tests. `implementation.md` → Tests added lists them, and Postman cites them instead of repeating them.

**Budget per endpoint:** ws2 direct **≤ 12** cases, ws1 proxy **≤ 5**. Going over is allowed only with a one-line reason per extra case in the doc (e.g. a second state-dependent rule that the unit tests can't reach).

| Category | Cases to write | Not here (unit tests own these) |
|---|---|---|
| POS | One happy path with a realistic body, asserting the response shape and the key persisted values. One more only if the plan defines a materially different variant (another filter/sort, a multi-item body that the DB stores differently). | Every optional-field combination |
| NEG | Missing/invalid client credentials (one case). **One representative case per contract `error_code`** (pick the clearest trigger). Wrong partner (isolation). Not found (ws2 404 / ws1 597) where the endpoint has an id. Each DB- or state-dependent rejection (overlap, run in progress, conflict). | Each required field missing, each wrong type, each invalid value of the same code |
| EDGE | Only what needs the real system: a DB constraint or column limit, transaction rollback, concurrency where the plan's Data & Performance Audit names a lock or constraint, a reference-data state the code depends on. | Boundaries ±1, empty/null/whitespace, unicode, NaN, format variants |

ws1 proxy cases cover only what ws1 adds: the happy path through the proxy, no session (401), one ws1 schema (Ajv) rejection if ws1 validates, and one ws2 error passed through (status, `error_code`, `details.upstream_*`), plus 597 if the endpoint has a not-found path. Don't repeat ws2 business rules via ws1.

- **Every AC** in `backend-plan.md` → AC coverage is covered by a Postman case **or** by a unit test that the doc cites (`unit: <spec file> → <test>`). Pure input-validation ACs normally go to unit tests. ACs that need the DB, auth, the proxy or concurrency always get a Postman case. One case may cover several ACs.
- **Every contract error code** gets one Postman case, or a cited unit test when it can't be triggered through the real system (give the reason).
- Each case cites its source: `[AC#] [Q#] [RC#] [backend-plan: Tier 1/2/3]`.
- The doc's **Coverage check** lists AC → TC or unit test, and error code → TC or unit test.

### 3. Write `testing-doc.md` (template `flow/templates/postman-testing-doc.md`)
- Environment and pre-conditions: base URLs as variables, auth per layer, the secret variable **names**
- Seed data: the pre-check, seed and cleanup SQL. The same SQL also goes in `seed.sql` / `cleanup.sql`.
- Case table: `TC<n>`, category, layer (ws2 / ws1), request, expected status, `error_code`, key assertions, citation
- Run instructions: the newman command, folder order

### 4. Write `collection.json` (Postman Collection v2.1.0)
- **Folders**:
  - `1 · ws2 direct`: Tier 1, per endpoint
  - `2 · ws1 proxy`: Tier 2/3, per endpoint
  - `3 · <state-dependent>`: cases that need a state change between runs, as in the team's example
- **Case name**: `TC<n> [POS|NEG|EDGE] <METHOD> <path> - <condition> -> <status>`
- **URLs**: `{{ws2_base_url}}/…` and `{{ws1_base_url}}/…`. Headers use the variables from `config/postman.md` → Auth. Add `X-Secure-Transmission-Type: x` on every ws1 request.
- **Tests on every request**:
  ```javascript
  pm.test("status 200", () => pm.response.to.have.status(200));
  pm.test("shape", () => pm.response.to.have.jsonSchema(schema));       // POS
  pm.test("error_code", () => pm.expect(pm.response.json().error_code).to.eql("…")); // NEG
  ```
  Key-field assertions use plan values. Volatile values (ids, timestamps) are only checked for type and format.
- **No-session cases** clear the cookie jar in a pre-request script (`config/postman.md` → Auth).
- **Order**: creates come before reads, updates and deletes. Ids are passed through collection variables. Data created by POST cases is captured, so cleanup can delete it.
- No secrets and no real personal data.

### 5. Write `environment.json`
`ws2_base_url`, `ws1_base_url`, `partner_id`, `user_id` and the fixture ids, with local values from `config/postman.md`. `client_id`, `client_secret` and `ws1_session_cookie` are **empty**: they're injected at run time.

### 6. Validate
Both JSON files parse. Count the cases per category and layer, and note the counts in `testing-doc.md`.

## Part 2: Run (orchestrator)

1. **Start the services** on the feature branch (`config/postman.md` → Services when running locally):
   - the changed ws2 service(s) first, then ws1 with the `WS2*_BASE_URL` override pointing at them
   - run them as background processes (Claude Code: Bash `run_in_background`; Codex, Cursor and Antigravity: a background terminal)
   - if the host can't keep a process running, print the exact start commands, ask the user to run them in their own terminals, and wait for "started"
   - wait until each one is ready
2. **Secrets**:
   - Ask the user to export `AIFLOW_WS2_CLIENT_ID`, `AIFLOW_WS2_CLIENT_SECRET`, `AIFLOW_WS1_SESSION_COOKIE`, `AIFLOW_PARTNER_ID` and `AIFLOW_USER_ID` in the shell the workflow uses, or to paste them for this session only.
   - Check they're set (`[ -n "$VAR" ]`) without printing them.
   - Never write them to a file.
3. **Seed**:
   1. Show the pre-check SQL, and run it only after the user's yes.
   2. If it returns rows, the api-tester adjusts the fixtures.
   3. Show the seed SQL, and run it only after the user's yes.
   4. Record "seeded" in `status.md` → Notes, so an interrupted run knows to clean up.
4. **Runner**:
   - `npx --no-install newman --version`. If that fails, ask before running `npx newman` (it downloads).
   - If newman is refused or unavailable, use the curl fallback: generate `postman/run.sh` (one curl per case, secrets read from env vars, PASS/FAIL per case), and note "curl fallback" in the report.
5. **Run**:
   ```bash
   npx newman run runs/<KEY>/postman/collection.json \
     -e runs/<KEY>/postman/environment.json \
     --env-var "client_id=$AIFLOW_WS2_CLIENT_ID" --env-var "client_secret=$AIFLOW_WS2_CLIENT_SECRET" \
     --env-var "ws1_session_cookie=$AIFLOW_WS1_SESSION_COOKIE" \
     --env-var "partner_id=$AIFLOW_PARTNER_ID" --env-var "user_id=$AIFLOW_USER_ID" \
     --reporters cli,json --reporter-json-export runs/<KEY>/postman/newman-result.json \
     2>&1 | tee runs/<KEY>/postman/run-output.txt
   ```
   Run the folders in the doc's order. Afterwards, **redact the output files**: replace any secret value, cookie or `Authorization` header with `[REDACTED: <kind>]` before anything else reads them.
6. **Cleanup**: run `cleanup.sql` (approved together with the seed) **every time**, including after failures. Record "cleaned up" in Notes.
7. **Failures**. Classify each one:
   - **code defect**: give the failure (case, expected vs actual, redacted snippet) to the developer role. It fixes the code and re-runs its unit tests. Then re-seed if needed and re-run the collection.
   - **wrong case**: the api-tester fixes the case. The reason (a source citation) goes in the report under Fixes made. Never change a case just to make it pass. The expectation must come from the plan or a source.
   - **plan wrong**: the code matches what the plan says, but the plan is wrong. Change the plan through its changelog, with approval (step 03 → action 2 BLOCKED handling).
   - **environment**: a service is down or the session expired. Ask the user.

   At most 3 fix rounds, then show what remains and ask.
8. **Stop the services**, unless the frontend browser test will use them (fullstack).
9. **Report**: `report.md` from `flow/templates/postman-report.md`, with numbers from the last run only.

## Don'ts
- Don't write cases against shared environments other than the local services.
- Don't assert on volatile values.
- Don't report results from a run that didn't happen, or merge numbers from different runs.
- Don't leave seeded data behind. If cleanup fails, say so and give the user the SQL.
