# fix-bug

Fix a bug ticket raised by QA. The first word after the command is the Jira key or just its number (`514` → `SCRUM-514`).

Read `flow/BUGFIX.md` and follow it exactly: Start if `runs/<KEY>/status.md` doesn't exist, otherwise Resume. Run B1 → B4 in this chat, with the roles run sequentially (`bug-investigator`, then the step 03 and 04 roles with `bug-analysis.md` → Fix plan as their plan). Start services in background terminals and use Cursor's built-in browser for the live browser test; the user logs in themselves. Stop and wait at every question and every gate: Gate B (root cause and fix), Gate 3 (commit), Gate 4 (push) and Gate 5 (deployment doc).
