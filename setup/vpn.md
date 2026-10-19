# VPN: connected for you (macOS + FortiClient)

The workflow connects the company VPN by itself at the start of a run (`flow/playbooks/vpn.md`). Nobody clicks Connect: a script clicks **Connect** in FortiClient, and FortiClient's Microsoft sign-in then completes in your browser. In live tests it connected in about 14 s with no clicks and no sign-in prompt, because the browser was already signed in to Microsoft.

```
setup/vpn/vpn up           connect
setup/vpn/vpn down         disconnect
setup/vpn/vpn check        is GitLab reachable? (no UI)
setup/vpn/vpn status       FortiClient's state + GitLab reachability
setup/vpn/vpn setup-check  is the clicking allowed?
setup/vpn/vpn dump         FortiClient's on-screen labels (for a new FortiClient version)
```

## How it works
- FortiClient (installed by IT) already has the rights to create the tunnel. Only its window needs a click.
- `setup/vpn/forticlient/VPNConnect.applescript` reads FortiClient's window through macOS Accessibility, without bringing it to the front:
  - **Disconnected:** the window shows "VPN Name: VPN SAML DM" and a **Connect** button.
  - **Connected:** it shows "VPN Connected" and a **Disconnect** button.
  - It only touches the FortiClient process, accepts only `connect`, `disconnect`, `status`, `check` and `dump`, and refuses to click when a label matches more than one button.
- After **Connect**, FortiClient opens the Microsoft sign-in in your browser:
  - If the browser has a Microsoft session, the sign-in finishes by itself.
  - If the session has expired or MFA is due, sign in there. No tool can skip that.
- `vpn up` waits until `jcvs.japfacomfeed.co.id:443` answers (up to 180 s).
- **Not possible:** FortiClient's own Auto Connect / Always Up. The FortiGate turns them off for this profile (`AllowAutoConnect 0`), and only IT can turn them on.

FortiClient 7.4 quirks the script handles (both found in live tests):
- `entire contents` sees nothing inside FortiClient's Electron page, so the script walks the window's elements level by level.
- FortiClient's accessibility tree goes stale while the window is in the background. It showed "VPN Connected" for 36 s after a disconnect. The script turns Electron's accessibility off and on before every read, which rebuilds it.

## Setup (once per Mac, no admin)
macOS only lets an app click buttons in another app after you allow it under **System Settings → Privacy & Security → Accessibility**. Pick one of these:

**A. Allow the app you run the workflow from (simplest).**
- Turn on **Visual Studio Code**, Cursor, Terminal or iTerm, whichever runs the agent.
- `vpn` then runs the script directly with `osascript`.
- Downside: everything inside that app (extensions, AI agents) can then click anything on screen.

**B. Allow only a small app (tighter).**
- Run `setup/vpn/install-applet.sh`. It builds `~/Applications/VPN Connect.app` and opens the Accessibility settings.
- Add **VPN Connect** there with **+**.
- `vpn` uses the app automatically when it exists, so your editor or terminal no longer needs the permission. Remove it from the list.
- After rebuilding the app, turn it off and on again in Accessibility.

Then:
```bash
setup/vpn/vpn setup-check     # click Allow if macOS asks to let it control System Events
setup/vpn/vpn down && setup/vpn/vpn up
```

## Uninstall
```bash
setup/vpn/install-applet.sh --uninstall
```
Then remove VPN Connect (or your editor or terminal) from the Accessibility list.

## Tests
```bash
setup/vpn/tests/run-tests.sh
```
This runs the `vpn` command against a simulated FortiClient script (both the app and the direct `osascript` way), checks the script's safety rules, and builds the app in a temp folder. It needs `shellcheck` (brew), and no permissions. It never touches the real FortiClient.

## Troubleshooting
- **Exit 3, "not allowed"**: the app named in the message isn't on under Accessibility, or VPN Connect was rebuilt. Turn it off and on.
- **"no SAML Login / Connect button found"**: FortiClient's window changed, for example after an update, or it's on another page.
  - Run `setup/vpn/vpn dump` to see its labels.
  - Then adjust `connectLabels`, `disconnectLabels` or `navLabels` at the top of `setup/vpn/forticlient/VPNConnect.applescript`. Rebuild only if you use VPN Connect.app.
- **Exit 1, "not connected after 180s"**: the browser sign-in didn't finish. Look at the browser tab FortiClient opened.
- **Exit 2, connected but GitLab unreachable**: FortiClient's tunnel is up, but DNS or routes don't cover GitLab. Ask IT.

## Alternative without FortiClient
`setup/vpn/openfortivpn/` replaces FortiClient with the open-source openfortivpn client. It needs IT to install it with admin rights; see its `README.md` and `REPORT.md`.
