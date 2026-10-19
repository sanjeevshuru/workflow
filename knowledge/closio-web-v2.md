# Repo profile: closio-web-v2

- Path: `../web/closio-web-v2` · Development branch: `development`
- derived_at_commit: `49bd1d6b` · derived_at: 2026-10-04 · by: SCRUM-523 code-scout (Codex)
- Documented sources: conventions `.claude/CLAUDE.md`, `SECURITY.md`; lessons.md yes; completed.md yes; project_docs yes. No root AGENTS.md/SKILLS.md or .claude command recipes found by hidden/no-ignore search.
- Depth: incentive detail/config deeply; rest shallow directory/shared-import inventory. Unmerged SCRUM-522 examined only as dependency, not included in development feature inventory.

## Directory map
- `src/views/`: feature views, module routes, types, components, tests. Incentive has schema list/detail, B1 point create/edit, B2 threshold/range create/edit and payout list/create/detail.
- `src/components/`: common controls, state cards, table/cell renderers, icons and sidebar.
- `src/api/`: axios clients, endpoint modules, mocks, tests.
- `src/composables/`, `src/stores/`, `src/utils/`, `src/constants/`, `src/common-types/`: hooks, Pinia, formatting/permissions, shared constants/types.
- `src/router/`: route mounts and guards; `src/test/setup.js`: test setup; `project_docs/`: ticket notes and local tech specs.

## Tooling
- Vue 3/Vuetify 3/Vite/Pinia, TypeScript mixed with JS, AG Grid. `package.json:6-29`: test `npm run test:run`, coverage `npm run test:coverage`, build `npm run build`, dev `npm run dev`; no lint script.
- `vitest.config.js:12-41`: jsdom, globals, src/test/setup.js, V8 coverage, global branches/functions/lines/statements 70 each. `tsconfig.json`: @ maps src, noEmit, Bundler resolution. Hidden file search found no .husky hooks.
- No execution or baseline test counts established during scouting; completed.md historical failures are historical only.

## Patterns (conventions)
| Layer | Pattern | Examples (≥3 where derived) | Source | Confidence |
|---|---|---|---|---|
| UI load states | Shared LoadingSpinner and MessageCard, retry invokes load function | IncentiveSchemaDetail.vue:11-23; PayoutConfigDetail.vue:17-29; EditSlabConfig.vue:30-43 | derived, same B1 module | high |
| View implementation | script setup TS, Vue refs/computed, local request/form state | IncentiveSchemaDetail.vue:122-191; PayoutConfigDetail.vue:70-113; PayoutConfigCreate.vue:65-95 | derived | high |
| API | shared axios, positional id/signal, raw success data, ErrorResponse, protected 597 mock fallback | src/api/incentive.ts:776-860 (B1 point detail), :1147-1210 (payout status), :1274-1347 (payout detail) | derived + lessons.md 2026-09-02/03/08 | high |
| Routes | named lazy module routes under authenticated feature-gated parent | routes.ts:34-51 (B1/create/detail), :64-68 (B1 edit), :80-95 (payout) | derived within module, parent policies differ only permission metadata | high |
| Tests | Vitest + Vue Test Utils; views stub API/router/table, use raw fixtures | __tests__/IncentiveSchemaDetail.test.ts:1-90,440-583; PayoutConfigDetail.test.ts:1-75; IncentivePointGroupCard.test.ts:1-66 | derived | high |
| Read-only group | Expanded by default, button-header toggle, ordinal index+1, unsorted rows | components/IncentivePointGroupCard.vue:1-67 | documented completed.md 489 + direct closest sibling | high for this sibling; not a 3-example derived global convention |
| Navigation | Return to named list with schemaId query | IncentiveSchemaDetail.vue:528-529, IncentiveSchemaList.vue:475-491 | closest sibling; two-file evidence only | low as repo-wide rule; factual local behavior |

All bare paths above are src/views/incentive/ in closio-web-v2.

## Anti-patterns (don't copy)
| What | Where / evidence | Rule |
|---|---|---|
| Cross-business normalized objects | lessons.md 2026-09-02/03; completed.md 488 correction | Keep raw endpoint types throughout UI; no fake IncentiveConfig rows. |
| Blind mock fallback on 597 | lessons.md 2026-08-23/09-08; api/incentive.ts:80-81,1315-1330 | Preserve wrapped genuine errors; check details.upstream_error_code/upstream_status. |
| Old docs treated as current truth | completed.md 499 says detail not implemented; current routes.ts:91-95 and PayoutConfigDetail exist | Verify code/history; profile supplements stale completed log. |
| Date/number comments treated as contract | dateFormatter.ts:143-148 strips padding; stringFormatter.ts:13-19 comment says no decimals but implementation uses Intl defaults | AC1 padded date uses formatDate; four-decimal percentages need an explicit formatting decision. |
| Mock unknown-id success and identity mismatches | api/mocks/incentive.ts:1471-1503 fallback objects; lessons.md 2026-09-09 | Follow real id fields; payout mock :2091-2111 provides explicit not-found model. |
| Lost code after merge | lessons.md 2026-09-03 | Check affected behavior against both parents; workflow forbids agent resolving merge conflicts. |
| Fake browser login | lessons.md 2026-08-20 | User login only, no fabricated Pinia auth session. |

## Gotchas
- api/axios.js:6-15 actual timeout 30s, credentials included; SECURITY.md's 10s prose is stale. Central interceptor handles 401/UNAUTHORIZED (:35-55).
- ErrorResponse retains `details` but not HTTP status (`src/common-types/error.ts:9-14`); application code must inspect actual error codes, including known wrapper fields, for distinct states.
- Feature `incentiveManagement` maps VITE_ENABLE_MANAJEMEN_INSENTIF_UI (`src/composables/useFeatureFlags.ts:16`); feature guard sends /404; schema route permission guard is commented (`incentive/routes.ts:27`), don't silently activate it.
- Store config cache is B2 IncentiveConfig-shaped (`src/stores/incentive.ts:18-36`), not a place to normalize ageing or B1 point data.

## What has been built (by module)
### Incentive (derived refresh beyond completed.md)
- B1 point detail with channel/group cards: cee7f43d, 2026-09-09, SCRUM-489; current IncentiveSchemaDetail.vue:52-86,449-467.
- B1 point create/edit: 790f70a2 (490, 2026-09-16), e6b9da76 (491, 2026-09-21); routes.ts:41-45,64-68; ChannelBox/SalesmanGroupBox/SlabConfigForm.
- Payout list/status: 845b5f9b / 2d91017e (2026-09-16/17), PayoutConfigList.vue, routes.ts:73-95.
- Payout detail/status badge: 7871d583 / 1847c444 (500, 2026-09-22/23), PayoutConfigDetail.vue.
- Payout create: 34bf9c24 (502, 2026-09-28), PayoutConfigCreate.vue.
- B2 threshold/range features coexist in module but are excluded as B1 behavior siblings.
- **No ageing config UI/API on development:** searched age/overdue terms in src/views/incentive, src/api, components/composables/utils + read completed.md. `origin/scrum-522` separately adds the list and leaves actions deferred; not landed inventory.

## Reusable inventory
| Piece | Path | What it does | Used by | Source |
|---|---|---|---|---|
| BaseButton | src/components/BaseButton.vue | Buttons | 94 production imports | import inventory |
| LoadingSpinner | src/components/LoadingSpinner.vue | Pending states | 66 imports | inventory + sibling |
| MessageCard | src/components/MessageCard.vue | Loading errors/empty states/retry callback | 54 imports | inventory + 499 |
| BaseDataTable | src/components/BaseDataTable.vue | Configurable AG Grid | 32 imports; B1 card/payout list/detail | inventory + code |
| Breadcrumb | src/components/Breadcrumb.vue | Detail breadcrumbs | 31 imports | inventory |
| dateFormatter | src/utils/dateFormatter.ts | formatDate padded, formatDateShort unpadded | 30 imports | inventory + code |
| IncentivePointGroupCard | src/views/incentive/components/IncentivePointGroupCard.vue | Collapsible read-only point table | B1 IncentiveSchemaDetail | completed.md 489 + code |
| IncentivePeriodPicker | src/views/incentive/components/IncentivePeriodPicker.vue | Add/Edit period picker | SlabConfigForm, PayoutConfigCreate | completed.md 486 + source |
| StatusTag | src/components/StatusTag.vue | Aktif/Nonaktif badge | detail siblings, EditSlabConfig | source |
| ChannelBox/SalesmanGroupBox | src/views/incentive/components/ | Editing channel/group point-slab form state | SlabConfigForm | source; unsuitable as-is for read view |
| formatNumberID | src/utils/stringFormatter.ts:14 | id-ID number formatting, defaults up to 3 decimals | group card, payout detail | completed.md 455 + source |
| Shared API safeguards | src/api/incentive.ts:80-81,1274-1347 | wrapped error guard, raw API/mocks, AbortSignal | payout detail and newer APIs | source |

Counts derived from import targets in src/**/*.vue,ts,js excluding __tests__; references counted, not runtime use counts.

## Legacy areas
- B2-only adapters/cache and hardcoded mock-endpoint patterns are not valid B1 siblings. No blanket claim that the mixed IncentiveSchemaDetail is legacy: its current B1 branch is the chosen sibling. Older completed.md route-query and error-mapper descriptions have been superseded by current code (schema context resolution and raw errors).

## Change log
| Date | Commit | By | What |
|---|---|---|---|
| 2026-10-04 | 49bd1d6b | SCRUM-523 | Initial profile; incentive B1 detail/config, reusable inventory, API/state guards, development vs SCRUM-522 dependency distinction. |
