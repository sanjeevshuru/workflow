# Workflow lessons: workflow

Process mistakes that aren't about one stack: Jira fetching, scope triage, Figma budget, question handling, gates, resume. Read by the orchestrator at every start and resume.

Rules for this file:
- Entries are added **only after the user approves** a lesson proposed by the orchestrator (`flow/ORCHESTRATOR.md` → Learning).
- Newest entry first. Never delete an entry. If a lesson becomes wrong, add a `Superseded by:` line to it.
- Cite an entry as `[lesson: workflow#<date> <title>]`.
- Rules about how to *write code* in one repo belong in that repo's own `lessons.md`. Here they're only noted as "candidate for <repo>/lessons.md".

Entry template:

```markdown
## [YYYY-MM-DD] Short title of the mistake
- **Ticket / role:** <KEY> / <code-scout | backend-planner | frontend-planner | requirements-analyst | orchestrator>
- **Tags:** <e.g. reuse, absence-claim, convention, contract, figma, jira>
- **What happened:** <the mistake, concretely>
- **Root cause:** <why the workflow made it>
- **Impact:** <extra questions, rework, wrong plan, …>
- **Fix applied:** <how it was corrected in the run>
- **Rule going forward:** <actionable "do X / never Y" that a role can follow>
- **Candidate for repo lessons:** <repo / none>
```

---

## [2026-10-23] Local ws1closio: no path prefix, Redis must be reachable
- **Ticket / role:** SCRUM-530 / orchestrator, api-tester
- **Tags:** postman, local-run, config, ws1closio
- **What happened:** `config/postman.md` listed ws1closio's local prefix as `/ws1closio`, so the login and the collection's `ws1_base_url` hit 404→597. ws1 also couldn't reach Redis (`connect ETIMEDOUT`), so login hung until the user applied their local-Redis tweaks from a stash.
- **Root cause:** the ws1 row in `config/postman.md` was assumed from `APP_PATH_PREFIX`, never confirmed by a run; ws1's Redis client always uses `rediss://` to the `.env` host.
- **Impact:** one failed login, one timed-out login, an environment.json fix and an extra user round-trip.
- **Fix applied:** base URL `http://localhost:3000`; user applied their stash; ws1 started with `REDIS_USER= REDIS_PASSWORD= REDIS_HOST=localhost REDIS_PORT=6379`; tweak files excluded from the commit; `config/postman.md` corrected.
- **Rule going forward:** For local ws1closio runs use `http://localhost:3000` with no prefix. Before the first ws1 request, check its log for `Redis Client …: Connected`; if it shows `ETIMEDOUT`, stop and ask the user how they run Redis locally before logging in. Never commit local Redis tweaks.
- **Candidate for repo lessons:** none

## [2026-10-22] Commit grouping and attribution
- **Ticket / role:** SCRUM-529 / orchestrator
- **Tags:** git, gate-3, commits
- **What happened:** At Gate 3 the orchestrator proposed 3 commits (service, endpoint, docs) and added a `Co-Authored-By: Claude` trailer. The user asked for a single commit and rejected the trailer.
- **Root cause:** `config/git.md` suggests one commit per concern; the host's default attribution was applied without checking the user's preference.
- **Impact:** Gate 3 needed two extra rounds.
- **Fix applied:** One commit `feat(SCRUM-529): add GET customer-handled S2S endpoint` with all 9 files, no trailer.
- **Rule going forward:** At Gate 3, propose ONE commit per repo by default (split only when the user asks), and never add a Co-Authored-By / Claude attribution trailer to commits or MRs.
- **Candidate for repo lessons:** none
