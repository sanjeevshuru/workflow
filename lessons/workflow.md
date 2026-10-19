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

