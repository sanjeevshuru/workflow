# Services

Paths are relative to this `workflow/` folder. Clone the repos beside it:

```
Japfa/
├── workflow/
├── backend/nodejs-*
└── web/closio-web-v2
```

If your layout differs, change the paths here only.

Step 03 also uses `config/git.md` (branches, commits, MRs) and `config/postman.md` (running services locally, test auth and data).

Agents: read a service's **Conventions** files before planning changes to it, in the order given by `flow/playbooks/code-analysis.md` §1. They take precedence over this file. **`completed.md`** (where listed) is the team's index of reusable work. Always read it.

## Adding a service
Copy a block below and fill in **Path**, **Owns** and **Keywords**. Set **Conventions** to the documented files that exist, or to `none`. The first ticket that touches the repo derives its profile in `knowledge/<service>.md` (patterns, anti-patterns, what's been built, reusable pieces). Nothing else is needed.

Documented sources today:

| Service | conventions | lessons.md | completed.md | profile |
|---|---|---|---|---|
| ws1closio | yes | no | no | `knowledge/ws1closio.md` (derived on first ticket) |
| ws2closio | yes | no | no | `knowledge/ws2closio.md` |
| ws2notification | none | no | no | `knowledge/ws2notification.md` |
| ws2pricingengine | none | no | no | `knowledge/ws2pricingengine.md` |
| ws2targetsales | yes | yes | yes | `knowledge/ws2targetsales.md` |
| closio-web-v2 | yes | yes | yes | `knowledge/closio-web-v2.md` |

## Backend defaults (all backend services)
- Stack: Node.js, Express, Sequelize + PostgreSQL, Mocha/Chai/Sinon + nyc
- API docs: `docs/openapi/` + JSDoc `@openapi` (`src/swagger.js`)
- Commands: unit `npm run test:unit` · all `npm test` · coverage `npm run coverage:check` (80/70/80/80) · lint `npm run lint` · dev `npm run dev`
- Layout: `src/{routes,controllers,services,models,migrations,middlewares,utils}`
- Development branch (sync target): `develop`. The remote's default (`origin/HEAD`) is `master`; never sync to it.

## ws1closio: API gateway / BFF
- Path: `../backend/nodejs-ws1closio`
- Owns: auth, users, roles, applications, object permissions (`mt_*`). Proxies and aggregates routes to the ws2 services for web and mobile. No DB of its own (Redis sessions).
- Keywords: login, auth, session, user, role, permission, gateway, proxy, "expose to web/mobile"
- Conventions: `.claude/CLAUDE.md`, `.claude/SKILLS.md`, `.claude/commands/new-proxy-endpoint.md`
- Gotchas: `src/middlewares/errorHandler.js` rewrites every 404 to **597** (original status in `details.upstream_status`). Never forward `req.headers`; build an explicit header object.
- Differs: **no test suite** (`npm test` exits 1). Layout is `src/{routes,controllers,schemas,middlewares}`.
- Calls: ws2closio, ws2notification, ws2pricingengine, ws2targetsales

## ws2closio
- Path: `../backend/nodejs-ws2closio`
- Owns: orders, order items, fulfilment, stock and capacity allocation, bulk order upload, external orders, forms (formulas, frequencies, queries, fields, submissions), surveys, credit limit (SAP), approvals, salesperson product map, custom field mappings, partner configurations, role-partner and user-sales-area mappings, data sources, file uploads, Jasper reports. Crons and workers.
- Keywords: order, fulfilment, allocation, stock, form, submission, survey, credit limit, approval, salesperson, product map, field mapping, partner configuration
- Conventions: `CLAUDE.md` (TDD mandatory, characterization tests, no N+1, paginate lists, `partner_id` on every query, `pgDbUtils` for joins/transactions, Sequelize for CRUD), `SKILLS.md`, `project_docs/`
- Calls: ws2notification, ws1 approval, SAP, Google Maps

## ws2notification
- Path: `../backend/nodejs-ws2notification`
- Owns: broadcasts, templates, categories, deeplinks, integrated variables, user inbox, external triggers. RabbitMQ consumers, FCM push.
- Keywords: notification, broadcast, push, FCM, template, deeplink, inbox, audience
- Conventions: none in repo. Derived into `knowledge/ws2notification.md` (playbook §1A).

## ws2pricingengine
- Path: `../backend/nodejs-ws2pricingengine`
- Owns: pricing types, priority, procedure, schema mapping, price resolution, UDM full and delta sync, quarantine reprocessing
- Keywords: price, pricing, pricing schema, procedure, UDM, sync, quarantine
- Conventions: none in repo. Derived into `knowledge/ws2pricingengine.md` (playbook §1A). Also read `docs/full-sync.md` and `docs/delta-sync.md`.

## ws2targetsales
- Path: `../backend/nodejs-ws2targetsales`
- Owns: sales targets, incentive engine (payout configs, point slabs, achievements, unlocks, slab corrections, feed ingestion, archival). BullMQ workers, crons, S3 feeds, alert emails.
- Keywords: target, incentive, payout, slab, achievement, unlock, feed, archival, Business 1, Business 2
- Conventions: `AGENTS.md` (same as `.claude/CLAUDE.md`), `lessons.md`, **`completed.md`**, `project_docs/` (ticket notes, test suites, Postman docs)
- Business boundary: Business 1 and Business 2 are separate code paths. A B1 change follows the closest **B1** sibling. Never borrow B2 behaviour or helpers.
- Calls: ws2closio

## closio-web-v2: back-office web (frontend)
- Path: `../web/closio-web-v2`
- Stack: Vue 3, Vuetify 3, Vite, Pinia stores, Vitest + @vue/test-utils
- Layout: `src/{views,components,composables,stores,api,router,constants,utils,test}`
- Owns: all back-office screens (orders, forms, pricing, incentives and payout config, field management, approvals, monitoring)
- Keywords: screen, page, UI, table, grid, form, back office, web
- Conventions: `.claude/CLAUDE.md` (gated, never assume), `lessons.md`, **`completed.md`**, `SECURITY.md`, `project_docs/`
- Reuse sources: `src/components/` (shared, e.g. `BaseDataTable`, `MessageCard`, `LoadingSpinner`, `MonthYearPicker`, cell renderers) and `src/views/<module>/components/` (module, e.g. `incentive/components/IncentivePeriodPicker.vue`); `src/composables/`, `src/utils/`
- Business boundary: B1 and B2 responses keep their own raw shapes up to the view (`lessons.md` 2026-09-03).
- Feature flags: `VITE_ENABLE_*` in `.env.development`, `.env.staging`, `.env.production`. Mocks: `VITE_USE_MOCKS`.
- Commands: test `npm run test:run` · build `npm run build` · dev `npm run dev`
- Calls: ws1closio only (`VITE_API_BASE_URL`)
- Scope isolation: in a `frontend` ticket, backend repos aren't read at all. The API contract comes from the ticket, the `sources/` tech specs, or the user.
- Development branch (sync target): `development`. The remote's default (`origin/HEAD`) is `main`; never sync to it.

## Cross-service rules
- Anything the UI needs goes **ws2 service → ws1closio route → closio-web-v2**. Plan and implement in that order.
- Changes between services must stay backward compatible, unless the plan explicitly calls for a coordinated release.
