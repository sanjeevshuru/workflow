# Playbook: Sync repos to the development branch

Code is always analysed on the **latest development branch**, never on whatever branch a repo happens to be on. The orchestrator runs this playbook (roles can't talk to the user):
- in step 01, right after scope triage, for the in-scope repos, before any code is read
- again whenever a repo is added to the scope later
- on resume

## Which branch
Use each service's **Development branch** from `config/services.md`: `develop` for the backend services, `development` for closio-web-v2. **Never** use the remote's default branch (`origin/HEAD`), which points at `master`/`main` in these repos.

## Allowed git commands
This is the only place where steps 01–02 change repo state (step 03 also uses `flow/playbooks/git.md`). Only these are allowed here:
- `git fetch`
- `git checkout <dev branch>`
- `git pull --ff-only`
- `git stash push`, only after the user chooses it

No merges, rebases, resets, branch deletions or `stash pop`.

## Merge conflicts: the user resolves them
The agent **never resolves merge conflicts**, not even trivial ones. That means no editing conflict markers, no `checkout --ours/--theirs`, no `merge --abort`/`rebase --abort`/`--continue`, and no `git add` on conflicted files. When a conflict or a half-finished merge, rebase, cherry-pick or revert is found:
1. **Stop** syncing that repo. Other repos may continue.
2. **Show** the repo, its current branch, the operation in progress (if any) and the conflicted files (at most 15, plus a count).
3. **Ask the user to resolve it themselves**, in their own editor or terminal, and to reply "resolved" when done. Give a one-line hint for the operation, for example "finish with `git commit` (merge) or `git rebase --continue`, or back out with `--abort`". The user chooses which.
4. Options:
   - **I've resolved it**: re-run the procedure for that repo from step 1. If the check still finds a conflict, ask again.
   - **Skip sync for this repo**: analyse it as is, recorded as "skipped: merge conflict". Every finding from it is marked as coming from a non-development branch.
   - **Abort** the run.
5. Record the outcome in `status.md` → Repo sync (`conflict resolved by user` or `skipped: merge conflict`).

## Procedure (per in-scope repo)
1. **Inspect**:
   - `git -C <path> branch --show-current`
   - `git -C <path> status --porcelain`
   - `git -C <path> rev-parse --short HEAD`
   - conflicted files: `git -C <path> diff --name-only --diff-filter=U`
   - operation in progress: whether any of `MERGE_HEAD`, `rebase-merge`, `rebase-apply`, `CHERRY_PICK_HEAD` or `REVERT_HEAD` exists under `git -C <path> rev-parse --git-dir`
2. **Conflicts first.** If there are conflicted files or an operation is in progress, follow **Merge conflicts: the user resolves them** above. Don't offer a stash, because a stash fails with unmerged files and would hide the conflict.
3. **Uncommitted changes.** If `status --porcelain` isn't empty, **stop and ask**. Show the repo, the current branch and the changed files (at most 15, plus a count). Options:
   - **Stash**: `git -C <path> stash push -u -m "ai-flow <KEY>: auto-stash before sync from <branch>"`. Record the stash message so the user can restore it later with `git stash list` / `git stash pop`.
   - **Skip sync for this repo**: analyse its current branch as is. Record "not synced: on `<branch>`, uncommitted changes". Every finding from this repo is then marked as coming from a non-development branch.
   - **Abort** the run.

   Never stash, discard or commit changes without the user's choice. If `stash push` fails, show the error and ask. Don't retry with other flags.
4. **Fetch**: `git -C <path> fetch origin --prune`. On failure (network or VPN), ask the user:
   - continue on the **local** development branch without pulling, recorded as "not pulled: fetch failed"
   - abort
5. **Check out** the development branch, if it isn't already current: `git -C <path> checkout <dev branch>`. If the local branch doesn't exist, use `git -C <path> checkout -b <dev branch> --track origin/<dev branch>`. If the checkout fails, show the error and ask. Don't force it.
6. **Pull**: `git -C <path> pull --ff-only origin <dev branch>`.
   - If it **isn't a fast-forward** (the local development branch has its own commits or has diverged), stop and ask. Never merge or rebase yourself. Options:
     - **I'll update it myself**: the user merges or rebases the development branch and resolves any conflicts on their own, then replies "done". Re-run the procedure for that repo from step 1, recorded as "conflict resolved by user" if it had conflicts.
     - **Skip the pull**: analyse the local state as is, recorded as "not pulled: not fast-forward".
     - **Abort** the run.
7. **Record** a row in `status.md` → Repo sync (template below): repo, previous branch, development branch, commit before and after, stash (if any), result, time.

## After syncing
- **Tell the user** in one short block which repos switched branches. Their previous branch is recorded, and the workflow does **not** switch back. They can return to it with `git checkout <previous>` (and `git stash pop` if stashed).
- **Profiles**: if a repo's commit moved, `code-scout` refreshes `knowledge/<service>.md` from the old commit to the new one, as usual.

## On resume
Re-run the procedure for the in-scope repos.
- If a pull brings new commits **after** Gate 1 or Gate 2, run `git diff --stat <old>..<new>` and check whether it touches files listed in `codebase.md` or in the plans.
- If it does, record "code changed since plan" in `status.md` → Notes, and ask the user whether to re-run `code-scout` and the affected planner. Re-running revises the plans through their changelog.

## Scope changes
If `code-scout` or step 02 finds that another repo is needed:
- the role lists it under `codebase.md` → Repos with `sync: needed` and stops using it
- the orchestrator syncs that repo with this playbook, then re-runs the role for it
