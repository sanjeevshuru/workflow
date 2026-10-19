# Playbook: VPN preflight

GitLab (`jcvs.japfacomfeed.co.id`) and the internal dev hosts are only reachable on the company VPN. Jira and Figma are cloud services and don't need it. The orchestrator runs this playbook (roles can't talk to the user):
- **Start** and **Resume** of a ticket run (`flow/ORCHESTRATOR.md`), before anything else
- **R0** of an MR review (`flow/REVIEW.md`)
- before a remote git action, when that action fails with a network error: repo-sync fetch, step 03 push, MR review fetch. The tunnel can drop during a long run or while the laptop sleeps.

`setup/vpn/vpn up` connects without anyone clicking:
- A script clicks **Connect** in FortiClient, through macOS Accessibility.
- The Microsoft sign-in then completes in the browser, by itself when the browser already has a Microsoft session.
- Machine setup, once per Mac, needs no admin: `setup/vpn.md`.

## Allowed commands
Paths are relative to this workflow folder.
- `setup/vpn/vpn check`: read-only, no UI
- `setup/vpn/vpn status`, `setup/vpn/vpn setup-check`: read-only
- `setup/vpn/vpn up`: connects. It's a local network action, not a write to a repo or Jira, so any step may run it.
- Never `setup/vpn/vpn down`, unless the user asks. The user may need the tunnel for other work.

## Procedure
1. **Check**: `setup/vpn/vpn check`. Exit 0 means GitLab is reachable. Record `reachable` and continue. Say nothing to the user.
2. **Connect**: run `setup/vpn/vpn up` in the foreground, with a command timeout of at least 200 s. Before running it, tell the user in one line: "Connecting the VPN through FortiClient. If Microsoft asks you to sign in, do it in the browser tab that opens."
   | Exit | Meaning | Do |
   |---|---|---|
   | 0 | connected and GitLab reachable | record `connected by vpn up`, continue |
   | 1 | the sign-in didn't finish in time, or FortiClient's window wasn't as expected | show the lines it printed, then ask (step 3) |
   | 2 | FortiClient connected, but GitLab doesn't answer | show the message (DNS or routes: IT), then ask (step 3) |
   | 3 | clicking FortiClient isn't allowed under Accessibility (the message names the app to allow) | point to `setup/vpn.md` → Setup (one time, no admin), then ask (step 3) |
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
