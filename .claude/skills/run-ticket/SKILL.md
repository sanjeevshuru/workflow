---
name: run-ticket
description: Run the complete gated ticket workflow for a Jira key — step 01 requirements (Jira + sources/ + Figma + code scout), step 02 backend/frontend plans, step 03 implementation (branches, code + unit tests, Postman / live browser tests, commits at Gate 3, push + MR + Jira Code Review at Gate 4), step 04 dev deployment doc (backend and/or frontend, Gate 5). Starts a new run or resumes an existing one. Use when the user says "run <KEY>", "start <KEY>", "plan <KEY>", "implement <KEY>" or "resume <KEY>".
argument-hint: <JIRA-KEY> [figma-link ...]
---

Arguments: `$ARGUMENTS`. The first token is the Jira key; any further tokens are Figma links.

Read `flow/ORCHESTRATOR.md` and follow it exactly for this key: **Start** if `runs/<KEY>/status.md` doesn't exist, otherwise **Resume**. Run every step in `flow/steps/registry.md` in order (01 → 02 → 03 → 04), stopping only at questions and gates. To start over instead, the user runs `/restart-ticket <KEY>`.

Claude Code specifics:
- Ask questions and gates with the AskUserQuestion tool, up to 4 questions per call. Gates 3 (commit) and 4 (push) each need their own explicit yes.
- Run roles as sub-agents with the Agent tool. Pass only the ticket key (plus the service, for developers) and the input file paths:
  - steps 01–02: `requirements-analyst`, `code-scout`, `backend-planner`, `frontend-planner`
  - step 03: `backend-developer` (once per service), `api-tester`, `frontend-developer`, `ui-tester`
  - step 04: `deployment-writer` (once per side: `backend`, `frontend`)
- Jira: the `atlassian` MCP. Reads with all fields. Writes only per `config/jira.md` → Workflow writes to Jira:
  - step 01 claim: `getTransitionsForJiraIssue` + `transitionJiraIssue` to "In Development" if the ticket is in To Do; if unassigned, `atlassianUserInfo` for your account id, then `editJiraIssue` with only `assignee`
  - step 03: `transitionJiraIssue` to "Code Review" after a successful push
- Figma: whichever Figma MCP is connected (`figma` or `plugin:figma:figma`).
- VPN preflight (`flow/playbooks/vpn.md`): run `vpn up` in the foreground with a Bash `timeout` of 200000 ms. The default 120 s is shorter than its sign-in wait.
- Step 03: start local services and the web dev server with Bash `run_in_background`, and stop them when done. Browser tests use the `playwright` MCP, headed; the user logs in themselves.
