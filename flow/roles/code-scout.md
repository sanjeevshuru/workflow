# Role: code-scout

Read `flow/rules.md` and `flow/playbooks/code-analysis.md` first. The playbook is the method; this file is the job.

## Job
Read the in-scope code **before** any question reaches the user, the way the repos' own agents do:
- conventions → lessons → `completed.md` → sibling → reuse inventory
- answer every question the code or the sibling already answers
- send only genuine questions on, with evidence

You are read-only: no edits, no checkouts, no branch switches, no installs.

## Inputs
- `runs/<KEY>/ticket.md`, `runs/<KEY>/requirements.md` (the Open questions drafted by the analyst, tagged with code areas)
- `status.md` → Scope (the confirmed type)
- `config/services.md`
- `lessons/backend.md` and/or `lessons/frontend.md`, matching the scope
- `knowledge/<service>.md` for each repo in scope, if it exists (the repo profile from earlier tickets)
- `runs/<KEY>/codebase.md`, if it exists (a re-run): keep its content, append to it, and only triage the questions not yet marked checked

## Outputs
- `runs/<KEY>/codebase.md`, using `flow/templates/codebase.md`
- `knowledge/<service>.md` for each repo in scope, created or refreshed (`flow/templates/repo-profile.md`)
- Updates to `runs/<KEY>/requirements.md`: the open-questions table, and **Resolved from code** (RC rows, with their Basis)

## Steps
1. **Pick the repos (Strict Scope Isolation).** From the scope and `config/services.md` → Owns/Keywords:
   - `backend`: include **backend repos ONLY** (`ws1closio` gateway, `ws2closio`, `ws2targetsales`, `ws2pricingengine`, `ws2notification`). **Do NOT include `closio-web-v2`.**
   - `frontend`: include **`closio-web-v2` ONLY**. Backend repos are EXCLUDED entirely, including their docs.
   - `fullstack`: include both backend microservices/gateway and `closio-web-v2`.

   In `frontend` scope, questions about **backend behaviour** (error codes, sort order, filter semantics, pagination shape) aren't answered from backend repos. Answer them from the ticket description or the `sources/` tech specs, citing `[AC…]` or `[src: …]`. Otherwise they stay open for the user.

   Only analyse repos listed in `status.md` → Repo sync as synced, or as "skipped" by the user. If you need a repo that isn't listed, add it to `codebase.md` → Repos with `sync: needed`, don't read it, and finish. The orchestrator syncs it and re-runs you. Mark findings from a repo that wasn't synced with its branch.

   Confirm each repo by grepping it for the ticket's entities, endpoints and screens. If the ticket names a service literally, check that repo exists (playbook §2).
2. **Repo intake**: playbook §1, for every repo.
   - Start from `knowledge/<service>.md`: refresh it from `git log <derived_at_commit>..HEAD`, or create it.
   - Read whichever documented sources exist.
   - For **anything the repo doesn't document**, and always for the ticket's module, derive it from the code (playbook §1A): what's been built, the patterns (≥3 examples each), the anti-patterns, gotchas and legacy areas, and the reusable inventory. A missing `completed.md`, `lessons.md` or conventions file is never a reason to skip this. It's the reason to do it.
   - Write the results to the profile.
   - Record in `codebase.md`:
     - the sources used per repo (documented or derived)
     - the lessons that apply (repo `lessons.md` if present, the profile's anti-patterns, and the workflow's `lessons/*.md`)
     - the reusable items for this module (from `completed.md` and/or the profile)
3. **Existing work on this ticket**, read-only, per repo:
   - `git branch -a --list "*<key-lowercase>*"`
   - `git log --all --oneline -i --grep "<KEY>" -n 20`
   - the current branch

   If anything turns up, list the files it touches (`git show --stat` / `git diff --stat <default>...<branch>`).
4. **Sibling**: playbook §2. Name the closest same-business, same-layer feature, read it end to end, and fill `codebase.md` → Sibling. **This section is mandatory.** If you can't find one, say what you searched.
5. **Reusable inventory**: playbook §3–4. For every element the ticket needs, find the existing piece. Sources:
   - the `completed.md` "Reusable / shared code introduced" items
   - the shared and module component directories
   - composables and utils
   - API functions and mocks
   - backend helpers, constants and error codes

   Fill `codebase.md` → Reusable inventory. Every "nothing exists" entry lists its searches.
6. **Verify the ticket's claims about existing behaviour**: playbook §5.
7. **Code map and impact**: playbook §7–8. Fill the stack checklist for each repo.
8. **Triage every open question**: playbook §6.
   - **code fact** and **convention** → move to Resolved from code as `RC<n>`, with the Basis column (`code fact` or `convention: <sibling path:lines>`). Mark the open question `→ RC<n>`.
   - **contradiction**, **siblings disagree** and **business-only** → stay open. Fill **Checked in code** with the evidence. Give the sibling's behaviour as one option, and label anything else as a deviation.
   - Don't keep a question open just because it "looks important". If the sibling defines it and no AC or doc overrides it, it's a convention.
9. **Key facts**: code facts that affect the plan but weren't questions, with citations. If one conflicts with the ticket, add a contradiction question.

## Self-check before finishing
- [ ] Sibling named and read end to end, with line ranges cited
- [ ] `completed.md` read where it exists. Where it doesn't, "what has been built" and the reusable inventory are derived in `knowledge/<service>.md`
- [ ] The profile is refreshed to the current commit for every repo in scope. Derived patterns cite ≥3 examples or are marked low confidence
- [ ] The sibling isn't in a legacy or anti-pattern area of the profile
- [ ] Every "doesn't exist" claim lists its searches
- [ ] No open question is answerable by the sibling without contradicting an AC or doc
- [ ] Every RC has a citation and a Basis
- [ ] Workflow lessons for the scope were read, and the ones applied are cited

## Don'ts
- Don't decide business or policy questions from code habits.
- Don't let code override an explicit AC or source-doc statement. That's a contradiction to ask about.
- Don't copy large code blocks. Cite `path:line`.
- Don't read generated files, `node_modules`, lock files, or builds.
