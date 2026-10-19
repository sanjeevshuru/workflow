# Ticket workflow

Give it a Jira ticket and it takes it all the way to tested code and merge requests. It asks you before every important decision. It can also review your teammates' MRs for you.

It works the same in **Claude Code, Cursor, Antigravity and Codex**. There's nothing to install or run. Your AI tool reads the instructions in this folder and follows them.

## What it can do

- **Run a ticket end to end**: read the ticket, designs and specs, ask only the questions the code can't answer, plan the backend and frontend, write the code with tests, test it, commit, push and open MRs, then write the deployment doc.
- **Review MRs**: pick the oldest MR waiting for your review, check it against the ticket and the spec, and post review comments.
- **Pause and pick up anywhere**: stop at any point and continue later, even in a different AI tool.
- **Learn from your corrections**: when you correct it, it proposes a lesson, and uses it on later tickets once you approve.

## Quick start

| What you want | Claude Code, Cursor, Antigravity | Codex |
|---|---|---|
| Work on a ticket (start, or continue where it stopped) | `/run-ticket SCRUM-123` | "run SCRUM-123" |
| Start a ticket over from scratch | `/restart-ticket SCRUM-123` | "restart SCRUM-123" |
| Review an MR | `/review-mr` (oldest waiting for you), `/review-mr <MR link>` or `/review-mr SCRUM-123` | "review MR" |

For a frontend ticket, you can add Figma links after the key: `/run-ticket SCRUM-123 <figma link> …`.

While it runs:
- **Answer** its questions.
- **Approve** a checkpoint with "yes" or "approve".
- **Change** something by just saying what to change. That part is redone, and the workflow waits for your approval again.

## Working on a ticket

`/run-ticket` goes through four steps. It stops at a ✋ checkpoint until you approve.

### 1. Requirements
1. Reads the Jira ticket with all its fields, plus the epic and linked issues. If the ticket is in **To Do**, it moves it to **In Development**, and assigns it to you if nobody has it.
2. Asks you whether it's **backend, frontend or fullstack**.
3. Updates each repo it needs to its development branch (`develop` / `development`).
   - If a repo has uncommitted changes or merge conflicts, it asks you first. It never resolves conflicts for you.
4. For frontend work, it maps out the Figma screens.
5. Finds the relevant parts of the BRD, PRD and tech specs in `sources/`.
6. Reads the code to answer as many questions as it can, with file references. Only what the code can't answer comes to you.

✋ **You approve the requirements.**

### 2. Planning
- **Backend plan**: the API contract (ws2 service, then the ws1 gateway, then what the client sees), data changes, tasks with real file paths, and the tests for each acceptance criterion.
- **Frontend plan**: each Figma screen, the components it reuses, the API calls, and how every acceptance criterion is covered.

✋ **You approve the plans.**

### 3. Implementation
1. **Branch**: the same branch in every repo, named after the ticket: `scrum-523`, or `fix/scrum-514` for a bug.
2. **Code + unit tests**: it follows the plan and the existing code style, until the tests, coverage and lint pass (Vitest and build for the frontend).
3. **API test (backend)**: a lean Postman collection, run with newman against your local services. Test data is added only after you approve the SQL, and is always cleaned up.
4. **Browser test (frontend)**: a short list of checks run in a real browser. You log in yourself.
5. **Report**: what was built, the test results, and anything left open.

✋ **You approve the commits.** The commit messages are short and descriptive, for example `feat(SCRUM-519): add ageing deduction config POST`.

✋ **You approve the push.** It then pushes, opens the MRs, moves the Jira ticket to **Code Review**, and gives you the MR links to add to the ticket.

### 4. Deployment doc
A short, step-by-step doc for whoever deploys the ticket to **dev**, saved in `runs/SCRUM-123/`:
- **Backend** (`deployment-backend.md`): what must be merged or deployed first, new env vars (names only), migrations in order, which services and worker deployments to deploy in which order, a few requests to check it works, and how to roll back.
- **Frontend** (`deployment-frontend.md`): which backend endpoints must be live first, the feature flags that changed, the build, a short checklist to try in the browser, and how to roll back.

It never invents a command or URL. The first time, it asks how dev deploys work in your team and saves the answer in `config/deployment.md`. If more commits are pushed later, the doc is regenerated.

✋ **You approve the deployment doc.**

## Reviewing an MR

`/review-mr` does this:
1. **Picks the MR**: the oldest open MR where you're a reviewer that you haven't reviewed since its last push. You can also give it an MR link or a ticket key.
2. **Groups the ticket's MRs**: a backend ticket usually has two, ws2 and ws1, and they're reviewed together.
3. **Rebase check first**: if a branch is behind the development branch or has conflicts, it **stops**.
   - After your yes, it asks the author on the MR to rebase.
   - The review happens on a later run, once the author has pushed.
4. **Reads** the Jira ticket and the matching tech spec sections.
5. **First pass** with your AI tool's code-review command: `/code-review` in Claude Code, `/review` in Codex. If it's missing, it asks you to install it.
6. **Full review** by the backend and frontend reviewers:
   - every acceptance criterion is implemented and tested
   - it matches the spec and the API contract
   - no anti-patterns
   - existing utils and components are reused
   - no stray files or secrets
   - every point from the first pass is checked, so false alarms are dropped

✋ **You see every comment before it's posted.** You can edit or drop any of them. After your yes, they go on the MR as line comments plus one summary. If nothing is wrong, nothing is posted.

When the author pushes fixes, run it again. It checks what was fixed and only adds new points.

## Pausing, restarting and finishing

| You want to | Do this |
|---|---|
| Stop for now | Just stop. Everything is saved in `runs/SCRUM-123/` (or `reviews/SCRUM-123/` for a review). |
| Continue | Run the same command again, in any AI tool. |
| Start over | `/restart-ticket SCRUM-123`. The old run is kept in `runs/_archive/`, not deleted. |
| Change the plan after approval | Say what changed. The plan is updated, the change is logged, and you approve it again. |
| Close a finished ticket | "archive SCRUM-123" (or "reopen SCRUM-123" to bring it back). |

## What it will never do

- Push or commit without your yes, force push, or push to `develop`, `development`, `main` or `master`
- Merge, rebase, skip git hooks, or approve or merge an MR
- Weaken or skip tests to make them pass
- Touch uncommitted work or resolve merge conflicts without asking you
- Read `.env` values, or save passwords, tokens or cookies anywhere
- Change Jira beyond moving your ticket to In Development (and assigning it to you if it's unassigned) and later to Code Review
- Guess. If something is unclear, it asks.

## What you need

**AI tool** (one of these): Claude Code, Cursor, Antigravity or Codex.

**Accounts and access**
- [ ] Jira (`productclosio.atlassian.net`): every step
- [ ] Figma, ideally a Dev or Full seat: frontend tickets only. View seats are limited to ~6 calls a month.
- [ ] GitLab (`jcvs.japfacomfeed.co.id`) and the **company VPN**: anything that touches the repos. On macOS the workflow can connect it for you at the start of a run (`setup/vpn.md`, one-time install by IT); otherwise connect FortiClient yourself.
- [ ] A GitLab personal access token with the `api` scope: MR review only
- [ ] Each service running locally with its own `.env`: for the step 3 tests
- [ ] A back-office login: for the browser test

**Connections in your AI tool** (MCP servers; see `setup/mcp.md`)
- [ ] Atlassian (Jira)
- [ ] Figma
- [ ] Playwright, for the browser test in Claude Code and Codex. Cursor and Antigravity use their built-in browser.

**Command-line tools**
- [ ] `git` 2.38 or newer
- [ ] Node.js 18+ and `npm` (also provides `npx newman`)
- [ ] `glab` and `jq`, for MR review
- [ ] `psql` or any DB client, for test data
- [ ] A code-review command in your AI tool, for MR review (`/code-review` in Claude Code)

## Setup

1. Put this folder next to the repos:
   ```
   Japfa/
   ├── workflow/          ← this folder
   ├── backend/nodejs-*   ← ws1closio, ws2closio, ws2targetsales, ws2notification, ws2pricingengine
   └── web/closio-web-v2
   ```
2. Install the command-line tools above, and get each service running locally once by following its own README.
3. Connect Jira, Figma and Playwright in your AI tool (`setup/mcp.md`).
4. For MR review: `brew install glab`, then on the VPN run `glab auth login --hostname jcvs.japfacomfeed.co.id` (`setup/mcp.md` → GitLab CLI).
5. Put the BRD, PRD and tech specs in `sources/` and list them in `sources/INDEX.md`.
6. Optional, macOS: the command-line VPN, so runs connect by themselves (`setup/vpn.md`). `brew install openfortivpn`, then an admin runs `sudo setup/vpn/install.sh --user <you>` once.

For the backend API test, it will ask you to set these in your terminal: `AIFLOW_WS2_CLIENT_ID`, `AIFLOW_WS2_CLIENT_SECRET`, `AIFLOW_WS1_SESSION_COOKIE`, `AIFLOW_PARTNER_ID` and `AIFLOW_USER_ID`. They're never saved to files (`config/postman.md`).

## Where things are

| Folder | What's in it |
|---|---|
| `runs/<KEY>/` | Everything for one ticket: requirements, plans, test docs and reports, deployment docs, status. Kept until the ticket is done. |
| `reviews/<KEY>/` | MR reviews and the comments that were posted |
| `sources/` | BRD, PRD and tech specs |
| `config/` | Repos and their stacks, Jira, git rules (branch names, commit messages), local test settings, dev deployment facts |
| `knowledge/` | What it has learned about each repo: patterns, anti-patterns, reusable pieces |
| `lessons/` | Lessons from your corrections (added only with your approval) |
| `flow/` | The workflow itself: steps, roles, rules, playbooks, templates |
| `setup/` | Connecting MCP servers and tools |

## For maintainers

- **One source of truth.** All logic lives in `flow/`. `AGENTS.md` holds the routing and the always-on rules. `.claude/`, `.cursor/` and `.agent/` are thin wrappers, so change a rule once, in `flow/`.
- **Roles.** Specialist roles (analyst, code scout, planners, developers, testers, reviewers) run as sub-agents where the tool supports it, and otherwise one after another in the same chat. They only talk to each other through files in `runs/<KEY>/`. Only the main agent talks to you.
- **Reading code.** The roles read code the way the repos' own agents do: conventions, `lessons.md` and `completed.md` first (or derived from the code when they're missing), then the closest existing feature, then reuse before writing anything new (`flow/playbooks/code-analysis.md`).
- **Adding a step**: create `flow/steps/<NN>-<name>.md` (Purpose, Inputs, Actions, Outputs, Gate), add any new roles to `flow/roles/`, and add a row to `flow/steps/registry.md`. If the step writes to repos or Jira, update rule 3 in `AGENTS.md`.
