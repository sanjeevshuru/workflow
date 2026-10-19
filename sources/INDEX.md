# Sources index

One row per document. The analyst uses this to decide which docs to open for a ticket, so keep **Modules / features** specific.

| Path | Type | Modules / features | Version / date | Status | Notes |
|---|---|---|---|---|---|
| `techspec/Tech Spec — Business 1 Incentive Engine.md` | Tech spec | Business 1 incentive engine: point model, Non-Trader and Trader incentive points (volume, transacted outlets, team volume, AR ageing deduction, stock level), payout and total points, DB schema, **admin/config APIs §14** (payout configs, slab configs, AR ageing configs, stock days multipliers), feed APIs §15, calculation §16, results §17, error codes §18, validation principles §19 | v1 (Pass 1) | current | Large (~7.9k lines). Use the headings to jump. §14.x numbers are what tickets cite. |
| `techspec/Tech Spec - Incentive (Business 2).md` | Tech spec | Business 2 incentive engine: scheme and slab management (FR-1/2), data ingestion, calculation engine, admin, RBAC (FR-6), data model (ageing, activation, call plan, revenue, unique transacting customer tables), target-sales prerequisites, data archival, BullMQ | last updated 2026-05-19 | current (status: Open) | Links to the B2 PRD (SharePoint, not in sources/) and a Figma file. |
| `techspec/Tech Spec — JOT Incentive Schemes (Business 2).md` | Tech spec | Business 2 JOT schemes: JOT Range Products (SMO), JOT Single Product (STO/SFT), range-slab GET/POST/PATCH APIs, external salesperson–product mapping API, JOT calculation workflow | n/a | current | Business 2 only. Never use it for Business 1 tickets. |
| `techspec/Incentive calc high level workflow.md` | Tech spec | Incentive calculation orchestration: Calculation CRON (2nd) and Catch-up CRON (4th), idempotency guard, data checks, run log, error tables, Redis keys, per-scheme job processing, retries | n/a | current | Cross-business calculation flow. |
