# Command-line VPN (openfortivpn): report

Branch `feature/vpn-automation` · 2026-10-21 · macOS 27.0.1 (Apple Silicon) · openfortivpn 1.24.1 · gateway `vpnwm.japfacomfeed.co.id` (SAML, Microsoft Entra ID)

## Verdict
**Working live, and the workflow's only way of connecting the VPN.** The FortiClient automation (AppleScript, VPN Connect app) has been removed.

- `vpn up` connected 5 out of 5 times live, in **9–10 s**, with no password, no clicks and no sign-in prompt, because the browser had a Microsoft session.
- After every connect, GitLab answered (`git ls-remote` on `nodejs-ws1closio`), and `jcvs.japfacomfeed.co.id` resolved to its internal address through the VPN's DNS.
- `vpn down` disconnected in about 1 s, removed the split-DNS files, and public DNS kept working.
- **Focus stays in your app.** The sign-in runs in a background browser tab. In 2 of 4 connects, Chrome flashed forward for under a second, and the guard put VS Code back.

## How the workflow uses it
`flow/playbooks/vpn.md`, run first at `/run-ticket` Start/Resume and at MR review R0:

0. **`vpn installed`**: checks the one-time install, including that the passwordless rule is active for this user. If anything's missing, the agent stops and asks the user to install it now, showing the exact `sudo … install.sh --user …` command. Agents never ask for or type the password.
1. **`vpn check`**: is GitLab already reachable? If so, done.
2. **`vpn up`**: connect. Exit codes: 0 ok, 1 failed, 2 tunnel up but GitLab unreachable, 3 not installed.
3. On failure, ask: retry, I've connected myself, continue offline, or abort.

A fetch, push or glab call that fails on the network reconnects and retries once. `/vpn [up|down|status]` does the same on demand (Claude Code, Cursor and Antigravity; "connect vpn" in Codex).

## Found in live testing (fixed)
| # | Finding | Fix |
|---|---|---|
| 1 | The **SAML redirect works**: the gateway hands the browser back to `127.0.0.1:8020`. This was the one unverified piece. | — |
| 2 | openfortivpn 1.24.1 logs "Listening for SAML login" but never the "Using SAML authentication URL" line, so `vpn up` waited its full 15 s start timeout (27 s per connect) | open the sign-in page as soon as it's listening, with the URL built from `work.conf` in openfortivpn's own format → **9–10 s** |
| 3 | Chrome comes to the front even for `open -g` (background) | a focus guard switches back to your app while the sign-in completes by itself; the browser is brought forward only if the tunnel isn't up after 25 s |
| 4 | `/etc/resolver` was created readable by root only (pppd runs `ip-up` with umask 077). DNS still worked, but the folder couldn't be inspected | `ip-up` sets umask 022 and `chmod 755`. **Re-run the installer to apply it.** |
| 5 | Re-running the installer while connected failed with **"Bootstrap failed: 5: Input/output error"**. `bootout` is asynchronous, so the reload hit the still-loaded old job; the VPN was dropped and the daemon left unloaded. `vpn installed` still said "installed", because it only checked files | the installer stops a running VPN cleanly, waits until the old job is gone, re-enables it, and retries `bootstrap` (tested against a fake launchctl that reproduces error 5). `vpn installed` now also checks that the daemon is loaded |

Also confirmed live:
- **Split DNS:** `ip-up` set `japfacomfeed.co.id → 10.90.0.53, 10.190.0.55`. macOS shows it as resolver #9; pppd also adds the same servers scoped to `ppp0`.
- **Routes:** about 150 internal routes were pushed via `ppp0`. Public traffic stays on the normal network.
- **FortiClient** keeps showing "Disconnected" while openfortivpn is up. That's expected (see Open points), and `vpn up` now says so.

## Tests
`setup/vpn/tests/run-tests.sh` → **108 passed, 0 failed**. No root needed; the daemon, `sudo`, `launchctl`, `open`, `lsappinfo` and `defaults` are simulated.

| Area | Covers |
|---|---|
| Lint | shellcheck on every script; bash 3.2 and `/bin/sh` parse |
| `vpn` command | connect, repeated up/down, status/check, another VPN already connected, rejected sign-in, crash, timeout, stale log lines, DNS broken (exit 2), not installed (exit 3), re-attaching to a pending sign-in; only the two allowed sudo commands are ever used |
| Live-found behaviour | URL built at once when the log has no URL line; a URL line in the log wins |
| Focus | background tab by default; browser forward only after the grace; guard pushes Chrome back during the quiet phase and stops once connected; nothing switched if you were already in the browser; `FORTIVPN_KEEP_FOCUS=0` |
| `vpn installed` | all present; each missing piece named; passwordless rule inactive; daemon not loaded; nothing installed; `vpn up` prints the diagnosis and command |
| pppd hooks | DNS from pppd or the log, other PPP links ignored, foreign files untouched, folder readable under umask 077 |
| Installer reload | macOS-like fake launchctl: reproduces error 5; first load; reload waits for the async bootout; connected VPN stopped first; never-unloading job and permanently failing bootstrap give clear errors; job re-enabled |
| Installer (staged) | relinked root-owned binary, signatures, plist, `visudo -c`, no secrets, ACL'd log, idempotent, refuses a foreign `ip-up`, uninstall |

## Security (unchanged)
- **No secrets anywhere:** sign-in is SAML in the browser.
- **sudoers allows exactly** `launchctl kickstart system/local.fortivpn` and `launchctl kill SIGTERM system/local.fortivpn`, with no wildcard.
- **Root never loads user-writable code.** openfortivpn and its OpenSSL libraries are copied root-owned and relinked, and OpenSSL's config and CA paths point at root-owned files.
- **Log:** root-owned at mode 600, readable by the one user through an ACL.

## Open points
- **FortiClient's window can't show this tunnel.** It only displays connections it created, and offers no way to be told about another client's tunnel. So its status stays "Disconnected" while openfortivpn is connected. Use `vpn status`. Don't press Connect in FortiClient while `vpn` is up.
- **Re-run the installer** after this branch's `ip-up` change, and after any `brew upgrade openfortivpn`:
  `sudo setup/vpn/install.sh --user "$(id -un)"`
- **Session length:** the gateway ends sessions after its own timeout. The workflow reconnects at the next preflight or failed fetch or push.
- **Certificate:** the gateway's leaf certificate expires 2027-02-03. A renewal by GoDaddy needs nothing; a different CA needs its intermediate in `setup/vpn/certs/`.
