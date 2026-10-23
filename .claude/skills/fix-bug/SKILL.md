---
name: fix-bug
description: Fix a bug ticket raised by QA — give the Jira key or just its number (e.g. 514 → SCRUM-514). Reads the bug report (steps, expected, actual, attachments, related story), traces the root cause in the code, gets your OK on the root cause and fix (Gate B), then implements it with a regression test, verifies it with Postman / browser, commits (Gate 3), pushes + MR + Jira Code Review (Gate 4) and writes the dev deployment doc (Gate 5). Starts or resumes; also handles a bug QA reopened. Use when the user says "fix bug <n>", "fix <KEY>" or "bug <n>".
argument-hint: <JIRA-KEY | number>
---

Arguments: `$ARGUMENTS`. The first token is the Jira key or the bare ticket number.

Read `flow/BUGFIX.md` and follow it exactly for this key: **Start** if `runs/<KEY>/status.md` doesn't exist, otherwise **Resume**. Run B1 → B2 → B3 → B4, stopping only at questions and gates (Gate B, Gate 3, Gate 4, Gate 5).

Claude Code specifics are the same as the `run-ticket` skill (AskUserQuestion, the `atlassian` MCP and its writes, the VPN preflight, background services, the `playwright` MCP), plus:
- Roles as sub-agents with the Agent tool: `bug-investigator` in B2; in B3 `backend-developer` (once per service), `api-tester`, `frontend-developer`, `ui-tester`; in B4 `deployment-writer`. Tell each step-03/04 role it's a bug-fix run and that the plan is `runs/<KEY>/bug-analysis.md` → Fix plan.
