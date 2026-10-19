# Playbook: Branch, commit, push (step 03)

The orchestrator runs this playbook. Roles edit files but **never run git commands that change state**. Conventions are in `config/git.md`. Three phases:
- **Branch**: right after Gate 2.
- **Commit**: at Gate 3, after the user's yes.
- **Push**: at Gate 4, after the user's yes.

Repos are handled in `status.md` → Scope order (providers first), with the **same branch name** in every repo.

## Allowed git commands in step 03
- Everything in `flow/playbooks/repo-sync.md`
- `git checkout -b <feature branch>` / `git checkout <feature branch>`
- `git add <paths>`, `git commit -m …`
- `git push -u origin <feature branch>` with the push options below

Read-only commands (`status`, `diff`, `log`, `rev-parse`, `branch`, `ls-remote`) are always fine.

**Never:**
- force pushes (`--force`, `--force-with-lease`)
- pushing to or committing on a protected or development branch
- `merge`, `rebase`, `reset --hard`, `cherry-pick`, deleting branches, `stash pop`
- `--no-verify`
- amending or squashing commits the user already approved, without asking again

## Phase: Branch
For each in-scope repo:
1. **Sync** with `flow/playbooks/repo-sync.md`: development branch, `pull --ff-only`, ask if the tree is dirty. Code must start from the latest development branch.
2. **Name** the branch per `config/git.md` → Branch naming, from `ticket.md` (key and type): `scrum-<n>`, or `fix/scrum-<n>` for a Bug. Use the same name for every repo. Refuse a name that matches a protected pattern.
3. **Existing branch?**
   - Check `git branch --list <name>` and `git ls-remote --heads origin <name>`.
   - Also look at `codebase.md` → Existing work for the ticket.
   - If the branch exists, stop and ask:
     - **continue on it**: check it out, then `pull --ff-only` if it has a remote. Its existing commits are shown at Gate 3 as "already on branch".
     - **use a new name**: add a `-v2` suffix (`scrum-<n>-v2`).
     - **abort**
4. **Create**: `git -C <path> checkout -b <branch>`. This starts from the freshly pulled development branch.
5. **Record** in `status.md` → Branches: repo, development branch, feature branch, base commit (`rev-parse --short HEAD`), time.

## Phase: Commit (prepare at Gate 3, commit after the yes)
For each repo:
1. **Scope check**:
   - Run `git -C <path> status --porcelain`, `git diff --stat`, and `git diff`.
   - Every changed or added file must be explained in `implementation.md` (the role's "Files changed").
   - If anything is unexplained, stop and ask: it could be a stray edit or a generated file.
2. **Junk and secret check**. Nothing in `config/git.md` → Files never committed may be staged. Scan the diff for secrets:
   - `password`, `secret`, `token`, `Authorization:`, `Cookie:`, `BEGIN PRIVATE KEY`, `AKIA`
   - any value of an `AIFLOW_*` variable used in this run (compare it in memory; never print it)

   If something is found, stop and ask.
3. **Group into commits**, one logical concern each, in this order: migration → model/service → route/controller → tests → docs/flags. Write each message per `config/git.md` → Commit message format: one short subject line (≤ 60 characters) that says what the commit does, and no body unless the why needs it. A test may go with the code it tests.
4. **Present** at Gate 3, as the list of proposed commits: message + files.
5. **On the user's yes**, for each commit: `git -C <path> add <files>`, then `git -C <path> commit -m "<subject>" -m "<body>"`.
   - If a **hook fails** (husky `npm test` / `coverage:check`), don't bypass it. Show the failure, send it to the developer role for a fix, re-run the tests, and re-present the affected commit(s).
6. **Verify**:
   - `git status --porcelain` is empty, apart from files the user chose to leave out.
   - `git log --oneline <dev branch>..HEAD` matches the approved list.
7. Re-run the repo's unit tests (and the build, for the frontend) on HEAD, and record the result.
8. **Record** hash + message in `implementation.md` → Commits, and `committed` in `status.md` → Implementation progress.

## Phase: Push (after the yes at Gate 4)
For each repo, providers first:
1. **Re-check**: the current branch is the feature branch, it's not protected, and `HEAD` equals the last approved commit hash.
2. **Push and open the MR** with GitLab push options:
   ```bash
   git -C <path> push -u origin <branch> \
     -o merge_request.create \
     -o merge_request.target=<dev branch> \
     -o merge_request.title="<KEY>: <ticket summary>" \
     -o merge_request.remove_source_branch
   ```
   - If the branch already has an open MR, GitLab doesn't create a second one. Report the existing MR.
   - Hooks run on pre-push. A failure is handled as in Commit → step 5.
3. **Capture the MR URL** from the remote's output (`View merge request` / `merge_requests/<n>`).
   - If GitLab printed only a "To create a merge request" link (push options disabled on the server), report that link and say the MR must be opened from it.
   - Never invent a URL.
4. **Verify**:
   - `git -C <path> ls-remote --heads origin <branch>` returns the hash that was pushed.
   - That hash equals `HEAD`.
5. **Record** in `status.md` → Implementation: pushed time, remote hash, MR URL.
6. If a push fails (rejected, network, hook), **stop**: don't push the remaining repos. Show the error and ask.

## On resume
- Compare `status.md` → Branches and Commits with the repo: current branch, `HEAD`, and `git log <dev>..HEAD`.
  - If they differ (the user committed or switched branches by hand), show the difference and ask before continuing.
- **Never push again** a repo that's recorded as pushed, unless there are new approved commits. Those go through Gate 4 again.
