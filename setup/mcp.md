# MCP setup (Jira + Figma + browser)

Jira and Figma are remote and use OAuth. No tokens go in any file. Each developer signs in once per tool. The browser server (step 03, live browser tests) runs locally.

| Server | URL | Used for |
|---|---|---|
| Atlassian (Jira Cloud) | `https://mcp.atlassian.com/v1/mcp` | Reading tickets, epics, linked issues, comments |
| Figma | `https://mcp.figma.com/mcp` | Reading design nodes from a link |
| Playwright (local) | `npx @playwright/mcp@latest` | Step 03 live browser tests (headed browser; you log in yourself) |

The Jira MCP is also used for three small writes (`config/jira.md` → Workflow writes to Jira): when you pick a ticket, it moves a To Do ticket to **In Development** and assigns it to you if it's unassigned; after the push you approve, it moves the ticket to **Code Review**.

## Claude Code
Already configured in `.mcp.json`. In this folder, run `claude`, then `/mcp`. Pick **atlassian**, then Authenticate; do the same for **figma**.

If you also have the Figma plugin (`plugin:figma:figma`), either one works, so you only need one of them connected.

The service repos sit outside this folder. `.claude/settings.json` adds `../backend` and `../web` as extra directories. If Claude still can't read them, start it with `claude --add-dir ../backend --add-dir ../web`.

## Codex
Add this to `~/.codex/config.toml`:

```toml
[mcp_servers.atlassian]
url = "https://mcp.atlassian.com/v1/mcp"

[mcp_servers.figma]
url = "https://mcp.figma.com/mcp"
```

Then run `codex mcp login atlassian` and `codex mcp login figma`. Older Codex versions also need `experimental_use_rmcp_client = true` at the top level for remote (HTTP) servers. Codex reads `AGENTS.md` automatically. Start with: `run SCRUM-123`.

## Cursor
Already configured in `.cursor/mcp.json`. Open **Settings → MCP** and click **Connect** / sign in for each server. Start with `/run-ticket SCRUM-123`.

## Antigravity
Open **Agent panel → … → MCP Servers → Manage → View raw config** (`mcp_config.json`) and add:

```json
{
  "mcpServers": {
    "atlassian": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://mcp.atlassian.com/v1/mcp"]
    },
    "figma": {
      "serverUrl": "https://mcp.figma.com/mcp"
    }
  }
}
```

`mcp-remote` opens a browser for the Atlassian OAuth. It needs Node 18+.

**Figma on Antigravity is not verified.** Figma's remote server only accepts clients on its approved list. If OAuth is refused, use the Figma **desktop** MCP server instead:
1. Open the Figma desktop app, switch to Dev Mode, and enable the MCP server (Preferences).
2. Set the `figma` entry to `{ "serverUrl": "http://127.0.0.1:3845/mcp" }`.

The desktop server also accepts frame links, but the desktop app must be running.

Start with `/run-ticket SCRUM-123`. That's the workflow in `.agent/workflows/`.

## Figma: links are all you need
Paste frame links such as `https://www.figma.com/design/<fileKey>/<name>?node-id=12-345`. The MCP reads the file key and node id from the link, so no selection is needed in the app.

- Always use **Copy link to selection** on the frame or section, so the link has a `node-id`.
- One flow, many nodes? Paste all the links, or one link to the **Section** that contains the screens. The workflow expands it (see `flow/playbooks/figma.md`).
- **Seat limits:** Starter plans and View/Collab seats get about 6 Figma MCP calls **per month**. Dev or Full seats on paid plans get per-minute limits. Planners should run on a Dev or Full seat.
- **This team's seat type: unknown.** The workflow doesn't block on it. It keeps Figma calls minimal and stops to ask on the first rate-limit or quota error. Once you know the seat type, write it here.

## Jira fields
The Jira MCP's default issue fetch skips custom fields such as **Figma**. The workflow always asks for all fields (`config/jira.md`). If your tool's Jira MCP can't request `*all`, use the REST fallback in `config/jira.md`, or paste the custom field values.

## Browser for live tests (step 03)
| Tool | Browser |
|---|---|
| Claude Code | `playwright` in `.mcp.json` (already configured; needs Node 18+). The first run downloads a browser, so allow it once with `npx playwright install chromium` if asked. It opens **headed**, so you can log in. |
| Codex | Add to `~/.codex/config.toml`: `[mcp_servers.playwright]` with `command = "npx"`, `args = ["@playwright/mcp@latest"]` |
| Cursor | Built-in browser (enable the browser tools in Settings). `playwright` is also in `.cursor/mcp.json` as an alternative. |
| Antigravity | Built-in browser agent (install its Chrome extension when prompted) |

If no browser tool works, the workflow falls back to a manual run: it walks you through each case and records your pass or fail.

## GitLab CLI (MR review)
MR review (`/review-mr`, `flow/REVIEW.md`) lists the MRs where you're a reviewer and posts comments through the `glab` CLI. It works the same in every tool. Step 03 doesn't need it.
1. Install it: `brew install glab` (Windows: `winget install glab.glab`).
2. In GitLab (`https://jcvs.japfacomfeed.co.id/-/user_settings/personal_access_tokens`), create a personal access token with the **`api`** scope. `read_api` isn't enough, because posting comments is a write. Give it an expiry date.
3. Connect the VPN, then run `glab auth login --hostname jcvs.japfacomfeed.co.id` and paste the token when asked. Choose HTTPS as the git protocol.
4. Check: `glab auth status --hostname jcvs.japfacomfeed.co.id`.

The token lives only in glab's own config (`~/.config/glab-cli/`). It never goes in this folder, in `runs/` or in `reviews/`. When it expires, run step 3 again.

## When an MCP is unavailable
The workflow never guesses. It says which server is down, then asks for one of these:
- **Jira**: fix the connection, or paste the ticket (summary, description, AC, relevant comments). The source is recorded as "pasted by user".
- **Figma**: fix the connection, or give PNG exports per frame plus a short written flow. Plans built this way say so in their header.

The fallback is recorded in `runs/<KEY>/status.md` → Notes.
