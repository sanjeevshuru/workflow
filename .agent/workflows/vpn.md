---
description: Connect, disconnect or check the company VPN through FortiClient, with no clicks (up | down | status)
---

1. Take `up` (the default), `down` or `status` from the user's message.
2. **up**: follow `flow/playbooks/vpn.md` → Procedure. Run `setup/vpn/vpn up` and allow it up to 200 s (it waits for the Microsoft sign-in in the browser).
3. **down**: run `setup/vpn/vpn down`, only because the user asked for it. **status**: run `setup/vpn/vpn status`.
4. Reply in one line with the result.
