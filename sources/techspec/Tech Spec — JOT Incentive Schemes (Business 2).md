# Tech Spec — JOT Incentive Schemes (Business 2\)

Doc Links \- 

- [JOT incentive result schema thinking Doc](https://docs.google.com/document/d/1QrY0ijjjd9p-zCTNJV1b3qJkDOcMYyJu-NX4nh4c1Xk/edit?usp=sharing)

## Context

The Incentive Engine supports two JOT-based incentive schemes for Business 2:

* **JOT Range Products** — applicable to SMO. Rewards a salesperson based on how many unique JOT **product groups** a customer purchased from them in a month. Customers are bucketed into configurable range bands (e.g. 2–3, 4–5, 6+), and the count of customers falling in each band is evaluated against Low / Mid / High thresholds to determine payout tier.

* **JOT for Single Product** — applicable to STO and SFT. Follows the same range-band and tier evaluation logic, but the metric is the count of unique **individual products** (not product groups) a customer purchased from that salesperson in the month.

Both schemes share the same slab structure, the same range evaluator, and the same DB tables for slab configuration. The distinction between them is purely in the input metric fed to the evaluator at calculation time.

Unlike standard threshold-based schemes (Call Plan, Weekly Revenue etc.), JOT schemes do not use incentive\_payout\_slabs. They use 2 dedicated tables — incentive\_range\_bands, incentive\_range\_payouts — which together model the fixed three-tier (Low / Mid / High) structure per range band per salesperson type.

Supervisor (SPV) incentive for both JOT schemes is computed by identifying the supervisor of each salesperson via the Hierarchy API at calculation time, then paying them the SPV payout amount configured for the tier their reportee achieved. The supervisor's own type is irrelevant to payout lookup — the SPV payout is keyed to the range band, not to the supervisor type. SP and SPV payout configurations are stored in the same table (incentive\_range\_payouts) distinguished by a participant\_type column ('SP' or 'SPV'), keeping them independently evolvable while maintaining an explicit structural link via range\_band\_id.

## 1\. DB Schema

### **1.1 Overview**

JOT slab configuration is split across two tables with a clear ownership boundary:

* incentive\_range\_bands — owns the range bucket definition (range\_start, range\_end), the tier thresholds (Low / Mid / High), the salesperson type scoping, and the lifecycle (status). This is the parent entity. One row per salesperson type per range band.

* incentive\_range\_payouts — owns payout amounts per band per participant type. Two rows per band — one for SP (participant\_type \= 'SP') and one for SPV (participant\_type \= 'SPV'). Kept as a separate table to allow independent UI and config evolution for SPV in future.

Thresholds live exclusively in incentive\_range\_bands because they define the tier boundaries for the band itself — both SP and SPV payout tiers are evaluated against the same thresholds. Status lives exclusively in incentive\_range\_bands because payout rows have no independent lifecycle — they are created and deactivated with their parent band.

**Schema evolution note:** The original design of this domain used a single table — incentive\_range\_payout\_slabs — which modelled each tier (Low, Mid, High) as a separate row, using threshold\_start / threshold\_end columns to represent the tier boundary and a single payout\_amount column for the payout value. This approach had four structural problems:

* **No SPV payout representation** — payout\_amount was a single column and could not hold both SP and SPV payout values per tier.  
* **Tier integrity not enforceable at DB level** — Low \< Mid \< High ordering across three independent rows cannot be expressed as a single CHECK constraint.  
* **No atomic guarantee** — on a partial write failure, 1 or 2 of 3 tier rows could be committed with the third missing, leaving a corrupt band in the table with no DB-level detection.  
* **Implicit SP↔SPV coupling** — there was no structural link between an SP row and its corresponding SPV row for the same band; the link was resolved implicitly by matching range\_start values in application code.

The current two-table design addresses all four problems.

### **1.2 Table Definitions**

#### **Table 1 — incentive\_range\_bands**

| CREATE TABLE incentive\_range\_bands (  id                UUID           PRIMARY KEY DEFAULT gen\_random\_uuid(),  schema\_config\_id  UUID           NOT NULL REFERENCES   incentive\_schema\_configs(id)                                   ON DELETE RESTRICT,  salesperson\_type  VARCHAR(20)    NOT NULL,  range\_start       INTEGER        NOT NULL,  range\_end         INTEGER,                   \-- NULL \= open-ended (e.g. 6+)  low\_threshold     NUMERIC(15,4)  NOT NULL,  mid\_threshold     NUMERIC(15,4)  NOT NULL,  high\_threshold    NUMERIC(15,4)  NOT NULL,  status            VARCHAR(20)    NOT NULL DEFAULT 'active',  created\_at        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),  created\_by        UUID,  updated\_at        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),  updated\_by        UUID,  CONSTRAINT chk\_irb\_salesperson\_type CHECK (    salesperson\_type IN ('STO', 'SFT', 'SMO') // Add more if missing  ),  CONSTRAINT chk\_irb\_range\_order CHECK (    range\_end IS NULL OR range\_end \> range\_start  ),  CONSTRAINT chk\_irb\_threshold\_order CHECK (    low\_threshold \< mid\_threshold    AND mid\_threshold \< high\_threshold  ),  CONSTRAINT chk\_irb\_status CHECK (    status IN ('active', 'inactive')  ),  CONSTRAINT uq\_irb\_config\_sp\_type\_range UNIQUE (    schema\_config\_id, salesperson\_type, range\_start  )); |
| :---- |

#### **Table 2 — incentive\_range\_payouts**

| CREATE TABLE incentive\_range\_payouts (  id                UUID           PRIMARY KEY DEFAULT gen\_random\_uuid(),  range\_band\_id     UUID           NOT NULL REFERENCES incentive\_range\_bands(id)                                   ON DELETE RESTRICT,  participant\_type  VARCHAR(10)    NOT NULL,   \-- 'SP' or 'SPV'  low\_payout        NUMERIC(15,2)  NOT NULL,  mid\_payout        NUMERIC(15,2)  NOT NULL,  high\_payout       NUMERIC(15,2)  NOT NULL,  created\_at        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),  created\_by        UUID,  updated\_at        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),  updated\_by        UUID,  CONSTRAINT chk\_irp\_participant\_type CHECK (    participant\_type IN ('SP', 'SPV')  ),  CONSTRAINT chk\_irp\_payout\_positive CHECK (    low\_payout \> 0    AND mid\_payout \> 0    AND high\_payout \> 0  ),  \-- one SP row and one SPV row per band, no more  CONSTRAINT uq\_irp\_band\_participant UNIQUE (range\_band\_id, participant\_type)); |
| :---- |

1.3 Indexes

| \-- incentive\_range\_bands\-- Primary config-time and calculation-time lookupCREATE INDEX idx\_irb\_schema\_config\_id  ON incentive\_range\_bands(schema\_config\_id);\-- Partial index \-- calculation engine only reads active bandsCREATE INDEX idx\_irb\_schema\_config\_active  ON incentive\_range\_bands(schema\_config\_id)  WHERE status \= 'active';\-- incentive\_range\_payouts\-- Join from band to payoutsCREATE INDEX idx\_irp\_range\_band\_id  ON incentive\_range\_payouts(range\_band\_id); |
| :---- |

1.4 Row Semantics

| Table | low/mid/high\_threshold | participant\_type | low/mid/high\_payout |
| :---- | :---- | :---- | :---- |
| incentive\_range\_bands | Tier boundary — absolute customer count. Same thresholds apply to both SP and SPV evaluation. | — | — |
| incentive\_range\_payouts (participant\_type \= 'SP') | — | SP | What the salesperson earns when their customer count for this band hits this tier. |
| incentive\_range\_payouts (participant\_type \= 'SPV') | — | SPV | What the supervisor earns when their reportee's customer count for this band hits this tier. Supervisor identity resolved at runtime via Hierarchy API. |

####  **Table 3 — jot\_incentive\_sp**

| CREATE TABLE jot\_incentive\_sp (  id                UUID           PRIMARY KEY DEFAULT gen\_random\_uuid(),  result\_id         UUID           NOT NULL REFERENCES incentive\_results(id) ON DELETE RESTRICT,  range\_band\_id     UUID           NOT NULL REFERENCES incentive\_range\_bands(id) ON DELETE RESTRICT,  range\_start       INTEGER        NOT NULL,  range\_end         INTEGER,                   \-- NULL \= open-ended (e.g. 6+)  raw\_customer\_count  INTEGER      NOT NULL,  carry\_in          INTEGER        NOT NULL DEFAULT 0,  adjusted\_count    INTEGER        NOT NULL,  carry\_out         INTEGER        NOT NULL DEFAULT 0,  tier\_hit VARCHAR(10) NOT NULL, \-- 'low', 'mid', 'high', 'not\_met'  payout\_amount     NUMERIC(15,2)  NOT NULL,  created\_at        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),  updated\_at        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),  CONSTRAINT chk\_jis\_tier\_hit CHECK ( tier\_hit IN ('low', 'mid', 'high', 'not\_met') ),  CONSTRAINT chk\_jis\_counts\_non\_negative CHECK (    raw\_customer\_count \>= 0    AND carry\_in \>= 0    AND adjusted\_count \>= 0    AND carry\_out \>= 0  ),  CONSTRAINT uq\_jis\_result\_band UNIQUE (result\_id, range\_band\_id)); |
| :---- |

**Indexes**	

| \-- Join from incentive\_results to SP band detailsCREATE INDEX idx\_jis\_result\_id  ON jot\_incentive\_sp(result\_id);\-- Lookup by band for auditing or carry-forward tracingCREATE INDEX idx\_jis\_range\_band\_id  ON jot\_incentive\_sp(range\_band\_id); |
| :---- |

#### **Table 4 —  jot\_incentive\_spv**

| CREATE TABLE jot\_incentive\_spv (  id                  UUID           PRIMARY KEY DEFAULT gen\_random\_uuid(),  result\_id           UUID           NOT NULL REFERENCES incentive\_results(id) ON DELETE RESTRICT,  \-- SPV's incentive\_results row  salesperson\_type    VARCHAR(50)    NOT NULL,  \-- SP type group being evaluated (e.g. 'SMO', 'STO')  range\_band\_id       UUID           NOT NULL REFERENCES incentive\_range\_bands(id) ON DELETE RESTRICT,  reportee\_count      INTEGER        NOT NULL,  \-- number of reportees in this SP type group \-- used to derive scaled thresholds  aggregated\_count    INTEGER        NOT NULL,  \-- sum of raw customer counts across all reportees for this band  carry\_in            INTEGER        NOT NULL DEFAULT 0,  carry\_out           INTEGER        NOT NULL DEFAULT 0,  tier\_hit            VARCHAR(10),  \-- 'low', 'mid', 'high', NULL if no tier met  payout\_amount       NUMERIC(15,2)  NOT NULL,  created\_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),  updated\_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),  CONSTRAINT chk\_jispv\_tier\_hit CHECK (tier\_hit IN ('low', 'mid', 'high', 'not\_met')),  CONSTRAINT chk\_jispv\_counts\_non\_negative CHECK (    reportee\_count   \>= 0    AND aggregated\_count \>= 0    AND carry\_in     \>= 0    AND carry\_out    \>= 0  ),  CONSTRAINT uq\_jispv\_result\_type\_band UNIQUE (result\_id, salesperson\_type, range\_band\_id)); |
| :---- |

**Indexes**

| \-- Primary join: SPV result → its band rowsCREATE INDEX idx\_jispv\_result\_id  ON jot\_incentive\_spv(result\_id);\-- Lookup by band for auditingCREATE INDEX idx\_jispv\_range\_band\_id  ON jot\_incentive\_spv(range\_band\_id);\-- Lookup by SP type groupCREATE INDEX idx\_jispv\_salesperson\_type  ON jot\_incentive\_spv(salesperson\_type); |
| :---- |

#### **Table 5 —  salesperson\_product\_map**

Note \- this table is created in pgclosio DB and its migration file will be present in ws2closio repository

| CREATE EXTENSION IF NOT EXISTS btree\_gist;CREATE TABLE salesperson\_product\_map (  id                UUID         PRIMARY KEY DEFAULT gen\_random\_uuid(),  partner\_id        UUID         NOT NULL,  salesperson\_type  VARCHAR(20)  NOT NULL,                 \-- STO, SFT, SMO, ...  mapping\_type      VARCHAR(20)  NOT NULL,                 \-- 'PRODUCT' | 'PRODUCT\_GROUP'  external\_refs     JSONB        NOT NULL DEFAULT '\[\]'::jsonb,                                                           \-- opaque Qlik/snapshot refs,                                                           \-- e.g. \["grp\_1","grp\_2"\] \-- no FK  valid\_from        DATE         NOT NULL,                 \-- first day of from-month (2026-03-01)  valid\_to          DATE,                                  \-- first day of to-month; NULL \= ongoing  status            VARCHAR(20)  NOT NULL DEFAULT 'active',-- 'active' | 'inactive' (kill-switch only)  created\_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),  created\_by        UUID,  updated\_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),  updated\_by        UUID,  CONSTRAINT chk\_spm\_mapping\_type   CHECK (mapping\_type IN ('PRODUCT', 'PRODUCT\_GROUP')),  CONSTRAINT chk\_spm\_status         CHECK (status IN ('active', 'inactive')),  CONSTRAINT chk\_spm\_refs\_is\_array  CHECK (jsonb\_typeof(external\_refs) \= 'array'),  CONSTRAINT chk\_spm\_refs\_nonempty  CHECK (jsonb\_array\_length(external\_refs) \> 0),  CONSTRAINT chk\_spm\_period\_order   CHECK (valid\_to IS NULL OR valid\_to \>= valid\_from),  \-- One active mapping per (partner, salesperson\_type, MAPPING\_TYPE) per period.  \-- A type may now hold one PRODUCT and one PRODUCT\_GROUP mapping at once, but  \-- never two of the same kind with overlapping periods.  CONSTRAINT excl\_spm\_no\_overlap EXCLUDE USING gist (    partner\_id        WITH \=,    salesperson\_type  WITH \=,    mapping\_type      WITH \=,                              \-- \<-- added to the grain    daterange(valid\_from, valid\_to, '\[\]') WITH &&  ) WHERE (status \= 'active'));CREATE INDEX idx\_spm\_partner\_active  ON salesperson\_product\_map (partner\_id, salesperson\_type, mapping\_type)  \-- \<-- added  WHERE status \= 'active'; |
| :---- |

#### **Table 6 —  supervisor\_salesperson\_type\_map**

| \-- btree\_gist already enabled by Table 5; statement is idempotentCREATE EXTENSION IF NOT EXISTS btree\_gist;CREATE TABLE supervisor\_salesperson\_type\_map (  id                 UUID         PRIMARY KEY DEFAULT gen\_random\_uuid(),  partner\_id         UUID         NOT NULL,  supervisor\_type    VARCHAR(20)  NOT NULL,                    \-- 'SPV DRY', 'SPV MIX', 'SPV MO', 'SPV FTO', ...  salesperson\_types  JSONB        NOT NULL DEFAULT '\[\]'::jsonb,-- SP types this supervisor oversees, e.g. \["STO","SMO"\]  valid\_from         DATE         NOT NULL,                    \-- first day of from-month (2026-03-01)  valid\_to           DATE,                                     \-- first day of to-month; NULL \= ongoing  status             VARCHAR(20)  NOT NULL DEFAULT 'active',   \-- 'active' │ 'inactive' (kill-switch only)  created\_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),  created\_by         UUID,  updated\_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),  updated\_by         UUID,  CONSTRAINT chk\_sstm\_status         CHECK (status IN ('active', 'inactive')),  CONSTRAINT chk\_sstm\_types\_is\_array CHECK (jsonb\_typeof(salesperson\_types) \= 'array'),  CONSTRAINT chk\_sstm\_types\_nonempty CHECK (jsonb\_array\_length(salesperson\_types) \> 0),  CONSTRAINT chk\_sstm\_period\_order   CHECK (valid\_to IS NULL OR valid\_to \>= valid\_from),  \-- One active mapping per (partner, supervisor\_type) per period \-- no overlapping active rows.  CONSTRAINT excl\_sstm\_no\_overlap EXCLUDE USING gist (    partner\_id       WITH \=,    supervisor\_type  WITH \=,    daterange(valid\_from, valid\_to, '\[\]') WITH &&  ) WHERE (status \= 'active'));CREATE INDEX idx\_sstm\_partner\_active  ON supervisor\_salesperson\_type\_map (partner\_id, supervisor\_type)  WHERE status \= 'active'; |
| :---- |

## 2\. GET Range Slabs API

### **2.1 Endpoint**

GET /api/incentives/v1/schemas/:schema\_id/configs/:config\_id/range-slabs

### **2.2 Auth Headers**

1. ws-1 will use cookies coming in the header to authenticate and retrieve the user details (in this API we only need partner\_id.  
2. ws2-incentive-engine uses x-client-id and x-client-secret coming in the headers to authenticate.  
3. X-Partner-Id is passed down as a request header.

### **2.3 Path Parameters**

| Parameter | Type | Required | Description |
| :---- | :---- | :---- | :---- |
| schema\_id | UUID | Yes | ID of the parent incentive schema |
| config\_id | UUID | Yes | ID of the incentive schema config |

### **2.4 Workflow**

1. Closio sends GET /api/incentives/v1/schemas/:schema\_id/configs/:config\_id/range-slabs to ws-1.  
2. ws-1 validates the cookie. If the cookie is invalid → ws-1 returns HTTP 401:  
   {  
     "status": "error",  
     "error\_code": "TOKEN\_INVALID",  
     "message": "User token invalid or expired"  
   }  
3. If cookie is valid → ws-1 retrieves authenticated user details (partner\_id).  
4. ws-1 validates the path parameters:  
   1. If schema\_id is not a valid UUID format → return HTTP 400:  
      {  
        "status": "error",  
        "error\_code": "INVALID\_SCHEMA\_ID",  
        "message": "schema\_id must be a valid UUID"  
      }  
   2. If config\_id is not a valid UUID format → return HTTP 400:  
      {  
        "status": "error",  
        "error\_code": "INVALID\_CONFIG\_ID",  
        "message": "config\_id must be a valid UUID"  
      }

5. ws-1 prepares a server-to-server request to ws2-incentive-engine:  
   1. Add headers: x-client-id, x-client-secret, X-Partner-Id  
6. ws2-incentive-engine applies S2S auth middleware. On any auth failure → return HTTP 401:  
   {  
     "status": "error",  
     "error\_code": "SIGNATURE\_INVALID",  
     "message": "Request signature invalid"  
   }

7. ws2-incentive-engine validates X-Partner-Id header is present. If missing → return HTTP 400:  
   {  
     "status": "error",  
     "error\_code": "PARTNER\_ID\_MISSING",  
     "message": "X-Partner-Id header is required"  
   }

8. ws2-incentive-engine verifies the schema exists and belongs to the given partner:  
     
   SELECT id FROM incentive\_schemas  
   WHERE id \= :schema\_id  
     AND partner\_id \= :partner\_id;

   1. If no record found → return HTTP 404:  
      {  
        "status": "error",  
        "error\_code": "SCHEMA\_NOT\_FOUND",  
        "message": "No incentive schema found for the given schema\_id"  
      }

9. ws2-incentive-engine verifies the config exists and belongs to the given schema:  
     
   SELECT id FROM incentive\_schema\_configs  
   WHERE id \= :config\_id  
     AND schema\_id \= :schema\_id;

   1. If no record found → return HTTP 404:

| {  "status": "error",  "error\_code": "CONFIG\_NOT\_FOUND",  "message": "No incentive schema config found for the given config\_id under the specified schema"} |
| :---- |

10. ws2-incentive-engine fetches all active range bands with SP and SPV payouts in a single query:

    SELECT  
      irb.id                AS range\_band\_id,  
      irb.salesperson\_type,  
      irb.range\_start,  
      irb.range\_end,  
      irb.low\_threshold,  
      irb.mid\_threshold,  
      irb.high\_threshold,  
      irp.participant\_type,  
      irp.low\_payout,  
      irp.mid\_payout,  
      irp.high\_payout  
    FROM incentive\_range\_bands irb  
    LEFT JOIN incentive\_range\_payouts irp  
      ON irp.range\_band\_id \= irb.id  
    WHERE irb.schema\_config\_id \= :config\_id  
      AND irb.status \= 'active'  
    ORDER BY irb.salesperson\_type ASC, irb.range\_start ASC, irp.participant\_type ASC;

11. If DB query fails → return HTTP 500:  
    {  
      "status": "error",  
      "error\_code": "INTERNAL\_ERROR",  
      "message": "Could not fetch range slabs for this config"  
    }

12. If zero rows returned → return HTTP 200 with empty slabs:  
    {  
      "status": "success",  
      "data": {  
        "schema\_id": "\<uuid\>",  
        "config\_id": "\<uuid\>",  
        "slabs": {}  
      }  
    }

13. ws2-incentive-engine assembles the response in a single pass over the query result:  
    1. Initialise an empty slabs object.  
    2. For each row in the query result:  
       1. If row.salesperson\_type is null → skip this row (band exists but has no payouts configured).  
       2. If slabs\[row.salesperson\_type\] does not exist → initialise it as an empty array.  
       3. Check if an entry for row.range\_band\_id already exists under slabs\[row.salesperson\_type\]. If not → create the band entry with empty tiers. Populate sp\_payout fields when participant\_type \= 'SP', populate spv\_payout fields when participant\_type \= 'SPV'.

14. Evaluate assembled result and return HTTP 200:

| {  "status": "success",  "data": {    "schema\_id": "\<uuid\>",    "config\_id": "\<uuid\>",    "slabs": {      "STO": \[        {          "range\_band\_id": "\<uuid\>",          "range\_start": 2,          "range\_end": 5,          "tiers": {            "low":  { "threshold": 30, "sp\_payout": 12000, "spv\_payout": 20000 },            "mid":  { "threshold": 40, "sp\_payout": 45000, "spv\_payout": 65000 },            "high": { "threshold": 50, "sp\_payout": 90000, "spv\_payout": 110000 }          }        }      \],      "SMO": \[        {          "range\_band\_id": "\<uuid\>",          "range\_start": 2,          "range\_end": 5,          "tiers": {            "low":  { "threshold": 30, "sp\_payout": 12000, "spv\_payout": 20000 },            "mid":  { "threshold": 40, "sp\_payout": 45000, "spv\_payout": 65000 },            "high": { "threshold": 50, "sp\_payout": 90000, "spv\_payout": 110000 }          }        }      \]    }  }} |
| :---- |

ws2-incentive-engine returns the response to ws-1. ws-1 validates the response structure and forwards it to Closio unchanged.

### 2.5 Error Reference

| HTTP Status | error\_code | Trigger |
| :---- | :---- | :---- |
| 400 | INVALID\_SCHEMA\_ID | schema\_id is not a valid UUID |
| 400 | INVALID\_CONFIG\_ID | config\_id is not a valid UUID |
| 400 | PARTNER\_ID\_MISSING | X-Partner-Id header is absent |
| 401 | TOKEN\_INVALID | Cookie invalid or expired at ws-1 |
| 401 | SIGNATURE\_INVALID | S2S auth failure at ws2-incentive-engine |
| 404 | SCHEMA\_NOT\_FOUND | No schema found for schema\_id under the given partner |
| 404 | CONFIG\_NOT\_FOUND | No config found for config\_id under the given schema\_id |
| 500 | INTERNAL\_ERROR | Unexpected DB or application error at any fetch step |

## 3\. POST Range Slabs API

### 3.1 Endpoint

POST /api/incentives/v1/schemas/:schema\_id/configs/range-slabs

### 3.2 Auth Headers

ws-1 will use cookies coming in the header to authenticate and retrieve the user details (in this API we need partner\_id, user\_id and user\_name).

ws2-incentive-engine uses x-client-id and x-client-secret coming in the headers to authenticate.

X-Partner-Id, X-User-Id and X-User-Name are passed down as request headers.

### 3.3 Path Parameters

| Parameter | Type | Required | Description |
| ----- | ----- | ----- | ----- |
| schema\_id | UUID | Yes | ID of the parent incentive schema |

### 3.4 Request Payload

| {  "valid\_from": "2026-03",  "valid\_to": "2026-12",  "slabs": {    "STO": \[      {        "range\_start": 2,        "range\_end": 5,        "tiers": {          "low":  { "threshold": 30, "sp\_payout": 12000, "spv\_payout": 20000 },          "mid":  { "threshold": 40, "sp\_payout": 45000, "spv\_payout": 65000 },          "high": { "threshold": 50, "sp\_payout": 90000, "spv\_payout": 110000 }        }      },      {        "range\_start": 6,        "range\_end": null,        "tiers": {          "low":  { "threshold": 30, "sp\_payout": 90000, "spv\_payout": 110000 },          "mid":  { "threshold": 40, "sp\_payout": 90000, "spv\_payout": 110000 },          "high": { "threshold": 50, "sp\_payout": 90000, "spv\_payout": 110000 }        }      }    \],    "SMO": \[ ... \]  }} |
| :---- |

### 3.5 Workflow

1. Closio sends POST /api/incentives/v1/schemas/:schema\_id/configs/range-slabs to ws-1.  
2. ws-1 validates the cookie. If the cookie is invalid → ws-1 returns HTTP 401:  
   {  
     "status": "error",  
     "error\_code": "TOKEN\_INVALID",  
     "message": "User token invalid or expired"  
   }  
3. If cookie is valid → ws-1 retrieves authenticated user details (partner\_id, user\_id, user\_name).  
4. ws-1 validates schema\_id path param is a valid UUID. If not → return HTTP 400:  
   {  
     "status": "error",  
     "error\_code": "VALIDATION\_ERROR",  
     "message": "schema\_id must be a valid UUID"  
   }  
5. ws-1 validates presence and basic format of required request body fields:  
   1. valid\_from and valid\_to must be present and in YYYY-MM format.  
   2. slabs must be present and must be a non-empty object.  
   3. If any fail → return HTTP 400:

   {

     "status": "error",

     "error\_code": "VALIDATION\_ERROR",

     "message": "Request body validation failed",

     "details": {

       "missing\_or\_invalid": \["valid\_from", "slabs"\]

     }

   }

6. ws-1 prepares a server-to-server request to ws2-incentive-engine:  
   1. Add headers: x-client-id, x-client-secret, X-Partner-Id, X-User-Id, X-User-Name  
   2. Pass schema\_id in the path param.  
   3. Include the validated request body.  
7. ws2-incentive-engine applies S2S auth middleware. On any auth failure → return HTTP 401:  
   {  
     "status": "error",  
     "error\_code": "SIGNATURE\_INVALID",  
     "message": "Request signature invalid"  
   }  
8. ws2-incentive-engine validates required headers are present (X-Partner-Id, X-User-Id, X-User-Name). If any missing → return HTTP 400:  
   {  
     "status": "error",  
     "error\_code": "MISSING\_HEADERS",  
     "message": "Required headers are missing",  
     "details": {  
       "missing": \["X-User-Id"\]  
     }  
   }  
9. ws2-incentive-engine validates schema\_id path param is a valid UUID. If invalid → return HTTP 400:  
   {  
     "status": "error",  
     "error\_code": "VALIDATION\_ERROR",  
     "message": "schema\_id must be a valid UUID"  
   }  
10. ws2-incentive-engine validates request body fields:  
    1. valid\_from and valid\_to must be present and in YYYY-MM format.  
    2. slabs must be present and must be a non-empty object.  
    3. If any fail → return HTTP 400:  
       {  
         "status": "error",  
         "error\_code": "VALIDATION\_ERROR",  
         "message": "Request body validation failed",  
         "details": {  
           "missing\_or\_invalid": \["valid\_to"\]  
         }  
       }  
11. ws2-incentive-engine verifies schema\_id exists in incentive\_schemas and is mapped to the partner\_id. If not found → return HTTP 404:  
    {  
      "status": "error",  
      "error\_code": "NOT\_FOUND",  
      "message": "Incentive schema not found for this partner"  
    }  
12. ws2-incentive-engine runs version level validations:  
    1. Parse valid\_from to the first day of the month (e.g. 2026-03 → 2026-03-01) and valid\_to to the last day of that month.  
    2. Both valid\_from and valid\_to must be the current month or a future month. If either is a past period → return HTTP 400:  
       {  
         "status": "error",  
         "error\_code": "INVALID\_PERIOD",  
         "message": "valid\_from and valid\_to must be current month or a future period"  
       }  
    3. valid\_to must be greater than or equal to valid\_from. If not → return HTTP 400:  
       {  
         "status": "error",  
         "error\_code": "INVALID\_PERIOD",  
         "message": "valid\_to must be greater than or equal to valid\_from"  
       }  
    4. Check for period overlap with existing configs for the same schema\_id and partner\_id:

       SELECT id FROM incentive\_schema\_configs

       WHERE schema\_id \= :schema\_id

         AND valid\_from \<= :valid\_to

         AND valid\_to \>= :valid\_from;

    If any record found → return HTTP 409:

       {

         "status": "error",

         "error\_code": "PERIOD\_OVERLAP",

         "message": "A config already exists for this schema that overlaps with the given period"

       }

13. ws2-incentive-engine runs slab level validations. All validations run upfront before any DB write. If any fail → return HTTP 400 immediately:

**Step 1 — Validate top-level slabs structure:**

1. If any key in slabs is not one of STO, SFT, SMO → return HTTP 400:

   {

     "status": "error",

     "error\_code": "INVALID\_SALESPERSON\_TYPE",

     "message": "Invalid salesperson type: \<type\>. Must be one of STO, SFT, SMO"

   }

2. If any salesperson type's band array is empty → return HTTP 400:

   {

     "status": "error",

     "error\_code": "INVALID\_PAYLOAD",

     "message": "slabs.\<salesperson\_type\> must contain at least one band"

   }

**Step 2 — Validate each band per salesperson type:**

1. Sort bands by range\_start ascending. For each band:  
   1. If range\_start is missing or not a positive integer → return HTTP 400:  
      {  
        "status": "error",  
        "error\_code": "INVALID\_RANGE\_START",  
        "message": "range\_start must be a positive integer in slabs.\<salesperson\_type\>\[\<index\>\]"  
      }  
   2. If range\_end is not null and not a positive integer → return HTTP 400:  
      {  
        "status": "error",  
        "error\_code": "INVALID\_RANGE\_END",  
        "message": "range\_end must be a positive integer or null in slabs.\<salesperson\_type\>\[\<index\>\]"  
      }  
   3. If range\_end is not null and range\_end \<= range\_start → return HTTP 400:

   {

    	 "status": "error",

     	"error\_code": "INVALID\_RANGE\_ORDER",

     	"message": "range\_end must be greater than range\_start in slabs.\<salesperson\_type\>\[\<index\>\]"

   }

   4. If range\_end is null and this is not the last band (highest range\_start) → return HTTP 400:  
      {  
        "status": "error",  
        "error\_code": "INVALID\_OPEN\_ENDED\_BAND",  
        "message": "range\_end can only be null on the last band in slabs.\<salesperson\_type\>"  
      }  
   5. If tiers is missing or any of low, mid, high keys are absent → return HTTP 400:  
      {  
        "status": "error",  
        "error\_code": "INVALID\_TIERS",  
        "message": "tiers must contain low, mid, and high in slabs.\<salesperson\_type\>\[\<index\>\]"  
      }  
   6. For each tier (low, mid, high) — if threshold, sp\_payout, or spv\_payout is missing or not a positive number → return HTTP 400:  
      {  
        "status": "error",  
        "error\_code": "INVALID\_TIER\_VALUE",  
        "message": "threshold, sp\_payout, and spv\_payout must be positive numbers in slabs.\<salesperson\_type\>\[\<index\>\].tiers.\<tier\>"  
      }  
   7. If low.threshold \>= mid.threshold or mid.threshold \>= high.threshold → return HTTP 400:  
      {  
        "status": "error",  
        "error\_code": "INVALID\_THRESHOLD\_ORDER",  
        "message": "Thresholds must be in ascending order (low \< mid \< high) in slabs.\<salesperson\_type\>\[\<index\>\]"  
      }

**Step 3 — Validate contiguity across bands within each salesperson type:**

1. For each consecutive pair of bands sorted by range\_start ascending — if band\_N.range\_end \+ 1 \!== band\_N+1.range\_start → return HTTP 400:  
   {  
     "status": "error",  
     "error\_code": "NON\_CONTIGUOUS\_RANGES",  
     "message": "Range bands must be contiguous. Gap or overlap detected between range\_end \<range\_end\> and range\_start \<range\_start\> in slabs.\<salesperson\_type\>"  
   }  
2. If all validations pass, begin a single DB transaction. If any operation inside fails → rollback the entire transaction and return HTTP 500:  
   {  
     "status": "error",  
     "error\_code": "INTERNAL\_ERROR",  
     "message": "Could not create range slabs. No data was written."  
   }  
14. Insertion

**Step 1 — Insert into incentive\_schema\_configs:**

INSERT INTO incentive\_schema\_configs (

  schema\_id, valid\_from, valid\_to,

  status, created\_by, created\_by\_name,

  created\_at, updated\_by, updated\_by\_name, updated\_at

) VALUES (

  :schema\_id, :valid\_from, :valid\_to,

  'active', :user\_id, :user\_name,

  NOW(), NULL, NULL, NOW()

)

RETURNING id;

Store the returned id as config\_id.

**Step 2 — Insert range bands and payout rows:**

For each salesperson\_type in slabs, for each band — insert into incentive\_range\_bands:

INSERT INTO incentive\_range\_bands (

  schema\_config\_id, salesperson\_type,

  range\_start, range\_end,

  low\_threshold, mid\_threshold, high\_threshold,

  status, created\_by, updated\_by, created\_at, updated\_at

) VALUES (

  :config\_id, :salesperson\_type,

  :range\_start, :range\_end,

  :low\_threshold, :mid\_threshold, :high\_threshold,

  'active', :user\_id, :user\_id, NOW(), NOW()

)

RETURNING id;

Store the returned id as band\_id.

Using band\_id — insert SP payout row into incentive\_range\_payouts:

INSERT INTO incentive\_range\_payouts (

  range\_band\_id, participant\_type,

  low\_payout, mid\_payout, high\_payout,

  created\_by, updated\_by, created\_at, updated\_at

) VALUES (

  :band\_id, 'SP',

  :sp\_low\_payout, :sp\_mid\_payout, :sp\_high\_payout,

  :user\_id, :user\_id, NOW(), NOW()

);

Using the same band\_id — insert SPV payout row into incentive\_range\_payouts:

INSERT INTO incentive\_range\_payouts (

  range\_band\_id, participant\_type,

  low\_payout, mid\_payout, high\_payout,

  created\_by, updated\_by, created\_at, updated\_at

) VALUES (

  :band\_id, 'SPV',

  :spv\_low\_payout, :spv\_mid\_payout, :spv\_high\_payout,

  :user\_id, :user\_id, NOW(), NOW()

);

Commit transaction.

15. On success → return HTTP 201:

| {  "status": "success",  "data": {    "config": {      "id": "\<uuid\>",      "schema\_id": "\<uuid\>",      "valid\_from": "2026-03-01T00:00:00Z",      "valid\_to": "2026-12-31T00:00:00Z",      "status": "active",      "created\_by": "\<uuid\>",      "created\_by\_name": "Budi Santoso",      "created\_at": "2026-04-17T00:00:00Z",      "updated\_by": null,      "updated\_by\_name": null,      "updated\_at": "2026-04-17T00:00:00Z",      "slabs": {        "STO": \[          {            "range\_band\_id": "\<uuid\>",            "range\_start": 2,            "range\_end": 5,            "tiers": {              "low":  { "threshold": 30, "sp\_payout": 12000, "spv\_payout": 20000 },              "mid":  { "threshold": 40, "sp\_payout": 45000, "spv\_payout": 65000 },              "high": { "threshold": 50, "sp\_payout": 90000, "spv\_payout": 110000 }            }          },          {            "range\_band\_id": "\<uuid\>",            "range\_start": 6,            "range\_end": null,            "tiers": {              "low":  { "threshold": 30, "sp\_payout": 90000, "spv\_payout": 110000 },              "mid":  { "threshold": 40, "sp\_payout": 90000, "spv\_payout": 110000 },              "high": { "threshold": 50, "sp\_payout": 90000, "spv\_payout": 110000 }            }          }        \],        "SMO": \[ ... \]      }    }  }} |
| :---- |

ws2-incentive-engine returns the response to ws-1. ws-1 validates the response structure and forwards it to Closio unchanged.

### 3.6 Error Reference

| HTTP Status | error\_code | Trigger |
| ----- | ----- | ----- |
| 400 | VALIDATION\_ERROR | schema\_id not a valid UUID, or valid\_from/valid\_to/slabs missing or malformed |
| 400 | MISSING\_HEADERS | One or more of X-Partner-Id, X-User-Id, X-User-Name absent |
| 400 | INVALID\_PERIOD | Period in the past, or valid\_to before valid\_from |
| 400 | INVALID\_SALESPERSON\_TYPE | A key in slabs is not one of STO, SFT, SMO |
| 400 | INVALID\_PAYLOAD | Band array for a salesperson type is empty |
| 400 | INVALID\_RANGE\_START | range\_start missing or not a positive integer |
| 400 | INVALID\_RANGE\_END | range\_end not a positive integer or null |
| 400 | INVALID\_RANGE\_ORDER | range\_end \<= range\_start |
| 400 | INVALID\_OPEN\_ENDED\_BAND | range\_end \= null on a non-last band |
| 400 | INVALID\_TIERS | tiers missing or low, mid, high keys absent |
| 400 | INVALID\_TIER\_VALUE | threshold, sp\_payout, or spv\_payout missing or not a positive number |
| 400 | INVALID\_THRESHOLD\_ORDER | Thresholds not in ascending order within a band |
| 400 | NON\_CONTIGUOUS\_RANGES | Gap or overlap between consecutive bands |
| 401 | TOKEN\_INVALID | Cookie invalid or expired at ws-1 |
| 401 | SIGNATURE\_INVALID | S2S auth failure at ws2-incentive-engine |
| 404 | NOT\_FOUND | Schema not found for schema\_id under the given partner |
| 409 | PERIOD\_OVERLAP | An existing config overlaps with the given valid\_from/valid\_to |
| 500 | INTERNAL\_ERROR | Transaction failed — no data written |

## 4\. PATCH Range Slabs API

### 4.1 Endpoint

PATCH /api/incentives/v1/schemas/:schema\_id/configs/:config\_id/range-slabs

### 4.2 Auth Headers

1. ws-1 will use cookies coming in the header to authenticate and retrieve the user details (in this API we need partner\_id, user\_id and user\_name).  
2. ws2-incentive-engine uses x-client-id and x-client-secret coming in the headers to authenticate.  
3. X-Partner-Id, X-User-Id and X-User-Name are passed down as request headers.

### 4.3 Path Parameters

| Parameter | Type | Required | Description |
| ----- | ----- | ----- | ----- |
| schema\_id | UUID | Yes | ID of the parent incentive schema |
| config\_id | UUID | Yes | ID of the config record being edited |

### 4.4 Request Payload

{

  "valid\_from": "2026-03",

  "valid\_to": "2026-12",

  "is\_config\_updated": true,

  "is\_slabs\_updated": true,

  "slabs": {

    "STO": \[

      {

        "range\_start": 2,

        "range\_end": 5,

        "tiers": {

          "low":  { "threshold": 30, "sp\_payout": 12000, "spv\_payout": 20000 },

          "mid":  { "threshold": 40, "sp\_payout": 45000, "spv\_payout": 65000 },

          "high": { "threshold": 50, "sp\_payout": 90000, "spv\_payout": 110000 }

        }

      },

      {

        "range\_start": 6,

        "range\_end": null,

        "tiers": {

          "low":  { "threshold": 30, "sp\_payout": 90000, "spv\_payout": 110000 },

          "mid":  { "threshold": 40, "sp\_payout": 90000, "spv\_payout": 110000 },

          "high": { "threshold": 50, "sp\_payout": 90000, "spv\_payout": 110000 }

        }

      }

    \],

    "SMO": \[ ... \]

  }

}

### 4.5 Workflow

1. Closio sends PATCH /api/incentives/v1/schemas/:schema\_id/configs/:config\_id/range-slabs to ws-1.  
2. ws-1 validates the cookie. If the cookie is invalid → ws-1 returns HTTP 401:  
   {  
     "status": "error",  
     "error\_code": "TOKEN\_INVALID",  
     "message": "User token invalid or expired"  
   }  
3. If cookie is valid → ws-1 retrieves authenticated user details (partner\_id, user\_id, user\_name).  
4. ws-1 validates path params are valid UUIDs. If not → return HTTP 400:  
   {  
     "status": "error",  
     "error\_code": "VALIDATION\_ERROR",  
     "message": "schema\_id and config\_id must be valid UUIDs"  
   }  
5. ws-1 validates presence and basic format of required request body fields:  
   1. is\_config\_updated and is\_slabs\_updated must be present and must be booleans.  
   2. At least one of is\_config\_updated or is\_slabs\_updated must be true.  
   3. If is\_config\_updated is true → valid\_from and valid\_to must be present and in YYYY-MM format.  
   4. If is\_slabs\_updated is true → slabs must be present and must be a non-empty object.  
   5. If any fail → return HTTP 400:  
      {  
        "status": "error",  
        "error\_code": "VALIDATION\_ERROR",  
        "message": "Request body validation failed",  
        "details": {  
          "missing\_or\_invalid": \["is\_config\_updated"\]  
        }  
      }  
6. ws-1 prepares a server-to-server request to ws2-incentive-engine:  
   1. Add headers: x-client-id, x-client-secret, X-Partner-Id, X-User-Id, X-User-Name  
   2. Pass schema\_id and config\_id in the path params.  
   3. Include the validated request body.  
7. ws2-incentive-engine applies S2S auth middleware. On any auth failure → return HTTP 401:  
   {  
     "status": "error",  
     "error\_code": "SIGNATURE\_INVALID",  
     "message": "Request signature invalid"  
   }  
8. ws2-incentive-engine validates required headers are present (X-Partner-Id, X-User-Id, X-User-Name). If any missing → return HTTP 400:  
   {  
     "status": "error",  
     "error\_code": "MISSING\_HEADERS",  
     "message": "Required headers are missing",  
     "details": {  
       "missing": \["X-User-Id"\]  
     }  
   }  
9. ws2-incentive-engine validates path params are valid UUIDs. If invalid → return HTTP 400:  
   {  
     "status": "error",  
     "error\_code": "VALIDATION\_ERROR",  
     "message": "schema\_id and config\_id must be valid UUIDs"  
   }  
10. ws2-incentive-engine verifies schema\_id exists in incentive\_schemas and is mapped to the partner\_id. If not found → return HTTP 404:  
    {  
      "status": "error",  
      "error\_code": "NOT\_FOUND",  
      "message": "Incentive schema not found for this partner"  
    }  
11. ws2-incentive-engine fetches the existing config record:

    SELECT \*

    FROM incentive\_schema\_configs

    WHERE id \= :config\_id

      AND schema\_id \= :schema\_id;

If not found → return HTTP 404:

{

  "status": "error",

  "error\_code": "NOT\_FOUND",

  "message": "Incentive schema config not found"

}

12. Store the retrieved config record. Determine the edit case based on the existing config periods:  
    1. **Case 1** — Both valid\_from and valid\_to are current month or future → full edit allowed. Both config and slabs are editable.  
    2. **Case 2** — valid\_from is a past period, valid\_to is current month or future → partial edit. Only valid\_to is editable. Slab rows are read-only.  
    3. **Case 3** — Both valid\_from and valid\_to are past → edit not permitted → return HTTP 400:  
       {  
         "status": "error",  
         "error\_code": "EDIT\_NOT\_PERMITTED",  
         "message": "This config cannot be edited as both valid\_from and valid\_to are in the past"  
       }  
13. If Case 2 and is\_slabs\_updated is true → return HTTP 400:  
    {  
      "status": "error",  
      "error\_code": "SLABS\_NOT\_EDITABLE",  
      "message": "Range bands cannot be edited for a config that has already started"  
    }  
14. If Case 2 and is\_config\_updated is true → validate that only valid\_to is being changed. If valid\_from in the request body differs from the existing valid\_from → return HTTP 400:  
    {  
      "status": "error",  
      "error\_code": "VALID\_FROM\_NOT\_EDITABLE",  
      "message": "valid\_from cannot be changed for a config that has already started"  
    }  
15. If is\_config\_updated is true — run version level validations:  
    1. Parse valid\_from to the first day of the month (e.g. 2026-03 → 2026-03-01) and valid\_to to the last day of that month.  
    2. valid\_to must be the current month or a future month. If past → return HTTP 400:  
       {  
         "status": "error",  
         "error\_code": "INVALID\_PERIOD",  
         "message": "valid\_to must be current month or a future period"  
       }  
    3. valid\_to must be greater than or equal to valid\_from. If not → return HTTP 400:  
       {  
         "status": "error",  
         "error\_code": "INVALID\_PERIOD",  
         "message": "valid\_to must be greater than or equal to valid\_from"  
       }  
    4. Check for period overlap with other existing configs for the same schema\_id and partner\_id, excluding the current config\_id:  
       SELECT id FROM incentive\_schema\_configs  
       WHERE schema\_id \= :schema\_id  
         AND id \!= :config\_id  
         AND valid\_from \<= :valid\_to

      AND valid\_to \>= :valid\_from;

If any record found → return HTTP 409:

{

  "status": "error",

  "error\_code": "PERIOD\_OVERLAP",

  "message": "The updated period overlaps with an existing config for this schema"

}

16. If is\_slabs\_updated is true — run slab level validations. All validations run upfront before any DB write. If any fail → return HTTP 400 immediately:

**Step 1 — Validate top-level slabs structure:**

- If any key in slabs is not one of STO, SFT, SMO → return HTTP 400:

  {

    "status": "error",

    "error\_code": "INVALID\_SALESPERSON\_TYPE",

    "message": "Invalid salesperson type: \<type\>. Must be one of STO, SFT, SMO"

  }

- If any salesperson type's band array is empty → return HTTP 400:

  {

    "status": "error",

    "error\_code": "INVALID\_PAYLOAD",

    "message": "slabs.\<salesperson\_type\> must contain at least one band"

  }

**Step 2 — Validate each band per salesperson type:**

Sort bands by range\_start ascending. For each band:

- If range\_start is missing or not a positive integer → return HTTP 400:

  {

    "status": "error",

    "error\_code": "INVALID\_RANGE\_START",

    "message": "range\_start must be a positive integer in slabs.\<salesperson\_type\>\[\<index\>\]"

  }

- If range\_end is not null and not a positive integer → return HTTP 400:

  {

    "status": "error",

    "error\_code": "INVALID\_RANGE\_END",

    "message": "range\_end must be a positive integer or null in slabs.\<salesperson\_type\>\[\<index\>\]"

  }

- If range\_end is not null and range\_end \<= range\_start → return HTTP 400:

  {

    "status": "error",

    "error\_code": "INVALID\_RANGE\_ORDER",

    "message": "range\_end must be greater than range\_start in slabs.\<salesperson\_type\>\[\<index\>\]"

  }

- If range\_end is null and this is not the last band (highest range\_start) → return HTTP 400:

  {

    "status": "error",

    "error\_code": "INVALID\_OPEN\_ENDED\_BAND",

    "message": "range\_end can only be null on the last band in slabs.\<salesperson\_type\>"

  }

- If tiers is missing or any of low, mid, high keys are absent → return HTTP 400:

  {

    "status": "error",

    "error\_code": "INVALID\_TIERS",

    "message": "tiers must contain low, mid, and high in slabs.\<salesperson\_type\>\[\<index\>\]"

  }

- For each tier (low, mid, high) — if threshold, sp\_payout, or spv\_payout is missing or not a positive number → return HTTP 400:

  {

    "status": "error",

    "error\_code": "INVALID\_TIER\_VALUE",

    "message": "threshold, sp\_payout, and spv\_payout must be positive numbers in slabs.\<salesperson\_type\>\[\<index\>\].tiers.\<tier\>"

  }

- If low.threshold \>= mid.threshold or mid.threshold \>= high.threshold → return HTTP 400:

  {

    "status": "error",

    "error\_code": "INVALID\_THRESHOLD\_ORDER",

    "message": "Thresholds must be in ascending order (low \< mid \< high) in slabs.\<salesperson\_type\>\[\<index\>\]"

  }

**Step 3 — Validate contiguity across bands within each salesperson type:**

For each consecutive pair of bands sorted by range\_start ascending — if band\_N.range\_end \+ 1 \!== band\_N+1.range\_start → return HTTP 400:

{

  "status": "error",

  "error\_code": "NON\_CONTIGUOUS\_RANGES",

  "message": "Range bands must be contiguous. Gap or overlap detected between range\_end \<range\_end\> and range\_start \<range\_start\> in slabs.\<salesperson\_type\>"

}

17. If all validations pass, begin a single DB transaction. If any operation inside fails → rollback the entire transaction and return HTTP 500:  
    {  
      "status": "error",  
      "error\_code": "INTERNAL\_ERROR",  
      "message": "Could not update range slabs. No data was written."  
    }  
18. Updation

**Step 1 — If is\_config\_updated is true → update incentive\_schema\_configs:**

UPDATE incentive\_schema\_configs

SET

  valid\_from        \= :valid\_from,

  valid\_to          \= :valid\_to,

  updated\_by        \= :user\_id,

  updated\_by\_name   \= :user\_name,

  updated\_at        \= NOW()

WHERE id \= :config\_id;

**Step 2 — If is\_slabs\_updated is true → mark existing active bands as deprecated:**

UPDATE incentive\_range\_bands

SET

  status      \= 'inactive',

  updated\_by  \= :user\_id,

  updated\_at  \= NOW()

WHERE schema\_config\_id \= :config\_id

  AND status \= 'active';

Note: incentive\_range\_payouts rows have no independent lifecycle — they are owned by their parent band. Deprecating the band is sufficient. Payout rows linked to inactive bands are never read by the calculation engine or GET API since both filter on status \= 'active' on the band.

**Step 3 — Insert new range bands and payout rows:**

For each salesperson\_type in slabs, for each band — insert into incentive\_range\_bands:

INSERT INTO incentive\_range\_bands (

  schema\_config\_id, salesperson\_type,

  range\_start, range\_end,

  low\_threshold, mid\_threshold, high\_threshold,

  status, created\_by, updated\_by, created\_at, updated\_at

) VALUES (

  :config\_id, :salesperson\_type,

  :range\_start, :range\_end,

  :low\_threshold, :mid\_threshold, :high\_threshold,

  'active', :user\_id, :user\_id, NOW(), NOW()

)

RETURNING id;

Using the returned band\_id — insert SP payout row:

INSERT INTO incentive\_range\_payouts (

  range\_band\_id, participant\_type,

  low\_payout, mid\_payout, high\_payout,

  created\_by, updated\_by, created\_at, updated\_at

) VALUES (

  :band\_id, 'SP',

  :sp\_low\_payout, :sp\_mid\_payout, :sp\_high\_payout,

  :user\_id, :user\_id, NOW(), NOW()

);

Using the same band\_id — insert SPV payout row:

INSERT INTO incentive\_range\_payouts (

  range\_band\_id, participant\_type,

  low\_payout, mid\_payout, high\_payout,

  created\_by, updated\_by, created\_at, updated\_at

) VALUES (

  :band\_id, 'SPV',

  :spv\_low\_payout, :spv\_mid\_payout, :spv\_high\_payout,

  :user\_id, :user\_id, NOW(), NOW()

);

**Commit transaction.**

19. On success → return HTTP 200:  
    {  
      "status": "success",  
      "data": {  
        "config": {  
          "id": "\<uuid\>",  
          "schema\_id": "\<uuid\>",  
          "valid\_from": "2026-03-01T00:00:00Z",  
          "valid\_to": "2026-12-31T00:00:00Z",  
          "status": "active",  
          "created\_by": "\<uuid\>",  
          "created\_by\_name": "Budi Santoso",  
          "created\_at": "2026-01-01T00:00:00Z",  
          "updated\_by": "\<uuid\>",  
          "updated\_by\_name": "Budi Santoso",  
          "updated\_at": "2026-04-17T00:00:00Z",  
          "slabs": {  
            "STO": \[  
              {  
                "range\_band\_id": "\<uuid\>",  
                "range\_start": 2,  
                "range\_end": 5,  
                "tiers": {  
                  "low":  { "threshold": 30, "sp\_payout": 12000, "spv\_payout": 20000 },  
                  "mid":  { "threshold": 40, "sp\_payout": 45000, "spv\_payout": 65000 },  
                  "high": { "threshold": 50, "sp\_payout": 90000, "spv\_payout": 110000 }  
                }  
              },  
              {  
                "range\_band\_id": "\<uuid\>",  
                "range\_start": 6,  
                "range\_end": null,  
                "tiers": {  
                  "low":  { "threshold": 30, "sp\_payout": 90000, "spv\_payout": 110000 },  
                  "mid":  { "threshold": 40, "sp\_payout": 90000, "spv\_payout": 110000 },  
                  "high": { "threshold": 50, "sp\_payout": 90000, "spv\_payout": 110000 }  
                }  
              }  
            \],  
            "SMO": \[ ... \]  
          }  
        }  
      }  
    }

ws2-incentive-engine returns the response to ws-1. ws-1 validates the response structure and forwards it to Closio unchanged.

### 4.6 Error Reference

| HTTP Status | error\_code | Trigger |
| ----- | ----- | ----- |
| 400 | VALIDATION\_ERROR | Path params not valid UUIDs, or required body fields missing or malformed |
| 400 | MISSING\_HEADERS | One or more of X-Partner-Id, X-User-Id, X-User-Name absent |
| 400 | EDIT\_NOT\_PERMITTED | Both valid\_from and valid\_to are in the past |
| 400 | SLABS\_NOT\_EDITABLE | is\_slabs\_updated \= true but config has already started (Case 2\) |
| 400 | VALID\_FROM\_NOT\_EDITABLE | valid\_from changed on a config that has already started |
| 400 | INVALID\_PERIOD | valid\_to in the past, or valid\_to before valid\_from |
| 400 | INVALID\_SALESPERSON\_TYPE | A key in slabs is not one of STO, SFT, SMO |
| 400 | INVALID\_PAYLOAD | Band array for a salesperson type is empty |
| 400 | INVALID\_RANGE\_START | range\_start missing or not a positive integer |
| 400 | INVALID\_RANGE\_END | range\_end not a positive integer or null |
| 400 | INVALID\_RANGE\_ORDER | range\_end \<= range\_start |
| 400 | INVALID\_OPEN\_ENDED\_BAND | range\_end \= null on a non-last band |
| 400 | INVALID\_TIERS | tiers missing or low, mid, high keys absent |
| 400 | INVALID\_TIER\_VALUE | threshold, sp\_payout, or spv\_payout missing or not a positive number |
| 400 | INVALID\_THRESHOLD\_ORDER | Thresholds not in ascending order within a band |
| 400 | NON\_CONTIGUOUS\_RANGES | Gap or overlap between consecutive bands |
| 401 | TOKEN\_INVALID | Cookie invalid or expired at ws-1 |
| 401 | SIGNATURE\_INVALID | S2S auth failure at ws2-incentive-engine |
| 404 | NOT\_FOUND | Schema or config not found |
| 409 | PERIOD\_OVERLAP | Updated period overlaps with an existing config for this schema |
| 500 | INTERNAL\_ERROR | Transaction failed — no data written |

## 5\. **External \- GET Salesperson–Product Mapping API**

This API will be created in ws2closio repository and not target incentive repository

#### **5.1 Endpoint**

GET /api/incentives/v1/salesperson-product-map

#### **5.2 Auth Headers**

* ws-1 will use cookies coming in the header to authenticate and retrieve the user details (in this API we only need partner\_id).  
* ws2closio uses x-client-id and x-client-secret coming in the headers to authenticate.  
* X-Partner-Id is passed down as a request header.

#### **5.3 Query Parameters**

| Parameter | Type | Required | Description |
| ----- | ----- | ----- | ----- |
| valid\_from | string (YYYY-MM) | Yes | Start of the month window to resolve mappings for. |
| valid\_to | string (YYYY-MM) | No | End of the window, inclusive. If omitted, defaults to valid\_from → resolves a single month. |
| salesperson\_type | string | No | Filter to one type (STO, SFT, SMO). Omit to return all types. |
| mapping\_type | string | No | Filter to one kind (PRODUCT, PRODUCT\_GROUP). Omit to return both. |
| status | string | No | active (default) or inactive. |

**Window semantics** — the API returns every mapping whose validity period **overlaps** \[valid\_from, valid\_to\]. Passing only valid\_from collapses the window to a single month, which is exactly the resolution the calculation engine needs ("the mapping in effect for month X"); passing a wide window serves the config/admin listing case. The two consumers share one endpoint.

#### **5.4 Workflow**

1. Closio sends GET /api/incentives/v1/salesperson-product-map to ws-1.  
2. ws-1 validates the cookie. If the cookie is invalid → ws-1 returns HTTP 401:

| {  "status": "error",  "error\_code": "TOKEN\_INVALID",  "message": "User token invalid or expired"} |
| :---- |

3. If cookie is valid → ws-1 retrieves authenticated user details (partner\_id).  
4. ws-1 validates the query parameters:  
   1. valid\_from must be present and in YYYY-MM format. If missing or malformed → return HTTP 400:

| {  "status": "error",  "error\_code": "INVALID\_VALID\_FROM",  "message": "valid\_from is required and must be in YYYY-MM format"} |
| :---- |

   2. If valid\_to is present and not in YYYY-MM format → return HTTP 400:

| {  "status": "error",  "error\_code": "INVALID\_VALID\_TO",  "message": "valid\_to must be in YYYY-MM format"} |
| :---- |

5. ws-1 prepares a server-to-server request to ws2closio:  
   Add headers: x-client-id, x-client-secret, X-Partner-Id. Forward the validated query parameters.  
6. ws2closio applies S2S auth middleware. On any auth failure → return HTTP 401:

| {  "status": "error",  "error\_code": "SIGNATURE\_INVALID",  "message": "Request signature invalid"} |
| :---- |

7. ws2closio validates X-Partner-Id header is present. If missing → return HTTP 400:

| {  "status": "error",  "error\_code": "PARTNER\_ID\_MISSING",  "message": "X-Partner-Id header is required"} |
| :---- |

8. ws2closio re-validates the query parameters (it never trusts upstream validation):  
   1. Parse valid\_from into the first day of its month (e.g. 2026-03 → 2026-03-01). If valid\_to is absent, set valid\_to \= valid\_from; otherwise parse it the same way. If valid\_to \< valid\_from → return HTTP 400:

| {  "status": "error",  "error\_code": "INVALID\_PERIOD",  "message": "valid\_to must be greater than or equal to valid\_from"} |
| :---- |

   2. If salesperson\_type is present and not one of STO, SFT, SMO → return HTTP 400:

| {  "status": "error",  "error\_code": "INVALID\_SALESPERSON\_TYPE",  "message": "Invalid salesperson type: \<type\>. Must be one of STO, SFT, SMO"} |
| :---- |

   3. If mapping\_type is present and not one of PRODUCT, PRODUCT\_GROUP → return HTTP 400:

| {  "status": "error",  "error\_code": "INVALID\_MAPPING\_TYPE",  "message": "Invalid mapping type: \<type\>. Must be one of PRODUCT, PRODUCT\_GROUP"} |
| :---- |

   4. If status is present and not one of active, inactive → return HTTP 400:

| {  "status": "error",  "error\_code": "INVALID\_STATUS",  "message": "Invalid status: \<status\>. Must be one of active, inactive"} |
| :---- |

9. ws2closio fetches all mappings for the partner whose period overlaps the window, in a single query (:status defaults to 'active'; :valid\_to defaults to :valid\_from when not supplied):

| SELECT  id                AS mapping\_id,  salesperson\_type,  mapping\_type,  valid\_from,  valid\_to,  external\_refs,  statusFROM salesperson\_product\_mapWHERE partner\_id \= :partner\_id  AND status     \= :status  AND valid\_from \<= :valid\_to  AND (valid\_to IS NULL OR valid\_to \>= :valid\_from)  AND (:salesperson\_type IS NULL OR salesperson\_type \= :salesperson\_type)  AND (:mapping\_type     IS NULL OR mapping\_type     \= :mapping\_type)ORDER BY salesperson\_type ASC, mapping\_type ASC, valid\_from ASC; |
| :---- |

10. If DB query fails → return HTTP 500:

| {  "status": "error",  "error\_code": "INTERNAL\_ERROR",  "message": "Could not fetch salesperson-product mappings"} |
| :---- |

11. If zero rows returned → return HTTP 200 with an empty object:

| {  "status": "success",  "data": {    "valid\_from": "2026-03-01T00:00:00Z",    "valid\_to": "2026-03-01T00:00:00Z",    "mappings": {}  }} |
| :---- |

12. ws2closio assembles the response in a single pass over the query result:  
    Initialise an empty mappings object. For each row — if mappings\[row.salesperson\_type\] does not exist, initialise it as an empty array; then push the mapping entry (mapping\_id, mapping\_type, valid\_from, valid\_to, external\_refs, status) onto it.  
13. Evaluate assembled result and return HTTP 200:

| {  "status": "success",  "data": {    "valid\_from": "2026-03-01T00:00:00Z",    "valid\_to": "2026-12-01T00:00:00Z",    "mappings": {      "STO": \[        {          "mapping\_id": "\<uuid\>",          "mapping\_type": "PRODUCT",          "valid\_from": "2026-03-01T00:00:00Z",          "valid\_to": "2026-12-01T00:00:00Z",          "external\_refs": \["prod\_101", "prod\_102", "prod\_103"\],          "status": "active"        },        {          "mapping\_id": "\<uuid\>",          "mapping\_type": "PRODUCT\_GROUP",          "valid\_from": "2026-03-01T00:00:00Z",          "valid\_to": null,          "external\_refs": \["grp\_1", "grp\_2"\],          "status": "active"        }      \],      "SMO": \[        {          "mapping\_id": "\<uuid\>",          "mapping\_type": "PRODUCT\_GROUP",          "valid\_from": "2026-03-01T00:00:00Z",          "valid\_to": null,          "external\_refs": \["grp\_5", "grp\_6", "grp\_7"\],          "status": "active"        }      \]    }  }} |
| :---- |

14. ws2closio returns the response to ws-1. ws-1 validates the response structure and forwards it to Closio unchanged.

#### **5.5 Error Reference**

| HTTP Status | error\_code | Trigger |
| ----- | ----- | ----- |
| 401 | TOKEN\_INVALID | Cookie invalid or expired (ws-1) |
| 400 | INVALID\_VALID\_FROM | valid\_from missing or not YYYY-MM |
| 400 | INVALID\_VALID\_TO | valid\_to present but not YYYY-MM |
| 401 | SIGNATURE\_INVALID | S2S auth failed (ws-2) |
| 400 | PARTNER\_ID\_MISSING | X-Partner-Id header absent |
| 400 | INVALID\_PERIOD | valid\_to \< valid\_from |
| 400 | INVALID\_SALESPERSON\_TYPE | salesperson\_type not in STO, SFT, SMO |
| 400 | INVALID\_MAPPING\_TYPE | mapping\_type not in PRODUCT, PRODUCT\_GROUP |
| 400 | INVALID\_STATUS | status not in active, inactive |
| 500 | INTERNAL\_ERROR | DB query failed |

# 

# 

# 

# **1\. JOT INCENTIVE CALCULATION OVERVIEW**

### **Queue Configuration**

The JOT incentive schemes use two dedicated BullMQ queues — one per scheme. Both queues follow the same job processing model as all other scheme queues in the Incentive Engine. Each queue receives exactly one job per calculation run, enqueued by the Calculation CRON (2nd) or Catch-up CRON (4th). SP and SPV are processed sequentially within the same job execution.

Both JOT jobs run in parallel with each other and with all other scheme jobs — they are fully isolated and do not block one another.

**Queue Definitions**

| Queue | Scheme | Purpose |
| ----- | ----- | ----- |
| jot-range-products-queue | JOT Range Products | Receives the JOT Range Products incentive calculation job. One job per run. Processes SP (SMO) and SPV sequentially within the same job execution. |
| jot-single-product-queue | JOT for Single Product | Receives the JOT for Single Product incentive calculation job. One job per run. Processes SP (STO, SFT) and SPV sequentially within the same job execution. |

Both queues feed into incentive-dlq on job exhaustion.  
Both jot-range-products-queue and jot-single-product-queue are processed by the **Scheme Calculation Worker** — the same single BullMQ worker subscribed to all 8 scheme queues. There is no dedicated JOT worker.

## **1.1 Shared Architecture**

| Dimension | JOT Range Products | JOT Single Product |
| :---- | :---- | :---- |
| Eligible SP Types | incentive\_schemas.applicable\_salesperson\_type — queried using schema\_id from job payload | Same |
| Metric per customer | Unique JOT product groups with net sales \> 0 | Unique individual products with net sales \> 0 |
| Snapshot column read | sales\_by\_jot\_group | sales\_by\_product |
| Slab structure | incentive\_range\_bands \+ incentive\_range\_payouts | Same |
| Carry-forward logic | Highest to lowest band, overflow carries down | Same |
| SPV payout model | Aggregated per SP type group — thresholds scaled by reportee count, carry-forward on aggregated counts  | Same |
| BullMQ queue | jot-range-products-queue | jot-single-product-queue |
| DB result tables | incentive\_results, jot\_incentive\_sp, jot\_incentive\_spv | Same |

# **2\. JOT Range Products — End-to-End Workflow**

## **2.1 Overview**

JOT Range Products incentive is calculated once at month end. Achievement \= count of customers per JOT product group range band that a salesperson has sold to, where each customer is classified into exactly one band based on the number of unique JOT product groups they bought from that salesperson with net sales \> 0\. Only product groups mapped to the salesperson's type are counted. Carry-forward logic applies — overflow from a higher band is added to the next lower band.

SPV incentive is calculated per salesperson type group. For each eligible SP type group under the supervisor, raw customer counts are aggregated across all reportees of that type per band, and the band thresholds are scaled by the number of reportees in the group. The scaled thresholds are then compared against the aggregated thresholds to determine the SPV's tier per band. Carry-forward logic applies on the aggregated counts. One jot\_incentive\_spv row is written per (SPV result, salesperson type, band) combination.

## **2.2 Data Sources**

| Data | Source |
| :---- | :---- |
| Customer product group sales per salesperson | salesperson\_metrics\_snapshot — sales\_by\_jot\_group column |
| Eligible salesperson types for this scheme | From applicable\_salesperson\_type column in incentive\_schemas table (schema\_id from job payload) |
| Supervisor to Salesperson mapping | supervisor\_salesperson\_type\_map — filter by partner\_id, status \= active, and the calculation period (valid\_from/valid\_to);read supervisor\_type and salesperson\_types |
| Valid JOT group IDs per salesperson type | GET /api/incentives/v1/salesperson-product-map — filter by mapping\_type \= PRODUCT\_GROUP and status \= active, read external\_refs |
| Range bands and tier thresholds | incentive\_range\_bands |
| SP and SPV payout amounts per band per tier | incentive\_range\_payouts |
| SP list | Redis → GET /users?level=1 |
| SPV list | Redis → GET /users?level=2 |
| SPV reportees | Redis → incentive:{partner\_id}:reportees → GET /users?upline\_id=\<spv\_id\> |

## **2.3 Job Payload**

The CRON enqueues this job into jot-range-products-queue:

| {   "run\_id":       "\<uuid\>",   "schema\_id":    "\<uuid\>",   "config\_id":    "\<uuid\>",   "partner\_id":   "\<uuid\>",   "month":        3,   "year":         2026,   "triggered\_by": "CALCULATION\_CRON" } |
| :---- |

*Note — triggered\_by reflects which CRON enqueued the job — CALCULATION\_CRON if enqueued on the 2nd, CATCHUP\_CRON if enqueued on the 4th. Workers do not behave differently based on this value — it is carried through to incentive\_run\_log for audit purposes only.*

## **2.4 CRON Gate Check — JOT-Specific Differences**

JOT Range Products participates in the standard CRON gate check loop but has the following deviations from other schemes:

1. **No Feed Gate Check**

   JOT Range Products does not depend on the Ageing or Activation Call feeds. The feed gate check does not apply and is not run for this scheme.

2. **Achievement Data Check — salesperson\_metrics\_snapshot**

   Unlike Call Plan, Weekly Revenue, Monthly Revenue, and Unique Transacting Customers which probe the achievements table via target\_type\_id, JOT Range Products sources its data from salesperson\_metrics\_snapshot:

| SELECT COUNT(\*) FROM salesperson\_metrics\_snapshot WHERE partner\_id \= :partner\_id   AND month      \= :month   AND year       \= :year; |
| :---- |

   If COUNT \= 0 — remove jot\_range\_products from schemes\_to\_process and send email alerts with ACHIEVEMENT\_MISSING.

3. **Settlement Check**

   Skips BullMQ queue depth check. Staleness heuristic is performed against salesperson\_metrics\_snapshot.updated\_at:

| SELECT MAX(updated\_at) AS last\_updated FROM salesperson\_metrics\_snapshot WHERE partner\_id \= :partner\_id   AND month      \= :month   AND year       \= :year; |
| :---- |

   If minutes\_since\_last\_write \< ACHIEVEMENT\_SETTLE\_THRESHOLD\_MINUTES — remove scheme from schemes\_to\_process and send email alert with ACHIEVEMENT\_NOT\_SETTLED.

   

4. **Slab Config Check — Band Rows Verified**

   In addition to the standard incentive\_schema\_configs check, the CRON also verifies that at least one active band row exists. The salesperson\_type filter is derived from incentive\_schemas.applicable\_salesperson\_type, queried using schema\_id before the band count check runs:

| First, fetch eligible SP types directly from the schema: SELECT applicable\_salesperson\_type FROM incentive\_schemas WHERE id \= :schema\_id; \-- store as eligible\_sp\_types Then run the band count check: SELECT COUNT(\*) FROM incentive\_range\_bands WHERE schema\_config\_id \= :config\_id   AND salesperson\_type \= ANY(:eligible\_sp\_types)  \-- from incentive\_schemas.applicable\_salesperson\_type   AND status           \= 'active'; |
| :---- |

If COUNT \= 0 — remove scheme from schemes\_to\_process, write SP\_SLAB\_MISSING to error log and send email alert.

## **2.5 Step-by-Step Calculation Workflow**

### **Step 1 — Update Run Log to Processing**

| UPDATE incentive\_run\_log SET status \= 'processing' WHERE run\_id    \= :run\_id   AND schema\_id \= :schema\_id; |
| :---- |

### **Step 2 — Lock salesperson\_metrics\_snapshot**

Lock all snapshot records for the calculation month to prevent the daily sales webhook from updating data that is now being used for incentive calculation:

| UPDATE salesperson\_metrics\_snapshot SET   is\_locked \= true,       locked\_at \= NOW() WHERE partner\_id \= :partner\_id   AND month      \= :month   AND year       \= :year   AND is\_locked  \= false; |
| :---- |

If this update fails → write DB\_WRITE\_FAILED and throw. BullMQ retries.

### **Step 3 — Retry Cleanup**

Runs at the start of every attempt. Safe on first attempt (nothing exists yet). On retry, marks all partial results from the previous failed attempt as deprecated:

| \-- Mark previous attempt errors as deprecated UPDATE incentive\_run\_errors SET is\_deprecated \= true WHERE run\_id    \= :run\_id   AND schema\_id \= :schema\_id; \-- Mark incentive\_results rows as deprecated UPDATE incentive\_results SET is\_deprecated \= true WHERE run\_id              \= :run\_id   AND incentive\_schema\_id \= :schema\_id; |
| :---- |

### **Step 4 — Fetch SP and SPV Data from Redis**

Check Redis for **incentive:{partner\_id}:salespersons**. If not found → call GET /users?level=1 with pagination, store in Redis with 2 hour TTL. If API fails → write SP\_FETCH\_FAILED and throw.

Check Redis for **incentive:{partner\_id}:supervisors**. If not found → call GET /users?level=2 with pagination, store in Redis with 2 hour TTL. If API fails → write SPV\_FETCH\_FAILED and throw.

Store both lists in memory:

| salespersonsList \= \[...\]  // full SP objects including id, name, type supervisorsList  \= \[...\]  // full SPV objects including id, name, type |
| :---- |

Check Redis for **incentive:{partner\_id}:reportees**. If found — verify all supervisor IDs are present as keys; fetch missing ones via **GET /users?upline\_id=\<supervisor.id\>** and merge. If not found — build a full map from scratch. Store with 2 hour TTL:

| reporteeMap \= {   "spv-uuid-1": \[{ id: "sp-uuid-1", name: "Andi", type: "SMO" }, ...\],   "spv-uuid-2": \[{ id: "sp-uuid-3", name: "Budi", type: "SMO" }, ...\] } |
| :---- |

If any upline\_id call fails → write REPORTEES\_FETCH\_FAILED and throw. If Redis write fails → write REDIS\_WRITE\_FAILED and throw. BullMQ retries.

### **Step 5 — Fetch Eligible SP Types from Schema and Filter SPs**

Before filtering, use the incentive\_schema table to determine eligible salesperson types for this scheme:

| SELECT applicable\_salesperson\_type FROM incentive\_schemas WHERE id \= :schema\_id AND partner\_id=:partner\_id;; \-- e.g. \["SMO"\] for jot\_range\_products |
| :---- |

Store result in memory and filter the SP list:

| // eligible\_sp\_types from DB query above // e.g. \["SMO"\] for JOT Range Products eligibleSPs \= salespersonsList.filter(sp \=\> eligible\_sp\_types.includes(sp.type)) eligible\_sp\_count \= eligibleSPs.length |
| :---- |

If DB query fails → write DB\_READ\_FAILED and throw. BullMQ retries.

### **Step 6 — Fetch JOT Group IDs from Salesperson Product Map API which contribute to this Incentive**

| GET /api/incentives/v1/salesperson-product-map Response: {    "status": "success",     "data": {     "mappings": {      "SMO": \[{ "mapping\_type": "PRODUCT\_GROUP", "status": "active",                "external\_refs": \["grp\_5", "grp\_6", "grp\_7"\] }\]    }  }} mappings \= apiResponse.data.mappings // For each eligible SP type, look up directly by type key // Filter by mapping\_type \= PRODUCT\_GROUP and status \= active // Guaranteed to return exactly one object after filtering validGroupMap \= {} for each spType in eligible\_sp\_types:   mapping \= mappings\[spType\]     .filter(m \=\> m.mapping\_type \=== "PRODUCT\_GROUP" && m.status \=== "active")\[0\]   validGroupMap\[spType\] \= mapping.external\_refs // e.g. { "SMO": \["grp\_5", "grp\_6", "grp\_7"\] }  |
| :---- |

If API fails → write SP\_FETCH\_FAILED with { reason: 'salesperson\_product\_map\_failed' } and throw. BullMQ retries.

### **Step 7  — Fetch Active Range Bands and Payouts**

Fetch all active range bands and their SP and SPV payout rows in a single query. The salesperson\_type filter uses eligible\_sp\_types from Step 5:

| SELECT   irb.id              AS range\_band\_id,   irb.salesperson\_type,   irb.range\_start,   irb.range\_end,   irb.low\_threshold,   irb.mid\_threshold,   irb.high\_threshold,   irp.participant\_type,   irp.low\_payout,   irp.mid\_payout,   irp.high\_payout FROM incentive\_range\_bands irb LEFT JOIN incentive\_range\_payouts irp   ON irp.range\_band\_id \= irb.id WHERE irb.schema\_config\_id \= :config\_id   AND irb.salesperson\_type \= ANY(:eligible\_sp\_types)  \-- from Step 5   AND irb.status           \= 'active' ORDER BY irb.salesperson\_type ASC, irb.range\_start ASC, irp.participant\_type ASC; |
| :---- |

Build bandMap in memory keyed by salesperson\_type, ordered by range\_start 

descending within each type (for carry-forward evaluation):

| bandMap \= {   "SMO": \[     {       range\_band\_id:  "band-uuid-3",       range\_start:    6,       range\_end:      null,       low\_threshold:  15,       mid\_threshold:  25,       high\_threshold: 35,       sp\_payout:  { low: 100000, mid: 150000, high: 170000 },       spv\_payout: { low:  60000, mid:  90000, high: 110000 }     },     { ... },     { ... }   \] } |
| :---- |

If the query returns zero rows → write SP\_SLAB\_MISSING with { schema\_id, month, year } and throw. BullMQ retries.

If DB query fails → write DB\_READ\_FAILED and throw. BullMQ retries.

### **Step 8 — Fetch salesperson\_metrics\_snapshot for Eligible SPs**

Using eligible\_sp\_types already resolved in Step 5, the column to read is determined as follows:

| // No API call needed here — response already held in memory from Step 5 // eligible\_sp\_types derived in Step 5 // column is fixed for this scheme: columnToRead \= "sales\_by\_jot\_group" // PRODUCT\_GROUP mapping\_type \-\> sales\_by\_jot\_group |
| :---- |

Fetch snapshot data for eligible SPs:

| SELECT   salesperson\_id,   sales\_by\_jot\_group    \-- PRODUCT\_GROUP mapping\_type → sales\_by\_jot\_group read in Step 5 FROM salesperson\_metrics\_snapshot WHERE partner\_id     \= :partner\_id   AND month          \= :month   AND year           \= :year   AND salesperson\_id \= ANY(:eligible\_sp\_ids); |
| :---- |

sales\_by\_jot\_group structure — keyed by customer\_id, then by jot\_group\_id, value is net sales:

| // sales\_by\_jot\_group for sp-uuid-1 {   "C1": { "JG-DRY": 150000, "JG-FEED": 320000, "JG-HEALTH": 85000 },   "C2": { "JG-DRY": 200000 },   "C3": { "JG-DRY": 0,      "JG-FEED": 0 },   "C4": { "JG-HEALTH": 95000, "JG-BREED": 45000, "JG-DRY": 70000, "JG-VIT": 30000 },   "C5": { "JG-DRY": 110000, "JG-FEED": 80000, "JG-HEALTH": 60000,           "JG-BREED": 40000, "JG-VIT": 55000, "JG-MISC": 25000 } } |
| :---- |

If DB query fails → write DB\_READ\_FAILED and throw. BullMQ retries.

## **Part A — SP Calculation**

### **Step 9 — Calculate Each Eligible SP (All in Memory)**

Initialize accumulators:

| spResults    \= \[\] spSchemeData \= \[\] spErrors     \= \[\] |
| :---- |

**Step 9.1 — Check Data Exists**

Look up SP in metricsMap using sp.id. If not found → push SP\_DATA\_MISSING with { name: sp.name, type: sp.type } to spErrors and continue to next SP.

**Step 9.2 — Classify Each Customer Into Exactly One Band**

From metricsMap\[sp.id\].sales\_by\_jot\_group, iterate over every customer. **Count the number of unique JOT group IDs where net\_sales \> 0 and that jot\_group\_id is present in validGroupMap**. Assign the customer to the highest matching band — no double counting:

| bandCustomerCounts \= {} for each band in bandMap\[sp.type\]: bandCustomerCounts\[band.range\_band\_id\] \= 0 for each customer\_id in sales\_by\_jot\_group:  qualifying\_count \= count of jot\_group\_ids where net\_sales \> 0 AND jot\_group\_id IN validGroupMap\[sp.type\] // validGroupMap from Step 6   // e.g. \["grp\_5", "grp\_6", "grp\_7"\] for SMO  if qualifying\_count \< bandMap\[sp.type\]\[lowest\].range\_start: continue  for each band in bandMap\[sp.type\] (highest range\_start first):     if range\_end IS NULL:       matches \= (qualifying\_count \>= band.range\_start)     else:       matches \= (qualifying\_count \>= band.range\_start                  AND qualifying\_count \<= band.range\_end)     if matches:       bandCustomerCounts\[band.range\_band\_id\] \+= 1       break  // exactly ONE band per customer |
| :---- |

**Example — Customer Classification**

SP-A sales\_by\_jot\_group:

| Customer | JOT Groups with Sales \> 0 | Count | Band |
| :---- | :---- | :---- | :---- |
| C1 | JG-DRY: 150000, JG-FEED: 320000, JG-HEALTH: 85000 | 3 | 2–3 |
| C2 | JG-DRY: 200000 | 1 | Below minimum — skip |
| C3 | JG-DRY: 0, JG-FEED: 0 | 0 | Skip |
| C4 | JG-HEALTH: 95000, JG-BREED: 45000, JG-DRY: 70000, JG-VIT: 30000 | 4 | 4–5 |
| C5 | JG-DRY: 110000, JG-FEED: 80000, JG-HEALTH: 60000, JG-BREED: 40000, JG-VIT: 55000, JG-MISC: 25000 | 6 | 6+ |
| C6 | JG-HEALTH: 95000, JG-BREED: 45000, JG-DRY: 70000, JG-VIT: 30000 | 4 | 4–5 |

**Step 9.3 — Apply Carry-Forward and Evaluate Tiers**

Process bands from highest range\_start to lowest. Overflow from a higher band carries into the next lower band:

| carry \= 0 spBandResults \= \[\] for each band in bandMap\[sp.type\] (highest range\_start first){   raw\_count      \= bandCustomerCounts\[band.range\_band\_id\]   adjusted\_count \= raw\_count \+ carry   carry\_in \= carry   if adjusted\_count \>= band.high\_threshold:     tier\_hit  \= "high"     payout    \= band.sp\_payout.high     carry\_out \= adjusted\_count \- band.high\_threshold     carry     \= carry\_out   else if adjusted\_count \>= band.mid\_threshold:     tier\_hit  \= "mid"     payout    \= band.sp\_payout.mid     carry\_out \= 0;  carry \= 0   else if adjusted\_count \>= band.low\_threshold:     tier\_hit  \= "low"     payout    \= band.sp\_payout.low     carry\_out \= 0;  carry \= 0   else:     tier\_hit \= 'not\_met'     payout \= 0     carry\_out \= 0 // no carry below the high threshold     carry \= 0   // Last band — carry\_out stored for audit, discarded from calculation   if this is the lowest band: carry \= 0   spBandResults.push({ range\_band\_id, range\_start, range\_end,     raw\_customer\_count, carry\_in, adjusted\_count,     carry\_out, tier\_hit, payout\_amount: payout })} total\_payout \= sum of payout\_amount across spBandResults |
| :---- |

**Example — Normal Flow**

SP actual counts: 6+ \= 20, 4–5 \= 55, 2–3 \= 90

| Band | Raw | Carry In | Adjusted | Threshold Check | Tier | Payout | Carry Out |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 6+ | 20 | 0 | 20 | 20 \>= 15 (Low), \< 25 (Mid) | low | Rp. 100,000 | 0 |
| 4–5 | 55 | 0 | 55 | 55 \>= 50 (Low), \< 60 (Mid) | low | Rp. 80,000 | 0 |
| 2–3 | 90 | 0 | 90 | 90 \< 100 (Low) | not\_met | Rp. 0 | 90 (discarded) |

Total payout \= Rp. 100,000 \+ Rp. 80,000 \+ Rp. 0 \= Rp. 180,000

**Example — Carry-Forward**

SP actual counts: 6+ \= 40, 4–5 \= 68, 2–3 \= 90

| Band | Raw | Carry In | Adjusted | Threshold Check | Tier | Payout | Carry Out |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 6+ | 40 | 0 | 40 | 40 \>= 35 (High) | high | Rp. 170,000 | 5 |
| 4–5 | 68 | 5 | 73 | 73 \>= 70 (High) | high | Rp. 150,000 | 3 |
| 2–3 | 90 | 3 | 93 | 93 \< 100 (Low) | not\_met | Rp. 0 | 93 (discarded) |

Total payout \= Rp. 170,000 \+ Rp. 150,000 \+ Rp. 0 \= Rp. 320,000

**Step 9.4 — Push to Accumulators**

| spResults.push({   salesperson\_id:    sp.id,   salesperson\_name:  sp.name,   sp\_type:           sp.type,   achievement\_value: null,     // always null for JOT    achievement\_pct:   null,           // always null for JOT — no percentage metric   payout\_amount:     total\_payout,   role:              "SP" }) spSchemeData.push({   salesperson\_id: sp.id,   band\_results:   spBandResults      // one entry per band for jot\_incentive\_sp }) |
| :---- |

### **Step 10 — Bulk Write SP Results (Single Transaction)**

Three inserts happen in a single DB transaction:

**Step 10.1 — Insert into incentive\_results**

| INSERT INTO incentive\_results (   run\_id, incentive\_schema\_id, partner\_id,   month, year, salesperson\_id, salesperson\_name,   sp\_type, achievement\_value, achievement\_pct,   payout\_amount, role, status, is\_deprecated ) VALUES ...  \-- one row per SP RETURNING id, salesperson\_id; spResultIdMap \= { salesperson\_id \-\> result\_id } |
| :---- |

**Step 10.2 — Insert into jot\_incentive\_sp**

The data comes from **spSchemeData** — the accumulator populated in Step 9.4 (Push to Accumulators).

Specifically:

* result\_id → from spResultIdMap\[sp.id\] returned by Step 10.1 RETURNING id, salesperson\_id  
* range\_band\_id, range\_start, range\_end, raw\_customer\_count, carry\_in, adjusted\_count, carry\_out, tier\_hit, payout\_amount → all from spSchemeData\[sp.id\].band\_results — the spBandResults array built in Step 9.3 for each band

So the insert loop looks like:

| for each sp in spResults:   result\_id \= spResultIdMap\[sp.salesperson\_id\]   band\_results \= spSchemeData                    .find(s \=\> s.salesperson\_id \=== sp.salesperson\_id)                    .band\_results   for each band in band\_results:     INSERT INTO jot\_incentive\_sp (       result\_id      \= result\_id,       range\_band\_id  \= band.range\_band\_id,       range\_start    \= band.range\_start,       range\_end      \= band.range\_end,       raw\_customer\_count \= band.raw\_customer\_count,       carry\_in       \= band.carry\_in,       adjusted\_count \= band.adjusted\_count,       carry\_out      \= band.carry\_out,       tier\_hit       \= band.tier\_hit,       payout\_amount  \= band.payout\_amount     ) |
| :---- |

Example rows written for SP-A (carry-forward example):

| result\_id | range\_band\_id | range\_start | range\_end | raw\_count | carry\_in | adjusted | carry\_out | tier\_hit | payout |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| ir-uuid-1 | band-uuid-3 | 6 | null | 40 | 0 | 40 | 5 | high | 170000 |
| ir-uuid-1 | band-uuid-2 | 4 | 5 | 68 | 5 | 73 | 3 | high | 150000 |
| ir-uuid-1 | band-uuid-1 | 2 | 3 | 90 | 3 | 93 | 93 (discard) | not\_met | 0 |

**Step 10.3 — Insert SP Errors into incentive\_run\_errors**

| INSERT INTO incentive\_run\_errors (   run\_id, schema\_id, error\_code, role,   entity\_id, payload, error\_message, attempt ) VALUES ...  \-- one row per entry in spErrors |
| :---- |

If transaction fails → rollback, write DB\_WRITE\_FAILED, throw. BullMQ retries.

## **Part B — SPV Calculation**

Runs immediately after SP write succeeds. Uses spResultIdMap and spSchemeData already held in memory — no additional fetch of SP results from DB needed.

### **Step 11 — Filter Eligible Supervisors** Before filtering, use the incentive\_schema table to determine eligible supervisor types for this scheme:

| SELECT applicable\_supervisor\_type FROM incentive\_schemas WHERE id \= :schema\_id AND partner\_id=:partner\_id;; \-- e.g. \["SMO"\] for jot\_range\_products |
| :---- |

Store result in memory and filter the SP list:

| eligibleSPVs \= supervisorsList.filter(sp \=\> eligible\_spv\_types.includes(spv.type)) eligible\_spv\_count \= eligibleSPVs.length |
| :---- |

If DB query fails → write DB\_READ\_FAILED and throw. BullMQ retries.

### **Step 12 — Calculate Each Supervisor (All in Memory)**

Initialize accumulators:

| spvResults    \= \[\] spvSchemeData \= \[\] spvErrors     \= \[\] |
| :---- |

For each supervisor, the calculation is done independently per eligible SP type group. Within each group, raw customer counts are aggregated across all reportees, thresholds are scaled by the reportee count, and 

carry-forward is applied on the aggregated counts against the scaled 

thresholds.

**Step 12.1 — Fetch Reportees and Filter by Eligible (which can contribute to this Incentive) SP Types**

Read reporteeMap\[supervisor.id\] from memory. If key is not found or empty → push SPV\_NO\_REPORTEES, set payout\_amount \= 0 and continue.

Before the supervisor loop, query supervisor\_salesperson\_type\_map once for the calculation period and build spvTypeMap in memory:

| SELECT supervisor\_type, salesperson\_typesFROM supervisor\_salesperson\_type\_mapWHERE partner\_id  \= :partner\_id  AND status      \= 'active'  AND valid\_from \<= :period\_start  AND (valid\_to IS NULL OR valid\_to \>= :period\_start);\-- :period\_start \= make\_date(:year, :month, 1\) |
| :---- |

// Build the lookup keyed by supervisor\_type

// e.g. { "SPV DRY": \["STO"\], "SPV MIX": \["STO","SMO"\], "SPV MO": \["SMO"\] }

| spvTypeMap \= {}for each row in result:  spvTypeMap\[row.supervisor\_type\] \= row.salesperson\_types |
| :---- |

If the query fails → write SPV\_TYPE\_MAP\_FETCH\_FAILED and throw. BullMQ retries.

BullMQ retries.Then inside the supervisor loop, intersect the supervisor’s overseen types with the scheme’s eligible types:

| // Step 1 — get SP types this supervisor oversees supervisedTypes \= spvTypeMap\[supervisor.type\] // e.g. SPV MIX → \["STO", "SMO"\] if supervisedTypes is empty or undefined:   push SPV\_TYPE\_UNRESOLVED, continue // Step 2 — intersect with scheme eligible types (from Step 5\) applicableTypes \= supervisedTypes.filter(t \=\> eligible\_sp\_types.includes(t)) // SPV DRY  → \["STO"\] ∩ \["SMO"\] \= \[\] → SPV\_NO\_REPORTEES // SPV MIX  → \["STO","SMO"\] ∩ \["SMO"\] \= \["SMO"\] // SPV SMO  → \["SMO"\] ∩ \["SMO"\] \= \["SMO"\] if applicableTypes.length \=== 0:   push SPV\_NO\_REPORTEES, payout \= 0, continue // Step 3 — filter reportees to applicable types reportees \= reporteeMap\[supervisor.id\]               .filter(r \=\> applicableTypes.includes(r.type)) if reportees.length \=== 0:   push SPV\_NO\_REPORTEES, payout \= 0, continue |
| :---- |

*Note — A supervisor whose type maps to zero eligible reportees (e.g. SPV Dry in JOT Range Products which has only STO reportees, not SMO) will hit SPV\_NO\_REPORTEES. This is an expected valid state — not an error.*

| // Group applicable reportees by SP type // reportee\_count per type is needed for threshold scaling in Step 12.3 spTypeGroups \= {} for each reportee in reportees:   if spTypeGroups\[reportee.type\] is undefined:     spTypeGroups\[reportee.type\] \= \[\]   spTypeGroups\[reportee.type\].push(reportee) // e.g. { "SMO": \[SP1, SP2\], "SDO": \[SP3, SP4, SP5\] } // store in memory for Step 12.3 |
| :---- |

**Step 12.2 — Resolve SPV Type**

Read supervisor.type from the supervisor object (e.g. SPV DRY, SPV MIX, SPV MO, SPV FTO). If type is missing or unrecognized → push SPV\_TYPE\_UNRESOLVED with { name: supervisor.name } and continue.

*Note — The supervisor type is not used for payout lookup in JOT — unlike other schemes. It is stored in incentive\_results.sp\_type for reporting only.*

**Step 12.3 — Compute SPV Payout Per Reportee Per Band**

For each eligible SP type group under this supervisor, aggregate raw customer counts per band across all reportees of that type, scale the band thresholds by the reportee count, apply carry-forward on the aggregated counts against the scaled thresholds, and derive the SPV tier per band.

| spv\_total\_payout \= 0 spvBandResults   \= \[\]   // one entry per (sp\_type, band) for jot\_incentive\_spv for each spType in Object.keys(spTypeGroups):   reporteesOfType \= spTypeGroups\[spType\]   reportee\_count  \= reporteesOfType.length   // Step 1 — aggregate raw customer counts per band across all reportees of this type   aggregatedCounts \= {}   for each band in bandMap\[spType\]:     aggregatedCounts\[band.range\_band\_id\] \= 0   for each reportee in reporteesOfType:     if reportee not in spSchemeData: continue     // SP calculation failed — exclude from aggregation     for each band in spSchemeData\[reportee.id\].band\_results:       aggregatedCounts\[band.range\_band\_id\] \+= band.raw\_customer\_count   // Step 2 — apply carry-forward on aggregated counts   // against thresholds scaled by reportee\_count   carry \= 0   for each band in bandMap\[spType\] (highest range\_start first):     raw\_aggregated \= aggregatedCounts\[band.range\_band\_id\]     carry\_in       \= carry     adjusted       \= raw\_aggregated \+ carry     scaled\_low  \= band.low\_threshold  \* reportee\_count     scaled\_mid  \= band.mid\_threshold  \* reportee\_count     scaled\_high \= band.high\_threshold \* reportee\_count     if adjusted \>= scaled\_high:       tier\_hit      \= 'high'       payout        \= band.spv\_payout.high       carry\_out     \= adjusted \- scaled\_high       carry         \= carry\_out     else if adjusted \>= scaled\_mid:       tier\_hit      \= 'mid'       payout        \= band.spv\_payout.mid       carry\_out     \= 0       carry         \= 0     else if adjusted \>= scaled\_low:       tier\_hit      \= 'low'       payout        \= band.spv\_payout.low       carry\_out     \= 0       carry         \= 0   else:     tier\_hit \= 'not\_met'     payout \= 0     carry\_out \= 0 // no carry below the high threshold     carry \= 0     // last band — discard remaining carry     if this is the lowest band: carry \= 0     spv\_total\_payout \+= payout     spvBandResults.push({       salesperson\_type: spType,       range\_band\_id:    band.range\_band\_id,       reportee\_count:   reportee\_count,       aggregated\_count: raw\_aggregated,       carry\_in:         carry\_in,       carry\_out:        carry\_out,       tier\_hit:         tier\_hit,       payout\_amount:    payout     }) |
| :---- |

**Example — Supervisor Manas (SPV MIX) with 2 SMO reportees**

SP1: 6+=80, 4-5=60, 2-3=95  
SP2: 6+=75, 4-5=55, 2-3=100

Base SMO thresholds from bandMap:   
6+ Low=30 Mid=40 High=70   
4-5 Low=50 Mid=60 High=80    
2-3 Low=100 Mid=120 High=150.

Aggregated Count: 6+=155, 4-5=115, 2-3=195)

Scaled thresholds (× 2 \- because 2 salesperson of this type are there):   
6+ Low=60 Mid=80 High=140  
4-5 Low=100 Mid=120 High=160  
2-3 Low=200 Mid=240 High=300

| Band | Aggregated | Carry In | Adjusted | Scaled Thresholds | Tier | Payout | Carry Out |
| ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- |
| 6+ | 155 | 0 | 155 | Low=60 Mid=80 High=140 | high | Rp. 110,000 | 15 |
| 4-5 | 115 | 15 | 130 | Low=100 Mid=120 High=160 | mid | Rp. 90,000 | 0 |
| 2-3 | 195 | 0 | 195 | Low=200 Mid=240 High=300 | not\_met | Rp. 0 | 0 |

Total \= **Rp. 200,000**.   
This one earns its place: the 6+ overflow (15 above scaled high 140\) carries into 4-5 and bumps it from low (115 ≥ 100\) up to mid (130 ≥ 120\) — the carry visibly changes a tier, against scaled thresholds.

**Step 12.4 — Push to Accumulators**

| spvResults.push({   salesperson\_id:    supervisor.id,   salesperson\_name:  supervisor.name,   sp\_type:           supervisor.type,   // stored for reporting   achievement\_value: spv\_total\_payout,   achievement\_pct:   null,              // always null for JOT   payout\_amount:     spv\_total\_payout,   role:              "SPV" }) spvSchemeData.push({   salesperson\_id: supervisor.id,   band\_results:   spvBandResults   // one entry per (sp\_type, band) for jot\_incentive\_spv }) |
| :---- |

### **Step 13 — Bulk Write SPV Results (Single Transaction)**

**Step 13.1 — Insert into incentive\_results**

| INSERT INTO incentive\_results (   run\_id, incentive\_schema\_id, partner\_id,   month, year, salesperson\_id, salesperson\_name,   sp\_type, achievement\_value, achievement\_pct,   payout\_amount, role, status, is\_deprecated ) VALUES ...  \-- one row per SPV RETURNING id, salesperson\_id; spvResultIdMap \= { salesperson\_id \-\> result\_id } |
| :---- |

**Step 13.2 — Insert into jot\_incentive\_spv**

One row per (SPV result, salesperson type, band) combination:

| // Data sourced from spvSchemeData\[spv.id\].band\_results // and spvResultIdMap for each spv in spvResults:   result\_id    \= spvResultIdMap\[spv.salesperson\_id\]   band\_results \= spvSchemeData                    .find(s \=\> s.salesperson\_id \=== spv.salesperson\_id)                    .band\_results   for each band in band\_results:     INSERT INTO jot\_incentive\_spv (       result\_id        \= result\_id,       salesperson\_type \= band.salesperson\_type,       range\_band\_id    \= band.range\_band\_id,       reportee\_count   \= band.reportee\_count,       aggregated\_count \= band.aggregated\_count,       carry\_in         \= band.carry\_in,       carry\_out        \= band.carry\_out,       tier\_hit         \= band.tier\_hit,       payout\_amount    \= band.payout\_amount     ) |
| :---- |

Example rows for SMO type salesperson:

| result\_id | sp\_type | range\_band\_id | reportee\_count | aggregated\_count | carry\_in | carry\_out | tier\_hit | payout\_amount |
| ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- |
| spv-result-uuid-1 | SMO | band-smo-uuid-3 (6+) | 2 | 155 | 0 | 15 | high | 110000 |
| spv-result-uuid-1 | SMO | band-smo-uuid-2 (4-5) | 2 | 115 | 15 | 0 | mid | 90000 |
| spv-result-uuid-1 | SMO | band-smo-uuid-1 (2-3) | 2 | 195 | 0 | 0 | not\_met | 0 |

**Step 13.3 — Insert SPV Errors into incentive\_run\_errors**

| INSERT INTO incentive\_run\_errors (   run\_id, schema\_id, error\_code, role,   entity\_id, payload, error\_message, attempt ) VALUES ...  \-- one row per entry in spvErrors |
| :---- |

If transaction fails → rollback, write DB\_WRITE\_FAILED, throw. BullMQ retries.

### **Step 14 — Update Run Log**

| UPDATE incentive\_run\_log SET   status       \= CASE WHEN (spErrors\_count \+ spvErrors\_count) \> 0                       THEN 'partial' ELSE 'success' END,   total        \= :eligible\_sp\_count \+ :eligible\_spv\_count,   processed    \= :spResults\_count \+ :spvResults\_count,   failed       \= :spErrors\_count \+ :spvErrors\_count,   completed\_at \= NOW() WHERE run\_id \= :run\_id; |
| :---- |

No Redis cleanup is performed. Keys expire automatically via the 2 hour TTL.

## **2.6 Retry and Failure Handling**

| Failure | Retryable | Behaviour |
| :---- | :---- | :---- |
| DB bulk write failed | Yes | Rollback, write DB\_WRITE\_FAILED, throw, retry up to 3x |
| DB read failed (metrics snapshot, range bands) | Yes | Write DB\_READ\_FAILED, throw, retry up to 3x |
| SP/SPV fetch API failed | Yes | Write SP\_FETCH\_FAILED / SPV\_FETCH\_FAILED, throw, retry up to 3x |
| salesperson-product-map API failed  | Yes | Write SP\_FETCH\_FAILED with { reason: 'salesperson\_product\_map\_failed' }, throw, retry up to 3x |
| supervisor\_salesperson\_type\_map table query failed | Yes | SPV\_TYPE\_MAP\_FETCH\_FAILED, throw, retry up to 3x |
| Reportees API failed for a supervisor | No | Push REPORTEES\_FETCH\_FAILED, skip that supervisor, job continues |
| SP data missing in metrics snapshot | No | Push SP\_DATA\_MISSING, skip that SP, job continues |
| No active range bands for config | Yes | Write SPV/SP\_SLAB\_MISSING, throw, retry up to 3x |
| SPV type unresolved | No | Push SPV\_TYPE\_UNRESOLVED, skip that supervisor, job continues |
| SPV has zero eligible reportees | No | Push SPV\_NO\_REPORTEES, set payout \= 0, job continues |
| Job exhausts 3 retries | Final | DLQ — incentive-dlq |

Retry backoff: exponential — 5s → 25s → 125s.

## **2.7 Error Reference**

| Error Code | Role | Payload | When |
| :---- | :---- | :---- | :---- |
| SP\_FETCH\_FAILED | SYSTEM | {} or { reason: '...' } | GET /users?level=1 failed, or GET /api/incentives/v1/salesperson-product-map failed |
| SPV\_FETCH\_FAILED | SYSTEM | {} | GET /users?level=2 failed |
| SPV\_TYPE\_MAP\_FETCH\_FAILED | SYSTEM | {} | supervisor\_salesperson\_type\_map table query failed |
| REPORTEES\_FETCH\_FAILED | SYSTEM | {} | One or more GET /users?upline\_id calls failed |
| REDIS\_WRITE\_FAILED | SYSTEM | {} | Failed to write SP/SPV/reportee data to Redis |
| DB\_READ\_FAILED | SYSTEM | {} or { reason: '...' } | salesperson\_metrics\_snapshot or incentive\_range\_bands query failed |
| DB\_WRITE\_FAILED | SYSTEM | {} | Bulk insert transaction failed |
| SPV/SP\_SLAB\_MISSING | SYSTEM | { schema\_id, month, year } | No active range band rows found for this config and period |
| MAX\_RETRIES\_EXHAUSTED | SYSTEM | {} | Job exhausted all 3 retry attempts and moved to DLQ |
| SP\_DATA\_MISSING | SP | { name, type } | No salesperson\_metrics\_snapshot row found for this SP |
| SPV\_TYPE\_UNRESOLVED | SPV | { name } | Supervisor type missing or unrecognized |
| SPV\_NO\_REPORTEES | SPV | { name, type } | Supervisor has zero eligible reportees — payout set to 0 |

# **3\.  JOT for Single Product — End-to-End Workflow**

## **3.1 Overview**

JOT for Single Product incentive is calculated once at month end. Achievement \= count of customers per distinct product count range band that a salesperson has sold to, where each customer is classified into exactly one band based on the number of unique **individual products** (not product groups) they bought from that salesperson with net sales \> 0\. Only products mapped to the salesperson's type are counted.

The distinction from JOT Range Products is solely in three areas — the eligible salesperson types (STO and SFT instead of SMO), the snapshot column read (sales\_by\_product instead of sales\_by\_jot\_group), and the band config structure (separate configs per SP type instead of one). All carry-forward logic, SPV payout model, DB tables, retry handling, and BullMQ infrastructure are identical to JOT Range Products.

## **3.2 Data Sources**

| Data | Source |
| :---- | :---- |
| Customer product sales per salesperson | salesperson\_metrics\_snapshot — sales\_by\_product column |
| Eligible salesperson types for this scheme | From applicable\_salesperson\_type column in incentive\_schemas table (schema\_id from job payload) |
| Supervisor to Salesperson mapping | supervisor\_salesperson\_type\_map — filter by partner\_id, status \= active, and the calculation period (valid\_from/valid\_to); read supervisor\_type and salesperson\_types |
| Valid product IDs per salesperson type | GET /api/incentives/v1/salesperson-product-map — filter by mapping\_type \= PRODUCT and status \= active, read external\_refs |
| Range bands and tier thresholds | incentive\_range\_bands |
| SP and SPV payout amounts per band per tier | incentive\_range\_payouts |
| SP list | Redis → GET /users?level=1 |
| SPV list | Redis → GET /users?level=2 |
| SPV reportees | Redis → incentive:{partner\_id}:reportees → GET /users?upline\_id=\<spv\_id\> |

## **3.3 Job Payload**

The CRON enqueues this job into jot-single-product-queue. Payload structure is identical to JOT Range Products — see Section 2.3. Only triggered\_by and the queue name differ.

## **3.4 CRON Gate Check — JOT-Specific Differences**

All gate check logic is identical to JOT Range Products — Section 2.4 — with one difference in the slab config band check: eligible\_sp\_types here resolves to \["STO", "SFT"\] from incentive\_schemas.applicable\_salesperson\_type, so the band count query filters to STO and SFT bands instead of SMO.

## **3.5 Step-by-Step Calculation Workflow**

### **Step 1 — Update Run Log to Processing** Identical to JOT Range Products — Section 2.5 Step 1\.  **Step 2 — Lock salesperson\_metrics\_snapshot** Identical to JOT Range Products — Section 2.5 Step 2\. 

### **Step 3 — Retry Cleanup** Identical to JOT Range Products — Section 2.5 Step 3\.

### **Step 4 — Fetch SP and SPV Data from Redis**

Identical to JOT Range Products — Section 2.5 Step 4\.

### **Step 5 — Fetch Eligible SP Types from Schema and Filter SPs**

Before filtering, use the incentive\_schema table to determine eligible salesperson types for this scheme:

| SELECT applicable\_salesperson\_type FROM incentive\_schemas WHERE id \= :schema\_id   AND partner\_id \= :partner\_id; \-- Example Return: \["STO", "SFT"\] |
| :---- |

Store result in memory and filter the SP list:

| // eligible\_sp\_types from DB query above // e.g. \["STO", "SFT"\] for jot\_single\_product eligibleSPs \= salespersonsList.filter(sp \=\> eligible\_sp\_types.includes(sp.type)) eligible\_sp\_count \= eligibleSPs.length |
| :---- |

If DB query fails → write DB\_READ\_FAILED and throw. BullMQ retries.

### **Step 6 — Fetch Valid Product IDs from Salesperson Product Map API which contribute to this Incentive**

| GET /api/incentives/v1/salesperson-product-map // Response: { //   "status": "success", //   "data": { //     "mappings": { //       "STO": \[{ "mapping\_type": "PRODUCT", "status": "active", //                 "external\_refs": \["prod\_101", "prod\_102", "prod\_103"\] }\], //       "SFT": \[{ "mapping\_type": "PRODUCT", "status": "active", //                 "external\_refs": \["prod\_201", "prod\_202"\] }\] //     } //   } // } mappings \= apiResponse.data.mappings // For each eligible SP type, look up directly by type key // Filter by mapping\_type \= PRODUCT and status \= active // Guaranteed to return exactly one object after filtering validProductMap \= {} for each spType in eligible\_sp\_types:   mapping \= mappings\[spType\]     .filter(m \=\> m.mapping\_type \=== "PRODUCT" && m.status \=== "active")\[0\]   validProductMap\[spType\] \= mapping.external\_refs // e.g. { "STO": \["prod\_101", "prod\_102", "prod\_103"\], "SFT": \["prod\_201", "prod\_202"\] } |
| :---- |

If API fails → write SP\_FETCH\_FAILED with { reason: 'salesperson\_product\_map\_failed' } and throw. BullMQ retries.

### **Step 7  — Fetch Active Range Bands and Payouts**

Identical to JOT Range products \- Section 2.5 Step 7

| SELECT   irb.id              AS range\_band\_id,   irb.salesperson\_type,   irb.range\_start,   irb.range\_end,   irb.low\_threshold,   irb.mid\_threshold,   irb.high\_threshold,   irp.participant\_type,   irp.low\_payout,   irp.mid\_payout,   irp.high\_payout FROM incentive\_range\_bands irb LEFT JOIN incentive\_range\_payouts irp   ON irp.range\_band\_id \= irb.id WHERE irb.schema\_config\_id \= :config\_id   AND irb.salesperson\_type \= ANY(:eligible\_sp\_types)  \-- from Step 5   AND irb.status           \= 'active' ORDER BY irb.salesperson\_type ASC, irb.range\_start ASC, irp.participant\_type ASC; |
| :---- |

Build bandMap in memory keyed by salesperson\_type, ordered by range\_start descending within each type:

| Example : bandMap \= {   "STO": \[     { range\_band\_id: "band-sto-uuid-3", range\_start: 6, range\_end: null,       low\_threshold: 15, mid\_threshold: 25, high\_threshold: 35,       sp\_payout: { low: 100000, mid: 150000, high: 170000 },       spv\_payout:{ low:  60000, mid:  90000, high: 110000 } },     { range\_band\_id: "band-sto-uuid-2", range\_start: 4, range\_end: 5, ... },     { range\_band\_id: "band-sto-uuid-1", range\_start: 2, range\_end: 3, ... }   \],   "SFT": \[     { range\_band\_id: "band-sft-uuid-3", range\_start: 6, range\_end: null, ... },     { range\_band\_id: "band-sft-uuid-2", range\_start: 4, range\_end: 5, ... },     { range\_band\_id: "band-sft-uuid-1", range\_start: 2, range\_end: 3, ... }   \] } |
| :---- |

If zero rows returned for any type in eligible\_sp\_types → write SP\_SLAB\_MISSING with { schema\_id, salesperson\_type, month, year } for the missing type. SPs of that type are skipped — job continues for the other type.

If DB query fails → write DB\_READ\_FAILED and throw. BullMQ retries.

### **Step 8 — Fetch salesperson\_metrics\_snapshot for Eligible SPs**

| // No API call needed here — eligible\_sp\_types already resolved in Step 5 // JOT Single Product always reads sales\_by\_product // PRODUCT mapping\_type \-\> sales\_by\_product columnToRead \= "sales\_by\_product" |
| :---- |

Fetch snapshot data for eligible SPs:

| SELECT   salesperson\_id,   sales\_by\_product    \-- PRODUCT mapping\_type → sales\_by\_product FROM salesperson\_metrics\_snapshot WHERE partner\_id     \= :partner\_id   AND month          \= :month   AND year           \= :year   AND salesperson\_id \= ANY(:eligible\_sp\_ids); |
| :---- |

sales\_by\_product structure — keyed by customer\_id, then by product\_id, value is net sales:

| // sales\_by\_product for sp-uuid-1 (STO) {   "C1": { "P-001": 150000, "P-002": 320000, "P-003": 85000 },   "C2": { "P-001": 200000 },   "C3": { "P-001": 0,      "P-002": 0 },   "C4": { "P-001": 95000, "P-004": 45000, "P-005": 70000, "P-006": 30000 },   "C5": { "P-001": 110000, "P-002": 80000, "P-003": 60000,           "P-004":  40000, "P-005":  55000, "P-006": 25000 } } |
| :---- |

If DB query fails → write DB\_READ\_FAILED and throw. BullMQ retries.

## **Part A — SP Calculation**

### **Step 9 — Calculate Each Eligible SP (All in Memory)**

Initialize accumulators — identical to JOT Range Products — Section 2.5 Step 9\.

**Step 9.1 — Check Data Exists**

Identical to JOT Range Products — Section 2.5 Step 9.1.

**Step 9.2 — Classify Each Customer Into Exactly One Band**

From metricsMap\[sp.id\].sales\_by\_product, iterate over every customer. Count the number of unique product IDs where net\_sales \> 0 and that product\_id is present in validProductMap\[sp.type\]. Assign the customer to the highest matching band using bandMap\[sp.type\] — no double counting:

| bandCustomerCounts \= {} for each band in bandMap\[sp.type\]: bandCustomerCounts\[band.range\_band\_id\] \= 0 for each customer\_id in sales\_by\_product: qualifying\_count \= count of product\_ids where net\_sales \> 0 AND product\_id IN validProductMap\[sp.type\] // validProductMap from Step 6 // e.g. \["prod\_101", "prod\_102", "prod\_103"\] for STO  if qualifying\_count \< bandMap\[sp.type\]\[lowest\].range\_start: continue  for each band in bandMap\[sp.type\] (highest range\_start first):     if range\_end IS NULL:       matches \= (qualifying\_count \>= band.range\_start)     else:       matches \= (qualifying\_count \>= band.range\_start                  AND qualifying\_count \<= band.range\_end)     if matches:       bandCustomerCounts\[band.range\_band\_id\] \+= 1       break  // exactly ONE band per customer |
| :---- |

**Example — STO Customer Classification:**

| Customer | Products with Sales \> 0 | Count | Band |
| :---- | :---- | :---- | :---- |
| C1 | P-001: 150000, P-002: 320000, P-003: 85000 | 3 | 2–3 |
| C2 | P-001: 200000 | 1 | Below minimum — skip |
| C3 | P-001: 0, P-002: 0 | 0 | Skip |
| C4 | P-001: 95000, P-004: 45000, P-005: 70000, P-006: 30000 | 4 | 4–5 |
| C5 | P-001: 110000, P-002: 80000, P-003: 60000, P-004: 40000, P-005: 55000, P-006: 25000 | 6 | 6+ |

**Step 9.3 — Apply Carry-Forward and Evaluate Tiers**

Carry-forward logic is identical to JOT Range Products — Section 2.5 Step 9.3. Each SP uses bandMap\[sp.type\] — STO uses STO bands, SFT uses SFT bands independently.

Example — Normal Flow (STO): counts 6+ \= 20, 4–5 \= 55, 2–3 \= 90

| Band | Raw | Carry In | Adjusted | Threshold Check | Tier | Payout | Carry Out |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 6+ | 20 | 0 | 20 | 20 \>= 15 (Low), \< 25 (Mid) | low | Rp. 100,000 | 0 |
| 4–5 | 55 | 0 | 55 | 55 \>= 50 (Low), \< 60 (Mid) | low | Rp. 80,000 | 0 |
| 2–3 | 90 | 0 | 90 | 90 \< 100 (Low) | not\_met | Rp. 0 | 90 (discarded) |

Total payout \= Rp. 100,000 \+ Rp. 80,000 \+ Rp. 0 \= Rp. 180,000

Example — Normal Flow (SFT): counts 6+ \= 12, 4–5 \= 50, 2–3 \= 85 (SFT has different band thresholds)

| Band | Raw | Carry In | Adjusted | Threshold Check (SFT) | Tier | Payout | Carry Out |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| 6+ | 12 | 0 | 12 | 12 \>= 10 (Low), \< 20 (Mid) | low | Rp. 90,000 | 0 |
| 4–5 | 50 | 0 | 50 | 50 \>= 40 (Low), \< 55 (Mid) | low | Rp. 70,000 | 0 |
| 2–3 | 85 | 0 | 85 | 85 \>= 80 (Low), \< 95 (Mid) | low | Rp. 50,000 | 0 |

Total payout \= Rp. 90,000 \+ Rp. 70,000 \+ Rp. 50,000 \= Rp. 210,000

*Note — STO and SFT are evaluated independently using their own band configs — they never share or mix band thresholds.*

**Step 9.4 — Push to Accumulators**

Identical to JOT Range Products — Section 2.5 Step 9.4. sp\_type stores "STO" or "SFT".

**Step 10 — Bulk Write SP Results (Single Transaction)**

Three inserts happen in a single DB transaction:

**Step 10.1 — Insert into incentive\_results**

Identical to JOT Range Products — Section 2.5 Step 10.1.

**Step 10.2 — Insert into jot\_incentive\_sp**

One row per band per SP. STO and SFT rows reference different range\_band\_id values since their band configurations are stored separately in incentive\_range\_bands. Insert statement identical to JOT Range Products — Section 2.5 Step 10.2. Data sourced from spSchemeData\[sp.id\].band\_results and spResultIdMap.

Example rows for STO SP-A (carry-forward) and SFT SP-B (normal flow):

| result\_id | range\_band\_id | range\_start | range\_end | raw | carry\_in | adjusted | carry\_out | tier\_hit | payout |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- |
| ir-uuid-1 (STO) | band-sto-uuid-3 | 6 | null | 40 | 0 | 40 | 5 | high | 170000 |
| ir-uuid-1 (STO) | band-sto-uuid-2 | 4 | 5 | 68 | 5 | 73 | 3 | high | 150000 |
| ir-uuid-1 (STO) | band-sto-uuid-1 | 2 | 3 | 90 | 3 | 93 | 93 (discard) | not\_met | 0 |
| ir-uuid-2 (SFT) | band-sft-uuid-3 | 6 | null | 12 | 0 | 12 | 0 | low | 90000 |
| ir-uuid-2 (SFT) | band-sft-uuid-2 | 4 | 5 | 50 | 0 | 50 | 0 | low | 70000 |
| ir-uuid-2 (SFT) | band-sft-uuid-1 | 2 | 3 | 85 | 0 | 85 | 0 | low | 50000 |

**Step 10.3 — Insert SP Errors into incentive\_run\_errors**

Identical to JOT Range Products — Section 2.5 Step 10.3.

## **Part B — SPV Calculation**

Runs immediately after SP write succeeds. Uses spResultIdMap and spSchemeData already held in memory.

### **Step 11 — Filter Eligible Supervisors**

Identical to JOT Range Products — Section 2.5 Step 11\.

### **Step 12 — Calculate Each Supervisor (All in Memory)**

Initialize accumulators — identical to JOT Range Products — Section 2.5 Step 12\.

**Step 12.1 — Fetch Reportees and Filter by Eligible SP Types**

Identical to JOT Range Products — Section 2.5 Step 12.1 — with the following difference in intersection outcome since eligible\_sp\_types \= \["STO", "SFT"\]:

| applicableTypes \= supervisedTypes.filter(t \=\> eligible\_sp\_types.includes(t)) // SPV Dry  → \["STO"\] ∩ \["STO","SFT"\] \= \["STO"\] // SPV MIX  → \["STO","SMO"\] ∩ \["STO","SFT"\] \= \["STO"\] // SPV SMO  → \["SMO"\] ∩ \["STO","SFT"\] \= \[\] → SPV\_NO\_REPORTEES |
| :---- |

**Step 12.2 — Resolve SPV Type**

Identical to JOT Range Products — Section 2.5 Step 12.2.

**Step 12.3 — Compute SPV Payout Per Reportee Per Band**

Identical to JOT Range Products — Section 2.5 Step 12.3. bandMap\[reportee.type\] correctly resolves to STO or SFT bands depending on each reportee's type — same lookup logic as Range Products, bandMap simply contains two keys here instead of one.

Example — SPV MIX with 3 reportees (SP-A STO, SP-B STO, SP-C SFT):

SPV payout config for STO bands:

| Band | Low SPV Payout | Mid SPV Payout | High SPV Payout |
| :---- | :---- | :---- | :---- |
| 6+ | Rp. 60,000 | Rp. 90,000 | Rp. 110,000 |
| 4–5 | Rp. 50,000 | Rp. 80,000 | Rp. 100,000 |
| 2–3 | Rp. 40,000 | Rp. 70,000 | Rp. 90,000 |

SPV payout config for SFT bands:

| Band | Low SPV Payout | Mid SPV Payout | High SPV Payout |
| :---- | :---- | :---- | :---- |
| 6+ | Rp. 55,000 | Rp. 85,000 | Rp. 105,000 |
| 4–5 | Rp. 45,000 | Rp. 75,000 | Rp. 95,000 |
| 2–3 | Rp. 35,000 | Rp. 65,000 | Rp. 85,000 |

| Reportee | Type | Band | tier\_hit | SPV Payout (uses reportee’s type config) |
| :---- | :---- | :---- | :---- | :---- |
| SP-A | STO | 6+ | high | Rp. 110,000 (STO SPV high) |
| SP-A | STO | 4–5 | high | Rp. 100,000 (STO SPV high) |
| SP-A | STO | 2–3 | not\_met | Rp. 0 |
| SP-B | STO | 6+ | low | Rp. 60,000 (STO SPV low) |
| SP-B | STO | 4–5 | low | Rp. 50,000 (STO SPV low) |
| SP-B | STO | 2–3 | not\_met | Rp. 0 |
| SP-C | SFT | 6+ | low | Rp. 55,000 (SFT SPV low — different config from STO) |
| SP-C | SFT | 4–5 | low | Rp. 45,000 (SFT SPV low) |
| SP-C | SFT | 2–3 | low | Rp. 35,000 (SFT SPV low) |

SPV payout from SP-A \= Rp. 110,000 \+ Rp. 100,000 \+ Rp. 0 \= Rp. 210,000

SPV payout from SP-B \= Rp. 60,000 \+ Rp. 50,000 \+ Rp. 0 \= Rp. 110,000

SPV payout from SP-C \= Rp. 55,000 \+ Rp. 45,000 \+ Rp. 35,000 \= Rp. 135,000

Total SPV payout \= Rp. 210,000 \+ Rp. 110,000 \+ Rp. 135,000 \= Rp. 455,000

**Step 12.4 — Push to Accumulators**

Identical to JOT Range Products — Section 2.5 Step 12.4.

### **Step 13 — Bulk Write SPV Results (Single Transaction)**

**Step 13.1 — Insert into incentive\_results**

Identical to JOT Range Products — Section 2.5 Step 13.1.

**Step 13.2 — Insert into jot\_incentive\_spv**

Identical to JOT Range Products — Section 2.5 Step 13.2. 

Example rows for SPV MIX with 3 reportees (SP-A STO, SP-B STO, SP-C SFT):

| result\_id | sp\_result\_id |
| :---- | :---- |
| spv-result-uuid-1 | ir-uuid-1 (SP-A, STO) |
| spv-result-uuid-1 | ir-uuid-2 (SP-B, STO) |
| spv-result-uuid-1 | ir-uuid-3 (SP-C, SFT) |

**Step 13.3 — Insert SPV Errors into incentive\_run\_errors**

### Identical to JOT Range Products — Section 2.5 Step 13.3.

### **Step 14 — Update Run Log**

Identical to JOT Range Products — Section 2.5 Step 14\.

## **3.6 Retry and Failure Handling**

Identical to JOT Range Products — Section 2.6

## **3.7 Error Reference**

Identical to JOT Range Products — Section 2.7