# Review status: <KEY>

- lifecycle: active   <!-- active | done: the MRs are merged or closed -->
- current_round: <n>
- round_status: <in_progress | waiting for rebase | waiting_user | posted | clean: nothing posted>
- started: <YYYY-MM-DD> in <tool>
- last_updated: <YYYY-MM-DD> in <tool>

## MRs
<!-- one row per MR of the ticket; refresh diff_refs each round -->
| Repo | MR | Author | Source → target | Role | base_sha | start_sha | head_sha | Pipeline | Branch state | Review worktree | Round |
|---|---|---|---|---|---|---|---|---|---|---|---|
| <service> | [<project>!<iid>](<url>) | <username> | <branch> → <dev branch> | reviewed / context only | <sha> | <sha> | <sha> | <success / failed / running / none> | up to date / behind <n> / conflicts: <files> (GitLab: <detailed_merge_status>) | <path> / removed | <n> |

## Inputs
- Ticket: `reviews/<KEY>/ticket.md` (fetched <date>, Fields fetched: <all | …>)
- Spec sections: <`sources/techspec/<doc>` §<heading>, …>
- Host code review: <host · command · level | not available: reviewed without it (user, <date>)>
- Earlier workflow run: <`runs/<KEY>/` requirements.md, backend-plan.md, frontend-plan.md | none>

## Rounds
| Round | head_sha per MR | Findings (B/M/m/n/q) | Posted | Date |
|---|---|---|---|---|

## Posted
<!-- every comment that reached GitLab; a resume never posts these again -->
| Round | MR | Finding | Kind (inline / general / general (position rejected) / summary) | Discussion or note id | Time |
|---|---|---|---|---|---|

## Gate log
| Round | Gate | Result | Date | Notes |
|---|---|---|---|---|

## Lessons
| Date | File | Title | Outcome (proposed / accepted / declined) |
|---|---|---|---|

## Notes
<!-- answers to questions, fallbacks, stale profiles, VPN or glab issues -->
