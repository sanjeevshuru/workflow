# run-ticket

Run the complete ticket workflow (steps 01 → 02 → 03 → 04). The first word after the command is the Jira key; any further words are Figma links.

Read `flow/ORCHESTRATOR.md` and follow it exactly: Start if `runs/<KEY>/status.md` doesn't exist, otherwise Resume. Run roles sequentially in this chat. In step 03, start services in background terminals and use Cursor's built-in browser for the live browser test; the user logs in themselves. Stop and wait at every question and every gate, including Gate 3 (commit), Gate 4 (push) and Gate 5 (deployment doc). To start over, the user runs `/restart-ticket <KEY>`.
