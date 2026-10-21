# VPN: connected for you (openfortivpn)

The workflow connects the company VPN by itself at the start of a run (`flow/playbooks/vpn.md`), and disconnects on request. It uses `openfortivpn`, an open-source FortiGate SSL VPN client, instead of the FortiClient app, driven by one command. Agents run it from the repo as `setup/vpn/vpn`; the install also puts a copy at `/usr/local/bin/vpn`.

```
vpn up       connect: the Microsoft sign-in runs in a background browser tab, so you stay in your app
vpn down     disconnect
vpn status   connected | connecting | disconnected, plus GitLab reachability
vpn check    is GitLab reachable, through any VPN?
vpn log      last 40 lines of the VPN log
vpn installed  is the one-time install in place? (exit 3 with the exact install command if not)
```

The workflow runs `vpn installed` first at every `/run-ticket` (Start and Resume) and MR review. If the install is missing, it asks you to install it before doing anything else. Once installed, it connects by itself whenever GitLab isn't reachable.

In AI tools: `/vpn`, `/vpn down`, `/vpn status` (Claude Code, Cursor, Antigravity), or "connect vpn" (Codex).

## How it works
- The gateway `vpnwm.japfacomfeed.co.id` (realm `sso`) signs in with **Microsoft Entra ID (SAML)**. There's no VPN password, so none is stored anywhere.
- `vpn up` starts an on-demand root daemon (`local.fortivpn`), which waits on `127.0.0.1:8020`. Then `vpn up` opens the gateway's sign-in page in a **background** tab of your default browser (`open -g`), so your focus doesn't move.
  - If the browser is signed in to Microsoft, the sign-in completes by itself. The gateway redirects the tab back to `127.0.0.1:8020`, and the tunnel comes up.
  - If the tunnel isn't up after **25 s** (`FORTIVPN_SIGNIN_GRACE`), Microsoft needs you, so `vpn up` brings the browser forward. `FORTIVPN_KEEP_FOCUS=0` opens the page in front straight away.
- **Not possible:** connecting at boot or reconnecting silently. Each connection needs a browser sign-in, and the gateway ends sessions after its timeout.
- **FortiClient's window keeps showing "Disconnected".** That's expected: the tunnel belongs to openfortivpn, and FortiClient only shows connections it made itself. It has no way to be told about another client's tunnel. Don't press Connect in FortiClient while `vpn` is up: two clients would fight over routes and DNS. To check the VPN, use `vpn status`.
- **Split DNS:** macOS ignores `/etc/resolv.conf`, so `/etc/ppp/ip-up` points each domain in `/etc/openfortivpn/resolver-domains` (default `japfacomfeed.co.id`) at the VPN's DNS servers through `/etc/resolver/`. `/etc/ppp/ip-down` removes them again.
- **TLS:** the gateway sends only its own certificate, without GoDaddy's G2 intermediate. The CA bundle adds that intermediate (`setup/vpn/certs/`), so certificate renewals by the same CA keep working with no pinned hash.

## Install (once per Mac, needs an admin password once)
1. Install the client (Homebrew under your home folder is fine):
   ```bash
   brew install openfortivpn
   ```
2. From this folder, as an admin user:
   ```bash
   sudo setup/vpn/install.sh --user "$(id -un)"
   ```
   - It copies openfortivpn and its OpenSSL libraries into a root-owned folder before anything runs as root. A user-writable Homebrew folder can then never be used to get root through the passwordless rule.
   - It installs a sudoers rule for exactly two commands: `launchctl kickstart system/local.fortivpn` and `launchctl kill SIGTERM system/local.fortivpn`. So after this, `vpn up` and `vpn down` need no password.
   - The header of `setup/vpn/install.sh` lists every file it writes.
   - Options: `--openfortivpn <path>` and `--domains "<d1> <d2>"` (internal DNS domains).
3. Disconnect FortiClient's VPN if it's connected (the two would fight over routes and DNS; `vpn up` won't start while GitLab is already reachable through another VPN). Then:
   ```bash
   setup/vpn/vpn up
   setup/vpn/vpn status
   ```

**Updating openfortivpn:** after `brew upgrade openfortivpn`, re-run step 2. The daemon keeps using the copied binary until then.

## Uninstall
```bash
sudo setup/vpn/install.sh --user <developer-login> --uninstall
brew uninstall openfortivpn
```

## Tests
```bash
setup/vpn/tests/run-tests.sh          # offline: vpn command against a simulated daemon, pppd hooks, staged installer
LIVE=1 setup/vpn/tests/run-tests.sh   # plus the gateway's TLS chain and SAML redirect (no sign-in)
```
They need `shellcheck` and `openfortivpn` (both from brew), and no root.

## Troubleshooting
- **`vpn up` exits 3 ("not allowed")**: the install (step 2) hasn't run on this Mac, or ran for another user.
- **"already reachable through another VPN"**: FortiClient is connected. Disconnect it there, then `vpn up`.
- **Browser ends on a gateway error instead of "SAML session id received"**: the FortiGate must allow SAML redirects back to the client (FortiOS 7.0+ does when the client sends `redirect=1`). Ask IT.
- **Exit 2: tunnel up, GitLab unreachable (DNS)**:
  - Run `vpn log` and look for `ip-up: resolver …`.
  - If it says `no DNS servers`, the gateway sent none. Ask IT for the internal DNS IP, and write `/etc/resolver/japfacomfeed.co.id` with `nameserver <ip>` (as root).
  - Check with `dscacheutil -q host -a name jcvs.japfacomfeed.co.id`.
- **Certificate errors after a renewal by a different CA**: replace `setup/vpn/certs/godaddy-g2-intermediate.pem` with the new CA's intermediate, then re-run the install.
- **Timed out**: you didn't finish the sign-in within 180 s. Run `vpn up` again; it reuses a connection that's still waiting.
