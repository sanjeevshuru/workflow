# Dev workflow: agent instructions

This folder is a markdown-driven, human-gated dev workflow. The same instructions run in Claude Code, Codex, Cursor and Antigravity. No program runs it: you, the agent, read these files and follow them.

## Routing

| The user says | Do |
|---|---|
| "run <KEY>" / "start <KEY>" / "plan ticket <KEY>" / `/run-ticket <KEY> [figma links...]` | Read `flow/ORCHESTRATOR.md`: Start if `runs/<KEY>/` doesn't exist, otherwise Resume. Run every registered step (01 → 02 → 03 → 04), stopping only at questions and gates |
| "resume <KEY>" / "resume" | Read `flow/ORCHESTRATOR.md` → Resume |
| "restart <KEY>" / `/restart-ticket <KEY>` | Read `flow/ORCHESTRATOR.md` → Restart (forced): set the old run aside and start from scratch |
| "implement <KEY>" | Same as `/run-ticket <KEY>`: Resume. If Gate 2 is approved this continues in step 03; if not, the earlier steps finish first |
| "deployment doc <KEY>" | Read `flow/ORCHESTRATOR.md` → Resume, then run step 04 (`flow/steps/04-deployment-doc.md`). It needs Gate 4 approved first |
| "approve" / "yes" / "proceed" at a gate | Pass the gate as described in the current step |
| "review MR" / "review <KEY>" / `/review-mr [MR url \| KEY]` / "resume review <KEY>" | Read `flow/REVIEW.md` and follow it (state in `reviews/<KEY>/`) |
| "archive <KEY>" / "reopen <KEY>" | Read `flow/ORCHESTRATOR.md` → Keeping plans until the ticket is done |
| anything else about a ticket in `runs/` | Read `runs/<KEY>/status.md` first (or `runs/_archive/<KEY>/status.md`) |

## Always-on rules

1. Follow `flow/rules.md` (never assume, cite everything, reuse before new, gates). It overrides convenience. Code is analysed with `flow/playbooks/code-analysis.md`.
2. Everything a step produces goes in files under `runs/<KEY>/`. Never rely on chat memory across steps or roles.
3. Writes to code repos and Jira are tightly limited:
   - **Steps 01–02** are **read-only** toward code repos and Jira, with two exceptions:
     - `flow/playbooks/repo-sync.md`: fetch, check out the development branch, `pull --ff-only`, and stash only when the user chooses it
     - the step 01 **claim** in Jira: To Do → In Development, and assign to the current user if unassigned (`config/jira.md` → Workflow writes to Jira)
   - **Step 03** may write to repos only through `flow/playbooks/git.md`:
     - create the feature branch after Gate 2
     - edit code on the feature branch (the developer roles)
     - commit only after the user's yes at Gate 3
     - push and open MRs only after the user's yes at Gate 4
   - No force pushes, no pushes to protected or development branches, no merges, rebases or `--no-verify`.
   - **Step 04** (deployment doc) is read-only toward repos and Jira. It writes only to `runs/<KEY>/`, plus `config/deployment.md` when the user answers a dev-deploy question.
   - Jira: the only writes are the step 01 claim (above) and moving the ticket to **Code Review** after a successful push. Never comment, edit other fields or add links.
   - **MR review** (`flow/REVIEW.md`) is read-only toward the user's repos and Jira: `git fetch`, plus temporary review worktrees outside the repo folders that are removed after each round. Never a checkout, stash or rebase in the user's own working trees. Its only GitLab write is posting review comments through `flow/playbooks/mr-review.md`, after the user's yes at Gate R. It never approves, merges or resolves threads.
4. Service repos live beside this folder. Their paths, stacks and conventions are in `config/services.md`. Jira site and field handling are in `config/jira.md`. A repo's own `CLAUDE.md` / `AGENTS.md` / `SKILLS.md` take precedence over generic patterns.
5. Tool names differ between hosts. When a file says "Jira MCP" or "Figma MCP `get_metadata`", use whatever tool your host exposes for that server. If it is not available, follow `setup/mcp.md` → "When an MCP is unavailable".
6. The workflow learns from its mistakes: `lessons/backend.md`, `lessons/frontend.md` and `lessons/workflow.md` are read by the roles for their scope. New entries are added only after the user approves (`flow/ORCHESTRATOR.md` → Learning).
7. Repo knowledge lives in `knowledge/<service>.md` (repo profiles). `code-scout` derives and refreshes them from the code, because many repos have no `completed.md`, `lessons.md` or agent files.
