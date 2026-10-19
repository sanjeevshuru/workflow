# knowledge/

One **repo profile** per service (`<service>.md`, template `flow/templates/repo-profile.md`), written and refreshed by `code-scout`.

Repos don't all have `completed.md`, `lessons.md` or agent files, and new repos usually start with none. The profile holds what the workflow learned by reading the code:
- what has been built
- the patterns (with ≥3 examples each) and anti-patterns
- gotchas, legacy areas, and the reusable inventory

Each profile records the commit it was derived at, so the next ticket refreshes it from `git log <sha>..HEAD` instead of re-reading the whole repo.

- Committed with this workflow. Derived from code only: no secrets, no `.env` values.
- Where the repo documents something, the repo wins and the profile cites it.
- If you correct a profile entry during a run, the orchestrator also proposes a lesson (`flow/ORCHESTRATOR.md` → Learning).
