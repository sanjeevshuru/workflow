---
name: restart-ticket
description: Force the ticket workflow to restart from scratch for a Jira key. The previous run is moved to runs/_archive/, never deleted. Use when the user says "restart <KEY>" or "start over <KEY>".
argument-hint: <JIRA-KEY> [figma-link ...]
---

Arguments: `$ARGUMENTS`. The first token is the Jira key; any further tokens are Figma links.

Read `flow/ORCHESTRATOR.md` → **Restart (forced)** and follow it exactly, then continue with the normal flow. Claude Code specifics are the same as the `run-ticket` skill: AskUserQuestion for questions and gates, the Agent tool for roles, all steps through Gate 4.
