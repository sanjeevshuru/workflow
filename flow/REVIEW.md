# Review: MRs where you are a reviewer

You review a teammate's merge requests for one ticket. You own every interaction with the user. The host's code-review command gives a first pass; the reviewer roles verify it and add the ticket, spec and convention checks. Only you post to GitLab, and only after Gate R.

This is a separate entry point from the ticket steps (`flow/steps/`). It never changes `runs/<KEY>/`. If that folder exists (the ticket was planned with this workflow), it is read as extra context.

GitLab and git mechanics (glab commands, worktrees, branch state, the host review command, payloads, never-list) are in `flow/playbooks/mr-review.md`. Read it before R0.

## Writes allowed in a review
- Repos: `git fetch`, and one **temporary review worktree** per MR outside the repo folder (playbook → Review worktree), removed when the round ends. The user's own working trees and branches are never touched: no checkout, stash, pull, merge or rebase in them.
- Jira: none. Read the ticket only.
- GitLab: posting the rebase notice, or the review comments (discussions and one summary note per MR), only after the user's yes at Gate R.
- Files: `reviews/<KEY>/` only.

## Start
Triggered by "review MR", `/review-mr`, `/review-mr <MR url>` or `/review-mr <KEY>`.
1. Read `flow/rules.md`, `flow/playbooks/mr-review.md` and `lessons/workflow.md`.
2. **R0. Preflight** (playbook → Preflight):
   - VPN: follow `flow/playbooks/vpn.md` first. It connects with `setup/vpn/vpn up` if GitLab isn't reachable.
   - glab is installed and logged in to the GitLab host, and you have the username. If not, stop and point the user to `setup/mcp.md` → GitLab CLI.
   - The host's **code-review command** is available (playbook → Host code review). If it isn't installed or enabled, **stop and ask the user to install it first**, with the install step for this host. Continue only when it's available, or if the user explicitly says to review without it (record that in `status.md` → Notes).
3. With an MR url: skip R1 and use that MR. With a key: skip R1 and go to R2 for that key.

## R1. Pick the MR
1. List open, non-draft MRs where the user is a reviewer, oldest created first (playbook → List my review MRs).
2. Keep only MRs whose project is a repo in `config/services.md`: compare the MR's project path (`references.full`, before the `!`) with each service repo's `git remote get-url origin`. Others are listed as "not a configured repo" and ignored.
3. Skip MRs **already reviewed** by the user (playbook → Already reviewed): the user approved it, or the user has a non-system note newer than the MR's latest version (pushed after your last comment counts as not reviewed). An MR waiting for the author's rebase is skipped the same way, until the author pushes.
4. Show at most 5 candidates in one line each (`project!iid · KEY · title · created`), say which one is picked (the oldest remaining), and continue. The user can name another one instead.
5. If none remain, say so and stop.

## R2. Group the ticket's MRs
1. Get the Jira key from the source branch (`scrum-<n>`, `fix/scrum-<n>`, older `scrum-<n>-<summary>`, or another project key the same way), else from the title. If none is found, ask the user for the key, or whether to review without a ticket (code-only review, no AC matrix).
2. Find every open MR for the key in the configured projects (playbook → MRs for a key).
3. Classify each:
   - **reviewed**: the user is a reviewer on it. Findings can be posted here.
   - **context only**: same ticket, the user isn't a reviewer. Read for the contract cross-check, never commented on.
4. Order: backend ws2 services first, then ws1closio; then closio-web-v2. A backend ticket usually has two MRs (ws2 + ws1). If only one side has an MR, the reviewer notes the other side as missing.
5. Show the group to the user in 2–4 lines and continue.

## R3. Set up `reviews/<KEY>/`
1. **New review**: create `reviews/<KEY>/status.md` from `flow/templates/review-status.md`.
   **Existing review**: read `status.md`. If every reviewed MR's head SHA equals the last round's, tell the user it's already reviewed at this commit and ask whether to review again anyway. If a head moved, start round n+1 (R10).
2. Record each MR (playbook → MR details): project, iid, URL, author, source → target branch, `diff_refs` (base, start, head SHA), pipeline status, GitLab merge status, reviewed or context.

## R4. Fetch the code and check the branch: rebase first
Run this before any other review work. For each MR's repo (paths in `config/services.md`):
1. `git -C <path> fetch origin <source_branch> <target_branch>` (playbook → Fetch). Check that `<head_sha>` and `<base_sha>` are present. On a network error, run `flow/playbooks/vpn.md` → Retry once on a network error. If the repo isn't cloned, or the fetch still fails, ask: retry, or abort.
2. **Branch state** (playbook → Branch state): how many commits the source branch is behind the latest target (development) branch, and whether it merges into it without conflicts (the conflicted files, if any). Cross-check with GitLab's merge status. Record it in `status.md` → MRs (`up to date`, `behind <n>`, or `conflicts: <files>`).
3. **Every reviewed MR is up to date**: continue with R5.
4. **Any reviewed MR is behind or conflicting**: **stop. Don't review the code.** No ticket or spec reading, no worktree, no host review, no roles, for any MR of the ticket. A backend pair is reviewed together, so one stale MR holds both.
   1. Prepare the **rebase notice** (playbook → Branch notice) for each reviewed MR that isn't up to date. It asks the author to rebase onto the latest target branch, resolve any conflicts, and push, and says the review starts after that.
   2. **Gate R (rebase notice)**: show the branch state of every MR and each notice exactly as it will be posted. The user can edit the text. Ask: "Post the rebase notice on <project!iid, …> and stop the review until it's rebased?" Only an explicit yes posts.
   3. On the yes: post each notice as a general discussion (playbook → Post comments → Branch notice) and record it in `status.md` → Posted. Without a yes, post nothing.
   4. Record the round as `waiting for rebase` (`status.md` → `round_status`, Rounds and Gate log). Tell the user the review starts once the author pushes the rebased branch: run `/review-mr <KEY>` again then. Stop.
   - A **context-only** MR that is behind doesn't stop the review. Note its state; its code may shift.
   - The user may explicitly say to review anyway. Then record "reviewed before rebase (user)" in `status.md` → Notes and continue with R5.

## R5. Read the ticket and spec
1. Fetch the ticket per `config/jira.md` → How to fetch an issue (all fields with names, epic and requirement-defining links too) and write `reviews/<KEY>/ticket.md` from `flow/templates/ticket.md`. If it's already there, re-fetch and update it. If the Jira MCP is unavailable, follow `setup/mcp.md` → "When an MCP is unavailable".
2. Pick the tech spec sections: from `sources/INDEX.md` choose the docs whose modules match the ticket, then the sections the ticket cites or that match its endpoints and screens. Apply the business boundary: a Business 1 ticket never uses Business 2 specs, and the other way round. List them in `status.md` → Inputs with their headings.
3. If `runs/<KEY>/` or `runs/_archive/<KEY>/` exists, list its `requirements.md`, `backend-plan.md` and `frontend-plan.md` in `status.md` → Inputs. Agreed decisions there (Q, RC) count as requirements.
4. **Review worktree** (playbook → Review worktree): for each MR, create a detached worktree at `<head_sha>` outside the repo folder, then move its `HEAD` back to `<base_sha>` without touching files. Its uncommitted diff is now exactly the MR's change. Record the path in `status.md` → MRs.

## R6. Host code review (first pass)
For each MR, run the host's code-review command on its review worktree (playbook → Host code review). In Claude Code that's `/code-review`.
- You run it, not the roles, because it's a host command.
- Review only; never use its options that post to a PR or apply fixes.
- Save what it reports, as reported, to `reviews/<KEY>/r<n>/code-review-<service>.md`, with the command and level used at the top.
- If it fails or times out, show the error and ask: retry, or continue without it (record that).

## R7. Run the reviewer roles
See `flow/ORCHESTRATOR.md` → Running a role.
- `backend-reviewer` once for **all** backend MRs of the ticket (reviewed and context), so it can check the ws2 → ws1 contract end to end.
- `frontend-reviewer` once for the closio-web-v2 MR.
- Pass:
  - the key and the round number
  - `reviews/<KEY>/status.md` (MRs, SHAs, branch state, worktree paths)
  - `reviews/<KEY>/ticket.md`
  - the host review files `reviews/<KEY>/r<n>/code-review-<service>.md`
  - the spec sections and any `runs/<KEY>/` files from `status.md` → Inputs
  - on round n+1, also the previous round's review files
- The role **verifies every host review finding** against the code, keeps the confirmed ones with a citation, and rejects the rest with a reason. Then it adds its own checks: AC coverage, spec, contract, anti-patterns, reuse, tests.
- Output: `reviews/<KEY>/r<n>/review-<service>.md`, one per MR (template `flow/templates/review.md`).
- If a role writes `STATUS: BLOCKED`, ask the user its questions, record the answers in `status.md` → Notes, and re-run it.

## R8. Gate R: post the comments
1. Read the review files. Check every finding has a citation and a file and line; send any that doesn't back to the role.
2. Present per MR:
   - AC coverage summary (covered / partial / missing counts, and the missing ones by name)
   - findings grouped by severity (`blocker`, `major`, `minor`, `nit`, `question`): id, source (`code-review` or `reviewer`), `file:line`, the comment text exactly as it will be posted, and the rule it cites
   - how many host review findings were rejected as false positives (the list is in the review file)
   - context-only MRs: findings about them are shown but **not** posted; say so
3. The user can drop findings, edit their text, or change their severity. Apply the changes to the review file (mark dropped ones `dropped by user`), and re-present if anything changed.
4. Ask: "Post <n> comments on <project!iid, …>?" Only an explicit yes passes. A yes covers only the comments shown.
5. **Nothing to post** (no findings, or all were dropped): post nothing. Show the AC coverage summary, record the round as `clean: nothing posted`, remove the worktrees (R9 step 5), and stop.

## R9. Post
Follow playbook → Post comments, MR by MR:
1. Each finding with a valid changed line → an inline discussion on that line.
2. If GitLab rejects the position, post it as a general discussion that starts with `` `file:line` ``. Don't retry other line numbers.
3. Last, one summary note per MR: AC coverage, finding counts by severity, and the round number.
4. Record each posted id in `status.md` → Posted. If a post fails for any other reason, stop, show the error, and ask before posting the rest.
5. Remove the review worktrees (playbook → Review worktree → Remove). Show the MR links and the number posted on each. Record Gate R in `status.md` → Gate log.

## R10. Re-review (round n+1)
Triggered when an MR's head SHA moved since the last round (the author pushed fixes or rebased).
- Start again at R4 with the new `diff_refs`: the branch must be up to date before anything is reviewed. If the last round was `waiting for rebase` and the branch is now up to date, this is the first real review: run R5–R9 as normal, and there are no earlier findings.
- Otherwise recreate the worktrees (R5 step 4), re-run the host review (R6), and run the roles with the previous round's files.
- The role marks each earlier finding `fixed`, `still open` or `not applicable`, with evidence, and adds new findings.
- If the branch fell behind again since the last round, R4 stops the review again. Don't post a second rebase notice while the earlier one is still the latest note on the MR; just tell the user it's still waiting.
- At Gate R, only new findings and still-open findings whose earlier thread is gone are offered for posting. Never post the same finding twice; the summary note lists what was fixed.

## R11. Learning
These are learning triggers (`flow/ORCHESTRATOR.md` → Learning). Record the outcome in `reviews/<KEY>/status.md` → Lessons.
- The user drops a finding as **wrong**, not just unimportant: the reviewer misread a pattern, a spec or the code. That's a lesson for `lessons/backend.md` or `lessons/frontend.md`.
- A GitLab or process problem (wrong MR picked, missed paired MR, position failures, a wrong branch-state verdict): `lessons/workflow.md`.

## Resume
"resume review <KEY>": read `reviews/<KEY>/status.md` and continue from the first unfinished action. Recreate a missing review worktree before running the host review or the roles. Never post again what `status.md` → Posted already lists.
