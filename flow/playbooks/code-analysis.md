# Playbook: Code analysis (find and follow existing patterns)

Used by `code-scout` (step 01) and both planners (step 02). The method is distilled from the repos' own agent files: closio-web-v2 `.claude/CLAUDE.md` §4–5, ws2targetsales `AGENTS.md`, ws2closio `CLAUDE.md` and `SKILLS.md`, ws1closio `.claude/CLAUDE.md`, `SKILLS.md` and `commands/`. Where a repo has those files, they stay the source of truth. Where it doesn't (no `completed.md`, no `lessons.md`, or no conventions file at all), the same knowledge is **derived from the code** (§1A). Either way, the result is kept in `knowledge/<service>.md`, so the next ticket starts from it.

The goal: every plan element either reuses something that already exists or proves that nothing fits. And no question reaches the user that the code, or the closest existing feature, already answers.

## 1. Repo intake (per repo in scope, before reading feature code)
Many repos have **no** `completed.md`, `lessons.md` or agent/conventions file, and new repos usually start with none. Documented knowledge is a bonus, not a requirement. The intake always ends with an up-to-date **repo profile** at `knowledge/<service>.md` (template `flow/templates/repo-profile.md`). The profile records what has been built, the patterns and anti-patterns, and the reusable inventory, whether that comes from documents or from reading the code.

### Scope Isolation Rules (Strict Repo Scoping)
Repo intake and scouting must strictly respect the ticket's confirmed scope:
- **`backend`**: Include **backend repos ONLY** (`ws1closio` gateway, `ws2closio`, `ws2targetsales`, `ws2pricingengine`, `ws2notification`). **`closio-web-v2` (frontend) is strictly EXCLUDED** from code intake and scouting.
- **`frontend`**: Include **frontend repos ONLY** (`closio-web-v2`). Backend repos are EXCLUDED entirely. The API contract comes from the ticket description, the `sources/` tech specs, or the user's input.
- **`fullstack`**: Include both backend repos and frontend repos (`closio-web-v2`).

**0. Profile first.** If `knowledge/<service>.md` exists, read it, then refresh only what changed since its `derived_at_commit`:
- `git log --oneline <sha>..HEAD`
- `git diff --stat <sha>..HEAD`

Update the profile for those areas, and bump the commit and date. If it doesn't exist, or the repo's default branch history no longer contains its commit, build it from scratch: steps 1–5 below, plus §1A for anything not documented.

Then read these in order, if they exist. The paths are in `config/services.md`, and a missing file is noted as "none" in the profile.
1. **Conventions**: `CLAUDE.md` / `.claude/CLAUDE.md`, `AGENTS.md`, `SKILLS.md` / `.claude/SKILLS.md`, `.claude/commands/*.md` (scaffold recipes such as ws1's `new-proxy-endpoint`). Note the "never" and "must" rules that apply to this ticket.
2. **`lessons.md`**: read every entry. Note the ones whose "Rule going forward" touches this ticket's area, and cite them.
3. **`completed.md`**: build the **reusable inventory** from it. For each entry related to the ticket's module, copy its **Reusable / shared code introduced** items, with their paths. This is the team's own index of reusable work. Never skip it.
4. **`project_docs/`**: files named after this ticket or its siblings (`<number>.md`, `<number>-test-suite.md`, tech specs). Prefer the actual payload examples over prose summaries.
5. **Workflow lessons**: `lessons/backend.md` and/or `lessons/frontend.md` in this workflow, for the scope in play.

## 1A. When documentation is missing: derive it from the code
Do this for each of conventions, lessons and `completed.md` that the repo lacks. Even when they exist, do it for the module the ticket touches if the documents don't cover it. Everything derived is labelled `derived` in the profile, with its evidence.

### What has been built (replaces `completed.md`)
- **Features**: list the routes, views or screens, services, workers and crons by module (route files and their mounts, `routes.ts`, cron/worker registries).
- **History**:
  - `git log --no-merges --since="12 months ago" --pretty="%h %ad %s" --date=short -- <module paths>`
  - Ticket keys and `feat` commits show which feature landed where. `git show --stat <sha>` shows its files.
- **Reusable pieces**:
  - shared directories: `components/`, `composables/`, `utils/`, `shared/`, `helpers/`, `constants/`, `middlewares/`, base classes
  - the most-imported modules: grep import or require lines and count them per target, so the top results are the de facto shared code
  - what each piece does, from its exports, props and signature

  Record each piece in the profile → Reusable inventory, with its path.

### Patterns (replaces conventions files)
- **Tooling**: `package.json` scripts, lint, format and TS configs, the test framework, its setup files and coverage thresholds, git hooks (`.husky/`, `lint-staged`).
- **Majority rule**: for each layer (route, controller, service, data access, error handling, validation, response shape, pagination, view, API client, state, test), sample **at least 3 files in recently changed areas**, and record the pattern most of them share.
  - A pattern needs **≥3 consistent examples** to count as a repo convention. Fewer than that is `low confidence`: cite it, but don't auto-adopt it as a convention RC.
- **Recency**: when old and new code differ, the pattern in **recently modified** files wins. Check `git log -1 --format=%ad -- <file>`. Note the old style as legacy.
- **Gotchas**: global middlewares and interceptors (error handlers, auth, status rewrites), base classes, and code generators or scaffolds.

### Anti-patterns (replaces `lessons.md`)
Signals that something should **not** be copied:
- `@deprecated`, `legacy`, `old`, `v1`, `_bak` and `unused` names, and directories marked as being replaced.
- `TODO`, `FIXME`, `HACK` and `XXX` comments, plus `eslint-disable` and `@ts-ignore` clusters near the code you'd copy.
- **Fix-after-feature commits**: `git log --grep "fix\|revert\|hotfix" -- <path>`. A file that got repeated fixes right after its feature commit shows what went wrong there. Read the fix diff and note the rule it implies.
- **Outliers**: the minority style in a layer that otherwise agrees. Duplicated helpers that do the same thing; prefer the most-imported one.
- **Divergence**: code that breaks a rule stated in the repo's own conventions, when those exist.

An outlier or deprecated file is **never** a sibling, even if it's the closest by name.

### Keep it proportional
Derive deeply for the module the ticket touches, and shallowly (directory map, tooling, top shared pieces) for the rest of the repo. The profile grows ticket by ticket.

## 2. Find the sibling
The **sibling** is the closest existing feature with the **same business** and the **same layer and shape**: a B1 list screen for a new B1 list screen, the B1 slab-set PATCH for a B1 config PATCH, an existing ws1 proxy for the same ws2 service.

- **Business boundary**: Business 1 and Business 2 are separate. A B1 ticket's sibling is B1 code. Never borrow B2 behaviour or helpers for B1 work, even when they look equivalent (ws2targetsales `lessons.md` 2026-09-27).
- **A literal service name** in a ticket ("ws2closio") means that repo. `ls` the sibling repos and grep each for the resource before assuming it lives in the repo you already know (ws2targetsales `lessons.md` 2026-08-06).
- **Read the sibling end to end**: route → middleware → controller → service → model/query → error mapping → tests (backend), or route → view → components → API function → mock → types → tests (frontend). Cite the line ranges.
- If two candidate siblings behave differently, record both. That's a genuine question (see §6).

## 3. Reuse ladder (every element the ticket needs)
For each needed element (endpoint, query, validation, error, component, cell renderer, picker, formatter, store, mock, test helper), go down the ladder and stop at the first rung that works:
1. **Reuse as is**: an existing piece does it. Cite it.
2. **Configure or extend**: an existing piece does it with props, options or a small addition. Say exactly what changes.
3. **Compose**: existing pieces combined do it.
4. **New**: only after recording the searches that found nothing (§4). Mirror the sibling's structure and naming.

Record the result in the **Reuse table** (codebase.md for the scout, the plan for the planners).

## 4. Absence claims need evidence
Never write "X doesn't exist", "only Y exists" or "no component for Z" without listing:
- **Grep terms**: the ticket's words, the Figma layer and component names, the Indonesian/English variants (period/periode, picker, range, bulan), and the likely code names (`*Picker`, `*Range*`, `*Period*`).
- **The directories searched**:
  - frontend: `src/components/`, `src/views/<module>/components/`, `src/composables/`, `src/utils/`, `src/api/`
  - backend: `src/services/`, `src/utils/`, `src/shared/`, `src/constants/`, `src/middlewares/`, `src/migrations/`
- **`completed.md` checked** if it exists, **and the profile's Reusable inventory** (`knowledge/<service>.md`): what they list for this module.
- For repos with another layout, use the directories the profile's Directory map names.

*Real miss (SCRUM-522):* "only a single-month chip exists" was claimed, but `closio-web-v2:src/views/incentive/components/IncentivePeriodPicker.vue` existed. It's also mentioned in `completed.md` (ticket 486).

## 5. Verify the ticket's claims about existing behaviour
A ticket saying "same as X already does" or "X is hidden for Y" describes the *new* requirement reliably, but not always the *current* code. Check X in the code before designing around it (closio-web-v2 `lessons.md` 2026-09-09). The same applies to `lessons.md` and `completed.md` entries: code can change after they were written. If the code differs from a lesson, say the lesson is stale.

## 6. Classify each open question
Once the sibling and the inventory are known:

| Outcome | When | Result |
|---|---|---|
| **code fact** | It's about what exists or how the system currently works (a route, table, constraint or component exists; error code → HTTP status; 404→597 in ws1; check order; scoping; locks), and the code shows it. | `RC<n>`, basis `code fact`. Not asked. |
| **convention** | It's about behaviour the **sibling already defines** (sort order, loading/empty/error states, pagination size, renderer, toasts, validation layer, audit fields, response envelope, check order), **and** no AC or source doc says otherwise. | `RC<n>`, basis `convention: <sibling path:lines>`. Adopted, not asked. |
| **contradiction** | An explicit AC or source doc says something different from the code or sibling. First check (§5) whether the ticket's claim about existing code is simply stale. | Ask. Quote both sides. |
| **siblings disagree** | Two equally close siblings do it differently. | Ask, and show both. |
| **business-only** | A policy or product decision that no code or doc decides (who may do what, a new business rule, copy that has no precedent). | Ask. Write "not answerable from code" and list what was checked. |

Convention RCs are listed at the requirements gate. The user can overrule any of them, and an overruled RC becomes a `Q<n>` (and a lesson candidate).

**Deviations.** Anything stricter, looser or "better" than the sibling is a **deviation**. Present it as "deviates from <sibling>: <what and why>". Never label it "(Recommended)", and never adopt it silently (ws2targetsales `lessons.md` 2026-09-27).

## 7. Impact map (both directions)
- **Callers**: who uses the code being changed (other views, other services, crons, workers).
- **Callees**: what it depends on.
- **Shared files** many branches touch: route barrels and `index.js`, `src/api/*.ts`, mocks, `types/*.ts`, constants, `.env.*` flags. Note them as merge-risk points.
- **Tests that assert counts or lists**: worker counts, route lists, menu items. These live outside `test/unit` too (ws2targetsales `lessons.md` 2026-07-21).

## 8. Stack checklists
Check each item against the repo's files. Cite the file, don't copy it.

### ws1closio (BFF / proxy): `.claude/CLAUDE.md`, `SKILLS.md`, `commands/new-proxy-endpoint.md`
- Is there an existing route already? Check `src/routes/` first (no duplicates).
- Proxy only: no DB, no business logic.
- Use the named axios instance (`apiWs2TargetSales`, `apiWs2Closio`, …) from `src/utils/axiosInstances.js`.
- **Build an explicit header object** (`Content-Type`, `X-Partner-Id`, `X-User-Id`, `accept-language` as the siblings do). Never pass `req.headers` (ws2targetsales `lessons.md` 2026-07-27).
- Read `X-Partner-Id` and `X-User-Id` from the session (`req.session.closioData`).
- `res.validateResponse(...)`, `asyncHandler`, an i18n namespace, and locale keys (en/id).
- Request validation: the Ajv schema pattern of the sibling (`src/schemas/`), and whether ws1 validates or only ws2.
- **Error mapping:** `src/middlewares/errorHandler.js` turns **every 404 into 597**, with the original in `details.upstream_status`. Any ws1-level expectation for upstream errors must use this.

### ws2 services (ws2closio, ws2targetsales, ws2notification, ws2pricingengine): `CLAUDE.md` / `AGENTS.md`, `SKILLS.md`
- Is there an existing route? Check `src/routes/`.
- Layering: route → thin controller → fat service. Business logic lives only in services.
- **`partner_id` in every business-data WHERE**, via `validatePartnerHeader` and `validateUserHeader`. Records of another partner behave as "not found" (check the sibling).
- Data access: raw `pgDbUtils` for joins, reports, transactions and locks; Sequelize for simple CRUD (ws2closio). Follow what the sibling uses in ws2targetsales.
- Error catalogue and constants (`src/constants/`, `appConstants.js`). Reuse existing error codes, HTTP statuses and DB-error mappings (for example `23P01` → overlap). Don't create new literals for values that already exist (ws2targetsales `lessons.md` 2026-07-16).
- Pagination (`buildPagination` or the sibling's shape), sort order, and response envelope `{ status, message, data }`.
- Transactions and locks: copy the sibling's pattern. Don't add locks the sibling doesn't have without labelling it as a deviation.
- Migrations: does the table, constraint or index already exist? The migration files are history. The live schema can differ (ws2targetsales `lessons.md` 2026-09-22).
- Tests: TDD (ws2closio mandatory); a characterization test before changing untested code; `proxyquire.noCallThru()` for infrastructure modules; the full `npm test` scope; coverage gates (80/70/80/80) where hooks enforce them.
- Docs: `docs/openapi/<feature>Docs.js`, updated last.

### closio-web-v2 (Vue 3 + Vuetify): `.claude/CLAUDE.md`, `lessons.md`, `completed.md`, `SECURITY.md`
- **Existing route or page first.** Check `src/views/<module>/routes.ts` and read the matching view end to end before proposing a new page (`lessons.md` 2026-08-11).
- Feature flag: the module flag (`VITE_ENABLE_*`, `useFeatureFlags`, route `beforeEnter`), as the sibling uses it.
- **Components:** map every Figma component to an existing one first.
  - Shared: `src/components/`, for example `BaseDataTable`, `MessageCard`, `LoadingSpinner`, `ConfirmationDialog`, `MonthYearPicker`, `DateFilter`, the cell renderers.
  - Module: `src/views/<module>/components/`, for example `IncentivePeriodPicker`, `UserStampCellRenderer`.
- API: `src/api/<module>.ts`.
  - Each endpoint keeps its **raw response shape**: no adapters into another list's row shape (`lessons.md` 2026-09-02 and 09-03).
  - The 597 mock fallback is guarded with `isWrappedUpstreamError` (`lessons.md` 2026-09-08).
  - Mock fixture keys must match the id the real call uses (`lessons.md` 2026-09-09).
- Types: `src/views/<module>/types/`. Pagination types and constants: `src/common-types/`, `src/constants/`.
- States: loading, empty and error, using the sibling's components and copy. Errors: the global axios interceptor handles 401.
- Formatting: `src/utils/dateFormatter.ts`, `stringFormatter.ts`. Copy: hardcoded Indonesian (there's no i18n library).
- Tests: Vitest + @vue/test-utils. Views stub the API function. Follow the sibling's `__tests__` files.

### Any repo without a documented checklist (new or undocumented repos)
Build the checklist from the profile's Patterns section (§1A): one line per layer, with its ≥3 examples. Then check the ticket's needs against it exactly as above. Note in the profile that the checklist is `derived`.

## 9. Output discipline
- Cite `<service>:<path>:<lines>` for every claim.
- List **files read** and **searches run**, so a reviewer can see the coverage.
- Short summaries only. No large code dumps.
