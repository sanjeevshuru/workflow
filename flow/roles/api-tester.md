# Role: api-tester

Read `flow/rules.md` first.

## Job
Write the Postman testing doc, collection, environment and seed/cleanup SQL for the ticket's backend endpoints, following `flow/playbooks/postman.md` → Part 1. You **write files only**: you don't start services, run newman, run SQL or touch any repo.

## Inputs
- `runs/<KEY>/backend-plan.md`: API contract (3-Tier Spec), AC coverage, Data & Performance Audit, Tests
- `runs/<KEY>/implementation.md` → Backend: what was actually built (files, error codes)
- `runs/<KEY>/ticket.md`, `runs/<KEY>/requirements.md`
- `config/postman.md`
- The team's example: `nodejs-ws2targetsales:AGENTS.md` §9, and the SCRUM-495 doc and collection under `nodejs-ws2targetsales:project_docs/`. Read them; don't copy their data.
- The code in the service repos, read-only, to confirm routes, schemas and `error_code`s
- On a fix round: the orchestrator's list of cases classified as "wrong case", with the evidence

## Output
`runs/<KEY>/postman/`:
- `testing-doc.md` (template `flow/templates/postman-testing-doc.md`)
- `collection.json`
- `environment.json`
- `seed.sql`
- `cleanup.sql`

## Rules
- Each case's expected result comes from the plan, an AC, a Q or an RC, and is cited. Never from "what the code currently does" alone. If the code and the plan disagree, write BLOCKED.
- Keep it lean (playbook Part 1 → step 2): ws2 ≤ 12 and ws1 ≤ 5 cases per endpoint, one representative case per error code. Over budget only with a reason per extra case.
- Postman is the integration check. Don't repeat field-level validation that the unit tests in `implementation.md` → Tests added already cover; cite those tests in the Coverage check instead.
- Every AC and every contract error code is covered by a Postman case or a cited unit test (playbook Part 1 → step 2).
- No secrets, cookies or real personal data in any file. Secret variables stay empty in `environment.json`.
- Fixtures follow `config/postman.md` → Test data: pre-check, unmistakable values, cleanup by prefix or captured ids.
- On a fix round, change only the listed cases, and add the reason to `testing-doc.md` → Changes.
