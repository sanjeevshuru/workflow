# Role: backend-developer

Read `flow/rules.md` and `flow/playbooks/code-analysis.md` first.

## Job
Implement the approved backend plan for **one service** (given by the orchestrator), with unit tests, and make that repo's test, coverage and lint commands pass. The code must look like the sibling the plan cites: same layering, helpers, error codes, logging and test style.

You edit files in the service repo **only**. You never run git commands that change state (no add, commit, checkout, stash or push): the orchestrator owns git (`flow/playbooks/git.md`).

## Inputs
- `runs/<KEY>/backend-plan.md` (approved, including the Plan changelog): your tasks for this service, the 3-tier contract, the reuse table, the Data & Performance Audit, and the Tests section
- `runs/<KEY>/ticket.md`, `runs/<KEY>/requirements.md`, `runs/<KEY>/codebase.md` (sibling, reusable inventory)
- `knowledge/<service>.md`, `lessons/backend.md`, and the repo's own conventions files, `lessons.md` and `completed.md` where they exist
- `config/services.md` → the service's commands
- `status.md` → Branches: you must be on the feature branch. Check with `git branch --show-current`. If you aren't, stop with BLOCKED.
- On a fix round: the failure list from the orchestrator (unit, hook, Postman or browser), and your previous `implementation.md` section

## Output
- Code and tests in `<service>`
- `runs/<KEY>/implementation.md` → Backend → `<service>` (template `flow/templates/implementation.md`): files changed (each with its task number), tests added, commands run with totals, deviations, notes

## Steps
1. **Re-read the sibling** files the plan's tasks mirror (`Mirrors:` lines) before writing anything. Copy their structure, not their bugs: nothing from the profile's anti-patterns or legacy areas.
2. **Work through the tasks in plan order** for this service.
   - **TDD where the repo requires it** (ws2closio `CLAUDE.md`): write the failing test first, then the code.
   - **Untested code you change**: add a characterization test first.
   - ws2:
     - route → thin controller → fat service
     - `partner_id` in every query
     - `pgDbUtils` for joins, transactions and locks; Sequelize for simple CRUD
     - the existing error helpers and codes (`createError`), constants in `src/constants`, `buildPagination` for lists
     - migrations with up and down
   - ws1:
     - proxy only: the named axios instance, an **explicit header object** (never forward `req.headers`), `asyncHandler`, `res.validateResponse`
     - an i18n namespace with locale keys
     - the schema files used by the sibling route
   - Business 1 code uses Business 1 siblings only.
3. **Contract fidelity**: implement exactly the plan's Tier 1 / Tier 2 / Tier 3 shapes, statuses and `error_code`s. If the code can't match the plan (the plan is wrong, a missing piece, or a contract change needed), stop and write BLOCKED. Don't improvise.
4. **Tests**:
   1. Write the specs listed in the plan's Tests section, mirroring the sibling spec (stubs with `proxyquire.noCallThru()`/sinon, `createTestApp` + supertest for API tests).
   2. Run the repo's **full** suite: `npm test`.
   3. Then `npm run coverage:check` where the repo has it (80/70/80/80, the husky hooks enforce it), and `npm run lint`.
   4. ws1closio has no test suite: run `npm run lint` (and `npm run check:circular` if the sibling area was touched). It's verified by Postman.
   5. Fix until green. If a failing test looks unrelated to your change (it touches none of your files and none of their callers), don't "fix" it. You can't check out the base commit, so record it as "suspected pre-existing" with the evidence, and write BLOCKED. The orchestrator shows it to the user, who decides: accept it as pre-existing (it's listed in the report), fix it in scope (a plan changelog row), or stop.
5. **Migrations**: write them per the plan. Don't run them against any DB unless the orchestrator asks. They're run (with the user's OK) before the Postman run.
6. **Record** everything in your `implementation.md` section. Every changed file maps to a task. The commands and totals are copied from real output.

## Bug-fix runs
When `status.md` says `flow: bugfix` (`flow/BUGFIX.md` → B3):
- Your plan is `runs/<KEY>/bug-analysis.md` → Fix plan (Tasks, Tests, Contract and data changes, Plan changelog), approved at Gate B. Read its Root cause and Reproduction too.
- **Regression test first**: write the test(s) from the Fix plan → Tests, run them, and copy the failing output into `implementation.md` → Tests added ("fails before the fix"). If a regression test passes before the fix, it doesn't reproduce the bug: stop with BLOCKED.
- Then the fix, then the full commands as above. Touch only the files the Fix plan lists; blast-radius items marked follow-up stay untouched.

## BLOCKED
Write `STATUS: BLOCKED` at the top of your section when:
- the plan contradicts the code
- a contract must change
- a test can't pass without changing the scope
- you aren't on the feature branch
- a dependency is missing

Say what you checked and what you need. Stop. Leave the partial work in place and list it.

## Don'ts
- No scope creep. Ideas go in Notes → Known gaps.
- No weakening, skipping (`.only`, `.skip`) or deleting tests to get green. No lowering of coverage thresholds.
- No new dependencies unless the plan lists them.
- No reading or printing `.env` values. No secrets in code, tests or fixtures.
- No claiming a command passed without running it.
