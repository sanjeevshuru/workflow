# Playbook: GitLab MR review (glab)

The orchestrator runs this playbook from `flow/REVIEW.md`. The reviewer roles never call glab, never run the host review command, and never post.

- Host: `jcvs.japfacomfeed.co.id` (`config/git.md` → Hosting). It needs the VPN.
- Tool: the `glab` CLI, logged in with a personal access token that has the `api` scope (`setup/mcp.md` → GitLab CLI). The token lives in glab's own config. Never print it, and never write it to any file.
- `<project>` below is the URL-encoded project path, for example `closio%2Fbackend%2Fnodejs-ws1closio`. Get the path from the repo's `git remote get-url origin` (drop the host and `.git`) or from an MR's `references.full` (before the `!`).

## Command shapes (fixed order)
Write the commands exactly in these shapes, so the host's permission rules can tell reads from writes:
- **Read:** `glab api --hostname jcvs.japfacomfeed.co.id "<endpoint>"`
- **Write:** `glab api -X POST --hostname jcvs.japfacomfeed.co.id "<endpoint>" -H "Content-Type: application/json" --input <body.json>`

Pipe read output through `jq` to keep only the fields you need. Never dump whole responses into chat.

## Allowed
- `glab auth status --hostname jcvs.japfacomfeed.co.id`
- `glab api` reads (GET) on the endpoints below
- `glab api -X POST` on exactly two endpoints:
  - `projects/<project>/merge_requests/<iid>/discussions` (review comments)
  - `projects/<project>/merge_requests/<iid>/notes` (the summary note)
- `git -C <path> fetch origin <branch> …`, and read-only git: `show`, `diff`, `log`, `grep`, `ls-tree`, `cat-file`, `rev-parse`, `rev-list`, `merge-base`, `remote get-url`
- `git merge-tree --write-tree` for the conflict check. It writes objects only, never refs or files.
- The review worktree commands in **Review worktree**, and only on a worktree under `.aiflow-review/`
- The host's code-review command, in review-only mode (**Host code review**)

## Never
- Any other write: approve or unapprove, merge, close or reopen, rebase, resolve or unresolve threads, edit or delete notes (yours included, unless the user asks for a specific one), change labels, assignees, reviewers, milestones or the title or description
- `PUT`, `PATCH` or `DELETE` on any endpoint
- In the user's repos: `git checkout`, `switch`, `stash`, `pull`, `merge`, `rebase`, `reset`, or any change to their working tree, index or branches. `reset --soft` is allowed only inside a review worktree.
- Rebasing or resolving conflicts for the author. The branch notice asks them to do it.
- The host review command's options that post to a PR or MR, apply fixes or run a billed cloud review (Claude Code: `--comment`, `--fix`, `ultra`), unless the user asks
- Posting before the yes at Gate R, or posting a comment the user didn't see

## Preflight
1. `glab --version`. If it's missing, stop: see `setup/mcp.md` → GitLab CLI.
2. `glab auth status --hostname jcvs.japfacomfeed.co.id`. If it's not logged in, stop and point to the setup. If the host can't be resolved or times out, run `flow/playbooks/vpn.md` (it connects with `setup/vpn/vpn up`, or asks the user), then retry once.
3. Username: `glab api --hostname jcvs.japfacomfeed.co.id "user" | jq -r .username`. Keep it in memory only.
4. The host code-review command is available (**Host code review** → Check). If it isn't, stop and ask the user to install it first, with the install step for this host.

## List my review MRs
```bash
glab api --hostname jcvs.japfacomfeed.co.id \
  "merge_requests?scope=all&state=opened&reviewer_username=<me>&draft=no&order_by=created_at&sort=asc&per_page=100" \
  | jq '[.[] | select(.draft == false) | {project_id, iid, title, web_url, ref: .references.full, source_branch, target_branch, author: .author.username, created_at}]'
```
If 100 come back, page with `&page=2` and so on.

## Already reviewed
For each candidate, in order, until one is not reviewed:
- Approved by you: `".../projects/<project_id>/merge_requests/<iid>/approvals"` → `.approved_by[].user.username` contains `<me>`.
- Latest version time: `".../merge_requests/<iid>/versions"` → `.[0].created_at`.
- Your latest note: `".../merge_requests/<iid>/notes?sort=desc&order_by=created_at&per_page=100"` → the first non-system note whose `author.username` is `<me>`.
- **Reviewed** = approved by you, or your latest note is newer than the latest version.

## MRs for a key
```bash
glab api --hostname jcvs.japfacomfeed.co.id \
  "merge_requests?scope=all&state=opened&search=<KEY>&in=title,description&per_page=100"
```
Also run the same search for the lowercase branch prefix (`scrum-<n>`) and match `source_branch` against `(^|/)scrum-<n>($|-)`, so `scrum-52` doesn't match `scrum-523`, because some titles don't carry the key. Keep only configured projects. Then check each MR's `reviewers[].username` for `<me>`.

## MR details
```bash
glab api --hostname jcvs.japfacomfeed.co.id "projects/<project>/merge_requests/<iid>?include_diverged_commits_count=true" \
  | jq '{iid, title, web_url, author: .author.username, source_branch, target_branch, source_project_id, target_project_id, diff_refs, head_pipeline: .head_pipeline.status, has_conflicts, detailed_merge_status, diverged_commits_count, description, reviewers: [.reviewers[].username]}'
```
- `diff_refs` gives `base_sha`, `start_sha` and `head_sha`. Record all three; inline comments need them.
- If `source_project_id` differs from `target_project_id` (a fork), stop and ask: the source branch can't be fetched from `origin`.

## Fetch
`git -C <path> fetch origin <source_branch> <target_branch>`, then confirm `git -C <path> cat-file -e <head_sha>^{commit}`.

Read code at the MR head without checking out:
- diff: `git -C <path> diff <base_sha>...<head_sha>` (`--stat` first; page large diffs by path)
- a file: `git -C <path> show <head_sha>:<file>`
- search: `git -C <path> grep -n "<term>" <head_sha> -- <dir>`
- list: `git -C <path> ls-tree -r --name-only <head_sha> -- <dir>`

The user's working tree may be on another branch, with uncommitted work. Never read it as if it were the MR. The review worktree (below) holds the MR head and may be read with ordinary file tools.

## Branch state
Is the source branch rebased on the latest target branch, and does it merge cleanly? This uses the target branch just fetched.
```bash
git -C <path> rev-list --count <head_sha>..origin/<target_branch>      # commits behind
git -C <path> merge-tree --write-tree --name-only --no-messages origin/<target_branch> <head_sha>
```
- `merge-tree` exits 0 when it merges cleanly. Exit 1 means conflicts: the lines after the first one (the tree id) are the conflicted files. It writes no refs and touches no files.
- Cross-check with **MR details**: `has_conflicts`, `detailed_merge_status` (`conflict`, `need_rebase`, `mergeable`, …) and `diverged_commits_count`.
  - If GitLab is still `checking` or `unchecked`, use the local result.
  - If they disagree, `has_conflicts: true` wins for conflicts. Show both numbers to the user.
- Verdict:
  - `up to date`: 0 behind
  - `behind <n>`: no conflicts, but not rebased
  - `conflicts: <files>`: conflicts, which also implies behind

## Branch notice
The **rebase notice**, posted when a reviewed MR isn't `up to date`. While it's open, the review doesn't start (`flow/REVIEW.md` → R4). It's posted after the yes at Gate R, as a general discussion, with nothing else. Fill in the target branch, the count and the files.

Conflicts:
```markdown
**Rebase needed before review: merge conflicts with `<target_branch>`**
This branch conflicts with the latest `<target_branch>` in:
- `<file>`
Please rebase onto the latest `<target_branch>` (`git fetch origin && git rebase origin/<target_branch>`), resolve the conflicts, and push. I'll start the review once the branch is up to date.
```

Behind, no conflicts:
```markdown
**Rebase needed before review: branch is behind `<target_branch>`**
This branch is <n> commits behind the latest `<target_branch>`. Please rebase onto it (`git fetch origin && git rebase origin/<target_branch>`) and push. I'll start the review once the branch is up to date, so it covers what will actually be merged.
```

If the team merges the target branch in instead of rebasing, the user may edit the text at Gate R.

## Review worktree
Host review commands review a working diff. Each MR gets its own temporary worktree, so the user's checkout is never touched. It lives outside the repo, beside it: `../backend/.aiflow-review/<repo>-<iid>` for backend repos, `../web/.aiflow-review/<repo>-<iid>` for closio-web-v2.

**Create:**
```bash
wt=<repo parent>/.aiflow-review/<repo>-<iid>
git -C <path> -c core.hooksPath=/dev/null worktree add --detach "$wt" <head_sha>
git -C "$wt" reset --soft <base_sha>
git -C "$wt" diff --cached --stat        # must equal: git -C <path> diff --stat <base_sha>...<head_sha>
```
- The files are the MR head, and `HEAD` is the merge base. So the worktree's staged diff is exactly the MR's change, with nothing else.
- `core.hooksPath=/dev/null` stops repo hooks (husky) from running on the checkout.
- If the path already exists from an earlier round, remove it first.
- If the stats don't match, remove the worktree, show both stats, and ask.

**Remove**, when the round ends (posted, clean, or aborted):
```bash
git -C <path> worktree remove --force "$wt" && git -C <path> worktree prune
```
`--force` is needed because the worktree holds staged changes. It removes only that worktree, never a branch or the user's checkout.

## Host code review
The first pass. Run it once per MR, on that MR's review worktree, in review-only mode. Save its output, as reported, to `reviews/<KEY>/r<n>/code-review-<service>.md`, with the host, the command, the level and the worktree path at the top.

| Host | Command | Check it's installed | If it's missing, ask the user to | Run it on the worktree |
|---|---|---|---|---|
| Claude Code | `/code-review` (built-in skill `code-review`, or the `code-review` plugin's `code-review:code-review`) | It's in the session's available skills list | update Claude Code (`claude update`), or install the plugin with `/plugin` → `code-review`, then restart the session | Skill `code-review` with args `<worktree path> high`. Never `--comment`, `--fix` or `ultra`. |
| Codex | `/review` → "Review uncommitted changes" | `codex --version`; `/review` is in the TUI's slash menu | update Codex (`npm i -g @openai/codex` or `brew upgrade codex`) | The user opens Codex in the worktree (`cd <wt> && codex`), runs `/review`, and pastes or saves the output. If your Codex has a non-interactive review command, you may run that instead. Verify this on first use. |
| Cursor | The review command or extension the user has set up | Ask the user which one they use | install or enable a code-review command or extension | Run it on the worktree folder's uncommitted changes. Verify this on first use. |
| Antigravity | Same as Cursor | Ask the user | Same as Cursor | Same as Cursor |

- If no command is available after asking, continue only on the user's explicit "review without it", and record it in `status.md` → Notes.
- The output is raw input, not findings. The reviewer roles verify each item before anything can be posted.

## Post comments
Build each body as a JSON file in a temporary directory (`mktemp -d`) and delete the directory after posting. Body files hold only the comment text and positions, never secrets.

**Rebase notice** (when the review is stopped for a rebase): a discussion without `position`, with `{"body": "<notice text>"}`, posted to `.../discussions`. Nothing else is posted in that round.

**Inline discussion** on a changed line:
```json
{
  "body": "<comment text>",
  "position": {
    "position_type": "text",
    "base_sha": "<base_sha>",
    "start_sha": "<start_sha>",
    "head_sha": "<head_sha>",
    "old_path": "<path before>",
    "new_path": "<path after>",
    "new_line": 42
  }
}
```
- An added line: `new_line` only.
- A removed line: `old_line` only.
- An unchanged line inside a diff hunk: both `old_line` and `new_line`.
- `old_path` equals `new_path` unless the file was renamed.

```bash
glab api -X POST --hostname jcvs.japfacomfeed.co.id \
  "projects/<project>/merge_requests/<iid>/discussions" \
  -H "Content-Type: application/json" --input "$tmp/F3.json" | jq '{id, note_id: .notes[0].id}'
```

**Fallback.** If GitLab rejects the position (400, for example "line_code can't be blank" or "position is invalid"), post the same discussion without `position`, with the body starting `` `<file>:<line>` ``. Record it as `general (position rejected)`.

**Summary note**, last, one per MR:
```bash
glab api -X POST --hostname jcvs.japfacomfeed.co.id \
  "projects/<project>/merge_requests/<iid>/notes" \
  -H "Content-Type: application/json" --input "$tmp/summary.json" | jq '{id}'
```

## Comment style
- Lead with what's wrong and why it matters, then the suggested change. Short; at most ~8 lines.
- Prefix the severity: `**[blocker]**`, `**[major]**`, `**[minor]**`, `**[nit]**`, `**[question]**`.
- Cite what the rule comes from in words a teammate can follow: "AC3 in SCRUM-519", "Tech Spec B1 §14.3", "same as `incentivePayoutConfigController.js:95`", "ws2targetsales lessons.md 2026-07-27". Never cite workflow-internal ids (RC12, Q5) without saying what they mean.
- No secret values, `.env` contents or personal data in comment text.
- English unless the team's MRs use another language.

## Failures
- 401 or 403: the token expired or lacks the `api` scope. Stop and point to the setup.
- 404 on a project or MR: check the project path encoding, then ask.
- 429 or 5xx: wait a little and retry once, then stop and ask.
- A post fails part-way: stop. `status.md` → Posted shows what's already on the MR, so a resume never posts it again.
