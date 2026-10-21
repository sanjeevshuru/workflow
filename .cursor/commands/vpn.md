# vpn

Connect, disconnect or check the company VPN through FortiClient, with no clicks. The word after the command is `up` (the default), `down` or `status`.

- **up**: follow `flow/playbooks/vpn.md` → Procedure. Run `setup/vpn/vpn up` and allow it up to 200 s (it waits for the Microsoft sign-in in the browser).
- **down**: run `setup/vpn/vpn down`, only because the user asked for it.
- **status**: run `setup/vpn/vpn status` and report its lines.

Reply in one line with the result.
