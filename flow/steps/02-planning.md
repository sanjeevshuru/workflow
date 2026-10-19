# Step 02: Planning

## Purpose
Produce implementation plans that a developer (human or agent) can execute without guessing: one for backend, one for frontend.

## Inputs
`runs/<KEY>/ticket.md`, `runs/<KEY>/requirements.md` (approved), `runs/<KEY>/codebase.md`, `runs/<KEY>/figma-flow.md` (frontend or fullstack only), `config/services.md`, `status.md` → Scope (type confirmed in step 01)

## Actions

### 1. Refine scope (orchestrator)
The type (`backend` / `frontend` / `fullstack`) was confirmed in step 01. Don't re-ask it. Now pin down the details:
1. Start from `codebase.md` → Repos and Key facts. Together with `requirements.md` and `config/services.md`, propose:
   - Backend services affected, in implementation order: providers before consumers, usually ws2 service(s) → ws1closio gateway
   - Whether closio-web-v2 is affected, which must agree with the confirmed type
2. If a service is needed that `codebase.md` doesn't cover, sync it first (`flow/playbooks/repo-sync.md`), then run `code-scout` again for that repo before proposing it.
3. If the code shows that the confirmed type is wrong (for example a "backend" ticket that needs a UI change), stop and ask the user. If the answer adds frontend, first run step 01 → action 3 (Figma manifest) and its questions.
4. Present the service list to the user with citations, and wait for confirmation. Record it in `status.md` → Scope.

### 2. Backend plan (role: `backend-planner`), if backend is in scope
- Inputs: `ticket.md`, `requirements.md`, `codebase.md`, `config/services.md`, the confirmed service list
- Output: `runs/<KEY>/backend-plan.md`
- If `STATUS: BLOCKED`: check that each question lists what code was checked (`flow/rules.md` → Code before questions). Send back any that don't. Ask the rest, record the answers, and re-run.

### 3. Frontend plan (role: `frontend-planner`), if frontend is in scope
- Runs **after** the backend plan when both are in scope. It consumes `backend-plan.md` → API contract: **Tier 3** (client envelope) for request and response shapes, and **Tier 2** for the error statuses the UI sees (for example 404 → 597).
- Inputs: `ticket.md`, `requirements.md`, `codebase.md`, `figma-flow.md`, `config/services.md`, and `backend-plan.md` if it exists
- Output: `runs/<KEY>/frontend-plan.md`, plus `runs/<KEY>/figma/<nodeId>.md` per node
- If `STATUS: BLOCKED`: same check as the backend planner (each question lists what code was checked). Ask the rest, record the answers, and re-run.

When only one side is in scope, run only that planner. A frontend-only ticket plans against the **existing or specified** APIs. Backend code is out of scope (`flow/playbooks/code-analysis.md` → Scope Isolation Rules). The contract comes from, in this order:
1. the ticket description
2. the `sources/` tech specs
3. the user's input: if neither defines what's needed, ask

Existing `closio-web-v2:src/api/*` functions that already call the endpoint can be cited as evidence of current usage.

### 4. Cross-check (orchestrator)
Before the gate, check:
- Every AC appears in at least one plan's AC coverage table.
- Every endpoint the frontend plan calls is defined in the backend plan's API contract (Tier 3 and Tier 2), or, for frontend-only tickets, in a contract source from the list above (cited).
- Neither plan contains an uncited requirement-level statement.

Fix gaps by re-running the relevant role or asking the user.

### 5. Gate 2: Plans approved
Present each plan separately, with its summary, services/files touched, open risks, and AC coverage. Approve the backend and frontend plans one at a time. Record each approval in `status.md`.

When every in-scope plan is approved, say in one line that step 03 (Implementation) starts next by creating the feature branches, and continue. If the user says to stop here, set `step_status: approved` and wait. `/run-ticket <KEY>` (or "implement <KEY>") picks it up later.

## Outputs
`runs/<KEY>/backend-plan.md`, `runs/<KEY>/frontend-plan.md`, `runs/<KEY>/figma/*.md`, and `status.md` updated.
