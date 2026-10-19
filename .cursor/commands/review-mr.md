# review-mr

Review the oldest open GitLab MR where the user is a reviewer, or the MR url / Jira key given after the command.

Read `flow/REVIEW.md` and follow it exactly, with `flow/playbooks/mr-review.md` for every `glab` call. Run the roles sequentially in this chat (`backend-reviewer` for all backend MRs of the ticket, `frontend-reviewer` for the closio-web-v2 MR). Before reviewing, ask the user which code-review command or extension they use in Cursor; if none is installed, ask them to install one first (`flow/playbooks/mr-review.md` → Host code review), and run it on each MR's review worktree. Never check out, stash or rebase in the user's repos; use the temporary review worktrees from the playbook. Check the branch first: if it's behind its target branch or has conflicts, stop before reviewing, show the rebase notice, post it after the user's yes, and end there. Stop and wait at Gate R: show every comment, and post only after the user's yes.
