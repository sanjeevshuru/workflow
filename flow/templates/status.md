# Status: <KEY>

- lifecycle: active   <!-- active: kept and updated until the ticket is implemented | archived: moved to runs/_archive/<KEY>/ -->
- current_step: 01
- step_status: in_progress   <!-- in_progress | waiting_user | blocked | approved -->
- started: <YYYY-MM-DD> in <host tool>
- last_updated: <YYYY-MM-DD> in <host tool>

## Inputs
- Figma links passed at start: <links or "none">

## Jira
<!-- step 01 claim and step 03 transition (config/jira.md → Workflow writes to Jira) -->
- Claim: <To Do → In Development on <date> | already <status>: not changed | transition not found | failed: <error>>
- Assignee: <assigned to current user on <date> | already assigned to <name>: not changed | failed: <error>>

## Scope
- type: <backend | frontend | fullstack>   <!-- confirmed in step 01 triage -->
- type source: <Q1>
- backend services (in order): <...>   <!-- set in step 02 -->
- frontend: <closio-web-v2 | none>

## Network
<!-- VPN preflight (flow/playbooks/vpn.md), one line per check: <date time>: reachable | connected by vpn up (<iface>) | connected via FortiClient | offline (user chose) | failed: <reason> -->

## Repo sync
| Repo | Previous branch | Dev branch | Commit before → after | Stash | Result | Time |
|---|---|---|---|---|---|---|
<!-- Result: synced | already up to date | skipped: uncommitted changes | not pulled: fetch failed | not pulled: not fast-forward | skipped: merge conflict | conflict resolved by user -->

## Branches
<!-- step 03, flow/playbooks/git.md → Branch -->
| Repo | Dev branch | Feature branch | Base commit | Created |
|---|---|---|---|---|

## Implementation
<!-- step 03 checkpoints: a resume (in any tool) continues from here -->
| Repo | Tasks done | Unit tests (last run) | Committed (hashes) | Pushed (remote hash, time) | MR |
|---|---|---|---|---|---|

- Postman: <not started | doc written | run <n>: <p>/<total> | done>; seed: <none | seeded | cleaned up | cleanup pending>
- Browser: <not started | doc written | run <n>: <p>/<total> | done>; backend used: <>
- Jira transition: <not done | Code Review on <date>>

## Deployment doc
<!-- step 04; dev only -->
| Side | File | For pushed hash(es) | State (written / approved / stale) | Date |
|---|---|---|---|---|

## Gate log
| Step | Gate | Result | Date | Notes |
|---|---|---|---|---|

## Lifecycle log
| Date | Event | By |
|---|---|---|

## Lessons
| Date | File | Title | Outcome (proposed / accepted / declined) |
|---|---|---|---|

## Notes
<!-- fallbacks used, stale outputs, MCP issues -->
