# Command-line VPN (macOS)

The workflow connects the company VPN by itself at the start of a run (`flow/playbooks/vpn.md`). It does this with `openfortivpn`, an open-source FortiGate SSL VPN client, driven by a small `vpn` command:

```
vpn up       connect (opens the Microsoft sign-in in your browser; no typing if you're already signed in)
vpn down     disconnect
vpn status   connected | connecting | disconnected
vpn check    is GitLab reachable, through any VPN?
vpn log      last 40 lines of the VPN log
```

Without it, nothing breaks: the workflow asks you to connect in FortiClient, as before.

## How it works
- The gateway `vpnwm.japfacomfeed.co.id` (realm `sso`) signs in with **Microsoft Entra ID (SAML)**. There's no VPN password, so none is stored anywhere.
- `vpn up` starts an on-demand root daemon (`local.fortivpn`). It waits on `127.0.0.1:8020`, while `vpn up` opens the gateway's sign-in page in your default browser. After Microsoft signs you in, the gateway redirects the browser back to `127.0.0.1:8020`, and the tunnel comes up.
- **Not possible:** connecting at boot or reconnecting silently. Each connection needs a browser sign-in, and the gateway ends sessions after its timeout.
- **Split DNS:** macOS ignores `/etc/resolv.conf`, so `/etc/ppp/ip-up` points each domain in `/etc/openfortivpn/resolver-domains` (default `japfacomfeed.co.id`) at the VPN's DNS servers through `/etc/resolver/`. `/etc/ppp/ip-down` removes them again.
- **TLS:** the gateway sends only its own certificate, without GoDaddy's G2 intermediate. The CA bundle adds that intermediate (`setup/vpn/certs/`), so certificate renewals by the same CA keep working with no pinned hash.

## Install (once per Mac, needs an admin)
Developer Macs are MDM-managed, and developer accounts aren't admins, so **IT runs step 2**. After that, daily use needs no admin and no password.

1. As the developer, install the client (Homebrew under your home folder is fine):
   ```bash
   brew install openfortivpn
   ```
2. As an admin, from this folder:
   ```bash
   sudo setup/vpn/install.sh --user <developer-login>
   ```
   - It copies openfortivpn and its OpenSSL libraries into a root-owned folder before anything runs as root. A user-writable Homebrew folder can then never be used to get root through the passwordless rule.
   - It installs a sudoers rule for exactly two commands: `launchctl kickstart system/local.fortivpn` and `launchctl kill SIGTERM system/local.fortivpn`.
   - The header of `setup/vpn/install.sh` lists every file it writes.
   - Options: `--openfortivpn <path>` and `--domains "<d1> <d2>"` (internal DNS domains).
   - It can also be pushed through the MDM as a script.
3. As the developer, quit FortiClient's VPN connection (the two would fight over routes and DNS), then run:
   ```bash
   vpn up
   vpn status
   ```

**Updating openfortivpn:** after `brew upgrade openfortivpn`, an admin re-runs step 2. The daemon keeps using the copied binary until then.

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
- **Browser ends on a gateway error instead of "SAML session id received"**: the FortiGate must allow SAML redirects back to the client (FortiOS 7.0+ does when the client sends `redirect=1`). Ask IT.
- **Exit 2: tunnel up, GitLab unreachable (DNS)**:
  - Run `vpn log` and look for `ip-up: resolver …`.
  - If it says `no DNS servers`, the gateway sent none. Ask IT for the internal DNS IP, and write `/etc/resolver/japfacomfeed.co.id` with `nameserver <ip>` (as root).
  - Check with `dscacheutil -q host -a name jcvs.japfacomfeed.co.id`.
- **Certificate errors after a renewal by a different CA**: replace `setup/vpn/certs/godaddy-g2-intermediate.pem` with the new CA's intermediate, then re-run the install.
- **Timed out**: you didn't finish the sign-in within 180 s. Run `vpn up` again; it reuses a connection that's still waiting.
