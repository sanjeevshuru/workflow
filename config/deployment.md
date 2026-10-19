# Deployment config

Used by step 04 (`flow/steps/04-deployment-doc.md`) and the `deployment-writer` role. The deployment docs only cover the **dev** environment for now. Staging and production sections will be added here later.

Never put secrets or `.env` values in this file. Names, hosts and commands only.

## How a dev deploy happens
<!-- TODO (user): fill in once. Step 04 asks on its first run and writes the answer here. -->
- Backend services: `<TODO: e.g. merge to develop triggers the pipeline / manual deploy from <tool> / ask <person>>`
- closio-web-v2: `<TODO>`
- Who runs migrations on dev, and where: `<TODO: e.g. the pipeline runs npm run migrate / a developer runs it from <where>>`

## Dev hosts
| Service | Dev base URL | Source |
|---|---|---|
| ws1closio | `https://dev-closio-ws1-apiprivate.japfacomfeed.co.id` (+ path prefix, TODO confirm) | `closio-web-v2:project_docs/492-test-suite.md` |
| ws2closio | `<TODO>` | |
| ws2targetsales | `<TODO>` | |
| ws2notification | `<TODO>` | |
| ws2pricingengine | `<TODO>` | |
| closio-web-v2 (web app) | `<TODO>` | |

A deployment doc never invents a URL. If a row is TODO, the doc says "ask <owner>" or the step asks the user.

## Backend services
All are Docker images (`CMD ["npm", "start"]`) running on Kubernetes. The development branch is `develop`.

| Service | Migrations | Seeds | Run modes (`RUN_MODE`): one deployment each | Source |
|---|---|---|---|---|
| ws1closio | none (no DB; Redis sessions) | none | single | `nodejs-ws1closio/package.json`, `Dockerfile` |
| ws2closio | `npm run migrate` / `npm run migrate:undo` (sequelize-cli) | `npm run seed` | single | `nodejs-ws2closio/package.json`, `.sequelizerc` |
| ws2targetsales | `npm run migrate` / `npm run migrate:undo` | `npm run seed` | `api` (default), `worker` (BullMQ workers), `incentive` (incentive consumer) | `nodejs-ws2targetsales/src/app.js:25,155-160`, `src/configs/appConfig.js:23` |
| ws2notification | `npm run migrate` / `npm run migrate:undo` | `npm run seed` | `api` (default), `worker` | `nodejs-ws2notification/src/app.js:12-14` |
| ws2pricingengine | `npm run migrate` / `npm run migrate:undo` | `npm run seed` | single | `nodejs-ws2pricingengine/package.json` |

- `migrate:undo` reverts **only the last** migration. Undo several in reverse order, one at a time.
- A change to a worker, queue or cron needs the matching `RUN_MODE` deployment restarted, not only the API.
- Deploy order across services: providers first (ws2 services, then ws1closio), as in `config/services.md` → Cross-service rules.

## closio-web-v2
- Development branch: `development`.
- Build: Docker multi-stage. `ARG ENV` selects `npm run build-${ENV}`, i.e. `build-development` for dev (`vite build --mode development`), served by nginx (`closio-web-v2/Dockerfile`, `nginx.conf`).
- Feature flags are `VITE_ENABLE_*` in `.env.development` and are **baked in at build time**. Changing a flag means a new build and deploy, not a runtime switch.
- The web app calls ws1closio only (`VITE_API_BASE_URL`).
