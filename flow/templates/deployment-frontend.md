<!-- STATUS: DONE | BLOCKED (questions below) -->
# Deploy to dev: <KEY> (frontend)

<one or two lines: what changes for the user, in plain words>

| Repo | MR | Branch | Pushed commit |
|---|---|---|---|
| closio-web-v2 | <url> | `<branch>` | `<hash>` |

## 1. Before you deploy
- [ ] The MR above is merged into `development`.
- [ ] These backend endpoints are live on dev: <`METHOD path` (from <KEY> backend doc / ticket <other KEY>) …, or "none">
- [ ] <new npm dependency: none | `<package>@<version>` (installed by the image build)>

## 2. Feature flags
<!-- "No flag changes." if none. Flags are baked in at build time. -->
| Flag | `.env.development` | Staging / production |
|---|---|---|
| `VITE_ENABLE_<NAME>` | `<old>` → `<new>` | unchanged (later environment) |

New `VITE_*` variables (names only): <none | `VITE_<NAME>`: what it's for>

## 3. Build and deploy
1. Build with the dev mode: the image's `ENV=development` (`npm run build-development`).
2. Deploy: <from config/deployment.md, or "TODO: ask <owner>">

New or changed pages: <route path → screen name, or "none">

## 4. Verify on dev
Web app: <dev URL from config/deployment.md>. Log in as <role needed>.

- [ ] <page path>: <what you should see>
- [ ] <action>: <expected result or message>
- [ ] <the key error or empty state>: <expected>

## 5. Rollback
1. <Turn the flag off in `.env.development` and rebuild, if the change is behind a flag>, or redeploy the previous build.
2. <anything else>

## Open items
- <known gaps from the browser report, `TODO: ask` lines, notes for staging or prod later; or "none">

## Questions (only if BLOCKED)
- <question, why it matters>

<details><summary>Sources</summary>

- <deployment-facts.md § closio-web-v2>, <frontend-plan.md § …>, <browser/testing-doc.md cases …>, <config/deployment.md row …>
</details>
