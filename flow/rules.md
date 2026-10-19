# Rules (apply to every step and role)

## Never assume
- If something is unclear, missing, or contradictory, **ask**. No doubt is too small.
- Never fill a gap with a "reasonable default". Convert it into a question.
- The one exception is when an existing repo convention decides the point. Then cite the file that shows the convention (`<service>:<path>`).
- If a document does not cover something, write "no relevant section in sources/". Do not infer what it "probably" says.
- If a tool call fails (MCP down, file missing), say so. Never fabricate its output.

## Code before questions
- A question must never reach the user if the in-scope code can answer it. The code is checked first, by `code-scout` in step 01 and by the planners in step 02.
- Every question put to the user states what was checked: `Checked in code: <paths> — <what they show, or "not answerable from code">`.
- Code settles two kinds of thing, both recorded as `RC<n>` (Resolved from code) with citations and **not asked**:
  - **Code facts**: how the system currently works. Existence of routes, tables, constraints or components; error codes and HTTP mapping (including ws1's 404→597); validation layers; locking; scoping.
  - **Conventions**: behaviour the **closest same-business sibling** already defines (sort order, loading, empty and error states, pagination, renderers, copy patterns, response envelope, check order, test style), **when no AC or source doc says otherwise**. Adopt the sibling's behaviour and cite `convention: <sibling path:lines>`.

  Both are shown at the requirements gate, and the user can overrule any of them.
- Questions still go to the user only for:
  - **contradictions**: an explicit AC or doc vs the code or sibling
  - **siblings that disagree**
  - **business or policy decisions**
  - **missing designs or contracts** that nothing in code or sources defines
- Code never settles business decisions, and never overrides an explicit AC or source-doc statement.

## Reuse before new
- Follow `flow/playbooks/code-analysis.md`. Every plan element reuses, configures, extends or composes something that exists. "New" is allowed only with the recorded searches that found nothing.
- **Absence claims** ("X doesn't exist", "only Y exists") must list the grep terms, the directories searched, and the `completed.md` check. An unproven absence claim is a defect.
- **Deviations** from the sibling (stricter, looser, "better") are labelled `deviates from <sibling>`, with the reason and source. Never mark a deviation "(Recommended)", and never adopt one silently.
- **Undocumented repos**: missing `completed.md`, `lessons.md` or conventions files don't lower the bar. The knowledge is derived from code into `knowledge/<service>.md` (playbook §1A). A derived pattern with fewer than 3 consistent examples is `low confidence`: it can be cited, but it can't be auto-adopted as a convention RC. Anything in a profile's anti-patterns or legacy areas is never copied.
- **Business boundary**: Business 1 work follows Business 1 siblings. Never borrow Business 2 behaviour or helpers.

## Cite everything
Every requirement-level statement in `requirements.md`, `backend-plan.md` and `frontend-plan.md` ends with at least one citation:

| Citation | Meaning |
|---|---|
| `[AC3]` | Acceptance criterion 3 in `runs/<KEY>/ticket.md` |
| `[Q5]` | Answer 5 in `runs/<KEY>/requirements.md` → Decisions log |
| `[RC2]` | Item 2 in `runs/<KEY>/requirements.md` → Resolved from code |
| `[lesson: frontend#2026-10-01 Title]` | An entry in `lessons/frontend.md` (or `backend.md`, `workflow.md`) |
| `[src: sources/prd/orders.md#Bulk upload]` | A section of a source doc |
| `[code: ws2closio:src/services/order.service.js]` | Existing code or convention |
| `[figma: F3]` | Row F3 in `runs/<KEY>/figma-flow.md` |

A statement without a citation is not allowed. Either find the source or turn it into a question.

## Repo state
- Code is analysed on the **latest development branch** of each in-scope repo (`flow/playbooks/repo-sync.md`), never on whatever branch a repo happens to be on.
- Uncommitted changes are never stashed, discarded or committed without the user's choice.
- Merge conflicts are never resolved by the agent. Stop, list the conflicted files and let the user resolve them (`flow/playbooks/repo-sync.md` → Merge conflicts).
- Findings from a repo the user chose not to sync are marked with the branch they came from.

## Writing code (step 03)
- **The approved plan is the spec.** Implement its tasks, mirroring the cited siblings. Anything the plan doesn't cover, or gets wrong, goes back as `STATUS: BLOCKED`, then becomes a **Plan changelog** row re-approved by the user. Never improvise silently.
- **Tests are evidence, not decoration.**
  - Run the repo's full commands and copy the totals from real output.
  - Never weaken, skip or delete a test, lower a coverage threshold, or bypass a hook to get green.
  - A Postman or browser case changes only when its expectation was wrong, with a cited reason.
- **Report honestly.** Numbers come from the last real run. Unrun, mocked or manual results are labelled as such. Unresolved failures are listed, not hidden.
- **Git and Jira writes** only through `flow/playbooks/git.md`, at the gates (AGENTS.md rule 3).
- **Shared data**: seed SQL runs only after the user's yes, and the cleanup always runs (`config/postman.md` → Test data).

## Secrets
`runs/` and `reviews/` are committed to git. Never write tokens, cookies, passwords, session IDs, or auth headers into any file. If a ticket or comment contains one, write `[REDACTED: <kind>]` and add a note in `status.md` → Notes.
- **Step 03:**
  - Test secrets come from the user's shell by **name** (`AIFLOW_*`, `config/postman.md`) and are passed on the command line. They never go into collections, environments, reports or `status.md`.
  - Run output is redacted before anything reads it.
  - Never read or print `.env` values; overrides go in the process environment.
  - Never commit `.env*` files (except closio-web-v2's tracked flag files, when the plan says so) or anything that contains a secret.
  - Browser logins are done by the user. Cookies and storage state are never saved.

## Asking the user
- Ask in batches of up to 4 related questions. Each question says **why it matters** and gives the **options** when they are known. Mark a recommended option only if a source supports it, and cite that source.
- Claude Code: use the AskUserQuestion tool. Other hosts: post a numbered list in chat.
- After asking, **stop and wait**. Do not continue the step on an unanswered question.
- Record every answer as `Q<n>` in `runs/<KEY>/requirements.md` → Decisions log, quoting the user's words.

## Gates
- A gate needs explicit approval ("approve", "yes", "proceed"). Silence or a new topic is not approval.
- If the user requests changes, apply them and re-present. The step does not advance.
- Record every gate result in `runs/<KEY>/status.md`.
- **Gates 3 (commit) and 4 (push)** each need their own explicit yes. A yes covers only what was shown. New commits, another repo, or a re-push after a fix round need a new yes. Approving the plans (Gate 2) covers creating branches, nothing more.
- **Gate R (MR review)**: review comments are posted only after an explicit yes, and the yes covers only the comments shown, with the text shown. Each round needs its own yes. Gate R results are recorded in `reviews/<KEY>/status.md`.
- **Gate 5 (deployment doc)**: the doc is approved only on an explicit yes. A regenerated (stale) doc needs a new yes.

## Roles and sub-agents
- Roles talk to each other only through files in `runs/<KEY>/`.
- A role that cannot finish without an answer writes `STATUS: BLOCKED` plus its questions at the top of its output file and stops. Only the orchestrator talks to the user.
