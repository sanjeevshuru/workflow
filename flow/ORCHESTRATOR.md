# Orchestrator

You run the flow for one ticket (`<KEY>`, e.g. `SCRUM-512`). You own every interaction with the user. Roles do focused work and report through files.

## Start
0. **VPN preflight**: follow `flow/playbooks/vpn.md`. GitLab needs the VPN, and `vpn up` connects it (it may open a Microsoft sign-in in the browser). Record the result in `status.md` → Network once that file exists.
1. Read `flow/rules.md`, `flow/steps/registry.md` and `lessons/workflow.md`. Apply the workflow lessons throughout the run.
2. If `runs/<KEY>/status.md` exists, go to **Resume** instead.
3. Create `runs/<KEY>/`, and create `status.md` from `flow/templates/status.md`.
4. If the user passed Figma links with the start command, write them to `status.md` → Inputs.
5. Run the first step in the registry.

## Running a step
1. Read the step file (`flow/steps/<NN>-<name>.md`) completely before acting.
2. Set `current_step` and `step_status: in_progress` in `status.md`.
3. Follow the step. When it says "run role X", see **Running a role**.
4. At the step's gate, present the summary it asks for and wait for approval (`flow/rules.md` → Gates).
5. On approval, record it in `status.md` → Gate log, then move to the next step in the registry.
6. After the last registered step, tell the user the flow is complete for now and list the output files.

## Running a role
Roles live in `flow/roles/<role>.md`. Each role reads only the files it is given and writes one output file.

- **Host has sub-agents** (Claude Code: the Agent tool with the matching `.claude/agents/<role>.md`, for example `requirements-analyst`, `code-scout`, `backend-planner`, `frontend-planner`, in step 03 `backend-developer`, `frontend-developer`, `api-tester`, `ui-tester`, and in step 04 `deployment-writer`; Codex or others if supported): spawn the role. Pass the ticket key and the input file paths only, not your conversation. When it returns, read its output file.
- **No sub-agents** (Cursor, Antigravity, or as a fallback): run it **sequentially**:
  1. Say "Switching to role: <role>".
  2. Read `flow/roles/<role>.md`, do only that role's job, and write its output file.
  3. Say "Back to orchestrator", then read the output file as if someone else wrote it.
- After any role, check the top of its output file. If it says `STATUS: BLOCKED`, ask the user its questions, append the answers to `requirements.md` → Decisions log, and re-run the role.

## Restart (forced)
Triggered by "restart <KEY>" or `/restart-ticket <KEY> [figma links…]`. The user wants a clean run, not a resume.
1. Don't ask again; the command is the confirmation. If `runs/<KEY>/` doesn't exist, just **Start**.
2. **Set the old run aside, never delete it.** Move `runs/<KEY>/` to `runs/_archive/<KEY>__restarted-<YYYYMMDD-HHMM>/`, and add a Lifecycle log row there ("restarted by user"). If it's already in `runs/_archive/<KEY>/` (archived), leave it there.
3. **Start** from scratch: a new `status.md`, step 01 from action 1. That re-fetches the ticket with all fields, re-asks the scope triage, and re-syncs the repos (`flow/playbooks/repo-sync.md`). Nothing from the old run is reused: no answers (`Q<n>`), no RCs, no plans.
4. Keep the shared knowledge: `knowledge/<service>.md` repo profiles and `lessons/*.md` are not reset. They aren't per ticket.
5. Add a Notes line in the new `status.md`: "Restarted; previous run at `runs/_archive/<KEY>__restarted-<…>/`". Tell the user in one line where the old run went.

If the user wants a fresh analysis but to **keep their answers**, that's not a restart. Resume and re-run the roles instead.

## Resume
0. **VPN preflight**: follow `flow/playbooks/vpn.md` and record the result in `status.md` → Network. The tunnel doesn't survive sleep or a new session.
1. Read `runs/<KEY>/status.md`: `current_step`, `step_status`, Gate log, Repo sync, Notes.
   - Re-sync the in-scope repos (`flow/playbooks/repo-sync.md` → On resume) before any role reads code. In step 03 this doesn't apply to repos on their feature branch (see below). If new commits touch files the plans rely on, ask whether to re-run `code-scout` and the affected planner.
   - A status file without a `lifecycle` field is an older run: treat it as `active` and add the field.
   - A status file without a **Jira** → Claim line predates the claim: do the step 01 claim now (`config/jira.md` → Workflow writes to Jira). It only changes a ticket that's still in To Do or unassigned.
   - An older run whose `ticket.md` has no `Fields fetched: all` line was fetched without custom fields. Re-fetch the ticket per `config/jira.md` and merge in what's new: Figma links, custom fields, links. If new Figma links appear on a frontend or fullstack ticket, rebuild `figma-flow.md`. Close any open question the new data answers (for example "no Figma link"), and tell the user what changed.
   - An older run whose `codebase.md` has no **Sibling (mandatory)** or **Reusable inventory** section predates the code-analysis playbook. Before asking any further questions, re-run `code-scout` on the still-open questions.
   - An older run in step 01 without `codebase.md` must run `code-scout` (step 01 → action 5) before any more questions are asked.
   - An older `status.md` without the **Branches** / **Implementation** sections: add them from the template when step 03 starts. Without a **Deployment doc** section: add it when step 04 starts.
   - **Inside step 03**, resume from the checkpoints in `status.md` → Branches and Implementation:
     - **Repos**: check every repo against them (`flow/playbooks/git.md` → On resume): the feature branch is checked out, `HEAD` and the commits match, and repos recorded as pushed are never pushed again. Don't re-sync a repo that's on its feature branch with work in progress; repo-sync applies to development branches only.
     - **Tasks**: re-run a developer role only for the tasks not yet ticked.
     - **Cleanup pending**: run the cleanup first (`config/postman.md` → Test data).
     - **Services and the dev server** aren't kept between sessions. Start them again for the next Postman or browser run.
   - **Step 04 / after Gate 5**: if a repo's pushed hash in `status.md` → Implementation is newer than the one in a deployment doc's header (new commits went through Gates 3 and 4), mark that doc `stale` in `status.md` → Deployment doc, and re-run step 04 for that side (`flow/steps/04-deployment-doc.md` → Keeping it current).
2. Read the step file for `current_step` and the outputs already written.
3. Tell the user where things stand in 2–3 lines, then continue from the first unfinished action.
4. Never redo an approved gate unless the user asks.

A run can start in one tool and resume in another. `runs/<KEY>/` is the only state.

## Learning (lessons)
The workflow learns from corrections. Lessons live in `lessons/backend.md`, `lessons/frontend.md` and `lessons/workflow.md`, kept separate. Roles read the file(s) for their scope; you read `workflow.md`.

**Triggers.** Draft a lesson when any of these happen:
- The user **overrules an RC** (a code fact or adopted convention was wrong).
- The user says something **exists or works differently** from what a role claimed, for example "this already exists".
- A question the user got turns out to be **answerable from code or the sibling**. The user says "follow existing", or the answer is in code.
- A plan is **sent back for rework**, or a gate needs **more than one round** for the same issue.
- The user corrects a **repo profile** entry (`knowledge/<service>.md`), for example a pattern or anti-pattern derived wrongly. Fix the profile too.
- A **process** failure: a missed Jira field, wrong scope triage, a wasted Figma call, a bad resume.
- **Step 03**: a developer role returns BLOCKED because the **plan was wrong** (a missed sibling detail, wrong contract, wrong file). A Postman or browser failure traces back to the plan or a wrong RC. A hook or coverage failure that the plan's Tests section should have foreseen. The user rejects proposed commits or finds unexplained changes.

**Procedure:**
1. Pick the file: backend or frontend for stack-specific analysis and planning mistakes, workflow for process mistakes.
2. Draft the entry with the template at the top of that file. The "Rule going forward" must be something a role can act on next time.
3. Show it to the user: "Proposed lesson for lessons/<file>.md: … Add it?" Write it **only on an explicit yes**. Edit it if the user corrects it.
4. Record the outcome in `status.md` → Lessons (`proposed / accepted / declined`).
5. If the rule also belongs in a repo's own `lessons.md` (a coding rule for that repo), say so in the entry. Don't write it to the repo's `lessons.md` yourself. Only the developer roles edit repos in step 03, and only for plan tasks. The user decides whether the repo file changes.

Propose lessons when a trigger happens, or batch them at the next gate. Don't interrupt a question round for them.

## Keeping plans until the ticket is done
`runs/<KEY>/` is the ticket's record. It's committed to git and stays **active** after the last step, until the ticket is implemented.
- **Never delete** a run folder or a plan file. Plans are only changed through their **Plan changelog**.
- **Living plans**: if something changes after Gate 2, update the affected plan, add a changelog row, and re-present only the changed part for approval. Examples: a requirement changes, a new code fact turns up, or implementation shows the plan is wrong. Future steps (implementation, review) read the plans from here.
- **After step 03** (pushed, in Code Review), the run stays active. MR review changes are made by resuming, on the same branch, through Gates 3 and 4 again.
- **Done** means the user says the ticket is implemented (e.g. the MRs are merged), or the Jira MCP shows the ticket in a done status category. In the Jira case, ask the user to confirm; don't archive automatically.
- **Archive** (the user says "archive <KEY>", or confirms the prompt above): move `runs/<KEY>/` to `runs/_archive/<KEY>/`, set `lifecycle: archived`, and add a Lifecycle log row. Archived runs are read-only. "reopen <KEY>" moves the folder back and sets it to active.
- **On resume**, if `lifecycle: active` and every registered step is approved, don't restart. Show the plans' status and ask what changed.

## Changing course
- If the user changes requirements after a gate, record the change as a new `Q<n>` in the Decisions log. Mark the affected outputs stale in `status.md` → Notes, and re-run from the earliest affected step, with the user's OK.
