# Jira config

- Site: `productclosio.atlassian.net` (cloudId `30794731-53bf-4cbe-9c50-b84b8d0cbad0`)
- Projects: `SCRUM`

## How to fetch an issue
The default issue fetch returns only ~13 standard fields. **Custom fields (Figma, Design, Sprint, …) are missing unless you ask for them.** Always request:

| Host | Call |
|---|---|
| Atlassian MCP (`getJiraIssue`) | `fields: ["*all"]`, `expand: "names"`, `responseContentFormat: "markdown"` |
| REST fallback | `GET /rest/api/3/issue/<KEY>?fields=*all&expand=names` |

`expand=names` returns a map from field id to display name (for example `customfield_10039 → "Figma"`). Use it to label every field. Field ids can differ between Jira sites, so **match by display name first** and fall back to the id.

Fetch the parent epic and any requirement-defining linked issues the same way. Epics often carry the Figma link for the whole feature.

## Workflow writes to Jira
The workflow writes to Jira in exactly these three places. Nothing else: no comments, no other field edits, no links.

| When | Write | How |
|---|---|---|
| Step 01, right after the ticket is fetched (**claim**) | Move the ticket to **In Development** if its status is in the **To Do** category | Read `fields.status.statusCategory.key`. Only `new` (To Do) qualifies. List the transitions for the key and pick the one whose name or target status is "In Development" (case-insensitive). Never hard-code an id. If there's no such transition, tell the user and move on; don't pick another one. |
| Step 01, claim | Assign the ticket to **the current user**, only if it's **unassigned** | Get the current user's account id from the Atlassian MCP (`atlassianUserInfo`, or `lookupJiraAccountId` with the user's email). Then edit the issue with **only** the `assignee` field (`{"accountId": "<id>"}`). If it's already assigned, to anyone, leave it and say who it's assigned to. |
| Step 03, after a successful push (Gate 4) | Move the ticket to **Code Review** | Same as above: pick the transition named "Code Review". If there's none, ask. |

- On this site (checked 2026-10-05 on SCRUM-522): the To Do status is named **"ToDo"** (category `new`), and the transitions **"In Development"** and **"Code Review"** exist. Match by category and name as above; ids can change.
- The claim runs automatically: picking the ticket with `/run-ticket` is the user's go-ahead. The orchestrator tells the user in one line what changed ("SCRUM-523: To Do → In Development, assigned to you"), or that nothing needed changing.
- The claim never moves a ticket backwards or sideways. In Development, Code Review, Done or any other non-To-Do status is left as it is.
- If a write fails (permissions, workflow rules), report the error in one line, record it in `status.md` → Notes, and continue the step. The claim isn't required for the rest of the workflow.

## Known custom fields
| Display name | Id (this site) | Use | Goes to |
|---|---|---|---|
| Figma | `customfield_10039` | Design links | `ticket.md` → Figma links found (source: "Jira field: Figma") |
| Design | `customfield_10034` | Design links or notes | `ticket.md` → Figma links found if it holds a figma.com URL, else → Custom fields |
| Sprint | `customfield_10020` | Planning context | `ticket.md` header |
| Story point estimate | `customfield_10016` | Size | `ticket.md` header |
| Start date | `customfield_10015` | Context | Custom fields |
| Team | `customfield_10001` | Context | Custom fields |

To add a field the team starts using, add a row here.

## Unknown fields: never silently dropped
Any field **not** in the table above and **not** on the ignore list is written to `ticket.md` → Custom fields if its value is non-empty, using its display name and its value verbatim (rich text converted to markdown). The analyst then decides whether it matters.

**Scan every field value**, known or unknown, for URLs:
- `figma.com/(design|file|proto|board|make)/…` → Figma links found, with source "Jira field: <display name>"
- other URLs (Confluence, Google Docs, Drive) → `ticket.md` → Links found

## Ignore list (noise)
`statuscategorychangedate`, `statusCategory`, `lastViewed`, `watches`, `votes`, `worklog`, `timetracking`, `timespent`, `timeestimate`, `timeoriginalestimate`, `aggregate*`, `progress`, `workratio`, `issuerestriction`, `customfield_10019` (Rank), `customfield_10017` (Issue color), `customfield_10021` (Flagged, unless set), `customfield_10074` (Agent Sessions), avatar and `self` URLs, `project`, `creator`.
