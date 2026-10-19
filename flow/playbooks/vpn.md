# Playbook: VPN preflight

GitLab (`jcvs.japfacomfeed.co.id`) and the internal dev hosts are only reachable on the company VPN. Jira and Figma are cloud services and don't need it. The orchestrator runs this playbook (roles can't talk to the user):
- **Start** and **Resume** of a ticket run (`flow/ORCHESTRATOR.md`), before anything else
- **R0** of an MR review (`flow/REVIEW.md`)
- before a remote git action, when that action fails with a network error: repo-sync fetch, step 03 push, MR review fetch. The tunnel can drop during a long run or while the laptop sleeps.

The VPN signs in with Microsoft SSO (SAML) in the browser, so it can't be fully headless. `vpn up` opens the sign-in. If the browser already has a Microsoft session, the sign-in finishes by itself; otherwise the user completes it there. Machine setup: `setup/vpn.md`.

## Allowed commands
- `vpn check`, `vpn status`, `vpn log`: read-only
- `vpn up`: connects. It's a local network action, not a write to a repo or Jira, so any step may run it.
- Never `vpn down`, unless the user asks. The user may need the tunnel for other work.
- If the `vpn` command isn't installed (another machine, another OS), use `nc -z -G 5 jcvs.japfacomfeed.co.id 443` as the check, and ask the user to connect in FortiClient instead of running `vpn up`.

## Procedure
1. **Check**: `vpn check`. Exit 0 means GitLab is reachable, through this tunnel or any other VPN (FortiClient). Record `reachable` and continue. Say nothing to the user.
2. **Connect**: `vpn up`, with a command timeout of at least 200 s. Before running it, tell the user in one line: "Connecting the VPN. If a Microsoft sign-in opens in your browser, complete it there."
   | Exit | Meaning | Do |
   |---|---|---|
   | 0 | connected and GitLab reachable | record `connected by vpn up`, continue |
   | 1 | sign-in failed, timed out or openfortivpn stopped | show the log lines it printed, then ask (step 3) |
   | 2 | tunnel up, but GitLab doesn't resolve or answer | show the message, point to `setup/vpn.md` → Troubleshooting → DNS, then ask (step 3) |
   | 3 | not installed, or the sudoers rule is missing | say `setup/vpn.md` needs an admin once, then ask (step 3) |
3. **Ask** when it couldn't connect:
   - **Retry**: run this procedure again.
   - **I've connected another way** (FortiClient): run `vpn check`, then continue.
   - **Continue offline**: only steps that don't need GitLab can continue. Repo sync records `not pulled: fetch failed` (`flow/playbooks/repo-sync.md`). A push or MR review can't continue offline.
   - **Abort** the run.
4. **Record** one line in `status.md` → Network (or `reviews/<KEY>/status.md` → Notes): result, how it was reached, time. Example: `2026-10-19 10:42: connected by vpn up (ppp0)`.

## Retry once on a network error
When `git fetch`, `git push`, `git ls-remote` or `glab` fails with a network error (`Could not resolve host`, `Connection timed out`, `Network is unreachable`, `Operation timed out`):
1. Run this procedure from step 1.
2. If it ends connected, retry the failed command **once**.
3. If it fails again, handle it as the calling playbook says (ask the user). Never loop.

A rejected push, a hook failure or an auth error isn't a network error. Don't run this playbook for those.
