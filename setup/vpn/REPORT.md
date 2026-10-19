# VPN automation through FortiClient: test report

Branch `feature/vpn-automation` · 2026-10-19 · macOS 27.0.1 · FortiClient VPN 7.4.3 (free VPN-only edition), profile "VPN SAML DM"

## Verdict
**Feasible, working live, and now part of the workflow.**
- `setup/vpn/vpn up` connected the VPN with **no clicks and no sign-in prompt** on all 6 live attempts, in 13–15 s each.
- GitLab answered after every connect: `git ls-remote` on `nodejs-ws1closio` returned `develop`.
- It needs no sudo and no admin. The one-time setup is allowing an app under Privacy & Security → Accessibility.

Limits:
- The Microsoft sign-in completes by itself only while the browser has a Microsoft session. When it has expired or MFA is due, the user signs in once in the browser.
- It needs a logged-in, unlocked Mac.

## The teammate's folder (`fortiauto 2/`)
**Not added as-is. Its two good ideas are folded into `setup/vpn/`.**

| Point | `fortiauto` | Result |
|---|---|---|
| Approach | `osascript` clicks Connect in FortiClient through Accessibility | same as ours; it confirmed the direction |
| Runs without building an app | ✅ | **adopted**: `vpn` now runs the script directly when VPN Connect.app isn't built |
| Refuses to click when several buttons match | ✅ | **adopted** in our script |
| Permission denied | ❌ the errors are swallowed, so `--diagnose` reports "completed" with an empty list (reproduced live) | ours detects it, including macOS's raw `-1728 … assistive access`, and exits 3 with the app to allow |
| Finding the button | ❌ uses `entire contents`, which returns **nothing** inside FortiClient's Electron page (reproduced live), so it could never find Connect | ours walks the elements level by level |
| Stale window state | ❌ not handled | ours rebuilds the tree before each read (see below) |
| Focus | brings FortiClient to the front on every run | ours stays in the background |
| Verifies the connection | ❌ "clicked" isn't "connected" | ours waits until GitLab answers |

The folder is still at the workflow root, untracked. It's safe to delete, and nothing from it was installed (no LaunchAgent found).

## Found in live testing (fixed)
1. **`entire contents` misses Electron content.** FortiClient's window reported 0 elements with it. Walking `UI elements` by hand finds everything: the heading, "VPN Connected", the IP, username, duration, and the Connect/Disconnect buttons.
2. **Stale accessibility tree.** After a disconnect, the tree kept showing "VPN Connected" and a Disconnect button for **36 s+** while the tunnel was down. The next `up` then wrongly said "already connected". Turning Electron's `AXManualAccessibility` off and on rebuilds the tree at once, so the script now does it before every read. After the fix, the state was right in every check.
3. **Empty "clicked" label.** `down` read the button's label after pressing it, when the element was already gone. It now reads it first.
4. **A hung script could block `vpn` (found by the tests).** The background `osascript` held the caller's output pipe, so a timeout still waited for it. Fixed: the output is detached and the job is killed on timeout.

Real UI labels confirmed:
- **Disconnected:** a "VPN Name: VPN SAML DM" pop-up and a **Connect** button. It's "Connect", not "SAML Login".
- **Connected:** "VPN Connected", IP, username, duration, bytes, and a **Disconnect** button.

## Live results
| Test | Result |
|---|---|
| `status` while disconnected, then connected | correct both ways after fix 2 (4–7 s; the tree walk is the slow part) |
| `up` from disconnected | 6/6 connected, 13–15 s, no clicks, no sign-in prompt |
| `up` when already connected | 0 s, no click (GitLab already reachable) |
| GitLab after connect | `git ls-remote --heads origin develop` OK every time |
| `down`, then `down` again | clicked Disconnect, GitLab unreachable; then "already disconnected" |
| 3 full cycles back to back (after fixes) | all correct |
| FortiClient window closed | reopened in the background; status correct |
| Permission missing (before the grant) | macOS `-1728 not allowed assistive access`, now detected (exit 3) |

## Offline tests
`setup/vpn/tests/run-tests.sh` → **57 passed, 0 failed**. They never touch the real FortiClient: `open`, `osascript` and `nc` are fakes.
- **Lint:** shellcheck, bash 3.2 parse, the AppleScript compiles.
- **Script rules (static checks):** only touches the FortiClient process; only the five request words; no shell command built from input; no `entire contents`; refreshes the tree; refuses ambiguous clicks; reads labels before pressing; detects macOS's error text.
- **`vpn` through VPN Connect.app (simulated):** connect, repeated commands, status, down, already connected, connected but GitLab unreachable (exit 2), not allowed (exit 3), button not found, sign-in timeout, app not answering, locks.
- **`vpn` through direct `osascript` (simulated):** connect and down, "not allowed" naming the app, raw `-1728` error, hung script stopped in 3 s, forced app mode with no app.
- **install-applet.sh:** build in a temp folder (bundle id, hidden from the Dock, signature), uninstall.

Mutation check:
- Going back to `entire contents` → caught.
- Dropping the raw-error detection → caught.
- Dropping the output detach → not caught, because the timeout kill alone already stops a hung job. The detach is a second safeguard.

The openfortivpn alternative (`setup/vpn/openfortivpn/`) still passes its 79 tests.

## In the workflow
- **When it runs:** `flow/playbooks/vpn.md`, called at ORCHESTRATOR Start/Resume (action 0) and REVIEW R0. It checks GitLab, runs `setup/vpn/vpn up` if needed, asks on failure, and records the result in `status.md` → Network.
- **Network errors** in repo-sync fetch, git push and the MR-review fetch/glab → reconnect, then retry once.
- **Rules:** AGENTS.md allows `setup/vpn/vpn up` in every step and never `down` unless asked. The `run-ticket` and `review-mr` skills use a 200 s Bash timeout for `up`.

## Decisions for you
1. **Which app holds the Accessibility permission.** VS Code has it now, which made these tests possible. It works, but every extension and agent in VS Code can then click anything on screen. Tighter option: run `setup/vpn/install-applet.sh`, allow **VPN Connect**, then remove VS Code from the list. `vpn` switches to the app automatically. (Building the app from the agent was blocked by the auto-mode classifier, so you run that script yourself.)
2. **`.claude/settings.json`** still has the uncommitted `Bash(vpn …)` entries, which no longer match the `setup/vpn/vpn` path. Suggest `git checkout .claude/settings.json`. Separately, you could allow `Bash(setup/vpn/vpn check)`, `Bash(setup/vpn/vpn status)` and `Bash(setup/vpn/vpn up)`, so runs don't prompt.
3. **`fortiauto 2/`**: delete it, or keep it outside the repo. It isn't committed.
