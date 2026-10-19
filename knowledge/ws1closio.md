# Repo profile: ws1closio

- Path: `../backend/nodejs-ws1closio` · Development branch: `develop`
- derived_at_commit: `32b6b14` (`develop`, merge of SCRUM-498) · derived_at: 2026-10-01 · by: SCRUM-519 code-scout (Claude Code). Uncommitted local-run edits in `src/configs/redisConfig.js` and `src/utils/redisClient.js` are not part of develop and are not profiled.
- Documented sources:
  - conventions: `.claude/CLAUDE.md`, `.claude/SKILLS.md`, `.claude/commands/new-proxy-endpoint.md`
  - `lessons.md`: none
  - `completed.md`: none (ws1 work is logged in ws2targetsales `completed.md`)
  - `project_docs`: none relevant (folder present)
- Depth: `incentives` proxy routes derived deeply; the rest is shallow

## Directory map
- `src/routes/incentives/`: one route file per resource; `index.js` mounts them all under `/incentives` (`index.js:15-21`)
- `src/controllers/v1/incentives/`: proxy controllers to ws2targetsales
- `src/schemas/v1/incentives/`: Ajv schema factories (request, queryParameter, and responses per status); `shared/payoutConfigSchemas.js`
- `src/middlewares/`: `validateSchema.js`, `isAuthenticated.js`, `errorHandler.js`, …
- `src/utils/`: `axiosInstances.js`, `helperFunctions.js` (`buildWs2Headers`, `buildUpstreamFailureResponse`, `isValidUUID`), `createError.js`, `replaceMessagePlaceholders.js`
- `src/configs/axiosConfig.js`: base URLs and timeouts
- `locales/{en,id}/target-sales/messages.json`: message keys for the `target-sales/messages` namespace

## Tooling
- Scripts: `npm test` exits 1 (no test suite); lint `npm run lint`; `check:circular`
- Verification used by previous tickets: an Ajv strict compile of the schemas after `i18nextInitialized` (ws2targetsales `lessons.md` 2026-09-27), and a `require('./src/routes/incentives')` load check

## Patterns (conventions)
| Layer | Pattern | Examples (≥3) | Source | Confidence |
|---|---|---|---|---|
| Route | `router.<verb>(path, validateSchema('schemas/v1/incentives/<x>.js'), isAuthenticated, asyncHandler(ctrl.fn))`. Schema validation runs **before** the session check. | `incentivePayoutConfigRoutes.js:13-50` (5 routes); `incentivePointsRoutes.js:29-34` and the rest of that file | derived (+ CLAUDE.md asyncHandler rule) | high |
| Controller (B1 mutation) | Read `req.session.closioV1Data.partnerId`, `req.session.cUserUuid` and `req.session.cUserName`. If any is missing → `401 INVALID_AUTH_CONTEXT`. Send `req.body` unchanged with `buildWs2Headers({req, partnerId, userId, userName})`, then `res.validateResponse(upstream.status, upstream.data, namespace)`. | `incentivePayoutConfigController.js:41-82` (POST), `:122-…` (PATCH), `:181-…` (status); `incentivePointsController.js:179-241` (slab POST), `:116-…` (slab status), `:242-…` (slab PATCH) | derived | high |
| Controller catch | `err.response.status` → `next(createError(err, undefined, ns))`. A network or axios error → `buildUpstreamFailureResponse` (502 `UPSTREAM_REQUEST_FAILED`). Anything else → `createError(err, err.status \|\| 500)`. | `incentivePayoutConfigController.js:28-38`, `:71-81`, and the PATCH/status catches | derived | high |
| Request schema (B1) | Mostly type-only, `additionalProperties: true`, no pattern or enum on business fields. The slab groups use `required: ['slabs']`. | `createPayoutConfig.js:12-38`; `createIncentivePointSlabConfig.js:11-60`; commit `d23005b` (2026-09-08) removed the YYYY-MM pattern and enum from `getIncentivePointSlabConfigs.js` | derived | high |
| Response schema | One per status (`201`/`400`/`401`/`409`/`500`). The 201 schema requires `status`, `data` and the key fields (e.g. `config_id`). Only 200/201/202/400/500 are compiled. | `createPayoutConfig.js:49-…`; `createIncentivePointSlabConfig.js:88-93`; `validateSchema.js:73-83` | derived | high |
| S2S credentials | Added by the axios interceptor on `apiWs2TargetSalesIncentive` (`X-Client-Id`, `X-Client-Secret`). Controllers never set them. | `src/utils/axiosInstances.js:150-154` | derived | high |
| Locales | Every new ws2 message gets an en key and an id key in `target-sales/messages` | `locales/{en,id}/target-sales/messages.json:109, :155, :178`; completed.md SCRUM-497 ("5 new keys each") | derived | high |

## Anti-patterns (don't copy)
| What | Where | Evidence | Rule |
|---|---|---|---|
| Forwarding `req.headers` to ws2 | unlock-achievements proxy (fixed) | ws2targetsales `lessons.md` 2026-07-27 | use `buildWs2Headers` |
| Writing ws1-level expectations of `404` | Postman docs | ws2targetsales `lessons.md` 2026-09-24 | expect 597 instead of 404 |
| `.claude/CLAUDE.md` says the partner is at `req.session.closioData.partnerId` | doc vs code | the incentive controllers read `req.session.closioV1Data.partnerId` (`incentivePayoutConfigController.js:43`) | follow the incentive siblings' session paths |

## Gotchas
- `errorHandler` rewrites every 404 to **597** [code: src/middlewares/errorHandler.js:41-49]. Statuses other than 400/401/403/404/409/415/422/429/502 become **500** with the error's own `error_code` [code: errorHandler.js:91-97].
- Upstream axios errors are rebuilt. `details` = the upstream details flattened, plus `upstream_error_code`, `upstream_message`, `upstream_status`, `upstream_method`, `upstream_url` and `upstream_network_code`. The message is re-translated, and `replacements`/`pg_error` are dropped. [code: src/utils/createError.js:18-49] The client never receives the ws2 body byte-for-byte.
- An Ajv request failure → `createError(<string>, 400)` → `error_code: 'GENERAL_ERROR'`. The message is `<path> <ajv msg> | value=… | schemaPath=…` (first error only) and there are no `details`. [code: src/middlewares/validateSchema.js:99-121, :350-352; createError.js:64-70]
- A response-validator mismatch → `next(createError(<string>, status))`. For a 201 that becomes HTTP 500 `GENERAL_ERROR` via the errorHandler fall-through. [code: validateSchema.js:395-397; errorHandler.js:91-97]
- No session or an expired one → `401 SESSION_EXPIRED` (web); a bearer token → the verifyToken error (mobile). There is no `TOKEN_INVALID` code in `src/`. [code: src/middlewares/isAuthenticated.js:112-168]
- The WS2 target-sales timeout is 60 s [code: src/configs/axiosConfig.js:88-91]
- ws2 messages are translated via locale keys in `target-sales/messages`. A key with no translation is passed straight to `i18next.t`. [code: validateSchema.js:419-431; src/utils/replaceMessagePlaceholders.js]

## What has been built (by module)
### incentives
- Schemes, configs and range slabs (B2), feeds, manual trigger, unlock achievements, salesperson product map
- B1 slab set: GET list/detail, POST (`f6dc118` 2026-09-11), PATCH, PATCH status (`28c6d61`)
- B1 payout config: GET list (`13a7b3e`), POST (`d60959f` 2026-09-23), GET detail (`d7b7df1`), PATCH (`1d4ee8f`, merged `d72b344`), PATCH status (`ced0122`, merged `32b6b14` 2026-09-28; schema `updatePayoutConfigStatus.js`)
- No ageing-deduction route, schema or locale key exists (SCRUM-519 scout, 2026-10-01)

## Reusable inventory
| Piece | Path | What it does | Used by (count / examples) | Source |
|---|---|---|---|---|
| `buildWs2Headers` | `src/utils/helperFunctions.js:22-30` | builds an explicit header object (accept-language, X-Partner-Id, X-User-Id, X-User-Name, Content-Type) | all payout and slab proxies | ws2targetsales completed.md (497) + derived |
| `buildUpstreamFailureResponse` | `src/utils/helperFunctions.js:10-20` | 502 `UPSTREAM_REQUEST_FAILED` for network errors and timeouts | payout and slab proxies | derived |
| `isValidUUID` | `src/utils/helperFunctions.js:5-8` | UUID v1-5 regex | path-id checks | derived |
| `apiWs2TargetSalesIncentive` | `src/utils/axiosInstances.js:67-73, 150-154` | ws2targetsales client with S2S credentials | all incentive proxies | derived |
| `validateSchema` / `res.validateResponse` | `src/middlewares/validateSchema.js` | request, query and response validation, plus message translation | every route | documented (CLAUDE.md) |
| `shared/payoutConfigSchemas.js` | `src/schemas/v1/incentives/shared/payoutConfigSchemas.js` | payout row, level and warnings sub-schemas | 3+ payout schemas | ws2targetsales completed.md (497) |

## Legacy areas
- `incentiveSchemesController.js` and the B2 schemas are Business 2. They are not siblings for B1 work.

## Change log
| Date | Commit | By (ticket) | What was added or refreshed |
|---|---|---|---|
| 2026-10-01 | `1d4ee8f` | SCRUM-519 code-scout | Profile created; incentives proxies derived deeply (on branch `scrum-497`) |
| 2026-10-01 | `32b6b14` | SCRUM-519 code-scout (restart) | Refreshed on `develop`. Added payout PATCH status (498). Corrected the slab POST proxy range (`:179-241`). Added the Ajv message format, the locale pattern row, and the "no TOKEN_INVALID" note. |
