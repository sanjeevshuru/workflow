---
description: Run the complete ticket workflow for a Jira key — requirements, plans, implementation with tests, commits and push after approval, then the dev deployment doc
---

1. Take the Jira key (and any Figma links) from the user's message.
2. Read `flow/ORCHESTRATOR.md` and follow it exactly: Start if `runs/<KEY>/status.md` doesn't exist, otherwise Resume. Run steps 01 → 02 → 03 → 04 in order.
3. Run roles sequentially. In step 03, use the built-in browser agent for the live browser test; the user logs in themselves.
4. Stop and wait at every question and every gate, including Gate 3 (commit), Gate 4 (push) and Gate 5 (deployment doc). To start over, use `/restart-ticket`.
