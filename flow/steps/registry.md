# Step registry

Steps run in this order. To add a step, create `flow/steps/<NN>-<name>.md` using the same sections (Purpose, Inputs, Actions, Outputs, Gate), add any new roles to `flow/roles/`, and append a row here. The host adapters do not need changes.

| # | Step | File | Produces |
|---|---|---|---|
| 01 | Requirements | `flow/steps/01-requirements.md` | `ticket.md`, `requirements.md`, `codebase.md`, `figma-flow.md` (frontend or fullstack only) |
| 02 | Planning | `flow/steps/02-planning.md` | `backend-plan.md`, `frontend-plan.md`, `figma/*.md` |
| 03 | Implementation | `flow/steps/03-implementation.md` | feature branches, code + unit tests, `implementation.md`, `postman/*` (backend), `browser/*` (frontend), commits (Gate 3), push + MRs + Jira Code Review (Gate 4) |
| 04 | Deployment doc | `flow/steps/04-deployment-doc.md` | `deployment-facts.md`, `deployment-backend.md` (backend), `deployment-frontend.md` (frontend): dev only (Gate 5) |

Steps 01–02 are read-only toward repos and Jira, except for repo sync and the step 01 Jira claim (To Do → In Development, assign if unassigned). Step 03 writes only through `flow/playbooks/git.md`, and to Jira only through the Code Review transition. Step 04 is read-only toward repos and Jira.
