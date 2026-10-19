# Step 03: Implementation

## Purpose
Turn the approved plans into code on feature branches:
- unit tests, green in every repo
- backend changes verified by a Postman run, frontend changes by a live browser run, with a report for each
- commits made after your OK
- push + merge requests + Jira "Code Review" after your permission

This is the only step that writes to code repos and Jira. Every write goes through `flow/playbooks/git.md`.

## Preconditions
- Gate 2 is approved for every in-scope plan (`status.md` → Gate log).
- `lifecycle: active`.
- The step starts right after Gate 2, or on a later `/run-ticket <KEY>` / "implement <KEY>" (a resume). If a plan has unapproved changelog rows, get them approved first.

## Inputs
`backend-plan.md` and/or `frontend-plan.md` (approved), `ticket.md`, `requirements.md`, `codebase.md`, `figma-flow.md` + `figma/*.md` (frontend), `status.md` → Scope and Repo sync, `config/services.md`, `config/git.md`, `config/postman.md`, and the `knowledge/` profiles and `lessons/` for the scope.

## Order
Backend → Postman → frontend → browser test → report → Gate 3 (commits) → Gate 4 (push). Frontend-only tickets skip the backend and Postman actions. Backend-only tickets skip the frontend and browser actions.

## Actions

### 1. Create branches (orchestrator)
Follow `flow/playbooks/git.md` → Branch for every in-scope repo, in Scope order. Then tell the user in one block:

| Repo | Branch | From |
|---|---|---|

No gate here: Gate 2 approval covers creating branches. Record it in `status.md` → Branches.

### 2. Backend implementation (role: `backend-developer`), if backend is in scope
- Run once per service, in `status.md` → Scope order (providers before consumers, usually ws2 → ws1closio). Pass the key, the service name and the input paths.
- Output: the code and tests in the repo, plus `runs/<KEY>/implementation.md` → Backend → `<service>`.
- After each service, check its section: the tests were run (command and totals present) and they pass. Tick the tasks in `status.md` → Implementation progress.
- **`STATUS: BLOCKED`**: the plan is wrong, a contract must change, or a test can't pass without changing the scope. The orchestrator then:
  1. Shows the problem.
  2. Proposes the plan change: a **Plan changelog** row in the plan.
  3. Re-presents the changed part for approval.
  4. Re-runs the role.
  5. Considers a lesson (`flow/ORCHESTRATOR.md` → Learning).

### 3. Postman doc (role: `api-tester`), if backend is in scope
- Inputs: `backend-plan.md` (API contract, AC coverage, Tests), `implementation.md` → Backend, `requirements.md`, `config/postman.md`
- Outputs in `runs/<KEY>/postman/`: `testing-doc.md`, `collection.json`, `environment.json`, `seed.sql`, `cleanup.sql`
- Keep the doc within the lean budget (`flow/playbooks/postman.md` → Part 1 step 2). If it comes back over budget without a reason per extra case, send it back.

### 4. Postman run (orchestrator)
Follow `flow/playbooks/postman.md` → Run:
1. Start the services.
2. Have the user export the secrets.
3. Get approval for the seed SQL.
4. Run newman.
5. Always clean up.
6. Classify failures and fix them; at most 3 rounds, then ask.

Output: `runs/<KEY>/postman/report.md`, `newman-result.json`, `run-output.txt`. Keep the services running if the frontend will test against them (fullstack). Otherwise stop them.

### 5. Frontend implementation (role: `frontend-developer`), if frontend is in scope
- Inputs: `frontend-plan.md`, `figma/*.md`, `figma-flow.md`, `ticket.md`, `requirements.md`, `codebase.md`. For fullstack, also `backend-plan.md` (Tier 3 / Tier 2) and `postman/report.md`.
- Output: the code and Vitest specs in closio-web-v2, plus `implementation.md` → Frontend.
- BLOCKED is handled as in action 2.

### 6. Browser test doc (role: `ui-tester`), if frontend is in scope
- Inputs: `frontend-plan.md` (Flow, Nodes, States, Validation, AC × node matrix), `figma-flow.md`, `figma/*.md`, `ticket.md`, `requirements.md`, `implementation.md` → Frontend
- Output: `runs/<KEY>/browser/testing-doc.md`

### 7. Browser run (orchestrator)
Follow `flow/playbooks/browser-test.md`:
1. Start the web app against the chosen backend.
2. The user logs in.
3. Run every `UI<n>` case with screenshots.
4. Classify failures and fix them; at most 3 rounds, then ask.
5. Stop the dev server, and any backend services still running from action 4.

Output: `runs/<KEY>/browser/report.md` and `browser/screenshots/`.

### 8. Report (orchestrator)
1. Complete `postman/report.md` and/or `browser/report.md` from their templates. The numbers come **only from the last real run**.
2. Complete `implementation.md`:
   - **AC coverage**: AC → code → unit test → Postman TC / UI case
   - **Deviations** with their changelog rows
   - **Known gaps**

   Every AC needs at least one unit test. It also needs a Postman or UI case, unless it is pure input validation that the testing doc's Coverage check cites a unit test for. Otherwise list it under Known gaps with the reason.

### 9. Gate 3: Implementation and commits
Follow `flow/playbooks/git.md` → Commit (prepare). Present:
- per repo: branch, `git diff --stat` summary, unit test / lint / build results (command → totals)
- Postman totals (backend) and browser totals (frontend), with any unresolved failures
- deviations from the plan and the changelog rows
- the **proposed commits** per repo: message + files, in order

Ask: "Commit these to <branches>?" Commit only on an explicit yes, repo by repo, as listed. A hook failure goes back to the developer role for a fix; then re-present the affected commits. Record the hashes in `implementation.md` → Commits. Changes requested at this gate are applied and the gate is re-presented.

### 10. Gate 4: Push permission
Present: per repo, the branch, the commits (hash + message) and the MR target (the development branch). Ask: "Push and open merge requests?"

On an explicit yes, follow `flow/playbooks/git.md` → Push (push + MR, per repo, providers first; stop on the first failure). Then:
1. **Jira**: move the ticket to **Code Review**. Use the Jira MCP's transitions for `<KEY>` and pick the one named "Code Review" (don't hard-code the id). If there's none, ask. Besides the claim in step 01, this is the only Jira write in the workflow (`config/jira.md` → Workflow writes to Jira). No comments, no other field edits, no links.
2. Record pushes, MR URLs and the transition in `status.md` → Implementation and in `implementation.md` → Merge requests.
3. Show the **MR links per repo**. The developer adds them to the Jira ticket as web links, by hand.
4. Say in one line that step 04 (Deployment doc) starts next, and continue with it (`flow/steps/04-deployment-doc.md`).

If the user declines, nothing is pushed. The commits stay local, and the step waits (`step_status: waiting_user`).

## Gates
- Gate 3: implementation and commits approved, then commits are made.
- Gate 4: push approved, then push + MR + Jira Code Review.

## Outputs
- Code and tests on `<branch>` in each in-scope repo; commits after Gate 3, pushed after Gate 4
- `runs/<KEY>/implementation.md`
- `runs/<KEY>/postman/{testing-doc.md, collection.json, environment.json, seed.sql, cleanup.sql, report.md, newman-result.json, run-output.txt}` (backend)
- `runs/<KEY>/browser/{testing-doc.md, report.md, screenshots/}` (frontend)
- `status.md` updated: Branches, Implementation progress, Gate log

After Gate 4 the run stays `lifecycle: active` until the ticket is done and archived (`flow/ORCHESTRATOR.md` → Keeping plans until the ticket is done). Review feedback on the MR is handled by resuming: "resume <KEY>", then describe the change. It's implemented on the same branch through the same gates.
