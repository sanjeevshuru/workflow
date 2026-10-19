---
description: Review the oldest GitLab MR waiting for your review (or a given MR / Jira key) — AC coverage, spec, anti-patterns, reuse — and post comments after approval
---

1. Take the MR url or Jira key from the user's message, if any.
2. Read `flow/REVIEW.md` and follow it exactly, with `flow/playbooks/mr-review.md` for every `glab` call.
3. First pass: the host code-review command on each MR's review worktree (`flow/playbooks/mr-review.md` → Host code review). If none is installed, ask the user to install one first.
4. Run roles sequentially (`backend-reviewer`, `frontend-reviewer`); they verify the host findings. Never check out, stash or rebase in the user's repos; use the temporary review worktrees. Check the branch first: if it's behind its target branch or has conflicts, stop before reviewing, post the rebase notice after the user's yes, and end there.
5. Stop and wait at every question and at Gate R. Post comments only after the user's yes.
