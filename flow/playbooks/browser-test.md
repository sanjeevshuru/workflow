# Playbook: Live browser test (step 03, frontend)

Frontend changes are verified in a real browser, not with Postman. There are two parts:
- **Doc**: role `ui-tester`, which only writes files.
- **Run**: the orchestrator, because the user has to pick the backend and log in.

All artefacts live in `runs/<KEY>/browser/` and are never committed to closio-web-v2.

## Part 1: Doc (ui-tester)
Write `browser/testing-doc.md` from `flow/templates/browser-testing-doc.md`. The cases come from:
- `frontend-plan.md`: Flow (entry, transitions, state passed), Nodes (route and file, states, validation and messages, permissions), the AC × node matrix, Feature flags
- `figma-flow.md` and `figma/<nodeId>.md`: frame order, the exact copy (verbatim), and the layout notes to check by eye
- `requirements.md`: decisions (Q) and code facts or conventions (RC) that define the behaviour

| Category | Cases |
|---|---|
| FLOW | Enter from the real entry point (menu, route, button), walk the node flow in order, and check the state passed between nodes |
| STATE | Each node's loading, empty, error (API failure, 597 / not-found) and success state |
| VALID | Every validation rule and message (copy verbatim from Figma or the plan), required fields, limits, disabled and enabled actions |
| PERM | Permissions and feature flags: visible vs hidden, B1/B2 menu visibility where relevant |
| DATA | Table and list behaviour the plan defines (sort, filter, pagination, renderers, date/period pickers), and values matching the API response |
| NAV | Back and cancel, deep link or refresh on each route, leaving with unsaved changes if the plan covers it |

- **Lean:** the browser run checks the real UI against the real API, not every rule the Vitest specs already cover. Budget **≤ 15 cases per ticket** (≤ 25 for a multi-screen flow). Going over needs a one-line reason per extra case.
  - VALID: one case per *kind* of validation (required, format, limit, cross-field), not one per field. Field-by-field messages are left to the Vitest specs, and the doc cites them.
  - STATE: loading and empty only where the plan defines a distinct UI for them. One API-error case per screen.
  - Combine steps: one walk-through case may check several nodes and ACs.
- Every AC in the AC × node matrix gets at least one case, or a cited Vitest spec when it is pure client-side validation.
- Each case has `UI<n>`, category, node, pre-conditions and data, numbered steps (what to click or type, using visible labels), expected result, and a citation (`[AC#] [Q#] [RC#] [figma: F#]`).
- If cases need specific backend data, write the seed and cleanup SQL the same way as `flow/playbooks/postman.md`. Fixtures are unmistakable, and the SQL only runs after the user's yes.

## Part 2: Run (orchestrator)

### 1. Pick the backend
- **fullstack**: the local ws1 (and ws2) already running from the Postman run.
- **frontend-only**: ask the user, once per ticket, and record the answer in `status.md` → Notes:

  | Option | Start command (in `../web/closio-web-v2`) | Use when |
  |---|---|---|
  | Dev ws1 via proxy | `npm run dev-proxy -- --port=5173` | the APIs already exist on dev |
  | Staging ws1 via proxy | `npm run dev-staging-proxy -- --port=5173` | the APIs are on staging only |
  | Local ws1 | `WS1_PROXY_TARGET=http://localhost:3000 VITE_WS1_PROXY_ENABLED=true VITE_USE_MOCKS=false VITE_PORT=5173 npx vite`, with the `VITE_*_BASE_URL` variables set as in `scripts/dev-proxy.js` (with ws1's local path prefix if it has one) | the APIs exist only on a local branch |
  | Mocks | `VITE_USE_MOCKS=true VITE_PORT=5173 npm run dev` | there's no backend yet. Mock results don't prove the integration; the report says so |

  Port 5173 avoids the clash with ws1 on 3000. Process-env overrides take precedence over `.env.development`, so `.env` files are never edited. For local ws1, check the exact base URLs on the first run and record the command that worked in `config/postman.md`.
- Start the dev server in the background (see `postman.md` → Run step 1 for hosts that can't). It's ready when `http://localhost:5173/` answers.

### 2. Browser tool per host
| Host | Tool |
|---|---|
| Claude Code, Codex | **Playwright MCP** (`playwright` in `.mcp.json` / `setup/mcp.md`), **headed**, so the user can see it and log in |
| Cursor | the built-in browser (Browser tab / browser tools) |
| Antigravity | the built-in browser agent |

If none is available, use the **manual fallback**:
1. The workflow presents the cases one at a time (steps + expected).
2. The user runs each one and answers pass or fail (plus a screenshot path, optional).
3. The workflow records the answers.

The report then says "manual run".

### 3. Log in (the user)
Open `http://localhost:5173/` and ask the user to log in in that browser window (credentials + OTP), then say "logged in". The workflow never types, reads or stores credentials, and never saves cookies or storage state to files. If the session expires during the run, ask again.

### 4. Seed
Only if the doc has seed SQL: pre-check → seed → cleanup, with the same approvals and the same always-clean-up rule as in `postman.md`.

### 5. Run each case
1. Follow the steps through the browser tool: navigate, click and type by visible label or role.
2. After the steps, check the expected result:
   - **Text**: exact copy, using the accessibility snapshot or the page text.
   - **Elements**: present, enabled or disabled, visible or hidden.
   - **Values**: table rows, values and order.
   - **Navigation**: the URL or route.
3. Save a screenshot as `browser/screenshots/UI<n>.png`. Take one per failure state too.
4. Read the browser console. New errors or warnings during the case are a failure, unless the plan expects them.
5. **Visual check**: for key screens, compare with the Figma screenshot of that node if step 02 already fetched one (`figma/<nodeId>.md`). Don't make new Figma calls just for this. List visible differences (layout, copy, missing elements) as findings. Pixel-level differences aren't failures.
6. Record pass or fail with the actual result.

### 6. Failures
Classify them like Postman failures:
- **code defect**: `frontend-developer` fixes the code and re-runs Vitest + build. Then re-run the failed cases and the cases on the same node.
- **wrong case**: `ui-tester` fixes the case, with a cited reason.
- **plan wrong**: the plan changes through its changelog, with approval.
- **environment**: backend down, data missing or session expired. Ask the user.

At most 3 rounds, then ask.

### 7. Clean up
1. Run the cleanup SQL if anything was seeded.
2. Close the browser session.
3. Stop the dev server, and any backend services started for this step.

### 8. Report
`browser/report.md` from `flow/templates/browser-report.md`, with numbers from the last run only. Screenshots are linked per case.

## Don'ts
- Don't test against production.
- Don't store credentials, cookies or browser storage state.
- Don't mark a case passed that wasn't run, or that was run against mocks without saying so.
- Don't change the code or the cases during a run without recording it in the report under Fixes made.
