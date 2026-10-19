---
name: review-mr
description: Review the oldest open GitLab MR where you are a reviewer (or a given MR url / Jira key) — groups the ticket's backend (ws2 + ws1) and frontend MRs, reads the Jira ticket and tech spec, checks AC coverage, spec conformance, anti-patterns and reuse, then posts review comments on the MR after your approval. Use when the user says "review MR", "review <KEY>" or pastes an MR link to review.
argument-hint: "[MR url | JIRA-KEY]"
---

Arguments: `$ARGUMENTS`. Empty means pick the oldest MR waiting for your review; an MR url or a Jira key picks that one.

Read `flow/REVIEW.md` and follow it exactly, with `flow/playbooks/mr-review.md` for every glab call. Claude Code specifics:
- GitLab only through the `glab` CLI in the fixed command shapes of the playbook. Reads are `glab api --hostname …`; posts are `glab api -X POST --hostname …`, and only after the yes at Gate R.
- Ask questions and Gate R with the AskUserQuestion tool. Show every comment's text before asking to post.
- VPN preflight (`flow/playbooks/vpn.md`): run `vpn up` in the foreground with a Bash `timeout` of 200000 ms. The default 120 s is shorter than its sign-in wait.
- **Host code review** first: check that the `code-review` skill (or the plugin's `code-review:code-review`) is in your available skills. If neither is, stop and ask the user to install it (`claude update`, or `/plugin` → code-review) before anything else. Run it yourself with the Skill tool on each MR's review worktree: `skill: "code-review"`, `args: "<worktree path> high"`. Never pass `--comment`, `--fix` or `ultra`. Save its output to `reviews/<KEY>/r<n>/code-review-<service>.md`.
- Run roles as sub-agents with the Agent tool: `backend-reviewer` (once for all backend MRs of the ticket), `frontend-reviewer` (once for the closio-web-v2 MR). Pass only the key, the round, and the input file paths.
- Jira: `atlassian` MCP read tools only (`getJiraIssue` with all fields). No transitions, no comments.
- Repos: `git fetch`, the branch-state check, and the temporary review worktrees under `.aiflow-review/` (playbook). Never check out, stash, pull or rebase in the user's repos; their working trees may hold uncommitted work. Remove the worktrees when the round ends.
- **Rebase first**: if any reviewed MR is behind its target (development) branch or has conflicts, stop before reviewing. Show the rebase notice, post it after the user's yes, and end the round as `waiting for rebase`. The review starts on a later run, after the author pushes the rebased branch.
