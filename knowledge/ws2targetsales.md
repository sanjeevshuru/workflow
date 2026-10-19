# Repo profile: ws2targetsales

- Path: `../backend/nodejs-ws2targetsales` · Development branch: `develop`
- derived_at_commit: `d3ee24f` (`develop`, merge of SCRUM-498) · derived_at: 2026-10-01 · by: SCRUM-519 code-scout (Claude Code)
- Documented sources:
  - conventions: `AGENTS.md` (process rules only: gates, lessons, completed, Postman docs; no code conventions)
  - `lessons.md`: yes (2026-07-16 … 2026-09-27)
  - `completed.md`: yes (SCRUM-428, 506, 509, 510, 495, 497)
  - `project_docs`: yes (ticket notes 411–510, Tech Specs, Postman docs, test results)
  - Note: `lessons.md` and `completed.md` are local files that git doesn't track (`git ls-files` returns nothing), so `git log` can't date them.
- Depth: Business 1 incentive config APIs (slab set, payout config) derived deeply; the rest is shallow

## Directory map
- `src/routes/incentives/`: one route file per resource. `index.js` applies `verifyClientAuth` to all of them and mounts each under `/incentives` (`index.js:14-21`). The app mounts this under `/api` (`src/routes/index.js:9`).
- `src/controllers/incentives/`: header and envelope validation, the service call, then `res.status(...).json({status:'success', data})`
- `src/services/incentives/`: business logic, Sequelize models, transactions
- `src/utils/incentives/`: pure validators/normalisers and `assert*` pre-checks per feature (`incentivePointSlabUtils.js`, `incentivePayoutConfigUtils.js`, `incentiveUtils.js`)
- `src/models/incentives/`: Sequelize models, registered in `index.js`
- `src/migrations/`, `src/seeders/`: sequelize-cli; raw SQL for CHECK, EXCLUDE and partial unique indexes
- `src/constants/appConstants.js`: shared constants (B1 block at `:323-330`)
- `src/workers/incentive/`: BullMQ workers per scheme (Business 2 calculation, including `ageing/`), `cron/`, `archival/`
- `src/routes/targets/`, `src/services/targets/`: the sales targets module (not incentives)
- Tests: `test/unit/{controller,services,utils,models,migrations,workers}`, `test/api/` (supertest + proxyquire), `test/bullmq/`
- `docs/openapi/`: only `healthCheckDocs.js` and `incentiveFeedsDocs.js`. No B1 config endpoint is documented there; B1 tickets ship Postman docs in `project_docs/`.

## Tooling
- Scripts: test `npm test` (`mocha --recursive test`), unit `npm run test:unit`, api `npm run test:api`, coverage `npm run coverage:check` (nyc 80/70/80/80), lint `npm run lint` (`package.json:44-53`)
- Test framework: Mocha + Chai + Sinon + proxyquire (`.noCallThru()`), supertest for `test/api`. Helpers are in `test/helpers/`.
- Hooks: `.husky/pre-commit` and `.husky/pre-push` both run `npm run coverage:check`

## Patterns (conventions)
| Layer | Pattern | Examples (≥3) | Source | Confidence |
|---|---|---|---|---|
| Route | `router.<verb>('/v1/<resource>', controllerFn)`. No per-route middleware; client auth is applied once in `routes/incentives/index.js`. | `incentivePayoutConfigRoutes.js:13-21`, `incentivePointsRoutes.js:14-31`, `routes/incentives/index.js:14` | derived | high |
| Controller (mutation) headers | X-Partner-Id, X-User-Id and X-User-Name are all required. A missing header returns `400 MISSING_HEADERS` with `details.missing: [...]`. Header values are not UUID-checked. | `incentivePayoutConfigController.js:95-115` (POST), `:226-…` (PATCH, `:241`), `:352-…` (status, `:367`); `incentivePointsController.js:193-213` | derived | high |
| Controller (GET) headers | X-Partner-Id only, otherwise `400 PARTNER_ID_MISSING` "Missing X-Partner-Id header" | `incentivePayoutConfigController.js:10-24`, `:188-202`; `incentivePointsController.js:10-22`, `:137-149` | derived | high |
| Controller envelope | Both periods pass `parseYearMonth` → order check `parseFirstOfMonth(to) < parseFirstOfMonth(from)` → top-level array non-empty. Each step is fail-fast with a field-specific message. | `incentivePayoutConfigController.js:136-170`; `incentivePointsController.js:229-265`; PATCH `incentivePayoutConfigController.js:270-330` | derived | high |
| Error envelope | `createError({error_code, message, details?}, status)` → `errorHandler` returns `{status:'error', error_code, message, details, replacements, pg_error}` | `src/utils/createError.js:37-43`, `src/middlewares/errorHandler.js:11-21` | derived | high |
| Validation | Hand-written and fail-fast (the first error is thrown). Strict JS types (`typeof === 'number'`, `Number.isInteger`, `includes` on allowed lists, so a missing value counts as invalid). Within a level, validity checks run before duplicate checks; set-level checks run after the loop. Unknown keys are ignored (only known keys are destructured). | `incentivePayoutConfigUtils.js:31-120`; `incentivePointSlabUtils.js:103-269`; `incentivePayoutConfigController.js:117-122`, `incentivePointsController.js:229` | derived | high |
| Field error codes (B1) | **Siblings disagree.** Payout uses `VALIDATION_ERROR` for period, level and rows. Slab uses `INVALID_PERIOD`, `INVALID_SALESPERSON_TYPE`, `INVALID_LEVEL`, `INVALID_SLAB`/`INVALID_OPERATOR`/`INVALID_POINTS`, and `VALIDATION_ERROR` for channel and duplicate group. | `incentivePayoutConfigController.js:136-170`, `incentivePayoutConfigUtils.js:31-120`; `incentivePointsController.js:231-253`, `incentivePointSlabUtils.js:111-266` | derived | n/a (disagreement) |
| Service create order | Normalise rows → `assertNoBusinessOneRunInProgress` → `assertNoOverlapping…` → `sequelize.transaction()` (header `create` + children `bulkCreate`) → commit. The catch maps `23P01` → `409 CONFIG_OVERLAP`; anything else → `500 INTERNAL_ERROR` with pg details. | `incentivePayoutConfigService.js:102-199`; `incentivePointsService.js:243-364`; `incentivePayoutConfigService.js:252-420` (PATCH) | derived | high |
| Overlap | App pre-check via `findOne` on active configs with `valid_from <= parsedTo AND valid_to >= parsedFrom`, plus a DB `EXCLUDE USING gist` partial on `status='active'` for races | `incentivePayoutConfigUtils.js:8-29`; `incentivePointSlabUtils.js:37-57`; migration `20260917053717…:99-107` | derived | high |
| Run-in-progress | `assertNoBusinessOneRunInProgress({partnerId, validFrom, validTo})` (YYYY-MM strings) on `incentive_run_log` with business_code BUSINESS_1 and status pending/processing, for every month in the range. No lock; it runs before the transaction. | `incentivePointSlabUtils.js:14-35`; called at `incentivePayoutConfigService.js:117`, `:322`, `:439`; `incentivePointsService.js:264`, `:464`, `:642` | derived | high |
| Audit | Header: `created_by`, `created_by_name`, `updated_by`, `updated_by_name` from the headers. Child rows: `created_by`/`updated_by` = userId, where the table has those columns. | `incentivePayoutConfigService.js:124-142`, `incentivePayoutConfigUtils.js:159-177`; `incentivePointsService.js:272-286` | derived | high |
| Response (create) | `201 {status:'success', data}`. `data` echoes the id, `valid_from`/`valid_to` as `YYYY-MM-DD` (`toISOString().slice(0,10)`), `status` and the child tree. The slab tree is in request order; payout rows are sorted by key. NUMERIC values go through `Number()`. | `incentivePayoutConfigService.js:173-184`; `incentivePointsService.js:338-346`, `incentivePointSlabUtils.js:271-289`; `incentivePayoutConfigUtils.js:106, :151` | derived | high |
| Model | `sequelize.define` with `underscored`, `timestamps`, `created_at`/`updated_at`, and `isIn` validators that mirror the DB CHECKs. Registered in `models/incentives/index.js`. | `IncentiveScorePayoutConfig.js`, `IncentiveScorePayout.js`, `IncentiveRunLog.js` | derived | high |
| Migration | `createTable`, then `setTableOwner`, then raw SQL for CHECKs, partial unique indexes and EXCLUDE. `CREATE EXTENSION IF NOT EXISTS btree_gist`. Schema and seed land in separate commits before the API tickets (`1064c65`, `f56ce53`). | `20260917053717-create-incentive-score-payout-configs.js`, `20260917053722-create-incentive-score-payouts.js`, `20260831063352-alter-incentive-run-log-add-b1-run-state.js` | derived | high |
| Tests | Per feature: `test/unit/controller/incentives/<x>Controller.spec.js`, `test/unit/services/incentives/<x>Service.spec.js`, `test/unit/utils/<x>Utils.spec.js`, `test/api/<x>.api.spec.js`. proxyquire `.noCallThru()` stubs the models. | `incentivePayoutConfigService.spec.js`, `test/api/incentivePayoutConfig.api.spec.js`, `test/unit/utils/incentivePointSlabUtils.spec.js` | derived | high |

## Anti-patterns (don't copy)
| What | Where | Evidence | Rule |
|---|---|---|---|
| Hardcoded literal when a DB or constant source exists | B2 activation call worker | `lessons.md` 2026-07-16 | reuse `appConstants.js` or fetched values |
| Overriding DB-configured values in code | `activationCallCalculator.js` (removed) | `lessons.md` 2026-07-16 | trust the stored config |
| "Improved" behaviour beyond the B1 sibling (extra locks, past-period guards) | SCRUM-497 planning | `lessons.md` 2026-09-27 | default = closest B1 sibling; label deviations |
| Running only `test:unit` | worker-count asserts duplicated in `test/bullmq` | `lessons.md` 2026-07-21 | run the full `npm test` |
| Trusting a create-migration as the live schema | `activation_activity.customer_id` | `lessons.md` 2026-09-22 | verify `\d table` before writing seed SQL |

## Gotchas
- `verifyClientAuth` returns `401 MISSING_CLIENT_CREDENTIALS` / `UNKNOWN_CLIENT` / `INVALID_CLIENT_AUTH`, never `SIGNATURE_INVALID` [code: src/middlewares/verifyClientAuth.js:8-42]
- Unexpected errors are coded `INTERNAL_ERROR` (not `INTERNAL_SERVER_ERROR`), with pg details in `details` [code: incentivePayoutConfigService.js:159-170]
- `parseYearMonth` trims its input, but `parseFirstOfMonth`/`parseLastOfMonth` do not [code: src/utils/dateFunctions.js:145-153, :273-281]
- `classifyConfigPeriod` and `isBusiness1ConfigPast` use UTC "now". Tests pin the time with sinon fake timers (completed.md SCRUM-497). [code: incentivePointSlabUtils.js:333-347; incentiveUtils.js:171-175]
- `VALID_BUSINESS1_SALESPERSON_TYPES` = `['NON_TRADER','TRADER']` (it includes TRADER). There is no NON_TRADER-only constant. [code: appConstants.js:328]
- No pg NUMERIC type parser is configured, so DECIMAL columns come back as strings. Always echo them through `Number()`.
- The shared run-check helper hardcodes `CONFIG_CHANGE_RUN_IN_PROGRESS` and has 6 call sites. Changing it affects slab and payout create, update and status.

## What has been built (by module)
### Business 1 config APIs
- Incentive point slab set: GET list/detail, POST, PATCH, PATCH status (`routes/incentives/incentivePointsRoutes.js`, `controllers/incentives/incentivePointsController.js`, `services/incentives/incentivePointsService.js`, `utils/incentives/incentivePointSlabUtils.js`). Landed in `6ed2e12` (481), `0c363d9` (483 POST, 2026-09-11) and `3bb33ce` (485 status).
- Payout config: GET list (`d5e7f69`), POST (`b584d94`, 496, 2026-09-22), GET detail (`432c873`, 495), PATCH (`33b9cff`, 497, merged `042f873`), PATCH status (`c046770`, 498, merged `d3ee24f` 2026-09-28)
- Schema and migrations were landed separately from the API tickets: `1064c65` 2026-09-01 (B1 tables + seeders), `f56ce53` 2026-09-17 (payout tables)
- Seeded B1 metric `NT_AR_AGEING_DEDUCTION` (component DEDUCTION, NON_TRADER, levels 1–3, requires_channel) [code: src/seeders/20260831063401-seed-incentive-point-metrics.js:49-58]. Slab configs are refused for DEDUCTION metrics [code: incentivePointSlabUtils.js:68-76].
- No `ar_ageing_*` table, model, migration, seeder or route exists, and no channel list or channel source exists (SCRUM-519 scout, 2026-10-01, on `d3ee24f`). The slab seeder uses channel `GT`.
### Business 2 incentives
- Schemes, configs and range slabs (`incentiveSchemesService.js`), feeds (including the ageing feed `POST /incentives/v1/feeds/ageing`), BullMQ workers per scheme, crons, and archival (SCRUM-428/506/509/510)

## Reusable inventory
| Piece | Path | What it does | Used by (count / examples) | Source |
|---|---|---|---|---|
| `assertNoBusinessOneRunInProgress` | `src/utils/incentives/incentivePointSlabUtils.js:14-35` | 409 if a B1 run is pending or processing for the partner in any month of the YYYY-MM range | 6 call sites (payout create/update/status, slab create/update/status) | derived |
| `assertNoOverlappingActivePayoutConfig` / `assertNoOverlappingActiveSlabConfig` | `incentivePayoutConfigUtils.js:8-29`, `incentivePointSlabUtils.js:37-57` | active-period overlap pre-check, with an optional `excludeConfigId` | create, update, status | derived |
| `classifyConfigPeriod` / `isBusiness1ConfigPast` | `incentivePointSlabUtils.js:333-347`; `incentiveUtils.js:171-175` | FUTURE / ACTIVE / PAST by UTC month | PATCH endpoints | derived |
| `buildPayoutRowsToInsert`, `buildPayoutRowsFromRecords` | `incentivePayoutConfigUtils.js:139-177` | payout rows for insert and for echo | completed.md SCRUM-495/497 | completed.md |
| `buildSlabGroupTree`, `groupSlabRows` | `incentivePointSlabUtils.js:271-319` | echo grouped child rows in request order, or from DB rows | slab POST/GET/PATCH | derived |
| `parseYearMonth`, `parseFirstOfMonth`, `parseLastOfMonth`, `monthYearRange`, `dateOnly`, `yyyyMmFromDate` | `src/utils/dateFunctions.js:47-50, 145-173, 273-288` | YYYY-MM parsing and month boundaries (UTC) | all B1 config APIs | derived |
| `getPartnerIdFromHeaders`, `getUserIdFromHeaders`, `getUserNameFromHeaders` | `src/utils/headerUtils.js:1-11` | read the S2S identity headers | all incentive controllers | derived |
| `isValidUuid` | `src/utils/pgDbUtils.js` | UUID regex | controllers (path ids); `targetTypeValuesController.js:159` (partner id) | derived |
| `createError` | `src/utils/createError.js:13-53` | standard error object | everywhere | derived |
| `resolveActiveBusinessCode` | `src/utils/incentives/incentiveUtils.js:16-32` | partner → active business_code; 404 `PARTNER_BUSINESS_MAPPING_NOT_FOUND` | only `incentiveSchemesService.js:133` (B2) | derived |
| B1 constants | `src/constants/appConstants.js:86-90, 106, 323-330` | `CONFIG_EDIT_CASES`, `INCENTIVE_BUSINESS_CODES`, `VALID_BUSINESS1_LEVELS`, `VALID_BUSINESS1_SALESPERSON_TYPES`, `VALID_BUSINESS1_SLAB_OPERATORS`, statuses | B1 utils and services | derived |
| `setTableOwner` | `src/utils/tableOwnership.js` | fixes the migration table owner | every recent create migration | derived |
| `buildDeadLetterQueueName`, `streamUploadToS3`, etc. | see completed.md | worker and archival helpers | not relevant to config APIs | completed.md |

## Legacy areas
- `src/workers/incentive/ageing/`, `AgeingActivity`, `AgeingIncentiveSpv`, `AgeingIncentiveReference` and the ageing feed are **Business 2** AR ageing calculation and feed code. Never use them as a sibling or helper source for Business 1 AR ageing work (business boundary, `lessons.md` 2026-09-27).
- The `details.missing_or_invalid` style in `incentiveSchemesController.js` belongs to Business 2 (and to the targets module). B1 controllers don't use it.

## Change log
| Date | Commit | By (ticket) | What was added or refreshed |
|---|---|---|---|
| 2026-10-01 | `33b9cff` | SCRUM-519 code-scout | Profile created; B1 config APIs derived deeply (on branch `scrum-497`) |
| 2026-10-01 | `d3ee24f` | SCRUM-519 code-scout (restart) | Refreshed on `develop`. Added payout PATCH/status (497, 498 merged). Corrected the line ranges. Run-check call sites 5 → 6. Added the field-code disagreement row, the validity-before-duplicate rule, the NUMERIC `Number()` gotcha, and the schema-before-API commit pattern. Noted that lessons/completed are not tracked by git. |
