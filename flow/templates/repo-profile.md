# Repo profile: <service>

- Path: `<relative path>` · Development branch: `<branch>` (from config/services.md)
- derived_at_commit: `<sha>` · derived_at: <YYYY-MM-DD> · by: <KEY> code-scout (<host tool>)
- Documented sources: conventions `<files | none>` · lessons.md `<yes | none>` · completed.md `<yes | none>` · project_docs `<yes | none>`
- Depth: <modules derived deeply: …; rest: shallow>

## Directory map
- `<dir>/`: <what lives here>

## Tooling
- Scripts: test `<>`, lint `<>`, build `<>` · Test framework and setup: <> · Coverage gates and hooks: <>

## Patterns (conventions)
| Layer | Pattern | Examples (≥3) | Source | Confidence |
|---|---|---|---|---|
| e.g. controller | thin, delegates to service, `{status,message,data}` envelope | `a.js:10-40`, `b.js:…`, `c.js:…` | documented: CLAUDE.md / derived | high / low |

## Anti-patterns (don't copy)
| What | Where | Evidence | Rule |
|---|---|---|---|
| e.g. forwards `req.headers` to downstream | `x.js:22` | fix commit `abc123` "fix content-length hang" | build an explicit header object |

## Gotchas
- <global middleware, interceptor or status rewrite that changes behaviour> [code: path:line]

## What has been built (by module)
### <module>
- <feature>: routes `<…>`, files `<…>`, landed in `<sha / ticket>` (<date>)

## Reusable inventory
| Piece | Path | What it does | Used by (count / examples) | Source |
|---|---|---|---|---|

## Legacy areas
- `<path>`: <why it's legacy (deprecated marker, superseded by …)>. Never use it as a sibling.

## Change log
| Date | Commit | By (ticket) | What was added or refreshed |
|---|---|---|---|
