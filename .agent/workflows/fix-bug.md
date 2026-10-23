---
description: Fix a bug ticket raised by QA (Jira key or just its number) — root cause, fix with a regression test, verify, commit and push after approval, then the dev deployment doc
---

1. Take the Jira key, or the bare number, from the user's message.
2. Read `flow/BUGFIX.md` and follow it exactly: Start if `runs/<KEY>/status.md` doesn't exist, otherwise Resume. Run B1 → B4 in order.
3. Run roles sequentially (`bug-investigator`, then the step 03 and 04 roles with `bug-analysis.md` → Fix plan as their plan). In B3, use the built-in browser agent for the live browser test; the user logs in themselves.
4. Stop and wait at every question and every gate: Gate B (root cause and fix), Gate 3 (commit), Gate 4 (push) and Gate 5 (deployment doc).
