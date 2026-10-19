---
trigger: always_on
---

Read and follow `AGENTS.md` at the workspace root. Antigravity specifics:
- Run roles **sequentially** in this conversation (see `flow/ORCHESTRATOR.md` → Running a role).
- Ask questions as a numbered list, then stop and wait for the answers. Don't continue autonomously past a question or a gate.
- Steps 01–02 are read-only toward code repos: don't edit files outside `runs/`. Step 03 edits repos only as `flow/steps/03-implementation.md` and `flow/playbooks/git.md` allow, and commits or pushes only after the user's yes.
