---
description: Connect, disconnect or check the company VPN with openfortivpn, with no clicks (up | down | status)
---

1. Take `up` (the default), `down` or `status` from the user's message.
2. **up**: follow `flow/playbooks/vpn.md` → Procedure, starting with step 0 (`setup/vpn/vpn installed`; if it exits 3, ask the user to install it now). Run `setup/vpn/vpn up` and allow it up to 200 s (the Microsoft sign-in runs in a background browser tab).
3. **down**: run `setup/vpn/vpn down`, only because the user asked for it. **status**: run `setup/vpn/vpn status`.
4. Reply in one line with the result.
