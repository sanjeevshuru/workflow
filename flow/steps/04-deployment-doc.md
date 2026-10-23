# Step 04: Deployment doc

## Purpose
Write a short, step-by-step deployment doc for the ticket, for the **developer who deploys** it to **dev**:
- **Backend**: what to deploy in which order, migrations, env vars, how to verify, how to roll back.
- **Frontend**: what must be live first, feature flags, build, how to verify, how to roll back.

The docs live in `runs/<KEY>/` only. This step is **read-only** toward repos and Jira.

## Preconditions
In a bug-fix run (`flow: bugfix`), `bug-analysis.md` replaces the plans and `requirements.md` in the inputs below.

- Gate 4 is approved, and `status.md` → Implementation shows every in-scope repo pushed, with its MR URL and remote hash.
- The step starts right after Gate 4, on a later `/run-ticket <KEY>` (a resume), or with "deployment doc <KEY>".

## Inputs
- `status.md`: Scope, Branches, Implementation (pushed hashes, MRs)
- `implementation.md`, `requirements.md` (Decisions log, deferred items), `backend-plan.md` and/or `frontend-plan.md`
- `runs/<KEY>/postman/` (collection, testing doc, report) and `runs/<KEY>/browser/` (testing doc, report)
- `config/services.md`, `config/deployment.md`

## Actions

### 1. Check the dev deploy config (orchestrator)
Read `config/deployment.md`. If **How a dev deploy happens** or a dev host the ticket needs is still `TODO`, ask the user (`flow/rules.md` → Asking the user). Write the answer into `config/deployment.md`, so it's asked only once. If the user doesn't know, keep it as `TODO: ask <owner>` and the doc says so.

### 2. Collect the facts (orchestrator, read-only git)
For each in-scope repo, use the development branch and the pushed hash from `status.md`:
- `git -C <repo> diff --name-status <dev branch>...<pushed hash>`
- **Migrations and seeders** added or changed (`src/migrations/`, `src/seeders/`): file names in order, and for each one what it creates or alters (`git show <hash>:<file>`). Note whether its `down` really reverts it.
- **Dependencies**: `package.json` changes (`git diff <dev>...<hash> -- package.json`).
- **Env var names** the change introduces: `process.env.<NAME>` (backend) or `import.meta.env.VITE_<NAME>` (frontend) in the diff, plus any `.env.example` lines. **Names only.** Never read `.env` or `.env.local`.
- **closio-web-v2 flags**: the `VITE_ENABLE_*` lines changed in `.env.development` (a tracked flag file, no secrets). Say whether `.env.staging` and `.env.production` changed.
- **Runtime pieces**: new or changed routes, BullMQ queues, workers, crons and consumers, and so the `RUN_MODE` deployments (`config/deployment.md`) that need a restart.

Write `runs/<KEY>/deployment-facts.md`, one section per repo, with every item cited `[code: <service>:<path>:<lines> @ <hash>]`.

### 3. Backend doc (role: `deployment-writer`, side `backend`), if backend is in scope
Run the role (`flow/ORCHESTRATOR.md` → Running a role).
- Inputs: the key, side `backend`, `deployment-facts.md` and the inputs above
- Output: `runs/<KEY>/deployment-backend.md` (template `flow/templates/deployment-backend.md`)

### 4. Frontend doc (role: `deployment-writer`, side `frontend`), if frontend is in scope
- Inputs: the same, side `frontend`. For a fullstack ticket, also `deployment-backend.md`, which becomes a prerequisite in the frontend doc.
- Output: `runs/<KEY>/deployment-frontend.md` (template `flow/templates/deployment-frontend.md`)

If a role writes `STATUS: BLOCKED`, ask the user its questions, record the answers in `requirements.md` → Decisions log, and re-run it.

### 5. Gate 5: Deployment doc approved
Present, per doc, one short block:
- **Backend**: deploy order (services and `RUN_MODE` deployments), migrations (count and names, reversible or not), new env var names, smoke checks (count), rollback in one line, and open items
- **Frontend**: backend prerequisites, flags changed, build, checklist (count), rollback in one line, and open items
- any `TODO: ask <owner>` lines left in the doc

Ask: "Approve the deployment doc(s) for <KEY>?" Only an explicit yes passes. Changes are applied and the gate is re-presented. On approval, record Gate 5 in `status.md` → Gate log and Deployment doc, and give the user the doc paths.

### 6. Keeping it current
The doc describes the pushed commits recorded in its header. If later commits are pushed (MR review fixes, through Gates 3 and 4 again), the doc is stale: on resume, re-run actions 2–5 for the affected side(s) and show what changed at Gate 5.

## Gate
Gate 5: the deployment doc(s) approved. This is the last registered step. After it, the run stays `active` until the ticket is done (`flow/ORCHESTRATOR.md` → Keeping plans until the ticket is done).

## Outputs
`runs/<KEY>/deployment-facts.md`, `runs/<KEY>/deployment-backend.md` (backend in scope), `runs/<KEY>/deployment-frontend.md` (frontend in scope), and `status.md` updated (Deployment doc, Gate log).
