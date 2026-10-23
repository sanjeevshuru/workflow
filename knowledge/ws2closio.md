# Repo profile: ws2closio

- Path: `../backend/nodejs-ws2closio` · Development branch: `develop` (from config/services.md)
- derived_at_commit: `4c05cbd` (`develop`, 2026-10-20) · derived_at: 2026-10-22 · by: SCRUM-529 code-scout (Claude Code)
- Documented sources:
  - conventions: `CLAUDE.md` (TDD, layering, multi-tenancy, patterns, "What NOT to do"), `SKILLS.md` (short rules + scaffold command names; the command files are not in the repo)
  - `lessons.md`: none
  - `completed.md`: none
  - `project_docs`: **not tracked by git** (`git ls-files project_docs` empty); local copies only. On the dev machine they sit in stash `c04441e` (SCRUM-529 sync): `451.md` + Salesperson Product Map test docs
- Depth: incentive S2S endpoint (salesperson product map), auth middlewares, replica-schema users/customers queries, error chain, tests: derived deeply. Rest: shallow (directory map, tooling)

## Directory map
- `src/routes/`: one file per feature (40), aggregated in `index.js` and mounted with `router.use('/api', …)`; each route file declares its full path (e.g. `/incentives/v1/salesperson-product-map`)
- `src/controllers/`: request validation + envelope; `src/services/`: SQL / Sequelize; `src/models/`: Sequelize models (PascalCase), replica models call `.schema('pgclosiorep')` or set `schema: 'pgclosiorep'`
- `src/middlewares/`: `verifyServiceCredentials` (S2S, multi-client), `verifyClientAuth` (S2S, single client from axiosConfig), `validatePartnerHeader`, `validateUserHeader`, `errorHandler`, `tracingMiddleware`, `resolvePlatformHeader`, `verifyApprovalCallbackToken`
- `src/configs/`: `pgDbConfig.js` (schema + `replicate_schema`), `credentialsConfig.js` (`SERVICE_CREDENTIALS` → Map, loaded at boot `src/app.js:21`), axios, redis, sequelize
- `src/constants/`: per-feature constant files (`salespersonProductMap.js`, `orderStatus.js`, …), `errorCodeEnums.json`
- `src/utils/`: `createError.js`, `sequelizeUtils.js` (`parseSequelizeError`), `pgDbUtils.js`, `helper.js` (`buildPagination`), `dateFunctions.js`, `logFunctions.js`
- `src/crons/`, `src/workers/`, `src/triggers/`, `src/migrations/`, `src/seeders/`
- `test/unit/{controllers,services,middlewares,configs,utils,models,crons,constants}`, `test/api/` (supertest), `test/helpers/` (`testApp.js`, `server.js`), `test/stubs/`, `test/fixtures/`
- `docs/openapi/*.js` (JSDoc `@openapi`), `docs/components/schemas/`; globbed by `src/swagger.js:18`

## Tooling
- Scripts: test `npm test` (`mocha --recursive test --exit`, NODE_ENV=test), unit `npm run test:unit`, api `npm run test:api` (PORT=0), coverage `npm run coverage:check` (nyc 80/70/80/80), lint `npm run lint`, circular `npm run check:circular`
- Test framework: Mocha + Chai + Sinon + proxyquire (`.noCallThru()`) + supertest + nock
- Hooks: none (no `.husky/`); no `.mocharc`, no `.nycrc` (thresholds are on the command line)

## Patterns (conventions)
| Layer | Pattern | Examples (≥3) | Source | Confidence |
|---|---|---|---|---|
| Route | `router.<verb>(fullPath, ...middlewares, asyncHandler(fn))` with a file-local `asyncHandler` one-liner; mounted `router.use('/api', x)` in `index.js` | `salespersonProductMapRoutes.js:4-13`; 24 of 40 route files define `asyncHandler`; `index.js:52-90` | documented CLAUDE.md:318-339 + derived | high |
| S2S route auth | `verifyServiceCredentials` → `validatePartnerHeader` → handler; no `validateUserHeader` | `salespersonProductMapRoutes.js:8-13` (only user) | derived | low (1 example) |
| Success envelope | `res.status(200).json({ status:'success', message:'<X> retrieved successfully', data })` | 73/100 success responses carry `message`; `integrationErrorLogsController.js:41-45`; CLAUDE.md:375-379, :590 | documented + derived | high |
| Error flow | `return next(createError({error_code, message, ...}, httpStatus))`; global `errorHandler` → `{status:'error', error_code, message, details, replacements, pg_error}` | `salespersonProductMapController.js:36-47`, `verifyServiceCredentials.js:9-17`, `errorHandler.js:11-25` | documented CLAUDE.md:586-605 + derived | high |
| Replica reads | `sequelize.query(sql, { replacements: {named}, type: QueryTypes.SELECT })` on `${replicate_schema}.<table>` | 17/17 replica services, e.g. `usersService.js:17-33`, `customersService.js:54-59`, `creditLimitService.js:155-180` | derived (CLAUDE.md:480 says "raw pg/pgDbUtils" for joins; replica practice is `sequelize.query`) | high |
| Partner scope for customers | through the owning user: `JOIN users u ON u.id = c.sales_id … u.partner_id = :partnerId` | `customersService.js:69-75, :213, :239-244`; `creditLimitService.js:160-174, :188-197` | derived | high |
| Soft delete | `deleted_at IS NULL` on every replica table in the join | `usersService.js:61, :106`; `customersService.js:174-175`; `ordersServices.js:2229-2230` | derived | high |
| Integer counts | `COUNT(...)::int` (no pg type parser configured) | `stockAllocationServices.js:196`, `customersService.js:389`, `orderFulfillmentsService.js:853-879`, `frequentlyOrderedService.js:44`, `surveysService.js:120` | derived | high |
| DB error in service | Sequelize-model services: `throw createError(parseSequelizeError(error), 500)`; raw-query helpers: `throw parseSequelizeError(error)` (56 sites), wrapped by the caller | `salespersonProductMapService.js:37-39`; `usersService.js:41, :82, :126` | derived | high (two styles; see Gotchas) |
| Controller catch | log `ERROR` via `writeLog`; forward errors that have `error_code`; otherwise `500 INTERNAL_SERVER_ERROR` with a feature message | `salespersonProductMapController.js:190-211`; `integrationErrorLogsController.js:46-…`; CLAUDE.md:380-383 | derived | medium |
| Query validation | hand-written in the controller, fail-fast, per-field codes, only known keys checked; `DUPLICATE_QUERY_PARAM` for repeated keys | `salespersonProductMapController.js:10-137` | derived | low (1 example for S2S) |
| Tests | `test/unit/<layer>/<x>.spec.js` (123 `.spec.js` vs 6 `.test.js`); service tests proxyquire `../db/init` and `../utils/sequelizeUtils`; API tests use `createTestApp` + proxyquired real route file with stubbed service, logger and `credentialsMap` | `usersService.spec.js:1-30`; `salespersonProductMapService.spec.js:1-30`; `salespersonProductMap.api.spec.js:1-65` | derived (CLAUDE.md:33, :732 say `.test.js`) | high |
| OpenAPI | one `docs/openapi/<feature>Docs.js` with `@openapi` blocks; header params listed; AC coverage in the description | `frequentlyOrderedDocs.js:1-60`, 25 files in `docs/openapi/` | documented CLAUDE.md:56-59 | high |

## Anti-patterns (don't copy)
| What | Where | Evidence | Rule |
|---|---|---|---|
| Lowercase enum literal `'shipto'` | `bulkOrderValidationService.js:141` | enum values are uppercase (`customersService.js:15-17`) | use the uppercase DB enum value via a constant |
| Unwrapped `throw parseSequelizeError(error)` reaching `errorHandler` | pattern in 56 service sites | its `status` field is the string `'error'`; `errorHandler.js:15` would call `res.status('error')` (read, not run) | wrap with `createError(…, 500)` before it leaves the service, as `salespersonProductMapService.js:38` |
| DB error responses expose `pg_error.stack` | `sequelizeUtils.js:74-79` → `createError.js:28` → `errorHandler.js:23` | read from code | be aware; any change to it is a deviation to label |
| `.env.example` `SERVICE_CREDENTIALS` line is invalid JSON (`{{…}}`) | `.env.example:30` (from `ad75d40`) | `credentialsConfig.js:9-13` throws on invalid JSON at boot | never copy that line as is |
| Repeated fixes after the sibling feature | salesperson product map: `2f686e5`, `ff95c39`, `d4e829c` within 2 weeks of `adec844` | empty result changed 200 → 404; duplicate/empty params added | define empty-result and query-param behaviour explicitly in the plan |

## Gotchas
- `validatePartnerHeader` replies itself (`res.status(403).json`), adds `details`, accepts legacy `partner-id`/`partner_id` headers, and its regex requires UUID version 1–5 and variant 8/9/a/b [code: src/middlewares/validatePartnerHeader.js:4-30]
- It checks format only; no code checks that the partner exists (`Partners` model never imported)
- `verifyServiceCredentials` accepts any client in `SERVICE_CREDENTIALS` (no per-route scoping); the app won't boot without a valid `SERVICE_CREDENTIALS` [code: src/configs/credentialsConfig.js:1-30, src/app.js:21]
- Two S2S auth middlewares exist: `verifyServiceCredentials` (multi-client, three codes) and `verifyClientAuth` (single client, always `INVALID_CLIENT_AUTH`, used by `internalFormRoutes.js`)
- No Users model: `pgclosiorep.users` columns are known only from raw SQL (`id`, `external_id`, `partner_id`, `email`, `full_name`, `first_name`, `last_name`, `status`, `role_id`, `upline_id`, timestamps, `deleted_at`) [code: src/services/usersService.js]
- The Customers model has no `partner_id` attribute; replica tables are owned by another (Go) backend and have no migrations here, so verify the live schema before writing seed SQL
- Id/partner column types are mixed in casts (`c.sales_id::text = u.id`, `u.partner_id::uuid = :partnerId::uuid`) [code: ordersServices.js:2164, creditLimitService.js:174]
- `test/helpers/server.js` deliberately avoids `routes/index.js`; API specs mount one route file through `createTestApp`
- CLAUDE.md says "paginate every list" and "validateUserHeader on partner routes"; S2S incentive feeds differ by their ACs

## What has been built (by module)
### Incentive engine S2S feeds
- Salesperson product map: `GET /api/incentives/v1/salesperson-product-map` (routes/controller/service/constants `salespersonProductMap*`, model `SalespersonProductMap`). Landed `adec844` 2026-08-11 (451); S2S auth `ad75d40` 2026-08-12; fixes `2f686e5`, `ff95c39` (404 on empty), `d4e829c` (duplicate params, case-insensitive status). No OpenAPI doc.
### Customers and users (replica readers)
- `customersService.js` (customer list with shared mappings, ship-to, registration status), `usersService.js` (external id, by id, by external id, team members by upline), `creditLimitService.js` (customer by external id within partner)
### Other modules (shallow)
- Orders, order items, fulfilments, stock and capacity allocation, bulk order upload, external orders, forms/formulas/frequencies/queries/submissions, surveys, credit limit (SAP), approvals (webhook/callback/tools/request), custom field mappings, partner configurations, role-partner and user-sales-area mappings, data sources, file uploads, Jasper reports, integration error logs (sfa-32/111), translations (multi-partner, Redis cache, `51d30da`)

## Reusable inventory
| Piece | Path | What it does | Used by (count / examples) | Source |
|---|---|---|---|---|
| `verifyServiceCredentials` | `src/middlewares/verifyServiceCredentials.js:4-45` | 401 `MISSING_CLIENT_CREDENTIALS` / `UNKNOWN_CLIENT` / `INVALID_CLIENT_AUTH` | salesperson product map | derived |
| `validatePartnerHeader` | `src/middlewares/validatePartnerHeader.js:2-36` | 403 `MISSING_PARTNER_ID` / `INVALID_PARTNER_ID`; sets `req.partner_id` | most partner routes | derived |
| `createError` | `src/utils/createError.js:13-53` | normalises axios / WS / runtime / object / string errors | everywhere | derived |
| `parseSequelizeError`, `mapSequelizeErrorToHttpStatus` | `src/utils/sequelizeUtils.js:18-89` | DB error → `DUPLICATE_KEY` / `FOREIGN_KEY_CONSTRAINT` / `CHECK_CONSTRAINT` / `VALIDATION_ERROR` / `SEQUELIZE_ERROR` | 56+ services | derived |
| `errorHandler`, `catch404NotFound` | `src/middlewares/errorHandler.js` | error body | app | derived |
| `replicate_schema` | `src/configs/pgDbConfig.js:20` | replica schema name (default `pgclosiorep`) | 17 services | derived |
| `usersService.getUserById`, `getUserByExternalId`, `getUserExternalId`, `getTeamMembers` | `src/services/usersService.js` | replica user lookups | approvals, orders, credit limit | derived |
| `buildPagination` | `src/utils/helper.js:16` | page/limit/offset, max 200 | list endpoints | documented |
| `createTestApp` | `test/helpers/testApp.js:4-25` | Express app + shared error handler for API specs | API specs | derived |

## Legacy areas
- `verifyClientAuth` (single-client S2S) is superseded for new S2S feeds by `verifyServiceCredentials` (`ad75d40` replaced it on the salesperson product map route). Don't use it for new incentive endpoints.

## Change log
| Date | Commit | By (ticket) | What was added or refreshed |
|---|---|---|---|
| 2026-10-22 | `4c05cbd` | SCRUM-529 code-scout | Profile created. Incentive S2S sibling, auth middlewares, replica users/customers queries, error chain and tests derived deeply |
