# Playbook: VPN preflight

GitLab (`jcvs.japfacomfeed.co.id`) and the internal dev hosts are only reachable on the company VPN. Jira and Figma are cloud services and don't need it. The orchestrator runs this playbook (roles can't talk to the user):
- **Start** and **Resume** of a ticket run (`flow/ORCHESTRATOR.md`), before anything else
- **R0** of an MR review (`flow/REVIEW.md`)
- before a remote git action, when that action fails with a network error: repo-sync fetch, step 03 push, MR review fetch. The tunnel can drop during a long run or while the laptop sleeps.

`setup/vpn/vpn up` connects with openfortivpn, without anyone clicking:
- The Microsoft sign-in runs in a background browser tab, so the user's focus doesn't move. It completes by itself when the browser has a Microsoft session.
- Only if the tunnel isn't up after 25 s does the browser come forward, for the user to sign in.
- Machine setup, once per Mac (one admin password): `setup/vpn.md`.

## Allowed commands
Paths are relative to this workflow folder.
- `setup/vpn/vpn check`: read-only, no UI
- `setup/vpn/vpn status`, `setup/vpn/vpn log`: read-only
- `setup/vpn/vpn up`: connects. It's a local network action, not a write to a repo or Jira, so any step may run it.
- Never `setup/vpn/vpn down`, unless the user asks. The user may need the tunnel for other work.

## Procedure
1. **Check**: `setup/vpn/vpn check`. Exit 0 means GitLab is reachable. Record `reachable` and continue. Say nothing to the user.
2. **Connect**: run `setup/vpn/vpn up` in the foreground, with a command timeout of at least 200 s. Before running it, tell the user in one line: "Connecting the VPN. If Microsoft needs you to sign in, the browser will come forward."
   | Exit | Meaning | Do |
   |---|---|---|
   | 0 | connected and GitLab reachable | record `connected by vpn up`, continue |
   | 1 | the sign-in didn't finish in time, or openfortivpn stopped | show the log lines it printed, then ask (step 3) |
   | 2 | tunnel up, but GitLab doesn't resolve or answer | show the message, point to `setup/vpn.md` → Troubleshooting, then ask (step 3) |
   | 3 | not installed (no passwordless rule) | point to `setup/vpn.md` → Install (one admin password, once), then ask (step 3) |
3. **Ask** when it couldn't connect:
   - **Retry**: run this procedure again.
   - **I've connected myself**: run `setup/vpn/vpn check`, then continue.
   - **Continue offline**: only steps that don't need GitLab can continue. Repo sync records `not pulled: fetch failed` (`flow/playbooks/repo-sync.md`). A push or MR review can't continue offline.
   - **Abort** the run.
4. **Record** one line in `status.md` → Network (or `reviews/<KEY>/status.md` → Notes): result, how it was reached, time. Example: `2026-10-19 10:42: connected by vpn up`.

## Retry once on a network error
When `git fetch`, `git push`, `git ls-remote` or `glab` fails with a network error (`Could not resolve host`, `Connection timed out`, `Network is unreachable`, `Operation timed out`):
1. Run this procedure from step 1.
2. If it ends connected, retry the failed command **once**.
3. If it fails again, handle it as the calling playbook says (ask the user). Never loop.

A rejected push, a hook failure or an auth error isn't a network error. Don't run this playbook for those.
