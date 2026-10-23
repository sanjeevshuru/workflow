# Bug fix

Fix a bug that QA (or anyone) raised in Jira: find the root cause in the code, fix it with a regression test, verify it, then commit, push and hand it back for review and a dev deploy. You own every interaction with the user, as in `flow/ORCHESTRATOR.md`.

A bug fix replaces steps 01–02 with a shorter intake and a root-cause investigation, then reuses step 03 (Implementation) and step 04 (Deployment doc). All rules still apply (`flow/rules.md`): never assume, cite everything, reuse before new, code before questions, gates.

State lives in `runs/<KEY>/`, like a ticket run, with `flow: bugfix` in `status.md`. Archive, reopen, restart, lessons and changing course work as in `flow/ORCHESTRATOR.md`.

## Picking the ticket
The user gives a key (`SCRUM-514`) or just the number (`514`).
- A bare number gets the project key from `config/jira.md` → Projects. With one project, use it and say so in the reply ("514 → SCRUM-514"). With several, ask which one.
- A run started with `/run-ticket` on a ticket whose Jira type is **Bug** asks, right after the fetch (step 01 → action 1), whether to switch to this flow. On a yes, set `flow: bugfix` and continue here at B1 → 4 (the ticket is already fetched and claimed).

## Start
0. **VPN preflight**: `flow/playbooks/vpn.md`, as in `flow/ORCHESTRATOR.md` → Start.
1. Read `flow/rules.md` and `lessons/workflow.md`.
2. If `runs/<KEY>/status.md` exists, go to **Resume**.
3. Create `runs/<KEY>/`, and `status.md` from `flow/templates/status.md` with `flow: bugfix` and `current_step: B1`.
4. Run B1.

## Steps
| # | Step | Produces | Gate |
|---|---|---|---|
| B1 | Intake | `ticket.md` (with the Bug report section), `requirements.md` (Decisions log), scope, synced repos | none (scope question) |
| B2 | Root cause | `bug-analysis.md`, `codebase.md` (light) | **Gate B**: root cause and fix approved |
| B3 | Implementation | step 03, with the bug-fix differences below | Gates 3 and 4 |
| B4 | Deployment doc | step 04, unchanged | Gate 5 |

### B1. Intake (orchestrator)
1. **Fetch** the issue with all fields, exactly as step 01 → action 1 (`config/jira.md` → How to fetch an issue), including comments, attachments and linked issues.
2. **Check the type.** If it isn't **Bug**, say so and ask: continue as a bug fix, or run the normal ticket flow (`/run-ticket <KEY>`)? A story-sized change ("make it also do X") belongs in the ticket flow.
3. **Claim** it: step 01 → action 1.4 (`config/jira.md` → Workflow writes to Jira). A bug QA reopened can be back in a To Do-category status; the same rule applies.
4. **Write `ticket.md`** from `flow/templates/ticket.md`, and fill its **Bug report** section from the description, comments and custom fields. Quote QA's words:
   - Steps to reproduce, Expected, Actual, Environment (dev / staging / build / URL / user role / partner), Frequency, Reporter
   - Attachments: screenshots, videos, HAR or log files. Read images when the Jira MCP returns them; otherwise list them as "not readable here" and ask for the key detail if the report depends on it.
   - **Related ticket**: the story the bug was found in (the parent, a "relates to" / "is caused by" / "found in" link, or a key in the summary or comments). If there's a run for it in `runs/<ORIG>/` or `runs/_archive/<ORIG>/`, note its path: its `ticket.md` AC, `requirements.md` decisions and plans define the intended behaviour.
5. **Acceptance criteria** for a bug are the expected behaviour:
   - QA's Expected lines become AC1, AC2, …, quoted.
   - If Expected is missing or vague, derive candidates from the related ticket's AC or the `sources/` docs, mark them `(proposed)` with their citation, and confirm them in the question below.
   - Always add one AC: "The steps to reproduce no longer produce the Actual result." It anchors the regression test.
6. **Triage scope**: as step 01 → action 2, from the symptom. A wrong number on a screen can still be a backend bug. When it's unclear, propose `fullstack` for the investigation and narrow it at Gate B. Ask in one AskUserQuestion batch (up to 4 questions):
   - the scope (`Q1`)
   - the proposed AC, if any
   - anything the report leaves out that only the user or QA can answer (which environment, which partner/role, whether it worked before)

   Record the answers in `requirements.md` → Decisions log (create it from its template; for a bug only the Decisions log, Open questions and Resolved from code sections are used). Set `status.md` → Scope.
7. **Sync the in-scope repos**: step 01 → action 2.5 (`flow/playbooks/repo-sync.md`).

No Figma manifest and no `requirements-analyst` run. If the fix needs a design decision (new copy, a new state), that's a Gate B question; a Figma link in the ticket is read only when the bug is about matching the design, and then with `flow/playbooks/figma.md` → Budget.

### B2. Root cause (role: `bug-investigator`)
Run the role (`flow/ORCHESTRATOR.md` → Running a role).
- Inputs: the key, `ticket.md`, `requirements.md`, `status.md` → Scope and Repo sync, `config/services.md`, the related ticket's run folder (if any), `lessons/backend.md` and/or `lessons/frontend.md`, and the `knowledge/` profiles for the scope
- Outputs: `runs/<KEY>/bug-analysis.md` (template `flow/templates/bug-analysis.md`) and `runs/<KEY>/codebase.md` (Repos, Existing work, Sibling, Key facts only)

Then:
1. **BLOCKED**: ask its questions (`flow/rules.md` → Asking the user), record the answers as `Q<n>`, and re-run it.
2. **Root cause `unconfirmed`** (the code reading found candidates but can't tell which one, or found nothing wrong): offer a **live reproduction** before the gate, and do it only on the user's yes:
   - backend: run the reproduction request(s) from `bug-analysis.md` → Reproduction against local services, as in `flow/playbooks/postman.md` → Run (secrets by name, seed SQL only after a yes, cleanup always)
   - frontend: follow the reproduction steps in the browser as in `flow/playbooks/browser-test.md` (the user logs in)
   - Write what happened to `bug-analysis.md` → Reproduction → Live result, and re-run the role with it.

   Never reproduce against a shared environment's data without the user naming it.
3. **Not a bug**: if the investigation shows the code does what an AC, a `Q`, or a source doc defines, or the expected behaviour was never specified, don't fix anything yet. Present the evidence and ask: close as "works as specified" (the user tells QA; nothing is written to Jira), or treat the new expectation as a change (record it as `Q<n>`, and continue with it as an AC).

### Gate B: Root cause and fix approved
Present:
- the bug in one line, and the AC
- **Reproduction**: the path from the user action or request to the wrong result, in 3–6 cited steps (`[code: …]`), plus the live result if one was run
- **Root cause**: what's wrong and why, with citations, and the confidence (`confirmed` by code or live run / `likely`)
- **Introduced by**: commit, MR or ticket, if found (`git log` / `git blame`), else "not found"
- **Fix**: per repo, the tasks and files, which sibling or convention it mirrors, and why it's the minimal correct fix. Any alternative considered and why not.
- **Regression tests**: the test(s) that fail before the fix and pass after, per repo
- **Blast radius**: other callers or screens with the same defect, and whether they're in this fix (`Q<n>`) or listed as a follow-up
- **Contract or data changes**: none, or each one (a response field, an `error_code`, a migration, a data fix for rows already wrong). A data fix for existing rows is a separate question: script in the run, run by whom.
- Scope narrowed to: `backend` / `frontend` / `fullstack`

Ask: "Approve the root cause and fix for <KEY>?" Only an explicit yes passes. Changes are applied by re-running the role and re-presenting. Record Gate B in `status.md` → Gate log, then say in one line that implementation starts by creating the branch, and continue.

### B3. Implementation
Follow `flow/steps/03-implementation.md`, with these differences:
- **The plan** is `bug-analysis.md` → Fix plan. It has the same parts the developer and tester roles read from `backend-plan.md` / `frontend-plan.md` (Tasks, Tests, AC coverage, and the contract or nodes it touches), and the same **Plan changelog** for anything that changes after Gate B. Pass it to the roles in place of the plans; each role has a "Bug-fix runs" section.
- **Precondition**: Gate B approved, in place of Gate 2.
- **Branch**: `fix/<key-lowercase>` (`config/git.md` → Branch naming). If QA reopened a bug whose earlier fix was pushed, the branch exists: continue on it if its MR is still open; if it's merged, a new branch from the fresh development branch with the `-v2` rule.
- **Regression test first**: the developer writes the test that reproduces the bug, runs it, and records the failing output (`implementation.md` → Tests added → "fails before the fix"). Then the fix, then the full suite. A regression test that passes before the fix doesn't reproduce the bug: BLOCKED.
- **Postman / browser**: lean. The reproduction as one case (it must now give the Expected result), plus at most 4 cases around it that the fix could break. `flow/playbooks/postman.md` and `browser-test.md` otherwise unchanged. If the user wants to skip a live run, record it in the report as "skipped by user", never as passed.
- **Gate 3**: commit type `fix` (`fix(<KEY>): <what is now correct>`), one commit per repo by default.
- **Gate 4**: as step 03, including the move to **Code Review**. The MR title is `<KEY>: <ticket summary>`.

### B4. Deployment doc
Follow `flow/steps/04-deployment-doc.md` unchanged. `deployment-writer` reads `bug-analysis.md` in place of the plans and `requirements.md`. QA needs the fix on dev to re-test, so the doc's verification lists the reproduction steps.

## Resume
As `flow/ORCHESTRATOR.md` → Resume (VPN, repo sync, step 03 checkpoints), with `current_step` one of `B1`–`B4`. Read this file, not the step registry.

**QA reopened the bug** (the user says so, or the ticket shows it moved back after Code Review or Done):
1. Re-fetch the ticket. Append the new comments and attachments to `ticket.md` → Bug report → Reopened, round `<n>`.
2. Re-run `bug-investigator` with them. It appends a **Round `<n>`** section to `bug-analysis.md` (what the first fix missed, and why) and adds Fix plan rows through the Plan changelog.
3. Gate B again for the new round only, then B3 on the same branch (or a `-v2` one if the MR was merged), then Gates 3, 4 and 5.
4. Consider a lesson (`flow/ORCHESTRATOR.md` → Learning): a fix QA rejects is a plan that was wrong.
