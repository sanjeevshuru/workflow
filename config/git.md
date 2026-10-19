# Git

Used by step 03 (`flow/playbooks/git.md`). These conventions come from the team's earlier workflow config, and recent branches in the repos match them.

## Hosting
- **GitLab (self-hosted):** `jcvs.japfacomfeed.co.id`. Every service repo's remote is `origin`.
- `gh` doesn't apply. Step 03 opens merge requests with **GitLab push options** (`-o merge_request.create`), so it needs no token.
- **MR review** (`flow/REVIEW.md`) uses the `glab` CLI, logged in to this host with a personal access token that has the `api` scope (`setup/mcp.md` → GitLab CLI). Commands and limits: `flow/playbooks/mr-review.md`.

## Base branches
Each service's **Development branch** in `config/services.md`: `develop` for the backend services, `development` for closio-web-v2. Feature branches start from it, and MRs target it.

## Protected branches (never commit to, never push to)
`master`, `main`, `develop`, `development`, `staging`, `release/*`

## Branch naming
The branch name is the Jira key in lowercase, and nothing else. There is no summary suffix.
- Story, task or sub-task: `scrum-<n>`, e.g. `scrum-523`.
- Bug (Jira type `Bug`): `fix/scrum-<n>`, e.g. `fix/scrum-514`.
- Other Jira projects use the same pattern with their key, e.g. `closio-852` or `fix/closio-852`.
- **Same branch name in every repo** the ticket touches.
- If the name is already taken by work that isn't this ticket's, the user picks: continue on it, or add `-v2` (`flow/playbooks/git.md` → Branch).
- Branches created before this rule (e.g. `scrum-519-business-1-post-ageing-deduction-config`) keep their names. Never rename a branch that has commits or an MR.

## Commit message format
Conventional Commits with the ticket as scope:
```
<type>(<KEY>): <what this commit does>
```
- `<type>`: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`
- **Short:** the whole subject line is at most **60 characters**, including `<type>(<KEY>): `. Imperative mood, lowercase after the colon, no full stop.
- **Descriptive:** say what the commit changes in the feature, in words a teammate understands from `git log --oneline` alone. Name the thing (endpoint, table, screen, rule), not the files or the process.
- **No body** by default. Add one (at most 3 lines, wrapped at 72) only when the *why* isn't obvious from the subject, e.g. a deviation from the sibling or a workaround.
- Don't use filler like "update code", "changes", "fix issues", "WIP" or "address review", and don't list file names, AC numbers or plan task ids (W3, S2).

| Good | Bad |
|---|---|
| `feat(SCRUM-519): add ageing deduction config POST` | `feat(SCRUM-519): implement tasks W1-W4 for business 1 ageing deduction config creation endpoint` |
| `feat(SCRUM-519): proxy ageing deduction config via ws1` | `feat(SCRUM-519): update routes and controller` |
| `test(SCRUM-519): cover overlap and validation errors` | `test(SCRUM-519): add tests` |
| `fix(SCRUM-514): keep month filter after page change` | `fix(SCRUM-514): fix bug` |

- One logical concern per commit (migration · model/service · route/controller · tests · docs), in that order. A test can go with the code it tests when that keeps the commit coherent. Prefer fewer, meaningful commits over one per file.

## Hooks
Husky runs on pre-commit and pre-push in **ws2notification**, **ws2pricingengine** (`npm test`) and **ws2targetsales** (`coverage:check`). ws1closio, ws2closio and closio-web-v2 have no hooks. If a hook fails, fix the cause. Never use `--no-verify`.

## Files never committed
- `.env*`. Exception: closio-web-v2's `.env.development`, `.env.staging` and `.env.production` are tracked, because the `VITE_ENABLE_*` feature flags live there. Commit them only when the plan says to change a flag, and scan them for secrets first.
- keys, certificates, `*adminsdk*.json`, tokens
- `node_modules/`, `coverage/`, `.nyc_output/`, `.test-logs/`, `dist/`, IDE folders, OS files, logs
- Postman, newman and browser-test output (those live in `runs/<KEY>/`)
