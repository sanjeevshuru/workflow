<!-- STATUS: BLOCKED goes at the top of a section, followed by what was checked and what is needed -->
# Implementation: <KEY>

Branch (all repos): `<branch>`

## Backend
<!-- One sub-section per service, in Scope order. Delete this section for frontend-only tickets. -->
### <service>
#### Files changed
| File | New / modify | Task (backend-plan) |
|---|---|---|
| `<service>:<path>` | | T<n> |

#### Tests added
- `<spec path>`: <cases> → AC<n>

#### Commands run (copied from real output)
| Command | Result | When |
|---|---|---|
| `npm test` | <passed>/<total>, <failed> failed | <ISO time> |
| `npm run coverage:check` | statements <x>% · branches <y>% · functions <z>% · lines <w>% | |
| `npm run lint` | <0 errors / n errors> | |

#### Migrations
- `<path>`: <what> · run against: <not run | local DB on <date> with the user's OK>

#### Deviations from plan
- <none | deviation, reason, plan changelog row>

#### Notes / suspected pre-existing failures
- <>

### Postman summary
- Report: `runs/<KEY>/postman/report.md`
- Totals: <n> cases, <p> passed, <f> failed (POS <x> · NEG <y> · EDGE <z>; ws2 <a> · ws1 <b>)
- Unresolved: <none | list>

## Frontend
<!-- Delete for backend-only tickets. -->
### closio-web-v2
#### Files changed
| File | New / modify | Task (frontend-plan) |
|---|---|---|

#### Specs added
- `<spec path>`: <cases> → AC<n>

#### Commands run (copied from real output)
| Command | Result | When |
|---|---|---|
| `npm run test:run` | <passed>/<total> | |
| `npm run build` | <ok / errors> | |

#### Deviations from plan
- <none | …>

### Browser test summary
- Report: `runs/<KEY>/browser/report.md`
- Backend used: <local ws1 | dev proxy | staging proxy | mocks>
- Totals: <n> cases, <p> passed, <f> failed
- Unresolved: <none | list>

## AC coverage
| AC | Code (task / file) | Unit test | Postman TC / UI case | Status |
|---|---|---|---|---|
| AC1 | | | | covered / gap |

## Known gaps
- <gap, reason, suggested follow-up> (or "none")

## Commits
<!-- Filled at Gate 3 after the user's yes -->
### <repo>
| # | Hash | Message | Files |
|---|---|---|---|

## Merge requests
<!-- Filled at Gate 4 -->
| Repo | Branch | Remote hash | MR | Target |
|---|---|---|---|---|

- Jira: <KEY> moved to <Code Review> on <date> (transition id <n>)
