<!-- STATUS: DONE | BLOCKED (questions below) -->
# Review: <KEY> · <service> · <project>!<iid> · round <n>

- MR: <url> · role: <reviewed | context only>
- Commits: base `<base_sha>` → head `<head_sha>` · <files changed>, +<added> −<removed>
- Pipeline: <status>
- Branch state: <up to date | reviewed before rebase (user) | context only: behind <n>>
- Host code review: `r<n>/code-review-<service>.md` · <n> items: <c> confirmed, <r> rejected
- Sibling: <feature> (`<service>:<file>`)
- Profile: <`knowledge/<service>.md` derived at <commit> | stale | missing>

## Verdict
<one or two lines: ready, ready with minor fixes, or needs changes; and why>

## AC coverage
| AC | Requirement (short) | Code | Tests | Status |
|---|---|---|---|---|
| AC1 | <> | `<file>:<line>` | `<test file>:<line>` | covered / partial: <what's missing> / missing |

## Spec conformance
| Item | Spec / ticket says | Code does | Match | Cite |
|---|---|---|---|---|

## 3-tier contract (backend; in the ws1 file, or the ws2 file if there's no ws1 MR)
| Endpoint | ws2 (route · codes) | ws1 (route · headers · 404→597) | Client shape | Match |
|---|---|---|---|---|

## Host review triage
<!-- every item from the host code-review output -->
| # | Host finding (short) | Verdict | Reason / merged into |
|---|---|---|---|
| 1 | <> | confirmed → F<n> / rejected | <false positive: …, lint-level, outside the change, contradicts spec …> |

## Previous round (round n+1 only)
| Finding | Was | Now | Evidence at new head |
|---|---|---|---|

## Findings
<!-- Ready to post. One row per finding; id is F<n>, unique across rounds for this file. -->
| Id | Severity | Source | File | new_line | old_line | Rule (cite) | Comment (as posted) | Suggested fix | Post |
|---|---|---|---|---|---|---|---|---|---|
| F1 | blocker / major / minor / nit / question | code-review / reviewer | `<path>` | <n or empty> | <n or empty> | [AC…] [src: …] [code: …] [lesson: …] | **[major]** <text> | <short> | yes / context only: not posted / dropped by user |

## Questions for the user (only if BLOCKED)
- <question, why it matters, options>

## Files read
- <service>:<file> @ <head_sha short>

## Searches run
- `git grep -n "<term>" <sha> -- <dir>`: <hits>
