# Tech Spec \- Incentive (Business 2\)

## 4th April 2026

| Participants | Suwandi, Livnoor, Jerin, Ayush, Kushal, Sanjeev, Jayesh, Nizar, Nabiila |
| :----------- | :---------------------------------------------------------------------- |
| Last Updated | 19th May 2026                                                           |
| Status       | Open                                                                    |
| Reviewer     | Suwandi, Listian, Livnoor                                               |

Related Documents:

- [PRD Incentive Engine \- Business 2.docx](https://japfacom-my.sharepoint.com/:w:/g/personal/ext_jerin_baiju_japfa_com/IQAeo3SUaIkkTb-oBB2AipZTAbz0sb-mhoN55eiKZyLWflg?e=9AqHdz)
- [Business 2 – Incentive Schemes.docx](https://japfacom-my.sharepoint.com/:w:/g/personal/ext_jerin_baiju_japfa_com/IQBu0-vAQv6KTZarnNr32DVZARHXZ1Z_sdmmSPm3Gil0-sM?e=keHXYD)
- [Figma Link](https://www.figma.com/design/jAnvUQuKFMGBL9Ma6AyTWT/03.-SFA-Backoffice?node-id=17875-314468&t=sE6smYDChNJrY2rj-0)
- [Swagger Docs](<https://dev-closio-ws1-apiprivate.japfacomfeed.co.id/api-docs/#/Incentive%20Feeds%20(Webhooks)/get_incentives_v1_feeds_status__log_id_>)
- [Swagger Docs \- Webhook API](<https://dev-target-sales-ws2-apiprivate.japfacomfeed.co.id/api-docs/#/Incentive%20Feeds%20(Webhooks)/post_incentives_v1_feeds_activation_call>)
- [Incentive calc high level workflow](https://docs.google.com/document/d/1oQxMPReOCEY2kNIvHkZdDXHqzaFDHzMfkIQR_d1KxEs/edit?usp=sharing)

# Context

Today, the organisation maintains monthly sales incentive schemes across multiple business units, product groups, channels, salesperson types, etc. However, incentive calculation is still performed manually through spreadsheets or semi-structured processes. These workflows rely on disconnected data sources \- sales actuals, returns, ageing, call plans, etc \- making the incentive payout process inconsistent, slow, and error-prone.

The Incentive Engine will be integrated with the Target Engine as the next logical module in the workflow. It will ingest:

- Target details (monthly/weekly breakdown)
- Achievement value and % (from Target Engine)
- Sales Actuals data
- Accounts receivable (AR) & ageing
- Return details
- Salesperson hierarchy, etc

Based on these inputs, the engine will compute incentives using configurable slabs. It will also provide transparent reporting for Sales/HR/Finance teams.

# Problem Statement

The current incentive calculation process for some businesses is manual, spreadsheet-driven, and non-auditable, creating operational inefficiencies and business risk:

Key Pain Points \-

- **Fragmented data**: Target achievement, sales, AR, returns, etc sit in different systems.
- **High manual effort**: Sales managers spend days consolidating datasets and calculating incentives each month.
- **Auditability gaps**: No traceability of changes, no versioning of schemes, no clear logs of overrides or formula updates.
- **Error risk**: Manual Excel formulas often introduce mistakes that impact salesperson payout and morale. · Delayed payouts: Incentive payouts take weeks due to cross-team dependencies and validation delays.

Without a unified Incentive Engine, administering incentive schemes, especially updates, validations, and monthly calculations, continues to demand significant manual effort and coordination.

# Functional Requirements:

## FR-1: Incentive Scheme Management

### FR-1.1: Scheme Registry

- The system shall maintain a static registry of exactly 8 predefined incentive schemes: Call Plan, Unique Transacting Customers, JOT Range Products, JOT for Single Product, Weekly Revenue, Monthly Revenue, Ageing, and Activation Call.
- Schemes shall not be user-creatable, editable, or deletable via any UI or API. They are seed data.
- Each scheme shall carry metadata: scheme code, display name, applicable salesperson types, whether it has a target, whether the supervisor has a target, and the achievement source.

### FR-1.2: Scheme-to-Salesperson Type Applicability

- The system shall enforce scheme applicability rules at both the slab configuration and calculation layer:
  - Call Plan → STO, SFT
  - Unique Transacting Customers → STO, SFT
  - JOT Range Products → SMO
  - JOT for Single Product → STO, SFT
  - Weekly Revenue → STO, SFT, SMO
  - Monthly Revenue → STO, SFT, SMO
  - Ageing → STO, SFT, SMO
  - Activation Call → STO
- Supervisor types (SPV DRY, SPV MIX, SPV MO, SPV FTO) are always treated as distinct salesperson types for slab configuration purposes, fully independent of the field salesperson types they oversee.

## FR-2: Incentive Slab Configuration

### FR-2.1: Slab Configuration Ownership

- Slabs are configured per incentive scheme and per salesperson type.
- Salesperson types for slab configuration are: STO, SFT, SMO, SMF, SPV DRY, SPV MIX, SPV MO, SPV FTO.
- Each supervisor type (SPV DRY, SPV MIX, SPV MO, SPV FTO) has its own independent slab configuration per scheme. This allows, for example, SPV DRY to have a different payout curve than SPV MIX for the same incentive scheme.
- Each configuration is bounded by a validity period: berlaku_sejak (From Period) and berlaku_sampai (To Period), expressed as month and year.

### FR-2.2: Period Validation Rules

- Both berlaku_sejak and berlaku_sampai must be the current month or a future period at the time of creation. Past periods are not permitted for new configurations.
- The rationale: incentive for the current month is calculated on the 2nd of the following month, so the current month's slab remains configurable throughout the month.
- berlaku_sampai must be greater than or equal to berlaku_sejak.
- The system shall reject any new configuration that overlaps in period with an existing active configuration for the same scheme and salesperson type.

### FR-2.3: Period-Based Edit Rules

- Case 1 — Both periods are current month or future: all fields including period and slab rows are fully editable.
- Case 2 — berlaku_sejak is a past period, berlaku_sampai is current month or future: only berlaku_sampai is editable; slab rows and berlaku_sejak are read-only.
- Case 3 — Both periods are past: edit is not permitted; the Edit action is hidden from the UI for these records.

### FR-2.4: Standard Slab Structure (All schemes except JOT Range Products and JOT for Single Product)

- Each slab row contains: Salesperson Type, Target Type (VALUE or %), Symbol (\>, \>=, \=), Threshold, and Payout Amount (IDR).
- All fields per row are mandatory.
- Duplicate rows — same Salesperson Type \+ Target Type \+ Symbol \+ Threshold within the same scheme and period — shall be rejected at API level.
- At least one slab row must be present before saving.
- Numeric fields (Threshold, Amount) must be positive, maximum 9 digits.

### FR-2.5: JOT Range Slab Structure

- JOT Range Products uses a distinct fixed-tier slab layout: three product-group range rows (e.g. 2–3, 4–5, 6+), each with Low, Mid, and High threshold-rate pairs. **JOT for Single Product uses the same range slab structure — range_start/range_end represent distinct product counts (not product groups) per customer.**
- The product-group ranges are not globally fixed — they vary per salesperson type and are configurable.
- Each range must have all three tiers (Low Target, Low Rate, Mid Target, Mid Rate, High Target, High Rate) filled before saving.
- System shall validate: Low Target \< Mid Target \< High Target within each range.
- Supervisor base thresholds for JOT Range are configured per supervisor type (SPV DRY, SPV MIX, SPV MO, SPV FTO) on the same screen. The engine scales these base thresholds by the SP group size of the corresponding reporting salesperson types at calculation time — thresholds are not stored pre-scaled.

### FR-2.6: Allowed Slab Types by Business Rule

- The system shall restrict the available slab_type options (VALUE / PERCENTAGE / BOTH) per scheme and salesperson type:
  - Activation Call \+ STO (Salesperson) → VALUE only
  - Activation Call \+ SPV DRY / SPV MIX / SPV MO / SPV FTO → PERCENTAGE only
  - Ageing (all types) → PERCENTAGE only
  - JOT Range Products (all types) → VALUE only
  - JOT for Single Product (all types) → VALUE only
  - Call Plan, Unique Customers, Weekly Revenue, Monthly Revenue → BOTH
- allowed_slab_types shall be stored at the scheme level and enforced at validation; the frontend dropdown shall be restricted accordingly.

### FR-2.7: Slab Configuration CRUD

- The system shall support List, View Detail, Create, and Edit operations for slab configurations.
- List screen shall support filtering by scheme (via dropdown), period (month \+ year), and shall display: scheme name, validity period, created by, last modified by, and actions.
- Records shall be ordered descending by berlaku_sejak.
- Pagination shall be applied; default page size to match existing system conventions.

##

##

##

## FR-3: Data Ingestion

### FR-3.1: Target Engine Integration (API-based Fetch)

- The Incentive Engine shall fetch target and achievement data from the Target Engine via dedicated APIs exposed by the Target Engine, called as part of each calculation run.
- The following APIs shall be consumed:
  - T3 API: fetch daily call plan targets and actuals per salesperson for the calculation month
  - T4 API: fetch monthly unique transacting customer targets per salesperson for the calculation month
  - T5 API: fetch monthly revenue targets per focus product per salesperson for the calculation month
  - T6 API: fetch weekly revenue targets per salesperson per week for the calculation month
- These API calls are made by the Incentive Engine during the calculation run, not pre-ingested or cached ahead of time.
- If any Target Engine API returns an error, a timeout, or incomplete data, the calculation run shall be aborted immediately and an alert raised to Admin. No partial execution against incomplete data.
- API authentication and contract details (endpoint structure, auth headers, pagination behaviour) shall be aligned with the Target Engine team and documented in the API contract before development begins.

### FR-3.2: Ageing Data Feed (Qlik Sense — Webhook/Push)

- The system shall expose a POST endpoint to receive the month-end ageing data feed from Qlik Sense as a CSV file upload.
- **Endpoint:** POST /incentive/v1/feeds/ageing
- **Request format:** multipart/form-data with the following fields:
- **Expected CSV columns (exact, order-independent):** salesperson_id, month, ar_0_10_days, ar_month_total
- The endpoint operates in two phases:
  - **Phase 1 — Synchronous Accept (target: ≤ 500ms):**
    - Validate x-client-id and x-client-secret headers against the SERVICE_CREDENTIALS credential map.
    - Validate all required form fields. Parse the CSV header row only — reject with 400 INVALID_CSV_SCHEMA immediately if column names do not match the expected schema.
    - Query feed_webhook_log for an existing record with (partner_id, feed_type='ageing', month, year) and status \= 'success' — if found, reject with 409 ALREADY_RECEIVED.
    - Stream the uploaded CSV file directly to S3 using the deterministic key {S3_FEED_PATH_PREFIX}ageing/{partner_id}/{year}/{month}/{original_filename} into the S3_FEED_BUCKET bucket. The S3 upload must complete before proceeding. If the upload fails, return 500 FEED_UPLOAD_FAILED and do not write any DB record. Record the filename (original filename from the multipart upload), s3_key, s3_bucket, and file_size_bytes from the upload response.
    - Insert a feed_webhook_log record with status \= 'pending', filename, s3_key, s3_bucket, file_size_bytes, and received_at \= NOW().
    - Enqueue a single BullMQ job into feed-ingestion-queue carrying log_id, feed_type, partner_id, month, year, s3_bucket, and s3_key. Row data is not embedded in the job payload.
  - **Phase 2 — Async BullMQ Processing (per chunk job):** Covered in FR-3.5.
- If the feed is not received before the CRON window on the 2nd (i.e. no feed_webhook_log record with status \= 'success' for the relevant partner_id, month, and year), the Ageing incentive type shall be flagged as DATA_UNAVAILABLE and excluded from that run. Admin shall be alerted.
- **S3 file lifecycle:** The CSV is uploaded to S3 in Phase 1 and is retained in the feed bucket for the duration defined by the bucket's S3 lifecycle policy. Because the file resides in S3, it is durable across pod restarts and server failures. If the Phase 2 worker encounters an S3 NoSuchKey error on the assigned s3_key, it must fail immediately without retry and write S3_OBJECT_NOT_FOUND to error_details on feed_webhook_log. The feed_webhook_log will reach failed status and Admin shall be alerted. Re-send is permitted as the original upload did not reach success status.

### FR-3.3: Activation Call Feed (Task Management — Webhook/Push)

- The system shall expose a POST endpoint to receive the month-end activation call feed from Task Management as a CSV file upload.
- **Endpoint:** POST /incentive/v1/feeds/activation-call
- **Request format:** multipart/form-data with the following fields:
- **Expected CSV columns (exact, order-independent):** salesperson_id, customer_id, month, year
- Each row represents one unique customer for whom an activation call was made by the given salesperson in the given month and year.
- The endpoint operates in the same two-phase flow as FR-3.2 (synchronous accept → async BullMQ processing), with the following specifics:
- S3 key: {S3_FEED_PATH_PREFIX}activation/{partner_id}/{year}/{month}/{original_filename} in S3_FEED_BUCKET. The s3_key, s3_bucket, and filename are recorded in feed_webhook_log on insert (identical Phase 1 flow to FR-3.2).
- Target insert table: activation_activity
- 409 ALREADY_RECEIVED returned if a success record already exists for (partner_id, feed_type='activation', month, year)
- **Deduplication:** The same (salesperson_id, customer_id, month, year) combination appearing more than once in the CSV, or in a re-ingested file, shall be counted only once. Deduplication is enforced at the database layer via INSERT ... ON CONFLICT DO NOTHING on the unique composite index on activation_activity (salesperson_id, customer_id, month, year). Application-layer deduplication is not relied upon.
- All ingested feed data is stored against feed_webhook_log_id on activation_activity for full traceability to the ingestion event.
- If the feed is not received before the CRON window on the 2nd, the Activation Call incentive type shall be flagged as DATA_UNAVAILABLE and excluded from that run. Admin shall be alerted.
- S3 file lifecycle and S3_OBJECT_NOT_FOUND error handling are identical to FR-3.2.

### FR-3.4: Feed Receipt Tracking

- The feed_webhook_log table is the single source of truth for feed receipt status. It maintains one record per (partner_id, feed_type, month, year) combination, tracking the full lifecycle of each feed upload from receipt through async processing completion.
- Status transitions on feed_webhook_log are: pending → processing → success | failed. The single Phase 2 worker sets status to 'processing' on job pickup and to 'success' on completion, or 'failed' if the job exhausts all retries. completed_at is set when the final status is written.
- The Calculation CRON on the 2nd serves as the primary gate. It queries feed_webhook_log as its pre-run gate before dispatching any scheme jobs. If any mandatory feed does not have a status \= 'success' record for the calculation month and partner, those schemes are excluded from that run and Admin is alerted.
- Both checks run within the same CRON process. Alerts from each check are dispatched independently — a failure in the achievement check does not suppress the feed check alert, and vice versa.
- The incentive calculation CRON on the 2nd shall query feed_webhook_log as its pre-run gate. If any mandatory feed does not have a status \= 'success' record for the calculation month and partner, the run shall abort as defined in FR-4.1.
- Admin shall be able to view feed receipt status per source for the current and previous month via the feed receipt monitoring screen, which reads directly from feed_webhook_log.

### FR-3.5: BullMQ Feed Processing Design

**Job payload:**

| { "log_id": "\<uuid\>", "feed_type": "ageing | activation", "partner_id": "\<uuid\>", "month": 4, "year": 2025, "s3_bucket": "japfa-incentive-feeds", "s3_key": "ageing/partner-japfa-b2/2025/4/ageing_feed_2025_04.csv" } |
| :------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

One job is enqueued per file. Row data is not embedded in the job payload. The worker streams the full file from S3 sequentially using a single GetObjectCommand with no Range header. The file is never buffered in memory — readline emits one line at a time, and only FEED_CHUNK_SIZE rows are held in the batch array at any point.

**Worker behaviour :**

1. Set feed_webhook_log.status to 'processing' on job pickup.
2. Issue a full S3 GetObjectCommand against s3_bucket/s3_key. If S3 NoSuchKey → fail immediately without retry, write S3_OBJECT_NOT_FOUND to error_details on feed_webhook_log, set status to 'failed'. For transient S3 errors (503 SlowDown, network timeout) → follow BullMQ exponential backoff retry.
3. Wrap the S3 response stream in readline with crlfDelay: Infinity. Skip the header row (first emitted line). Process rows sequentially — do not buffer the full file in memory.
4. Validate each row for data types, nullability, and range constraints. Invalid rows are skipped and accumulated into a local error list. Processing continues for remaining rows.
5. Accumulate valid rows into a batch array of FEED_CHUNK_SIZE rows. Bulk insert each batch into ageing_activity or activation_activity via INSERT ... ON CONFLICT DO NOTHING. Clear the batch array and continue.
6. After the stream closes, flush any remaining rows in the batch array.
7. Set feed_webhook_log.status to 'success' and completed_at \= NOW(). Write accumulated row-level errors to error_details if any exist.
8. No file cleanup is performed. The raw CSV is retained in S3 per the bucket lifecycle policy. The s3_key and s3_bucket recorded in feed_webhook_log remain the permanent audit reference to the original uploaded file.

**Retry strategy:**

| Parameter                               | Value                                                                    |
| --------------------------------------- | ------------------------------------------------------------------------ |
| Max attempts                            | 3                                                                        |
| Backoff                                 | Exponential, starting at 5 seconds                                       |
| S3 NoSuchKey (object not found)         | Fail immediately — no retry                                              |
| Transient S3 errors (SlowDown, timeout) | Retryable — follow exponential backoff                                   |
| On max retries exhausted                | Move to incentive-dlq; dispatch; set feed_webhook_log status to 'failed' |

**Idempotency:** **Idempotency:** INSERT ... ON CONFLICT DO NOTHING ensures re-processing the full file on BullMQ retry does not create duplicate records.

### FR-3.6 Achievement Data Readiness Check

- The system shall verify that achievement data for all salespersons.
- Achievement data is sourced from the Target Engine... However, the Data Readiness CRON shall perform an early availability check.
- The check is performed per target type (T3, T4, T5, T6) and per partner.
- This check does not trigger calculation or persist any data. It is a fire-and-forget probe.
- If achievement data is unavailable but becomes available by the calculation day.
- At calculation time, the pre-run gate (FR-4.1) remains the hard block.

## FR-4: Incentive Calculation Engine

### FR-4.1: Automatic Monthly Calculation (CRON)

- The system shall run a scheduled calculation job on a configurable day of month (default: **2nd**) at a configurable time.
- The default of the 2nd is intentional: the 1st of each month serves as a data finalization window, allowing achievement data for all salespersons for the previous month to be updated and locked before the incentive run executes.
- The job shall process the previous calendar month for all active incentive types.
- **Pre-run validation:** At calculation time, before any calculation jobs are dispatched, the Run Orchestrator performs the following gate checks in order:

1. **Feed gate:** Queries feed_webhook_log for status \= 'success' records for all mandatory feeds (Ageing, Activation Call) for the calculation month and partner. If any mandatory feed is absent or not in success status, the run is aborted and Admin is alerted. No partial execution.
2. **Achievement data gate:** Probes the Target Engine T3, T4, T5, and T6 APIs to confirm achievement data is available for the calculation month. If any API returns an error, timeout, or empty dataset, the affected incentive type job is failed with DATA_UNAVAILABLE and Admin is alerted.

- Note: the Calculation CRON gate check on the 2nd is the primary hard block. The Catch-up CRON on the 4th re-runs gate checks for any schemes that did not complete successfully on the 2nd.
- On completion, all results shall be persisted and available for reporting.
- Every run shall be logged: run ID, trigger type (CRON), timestamp, month processed, incentive types processed, salespersons processed, errors and warnings.
- A **Catch-up CRON** runs on the 4th of each month. It queries incentive_run_log to identify which schemes were not successfully calculated on the 2nd, runs gate checks for those remaining schemes only, and enqueues the missing scheme jobs into their dedicated queues. The same worker processing flow applies. Schemes already completed successfully on the 2nd are not re-processed.

### FR-4.2: Manual Calculation Trigger

- Admin can manually trigger a recalculation for the most recently closed month only.
- A confirmation dialog shall be shown before execution, warning that existing results for that month will be overwritten.
- Same pre-run feed validation applies as CRON.
- Manual triggers shall be logged with triggering user identity and timestamp.

### FR-4.3: Per-Scheme Calculation Logic

#### FR-4.3.1: Call Plan

- For each salesperson, for each day D: compute achievement value (actuals) and achievement % (actuals / T3 target × 100). Evaluate against slab to assign daily incentive I(D). Monthly total \= sum of all I(D).
- If T3 target is zero or unavailable for a day, that day's achievement \= 0; daily incentive \= 0\. Zero days are not excluded — they contribute Rp. 0\.
- For supervisors: slab is looked up against the applicable supervisor type (SPV DRY, SPV MIX, SPV MO, SPV FTO). Achievement Value \= sum of actuals of all reporting SPs; Achievement % \= sum of actuals / sum of T3 targets of reporting SPs × 100\. Summation of each day is then to calculate the supervisor's final incentive.
- No personal target for supervisor.

#### FR-4.3.2: Unique Transacting Customers

- For each salesperson: Achievement Value \= count of unique customers with net sales \> 0 for the month. Achievement % \= Achievement Value / T4 target × 100\.
- For supervisors: SPV Target \= sum of T4 targets of reporting SPs \+ SPV's own actual unique customer count. SPV Achievement \= deduplicated union of unique customers across all reporting SPs \+ SPV's own unique customers. Deduplication rule: same customer ID across two reporting SPs counts once. Slab lookup uses the applicable supervisor type.

#### FR-4.3.3: JOT Range Products

##### Salesperson Logic

- Each customer is classified into exactly one JOT range based on the number of unique JOT product groups they bought from that salesperson in the month (net sales \> 0). No double counting.
- Unique JOT Product Groups for a salesperson is considered only for those product groups which are mapped to the salesperson type. There are chances that STO salesperson sells frozen products, but it will not be counted towards the product range count. The salesperson type – JOT product group mappings can be identified through an API (to be shared).
- Evaluate ranges from highest to lowest: 6+ → 4–5 → 2–3 (the product group ranges can vary based on salesperson type).
- For each range, compare the customer count against Low / Mid / High slab thresholds.
- Assign incentive amount based on which slab is met. Total incentive \= sum across all ranges.
- Carry-forward rule: if count \> High threshold, overflow \= count − High threshold. Add overflow to the next lower range. Current range is capped at High threshold rate.
- Carry-forward continues down to the 2–3 range (the lowest range), where any remaining overflow is discarded.

##### **Supervisor Logic (To be updated)**

- The SPV incentive is computed separately per salesperson type group (STO, SMO, SFT), then summed.
- For each group:
  - Aggregate customer counts per range across all SPs in the group
  - Adjusted threshold \= base threshold × number of SPs in the group
  - Incentive amounts are NOT multiplied — only thresholds are scaled
  - Apply same carry-forward logic within the group
  - Carry-forward does NOT cross groups (e.g., STO overflow does not go to SMO)
- Final SPV incentive \= STO group incentive \+ SMO group incentive \+ SFT group incentive

#### FR-4.3.4: JOT for Single Product

- Applicable to: STO, SFT.
- For each salesperson: per customer, count the number of **distinct products** (not product groups) for which net sales \> 0 in the month. Each customer is then classified into exactly one range band based on that product count.
- Evaluate ranges from highest to lowest (e.g. 6+ → 4–5 → 2–3). The product count ranges vary per salesperson type and are configurable via incentive_range_payout_slabs.
- For each range band, compare the customer count in that band against the Low / Mid / High slab thresholds. Carry-forward logic applies identically to JOT Range Products: customers classified into a higher range that do not meet the Low threshold carry forward into the next lower range.
- Slab lookup uses the applicable salesperson type (STO or SFT). Achievement Unit \= customer count per range band.
- For supervisors: SPV incentive is computed separately per salesperson type group (STO, SFT), then summed. Carry-forward does NOT cross groups. Aggregate customer counts per range across all SPs in the group. Scale the SPV base thresholds by SP group size for each type.

#### FR-4.3.5: Weekly Revenue

- Weeks are defined by a configurable days-to-week mapping master (W1–W4), not calendar weeks.
- For each salesperson per week W: Achievement Value \= net revenue for all T6 focus product groups for that week. Achievement % \= Achievement Value / T6 weekly target × 100\. Monthly total \= sum of I(W1) through I(W4).
- For supervisors: SPV Target \= sum of T6 weekly targets of reporting SPs \+ SPV's own T6 target. SPV Achievement \= sum of weekly revenue of reporting SPs \+ SPV's own revenue. Slab lookup uses the applicable supervisor type (SPV DRY, SPV MIX, SPV MO, SPV FTO).

#### FR-4.3.6: Monthly Revenue

- For each salesperson: Achievement Value \= sum of net revenue across all T5 focus products for the month. Target \= sum of T5 targets across all focus products. Products are NOT evaluated individually — combined target vs. combined achievement.
- For supervisors: SPV Target \= sum of T5 targets of reporting SPs \+ SPV's own T5 target. SPV Achievement \= sum of monthly revenue of reporting SPs \+ SPV's own revenue. Slab lookup uses the applicable supervisor type.

#### FR-4.3.7: Ageing

- Input: Ageing data feed from Qlik Sense. For each salesperson: Ageing % \= AR (0–10 days) / Total AR × 100\. No target; purely percentage-based slab.
- Edge case: if Total AR \= 0, Ageing % \= 0; incentive \= Rp. 0 (no division by zero).
- For supervisors: Numerator \= sum of AR (0–10 days) of all reporting SPs \+ SPV's own. Denominator \= sum of Total AR of all reporting SPs \+ SPV's own. Slab lookup uses the applicable supervisor type (SPV DRY, SPV MIX, SPV MO, SPV FTO).

#### FR-4.3.8: Activation Call

- Input: Activation call feed from Task Management. Feed format: salesperson_id | customer | month | year.
- Achievement \= count of unique customers from the feed who had net sales \> 0 in M, M-1, and M-2. The 3-month lookback includes the current month M — e.g. if the feed is for April, the system checks April, March, and February.
- No target for salesperson — slab is value-based.
- Edge case: if prior-month sales data is unavailable (system cold-start), qualifying count \= 0\. A one-time historical data upload covering 2 months prior to go-live must be performed before the first calculation run.
- For supervisors: SPV Target \= Σ (count of reporting SPs per salesperson type × multiplier for that type). Multiplier is configurable per salesperson type (default: 280 for all types). SPV Achievement \= sum of activation call counts of all reporting SPs. SPV's own activation calls are NOT included.
- Achievement % \= SPV Achievement / SPV Target × 100\. Slab lookup uses the applicable supervisor type (SPV DRY, SPV MIX, SPV MO, SPV FTO).

### FR-4.4: Achievement Floor

- If net achievement for any incentive is negative (returns exceed sales), achievement is floored at 0 for slab comparison purposes.

### FR-4.5: Generic Slab Evaluator

- The system shall provide a shared slab evaluation function usable by all standard schemes.
- Given: an achievement value or percentage, a slab_type (VALUE / PERCENTAGE), and the active slab configuration for the scheme \+ salesperson type \+ period — the evaluator returns the matched payout amount.
- For JOT Range Products and JOT for Single Product, a shared range evaluator handles the threshold logic and carry-forward. The distinction between the two schemes is solely in the input metric: JOT Range Products uses distinct product **groups** per customer; JOT for Single Product uses distinct **products** per customer.
- The evaluator shall resolve the correct supervisor type (SPV DRY, SPV MIX, SPV MO, SPV FTO) from the salesperson's supervisor record before performing the slab lookup.

### FR-4.6: Calculation Result Storage

- Results shall be stored per salesperson per incentive type per month with: salesperson ID, salesperson type, scheme ID, month, achievement value, achievement %, payout amount, run ID, and calculation timestamp.
- For schemes with sub-period granularity (Call Plan: daily; Weekly Revenue: weekly), intermediate results shall also be stored alongside the monthly total.
- Results for a re-run shall overwrite previous results for the same salesperson \+ scheme \+ month combination.

## FR-5: Administration

### FR-5.1: CRON Schedule Configuration

- The system shall allow Admin to configure the day of month and time for the automatic calculation CRON (default: 2nd of each month).
- Changes in the CRON JOB timings take effect from the next calendar month.
- A second system-managed CRON — the **Catch-up CRON** — runs automatically on the 4th of each month. It is not user-configurable. Its responsibilities are: query incentive_run_log for the previous month to identify schemes that did not complete successfully on the 2nd; run gate checks (feed receipt, achievement data, slab config) for those schemes only; enqueue only the missing scheme jobs into their dedicated BullMQ queues. It does not re-process schemes already completed.

### FR-5.2: Activation Call Multiplier Configuration

- Admin can view and edit the SPV target multiplier per salesperson type used in the Activation Call incentive SPV target formula.
- Multiplier values are stored in the database with the following structure: id | partner_id | salesperson_type | multiplier | valid_from | valid_to | created_at | updated_at
- Multipliers are partner-scoped — each partner can have independent multiplier values per salesperson type (STO, SFT, SMO in future).
- Multipliers are period-bounded via valid_from and valid_to. At calculation time, the engine shall resolve the multiplier record whose validity period covers the calculation month for the given partner and salesperson type.
- Default multiplier value for all salesperson types is 280 until explicitly overridden.
- New multiplier records must have valid_from set to a current or future month. Past periods are not permitted for new entries.
- Period overlap for the same partner_id \+ salesperson_type combination shall be rejected at API level.
- Changes take effect from the applicable valid_from period — they do not retroactively affect completed calculation runs.
- A confirmation is required before saving: any change to multiplier values will affect the next Activation Call incentive calculation for the applicable partner and salesperson type.
- If no valid multiplier record is found for a given partner \+ salesperson type \+ calculation month at run time, the calculation run shall flag an error.

### FR-5.3: Manual Recalculation Trigger UI

- Admin can initiate a manual recalculation from the admin screen for the most recently closed month only.
- System validates feed availability before proceeding.
- Confirmation modal warns that previous results will be overwritten.

### FR-5.4: Achievement Data Lock Window

- The system shall treat the 1st through 3rd of each month as a data finalization window.
- During this window, no automated incentive calculation shall execute, allowing upstream systems to push final achievement data for the previous month.
- Admin shall have visibility into which feeds have been received and which are pending during this window.

## FR-6: Role-Based Access Control

### FR-6.1: Persona Permissions

- Sales Manager: can view, create, and edit incentive slabs. Cannot trigger calculations or modify CRON settings or multiplier values.
- Admin: all Sales Manager permissions plus manual calculation trigger, CRON schedule configuration, multiplier configuration, and feed receipt monitoring.
- All API endpoints shall enforce RBAC. Unauthorized access attempts shall return 403\.

#

# Non-Functional Requirements

## APIs (Slab Management \+ Admin \+ Data Ingestion)

| Category            | Requirement                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Performance**     | All slab management and admin APIs must respond in ≤ 1s for standard page loads under normal load. Target Engine API calls must complete within a configurable timeout (default: 30s per API call) before the run is aborted.Feed ingestion endpoints must acknowledge receipt (Phase 1 accept) within ≤ 500ms regardless of CSV file size. CSV parsing, validation, and DB insertion are performed asynchronously via BullMQ and must not affect the acknowledgement latency. Full ingestion of a feed file (up to 200,000 rows streamed sequentially by a single worker with batch inserts of FEED_CHUNK_SIZE rows) must complete within 10 minutes under normal load. |
| **Scalability**     | Slab and configuration APIs must support concurrent access from multiple admin/sales manager users without race conditions on period overlap validation. Overlap check must be enforced at DB constraint level to handle concurrent writes. Feed ingestion must handle bulk payloads from Qlik Sense and Task Management without blocking the calculation pipeline. Addition of new supervisor types beyond SPV DRY, SPV MIX, SPV MO, SPV FTO must be supportable by adding slab configuration rows and salesperson type seed data, not schema changes.                                                                                                                  |
| **Security**        | All admin and slab APIs are secured via JWT with role claims. Feed ingestion endpoints from Qlik Sense and Task Management are authenticated via x-client-id and x-client-secret headers validated against the SERVICE_CREDENTIALS credential map. Target Engine API calls must use agreed authentication headers per the API contract. All data encrypted in transit (TLS) and at rest.                                                                                                                                                                                                                                                                                 |
| **Availability**    | Incentive Engine API uptime target: ≥ 99% measured monthly.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| **Data Integrity**  | Period overlap validation enforced at DB constraint level. Duplicate slab rows rejected at API level before DB write. Activation call feed deduplicated on ingestion on salesperson_id \+ customer \+ month \+ year. Negative achievement floored at 0 before slab evaluation. Division-by-zero (Ageing zero Total AR) handled explicitly — treated as 0%, not an error. Supervisor type resolution (SPV DRY, SPV MIX, SPV MO, SPV FTO) must be deterministic and consistent across all schemes at slab lookup time. Target Engine API response snapshots stored against run ID — the data used in a calculation run must be fully reproducible from stored records.     |
| **Auditability**    | All slab configuration creates, edits, and period changes logged with user ID, timestamp, and before/after state. All feed receipts logged with source, received timestamp, and associated month. All multiplier value changes logged with Admin user ID and timestamp. All Target Engine API responses stored against the calculation run ID. Activation call and ageing feed ingestion events logged with payload size, receipt timestamp, and source.                                                                                                                                                                                                                 |
| **Maintainability** | allowed_slab_types rules are data-driven (stored on the scheme record), not hardcoded in API handlers. Supervisor types (SPV DRY, SPV MIX, SPV MO, SPV FTO) are stored as configurable seed data so new types can be added without code changes. Target Engine API endpoints are configurable via environment variables, not hardcoded. Feed ingestion endpoints are decoupled from the calculation engine — a feed can be received and stored independently of whether a calculation run is in progress.                                                                                                                                                                |

## Calculation Engine (CRON \+ Manual Trigger \+ Job Processing)

| Category            | Requirement                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Performance**     | Full incentive calculation for all salespersons and supervisors (\~350 total) across all 8 schemes must be completed within 20 minutes per run.Individual scheme calculations are processed sequentially via 2 BullMQ workers picking jobs one at a time. The 20-minute SLO accounts for this sequential processing model. Target Engine API calls must support batched or bulk fetch to avoid N×4 sequential calls for \~300 salespersons breaching the time budget. The 1st data finalization window must not impose any processing overhead on the calculation run on the 2nd.                                                                                                                                                |
| **Scalability**     | BullMQ worker count must be configurable via environment variable without code deployment. New salesperson onboarding must not require schema changes. All four supervisor types (SPV DRY, SPV MIX, SPV MO, SPV FTO) must be supported without separate code paths — the slab evaluator resolves type from the salesperson record at runtime. New incentive schemes must be addable as independent calculation modules without redesigning the job queue architecture.                                                                                                                                                                                                                                                           |
| **Reliability**     | CRON default on the 2nd provides a 1-day buffer post-month-end for data to arrive and be finalized before calculation executes. CRON failures must trigger an alert to Admin. Failed calculation runs must roll back to previous stored results — no partial overwrite. BullMQ jobs must use persistent queues so in-flight jobs survive a Redis restart. Automatic retries for transient failures (e.g. Target Engine API timeout) with configurable retry count and backoff.                                                                                                                                                                                                                                                   |
| **Data Integrity**  | Each calculation run is assigned a unique run ID. All data fetched from Target Engine APIs (T3, T4, T5, T6) and all external feed data (Ageing, Activation Call) is stored against the run ID. Result overwrite on re-run is atomic — no state where some salespersons have new results and others have old results for the same month. Activation call 3-month lookback (M, M-1, M-2) must correctly handle month boundary arithmetic including year rollover (e.g. M \= January → M-1 \= December of prior year). Supervisor hierarchy and supervisor type assignments (SPV DRY, SPV MIX, SPV MO, SPV FTO) used at calculation time are snapshotted against the run ID to support future audit of mid-month hierarchy changes. |
| **Availability**    | Recovery Time Objective (RTO): ≤ 5 minutes for the calculation queue to recover from a Redis or worker restart. The CRON scheduler must be resilient to application restarts — missed CRON triggers due to downtime must be detectable and manually triggerable by Admin.                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| **Maintainability** | Each incentive scheme is implemented as a self-contained calculation module. The generic slab evaluator is shared across all standard schemes; **JOT Range Products and JOT for Single Product share a separate range evaluator.** Supervisor type (SPV DRY, SPV MIX, SPV MO, SPV FTO) is resolved from the salesperson master at runtime — it is not hardcoded per scheme. Per-salesperson, per-scheme calculation logs must be queryable independently for debugging without scanning the full run log. CRON schedule must be configurable via admin UI without code deployment or server restart. Target Engine API base URLs and auth config must be manageable via environment variables.                                   |
| **Auditability**    | Every calculation run is logged with: run ID, trigger type (CRON / Manual), triggered by (system or user ID), timestamp, month processed, list of schemes run, total SPs processed, per-SP errors and warnings. Manual triggers additionally log the Admin's user ID. Activation call feed data used in each run is traceable via the stored ingestion snapshot tied to the run ID. Logs retained in full for 3 months; summary retained for 12 months.                                                                                                                                                                                                                                                                          |
| **Observability**   | Failed CRON runs must emit an alert to Admin within ≤ 2 minutes of failure. Target Engine API failures must be logged with full request/response detail for debugging. Dead-letter queue must capture BullMQ jobs that exhaust retries, with sufficient metadata to replay them manually.                                                                                                                                                                                                                                                                                                                                                                                                                                        |

# Infrastructure Requirements

1. ## Application Server

| Parameter               | Description                                                                                                                                                                                                                                                |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Runtime Environment** | Node.js 18 LTS                                                                                                                                                                                                                                             |
| **Deployment Mode**     | Incentive module deployed within the existing ws2targetsales Kubernetes deployment. API routes served by the existing API pod. Calculation workers run as a **separate dedicated Worker pod** (ws2targetsales-incentive-worker) within the same namespace. |
| **Service Name**        | ws2targetsales (unchanged — incentive routes are added to this existing service)                                                                                                                                                                           |
| **API Base Paths**      | Incentive APIs are mounted on the existing ws2targetsales API server: /api/incentives/v1/\* for slab management, calculation triggers, and admin config. Feed webhook endpoints: /incentive/v1/feeds/\*                                                    |
| **Communication**       | Internal cluster ingress via Closio gateway                                                                                                                                                                                                                |
| **Concurrency Model**   | Stateless API service; horizontally scalable via replica count / HPA. Calculation workers run as separate deployments, scaled independently                                                                                                                |
| **Logging**             | Structured JSON logs via Winston → central logging pipeline                                                                                                                                                                                                |
| **Health Checks**       | Liveness & readiness probes at /v1/health-checker                                                                                                                                                                                                          |
| **Error Handling**      | Centralized middleware for error normalization and structured logs                                                                                                                                                                                         |

2. ## Database

| Parameter          | Description                                                                                                                                                                                                                                              |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Engine             | PostgreSQL 14+ (shared with ws2targetsales)                                                                                                                                                                                                              |
| Database Name      | Same DB as ws2targetsales (existing). Incentive tables are created in a dedicated incentive schema within this database for logical isolation.                                                                                                           |
| Deployment         | No new DB deployment. Incentive tables are migrated into the existing ws2targetsales database via schema-namespaced migrations.                                                                                                                          |
| Schema Management  | Migration-based (no direct DDL). Incentive migrations are namespaced under the incentive schema and co-located in the ws2targetsales repository migration folder. Migration files are prefixed incentive\_ to distinguish from target engine migrations. |
| Connection Pooling | Shared pg-pool / Sequelize connection pool from the existing ws2targetsales service. No new pool instantiated.                                                                                                                                           |
| Backup & Retention | Inherits existing ws2targetsales database backup policy (daily snapshot, 30-day rolling retention).                                                                                                                                                      |
| Constraints        | Same as before — unique constraints on slab configurations, composite unique keys, calculation run log retention.                                                                                                                                        |

3. ## BullMQ / Redis (Calculation Job Processing)
   1. ### BullMQ

| Parameter          | Description                                                                                                                                                                                                                                                                                                                                                                                                         |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Usage**          | Job queue for incentive calculation runs. CRON-triggered and manual-triggered calculation jobs are dispatched as BullMQ jobs. Each incentive type per calculation run is processed as an individual job to allow parallel execution and per-type failure isolation                                                                                                                                                  |
| **Deployment**     | Redis-backed BullMQ workers deployed as a separate Kubernetes Deployment, scaling independently from the API server                                                                                                                                                                                                                                                                                                 |
| **Persistence**    | Redis with AOF persistence enabled, ensures queued jobs survive pod restarts                                                                                                                                                                                                                                                                                                                                        |
| **Job Types**      | One job type per incentive scheme, dispatched by the Calculation CRON (2nd) or Catch-up CRON (4th) directly into the scheme's dedicated queue. Each job processes both SP and SPV sequentially within the same execution. Job types: call_plan_job, unique_transacting_customers_job, **jot_range_products_job, jot_single_product_job,** weekly_revenue_job, monthly_revenue_job, ageing_job, activation_call_job. |
| **Retry Strategy** | Exponential backoff with max 3 retries for transient failures (Target Engine API errors, DB timeouts). Non-retryable failures (missing data feed, invalid slab config) are failed immediately and logged                                                                                                                                                                                                            |
| **Concurrency**    | **8** dedicated queues, one per scheme. Each queue has a single worker with concurrency 1\. All **8** scheme jobs run in parallel with each other — schemes are isolated and do not block one another. SP and SPV are processed sequentially within each scheme job.                                                                                                                                                |
| **Dead Letter**    | Failed jobs after max retries are moved to a dead-letter queue; Admin alert is triggered                                                                                                                                                                                                                                                                                                                            |
| **Job Isolation**  | Each incentive type calculation runs as an isolated job. A failure in JOT Range computation does not block Ageing or Activation Call computation in the same run                                                                                                                                                                                                                                                    |

2.  ### BullMQ Queue Configuration

| Queue                              | Purpose                                                                                                                                                                                                                                                                                                                                                   |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| call-plan-queue                    | Receives the call plan incentive calculation job. One job per run, enqueued by the Calculation CRON (2nd) or Catch-up CRON (4th). Processes SP and SPV sequentially in the same job.                                                                                                                                                                      |
| unique-transacting-customers-queue | Receives the unique transacting customers incentive calculation job. One job per run. Processes SP and SPV sequentially.                                                                                                                                                                                                                                  |
| weekly-revenue-queue               | Receives the weekly revenue incentive calculation job. One job per run. Processes SP and SPV sequentially.                                                                                                                                                                                                                                                |
| monthly-revenue-queue              | Receives the monthly revenue incentive calculation job. One job per run. Processes SP and SPV sequentially.                                                                                                                                                                                                                                               |
| ageing-queue                       | Receives the ageing incentive calculation job. One job per run. Processes SP and SPV sequentially.                                                                                                                                                                                                                                                        |
| activation-call-queue              | Receives the activation call incentive calculation job. One job per run. Processes SP and SPV sequentially.                                                                                                                                                                                                                                               |
| jot-range-products-queue           | Receives the JOT Range Products incentive calculation job. One job per run. Processes SP (SMO) and SPV sequentially.                                                                                                                                                                                                                                      |
| jot-single-product-queue           | Receives the JOT for Single Product incentive calculation job. One job per run. Processes SP (STO, SFT) and SPV sequentially.                                                                                                                                                                                                                             |
| incentive-dlq                      | Dead Letter Queue. Receives jobs that have exhausted all retries. Triggers an Admin alert on any new entry.                                                                                                                                                                                                                                               |
| feed-ingestion-queue               | Receives feed ingestion jobs for Ageing and Activation Call feed uploads. One job per file. The worker streams the full file from S3 sequentially and bulk inserts rows in batches of FEED_CHUNK_SIZE.                                                                                                                                                    |
| Calculation CRON                   | System-managed standalone Node.js cron process. Configurable day-of-month and time stored in the env and in case data is missing email alerts will be sent in this CRON.                                                                                                                                                                                  |
| Catch-up CRON                      | System-managed standalone Node.js cron process. Runs on the 4th. Queries incentive_run_log to identify schemes not successfully calculated on the 2nd. Runs gate checks for those schemes only. Enqueues missing scheme jobs into their dedicated queues. Not BullMQ-backed for the CRON scheduler — uses existing BullMQ scheme queues for job dispatch. |

3.  ### BullMQ Workers

Scheme Calculation Worker \- A single BullMQ worker subscribed to all 8 scheme queues, with concurrency 1 per queue. Fetches SP/SPV data from Redis (calls API if cache miss), calculates SP incentives and bulk writes SP results, then calculates SPV incentives using SP results and bulk writes SPV results, and updates incentive_run_log on completion. All 8 scheme jobs run in parallel across queues and are fully isolated from each other.

| Worker                    | Responsibility                                                                                                                                                                                                                                                                                                                                        |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Scheme Calculation Worker | Single BullMQ worker subscribed to call-plan-queue, unique-transacting-customers-queue, weekly-revenue-queue, monthly-revenue-queue, ageing-queue, jot-range-products-queue, jot-single-product-queue and activation-call-queue. Concurrency 1 per queue. Picks up one job per queue at a time and processes SP and SPV sequentially within each job. |

Feed Ingestion Worker — multiple instances, count configurable via FEED_INGESTION_WORKER_COUNT.

| Worker                | Responsibility                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Feed Ingestion Worker | Processes one feed ingestion job at a time. Issues a full S3 GetObjectCommand against s3_bucket and s3_key, wraps the response in readline, streams rows sequentially without buffering the full file in memory, validates each row, and bulk inserts valid rows in batches of FEED_CHUNK_SIZE into ageing_activity or activation_activity via INSERT ... ON CONFLICT DO NOTHING. Updates feed_webhook_log status to 'success' on completion or 'failed' on exhausted retries. S3 NoSuchKey errors fail immediately without retry. Transient S3 errors follow standard BullMQ exponential backoff. |

**Scale Strategy**

All incentive workers (8 Scheme Calculation Workers, Feed Ingestion Processor) run exclusively in the ws2targetsales-incentive-worker pod. This pod is separate from the API pod and is sized for compute-heavy workloads. The API pod contains zero worker registrations for incentive queues — it only enqueues jobs via BullMQ. Single worker instance subscribed to all 8 scheme queues. Not horizontally scalable — concurrency is set to 1 per queue by design to prevent duplicate calculation. Feed Ingestion Worker count is independently scalable via FEED_INGESTION_WORKER_COUNT.

**Message Flow (CRON)**

**Calculation CRON (2nd of month):** Fires on the 2nd → performs gate checks (feed receipt, achievement data, slab config) → fetches SP/SPV data and caches in Redis with TTL → enqueues one job per passing scheme into its dedicated queue → each scheme worker picks up its job independently → worker fetches SP/SPV data from Redis (calls API if cache miss) → calculates SP incentives, bulk writes SP results → calculates SPV incentives using SP results, bulk writes SPV results → updates incentive_run_log → all 8 scheme jobs run in parallel, each isolated from the others → results available for reporting.

**Catch-up CRON (4th of month):** Fires on the 4th → queries incentive_run_log to identify which schemes were not successfully calculated on the 2nd → runs gate checks for remaining schemes only → enqueues missing schemes into their dedicated queues → same worker processing flow as above.

**Message Flow (Manual)**

Admin triggers via Admin UI → confirmation dialog acknowledged → gate checks run for the selected scheme → job dispatched into the scheme's dedicated queue with trigger_type \= 'manual' and triggered_by_id \= Admin user ID. Same worker processing flow as CRON from that point onwards.

4. ## External Integrations
   1. ### Qlik Sense (Ageing Data Feed)

| Parameter        | Description                                                                                                                                                                                                                                                                                                                                                                                                            |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Integration Type | Webhook push from Qlik Sense to Incentive Engine at month-end                                                                                                                                                                                                                                                                                                                                                          |
| Feed Format      | CSV file with columns: salesperson_id, month, ar_0_10_days, ar_month_total. Delivered as multipart/form-data                                                                                                                                                                                                                                                                                                           |
| Endpoint         | POST /incentive/v1/feeds/ageing — secured via X-Client-Id and X-Client-Secret                                                                                                                                                                                                                                                                                                                                          |
| Upload Volume    | Up to 60,000 rows per monthly feed                                                                                                                                                                                                                                                                                                                                                                                     |
| Storage          | CSV streamed directly to S3 (S3_FEED_BUCKET, key pattern: ageing/{partner_id}/{year}/{month}/{filename}) during the synchronous accept phase. s3_key, s3_bucket, and filename are recorded in feed_webhook_log. A single BullMQ worker streams the full file from S3 sequentially and bulk-inserts rows in batches of FEED_CHUNK_SIZE into ageing_activity. Each row tagged with feed_webhook_log_id for traceability. |
| Feed Validation  | Pre-run gate queries feed_webhook_log for status \= 'success' for (partner_id, feed_type='ageing', month, year). If absent or not success, Ageing incentive type is skipped with status DATA_UNAVAILABLE and Admin is alerted                                                                                                                                                                                          |
| Failure Handling | Duplicate feed pushes for the same (partner_id, month, year) after a success status are rejected with 409 ALREADY_RECEIVED. Re-send is only permitted if the prior attempt did not reach success (i.e. status is failed or partial)                                                                                                                                                                                    |

2.  ### Task Management (Activation Call Feed)

| Parameter        | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Integration Type | Webhook push from Task Management to Incentive Engine at month-end                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Feed Format      | CSV file with columns: salesperson_id, customer_id, month, year. Delivered as multipart/form-data. Each row represents one unique customer for whom an activation call was made by that salesperson in that month                                                                                                                                                                                                                                                                                                                                 |
| Endpoint         | POST /incentive/v1/feeds/activation-call — secured via X-Client-Id and X-Client-Secret                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Upload Volume    | Up to 60,000 rows per monthly feed                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Storage          | CSV streamed directly to S3 (S3_FEED_BUCKET, key pattern: activation/{partner_id}/{year}/{month}/{filename}) during the synchronous accept phase. s3_key, s3_bucket, and filename are recorded in feed_webhook_log. A single BullMQ worker streams the full file from S3 sequentially and bulk-inserts rows in batches of FEED_CHUNK_SIZE into activation_activity. Deduplication enforced at DB layer via ON CONFLICT DO NOTHING on composite unique index (salesperson_id, customer_id, month, year). Each row tagged with feed_webhook_log_id. |
| Feed Validation  | Pre-run gate queries feed_webhook_log for status \= 'success' for (partner_id, feed_type='activation', month, year). Absent or non-success → Activation Call incentive skipped, Admin alerted                                                                                                                                                                                                                                                                                                                                                     |
| Failure Handling | Duplicate feed pushes after a success status rejected with 409 ALREADY_RECEIVED. Re-send permitted if prior attempt did not reach success                                                                                                                                                                                                                                                                                                                                                                                                         |

3.  ### Salesperson / Hierarchy API

| Parameter          | Description                                                                                 |
| ------------------ | ------------------------------------------------------------------------------------------- |
| **Usage**          | Fetched at calculation run time to resolve salesperson types, supervisor-reporter hierarchy |
| **Authentication** | X-Client-Id and X-Client-Secret                                                             |

5. ## Environment Configuration

| Variable                                        | Purpose                                                                                                                                                                                                                                                       |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD | Database connection details. Shared with ws2targetsales — no new DB credentials required. Incentive tables are accessed via the incentive schema prefix (e.g. incentive.feed_webhook_log). Implement connection pool for performance and resource management. |
| REDIS_URL                                       | Redis connection string for BullMQ                                                                                                                                                                                                                            |
| BULLMQ_WORKER_COUNT                             | Number of workers for incentive type processor queues (SP and SPV). Default: 2\. Each worker processes one job at a time.                                                                                                                                     |
| BULLMQ_MAX_RETRIES                              | Max retry attempts for failed jobs (default: 3\)                                                                                                                                                                                                              |
| TARGET_ENGINE_BASE_URL                          | Base URL for ws2targetsales S2S API calls                                                                                                                                                                                                                     |
| TARGET_ENGINE_CLIENT_ID                         | Client ID for Target Engine S2S auth                                                                                                                                                                                                                          |
| TARGET_ENGINE_CLIENT_SECRET                     | Client secret for Target Engine S2S auth                                                                                                                                                                                                                      |
| SALESPERSON_API_BASE_URL                        | Base URL for salesperson/hierarchy API                                                                                                                                                                                                                        |
| SALESPERSON_API_CLIENT_ID                       | Client ID for Salesperson API auth                                                                                                                                                                                                                            |
| SALESPERSON_API_CLIENT_SECRET                   | Client secret for Salesperson API auth                                                                                                                                                                                                                        |
| SERVICE_CREDENTIALS                             | JSON array of allowed inbound S2S clients: \[ { "client_id": "ws1-closio", "client_secret": "\<secret\>" }, { "client_id": "qlik-sense", "client_secret": "\<secret\>" }, { "client_id": "task-management", "client_secret": "\<secret\>" } \]                |
| CRON_DEFAULT_DAY                                | Default day of month for automatic calculation CRON (default: 2\)                                                                                                                                                                                             |
| CRON_DEFAULT_TIME                               | Default time for CRON run in HH:MM UTC                                                                                                                                                                                                                        |
| CATCHUP_CRON_DAY                                | Day of month for Catch-up CRON. Default: 4\.                                                                                                                                                                                                                  |
| CATCHUP_CRON_TIME                               | Time (HH:MM UTC) for the Catch-up CRON to fire.                                                                                                                                                                                                               |
| LOG_LEVEL                                       | Log verbosity                                                                                                                                                                                                                                                 |
| NODE_ENV                                        | Environment (development / staging / production)                                                                                                                                                                                                              |
| MAX_CALCULATION_RUN_TIME_MINUTES                | Hard timeout for a single calculation run before abort (default: 15\)                                                                                                                                                                                         |
| FEED_INGESTION_WORKER_COUNT                     | Number of parallel workers subscribed to feed-ingestion-queue. Default: 1\. One job per file — increasing this allows concurrent processing of multiple feed files across different partners simultaneously.                                                  |
| FEED_CHUNK_SIZE                                 | Number of rows per DB bulk insert batch within the sequential streaming worker. Default: 1000\. Increasing this reduces DB round trips but increases peak batch memory slightly.                                                                              |
| AWS_REGION                                      | AWS region for S3 client (e.g. ap-southeast-1)                                                                                                                                                                                                                |
| AWS_ACCESS_KEY_ID                               | IAM access key for S3 operations. In production, use IAM role attached to the pod (IRSA) instead of key-based auth.                                                                                                                                           |
| AWS_SECRET_ACCESS_KEY                           | IAM secret key for S3 operations. Not required if using IRSA/pod identity.                                                                                                                                                                                    |
| S3_ARCHIVE_BUCKET                               | Target S3 bucket name for feed archival (e.g. japfa-incentive-archive)                                                                                                                                                                                        |
| S3_ARCHIVE_PATH_PREFIX                          | Optional prefix to prepend to all S3 keys. Defaults to empty string. Useful for environment segregation (e.g. dev/, staging/).                                                                                                                                |
| SMTP_HOST                                       | SMTP server hostname                                                                                                                                                                                                                                          |
| SMTP_PORT                                       | SMTP server port (typically 587 for STARTTLS, 465 for SMTPS)                                                                                                                                                                                                  |
| SMTP_SECURE                                     | Boolean. true for SMTPS (port 465), false for STARTTLS (port 587\)                                                                                                                                                                                            |
| SMTP_USER                                       | SMTP authentication username                                                                                                                                                                                                                                  |
| SMTP_PASSWORD                                   | SMTP authentication password                                                                                                                                                                                                                                  |
| SMTP_FROM_ADDRESS                               | Sender email address for all alert emails                                                                                                                                                                                                                     |
| SMTP_ALERT_RECIPIENTS                           | Comma-separated list of Admin email addresses to receive all system alerts                                                                                                                                                                                    |
| S3_FEED_BUCKET                                  | S3 bucket for incoming raw feed CSV files (e.g. japfa-incentive-feeds). Separate from S3_ARCHIVE_BUCKET to allow independent lifecycle policies.                                                                                                              |
| S3_FEED_PATH_PREFIX                             | Optional prefix for all feed CSV S3 keys. Defaults to empty string. Useful for environment segregation (e.g. dev/, staging/).                                                                                                                                 |

6. ## Networking & Security

| Parameter                     | Description                                                                                                                                                                                                                                                                                                                                                                                                              |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Ingress Routing**           | /incentive/\* routed via Closio gateway                                                                                                                                                                                                                                                                                                                                                                                  |
| **Authentication — Inbound**  | Inbound S2S authentication for feed webhooks (Qlik Sense, Task Management) and ws-1 API calls is handled via verifyClientAuth middleware, which validates x-client-id and x-client-secret against the SERVICE_CREDENTIALS credential map (JSON array in env). Each caller is registered as a named entry in this map.                                                                                                    |
| **Authentication — Outbound** | X-Client-Id and X-Client-Secret for all calls to Target Engine and Salesperson API                                                                                                                                                                                                                                                                                                                                       |
| **Authorization**             | Role-based access: Admin (full access — CRON config, manual trigger, multiplier config, slab management); Sales Manager (slab view, create, edit within period rules only)                                                                                                                                                                                                                                               |
| **Secrets Management**        | Kubernetes Secrets (encrypted at rest) for DB credentials, Redis URL, Target Engine credentials, Salesperson API credentials,SERVICE_CREDENTIALS, AWS S3 credentials (or IRSA pod identity in production), and SMTP credentials. AWS IAM Role for Service Accounts (IRSA) is the preferred mechanism for S3 access in production — explicit AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY vars are only used in dev/staging. |
| **Rate Limiting**             | API rate limiting at gateway level for inbound feed webhooks to prevent accidental bulk pushes                                                                                                                                                                                                                                                                                                                           |
| **Data Encryption**           | TLS 1.2+ for all outbound API calls; persistent volume encryption at rest for Redis and Postgres                                                                                                                                                                                                                                                                                                                         |

7. ## Object Storage (S3 — Feed Archival)

| Parameter                  | Description                                                                                                                                                                                                           |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Provider**               | AWS S3                                                                                                                                                                                                                |
| **Bucket Name**            | japfa-incentive-archive                                                                                                                                                                                               |
| **Purpose**                | Cold storage for archived ageing and activation call feed records. Data is moved here from the primary DB after incentive calculation is confirmed successful and the bucket period is older than 2 completed months. |
| **Access Pattern**         | Write-only from the Incentive Engine during archival jobs. Read access reserved for Admin audit/recovery scenarios only.                                                                                              |
| **Path Convention**        | /{feed_type}/{partner_id}/{year}/{month}/{filename} — Example: /ageing_feed/partner-japfa-b2/2025/08/ageing_feed_2025_08.json                                                                                         |
| **File Format**            | Structured JSON documents, one file per (partner_id, feed_type, year, month) bucket                                                                                                                                   |
| **Versioning**             | Disabled — each bucket key is unique by design (one file per period per partner per feed type). feed_archive_log is the source of truth; S3 versioning is not relied upon                                             |
| **Encryption**             | Server-side encryption (SSE-S3 or SSE-KMS) enabled on the bucket                                                                                                                                                      |
| **Access Control**         | Bucket policy restricted to the Incentive Engine's IAM role (least privilege). No public access.                                                                                                                      |
| **Upload Acknowledgement** | S3 ETag returned on successful PutObject is recorded in feed_archive_log.s3_key. DB deletion proceeds only after this confirmation.                                                                                   |
| **Failure Behaviour**      | Any S3 SDK error (timeout, permission denied, service unavailable) causes the archival job to abort for that bucket without touching the DB. The BullMQ retry strategy handles re-attempts with exponential backoff.  |

8. ## Object Storage (S3 \--- Feed Ingestion)

| Parameter                  | Description                                                                                                                                                                                                                                                                                                                                                                                             |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Provider**               | AWS S3                                                                                                                                                                                                                                                                                                                                                                                                  |
| **Bucket Name**            | japfa-incentive-feeds (configured via S3_FEED_BUCKET)                                                                                                                                                                                                                                                                                                                                                   |
| **Purpose**                | Durable storage for raw incoming CSV files from Qlik Sense (ageing) and Task Management (activation call). Files are uploaded synchronously during the webhook accept phase (Phase 1\) before any DB record is written or BullMQ jobs are enqueued. Files are retained per S3 lifecycle policy for audit and re-ingestion support.                                                                      |
| **Access Pattern**         | Write-once during Phase 1 accept (API pod). Read via full sequential stream by a single BullMQ worker per file (Worker pod). No application-level deletion.                                                                                                                                                                                                                                             |
| **Path Convention**        | {S3_FEED_PATH_PREFIX}{feed_type}/{partner_id}/{year}/{month}/{filename} — Example: ageing/partner-japfa-b2/2025/4/ageing_feed_2025_04.csv                                                                                                                                                                                                                                                               |
| **File Format**            | Raw CSV as uploaded by the caller. No transformation at ingestion time.                                                                                                                                                                                                                                                                                                                                 |
| **Versioning**             | Disabled. Key is deterministic per (partner_id, feed_type, year, month, filename). feed_webhook_log is the source of truth.                                                                                                                                                                                                                                                                             |
| **Encryption**             | Server-side encryption (SSE-S3 or SSE-KMS) enabled on the bucket.                                                                                                                                                                                                                                                                                                                                       |
| **Access Control**         | Bucket policy restricted to the Incentive Engine's IAM role (least privilege). No public access.                                                                                                                                                                                                                                                                                                        |
| **Upload Acknowledgement** | S3 PutObject must return a confirmed ETag before the feed_webhook_log record is inserted. If the S3 upload fails, the request returns 500 FEED_UPLOAD_FAILED and no DB state is written.                                                                                                                                                                                                                |
| **Failure Behaviour**      | S3 upload failure in Phase 1 is a hard failure — return 500 FEED_UPLOAD_FAILED, do not insert DB record, do not enqueue job. S3 NoSuchKey error in the Phase 2 worker is non-retryable — write S3_OBJECT_NOT_FOUND to error_details, set feed_webhook_log status to 'failed', and fail the job immediately. Transient S3 errors (SlowDown, network timeout) follow standard BullMQ exponential backoff. |
| **Lifecycle Policy**       | Configure an S3 lifecycle rule on S3_FEED_BUCKET to expire objects after the defined retention period (minimum 6 months). No application-level deletion is performed.                                                                                                                                                                                                                                   |

9. ## SMTP (Alert Notifications)

| Parameter          | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Purpose**        | Transactional alert emails dispatched to Admin when system events require human attention. This is the delivery mechanism for all "Admin shall be alerted" events defined throughout this spec.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| **Transport**      | SMTP over TLS (STARTTLS or SMTPS on port 587/465)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| **Provider**       | Configured via environment variables — provider-agnostic. Compatible with SendGrid, AWS SES, or internal SMTP relay per Closio standard.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| **Sender Address** | Configurable via SMTP_FROM_ADDRESS env variable (e.g. incentive-engine@japfa.com)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| **Recipients**     | Admin alert recipient list configurable via SMTP_ALERT_RECIPIENTS env variable (comma-separated). Not stored in DB — this is infrastructure config, not application config.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| **Alert Events**   | All events that dispatch an alert to Admin: (1) Calculation CRON gate check — missing Ageing or Activation Call feed for any partner; (2) Calculation CRON gate check — Target Engine T3/T4/T5/T6 API unavailable for any partner; (3) Catch-up CRON gate check — same feed/achievement checks for remaining schemes on the 4th; (4) Calculation CRON not triggered on scheduled day; (5) Calculation run failed or aborted (feed gate failure, data unavailable); (6) Any incentive type job in DATA_UNAVAILABLE status; (7) BullMQ dead-letter queue receives a new job (feed ingestion or calculation); (8) Worker crashes or zero active workers detected; (9) DB/Redis connectivity issues; (10) S3 archival job failure after max retries |
| **Retry**          | nodemailer SMTP transport handles connection-level retries internally. Application-level: if the SMTP dispatch itself fails (not the alert condition), the failure is logged to Datadog with severity ERROR but does not cause the triggering job to fail. Alert delivery is best-effort, not transactional.                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| **Health Check**   | SMTP connectivity is verified during pre-deployment checks (see Deployment and CI/CD).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

10. ## Deployment and CI/CD

| Parameter             | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Repository            | ws2targetsales (GitLab) — Incentive module is co-located in the existing repository. Incentive source code lives under src/incentive/. Incentive worker entry point is a separate process file (e.g. src/incentive/worker.ts) used as the container CMD for the incentive worker pod.                                                                                                                                                                                           |
| Build Pipeline        | Jenkins → Docker build → K8s deployment                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Branch Policy         | main \= production, develop \= development                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Deployment Strategy   | API pod: Rolling update (unchanged from existing ws2targetsales strategy). Incentive Worker pod (ws2targetsales-incentive-worker): **Recreate strategy** to prevent duplicate CRON registration and avoid two instances of the Run Orchestrator running concurrently.                                                                                                                                                                                                           |
| DB Migration          | Automatic in CI/CD before app startup — migrations for incentive tables run in the same migration pipeline as target tables                                                                                                                                                                                                                                                                                                                                                     |
| Worker Deployment     | A dedicated Kubernetes Deployment (ws2targetsales-incentive-worker) runs the incentive BullMQ workers as a **separate pod** from the API server. This pod uses the same Docker image as the API pod but a different CMD (node dist/incentive/worker.js). The worker pod is not in the request path and can be sized independently (CPU/memory) for heavy calculation workloads. The API pod does **not** run any incentive workers — it only enqueues jobs.                     |
| Versioning            | Semantic versioning (v1.x.x)                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Rollback Plan         | K8s rollback to previous deployment revision; DB migration rollback scripts maintained. On failed calculation run — system rolls back to previous month's results (BullMQ job-level rollback); no pod-level rollback required for calculation logic                                                                                                                                                                                                                             |
| Pre-deployment Checks | Verify Redis connectivity; verify Target Engine S2S credentials resolve; verify DB migration scripts complete cleanly; verify CRON job registration does not duplicate; verify S3 bucket reachability and write permissions using a probe PutObject call on startup (non-blocking — logs a warning on failure but does not abort startup); verify SMTP connectivity using nodemailer.verify() on startup (non-blocking — logs a warning on failure but does not abort startup). |

11. ## Observability & Monitoring

| Parameter         | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Metrics**       | Datadog metrics: API latency, BullMQ queue depth, worker job failures, calculation run duration, per-incentive-type processing time, data feed receipt status per month, slab config changes per day                                                                                                                                                                                                                                                                                                                                                                                                                 |
| **Logs**          | Structured JSON logs with correlation IDs (including run_id on all calculation-related logs) shipped to Datadog Logs; separate log streams for API, BullMQ workers, Target Engine fetch, feed ingestion                                                                                                                                                                                                                                                                                                                                                                                                              |
| **Tracing**       | Datadog APM (distributed traces across API → BullMQ → worker → Target Engine fetch → DB write)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| **Alerts**        | Catch-up CRON not triggered on the 4th; Calculation CRON gate check failure — missing feed per feed type per partner; Calculation CRON gate check failure — achievement data unavailable per target type per partner; BullMQ dead-letter queue size \> 0; Target Engine fetch failure rate \> 0; worker crashes or zero active workers; DB/Redis connectivity issuesSMTP dispatch failure (alert email could not be delivered — severity ERROR, does not cascade to job failure); S3 archival job failure after max retries (with partner_id, feed_type, period detail); S3 upload latency \> 30 seconds per bucket. |
| **Health Checks** | Liveness probe: Redis TCP connection check every 30s. Readiness probe: verify DB connection pool is healthy and BullMQ queues are reachable                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

# Data Model Design

The following table is part of the **Target Sales**. It is created and maintained by the Target Sales Engine and consumed by the Incentive Engine for achievement calculation.

Note: JOT incentive calculation related schemas are still pending for both JOT Range Products and JOT for Single Product.

| Category                                     | Tables                                                                              |
| -------------------------------------------- | ----------------------------------------------------------------------------------- |
| Scheme & Slab Tables                         | incentive_schemas, incentive_payout_slabs, incentive_range_payout_slabs             |
| Run & Result Tables                          | incentive_run_log, incentive_results, incentive_result_references                   |
| Feed & Activity Tables                       | feed_webhook_log, ageing_activity, activation_activity, feed_archive_log            |
| Admin Tables                                 | salesperson_type_multiplier                                                         |
| Ageing Incentive Tables                      | ageing_incentive_spv, ageing_incentive_reference                                    |
| Activation Incentive Tables                  | activation_incentive_sp, activation_incentive_spv, activation_incentive_reference   |
| Call Plan Incentive Tables                   | call_plan_incentive_sp, call_plan_incentive_spv                                     |
| Weekly Revenue Incentive Tables              | weekly_payout_incentive_sp, weekly_payout_incentive_spv                             |
| Monthly Revenue Incentive Tables             | monthly_revenue_incentive_spv                                                       |
| Unique Transacting Customer Incentive Tables | unique_transacting_customer_incentive_sp, unique_transacting_customer_incentive_spv |

## Scheme & Slab Tables

### incentive_schemas

Predefined incentive scheme definitions for Business 2\. The 7 incentive types are seeded at system setup and are not user-managed.

| CREATE TABLE incentive_schemas ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), schema_name VARCHAR(100) NOT NULL, description TEXT, partner_id UUID NOT NULL, slab_structure VARCHAR(20) NOT NULL, allowed_slab_types VARCHAR(10)\[\] NOT NULL, applicable_salesperson_types VARCHAR(10)\[\] NOT NULL, applicable_supervisor_types VARCHAR(50)\[\] NOT NULL, supervisor_has_target BOOLEAN NOT NULL DEFAULT FALSE, salesperson_has_target BOOLEAN NOT NULL DEFAULT FALSE, supervisor_has_own BOOLEAN NOT NULL DEFAULT FALSE, target_source_id UUID, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT chk_slab_structure CHECK ( slab_structure IN ('threshold', 'range') ), CONSTRAINT chk_allowed_slab_types_not_empty CHECK ( array_length(allowed_slab_types, 1) \> 0 ),  CONSTRAINT uq_schema_partner UNIQUE (schema_name, partner_id)); |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE UNIQUE INDEX idx_incentive_schemas_name_partner ON incentive_schemas(schema_name, partner_id);CREATE INDEX idx_incentive_schemas_partner_id ON incentive_schemas(partner_id); |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Seed data

| INSERT INTO incentive_schemas ( schema_name, description, partner_id, slab_structure, allowed_slab_types, applicable_salesperson_types, applicable_supervisor_types, salesperson_has_target, supervisor_has_target, supervisor_has_own, target_source_id) VALUES ('call_plan', 'Daily call plan completion incentive, summed monthly', :partner_id, 'threshold', ARRAY\['value', 'percentage'\], ARRAY\['STO', 'SFT'\], ARRAY\['SPV'\], TRUE, FALSE, FALSE, 'T3'), ('unique_transacting_customers', 'Monthly count of customers with net sales \> 0', :partner_id, 'threshold', ARRAY\['value', 'percentage'\], ARRAY\['STO', 'SFT'\], ARRAY\['SPV'\], TRUE, FALSE, TRUE, 'T4'), ('jot_range_products', 'Customers per JOT product-group range, monthly', :partner_id, 'range', ARRAY\['value'\], ARRAY\['SMO'\], ARRAY\['SPV'\], FALSE, FALSE, FALSE, NULL), ('jot_single_product', 'Customers per distinct product count range, monthly', :partner_id, 'range', ARRAY\['value'\], ARRAY\['STO', 'SFT'\], ARRAY\['SPV'\], FALSE, FALSE, FALSE, NULL), ('weekly_revenue', 'Net revenue vs weekly target, summed monthly', :partner_id, 'threshold', ARRAY\['value', 'percentage'\], ARRAY\['STO', 'SFT', 'SMO'\], ARRAY\['SPV'\], TRUE, TRUE, TRUE, 'T6'), ('monthly_revenue', 'Cumulative net revenue vs monthly target', :partner_id, 'threshold', ARRAY\['value', 'percentage'\], ARRAY\['STO', 'SFT', 'SMO'\], ARRAY\['SPV'\], TRUE, TRUE, TRUE, 'T5'), ('ageing', 'AR (0\-10 days) / Total AR percentage at month-end', :partner_id, 'threshold', ARRAY\['percentage'\], ARRAY\['STO', 'SFT', 'SMO'\], ARRAY\['SPV'\], FALSE, FALSE, TRUE, NULL), ('activation_call', 'Qualified activated customers with 3\-month sales lookback', :partner_id, 'threshold', ARRAY\['value', 'percentage'\], ARRAY\['STO',\], ARRAY\['SPV'\], FALSE, FALSE, FALSE, NULL); |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

### incentive_schema_configs

Stores the period-bound configuration header for each incentive schema, defining the validity window under which the associated slab rows are grouped and applied.

| CREATE TABLE incentive_schema_configs ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), schema_id UUID NOT NULL, valid_from TIMESTAMPTZ NOT NULL, valid_to TIMESTAMPTZ NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'active', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), created_by UUID, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_by UUID, created_by_name VARCHAR(200),  updated_by_name VARCHAR(200), CONSTRAINT fk_isc_schema FOREIGN KEY (schema_id) REFERENCES incentive_schemas(id) ON DELETE RESTRICT, CONSTRAINT chk_isc_period_order CHECK ( valid_to \> valid_from ), CONSTRAINT chk_isc_status CHECK ( status IN ('active', 'inactive') )); |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

Indexes

| CREATE INDEX idx_isc_schema_id ON incentive_schema_configs(schema_id);CREATE INDEX idx_isc_period ON incentive_schema_configs(schema_id, valid_from, valid_to);CREATE INDEX idx_isc_active ON incentive_schema_configs(schema_id, status) WHERE status \= 'active'; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

### incentive_payout_slabs

Stores the individual slab rows for each incentive schema, scoped to a validity period and salesperson type

| CREATE TABLE incentive_payout_slabs ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), schema_id UUID NOT NULL, schema_config_id UUID NOT NULL, salesperson_type VARCHAR(20) NOT NULL, slab_type VARCHAR(15) NOT NULL, symbol VARCHAR(5) NOT NULL, threshold NUMERIC(15, 4) NOT NULL, payout_amount NUMERIC(15, 2) NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'active', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), created_by UUID, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_by UUID, CONSTRAINT fk_ips_schema FOREIGN KEY (schema_id) REFERENCES incentive_schemas(id) ON DELETE RESTRICT, CONSTRAINT fk_ips_schema_config FOREIGN KEY (schema_config_id) REFERENCES incentive_schema_configs(id) ON DELETE RESTRICT, ~~CONSTRAINT chk_ips_salesperson_type CHECK ( salesperson_type IN ('STO', 'SFT', 'SMO', 'SMF', 'SPV DRY', 'SPV FTO', 'SPV MIX', 'SPV MO') ),~~ CONSTRAINT chk_ips_slab_type CHECK ( slab_type IN ('value', 'percentage') ), CONSTRAINT chk_ips_symbol CHECK ( symbol IN ('gte', 'gt', 'eq') ), CONSTRAINT chk_ips_threshold_positive CHECK (threshold \> 0), CONSTRAINT chk_ips_payout_positive CHECK (payout_amount \> 0), CONSTRAINT chk_ips_status CHECK ( status IN ('active', 'deprecated') ),); |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE UNIQUE INDEX uq_ips_active_slab_row ON incentive_payout_slabs ( schema_config_id, salesperson_type, slab_type, symbol, threshold ) WHERE status \= 'active'; CREATE INDEX idx_ips_schema_id ON incentive_payout_slabs(schema_id);CREATE INDEX idx_ips_schema_config_id ON incentive_payout_slabs(schema_config_id);CREATE INDEX idx_ips_schema_sp_type ON incentive_payout_slabs(schema_id, salesperson_type);CREATE INDEX idx_ips_active ON incentive_payout_slabs(schema_config_id, salesperson_type, status) WHERE status \= 'active'; |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

### incentive_range_payout_slabs

Stores the JOT Range product group slab configuration, where each row represents one threshold band within a range, breaking the traditional Low/Mid/High into individual rows.

| CREATE TABLE incentive_range_payout_slabs ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), schema_id UUID NOT NULL, schema_config_id UUID NOT NULL, range_start INTEGER NOT NULL, range_end INTEGER, threshold_start NUMERIC(15, 4) NOT NULL, threshold_end NUMERIC(15, 4) NOT NULL, salesperson_type VARCHAR(20) NOT NULL, payout_amount NUMERIC(15, 2) NOT NULL, slab_type VARCHAR(15) NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'active', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), created_by UUID, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_by UUID, CONSTRAINT fk_irps_schema FOREIGN KEY (schema_id) REFERENCES incentive_schemas(id) ON DELETE RESTRICT, CONSTRAINT fk_irps_schema_config FOREIGN KEY (schema_config_id) REFERENCES incentive_schema_configs(id) ON DELETE RESTRICT, CONSTRAINT chk_irps_range_order CHECK ( range_end IS NULL OR range_end \> range_start ), CONSTRAINT chk_irps_threshold_order CHECK ( threshold_end \> threshold_start ), ~~CONSTRAINT chk_irps_salesperson_type CHECK ( salesperson_type IN ('STO', 'SFT', 'SMO', 'SPV DRY', 'SPV FTO', 'SPV MIX', 'SPV MO') ),~~ CONSTRAINT chk_irps_slab_type CHECK ( slab_type IN ('value', 'percentage') ), CONSTRAINT chk_irps_payout_positive CHECK (payout_amount \> 0), CONSTRAINT chk_irps_status CHECK ( status IN ('active', 'inactive') )); |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_irps_schema_id ON incentive_range_payout_slabs(schema_id);CREATE INDEX idx_irps_schema_config_id ON incentive_range_payout_slabs(schema_config_id);CREATE INDEX idx_irps_schema_sp_type ON incentive_range_payout_slabs(schema_config_id, salesperson_type);CREATE INDEX idx_irps_active ON incentive_range_payout_slabs(schema_config_id, salesperson_type, status) WHERE status \= 'active';CREATE INDEX idx_irps_range ON incentive_range_payout_slabs(schema_config_id, range_start, range_end); |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

## Run & Result Tables

### incentive_run_log

Tracks each incentive calculation run per schema and partner, including trigger source, processing counts, and final status.

| CREATE TABLE incentive_run_log ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), schema_id UUID NOT NULL, partner_id UUID NOT NULL, month SMALLINT NOT NULL, year SMALLINT NOT NULL, triggered_by VARCHAR(50) NOT NULL, triggered_by_id UUID, status VARCHAR(20) NOT NULL DEFAULT 'pending', total INTEGER NOT NULL DEFAULT 0, processed INTEGER NOT NULL DEFAULT 0, failed INTEGER NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), completed_at TIMESTAMPTZ, CONSTRAINT fk_irl_schema FOREIGN KEY (schema_id) REFERENCES incentive_schemas(id) ON DELETE RESTRICT, CONSTRAINT chk_irl_triggered_by CHECK ( triggered_by IN ('CRON', 'MANUAL') ), CONSTRAINT chk_irl_status CHECK ( status IN ('processing', 'pending', 'success', 'failed', 'partial') )); |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_irl_schema_id ON incentive_run_log(schema_id);CREATE INDEX idx_irl_partner_id ON incentive_run_log(partner_id);CREATE INDEX idx_irl_partner_period ON incentive_run_log(partner_id, year, month);CREATE INDEX idx_irl_status ON incentive_run_log(status) WHERE status IN ('pending', 'processing'); |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

### incentive_results

Stores the computed incentive output per salesperson or supervisor for a given run, including achievement, matched slab, and payout amount.

| CREATE TABLE incentive_results ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), run_id UUID NOT NULL, incentive_schema_id UUID NOT NULL, partner_id UUID NOT NULL, month SMALLINT NOT NULL, year SMALLINT NOT NULL, salesperson_id UUID NOT NULL, salesperson_name VARCHAR(200) NOT NULL, sp_type VARCHAR(10) NOT NULL, supervisor_id UUID, achievement_value NUMERIC(15, 4), achievement_pecentage NUMERIC(8, 4), slab_id UUID, payout_amount NUMERIC(15, 2), status VARCHAR(20) NOT NULL DEFAULT 'pending', role VARCHAR(10) NOT NULL, is_deprecated BOOLEAN NOT NULL DEFAULT FALSE, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT fk_ir_run FOREIGN KEY (run_id) REFERENCES incentive_run_log(id) ON DELETE RESTRICT, CONSTRAINT fk_ir_schema FOREIGN KEY (incentive_schema_id) REFERENCES incentive_schemas(id) ON DELETE RESTRICT, CONSTRAINT fk_ir_slab FOREIGN KEY (slab_id) REFERENCES incentive_payout_slabs(id) ON DELETE RESTRICT, ~~CONSTRAINT chk_ir_sp_type CHECK ( (role \= 'SP' AND sp_type IN ('STO', 'SFT', 'SMO', 'SMF')) OR (role \= 'SPV' AND sp_type IN ('SPV DRY', 'SPV FGT', 'SPV MO', 'SPV ALL'))~~ CONSTRAINT chk_ir_status CHECK ( status IN ('pending', 'success', 'failed') ), CONSTRAINT chk_ir_role CHECK ( role IN ('SP', 'SPV') )); |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

Indexes

| CREATE INDEX idx_ir_run_id ON incentive_results(run_id);CREATE INDEX idx_ir_schema_id ON incentive_results(incentive_schema_id);CREATE INDEX idx_ir_partner_period ON incentive_results(partner_id, year, month);CREATE INDEX idx_ir_salesperson_id ON incentive_results(salesperson_id);CREATE INDEX idx_ir_supervisor_id ON incentive_results(supervisor_id) WHERE supervisor_id IS NOT NULL;CREATE INDEX idx_ir_role ON incentive_results(role, partner_id, year, month); CREATE INDEX idx_ir_active ON incentive_results(partner_id, year, month, is_deprecated) WHERE is_deprecated \= FALSE; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

### incentive_result_reference

Stores the target and achievement record references linked to each incentive result for auditability and traceability.

| CREATE TABLE incentive_result_reference ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), result_id UUID NOT NULL, target_type_id UUID NOT NULL, achievement_ids UUID\[\] NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT fk_irr_result FOREIGN KEY (result_id) REFERENCES incentive_results(id) ON DELETE RESTRICT); |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_irr_result_id ON incentive_result_reference(result_id);CREATE INDEX idx_irr_target_type_id ON incentive_result_reference(target_type_id); |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------- |

## Feed & Activity Tables

### feed_webhook_log

Tracks incoming data feed webhooks for Ageing and Activation Call incentives, including the S3 location of the uploaded CSV file, processing status, and job-level counts. s3_key and s3_bucket are the durable reference used by BullMQ chunk workers to stream rows from S3. filename is the original filename provided by the upstream caller, retained for audit.

| CREATE TABLE feed_webhook_log ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), partner_id UUID NOT NULL, feed_type VARCHAR(20) NOT NULL, month SMALLINT NOT NULL, year SMALLINT NOT NULL, filename TEXT NOT NULL, s3_bucket TEXT NOT NULL, s3_key TEXT NOT NULL, file_size_bytes BIGINT, total_records INTEGER NOT NULL DEFAULT 0, error_details TEXT, status VARCHAR(20) NOT NULL DEFAULT 'pending', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), created_by UUID, received_at TIMESTAMPTZ, completed_at TIMESTAMPTZ, CONSTRAINT chk_fwl_feed_type CHECK (feed_type IN ('ageing', 'activation')), CONSTRAINT chk_fwl_status CHECK (status IN ('pending', 'processing', 'success', 'failed')), CONSTRAINT uq_fwl_partner_feed_period UNIQUE (partner_id, feed_type, month, year)); |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_fwl_partner_id ON feed_webhook_log(partner_id);CREATE INDEX idx_fwl_feed_type ON feed_webhook_log(feed_type);CREATE INDEX idx_fwl_partner_period ON feed_webhook_log(partner_id, year, month);CREATE INDEX idx_fwl_partner_feed_period ON feed_webhook_log(partner_id, feed_type, year, month);CREATE INDEX idx_fwl_status ON feed_webhook_log(status) WHERE status IN ('pending', 'processing'); |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

### ageing_activity

Stores the raw ageing data received from the Qlik Sense feed, one record per salesperson per month.

| CREATE TABLE ageing_activity ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), feed_webhook_log_id UUID NOT NULL, partner_id UUID NOT NULL, salesperson_id UUID NOT NULL, month SMALLINT NOT NULL, year SMALLINT NOT NULL, ar_10 NUMERIC(15, 2\) NOT NULL, month_total NUMERIC(15, 2\) NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT fk_aa_feed_webhook_log FOREIGN KEY (feed_webhook_log_id) REFERENCES feed_webhook_log(id) ON DELETE RESTRICT); |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_aa_feed_webhook_log_id ON ageing_activity(feed_webhook_log_id);CREATE INDEX idx_aa_partner_id ON ageing_activity(partner_id);CREATE INDEX idx_aa_salesperson_id ON ageing_activity(salesperson_id);CREATE INDEX idx_aa_partner_period ON ageing_activity(partner_id, year, month);CREATE INDEX idx_aa_salesperson_period ON ageing_activity(salesperson_id, year, month); |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

### activation_activity

Stores the raw activation call data received from the Task Management feed, one record per salesperson per customer per month.

| CREATE TABLE activation_activity ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), partner_id UUID NOT NULL, salesperson_id UUID NOT NULL, customer_id UUID NOT NULL, month SMALLINT NOT NULL, year SMALLINT NOT NULL, feed_webhook_log_id UUID NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT fk_aca_feed_webhook_log FOREIGN KEY (feed_webhook_log_id) REFERENCES feed_webhook_log(id) ON DELETE RESTRICT, CONSTRAINT uq_aca_salesperson_customer_period UNIQUE (salesperson_id, customer_id, month, year)); |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_aca_feed_webhook_log_id ON activation_activity(feed_webhook_log_id);CREATE INDEX idx_aca_partner_id ON activation_activity(partner_id);CREATE INDEX idx_aca_salesperson_id ON activation_activity(salesperson_id);CREATE INDEX idx_aca_customer_id ON activation_activity(customer_id);CREATE INDEX idx_aca_partner_period ON activation_activity(partner_id, year, month);CREATE INDEX idx_aca_salesperson_period ON activation_activity(salesperson_id, year, month); |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

### feed_archive_log

| CREATE TABLE feed_archive_log ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), partner_id UUID NOT NULL, feed_type VARCHAR(20) NOT NULL, period_month SMALLINT NOT NULL, period_year SMALLINT NOT NULL, s3_bucket TEXT NOT NULL, s3_key TEXT NOT NULL, record_count INTEGER NOT NULL, archived_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT chk_fal_feed_type CHECK ( feed_type IN ('AGEING', 'ACTIVATION_CALL') ), CONSTRAINT uq_fal_partner_feed_period UNIQUE ( partner_id, feed_type, period_year, period_month )); |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_fal_partner_id ON feed_archive_log(partner_id);CREATE INDEX idx_fal_feed_type ON feed_archive_log(feed_type);CREATE INDEX idx_fal_partner_period ON feed_archive_log(partner_id, period_year, period_month); |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

The UNIQUE constraint on (partner_id, feed_type, period_year, period_month) prevents a second archival attempt from writing a duplicate log entry for the same bucket and acts as a natural idempotency guard if the job is re-triggered.

## Admin Tables

### salesperson_type_multiplier

Stores the configurable multiplier value per salesperson type per partner, used to calculate the SPV target for the Activation Call incentive.

| CREATE TABLE salesperson_type_multiplier ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), partner_id UUID NOT NULL, salesperson_type VARCHAR(20) NOT NULL, multiplier NUMERIC(10, 2) NOT NULL, valid_from TIMESTAMPTZ NOT NULL, valid_to TIMESTAMPTZ NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), ~~CONSTRAINT chk_stm_salesperson_type CHECK ( salesperson_type IN ('STO', 'SFT', 'SMO', 'SMF') ),~~ CONSTRAINT chk_stm_multiplier_positive CHECK ( multiplier \> 0 ), CONSTRAINT chk_stm_period_order CHECK ( valid_to \> valid_from ), CONSTRAINT uq_stm_partner_sp_type_period UNIQUE ( partner_id, salesperson_type, valid_from, valid_to )); |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

Indexes

| CREATE INDEX idx_stm_partner_id ON salesperson_type_multiplier(partner_id);CREATE INDEX idx_stm_partner_sp_type ON salesperson_type_multiplier(partner_id, salesperson_type);CREATE INDEX idx_stm_period ON salesperson_type_multiplier(partner_id, valid_from, valid_to); |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

## Ageing Incentive Tables

### ageing_incentive_spv

Stores the computed ageing incentive for each supervisor, referencing the SP level incentive results that were aggregated to produce the SPV payout.

| CREATE TABLE ageing_incentive_spv ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), result_id UUID NOT NULL, incentive_result_ids UUID\[\] NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT fk_ais_result FOREIGN KEY (result_id) REFERENCES incentive_results(id) ON DELETE RESTRICT); |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_ais_result_id ON ageing_incentive_spv(result_id); |
| :----------------------------------------------------------------- |

### ageing_incentive_reference

Stores the traceability link between an incentive result and the raw ageing activity row used in the calculation.

| CREATE TABLE ageing_incentive_reference ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), result_id UUID NOT NULL, ageing_row_reference_id UUID NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT fk_air_result FOREIGN KEY (result_id) REFERENCES incentive_results(id) ON DELETE RESTRICT, CONSTRAINT fk_air_ageing_activity FOREIGN KEY (ageing_row_reference_id) REFERENCES ageing_activity(id) ON DELETE RESTRICT); |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_air_result_id ON ageing_incentive_reference(result_id);CREATE INDEX idx_air_ageing_row_reference_id ON ageing_incentive_reference(ageing_row_reference_id); |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

## Activation Incentive Tables

### activation_incentive_sp

Stores the computed activation call incentive for each salesperson, including the list of eligible unique customers that qualified for the payout.

| CREATE TABLE activation_incentive_sp ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), result_id UUID NOT NULL, eligible_unique_customers UUID\[\] NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT fk_aisp_result FOREIGN KEY (result_id) REFERENCES incentive_results(id) ON DELETE RESTRICT); |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_aisp_result_id ON activation_incentive_sp(result_id); |
| :--------------------------------------------------------------------- |

### activation_incentive_spv

Stores the computed activation call incentive for each supervisor, referencing the SP level incentive results that were aggregated to produce the SPV payout.

| CREATE TABLE activation_incentive_spv ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), result_id UUID NOT NULL, activation_incentive_result_ids UUID\[\] NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT fk_aispv_result FOREIGN KEY (result_id) REFERENCES incentive_results(id) ON DELETE RESTRICT); |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_aispv_result_id ON activation_incentive_spv(result_id); |
| :----------------------------------------------------------------------- |

### activation_incentive_reference

Stores the traceability link between an incentive result and the raw activation activity rows used in the calculation.

| CREATE TABLE activation_incentive_reference ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), result_id UUID NOT NULL, activation_row_reference_ids UUID\[\] NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT fk_air_result FOREIGN KEY (result_id) REFERENCES incentive_results(id) ON DELETE RESTRICT); |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_acr_result_id ON activation_incentive_reference(result_id); |
| :--------------------------------------------------------------------------- |

## Call Plan Incentive Tables

### call_plan_incentive_sp

Stores the computed call plan incentive for each salesperson, with daily payout breakdown stored as a JSONB array.

| CREATE TABLE call_plan_incentive_sp ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), result_id UUID NOT NULL, daily_payouts JSONB NOT NULL DEFAULT '\[\]'::JSONB,  – \[‘1000’, ‘200’, \_ \_ \_ \_ , ‘500’\] Each day payout is stored at the respective index. created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT fk_cpisp_result FOREIGN KEY (result_id) REFERENCES incentive_results(id) ON DELETE RESTRICT, CONSTRAINT chk_cpisp_daily_payouts_is_array CHECK ( jsonb_typeof(daily_payouts) \= 'array' )); |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_cpisp_result_id ON call_plan_incentive_sp(result_id); |
| :--------------------------------------------------------------------- |

### call_plan_incentive_spv

Stores the computed call plan incentive for each supervisor, with daily payout breakdown including the SP result references per day.

| CREATE TABLE call_plan_incentive_spv ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), result_id UUID NOT NULL, daily_payouts JSONB NOT NULL DEFAULT '\[\]'::JSONB, – \[{“date”:”01-01-2002”, “call_plan_salesperson_result_ids”: UUID\[\], “payout”:”5000”}\] created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT fk_cpispv_result FOREIGN KEY (result_id) REFERENCES incentive_results(id) ON DELETE RESTRICT, CONSTRAINT chk_cpispv_daily_payouts_is_array CHECK ( jsonb_typeof(daily_payouts) \= 'array' )); |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_cpispv_result_id ON call_plan_incentive_spv(result_id); |
| :----------------------------------------------------------------------- |

## Weekly Revenue Incentive Tables

### weekly_payout_incentive_sp

Stores the computed weekly revenue incentive for each salesperson, with one row per week.

| CREATE TABLE weekly_payout_incentive_sp ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), result_id UUID NOT NULL, week_label VARCHAR(2) NOT NULL, payout NUMERIC(15, 2) NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT fk_wpisp_result FOREIGN KEY (result_id) REFERENCES incentive_results(id) ON DELETE RESTRICT, CONSTRAINT chk_wpisp_week_label CHECK ( week_label IN ('W1', 'W2', 'W3', 'W4') )); |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_wpisp_result_id ON weekly_payout_incentive_sp(result_id); |
| :------------------------------------------------------------------------- |

### weekly_payout_incentive_spv

Stores the computed weekly revenue incentive for each supervisor, with one row per week including the SP result references used in aggregation.

| CREATE TABLE weekly_payout_incentive_spv ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), result_id UUID NOT NULL, week_label VARCHAR(2) NOT NULL, sp_result_ids UUID\[\] NOT NULL, payout NUMERIC(15, 2) NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT fk_wpispv_result FOREIGN KEY (result_id) REFERENCES incentive_results(id) ON DELETE RESTRICT, CONSTRAINT chk_wpispv_week_label CHECK ( week_label IN ('W1', 'W2', 'W3', 'W4') )); |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_wpispv_result_id ON weekly_payout_incentive_spv(result_id); |
| :--------------------------------------------------------------------------- |

## Monthly Revenue Incentive Tables

### monthly_revenue_incentive_spv

Stores the computed monthly revenue incentive for each supervisor, referencing the SP level incentive results that were aggregated to produce the SPV payout.

| CREATE TABLE monthly_revenue_incentive_spv ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), result_id UUID NOT NULL, incentive_result_ids UUID\[\] NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT fk_mrispv_result FOREIGN KEY (result_id) REFERENCES incentive_results(id) ON DELETE RESTRICT); |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_mrispv_result_id ON monthly_revenue_incentive_spv(result_id); |
| :----------------------------------------------------------------------------- |

## Unique Transacting Customer Incentive Tables

### unique_transacting_customer_incentive_sp

Stores the computed unique transacting customer incentive for each salesperson, holding only customers with net sales greater than zero.

| CREATE TABLE unique_transacting_customer_incentive_sp ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), result_id UUID NOT NULL, eligible_unique_customers UUID\[\] NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT fk_utcisp_result FOREIGN KEY (result_id) REFERENCES incentive_results(id) ON DELETE RESTRICT); |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

Indexes

| CREATE INDEX idx_utcisp_result_id ON unique_transacting_customer_incentive_sp(result_id); |
| :---------------------------------------------------------------------------------------- |

### unique_transacting_customer_incentive_spv

Stores the computed unique transacting customer incentive for each supervisor, referencing the SP level unique customer transaction results used in aggregation.

| CREATE TABLE unique_transacting_customer_incentive_spv ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), result_id UUID NOT NULL, unique_customer_transaction_ids UUID\[\] NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT fk_utcispv_result FOREIGN KEY (result_id) REFERENCES incentive_results(id) ON DELETE RESTRICT); |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_utcispv_result_id ON unique_transacting_customer_incentive_spv(result_id); |
| :------------------------------------------------------------------------------------------ |

## salesperson_metrics_snapshot

For now it stores per-product sales metrics per salesperson, per period, sent to the Target Engine for schemes where no formal target exists. Keyed by (partner_id, salesperson_id, month, year) with the metrics payload in a JSONB column. Designed to accommodate additional metric types in future without schema change.

| CREATE TABLE salesperson_metrics_snapshot ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), partner_id UUID NOT NULL, salesperson_id UUID NOT NULL, month SMALLINT NOT NULL, year SMALLINT NOT NULL, sales_by_product JSONB NOT NULL DEFAULT '{}', \-- {"\<customer_id\>": {"\<product_id\>": \<net_sales\>}} sales_by_jot_group JSONB NOT NULL DEFAULT '{}', \-- {"\<customer_id\>": {"\<jot_group_id\>": \<net_sales\>}} \-- Only products resolving a jot_group are recorded. \-- Products with no jot_group are skipped. created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT uq_sms_sp_period UNIQUE (partner_id, salesperson_id, month, year)); |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Indexes

| CREATE INDEX idx_sms_partner_id ON salesperson_metrics_snapshot(partner_id);CREATE INDEX idx_sms_salesperson_id ON salesperson_metrics_snapshot(salesperson_id);CREATE INDEX idx_sms_partner_period ON salesperson_metrics_snapshot(partner_id, year, month);CREATE INDEX idx_sms_salesperson_period ON salesperson_metrics_snapshot(salesperson_id, year, month);CREATE INDEX idx_sms_sales_by_product ON salesperson_metrics_snapshot USING GIN (sales_by_product); |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

# Pre-requisites — Target Sales Engine Changes for Incentive Engine Support

### Achievement Table Migration: record_id → target_record_id

**Context**

The achievements table currently has a column named record_id (UUID) which holds a reference to the specific record in the matched target table (e.g., target_sales_volume, target_call_plan, etc.). The name record_id is ambiguous — it provides no indication of what entity it references, making it harder to reason about queries and joins.

**Change**

Rename record_id to target_record_id across the achievements table, Sequelize model, and all query references.

**Migration Script**

| ALTER TABLE achievementsRENAME COLUMN record_id TO target_record_id; |
| :------------------------------------------------------------------- |

**Sequelize Model Update**

| target_record_id: { type: DataTypes.UUID, allowNull: false}, |
| :----------------------------------------------------------- |

**Impact**

All existing INSERT, UPDATE, and SELECT queries referencing record_id on the achievements table must be updated to target_record_id. This is a breaking rename — ensure the migration runs before the application deployment. No data loss occurs as this is a column rename only.

### T4 Achievement Changes

**Background**

The T4 achievement JSONB structure previously stored unique transacting customer data keyed by customer_id, with each customer's sales broken down per focus_group_id. This sub-keying by focus group is not required for the Incentive Engine — T4 only needs to know whether a customer transacted (i.e. has total_sales \> 0), not which focus group they transacted in. The structure is therefore simplified to a flat map of customer_id → total_sales, removing the per-focus-group sub-structure entirely. **This also eliminates the need to resolve focus_group_id during T4 processing**; that lookup is now scoped exclusively to T5/T6.

The focus group division was earlier added because of an incentive discussed earlier but now is not a part of the scope.

**Current Structure** _(discontinued)_

| { "\<customer_id\>": { "\<focus_group_id\>": \<net_sales\> }} |
| :------------------------------------------------------------ |

// discontinued — focus_group sub-keying removed  
**New Structure**

| { "\<customer_id\>": \<total_sales\>} |
| :------------------------------------ |

**Field definitions:**

- total_sales — The cumulative net sales amount for that customer across all products in the period (i.e. net_sales_amount accumulated across all webhook events for this customer in the month). A customer is considered "achieved" when total_sales \> 0. The count of such customers drives actual_achieved in the achievement JSONB.

**Implementation Notes**

- The /api/product-submissions lookup (for omset_group and jot_group resolution) is no longer required during T4 webhook processing. It is performed only when matching T5 or T6 targets. T4 processing consumes net_sales_amount directly from the job payload.
- A customer transitions from not-achieved to achieved (incrementing actual_achieved and daily) when their cumulative total_sales crosses 0 for the first time. Subsequent sales events for an already-achieved customer update unique_customers only — actual_achieved and daily are not double-counted.
- This change is **confined to the daily sales webhook processing logic only**. No database schema change is required. Any existing T4 achievement rows in dev that carry the old { customer_id: { focus_group_id: sales } } shape must be migrated via a one-time SQL script before the feature branch is merged — run inside a transaction and verify row counts before committing:

| BEGIN;UPDATE achievementSET unique_customers \= ( SELECT jsonb_object_agg( cust_id, ( SELECT COALESCE(SUM((fg.value)::numeric), 0) FROM jsonb_each(cust_val.value) AS fg ) ) FROM jsonb_each(unique_customers) AS cust_val(cust_id, value) ), updated_at \= NOW()WHERE target_type \= (SELECT id FROM target_types WHERE name \= 'T4') AND unique_customers IS NOT NULL AND jsonb_typeof( unique_customers \-\> ( SELECT key FROM jsonb_object_keys(unique_customers) LIMIT 1 ) ) \= 'object'; \-- guard: only process rows still in old shape\-- Verify before committingSELECT id, jsonb_typeof( unique_customers \-\> ( SELECT key FROM jsonb_object_keys(unique_customers) LIMIT 1 ) ) AS value_type \-- should be 'number' for all rowsFROM achievementWHERE target_type \= (SELECT id FROM target_types WHERE name \= 'T4') AND unique_customers IS NOT NULL;COMMIT; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

### Achievement Locking

**Background**

Once the Incentive Engine completes the monthly incentive calculation, the achievement data for that month must be locked to prevent any further updates from manipulating already-computed incentive results. Without this, late-arriving webhook data or data corrections could silently alter the values that were used as the basis for payout.

**Approach**

Two new columns are added to the achievements table:

| Column    | Type        | Description                                                                                  |
| --------- | ----------- | -------------------------------------------------------------------------------------------- |
| is_locked | BOOLEAN     | Indicates whether this achievement record is locked from further updates. Defaults to false. |
| locked_at | TIMESTAMPTZ | Timestamp of when the lock was applied. Null until locked.                                   |

The lock is applied at the individual achievement record level. All achievement records whose start_date and end_date fall within the calculated month are locked together once the incentive calculation for that month completes successfully.

Webhook Behaviour When Locked

If the daily sales webhook worker attempts to update an achievement record that has is_locked \= true, the worker will skip the update and log a warning with the relevant record details. No error is returned to the caller and no retry is triggered — the incoming data is acknowledged but not applied.

### Daily Sales Webhook — Incentive Engine Extension

Additive changes to the existing BullMQ pipeline. Achievement logic is unchanged.

#### **Overview**

#### Before existing target matching and achievement logic runs, the Daily Sales webhook job now also populates a new salesperson_metrics_snapshot table, the data foundation for the Incentive Engine. It holds a single aggregated monthly record per salesperson (SP) or supervisor (SPV) per partner, capturing cumulative sales broken down by product and by JOT group.

Both concerns run as **parallel threads** within the same BullMQ job, wrapped in a single database transaction — either both succeed and commit, or both roll back and the job is retried.

#### New table — salesperson_metrics_snapshot

One row per (partner_id, salesperson_id, month, year). Consumed by the Incentive Engine for eligibility and payout calculations.

Scope – SP \+ SPV (same column)

JSONB strategy – Merge & increment

Negative values – Allowed (no floor)

#### JOT group resolution

Each billing event carries a material_no. The jot_group_id is resolved via the /api/product-submissions external API endpoint (Closio WS2 Service).

**Cache strategy**

Shared with the T5 omset_group_id product metadata lookup — same cache key, same TTL. The cache entry must include jot_group_id in addition to omset_group_id.

![][image1]

Resolution rules![][image2]

#### Processing architecture — parallel threads in a single transaction

The Daily Sales job processor runs two concurrent threads inside each BullMQ job execution, sharing a single database transaction. If either thread fails, the transaction rolls back entirely and BullMQ retries the job.  
![][image3]

#### Pseudocode

| async function processDailySalesJob(jobPayload) { const alreadyProcessed \= await checkProcessedNetSalesEvent(jobPayload); if (alreadyProcessed) return { skipped: true, reason: 'DUPLICATE_EVENT' }; const transaction \= await db.beginTransaction(); try { const \[achievementResult, snapshotResult\] \= await Promise.all(\[ processAchievementLogic(jobPayload, transaction), // Thread 1 (existing) updateSalespersonMetricsSnapshot(jobPayload, transaction) // Thread 2 (new) \]); await insertProcessedNetSalesEvent(jobPayload, transaction); await transaction.commit(); return { ok: true, achievementResult, snapshotResult }; } catch (err) { await transaction.rollback(); throw err; // BullMQ catches this → retries job }} |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

#### Merge rules

![][image4]

#### SP vs SPV handling

Thread 2 handles both identically, there is no branching logic. Each entity gets its own row keyed by their salesperson_id. When a supervisor's direct sales arrive through the same webhook, they are accumulated into the supervisor's snapshot row exactly as a salesperson's would be.

### Manual Target Creation — T5 Salesperson Level Change

The manual target creation screen currently populates the salesperson dropdown by calling the external Partner Public API ( default level 1 ) restricting selection to field salespersons only. For T5 targets, supervisors (level 2\) are also valid salespersons since T5 revenue targets can be assigned to them. This change updates the frontend to include level 2 salespersons in the dropdown exclusively for T5.

Change Required

The salesperson dropdown on the manual target creation screen fetches salespersons from:

| GET https://jxa-dev-apipartnerpublic.japfacomfeed.co.id/users |
| :------------------------------------------------------------ |

For T5 target type only, this call must be updated to:

| GET https://jxa-dev-apipartnerpublic.japfacomfeed.co.id/users?level=1,2 |
| :---------------------------------------------------------------------- |

**For all other target types (T1, T2, T3, T4), the call will be ?level=1**

Behaviour

- When the user navigates to manual target creation of **T5 target**, the salesperson dropdown must include both level 1 and level 2 salespersons.
- When any other target type is selected, the salesperson dropdown must include level 1 salespersons only.
- Backend API change is required to accept level=1,2 — which is done by the Japfa team as this is an external API.
- No changes required to validation logic, DB schema, or target type metadata.

### Bulk Upload — T5 Salesperson Level Change

The bulk upload processor currently fetches all valid salespersons from the Partner Public API with ?level=1 and loads them into a usersMap. For every CSV row, the salesperson_id is validated against this map. Since T5 targets can be assigned to supervisors (level 2), the bulk processor must be updated to allow level 2 salespersons for T5 rows only. T1 and T2 must continue to allow level 1 only.

**Change Required**

Currently in the bulk upload confirm flow, users are fetched as:

| GET https://jxa-dev-apipartnerpublic.japfacomfeed.co.id/users?page=1\&limit=5000\&level=1 |
| :---------------------------------------------------------------------------------------- |

This produces a single usersMap used for all target types.

The change introduces a **level-aware user fetch per target type**:

- For **T1 and T2** — fetch with ?level=1 (unchanged)
- For **T5** — fetch with ?level=1,2

This must be implemented as a target-type-specific fetch — the global user fetch must not be widened to level=1,2 for all types, as that would unintentionally allow level 2 salespersons for T1 and T2.

**Implementation Notes**

- Parameterise the user fetch function to accept allowedLevels per target type:
  - T1, T2 → allowedLevels: \[1\]
  - T5 → allowedLevels: \[1, 2\]
- If the Partner Public API supports multiple levels in a single call, use ?level=1,2 directly.
- If not, make two separate calls — one with ?level=1 and one with ?level=2 — and merge the results into a single usersMap.
- Update the T5 validation error message from:
  - Salesperson tidak ditemukan atau bukan level 1
  - to: Salesperson tidak ditemukan atau bukan level 1/2
- T1 and T2 error messages remain unchanged.

# Data Archival

Feed tables (ageing_activity, activation_activity) accumulate raw ingestion data indefinitely. Each feed record is scoped to a specific month and is consumed exactly once — during the incentive calculation run for that month. Once a run completes successfully and results are persisted in incentive_results, the raw feed data for that month has no further computational role.

Retaining this data in the primary DB beyond the calculation window is operationally wasteful and will degrade query performance over time as row counts grow across monthly cycles.

A structured archival process moves aged feed records to S3 cold storage and clears them from the DB, while maintaining a full audit trail of what was archived and where.

**Retention Policy:** Feed records for a given (partner_id, feed_type, year, month) bucket are eligible for archival when both of the following conditions are met:

- The incentive calculation run for that month has completed with status success.
- The bucket period is older than 2 completed months from the current month — this guards against manual recalculation scenarios where Admin may re-trigger a run for the most recently closed month.

### **Step 1 — Archival Job**

A BullMQ job is dispatched to the feed-archival-queue on the 1st of every month via the existing BullMQ repeat job scheduler.

**Job behaviour:**

1. Determine eligible buckets: query incentive_run_log for all (partner_id, year, month) combinations where status \= 'success' and the period is older than 2 completed months from today.
2. Cross-reference against feed_archive_log — skip any bucket that already has an entry (idempotency guard).
3. For each eligible (partner_id, feed_type, year, month) bucket:
   - Query the relevant table in batches (default: 1,000 rows per batch) to avoid memory pressure.
   - Serialize the full bucket result into a single structured JSON document.
   - Upload to S3 at the path:
     1. Examples:
        1. s3://japfa-incentive-archive/ageing_feed/partner-japfa-b2/2025/08/ageing_feed_2025_08.json
        2. s3://japfa-incentive-archive/activation_call_feed/partner-japfa-b2/2025/08/activation_calls_2025_08.json
4. Only proceed to Step 2 after receiving a confirmed success response from the S3 SDK. Any S3 upload failure aborts archival for that bucket, logs the error, and leaves DB records untouched. The S3 client is initialized using the AWS SDK v3 (@aws-sdk/client-s3) with credentials resolved from environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) in dev/staging, and from the pod's IRSA role in production. The bucket name is read from the S3_ARCHIVE_BUCKET environment variable — it is not hardcoded.
5. S3 path structure:
   - /{feed_type}/{partner_id}/{year}/{month}/{filename}

### Step 2 — Delete from DB After Confirmed Upload

Deletion is strictly conditional on a successful S3 upload acknowledgement. The sequence is:

1. Upload succeeds → S3 ETag / version ID is returned.
2. feed_archive_log row is inserted with s3_bucket, s3_key, record_count, and archived_at.
3. DB rows for that (partner_id, feed_type, year, month) bucket are deleted.
4. If the delete fails after the log entry is written, the job logs a PARTIAL warning. The feed_archive_log entry acts as the source of truth that data is safely in S3 — the delete can be retried safely on the next run without re-uploading.

**Never delete before upload confirmation. Never delete without a feed_archive_log entry.**

### Step 3 — Archive Log Table

A feed_archive_log entry is written per (partner_id, feed_type, year, month) bucket upon successful upload and before deletion. This table is the single source of truth for what has been moved to S3 and cleared from the DB.

**Table category:** Feed & Activity Tables

The UNIQUE constraint on (partner_id, feed_type, period_year, period_month) prevents a second archival attempt from writing a duplicate log entry for the same bucket and acts as a natural idempotency guard if the job is re-triggered.

## BullMQ Integration

| Parameter          | Description                                                                                                                                                                   |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Queue**          | feed-archival-queue                                                                                                                                                           |
| **Trigger**        | BullMQ repeat job on the 1st of every month \+ Admin manual trigger                                                                                                           |
| **Job Payload**    | { partner_id, feed_type, period_month, period_year } — one job per eligible bucket                                                                                            |
| **Retry Strategy** | Exponential backoff, max 3 retries. Safe to retry because deletion only happens after a confirmed upload and log entry.                                                       |
| **Dead Letter**    | Failed jobs after max retries move to incentive-dlq and trigger an Admin alert                                                                                                |
| **Idempotency**    | Job checks feed_archive_log for an existing entry for the bucket before proceeding. If an entry already exists, the job exits as no-op — safe to replay without side effects. |

## Failure Handling

| Failure Scenario                                           | Behaviour                                                                                                                                                                                                                                    |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| S3 upload fails                                            | Abort for that bucket. DB untouched. No log entry written. Job retried with backoff.                                                                                                                                                         |
| DB delete fails after successful upload                    | feed_archive_log entry already written with S3 coordinates. Delete retried on next run — log entry prevents re-upload.                                                                                                                       |
| Job crashes mid-batch                                      | On retry, eligible buckets are re-queried. Already-archived buckets skipped via feed_archive_log check. Partially uploaded buckets are re-uploaded since no log entry was committed.                                                         |
| Calculation run for that month not yet complete            | Bucket is ineligible — archival eligibility check gates on incentive_run_log.status \= 'success'. No archival proceeds for that bucket.                                                                                                      |
| Manual recalculation triggered for a recently closed month | A 2-month safety floor ensures the prior month and the month before are never archived, keeping their feed data available in DB for any re-run.                                                                                              |
| Archival job and calculation job run concurrently          | No collision possible — archival only targets buckets whose run status is success and period is older than 2 months. Any active or pending calculation run operates on current or prior month data, which the archival job will never touch. |

# Workflows \-

1. ## Feed Data Ingestion Webhook
   1. ### Ageing data feed

#### POST /api/incentives/v1/feeds/ageing

**Auth headers used:**

- x-client-id and x-client-secret for S2S authentication
- No cookie-based authentication — this is a direct S2S call from Qlik Sense. ws-1 is not involved.
- x-partner-id — UUID of the partner this feed belongs to

**Request format:** multipart/form-data

**Form fields:**

- file — The CSV file upload (Required)
- month — Integer, 1–12 (Required)
- year — Integer (Required)

**Expected CSV columns** (exact, order-independent): salesperson_id, month, ar_0_10_days, ar_month_total

**Workflow:**

This endpoint operates in two phases.

**Phase 1 — Synchronous Accept**

1. Apply middleware. Returns HTTP 401 with the following error codes based on the failure:
2. If x-client-id or x-client-secret headers are missing:

| { "status": "error", "error_code": "UNAUTHORIZED", "message": "Missing client credentials"} |
| :------------------------------------------------------------------------------------------ |

3. If x-client-id is not registered in the credentials map:

| {  "status": "error",  "error_code": "UNKNOWN_CLIENT",  "message": "Unknown client" } |
| :------------------------------------------------------------------------------------ |

4. If x-client-secret does not match:

| {  "status": "error",  "error_code": "INVALID_CLIENT_AUTH",  "message": "Invalid client credentials" } |
| :----------------------------------------------------------------------------------------------------- |

5. Validate all required form fields are present (file, partner_id, month, year). If any are missing → return HTTP 400:

| { "status": "error", "error_code": "MISSING_FIELDS", "message": "Required fields are missing", "details": { "missing_fields": \["month", "year"\] } } |
| :---------------------------------------------------------------------------------------------------------------------------------------------------- |

6. Validate partner_id is a valid UUID, month is an integer between 1–12, and year is a valid integer. If any fail → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "Request field validation failed", "details": { "missing_or_invalid": \["month"\] } } |
| :------------------------------------------------------------------------------------------------------------------------------------------------------ |

7. Validate the uploaded file is a CSV. If not → return HTTP 415:

| { "status": "error", "error_code": "INVALID_FILE_TYPE", "message": "Only CSV files are accepted" } |
| :------------------------------------------------------------------------------------------------- |

8. Parse the CSV header row only. Validate that column names exactly match the expected schema: salesperson_id, month, ar_0_10_days, ar_month_total. If column names do not match → return HTTP 400 immediately:

| { "status": "error", "error_code": "INVALID_CSV_SCHEMA", "message": "CSV column names do not match expected schema", "details": { "expected": \["salesperson_id", "month", "ar_0_10_days", "ar_month_total"\], "received": \["salesperson_id", "month", "ar_10", "ar_total"\] } } |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

9. Query feed_webhook_log for an existing record with (partner_id, feed_type \= 'ageing', month, year) and status \= 'success'. If found → return HTTP 409:

| { "status": "error", "error_code": "ALREADY_RECEIVED", "message": "Ageing feed for this partner and period has already been successfully received", "details": { "log_id": "\<existing_log_uuid\>" } } |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

10. Stream the uploaded CSV file directly to S3. Use the deterministic key:

| {S3_FEED_PATH_PREFIX}ageing/{partner_id}/{year}/{month}/{original_filename} |
| :-------------------------------------------------------------------------- |

    into the S3\_FEED\_BUCKET bucket. The S3 upload must complete and return a confirmed ETag before proceeding. If the upload fails → return HTTP 500:

| { "status": "error", "error_code": "FEED_UPLOAD_FAILED", "message": "Failed to upload feed file to storage"} |
| :----------------------------------------------------------------------------------------------------------- |

Do not write any DB record. Record the filename (original filename from the multipart upload), s3_key, s3_bucket, and file_size_bytes from the upload response for use in step 12\.

11. Insert a new record into feed_webhook_log:

| INSERT INTO feed_webhook_log ( partner_id, feed_type, month, year, filename, s3_bucket, s3_key, file_size_bytes, status, received_at ) VALUES ( :partner_id, 'ageing', :month, :year, :filename, :s3_bucket, :s3_key, :file_size_bytes, 'pending', NOW() ); |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

12. Enqueue a single BullMQ job into feed-ingestion-queue. The job carries:

| { "log_id": "\<uuid\>", "feed_type": "ageing", "partner_id": "\<uuid\>", "month": 4, "year": 2026, "s3_bucket": "japfa-incentive-feeds", "s3_key": "ageing/partner-japfa-b2/2026/4/ageing_feed_2026_04.csv" } |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

Row data is not embedded in the job payload. The worker streams the full file from S3 sequentially

13. Return HTTP 202 Accepted:

| ​​{ "status": "success", "data": { "log_id": "\<uuid\>", "status": "pending", "total_records": 60000 } } |
| :------------------------------------------------------------------------------------------------------- |

**Phase 2 — Async BullMQ Processing (Feed Ingestion Worker)**

The job is picked up by a Feed Ingestion Worker from feed-ingestion-queue and processed as follows:

- Set feed_webhook_log.status to 'processing' on job pickup.
- Issue a full S3 GetObjectCommand against s3_bucket/s3_key with no Range header. If the object is not found (S3 NoSuchKey error) → fail immediately without retry:
  - Write S3_OBJECT_NOT_FOUND to error_details on feed_webhook_log
  - Set status \= 'failed'
  - Exit
- For transient S3 errors (503 SlowDown, network timeout) → follow the standard BullMQ exponential backoff retry strategy.
- Use readS3StreamFile to open a full streaming connection to S3. The function returns the raw S3 Body stream — the file is never buffered in memory. S3 NoSuchKey → throws S3ObjectNotFoundError immediately, caught by the worker to set status \= 'failed' and exit. Transient S3 errors → thrown to BullMQ for exponential backoff retry.

| // S3 utility \-- returns raw stream, never buffers full fileconst readS3StreamFile \= async ({ bucket, key }) \=\> { const { Body } \= await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key })); return Body; // throws S3ObjectNotFoundError on NoSuchKey // throws raw error on transient S3 failures \-- BullMQ retries}; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

- Pass the stream into readS3FileInChunks, a generator utility that wraps the stream in readline, skips the header row, and yields batches of chunkSize rows. The worker never sees the full file — it receives one batch at a time.

| // Generator utility \-- yields { rows, offset } batches, skips headerasync function\* readS3FileInChunks(bucket, key, chunkSize) { const stream \= await readS3StreamFile(bucket, key); const rl \= readline.createInterface({ input: stream, crlfDelay: Infinity }); let isHeader \= true; let rows \= \[\]; let offset \= 0; for await (const line of rl) { if (isHeader) { isHeader \= false; continue; } rows.push(line); if (rows.length \>= chunkSize) { yield { rows, offset }; offset \+= rows.length; rows \= \[\]; } } if (rows.length \> 0) { yield { rows, offset }; } // flush tail} |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

- Iterate over yielded batches. For each batch, validate each row and bulk insert valid rows into ageing_activity. Invalid rows are skipped and accumulated into a local error list. Processing continues for remaining batches.  
  Validate each row (applied inside the batch loop above):
- salesperson_id must be a valid UUID
- month column in CSV must be in YYYY-MM format (e.g. 2026-03). If format does not match → skip row, log warning.
- Parse month and year by splitting on \-: left part \= month integer (1–12), right part \= year integer.
- The month and year must match the form field values passed in Phase 1\. If they do not match → skip row, log warning.
- ar_0_10_days and ar_month_total must be valid numeric values
- Row must not have null values in any required column

| const errors \= \[\];for await (const { rows, offset } of readS3FileInChunks( job.data.s3_bucket, job.data.s3_key, FEED_CHUNK_SIZE)) { const validRows \= \[\]; for (const line of rows) { const row \= parseCsvLine(line); const validationError \= validateAgeingRow(row, job.data.month, job.data.year); if (validationError) { errors.push({ line, reason: validationError }); continue; } validRows.push(row); } if (validRows.length \> 0) { await bulkInsertAgeing(validRows, job.data.log_id, job.data.partner_id); }} |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

- Bulk insert implementation using ON CONFLICT DO NOTHING:

| INSERT INTO ageing_activity ( feed_webhook_log_id, partner_id, salesperson_id, month, year, ar_10, month_total, created_at, updated_at) VALUES (...) ON CONFLICT DO NOTHING; |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

- Set feed_webhook_log.status \= 'success' and completed_at \= NOW(). Write accumulated row-level errors to error_details if any exist.

| await db.query(\` UPDATE feed_webhook_log SET status \= 'success', completed_at \= NOW(), error_details \= :errorDetails WHERE id \= :logId \`, { logId: job.data.log_id, errorDetails: errors.length \> 0 ? JSON.stringify(errors) : null }); |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**Retry strategy:**

- Max attempts — 3
- Backoff — Exponential, starting at 5 seconds
- S3 NoSuchKey (object not found) — Fail immediately, no retry
- Transient S3 errors (SlowDown, timeout) — Retryable, follow exponential backoff
- On max retries exhausted — Move to incentive-dlq, dispatch, set feed_webhook_log status to 'failed'
  2. ### Activation Feed Data

#### POST /api/incentives/v1/feeds/activation-call

**Auth headers used:**

- x-client-id and x-client-secret for S2S authentication
- No cookie-based authentication — this is a direct S2S call from Task Management. ws-1 is not involved.
- x-partner-id — UUID of the partner this feed belongs to

**Request format:** multipart/form-data

**Request fields:**

- file — The CSV file upload (Required)
- month — Feed period month, Integer 1–12 (Required)
- year — Feed period year, Integer (Required)

**Expected CSV columns** (exact, order-independent): salesperson_id, customer_id, month, year

Each row represents one unique customer for whom an activation call was made by the given salesperson in the given month and year.

**Workflow:**

This endpoint operates in two phases.

**Phase 1 — Synchronous Accept**

1. Apply middleware. Returns HTTP 401 with the following error codes based on the failure:
2. If x-client-id or x-client-secret headers are missing:

| { "status": "error", "error_code": "UNAUTHORIZED", "message": "Missing client credentials"} |
| :------------------------------------------------------------------------------------------ |

3. If x-client-id is not registered in the credentials map:

| {  "status": "error",  "error_code": "UNKNOWN_CLIENT",  "message": "Unknown client" } |
| :------------------------------------------------------------------------------------ |

4. If x-client-secret does not match:

| {  "status": "error",  "error_code": "INVALID_CLIENT_AUTH",  "message": "Invalid client credentials" } |
| :----------------------------------------------------------------------------------------------------- |

5. Validate all required form fields are present (file, partner_id, month, year). If any are missing → return HTTP 400:

| { "status": "error", "error_code": "MISSING_FIELDS", "message": "Required fields are missing", "details": { "missing_fields": \["month", "year"\] } } |
| :---------------------------------------------------------------------------------------------------------------------------------------------------- |

6. Validate partner_id is a valid UUID, month is an integer between 1–12, and year is a valid integer. If any fail → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "Request field validation failed", "details": { "missing_or_invalid": \["month"\] } } |
| :------------------------------------------------------------------------------------------------------------------------------------------------------ |

7. Validate the uploaded file is a CSV. If not → return HTTP 415:

| { "status": "error", "error_code": "INVALID_FILE_TYPE", "message": "Only CSV files are accepted" } |
| :------------------------------------------------------------------------------------------------- |

8. Parse the CSV header row only. Validate that column names exactly match the expected schema: salesperson_id, customer_id, month, year. If column names do not match → return HTTP 400 immediately:

| { "status": "error", "error_code": "INVALID_CSV_SCHEMA", "message": "CSV column names do not match expected schema", "details": { "expected": \["salesperson_id", "customer_id", "month", "year"\], "received": \["salesperson_id", "customer", "month", "year"\] } } |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

9. Query feed_webhook_log for an existing record with (partner_id, feed_type \= 'activation', month, year) and status \= 'success'. If found → return HTTP 409:

| { "status": "error", "error_code": "ALREADY_RECEIVED", "message": "Activation Call feed for this partner and period has already been successfully received", "details": { "log_id": "\<existing_log_uuid\>" } } |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

10. Stream the uploaded CSV file directly to S3. Use the deterministic key:

| {S3_FEED_PATH_PREFIX}activation/{partner_id}/{year}/{month}/{original_filename} |
| :------------------------------------------------------------------------------ |

    into the S3\_FEED\_BUCKET bucket. The S3 upload must complete and return a confirmed ETag before proceeding. If the upload fails → return HTTP 500:

| { "status": "error", "error_code": "FEED_UPLOAD_FAILED", "message": "Failed to upload feed file to storage"} |
| :----------------------------------------------------------------------------------------------------------- |

Do not write any DB record. Record the filename, s3_key, s3_bucket, and file_size_bytes from the upload response for use in step 12\.

     11\.  Insert a new record into feed\_webhook\_log:

| INSERT INTO feed_webhook_log ( partner_id, feed_type, month, year, filename, s3_bucket, s3_key, file_size_bytes, status, received_at ) VALUES ( :partner_id, 'activation', :month, :year, :filename, :s3_bucket, :s3_key, :file_size_bytes, 'pending', NOW() ); |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

     12\. Enqueue a single BullMQ job into feed-ingestion-queue. The job carries:

| { "log_id": "\<uuid\>", "feed_type": "activation", "partner_id": "\<uuid\>", "month": 4, "year": 2026, "s3_bucket": "japfa-incentive-feeds", "s3_key": "activation/partner-japfa-b2/2026/4/activation_feed_2026_04.csv" } |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

Row data is not embedded in the job payload. The worker streams the full file from S3 sequentially

14. Return HTTP 202 Accepted:

| ​​{ "status": "success", "data": { "log_id": "\<uuid\>", "status": "pending", "total_records": 60000 } } |
| :------------------------------------------------------------------------------------------------------- |

**Phase 2 — Async BullMQ Processing (Feed Ingestion Worker)**

The job is picked up by a Feed Ingestion Worker from feed-ingestion-queue and processed as follows:

- Set feed_webhook_log.status to 'processing' on job pickup.
- Issue a full S3 GetObjectCommand against s3_bucket/s3_key with no Range header. If the object is not found (S3 NoSuchKey error) → fail immediately without retry:
  - Write S3_OBJECT_NOT_FOUND to error_details on feed_webhook_log
  - Set status \= 'failed'
  - Exit
- For transient S3 errors (503 SlowDown, network timeout) → follow the standard BullMQ exponential backoff retry strategy.
- Use readS3StreamFile to open a full streaming connection to S3. The function returns the raw S3 Body stream — the file is never buffered in memory. S3 NoSuchKey → throws S3ObjectNotFoundError immediately, caught by the worker to set status \= 'failed' and exit. Transient S3 errors → thrown to BullMQ for exponential backoff retry. For code refer Ageing Incentive
- Pass the stream into readS3FileInChunks, a generator utility that wraps the stream in readline, skips the header row, and yields batches of chunkSize rows. The worker never sees the full file — it receives one batch at a time .For code refer Ageing Incentive
- Iterate over yielded batches. For each batch, validate each row and bulk insert valid rows into activation_activity. Invalid rows are skipped and accumulated into a local error list. Processing continues for remaining batches. For code refer Ageing Incentive
- Validate each row:
- salesperson_id must be a valid UUID
- customer_id must be a valid UUID
- month must be a valid integer (1–12)
- year must be a valid integer
- Row must not have null values in any required column
- Invalid rows are skipped and accumulated into a local error list. Processing continues for remaining rows.

Accumulate valid rows into a batch array of FEED_CHUNK_SIZE rows. Bulk insert each batch into activation_activity. Clear the batch array and continue. After the stream closes, flush any remaining rows in the batch array. For code refer Ageing Incentive

Bulk insert implementation. Deduplication is enforced at the database layer — duplicate rows on (salesperson_id, customer_id, month, year) within the same feed or across re-ingestion attempts are silently skipped:

| INSERT INTO activation_activity ( feed_webhook_log_id, partner_id, salesperson_id, customer_id, month, year, created_at) VALUES (...) ON CONFLICT (salesperson_id, customer_id, month, year)DO NOTHING; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

Set feed_webhook_log.status \= 'success' and completed_at \= NOW(). Write accumulated row-level errors to error_details if any exist

| await db.query(\` UPDATE feed_webhook_log SET status \= 'success', completed_at \= NOW(), error_details \= :errorDetails WHERE id \= :logId\`, { logId: job.data.log_id, errorDetails: errors.length \> 0 ? JSON.stringify(errors) : null});. |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**Retry strategy:**

- Max attempts — 3
- Backoff — Exponential, starting at 5 seconds
- S3 NoSuchKey (object not found) — Fail immediately, no retry
- Transient S3 errors (SlowDown, timeout) — Retryable, follow exponential backoff
- On max retries exhausted — Move to incentive-dlq, dispatch, set feed_webhook_log status to 'failed'
  3. ### Feed Ingestion Status

#### GET /api/incentives/v1/feeds/status/:log_id

**Auth headers used:**

- ws-1 will use cookies coming in the header to authenticate and retrieve the user details
- x-client-id and x-client-secret for S2S authentication from ws-1 to ws2targetsales
- X-Partner-Id and X-User-Id are passed down as request headers
- Access restricted to **Admin role only**

**Path params:**

- log_id (UUID) — The feed_webhook_log record ID to fetch status for

**Workflow:**

1. ws-1 validates the cookie. If the cookie is invalid → ws-1 returns HTTP 401:

| { "status": "error", "error_code": "TOKEN_INVALID", "message": "User token invalid or expired" } |
| :----------------------------------------------------------------------------------------------- |

2. If cookie is valid → ws-1 retrieves authenticated user details. If the authenticated user does not have Admin role → return HTTP 403:

| { "status": "error", "error_code": "FORBIDDEN", "message": "Only Admin users can access feed status" } |
| :----------------------------------------------------------------------------------------------------- |

3. ws-1 validates log_id path param is a valid UUID. If not → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "log_id must be a valid UUID" } |
| :------------------------------------------------------------------------------------------------ |

4. ws-1 prepares server-to-server request to ws2targetsales:
   - Add headers: x-client-id, x-client-secret, X-Partner-Id, X-User-Id
   - Pass log_id in the path param
5. Apply middleware. On any auth failure → return HTTP 401:

| {  "status": "error",  "error_code": "SIGNATURE_INVALID", "message": "Request signature invalid" } |
| :------------------------------------------------------------------------------------------------- |

6. Validate log_id path param is present and is a valid UUID. If missing or invalid → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "log_id must be a valid UUID" } |
| :------------------------------------------------------------------------------------------------ |

7. Query feed_webhook_log by log_id:

| SELECT id, feed_type, partner_id, month, year, status, total_records, jobs_completed, jobs_failed, error_details, received_at, completed_at FROM feed_webhook_log WHERE id \= :log_id; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

8. Evaluate query result:
   - If no record found → return HTTP 404:

| { "status": "error", "error_code": "NOT_FOUND", "message": "No feed log record found for the given log_id" } |
| :----------------------------------------------------------------------------------------------------------- |

- If the record's partner_id does not match the X-Partner-Id from the request headers → return HTTP 403:

| { "status": "error", "error_code": "FORBIDDEN", "message": "You do not have access to this feed log record" } |
| :------------------------------------------------------------------------------------------------------------ |

- If DB query fails → return HTTP 500:

| { "status": "error", "error_code": "INTERNAL_ERROR", "message": "Could not fetch feed status" } |
| :---------------------------------------------------------------------------------------------- |

9. If record found and partner matches → return HTTP 200:

| { "status": "success", "data": { "log_id": "\<uuid\>", "feed_type": "ageing", "partner_id": "\<uuid\>", "month": 4, "year": 2026, "status": "processing", "total_records": 60000, "jobs_completed": 34, "jobs_failed": 0, "error_details": null, "received_at": "2026-04-01T01:00:00Z", "completed_at": null } } |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**Note**: \`error_details\` contains a JSON summary of row-level validation errors accumulated during chunk processing. It is \`null\` until the final chunk job completes and errors are written. It is not returned to the calling system in real time during processing.

2. ## Incentive Slab Management
   1. ### Incentive Schemas

#### GET /api/incentives/v1/schemas

- **Auth headers used:**
  - ws-1 will use cookies coming in the header to authenticate and retrieve the user details (in this API we only need partner_id)
  - ws2targetsales uses x-client-id and x-client-secret coming in the headers to authenticate
  - X-Partner-Id is passed down as a request header
- **Accepted Query Parameters**: \-
  - search (optional, string): Partial match filter applied to schema_name. Case-insensitive. Min length: 1 character. Max length: 100 characters. Trailing/leading whitespace is trimmed before use.

**Workflow:**

1. Closio sends GET /api/incentives/v1/schemas to ws-1.
2. ws-1 validates the cookie. If the cookie is invalid → ws-1 returns HTTP 401:

| { "status": "error", "error_code": "TOKEN_INVALID", "message": "User token invalid or expired"} |
| :---------------------------------------------------------------------------------------------- |

3. If cookie is valid → ws-1 retrieves authenticated user details (partner_id).
4. ws-1 extracts the \`search\` query parameter if present.
   1. Trim leading/trailing whitespace.
   2. If present and trimmed value is an empty string → return HTTP 400:

| { "status": "error", "error_code": "INVALID_SEARCH_QUERY", "message": "Search query must not be empty"} |
| :------------------------------------------------------------------------------------------------------ |

3.  If present and trimmed length exceeds 100 characters → return HTTP 400:

| { "status": "error", "error_code": "INVALID_SEARCH_QUERY", "message": "Search query must not exceed 100 characters"} |
| :------------------------------------------------------------------------------------------------------------------- |

4. If valid, forward the trimmed value as a search query parameter to ws2targetsales in the S2S request.
5. ws-1 prepares a server-to-server request to ws2targetsales:
   1. Add headers: x-client-id, x-client-secret, X-Partner-Id
6. Apply middleware. On any auth failure → return HTTP 401:

| {  "status": "error",  "error_code": "SIGNATURE_INVALID", "message": "Request signature invalid" } |
| :------------------------------------------------------------------------------------------------- |

7. Validate X-Partner-Id header is present. If missing → return HTTP 400:

| { "status": "error", "error_code": "PARTNER_ID_MISSING", "message": "X-Partner-Id header is required"} |
| :----------------------------------------------------------------------------------------------------- |

8. Query incentive_schemas for all records matching the partner_id:

| SELECT \* FROM incentive_schemasWHERE partner_id \= :partner_id AND schema_name ILIKE '%' |     | :search |     | '%'; |
| :---------------------------------------------------------------------------------------- | --- | ------- | --- | ---- |

9. Evaluate query result:
   1. If DB query fails → return HTTP 500:

| { "status": "error", "error_code": "INTERNAL_ERROR", "message": "Could not fetch incentive schemas"} |
| :--------------------------------------------------------------------------------------------------- |

2.  If zero rows returned → return HTTP 404
    1. Case A — No search param provided, zero rows:

| { "status": "error", "error_code": "NOT_FOUND", "message": "No incentive schemas found for this partner"} |
| :-------------------------------------------------------------------------------------------------------- |

      2. Case B — search param provided, zero rows matched:

| { "status": "error", "error_code": "NOT_FOUND", "message": "No incentive schemas found matching the given search query"} |
| :----------------------------------------------------------------------------------------------------------------------- |

10. If one or more rows returned → return HTTP 200:

| { "status": "success", "data": { "schemas": \[ { "id": "\<uuid\>", "schema_name": "call_plan", "description": "Daily call plan incentive, summed monthly", "slab_structure": "threshold", "allowed_slab_types": \["value", "percentage"\], "applicable_salesperson_types": \["STO", "SFT"\], "applicable_supervisor_types": \["SPV"\], "supervisor_has_target": false, "salesperson_has_target": true, "supervisor_has_own": false, "target_source_id": "T3", "created_by": "\<uuid\>", "updated_by": "\<uuid\>", } \] }} |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

11. ws2targetsales returns the response to ws-1. ws-1 validates the response structure and forwards it to Closio unchanged.

### Incentive Schema Configs

#### GET /api/incentives/v1/schemas/:schema_id/configs

**Auth headers used:**

- ws-1 will use cookies coming in the header to authenticate and retrieve the user details (in this API we only need partner_id)
- ws2targetsales uses x-client-id and x-client-secret coming in the headers to authenticate
- X-Partner-Id is passed down as a request header

**Path params:**

- schema_id (UUID) — The incentive schema ID

**Query params:**

- month (Integer, 1–12, Optional) — Filter period month
  - year (Integer, Optional) — Filter period year
  - page (Integer, Optional) — Page number, default: 1
  - limit (Integer, Optional) — Records per page, default: 10

**Workflow:**

1. Closio sends GET /api/incentives/v1/schemas/:schema_id/configs to ws-1.
2. ws-1 validates the cookie. If the cookie is invalid → ws-1 returns HTTP 401:

| { "status": "error", "error_code": "TOKEN_INVALID", "message": "User token invalid or expired"} |
| :---------------------------------------------------------------------------------------------- |

3. If cookie is valid → ws-1 retrieves authenticated user details (partner_id).
4. ws-1 validates schema_id path param is a valid UUID. If not → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "schema_id must be a valid UUID"} |
| :-------------------------------------------------------------------------------------------------- |

5. ws-1 validates query params if provided:
   1. month must be an integer between 1–12
   2. year must be a valid integer, max 9999
   3. month and year must both be provided together — passing one without the other is not allowed
   4. page must be an integer \>= 1
   5. limit must be an integer between 1–100
   6. If any fail → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "Request validation failed", "details": { "missing_or_invalid": \["month"\] }} |
| :----------------------------------------------------------------------------------------------------------------------------------------------- |

6. ws-1 prepares a server-to-server request to ws2targetsales:
   1. Add headers: x-client-id, x-client-secret, X-Partner-Id
   2. Pass schema_id in the path param
   3. Pass month, year, page, limit as query params
7. Apply middleware. On any auth failure → return HTTP 401:

| {  "status": "error",  "error_code": "SIGNATURE_INVALID", "message": "Request signature invalid" } |
| :------------------------------------------------------------------------------------------------- |

8. Validate X-Partner-Id header is present. If missing → return HTTP 400:

| { "status": "error", "error_code": "PARTNER_ID_MISSING", "message": "X-Partner-Id header is required"} |
| :----------------------------------------------------------------------------------------------------- |

9. Validate schema_id path param is a valid UUID. If invalid → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "schema_id must be a valid UUID"} |
| :-------------------------------------------------------------------------------------------------- |

10. Verify schema_id exists in incentive_schemas for the given partner_id. If not found → return HTTP 404:

| { "status": "error", "error_code": "NOT_FOUND", "message": "Incentive schema not found for this partner"} |
| :-------------------------------------------------------------------------------------------------------- |

11. Build the query against incentive_schema_configs. If month and year are provided, compute filter_date as the first day of that month (YYYY-MM-01) and apply the period filter:

| SELECT isc.id, is.schema_name, is.description, isc.valid_from, isc.valid_to, isc.status, isc.created_by, isc.created_by_name, isc.updated_by_name, isc.created_at, isc.updated_by, isc.updated_at FROM incentive_schema_configs isc JOIN incentive_schemas is ON isc.schema_id \= is.id WHERE isc.schema_id \= :schema_id AND is.partner_id \= :partner_id \[AND isc.valid_from \<= :filter_date AND isc.valid_to \>= :filter_date\] \-- only if month and year provided ORDER BY isc.valid_from DESC LIMIT :limit OFFSET (:page \- 1) \* :limit; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

12. Execute a count query for pagination metadata:

| SELECT COUNT(\*) FROM incentive_schema_configs isc JOIN incentive_schemas is ON isc.schema_id \= is.id WHERE isc.schema_id \= :schema_id AND is.partner_id \= :partner_id \[AND isc.valid_from \<= :filter_date AND isc.valid_to \>= :filter_date\]; |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

13. Evaluate query result:
    1. If DB query fails → return HTTP 500:

| { "status": "error", "error_code": "INTERNAL_ERROR", "message": "Could not fetch incentive schema configs"} |
| :---------------------------------------------------------------------------------------------------------- |

    2. If count is 0 → return HTTP 200 with empty records:

| { "status": "success", "data": { "records": \[\], "pagination": { "current_page": 1, "total_pages": 0, "total_records": 0, "records_per_page": 10, "has_next": false, "has_previous": false } }} |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

14. If records found → return HTTP 200:

| { "status": "success", "data": { "records": \[ { "id": "\<uuid\>", "schema_name": "call_plan", "description": "Daily call plan completion incentive, summed monthly", "valid_from": "2026-01-01T00:00:00Z", "valid_to": "2026-12-31T00:00:00Z", "status": "active", "created_by": "\<uuid\>", "created_at": "2026-01-01T00:00:00Z", "created_by_name": "Budi Santoso",  "updated_by_name": null, "updated_by": "\<uuid\>", "updated_at": "2026-01-01T00:00:00Z" } \], "pagination": { "current_page": 1, "total_pages": 5, "total_records": 48, "records_per_page": 10, "has_next": true, "has_previous": false } } } |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

15. ws2targetsales returns the response to ws-1. ws-1 validates the response structure and forwards it to Closio unchanged.

#### GET /api/incentives/v1/schemas/:schema_id/configs/:config_id

**Auth headers used:**

- ws-1 will use cookies coming in the header to authenticate and retrieve the user details (in this API we only need partner_id)
- ws2targetsales uses x-client-id and x-client-secret coming in the headers to authenticate
- X-Partner-Id is passed down as a request header

**Path params:**

- schema_id (UUID) — The incentive schema ID
- config_id (UUID) — The config record to view

**Workflow:**

1. Closio sends GET /api/incentives/v1/schemas/:schema_id/configs/:config_id to ws-1.
2. ws-1 validates the cookie. If the cookie is invalid → ws-1 returns HTTP 401:

| { "status": "error", "error_code": "TOKEN_INVALID", "message": "User token invalid or expired"} |
| :---------------------------------------------------------------------------------------------- |

3. If cookie is valid → ws-1 retrieves authenticated user details (partner_id).
4. ws-1 validates path params are valid UUIDs. If not → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "schema_id and config_id must be valid UUIDs"} |
| :--------------------------------------------------------------------------------------------------------------- |

5. ws-1 prepares a server-to-server request to ws2targetsales:

- Add headers: x-client-id, x-client-secret, X-Partner-Id
- Pass schema_id and config_id in the path params

6. Apply middleware. On any auth failure → return HTTP 401:

| {  "status": "error",  "error_code": "SIGNATURE_INVALID", "message": "Request signature invalid" } |
| :------------------------------------------------------------------------------------------------- |

7. Validate X-Partner-Id header is present. If missing → return HTTP 400:

| { "status": "error", "error_code": "PARTNER_ID_MISSING", "message": "X-Partner-Id header is required"} |
| :----------------------------------------------------------------------------------------------------- |

8. Validate path params are valid UUIDs. If invalid → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "schema_id and config_id must be valid UUIDs"} |
| :--------------------------------------------------------------------------------------------------------------- |

9. Verify schema_id exists in incentive_schemas and is mapped to the partner_id. If not found → return HTTP 404:

| { "status": "error", "error_code": "NOT_FOUND", "message": "Incentive schema not found for this partner"} |
| :-------------------------------------------------------------------------------------------------------- |

10. Fetch the config record along with its active slab rows:

| SELECT isc.id, isc.schema_id, is.schema_name, isc.valid_from, isc.valid_to, isc.status, isc.created_by, isc.created_by_name, isc.created_at, isc.updated_by, isc.updated_by_name, \-- NEW isc.updated_at FROM incentive_schema_configs isc JOIN incentive_schemas is ON isc.schema_id \= is.id WHERE isc.id \= :config_id AND isc.schema_id \= :schema_id AND is.partner_id \= :partner_id; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

| SELECT id, salesperson_type, slab_type, symbol, threshold, payout_amount, status, created_by, created_at, updated_by, updated_at FROM incentive_payout_slabs WHERE schema_config_id \= :config_id AND status \= 'active'; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

11. Evaluate query result:
    1. If config not found → return HTTP 404:

| { "status": "error", "error_code": "NOT_FOUND", "message": "Incentive schema config not found"} |
| :---------------------------------------------------------------------------------------------- |

    2. If DB query fails → return HTTP 500:

| { "status": "error", "error_code": "INTERNAL_ERROR", "message": "Could not fetch incentive schema config"} |
| :--------------------------------------------------------------------------------------------------------- |

12. If record found → return HTTP 200:

| { "status": "success", "data": { "config": { "id": "\<uuid\>", "schema_id": "\<uuid\>", "schema_name": "call_plan", "valid_from": "2026-03-01T00:00:00Z", "valid_to": "2026-12-31T00:00:00Z", "status": "active", "created_by": "\<uuid\>", "created_at": "2026-04-17T00:00:00Z", "updated_by": null, "updated_at": "2026-04-17T00:00:00Z", "created_by_name": "Budi Santoso", "updated_by_name": null, "slabs": \[ { "id": "\<uuid\>", "salesperson_type": "STO", "slab_type": "percentage", "symbol": "\>=", "threshold": 90, "payout_amount": 220000, "status": "active", "created_by": "\<uuid\>", "created_at": "2026-01-01T00:00:00Z", "updated_by": null, "updated_at": "2026-01-01T00:00:00Z" } \] } } } |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

13. ws2targetsales returns the response to ws-1. ws-1 validates the response structure and forwards it to Closio unchanged.

#### POST /api/incentives/v1/schemas/:schema_id/configs

**Auth headers used:**

- ws-1 will use cookies coming in the header to authenticate and retrieve the user details (in this API we need partner_id, user_id and user_name)
- ws2targetsales uses x-client-id and x-client-secret coming in the headers to authenticate
- X-Partner-Id, X-User-Id and X-User-Name are passed down as request headers

**Path params:**

- schema_id (UUID) — The incentive schema ID for which the config is being created

**Request body:**

| { "valid_from": "YYYY-MM", "valid_to": "YYYY-MM", "slabs": \[ { "salesperson_type": "STO", "slab_type": "percentage", "symbol": "\>=", "threshold": 90, "payout_amount": 220000 } \]} |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

**Workflow:**

1. Closio sends POST /api/incentives/v1/schemas/:schema_id/configs to ws-1.
2. ws-1 validates the cookie. If the cookie is invalid → ws-1 returns HTTP 401:

| { "status": "error", "error_code": "TOKEN_INVALID", "message": "User token invalid or expired"} |
| :---------------------------------------------------------------------------------------------- |

3. If cookie is valid → ws-1 retrieves authenticated user details (partner_id, user_id, user_name).
4. ws-1 validates schema_id path param is a valid UUID. If not → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "schema_id must be a valid UUID"} |
| :-------------------------------------------------------------------------------------------------- |

5. ws-1 validates presence and basic format of required request body fields:
   1. valid_from and valid_to must be present and in YYYY-MM format
   2. slabs must be present and must be a non-empty array
   3. If any fail → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "Request body validation failed", "details": { "missing_or_invalid": \["valid_from", "slabs"\] }} |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

6. ws-1 prepares a server-to-server request to ws2targetsales:
   1. Add headers: x-client-id, x-client-secret, X-Partner-Id, X-User-Id, X-User-Name
   2. Pass schema_id in the path param
   3. Include the validated request body
7. Apply middleware. On any auth failure → return HTTP 401:

| {  "status": "error",  "error_code": "SIGNATURE_INVALID", "message": "Request signature invalid" } |
| :------------------------------------------------------------------------------------------------- |

8. Validate required headers are present (X-Partner-Id, X-User-Id, X-User-Name). If any missing → return HTTP 400:

| { "status": "error", "error_code": "MISSING_HEADERS", "message": "Required headers are missing", "details": { "missing": \["X-User-Id"\] }} |
| :------------------------------------------------------------------------------------------------------------------------------------------ |

9. Validate schema_id path param is a valid UUID. If invalid → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "schema_id must be a valid UUID"} |
| :-------------------------------------------------------------------------------------------------- |

10. Validate request body fields:
    1. valid_from and valid_to must be present and in YYYY-MM format
    2. slabs must be present and must be a non-empty array
    3. Each slab row must have all fields present: salesperson_type, slab_type, symbol, threshold, payout_amount
    4. If any fail → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "Request body validation failed", "details": { "missing_or_invalid": \["valid_to"\] }} |
| :------------------------------------------------------------------------------------------------------------------------------------------------------- |

11. Verify schema_id exists in incentive_schemas and is mapped to the partner_id. If not found → return HTTP 404:

| { "status": "error", "error_code": "NOT_FOUND", "message": "Incentive schema not found for this partner"} |
| :-------------------------------------------------------------------------------------------------------- |

12. Version level validations:
    1. Parse \`valid_from\` and \`valid_to\` into the first day of their respective months (e.g. \`03-2026\` → \`2026-03-01\`).
    2. Both \`valid_from\` and \`valid_to\` must be the current month or future. If either is a past period → return HTTP 400:

| { "status": "error", "error_code": "INVALID_PERIOD", "message": "valid_from and valid_to must be current month or a future period"} |
| :---------------------------------------------------------------------------------------------------------------------------------- |

    3. \`valid\_to\` must be greater than or equal to \`valid\_from\`. If not → return HTTP 400:

| { "status": "error", "error_code": "INVALID_PERIOD", "message": "valid_to must be greater than or equal to valid_from"} |
| :---------------------------------------------------------------------------------------------------------------------- |

    4. Check for period overlap with existing configs for the same \`schema\_id\` and \`partner\_id\`:

| SELECT id FROM incentive_schema_configs WHERE schema_id \= :schema_id AND valid_from \<= :valid_to AND valid_to \>= :valid_from; |
| :------------------------------------------------------------------------------------------------------------------------------- |

If any record is found → return HTTP 409:

| { "status": "error", "error_code": "PERIOD_OVERLAP", "message": "A config already exists for this schema that overlaps with the given period"} |
| :--------------------------------------------------------------------------------------------------------------------------------------------- |

13. **Slab level validations** (applied to each row in slabs array):
    1. salesperson_type must be one of the values in applicable_salesperson_types or applicable_supervisor_types on the retrieved schema record. If not → return HTTP 400:

| { "status": "error", "error_code": "INVALID_SALESPERSON_TYPE", "message": "salesperson_type is not applicable for this incentive schema", "details": { "invalid_value": "SMF" }} |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

    2. \`slab\_type\` must be one of the values in \`allowed\_slab\_types\` on the retrieved schema record. If not → return HTTP 400:

| { "status": "error", "error_code": "INVALID_SLAB_TYPE", "message": "slab_type is not allowed for this incentive schema", "details": { "allowed": \["percentage"\], "provided": "value" }} |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

    3. \`symbol\` must be one of: \`\>\`, \`\>=\`, \`=\`. If not → return HTTP 400:

| { "status": "error", "error_code": "INVALID_SYMBOL", "message": "symbol must be one of: \>, \>=, \=" } |
| :----------------------------------------------------------------------------------------------------- |

    4. \`threshold\` and \`payout\_amount\` must be positive numeric values with a maximum of 9 digits. If not → return HTTP 400:

| { "status": "error", "error_code": "INVALID_NUMERIC_VALUE", "message": "threshold and payout_amount must be positive numeric values with a maximum of 9 digits"} |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------- |

    5. No duplicate rows — same \`salesperson\_type \+ slab\_type \+ symbol \+ threshold\` combination must not appear more than once in the request. If duplicate found → return HTTP 400:

| { "status": "error", "error_code": "DUPLICATE_SLAB_ROW", "message": "Duplicate slab rows are not allowed", "details": { "duplicate": { "salesperson_type": "STO", "slab_type": "percentage", "symbol": "\>=", "threshold": 90 } }} |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

14. If all validations pass, begin a DB transaction:
    1. a. Insert into incentive_schema_configs:

| INSERT INTO incentive_schema_configs ( schema_id, valid_from, valid_to, status, created_by, created_by_name, created_at, updated_by, updated_by_name, updated_at) VALUES ( :schema_id, :valid_from, :valid_to, 'active', :user_id, :user_name, NOW(), NULL, NULL, NOW()) RETURNING id; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

    2. Bulk insert all slab rows into \`incentive\_payout\_slabs\`:

| INSERT INTO incentive_payout_slabs ( schema_id, schema_config_id, salesperson_type, slab_type, symbol, threshold, payout_amount, status, created_by, created_at, updated_by, updated_at ) VALUES (:schema_id, :config_id, :salesperson_type, :slab_type, :symbol, :threshold, :payout_amount, 'active', :user_id, NOW(), NULL, NOW()), ... \-- one row per slab |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

    3. Commit transaction.
    4. If any DB operation fails → rollback transaction and return HTTP 500:

| { "status": "error", "error_code": "INTERNAL_ERROR", "message": "Could not create incentive schema config"} |
| :---------------------------------------------------------------------------------------------------------- |

15. On success → return HTTP 201:

| { "status": "success", "data": { "config": { "id": "\<uuid\>", "schema_id": "\<uuid\>", "schema_name": "call_plan", "valid_from": "2026-03-01T00:00:00Z", "valid_to": "2026-12-31T00:00:00Z", "status": "active", "created_by": "\<uuid\>", "created_at": "2026-04-17T00:00:00Z", "updated_by": null, "updated_at": "2026-04-17T00:00:00Z", "created_by_name": "Budi Santoso", "updated_by_name": null, "slabs": \[ { "id": "\<uuid\>", "salesperson_type": "STO", "slab_type": "percentage", "symbol": "\>=", "threshold": 90, "payout_amount": 220000, "status": "active", "created_by": "\<uuid\>", "created_at": "2026-01-01T00:00:00Z", "updated_by": null, "updated_at": "2026-01-01T00:00:00Z" } \] } }} |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

16. ws2targetsales returns the response to ws-1. ws-1 validates the response structure and forwards it to Closio unchanged.

#### PATCH /api/incentives/v1/schemas/:schema_id/configs/:config_id

**Auth headers used:**

- ws-1 will use cookies coming in the header to authenticate and retrieve the user details (in this API we need partner_id, user_id and user_name)
- ws2targetsales uses x-client-id and x-client-secret coming in the headers to authenticate
- X-Partner-Id, X-User-Id and X-User-Name are passed down as request headers

**Path params:**

- schema_id (UUID) — The incentive schema ID
- config_id (UUID) — The config record being edited

**Request body:**

| { "valid_from": "YYYY-MM", "valid_to": "YYYY-MM", "is_config_updated": true, "is_slabs_updated": true, "slabs": \[ { "salesperson_type": "STO", "slab_type": "percentage", "symbol": "\>=", "threshold": 90, "payout_amount": 220000 } \]} |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**Workflow:**

1. Closio sends PATCH /api/incentives/v1/schemas/:schema_id/configs/:config_id to ws-1.
2. ws-1 validates the cookie. If the cookie is invalid → ws-1 returns HTTP 401:

| { "status": "error", "error_code": "TOKEN_INVALID", "message": "User token invalid or expired" } |
| :----------------------------------------------------------------------------------------------- |

3. If cookie is valid → ws-1 retrieves authenticated user details (partner_id, user_id, user_name).
4. ws-1 validates path params are valid UUIDs. If not → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "schema_id and config_id must be valid UUIDs"} |
| :--------------------------------------------------------------------------------------------------------------- |

5. ws-1 validates presence and basic format of required request body fields:
   1. is_config_updated and is_slabs_updated must be present and must be booleans
   2. At least one of is_config_updated or is_slabs_updated must be true
   3. If is_config_updated is true → valid_from and valid_to must be present and in YYYY-MM format
   4. If is_slabs_updated is true → slabs must be present and must be a non-empty array
   5. If any fail → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "Request body validation failed", "details": { "missing_or_invalid": \["is_config_updated"\] }} |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------- |

6. ws-1 prepares a server-to-server request to ws2targetsales:
   1. Add headers: x-client-id, x-client-secret, X-Partner-Id, X-User-Id, X-User-Name
   2. Pass schema_id and config_id in the path params
   3. Include the validated request body
7. Apply middleware. On any auth failure → return HTTP 401:

| {  "status": "error",  "error_code": "SIGNATURE_INVALID", "message": "Request signature invalid" } |
| :------------------------------------------------------------------------------------------------- |

8. Validate required headers are present (X-Partner-Id, X-User-Id, X-User-Name). If any missing → return HTTP 400:

| { "status": "error", "error_code": "MISSING_HEADERS", "message": "Required headers are missing", "details": { "missing": \["X-User-Id"\] }} |
| :------------------------------------------------------------------------------------------------------------------------------------------ |

9. Validate path params are valid UUIDs. If invalid → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "schema_id and config_id must be valid UUIDs"} |
| :--------------------------------------------------------------------------------------------------------------- |

10. Verify schema_id exists in incentive_schemas and is mapped to the partner_id. If not found → return HTTP 404:

| { "status": "error", "error_code": "NOT_FOUND", "message": "Incentive schema not found for this partner"} |
| :-------------------------------------------------------------------------------------------------------- |

Store the retrieved schema record for subsequent validations.

11. Fetch the existing config record:

| SELECT \* FROM incentive_schema_configs WHERE id \= :config_id AND schema_id \= :schema_id; |
| :------------------------------------------------------------------------------------------ |

    If not found → return HTTP 404\.

    Store the retrieved config record. Determine the edit case based on the periods:

- **Case 1** — Both valid_from and valid_to are current month or future → full edit allowed
- **Case 2** — valid_from is a past period, valid_to is current month or future → only valid_to is editable, valid_from and slab rows are read-only
- **Case 3** — Both valid_from and valid_to are past → edit not permitted → return HTTP 400:

| { "status": "error", "error_code": "EDIT_NOT_PERMITTED", "message": "This config cannot be edited as both valid_from and valid_to are in the past"} |
| :-------------------------------------------------------------------------------------------------------------------------------------------------- |

12. **If Case 2 and is_slabs_updated is true** → return HTTP 400:

| { "status": "error", "error_code": "SLABS_NOT_EDITABLE", "message": "Slab rows cannot be edited for a config that has already started"} |
| :-------------------------------------------------------------------------------------------------------------------------------------- |

13. **If Case 2 and is_config_updated is true** → validate that only valid_to is being changed. If valid_from in the request body differs from the existing valid_from → return HTTP 400:

| { "status": "error", "error_code": "VALID_FROM_NOT_EDITABLE", "message": "valid_from cannot be changed for a config that has already started"} |
| :--------------------------------------------------------------------------------------------------------------------------------------------- |

14. **If is_config_updated is true** — run version level validations:
    1. Parse valid_from and valid_to into the first day of their respective months.
    2. valid_to must be the current month or future. If past → return HTTP 400:

| { "status": "error", "error_code": "INVALID_PERIOD", "message": "valid_to must be current month or a future period"} |
| :------------------------------------------------------------------------------------------------------------------- |

    3. \`valid\_to\` must be greater than or equal to \`valid\_from\`. If not → return HTTP 400:

| { "status": "error", "error_code": "INVALID_PERIOD", "message": "valid_to must be current month or a future period"} |
| :------------------------------------------------------------------------------------------------------------------- |

    4. Check for period overlap with other existing configs for the same \`schema\_id\` and \`partner\_id\`, excluding the current \`config\_id\`:

| { "status": "error", "error_code": "INVALID_PERIOD", "message": "valid_to must be greater than or equal to valid_from"} |
| :---------------------------------------------------------------------------------------------------------------------- |

If any record found → return HTTP 409:

| { "status": "error", "error_code": "PERIOD_OVERLAP", "message": "The updated period overlaps with an existing config for this schema"} |
| :------------------------------------------------------------------------------------------------------------------------------------- |

15. **If is_slabs_updated is true** — run slab level validations (same as POST API steps 13a through 13e).
16. If all validations pass, begin a DB transaction: a. **If is_config_updated is true** → update incentive_schema_configs:

| UPDATE incentive_schema_configsSET valid_from \= :valid_from, valid_to \= :valid_to, updated_by \= :user_id, updated_by_name \= :user_name, updated_at \= NOW()WHERE id \= :config_id; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**If is_slabs_updated is true** → mark existing active slab rows as deprecated and bulk insert new ones:

| \-- Mark existing slabs as inactiveUPDATE incentive_payout_slabsSET status \= 'deprecated', updated_by \= :user_id, updated_at \= NOW()WHERE schema_config_id \= :config_id AND status \= 'active';\-- Insert new slabsINSERT INTO incentive_payout_slabs ( schema_id, schema_config_id, salesperson_type, slab_type, symbol, threshold, payout_amount, status, created_by, created_at, updated_by, updated_at) VALUES (:schema_id, :config_id, :salesperson_type, :slab_type, :symbol, :threshold, :payout_amount, 'active', :user_id, NOW(), NULL, NOW()), ... |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Commit transaction.

If any DB operation fails → rollback transaction and return HTTP 500:

| { "status": "error", "error_code": "INTERNAL_ERROR", "message": "Could not update incentive schema config"} |
| :---------------------------------------------------------------------------------------------------------- |

17. On success → return HTTP 200:

| { "status": "success", "data": { "config": { "id": "\<uuid\>", "schema_id": "\<uuid\>", "schema_name": "call_plan", "valid_from": "2026-03-01T00:00:00Z", "valid_to": "2026-12-31T00:00:00Z", "status": "active", "created_by": "\<uuid\>", "created_at": "2026-01-01T00:00:00Z", "updated_by": "\<uuid\>", "updated_at": "2026-04-17T00:00:00Z", "created_by_name": "Budi Santoso", "updated_by_name": "Budi Santoso", "slabs": \[ { "id": "\<uuid\>", "salesperson_type": "STO", "slab_type": "percentage", "symbol": "\>=", "threshold": 90, "payout_amount": 220000, "status": "active", "created_by": "\<uuid\>", "created_at": "2026-01-01T00:00:00Z", "updated_by": "\<uuid\>", "updated_at": "2026-04-17T00:00:00Z", } \] } } } |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

18. ws2targetsales returns the response to ws-1. ws-1 validates the response structure and forwards it to Closio unchanged.

#### PATCH /api/incentives/v1/schemas/:schema_id/configs/:config_id/status

**Auth headers used:**

- ws-1 will use cookies coming in the header to authenticate and retrieve the user details (in this API we need partner_id, user_id, user_name)
- ws2targetsales uses x-client-id and x-client-secret coming in the headers to authenticate
- X-Partner-Id, X-User-Id and X-User-Name are passed down as request headers

**Path params:**

- schema_id (UUID) — The incentive schema ID
- config_id (UUID) — The config record to enable or disable

**Request body:**

| { "action": "enable"} |
| :-------------------- |

**Workflow:**

1. Closio sends PATCH /api/incentives/v1/schemas/:schema_id/configs/:config_id/status to ws-1.
2. ws-1 validates the cookie. If the cookie is invalid → ws-1 returns HTTP 401:

| { "status": "error", "error_code": "TOKEN_INVALID", "message": "User token invalid or expired"} |
| :---------------------------------------------------------------------------------------------- |

3. If cookie is valid → ws-1 retrieves authenticated user details (partner_id, user_id).
4. ws-1 validates path params are valid UUIDs. If not → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "schema_id and config_id must be valid UUIDs"} |
| :--------------------------------------------------------------------------------------------------------------- |

5. ws-1 validates action is present in the request body and is one of enable or disable. If not → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "action must be one of: enable, disable"} |
| :---------------------------------------------------------------------------------------------------------- |

6. ws-1 prepares a server-to-server request to ws2targetsales:
   1. Add headers: x-client-id, x-client-secret, X-Partner-Id, X-User-Id, X-User-Name
   2. Pass schema_id and config_id in the path params
   3. Include the validated request body
7. Apply middleware. On any auth failure → return HTTP 401:

| {  "status": "error",  "error_code": "SIGNATURE_INVALID", "message": "Request signature invalid" } |
| :------------------------------------------------------------------------------------------------- |

8. Validate required headers are present (X-Partner-Id, X-User-Id, X-User-Name). If any missing → return HTTP 400:

| { "status": "error", "error_code": "MISSING_HEADERS", "message": "Required headers are missing", "details": { "missing": \["X-User-Id"\]}} |
| :----------------------------------------------------------------------------------------------------------------------------------------- |

9. Validate path params are valid UUIDs. If invalid → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "schema_id and config_id must be valid UUIDs"} |
| :--------------------------------------------------------------------------------------------------------------- |

10. Validate action is present and is one of enable or disable. If not → return HTTP 400:

| { "status": "error", "error_code": "VALIDATION_ERROR", "message": "action must be one of: enable, disable"} |
| :---------------------------------------------------------------------------------------------------------- |

11. Verify schema_id exists in incentive_schemas and is mapped to the partner_id. If not found → return HTTP 404:

| { "status": "error", "error_code": "NOT_FOUND", "message": "Incentive schema not found for this partner"} |
| :-------------------------------------------------------------------------------------------------------- |

12. Fetch the existing config record:

| SELECT \* FROM incentive_schema_configs WHERE id \= :config_id AND schema_id \= :schema_id; |
| :------------------------------------------------------------------------------------------ |

If not found → return HTTP 404:

| { "status": "error", "error_code": "NOT_FOUND", "message": "Incentive schema config not found"} |
| :---------------------------------------------------------------------------------------------- |

13. **If action \= 'enable'** — run the following validations:
    1. Check if valid_to is in the past. If yes → return HTTP 400:

| { "status": "error", "error_code": "CONFIG_EXPIRED", "message": "Cannot enable a config whose validity period has already expired"} |
| :---------------------------------------------------------------------------------------------------------------------------------- |

    2. Check for overlap with any other active config for the same schema\_id and partner\_id:

| SELECT id FROM incentive_schema_configs WHERE schema_id \= :schema_id AND id \!= :config_id AND status \= 'active' AND valid_from \<= :valid_to AND valid_to \>= :valid_from; |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If any record found → return HTTP 409 with details of the conflicting config so the FE can show the popup:

| { "status": "error", "error_code": "OVERLAPPING_ACTIVE_CONFIG", "message": "Cannot enable this config as it overlaps with an existing active config. Please disable the overlapping config first.", "details": { "conflicting_config_id": "\<uuid\>", "conflicting_valid_from": "2026-01", "conflicting_valid_to": "2026-05" }} |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

**If action \= 'disable'** — no additional validations. Proceed directly to update.

14. Update the config status:

UPDATE incentive_schema_configs

| SET status \= CASE WHEN :action \= 'enable' THEN 'active' ELSE 'inactive' END, updated_by \= :user_id, updated_by_name \= :user_name, updated_at \= NOW() |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------- |

15. If DB operation fails → return HTTP 500:

| { "status": "error", "error_code": "INTERNAL_ERROR", "message": "Could not update incentive schema config status"} |
| :----------------------------------------------------------------------------------------------------------------- |

16. On success → return HTTP 200:

| { "status": "success", "data": { "id": "\<uuid\>", "schema_id": "\<uuid\>", "status": "active", "updated_by": "\<uuid\>", "updated_by_name": "Rina Wijaya", "updated_at": "2026-04-17T00:00:00Z" }} |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

17. ws2targetsales returns the response to ws-1. ws-1 validates the response structure and forwards it to Closio unchanged.

# Dependencies

### External Services

**Redis** — Used as the message broker for all BullMQ job queues and as a shared in-memory store for salesperson and supervisor data across worker processes during a calculation run.

**AWS S3 (or equivalent object store)** — Used for storing inbound CSV feed files from Qlik Sense (Ageing) and Task Management (Activation Call). Files are retained for audit and reprocessing purposes.

# Monitoring and Alerting

Metrics to Track

- API response times (p50, p95, p99)
- Error rates by endpoint
- Database query performance

Alerts and Dashboards

- Response time \> 1 second (Warning)
- Error rate \> 5% (Critical)
- Database connection pool exhaustion (Critical)

# Test Plan

- Unit Tests
- Coverage target: 70%
- Focus areas: validation logic, data transformation, API endpoints
- Integration Tests
- Database operations with real PostgreSQL instance
- API endpoint testing with sample data
- Load/Performance Tests
- Single user operations: 500ms target
- Concurrent orders simulation: 1800-2000 customer orders / hour
- Security Testing
- SQL injection prevention
- Input validation bypass attempts
- PII data encryption verification

# Open Questions
