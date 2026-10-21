---
name: vpn
description: Connect (or disconnect, or check) the company VPN with openfortivpn, with no clicks. Use when the user says "connect vpn", "vpn up", "vpn down", "vpn status", or when GitLab (jcvs.japfacomfeed.co.id) is unreachable.
argument-hint: "[up | down | status]"
---

Arguments: `$ARGUMENTS`. Empty or `up` connects; `down` disconnects; `status` reports.

- **up**: follow `flow/playbooks/vpn.md` → Procedure. Run `setup/vpn/vpn up` in the foreground with a Bash `timeout` of 200000 ms (the default 120 s is shorter than its sign-in wait). On a non-zero exit, ask with the AskUserQuestion tool, using the playbook's options.
- **down**: run `setup/vpn/vpn down`, only because the user asked for it.
- **status**: run `setup/vpn/vpn status` and report its lines.

Reply in one line with the result, for example "VPN connected; GitLab reachable."
