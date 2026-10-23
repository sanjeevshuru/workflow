# Step 01: Requirements

## Purpose
Turn the Jira ticket, the source documents and the designs into one agreed requirements file with no open questions. That file is the single source of truth for every later step.

## Inputs
- Ticket key `<KEY>`
- Optional Figma links from the start command (`status.md` → Inputs)
- `sources/` (BRD, PRD, tech spec) and `sources/INDEX.md`

## Actions

### 1. Read the ticket (orchestrator, Jira MCP)
1. Fetch the issue with the Jira MCP, requesting **all fields with their names**, as in `config/jira.md` → How to fetch an issue. The default fetch omits custom fields such as **Figma**. Get:
   - the standard fields: key, summary, type, status, priority, labels, components, description, acceptance criteria, comments, parent/epic, linked issues, sub-tasks, and the attachments list
   - **every custom field**, handled per `config/jira.md`: known fields go to their mapped place, unknown non-empty fields go to Custom fields, and every field value is scanned for Figma and other URLs
2. If the parent epic or a linked issue defines requirements (for example the epic description, or a "blocked by" relation), fetch it too, the same way (all fields). Figma links on the epic count as well.
3. If the Jira MCP is unavailable, follow `setup/mcp.md` → "When an MCP is unavailable". Record this in `status.md` → Notes.
4. **Claim the ticket** (`config/jira.md` → Workflow writes to Jira):
   - If its status is in the **To Do** category, move it to **In Development**.
   - If it's **unassigned**, assign it to the current user.

   Don't ask first: picking the ticket is the go-ahead. Tell the user in one line what changed (or that nothing needed to), and record it in `status.md` → Jira. If a write fails, report it and continue. Then re-read the status and assignee for `ticket.md`.
5. **Bug?** If the Jira type is **Bug**, ask before anything else: switch to the bug-fix flow (`flow/BUGFIX.md`: root cause, fix, regression test), or continue with this flow? On a switch, set `status.md` → `flow: bugfix` and continue at `flow/BUGFIX.md` → B1 → 4.
6. Write `runs/<KEY>/ticket.md` from `flow/templates/ticket.md`:
   - Number the acceptance criteria AC1, AC2, …, quoting the ticket's wording.
   - If the ticket has no AC, derive **candidates** from the description, mark each `(proposed)`, and add a question asking the user to confirm them. Proposed AC are not agreed AC.
   - Quote rather than paraphrase when the wording matters.
   - Record in the header `Fields fetched: all (N custom fields non-empty)`, so a later resume can tell a full fetch from a partial one.

### 2. Triage scope (orchestrator)
Decide early whether this ticket includes frontend work. That decides whether any Figma work happens at all.

1. Propose a scope of `backend`, `frontend` or `fullstack` from the ticket alone:
   - summary and title prefixes (for example "Backend …", "FE …", "[API]")
   - labels, components, issue type
   - description and AC wording (endpoints and validation rules vs screens and interactions)
   - each service's **Keywords** in `config/services.md`

   Cite what drove the decision.
2. A Figma link alone does **not** make a ticket frontend. Backend stories often link the screen they serve, as context.
3. Ask the user to confirm the scope. Do this now, as its own question, before any other work. Record the answer as `Q1` in the Decisions log (create `requirements.md` from its template if it doesn't exist yet). Also record it in `status.md` → Scope (`type`, `source: triage Q1`).
4. If the user says backend-only, skip action 3 and go straight to action 4 (Analyse the sources). Do not create `figma-flow.md` and do not call the Figma MCP.
5. **Sync the in-scope repos**: follow `flow/playbooks/repo-sync.md`.
   1. From the confirmed scope and `config/services.md` (Owns / Keywords), list the candidate repos (`backend`: backend services, `frontend`: closio-web-v2, `fullstack`: both).
   2. Check out each one's development branch and pull it.
   3. Uncommitted changes: stop and ask each time.
   4. Merge conflicts, a half-finished merge or rebase, or a diverged development branch: stop and ask the user to resolve it themselves (`repo-sync.md` → Merge conflicts). Never resolve conflicts, abort or continue an operation yourself. Wait for the user's "resolved", then re-check that repo.

   No repo code is read before this is done. Record the results in `status.md` → Repo sync.

### 3. Build the Figma flow manifest (orchestrator), only if scope is `frontend` or `fullstack`
Follow `flow/playbooks/figma.md` → Part 1 (collect, expand, manifest). This writes `runs/<KEY>/figma-flow.md`. If the frontend is in scope but there are no Figma links, write "No designs: <reason>" in that file and add a question asking for the designs.

For a `backend` ticket, skip this step. List any Figma links in `ticket.md` → Figma links found as **reference only**, and never fetch them.

### 4. Analyse the sources (role: `requirements-analyst`)
Run the role (see `flow/ORCHESTRATOR.md` → Running a role).
- Inputs: `runs/<KEY>/ticket.md`, `runs/<KEY>/requirements.md` (keep the triage `Q1`), `runs/<KEY>/figma-flow.md` (only if it exists), `sources/INDEX.md`, and the confirmed scope from `status.md` → Scope
- Output: `runs/<KEY>/requirements.md` (open questions are a **draft** until action 5 has run)

### 5. Check the code (role: `code-scout`)
**No question goes to the user before this runs.** Run the role.
- Inputs: `runs/<KEY>/ticket.md`, `runs/<KEY>/requirements.md`, `status.md` → Scope, `config/services.md`
- Outputs: `runs/<KEY>/codebase.md`. It also updates `requirements.md`: code-answerable questions move to **Resolved from code** (RC1…), and the rest get **Checked in code** evidence.

### 6. Resolve questions (orchestrator)
1. Read the remaining Open questions in `requirements.md`, including those from the Figma manifest if there is one. Only ask questions whose **Checked in code** column is filled.
2. Ask them per `flow/rules.md` → Asking the user. Ask the ones that block the most first.
3. Record the answers as `Q<n>` in the Decisions log. Close the matching open question and mark it `→ Q<n>`.
4. If answers change the picture (a new doc to read), re-run the analyst with the updated file. It appends; it does not start over. Then re-run `code-scout` on the new open questions only.
   - If an answer changes the scope, update `status.md` → Scope. If the scope now includes frontend and `figma-flow.md` doesn't exist, run action 3. Also re-run `code-scout` so it covers the new repos.
5. Repeat until Open questions is empty. For each question the user explicitly defers, record the answer as "deferred by user" together with its impact.

### 7. Gate 1: Requirements approved
Present:
- Scope (`backend` / `frontend` / `fullstack`), then 3–5 bullets, and what is explicitly out of scope
- The AC list, final wording
- Decisions made (Q1…Qn), one line each
- **Resolved from code** (RC1…RCn), one line each with its citation, in two groups:
  - **Code facts**: what exists and how it works today
  - **Conventions adopted**: behaviour taken from the sibling (named)

  The user can overrule any of them. An overruled item becomes a `Q<n>`, and a lesson is proposed (`flow/ORCHESTRATOR.md` → Learning).
- Existing work found for this ticket (branches or commits), if any
- The Figma flow (frontend or fullstack only): node count, order, any node not in scope
- Any "deferred" item and its risk

Ask: "Approve requirements for <KEY>?" Only an explicit yes passes the gate.

## Outputs
`runs/<KEY>/ticket.md`, `runs/<KEY>/requirements.md`, `runs/<KEY>/codebase.md`, `runs/<KEY>/figma-flow.md` (frontend or fullstack only), and `status.md` updated (including Scope).
