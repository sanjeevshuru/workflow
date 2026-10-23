# Repo profile: ws1closio

- Path: `../backend/nodejs-ws1closio` · Development branch: `develop`
- derived_at_commit: `944f9e9` (`develop`, merge of `SCRUM-540/temp`) · derived_at: 2026-10-23 · by: SCRUM-530 code-scout (Claude Code). The local edits in `src/configs/redisConfig.js` and `src/utils/redisClient.js` are stashed (`ai-flow SCRUM-530: auto-stash before sync from develop`) and are not profiled.
- Documented sources:
  - conventions: `.claude/CLAUDE.md`, `.claude/SKILLS.md`, `.claude/commands/new-proxy-endpoint.md`
  - `lessons.md`: none
  - `completed.md`: none (ws1 work is logged in ws2targetsales `completed.md`)
  - `project_docs`: none relevant (folder present)
- Depth: `incentives` proxy routes, `validateSchema`, `isAuthenticated`, `errorHandler`, `createError`, axios instances derived deeply; the rest is shallow

## Directory map
- `src/routes/incentives/`: one route file per resource; `index.js` mounts them all under `/incentives` (`index.js:17-25`); `src/routes/index.js:18, :51` mounts that under `/api`
- `src/controllers/v1/incentives/`: proxy controllers (ws2targetsales via `apiWs2TargetSalesIncentive`; salesperson product map via `apiWs2Closio`)
- `src/schemas/v1/incentives/`: Ajv schema factories (request, queryParameter, and responses per status); `shared/payoutConfigSchemas.js`, `shared/ageingDeductionConfigSchemas.js`
- `src/middlewares/`: `validateSchema.js`, `isAuthenticated.js`, `isAuthorized.js`, `validatePartnerContext.js`, `errorHandler.js`, …
- `src/utils/`: `axiosInstances.js`, `helperFunctions.js` (`buildWs2Headers`, `buildUpstreamFailureResponse`, `isValidUUID`), `createError.js`, `replaceMessagePlaceholders.js`, `dateFunctions.js`
- `src/configs/axiosConfig.js`: base URLs, timeouts, S2S client credentials (`ws1ClosioAuth`, `pricingEngineAuth`, `partnerToolsAuth`)
- `locales/{en,id}/target-sales/messages.json`: message keys for the `target-sales/messages` namespace
- `docs/openapi/`: swagger JSDoc. B1 incentive proxies have **no** docs (only the B2 `closio-v2/incentiveSchemasDocs.js`)

## Tooling
- Scripts: `npm test` exits 1 (no test suite; `package.json:23`); lint `npm run lint`; `check:circular`
- Verification used by previous tickets: an Ajv strict compile of the schemas after `i18nextInitialized` (ws2targetsales `lessons.md` 2026-09-27), a `require('./src/routes/incentives')` load check, and Postman (runs/SCRUM-519/backend-plan.md:55, :408)

## Patterns (conventions)
| Layer | Pattern | Examples (≥3) | Source | Confidence |
|---|---|---|---|---|
| Route | `router.<verb>(path, validateSchema('schemas/v1/incentives/<x>.js'), isAuthenticated, asyncHandler(ctrl.fn))`. Schema validation runs **before** the session check. No `isAuthorized` on any incentive route. | `incentivePayoutConfigRoutes.js:13-50`; `incentiveSalespersonProductMapRoutes.js:13-18`; `incentiveTraderStockDaysMultiplierConfigRoutes.js:13-18`; `incentiveAgeingDeductionConfigRoutes.js` (6 routes). `isAuthorized` appears in 28 route files elsewhere (e.g. `target-sales/masterCalendarRoutes.js:16`), 0 in `src/routes/incentives/` | derived (+ CLAUDE.md asyncHandler rule) | high |
| Controller (B1 GET/mutation) | Read `req.session.closioV1Data.partnerId` (mutations also `cUserUuid`, `cUserName`). Missing → `401 INVALID_AUTH_CONTEXT` "User session missing partner_id" (outlier: trader-stock-days GET uses `400 PARTNER_ID_MISSING`). Call ws2, then `res.validateResponse(upstream.status, upstream.data, namespace)`. | `incentivePayoutConfigController.js:41-82`; `incentivePointsController.js:179-241`; `incentiveSalespersonProductMapController.js:11-47`; 18 `INVALID_AUTH_CONTEXT` uses in `src/controllers/v1/incentives/` | derived | high |
| Controller catch | `err.response.status` → `next(createError(err, undefined, ns))`. A network or axios error → `buildUpstreamFailureResponse` (502 `UPSTREAM_REQUEST_FAILED`). Anything else → `createError(err, err.status \|\| 500)`. | `incentivePayoutConfigController.js:28-38`, `:71-81`; `incentiveSalespersonProductMapController.js:48-58`; `incentiveTraderStockDaysMultiplierConfigController.js:60-70` | derived | high |
| ws2closio proxy (S2S) | `apiWs2Closio.<verb>(path, { params, partnerId, headers: { 'X-Client-Id': ws1ClosioAuth.clientId, 'X-Client-Secret': ws1ClosioAuth.secretKey } })`. The interceptor adds `X-Partner-Id` / `X-User-Id` / `X-Trace-Id` from `config.partnerId` / `config.userId`. | `incentiveSalespersonProductMapController.js:38-45` (only incentive example) | derived | low (1 example; the ticket SCRUM-530 names it as the pattern) |
| Request schema, no query params | `queryParameter: { type:'object', properties:{}, additionalProperties:false, errorMessage:{ additionalProperties: replaceMessagePlaceholders('invalid schema', namespace) } }` | `getAgeingDeductionConfigOptions.js:14-21`; `getIncentivePointSlabConfigDetail.js:20-27`; `getPayoutConfigDetail.js:34-41` | derived | high |
| Request schema, query params | Typed props with per-keyword `errorMessage` via `replaceMessagePlaceholders` (`type` → "object must not be provided more than once"), `additionalProperties:false` → "invalid schema" | `getSalespersonProductMap.js:26-98`; `getPayoutConfigs.js:21-33`; `getAgeingDeductionConfigs.js:21-34` | derived | high |
| Request schema (B1 body) | Mostly type-only, `additionalProperties: true`, no pattern or enum on business fields. | `createPayoutConfig.js:12-38`; `createIncentivePointSlabConfig.js:11-60`; commit `d23005b` | derived | high |
| Response schema | One per status (`200`/`201`/`400`/`401`/`403`/`500`), all loose (`additionalProperties: true`). Success requires `status` (enum `success`) and `data` plus the key `data` fields. Only 200/201/202/400/500 are compiled. No `404` schema. | `getSalespersonProductMap.js:100-185`; `getPayoutConfigs.js`; `getAgeingDeductionConfigs.js`; `getTraderStockDaysMultiplierConfigs.js`; `validateSchema.js:73-83` | derived | high |
| S2S credentials (ws2targetsales) | Added by the axios interceptor on `apiWs2TargetSalesIncentive` (`X-Client-Id`, `X-Client-Secret`). Controllers never set them. | `src/utils/axiosInstances.js:160-164`; also `apiWs2TargetSalesWorker` `:166-170`, `apiWs2Notifications` `:172-176` | derived | high |
| Locales | Every new ws2 message gets an en key and an id key in `target-sales/messages` | `locales/{en,id}/target-sales/messages.json:88, :100, :215`; completed.md SCRUM-497 ("5 new keys each"). Gap: the salesperson-product-map sibling has no key for "Failed to reach WS2 Closio" | derived | high |
| Docs | B1 incentive proxies have no OpenAPI docs | grep `payout-configs\|salesperson-product-map\|ageing-deduction\|slab-configs\|trader-stock` in `docs/` → none | derived | high |

## Anti-patterns (don't copy)
| What | Where | Evidence | Rule |
|---|---|---|---|
| Forwarding `req.headers` to ws2 | unlock-achievements proxy (fixed) | ws2targetsales `lessons.md` 2026-07-27 | use `buildWs2Headers` or an explicit object |
| Writing ws1-level expectations of `404` | Postman docs | ws2targetsales `lessons.md` 2026-09-24 | expect 597 instead of 404 |
| `.claude/CLAUDE.md` says the partner is at `req.session.closioData.partnerId` | doc vs code | the incentive controllers read `req.session.closioV1Data.partnerId` (`incentivePayoutConfigController.js:43`, `incentiveSalespersonProductMapController.js:13`) | follow the incentive siblings' session paths |
| `temp:` commits merged to `develop` (hard-coded `partner_id = null`, `localhost:9999` URLs), later reverted | `c6a91ee`, `0d81089`, `516f5a1`, `be2b1c7`, `e97fa25`, `61dd80f` (ageing / trader-stock-days controllers) | net diff of the trader controller since `59256c0` is empty; grep `localhost:9999\|// TEMP\|partner_id = null` in `src/` → none at `944f9e9` | never copy code from a `temp:` commit; re-check HEAD |
| Raw forward of the ws2 error body (`res.status(...).json(err.response.data)`) | `closio-v2/sfa/translationsController.js:34-38` | outlier vs the incentive catch pattern | use the incentive catch pattern |
| Hard-coded fallback secret for `ws1ClosioAuth.secretKey` | `src/configs/axiosConfig.js:142-145` | literal default in code | never copy; config must come from env |

## Gotchas
- `errorHandler` rewrites every 404 to **597** [code: src/middlewares/errorHandler.js:41-49]. Statuses other than 400/401/403/404/409/415/422/429/502 become **500** with the error's own `error_code` and no `details` [code: errorHandler.js:91-97].
- Upstream axios errors are rebuilt. `details` = the upstream details flattened, plus `upstream_error_code`, `upstream_message`, `upstream_status`, `upstream_method`, `upstream_url` and `upstream_network_code`. The message is re-translated, and `replacements`/`pg_error` are dropped. [code: src/utils/createError.js:18-49] The client never receives the ws2 body byte-for-byte.
- An Ajv request/query failure → `createError(<string>, 400)` → `error_code: 'GENERAL_ERROR'`. The message is `<path> <ajv msg> | value=… | schemaPath=…` (first error only) and there are no `details`. [code: src/middlewares/validateSchema.js:99-121, :350-357; createError.js:64-70]
- A response-validator mismatch → `next(createError(<string>, status))`. For a 200 or 201 that becomes HTTP 500 `GENERAL_ERROR` via the errorHandler fall-through. [code: validateSchema.js:395-397; errorHandler.js:91-97]
- `validateSchema` requires the `X-Secure-Transmission-Type` header (`x`/`0`/`1`/`2`) on every request, and with `1`/`2` encrypts the response. [code: validateSchema.js:189-230, :399-419]
- `validateSchema` verifies a Bearer token itself **before** the query is validated and before `isAuthenticated` runs [code: validateSchema.js:262-282, :502-586].
- Web: no or expired session → `401 SESSION_EXPIRED` [code: isAuthenticated.js:127-168]. Mobile Bearer: unknown token → `401 INVALID_TOKEN` "invalid token"; token ≠ session token or past `dTokenExp` → `401 INVALID_TOKEN` "invalid or expired token" [code: isAuthenticated.js:21-24, :78-81]. There is no `TOKEN_INVALID` code in `src/`.
- `closioV1Data` (with `partnerId`) is set in the session at web and mobile login (`authController.js:284-353`, `:630-697`, `:997-1070`) and restored for a mobile token from Redis `v1-token:mobile:<cuser_id>` [code: isAuthenticated.js:36-66].
- The WS2 timeouts are 60 s (`axiosConfig.js:66` ws2Closio, `:88-91` target-sales).
- ws2 messages are translated via locale keys. A key with no translation is passed straight to `i18next.t` and comes back as the key; `fallbackLng` is `id` [code: validateSchema.js:419-433; src/utils/replaceMessagePlaceholders.js; src/configs/localeConfig.js:4].
- `buildUpstreamFailureResponse` writes the 502 directly (`res.status(502).json`), bypassing `validateResponse` and encryption; `details` holds the raw axios `code` and `message` [code: helperFunctions.js:10-20].

## What has been built (by module)
### incentives
- Schemes, configs and range slabs (B2), feeds, manual trigger, unlock achievements
- Salesperson product map GET → ws2closio (`897c792` 2026-08-11, `a9ead3f`, `dab7033` 2026-08-25)
- B1 slab set: GET list/detail, POST (`f6dc118` 2026-09-11), PATCH, PATCH status (`28c6d61`)
- B1 payout config: GET list (`13a7b3e`), POST (`d60959f`), GET detail (`d7b7df1`), PATCH (`1d4ee8f`), PATCH status (`ced0122`)
- B1 ageing deduction config: POST (`495e15a` SCRUM-519), PATCH status (`8079113` SCRUM-520), PATCH (`e2d65cc` SCRUM-521), GET list/detail/options; locale keys (`4436fe1` / `fd18df9` SCRUM-566)
- B1 trader stock days multiplier configs GET (`59256c0` SCRUM-540)
- No customer-handled route, schema or locale key exists (SCRUM-530 scout, 2026-10-23)
### other since `32b6b14`
- closio-v2 SFA translations GET → ws2closio (`translationsController.js`, `validatePartnerContext`); `apiClosioV1Partner` instance and `partnerToolsAuth`

## Reusable inventory
| Piece | Path | What it does | Used by (count / examples) | Source |
|---|---|---|---|---|
| `buildWs2Headers` | `src/utils/helperFunctions.js:22-30` | builds an explicit header object (accept-language, X-Partner-Id, X-User-Id, X-User-Name, Content-Type) | all payout, slab, ageing, trader proxies | ws2targetsales completed.md (497) + derived |
| `buildUpstreamFailureResponse` | `src/utils/helperFunctions.js:10-20` | 502 `UPSTREAM_REQUEST_FAILED` for network errors and timeouts | all B1 incentive proxies | derived |
| `isValidUUID` | `src/utils/helperFunctions.js:5-8` | UUID v1-5 regex | path-id checks, `validatePartnerContext` | derived |
| `apiWs2TargetSalesIncentive` | `src/utils/axiosInstances.js:76-82, 160-164` | ws2targetsales client with S2S credentials | all ws2targetsales incentive proxies | derived |
| `apiWs2Closio` | `src/utils/axiosInstances.js:52-58, 193-209` | ws2closio client; interceptor sets X-Partner-Id / X-User-Id from `config.partnerId` / `config.userId` and X-Trace-Id. No S2S credentials. | 7 controllers (e.g. salesperson product map, translations, external orders) | derived |
| `ws1ClosioAuth` | `src/configs/axiosConfig.js:142-145` | `WS1_AUTH_CLIENT_ID` / `WS1_AUTH_SECRET_KEY` | ws2targetsales/notifications interceptors; salesperson product map controller | derived |
| `validateSchema` / `res.validateResponse` | `src/middlewares/validateSchema.js` | request, query and response validation, plus message translation | every route | documented (CLAUDE.md) |
| `validatePartnerContext` | `src/middlewares/validatePartnerContext.js:16-40` | 403 if session partner missing / not UUID; sets `req.partnerId`, `req.userId` | closio-v2 translations only (not used by incentive routes) | derived |
| `shared/payoutConfigSchemas.js`, `shared/ageingDeductionConfigSchemas.js` | `src/schemas/v1/incentives/shared/` | sub-schemas | payout and ageing schemas | ws2targetsales completed.md (497) + derived |

## Legacy areas
- `incentiveSchemesController.js` and the B2 schemas are Business 2. They are not siblings for B1 work.

## Change log
| Date | Commit | By (ticket) | What was added or refreshed |
|---|---|---|---|
| 2026-10-01 | `1d4ee8f` | SCRUM-519 code-scout | Profile created; incentives proxies derived deeply (on branch `scrum-497`) |
| 2026-10-01 | `32b6b14` | SCRUM-519 code-scout (restart) | Refreshed on `develop`. Added payout PATCH status (498). Corrected the slab POST proxy range (`:179-241`). Added the Ajv message format, the locale pattern row, and the "no TOKEN_INVALID" note. |
| 2026-10-23 | `944f9e9` | SCRUM-530 code-scout | Refreshed from `32b6b14..944f9e9` (ageing deduction 519/520/521/566, trader stock days 540, SFA translations, `apiClosioV1Partner`). Added: `apiWs2Closio` S2S pattern (low confidence), empty-query schema pattern, response-schema/docs conventions, Bearer verification in `validateSchema`, `X-Secure-Transmission-Type`, session `closioV1Data` sources, `temp:` commits anti-pattern, translations-controller outlier, hard-coded fallback secret. |
