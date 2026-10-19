# Postman report: <KEY>

## Run info
- Date: <ISO datetime> · round <n> of fixes
- Environment: local services on branch `<branch>` (commit <hash> per repo)
- Base URLs: ws2 <service>: `http://localhost:<port>/<prefix>` · ws1: `http://localhost:3000/ws1closio`
- Tool: <newman x.y.z | curl fallback>
- Seed: <none | seeded and cleaned up | cleanup FAILED: see Remaining issues>
- Raw output: `runs/<KEY>/postman/run-output.txt`, `newman-result.json` (redacted)

## Totals
| Category | Cases | Passed | Failed | Skipped |
|---|---|---|---|---|
| POS | | | | |
| NEG | | | | |
| EDGE | | | | |
| **total** | | | | |

Per layer: ws2 <p>/<n> · ws1 <p>/<n>. Assertions: <passed>/<total>.

## Cases
| TC | Cat | Layer | Case | Expected | Actual | Result |
|---|---|---|---|---|---|---|
| TC1 | POS | ws2 | | 200 | 200 | pass |

## AC coverage
| AC | Cases | Result |
|---|---|---|

## Failures
### TC<n> <case name>
- Request: `<METHOD> <url>` body: `<trimmed, redacted>`
- Expected: <status, fields> [source]
- Actual: <status, fields>
- Response snippet (max ~20 lines, redacted):
  ```
  ```
- Classification: <code defect | wrong case | plan wrong | environment>: <explanation>

## Fixes made
| Round | Case(s) | Fix (file or case) | Re-run result |
|---|---|---|---|

## Remaining issues
- <issue, why unresolved, suggested next step> (or "none")
