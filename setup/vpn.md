# VPN: connected for you (macOS + FortiClient)

The workflow connects the company VPN by itself at the start of a run (`flow/playbooks/vpn.md`). Nobody clicks Connect: a small app, **VPN Connect**, clicks **SAML Login** in FortiClient, and the Microsoft sign-in then completes in your browser.

```
setup/vpn/vpn up           connect
setup/vpn/vpn down         disconnect
setup/vpn/vpn check        is GitLab reachable? (no UI)
setup/vpn/vpn status       FortiClient's state + GitLab reachability
setup/vpn/vpn setup-check  is VPN Connect built and allowed?
setup/vpn/vpn dump         FortiClient's on-screen labels (for a new FortiClient version)
```

## How it works
- FortiClient (installed by IT) already has the rights to create the tunnel. Only its window needs a click.
- `vpn up` asks **VPN Connect.app** to click SAML Login, without bringing FortiClient to the front. FortiClient opens the Microsoft sign-in in your default browser:
  - If the browser already has a Microsoft session, the sign-in finishes by itself.
  - If the session has expired or MFA is due, sign in there. No tool can skip that.
- `vpn up` then waits until `jcvs.japfacomfeed.co.id:443` answers (up to 180 s).
- **Why a separate app:** macOS lets an app click buttons in another app only after you allow it under **Accessibility**. Giving that permission to one tiny app is safer than giving it to your editor or terminal, which run extensions and AI agents. VPN Connect only drives the FortiClient process, and only accepts the words `connect`, `disconnect`, `status`, `check` and `dump`.
- **Not possible:** FortiClient's own Auto Connect / Always Up. The FortiGate turns them off for the "VPN SAML DM" profile (`AllowAutoConnect 0`), and only IT can turn them on.

## Setup (once per Mac, no admin)
1. Build the app:
   ```bash
   setup/vpn/install-applet.sh
   ```
   This creates `~/Applications/VPN Connect.app` and opens System Settings → Privacy & Security → **Accessibility**.
2. Click **+**, pick **VPN Connect** from your home folder's `Applications`, and turn it on.
3. Check it:
   ```bash
   setup/vpn/vpn setup-check
   ```
   The first run may also ask "VPN Connect wants to control System Events". Click **Allow**.
4. Try it, with FortiClient disconnected:
   ```bash
   setup/vpn/vpn up
   setup/vpn/vpn down
   ```

After rebuilding the app (`install-applet.sh` again), macOS may ignore the old permission. Turn VPN Connect off and on again under Accessibility.

## Uninstall
```bash
setup/vpn/install-applet.sh --uninstall
```
Then remove VPN Connect from the Accessibility list.

## Tests
```bash
setup/vpn/tests/run-tests.sh
```
This runs the `vpn` command against a simulated applet, checks the applet's source rules, and builds the applet in a temp folder. It needs `shellcheck` (brew), and no permissions.

## Troubleshooting
- **Exit 3, "not allowed"**: VPN Connect isn't on under Accessibility, or it was rebuilt. Turn it off and on.
- **"no SAML Login / Connect button found"**: FortiClient's window changed, for example after an update, or it's on another page.
  - Run `setup/vpn/vpn dump` to see its labels.
  - Then adjust `connectLabels`, `disconnectLabels` or `navLabels` at the top of `setup/vpn/forticlient/VPNConnect.applescript`, and rebuild.
- **Exit 1, "not connected after 180s"**: the browser sign-in didn't finish. Look at the browser tab FortiClient opened.
- **Exit 2, connected but GitLab unreachable**: FortiClient's tunnel is up, but DNS or routes don't cover GitLab. Ask IT.

## Alternative without FortiClient
`setup/vpn/openfortivpn/` replaces FortiClient with the open-source openfortivpn client. It needs IT to install it with admin rights; see its `README.md` and `REPORT.md`.
