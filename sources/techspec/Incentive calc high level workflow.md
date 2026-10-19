**Incentive Calculation System Workflow**

# **Architecture Overview**

- Two CRON triggers — Calculation CRON (2nd of month) and Catch-up CRON (4th of month)

- Each CRON executes at most once per month per partner. On entry, each CRON atomically inserts a row into incentive_cron_log (ON CONFLICT DO NOTHING). If the insert returns zero rows, the CRON exits immediately without performing any work. This guard survives pod restarts and env variable updates.

- Calculation CRON triggers calculation immediately if any data is available

- Catch-up CRON on 4th reruns all active schemes regardless of whether they were successfully calculated on the 2nd

- Each scheme has its own run_id — fresh one per scheme per CRON run

- 6 separate queues, one per scheme. Single worker per queue

- SP and SPV calculated sequentially in the same job

- Each scheme is fully isolated — failure in one does not affect others

- SP/SPV data fetched once in CRON, stored in Redis, shared across all jobs

- Redis keys use only partner_id as identifier. TTL \= 2 hours. No manual deletion

- All SP/SPV results and errors held in memory during processing, single bulk write at end

- On retry — delete partial results and errors first, then recalculate fresh

- 3 retries max, exponential backoff: 5s → 25s → 125s

- DLQ: incentive-dlq

- One incentive_run_log row per scheme per run

- For different email templates please refer to point 15\.

# **1\. Key Tables Reference**

## **incentive_run_log — one row per scheme per run**

| Column          | Type        | Notes                                             |
| :-------------- | :---------- | :------------------------------------------------ |
| id              | UUID        | Primary key                                       |
| run_id          | UUID        | Unique per scheme per run                         |
| schema_id       | UUID        | Which incentive scheme                            |
| partner_id      | UUID        |                                                   |
| month           | INTEGER     | Month being calculated                            |
| year            | INTEGER     | Year being calculated                             |
| triggered_by    | VARCHAR     | CALCULATION_CRON, CATCHUP_CRON, or MANUAL_TRIGGER |
| triggered_by_id | UUID        | Null for CRON, admin user id for manual           |
| status          | VARCHAR     | pending, processing, success, partial, failed     |
| total           | INTEGER     | Total SPs \+ SPVs eligible                        |
| processed       | INTEGER     | Successfully calculated                           |
| failed          | INTEGER     | Skipped or errored                                |
| completed_at    | TIMESTAMPTZ |                                                   |
| created_at      | TIMESTAMPTZ |                                                   |

## **incentive_run_errors — one row per error**

| Column        | Type        | Notes                                       |
| :------------ | :---------- | :------------------------------------------ |
| id            | UUID        | Primary key                                 |
| run_id        | UUID        | References incentive_run_log                |
| schema_id     | UUID        | Which incentive scheme                      |
| partner_id    | UUID        | Partner Id                                  |
| error_code    | VARCHAR(50) | Standardized error code                     |
| role          | VARCHAR     | SYSTEM, SP, or SPV                          |
| entity_id     | UUID        | SP or SPV id. Null for general errors       |
| payload       | JSONB       | Display context: name, type, any extra info |
| error_message | TEXT        | Human readable detail                       |
| attempt       | INTEGER     | Which retry attempt this error occurred on  |
| is_deprecated | BOOLEAN     | Soft deletion while retrying                |
| created_at    | TIMESTAMPTZ |                                             |

## **incentive_cron_log**

| Column       | Type        | Notes                                                                                                                                                                                                                                                                                            |
| ------------ | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| id           | UUID        | Primary key                                                                                                                                                                                                                                                                                      |
| cron_type    | VARCHAR(20) | 'CALCULATION_CRON' or 'CATCHUP_CRON'                                                                                                                                                                                                                                                             |
| partner_id   | UUID        |                                                                                                                                                                                                                                                                                                  |
| month        | INTEGER     | Month being processed                                                                                                                                                                                                                                                                            |
| year         | INTEGER     | Year being processed                                                                                                                                                                                                                                                                             |
| status       | VARCHAR(20) | 'started', 'completed', or 'failed'                                                                                                                                                                                                                                                              |
| started_at   | TIMESTAMPTZ | When CRON entered execution                                                                                                                                                                                                                                                                      |
| completed_at | TIMESTAMPTZ | Null until CRON finishes all steps. A row with status \= 'failed' and completed_at \= NULL indicates a CRON that crashed mid-execution and was explicitly marked as failed. A row with status \= 'started' and completed_at \= NULL that is not 'failed' indicates a CRON currently in progress. |

INDEX:  
CREATE UNIQUE INDEX uq_cron_log_active ON incentive_cron_log (cron_type, partner_id, month, year) WHERE status IN ('started', 'completed');

– A full UNIQUE constraint is intentionally NOT used.  
– The partial unique index enforces that only one active-or-completed run can exist per period, while allowing a new row to be inserted when the previous run has status \= 'failed'

## **incentive_results** — add **is_deprecated**

One row per SP or SPV per scheme per run. Stores the final computed achievement and payout. The existing status column (pending, success, failed) represents computation state and remains unchanged. A new is_deprecated column is added to represent data lifecycle — whether this result has been superseded by a newer manual run.  
The active result for any SP for a given scheme and month is always the row where is_deprecated \= false.

**Achievement Locking — salesperson_metrics_snapshot**

Similar to the achievements table, the salesperson_metrics_snapshot table requires the same locking mechanism to prevent daily sales webhook updates from modifying snapshot data after the incentive calculation for that month has completed.

Two new columns are added to the salesperson_metrics_snapshot table:

| Column    | Type        | Description                                                                               |
| --------- | ----------- | ----------------------------------------------------------------------------------------- |
| is_locked | BOOLEAN     | Indicates whether this snapshot record is locked from further updates. Defaults to false. |
| locked_at | TIMESTAMPTZ | Timestamp of when the lock was applied. Null until locked.                                |

| ALTER TABLE salesperson_metrics_snapshotADD COLUMN is_locked BOOLEAN NOT NULL DEFAULT FALSE,ADD COLUMN locked_at TIMESTAMPTZ; |
| :---------------------------------------------------------------------------------------------------------------------------- |

# **2\. Error Code Reference**

## **SYSTEM Level Errors**

These errors affect the entire scheme calculation. role \= SYSTEM, entity_id \= null.

| Error Code             | payload                        | When                                                                                             |
| :--------------------- | :----------------------------- | :----------------------------------------------------------------------------------------------- |
| REDIS_WRITE_FAILED     | {}                             | Failed to write SP/SPV data to Redis during CRON                                                 |
| DB_READ_FAILED         | {}                             | DB query failed during scheme data fetch                                                         |
| DB_WRITE_FAILED        | {}                             | Bulk insert transaction failed                                                                   |
| CONFIG_MISSING         | {}                             | No active slab config found for this scheme and period                                           |
| MAX_RETRIES_EXHAUSTED  | {}                             | Job exhausted all 3 retry attempts and moved to DLQ                                              |
| SP_FETCH_FAILED        | {}                             | GET /users?level=1 API call failed                                                               |
| SPV_FETCH_FAILED       | {}                             | GET /users?level=2 API call failed                                                               |
| REPORTEES_FETCH_FAILED | {}                             | One or more GET /users?upline_id=\<spv_id\> API calls failed during CRON reportee pre-population |
| SP_SLAB_MISSING        | {"type": "STO/SFT/SMO"}        | No slab row for this SP type — all SPs of that type skipped                                      |
| SPV_SLAB_MISSING       | {"type": "SPV DRY/MIX/MO/FTO"} | No slab row for this SPV type — all SPVs of that type skipped                                    |

## **SP Level Errors**

These errors affect only a specific salesperson. The rest of the job continues normally. role \= SP.

| Error Code      | payload                        | When                                                         |
| :-------------- | :----------------------------- | :----------------------------------------------------------- |
| SP_DATA_MISSING | {"name": "...", "type": "STO"} | No scheme data found for this specific SP in DB — SP skipped |

## **SPV Level Errors**

These errors affect only a specific supervisor. The rest of the job continues normally. role \= SPV.

| Error Code                 | payload                            | When                                                                         |
| :------------------------- | :--------------------------------- | :--------------------------------------------------------------------------- |
| SPV_REPORTEES_FETCH_FAILED | {"name": "...", "type": "SPV MIX"} | Reporters API failed for this specific supervisor — supervisor skipped       |
| SPV_TYPE_UNRESOLVED        | {"name": "..."}                    | Supervisor type missing or unrecognized in API response — supervisor skipped |
| SPV_NO_REPORTEES           | {"name": "...", "type": "SPV MO"}  | Supervisor has zero reportees — payout set to 0, logged as warning           |

## **Data Check Errors**

These are CRON-level checks only. No DB row is written — Email alert is sent.

| Error Code              | When                                                                                                                                            |
| :---------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------- |
| FEED_AGEING_MISSING     | Ageing feed not received or not in success status                                                                                               |
| FEED_ACTIVATION_MISSING | Activation feed not received or not in success status                                                                                           |
| ACHIEVEMENT_MISSING     | No achievement data found for partner and month                                                                                                 |
| CONFIG_MISSING          | No active slab config found for scheme and period                                                                                               |
| ACHIEVEMENT_NOT_SETTLED | Achievement data exists but is still being actively written — queue has in-flight jobs or last write was within the settlement threshold window |

# **3\. Redis Keys Reference**

| Key                                 | Value                                                                       | TTL     |
| :---------------------------------- | :-------------------------------------------------------------------------- | :------ |
| incentive:{partner_id}:salespersons | JSON array of all level 1 SPs                                               | 2 hours |
| incentive:{partner_id}:supervisors  | JSON array of all level 2 SPVs                                              | 2 hours |
| incentive:{partner_id}:reportees    | Full map { spv_id → \[reportee objects\] } — written by CRON pre-population | 2 hours |

No counter keys. No manual deletion. Keys expire automatically via TTL.

# **4\. Calculation CRON (Fires on 2nd of each month)**

Standalone Node.js cron. Not BullMQ-backed. Processes the previous calendar month. Performs data checks and triggers calculation if data is ready.

**_Note \- For all the checks where email notification is required please check point 15 for email template._**

## **Step 4.0 — Idempotency guard (runs before everything else)**

Insert a sentinel row into incentive_cron_log atomically:

| INSERT INTO incentive_cron_log (cron_type, partner_id, month, year, status, started_at)VALUES ('CALCULATION_CRON', :partner_id, :month, :year, 'started', NOW())ON CONFLICT ON CONSTRAINT uq_cron_log_active DO NOTHINGRETURNING id |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

month and year here refer to the previous calendar month — the period being calculated, not the current calendar month.

If RETURNING returns zero rows — a row with status \= 'started' or 'completed' already exists for this (CALCULATION_CRON, partner_id, month, year) combination. Another execution is currently in progress or has already completed for this period. Exit immediately. No gate checks, no scheme fetches, no emails.  
Note: A row with status \= 'failed' does NOT block this insert — the partial unique index excludes failed rows, so a new 'started' row is inserted cleanly and the CRON proceeds normally.

### **CRON failure handling:**

The CRON wraps all logic from Step 4.1 onward in a try/catch. If an unhandled exception occurs before the 'completed' update in Step 4.6, the catch block updates incentive_cron_log to status \= 'failed' for this row before re-throwing. This is what allows a subsequent CRON or manual trigger to retry — the failed status is excluded from the partial unique index.

| UPDATE incentive_cron_log SET status \= 'failed'WHERE cron_type \= 'CALCULATION_CRON' AND partner_id \= :partner_id AND month \= :month AND year \= :year AND status \= 'started'; |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If RETURNING returns one row — this is the first execution. Proceed to Step 4.1.

## **Step 4.1 — Fetch active schemes dynamically**

Rather than hardcoding the list of schemes, active schemes are fetched from the database:

| SELECT id, scheme_name, target_source_id FROM incentive_schemasWHERE partner_id \= :partner_id; |
| :---------------------------------------------------------------------------------------------- |

The result becomes schemes_to_process for the rest of the CRON.

## **Step 4.2 — Feed Data Check**

Check ageing feed:

| SELECT status FROM feed_webhook_logWHERE partner_id \= :partner_id AND feed_type \= 'ageing'AND month \= :month AND year \= :year AND status \= 'success' |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------- |

If missing or not successful — remove ageing from schemes_to_process and send email alerts with FEED_AGEING_MISSING.

Check activation feed:

| SELECT status FROM feed_webhook_logWHERE partner_id \= :partner_id AND feed_type \= 'activation'AND month \= :month AND year \= :year AND status \= 'success' |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------ |

If missing or not successful — remove activation_call from schemes_to_process and send email alerts with FEED_ACTIVATION_MISSING.

## **Step 4.3 — Achievement Data Check**

For each scheme individually, check achievements using the target_source_id from Step 4.1

| SELECT COUNT(\*) FROM achievementsWHERE target_type_id \= :target_source_idAND partner_id \= :partner_idAND start_date \= :monthStart AND end_date \= :monthEnd |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If COUNT \= 0 for a scheme — remove only that scheme from schemes_to_process and send an individual email alert with ACHIEVEMENT_MISSING for that scheme. Each scheme is evaluated independently. If the table_name is not found in target_types at all, treat it the same as missing data — remove the scheme and alert.

Schemes that pass this check (COUNT \> 0\) proceed to Step 4.3a — Achievement Settlement Check.

## **Step 4.3a — Achievement Settlement Check**

Applies only to achievement-based schemes still in schemes_to_process after Step 4.3. Ageing and activation_call schemes are skipped — they do not use the achievement queues.

The queue-to-scheme mapping is:

| Scheme                       | Queue checked              |
| ---------------------------- | -------------------------- |
| call_plan                    | achievement-daily-callplan |
| unique_transacting_customers | achievement-daily-orders   |
| weekly_revenue               | achievement-daily-orders   |
| monthly_revenue              | achievement-daily-orders   |

For each achievement-based scheme still in schemes_to_process, run two sequential checks:

**Check A — BullMQ queue depth**

For the queue mapped to this scheme:

| active \+ waiting \+ delayed job count \> 0→ queue is in-flight |
| :-------------------------------------------------------------- |

All three states must be checked — active, waiting, and delayed. delayed covers jobs in exponential backoff retry that have not yet re-entered the queue.

If in-flight — remove scheme from schemes_to_process and send email alert with ACHIEVEMENT_NOT_SETTLED using Email Template 1 (reason: QUEUE_IN_FLIGHT). Do not proceed to Check B for this scheme.

**Check B — Staleness heuristic**

Only runs if Check A passes (queue depth \= 0).

| SELECT MAX(updated_at) AS last_updatedFROM achievementsWHERE partner_id \= :partner_id AND start_date \= :month_start AND end_date \= :month_end |
| :----------------------------------------------------------------------------------------------------------------------------------------------- |

Where month_start and month_end are the first and last day of the previous calendar month being calculated.

Evaluate result:

| minutes_since_last_write \= (NOW() \- last_updated) in minutesif minutes_since_last_write \< ACHIEVEMENT_SETTLE_THRESHOLD_MINUTES: → still settling |
| :-------------------------------------------------------------------------------------------------------------------------------------------------- |

If still settling — remove scheme from schemes_to_process and send email alert with ACHIEVEMENT_NOT_SETTLED using Email Template 1 (reason: STILL_SETTLING, include minutes_since_last_write and last_updated in payload).

If last_updated is NULL — this means no achievement rows exist. Step 4.3 already handles COUNT \= 0\. This state should not be reached here. Treat as settled and continue — the scheme was already removed in Step 4.3 if COUNT was 0\.

Note: ACHIEVEMENT_SETTLE_THRESHOLD_MINUTES is an environment variable. Default value: 30\.

## **Step 4.4 — Slab Config Check**

For each scheme still in schemes_to_process:

| SELECT id FROM incentive_schema_configsWHERE schema_id \= :schema_id AND status \= 'active'AND valid_from \<= :calc_month_start AND valid_to \>= :calc_month_end |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If missing — remove scheme from schemes_to_process  
If found — store config_id for this scheme to include in the job payload.

## **Step 4.5 — Check if anything is left**

If schemes_to_process is empty — exit. Nothing to calculate.

## **Step 4.6 — Create run log rows and enqueue jobs**

For each scheme in schemes_to_process, generate a unique run_id and insert into incentive_run_log:

| INSERT INTO incentive_run_log (run_id, schema_id, partner_id, month, year, triggered_by, status, total, processed, failed)VALUES (:run_id, :schema_id, :partner_id, :month, :year, 'CALCULATION_CRON', 'pending', 0, 0, 0) |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Enqueue job into the scheme's dedicated queue:

| Scheme                       | Queue                              |
| :--------------------------- | :--------------------------------- |
| call_plan                    | call-plan-queue                    |
| unique_transacting_customers | unique-transacting-customers-queue |
| weekly_revenue               | weekly-revenue-queue               |
| monthly_revenue              | monthly-revenue-queue              |
| ageing                       | ageing-queue                       |
| activation_call              | activation-call-queue              |

Job payload:

| {  "run_id": "\<uuid\>",  "schema_id": "\<uuid\>",  "config_id": "\<uuid\>", "partner_id": "\<uuid\>",  "month": 3,  "year": 2026, } |
| :----------------------------------------------------------------------------------------------------------------------------------- |

After all scheme rows are inserted into incentive_run_log and all jobs are enqueued into their respective queues, mark the CRON execution as completed:

| UPDATE incentive_cron_log SET status \= 'completed', completed_at \= NOW() WHERE cron_type \= 'CALCULATION_CRON' AND partner_id \= :partner_id AND month \= :month AND year \= :year |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Note: if the CRON exits early at Step 4.5 (schemes_to_process is empty), this update still runs — the CRON completed its work (there was nothing to enqueue). A CRON that crashed mid-execution will have status \= 'failed' (set by the catch block described in Step 4.0). A row with status \= 'started' and null completed_at that is not subsequently updated to 'failed' indicates a pod that was killed before the catch block could execute; this is operationally distinguishable and useful for debugging.

# **5\. Catch-up CRON (Fires on 4th of each month)**

Reruns all active schemes for the previous month regardless of their status from the 2nd. Previous results for each scheme are deprecated by the worker's retry cleanup (Step 6.2) before new results are written.

**_Note \- For all the checks where email notification is required please check point 15 for email template._**

## **Step 5.0 — Idempotency guard (runs before everything else)**

Insert a sentinel row into incentive_cron_log atomically:

| INSERT INTO incentive_cron_log (cron_type, partner_id, month, year, status, started_at)VALUES ('CALCULATION_CRON', :partner_id, :month, :year, 'started', NOW())ON CONFLICT ON CONSTRAINT uq_cron_log_active DO NOTHINGRETURNING id |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

month and year here refer to the previous calendar month — the same period the Calculation CRON processed on the 2nd.

If RETURNING returns zero rows — exit immediately. No scheme checks, no gate checks, no emails.

If RETURNING returns one row — proceed to Step 5.1.

Note: The Catch-up CRON's guard is independent of the Calculation CRON's guard. The UNIQUE constraint is on (cron_type, partner_id, month, year) — so a CALCULATION_CRON row for March does not block a CATCHUP_CRON row for March. Both can exist for the same period. They guard against their own re-execution only.

## **Step 5.1 — Fetch active schemes dynamically**

Same query as Step 4.1 — fetches all active schemes from incentive_schemas.

## **Step 5.2 — Run data checks for schemes**

Same data checks as Steps 4.2, 4.3, **4.3a**, and 4.4 applied to all active schemes in schemes_to_process.

## **Step 5.3 — Check if anything is left after checks**

If empty — all remaining schemes have missing data. Exit

Note: In all exit paths of the Catch-up CRON — whether exiting at Step 5.3 (all schemes have missing data after checks) or after successfully enqueuing scheme jobs — mark the CRON execution as completed.

| UPDATE incentive_cron_logSET status \= 'completed', completed_at \= NOW()WHERE cron_type \= 'CATCHUP_CRON' AND partner_id \= :partner_id AND month \= :month AND year \= :year |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

# **6\. Scheme Job Processing**

Single worker per queue, concurrency 1\. Same processing logic regardless of whether triggered from the 2nd or 4th CRON.

## **Step 6.1 — Update run log to processing**

| UPDATE incentive_run_log SET status \= 'processing'WHERE run_id \= :run_id AND schema_id \= :schema_id |
| :----------------------------------------------------------------------------------------------------- |

####

#### **Step 6.2 — Lock achievements for Call Plan (T3) and delete redis key for buffer alert**

Once SP and SPV results are bulk written, lock all T3 achievement records for the calculation month to prevent further webhook updates:

| UPDATE achievementsSET is_locked \= true, locked_at \= NOW()WHERE target_type_id \= :t3_target_type_id AND partner_id \= :partner_id AND month \= :month AND year \= :year AND is_locked \= false; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Clear the buffer alert Redis key for the partner and calculation date:

| DEL incentive:buffer-alert:{partner_id}:{YYYY-MM-DD} |
| :--------------------------------------------------- |

Where YYYY-MM-DD is the current date at the time of the incentive calculation.

## **Step 6.3 — Retry cleanup**

Runs at the start of every attempt. Safe on first attempt (nothing to mark). Rather than deleting previous attempt data, all existing rows for this run are marked as deprecated so they are excluded from reporting and future reads while remaining available for audit.

| \-- Mark previous attempt errors as deprecatedUPDATE incentive_run_errorsSET is_deprecated \= trueWHERE run_id \= :run_idAND schema_id \= :schema_id\-- Mark incentive_results rows as deprecatedUPDATE incentive_resultsSET is_deprecated \= trueWHERE run_id \= :run_idAND incentive_schema_id \= :schema_id |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

## **Step 6.4 — Fetch SP and SPV Data from Redis**

Check Redis first, call API only if cache misses. By the time the 4th CRON fires, the 1 hour TTL from the 2nd will have long expired, so in most cases the API will be called and fresh keys will be set.

Check Redis for cached salespersons key incentive:{partner_id}:salespersons and incentive:${partner_id}:supervisors

If found — use cached data. If not found — fetch level 1 salespersons via GET /users?level=1 with pagination and store in Redis:

| await redis.set(\`incentive:${partner_id}:salespersons\`, JSON.stringify(salespersons), "EX", 3600) |
| :-------------------------------------------------------------------------------------------------- |

If API fails — Add to error log table with SP_FETCH_FAILED and exit.

If Redis write fails — Add to error log table with REDIS_WRITE_FAILED and exit.

If found — use cached data. If not found — Fetch level 2 supervisors via GET /users?level=2 with pagination and store in Redis:

If DB query fails → write DB_READ_FAILED and throw. BullMQ retries.

| await redis.set(\`incentive:${partner_id}:supervisors\`, JSON.stringify(supervisorList), "EX", 3600) |
| :--------------------------------------------------------------------------------------------------- |

If the API fails — Add to error log table with SPV_FETCH_FAILED and exit.

If Redis write fails — Add to error log table with REDIS_WRITE_FAILED and exit.

Check Redis for incentive:{partner_id}:reportees.

**If found** — verify that all supervisor IDs in supervisorsList are present as keys in the cached map. For any supervisor ID missing from the cache, call GET /users?upline_id=\<supervisor.id\>to fetch their reportees. The response returns a list of objects — the id key in each object is the salesperson ID. Append the newly fetched entries into the existing map and update the cache with the full merged result.

// spv-3 is missing from cache

const reporteeMap \= JSON.parse(await redis.get(\`incentive:${partner_id}:reportees\`));

// { "spv-1": \[...\], "spv-2": \[...\] }

const reportees \= await fetch(\`GET /users?upline_id=spv-3\`);

reporteeMap\["spv-3"\] \= reportees;

// { "spv-1": \[...\], "spv-2": \[...\], "spv-3": \[...\] }

await redis.set(\`incentive:${partner_id}:reportees\`, JSON.stringify(reporteeMap), "EX", 7200);

**If not found** — call GET /users?upline_id=\<supervisor.id\> for each supervisor in supervisorsList and build the full map from scratch.

const reporteeMap \= {};

for (const supervisor of supervisorsList) {

    const reportees \= await fetch(\`GET /users?upline\_id=${supervisor.id}\`);

    reporteeMap\[supervisor.id\] \= reportees;

}

// { "spv-1": \[...\], "spv-2": \[...\], "spv-3": \[...\] }

await redis.set(\`incentive:${partner_id}:reportees\`, JSON.stringify(reporteeMap), "EX", 7200);

In both cases, store the final reporteeMap \= { supervisor.id → \[reportee objects\] } in Redis as incentive:{partner_id}:reportees with a 2-hour TTL.

If any upline_id call fails → write REPORTEES_FETCH_FAILED and throw. BullMQ retries.

If Redis write fails → write REDIS_WRITE_FAILED and throw. BullMQ retries.

## **Part A — SP Calculation**

### **Step 6.5 — Filter eligible SPs for this scheme**

Filtering will be done using the applicable_salesperson_type columns present in the incentive schema table

| Scheme                       | Eligible SP Types |
| :--------------------------- | :---------------- |
| call_plan                    | STO, SFT          |
| unique_transacting_customers | STO, SFT          |
| weekly_revenue               | STO, SFT, SMO     |
| monthly_revenue              | STO, SFT, SMO     |
| ageing                       | STO, SFT, SMO     |
| activation_call              | STO               |

### **Step 6.6 — Fetch active slab rows for SP types**

| SELECT \* FROM incentive_payout_slabsWHERE schema_config_id \= :config_id AND salesperson_type IN (:eligible_sp_types) AND status \= 'active' |
| :-------------------------------------------------------------------------------------------------------------------------------------------- |

Store in memory as { salesperson_type → \[slab rows\] }.

If any eligible SP type has no slab rows — write SP_SLAB_MISSING with payload  
{ type: 'SMO' } to incentive_run_errors. SPs of that type will be skipped later.

### **Step 6.7 — Fetch scheme-specific data from DB**

| Scheme                       | Table                                        | What is fetched                                      |
| :--------------------------- | :------------------------------------------- | :--------------------------------------------------- |
| call_plan                    | achievements                                 | Daily call plan targets and actuals per SP           |
| unique_transacting_customers | achievements \+ salesperson_metrics_snapshot | Monthly unique transacting customer data             |
| weekly_revenue               | achievements                                 | Weekly revenue targets per SP per week W1–W4         |
| monthly_revenue              | achievements                                 | Monthly revenue targets per SP across focus products |
| ageing                       | ageing_activity                              | AR(0–10 days) and Total AR per SP                    |
| activation_call              | activation_activity                          | Unique customers per SP for the month                |

If DB query fails — write DB_READ_FAILED error and throw. BullMQ retries.

### **Step 6.8 — Calculate each eligible SP (all in memory)**

Initialize accumulators: spResults, spSchemeData, spErrors.

For each eligible SP:

- If no data found in DB — push SP_DATA_MISSING to spErrors and continue to next SP

- Floor any negative net achievement to 0

- Evaluate slab to get payout_amount

- Push result to spResults and scheme-specific data to spSchemeData

Scheme-specific calculation logic:

| Scheme                       | Logic                                                                                                                             |
| :--------------------------- | :-------------------------------------------------------------------------------------------------------------------------------- |
| call_plan                    | Per day D: actuals and actuals/target x 100\. If target \= 0 then achievement \= 0\. Monthly total \= sum of all daily incentives |
| unique_transacting_customers | Achievement Value \= count of unique customers with net sales \> 0\. Achievement % \= value / T4 target x 100                     |
| weekly_revenue               | Per week W1–W4: net revenue / weekly target x 100\. Monthly total \= sum of W1–W4                                                 |
| monthly_revenue              | Achievement Value \= sum of net revenue across all T5 focus products. Combined target vs combined achievement — not per product   |
| ageing                       | Ageing % \= AR(0–10 days) / Total AR x 100\. If Total AR \= 0 then Ageing % \= 0 and payout \= 0                                  |
| activation_call              | Count unique customers from feed with net sales \> 0 in M, M-1, M-2. Value-based slab, no target                                  |

### **Step 6.9 — Bulk write SP results (single transaction)**

All three inserts happen in a single DB transaction:

- Bulk insert all spResults into incentive_results, returning id and salesperson_id

- Bulk insert into the scheme-specific SP table using returned result IDs

- Bulk insert all spErrors into incentive_run_errors

| Scheme                       | SP Table                                                                                         |
| :--------------------------- | :----------------------------------------------------------------------------------------------- |
| call_plan                    | call_plan_incentive_sp (result_id, daily_payouts)                                                |
| unique_transacting_customers | unique_transacting_customer_incentive_sp (result_id, eligible_unique_customers)                  |
| weekly_revenue               | weekly_payout_incentive_sp (result_id, week_label, payout) — one row per week per SP             |
| monthly_revenue              | No scheme-specific table                                                                         |
| ageing                       | ageing_incentive_reference (result_id, ageing_row_reference_id)                                  |
| activation_call              | activation_incentive_sp (result_id, eligible_unique_customers) \+ activation_incentive_reference |

If the transaction fails — rollback, write DB_WRITE_FAILED error and throw. BullMQ retries.

## **Part B — SPV Calculation**

Runs immediately after SP write succeeds.

### **Step 6.10 — Filter eligible supervisors**

Use the incentive_schema table to determine eligible supervisor types for this scheme:

| SELECT applicable_supervisor_type FROM incentive_schemas WHERE id \= :schema_id AND partner_id=:partner_id;; \-- e.g. \["SMO"\] for jot_range_products |
| :----------------------------------------------------------------------------------------------------------------------------------------------------- |

Store result in memory and filter the SP list:

| eligibleSPVs \= supervisorsList.filter(sp \=\> eligible_spv_types.includes(spv.type)) |
| :------------------------------------------------------------------------------------ |

### **Step 6.11 — Fetch active slab rows for SPV types**

| SELECT \* FROM incentive_payout_slabsWHERE schema_config_id \= :config_idAND salesperson_type IN (​​eligibleSPVs') AND status \= 'active' |
| :---------------------------------------------------------------------------------------------------------------------------------------- |

If any SPV type has no slab rows — write SPV_SLAB_MISSING with payload { type: 'SPV DRY' }. SPVs of that type will be skipped later.

### **Step 6.12 — Read SP results from DB into memory**

| SELECT ir.id as result_id, ir.salesperson_id, ir.sp_type, ir.achievement_value, ir.achievement_percentage, ir.payout_amountFROM incentive_results irWHERE ir.run_id \= :run_id AND ir.incentive_schema_id \= :schema_id AND ir.role \= 'SP' |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

Build in-memory map: { salesperson_id → result }.

### **Step 6.13 — Calculate each supervisor (all in memory)**

Initialize accumulators: spvResults, spvSchemeData, spvErrors.

For each supervisor:

- Read reportees from reporteeMap\[supervisor.id\] — already populated in Step 6.4 via GET /users?upline_id=\<supervisor.id\>. If key not found or empty → push SPV_NO_REPORTEES and continue to next supervisor

- Resolve supervisor type (SPV DRY / SPV MIX / SPV MO / SPV FTO). If fails — push SPV_TYPE_UNRESOLVED and continue

- Check slab exists for supervisor type. If not — push SPV_SLAB_MISSING and continue

- If zero reportees — push SPV_NO_REPORTEES, set payout \= 0

- Apply scheme-specific SPV aggregation logic

- Floor any negative achievement to 0

- Evaluate slab to get payout_amount

- Push to spvResults and spvSchemeData

SPV aggregation logic per scheme:

| Scheme                       | SPV Logic                                                                                                                                                |
| :--------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------- |
| call_plan                    | Per day: sum of reportee actuals / sum of reportee targets x 100\. Evaluate daily slab. Sum across all days                                              |
| unique_transacting_customers | SPV target \= sum of T4 targets of reportees \+ SPV's own actual. SPV achievement \= deduplicated union of reportee customers \+ SPV's own               |
| weekly_revenue               | Per week W1–W4: sum of reportee weekly revenue / sum of reportee weekly targets x 100                                                                    |
| monthly_revenue              | SPV target \= sum of T5 targets of reportees \+ SPV's own. SPV achievement \= sum of monthly revenue of reportees \+ SPV's own                           |
| ageing                       | Numerator \= sum of AR(0–10) of reportees \+ SPV's own. Denominator \= sum of Total AR of reportees \+ SPV's own. If denominator \= 0 then ageing % \= 0 |
| activation_call              | SPV target \= sum of (reportee count per SP type x multiplier). SPV achievement \= sum of activation counts of reportees. SPV's own NOT included         |

### **Step 6.14 — Bulk write SPV results (single transaction)**

All three inserts happen in a single DB transaction:

- Bulk insert all spvResults into incentive_results, returning id and salesperson_id

- Bulk insert into the scheme-specific SPV table using returned result IDs

- Bulk insert all spvErrors into incentive_run_errors

| Scheme                       | SPV Table                                                                                             |
| :--------------------------- | :---------------------------------------------------------------------------------------------------- |
| call_plan                    | call_plan_incentive_spv (result_id, daily_payouts)                                                    |
| unique_transacting_customers | unique_transacting_customer_incentive_spv (result_id, unique_customer_transaction_ids)                |
| weekly_revenue               | weekly_payout_incentive_spv (result_id, week_label, sp_result_ids, payout) — one row per week per SPV |
| monthly_revenue              | monthly_revenue_incentive_spv (result_id, incentive_result_ids)                                       |
| ageing                       | ageing_incentive_spv (result_id, incentive_result_ids)                                                |
| activation_call              | activation_incentive_spv (result_id, activation_incentive_result_ids)                                 |

If the transaction fails — rollback, write DB_WRITE_FAILED error and throw. BullMQ retries.

# **7\. Job Completion**

## **Step 7.1 — Update run log**

After SP and SPV are both written successfully:

- status \= partial if any spErrors or spvErrors exist, otherwise status \= success

- total \= eligible SP count \+ eligible SPV count

- processed \= spResults.length \+ spvResults.length

- failed \= spErrors.length \+ spvErrors.length

- completed_at \= NOW()

No Redis cleanup is performed. Keys expire automatically via the 1 hour TTL.

# **8\. Retry and Failure Handling**

| Failure                 | Retryable | Behaviour                                                             |
| :---------------------- | :-------- | :-------------------------------------------------------------------- |
| DB bulk write failed    | Yes       | Rollback, write SYSTEM error, throw, retry up to 3x                   |
| DB read failed          | Yes       | Write SYSTEM error, throw, retry up to 3x                             |
| SP/SPV fetch API failed | Yes       | Write SYSTEM error, throw, retry up to 3x                             |
| SP data missing         | No        | Push SP error, skip that SP, job continues                            |
| Slab missing for a type | No        | Push SYSTEM error with type in payload, skip that type, job continues |
| SPV type unresolved     | No        | Push SPV error, skip that supervisor, job continues                   |
| Job exhausts 3 retries  | Final     | DLQ                                                                   |

On max retries exhausted:

- Update incentive_run_log status to failed

- Write MAX_RETRIES_EXHAUSTED error to incentive_run_errors

- BullMQ automatically moves job to incentive-dlq. The job payload should be like below

  {

  "run_id": "uuid”,

  "schema_id": "uuid",

  "partner_id": "uuid",

  "month": month,

  "year": year,

  "config_id": "uuid",

  "\_sourceQueue": "scheme-queue-name"

  }

# **9\. Full Run Scenarios**

## **Best case — all data ready on 2nd**

- 2nd CRON fetches active schemes, all pass data checks

- SP/SPV data cached in Redis with 1 hour TTL

- All jobs enqueued with fresh run_ids and complete successfully

- 4th CRON reruns all schemes — gate checks pass for all, fresh run_ids generated, previous results deprecated, new results written

## **Partial case — some data missing on 2nd**

- 2nd CRON: 4 schemes pass data checks and are calculated. 2 schemes have missing data — Email alert sent, skipped

- 4th CRON: all 6 schemes go through data checks regardless of 2nd CRON outcome. Previously calculated schemes are rerun with fresh run_ids — old results deprecated. The 2 previously missing schemes are calculated if data is now available, alerted again if still missing.

## **Worst case — all data missing on 2nd**

- 2nd CRON: all schemes fail data checks. Email alert sent. Nothing enqueued. No Redis keys set

- 4th CRON: all 6 schemes go through data checks. Available schemes are calculated with fresh run_ids. Still-missing schemes trigger email alerts.

- Schemes where the achievement queue is in-flight or data has not yet settled beyond the configured threshold are also removed from schemes_to_process at Step 4.3a, with ACHIEVEMENT_NOT_SETTLED alert sent.

# **10\. Error Table — Sample Data**

The following rows illustrate how different error types appear in incentive_run_errors.

| id      | run_id   | schema_id         | error_code                 | role   | entity_id    | payload                                                        | error_message                                                         | attempt | created_at          |
| :------ | :------- | :---------------- | :------------------------- | :----- | :----------- | :------------------------------------------------------------- | :-------------------------------------------------------------------- | :------ | :------------------ |
| err-003 | run-bbc2 | schema-ageing     | DB_READ_FAILED             | SYSTEM | null         | { "table": "ageing_activity" }                                 | DB query failed on ageing_activity                                    | 1       | 2026-03-02 00:02:10 |
| err-004 | run-ccd3 | schema-ageing     | SP_SLAB_MISSING            | SYSTEM | null         | {"type":"SMO"}                                                 | No active slab row found for type SMO                                 | 1       | 2026-03-02 00:05:10 |
| err-005 | run-ccd3 | schema-ageing     | SP_DATA_MISSING            | SP     | sp-uuid-001  | {"name":"Rahul Sharma","type":"STO"}                           | No ageing activity record found for this SP                           | 1       | 2026-03-02 00:05:20 |
| err-006 | run-ccd3 | schema-ageing     | SP_DATA_MISSING            | SP     | sp-uuid-002  | {"name":"Priya Patel","type":"SFT"}                            | No ageing activity record found for this SP                           | 1       | 2026-03-02 00:05:20 |
| err-007 | run-ccd3 | schema-ageing     | SPV_SLAB_MISSING           | SYSTEM | null         | {"type":"SPV DRY"}                                             | No active slab row found for SPV DRY                                  | 1       | 2026-03-02 00:05:45 |
| err-008 | run-ccd3 | schema-ageing     | SPV_REPORTEES_FETCH_FAILED | SPV    | spv-uuid-001 | {"name":"Neha Gupta","type":"SPV MIX"}                         | GET /users?upline_id=spv-uuid-001 returned 503                        | 1       | 2026-03-02 00:05:45 |
| err-009 | run-ccd3 | schema-ageing     | SPV_NO_REPORTEES           | SPV    | spv-uuid-002 | {"name":"Suresh Menon","type":"SPV MO"}                        | Supervisor has zero reportees                                         | 1       | 2026-03-02 00:05:45 |
| err-010 | run-ccd3 | schema-ageing     | SPV_TYPE_UNRESOLVED        | SPV    | spv-uuid-003 | {"name":"Kavitha Reddy"}                                       | Could not resolve supervisor type from salesperson record             | 1       | 2026-03-02 00:05:45 |
| err-011 | run-dde4 | schema-activation | CONFIG_MISSING             | SYSTEM | null         | { "schema_id": "schema-activation", "month": 3, "year": 2026 } | No active slab config found for activation_call for month 3 year 2026 | 1       | 2026-03-02 00:07:00 |

### **Reading the sample data**

err-003 — ageing: DB query timed out on attempt 1\. BullMQ will retry automatically.

err-004 — ageing: SMO slab not configured. All SMO salespersons were skipped as a group.

err-005 and err-006 — ageing: Two specific SPs had no ageing activity data. Only those SPs were skipped.

err-007 — ageing: SPV DRY slab not configured. All SPV DRY supervisors were skipped as a group.

err-008 — ageing: One specific supervisor's reportees API returned 503\. Only that supervisor was skipped.

err-009 — ageing: One supervisor had no reportees. Logged as a warning with payout set to 0\.

err-010 — ageing: One supervisor's type field was null or unrecognized. Only that supervisor was skipped.

err-011 — activation_call: No slab config exists for this period at all. Job failed immediately without calculating anyone.

# **11\. Manual Trigger — Incentive Calculation**

### **Overview**

The manual trigger allows an Admin to re-run incentive calculation for a specific scheme for the most recently closed month. The trigger accepts an optional list of salesperson IDs — if not provided, calculation runs for all eligible salespersons under that scheme. Results from previous runs are not deleted but marked as deprecated, preserving full history.

### **API**

**POST /incentive/v1/manual-trigger**

Request body:

| { "scheme_id": "uuid", "salesperson_ids": \["uuid1", "uuid2"\]} |
| :-------------------------------------------------------------- |

- schema_id is mandatory. Must be a valid UUID of an active incentive schema for the partner.
- salesperson_ids is optional. If omitted, all eligible SPs for the scheme are recalculated.
- Month and year are always derived server-side as the previous calendar month. No client input accepted for a period.
- Response is async — returns run_id immediately. Caller uses run_id to track status.

### **Step 0 — Privileged User Guard**

Before any gate check or DB operation, validate that the requesting admin is permitted to trigger manual recalculation. A fixed list of privileged user IDs is configured via environment variable:

| MANUAL_TRIGGER_ALLOWED_IDS=uuid\-1,uuid\-2,uuid\-3 |
| :------------------------------------------------- |

Extract the requesting user's ID from the auth token in the request header. Check it against this list:

| if (\!MANUAL_TRIGGER_ALLOWED_IDS.includes(requestingUserId)) { return 403 Forbidden} |
| :----------------------------------------------------------------------------------- |

Return 403 Forbidden with the following response:

| { "status": "error", "error_code": "MANUAL_TRIGGER_NOT_AUTHORIZED", "message": "You are not authorized to trigger incentive recalculation"} |
| :------------------------------------------------------------------------------------------------------------------------------------------ |

No DB query is made. Nothing is enqueued. The request is rejected immediately. Only after this check passes does the flow proceed to Step 1 — Pre-run Gate Checks.

### **Step 1 — Pre-run Gate Checks (Synchronous)**

All checks are scoped to the single triggered schema_id only. Other schemes are not checked, not touched, and not affected.

#### **Step 1.0 — Resolve schema**

| SELECT schema_nameFROM incentive_schemasWHERE id \= :schema_id AND partner_id \= :partner_id AND status \= 'active'; |
| :------------------------------------------------------------------------------------------------------------------- |

If not found → return 404 SCHEMA_NOT_FOUND. Store schema_name to determine which subsequent checks apply.

**Step 1.1 — Slab config check (this step is done for all schemes)**

| SELECT id FROM incentive_schema_configsWHERE schema_id \= :schema_id AND status \= 'active' AND valid_from \<= :calc_month_start AND valid_to \>= :calc_month_end; |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If missing → return 400 CONFIG_MISSING. Store config_id for use in job payload.

#### **Step 1.2 — Feed check (only done for ageing and activation_call)**

Only runs if schema_name is ageing or activation_call.

| SELECT status FROM feed_webhook_logWHERE partner_id \= :partner_id AND feed_type \= :feed_type \-- 'ageing' or 'activation' AND month \= :month AND year \= :year AND status \= 'success'; |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If missing or not success → return 400 FEED_NOT_READY.

#### **Step 1.3 — Achievement data check (call_plan, unique_transacting_customers, weekly_revenue, monthly_revenue only)**

Only runs if schema_name is one of the four above. Probe only the single Target Engine API relevant to this scheme:

| schema_name                  | Target API probed |
| ---------------------------- | ----------------- |
| call_plan                    | T3                |
| unique_transacting_customers | T4                |
| weekly_revenue               | T6                |
| monthly_revenue              | T5                |

If error or empty → return 400 ACHIEVEMENT_DATA_NOT_READY.

Then probe the achievements table:

| SELECT COUNT(\*) FROM achievementsWHERE target_type_id \= :target_type_id AND partner_id \= :partner_id AND month \= :month AND year \= :year; |
| :--------------------------------------------------------------------------------------------------------------------------------------------- |

If COUNT \= 0 → return 400 ACHIEVEMENT_DATA_NOT_READY.

#### **Step 1.4 — Achievement Settlement Check**

Runs after Step 1.3 passes (COUNT \> 0). Applies only if schema_name is one of: call_plan, unique_transacting_customers, weekly_revenue, monthly_revenue. Skip for ageing and activation_call.

**Check A — BullMQ queue depth**

Check the queue mapped to this scheme (refer to Step 4.3a for the queue-to-scheme mapping table). If active \+ waiting \+ delayed \> 0:

| return \- 400 ACHIEVEMENT_NOT_SETTLED{ "status": "error", "error_code": "ACHIEVEMENT_NOT_SETTLED", "message": "Achievement data is currently being written. Please retry after the queue has settled.", "reason": "QUEUE_IN_FLIGHT"} |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**Check B — Staleness heuristic**

Only runs if Check A passes. Same query as Step 4.3a Check B. If minutes_since_last_write \< ACHIEVEMENT_SETTLE_THRESHOLD_MINUTES:

| return \- 400 ACHIEVEMENT_NOT_SETTLED{ "status": "error", "error_code": "ACHIEVEMENT_NOT_SETTLED", "message": "Achievement data was updated recently and may still be settling. Please retry in a few minutes.", "reason": "STILL_SETTLING", "minutes_since_last_write": \<value\>} |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Note: If the manual trigger is retried after clearing the settlement condition, the ACHIEVEMENT_NOT_SETTLED response will no longer be returned. Note: the ACHIEVEMENT_NOT_SETTLED email alert uses Email Template 1 when sent from CRON context (Steps 4.3a / 5.2). The Manual Trigger path returns an API error response only — it does not send an email.

### **Step 2 — Create Run Log Row and Enqueue Job**

Generate a fresh run_id and insert into incentive_run_log:

| INSERT INTO incentive_run_log ( run_id, schema_id, partner_id, month, year, triggered_by, triggered_by_id, status, total, processed, failed) VALUES (:run_id, :schema_id, :partner_id, :month, :year, 'MANUAL_TRIGGER', :admin_user_id, 'pending', 0, 0, 0) |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Enqueue job into the scheme's dedicated queue with the following payload:

| { "run_id": "\<uuid\>", "schema_id": "\<uuid\>", "config_id": "\<uuid\>", "partner_id": "\<uuid\>", "month": 3, "year": 2026, "triggered_by": "MANUAL_TRIGGER", "triggered_by_id": "\<admin_user_id\>", "salesperson_ids": \["uuid1", "uuid2"\]} |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

salesperson_ids is null in the payload if this is a full trigger.

Return 202 Accepted with run_id to caller immediately.

**Step 3 — Update Run Log to Processing:**

UPDATE incentive_run_log

| SET status \= 'processing'WHERE run_id \= :run_id AND schema_id \= :schema_id; |
| :----------------------------------------------------------------------------- |

### **Step 4 — Retry Cleanup**

Runs at the start of every attempt. Safe on first attempt (nothing exists yet). On retry, marks all partial results from the previous failed attempt as deprecated so the retry starts from a clean state.

| \-- Mark previous attempt errors as deprecatedUPDATE incentive_run_errorsSET is_deprecated \= trueWHERE run_id \= :run_id AND schema_id \= :schema_id;\-- Mark incentive_results rows as deprecatedUPDATE incentive_resultsSET is_deprecated \= trueWHERE run_id \= :run_id AND incentive_schema_id \= :schema_id; |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

### **Step 5 — Fetch SP and SPV Data from Redis**

### Refer to Step 6.4 ( Scheme job processing ) — the SP, SPV, and reportee fetch logic is identical. Store in memory:

- ### **salespersonsList** — full SP objects including id, name, type, upline

- ### **supervisorsList** — full SPV objects including id, name, type

- ### **reporteeMap** — map of supervisor ID to their list of reportee objects { spv_id → \[reportee objects\] }

### **Step 6 — Resolve Affected Supervisors**

**If salesperson_ids is present (partial trigger)**

Use upline.id from each SP object in salespersonsList to identify affected supervisors directly — no additional API calls needed:

| affected_spv_ids \= unique values of sp.upline.id for each sp in salespersonsList where sp.id is in salesperson_ids and sp.upline is not null |
| :-------------------------------------------------------------------------------------------------------------------------------------------- |

Then for each affected supervisor, read their reportees from reporteeMap\[spv_id\].

**If salesperson_ids is null (full trigger)**

Skip affected supervisor resolution. All supervisors are recalculated using reporteeMap from Redis. Also filter the SPV’s from the applicable_supervisors column present in the incentive_schema table.

### **Part A — SP Calculation**

#### **Step 7 — Filter Eligible SPs**

Filter salespersonsList by the scheme's applicable SP types. Refer to Section 6 — Step 6.4 for the eligible SP types per scheme.

**If salesperson_ids is present** — further filter to only those IDs. Any ID not found in the SP list is logged as a warning and skipped.

**If salesperson_ids is null** — all eligible SPs of the applicable types are included.

| eligible_sp_count \= eligibleSPs.length |
| :-------------------------------------- |

**Step 8 — Fetch Active Slab Rows for SP Types**

| SELECT \* FROM incentive_payout_slabsWHERE schema_config_id \= :config_id AND salesperson_type IN (:eligible_sp_types) AND status \= 'active'; |
| :--------------------------------------------------------------------------------------------------------------------------------------------- |

Store in memory as { salesperson_type → \[slab rows ordered by threshold DESC\] }.

If any eligible SP type has no slab rows → write SP_SLAB_MISSING with { type: 'STO' } to incentive_run_errors. SPs of that type will be skipped.

#### **Step 9 — Fetch Scheme-Specific Data from DB**

Fetch only the data relevant to the triggered scheme. If salesperson_ids is present, scope the query to only those IDs. Refer to Section 12 for the exact queries per scheme — Step 6 of each scheme's CRON workflow (e.g. Call Plan Step 6, Unique Transacting Customers Step 6, etc.).

If DB query fails → write DB_READ_FAILED and throw. BullMQ retries.

#### **Step 10 — Calculate Each Eligible SP (All in Memory)**

Initialize accumulators:

| spResults \= \[\]spSchemeData \= \[\]spErrors \= \[\] |
| :---------------------------------------------------- |

For each SP in eligibleSPs:

- If no data found in DB → push SP_DATA_MISSING to spErrors and continue to next SP.
- Floor any negative net achievement to 0\.
- Apply scheme-specific calculation logic and slab evaluation. Refer to Section 12 — Step 7 of each scheme's CRON workflow for the exact per-SP calculation logic.
- Push result to spResults and scheme-specific data to spSchemeData.

#### **Step 11 — Deprecate Old SP Results and Write New Ones (Single Transaction)**

Before writing new results, mark existing non-deprecated incentive_results rows for the recalculated SPs as deprecated. Then deprecate the linked rows in the scheme-specific SP table. Both the deprecation and the new inserts happen in a single DB transaction.

| \-- Deprecate old SP results for the recalculated SPs onlyUPDATE incentive_resultsSET is_deprecated \= trueWHERE incentive_schema_id \= :schema_id AND partner_id \= :partner_id AND month \= :month AND year \= :year AND role \= 'SP' AND salesperson_id \= ANY(:recalculated_sp_ids) AND is_deprecated \= false; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

Then in the same transaction:

**Insert into incentive_results:**

| INSERT INTO incentive_results ( run_id, incentive_schema_id, partner_id, month, year, salesperson_id, salesperson_name, sp_type, achievement_value, achievement_pct, payout_amount, role, status, is_deprecated) VALUES ... \-- one row per SP in spResultsRETURNING id, salesperson_id; |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Build map: spResultIdMap \= { salesperson_id → result_id }

**Insert into scheme-specific SP tables and SP errors.** Refer to Section 12 — Step 8 of each scheme's CRON workflow for the exact tables and columns.

If the transaction fails → rollback, write DB_WRITE_FAILED, throw. BullMQ retries.

### **Part B — SPV Calculation**

#### **Step 12 — Identify Affected Supervisors**

**If full trigger** — all supervisors from supervisorsList are affected, same as CRON.

**If partial trigger** — only supervisors whose reportees were recalculated in Step 11:

| affected_spv_ids \= unique sp.upline.id for each sp_id in recalculated_sp_ids where upline is not null |
| :----------------------------------------------------------------------------------------------------- |

Only these supervisors are recalculated. All other supervisors are not touched.

| eligible_spv_count \= affected_spv_ids.length |
| :-------------------------------------------- |

**Step 13 — Fetch Active Slab Rows for SPV Types**

| SELECT \* FROM incentive_payout_slabsWHERE schema_config_id \= :config_id AND salesperson_type IN ('SPV DRY', 'SPV MIX', 'SPV MO', 'SPV FTO') AND status \= 'active'; |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Store in memory as { spv_type → \[slab rows ordered by threshold DESC\] }.

If any SPV type has no slab rows → write SPV_SLAB_MISSING with { type: 'SPV DRY' }. SPVs of that type will be skipped.

#### **Step 14 — Read SP Results from DB into Memory**

Read all non-deprecated SP results for this scheme and month — including both newly calculated SPs from this run and any pre-existing SPs that were not recalculated but are reportees of affected supervisors:

| SELECT ir.id as result_id, ir.salesperson_id, ir.sp_type, ir.achievement_value, ir.achievement_percentage, ir.payout_amountFROM incentive_results irWHERE ir.incentive_schema_id \= :schema_id AND ir.partner_id \= :partner_id AND ir.month \= :month AND ir.year \= :year AND ir.role \= 'SP' AND ir.is_deprecated \= false; |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Build in-memory map: { salesperson_id → result }.

This ensures SPV aggregation uses the latest non-deprecated SP result for every reportee — whether they were recalculated in this run or not.

#### **Step 15 — Calculate Each Affected Supervisor (All in Memory)**

Initialize accumulators:

| spvResults \= \[\]spvSchemeData \= \[\]spvErrors \= \[\] |
| :------------------------------------------------------- |

For each supervisor in affected_spv_ids:

- Read reportees from reporteeMap\[supervisor.id\]. If not found or empty → push SPV_NO_REPORTEES, set payout \= 0, push to spvResults and continue.
- Check slab exists for supervisor type. If not → push SPV_SLAB_MISSING and continue.
- Floor any negative achievement to 0\.
- Apply scheme-specific SPV aggregation logic and slab evaluation. Refer to Section 12 — Step 10 of each scheme's CRON workflow for the exact per-SPV calculation logic.
- Push to spvResults and spvSchemeData.

#### **Step 16 — Deprecate Old SPV Results and Write New Ones (Single Transaction)**

Before writing new results, mark existing non-deprecated incentive_results rows for the affected supervisors as deprecated. Both the deprecation and the new inserts happen in a single DB transaction.

| \-- Deprecate old SPV results for affected supervisors onlyUPDATE incentive_resultsSET is_deprecated \= trueWHERE incentive_schema_id \= :schema_id AND partner_id \= :partner_id AND month \= :month AND year \= :year AND role \= 'SPV' AND salesperson_id \= ANY(:affected_spv_ids) AND is_deprecated \= false; |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Then in the same transaction:

**Insert into incentive_results:**

| INSERT INTO incentive_results ( run_id, incentive_schema_id, partner_id, month, year, salesperson_id, salesperson_name, sp_type, achievement_value, achievement_pct, payout_amount, role, status, is_deprecated) VALUES ... \-- one row per SPV in spvResultsRETURNING id, salesperson_id; |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Build map: spvResultIdMap \= { salesperson_id → result_id }

**Insert into scheme-specific SPV table and SPV errors.** Refer to Section 12 — Step 11 of each scheme's CRON workflow for the exact tables and columns.

If the transaction fails → rollback, write DB_WRITE_FAILED, throw. BullMQ retries.

**Step 17 — Update Run Log**

| UPDATE incentive_run_logSET status \= CASE WHEN (spErrors_count \+ spvErrors_count) \> 0 THEN 'partial' ELSE 'success' END, total \= :eligible_sp_count \+ :eligible_spv_count, processed \= :spResults_count \+ :spvResults_count, failed \= :spErrors_count \+ :spvErrors_count, completed_at \= NOW()WHERE run_id \= :run_id; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

### **Retry and Failure Handling**

3 attempts maximum, exponential backoff: 5s → 25s → 125s.

At the start of every retry attempt, cleanup runs first — un-deprecate any rows deprecated by the previous failed attempt and delete any fresh inserts made by that attempt. This ensures each retry starts from a clean state.

On max retries exhausted → update incentive_run_log status to failed, write MAX_RETRIES_EXHAUSTED to incentive_run_errors, BullMQ moves job to incentive-dlq  
The job payload should look like :  
 {

"run_id": "uuid”,

"schema_id": "uuid",

"partner_id": "uuid",

"month": month,

"year": year,

"config_id": "uuid",

"\_sourceQueue": "scheme-queue-name"

}

# **12\. CRON Calculation Workflow**

## **Call Plan Incentive**

### **Overview**

Call plan incentive is calculated daily — for each day D in the month, achievement is evaluated against the slab and a daily incentive is assigned. Monthly total \= sum of all daily incentives. Applicable to STO and SFT salespersons only. SPV has no personal target — their achievement is derived from reportees.

#### **Data Sources**

| Data                      | Source                                                                     |
| ------------------------- | -------------------------------------------------------------------------- |
| Daily actuals and targets | achievements table — actual_achieved and target arrays                     |
| Slab config               | incentive_payout_slabs                                                     |
| SP list                   | Redis → GET /users?level=1                                                 |
| SPV list                  | Redis → GET /users?level=2                                                 |
| SPV reportees             | Redis → incentive:{partner_id}:reportees → GET /users?upline_id=\<spv_id\> |

#### **Job Payload**

The CRON enqueues this job into a call-plan-queue. All values referenced in subsequent steps as "from job payload" refer to this:

| { "run_id": "\<uuid\>", "schema_id": "\<uuid\>", "config_id": "\<uuid\>", "partner_id": "\<uuid\>", "month": 3, "year": 2026, "triggered_by": "CALCULATION_CRON"} |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Note: triggered_by in the job payload reflects which CRON enqueued the job — 'CALCULATION_CRON' if enqueued on the 2nd, 'CATCHUP_CRON' if enqueued on the 4th. Workers do not behave differently based on this value — it is carried through to incentive_run_log for audit purposes only.

#### **Step 1 — Update run log to processing**

run_id and schema_id from job payload.

| UPDATE incentive_run_log SET status \= 'processing'WHERE run_id \= :run_id AND schema_id \= :schema_id; |
| :------------------------------------------------------------------------------------------------------ |

####

#### **Step 2 — Resolve T3 target type ID, lock achievements and clear buffer alert**

partner_id, month, year from job payload.

**2.1 — Resolve T3 target type ID**

| SELECT id FROM target_typesWHERE table_name \= 'target_call_plan' AND status \= 'ACTIVE' AND partner_id \= :partner_id; |
| :---------------------------------------------------------------------------------------------------------------------- |

If not found → write DB_READ_FAILED with message "T3 target type not found" and throw. BullMQ retries.

Store result as t3_target_type_id.

**2.2 — Lock T3 achievements**

Lock all T3 achievement records for the calculation month to prevent further webhook updates:

| UPDATE achievementsSET is_locked \= true, locked_at \= NOW()WHERE target_type_id \= :t3_target_type_id AND partner_id \= :partner_id AND month \= :month AND year \= :year AND is_locked \= false; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**2.3 — Clear buffer alert Redis key**

Clear the buffer alert Redis key for the partner and calculation date:

| DEL incentive:buffer-alert:{partner_id}:{YYYY-MM-DD} |
| :--------------------------------------------------- |

Where YYYY-MM-DD is the current date at the time of the incentive calculation.

#### **Step 3 — Retry cleanup**

Runs at the start of every attempt. Safe on first attempt as nothing exists yet. On retry, marks all partial results from the previous failed attempt as deprecated so the retry starts from a clean state. The scheme-specific table updates must run before the incentive_results update because the subquery relies on incentive_results rows still being identifiable by run_id and schema_id.

run_id and schema_id from job payload.

| \-- Mark previous attempt errors as deprecatedUPDATE incentive_run_errorsSET is_deprecated \= trueWHERE run_id \= :run_id AND schema_id \= :schema_id;\-- Mark incentive_results rows as deprecatedUPDATE incentive_resultsSET is_deprecated \= trueWHERE run_id \= :run_id AND incentive_schema_id \= :schema_id; |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

#### **Step 4 — Fetch SP and SPV data from Redis**

partner_id from job payload.

Check Redis for incentive:{partner_id}:salespersons. If not found → call GET /users?level=1 with pagination, store in Redis with 2 hour TTL. If API fails → write SP_FETCH_FAILED to incentive_run_errors and throw. BullMQ retries.

Check Redis for incentive:{partner_id}:supervisors. If not found → call GET /users?level=2,

If API fails → write SPV_FETCH_FAILED and throw.

Use the incentive_schema table to determine eligible supervisor types for this scheme:

| SELECT applicable_supervisor_type FROM incentive_schemas WHERE id \= :schema_id AND partner_id=:partner_id;; \-- e.g. \["SMO"\] for jot_range_products |
| :----------------------------------------------------------------------------------------------------------------------------------------------------- |

Store result in memory and filter the SP list:

| eligibleSPVs \= supervisorsList.filter(sp \=\> eligible_spv_types.includes(spv.type)) |
| :------------------------------------------------------------------------------------ |

Store eligibleSPVs Redis with 2 hour TTL.

| await redis.set(\`incentive:${partner_id}:supervisors\`, JSON.stringify(eligibleSPVs), "EX", 3600) |
| :------------------------------------------------------------------------------------------------- |

Store both lists in memory:

| salespersonsList \= \[...\] \-- full SP objects including id, name, typesupervisorsList \= \[...\] \-- full SPV objects including id, name, type |
| :----------------------------------------------------------------------------------------------------------------------------------------------- |

Check Redis for incentive:{partner_id}:reportees. If found — verify that all supervisor IDs in supervisorsList are present as keys in the cached map. For any supervisor ID missing from the cache, call GET /users?upline_id=\<supervisor.id\> to fetch their reportees. The response returns a list of objects — the id key in each object is the salesperson ID. Append the newly fetched entries into the existing map and update the cache with the full merged result.  
If not found — call GET /users?upline_id=\<supervisor.id\> for each supervisor in supervisorsList and build the full map from scratch. In both cases, store the final reporteeMap as incentive:{partner_id}:reportees with a 2-hour TTL. If any upline_id call fails → write REPORTEES_FETCH_FAILED and throw. If Redis write fails → write REDIS_WRITE_FAILED and throw. BullMQ retries.

#### **Step 5 — Filter eligible SPs**

Fetch applicable salesperson types for this scheme from the DB:

| SELECT applicable_salesperson_type FROM incentive_schemas WHERE id \= :schema_id AND partner_id \= :partner_id; |
| :-------------------------------------------------------------------------------------------------------------- |

Store results in memory as eligible_sp_types.

If DB query fails → write DB_READ_FAILED and throw. BullMQ retries.

| eligibleSPs \= salespersonsList.filter(sp \=\> eligible_sp_types.includes(sp.type)) |
| :---------------------------------------------------------------------------------- |

Track count for run log later:

| eligible_sp_count \= eligibleSPs.length |
| :-------------------------------------- |

#### **Step 6 — Fetch slab rows for SP types**

config_id from job payload.

| SELECT \* FROM incentive_payout_slabsWHERE schema_config_id \= :config_id AND salesperson_type IN (eligibleSPs) AND status \= 'active'; |
| :-------------------------------------------------------------------------------------------------------------------------------------- |

Store in memory as:

| spSlabMap \= { "STO": \[slab rows ordered by threshold DESC\], "SFT": \[slab rows ordered by threshold DESC\]} |
| :------------------------------------------------------------------------------------------------------------- |

If STO has no slab rows → write SP_SLAB_MISSING with { type: 'STO' } to incentive_run_errors. All STO salespersons will be skipped. Same check independently for SFT.

#### **Step 7 — Fetch achievement data from DB**

**Step 7.1 — Resolve T3 target type ID**

t3_target_type_id from Step 2.1.

**7.2 — Derive month boundaries from job payload**

month and year from job payload.

| month_start \= first day of month \-- e.g. 2026-03-01month_end \= last day of month \-- e.g. 2026-03-31 |
| :------------------------------------------------------------------------------------------------------ |

**7.3 — Fetch achievements**

partner_id from job payload. t3_target_type_id from Step 7.1. month_start and month_end from Step 7.2.

| SELECT salesperson_id, achievement \-\> 'target' AS target, achievement \-\> 'actual_achieved' AS actual_achievedFROM achievementsWHERE partner_id \= :partner_id AND target_type_id \= :t3_target_type_id AND start_date \= :month_start AND end_date \= :month_end; |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Build in-memory map:

| achievementMap \= { "sp-uuid-1": { target: \[20,20,...\], actual_achieved: \[0,3866,...\] }, "sp-uuid-2": { target: \[20,20,...\], actual_achieved: \[8,10,...\] }} |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

If DB query fails → write DB_READ_FAILED and throw. BullMQ retries.

#### **Step 8 — Calculate each eligible SP (all in memory)**

Initialize accumulators:

| spResults \= \[\]spSchemeData \= \[\]spErrors \= \[\] |
| :---------------------------------------------------- |

For each SP in eligibleSPs from Step 5:

**8.1 — Check data exists**

Look up SP in achievementMap using sp.id. If not found → push SP_DATA_MISSING with { name: sp.name, type: sp.type } to spErrors and continue to next SP.

**8.2 — Resolve slab for this SP type**

Look up spSlabMap\[sp.type\]. If no slabs exist for this type → SP was already flagged in Step 6, skip.

**8.3 — Day-level calculation**

For each index D from 0 to 30 (index 0 \= Day 1, index 30 \= Day 31). For months shorter than 31 days, remaining indices will be 0 for both target and actual and contribute nothing.

| target_D \= achievement.target\[D\]actual_D \= achievement.actual_achieved\[D\] |
| :------------------------------------------------------------------------------ |

If target_D \= 0 → daily_incentive_D \= 0, continue to the next day.  
If target_D \> 0:

| achievement_value_D \= actual_Dachievement_pct_D \= (actual_D / target_D) \* 100// Floor negative to 0if achievement_value_D \< 0 → achievement_value_D \= 0if achievement_pct_D \< 0 → achievement_pct_D \= 0 |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Pass to slab evaluator — iterate slab rows from spSlabMap\[sp.type\] in descending threshold order, return payout of first match:

Input passed to evaluator:

| if slab_type \= 'value' → pass achievement_value_Dif slab_type \= 'percentage' → pass achievement_pct_D |
| :------------------------------------------------------------------------------------------------------ |

**Example:**

Slab config for STO (percentage-based):

\>= 90% → Rp. 50,000

\>= 80% → Rp. 30,000

\>= 60% → Rp. 15,000

Day 2 (index 1): target \= 20, actual \= 24

| achievement_pct \= (24 / 20) \* 100 \= 120%120 \>= 90 → match → daily_incentive \= Rp. 50,000 |
| :-------------------------------------------------------------------------------------------- |

Day 1 (index 0): target \= 20, actual \= 0

| achievement_pct \= 0%no match → daily_incentive \= 0 |
| :--------------------------------------------------- |

**8.4 — Monthly total**

| monthly_payout \= sum of daily_incentive_D for D \= 0 to 30total_actual_for_month \= sum of actual_achieved\[D\] for D \= 0 to 30total_target_for_month \= sum of target\[D\] for D \= 0 to 30monthly_achievement_pct \= (total_actual_for_month / total_target_for_month) \* 100 |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

monthly_achievement_pct is stored for reporting only. The actual payout is always the sum of daily incentives.

**8.5 — Push to accumulators**

| spResults.push({ salesperson_id: sp.id, salesperson_name: sp.name, sp_type: sp.type, achievement_value: total_actual_for_month, achievement_pct: monthly_achievement_pct, payout_amount: monthly_payout, role: 'SP'}) |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

| spSchemeData.push({ salesperson_id: sp.id, daily_payouts: \[daily_incentive_0, ..., daily_incentive_30\]}) |
| :--------------------------------------------------------------------------------------------------------- |

#### **Step 9 — Bulk write SP results (single transaction)**

run_id, schema_id, partner_id, month, year from job payload.

Three inserts in one DB transaction:

**9.1 — Insert into incentive_results**

| INSERT INTO incentive_results ( run_id, incentive_schema_id, partner_id, month, year, salesperson_id, salesperson_name, sp_type, achievement_value, achievement_pct, payout_amount, role, status, is_deprecated)VALUES ... \-- one row per SP in spResultsRETURNING id, salesperson_id; |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Build map from RETURNING clause:

| spResultIdMap \= { salesperson_id → result_id } |
| :---------------------------------------------- |

**9.2 — Insert into call_plan_incentive_sp**

result_id from spResultIdMap. daily_payouts from spSchemeData.

| INSERT INTO call_plan_incentive_sp (result_id, daily_payouts)VALUES ... \-- one row per SP |
| :----------------------------------------------------------------------------------------- |

**9.3 — Insert SP errors into incentive_run_errors**

run_id and schema_id from job payload. Error details from spErrors accumulator.

| INSERT INTO incentive_run_errors ( run_id, schema_id, error_code, role, entity_id, payload, error_message, attempt)VALUES ... \-- one row per entry in spErrors |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If transaction fails → rollback, write DB_WRITE_FAILED, throw. BullMQ retries.

#### **Step 10 — Fetch SPV slab rows**

First fetch the applicable supervisor types for the scheme

| SELECT applicable_supervisor_type FROM incentive_schemas WHERE id \= :schema_id AND partner_id \= :partner_id; |
| :------------------------------------------------------------------------------------------------------------- |

Store result in memory as eligible_spv_types.

Filter out eligible supervisor types from the available supervisorList

| eligibleSPVs \= supervisorList.filter(spv \=\> eligible_spv_types.includes(spv.type)) |
| :------------------------------------------------------------------------------------ |

config_id from job payload.

| SELECT \* FROM incentive_payout_slabsWHERE schema_config_id \= :config_id AND salesperson_type IN (eligibleSPVs) AND status \= 'active'; |
| :--------------------------------------------------------------------------------------------------------------------------------------- |

Store in memory as:

| spvSlabMap \= { "SPV DRY": \[slab rows ordered by threshold DESC\], "SPV MIX": \[slab rows ordered by threshold DESC\], "SPV MO": \[slab rows ordered by threshold DESC\], "SPV FTO": \[slab rows ordered by threshold DESC\]} |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If any SPV type has no slab rows → write SPV_SLAB_MISSING with { type: 'SPV DRY' }. SPVs of that type will be skipped.

#### **Step 11 — Calculate each supervisor (all in memory)**

Initialize accumulators:

| spvResults \= \[\]spvSchemeData \= \[\]spvErrors \= \[\] |
| :------------------------------------------------------- |

Track count for run log later:

| eligible_spv_count \= supervisorsList.length |
| :------------------------------------------- |

For each supervisor in supervisorsList from Step 4:

**11.1 — Fetch reportees**

Read reporteeMap\[supervisor.id\] from memory — already populated in Step 4

**11.2 — Check slab exists**

Look up spvSlabMap\[supervisor.type\]. If missing → push SPV_SLAB_MISSING with { type: supervisor.type } and continue.

**11.3 —Get all reportees**

Take all salespersons from reporteeMap\[supervisor.id\] read in Step 11.1.

**11.4 — Check reportees count**

Filter the reportees map with only eligible salesperson type

**const reportees \= (reporteeMap\[spv.id\] || \[\]).filter((r) \=\> spTypes.includes(r.type));**

If zero eligible reportees after filtering → push SPV_NO_REPORTEES with { name: supervisor.name, type: supervisor.type }, set payout_amount \= 0, push to spvResults and continue to next supervisor.

**11.5 — Day-level calculation**

Using achievementMap built in Step 7 — no extra DB call needed.

For each index D from 0 to 30:

| sum_actual_D \= sum of actual_achieved\[D\] for each reportee \-- if reportee not in achievementMap, treat as 0sum_target_D \= sum of target\[D\] for each reportee \-- if reportee not in achievementMap, treat as 0 |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If sum_target_D \= 0 → spv_daily_incentive_D \= 0, continue to next day.  
If sum_target_D \> 0:

| spv_achievement_value_D \= sum_actual_Dspv_achievement_pct_D \= (sum_actual_D / sum_target_D) \* 100// Floor negative to 0if spv_achievement_value_D \< 0 → spv_achievement_value_D \= 0if spv_achievement_pct_D \< 0 → spv_achievement_pct_D \= 0 |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Pass to slab evaluator using spvSlabMap\[supervisor.type\] — same evaluator logic as SP.

**Example:**

SPV MIX slab (percentage-based):

\>= 90% → Rp. 150,000

\>= 80% → Rp. 100,000

\>= 60% → Rp. 50,000

3 reportees on Day 2 (index 1):

| sum_actual_1 \= 24 \+ 16 \+ 28 \= 68sum_target_1 \= 20 \+ 15 \+ 25 \= 60spv_achievement_pct_1 \= (68 / 60) \* 100 \= 113.3%113 \>= 90 → match → spv_daily_incentive_1 \= Rp. 150,000 |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**11.6 — Monthly total**

| spv_monthly_payout \= sum of spv_daily_incentive_D for D \= 0 to 30spv_total_actual_for_month \= sum of sum_actual_D for D \= 0 to 30spv_total_target_for_month \= sum of sum_target_D for D \= 0 to 30spv_monthly_achievement_pct \= (spv_total_actual_for_month / spv_total_target_for_month) \* 100 |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**11.7 — Push to accumulators**

| spvResults.push({ salesperson_id: supervisor.id, salesperson_name: supervisor.name, sp_type: supervisor.type, achievement_value: spv_total_actual_for_month, achievement_pct: spv_monthly_achievement_pct, payout_amount: spv_monthly_payout, role: 'SPV'})spvSchemeData.push({ salesperson_id: supervisor.id, daily_payouts: \[spv_daily_incentive_0, ..., spv_daily_incentive_30\]}) |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

#### **Step 12 — Bulk write SPV results (single transaction)**

run_id, schema_id, partner_id, month, year from job payload.

**12.1 — Insert into incentive_results**

| INSERT INTO incentive_results ( run_id, incentive_schema_id, partner_id, month, year, salesperson_id, salesperson_name, sp_type, achievement_value, achievement_pct, payout_amount, role, status, is_deprecated)VALUES ... \-- one row per SPV in spvResultsRETURNING id, salesperson_id; |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Build map from RETURNING clause:

| spvResultIdMap \= { salesperson_id → result_id } |
| :----------------------------------------------- |

**12.2 — Insert into call_plan_incentive_spv**

result_id from spvResultIdMap. daily_payouts from spvSchemeData.

| INSERT INTO call_plan_incentive_spv (result_id, daily_payouts)VALUES ... \-- one row per SPV |
| :------------------------------------------------------------------------------------------- |

**12.3 — Insert SPV errors into incentive_run_errors**

run_id and schema_id from job payload. Error details from spvErrors accumulator.

| INSERT INTO incentive_run_errors ( run_id, schema_id, error_code, role, entity_id, payload, error_message, attempt)VALUES ... \-- one row per entry in spvErrors |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If transaction fails → rollback, write DB_WRITE_FAILED, throw. BullMQ retries.

#### **Step 13 — Update run log**

All counts tracked from earlier steps. run_id from job payload.

| eligible_sp_count \= eligibleSPs.length \-- from Step 5eligible_spv_count \= supervisorsList.length \-- from Step 11spResults_count \= spResults.length \-- from Step 8spvResults_count \= spvResults.length \-- from Step 11spErrors_count \= spErrors.length \-- from Step 8spvErrors_count \= spvErrors.length \-- from Step 11 |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

| UPDATE incentive_run_logSET status \= CASE WHEN (spErrors_count \+ spvErrors_count) \> 0 THEN 'partial' ELSE 'success' END, total \= :eligible_sp_count \+ :eligible_spv_count, processed \= :spResults_count \+ :spvResults_count, failed \= :spErrors_count \+ :spvErrors_count, completed_at \= NOW()WHERE run_id \= :run_id; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

#### **Error Reference**

| Error code                 | Role   | When                                     |
| -------------------------- | ------ | ---------------------------------------- |
| SP_FETCH_FAILED            | SYSTEM | GET /users?level=1 failed                |
| SPV_FETCH_FAILED           | SYSTEM | GET /users?level=2 failed                |
| DB_READ_FAILED             | SYSTEM | achievements query failed                |
| DB_WRITE_FAILED            | SYSTEM | bulk insert transaction failed           |
| SP_SLAB_MISSING            | SYSTEM | no active slab rows for STO or SFT       |
| SPV_SLAB_MISSING           | SYSTEM | no active slab rows for an SPV type      |
| SP_DATA_MISSING            | SP     | no achievement record found for this SP  |
| SPV_REPORTEES_FETCH_FAILED | SPV    | reportees API failed for this supervisor |
| SPV_TYPE_UNRESOLVED        | SPV    | supervisor type missing or unrecognized  |
| SPV_NO_REPORTEES           | SPV    | supervisor has zero eligible reportees   |

## **Unique Transacting Customers Incentive**

#### **Overview**

Unique transacting customers incentive is calculated once at month end.  
Achievement \= count of unique customers with net sales \> 0 for the month.  
Target comes from T4.  
SPV target \= sum of all reportee SP targets \+ SPV's own unique customer count (since SPV has no formal target).  
SPV achievement \= deduplicated union of all reportee eligible customers \+ SPV's own customers not already in the reportee union. Applicable to STO and SFT salespersons only.

#### **Data Sources**

| Data                                    | Source                                                                              |
| --------------------------------------- | ----------------------------------------------------------------------------------- |
| SP target and unique customer sales map | achievements table — achievement column (target key) and unique_customers column    |
| SPV own customer sales                  | salesperson_metrics_snapshot table — sales_by_product column                        |
| Slab config                             | incentive_payout_slabs                                                              |
| SP list                                 | Redis → GET /users?level=1                                                          |
| SPV list                                | Redis → GET /users?level=2                                                          |
| SPV reportees                           | reporteesRedis → incentive:{partner_id}:reportees → GET /users?upline_id=\<spv_id\> |

#### **Job Payload**

Refer to Call Plan — Job Payload.

#### **Step 1 — Update run log to processing**

Refer to Call Plan — Step 1\.

#### **Step 2 — Lock achievements for Call Plan (T3) and delete redis key for buffer alert**

Refer to Call Plan \- Step 2

#### **Step 3 — Retry cleanup**

Refer to Call Plan — Step 3\.

#### **Step 4 — Fetch SP and SPV data from Redis**

Refer to Call Plan — Step 4\.

#### **Step 5 — Filter eligible SPs**

Refer to Call Plan — Step 5\.

#### **Step 6 — Fetch slab rows for SP types**

Refer to Call Plan — Step 6\.

#### **Step 7 — Fetch achievement data from DB**

**7.1 — Resolve T4 target type ID**

t4_target_type_id from Step 2.1.

**7.2 — Derive month boundaries from job payload**

month and year from job payload.

| month_start \= first day of month \-- e.g. 2026-03-01month_end \= last day of month \-- e.g. 2026-03-31 |
| :------------------------------------------------------------------------------------------------------ |

**7.3 — Fetch achievements for all eligible SPs**

partner_id from job payload. t4_target_type_id from Step 7.1. month_start and month_end from Step 7.2. eligible_sp_ids \= list of IDs from eligibleSPs in Step 5\.

| SELECT id, salesperson_id, achievement \-\> 'target' AS target, unique_customersFROM achievementsWHERE partner_id \= :partner_id AND target_type_id \= :t4_target_type_id AND salesperson_id \= ANY(:eligible_sp_ids) AND start_date \= :month_start AND end_date \= :month_end; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Note — id is fetched for traceability. It will be stored in incentive_result_reference later.

Build in-memory map:

| achievementMap \= { "sp-uuid-1": { achievement_id: "ach-uuid-1", target: 80, unique_customers: { "C1": 150000, "C2": 320000, "C3": 0, "C4": 85000, "C5": 95000 } }, "sp-uuid-2": { achievement_id: "ach-uuid-2", target: 60, unique_customers: { "C2": 200000, "C6": 0, "C7": 45000 } }} |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If DB query fails → write DB_READ_FAILED and throw. BullMQ retries.

#### **Step 8 — Calculate each eligible SP (all in memory)**

Initialize accumulators:

| spResults \= \[\]spSchemeData \= \[\]spErrors \= \[\] |
| :---------------------------------------------------- |

For each SP in eligibleSPs from Step 5:

**8.1 — Check data exists**

Look up SP in achievementMap using sp.id. If not found → push SP_DATA_MISSING with { name: sp.name, type: sp.type } to spErrors and continue to next SP.

**8.2 — Resolve slab for this SP type**

Look up spSlabMap\[sp.type\]. If no slabs exist for this type → SP was already flagged in Step 6, skip.

**8.3 — Derive eligible customers**

From achievementMap\[sp.id\].unique_customers, filter entries where total_sales \> 0:

| eligible_customer_ids \= Object.keys(unique_customers) .filter(customer_id \=\> unique_customers\[customer_id\] \> 0) |
| :-------------------------------------------------------------------------------------------------------------------- |

**Example:**

SP-A unique_customers:

| { "C1": 150000, "C2": 320000, "C3": 0, "C4": 85000, "C5": 95000 }eligible_customer_ids \= \["C1", "C2", "C4", "C5"\] \-- C3 excluded (sales \= 0\)achievement_value \= 4 |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**8.4 — Calculate achievement %**

| target \= achievementMap\[sp.id\].targetachievement_value \= eligible_customer_ids.lengthachievement_pct \= (achievement_value / target) \* 100// Floor negative to 0if achievement_value \< 0 → achievement_value \= 0if achievement_pct \< 0 → achievement_pct \= 0 |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If target \= 0 → achievement_pct \= 0, payout_amount \= 0, push to accumulators and continue.

**8.5 — Slab evaluation**

Pass to slab evaluator using spSlabMap\[sp.type\]. Refer to Call Plan — Step 8.3 for evaluator logic.

Input passed to evaluator:

| if slab_type \= 'value' → pass achievement_valueif slab_type \= 'percentage' → pass achievement_pct |
| :-------------------------------------------------------------------------------------------------- |

**Example:**

Slab config for STO (percentage-based):

\>= 90% → Rp. 400,000

\>= 80% → Rp. 300,000

\>= 70% → Rp. 200,000

| target \= 80achievement_value \= 72achievement_pct \= (72 / 80) \* 100 \= 90%90 \>= 90 → match → payout_amount \= Rp. 400,000 |
| :---------------------------------------------------------------------------------------------------------------------------- |

**8.6 — Push to accumulators**

| spResults.push({ salesperson_id: sp.id, salesperson_name: sp.name, sp_type: sp.type, achievement_value: achievement_value, achievement_pct: achievement_pct, payout_amount: payout_amount, role: 'SP'})spSchemeData.push({ salesperson_id: sp.id, achievement_id: achievementMap\[sp.id\].achievement_id, eligible_customer_ids: eligible_customer_ids, target: target \-- stored for SPV target summation later}) |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

#### **Step 9 — Bulk write SP results (single transaction)**

run_id, schema_id, partner_id, month, year from job payload.

**9.1 — Insert into incentive_results**

| INSERT INTO incentive_results ( run_id, incentive_schema_id, partner_id, month, year, salesperson_id, salesperson_name, sp_type, achievement_value, achievement_pct, payout_amount, role, status, is_deprecated)VALUES ... \-- one row per SP in spResultsRETURNING id, salesperson_id; |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Build map from RETURNING clause:

| spResultIdMap \= { salesperson_id → result_id } |
| :---------------------------------------------- |

**9.2 — Insert into unique_transacting_customer_incentive_sp**

result_id from spResultIdMap. eligible_unique_customers from spSchemeData.

| INSERT INTO unique_transacting_customer_incentive_sp ( result_id, eligible_unique_customers)VALUES ... \-- one row per SP |
| :------------------------------------------------------------------------------------------------------------------------ |

**9.3 — Insert into incentive_result_reference**

result_id from spResultIdMap. achievement_id from spSchemeData. t4_target_type_id from Step 7.1.

| INSERT INTO incentive_result_reference ( result_id, target_type_id, achievement_ids)VALUES ... \-- one row per SP, achievement_ids \= \[achievement_id\] |
| :------------------------------------------------------------------------------------------------------------------------------------------------------- |

**9.4 — Insert SP errors into incentive_run_errors**

| INSERT INTO incentive_run_errors ( run_id, schema_id, error_code, role, entity_id, payload, error_message, attempt)VALUES ... \-- one row per entry in spErrorsIf transaction fails → rollback, write DB_WRITE_FAILED, throw. BullMQ retries. |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

#### **Step 10 — Fetch SPV slab rows**

Refer to Call Plan — Step 10\.

#### **Step 11 — Fetch SPV own customer data from DB**

partner_id, month, year from job payload. supervisor_ids \= list of IDs from supervisorsList fetched in Step 4\. Also filter the SPV’s from the applicable_supervisors column present in the incentive_schema table.

| SELECT salesperson_id, sales_by_productFROM salesperson_metrics_snapshotWHERE partner_id \= :partner_id AND month \= :month AND year \= :year AND salesperson_id \= ANY(:supervisor_ids); |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

For each supervisor, derive own eligible customers from sales_by_product:

sales_by_product structure:

| { "\<customer_id\>": { "\<product_id\>": \<net_sales\> }} |
| :-------------------------------------------------------- |

For each customer, sum net_sales across all products. If total \> 0 → customer is eligible.

| spv_own_customers_map \= { "spv-uuid-1": \["C5", "C8", "C9"\], "spv-uuid-2": \["C10", "C11"\]} |
| :--------------------------------------------------------------------------------------------- |

If DB query fails → write DB_READ_FAILED and throw. BullMQ retries.

#### **Step 12 — Lock salesperson_metrics_snapshot**

partner_id, month, year from job payload.

| UPDATE salesperson_metrics_snapshotSET is_locked \= true, locked_at \= NOW()WHERE partner_id \= :partner_id AND month \= :month AND year \= :year AND is_locked \= false; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

If this update fails → write DB_WRITE_FAILED and throw. BullMQ retries.

#### **Step 13 — Calculate each supervisor (all in memory)**

Initialize accumulators:

| spvResults \= \[\]spvSchemeData \= \[\]spvErrors \= \[\] |
| :------------------------------------------------------- |

Track count for run log later:

| eligible_spv_count \= supervisorsList.length |
| :------------------------------------------- |

For each supervisor in supervisorsList from Step 4:

**13.1 through 13.4** — Refer to Call Plan — Steps 11.1 through 11.4

**13.5 — Build SP union customer list**

From spSchemeData, collect eligible_customer_ids for each reportee and take union (deduplicated):

| sp_union_customers \= new Set()for each reportee in reportees: if spSchemeData\[reportee.id\] exists: spSchemeData\[reportee.id\].eligible_customer_ids.forEach(c \=\> sp_union_customers.add(c)) |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

**Example:**

| SP\-A eligible: \["C1", "C2", "C4", "C5"\]SP\-B eligible: \["C2", "C6", "C7"\]sp_union_customers \= Set { "C1", "C2", "C4", "C5", "C6", "C7" } \-- C2 deduplicated |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**13.6 — Derive SPV's own final customer list**

SPV's own customers from spv_own_customers_map\[supervisor.id\]. Exclude any customer already in sp_union_customers to avoid double counting:

| spv_own_all \= spv_own_customers_map\[supervisor.id\] ?? \[\]spv_own_final \= spv_own_all.filter(c \=\> \!sp_union_customers.has(c)) |
| :----------------------------------------------------------------------------------------------------------------------------------- |

**Example:**

| spv_own_all \= \["C2", "C5", "C8"\]sp_union \= Set { "C1", "C2", "C4", "C5", "C6", "C7" }spv_own_final \= \["C8"\] \-- C2 and C5 already in SP union, excluded |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**13.7 — Compute SPV achievement and target**

| spv_achievement \= sp_union_customers.size \+ spv_own_final.length \= 6 \+ 1 \= 7// SPV target \= sum of all reportee SP targets \+ SPV's own final customer count// (SPV has no formal target \-- own customers count substitutes)spv_target \= sum of spSchemeData\[reportee.id\].target for each reportee \+ spv_own_final.length (this will be the deduplicated final row) |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If reportee not found in spSchemeData (SP_DATA_MISSING) → treat their target as 0\.

**Example:**

| SP-A target \= 80SP-B target \= 60spv_own_final count \= 1spv_target \= 80 \+ 60 \+ 1 \= 141spv_achievement \= 7 |
| :--------------------------------------------------------------------------------------------------------------- |

**13.8 — Achievement % and slab evaluation**

If spv_target \= 0:

| spv_achievement_pct \= 0spv_payout_amount \= 0 |
| :--------------------------------------------- |

Push to accumulators and continue.

If spv_target \> 0:

| spv_achievement_pct \= (spv_achievement / spv_target) \* 100// Floor negative to 0if spv_achievement_pct \< 0 → spv_achievement_pct \= 0 |
| :--------------------------------------------------------------------------------------------------------------------------------------- |

Pass to slab evaluator using spvSlabMap\[supervisor.type\]. Refer to Call Plan — Step 8.3 for evaluator logic.

**Example:**

SPV MIX slab (percentage-based):

\>= 90% → Rp. 800,000  
\>= 80% → Rp. 600,000  
\>= 70% → Rp. 400,000

| spv_achievement_pct \= (7 / 141) \* 100 \= 4.96%no match → spv_payout_amount \= 0 |
| :-------------------------------------------------------------------------------- |

**13.9 — Push to accumulators**

| spvResults.push({ salesperson_id: supervisor.id, salesperson_name: supervisor.name, sp_type: supervisor.type, achievement_value: spv_achievement, achievement_pct: spv_achievement_pct, payout_amount: spv_payout_amount, role: 'SPV'})spvSchemeData.push({ salesperson_id: supervisor.id, unique_customer_transaction_ids: reportees.map(r \=\> spResultIdMap\[r.id\]).filter(Boolean)}) |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

#### **Step 14 — Bulk write SPV results (single transaction)**

run_id, schema_id, partner_id, month, year from job payload.

**14.1 — Insert into incentive_results**

| INSERT INTO incentive_results ( run_id, incentive_schema_id, partner_id, month, year, salesperson_id, salesperson_name, sp_type, achievement_value, achievement_pct, payout_amount, role, status, is_deprecated)VALUES ... \-- one row per SPV in spvResultsRETURNING id, salesperson_id; |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Build map from RETURNING clause:

| spvResultIdMap \= { salesperson_id → result_id } |
| :----------------------------------------------- |

**14.2 — Insert into unique_transacting_customer_incentive_spv**

result_id from spvResultIdMap. unique_customer_transaction_ids from spvSchemeData.

| INSERT INTO unique_transacting_customer_incentive_spv ( result_id, unique_customer_transaction_ids)VALUES ... \-- one row per SPV |
| :-------------------------------------------------------------------------------------------------------------------------------- |

**14.3 — Insert SPV errors into incentive_run_errors**

| INSERT INTO incentive_run_errors ( run_id, schema_id, error_code, role, entity_id, payload, error_message, attempt)VALUES ... \-- one row per entry in spvErrors |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If transaction fails → rollback, write DB_WRITE_FAILED, throw. BullMQ retries.

#### **Step 15 — Update run log**

Refer to Call Plan — Step 13\. eligible_sp_count from Step 5, eligible_spv_count from Step 12\.

#### **Error Reference**

Refer to Call Plan — Error Reference. DB_READ_FAILED also covers T4 target type lookup and salesperson_metrics_snapshot query failure.

### **Weekly Revenue Incentive**

#### **Overview**

Weekly revenue incentive is calculated per week — for each week W in the month (W1 to W4), achievement is evaluated against the slab and a weekly incentive is assigned. Monthly total \= sum of all weekly incentives. Weeks are defined by the master calendar, not calendar weeks. Applicable to STO, SFT, and SMO salespersons. SPV has their own target and revenue included alongside reportees.

#### **Data Sources**

| Data                       | Source                                                                     |
| -------------------------- | -------------------------------------------------------------------------- |
| Weekly actuals and targets | achievements table — actual_achieved and target arrays (4 elements, W1–W4) |
| Slab config                | incentive_payout_slabs                                                     |
| SP list                    | Redis → GET /users?level=1                                                 |
| SPV list                   | Redis → GET /users?level=2                                                 |
| SPV reportees              | Redis → incentive:{partner_id}:reportees → GET /users?upline_id=\<spv_id\> |

#### **Job Payload**

The CRON enqueues this job into a weekly-revenue-queue

Refer Call Plan \- Job Payload

#### **Step 1 — Update run log to processing**

Refer to Call Plan — Step 1\.

#### **Step 2 — Lock achievements for Call Plan (T3) and delete redis key for buffer alert**

Refer to Call Plan \- Step 2

#### **Step 3 — Retry cleanup**

Refer to Call Plan — Step 3

#### **Step 4 — Fetch SP and SPV data from Redis**

Refer to Call Plan — Step 4\.

#### **Step 5 — Filter eligible SPs**

Refer to Call Plan — Step 5\.

#### **Step 6 — Fetch slab rows for SP types**

Refer to Call Plan — Step 6\.

#### **Step 7 — Fetch achievement data from DB**

**7.1 — Resolve T6 target type ID**

t6_target_type_id from Step 2.1.

**7.2 — Derive month boundaries from job payload**

Refer to Call Plan — Step 7.2.

**7.3 — Fetch achievements for all SPs and SPVs**

partner_id from job payload. t6_target_type_id from Step 7.1. month_start and month_end from Step 7.2.

| SELECT salesperson_id, achievement \-\> 'target' AS target, achievement \-\> 'actual_achieved' AS actual_achievedFROM achievementsWHERE partner_id \= :partner_id AND target_type_id \= :t6_target_type_id AND start_date \= :month_start AND end_date \= :month_end AND status \= 'ACTIVE'; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Note — this query fetches both SP and SPV rows in one call since SPVs also have their own achievement record in this table. Both are stored in the same map and used later for SP calculation (Step 8\) and SPV own revenue (Step 11).

Build in-memory map:

| achievementMap \= { "sp-uuid-1": { target: \[5000, 7500, 6250, 6250\], actual_achieved: \[8000, 4500, 0, 0\] }, "sp-uuid-2": { target: \[4000, 6000, 5000, 5000\], actual_achieved: \[4200, 6500, 5100, 0\] }, "spv-uuid-1": { target: \[3000, 4000, 3500, 3500\], actual_achieved: \[3200, 4200, 3600, 0\] }} |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If DB query fails → write DB_READ_FAILED and throw. BullMQ retries.

#### **Step 8 — Calculate each eligible SP (all in memory)**

Initialize accumulators:

| spResults \= \[\]spSchemeData \= \[\]spErrors \= \[\] |
| :---------------------------------------------------- |

For each SP in eligibleSPs from Step 5:

**8.1 — Check data exists**

Look up SP in achievementMap using sp.id. If not found → push SP_DATA_MISSING with { name: sp.name, type: sp.type } to spErrors and continue to next SP.

**8.2 — Resolve slab for this SP type**

Look up spSlabMap\[sp.type\]. If no slabs exist for this type → SP was already flagged in Step 6, skip.

**8.3 — Week-level calculation**

For each index W from 0 to 3 (index 0 \= W1, index 1 \= W2, index 2 \= W3, index 3 \= W4):

| target_W \= achievement.target\[W\]actual_W \= achievement.actual_achieved\[W\] |
| :------------------------------------------------------------------------------ |

If target_W \= 0 → weekly_incentive_W \= 0, continue to next week.

If target_W \> 0:

| achievement_value_W \= actual_Wachievement_pct_W \= (actual_W / target_W) \* 100// Floor negative to 0if achievement_value_W \< 0 → achievement_value_W \= 0if achievement_pct_W \< 0 → achievement_pct_W \= 0 |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Pass to slab evaluator — iterate slab rows from spSlabMap\[sp.type\] in descending threshold order, return payout of first match. Refer to Call Plan — Step 8.3 for evaluator logic.

Input passed to evaluator:

| if slab_type \= 'value' → pass achievement_value_Wif slab_type \= 'percentage' → pass achievement_pct_W |
| :------------------------------------------------------------------------------------------------------ |

**Example:**

Slab config for STO (percentage-based):

\>= 90% → Rp. 200,000

\>= 80% → Rp. 150,000

\>= 60% → Rp. 100,000

SP achievement data:

| target \= \[5000, 7500, 6250, 6250\]actual_achieved \= \[8000, 4500, 0, 0\] |
| :-------------------------------------------------------------------------- |

W1 (index 0): target \= 5000, actual \= 8000

| achievement_pct \= (8000 / 5000) \* 100 \= 160%160 \>= 90 → match → weekly_incentive_W1 \= Rp. 200,000 |
| :----------------------------------------------------------------------------------------------------- |

W2 (index 1): target \= 7500, actual \= 4500

| achievement_pct \= (4500 / 7500) \* 100 \= 60%60 \>= 90 → no60 \>= 80 → no60 \>= 60 → match → weekly_incentive_W2 \= Rp. 100,000 |
| :------------------------------------------------------------------------------------------------------------------------------- |

W3 (index 2): target \= 6250, actual \= 0

| achievement_pct \= 0%no match → weekly_incentive_W3 \= 0 |
| :------------------------------------------------------- |

W4 (index 3): target \= 6250, actual \= 0

| achievement_pct \= 0%no match → weekly_incentive_W4 \= 0 |
| :------------------------------------------------------- |

**8.4 — Monthly total**

| monthly_payout \= weekly_incentive_W1 \+ weekly_incentive_W2 \+ weekly_incentive_W3 \+ weekly_incentive_W4 \= 200,000 \+ 100,000 \+ 0 \+ 0 \= Rp. 300,000total_actual_for_month \= sum of actual_achieved\[W\] for W \= 0 to 3 \= 8000 \+ 4500 \+ 0 \+ 0 \= 12,500total_target_for_month \= sum of target\[W\] for W \= 0 to 3 \= 5000 \+ 7500 \+ 6250 \+ 6250 \= 25,000monthly_achievement_pct \= (12500 / 25000) \* 100 \= 50% |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

monthly_achievement_pct is stored for reporting only. Payout is always the sum of weekly incentives.

**8.5 — Push to accumulators**

| spResults.push({ salesperson_id: sp.id, salesperson_name: sp.name, sp_type: sp.type, achievement_value: total_actual_for_month, achievement_pct: monthly_achievement_pct, payout_amount: monthly_payout, role: 'SP'})spSchemeData.push({ salesperson_id: sp.id, weekly_payouts: \[ { week_label: 'W1', payout: weekly_incentive_W1 }, { week_label: 'W2', payout: weekly_incentive_W2 }, { week_label: 'W3', payout: weekly_incentive_W3 }, { week_label: 'W4', payout: weekly_incentive_W4 } \]}) |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

#### **Step 9 — Bulk write SP results (single transaction)**

run_id, schema_id, partner_id, month, year from job payload.

**9.1 — Insert into incentive_results**

| INSERT INTO incentive_results ( run_id, incentive_schema_id, partner_id, month, year, salesperson_id, salesperson_name, sp_type, achievement_value, achievement_pct, payout_amount, role, status, is_deprecated)VALUES ... \-- one row per SP in spResultsRETURNING id, salesperson_id; |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Build map from RETURNING clause:

| spResultIdMap \= { salesperson_id → result_id } |
| :---------------------------------------------- |

**9.2 — Insert into weekly_payout_incentive_sp**

result_id from spResultIdMap. weekly_payouts from spSchemeData. One row per week per SP.

| INSERT INTO weekly_payout_incentive_sp (result_id, week_label, payout)VALUES ... \-- 4 rows per SP (W1, W2, W3, W4) |
| :------------------------------------------------------------------------------------------------------------------ |

**9.3 — Insert SP errors into incentive_run_errors**

run_id and schema_id from job payload. Error details from spErrors accumulator.

| INSERT INTO incentive_run_errors ( run_id, schema_id, error_code, role, entity_id, payload, error_message, attempt)VALUES ... \-- one row per entry in spErrors |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If transaction fails → rollback, write DB_WRITE_FAILED, throw. BullMQ retries.

#### **Step 10 — Fetch SPV slab rows**

Refer to Call Plan — Step 10\.

#### **Step 11 — Calculate each supervisor (all in memory)**

Initialize accumulators:

| spvResults \= \[\]spvSchemeData \= \[\]spvErrors \= \[\] |
| :------------------------------------------------------- |

Track count for run log later:

| eligible_spv_count \= supervisorsList.length |
| :------------------------------------------- |

For each supervisor in supervisorsList from Step 4:

**11.1 through 11.4** — Refer to Call Plan — Steps 11.1 through 11.4

**11.6 — Week-level calculation**

Using achievementMap built in Step 7 — no extra DB call needed. SPV's own revenue and target are also in achievementMap under supervisor.id.

For each index W from 0 to 3:

| // Sum reportee actuals and targetssum_reportee_actual_W \= sum of actual_achieved\[W\] for each reportee \-- if reportee not in achievementMap, treat as 0sum_reportee_target_W \= sum of target\[W\] for each reportee \-- if reportee not in achievementMap, treat as 0// Add SPV own revenue and targetspv_own_actual_W \= achievementMap\[supervisor.id\].actual_achieved\[W\] \-- if supervisor not in achievementMap, treat as 0spv_own_target_W \= achievementMap\[supervisor.id\].target\[W\] \-- if supervisor not in achievementMap, treat as 0spv_total_actual_W \= sum_reportee_actual_W \+ spv_own_actual_Wspv_total_target_W \= sum_reportee_target_W \+ spv_own_target_W |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If spv_total_target_W \= 0 → spv_weekly_incentive_W \= 0, continue to next week.

If spv_total_target_W \> 0:

| spv_achievement_value_W \= spv_total_actual_Wspv_achievement_pct_W \= (spv_total_actual_W / spv_total_target_W) \* 100// Floor negative to 0if spv_achievement_value_W \< 0 → spv_achievement_value_W \= 0if spv_achievement_pct_W \< 0 → spv_achievement_pct_W \= 0 |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Pass to slab evaluator using spvSlabMap\[supervisor.type\] — refer to Call Plan — Step 8.3 for evaluator logic.

**Example:**

SPV MIX slab (percentage-based):

\>= 90% → Rp. 500,000

\>= 80% → Rp. 350,000

\>= 60% → Rp. 200,000

SPV MIX has 2 reportees — SP-A and SP-B. SPV also has its own revenue.

Achievement data:

| SP-A: target \= \[5000, 7500, 6250, 6250\], actual_achieved \= \[8000, 4500, 0, 0\]SP-B: target \= \[4000, 6000, 5000, 5000\], actual_achieved \= \[4200, 6500, 5100, 0\]SPV: target \= \[3000, 4000, 3500, 3500\], actual_achieved \= \[3200, 4200, 3600, 0\] |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

W1 (index 0):

| sum_reportee_actual_0 \= 8000 \+ 4200 \= 12200sum_reportee_target_0 \= 5000 \+ 4000 \= 9000spv_own_actual_0 \= 3200spv_own_target_0 \= 3000spv_total_actual_0 \= 12200 \+ 3200 \= 15400spv_total_target_0 \= 9000 \+ 3000 \= 12000spv_achievement_pct_0 \= (15400 / 12000) \* 100 \= 128.3%128.3 \>= 90 → match → spv_weekly_incentive_W1 \= Rp. 500,000 |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

W2 (index 1):

| sum_reportee_actual_1 \= 4500 \+ 6500 \= 11000sum_reportee_target_1 \= 7500 \+ 6000 \= 13500spv_own_actual_1 \= 4200spv_own_target_1 \= 4000spv_total_actual_1 \= 11000 \+ 4200 \= 15200spv_total_target_1 \= 13500 \+ 4000 \= 17500spv_achievement_pct_1 \= (15200 / 17500) \* 100 \= 86.9%86.9 \>= 90 → no86.9 \>= 80 → match → spv_weekly_incentive_W2 \= Rp. 350,000 |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**11.7 — Monthly total**

| spv_monthly_payout \= spv_weekly_incentive_W1 \+ spv_weekly_incentive_W2 \+ spv_weekly_incentive_W3 \+ spv_weekly_incentive_W4 \= 500,000 \+ 350,000 \+ 0 \+ 0 \= Rp. 850,000spv_total_actual_for_month \= sum of spv_total_actual_W for W \= 0 to 3spv_total_target_for_month \= sum of spv_total_target_W for W \= 0 to 3spv_monthly_achievement_pct \= (spv_total_actual_for_month / spv_total_target_for_month) \* 100 |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**11.8 — Push to accumulators**

| spvResults.push({ salesperson_id: supervisor.id, salesperson_name: supervisor.name, sp_type: supervisor.type, achievement_value: spv_total_actual_for_month, achievement_pct: spv_monthly_achievement_pct, payout_amount: spv_monthly_payout, role: 'SPV'})spvSchemeData.push({ salesperson_id: supervisor.id, weekly_payouts: \[ { week_label: 'W1', payout: spv_weekly_incentive_W1 }, { week_label: 'W2', payout: spv_weekly_incentive_W2 }, { week_label: 'W3', payout: spv_weekly_incentive_W3 }, { week_label: 'W4', payout: spv_weekly_incentive_W4 } \]}) |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

#### **Step 12 — Bulk write SPV results (single transaction)**

Refer to Call Plan — Step 12\. The scheme-specific table is weekly_payout_incentive_spv. One row per week per SPV (W1, W2, W3, W4) using week_label, sp_result_ids, and payout columns.sp_result_ids is the list of SP result_id values (from spResultIdMap) for the reportees whose weekly revenue contributed to this SPV's calculation for that week. Built from spvSchemeData in the same way as other SPV scheme tables.

#### **Step 13 — Update run log**

Refer to Call Plan — Step 13\. eligible_sp_count from Step 5, eligible_spv_count from Step 11\.

**Error Reference**

Refer to Call Plan — Error Reference. Additional error for weekly revenue:

DB_READ_FAILED also covers T6 target type lookup failure.

###

### **Monthly Revenue Incentive**

#### **Overview**

Monthly revenue incentive is calculated once at month end. Achievement \= sum of net revenue across all T5 focus product groups for the month. Target \= sum of T5 targets across all focus product groups. Products are not evaluated individually — it is one combined target vs one combined actual. Applicable to STO, SFT, and SMO salespersons. SPV has their own target and revenue included alongside reportees.

#### **Data Sources**

| Data                        | Source                                                                             |
| --------------------------- | ---------------------------------------------------------------------------------- |
| Monthly actuals and targets | achievements table — aggregated across all T5 focus product groups per salesperson |
| Slab config                 | incentive_payout_slabs                                                             |
| SP list                     | Redis → GET /users?level=1                                                         |
| SPV list                    | Redis → GET /users?level=2                                                         |
| SPV reportees               | Redis → incentive:{partner_id}:reportees → GET /users?upline_id=\<spv_id\>         |

#### **Job Payload**

The CRON enqueues this job into a monthly-revenue-queue

Refer Call Plan \- Job Payload

#### **Step 1 — Update run log to processing**

Refer to Call Plan — Step 1\.

#### **Step 2 — Lock achievements for Call Plan (T3) and delete redis key for buffer alert**

Refer to Call Plan \- Step 2\.

#### **Step 3 — Retry cleanup**

Refer to Call Plan — Step 3

#### **Step 4 — Fetch SP and SPV data from Redis**

Refer to Call Plan — Step 4\.

#### **Step 5 — Filter eligible SPs**

Refer to Call Plan — Step 5\.

#### **Step 6 — Fetch slab rows for SP types**

Refer to Call Plan — Step 6\.

#### **Step 7 — Fetch achievement data from DB**

**7.1 — Resolve T5 target type ID**

t5_target_type_id from Step 2.1.

**7.2 — Derive month boundaries from job payload**

Refer to Call Plan — Step 7.2.

**7.3 — Fetch and aggregate achievements per salesperson**

partner_id from job payload. t5_target_type_id from Step 7.1. month_start and month_end from Step 7.2.

Since each salesperson can have multiple rows in achievements (one per focus product group), we aggregate in the query directly — summing target and actual across all focus product groups per salesperson.

| SELECT salesperson_id, SUM((achievement \-\> 'target' \-\> 0)::NUMERIC) AS total_target, SUM((achievement \-\> 'actual_achieved' \-\> 0)::NUMERIC) AS total_actualFROM achievementsWHERE partner_id \= :partner_id AND target_type_id \= :t5_target_type_id AND start_date \= :month_start AND end_date \= :month_end AND status \= 'ACTIVE'GROUP BY salesperson_id; |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Note — this query fetches both SP and SPV rows in one call since SPVs also have their own achievement record in this table. Both are stored in the same map and used later for SP calculation (Step 8\) and SPV own revenue (Step 11).

Build in-memory map:

| achievementMap \= { "sp-uuid-1": { total_target: 50000000, total_actual: 46000000 }, "sp-uuid-2": { total_target: 30000000, total_actual: 28000000 }, "spv-uuid-1": { total_target: 20000000, total_actual: 19000000 }} |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If DB query fails → write DB_READ_FAILED and throw. BullMQ retries.

#### **Step 8 — Calculate each eligible SP (all in memory)**

Initialize accumulators:

| spResults \= \[\]spErrors \= \[\] |
| :-------------------------------- |

For each SP in eligibleSPs from Step 5:

**8.1 — Check data exists**

Look up SP in achievementMap using sp.id. If not found → push SP_DATA_MISSING with { name: sp.name, type: sp.type } to spErrors and continue to next SP.

**8.2 — Resolve slab for this SP type**

Look up spSlabMap\[sp.type\]. If no slabs exist for this type → SP was already flagged in Step 6\. skip.

**8.3 — Monthly calculation**

| total_target \= achievementMap\[sp.id\].total_targettotal_actual \= achievementMap\[sp.id\].total_actualachievement_value \= total_actualachievement_pct \= (total_actual / total_target) \* 100// Floor negative to 0if achievement_value \< 0 → achievement_value \= 0if achievement_pct \< 0 → achievement_pct \= 0 |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Pass to slab evaluator — iterate slab rows from spSlabMap\[sp.type\] in descending threshold order, return payout of first match. Refer to Call Plan — Step 8.3 for evaluator logic.

Input passed to evaluator:

| if slab_type \= 'value' → pass achievement_valueif slab_type \= 'percentage' → pass achievement_pct |
| :-------------------------------------------------------------------------------------------------- |

**Example:**

Slab config for STO (percentage-based):

\>= 90% → Rp. 500,000

\>= 80% → Rp. 350,000

\>= 60% → Rp. 200,000

SP achievement data (aggregated across 2 focus product groups):

| total_target \= 20,000,000 \+ 30,000,000 \= 50,000,000total_actual \= 18,000,000 \+ 28,000,000 \= 46,000,000achievement_pct \= (46,000,000 / 50,000,000) \* 100 \= 92%92 \>= 90 → match → payout_amount \= Rp. 500,000 |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**8.4 — Push to accumulators**

| spResults.push({ salesperson_id: sp.id, salesperson_name: sp.name, sp_type: sp.type, achievement_value: achievement_value, achievement_pct: achievement_pct, payout_amount: payout_amount, role: 'SP'}) |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

#### **Step 9 — Bulk write SP results (single transaction)**

run_id, schema_id, partner_id, month, year from job payload.

**9.1 — Insert into incentive_results**

| INSERT INTO incentive_results ( run_id, incentive_schema_id, partner_id, month, year, salesperson_id, salesperson_name, sp_type, achievement_value, achievement_pct, payout_amount, role, status, is_deprecated)VALUES ... \-- one row per SP in spResults |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**9.2 — Insert SP errors into incentive_run_errors**

run_id and schema_id from job payload. Error details from spErrors accumulator.

| INSERT INTO incentive_run_errors ( run_id, schema_id, error_code, role, entity_id, payload, error_message, attempt)VALUES ... \-- one row per entry in spErrors |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If transaction fails → rollback, write DB_WRITE_FAILED, throw. BullMQ retries.

#### **Step 10 — Fetch SPV slab rows**

Refer to Call Plan — Step 10\.

#### **Step 11 — Calculate each supervisor (all in memory)**

Initialize accumulators:

| spvResults \= \[\]spvSchemeData \= \[\]spvErrors \= \[\] |
| :------------------------------------------------------- |

Track count for run log later:

| eligible_spv_count \= supervisorsList.length |
| :------------------------------------------- |

For each supervisor in supervisorsList from Step 4:

**11.1 through 11.4** — Refer to Call Plan — Steps 11.1 through 11.4

**11.6 — Monthly calculation**

Using achievementMap built in Step 7 — no extra DB call needed. SPV's own revenue and target are also in achievementMap under supervisor.id.

| // Sum reportee actuals and targetssum_reportee_actual \= sum of achievementMap\[reportee.id\].total_actual for each reportee \-- if reportee not in achievementMap, treat as 0sum_reportee_target \= sum of achievementMap\[reportee.id\].total_target for each reportee \-- if reportee not in achievementMap, treat as 0// Add SPV own revenue and targetspv_own_actual \= achievementMap\[supervisor.id\].total_actual \-- if supervisor not in achievementMap, treat as 0spv_own_target \= achievementMap\[supervisor.id\].total_target \-- if supervisor not in achievementMap, treat as 0spv_total_actual \= sum_reportee_actual \+ spv_own_actualspv_total_target \= sum_reportee_target \+ spv_own_target |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If spv_total_target \= 0 → spv_payout_amount \= 0, push to spvResults and continue to next supervisor.  
If spv_total_target \> 0:

| spv_achievement_value \= spv_total_actualspv_achievement_pct \= (spv_total_actual / spv_total_target) \* 100// Floor negative to 0if spv_achievement_value \< 0 → spv_achievement_value \= 0if spv_achievement_pct \< 0 → spv_achievement_pct \= 0 |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Pass to slab evaluator using spvSlabMap\[supervisor.type\] — refer to Call Plan — Step 8.3 for evaluator logic.

**Example:**

SPV MIX slab (percentage-based):

\>= 90% → Rp. 1,500,000

\>= 80% → Rp. 1,000,000

\>= 60% → Rp. 500,000

SPV MIX has 2 reportees — SP-A and SP-B. SPV also has own revenue.

Achievement data (already aggregated across focus product groups):

| SP-A: total_target \= 50,000,000 total_actual \= 46,000,000SP-B: total_target \= 30,000,000 total_actual \= 28,000,000SPV: total_target \= 20,000,000 total_actual \= 19,000,000sum_reportee_actual \= 46,000,000 \+ 28,000,000 \= 74,000,000sum_reportee_target \= 50,000,000 \+ 30,000,000 \= 80,000,000spv_total_actual \= 74,000,000 \+ 19,000,000 \= 93,000,000spv_total_target \= 80,000,000 \+ 20,000,000 \= 100,000,000spv_achievement_pct \= (93,000,000 / 100,000,000) \* 100 \= 93%93 \>= 90 → match → spv_payout_amount \= Rp. 1,500,000 |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**11.7 — Push to accumulators**

| reportee_result_ids \= reportees .filter(r \=\> spResultIdMap\[r.id\] exists) .map(r \=\> spResultIdMap\[r.id\])spvResults.push({ salesperson_id: supervisor.id, salesperson_name: supervisor.name, sp_type: supervisor.type, achievement_value: spv_achievement_value, achievement_pct: spv_achievement_pct, payout_amount: spv_payout_amount, role: 'SPV'})spvSchemeData.push({ salesperson_id: supervisor.id, incentive_result_ids: reportee_result_ids}) |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

#### **Step 12 — Bulk write SPV results (single transaction)**

run_id, schema_id, partner_id, month, year from job payload.

**12.1 — Insert into incentive_results**

| INSERT INTO incentive_results ( run_id, incentive_schema_id, partner_id, month, year, salesperson_id, salesperson_name, sp_type, achievement_value, achievement_pct, payout_amount, role, status, is_deprecated)VALUES ... \-- one row per SPV in spvResultsRETURNING id, salesperson_id; |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Build map from RETURNING clause:

| spvResultIdMap \= { salesperson_id → result_id } |
| :----------------------------------------------- |

**12.2 — Insert into monthly_revenue_incentive_spv**

result_id from spvResultIdMap. incentive_result_ids from spvSchemeData — already collected in memory during Step 11.7 using spResultIdMap. No DB query needed.

| INSERT INTO monthly_revenue_incentive_spv (result_id, incentive_result_ids)VALUES ... \-- one row per SPV |
| :-------------------------------------------------------------------------------------------------------- |

**12.3 — Insert SPV errors into incentive_run_errors**

run_id and schema_id from job payload. Error details from spvErrors accumulator.

| INSERT INTO incentive_run_errors ( run_id, schema_id, error_code, role, entity_id, payload, error_message, attempt)VALUES ... \-- one row per entry in spvErrors |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If transaction fails → rollback, write DB_WRITE_FAILED, throw. BullMQ retries.

#### **Step 13 — Update run log**

Refer to Call Plan — Step 13\. eligible_sp_count from Step 5, eligible_spv_count from Step 11\.

**Error Reference**

Refer to Call Plan — Error Reference.  
DB_READ_FAILED also covers T5 target type lookup failure.

###

### **Ageing Incentive**

#### **Overview**

Ageing incentive is calculated once at month end. Achievement \= AR (0–10 days) / Total AR × 100\. No target — purely percentage based. Slab evaluation is always percentage. If Total AR \= 0, ageing % \= 0 and incentive \= 0\. Applicable to STO, SFT, and SMO salespersons. SPV includes their own AR alongside reportees.

#### **Data Sources**

| Data                                        | Source                                                                     |
| ------------------------------------------- | -------------------------------------------------------------------------- |
| AR (0–10 days) and Total AR per salesperson | ageing_activity table                                                      |
| Slab config                                 | incentive_payout_slabs                                                     |
| SP list                                     | Redis → GET /users?level=1                                                 |
| SPV list                                    | Redis → GET /users?level=2                                                 |
| SPV reportees                               | Redis → incentive:{partner_id}:reportees → GET /users?upline_id=\<spv_id\> |

#### **Job Payload**

The CRON enqueues this job into an ageing-queue

Refer to Call Plan — Job Payload.

#### **Step 1 — Update run log to processing**

Refer to Call Plan — Step 1\.

#### **Step 2 — Retry cleanup**

Refer to Call Plan — Step 3

#### **Step 3 — Fetch SP and SPV data from Redis**

Refer to Call Plan — Step 4

#### **Step 4 — Filter eligible SPs**

Refer to Call Plan — Step 5\.

#### **Step 5 — Fetch slab rows for SP types**

Refer to Call Plan — Step 6\. Note — ageing only allows slab_type \= percentage. All slab rows for this scheme will always have slab_type \= 'percentage'.

#### **Step 6 — Fetch ageing data from DB**

partner_id, month, year from job payload.

| SELECT id, salesperson_id, ar_10, month_totalFROM ageing_activityWHERE partner_id \= :partner_id AND month \= :month AND year \= :year; |
| :-------------------------------------------------------------------------------------------------------------------------------------- |

Note — this query fetches both SP and SPV rows in one call since SPVs also have their own ageing record. Both are stored in the same map and used later for SP calculation (Step 7\) and SPV own AR (Step 10).

Build in-memory map:

| agingMap \= { "sp-uuid-1": { id: "aa-uuid-1", ar_10: 275000, month_total: 303000 }, "sp-uuid-2": { id: "aa-uuid-2", ar_10: 180000, month_total: 200000 }, "spv-uuid-1": { id: "aa-uuid-3", ar_10: 90000, month_total: 100000 }} |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

If DB query fails → write DB_READ_FAILED and throw. BullMQ retries.

#### **Step 7 — Calculate each eligible SP (all in memory)**

Initialize accumulators:

| spResults \= \[\]spSchemeData \= \[\]spErrors \= \[\] |
| :---------------------------------------------------- |

For each SP in eligibleSPs from Step 4:

**7.1 — Check data exists**

Look up SP in agingMap using sp.id. If not found → push SP_DATA_MISSING with { name: sp.name, type: sp.type } to spErrors and continue to next SP.

**7.2 — Resolve slab for this SP type**

Look up spSlabMap\[sp.type\]. If no slabs exist for this type → SP was already flagged in Step 5, skip.

**7.3 — Ageing % calculation**

| ar_10 \= agingMap\[sp.id\].ar_10month_total \= agingMap\[sp.id\].month_total |
| :--------------------------------------------------------------------------- |

If month_total \= 0:

| ageing_pct \= 0payout_amount \= 0 |
| :-------------------------------- |

Push to accumulators and continue to the next SP — no slab evaluation needed.

If month_total \> 0:

| ageing_pct \= (ar_10 / month_total) \* 100// Floor negative to 0 (should not occur for ageing but defensive)if ageing_pct \< 0 → ageing_pct \= 0 |
| :----------------------------------------------------------------------------------------------------------------------------------------------- |

Pass ageing_pct to slab evaluator — iterate slab rows from spSlabMap\[sp.type\] in descending threshold order, return payout of first match. Slab type is always the percentage for ageing. Refer to Call Plan — Step 8.3 for evaluator logic.

**Example:**

Slab config for STO (percentage-based):

\>= 90% → Rp. 300,000

\>= 80% → Rp. 200,000

\>= 70% → Rp. 100,000

SP ageing data:

| ar_10 \= 275,000month_total \= 303,000ageing_pct \= (275,000 / 303,000) \* 100 \= 90.8%90.8 \>= 90 → match → payout_amount \= Rp. 300,000 |
| :---------------------------------------------------------------------------------------------------------------------------------------- |

**7.4 — Push to accumulators**

| spResults.push({ salesperson_id: sp.id, salesperson_name: sp.name, sp_type: sp.type, achievement_value: ar_10, achievement_pct: ageing_pct, payout_amount: payout_amount, role: 'SP'})spSchemeData.push({ salesperson_id: sp.id, ageing_row_reference_id: agingMap\[sp.id\].id \-- ageing_activity row id for traceability}) |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

#### **Step 8 — Bulk write SP results (single transaction)**

run_id, schema_id, partner_id, month, year from job payload.

**8.1 — Insert into incentive_results**

| INSERT INTO incentive_results ( run_id, incentive_schema_id, partner_id, month, year, salesperson_id, salesperson_name, sp_type, achievement_value, achievement_pct, payout_amount, role, status, is_deprecated)VALUES ... \-- one row per SP in spResultsRETURNING id, salesperson_id; |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Build map from RETURNING clause:

| spResultIdMap \= { salesperson_id → result_id } |
| :---------------------------------------------- |

**8.2 — Insert into ageing_incentive_reference**

result_id from spResultIdMap. ageing_row_reference_id from spSchemeData. One row per SP linking the incentive result to the raw ageing activity row.

| INSERT INTO ageing_incentive_reference (result_id, ageing_row_reference_id)VALUES ... \-- one row per SP |
| :------------------------------------------------------------------------------------------------------- |

**8.3 — Insert SP errors into incentive_run_errors**

run_id and schema_id from job payload. Error details from spErrors accumulator.

| INSERT INTO incentive_run_errors ( run_id, schema_id, error_code, role, entity_id, payload, error_message, attempt)VALUES ... \-- one row per entry in spErrors |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If transaction fails → rollback, write DB_WRITE_FAILED, throw. BullMQ retries.

#### **Step 9 — Fetch SPV slab rows**

Refer to Call Plan — Step 10\.

#### **Step 10 — Calculate each supervisor (all in memory)**

Initialize accumulators:

| spvResults \= \[\]spvSchemeData \= \[\]spvErrors \= \[\] |
| :------------------------------------------------------- |

Track count for run log later:

| eligible_spv_count \= supervisorsList.length |
| :------------------------------------------- |

For each supervisor in supervisorsList from Step 3:

**10.1 through 10.4** — Refer to Call Plan — Steps 11.1 through 11.4

**10.5 — Ageing % calculation for SPV**

Using agingMap built in Step 6 — no extra DB call needed. SPV's own AR is also in agingMap under supervisor.id.

| // Sum reportee AR valuessum_reportee_ar_10 \= sum of agingMap\[reportee.id\].ar_10 for each reportee \-- if reportee not in agingMap, treat as 0sum_reportee_month_total \= sum of agingMap\[reportee.id\].month_total for each reportee \-- if reportee not in agingMap, treat as 0// Add SPV own ARspv_own_ar_10 \= agingMap\[supervisor.id\].ar_10 \-- if supervisor not in agingMap, treat as 0spv_own_month_total \= agingMap\[supervisor.id\].month_total \-- if supervisor not in agingMap, treat as 0spv_numerator \= sum_reportee_ar_10 \+ spv_own_ar_10spv_denominator \= sum_reportee_month_total \+ spv_own_month_total |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If spv_denominator \= 0:

| spv_ageing_pct \= 0spv_payout_amount \= 0 |
| :---------------------------------------- |

Push to accumulators and continue to next supervisor.

If spv_denominator \> 0:

| spv_ageing_pct \= (spv_numerator / spv_denominator) \* 100// Floor negative to 0if spv_ageing_pct \< 0 → spv_ageing_pct \= 0 |
| :--------------------------------------------------------------------------------------------------------------------------- |

Pass spv_ageing_pct to slab evaluator using spvSlabMap\[supervisor.type\] — refer to Call Plan — Step 8.3 for evaluator logic.

**Example:**

SPV MIX slab (percentage-based):

\>= 90% → Rp. 800,000

\>= 80% → Rp. 500,000

\>= 70% → Rp. 300,000

SPV MIX has 2 reportees — SP-A and SP-B. SPV also has own AR.

**Ageing data:**

| SP-A: ar_10 \= 275,000 month_total \= 303,000SP-B: ar_10 \= 180,000 month_total \= 200,000SPV: ar_10 \= 90,000 month_total \= 100,000spv_numerator \= 275,000 \+ 180,000 \+ 90,000 \= 545,000spv_denominator \= 303,000 \+ 200,000 \+ 100,000 \= 603,000spv_ageing_pct \= (545,000 / 603,000) \* 100 \= 90.4%90.4 \>= 90 → match → spv_payout_amount \= Rp. 800,000 |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

**10.6 — Push to accumulators**

| reportee_result_ids \= reportees .filter(r \=\> spResultIdMap\[r.id\] exists) .map(r \=\> spResultIdMap\[r.id\])spvResults.push({ salesperson_id: supervisor.id, salesperson_name: supervisor.name, sp_type: supervisor.type, achievement_value: spv_numerator, achievement_pct: spv_ageing_pct, payout_amount: spv_payout_amount, role: 'SPV'})spvSchemeData.push({ salesperson_id: supervisor.id, incentive_result_ids: reportee_result_ids}) |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**Step 11 — Bulk write SPV results (single transaction)**

run_id, schema_id, partner_id, month, year from job payload.

**11.1 — Insert into incentive_results**

| INSERT INTO incentive_results ( run_id, incentive_schema_id, partner_id, month, year, salesperson_id, salesperson_name, sp_type, achievement_value, achievement_pct, payout_amount, role, status, is_deprecated)VALUES ... \-- one row per SPV in spvResultsRETURNING id, salesperson_id; |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Build map from RETURNING clause:

| spvResultIdMap \= { salesperson_id → result_id } |
| :----------------------------------------------- |

**11.2 — Insert into ageing_incentive_spv**

result_id from spvResultIdMap.  
incentive_result_ids from spvSchemeData —

| INSERT INTO ageing_incentive_spv (result_id, incentive_result_ids)VALUES ... \-- one row per SPV |
| :----------------------------------------------------------------------------------------------- |

**11.3 — Insert SPV errors into incentive_run_errors**

run_id and schema_id from job payload. Error details from spvErrors accumulator.

| INSERT INTO incentive_run_errors ( run_id, schema_id, error_code, role, entity_id, payload, error_message, attempt)VALUES ... \-- one row per entry in spvErrors |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If transaction fails → rollback, write DB_WRITE_FAILED, throw. BullMQ retries.

#### **Step 12 — Update run log**

Refer to Call Plan — Step 13\. eligible_sp_count from Step 3, eligible_spv_count from Step 10\.

**Error Reference**

Refer to Call Plan — Error Reference. DB_READ_FAILED also covers ageing activity query failure.

### **Activation Call Incentive**

#### **Overview**

Activation call incentive is calculated once at month end. Achievement \= count of unique customers from the activation feed who had net sales \> 0 in M, M-1, and M-2. No target for SP — slab is value-based. SPV target is derived from STO reportee count multiplied by a configurable multiplier. Applicable to STO salespersons only.

#### **Data Sources**

| Data                                   | Source                                                                     |
| -------------------------------------- | -------------------------------------------------------------------------- |
| Activated customers per SP             | activation_activity table                                                  |
| Customer sales history for M, M-1, M-2 | achievements table — T4, achievement JSON (customer ID → total sales map)  |
| Activation call multiplier per SP type | salesperson_type_multiplier table                                          |
| Slab config                            | incentive_payout_slabs                                                     |
| SP list                                | Redis → GET /users?level=1                                                 |
| SPV list                               | Redis → GET /users?level=2                                                 |
| SPV reportees                          | Redis → incentive:{partner_id}:reportees → GET /users?upline_id=\<spv_id\> |

#### **Job Payload**

Refer to Call Plan — Job Payload.

#### **Step 1 — Update run log to processing**

Refer to Call Plan — Step 1\.

#### **Step 2 — Retry cleanup**

Refer to Call Plan — Step 3\.

#### **Step 3 — Fetch SP and SPV data from Redis**

Refer to Call Plan — Step 4

#### **Step 4 — Filter eligible SPs**

Refer to Call Plan — Step 5\.

#### **Step 5 — Fetch slab rows for SP types**

Refer to Call Plan — Step 6\. Note — activation call SP slab is always slab_type \= value

#### **Step 6 — Fetch activation data from DB**

partner_id, month, year from job payload.

| SELECT id, salesperson_id, customer_idFROM activation_activityWHERE partner_id \= :partner_id AND month \= :month AND year \= :year; |
| :----------------------------------------------------------------------------------------------------------------------------------- |

Note — id is fetched here for traceability. It will be used later in Step 9.5 to populate activation_row_reference_ids in spSchemeData without needing a second query.

Build two in-memory maps:

| activationMap \= { "sp-uuid-1": \["C1", "C2", "C3", "C4", "C5"\], "sp-uuid-2": \["C3", "C6", "C7"\]}activationReferenceMap \= { "sp-uuid-1": { "C1": "aa-uuid-1", "C2": "aa-uuid-2", "C3": "aa-uuid-3", "C4": "aa-uuid-4", "C5": "aa-uuid-5" }, "sp-uuid-2": { "C3": "aa-uuid-6", "C6": "aa-uuid-7", "C7": "aa-uuid-8" }} |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

If DB query fails → write DB_READ_FAILED and throw. BullMQ retries.

#### **Step 7 — Fetch T4 sales history for M, M-1, M-2**

**7.1 — Resolve T4 target type ID**

| SELECT id FROM target_typesWHERE table_name \= 'target_unique_transacting_customers' AND status \= 'ACTIVE'; |
| :----------------------------------------------------------------------------------------------------------- |

If not found → write DB_READ_FAILED with message "T4 target type not found" and throw. BullMQ retries.

Store result as t4_target_type_id.

**7.2 — Derive M, M-1, M-2 boundaries**

month and year from job payload.

| M start/end \= first and last day of calculation monthM\-1 start/end \= first and last day of previous monthM\-2 start/end \= first and last day of two months prior |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**7.3 — Fetch achievement rows for all eligible SPs across 3 months**

partner_id from job payload. t4_target_type_id from Step 7.1. eligible_sp_ids \= list of IDs from eligibleSPs in Step 4\.

| SELECT salesperson_id, start_date, achievementFROM achievementsWHERE partner_id \= :partner_id AND target_type_id \= :t4_target_type_id AND salesperson_id \= ANY(:eligible_sp_ids) AND ( (start_date \= :m_start AND end_date \= :m_end) OR (start_date \= :m1_start AND end_date \= :m1_end) OR (start_date \= :m2_start AND end_date \= :m2_end) ) AND status \= 'ACTIVE'; |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Build in-memory sales lookup map per SP per month:

| salesLookup \= { "sp-uuid-1": { "M": { "C1": 150000, "C2": 320000, "C3": 0, "C4": 85000 }, "M-1":{ "C1": 200000, "C2": 0, "C3": 50000, "C4": 120000 }, "M-2":{ "C1": 90000, "C2": 180000, "C3": 75000, "C4": 0 } }} |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |

If a month has no achievement row for an SP → treat all customer sales as 0 for that month (cold-start scenario).

If DB query fails → write DB_READ_FAILED and throw. BullMQ retries.

#### **Step 8 — Calculate each eligible SP (all in memory)**

Initialize accumulators:

| spResults \= \[\]spSchemeData \= \[\]spErrors \= \[\] |
| :---------------------------------------------------- |

For each SP in eligibleSPs from Step 4:

**8.1 — Check activation data exists**

Look up SP in activationMap. If not found → SP had no activation calls this month. Push SP_DATA_MISSING with { name: sp.name, type: sp.type } to spErrors and continue to next SP.

**8.2 — Resolve slab for this SP type**

Look up spSlabMap\[sp.type\]. If no slabs exist for this type → SP was already flagged in Step 5 skip.

**8.3 — 3-month lookback per activated customer**

For each customer in activationMap\[sp.id\]:

| sales_M \= salesLookup\[sp.id\]\["M"\]\[customer_id\] ?? 0sales_M1 \= salesLookup\[sp.id\]\["M-1"\]\[customer_id\] ?? 0sales_M2 \= salesLookup\[sp.id\]\["M-2"\]\[customer_id\] ?? 0if sales_M \> 0 AND sales_M1 \> 0 AND sales_M2 \> 0: customer qualifies → add to qualifying_customers list |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

| achievement_value \= qualifying_customers.length |
| :----------------------------------------------- |

**Example:**

SP-A activation feed: \[C1, C2, C3, C4, C5\]

Sales lookup for SP-A:

| C1: M\=150000 M-1\=200000 M-2\=90000 → qualifies ✓C2: M\=320000 M-1\=0 M-2\=180000 → fails M-1 ✗C3: M\=0 M-1\=50000 M-2\=75000 → fails M ✗C4: M\=85000 M-1\=120000 M-2\=0 → fails M-2 ✗C5: M\=95000 M-1\=110000 M-2\=60000 → qualifies ✓ |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

| achievement_value \= 2 |
| :--------------------- |

**8.4 — Slab evaluation**

Pass achievement_value to slab evaluator using spSlabMap\[sp.type\]. Slab type is always value for activation call SP. Refer to Call Plan — Step 8.3 for evaluator logic.

Slab config for STO (value-based):

\>= 40 → Rp. 300,000

\>= 30 → Rp. 200,000

\>= 20 → Rp. 100,000

| achievement_value \= 22 \>= 40 → no2 \>= 30 → no2 \>= 20 → nono match → payout_amount \= 0 |
| :----------------------------------------------------------------------------------------- |

**8.5 — Push to accumulators**

activationReferenceMap from Step 7 — collect reference IDs only for qualifying customers.

| activation*\_row\_*reference*\_ids \= qualifying\_*customers.map(c \=\> activationReferenceMap\[sp.id\]\[c\]) |
| :------------------------------------------------------------------------------------------------------------ |

| spResults.push({ salesperson_id: sp.id, salesperson_name: sp.name, sp_type: sp.type, achievement_value: achievement_value, achievement_pct: null, payout_amount: payout_amount, role: 'SP'})spSchemeData.push({ salesperson_id: sp.id, eligible_unique_customers: qualifying_customers, activation_row_reference_ids: activation_row_reference_ids}) |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

#### **Step 9 — Bulk write SP results (single transaction)**

run_id, schema_id, partner_id, month, year from job payload.

**9.1 — Insert into incentive_results**

| INSERT INTO incentive_results ( run_id, incentive_schema_id, partner_id, month, year, salesperson_id, salesperson_name, sp_type, achievement_value, achievement_pct, payout_amount, role, status, is_deprecated)VALUES ... \-- one row per SP in spResultsRETURNING id, salesperson_id; |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Build map from RETURNING clause:

| spResultIdMap \= { salesperson_id → result_id } |
| :---------------------------------------------- |

**9.2 — Insert into activation_incentive_sp**

result_id from spResultIdMap. eligible_unique_customers from spSchemeData.

| INSERT INTO activation_incentive_sp (result_id, eligible_unique_customers)VALUES ... \-- one row per SP |
| :------------------------------------------------------------------------------------------------------ |

**9.3 — Insert into activation_incentive_reference**

result_id from spResultIdMap. activation_row_reference_ids from spSchemeData.

| INSERT INTO activation_incentive_reference (result_id, activation_row_reference_ids)VALUES ... \-- one row per SP |
| :---------------------------------------------------------------------------------------------------------------- |

**9.4 — Insert SP errors into incentive_run_errors**

| INSERT INTO incentive_run_errors ( run_id, schema_id, error_code, role, entity_id, payload, error_message, attempt)VALUES ... \-- one row per entry in spErrors |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If transaction fails → rollback, write DB_WRITE_FAILED, throw. BullMQ retries.

#### **Step 10 — Fetch activation call multiplier**

partner_id, month, year from job payload. month_start and month_end derived from job payload as the first and last day of calculation month.

| SELECT salesperson_type, multiplierFROM salesperson_type_multiplierWHERE partner_id \= :partner_id AND valid_from \<= :month_start AND valid_to \>= :month_end AND salesperson_type \= 'STO'; |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Build in-memory map:

| multiplierMap \= { "STO": 280} |
| :----------------------------- |

If no multiplier found for STO → write MULTIPLIER_NOT_CONFIGURED with { type: 'STO' } to incentive_run_errors and throw. BullMQ retries. SPV target cannot be computed without this.

#### **Step 11 — Fetch SPV slab rows**

Refer to Call Plan — Step 10\. Note — activation call SPV slab is always slab_type \= percentage.

#### **Step 12 — Calculate each supervisor (all in memory)**

Initialize accumulators:

| spvResults \= \[\]spvSchemeData \= \[\]spvErrors \= \[\] |
| :------------------------------------------------------- |

Track count for run log later:

| eligible_spv_count \= supervisorsList.length |
| :------------------------------------------- |

For each supervisor in supervisorsList from Step 3:

**12.1 \- Get reportees of all supervisors**

Read reporteeMap\[supervisor.id\] from Redis → GET /api/salespersons/v1/supervisor/reportees if not in Redis. Loaded in Step 4\. If key not found or empty → push SPV_NO_REPORTEES with { name: supervisor.name, type: supervisor.type } to spvErrors and continue to next supervisor. Refer to Call Plan — Steps 11.2 through 11.4 for remaining steps.

**12.2 — Filter reportees to STO only**

Keep only STO reportees. All other types are not applicable for activation call SPV calculation.

| sto_reportees \= reportees.filter(r \=\> r.type \= 'STO') |
| :-------------------------------------------------------- |

**12.3 — Compute SPV target**

Apply STO multiplier from multiplierMap (populated in Step 10):

| spv_target \= count of sto_reportees × multiplierMap\["STO"\] |
| :------------------------------------------------------------ |

**Example:**

SPV has 5 STO reportees

| multiplierMap \= { STO: 280 }spv_target \= 5 × 280 \= 1400 |
| :--------------------------------------------------------- |

**12.4 — Compute SPV achievement**

SPV achievement \= sum of achievement_value of all STO reportees. Look up each reportee's result using spResultMap — a keyed map built from spResults after Step 9\. SPV's own activation calls are NOT included.

Build the map once after Step 9 completes:

| spResultMap \= {}for each result in spResults: spResultMap\[result.salesperson_id\] \= result |
| :-------------------------------------------------------------------------------------------- |

Then for SPV achievement:

| spv_achievement \= sum of spResultMap\[reportee.id\].achievement_value for each reportee in sto_reportees \-- if reportee.id not in spResultMap (SP_DATA_MISSING), treat as 0 |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Example:

| SP-A achievement \= 32SP-B achievement \= 28SP-C achievement \= 35SP-D achievement \= 0 \-- SP_DATA_MISSING, treat as 0SP-E achievement \= 22spv_achievement \= 32 \+ 28 \+ 35 \+ 0 \+ 22 \= 117 |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**12.5 — Achievement % and slab evaluation**

If spv_target \= 0:

| spv_achievement_pct \= 0spv_payout_amount \= 0 |
| :--------------------------------------------- |

Push to accumulators and continue.

If spv_target \> 0:

| spv_achievement_pct \= (spv_achievement / spv_target) \* 100// Floor negative to 0if spv_achievement_pct \< 0 → spv_achievement_pct \= 0 |
| :--------------------------------------------------------------------------------------------------------------------------------------- |

Pass spv_achievement_pct to slab evaluator using spvSlabMap\[supervisor.type\]. Slab type is always the percentage for activation call SPV. Refer to Call Plan — Step 8.3 for evaluator logic.

**Example:**

SPV MIX slab (percentage-based):

\>= 90% → Rp. 1,000,000

\>= 80% → Rp. 700,000

\>= 60% → Rp. 400,000

| spv_achievement_pct \= (117 / 1400) \* 100 \= 8.36%8.36 \>= 90 → no8.36 \>= 80 → no8.36 \>= 60 → nono match → spv_payout_amount \= 0 |
| :----------------------------------------------------------------------------------------------------------------------------------- |

**12.6 — Push to accumulators**

| spvResults.push({ salesperson_id: supervisor.id, salesperson_name: supervisor.name, sp_type: supervisor.type, achievement_value: spv_achievement, achievement_pct: spv_achievement_pct, payout_amount: spv_payout_amount, role: 'SPV'})spvSchemeData.push({ salesperson_id: supervisor.id, activation_incentive_result_ids: sto_reportees.map(r \=\> spResultIdMap\[r.id\]).filter(Boolean)}) |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

#### **Step 13 — Bulk write SPV results (single transaction)**

run_id, schema_id, partner_id, month, year from job payload.

**13.1 — Insert into incentive_results**

| INSERT INTO incentive_results ( run_id, incentive_schema_id, partner_id, month, year, salesperson_id, salesperson_name, sp_type, achievement_value, achievement_pct, payout_amount, role, status, is_deprecated)VALUES ... \-- one row per SPV in spvResultsRETURNING id, salesperson_id; |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Build map from RETURNING clause:

| spvResultIdMap \= { salesperson_id → result_id } |
| :----------------------------------------------- |

**13.2 — Insert into activation_incentive_spv**

result_id from spvResultIdMap. activation_incentive_result_ids from spvSchemeData.

| INSERT INTO activation_incentive_spv (result_id, activation_incentive_result_ids)VALUES ... \-- one row per SPV |
| :-------------------------------------------------------------------------------------------------------------- |

**13.3 — Insert SPV errors into incentive_run_errors**

| INSERT INTO incentive_run_errors ( run_id, schema_id, error_code, role, entity_id, payload, error_message, attempt)VALUES ... \-- one row per entry in spvErrors |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If transaction fails → rollback, write DB_WRITE_FAILED, throw. BullMQ retries.

#### **Step 14 — Update run log**

Refer to Call Plan — Step 13\. eligible_sp_count from Step 4, eligible_spv_count from step 12\.

#### **Error Reference**

Refer to Call Plan — Error Reference. Additional errors for activation call:

| Error code                | Role   | When                                                                                         |
| ------------------------- | ------ | -------------------------------------------------------------------------------------------- |
| MULTIPLIER_NOT_CONFIGURED | SYSTEM | No multiplier found for STO in salesperson_type_multiplier                                   |
| DB_READ_FAILED            | SYSTEM | Also covers activation activity query, T4 target type lookup, or sales history query failure |

# **13\. Architectural Analysis of Edge Cases for the Slab Correction & Rerun Flow**

![][image1]  
\*\*IMP \= Incentive Management People

This section covers the end-to-end flow for when an incentive slab error is identified after the month's first incentive calculation has already completed. It describes how slabs are corrected, who gets notified, how old records are deprecated, and how recalculation is triggered — either manually by IMP (Incentive Management People) or automatically by the Catch-up CRON on the configured rerun date.

### **Key Concepts**

**Grace window** — A configurable period after the initial calculation during which IMP is permitted to correct slab configurations. The grace window closes on the same date the Catch-up CRON is scheduled to run (configured in the system, not hardcoded). Slab edits via the admin panel are only accepted while the grace window is open.

**Slab deprecation** — When a slab config is corrected, the PATCH /schemas/:id/configs/:config_id endpoint atomically deprecates the old slab rows (status \= 'deprecated') and inserts new rows with corrected values in a single DB transaction. No partial state is possible — either both happen or neither does.

**Result deprecation** — When recalculation runs, existing incentive_results rows from the previous run for the affected scheme and period are marked is_deprecated \= true. They are never deleted. The active result for any SP or SPV is always the row where is_deprecated \= false.

**Idempotency guard** — Before any rerun job is enqueued (whether triggered manually by IMP or by the CRON), the system performs an optimistic lock on incentive_run_log. If the row is already being processed, the trigger aborts silently. This prevents double-calculation when manual and CRON triggers overlap.

### **Step 1 — Slab Correction Identified**

After the Calculation CRON runs on the 2nd, IMP identifies either:

- A mistake in one or more slab rows (wrong threshold, wrong payout value), or
- Data that was missing at calculation time, causing incorrect results

The grace window is open — slab edits are permitted until the configured rerun date.

### **Step 2 — Admin Updates Incentive Slabs**

IMP logs into the admin panel and corrects the affected slab config via PATCH /schemas/:id/configs/:config_id.

#### **Authorization Check**

Before any DB operation, the backend validates two conditions in order:

**Check 1 — Privileged user guard**

Slab edits for a previous month's config are restricted to a fixed list of privileged user IDs configured via environment variable:

| SLAB_CORRECTION_ALLOWED_IDS=uuid\-1,uuid\-2,uuid\-3 |
| :-------------------------------------------------- |

The requesting admin's user ID (from the auth token) is checked against this list. If the user ID is not present, the API returns 403 Forbidden immediately. No DB query is made.

| if (\!SLAB_CORRECTION_ALLOWED_IDS.includes(requestingUserId)) { return 403 Forbidden \-- { error: 'SLAB_EDIT_NOT_AUTHORIZED' }} |
| :------------------------------------------------------------------------------------------------------------------------------ |

Non-privileged admins can still update slabs for the **current active month** through the standard slab management flow. The restriction above applies only when the config being edited belongs to a **previous month** — i.e., valid_to \< current month start.

**Check 2 — Grace window guard**

If the user passes Check 1, the backend checks whether the grace window is still open:

| if (currentDate \>= configuredRerunDate) { return 423 Locked \-- { error: 'GRACE_WINDOW_CLOSED' }} |
| :------------------------------------------------------------------------------------------------- |

If the grace window has closed, the edit is rejected regardless of whether the user is privileged. No DB changes are made.

#### **Slab Update Transaction**

Only after both checks pass does the backend proceed with the DB update. The deprecation and insertion happen atomically in a single transaction:

| \-- Step A: Deprecate all existing active slab rows for this configUPDATE incentive_payout_slabsSET status \= 'deprecated'WHERE schema_config_id \= :config_id AND status \= 'active';\-- Step B: Insert corrected slab rowsINSERT INTO incentive_payout_slabs (schema_config_id, salesperson_type, ...)VALUES (...); |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

If the insert in Step B fails, the transaction rolls back — the old rows remain active and no partial state is written. The API returns 400 with the validation error.

#### **Authorization Flow Summary**

| Condition                                      | Result                                         |
| ---------------------------------------------- | ---------------------------------------------- |
| User ID not in SLAB_CORRECTION_ALLOWED_IDS     | 403 Forbidden — SLAB_EDIT_NOT_AUTHORIZED       |
| User is privileged but grace window has closed | 423 Locked — GRACE_WINDOW_CLOSED               |
| User is privileged and grace window is open    | Proceed to slab update transaction             |
| Slab update transaction fails                  | 400 Bad Request — SLAB_UPDATE_FAILED, rollback |

### **Step 3 — Email Notification to IMP Stakeholders**

Immediately after the slab update transaction commits, the system sends an email notification to all configured IMP contacts for the partner.

The email includes:

- Which schema_id had slabs updated
- The previous slab values (deprecated rows)
- The new slab values (inserted rows)
- The period affected (month, year)

**Important:** Email sending is fire-and-forget. It does not block or roll back the slab update transaction if SMTP fails. Failures are logged to the notification log.

**_Please refer to point 15 for the email template._**

### **Step 4 — Recalculation Trigger**

Recalculation can be triggered two ways. Both paths converge on the same job processing logic.

#### **Path A — Manual trigger by IMP**

IMP calls POST /incentive/v1/manual-trigger with the specific scheme to recalculate:

| { "scheme": "call_plan", "salesperson_ids": \[\] // optional \-- omit for full scheme rerun} |
| :------------------------------------------------------------------------------------------- |

Only the targeted scheme is recalculated. Other schemes are not affected.

The API runs the standard pre-run gate checks (slab config, feed status, achievement data) before enqueuing. If any check fails, it returns 400 immediately and nothing is enqueued. Refer to Section 11 for the full gate check and calculation logic.

#### **Path B — Catch-up CRON on configured rerun date**

The Catch-up CRON fires on the configured rerun date (same date as the grace window closes). It recalculates all schemes that do not already have a success or partial status in incentive_run_log for the period.

All schema calculation rerun happens at this point of time. Refer to Section 5 for the full Catch-up CRON logic.

#### **Idempotency guard — both paths**

Before enqueuing any job, regardless of trigger path, the system performs an optimistic lock:

| UPDATE incentive_run_logSET status \= 'processing', triggered_by \= :triggerWHERE run_id \= :run_id AND status IN ('pending', 'deprecated')RETURNING id |
| :------------------------------------------------------------------------------------------------------------------------------------------------------ |

If RETURNING returns 0 rows, another process has already picked up this job. The trigger aborts silently — no duplicate job is enqueued. This prevents double-calculation when IMP triggers a manual rerun at the same time the CRON fires.

### **Step 5 — Old Incentive Records Deprecated**

Before writing any new results, the rerun job marks all existing incentive_results rows for this run as deprecated:

| \-- Deprecate previous resultsUPDATE incentive_resultsSET is_deprecated \= trueWHERE run_id \= :run_id AND incentive_schema_id \= :schema_id;\-- Deprecate previous errorsUPDATE incentive_run_errorsSET is_deprecated \= trueWHERE run_id \= :run_id AND schema_id \= :schema_id; |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**Atomicity:** Deprecation and new record insertion happen inside the same DB transaction (Step 6 below). A reporting API reading incentive_results WHERE is_deprecated \= false will never see zero rows for a completed scheme — it will always see either the old results or the new results, never a gap between the two.

The incentive_run_log row for the original run is updated to status \= 'deprecated':

| UPDATE incentive_run_logSET status \= 'deprecated'WHERE run_id \= :run_id AND schema_id \= :schema_id; |
| :----------------------------------------------------------------------------------------------------- |

All deprecated rows remain in the DB permanently for audit purposes.

### **Step 6 — New Incentive Records Created**

A fresh run_id is generated and a new row is inserted into incentive_run_log with triggered_by \= 'MANUAL' or triggered_by \= 'CRON' depending on the trigger path, and status \= 'pending'.

Calculation then proceeds identically to the standard CRON job for that scheme — using the now-corrected active slab rows. Refer to the relevant scheme section (Sections 6 onwards) for the full step-by-step calculation logic.

On completion:

- incentive_run_log is updated to success or partial
- New incentive_results rows have is_deprecated \= false
- Old rows from the previous run remain with is_deprecated \= true

### **Edge Cases**

#### **Concurrent rerun trigger (IMP \+ CRON fire simultaneously)**

If IMP triggers a manual rerun and the Catch-up CRON fires at the same time for the same scheme, the idempotency guard in Step 4 ensures only one job is enqueued and processed. The second trigger finds status already moved past pending and aborts silently. No duplicate calculation occurs.

#### **Slab update fails mid-transaction**

If the insert of corrected slab rows fails after the deprecation UPDATE, the entire transaction rolls back. The old slab rows remain status \= 'active'. The API returns an error. No rerun is triggered. IMP must correct the input and retry.

#### **Rerun triggered while a previous run is still processing**

If a rerun is triggered for a scheme that currently has status \= 'processing' in incentive_run_log (e.g., the original 2nd CRON job is still running slowly), the idempotency guard will find the row in a state not in ('pending', 'deprecated') and abort. The API returns error code RERUN_BLOCKED_ACTIVE_JOB with HTTP 409. IMP must wait for the active job to complete before triggering a rerun.

#### **Grace window closes before slab edit is submitted**

If IMP attempts to update slabs after the grace window has closed, the PATCH /schemas/:id/configs/:config_id endpoint returns 423 Locked. No slab changes are written. To proceed, the grace window date must be reconfigured by an operator with sufficient access — this is an out-of-band operational action and is not handled by the system automatically.

#### **Email notification fails**

SMTP failure does not block or roll back the slab update. The failure is written to the notification log. IMP stakeholders may not receive the email but the slab correction and rerun proceed normally.

#### **Rerun produces partial status**

If the rerun completes but some SPs or SPVs are skipped (due to SP_DATA_MISSING, SPV_NO_REPORTEES, etc.), incentive_run_log status is set to partial. This is not an error state — it means the calculation completed with non-retryable individual-level skips. The old deprecated rows remain available for comparison. IMP can inspect incentive_run_errors for the new run_id to see which entities were skipped and why.

#

#

#

#

#

#

# **14\. Achievement Unlock & Reprocessing API**

![][image2]

### **New Table — feed_data_buffer**

Lives in the same database as the Target Engine (TARGET_INCENTIVE_DB). Stores raw event payloads that were rejected by the locked achievement check and are awaiting reprocessing by the Unlock API.

| CREATE TABLE feed_data_buffer ( id UUID PRIMARY KEY DEFAULT gen_random_uuid(), partner_id UUID NOT NULL, event_type VARCHAR(50) NOT NULL, salesperson_id UUID NOT NULL, month INTEGER NOT NULL, year INTEGER NOT NULL, payload JSONB NOT NULL, original_job_queue VARCHAR(100) NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'pending', last_enqueue_error TEXT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), enqueued_at TIMESTAMPTZ NULL, \-- Constraints CONSTRAINT chk_fdb_event_type CHECK (event_type IN ('net_sales', 'call_plan', 'new_customer')), CONSTRAINT chk_fdb_status CHECK (status IN ('pending', 'enqueued', 'processed')), CONSTRAINT chk_fdb_month CHECK (month BETWEEN 1 AND 12), CONSTRAINT chk_fdb_year CHECK (year BETWEEN 2025 AND 9999), CONSTRAINT chk_fdb_enqueued_at CHECK ( (status \= 'pending' AND enqueued_at IS NULL) OR (status IN ('enqueued', 'processed') AND enqueued_at IS NOT NULL) ), CONSTRAINT chk_fdb_last_enqueue_error CHECK ( (status \= 'pending' AND last_enqueue_error IS NOT NULL) OR last_enqueue_error IS NULL OR status \= 'pending' ));\-- IndexesCREATE INDEX idx_fdb_partner_period_status ON feed_data_buffer (partner_id, year, month, status);CREATE INDEX idx_fdb_pending_backlog ON feed_data_buffer (created_at ASC) WHERE status \= 'pending'; |
| :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

Note on the chk_fdb_last_enqueue_error constraint: it deliberately does NOT restrict last_enqueue_error to only pending rows via a hard CHECK. The reason — when the Unlock worker writes the error and leaves the status as pending, that's the valid state. The column is nullable and free to be set or cleared at any time. The constraint above is intentionally permissive; the invariant is enforced at the application layer (only the Unlock worker writes this column).

**Status lifecycle**

- pending — set at insert time by the webhook worker. Event is buffered and awaiting the Unlock API.
- enqueued — set by the Unlock API when it re-enqueues the payload into BullMQ. Marked optimistically at enqueue time, not after worker completion. enqueued_at is set in the same atomic UPDATE that changes status.
- processed — reserved for future manual reconciliation use. Not written by the worker. True processing confirmation lives in the processed\_\* event tables.

### **Updated Webhook Behavior When Achievement Is Locked**

#### **Scope**

This change applies to all three BullMQ achievement workers:

![][image3]

#### **Previous behavior**

If the achievement record was locked (is_locked \= true), the worker skipped the update silently, logged a warning, and acknowledged the job. The incoming data was not applied and not recoverable.

#### **Updated Behavior**

When a job arrives on any of the three achievement queues, the worker now runs four sequential gates before the existing achievement calculation logic. Each gate is a decision point that either routes the event forward, skips it with a log, or buffers it into feed_data_buffer. The existing achievement calculation logic is only reached if all four gates pass.

#### **Gate 1 — Idempotency Check**

Unchanged from the existing implementation. The worker checks the processed\_\* event table for this event before opening any transaction. If the event has already been processed, the job is acknowledged and exits with DUPLICATE_EVENT. No further gates are evaluated.

#### **Gate 2 — Date Validity Check**

The worker derives month and year from the date field in the job payload. The date field used depends on the queue:

- billing_date — for achievement-daily-orders and achievement-monthly-new-customers
- record_date — for achievement-daily-callplan

Month and year are always derived in UTC. The derived values are compared against the current calendar month and year in UTC at the time of job processing.

Three outcomes:

- **Event belongs to the current month** — proceed to Gate 4\. Gate 3 is skipped entirely.
- **Event belongs to the previous calendar month** — proceed to Gate 3\.
- **Event is older than the previous calendar month** — skip entirely. The job is acknowledged. BullMQ does not retry. No buffer insert is made. A structured warning log is emitted. Data older than the previous month has no valid processing path — the incentive calculation for that period has either completed or is irrecoverably stale, and buffering it would produce incorrect results on reprocessing.

**Note on UTC boundary behaviour:** Month and year must be derived from the UTC value of the date field in the payload — not the server's local wall clock. The comparison against current month and previous month is made entirely in UTC. This avoids ambiguity on the last day of a month for events originating in UTC+7 (WIB).

#### **Gate 3 — incentive_run_log Check**

This gate runs **only for events that belong to the previous calendar month**. Events belonging to the current month skip this gate entirely.

The worker queries incentive_run_log for any row matching partner_id \+ month \+ year. The schema_id is not considered — any row for that partner and period, in any status (pending, processing, success, partial, failed), is sufficient to trigger buffering. The presence of any row indicates the incentive calculation cycle has been initiated for that partner and period, meaning late-arriving data must not be written directly to achievements.

This check runs before a transaction is opened. It is a read-only query and does not require transactional scope.

Two outcomes:

- **Row found** — buffer the event into feed_data_buffer in a standalone transaction. The job is acknowledged. BullMQ does not retry. A structured warning log is emitted.
- **No row found** — the calculation cycle has not been initiated for that period. Proceed to Gate 4\.

#### **Gate 4 — Lock Check on Achievement Row**

This gate applies to all events that have passed Gate 2 and Gate 3 — both current month events and previous month events where no incentive_run_log row was found.

The lock check is folded directly into the existing achievement upsert query using a WHERE is_locked \= false condition, not as a standalone SELECT before the upsert. This eliminates the TOCTOU (Time-of-Check-Time-of-Use) race condition that would exist if the lock check and the upsert were two separate queries — the Incentive Engine could apply the lock in the window between them, causing the event to be written to a locked achievement silently. Folding the guard into the upsert makes the check and the write atomic.

The upsert executes with the lock guard. rowsAffected is then evaluated:

**rowsAffected \= 1** — the achievement row existed, was not locked, and was updated. The worker continues with the existing calculation flow. Behavior is unchanged.

**rowsAffected \= 0** — two possible causes that must be disambiguated via a single point lookup on the achievement row, executed inside the same transaction:

- **Row not found, event belongs to current month** — the achievement row does not exist yet. This is normal for a new SP or the first event of the month. The worker inserts a fresh achievement row and continues normally. No calculation cycle is running for the current month, so this is safe.
- **Row not found, event belongs to previous month** — the worker does not insert a fresh achievement row. The event is buffered into feed_data_buffer. The rationale: if the achievement row for a previous month does not exist at this point, the system has no safe baseline to write against — the achievement table may be in the middle of initial population by the calculation engine, or the SP may not yet be seeded for that period. Buffering and replaying via the Unlock API is the safe path.
- **Row found, is_locked \= true** — the lock is active. The worker rolls back the current transaction and inserts the event into feed_data_buffer in a new standalone transaction. The job is acknowledged cleanly. BullMQ does not retry. A structured warning log is emitted.
- **Row found, is_locked \= false** — this should not occur after rowsAffected \= 0. Treated as a transient anomaly. The worker throws an error and BullMQ retries with its standard backoff.

#### **Updated Gate Sequence Summary![][image4]**

#### **Buffer Insert — One Row Per Event**

A single feed_data_buffer row is inserted per event, regardless of which gate triggered the buffer. Thread 2 (salesperson_metrics_snapshot) does not insert a separate buffer row. One buffer row covers the full job replay because the Unlock API re-enqueues the original payload intact, and the worker processes it end-to-end — covering both the achievement write and the snapshot write — when it is replayed.

#### **Buffer Email Notification — Once Per Partner Per Day**

**Step — Check Redis and send buffer alert email (within the same gate that triggered the buffer insert)**

This step executes immediately after the feed_data_buffer row is successfully committed. It applies regardless of which gate triggered the buffer (Gate 3 or Gate 4). It runs outside any open database transaction.

**Step A — Derive the Redis key**

Construct the key as:

| incentive:buffer-alert:{partner_id}:{YYYY-MM-DD} |
| :----------------------------------------------- |

Where YYYY-MM-DD is the current calendar date in UTC. Using UTC is mandatory — the rest of the system operates in UTC and the TTL calculation in Step C depends on a consistent clock reference.

**Step B — Check Redis for key existence**

Perform a Redis EXISTS check on the key derived in Step A.

- **Key exists** — an alert has already been sent today for this partner. Skip Steps C and D entirely. Emit a structured debug log: event: BUFFER_ALERT_SUPPRESSED, partner_id, date. Exit this step cleanly. The buffer insert is already committed and is unaffected.
- **Key does not exist** — proceed to Step C.

**Step C — Set the Redis key with a TTL calculated to midnight UTC**

Before sending the email, atomically set the Redis key using SET ... EX with TTL in seconds computed as:

| TTL \= seconds remaining until 23:59:59 UTC today \= (end of day UTC in epoch seconds) − (now in epoch seconds) |
| :-------------------------------------------------------------------------------------------------------------- |

Use a SET NX EX (set-if-not-exists with expiry) operation, not a plain SET, to guard against a race condition where two concurrent workers both pass the EXISTS check and attempt to send simultaneously. Only the worker that wins the SET NX proceeds to Step D. The worker that loses SET NX suppresses the email and emits BUFFER_ALERT_SUPPRESSED. This makes the send exactly-once even under concurrent load.

**Step D — Send the buffer alert email**

Resolve the recipient list from BUFFER_ALERT_NOTIFICATION_RECIPIENTS env using partner_id as the key. This follows the same pattern as UNLOCK_NOTIFICATION_RECIPIENTS used in the Unlock worker. If no recipients are configured for the partner, log a warning and skip the send without throwing. The buffer insert is already committed and must not be affected by an email failure.

Send via the existing SMTP infrastructure. If the send fails, log it as a warning (event: BUFFER_ALERT_EMAIL_FAILED) and do not throw. Do not retry the email — the Redis key is already set, so the next buffer insert on the same day will be suppressed anyway. The email failure is non-critical.

On success, emit a structured log: event: BUFFER_ALERT_EMAIL_SENT, partner_id, date, gate (which gate triggered this buffer — for traceability).

Refer to the point 15, to find the email template.

### **Achievement Unlock API**

This API is an ops-level endpoint callable only by a restricted set of human operators. Access is controlled through three layers of validation — service credentials, a permitted client allowlist, and a permitted user ID allowlist — all configured via environment variables. It is not routed through ws-1 and is not accessible via the admin UI.

When called, it enqueues a job into the dedicated achievement-unlock BullMQ queue and returns 202 Accepted immediately. The unlock worker picks up this job and executes two sequential steps for the previous calendar month (UTC) for the given partner:

- **Step 1** — Unlocks all achievement rows and salesperson_metrics_snapshot rows for partner_id \+ previous_month \+ previous_year by setting is_locked \= false and clearing locked_at.
- **Step 2** — Reads all pending rows from feed_data_buffer for the same partner_id \+ month \+ year, re-enqueues each payload into its original_job_queue unchanged, and transitions each buffer row status to enqueued.

After Step 2 completes, the unlock worker sends an email notification to the configured recipients for the partner.

#### **Endpoint**

| POST /incentive/v1/internal/unlock-achievements |
| :---------------------------------------------- |

Direct S2S call to the Incentive Engine. Not routed through ws-1.

#### **Request Headers**

| Header          | Required | Notes                                       |
| --------------- | -------- | ------------------------------------------- |
| x-client-id     | Yes      | Validated against SERVICE_CREDENTIALS       |
| x-client-secret | Yes      | Validated against SERVICE_CREDENTIALS       |
| x-user-id       | Yes      | Validated against UNLOCK_PERMITTED_USER_IDS |

#### **Request Body**

| Field      | Type | Required | Notes                                            |
| ---------- | ---- | -------- | ------------------------------------------------ |
| partner_id | UUID | Yes      | Partner for whom achievements are to be unlocked |

#### **Step 1 \- Auth**

The Incentive Engine validates three layers on every request to this endpoint, in sequence. If any layer fails, the request is rejected immediately and the subsequent layers are not evaluated.

**Layer 1.1 — Service credential check**

x-client-id and x-client-secret are validated against SERVICE_CREDENTIALS in env. This is the same check applied to all S2S endpoints in the Incentive Engine.

On failure:

| { "status": "error", "error_code": "SIGNATURE_INVALID", "message": "Request signature invalid"} |
| :---------------------------------------------------------------------------------------------- |

**Layer 1.2 — Permitted user ID check**

After Layer 2 passes, the x-user-id header is checked against UNLOCK_PERMITTED_USER_IDS — a JSON array of permitted operator user IDs stored in env. This is the third and final gate. Even if the calling service identity is permitted, the specific human operator initiating the call must be explicitly listed.

x-user-id is a required header on this endpoint. If it is absent:

| { "status": "error", "error_code": "USER_ID_MISSING", "message": "x-user-id header is required for this endpoint"} |
| :----------------------------------------------------------------------------------------------------------------- |

If x-user-id is present but not in UNLOCK_PERMITTED_USER_IDS:

| { "status": "error", "error_code": "UNAUTHORIZED_USER", "message": "This user is not permitted to call this endpoint"} |
| :--------------------------------------------------------------------------------------------------------------------- |

month and year are never accepted as inputs. The previous calendar month and year are always derived server-side from the UTC clock at the time of the API call. This prevents accidental or malicious unlock of arbitrary periods.

#### **Step 2 \- Pre-checks (synchronous, before enqueuing the unlock job)**

The following validations run synchronously after auth passes. If any pre-check fails, the API returns a 4xx immediately and no job is enqueued.

**Pre-check 2.1 — Target for that partner exists and is active**

**Validate that partner_id has an active target. On failure:**

| { "status": "error", "error_code": "PARTNER_NOT_FOUND", "message": "No active target found for given partner_id"} |
| :---------------------------------------------------------------------------------------------------------------- |

**Pre-check 2.2 — No active calculation running for the previous month**

Query incentive_run_log for any row matching partner_id \+ previous_month \+ previous_year with status IN ('pending', 'processing'). If found, the incentive calculation is actively running and unlocking achievements at this point would corrupt the in-flight calculation.

| { "status": "error", "error_code": "CALCULATION_IN_PROGRESS", "message": "An incentive calculation is currently running for the previous month. Unlock is not permitted until it completes."} |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

**Pre-check 2.3 — No duplicate unlock job already active**

Check whether an unlock job for this partner_id \+ previous_month \+ previous_year is already present in the BullMQ unlock queue in an active or waiting state. Prevents duplicate jobs from being enqueued if the endpoint is called twice in quick succession.

| { "status": "error", "error_code": "UNLOCK_ALREADY_IN_PROGRESS", "message": "An unlock job for this period is already in progress."} |
| :----------------------------------------------------------------------------------------------------------------------------------- |

#### **Step 3 — Derive previous month and year (synchronous)**

The API derives previous_month and previous_year from the UTC clock at the time the request is processed. These values are baked directly into the job payload before enqueue. The unlock worker uses these values as-is and does not re-derive them.

#### **Step 4 — Enqueue job into achievement-unlock queue (synchronous)**

The API enqueues a single job into the achievement-unlock BullMQ queue with the following payload:

| { "job_type": "ACHIEVEMENT_UNLOCK", "partner_id": "\<uuid\>", "month": 3, "year": 2026, "triggered_by_client": "\<x-client-id\>", "triggered_by_user": "\<x-user-id\>"} |
| :---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

The job_type: ACHIEVEMENT_UNLOCK field serves as an explicit identifier. The unlockNotificationMailer (Step 7\) validates this field before sending the email and refuses to send if it is absent or does not match. This ensures the email notification can never be triggered from any context other than a legitimate unlock job.

#### **Step 5 — API returns 202 Accepted (synchronous)**

The API returns immediately after the job is enqueued. All subsequent steps execute asynchronously in the unlock worker.

| { "status": "success", "data": { "message": "Unlock initiated. Achievements will be unlocked and buffered events re-enqueued asynchronously.", "partner_id": "\<uuid\>", "month": 3, "year": 2026, "triggered_by_client": "\<x-client-id\>", "triggered_by_user": "\<x-user-id\>" }} |
| :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |

#### **Step 6 — Unlock worker picks up the job from achievement-unlock queue (async)**

The unlock worker, co-located in the same Kubernetes worker deployment as the three existing achievement workers, picks up the job from the achievement-unlock queue. It reads partner_id, month, year, triggered_by_client, and triggered_by_user from the job payload.

If the worker crashes or throws at any point during Steps 7 or 8, BullMQ marks the job as failed and retries it after a backoff delay. Both steps are designed to be idempotent — safe to run multiple times without producing incorrect results.

#### **Step 7 — Unlock achievements and snapshots (async, within unlock worker)**

The unlock worker opens a database transaction and issues a bulk UPDATE on the achievement table for all rows matching partner_id \+ month \+ year where is_locked \= true, setting is_locked \= false and locked_at \= NULL.

The same bulk UPDATE is applied to salesperson_metrics_snapshot for the same partner_id \+ month \+ year in the same transaction. Both tables are unlocked atomically — if the transaction fails, neither table is partially unlocked and the job retries.

This step is idempotent. Setting is_locked \= false on already-unlocked rows is a no-op. On a retry, rows unlocked in a previous attempt are unaffected and rowsAffected for those rows will be zero.

If no locked rows are found in either table, the step completes with zero rows affected and the worker proceeds to Step 8 regardless.

Structured log on completion:

- event: ACHIEVEMENTS_UNLOCKED
- partner_id, month, year, achievement_rows_unlocked, snapshot_rows_unlocked, triggered_by_client, triggered_by_user

#### **Step 8 — Re-enqueue buffered events (async, within unlock worker)**

The unlock worker queries feed_data_buffer for all rows matching partner_id \+ month \+ year where status \= 'pending'. Rows are fetched in created_at ASC order — oldest first — to preserve approximate arrival order on reprocessing.

Rows are processed in batches (default batch size: 100\) to avoid holding large in-memory sets or overwhelming the queues in a single burst.

For each row in the batch:

- The raw payload is enqueued into the BullMQ queue named in original_job_queue, unchanged. No transformation is applied. The receiving achievement worker's existing Gate 1 idempotency check handles any duplicates.
- If the BullMQ enqueue call succeeds: feed_data_buffer.status is set to enqueued, enqueued_at is set to NOW(), and last_enqueue_error is set to NULL — all atomically in the same DB UPDATE.
- If the BullMQ enqueue call fails (Redis unavailable, queue error): the row status remains pending and last_enqueue_error is updated with the error message. The worker logs a structured warning (event: BUFFER_REENQUEUE_FAILED, row id, error) and continues to the next row. The row will be retried on the next Unlock API call. This failure does not cause the BullMQ job itself to throw — the unlock worker processes all rows in the batch and reports per-row outcomes in the structured completion log.

This step is idempotent. The worker only reads rows where status \= 'pending'. Rows already transitioned to enqueued in a previous attempt are not picked up again on retry.

If no pending rows are found, the step completes with zero rows processed

Structured log on completion:

- event: BUFFER_EVENTS_REENQUEUED
- partner_id, month, year, net_sales_rows_enqueued, call_plan_rows_enqueued, new_customer_rows_enqueued, total_rows_enqueued, rows_failed_to_enqueue, triggered_by_client, triggered_by_user

# **15\. Email template**

### **Email Template 1 — ACHIEVEMENT_NOT_SETTLED**

**Subject:** \[Action Required\] Achievement Data Not Ready — {Partner Name} ({Month} {Year})

**Body:**

Hi Team,

The incentive calculation for **{Partner Name}** for **{Month} {Year}** could not proceed for the following scheme(s) because the achievement data is not yet ready for processing.

| Scheme        | Status    | Details   |
| :------------ | :-------- | :-------- |
| {scheme_name} | Not Ready | {details} |

Where {details} is populated as:

- For QUEUE_IN_FLIGHT: _"Data is still being written — {active \+ waiting \+ delayed} job(s) pending in queue."_
- For STILL_SETTLING: _"Data was last updated {minutes_since_last_write} min ago and may not be complete yet."_

**Action Required:** Please wait for the data to finish processing and retry the incentive calculation. If this issue persists, contact the engineering team.

**Triggered by:** {CALCULATION_CRON / CATCHUP_CRON / MANUAL_TRIGGER} **Checked at:** {timestamp} WIB

_— Incentive Management System. This is an automated message. Do not reply to this email._

### **Email Template 2 — Data added in Buffer Table**

**Subject:** \[Action Required\] Buffered Achievement Events Detected — {Partner Name} ({Month} {Year})

**Body:**

Hi Team,

Achievement data has arrived for **{Partner Name}** for the period **{Month} {Year}**, but could not be processed because the incentive calculation cycle has been initiated or the achievement record is currently locked.

The event(s) have been buffered and are awaiting reprocessing.

**Action Required:** Once the incentive calculation for this period is complete, please call the Achievement Unlock API to unlock achievement rows and replay all buffered events.

**Endpoint:** POST /incentive/v1/internal/unlock-achievements **Partner ID:** {partner_id} **Period:** {Month} {Year}

If you have already initiated an unlock or believe this alert is not actionable, no further action is needed.

Check the feed_data_buffer table for the full list of pending events.

_— Incentive Management System This is an automated message. Do not reply to this email._

### **Email template 3 — Notify IMP Stakeholders about Slab updation**

**Subject:** Incentive Slab Configuration Updated — {{Scheme Name}} | {{Month}} {{Year}}

**Email:**

Hi Team,

The incentive slab configuration for **{{scheme\_name}}** has been updated for the period **{{valid\_from}} – {{valid\_to}}**. Recalculation will run automatically on **{{rerun\_date}}**, or can be triggered manually before then.

**Configuration Period**

| Field      | Value                  |
| ---------- | ---------------------- |
| Valid From | {{valid\_from}}        |
| Valid To   | {{valid\_to}}          |
| Config ID  | {{schema\_config\_id}} |

**Deprecated Slabs**

| Salesperson Type | Slab Type      | Symbol     | Threshold          | Payout (Rp)     |
| ---------------- | -------------- | ---------- | ------------------ | --------------- |
| {{sp\_type}}     | {{slab\_type}} | {{symbol}} | {{old\_threshold}} | {{old\_payout}} |

**New Slabs**

| Salesperson Type | Slab Type      | Symbol     | Threshold          | Payout (Rp)     |
| ---------------- | -------------- | ---------- | ------------------ | --------------- |
| {{sp\_type}}     | {{slab\_type}} | {{symbol}} | {{new\_threshold}} | {{new\_payout}} |

**Updated by:** {{updated\_by\_name}} **Updated at:** {{updated\_at}} WIB

If this change was made in error, contact your system operator immediately. Slab edits are locked after **{{rerun\_date}}**.

_— Incentive Management System This is an automated message. Do not reply to this email._

### **Email template 4 — Feed and Achievement Data check**

**Subject:** \[ACTION REQUIRED\] Incentive data missing — {PARTNER_NAME} / {MONTH YYYY}

Hi Team,

The Incentive Engine's pre-calculation check detected missing data for **{MONTH YYYY}** under partner **{PARTNER_NAME}**. Incentive calculations for the affected schemes cannot proceed until this is resolved.

**Missing data summary**

| Data Type                           | Status         | Affected Scheme(s) | Details                                      |
| ----------------------------------- | -------------- | ------------------ | -------------------------------------------- |
| Ageing data                         | {MISSING / OK} | Incentive 6        | No ageing records found for {MONTH YYYY}     |
| Activation call data                | {MISSING / OK} | Incentive 5        | No activation records found for {MONTH YYYY} |
| Achievement — T3 (Call Plan)        | {MISSING / OK} | Incentive 7, 8     | No achievement rows found for {MONTH YYYY}   |
| Achievement — T4 (Unique Customers) | {MISSING / OK} | Incentive 9, 10    | No achievement rows found for {MONTH YYYY}   |
| Achievement — T5 (JOT Omset)        | {MISSING / OK} | Incentive 10, 11   | No achievement rows found for {MONTH YYYY}   |
| Achievement — T6 (Weekly Revenue)   | {MISSING / OK} | Incentive 8        | No achievement rows found for {MONTH YYYY}   |

**_NOTE for us \- (Only rows marked MISSING require action. Remove OK rows before sending.)_**

**Incident details**

- Partner: {PARTNER_NAME} (partner_id: {PARTNER_ID})
- Affected period: {01 MMM YYYY} – {31 MMM YYYY}
- Detected at: {DD MMM YYYY, HH:MM WIB}
- Payout cutoff: {DD MMM YYYY}
- Correlation ID: {JOB_ID / TRACE_ID}
- Environment: {PROD / STAGING}

**Required actions**

1. **Ageing data** (if missing) — Submit the AR ageing CSV for {MONTH YYYY} via POST /api/incentive/v1/webhooks/ar-ageing
2. **Activation call data** (if missing) — Submit the activation call CSV for {MONTH YYYY} via POST /api/incentive/v1/webhooks/activation-calls. Include all salespersons — if a salesperson had zero activations, include them with activation_count \= 0
3. **Achievement data** (if missing) — Verify that all daily billing and monthly new-customer webhooks were received and processed for every working day. Re-submit any missing feeds via \-  
   POST /target/v1/webhooks/daily-calls  
   POST /target/v1/webhooks/daily-sales  
   POST /target/v1/webhooks/new-customer-monthly

If any data is genuinely unavailable or no incentives are being disbursed for this period, kindly ignore this email.

_— Incentive Management System This is an automated message. Do not reply to this email._

### **Email template 5 — CONFIG_MISSING Check at the start of incentive calculation**

**Subject:** \[Action Required\] Slab Config Missing — {Partner Name} ({Month} {Year})

Hi Team,

The incentive calculation for {Partner Name} for {Month} {Year} could not proceed for the following scheme(s) because no active slab configuration was found for the calculation period.

**| Schema | Schema ID | Expected Period |**

**| {scheme_name} | {schema_id} | {calc_month_start} – {calc_month_end} |**

What this means: Without a valid slab configuration, incentive payouts cannot be computed for the affected scheme(s). These schemes have been skipped for the current run and an error has been recorded in the run error log.

Action Required: Ensure an active slab config exists in incentive_schema_configs for the above schema(s) with:

• status \= 'active'

• valid_from \<= {calc_month_start}

• valid_to \>= {calc_month_end}

Once the config is in place, the Catch-up CRON on the 4th will retry automatically. Alternatively, a manual recalculation can be triggered via:

POST /incentive/v1/manual-trigger

Triggered by: {CALCULATION_CRON / CATCHUP_CRON / MANUAL_TRIGGER}

Checked at: {timestamp} WIB

_— Incentive Management System. This is an automated message. Do not reply to this email._
