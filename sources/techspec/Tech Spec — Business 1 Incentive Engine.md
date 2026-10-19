# **Tech Spec — Business 1 Incentive Engine**

## **Document Status**

Version: Version v1  
Scope: Pass 1 — Core solution, calculation logic, data model, integrations, and APIs  
Out of scope for this draft: Detailed BullMQ processing, CRON orchestration, retry/DLQ behavior, and worker sequencing. These will be added in the next iteration.

# **1\. Context**

Business 1 incentive calculation is a point-based incentive model.

Unlike Business 2, where each incentive scheme directly calculates a payout amount, Business 1 incentives calculate points for each incentive point component. The total points are then mapped to a final incentive amount using a level-based payout table.

Business 1 has two mutually exclusive salesperson types:

1. Non-Trader  
2. Trader

A salesperson belongs to either Trader or Non-Trader, never both.

Business 1 calculation uses salesperson level for calculation logic:

Level 1 \= SALES  
Level 2 \= SPV / KAO  
Level 3 \= RSO

KAO is processed as Level 2 for calculation. The original role returned by Users API is still stored for audit and reporting.

## **1.1 High-Level Model**

Incentive point achievement  
→ Match point slab  
→ Award points  
→ Sum points into Total Points  
→ Lookup payout amount from payout table  
→ Apply AR ageing deduction for Non-Trader only  
→ Store final incentive result

## **1.2 Key Difference from Business 2**

Business 2:

Scheme achievement → Slab → Direct payout amount

Business 1:

Incentive point achievement → Slab → Points  
Total points → Payout table → Incentive amount

Therefore, Business 1 requires a separate point-based model and point-slab configuration. We should reuse Business 2 infrastructure patterns and existing common tables where feasible, but we should not directly reuse the Business 2 payout slab/result model where it does not fit the point-based calculation flow.

For example, Business 2 result flow stores payout amount directly against a scheme result. Business 1 first stores incentive point-level results, then sums points, applies payout table lookup, and finally applies AR ageing deduction for Non-Trader. Because of this difference, Business 1 needs separate point-result and final-result tables while still reusing common run/logging tables where feasible.

---

# **2\. Goals**

## **2.1 Functional Goals**

The system should support:

1. Configuring Business 1 incentive points.  
2. Configuring point slabs per incentive point, level, salesperson type, and channel where applicable.  
3. Configuring total points-to-payout table.  
4. Configuring AR ageing deduction rules.  
5. Ingesting required external inputs.  
6. Calculating Non-Trader incentive points.  
7. Calculating Trader incentive points.  
8. Calculating total points and final incentive payout.  
9. Applying Non-Trader AR ageing deduction.  
10. Storing detailed incentive point-level and final-level results for auditability.  
11. Providing APIs for configuration, input feeds, calculation trigger, and result reporting.

## **2.2 Non-Goals for Phase 1**

The following are out of scope for Phase 1:

1. Finance disbursement workflow after final payout dataset is generated.  
2. Salesperson-facing incentive dashboard or self-view.  
3. Historical back-calculation for cycles before Business 1 engine launch.  
4. Master data management for salesperson-channel, salesperson-customer, or salesperson-unit mapping.  
5. UI-based management of privileged users. Privileged users will be configured through environment/config.  
6. Full approval workflow such as approved/paid lifecycle.  
---

# **3\. Confirmed Product Decisions**

The following decisions were confirmed by Product and should be treated as part of this tech spec.

## **3.1 Channel Decisions**

1. Non-Trader Team Volume slabs are channel-specific.  
2. AR ageing deduction is channel-specific.  
3. Channel mapping comes from the Users/Salesperson API.  
4. If the existing Users/Salesperson API does not expose channel, it must be added.  
5. SPV, KAO, and RSO each have their own channel.  
6. One SPV or RSO will have reportees belonging to one channel only.  
7. Channel should be stored in participant snapshot and copied into result tables for audit/reporting.

## **3.2 Salesperson Type and Level Decisions**

1. Salesperson type source is the same Users/Salesperson API used in Business 2\.  
2. The API currently provides salesperson type codes such as STO, SMO, SPV Dry, etc.  
3. For Business 1, these type codes must be mapped to Trader / Non-Trader eligibility.  
4. A salesperson belongs to either Trader or Non-Trader, never both.  
5. Business 1 calculation should use level.

Level mapping:

Level 1 \= SALES  
Level 2 \= SPV / KAO  
Level 3 \= RSO

6. KAO is treated the same as SPV for incentive calculation because both are Level 2\.  
7. The original role returned by the Users API should still be stored for reporting/audit.  
8. Example: if Users API returns KAO, then level \= 2 and original\_role \= KAO.

## **3.3 Hierarchy Decision**

Hierarchy should be taken at the point of incentive calculation.

The calculation will not use historical/effective-dated hierarchy unless added later.

There will be no dedicated hierarchy API.

The Incentive Engine will use Users/Salesperson API and build hierarchy using upline\_id.

Users API supports filtering by multiple upline IDs using:

dynamic\_filters\[UPLINE\_ID\]=\[id\_1,id\_2\]

Example hierarchy fetch for RSO:

1. Fetch direct reportees under RSO using dynamic\_filters\[UPLINE\_ID\]=\[rso\_id\].  
2. From this response, collect Level 2 users.  
3. Fetch users under those Level 2 users using dynamic\_filters\[UPLINE\_ID\]=\[level\_2\_id\_1,level\_2\_id\_2\].  
4. Build RSO → Level 2 → Level 1 hierarchy in participant snapshot.

The hierarchy snapshot created at run start will be used for all roll-up calculations in that run.

## **3.4 Target Decisions**

1. For Volume Achievement, Level 2 / Level 3 target \= own target \+ reportee targets.  
2. For New Transacted Outlets, Level 2 / Level 3 target \= own target \+ reportee targets.  
3. The existing T2 New Customer target and achievement are changed globally from sales quantity to customer count. The existing target field remains in use; no new target table or target type is required.  
4. New Transacted Outlets uses the monthly New Customer Monthly feed. The source system identifies which customers are new. Target Sales groups the source rows by salesperson and customer, sums net\_sales\_quantity\_kg for the month, and considers a customer transacted only when the monthly total is greater than zero.

Business 1 uses the resulting active monthly customer activity snapshot directly. It does not perform a separate Daily Sales lookup during the incentive-point calculation.

## **3.5 Volume Decisions**

1. The volume unit is kg.  
2. Daily sales feed reflects quantity in kg.  
3. Returns appear as negative quantities.  
4. Negative quantities should reduce achievement.  
5. Monthly actual volume should be calculated as sum(quantity\_kg).

## **3.6 Customer Handled Decisions**

1. Total customers handled will come from a new Customer Management API.  
2. The Customer Handled source API will be implemented in nodejs-ws2closio and consumed by ws2targetsalesincentive.  
3. A handled customer is a row in the Closio customers table where customer\_type \= 'CUSTOMER' and deleted\_at IS NULL. Customer ownership is determined using customers.sales\_id.  
4. Closio returns the salesperson’s own customer count for all non-deleted partner users, including users with zero handled customers. Closio does not apply Business 1 level, role, or Trader/Non-Trader filtering. Eligibility filtering and hierarchy aggregation are performed by the Incentive Engine.  
5. Data will be available for all levels.  
6. For Level 2 / Level 3, the API returns own data only.  
7. Final Level 2 / Level 3 achievement must also include reportee data.  
8. Period includes month and year.  
9. Data is final at month-end.  
10. Data can be refreshed again for the same partner and period.  
11. On refresh, previous active Customer Handled rows for the same partner and period are marked replaced/inactive, and latest rows are inserted as active.  
12. Refresh is rejected when a Business 1 calculation run is pending or processing for the same partner and period. It is also rejected after the successful CATCHUP\_CRON run for that period.  
13. One customer cannot appear under multiple salespeople.  
14. Customer counts should trust the source. No deduplication is required during roll-up.

## **3.7 New Transacted Customer Decisions**

1. New Transacted Outlets uses the existing POST /api/target/v1/webhooks/new-customer-monthly feed. The source system sends one complete monthly file containing the new-customer subset of Daily Sales-compatible transaction rows.  
2. The source system provides the final monthly new-customer transaction dataset. Target Sales determines which new customers qualify as transacted by calculating whether their monthly net sales quantity is greater than zero.  
3. Incentive Engine does not perform a separate Daily Sales check for this incentive point.  
4. The source system owns identifying whether the customer is new. Target Sales groups the incoming rows by partner, period, salesperson, and customer; sums net\_sales\_quantity\_kg; and considers the customer transacted only when the resulting monthly quantity is greater than zero.  
5. One customer must not be assigned to multiple salespeople for the same partner and month. If this occurs, all rows for that customer are excluded and flagged, neither salesperson receives achievement for the customer, and other valid customers continue processing.”  
6. Multiple transaction rows for the same salesperson and customer are allowed and are aggregated. An exact duplicate transaction event must not be counted more than once.  
7. DB storage remains one active row per salesperson and qualifying customer.  
8. The source may resend one complete corrected file for the same partner and period before the successful CATCHUP\_CRON run. Incremental and delta files are not supported.  
9. When a corrected complete file succeeds, previous active rows for the same partner and period are marked replaced/inactive and the latest qualifying rows are inserted as active.  
10. New Customer Monthly ingestion is rejected when a Business 1 calculation run is pending or processing for the same partner and period. Replacement is also rejected after the successful CATCHUP\_CRON run for that period.  
11. The existing new-customer-monthly webhook is the final delivery contract. The mechanism for explicitly representing a month with zero new customers remains pending and does not block the rest of the implementation.

## **3.8 Team Volume Decisions**

1. Team Volume denominator should include all active reporting users.  
2. Missing target, zero target, missing sales, or missing Volume Achievement result should not remove the user from the denominator.  
3. For such users, Volume Achievement should default to 0\.  
4. Inactive users should not be included.  
5. For Level 2, denominator includes direct active Level 1 reportees.  
6. For Level 3, denominator includes active Level 2 and Level 1 reportees.  
7. Slab boundaries are admin-configurable.  
8. Any value that does not fall into configured slabs gets 0 points.  
9. Admin may or may not explicitly configure 0% \= 0 points.

   ## **3.9 AR Ageing Decisions**

1. AR ageing deduction applies to Non-Trader only.  
2. AR ageing deduction is channel-specific.  
3. AR ageing configuration is period-level. One active AR ageing config exists for a partner and validity period. Channels and salesman-level rules are configured as child rows under that config.  
4. AR ageing feed contains overdue bucket amounts.  
5. AR Ending Balance is not required for storage or calculation.  
6. Current amount is not required for storage or calculation.  
7. Total Overdue \= OD 1-7 \+ OD 8-14 \+ OD 15-21 \+ OD 22-30 \+ OD \> 30\.  
8. The previous bucket-percentage logic is not used for deduction selection in Phase 1\.  
9. Deduction is selected by the highest overdue-day window that has overdue amount greater than 0 after aggregation.  
10. Fixed overdue-day windows are:  
     OD\_GT\_30 \= overdue \> 30 days  
     OD\_GT\_21 \= overdue \> 21 days  
     OD\_GT\_14 \= overdue \> 14 days  
     OD\_GT\_7 \= overdue \> 7 days  
     OD\_GT\_0 \= overdue \> 0 days  
11. Bucket priority is fixed and evaluated from highest overdue window to lowest:  
12. OD\_GT\_30  
13. OD\_GT\_21  
14. OD\_GT\_14  
15. OD\_GT\_7  
16. OD\_GT\_0  
17. The operator is fixed as `>` and is display-only in the UI.  
18. Overdue-day thresholds are fixed and are display-only in the UI.  
19. Admin can configure only deduction\_percentage for each fixed overdue-day window.  
20. deduction\_percentage is stored as a positive number. Example: 20 means deduct 20% of gross incentive.  
21. Deduction amount \= gross\_incentive × deduction\_percentage / 100\.  
22. If total\_overdue \= 0, deduction is 0\.  
23. If all overdue bucket amounts are 0, deduction is 0\.  
24. If a matching overdue window has deduction\_percentage \= 0, deduction is 0\.  
25. AR ageing config is configured by channel and Non-Trader level:  
     Level 1 \= SALES  
     Level 2 \= SPV / KAO  
     Level 3 \= RSO  
26. AR ageing config may be partial by channel and level. If no active AR ageing config header exists for partner \+ calculation period, fail with AGEING\_CONFIG\_MISSING. If config header exists but no active rule group exists for the participant’s channel \+ salesperson\_type \= NON\_TRADER \+ level, fail with AGEING\_RULE\_MISSING.

## **3.10 Slab Lookup Decision**

1. Business 1 point slabs use ordered threshold lookup.  
2. Each slab row contains one condition using operator \+ value and a point value.  
3. Multiple slab rows may match the same achievement value.  
4. When multiple rows match, the backend selects the matching row with the highest points value.  
5. If multiple matching rows have the same highest points, the backend uses band\_order as deterministic tie-breaker, then earliest created row/id if still tied.  
6. If no slab row matches the achievement value, the participant receives 0 points for that incentive point.  
7. The system should not require lower and upper bounds for Business 1 slabs in Phase 1\.

# **4\. Core Concepts**

## **4.1 Salesperson Type**

Business 1 supports two salesperson types:

NON\_TRADER  
TRADER

A user belongs to one salesperson type only.

The value comes from Users/Salesperson API and is mapped by backend from source salesperson type codes.

## **4.2 Level and Original Role**

Business 1 calculation uses level for logic.

Supported levels:

Level 1 \= SALES  
Level 2 \= SPV / KAO  
Level 3 \= RSO

Calculation logic should use level. The source role should be stored only as original\_role for audit/reporting.  
The original role returned by Users API should still be stored in original\_role.

Example:

Users API returns KAO.

Store:

level \= 2  
original\_role \= KAO

Calculation treats this user as Level 2\.

This keeps calculation simple while preserving the original source role for reporting and audit.

## **4.3 Hierarchy**

Hierarchy comes from Users/Salesperson API.

Each user has an upline\_id.

The Incentive Engine builds hierarchy from upline\_id at the start of each run.

The hierarchy is snapshotted for the run so that all calculations in the run use the same hierarchy.

There is no separate hierarchy API.

Users API supports filtering by multiple upline IDs using:

dynamic\_filters\[UPLINE\_ID\]=\[id\_1,id\_2\]

**Roll-up calculation rule**

Every hierarchy roll-up must use each participant’s own raw fact exactly once.

For Level 2 and Level 3 roll-ups, the engine should:

1. Resolve the distinct descendant set from the participant snapshot.  
2. Read own-only raw facts for the participant and each eligible descendant.  
3. Sum those own-only facts once.  
4. Never add an already aggregated parent result and then add the same child participants again.

This rule applies to volume, targets, customers handled, new transacted customers, AR ageing, Trader stock, and Trader GPM wherever roll-up is required.

For ratio-based calculations, calculate using ratio of sums, not average of row-level ratios.

Examples:

Trader stock roll-up:

SUM(stock\_eom) / SUM(billing\_eom) × multiplier\_days

Trader GPM roll-up:

SUM(gp\_value) / SUM(revenue) × 100

## **4.4 Channel**

Channels apply to Non-Trader only.

Supported channels from BRD:

Catering  
FC Local  
QSR  
HoRe  
Industry

The channel should be fetched from Users/Salesperson API.

For auditability, the channel used during calculation should be stored in participant snapshot and result tables.

## **4.5 Incentive Point**

An incentive point is one point-producing or deduction calculation component.

Examples:

Volume Achievement  
% Transacted Outlets  
Stock Level — By Product  
GPM All Product  
AR Ageing Deduction

Most incentive points produce points.

AR Ageing Deduction does not produce points. It reduces gross incentive for Non-Trader users.

## **4.6 Total Points**

Each applicable point-producing incentive point returns points.

The system sums all applicable points for the participant.

total\_points \= sum(points from applicable point-producing incentive points)

Total points are then used to lookup gross incentive from the payout table.

## **4.7 Payout**

Payout is the final incentive amount calculated from total points.

For Business 1:

Incentive point results → Total Points → Payout table → Gross Incentive

For Non-Trader:

Gross Incentive \- AR Ageing Deduction \= Net Incentive

For Trader:

Gross Incentive \= Net Incentive

## **4.8 Run Model**

Business 1 incentive calculation uses a run-based model.

Supported Business 1 run types:

1. CRON  
2. CATCHUP\_CRON  
3. MANUAL

CRON is the scheduled monthly calculation run.

CATCHUP\_CRON is the scheduled catch-up run, aligned with the Business 2 catch-up pattern.

MANUAL is an admin/privileged manual recalculation trigger.

Business 1 does not use Open / Grace / Locked cycle states.

Business 1 does not lock the period after CATCHUP\_CRON.

Manual recalculation can be triggered even after CATCHUP\_CRON has completed, subject to normal validation rules.

Customer input finality is a specific exception to the general no-lock rule. Customer Handled refresh and New Customer Monthly replacement are rejected after the successful CATCHUP\_CRON run for the period. This does not prevent manual recalculation using the customer data already finalized for that period.

Except for the customer-input finality rule above, Business 1 rejects mutating actions while another Business 1 calculation run is pending or processing for the same partner and period.

This applies to:

1. input refresh  
2. AR Ageing feed replacement  
3. Trader upload  
4. Trader active-row delete  
5. config create/update/status change  
6. manual recalculation trigger

Run status is tracked in incentive\_run\_log.

Calculation outputs are controlled using publication\_status and is\_deprecated. Draft rows are not visible in default result APIs. Published, non-deprecated rows represent the current visible result.

When a new publishable run is produced, older current results for the same partner, period, and impacted participants are marked is\_deprecated \= true.

Old calculation results should not be physically deleted during recalculation.

# **5\. Business 1 Incentive Point Registry**

Business 1 incentive points should be stored as static/seeded records.

The registry uses incentive point terminology.

Recommended table name:

incentive\_point\_metrics

The registry identifies:

1. Which incentive points exist.  
2. Applicable salesperson type: NON\_TRADER or TRADER.  
3. component\_type defines whether the incentive point is a POINT component or a DEDUCTION component.  
4. Whether channel is required.  
5. Which levels are applicable.

The registry should include partner\_id so the same structure can support partner-specific incentive points in future.

## **5.1 Non-Trader Incentive Points**

| Incentive Point Code | Incentive Point Name | Component Type. | Applicable Levels | Channel Specific |
| ----- | ----- | ----- | ----- | ----- |
| NT\_VOLUME\_ACHIEVEMENT | Volume Achievement | POINT | 1, 2, 3 | Yes |
| NT\_TRANSACTED\_OUTLETS | % Transacted Outlets | POINT | 1, 2, 3 | Yes |
| NT\_NEW\_TRANSACTED\_OUTLETS | % New Transacted Outlets | POINT | 1, 2, 3 | Yes |
| NT\_TEAM\_VOLUME\_ACHIEVEMENT | Team Volume Achievement | POINT | 2, 3 | Yes |
| NT\_AR\_AGEING\_DEDUCTION | AR Ageing Deduction | DEDUCTION | 1, 2, 3 | Yes |

## **5.2 Trader Incentive Points**

| Incentive Point Code | Incentive Point Name | Component Type. | Applicable Levels | Channel Specific |
| ----- | ----- | ----- | ----- | ----- |
| TR\_STOCK\_BY\_PRODUCT | Stock Level — By Product | POINT | 1, 2, 3 | No |
| TR\_STOCK\_GRADE | Stock Level — Grade | POINT | 1, 2, 3 | No |
| TR\_STOCK\_SIDE\_PRODUCT | Stock Level — Side Product | POINT | 1, 2, 3 | No |
| TR\_GPM\_BY\_PRODUCT | GPM by Product | POINT | 1 | No |
| TR\_GPM\_ALL\_PRODUCT | GPM All Product | POINT | 2, 3 | No |
| TR\_TEAM\_VOLUME\_SALES | Team Volume Sales | POINT | 2, 3 | No |

---

# **6\. Non-Trader Calculation Logic**

## **6.1 Non-Trader Calculation Flow**

For each Non-Trader participant:

1. Calculate Volume Achievement points.  
2. Calculate % Transacted Outlets points.  
3. Calculate % New Transacted Outlets points.  
4. Calculate Team Volume Achievement points.  
5. Sum points into Total Points.  
6. Lookup Gross Incentive from payout table.  
7. Calculate AR ageing deduction.  
8. Apply deduction.  
9. Store Net Incentive.

For Level 1, Team Volume Achievement points \= 0\.

AR ageing deduction applies to Non-Trader levels 1, 2, and 3\. The applicable deduction rule is resolved using the participant’s channel and level. If no active AR ageing rule exists for the participant’s channel \+ level \+ calculation period, the participant should fail with AGEING\_RULE\_MISSING.

## **6.2 A.1 Volume Achievement**

### **Applicable Levels**

| Level | Role Mapping | Applicable |
| ----- | ----- | ----- |
| Level 1 | SALES | Yes |
| Level 2 | SPV / KAO | Yes |
| Level 3 | RSO | Yes |

KAO is treated as Level 2\.

### **Data Sources**

| Data | Source |
| ----- | ----- |
| Target volume | Target Engine |
| Actual volume | Daily sales feed |
| Hierarchy | Users/Salesperson API |
| Channel | Users/Salesperson API |

### **Formula**

% Achievement \= aggregated actual volume / aggregated target volume × 100

Volume unit: kg

Returns appear as negative quantities and reduce actual volume.

Monthly actual volume should be calculated as:

actual\_volume \= sum(quantity\_kg)

### **Aggregation Rules**

| Level | Actual Volume | Target Volume |
| ----- | ----- | ----- |
| Level 1 | Own actual volume | Own target volume |
| Level 2 | Own actual volume \+ direct Level 1 reportee actual volume | Own target volume \+ direct Level 1 reportee target volume |
| Level 3 | Own actual volume \+ downstream Level 2 actual volume \+ downstream Level 1 actual volume | Own target volume \+ downstream Level 2 target volume \+ downstream Level 1 target volume |

### **Edge Cases**

| Scenario | Treatment |
| ----- | ----- |
| target is null | points \= 0 |
| target \= 0 | points \= 0 |
| actual is null | treat as 0 |
| actual is negative after returns | achievement can be negative; unmatched slab gives 0 |
| no matching slab | points \= 0 |

### **Slab Lookup**

| Dimension | Value |
| ----- | ----- |
| salesperson\_type | NON\_TRADER |
| incentive\_point\_code | NT\_VOLUME\_ACHIEVEMENT |
| level | 1 / 2 / 3 |
| channel | participant channel |
| period | calculation month |

### **Output**

| Output Field | Description |
| ----- | ----- |
| points | Points awarded from matched slab |
| matched\_slab\_id | Matching incentive point slab ID |

Channel should be stored in participant snapshot and copied into incentive point result and final result tables for audit/reporting.

## **6.3 A.2 % Transacted Outlets**

### **Applicable Levels**

| Level | Role Mapping | Applicable |
| ----- | ----- | ----- |
| Level 1 | SALES | Yes |
| Level 2 | SPV / KAO | Yes |
| Level 3 | RSO | Yes |

KAO is treated as Level 2\.

### **Data Sources**

| Data | Source |
| ----- | ----- |
| Total customers handled | Customer Management API |
| Customers with positive sales | Daily sales feed |
| Hierarchy | Users/Salesperson API |
| Channel | Users/Salesperson API |

### **Formula**

% Transacted \= customers with positive sales quantity / total customers handled × 100

A customer qualifies as transacted if:

sum(sales quantity for the customer in the month) \> 0

For each salesperson \+ customer \+ month, the system should sum all sales quantity rows.

| Net Monthly Quantity | Treatment |
| ----- | ----- |
| \> 0 | Count customer once as transacted |
| \= 0 | Do not count |
| \< 0 | Do not count |

Multiple transactions for the same customer count once.

### **Customer Handled Input**

Customer Management API provides own customer count for each salesperson/level.

Expected logical data:

| Field | Description |
| ----- | ----- |
| period | Month/year of the data |
| salesperson\_id | Salesperson/user ID |
| customer\_count | Total customers handled by that salesperson |

For Level 2 / Level 3, this data represents only their own customers. The Incentive Engine must add reportee customer counts during roll-up.

### **Aggregation Rules**

| Level | Denominator | Numerator |
| ----- | ----- | ----- |
| Level 1 | Own handled customer count | Own unique positive transacted customers |
| Level 2 | Own handled customers \+ direct Level 1 handled customers | Own positive transacted customers \+ direct Level 1 positive transacted customers |
| Level 3 | Own handled customers \+ downstream Level 2 handled customers \+ downstream Level 1 handled customers | Own positive transacted customers \+ downstream Level 2 positive transacted customers \+ downstream Level 1 positive transacted customers |

### **Deduplication**

| Rule | Decision |
| ----- | ----- |
| Can one customer appear under multiple salespeople? | No |
| Should source count be trusted? | Yes |
| Is deduplication required during Level 2 / Level 3 roll-up? | No |

### **Edge Cases**

| Scenario | Treatment |
| ----- | ----- |
| customer\_count \= 0 | points \= 0 |
| customer\_count missing | points \= 0 and flag DATA\_MISSING |
| no positive transactions | achievement \= 0, points \= 0 |
| no matching slab | points \= 0 |

## **6.4 A.3 % New Transacted Outlets**

### **Applicable Levels**

| Level | Role Mapping | Applicable |
| ----- | ----- | ----- |
| Level 1 | SALES | Yes |
| Level 2 | SPV / KAO | Yes |
| Level 3 | RSO | Yes |

KAO is treated as Level 2\.

### **Data Sources**

| Data | Source |
| ----- | ----- |
| Final monthly new-customer transaction data | POST /api/target/v1/webhooks/new-customer-monthly |
| Target new transacted customer count | Target Engine |
| Hierarchy | Users/Salesperson API |
| Channel | Users/Salesperson API |

### **Target Requirement**

The existing T2 New Customer target is changed globally from a sales-quantity target in KG to a customer-count target.

The existing target\_value field and target\_sales\_volume\_new\_customers table continue to be used. No separate target field or target table is introduced.

For T2:

target\_value \= monthly new-customer count target

### **Source / Achievement**

New Transacted Outlets uses the monthly new-customer sales feed delivered through:

POST /api/target/v1/webhooks/new-customer-monthly

The source system identifies which customers are new for the month. Target Sales determines whether those new customers are transacted.

For each partner, period, salesperson, and customer:

monthly\_net\_sales\_quantity \= SUM(net\_sales\_quantity\_kg)

The customer qualifies as a new transacted customer only when monthly\_net\_sales\_quantity is greater than zero.

Multiple transaction rows for the same salesperson and customer are allowed and are aggregated. Returns and negative transactions reduce the monthly total.

The finalized active dataset contains one row per salesperson and qualifying customer in incentive\_new\_transacted\_customer\_activity.

Business 1 uses this active monthly snapshot directly and does not perform a separate Daily Sales lookup during the incentive-point calculation.

Expected stored data:

period — Month and year derived from billing\_date

salesperson\_id — Salesperson ID derived from sid

customer\_id — Customer identifier derived from customer

monthly\_net\_sales\_quantity — Aggregated monthly net sales quantity

### **Formula**

Achievement Count \= count of active qualifying customer rows in incentive\_new\_transacted\_customer\_activity for the participant’s applicable hierarchy scope

% Achievement \= Achievement Count / target new transacted customers × 100

### **Aggregation Rules**

| Level | Achievement Count | Target |
| ----- | ----- | ----- |
| Level 1 | Own new transacted customers | Own target |
| Level 2 | Own achievement count \+ direct Level 1 achievement count | Own target \+ direct Level 1 targets |
| Level 3 | Own achievement count \+ downstream Level 2 achievement count \+ downstream Level 1 achievement count | Own target \+ downstream Level 2 targets \+ downstream Level 1 targets |

### **Duplicate / Replacement Rules**

| Rule | Decision |
| ----- | ----- |
| Input transaction grain | Multiple transaction rows for the same salesperson and customer are allowed |
| Aggregation grain | partner\_id \+ period \+ salesperson\_id \+ customer\_id |
| Exact duplicate transaction event | Exclude the duplicate copy so it does not contribute more than once |
| Same customer under multiple salespeople | Exclude all rows for the affected customer, flag them with CUSTOMER\_ASSIGNED\_TO\_MULTIPLE\_SALESPEOPLE, and process other valid customers |
| Incremental or delta input | Not supported |
| Replacement during calculation | Reject when a Business 1 run is pending or processing for the same partner and period |
| Replacement after successful CATCHUP\_CRON | Reject |

### **Edge Cases**

| Scenario | Treatment |
| ----- | ----- |
| target is null | points \= 0 |
| target \= 0 | points \= 0 |
| new transacted customer list empty | achievement\_count \= 0, points \= 0 |
| no matching slab | points \= 0 |
| Exact duplicate transaction event | Exclude the duplicate copy and do not count it twice |
| Same customer assigned to multiple salespeople | Exclude all rows for the affected customer and flag them; process other valid customers |

## **6.5 A.4 Team Volume Achievement**

### **Applicable Levels**

| Level | Role Mapping | Applicable |
| ----- | ----- | ----- |
| Level 1 | SALES | No, always 0 points |
| Level 2 | SPV / KAO | Yes |
| Level 3 | RSO | Yes |

KAO is treated as Level 2\.

### **Data Sources**

| Data | Source |
| ----- | ----- |
| Volume Achievement output | NT\_VOLUME\_ACHIEVEMENT incentive point results |
| Hierarchy | Users/Salesperson API |
| Channel | Users/Salesperson API |
| User active/inactive status | Users/Salesperson API |

### **Dependency**

Team Volume Achievement depends on Volume Achievement results.

Volume Achievement must be calculated first.

### **Formula**

| Level | Formula |
| ----- | ----- |
| Level 2 | Team % \= direct active Level 1 reportees with Volume Achievement \>= 100% / total active direct Level 1 reportees × 100 |
| Level 3 | Team % \= active downstream members with Volume Achievement \>= 100% / total active downstream members × 100 |

For Level 3, denominator includes:

| Included Level | Included |
| ----- | ----- |
| Level 2 | Yes |
| Level 1 | Yes |

### **Eligible Member Rules**

Team Volume denominator should include all active reporting users.

A member is included in the denominator if:

| Condition | Required |
| ----- | ----- |
| User is active | Yes |
| User is part of reporting hierarchy | Yes |

A member should not be excluded just because:

| Scenario | Treatment |
| ----- | ----- |
| target is missing | Include in denominator; Volume Achievement defaults to 0 |
| target is zero | Include in denominator; Volume Achievement defaults to 0 |
| sales data is missing | Include in denominator; Volume Achievement defaults to 0 |
| Volume Achievement result is missing | Include in denominator; Volume Achievement defaults to 0 |
| Volume Achievement could not be calculated normally | Include in denominator; Volume Achievement defaults to 0 |
| user is inactive | Exclude |

### **Numerator Rule**

| Condition | Treatment |
| ----- | ----- |
| Volume Achievement \>= 100% | Include in numerator |
| Volume Achievement \< 100% | Do not include in numerator |
| Missing/defaulted Volume Achievement | Treat as 0%; do not include in numerator |

### **Example**

Level 2 has 4 active Level 1 reportees:

| Reportee | Volume Achievement | Denominator | Numerator |
| ----- | ----- | ----- | ----- |
| Reportee 1 | 120% | Included | Included |
| Reportee 2 | 80% | Included | Not included |
| Reportee 3 | Missing target, default achievement \= 0% | Included | Not included |
| Reportee 4 | No sales, default achievement \= 0% | Included | Not included |

Numerator \= 1

Denominator \= 4

Team % \= 25%

### **Slab Behavior**

Team Volume slabs are configurable by admin.

Example possible slab:

| Condition | Points |
| ----- | ----- |
| \> 0% and \< 75% | 1 |
| \= 75% | 2 |
| \> 75% | 3 |

Any value not matching any configured slab gives 0 points.

Admin does not need to explicitly configure 0% \= 0 points.

### **Slab Lookup**

| Dimension | Value |
| ----- | ----- |
| salesperson\_type | NON\_TRADER |
| incentive\_point\_code | NT\_TEAM\_VOLUME\_ACHIEVEMENT |
| level | 2 / 3 |
| channel | participant channel |
| period | calculation month |

## **6.6 A.5 AR Ageing Deduction**

### **Applicable Levels**

Level 1 \= SALES  
 Level 2 \= SPV / KAO  
 Level 3 \= RSO

AR ageing deduction applies only to Non-Trader participants.

### **Data Source**

Qlik Sense ageing feed.

### **Feed Fields**

Expected logical fields:

period  
 salesperson\_id  
 channel  
 customer\_id  
 total\_overdue  
 od\_1\_7  
 od\_8\_14  
 od\_15\_21  
 od\_22\_30  
 od\_gt\_30

### **Fields not stored**

ar\_ending\_balance  
 current\_amount  
 current\_pct  
 CURRENT bucket

### **Confirmed Rules**

Total Overdue \= od\_1\_7 \+ od\_8\_14 \+ od\_15\_21 \+ od\_22\_30 \+ od\_gt\_30.

AR Ending Balance is not used.

Current amount is not used.

Bucket percentage is not used for deduction selection.

Salesperson \+ customer should be unique for a partner and period.

There can be multiple customer rows for a single salesperson.

### **Aggregation Rules**

For Level 1:  
 Own AR rows only.

For Level 2:  
 Own AR rows \+ direct Level 1 reportee AR rows.

For Level 3:  
 Own AR rows \+ downstream Level 2 AR rows \+ downstream Level 1 AR rows.

Aggregation should happen at bucket level.

For each participant, first sum all applicable bucket amounts:

total\_od\_1\_7  
 total\_od\_8\_14  
 total\_od\_15\_21  
 total\_od\_22\_30  
 total\_od\_gt\_30  
 total\_overdue

### **Deduction Window Mapping**

After aggregation, backend determines the highest overdue-day window that has amount greater than 0\.

Mapping:

If total\_od\_gt\_30 \> 0, selected bucket \= OD\_GT\_30.

Else if total\_od\_22\_30 \> 0, selected bucket \= OD\_GT\_21.

Else if total\_od\_15\_21 \> 0, selected bucket \= OD\_GT\_14.

Else if total\_od\_8\_14 \> 0, selected bucket \= OD\_GT\_7.

Else if total\_od\_1\_7 \> 0, selected bucket \= OD\_GT\_0.

Else no bucket is selected and deduction\_percentage \= 0\.

### **Bucket Priority**

Bucket priority is fixed:

1. OD\_GT\_30  
2. OD\_GT\_21  
3. OD\_GT\_14  
4. OD\_GT\_7  
5. OD\_GT\_0

The first bucket with aggregated amount greater than 0 wins.

### **Config Lookup**

Resolve active AR ageing config by:

partner\_id  
 calculation period  
 status \= active

Then resolve active AR ageing rule by:

deduction\_config\_id  
 participant channel  
 salesperson\_type \= NON\_TRADER  
 participant level  
 selected bucket\_code  
 is\_deprecated \= false

### **Deduction Calculation**

If selected bucket has configured deduction\_percentage:

deduction\_amount \= gross\_incentive × deduction\_percentage / 100

net\_incentive \= gross\_incentive \- deduction\_amount

If selected bucket has deduction\_percentage \= 0:

deduction\_amount \= 0

net\_incentive \= gross\_incentive

If no bucket is selected:

deduction\_amount \= 0

net\_incentive \= gross\_incentive

Before bucket-specific lookup, backend should verify that an active AR ageing rule group exists for participant channel \+ salesperson\_type \= NON\_TRADER \+ participant level. If no rule group exists, fail with AGEING\_RULE\_MISSING. If the group exists and all overdue bucket amounts are 0, final\_bucket\_code \= null and deduction\_percentage \= 0\.

This prevents a missing channel/level config from being hidden when a user has zero overdue.

### **Example**

Aggregated AR bucket amounts:

OD 1-7 \= 100  
 OD 8-14 \= 0  
 OD 15-21 \= 200  
 OD 22-30 \= 50  
 OD \> 30 \= 0

Evaluation:

OD\_GT\_30 does not match because OD \> 30 amount \= 0\.  
 OD\_GT\_21 matches because OD 22-30 amount \> 0\.  
 Selected bucket \= OD\_GT\_21.

If configured deduction\_percentage for OD\_GT\_21 is 10:

deduction\_amount \= gross\_incentive × 10 / 100  
 net\_incentive \= gross\_incentive \- deduction\_amount

### **Edge Cases**

total\_overdue \= 0 → deduction \= 0\.

total\_overdue missing in feed row → reject row / fail feed processing before activation

All overdue bucket amounts are 0 → deduction \= 0\.

Matching bucket has deduction\_percentage \= 0 → deduction \= 0\.

No active AR ageing config found for partner \+ period → fail with AGEING\_CONFIG\_MISSING.

No active AR ageing rule found for participant channel \+ level \+ bucket → fail with AGEING\_RULE\_MISSING.

Trader participant → AR ageing deduction is not applicable.

---

# **7\. Trader Calculation Logic**

## **7.1 Trader Calculation Flow**

For each Trader participant:

1. Calculate Stock Level — By Product points.  
2. Calculate Stock Level — Grade points.  
3. Calculate Stock Level — Side Product points.  
4. Calculate GPM by Product points.  
5. Calculate GPM All Product points.  
6. Calculate Team Volume Sales points.  
7. Sum points into Total Points.  
8. Lookup Gross Incentive from payout table.  
9. Store final incentive result.

Trader does not have AR ageing deduction.

For Trader:

Gross Incentive \= Net Incentive

## **7.2 B.1 Stock Level — By Product**

### **Applicable Levels**

Level 1  
Level 2  
Level 3

KAO is treated as Level 2\.

### **Data Sources**

| Data | Source |
| ----- | ----- |
| Stock EOM | Trader stock upload |
| Billing EOM | Trader stock upload |
| Day multiplier | Backend configuration |
| Hierarchy | Users/Salesperson API |
| Salesperson type / level | Users/Salesperson API |

### **Formula**

Stock Level \= Stock EOM / Billing EOM × Day Multiplier

For Stock Level — By Product, use rows where category \= BY\_PRODUCT.

### **Calculation Rules**

The worker should calculate Stock Level for each applicable participant and compare the result against configured incentive point slabs.

For Level 1, use own stock and billing values.

For Level 2 and Level 3, use aggregated stock and billing values from the participant and applicable reportees as per hierarchy snapshot.

### **Slab Lookup**

salesperson\_type \= TRADER  
incentive\_point\_code \= TR\_STOCK\_BY\_PRODUCT  
level \= 1 / 2 / 3  
period \= calculation month

Channel is not applicable for Trader stock calculations.

### **Edge Cases**

| Scenario | Treatment |
| ----- | ----- |
| billing\_eom \= 0 | points \= 0 and flag DATA\_INVALID |
| billing\_eom missing | points \= 0 and flag DATA\_MISSING |
| stock\_eom missing | treat as 0 |
| day multiplier missing | fail config gate |
| no matching slab | points \= 0 |
| no stock upload data | points \= 0 and flag DATA\_MISSING |

## **7.3 B.2 Stock Level — Grade**

### **Applicable Levels**

Level 1  
Level 2  
Level 3

KAO is treated as Level 2\.

### **Data Sources**

| Data | Source |
| ----- | ----- |
| Stock EOM | Trader stock upload |
| Billing EOM | Trader stock upload |
| Grade | Trader stock upload |
| Day multiplier | Backend configuration |
| Hierarchy | Users/Salesperson API |
| Salesperson type / level | Users/Salesperson API |

### **Formula**

Stock Level \= Stock EOM / Billing EOM × Day Multiplier

For Stock Level — Grade, use rows where category \= GRADE.

### **Calculation Rules**

The worker should calculate Stock Level for each applicable participant and compare the result against configured incentive point slabs.

For Level 1, use own stock and billing values.

For Level 2 and Level 3, use aggregated stock and billing values from the participant and applicable reportees as per hierarchy snapshot.

### **Slab Lookup**

salesperson\_type \= TRADER  
incentive\_point\_code \= TR\_STOCK\_GRADE  
level \= 1 / 2 / 3  
period \= calculation month

Channel is not applicable for Trader stock calculations.

### **Edge Cases**

| Scenario | Treatment |
| ----- | ----- |
| billing\_eom \= 0 | points \= 0 and flag DATA\_INVALID |
| billing\_eom missing | points \= 0 and flag DATA\_MISSING |
| stock\_eom missing | treat as 0 |
| grade missing | points \= 0 and flag DATA\_MISSING |
| day multiplier missing | fail config gate |
| no matching slab | points \= 0 |
| no stock upload data | points \= 0 and flag DATA\_MISSING |

## **7.4 B.3 Stock Level — Side Product**

### **Applicable Levels**

Level 1  
Level 2  
Level 3

KAO is treated as Level 2\.

### **Data Sources**

| Data | Source |
| ----- | ----- |
| Stock EOM | Trader stock upload |
| Billing EOM | Trader stock upload |
| Product category | Trader stock upload |
| Day multiplier | Backend configuration |
| Hierarchy | Users/Salesperson API |
| Salesperson type / level | Users/Salesperson API |

### **Formula**

Stock Level \= Stock EOM / Billing EOM × Day Multiplier

For Stock Level — Side Product, use rows where category \= SIDE\_PRODUCT.

### **Calculation Rules**

The worker should calculate Stock Level for each applicable participant and compare the result against configured incentive point slabs.

For Level 1, use own stock and billing values.

For Level 2 and Level 3, use aggregated stock and billing values from the participant and applicable reportees as per hierarchy snapshot.

### **Slab Lookup**

salesperson\_type \= TRADER  
incentive\_point\_code \= TR\_STOCK\_SIDE\_PRODUCT  
level \= 1 / 2 / 3  
period \= calculation month

Channel is not applicable for Trader stock calculations.

### **Edge Cases**

| Scenario | Treatment |
| ----- | ----- |
| billing\_eom \= 0 | points \= 0 and flag DATA\_INVALID |
| billing\_eom missing | points \= 0 and flag DATA\_MISSING |
| stock\_eom missing | treat as 0 |
| product category missing | points \= 0 and flag DATA\_MISSING |
| day multiplier missing | fail config gate |
| no matching slab | points \= 0 |
| no stock upload data | points \= 0 and flag DATA\_MISSING |

##  **7.5 B.4 GPM by Product**

### Applicable Levels

Level 1 only.

### Data Sources

| Data | Source |
| ----- | ----- |
| Revenue | Trader GPM upload |
| GP value | Trader GPM upload |
| Customer ID | Trader GPM upload |
| Product ID | Trader GPM upload |
| Product category | Product Submissions API |
| Salesperson type / level | Users/Salesperson API |

Trader GPM Upload Format

Trader GPM upload file contains the following columns:

| Column | Required | Notes |
| ----- | ----- | ----- |
| Period | Yes | YYYY-MM |
| Sales ID | Yes | Salesperson/user ID |
| Cust ID | Yes | Customer ID |
| Prod ID | Yes | Product UUID |
| GP | Yes | GP value |
| Revenue | Yes | Revenue value |

Unique Key

The unique key for GPM upload rows is:

partner\_id \+ period \+ sales\_id \+ cust\_id \+ prod\_id

Duplicate rows with the same unique key in the same upload should be rejected.

### Product Lookup

The uploaded Prod ID is the Product UUID.

During upload processing, the backend should collect unique product IDs from the uploaded file and call Product Submissions API using PRODUCT\_ID filter.

Product API lookup should support multiple product IDs.

The Product API response field category\_label should be stored as product\_category.

For GPM by Product calculation:

product\_category \= 'BY PRODUCT'

means the row is eligible for GPM by Product calculation.

### Product Lookup Validation

| Scenario | Treatment |
| ----- | ----- |
| Product ID not found in Product API | Reject row |
| Product is inactive | Reject row |
| Product API call fails | Mark upload processing as failed or row as rejected based on retry/error handling |
| Product channel does not contain TRADER | No validation required |
| Product category missing | Reject row |

### Formula

**GPM percentage calculation should aggregate first.**

total\_gp\_value \= SUM(gp\_value)

total\_revenue \= SUM(revenue)

If total\_revenue \> 0:

GPM % \= total\_gp\_value / total\_revenue × 100

If total\_revenue \= 0:

points \= 0 and flag DATA\_INVALID

If total\_revenue \< 0:

GPM % \= \-1 × ABS(total\_gp\_value / total\_revenue) × 100

Negative GP and negative revenue should not cancel each other out and produce a positive GPM percentage.

If aggregated revenue is negative, calculated GPM percentage should be negative and should go through normal slab lookup. If the calculated GPM percentage does not match any configured slab, points \= 0\. No separate low-end slab is required in Phase 1\.

Calculation Rules

For GPM by Product:

1. Use active Trader GPM activity rows for the participant and period.  
2. Include rows where product\_category \= 'BY PRODUCT'.  
3. Exclude KW / Special Choice rows only after the Product team confirms the field used to identify KW / Special Choice.  
4. Until the KW / Special Choice field is confirmed, this exclusion rule remains pending and should not be hardcoded using grade.  
5. Calculate GPM percentage using the formula rules defined above. If aggregated revenue is negative, the calculated GPM percentage must remain negative and should go through normal slab lookup.

The column tipe\_3 is not required and should be removed from normalized GPM table and calculation logic.

The upload file does not contain grade. Filtering should not depend on grade unless Product later confirms a grade-equivalent field.

### Slab Lookup

salesperson\_type \= TRADER

incentive\_point\_code \= TR\_GPM\_BY\_PRODUCT

level \= 1

period \= calculation month

Channel is not applicable for Trader GPM calculations.

### Edge Cases

| Scenario | Treatment |
| ----- | ----- |
| SUM(revenue) \= 0 | points \= 0 and flag DATA\_INVALID |
| revenue missing | reject row during upload validation |
| revenue is negative | allow; if aggregated revenue is negative, calculated GPM percentage should be negative and should go through normal slab lookup |
| gp\_value missing | reject row during upload validation |
| gp\_value is negative | allow and include in SUM(gp\_value) |
| product ID missing | reject row |
| product ID invalid UUID | reject row |
| product not found | reject row |
| product inactive | reject row |
| product\_category missing after lookup | reject row |
| duplicate Period \+ Sales ID \+ Cust ID \+ Prod ID in same upload | reject duplicate row |
| no eligible rows after filtering | points \= 0 |
| no matching slab | points \= 0 |
| KW / Special Choice field not confirmed | keep exclusion rule pending |

## 

## **7.6 B.5 GPM All Product**

### Applicable Levels

Level 2

Level 3

KAO is treated as Level 2\.

### Data Sources

| Data | Source |
| ----- | ----- |
| Revenue | Trader GPM upload |
| GP value | Trader GPM upload |
| Customer ID | Trader GPM upload |
| Product ID | Trader GPM upload |
| Product category | Product Submissions API |
| Hierarchy | Users/Salesperson API |
| Salesperson type / level | Users/Salesperson API |

### Trader GPM Upload Format

Trader GPM upload file contains:

1. Period  
2. Sales ID  
3. Cust ID  
4. Prod ID  
5. GP  
6. Revenue

The uploaded Prod ID is the Product UUID.

Product metadata is resolved from Product Submissions API during upload processing.

The Product API response field category\_label is stored as product\_category.

### Formula

**GPM percentage calculation should aggregate first.**

total\_gp\_value \= SUM(gp\_value)

total\_revenue \= SUM(revenue)

If total\_revenue \> 0:

GPM % \= total\_gp\_value / total\_revenue × 100

If total\_revenue \= 0:

points \= 0 and flag DATA\_INVALID

If total\_revenue \< 0:

GPM % \= \-1 × ABS(total\_gp\_value / total\_revenue) × 100

Negative GP and negative revenue should not cancel each other out and produce a positive GPM percentage.

If aggregated revenue is negative, calculated GPM percentage should be negative and should go through normal slab lookup. If the calculated GPM percentage does not match any configured slab, points \= 0\. No separate low-end slab is required in Phase 1\.

Calculation Rules

For GPM All Product:

1. Use active Trader GPM activity rows for the participant, applicable reportees, and period.  
2. Include all product categories.  
3. Exclude KW / Special Choice rows only after the Product team confirms the field used to identify KW / Special Choice.  
4. Until the KW / Special Choice field is confirmed, this exclusion rule remains pending and should not be hardcoded using grade.  
5. Aggregate eligible rows for the Level 2 / Level 3 participant and applicable reportees.  
6. Calculate GPM percentage using the formula rules defined above. If aggregated revenue is negative, the calculated GPM percentage must remain negative and should go through normal slab lookup.

The column tipe\_3 is not required and should be removed from normalized GPM table and calculation logic.

The upload file does not contain grade. Filtering should not depend on grade unless Product later confirms a grade-equivalent field.

### Slab Lookup

salesperson\_type \= TRADER

incentive\_point\_code \= TR\_GPM\_ALL\_PRODUCT

level \= 2 / 3

period \= calculation month

Channel is not applicable for Trader GPM calculations.

### Edge Cases

| Scenario | Treatment |
| ----- | ----- |
| SUM(revenue) \= 0 | points \= 0 and flag DATA\_INVALID |
| revenue missing | reject row during upload validation |
| revenue is negative | allow; if aggregated revenue is negative, calculated GPM percentage should be negative and should go through normal slab lookup |
| gp\_value missing | reject row during upload validation |
| gp\_value is negative | allow and include in SUM(gp\_value) |
| product ID missing | reject row |
| product ID invalid UUID | reject row |
| product not found | reject row |
| product inactive | reject row |
| product\_category missing after lookup | reject row |
| duplicate Period \+ Sales ID \+ Cust ID \+ Prod ID in same upload | reject duplicate row |
| no eligible rows after filtering | points \= 0 |
| no matching slab | points \= 0 |
| KW / Special Choice field not confirmed | keep exclusion rule pending |

##   **7.7 B.6 Team Volume Sales**

TR\_TEAM\_VOLUME\_SALES is active for Trader Level 2 and Level 3 participants.

### **Applicable Levels**

| Level | Applicable |
| ----- | ----- |
| Level 1 | No |
| Level 2 | Yes |
| Level 3 | Yes |

Level 1 does not receive Team Volume Sales points.

KAO is treated as Level 2\.

### **Data Sources**

| Data | Source |
| ----- | ----- |
| Trader volume target | Target Engine |
| Trader actual volume | Daily Sales Feed |
| Hierarchy | Users/Salesperson API |
| User active/inactive status | Users/Salesperson API |
| Salesperson type / level | Users/Salesperson API |

### **Calculation Rules**

Team Volume Sales is calculated for Trader Level 2 and Level 3 participants.

For Level 2:

Team % \= direct active Trader Level 1 reportees with temporary Volume Achievement \>= 100% / total active direct Trader Level 1 reportees × 100

For Level 3:

Team % \= active downstream Trader Level 2 \+ Level 1 members with temporary Volume Achievement \>= 100% / total active downstream Trader Level 2 \+ Level 1 members × 100

Temporary Volume Achievement is calculated only as a helper for Trader Team Volume Sales.

It is not a separate scored Trader incentive point.

### **Eligible Member Rules**

Team Volume denominator should include all active Trader reporting members.

A member is included in the denominator if:

| Condition | Required |
| ----- | ----- |
| User is active | Yes |
| User is part of Trader reporting hierarchy | Yes |

A member should not be excluded just because:

| Scenario | Treatment |
| ----- | ----- |
| Target missing | Include in denominator; temporary Volume Achievement \= 0 |
| Target \= 0 | Include in denominator; temporary Volume Achievement \= 0 |
| Sales data missing | Include in denominator; actual volume \= 0 and temporary Volume Achievement \= 0 |
| Temporary Volume Achievement could not be calculated normally | Include in denominator; temporary Volume Achievement \= 0 |
| User inactive | Exclude |

### **Numerator Rule**

| Condition | Treatment |
| ----- | ----- |
| Temporary Volume Achievement \>= 100% | Include in numerator |
| Temporary Volume Achievement \< 100% | Do not include in numerator |
| Missing/defaulted temporary Volume Achievement | Treat as 0%; do not include in numerator |

### **Slab Lookup**

| Dimension | Value |
| ----- | ----- |
| salesperson\_type | TRADER |
| incentive\_point\_code | TR\_TEAM\_VOLUME\_SALES |
| level | 2 / 3 |
| period | calculation month |

Channel is not applicable for Trader Team Volume Sales.

### **Edge Cases**

| Scenario | Treatment |
| ----- | ----- |
| no active reportees | points \= 0 and flag NO\_TEAM |
| target missing for reportee | include in denominator; temporary Volume Achievement \= 0 |
| target \= 0 for reportee | include in denominator; temporary Volume Achievement \= 0 |
| sales data missing for reportee | include in denominator; temporary Volume Achievement \= 0 |
| inactive reportee | exclude |
| no matching slab | points \= 0 |

---

# **8\. Final Incentive Calculation**

## **8.1 Final Calculation Flow**

After all applicable incentive point calculations are completed, the finalizer calculates the final incentive amount for each participant.

The finalizer is responsible for:

1. Reading all applicable incentive point results for the participant.  
2. Summing point-producing incentive points.  
3. Looking up gross incentive from the payout table.  
4. Applying AR ageing deduction for Non-Trader participants.  
5. Storing final result snapshot.  
6. Marking older result rows as deprecated where applicable.  
7. Updating run status.

## **8.2 Total Points Calculation**

Total Points is calculated by summing all applicable point-producing incentive point results.

For Non-Trader:

Total Points \= Volume Achievement points

* % Transacted Outlets points  
* % New Transacted Outlets points  
* Team Volume Achievement points

AR Ageing Deduction is not included in Total Points because it is a deduction component, not a point component.

For Trader:

Total Points \= Stock Level — By Product points

* Stock Level — Grade points  
* Stock Level — Side Product points  
* GPM by Product points  
* GPM All Product points  
* Team Volume Sales points

Only applicable incentive points should be included. If an incentive point is not applicable to a level, it should not contribute points.

## **8.3 Gross Incentive Lookup**

Gross Incentive is calculated from the payout table using Total Points.

Payout lookup dimensions:

![][image1]

If total\_points \= 0, return payout\_amount \= 0 directly — no table lookup performed.

For total\_points \> 0, the payout table should return the matching incentive amount for the level, period, and total\_points — shared across Trader and Non-Trader.

If no payout row exists for the level and total\_points, finalization should fail with PAYOUT\_ROW\_MISSING.

Lookup uses the active payout config header (matching partner\_id, period, and status \= 'active') to resolve payout\_config\_id, then matches the active child payout row (is\_deprecated \= false) for level and total\_points.

## **8.4 Net Incentive Calculation**

For Non-Trader:

Net Incentive \= Gross Incentive \- AR Ageing Deduction

For Trader:

Net Incentive \= Gross Incentive

Trader does not have AR ageing deduction.

## **8.5 AR Ageing Deduction Application**

AR ageing deduction applies only to Non-Trader participants.

The AR ageing worker calculates the selected overdue bucket and deduction\_percentage for each Non-Trader participant.

The finalizer uses the calculated AR ageing deduction result for the participant and run.

If deduction\_percentage \> 0:

deduction\_amount \= gross\_incentive × deduction\_percentage / 100

net\_incentive \= gross\_incentive \- deduction\_amount

If deduction\_percentage \= 0:

deduction\_amount \= 0

net\_incentive \= gross\_incentive

If total\_overdue \= 0 or no overdue bucket has amount greater than 0:

deduction\_amount \= 0

net\_incentive \= gross\_incentive

Trader participants do not have AR ageing deduction.

## **8.6 Final Result Snapshot**

The final result should be stored as a snapshot so the payable output remains stable even if master data changes later.

The final result should include:

| Field | Purpose |
| ----- | ----- |
| run\_id | Calculation run reference |
| partner\_id | Partner reference |
| period\_month | Calculation month |
| period\_year | Calculation year |
| salesperson\_id | Participant ID |
| salesperson\_name | Name used during calculation |
| salesperson\_type | NON\_TRADER / TRADER |
| level | Calculation level: 1 / 2 / 3 |
| original\_role | Source role from Users API |
| channel | Channel used during calculation, mainly for Non-Trader |
| total\_points | Sum of point-producing incentive points |
| gross\_incentive | Incentive amount before deduction |
| deduction\_amount | AR ageing deduction amount, Non-Trader only |
| net\_incentive | Final payable incentive |
| status | success / skipped / failed |
| calculation\_details | JSONB audit details |

## **8.7 Why Business 1 Should Use Separate Result Tables**

Business 2 result flow is direct payout based.

Business 2:

Scheme achievement → Slab → Payout amount

Business 1 is point based.

Business 1:

Incentive point achievement → Point slab → Points  
Total points → Payout table → Gross incentive  
Gross incentive → Deduction → Net incentive

Because of this difference, Business 1 should not force-fit final results into the existing Business 2 incentive\_results table.

Reusing the existing table would require adding many Business 1-specific nullable columns and branching logic, such as:

1. incentive\_point\_code  
2. total\_points  
3. gross\_incentive  
4. deduction\_amount  
5. net\_incentive  
6. level  
7. original\_role  
8. channel  
9. point-based slab references

This would increase the risk of breaking Business 2 logic and make the result table harder to understand.

Recommended approach:

Use existing common run/logging tables where feasible, but create separate Business 1 point-result and final-result tables.

## **8.8 Result Publication and Deprecation on Recalculation**

When a recalculation happens for the same partner and period, older published result rows should not be physically deleted.

A recalculation run should not deprecate previous current results until the new run output is ready to publish.

New calculation rows should first be inserted as draft rows.

Draft rows are not visible in default result APIs.

Result tables should support publication state using:

| Field | Purpose |
| ----- | ----- |
| publication\_status | Identifies whether a result row is draft or published |
| published\_at | Timestamp when the result row became visible as published output |
| superseded\_by\_run\_id | Run that replaced this result row |
| superseded\_at | Timestamp when this result row was superseded |

Supported publication\_status values:

| Value | Meaning |
| ----- | ----- |
| draft | Result was generated by a run but is not yet visible as current output |
| published | Result is visible as calculation output |

Newly calculated result rows are inserted with:

| Field | Value |
| ----- | ----- |
| publication\_status | draft |
| is\_deprecated | false |

Default result APIs should return only:

| Field | Required value |
| ----- | ----- |
| publication\_status | published |
| is\_deprecated | false |

**Publishable Run Rule**

A run is publishable only when the run output is safe to become the latest current result.

For CRON, CATCHUP\_CRON, and MANUAL runs:

| Case | Rule |
| ----- | ----- |
| Run status is success | Publishable |
| Run status is partial | Publishable only for successfully calculated participants |
| Participant failed in partial run | Should not replace previous current successful result |
| Participant failed and has no previous current result | Remains without current payable result until recalculated successfully |
| Run fails because of required config gate failure | Not publishable |
| CRON completed | Does not lock the period |
| CATCHUP\_CRON completed | Does not lock the period |
| MANUAL after CATCHUP\_CRON | Allowed, subject to run-in-progress validation |

**Publication Transaction Rule**

Publication must happen in one database transaction.

For each participant whose new result is publishable:

| Step | Action |
| ----- | ----- |
| 1 | Mark previous published current rows for the same partner, period, and participant as deprecated |
| 2 | Set superseded\_by\_run\_id on previous rows to the new run\_id |
| 3 | Set superseded\_at on previous rows to current timestamp |
| 4 | Mark new draft rows as published |
| 5 | Set published\_at on new rows |
| 6 | Keep new rows as is\_deprecated \= false |
| 7 | Update run status |

For full-period recalculation:

| Step | Action |
| ----- | ----- |
| 1 | Create a new run\_id |
| 2 | Insert participant snapshot for the run |
| 3 | Calculate incentive point results, AR ageing deduction results, and final results under the new run\_id |
| 4 | Store all new result rows as publication\_status \= draft |
| 5 | Determine whether the run is publishable |
| 6 | If publishable, publish successful participant results using the Publication Transaction Rule |
| 7 | If not publishable, previous published current rows remain active and visible |

For scoped recalculation:

| Step | Action |
| ----- | ----- |
| 1 | Resolve the full impacted participant set |
| 2 | Recalculate only the impacted participant set |
| 3 | Store all new result rows as publication\_status \= draft |
| 4 | If publishable, publish successful participant results using the Publication Transaction Rule |
| 5 | Previous published current rows for failed participants remain active |
| 6 | Previous published current rows for non-impacted participants remain active |

This applies to:

| Table |
| ----- |
| incentive\_point\_results |
| incentive\_ar\_ageing\_deduction\_results |
| incentive\_final\_results |

Default result APIs should return only published, non-deprecated rows.

Run-specific audit/debug APIs may return draft or deprecated rows when run\_id is provided.

## **8.9 Finalizer Edge Cases**

| Scenario | Treatment |
| ----- | ----- |
| Missing applicable incentive point result | Final result should fail with INCENTIVE\_POINT\_RESULT\_MISSING. The finalizer should not silently treat a missing applicable point result as 0\. |
| Incentive point not applicable to participant level/type | Ignore it. It should not contribute to total\_points. |
| Source data missing but metric rule allows default zero | Store a point result row with points \= 0 and calculation\_details explaining the default. |
| AR deduction not applicable | deduction\_amount \= 0 |
| Trader participant | deduction\_amount \= 0 |
| Participant inactive at calculation time | Do not calculate final incentive |
| Older result exists for same partner/period/user | Follow Section 8.8 publication and deprecation rule. Older current rows should be deprecated only after the new run output is ready to publish. |

---

# **9\. External Dependencies / Integrations**

Business 1 Incentive Engine depends on the following external/internal sources for calculation data.

## **9.1 Users / Salesperson API**

Used for participant metadata, hierarchy, active/inactive status, salesperson type, level, original role, channel, and upline mapping.

There will be no dedicated hierarchy API.

Hierarchy will be built using Users API and upline\_id.

Users API supports filtering by multiple upline IDs using:

dynamic\_filters\[UPLINE\_ID\]=\[id\_1,id\_2\]

Business 1 calculation should use level for logic and store original\_role for audit/reporting.

Level mapping:

Level 1 \= SALES  
Level 2 \= SPV / KAO  
Level 3 \= RSO

KAO is treated as Level 2\.

The participant snapshot created at run start should store user metadata and hierarchy used for that run.

## **9.2 Target Engine**

Used for target values required by Business 1 calculations.

Required targets:

1. Volume target for Volume Achievement.  
2. Count-based new customer target for New Transacted Outlets.

For Volume Achievement, Level 2 and Level 3 target will be calculated by adding own target and reportee targets.

For New Transacted Outlets, the existing T2 New Customer target is changed globally from sales quantity in KG to customer count. The existing target\_value field and target\_sales\_volume\_new\_customers table continue to be used; no separate target field or table is required.

The T2 achievement logic is also changed globally. It counts distinct new customers whose monthly SUM(net\_sales\_quantity\_kg) is greater than zero instead of summing net sales quantity.

New-customer transaction data is delivered through POST /api/target/v1/webhooks/new-customer-monthly. The source identifies which customers are new, while Target Sales performs the monthly quantity aggregation required to determine which new customers are transacted.

Business 1 reads the resulting active incentive\_new\_transacted\_customer\_activity snapshot. It does not perform another Daily Sales lookup during the incentive-point calculation.

## **9.3 Daily Sales Feed**

Used for:

1. Actual volume calculation.  
2. % Transacted Outlets calculation.  
3. Trader Team Volume Sales temporary Volume Achievement calculation.

Volume is calculated in kg.

Returns appear as negative quantities and reduce achievement.

For transacted outlet calculation, sales should be summed per salesperson \+ customer \+ month. If net quantity is greater than 0, the customer is counted once.

## **9.4 Customer Management API**

The Customer Management API is used only for Customer Handled data.

nodejs-ws2closio exposes:

GET /api/incentives/v1/customer-handled?period=YYYY-MM

The endpoint counts customers from the customers table where customer\_type \= 'CUSTOMER' and deleted\_at IS NULL, grouped by customers.sales\_id.

The query starts with all non-deleted users belonging to the requested partner and left joins the customers table. This ensures that partner users with no matching customers are returned with customer\_count \= 0\.

The response contains each salesperson’s own customer count only. The Incentive Engine performs the Level 2 and Level 3 hierarchy roll-ups using the Business 1 participant hierarchy snapshot.

The endpoint does not apply incentive level, role, channel, or Trader/Non-Trader filtering.

No pagination is required in Phase 1\.

New Transacted Customer data does not come from the Customer Management API. It is delivered through POST /api/target/v1/webhooks/new-customer-monthly.

## **9.5 AR Ageing Feed**

Used for Non-Trader AR ageing deduction.

Source:

Qlik Sense / finalized finance source

AR ending balance and current amount are not required.

The feed should contain only overdue fields needed for deduction:

1. total\_overdue  
2. od\_1\_7  
3. od\_8\_14  
4. od\_15\_21  
5. od\_22\_30  
6. od\_gt\_30

AR Ageing feed stores source overdue bucket amounts only. Bucket percentage is not calculated or used for deduction selection. Deduction selection happens during AR ageing calculation by checking the highest overdue bucket amount greater than 0\.

## **9.6 Trader Stock Upload**

Used for Trader stock-level incentive points:

1. Stock Level — By Product  
2. Stock Level — Grade  
3. Stock Level — Side Product

Formula:

Stock EOM / Billing EOM × Day Multiplier

Trader stock rows should reference upload\_id / upload session, not feed\_log\_id.

Region is not required for calculation and should be removed unless needed for display/audit.

## **9.7 Trader GPM Upload**

Used for Trader GPM incentive points:

1. GPM by Product  
2. GPM All Product

Trader GPM upload file contains:

1. Period  
2. Sales ID  
3. Cust ID  
4. Prod ID  
5. GP  
6. Revenue

The uploaded Prod ID is the Product UUID.

Unique key:

partner\_id \+ period \+ sales\_id \+ cust\_id \+ prod\_id

Duplicate rows with the same unique key in the same upload should be rejected.

Product metadata is not uploaded directly in the file.

The backend resolves product metadata from Product Submissions API using PRODUCT\_ID filter.

The Product API response field category\_label should be stored as product\_category.

For GPM by Product:

product\_category \= 'BY PRODUCT'

For GPM All Product:

all product categories are included.

Formula: GPM percentage should be calculated using the formula rules defined in Sections 7.5 and 7.6.

The calculation should aggregate GP and revenue first. If aggregated revenue is negative, calculated GPM percentage should also be negative. Negative GP and negative revenue should not cancel each other out and produce a positive GPM percentage.

Negative gp\_value is allowed.

Negative revenue is allowed. If aggregated revenue is negative, calculated GPM percentage should also be negative. Negative GP and negative revenue should not cancel each other out and produce a positive GPM percentage. The negative GPM percentage should go through normal slab lookup. If the calculated GPM percentage does not match any configured slab, points \= 0\. No separate low-end slab is required in Phase 1\.

Product lookup rules:

1. Product ID must be a valid UUID.  
2. Product ID must exist in Product API.  
3. Inactive products should be rejected.  
4. Product channel validation is not required.  
5. category\_label is required because it is used as product\_category.

KW / Special Choice exclusion is still pending because the field is not yet available. The engine should not hardcode this using grade unless Product confirms a grade-equivalent field.

The tipe\_3 column should not be used.

Trader GPM rows should reference upload\_id / upload session, not feed\_log\_id.

## **9.8 Reuse of Existing Business 2 Infrastructure**

Where feasible, Business 1 should reuse existing common incentive infrastructure already used by Business 2\.

Reusable tables:

1. incentive\_run\_log  
2. incentive\_cron\_log  
3. incentive\_run\_errors

Run history and run-in-progress checks can be derived from incentive\_run\_log using run\_type and run status.

Business 1 result tables should remain separate because Business 1 uses point-based calculation and final payout lookup, while Business 2 stores direct scheme payout results.

---

# **10\. Proposed DB Schema**

All table names are proposed. Final names can be adjusted to match repository conventions.

Schema namespace:

incentives

or existing target-sales incentive schema.

This section covers Business 1 configuration and input-supporting master tables only.

Run tracking and result tables are handled separately in Section 12\.

## **10.1 incentive\_partner\_business\_mappings**

Maps each partner to the incentive business it belongs to.

This table is used by the common incentive catalogue API:

**GET /api/incentives/v1/schemas**

The API resolves partner\_id from the existing Business 2 header/request flow and uses this table to determine whether the partner belongs to BUSINESS\_1 or BUSINESS\_2.

The resolved business\_code is returned in the API response so the frontend can route to the correct business-specific API flow.

| CREATE TABLE incentive\_partner\_business\_mappings (    id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),    partner\_id UUID NOT NULL,    business\_code VARCHAR(30) NOT NULL,    status VARCHAR(20) NOT NULL DEFAULT 'active',    created\_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),    updated\_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),    created\_by UUID,    created\_by\_name VARCHAR(255),    updated\_by UUID,    updated\_by\_name VARCHAR(255), CONSTRAINT chk\_ipbm\_business\_code CHECK (    business\_code IN ('BUSINESS\_1', 'BUSINESS\_2')    ),    CONSTRAINT chk\_ipbm\_status CHECK (    status IN ('active', 'inactive')    ));CREATE UNIQUE INDEX uq\_ipbm\_partner\_business ON incentive\_partner\_business\_mappings (    partner\_id,    business\_code);CREATE UNIQUE INDEX uq\_ipbm\_partner\_active ON incentive\_partner\_business\_mappings (    partner\_id ) WHERE status \= 'active';CREATE INDEX idx\_ipbm\_business\_code ON incentive\_partner\_business\_mappings (    business\_code,    status); |
| :---- |

**Rules:**

1. Each active partner should map to exactly one active business\_code.  
2. Supported business\_code values are BUSINESS\_1 and BUSINESS\_2.  
3. The same partner cannot have two active mappings at the same time.  
4. If a partner moves from one business mapping to another, the old row should be marked inactive and a new active row should be created.  
5. GET /api/incentives/v1/schemas uses this table to resolve the business\_code for the incoming partner\_id.  
6. If no active mapping exists for the partner\_id, return PARTNER\_BUSINESS\_MAPPING\_NOT\_FOUND.  
7. If the active mapping contains an unsupported business\_code, return INVALID\_BUSINESS\_CODE.  
8. The frontend should use the returned business\_code to route to the correct Business 1 or Business 2 API flow.

Example seed data:

| INSERT INTO incentive\_partner\_business\_mappings ( partner\_id, business\_code, status, created\_at, updated\_at ) VALUES (:business\_1\_partner\_id, 'BUSINESS\_1', 'active', NOW(), NOW()), (:business\_2\_partner\_id, 'BUSINESS\_2', 'active', NOW(), NOW()); |
| :---- |

## **10.2 incentive\_point\_metrics**

Static registry for Business 1 incentive points.

This table defines the incentive points available for a partner and stores their applicability rules.

It identifies:

1. incentive point code  
2. incentive point name  
3. applicable salesperson type  
4. component type: POINT or DEDUCTION  
5. whether channel is required  
6. applicable levels

| CREATE TABLE incentive\_point\_metrics (  id                    UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  partner\_id            UUID NOT NULL,  incentive\_point\_code  VARCHAR(100) NOT NULL,  incentive\_point\_name  VARCHAR(255) NOT NULL,  description VARCHAR(255) NOT NULL,  applicable\_salesperson\_type      VARCHAR(30)\[\] NOT NULL,  component\_type        VARCHAR(20) NOT NULL,  requires\_channel      BOOLEAN NOT NULL DEFAULT false,  applicable\_levels     JSONB NOT NULL DEFAULT '\[\]'::jsonb,  status                VARCHAR(20) NOT NULL DEFAULT 'active',  created\_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),  created\_by UUID,  updated\_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),  updated\_by UUID,  CONSTRAINT chk\_ipm\_applicable\_salesperson\_type CHECK (    applicable\_salesperson\_type \<@ ARRAY\['NON\_TRADER','TRADER'\]::VARCHAR(30)\[\]    AND array\_length(applicable\_salesperson\_type, 1\) \> 0  ),  CONSTRAINT chk\_ipm\_status CHECK (    status IN ('active', 'inactive')  ),  CONSTRAINT chk\_ipm\_levels\_array CHECK (    jsonb\_typeof(applicable\_levels) \= 'array'  ),  CONSTRAINT uq\_ipm\_partner\_code UNIQUE (    partner\_id,    incentive\_point\_code  ),  CONSTRAINT chk\_ipm\_component\_type CHECK (    component\_type IN ('POINT', 'DEDUCTION')  ));CREATE INDEX idx\_ipm\_partner\_status  ON incentive\_point\_metrics(partner\_id, status);\-- GIN index needed for array containment lookups (@\>, \<@, &&)CREATE INDEX idx\_ipm\_applicable\_salesperson\_type\_gin  ON incentive\_point\_metrics USING GIN (applicable\_salesperson\_type); |
| :---- |

Seeder values \-

| incentive\_point\_code | incentive\_point\_name | applicable\_salesperson\_type | component\_type | requires\_channel | applicable\_levels |
| ----- | ----- | ----- | ----- | ----- | ----- |
| NT\_VOLUME\_ACHIEVEMENT | Volume Achievement | \['NON\_TRADER'\] | POINT | true | \[1,2,3\] |
| NT\_TRANSACTED\_OUTLETS | % Transacted Outlets | \['NON\_TRADER'\] | POINT | true | \[1,2,3\] |
| NT\_NEW\_TRANSACTED\_OUTLETS | % New Transacted Outlets | \['NON\_TRADER'\] | POINT | true | \[1,2,3\] |
| NT\_TEAM\_VOLUME\_ACHIEVEMENT | Team Volume Achievement | \['NON\_TRADER'\] | POINT | true | \[2,3\] |
| NT\_AR\_AGEING\_DEDUCTION | AR Ageing Deduction | \['NON\_TRADER'\] | DEDUCTION | true | \[1,2,3\] |
| TR\_STOCK\_BY\_PRODUCT | Stock Level \- By Product | \['TRADER'\] | POINT | false | \[1,2,3\] |
| TR\_STOCK\_GRADE | Stock Level \- Grade | \['TRADER'\] | POINT | false | \[1,2,3\] |
| TR\_STOCK\_SIDE\_PRODUCT | Stock Level \- Side Product | \['TRADER'\] | POINT | false | \[1,2,3\] |
| TR\_GPM\_BY\_PRODUCT | GPM by Product | \['TRADER'\] | POINT | false | \[1\] |
| TR\_GPM\_ALL\_PRODUCT | GPM All Product | \['TRADER'\] | POINT | false | \[2,3\] |
| TR\_TEAM\_VOLUME\_SALES | Team Volume Sales | \['TRADER'\] | POINT | false | \[2,3\] |

| Example applicable\_levels:Level 1 \= SALESLevel 2 \= SPV / KAOLevel 3 \= RSO\-- Example values\[1, 2, 3\]\[2, 3\]\[1\] |
| :---- |

## **10.3 Incentive Point Slab Configuration Model**

For this module we will use already existing table \- incentive\_schema\_configs

**Add:**

* partner\_id UUID  
* incentive\_point\_metric\_id UUID (FK → incentive\_point\_metrics)

**Modify:**

* schema\_id → nullable

**Add constraint \+ index:**

| ALTER TABLE incentive\_schema\_configs  ADD COLUMN partner\_id UUID,  ADD COLUMN incentive\_point\_metric\_id UUID    REFERENCES incentive\_point\_metrics(id) ON DELETE RESTRICT;ALTER TABLE incentive\_schema\_configs  ALTER COLUMN schema\_id DROP NOT NULL;ALTER TABLE incentive\_schema\_configs  ADD CONSTRAINT chk\_isc\_one\_ref CHECK (    (schema\_id IS NOT NULL) \<\> (incentive\_point\_metric\_id IS NOT NULL)  );CREATE UNIQUE INDEX uq\_isc\_b1\_set  ON incentive\_schema\_configs(incentive\_point\_metric\_id, valid\_from, valid\_to)  WHERE incentive\_point\_metric\_id IS NOT NULL;CREATE EXTENSION IF NOT EXISTS btree\_gist;ALTER TABLE incentive\_schema\_configsADD CONSTRAINT excl\_isc\_no\_active\_overlapEXCLUDE USING gist (  incentive\_point\_metric\_id WITH \=,  daterange(valid\_from, valid\_to, '\[\]') WITH &&)WHERE (status \= 'active' AND incentive\_point\_metric\_id IS NOT NULL); |
| :---- |

## **10.4 incentive\_point\_slabs**

Slabs are applicable only for incentive point metrics where component\_type \= POINT.

Deduction components such as NT\_AR\_AGEING\_DEDUCTION should not have rows in incentive\_point\_slabs. Deduction components should use their dedicated deduction configuration tables.

If an admin attempts to create slab configuration for an incentive point where component\_type \= DEDUCTION, backend should reject the request with SLAB\_NOT\_ALLOWED\_FOR\_DEDUCTION\_COMPONENT.

This keeps slab lookup simple and avoids an additional join during calculation.

| CREATE TABLE incentive\_point\_slabs (   id                        UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),   partner\_id                UUID NOT NULL,   incentive\_point\_metric\_id UUID NOT NULL     REFERENCES incentive\_point\_metrics(id)     ON DELETE RESTRICT,   slab\_config\_id            UUID NOT NULL     REFERENCES incentive\_schema\_configs(id)     ON DELETE RESTRICT,   salesperson\_type VARCHAR(20) NOT NULL,   level SMALLINT NOT NULL,   channel                   VARCHAR(100),   band\_order                INTEGER NOT NULL,   operator                  VARCHAR(5) NOT NULL,   value                     NUMERIC(15,4) NOT NULL,   points                    INTEGER NOT NULL DEFAULT 0,   is\_deprecated             BOOLEAN NOT NULL DEFAULT false,   created\_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),   updated\_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),   CONSTRAINT chk\_ips\_salesperson\_type CHECK (     salesperson\_type IN ('NON\_TRADER', 'TRADER')   ),   CONSTRAINT chk\_ips\_level CHECK (     level IN (1, 2, 3\)   ),   CONSTRAINT chk\_ips\_operator CHECK (     operator IN ('\>', '\>=', '=')   ),   CONSTRAINT chk\_ips\_points CHECK (     points \>= 0   ) );CREATE INDEX idx\_ips\_lookup ON incentive\_point\_slabs(   partner\_id, incentive\_point\_metric\_id, slab\_config\_id,   salesperson\_type, level, channel, is\_deprecated ); |
| :---- |

Slab evaluation rule:

1. Resolve incentive point from incentive\_point\_metrics using partner\_id and incentive\_point\_code.  
2. Resolve active slab\_config from incentive\_schema\_configs using incentive\_point\_metric\_id, partner\_id, calculation period, and status \= active. The exclusion constraint excl\_isc\_no\_active\_overlap guarantees this resolution returns at most one row — no application-level tie-break for header selection is required.  
3. Resolve active slab rows from incentive\_point\_slabs using slab\_config\_id, salesperson\_type, level, channel, and is\_deprecated \= false.  
4. Match the achievement value against each slab row using operator \+ value.  
5. More than one slab row may match the same achievement value. This is expected for ordered threshold slabs.  
6. If multiple rows match, select the matching row with the highest points.  
7. If multiple matching rows have the same highest points, select the row with the lowest band\_order.  
8. If there is still a tie, select the earliest created row/id to keep the result deterministic.  
9. Return selected slab row as matched\_slab\_id and selected row’s points.  
10. If no row matches, return matched\_slab\_id \= null and points \= 0.  
11. No matching slab row is not a calculation failure.

Parent slab configuration is identified by:

1. partner\_id  
2. incentive\_point\_metric\_id  
3. valid\_from  
4. Valid\_to  (period/status live on incentive\_schema\_configs; salesperson\_type \+ channel scope slab rows within it)  
5. status

Slab rows inside the parent config are evaluated by group:

1. slab\_config\_id  
2. salesperson\_type  
3. level  
4. channel

Backend validation should enforce only structural correctness:

1. band\_order must be unique within the same slab evaluation group.  
2. Duplicate operator \+ value rows are not allowed within the same slab evaluation group.  
3. operator must be supported.  
4. value must be numeric.  
5. points must be an integer greater than or equal to 0\.  
6. salesperson\_type, level, and channel must be valid and applicable for the selected incentive point.

A slab evaluation group is identified by:

1. slab\_config\_id  
2. salesperson\_type  
3. level  
4. channel

For incentive points where incentive\_point\_metrics.requires\_channel \= false, channel must be null or omitted in incentive\_point\_slabs. requires\_channel is the sole source of truth for channel applicability — salesperson\_type must not be used to infer it.

## **10.5 incentive\_score\_payout\_configs**

Period-level total points-to-payout config.

Defines the active payout configuration for a validity period.

Business 1 converts total points into gross incentive amount using this payout setup.

| CREATE TABLE incentive\_score\_payout\_configs ( id                  UUID PRIMARY KEY DEFAULT gen\_random\_uuid(), partner\_id          UUID NOT NULL, salesperson\_type    VARCHAR(30) NOT NULL DEFAULT 'ALL', valid\_from          DATE NOT NULL, valid\_to            DATE NOT NULL, status              VARCHAR(20) NOT NULL DEFAULT 'active', created\_by          UUID, created\_by\_name     VARCHAR(255), updated\_by          UUID, updated\_by\_name     VARCHAR(255), created\_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated\_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT chk\_ispc\_salesperson\_type CHECK (   salesperson\_type \= 'ALL' ), CONSTRAINT chk\_ispc\_period CHECK (   valid\_to \>= valid\_from ), CONSTRAINT chk\_ispc\_status CHECK (   status IN ('active', 'inactive') ));CREATE INDEX idx\_ispc\_lookup ON incentive\_score\_payout\_configs(   partner\_id,   salesperson\_type,   valid\_from,   valid\_to ) WHERE status \= 'active';ALTER TABLE incentive\_score\_payout\_configsADD CONSTRAINT excl\_ispc\_no\_active\_overlapEXCLUDE USING gist (  partner\_id WITH \=,  salesperson\_type WITH \=,  daterange(valid\_from, valid\_to, '\[\]') WITH &&)WHERE (status \= 'active'); |
| :---- |

For Phase 1, active payout configs should use salesperson\_type \= 'ALL'.

ALL means the payout config applies to both Trader and Non-Trader participants.

Active payout configs use salesperson\_type \= 'ALL'.

Only one active ALL payout config should exist for the same partner and overlapping period.

## **10.6 incentive\_score\_payouts**

Stores total points-to-payout rows per level.

Payout rows are configured per calculation level:

1. Level 1 \= SALES  
2. Level 2 \= SPV / KAO  
3. Level 3 \= RSO

| CREATE TABLE incentive\_score\_payouts (  id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  payout\_config\_id UUID NOT NULL    REFERENCES incentive\_score\_payout\_configs(id)    ON DELETE RESTRICT,  level SMALLINT NOT NULL,  total\_points INTEGER NOT NULL,  payout\_amount NUMERIC(15,2) NOT NULL,  is\_deprecated BOOLEAN NOT NULL DEFAULT false,  created\_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),  created\_by UUID,  updated\_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),  updated\_by UUID,  CONSTRAINT chk\_isp\_level CHECK (level IN (1, 2, 3)),  CONSTRAINT chk\_isp\_total\_points CHECK (total\_points \> 0),  CONSTRAINT chk\_isp\_payout\_amount CHECK (payout\_amount \>= 0));\-- was table-level CONSTRAINT UNIQUE; moved to a partial index since\-- Postgres UNIQUE constraints can't carry a WHERE clauseCREATE UNIQUE INDEX uq\_isp\_config\_level\_points  ON incentive\_score\_payouts(payout\_config\_id, level, total\_points)  WHERE is\_deprecated \= false;CREATE INDEX idx\_isp\_config\_lookup  ON incentive\_score\_payouts(payout\_config\_id, level, total\_points)  WHERE is\_deprecated \= false; |
| :---- |

Payout rows are shared across Trader and Non-Trader — one row per (level, total\_points), no salesperson\_type distinction at this level. If Trader/Non-Trader payout ever needs to diverge, salesperson\_type will be added at the incentive\_score\_payout\_configs (header) level instead — replacing the constant 'ALL' value — not re-added here.

PATCH replace-semantics: existing active rows are marked is\_deprecated \= true rather than hard-deleted; new rows are inserted with is\_deprecated \= false. This avoids breaking incentive\_final\_results.payout\_row\_id FK references from past runs

total\_points \= 0 is **not stored**. tier count will be counted as:

| SELECT payout\_config\_id, COUNT(DISTINCT total\_points) AS tier\_countFROM incentive\_score\_payoutsWHERE payout\_config\_id \= ANY(:config\_ids)AND is\_deprecated \= falseGROUP BY payout\_config\_id; |
| :---- |

A config with no rows yet won't appear in this result — default to tier\_count: 0 for any missing config\_id when mapping back.

Level mapping:

Level 1 \= SALES  
Level 2 \= SPV / KAO  
Level 3 \= RSO

## **10.7 ar\_ageing\_deduction\_configs**

Period-level AR ageing deduction configuration header.

This table represents one AR ageing configuration for a partner and validity period.

The config header is not channel-specific. One config can contain multiple channels and multiple Non-Trader level groups through child rule rows.

AR ageing applies only to Non-Trader participants, but salesperson\_type is not stored on the header because the header represents the whole period-level AR config. The Non-Trader level scope is stored in child rule rows.

This table no longer stores threshold\_percentage because AR deduction is no longer selected using bucket percentage threshold logic. Deduction is now selected using the highest overdue-day window that has overdue amount greater than 0\.

| CREATE TABLE ar\_ageing\_deduction\_configs ( id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(), partner\_id UUID NOT NULL, valid\_from DATE NOT NULL, valid\_to DATE NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'active', created\_by UUID, created\_by\_name VARCHAR(255), updated\_by UUID, updated\_by\_name VARCHAR(255), created\_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated\_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),CONSTRAINT chk\_aadc\_period CHECK ( valid\_to \>= valid\_from ),CONSTRAINT chk\_aadc\_status CHECK ( status IN ('active', 'inactive') ) );CREATE INDEX idx\_aadc\_lookup ON ar\_ageing\_deduction\_configs( partner\_id, valid\_from, valid\_to ) WHERE status \= 'active';ALTER TABLE ar\_ageing\_deduction\_configs ADD CONSTRAINT excl\_aadc\_no\_active\_overlap EXCLUDE USING gist ( partner\_id WITH \=, daterange(valid\_from, valid\_to, '\[\]') WITH && ) WHERE (status \= 'active'); |
| :---- |

Rules:

1. One active AR ageing config can exist for a partner and overlapping validity period (but only one can be active at any given point of time).  
2. The config header applies to the full Overdue Date config shown in the UI.  
3. Channels are not stored on the header. Channels are stored in child rule rows.  
4. Salesman type / level is not stored on the header. It is stored in child rule rows.  
5. threshold\_percentage is not stored because threshold-percentage based deduction selection is no longer used.  
6. Status applies to the whole config header.  
7. Deactivating the config header disables all child rules during calculation lookup.  
8. Config changes are rejected when a Business 1 calculation run is pending or processing for the same partner and impacted period.  
9. Existing calculated results are not automatically recalculated after config change.

## **10.8 ar\_ageing\_deduction\_buckets and ar\_ageing\_deduction\_rules**

AR ageing uses fixed overdue-day windows.

The bucket master stores fixed bucket code, display name, operator, overdue-day threshold, and priority.

Admin cannot edit bucket priority, operator, or overdue-day threshold.

Admin can only configure deduction\_percentage for each fixed overdue-day window under a channel \+ Non-Trader level group.

The engine evaluates overdue windows by priority and applies the deduction\_percentage of the first matching window.

Matching is based on aggregated source overdue amount, not bucket percentage.

### **10.8.1 ar\_ageing\_buckets**

Seeded bucket master.

| CREATE TABLE ar\_ageing\_buckets ( id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(), bucket\_code VARCHAR(30) NOT NULL UNIQUE, bucket\_name VARCHAR(100) NOT NULL, operator VARCHAR(5) NOT NULL DEFAULT '\>', overdue\_days INTEGER NOT NULL, priority INTEGER NOT NULL, status VARCHAR(20) NOT NULL DEFAULT 'active', created\_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated\_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),CONSTRAINT chk\_aab\_bucket\_code CHECK ( bucket\_code IN ( 'OD\_GT\_30', 'OD\_GT\_21', 'OD\_GT\_14', 'OD\_GT\_7', 'OD\_GT\_0' ) ),CONSTRAINT chk\_aab\_operator CHECK ( operator \= '\>' ),CONSTRAINT chk\_aab\_overdue\_days CHECK ( overdue\_days IN (0, 7, 14, 21, 30\) ),CONSTRAINT chk\_aab\_priority CHECK ( priority \> 0 ),CONSTRAINT chk\_aab\_status CHECK ( status IN ('active', 'inactive') ) );CREATE UNIQUE INDEX uq\_aab\_priority ON ar\_ageing\_buckets(priority) WHERE status \= 'active';Seed data:INSERT INTO ar\_ageing\_buckets ( bucket\_code, bucket\_name, operator, overdue\_days, priority ) VALUES ('OD\_GT\_30', 'OD \> 30', '\>', 30, 1), ('OD\_GT\_21', 'OD \> 21', '\>', 21, 2), ('OD\_GT\_14', 'OD \> 14', '\>', 14, 3), ('OD\_GT\_7', 'OD \> 7', '\>', 7, 4), ('OD\_GT\_0', 'OD \> 0', '\>', 0, 5); |
| :---- |

**Rules:**

1. Bucket priority is fixed by backend.  
2. Operator is fixed as `>`.  
3. overdue\_days is fixed.  
4. Admin cannot edit bucket\_code, operator, overdue\_days, or priority.  
5. CURRENT bucket is not used.  
6. Old config/result bucket codes should not be used:  
    OD\_1\_7  
    OD\_8\_14  
    OD\_15\_21  
    OD\_22\_30  
7. Source feed columns still remain:  
    od\_1\_7  
    od\_8\_14  
    od\_15\_21  
    od\_22\_30  
    od\_gt\_30  
8. During calculation, source feed columns are mapped to configured bucket codes:  
    od\_1\_7 → OD\_GT\_0  
    od\_8\_14 → OD\_GT\_7  
    od\_15\_21 → OD\_GT\_14  
    od\_22\_30 → OD\_GT\_21  
    od\_gt\_30 → OD\_GT\_30

### **10.8.2 ar\_ageing\_deduction\_rules**

Stores deduction percentage per AR ageing config, channel, Non-Trader level, and overdue-day window.

This table replaces ar\_ageing\_deduction\_bucket\_configs.

The old table stored only deduction percentage per config \+ bucket. That is no longer enough because the new UI configures deduction rules per channel and salesman type / level.

| CREATE TABLE ar\_ageing\_deduction\_rules ( id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(), deduction\_config\_id UUID NOT NULL REFERENCES ar\_ageing\_deduction\_configs(id) ON DELETE RESTRICT,channel VARCHAR(100) NOT NULL,salesperson\_type VARCHAR(30) NOT NULL DEFAULT 'NON\_TRADER',level SMALLINT NOT NULL,bucket\_id UUID NOT NULL REFERENCES ar\_ageing\_buckets(id) ON DELETE RESTRICT,bucket\_code VARCHAR(30) NOT NULL,deduction\_percentage NUMERIC(8,4) NOT NULL,is\_deprecated BOOLEAN NOT NULL DEFAULT false,created\_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), created\_by UUID, updated\_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated\_by UUID,CONSTRAINT chk\_aadr\_salesperson\_type CHECK ( salesperson\_type \= 'NON\_TRADER' ),CONSTRAINT chk\_aadr\_level CHECK ( level IN (1, 2, 3) ),CONSTRAINT chk\_aadr\_bucket\_code CHECK ( bucket\_code IN ( 'OD\_GT\_30', 'OD\_GT\_21', 'OD\_GT\_14', 'OD\_GT\_7', 'OD\_GT\_0' ) ),CONSTRAINT chk\_aadr\_deduction\_percentage CHECK ( deduction\_percentage BETWEEN 0 AND 100 ) );CREATE UNIQUE INDEX uq\_aadr\_active\_rule ON ar\_ageing\_deduction\_rules( deduction\_config\_id, channel, salesperson\_type, level, bucket\_code ) WHERE is\_deprecated \= false;CREATE INDEX idx\_aadr\_lookup ON ar\_ageing\_deduction\_rules( deduction\_config\_id, channel, salesperson\_type, level, bucket\_code ) WHERE is\_deprecated \= false; |
| :---- |

**Rules:**

1. AR ageing rules apply only to Non-Trader.  
2. Each channel \+ level group must have exactly five active bucket rules:  
    OD\_GT\_0  
    OD\_GT\_7  
    OD\_GT\_14  
    OD\_GT\_21  
    OD\_GT\_30  
3. Duplicate channel \+ level \+ bucket\_code rows are not allowed within the same deduction\_config\_id.  
4. Same level can exist under different channels.  
5. Same channel can contain multiple levels.  
6. Same channel cannot be duplicated in the same API request.  
7. Same level cannot be duplicated under the same channel in the same API request.  
8. deduction\_percentage is stored as a positive number. Example: 20 means deduct 20% from gross incentive.  
9. PATCH rule replacement should not hard-delete old rows.  
10. PATCH rule replacement should mark existing active rules as is\_deprecated \= true and insert new active rules.  
11. Calculation lookup should read only is\_deprecated \= false rows.  
12. If a calculated AR deduction result references a rule row, that rule row must remain available for historical audit even if later deprecated.

## **10.9 trader\_stock\_days\_multiplier\_configs**

Used for Trader stock-level calculation.

Defines the day multiplier used for Trader stock-level calculations.

| CREATE TABLE trader\_stock\_days\_multiplier\_configs ( id                  UUID PRIMARY KEY DEFAULT gen\_random\_uuid(), partner\_id          UUID NOT NULL, multiplier\_days     NUMERIC(8,2) NOT NULL DEFAULT 30, valid\_from          DATE NOT NULL, valid\_to            DATE, status              VARCHAR(20) NOT NULL DEFAULT 'active', created\_by          UUID, created\_by\_name     VARCHAR(255), updated\_by          UUID, updated\_by\_name     VARCHAR(255), created\_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated\_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT chk\_tsdmc\_multiplier CHECK (   multiplier\_days \> 0 ), CONSTRAINT chk\_tsdmc\_period CHECK (   valid\_to IS NULL OR valid\_to \>= valid\_from ), CONSTRAINT chk\_tsdmc\_status CHECK (   status IN ('active', 'inactive') ));CREATE INDEX idx\_tsdmc\_lookup ON trader\_stock\_days\_multiplier\_configs(   partner\_id,   valid\_from,   valid\_to ) WHERE status \= 'active'; ALTER TABLE trader\_stock\_days\_multiplier\_configsADD CONSTRAINT excl\_tsdmc\_no\_active\_overlapEXCLUDE USING gist (  partner\_id WITH \=,  daterange(valid\_from, valid\_to, '\[\]') WITH &&)WHERE (status \= 'active'); |
| :---- |

**Recommended default:** 30

**Formula:** stock\_level\_days \= stock\_eom / billing\_eom × multiplier\_days

# **11\. Feed / Input Tables**

Business 1 uses three input patterns:

Pull-based monthly refresh from an upstream API:

* Customer Handled

Push-based monthly feed ingestion:

* New Customer Monthly  
* AR Ageing

Admin-uploaded Trader CSV files:

* Trader Stock  
* Trader GPM

Customer Handled is pulled by ws2targetsalesincentive from ws2closio.

New Customer Monthly data is pushed by the finalized source system through the existing S2S webhook.

incentive\_feed\_logs tracks Customer Handled refreshes, New Customer Monthly ingestion, and AR Ageing ingestion.

Trader Stock and Trader GPM uploads use incentive\_upload\_sessions. Their activity rows reference upload\_id rather than feed\_log\_id.

Neither Customer Handled nor New Customer Monthly uses Trader upload tables or S3.

## **11.1 incentive\_feed\_logs**

Generic log table for Business 1 monthly input ingestion/refresh events.

Applicable feed types:

1. CUSTOMER\_HANDLED  
2. NEW\_TRANSACTED\_CUSTOMERS  
3. AR\_AGEING

Customer Handled is logged as a monthly Customer Management pull refresh. New Transacted Customers are logged as a monthly new-customer webhook ingestion.

For CUSTOMER\_HANDLED and NEW\_TRANSACTED\_CUSTOMERS feed logs, s3\_key remains null.

AR Ageing is logged as a monthly pushed feed event.

For AR Ageing, the original CSV is uploaded to S3 and s3\_key is stored.

Trader stock and Trader GPM uploads should not use this table as their parent reference.

CREATE TABLE incentive\_feed\_logs (  
id                  UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
partner\_id          UUID NOT NULL,  
feed\_type           VARCHAR(100) NOT NULL,  
period\_month        INTEGER NOT NULL,  
period\_year         INTEGER NOT NULL,  
file\_name           VARCHAR(255),  
s3\_bucket           TEXT,  
s3\_key              TEXT,  
status              VARCHAR(30) NOT NULL DEFAULT 'pending',  
total\_rows          INTEGER DEFAULT 0,  
accepted\_rows       INTEGER DEFAULT 0,  
rejected\_rows       INTEGER DEFAULT 0,  
error\_details       JSONB,  
replaces\_feed\_log\_id UUID  
  REFERENCES incentive\_feed\_logs(id)  
  ON DELETE SET NULL,  
completed\_at        TIMESTAMPTZ,  
created\_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),  
updated\_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),  
created\_by          UUID,  
created\_by\_name     VARCHAR(255),  
updated\_by          UUID,  
updated\_by\_name     VARCHAR(255),

CONSTRAINT chk\_b1\_feed\_type CHECK (  
  feed\_type IN (  
    'CUSTOMER\_HANDLED',  
    'NEW\_TRANSACTED\_CUSTOMERS',  
    'AR\_AGEING'  
  )  
),

CONSTRAINT chk\_b1\_feed\_status CHECK (  
  status IN (  
    'pending',  
    'processing',  
    'success',  
    'failed'  
  )  
),

CONSTRAINT chk\_b1\_feed\_month CHECK (  
  period\_month BETWEEN 1 AND 12  
)  
);

CREATE INDEX idx\_b1\_feed\_logs\_lookup  
ON incentive\_feed\_logs(  
  partner\_id,  
  feed\_type,  
  period\_month,  
  period\_year,  
  status  
);

CREATE INDEX idx\_b1\_feed\_logs\_processing  
ON incentive\_feed\_logs(status, created\_at)  
WHERE status IN ('pending', 'processing');

Status and row counts in incentive\_feed\_logs are updated after validation and persistence into the respective input table completes.

On successful replacement, previous active input rows for the same partner, period, and feed type are marked replaced/inactive before latest rows are inserted as active.

If validation or processing fails, previous active rows remain unchanged.

Replacement is rejected when a Business 1 calculation run is pending or processing for the same partner and period. Customer Handled and New Transacted Customer replacement are additionally rejected after a successful CATCHUP\_CRON run for the period.

Trader stock and Trader GPM uploads do not use incentive\_feed\_logs. They use incentive\_upload\_sessions.

---

## **11.2 incentive\_customer\_handled\_snapshots**

Stores Customer Management handled customer counts.

The source provides its own customer count only.

Level 2 and Level 3 roll-up is done by the Incentive Engine using the participant hierarchy snapshot.

CREATE TABLE incentive\_customer\_handled\_snapshots (  
id                  UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
feed\_log\_id         UUID NOT NULL  
  REFERENCES incentive\_feed\_logs(id)  
  ON DELETE RESTRICT,

partner\_id          UUID NOT NULL,  
period\_month        INTEGER NOT NULL,  
period\_year         INTEGER NOT NULL,  
salesperson\_id      UUID NOT NULL,  
customer\_count      INTEGER NOT NULL,  
row\_status          VARCHAR(30) NOT NULL DEFAULT 'active',  
replaced\_by\_feed\_log\_id UUID  
  REFERENCES incentive\_feed\_logs(id)  
  ON DELETE SET NULL,  
replaced\_at         TIMESTAMPTZ,  
is\_active           BOOLEAN NOT NULL DEFAULT true,  
created\_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),  
updated\_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

CONSTRAINT chk\_b1\_ch\_month CHECK (  
  period\_month BETWEEN 1 AND 12  
),

CONSTRAINT chk\_b1\_ch\_customer\_count CHECK (  
  customer\_count \>= 0  
),

CONSTRAINT chk\_b1\_ch\_row\_status CHECK (  
  row\_status IN ('active', 'replaced')  
),

CONSTRAINT chk\_b1\_ch\_lifecycle\_consistency CHECK (  
  (row\_status \= 'active' AND is\_active \= true)  
  OR  
  (row\_status \= 'replaced' AND is\_active \= false)  
)  
);

CREATE UNIQUE INDEX uq\_b1\_customer\_handled\_active  
ON incentive\_customer\_handled\_snapshots(  
  partner\_id,  
  period\_month,  
  period\_year,  
  salesperson\_id  
)  
WHERE is\_active \= true;

CREATE INDEX idx\_b1\_customer\_handled\_lookup  
ON incentive\_customer\_handled\_snapshots(  
  partner\_id,  
  period\_month,  
  period\_year,  
  salesperson\_id  
)  
WHERE is\_active \= true;

On refresh, all previous active rows for the same partner and period are marked:

row\_status \= replaced  
 is\_active \= false  
 replaced\_by\_feed\_log\_id \= latest\_feed\_log\_id  
 replaced\_at \= NOW()

Then latest rows are inserted as fresh active rows.

No row-by-row comparison is required.

## **11.3 incentive\_new\_transacted\_customer\_activity**

Stores qualifying monthly New Transacted Customer activity derived from the New Customer Monthly feed received through POST /api/target/v1/webhooks/new-customer-monthly.

The source identifies which customers are new. Target Sales groups their transaction rows by salesperson and customer, calculates monthly\_net\_sales\_quantity, and stores only customers whose monthly quantity is greater than zero.

Incentive Engine does not perform a Daily Sales check for this incentive point.

DB storage remains one row per salesperson \+ customer.

CREATE TABLE incentive\_new\_transacted\_customer\_activity (  
id                  UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
feed\_log\_id         UUID NOT NULL  
  REFERENCES incentive\_feed\_logs(id)  
  ON DELETE RESTRICT,

partner\_id          UUID NOT NULL,  
period\_month        INTEGER NOT NULL,  
period\_year         INTEGER NOT NULL,  
salesperson\_id      UUID NOT NULL,

monthly\_net\_sales\_quantity NUMERIC(18,2) NOT NULL,

customer\_id         VARCHAR(100) NOT NULL,  
row\_status          VARCHAR(30) NOT NULL DEFAULT 'active',  
replaced\_by\_feed\_log\_id UUID  
  REFERENCES incentive\_feed\_logs(id)  
  ON DELETE SET NULL,  
replaced\_at         TIMESTAMPTZ,  
is\_active           BOOLEAN NOT NULL DEFAULT true,  
created\_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),  
updated\_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

CONSTRAINT chk\_b1\_new\_transacted\_customer\_month CHECK (  
  period\_month BETWEEN 1 AND 12  
),

CONSTRAINT chk\_b1\_new\_transacted\_customer\_positive\_quantity CHECK (  
monthly\_net\_sales\_quantity \> 0  
),

CONSTRAINT chk\_b1\_new\_transacted\_customer\_row\_status CHECK (  
 row\_status IN ('active', 'replaced')  
),

CONSTRAINT chk\_b1\_new\_transacted\_customer\_lifecycle\_consistency CHECK (  
 (row\_status \= 'active' AND is\_active \= true)  
 OR  
 (row\_status \= 'replaced' AND is\_active \= false)  
)  
);

CREATE UNIQUE INDEX uq\_b1\_new\_transacted\_customer\_active  
ON incentive\_new\_transacted\_customer\_activity(  
  partner\_id,  
  period\_month,  
  period\_year,  
  salesperson\_id,  
  customer\_id  
)  
WHERE is\_active \= true;

CREATE UNIQUE INDEX uq\_b1\_new\_transacted\_customer\_customer\_active  
ON incentive\_new\_transacted\_customer\_activity(  
partner\_id,  
period\_month,  
period\_year,  
customer\_id  
)  
WHERE is\_active \= true;

CREATE INDEX idx\_b1\_new\_transacted\_customer\_lookup  
ON incentive\_new\_transacted\_customer\_activity(  
  partner\_id,  
  period\_month,  
  period\_year,  
  salesperson\_id  
)  
WHERE is\_active \= true;

Duplicate active rows should not exist because refresh uses full replacement.

On refresh, all previous active rows for the same partner and period are marked replaced/inactive before latest rows are inserted.

Multiple transaction rows for the same salesperson and customer are valid and are aggregated. Exact duplicate transaction events must not contribute more than once.

Where the same customer is assigned to multiple salespeople, all rows for that customer are excluded and flagged. Other valid customers may still be activated.

Business 1 calculation reads only active rows from incentive\_new\_transacted\_customer\_activity. It does not read processed\_new\_customer\_events directly.

Only qualifying aggregated rows with monthly\_net\_sales\_quantity greater than zero are stored as active achievement rows.

## **11.4 incentive\_ar\_ageing\_activity**

Stores AR ageing feed rows.

AR Ageing is a push-based feed.

The original AR Ageing CSV is uploaded to S3 before worker processing.

There can be multiple rows for a single salesperson.

Salesperson \+ customer should be unique for a partner and period.

Uses customer\_id as the customer identifier.

AR ending balance and current amount are not stored because they are not required for AR ageing deduction calculation.

CREATE TABLE incentive\_ar\_ageing\_activity (  
id                    UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
feed\_log\_id           UUID NOT NULL  
  REFERENCES incentive\_feed\_logs(id)  
  ON DELETE RESTRICT,

partner\_id            UUID NOT NULL,  
period\_month          INTEGER NOT NULL,  
period\_year           INTEGER NOT NULL,  
salesperson\_id        UUID NOT NULL,  
channel               VARCHAR(100) NOT NULL,  
customer\_id           VARCHAR(100) NOT NULL,  
total\_overdue         NUMERIC(18,2) NOT NULL DEFAULT 0,  
od\_1\_7                NUMERIC(18,2) NOT NULL DEFAULT 0,  
od\_8\_14               NUMERIC(18,2) NOT NULL DEFAULT 0,  
od\_15\_21              NUMERIC(18,2) NOT NULL DEFAULT 0,  
od\_22\_30              NUMERIC(18,2) NOT NULL DEFAULT 0,  
od\_gt\_30              NUMERIC(18,2) NOT NULL DEFAULT 0,  
row\_status            VARCHAR(30) NOT NULL DEFAULT 'active',  
replaced\_by\_feed\_log\_id UUID  
  REFERENCES incentive\_feed\_logs(id)  
  ON DELETE SET NULL,  
replaced\_at           TIMESTAMPTZ,  
is\_active             BOOLEAN NOT NULL DEFAULT true,  
created\_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),  
updated\_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

CONSTRAINT chk\_b1\_ageing\_month CHECK (  
  period\_month BETWEEN 1 AND 12  
),

CONSTRAINT chk\_b1\_ageing\_non\_negative CHECK (  
  total\_overdue \>= 0  
  AND od\_1\_7 \>= 0  
  AND od\_8\_14 \>= 0  
  AND od\_15\_21 \>= 0  
  AND od\_22\_30 \>= 0  
  AND od\_gt\_30 \>= 0  
),

CONSTRAINT chk\_b1\_ageing\_total\_overdue CHECK (  
  total\_overdue \= od\_1\_7 \+ od\_8\_14 \+ od\_15\_21 \+ od\_22\_30 \+ od\_gt\_30  
),

CONSTRAINT chk\_b1\_ageing\_row\_status CHECK (  
 row\_status IN ('active', 'replaced')  
),

CONSTRAINT chk\_b1\_ageing\_lifecycle\_consistency CHECK (  
 (row\_status \= 'active' AND is\_active \= true)  
 OR  
 (row\_status \= 'replaced' AND is\_active \= false)  
)  
);

CREATE UNIQUE INDEX uq\_b1\_ageing\_activity\_active  
ON incentive\_ar\_ageing\_activity(  
  partner\_id,  
  period\_month,  
  period\_year,  
  salesperson\_id,  
  customer\_id  
)  
WHERE is\_active \= true;

CREATE INDEX idx\_b1\_ageing\_activity\_lookup  
ON incentive\_ar\_ageing\_activity(  
  partner\_id,  
  period\_month,  
  period\_year,  
  salesperson\_id  
)  
WHERE is\_active \= true;

On successful processing, all previous active AR Ageing rows for the same partner and period are marked replaced/inactive before latest rows are inserted as active.

No row-by-row comparison is required.

If AR Ageing feed processing fails, previous active AR Ageing rows remain unchanged.

Calculation should read only rows where is\_active \= true.

AR Ageing feed stores source overdue range amounts using these columns:

od\_1\_7  
 od\_8\_14  
 od\_15\_21  
 od\_22\_30  
 od\_gt\_30

These source columns are not the same as AR config bucket codes.

During calculation, backend maps source range columns to AR deduction bucket codes as follows:

od\_1\_7 → OD\_GT\_0  
 od\_8\_14 → OD\_GT\_7  
 od\_15\_21 → OD\_GT\_14  
 od\_22\_30 → OD\_GT\_21  
 od\_gt\_30 → OD\_GT\_30

The worker should validate:

total\_overdue \= od\_1\_7 \+ od\_8\_14 \+ od\_15\_21 \+ od\_22\_30 \+ od\_gt\_30

The worker should not calculate bucket percentages.

The worker should not calculate deduction\_percentage.

The worker should not select final\_bucket\_code.

The worker only validates and activates raw AR ageing rows.

Final bucket selection happens during AR ageing calculation by checking the highest source range amount greater than 0\.

## **11.5 Trader Upload Tables**

Trader stock and GPM inputs are admin-uploaded CSV files.

Trader uploads do not use preview \+ commit flow.

Trader uploads follow asynchronous worker processing:

1. Admin uploads CSV file through Trader upload API.  
2. API validates request-level fields.  
3. API uploads the original CSV file to S3.  
4. API creates an upload session.  
5. API enqueues a Trader upload worker job.  
6. Worker reads the original file from S3.  
7. Worker validates file structure and rows.  
8. Worker enriches GPM rows using Product Submissions API where required.  
9. Worker writes valid rows into Trader stock/GPM activity tables.  
10. Worker stores rejected rows in incentive\_upload\_errors.  
11. Worker generates success and reject CSV files.  
12. Worker uploads success and reject files to S3.  
13. Worker updates upload session status and row counts.

Trader stock and Trader GPM activity tables reference incentive\_upload\_sessions.id through upload\_id.

They do not reference incentive\_feed\_logs.

Only CSV files are supported in Phase 1\.

S3 key format:

original file:

*incentive/trader-uploads/{partner\_id}/{period}/{upload\_type}/{upload\_id}/original.csv*

success file:

*incentive/trader-uploads/{partner\_id}/{period}/{upload\_type}/{upload\_id}/success.csv*

reject file:

*incentive/trader-uploads/{partner\_id}/{period}/{upload\_type}/{upload\_id}/reject.csv*

The frontend should not receive raw S3 keys.

For downloads, frontend should use backend download APIs. Backend will fetch the file from S3 and stream it as a downloadable file.

No separate artifact table is required for Phase 1 because each upload has at most one original file, one success file, and one reject file. These file keys are stored directly on incentive\_upload\_sessions.

No staged rows table is required because there is no preview \+ commit flow. The worker validates and activates valid rows during processing.

### **11.5.1 incentive\_upload\_sessions**

CREATE TABLE incentive\_upload\_sessions (  
id                    UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
partner\_id            UUID NOT NULL,  
upload\_type           VARCHAR(100) NOT NULL,  
period\_month          INTEGER NOT NULL,  
period\_year           INTEGER NOT NULL,  
status                VARCHAR(30) NOT NULL DEFAULT 'queued',  
total\_rows            INTEGER NOT NULL DEFAULT 0,  
success\_rows          INTEGER NOT NULL DEFAULT 0,  
insert\_rows           INTEGER NOT NULL DEFAULT 0,  
update\_rows           INTEGER NOT NULL DEFAULT 0,  
rejected\_rows         INTEGER NOT NULL DEFAULT 0,  
unchanged\_rows        INTEGER NOT NULL DEFAULT 0,  
original\_filename     TEXT NOT NULL,  
s3\_bucket             TEXT NOT NULL,  
original\_file\_key     TEXT NOT NULL,  
success\_file\_key      TEXT,  
reject\_file\_key       TEXT,  
file\_size\_bytes       BIGINT,  
content\_type          VARCHAR(100) NOT NULL DEFAULT 'text/csv',  
uploaded\_by           UUID NOT NULL,  
uploaded\_by\_name      VARCHAR(255) NOT NULL,  
processing\_started\_at TIMESTAMPTZ,  
completed\_at          TIMESTAMPTZ,  
error\_details         JSONB,  
created\_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),  
updated\_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

CONSTRAINT chk\_b1\_upload\_month CHECK (  
  period\_month BETWEEN 1 AND 12  
),

CONSTRAINT chk\_b1\_upload\_type CHECK (  
  upload\_type IN (  
    'TRADER\_STOCK\_BY\_PRODUCT',  
    'TRADER\_STOCK\_GRADE',  
    'TRADER\_STOCK\_SIDE\_PRODUCT',  
    'TRADER\_GPM'  
  )  
),

CONSTRAINT chk\_b1\_upload\_status CHECK (  
  status IN (  
    'queued',  
    'processing',  
    'success',  
    'partial\_success',  
    'failed',  
    'cancelled'  
  )  
)  
);

CREATE INDEX idx\_b1\_upload\_sessions\_lookup  
ON incentive\_upload\_sessions(  
  partner\_id,  
  period\_year,  
  period\_month,  
  upload\_type,  
  status,  
  created\_at DESC  
);

CREATE INDEX idx\_b1\_upload\_sessions\_processing  
ON incentive\_upload\_sessions(status, created\_at)  
WHERE status IN ('queued', 'processing');

CREATE INDEX idx\_b1\_upload\_sessions\_uploaded\_by  
ON incentive\_upload\_sessions(uploaded\_by, created\_at DESC);

Status Meaning

| Status | Meaning |
| ----- | ----- |
| queued | File has been uploaded to S3 and worker job has been queued. |
| processing | Worker has started processing the file. |
| success | All rows were successfully processed. |
| partial\_success | At least one row succeeded and at least one row was rejected. |
| failed | Upload failed due to file-level error, S3 error, Product API hard failure, invalid structure, or zero successful rows. |
| cancelled | Upload was cancelled before processing started. |

Row Count Meaning

| Column | Meaning |
| ----- | ----- |
| total\_rows | Total data rows read from CSV, excluding header. |
| success\_rows | Rows accepted by worker. This includes inserted, updated, and unchanged rows. |
| insert\_rows | Rows inserted as new active rows. |
| update\_rows | Rows that replaced existing active rows. |
| unchanged\_rows | Rows where the same active data already existed and no new active row was inserted. |
| rejected\_rows | Rows rejected due to validation or enrichment errors. |

### **11.5.2 incentive\_upload\_errors**

CREATE TABLE incentive\_upload\_errors (  
id                UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
upload\_id         UUID NOT NULL  
  REFERENCES incentive\_upload\_sessions(id)  
  ON DELETE RESTRICT,

row\_number        INTEGER,  
error\_code        VARCHAR(100) NOT NULL,  
error\_message     TEXT,  
row\_payload       JSONB,  
error\_details     JSONB,  
created\_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()  
);

CREATE INDEX idx\_b1\_upload\_errors\_upload  
ON incentive\_upload\_errors(upload\_id);

CREATE INDEX idx\_b1\_upload\_errors\_code  
ON incentive\_upload\_errors(upload\_id, error\_code);

* row\_number should represent the row number from the original CSV file.  
* The parser should assign row\_number before any batching or parallel processing.  
* row\_number is useful for admin troubleshooting and for the reject CSV file.  
* row\_payload stores the original uploaded row payload.  
* error\_details can store additional debug data such as invalid field name, expected value, received value, Product API response issue, or duplicate natural key.  
* Rejected rows are stored here for audit/debugging.  
* The downloadable reject CSV is generated from worker processing and uploaded to S3.

---

## **11.6 incentive\_trader\_stock\_activity**

Stores normalized rows from Trader stock upload.

This table should reference upload\_id, not feed\_log\_id.

region is removed because it is not required for calculation.

| CREATE TABLE incentive\_trader\_stock\_activity ( id                  UUID PRIMARY KEY DEFAULT gen\_random\_uuid(), upload\_id           UUID NOT NULL   REFERENCES incentive\_upload\_sessions(id)   ON DELETE RESTRICT, partner\_id          UUID NOT NULL, period\_month        INTEGER NOT NULL, period\_year         INTEGER NOT NULL, salesperson\_id      UUID NOT NULL, unit\_code           VARCHAR(100) NOT NULL, category            VARCHAR(50) NOT NULL, grade               VARCHAR(100), stock\_eom           NUMERIC(18,4) NOT NULL DEFAULT 0, billing\_eom         NUMERIC(18,4) NOT NULL DEFAULT 0, row\_status          VARCHAR(30) NOT NULL DEFAULT 'active', superseded\_by       UUID, deleted\_by          UUID, deleted\_at          TIMESTAMPTZ, delete\_reason       TEXT, is\_active           BOOLEAN NOT NULL DEFAULT true, created\_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated\_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT chk\_b1\_trader\_stock\_month CHECK (   period\_month BETWEEN 1 AND 12 ), CONSTRAINT chk\_b1\_trader\_stock\_category CHECK (   category IN (     'BY\_PRODUCT',     'GRADE',     'SIDE\_PRODUCT'   ) ), CONSTRAINT chk\_b1\_trader\_stock\_non\_negative CHECK (   stock\_eom \>= 0   AND billing\_eom \>= 0 ), CONSTRAINT chk\_b1\_trader\_stock\_row\_status CHECK (   row\_status IN (     'active',     'superseded',     'deleted'   ) ),  CONSTRAINT chk\_b1\_trader\_stock\_lifecycle\_consistency CHECK (    (row\_status \=  'active' AND is\_active \= true) OR    (row\_status IN ('superseded', 'deleted') AND is\_active \= false)   ));CREATE INDEX idx\_b1\_trader\_stock\_lookup ON incentive\_trader\_stock\_activity(   partner\_id,   period\_month,   period\_year,   salesperson\_id,   category ) WHERE is\_active \= true;CREATE INDEX idx\_b1\_trader\_stock\_upload ON incentive\_trader\_stock\_activity(upload\_id); CREATE UNIQUE INDEX uq\_b1\_trader\_stock\_active  ON incentive\_trader\_stock\_activity(    partner\_id,    period\_month,    period\_year,    salesperson\_id,    unit\_code,    category,    COALESCE(grade, '')  )  WHERE is\_active \= true;  |
| :---- |

Category values:

1. BY\_PRODUCT  
2. GRADE  
3. SIDE\_PRODUCT

Formula:

stock\_level\_days \= stock\_eom / billing\_eom × day\_multiplier

row\_status is used for active-row lifecycle: active, superseded, deleted. Rejected rows are stored in incentive\_upload\_errors and are not inserted into Trader activity tables.

## **11.7 incentive\_trader\_gpm\_activity**

Stores normalized and product-enriched rows from Trader GPM upload.

This table should reference upload\_id, not feed\_log\_id.

Trader GPM upload file contains:

1. Period  
2. Sales ID  
3. Cust ID  
4. Prod ID  
5. GP  
6. Revenue

The uploaded Prod ID is the Product UUID.

Product metadata is resolved from Product Submissions API during upload processing.

product\_category is populated from Product API response field category\_label.

unit\_code is not part of the confirmed GPM upload format and should not be stored for GPM.

grade is not part of the confirmed GPM upload format. KW / Special Choice exclusion remains pending until Product confirms the field to identify those products.

tipe\_3 is not part of the normalized GPM table or calculation logic.

CREATE TABLE incentive\_trader\_gpm\_activity (  
id                  UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
upload\_id           UUID NOT NULL  
  REFERENCES incentive\_upload\_sessions(id)  
  ON DELETE RESTRICT,

partner\_id          UUID NOT NULL,  
period\_month        INTEGER NOT NULL,  
period\_year         INTEGER NOT NULL,  
salesperson\_id      UUID NOT NULL,  
customer\_id         VARCHAR(100) NOT NULL,  
product\_id          UUID NOT NULL,  
product\_code        VARCHAR(100),  
product\_name        VARCHAR(255),  
product\_category    VARCHAR(255),  
product\_metadata    JSONB,  
revenue             NUMERIC(18,2) NOT NULL DEFAULT 0,  
gp\_value            NUMERIC(18,2) NOT NULL DEFAULT 0,  
row\_status          VARCHAR(30) NOT NULL DEFAULT 'active',  
superseded\_by       UUID,  
deleted\_by          UUID,  
deleted\_at          TIMESTAMPTZ,  
delete\_reason       TEXT,  
is\_active           BOOLEAN NOT NULL DEFAULT true,  
created\_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),  
updated\_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

CONSTRAINT chk\_b1\_trader\_gpm\_month CHECK (  
  period\_month BETWEEN 1 AND 12  
),

CONSTRAINT chk\_b1\_trader\_gpm\_row\_status CHECK (  
  row\_status IN (  
    'active',  
    'superseded',  
    'deleted'  
  )  
),

CONSTRAINT chk\_b1\_trader\_gpm\_lifecycle\_consistency CHECK (  
 (row\_status \= 'active' AND is\_active \= true)  
 OR   
 (row\_status IN ('superseded', 'deleted') AND is\_active \= false)   
)  
);

CREATE UNIQUE INDEX uq\_b1\_trader\_gpm\_active  
ON incentive\_trader\_gpm\_activity(  
  partner\_id,  
  period\_month,  
  period\_year,  
  salesperson\_id,  
  customer\_id,  
  product\_id  
)  
WHERE is\_active \= true;

CREATE INDEX idx\_b1\_trader\_gpm\_lookup  
ON incentive\_trader\_gpm\_activity(  
  partner\_id,  
  period\_month,  
  period\_year,  
  salesperson\_id  
)  
WHERE is\_active \= true;

CREATE INDEX idx\_b1\_trader\_gpm\_category\_lookup  
ON incentive\_trader\_gpm\_activity(  
  partner\_id,  
  period\_month,  
  period\_year,  
  product\_category  
)  
WHERE is\_active \= true;

CREATE INDEX idx\_b1\_trader\_gpm\_upload  
ON incentive\_trader\_gpm\_activity(upload\_id);

Field Notes

product\_id stores the uploaded Prod ID from the GPM file.

customer\_id stores the uploaded Cust ID from the GPM file.

product\_code, product\_name, product\_category, and product\_metadata are resolved from Product Submissions API.

product\_category stores category\_label from Product API response.

product\_metadata can store relevant Product API response fields for audit/debugging.

GPM by Product:

1. Filter product\_category \= 'BY PRODUCT'.  
2. Exclude KW / Special Choice rows only after Product confirms the source field.  
3. Calculate GPM percentage using the GPM formula rules defined in Sections 7.5 and 7.6. If aggregated revenue is negative, calculated GPM percentage should remain negative and should go through normal slab lookup.

GPM All Product:

1. Include all product categories.  
2. Exclude KW / Special Choice rows only after Product confirms the source field.  
3. Calculate GPM percentage using the GPM formula rules defined in Sections 7.5 and 7.6. If aggregated revenue is negative, calculated GPM percentage should remain negative and should go through normal slab lookup.

Negative gp\_value is allowed.

Negative revenue is allowed. If aggregated revenue is negative, calculated GPM percentage should also be negative. Negative GP and negative revenue should not cancel each other out and produce a positive GPM percentage. The negative GPM percentage should go through normal slab lookup

---

# **12\. Run and Result Tables**

Business 1 should reuse existing common run/logging infrastructure where feasible.

Business 1 should not reuse the existing Business 2 incentive\_results table because Business 1 uses a point-based calculation model.

Business 1 requires separate result tables for:

1. participant snapshot  
2. incentive point results  
3. AR ageing deduction result  
4. final payable result

## **12.1 Existing Common Run / Log Tables**

Business 1 should reuse and extend these existing tables:

1. incentive\_run\_log  
2. incentive\_cron\_log  
3. incentive\_run\_errors

These changes must be backward-compatible with Business 2\.

### **incentive\_run\_log changes**

Business 1 should reuse incentive\_run\_log for calculation run tracking.

Business 1 needs run\_type because the calculation has CRON, CATCHUP\_CRON, and MANUAL runs.

Existing common table compatibility:

Business 2 uses schema\_id as a mandatory reference to incentive\_schemas.

Business 1 does not calculate against one incentive schema\_id, because Business 1 uses point registry, point slabs, payout config, AR ageing config, and Trader multiplier config.

For Business 1:

1\. schema\_id should be nullable.

2\. business\_code \= BUSINESS\_1 identifies Business 1 rows.

3\. run\_type identifies CRON, CATCHUP\_CRON, or MANUAL.

4\. triggered\_by should continue using existing common values:

   \- CRON for CRON

   \- CRON for CATCHUP\_CRON

   \- MANUAL for MANUAL

5\. The API may expose run\_type to distinguish CRON from CATCHUP\_CRON.

For Business 2:

1\. schema\_id remains mandatory by application validation.

2\. run\_type can remain null.

3\. existing triggered\_by behavior remains unchanged.

| ALTER TABLE incentive\_run\_logADD COLUMN IF NOT EXISTS business\_code VARCHAR(30) NOT NULL DEFAULT 'BUSINESS\_2';ALTER TABLE incentive\_run\_logADD COLUMN IF NOT EXISTS run\_type VARCHAR(30);ALTER TABLE incentive\_run\_logADD COLUMN IF NOT EXISTS is\_superseded BOOLEAN NOT NULL DEFAULT false;ALTER TABLE incentive\_run\_logADD COLUMN IF NOT EXISTS superseded\_by\_run\_id UUID; ALTER TABLE incentive\_run\_log ALTER COLUMN schema\_id DROP NOT NULL;ALTER TABLE incentive\_run\_logDROP CONSTRAINT IF EXISTS chk\_irl\_business\_code;ALTER TABLE incentive\_run\_logADD CONSTRAINT chk\_irl\_business\_code CHECK ( business\_code IN ('BUSINESS\_1', 'BUSINESS\_2'));ALTER TABLE incentive\_run\_logDROP CONSTRAINT IF EXISTS chk\_irl\_run\_type;ALTER TABLE incentive\_run\_logADD CONSTRAINT chk\_irl\_run\_type CHECK ( run\_type IS NULL OR run\_type IN (   'CRON',   'CATCHUP\_CRON',   'MANUAL' ));CREATE INDEX idx\_irl\_business\_period ON incentive\_run\_log(   business\_code,   partner\_id,   year,   month );CREATE INDEX idx\_irl\_business\_run\_type ON incentive\_run\_log(   business\_code,   partner\_id,   year,   month,   run\_type );CREATE UNIQUE INDEX uq\_irl\_b1\_active\_run ON incentive\_run\_log(   business\_code,   partner\_id,   year,   month ) WHERE business\_code \= 'BUSINESS\_1'   AND status IN ('pending', 'processing'); |
| :---- |

For Business 2:

business\_code \= BUSINESS\_2  
run\_type can remain null

For Business 1:

business\_code \= BUSINESS\_1  
run\_type is required by application validation

Allowed Business 1 run\_type values:

1. CRON  
2. CATCHUP\_CRON  
3. MANUAL

**Run tracking responsibility**

1. Business 1 run tracking should use incentive\_run\_log as the source of truth for calculation run status.  
2. Run-level errors should be stored in incentive\_run\_errors.  
3. Participant-level calculation output status should be stored in the relevant result tables.  
4. BullMQ job status should be used for worker execution tracking and operational debugging.  
5. Result APIs should depend on persisted run/result tables, not directly on BullMQ job state.  
6. That keeps the useful implementation guidance without mentioning tables we are not creating.

### **incentive\_cron\_log changes**

Business 1 should reuse incentive\_cron\_log.

Existing cron types are not enough because Business 1 has separate CRON, CATCHUP\_CRON, and MANUAL trigger tracking needs.

| ALTER TABLE incentive\_cron\_logADD COLUMN IF NOT EXISTS business\_code VARCHAR(30) NOT NULL DEFAULT 'BUSINESS\_2';ALTER TABLE incentive\_cron\_logDROP CONSTRAINT IF EXISTS chk\_icl\_business\_code;ALTER TABLE incentive\_cron\_logADD CONSTRAINT chk\_icl\_business\_code CHECK ( business\_code IN ('BUSINESS\_1', 'BUSINESS\_2'));ALTER TABLE incentive\_cron\_logDROP CONSTRAINT IF EXISTS chk\_icl\_cron\_type;ALTER TABLE incentive\_cron\_logALTER COLUMN cron\_type TYPE VARCHAR(40);ALTER TABLE incentive\_cron\_logADD CONSTRAINT chk\_icl\_cron\_type CHECK ( cron\_type IN (   'CALCULATION\_CRON',   'CATCHUP\_CRON',   'MANUAL\_TRIGGER' ));CREATE INDEX idx\_icl\_business\_period ON incentive\_cron\_log(   business\_code,   partner\_id,   year,   month,   cron\_type ); |
| :---- |

Business 1 cron\_type values:

1. CALCULATION\_CRON  
2. CATCHUP\_CRON  
3. MANUAL\_TRIGGER

### **incentive\_run\_errors changes**

Business 1 should reuse incentive\_run\_errors.

Current Business 2 flow uses role values like SYSTEM, SP, and SPV. Business 1 calculation should use level and original\_role.

For Business 1 errors:  
1\. schema\_id should be nullable.  
2\. role should be nullable.  
3\. Business 1 should use level, original\_role, and incentive\_point\_code for error context.  
4\. Existing role values should remain for Business 2 compatibility.

| ALTER TABLE incentive\_run\_errorsADD COLUMN IF NOT EXISTS business\_code VARCHAR(30) NOT NULL DEFAULT 'BUSINESS\_2';ALTER TABLE incentive\_run\_errorsADD COLUMN IF NOT EXISTS level SMALLINT;ALTER TABLE incentive\_run\_errorsADD COLUMN IF NOT EXISTS original\_role VARCHAR(50);ALTER TABLE incentive\_run\_errorsADD COLUMN IF NOT EXISTS incentive\_point\_code VARCHAR(100); ALTER TABLE incentive\_run\_errors ALTER COLUMN schema\_id DROP NOT NULL; ALTER TABLE incentive\_run\_errors ALTER COLUMN "role" DROP NOT NULL;ALTER TABLE incentive\_run\_errorsDROP CONSTRAINT IF EXISTS chk\_ire\_business\_code;ALTER TABLE incentive\_run\_errorsADD CONSTRAINT chk\_ire\_business\_code CHECK ( business\_code IN ('BUSINESS\_1', 'BUSINESS\_2'));ALTER TABLE incentive\_run\_errorsDROP CONSTRAINT IF EXISTS chk\_ire\_level;ALTER TABLE incentive\_run\_errorsADD CONSTRAINT chk\_ire\_level CHECK ( level IS NULL OR level IN (1, 2, 3));CREATE INDEX idx\_ire\_business\_run ON incentive\_run\_errors(   business\_code,   run\_id,   is\_deprecated ) WHERE is\_deprecated \= false;CREATE INDEX idx\_ire\_business\_point ON incentive\_run\_errors(   business\_code,   partner\_id,   incentive\_point\_code ) WHERE is\_deprecated \= false; |
| :---- |

For Business 1 user-level errors, use:

level  
original\_role  
entity\_id  
incentive\_point\_code

The existing role column can remain for Business 2 compatibility.

## **12.2 incentive\_participant\_snapshots**

Stores participant, hierarchy, level, original role, channel, and active status snapshot for a calculation run.

This ensures all jobs inside the same run use the same user metadata and hierarchy.

Channel should be stored here and copied into incentive point result and final result tables for audit/reporting.

| CREATE TABLE incentive\_participant\_snapshots ( id                    UUID PRIMARY KEY DEFAULT gen\_random\_uuid(), run\_id                UUID NOT NULL   REFERENCES incentive\_run\_log(run\_id)   ON DELETE RESTRICT, partner\_id            UUID NOT NULL, period\_month          INTEGER NOT NULL, period\_year           INTEGER NOT NULL, salesperson\_id        UUID NOT NULL, salesperson\_name      VARCHAR(255), salesperson\_type      VARCHAR(30) NOT NULL, level                 SMALLINT NOT NULL, original\_role         VARCHAR(50), channel               VARCHAR(100), status                VARCHAR(30) NOT NULL, upline\_id             UUID, hierarchy\_path        JSONB, created\_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(), CONSTRAINT chk\_b1\_participant\_month CHECK (   period\_month BETWEEN 1 AND 12 ), CONSTRAINT chk\_b1\_participant\_salesperson\_type CHECK (   salesperson\_type IN ('NON\_TRADER', 'TRADER') ), CONSTRAINT chk\_b1\_participant\_level CHECK (   level IN (1, 2, 3) ), CONSTRAINT chk\_b1\_participant\_status CHECK (   status IN ('ACTIVE', 'INACTIVE') ), CONSTRAINT uq\_b1\_participant\_run\_user UNIQUE (   run\_id,   salesperson\_id ));CREATE INDEX idx\_b1\_participant\_run ON incentive\_participant\_snapshots(run\_id);CREATE INDEX idx\_b1\_participant\_lookup ON incentive\_participant\_snapshots(   partner\_id,   period\_month,   period\_year,   salesperson\_id );CREATE INDEX idx\_b1\_participant\_upline ON incentive\_participant\_snapshots(   run\_id,   upline\_id ) WHERE upline\_id IS NOT NULL; |
| :---- |

Level mapping:

Level 1 \= SALES  
Level 2 \= SPV / KAO  
Level 3 \= RSO

Calculation uses level.

Reporting/audit can use original\_role.

## **12.3 incentive\_point\_results**

Stores one row per participant, incentive point, month, and run.

Result rows use incentive point terminology for consistency with Business 1 calculation and API contracts.

| CREATE TABLE incentive\_point\_results ( id                        UUID PRIMARY KEY DEFAULT gen\_random\_uuid(), run\_id                    UUID NOT NULL   REFERENCES incentive\_run\_log(run\_id)   ON DELETE RESTRICT, participant\_snapshot\_id   UUID NOT NULL   REFERENCES incentive\_participant\_snapshots(id)   ON DELETE RESTRICT, partner\_id                UUID NOT NULL, period\_month              INTEGER NOT NULL, period\_year               INTEGER NOT NULL, incentive\_point\_metric\_id UUID NOT NULL   REFERENCES incentive\_point\_metrics(id)   ON DELETE RESTRICT, incentive\_point\_code      VARCHAR(100) NOT NULL, salesperson\_id            UUID NOT NULL, salesperson\_name          VARCHAR(255), level                     SMALLINT NOT NULL, original\_role             VARCHAR(50), salesperson\_type          VARCHAR(30) NOT NULL, channel                   VARCHAR(100), achievement\_value         NUMERIC(18,4), achievement\_percentage    NUMERIC(18,4), matched\_slab\_id           UUID   REFERENCES incentive\_point\_slabs(id)   ON DELETE RESTRICT, points INTEGER NOT NULL DEFAULT 0, status                    VARCHAR(30) NOT NULL DEFAULT 'success', error\_code                VARCHAR(100), error\_message             TEXT, calculation\_details       JSONB, is\_deprecated             BOOLEAN NOT NULL DEFAULT false, created\_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated\_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(), publication\_status VARCHAR(20) NOT NULL DEFAULT 'draft', published\_at TIMESTAMPTZ, superseded\_by\_run\_id UUID  REFERENCES incentive\_run\_log(run\_id)  ON DELETE SET NULL, superseded\_at TIMESTAMPTZ, CONSTRAINT chk\_publication\_status CHECK (   publication\_status IN ('draft', 'published') ),  CONSTRAINT chk\_b1\_point\_result\_month CHECK (   period\_month BETWEEN 1 AND 12 ), CONSTRAINT chk\_b1\_point\_result\_level CHECK (   level IN (1, 2, 3) ), CONSTRAINT chk\_b1\_point\_result\_salesperson\_type CHECK (   salesperson\_type IN ('NON\_TRADER', 'TRADER') ), CONSTRAINT chk\_b1\_point\_result\_points CHECK (   points \>= 0 ), CONSTRAINT chk\_b1\_point\_result\_status CHECK (   status IN ('success', 'skipped', 'failed') ), CONSTRAINT uq\_ipr\_run\_user\_point UNIQUE (   run\_id,   salesperson\_id,   incentive\_point\_code ));CREATE INDEX idx\_b1\_point\_results\_run ON incentive\_point\_results(run\_id);CREATE INDEX idx\_b1\_point\_results\_person ON incentive\_point\_results(   partner\_id,   period\_month,   period\_year,   salesperson\_id ) WHERE publication\_status \= 'published' AND is\_deprecated \= false;CREATE INDEX idx\_b1\_point\_results\_code ON incentive\_point\_results(   partner\_id,   period\_month,   period\_year,   incentive\_point\_code ) WHERE publication\_status \= 'published' AND is\_deprecated \= false; |
| :---- |

incentive\_point\_code is stored as a snapshot field for readability, reporting, and debugging.

Although it can be derived by joining incentive\_point\_metrics, keeping it on the result row makes historical calculation output self-explanatory and avoids unnecessary joins in result APIs/exports.

Example calculation\_details:

{  
  "actual\_volume": 1080,  
  "target\_volume": 1000,  
  "achievement\_percentage": 108,  
  "slab\_condition": "\> 100",  
  "matched\_points": 5,  
  "channel": "Catering",  
  "level": 1  
}

## **12.4 incentive\_ar\_ageing\_deduction\_results**

Stores calculated AR ageing deduction breakdown per participant and run.

This is a calculated aggregate snapshot.

It should not be replaced by directly reading incentive\_ar\_ageing\_activity because activity rows are raw customer-level input, while this table stores participant-level calculated output.

| CREATE TABLE incentive\_ar\_ageing\_deduction\_results ( id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(), run\_id UUID NOT NULL REFERENCES incentive\_run\_log(run\_id) ON DELETE RESTRICT,participant\_snapshot\_id UUID NOT NULL REFERENCES incentive\_participant\_snapshots(id) ON DELETE RESTRICT,partner\_id UUID NOT NULL, period\_month INTEGER NOT NULL, period\_year INTEGER NOT NULL, salesperson\_id UUID NOT NULL, salesperson\_name VARCHAR(255), salesperson\_type VARCHAR(30) NOT NULL DEFAULT 'NON\_TRADER', level SMALLINT NOT NULL, original\_role VARCHAR(50), channel VARCHAR(100) NOT NULL,total\_overdue NUMERIC(18,2) NOT NULL DEFAULT 0, od\_1\_7\_amount NUMERIC(18,2) NOT NULL DEFAULT 0, od\_8\_14\_amount NUMERIC(18,2) NOT NULL DEFAULT 0, od\_15\_21\_amount NUMERIC(18,2) NOT NULL DEFAULT 0, od\_22\_30\_amount NUMERIC(18,2) NOT NULL DEFAULT 0, od\_gt\_30\_amount NUMERIC(18,2) NOT NULL DEFAULT 0,final\_bucket\_code VARCHAR(30),ageing\_deduction\_config\_id UUID REFERENCES ar\_ageing\_deduction\_configs(id) ON DELETE RESTRICT,ageing\_deduction\_rule\_id UUID REFERENCES ar\_ageing\_deduction\_rules(id) ON DELETE RESTRICT,deduction\_percentage NUMERIC(8,4) NOT NULL DEFAULT 0, source\_activity\_ids UUID\[\], status VARCHAR(30) NOT NULL DEFAULT 'success', error\_code VARCHAR(100), error\_message TEXT, calculation\_details JSONB, is\_deprecated BOOLEAN NOT NULL DEFAULT false, created\_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated\_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),publication\_status VARCHAR(20) NOT NULL DEFAULT 'draft', published\_at TIMESTAMPTZ, superseded\_by\_run\_id UUID REFERENCES incentive\_run\_log(run\_id) ON DELETE SET NULL, superseded\_at TIMESTAMPTZ,CONSTRAINT chk\_publication\_status CHECK ( publication\_status IN ('draft', 'published') ),CONSTRAINT chk\_b1\_ageing\_result\_month CHECK ( period\_month BETWEEN 1 AND 12 ),CONSTRAINT chk\_b1\_ageing\_result\_salesperson\_type CHECK ( salesperson\_type \= 'NON\_TRADER' ),CONSTRAINT chk\_b1\_ageing\_result\_level CHECK ( level IN (1, 2, 3\) ),CONSTRAINT chk\_b1\_ageing\_result\_non\_negative CHECK ( total\_overdue \>= 0 AND od\_1\_7\_amount \>= 0 AND od\_8\_14\_amount \>= 0 AND od\_15\_21\_amount \>= 0 AND od\_22\_30\_amount \>= 0 AND od\_gt\_30\_amount \>= 0 AND deduction\_percentage BETWEEN 0 AND 100 ),CONSTRAINT chk\_b1\_ageing\_result\_bucket CHECK ( final\_bucket\_code IS NULL OR final\_bucket\_code IN ( 'OD\_GT\_30', 'OD\_GT\_21', 'OD\_GT\_14', 'OD\_GT\_7', 'OD\_GT\_0' ) ),CONSTRAINT chk\_b1\_ageing\_result\_status CHECK ( status IN ('success', 'skipped', 'failed') ),CONSTRAINT uq\_iadr\_run\_user UNIQUE ( run\_id, salesperson\_id ) );CREATE INDEX idx\_b1\_ageing\_results\_run ON incentive\_ar\_ageing\_deduction\_results(run\_id);CREATE INDEX idx\_b1\_ageing\_results\_person ON incentive\_ar\_ageing\_deduction\_results( partner\_id, period\_month, period\_year, salesperson\_id ) WHERE publication\_status \= 'published' AND is\_deprecated \= false;CREATE INDEX idx\_b1\_ageing\_results\_rule ON incentive\_ar\_ageing\_deduction\_results(ageing\_deduction\_rule\_id) WHERE ageing\_deduction\_rule\_id IS NOT NULL; |
| :---- |

Fields not stored:

1. ar\_ending\_balance  
2. current\_amount  
3. current\_pct  
4. bucket percentage fields  
5. threshold\_percentage

Bucket percentages are not calculated because AR deduction is no longer selected using bucket percentage threshold logic.

The result stores the aggregated source ageing amounts and the selected deduction bucket.

Source amount fields remain:

od\_1\_7\_amount  
 od\_8\_14\_amount  
 od\_15\_21\_amount  
 od\_22\_30\_amount  
 od\_gt\_30\_amount

Configured bucket codes use overdue-day threshold naming:

OD\_GT\_0  
 OD\_GT\_7  
 OD\_GT\_14  
 OD\_GT\_21  
 OD\_GT\_30

Mapping from source amount fields to final bucket codes:

od\_1\_7\_amount → OD\_GT\_0  
 od\_8\_14\_amount → OD\_GT\_7  
 od\_15\_21\_amount → OD\_GT\_14  
 od\_22\_30\_amount → OD\_GT\_21  
 od\_gt\_30\_amount → OD\_GT\_30

Selection rule:

1. If od\_gt\_30\_amount \> 0, final\_bucket\_code \= OD\_GT\_30.  
2. Else if od\_22\_30\_amount \> 0, final\_bucket\_code \= OD\_GT\_21.  
3. Else if od\_15\_21\_amount \> 0, final\_bucket\_code \= OD\_GT\_14.  
4. Else if od\_8\_14\_amount \> 0, final\_bucket\_code \= OD\_GT\_7.  
5. Else if od\_1\_7\_amount \> 0, final\_bucket\_code \= OD\_GT\_0.  
6. Else final\_bucket\_code \= null and deduction\_percentage \= 0\.

ageing\_deduction\_rule\_id references the exact AR ageing deduction rule used during calculation.

If final\_bucket\_code is null because all overdue amounts are 0, ageing\_deduction\_rule\_id can be null.

If final\_bucket\_code is not null, ageing\_deduction\_rule\_id should be populated from the matched active AR ageing rule.

Example calculation\_details:

{  
 "total\_overdue": 192,  
 "bucket\_amounts": {  
 "OD\_GT\_0": 41,  
 "OD\_GT\_7": 20,  
 "OD\_GT\_14": 60,  
 "OD\_GT\_21": 30,  
 "OD\_GT\_30": 41  
 },  
 "selection\_order": \["OD\_GT\_30", "OD\_GT\_21", "OD\_GT\_14", "OD\_GT\_7", "OD\_GT\_0"\],  
 "selected\_bucket": "OD\_GT\_30",  
 "deduction\_percentage": 20,  
 "reason": "Highest overdue bucket with amount greater than 0 was OD\_GT\_30."  
 }

## 12.5 incentive\_final\_results

Stores one final payable result per participant \+ month \+ run.

| CREATE TABLE incentive\_final\_results ( id                          UUID PRIMARY KEY DEFAULT gen\_random\_uuid(), run\_id                      UUID NOT NULL   REFERENCES incentive\_run\_log(run\_id)   ON DELETE RESTRICT, participant\_snapshot\_id     UUID NOT NULL   REFERENCES incentive\_participant\_snapshots(id)   ON DELETE RESTRICT, partner\_id                  UUID NOT NULL, period\_month                INTEGER NOT NULL, period\_year                 INTEGER NOT NULL, salesperson\_id              UUID NOT NULL, salesperson\_name            VARCHAR(255), level                       SMALLINT NOT NULL, original\_role               VARCHAR(50), salesperson\_type            VARCHAR(30) NOT NULL, channel                     VARCHAR(100), total\_points INTEGER NOT NULL DEFAULT 0,  payout\_row\_id             UUID   REFERENCES incentive\_score\_payouts(id)   ON DELETE RESTRICT, gross\_incentive             NUMERIC(15,2) NOT NULL DEFAULT 0, ageing\_deduction\_result\_id  UUID   REFERENCES incentive\_ar\_ageing\_deduction\_results(id)   ON DELETE RESTRICT, deduction\_percentage        NUMERIC(8,4) NOT NULL DEFAULT 0, deduction\_amount            NUMERIC(15,2) NOT NULL DEFAULT 0, net\_incentive               NUMERIC(15,2) NOT NULL DEFAULT 0, status                      VARCHAR(30) NOT NULL DEFAULT 'success', error\_code                  VARCHAR(100), error\_message               TEXT, calculation\_details         JSONB, is\_deprecated               BOOLEAN NOT NULL DEFAULT false, created\_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated\_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),  publication\_status VARCHAR(20) NOT NULL DEFAULT 'draft',  published\_at TIMESTAMPTZ,  superseded\_by\_run\_id UUID    REFERENCES incentive\_run\_log(run\_id)    ON DELETE SET NULL,  superseded\_at TIMESTAMPTZ, CONSTRAINT chk\_publication\_status CHECK (   publication\_status IN ('draft', 'published') ),  CONSTRAINT chk\_b1\_final\_result\_month CHECK (   period\_month BETWEEN 1 AND 12 ), CONSTRAINT chk\_b1\_final\_result\_level CHECK (   level IN (1, 2, 3\) ), CONSTRAINT chk\_b1\_final\_result\_salesperson\_type CHECK (   salesperson\_type IN ('NON\_TRADER', 'TRADER') ), CONSTRAINT chk\_b1\_final\_result\_amounts CHECK (   total\_points \>= 0   AND gross\_incentive \>= 0   AND deduction\_percentage BETWEEN 0 AND 100   AND deduction\_amount \>= 0   AND net\_incentive \>= 0 ), CONSTRAINT chk\_b1\_final\_result\_status CHECK (   status IN ('success', 'skipped', 'failed') ),CONSTRAINT uq\_ifr\_run\_user UNIQUE (   run\_id,   salesperson\_id ));CREATE INDEX idx\_b1\_final\_results\_run ON incentive\_final\_results(run\_id);CREATE INDEX idx\_b1\_final\_results\_lookup ON incentive\_final\_results(   partner\_id,   period\_month,   period\_year,   salesperson\_id ) WHERE publication\_status \= 'published' AND is\_deprecated \= false;CREATE INDEX idx\_b1\_final\_results\_type\_level ON incentive\_final\_results(   partner\_id,   period\_year,   period\_month,   salesperson\_type,   level ) WHERE publication\_status \= 'published' AND is\_deprecated \= false; |
| :---- |

When a participant's total\_points \= 0, payout\_row\_id is stored as NULL and gross\_incentive is set to 0 directly by application logic — no incentive\_score\_payouts row exists to reference. For total\_points \> 0, payout\_row\_id must be populated from the matched row.

Since incentive\_score\_payouts rows are never hard-deleted, payout\_row\_id keeps pointing to the exact row active at calculation time, even if that row is later marked is\_deprecated \= true by a subsequent Payout Config edit. This is expected and preserves historical accuracy don’t filter this join by is\_deprecated.

For Trader:  
gross\_incentive \= net\_incentive

For Non-Trader:  
net\_incentive \= gross\_incentive \- deduction\_amount

Example calculation\_details:

{  
  "point\_results": \[  
    {  
      "incentive\_point\_code": "NT\_VOLUME\_ACHIEVEMENT",  
      "points": 5  
    },  
    {  
      "incentive\_point\_code": "NT\_TRANSACTED\_OUTLETS",  
      "points": 2  
    }  
  \],  
  "total\_points": 7,  
  "gross\_incentive": 1500000,  
  "deduction\_percentage": 10,  
  "deduction\_amount": 150000,  
  "net\_incentive": 1350000  
}

## **12.6 Why Not Reuse Existing incentive\_results for Business 1?**

Existing incentive\_results is designed for Business 2 direct payout logic, where one scheme result directly stores achievement, slab, and payout amount.

Business 1 is different.

Business 1 first calculates incentive point results, then sums points, then maps total points to a payout amount, and finally applies AR ageing deduction for Non-Trader users.

Reusing incentive\_results for Business 1 would require adding many nullable Business 1-specific columns and branching logic, such as:

1. incentive\_point\_code  
2. total\_points  
3. gross\_incentive  
4. net\_incentive  
5. level  
6. original\_role  
7. channel  
8. ageing deduction references

That would increase the risk of breaking Business 2 logic and make the table harder to reason about.

Therefore, Business 1 should use separate point-result and final-result tables, while still reusing common run/logging tables where feasible.

# **13\. API Design**

## **13.1 Common API Architecture**

Business 1 APIs follow the existing WS1 → WS2 pattern.

**For frontend/admin APIs:**

Closio / FE  
→ WS1  
→ ws2targetsales / incentive service

**For pull-based monthly refresh:**

Admin/authorized caller → WS1 → ws2targetsalesincentive refresh API → ws2closio Customer Handled API → validation → active monthly snapshot.

**New customer monthly flow:**

Source system → POST /api/target/v1/webhooks/new-customer-monthly → file validation and monthly aggregation → active monthly New Transacted Customer snapshot.

**For push-based external feeds:**

Qlik / Finance / external source  
 → ws2targetsales / incentive service  
 → Feed API stores original CSV in S3  
 → Feed worker validates and processes file asynchronously

**For admin-uploaded Trader files:**

Closio / FE  
 → WS1  
 → ws2targetsales / incentive service  
 → Upload API stores original CSV in S3  
 → Upload worker validates and processes file asynchronously  
 → Success/reject files are stored in S3  
 → Backend download APIs stream files back to frontend when requested

## **13.2 Common Auth Rules**

### **Frontend/Admin APIs**

WS1:

1. Validates cookie/session.  
2. Fetches logged-in user details.  
3. Extracts partner\_id, user\_id, and user\_name.  
4. Forwards request to WS2 with S2S headers.

WS2:

1. Validates x-client-id and x-client-secret.  
2. Validates X-Partner-Id.  
3. Uses X-User-Id and X-User-Name for audit where required.  
4. Applies partner-level access control.

Headers from WS1 to WS2:

x-client-id  
x-client-secret  
X-Partner-Id  
X-User-Id  
X-User-Name

### External Feed APIs

External feed APIs are used for push-based monthly feeds such as AR Ageing.

External systems should call the WS1 counterpart / exposed gateway API. WS1 forwards the request to WS2 with required S2S headers. WS2 validates the forwarded S2S request and partner context.

Internal WS1 → WS2 headers:

1. x-client-id  
2. x-client-secret  
3. X-Partner-Id

Customer Handled is pulled by ws2targetsalesincentive from ws2closio. New Transacted Customer data is pushed by the source system through the existing new-customer-monthly S2S webhook. Neither flow uses Trader upload APIs or S3.

Trader stock and Trader GPM files are not S2S feed APIs. They are admin-uploaded CSV files. The upload API stores the original file in S3 and queues asynchronous worker processing. Valid rows are activated by the worker, rejected rows are stored in incentive\_upload\_errors, and success/reject CSV files are stored in S3 for backend download.

## **13.3 Common Terminology**

Business 1 APIs should use consistent terminology across config, feed, calculation, and result APIs.

Common terms:

1. salesperson\_type  
2. incentive\_point\_code  
3. incentive\_point\_name  
4. incentive\_point\_id  
5. level  
6. original\_role  
7. channel  
8. total\_points  
9. gross\_incentive  
10. net\_incentive

Calculation logic should use level.

original\_role should be used only for storing the source role returned by Users API for audit/reporting.

Level mapping:

Level 1 \= SALES  
Level 2 \= SPV / KAO  
Level 3 \= RSO

## **13.4 Common Period Format**

All monthly APIs should use:

YYYY-MM

Example:

2026-06

Backend should convert this internally as required:

valid\_from \= first day of month  
valid\_to \= last day of month

For tables that store month/year separately:

period\_month \= 6  
period\_year \= 2026

## **13.5 Common Response Format**

**Success response:**

{  
  "status": "success",  
  "data": {}  
}

**Error response:**

{  
  "status": "error",  
  "error\_code": "VALIDATION\_ERROR",  
  "message": "Request body validation failed",  
  "details": {}  
}

## **13.6 Common Validation Rules**

Common API validation rules:

1. partner\_id must be available from headers.  
2. period must be valid YYYY-MM where applicable.  
3. salesperson\_type must be NON\_TRADER or TRADER where applicable.  
4. level must be 1, 2, or 3 where applicable.  
5. incentive\_point\_code must be a valid seeded incentive point.  
6. channel is required where the incentive point requires channel.  
7. Mutating actions should be rejected when a Business 1 calculation run is pending or processing for the same partner and impacted period.  
8. audit fields should be populated from X-User-Id and X-User-Name for admin actions.

## **13.7 Customer Input Integration and Incentive Usage**

This section defines the source ownership, API flow, storage, and calculation usage for the two customer-related Business 1 incentive points:

* A.2 % Transacted Outlets  
* A.3 % New Transacted Outlets

Customer input collection and incentive calculation are separate operations. Input refresh or ingestion stores a monthly dataset but does not calculate points or automatically trigger recalculation.

Both incentive points apply to eligible Non-Trader Level 1, Level 2, and Level 3 participants.

Level 1 uses own data. Level 2 uses own data together with direct Level 1 reportee data. Level 3 uses own data together with all downstream Level 2 and Level 1 data.

### **13.7.1 A.2 % Transacted Outlets**

**Purpose**

% Transacted Outlets measures the percentage of handled customers who transacted during the incentive month.

% Transacted Outlets \= Transacted Customer Count / Customer Handled Count × 100

**Input ownership**

The calculation uses two independent inputs:

* Customer Handled Count comes from Closio Customer Management.  
* Transacted Customer Count comes from the Daily Sales data already received by Target Sales.

Customer Handled is not calculated from Daily Sales. Daily Sales is used only to identify which handled customers transacted.

**Closio Customer Handled source API**

The Customer Handled source API is implemented in *nodejs-ws2closio*.

Endpoint:

**GET /api/incentives/v1/customer-handled**

Query parameter:

* period: required in YYYY-MM format

Required headers:

* x-client-id  
* x-client-secret  
* X-Partner-Id

The API is internal and read-only. It is called by ws2targetsalesincentive and is not called directly by the frontend.

The API returns:

* period  
* customers  
  * salesperson\_id  
  * customer\_count

The customers array contains one row for every non-deleted user belonging to the requested partner, including users with customer\_count \= 0\.

No pagination is required in Phase 1\.

**Closio data selection**

Customer ownership is determined by customers.sales\_id.

A customer is counted when:

* customer\_type \= CUSTOMER  
* deleted\_at IS NULL

No additional customer status or registration status filter is applied.

Partner scope is resolved through the user who owns the customer. The query starts from partner users and left joins customers so users with no matching customers are returned with a zero count.

The source returns own customer count only. It does not calculate Level 2 or Level 3 hierarchy totals.

The period is returned as snapshot context. It does not filter the Closio customers table because Closio does not maintain monthly customer-ownership history.

**Target Sales refresh API**

The monthly snapshot is created through the Target Sales endpoint:

**POST /api/incentives/v1/feeds/customer-handled/refresh**

Request field:

* period: required in YYYY-MM format

Call flow:

Authorized admin / FE → WS1 → ws2targetsalesincentive Customer Handled refresh API → ws2closio Customer Handled source API

WS1 performs the existing frontend session and user-context handling. WS2 validates S2S credentials, partner context, and period.

Target Sales then:

1. Creates an incentive\_feed\_logs row with feed\_type \= CUSTOMER\_HANDLED.  
2. Calls the Closio Customer Handled source API.  
3. Validates the complete response.  
4. Rejects duplicate salesperson\_id rows or invalid customer counts.  
5. In one database transaction, marks the previous active snapshot for the partner and period as replaced.  
6. Inserts the latest rows into incentive\_customer\_handled\_snapshots as active.  
7. Marks the feed log as successful with row counts.

If the source call or validation fails, the feed log is marked failed and the previous active snapshot remains unchanged.

The refresh does not use S3 and does not trigger incentive recalculation.

The refresh is rejected when:

* A Business 1 run for the same partner and period is pending or processing.  
* The successful second or CATCHUP\_CRON run has already completed for the period.

A failed CATCHUP\_CRON does not close the refresh window.

**Transacted customer calculation**

For each salesperson, customer, and month:

monthly\_sales\_quantity \= SUM(net\_sales\_quantity)

A customer qualifies as transacted when monthly\_sales\_quantity is greater than zero.

Multiple Daily Sales transactions for the same customer count once. Returns and negative quantities reduce the monthly total.

The existing T4 achievement must not be used directly because T4 currently qualifies customers using net sales amount. Business 1 qualifies customers using net sales quantity.

**Hierarchy roll-up**

The calculation uses the hierarchy snapshot created at the start of the Business 1 run.

**For a Level 1 Salesperson:**

Customer Handled denominator \= own Customer Handled count.

Transacted numerator \= own qualifying transacted customers.

**For a Level 2 SPV or KAO:**

Customer Handled denominator \= own Customer Handled count \+ direct Level 1 reportee own counts.

Transacted numerator \= own qualifying transacted customers \+ direct Level 1 reportee qualifying customers.

**For a Level 3 RSO:**

Customer Handled denominator \= own Customer Handled count \+ downstream Level 2 own counts \+ downstream Level 1 own counts.

Transacted numerator \= own qualifying transacted customers \+ downstream Level 2 own qualifying customers \+ downstream Level 1 own qualifying customers.

Each participant receives an independent incentive-point result for their applicable hierarchy scope.

Each participant’s own raw data is included exactly once. An already-aggregated Level 2 result must not be added together with the Level 1 values already included in that result.

Customer Handled counts are trusted from Closio and are summed without customer-level deduplication.

If the aggregated Customer Handled count is zero, achievement and points are zero.

The calculated percentage is rounded according to the common Business 1 precision rules and matched against the active NT\_TRANSACTED\_OUTLETS slab for the participant’s channel and level.

### **13.7.2 A.3 % New Transacted Outlets**

**Purpose**

% New Transacted Outlets measures achievement against the assigned monthly new-customer count target.

% New Transacted Outlets \= New Transacted Customer Count / New Customer Count Target × 100

**Source ownership and delivery**

The source system owns identifying whether a customer is new for the month.

New Transacted Customer data does not come from the Closio Customer Handled API. It is delivered through the existing Target Sales endpoint:

POST /api/target/v1/webhooks/new-customer-monthly

The source sends one complete monthly CSV at the end of the month. The file is a subset of the Daily Sales format and contains the new customers and their monthly transaction rows.

This is a push-based S2S input. It is not triggered from the frontend and does not use the Customer Handled refresh API.

The source may resend a complete corrected file for the same partner and period before the successful second or CATCHUP\_CRON run. The latest successfully processed file replaces the earlier active monthly dataset.

Incremental or delta files are not supported.

The original file is not stored in S3 for this flow.

**Required source information**

The fields required for Business 1 processing are:

* partner\_id  
* billing\_date  
* salesperson identifier from sid  
* customer identifier from customer  
* net\_sales\_quantity\_kg

Other existing Daily Sales-compatible fields may be retained for transaction identity and audit. Additional fields not required for this calculation may be ignored.

**Monthly processing**

Only rows whose billing\_date belongs to the previous incentive month are considered.

Rows belonging to other months do not fail the complete file. They are ignored and reported in the rejected row count with the applicable reason.

For each salesperson and customer:

monthly\_net\_sales\_quantity \= SUM(net\_sales\_quantity\_kg)

The customer qualifies as a new transacted customer when monthly\_net\_sales\_quantity is greater than zero.

Multiple valid transaction rows for the same salesperson and customer are allowed and are aggregated. An exact duplicate transaction event must not be counted twice.

The finalized active dataset contains one row per salesperson and qualifying customer in incentive\_new\_transacted\_customer\_activity.

The monthly\_net\_sales\_quantity should be stored with the derived activity row for auditability.

**Conflicting salesperson ownership**

The same customer must not be assigned to multiple salespeople in the same partner and month.

If this occurs:

* All rows for that customer are excluded.  
* Neither salesperson receives achievement for that customer.  
* The affected rows are recorded as rejected with CUSTOMER\_ASSIGNED\_TO\_MULTIPLE\_SALESPEOPLE.  
* Other valid customers in the file continue processing.

A database-level active unique constraint on partner\_id, period\_month, period\_year, and customer\_id should provide a final safeguard against activating the same customer under multiple salespeople.

**Replacement processing**

The new-customer monthly input creates an incentive\_feed\_logs row with feed\_type \= NEW\_TRANSACTED\_CUSTOMERS.

After the complete file has been validated and aggregated, Target Sales performs the following in one transaction:

1. Marks previous active incentive\_new\_transacted\_customer\_activity rows for the partner and period as replaced and inactive.  
2. Inserts the latest accepted qualifying customers as active.  
3. Updates the feed log with total, accepted, and rejected row counts.  
4. Marks the feed log as successful.

A structural file error or processing failure must preserve the previous active monthly dataset.

The source file is rejected when:

* A Business 1 calculation run for the same partner and period is pending or processing.  
* The successful second or CATCHUP\_CRON run has already completed for the period.

The zero-new-customer delivery format is pending confirmation. This does not block implementation of the remaining ingestion, replacement, and calculation flow.

**Target Engine change**

The existing T2 new-customer target changes globally from sales quantity to customer count.

The existing target field continues to be used. No new target table is required.

The T2 target represents:

target\_new\_transacted\_customer\_count

The T2 achievement logic must also change from summing net sales quantity to counting distinct qualifying new customers.

**Business 1 calculation usage**

Business 1 reads only active incentive\_new\_transacted\_customer\_activity rows for the calculation period.

No separate Daily Sales lookup or validation is performed during this incentive-point calculation. The monthly file processing has already determined which new customers have positive net sales quantity.

For a Level 1 Salesperson:

Achievement Count \= own qualifying new transacted customers.

Target Count \= own T2 customer-count target.

For a Level 2 SPV or KAO:

Achievement Count \= own qualifying customers \+ direct Level 1 reportee qualifying customers.

Target Count \= own T2 count target \+ direct Level 1 reportee T2 count targets.

For a Level 3 RSO:

Achievement Count \= own qualifying customers \+ downstream Level 2 own qualifying customers \+ downstream Level 1 own qualifying customers.

Target Count \= own T2 count target \+ downstream Level 2 own T2 count targets \+ downstream Level 1 own T2 count targets.

Each participant receives an independent incentive-point result for their applicable hierarchy scope.

Each participant’s raw own achievement and target value is included exactly once.

If the aggregated target is zero, achievement percentage and points are zero.

The calculated percentage is rounded according to the common Business 1 precision rules and matched against the active NT\_NEW\_TRANSACTED\_OUTLETS slab for the participant’s channel and level.

### **13.7.3 Shared Processing and Audit Rules**

Both customer input flows use incentive\_feed\_logs for attempt status, row counts, error details, audit users, and replacement lineage.

Calculation reads only active monthly input rows.

Every Business 1 point result should record the source feed log or input version used by the calculation so the result can be reproduced and audited.

Input replacement does not automatically trigger recalculation. A corrected input is used by the next MANUAL, CRON, or CATCHUP\_CRON calculation run.

The calculation preflight must reject creation of a Business 1 run while either customer input is pending or processing for the same partner and period.

Customer input activation must recheck that no Business 1 calculation run became pending or processing after the initial request validation.

The Customer Handled refresh and New Customer Monthly ingestion are independent flows:

* Customer Handled provides the denominator for % Transacted Outlets.  
* Daily Sales provides the numerator for % Transacted Outlets.  
* New Customer Monthly provides the numerator for % New Transacted Outlets.  
* The count-based T2 target provides the denominator for % New Transacted Outlets.

# **14\. Admin / Config APIs**

Admin / Config APIs are used to manage Business 1 incentive setup.

This section covers APIs for:

1. Incentive point registry  
2. Incentive point slabs  
3. Total points payout config  
4. AR ageing deduction config  
5. Trader stock day multiplier config

All admin APIs follow the auth rules defined in Section 13\.

All monthly config inputs should use YYYY-MM.

Backend should convert monthly input into date boundaries before saving.

Example: 2026-06

is stored as:  
valid\_from \= 2026-06-01  
valid\_to \= 2026-06-30

## Incentive-points-metric

### 14.1 GET Incentive Schemas

**Existing API**

GET /api/incentives/v1/schemas

This is the existing API used by the frontend for the **Tipe Insentif** dropdown / incentive type selection screen.

This API will remain the common frontend-facing incentive catalogue API for both Business 1 and Business 2\.

No separate frontend-facing API should be introduced for Business 1 incentive points.

**Purpose**

Returns the list of incentive types available for the selected partner.

The frontend uses this API to populate the **Tipe Insentif** dropdown.

The response envelope must remain compatible with the existing Business 2 API: status → data → schemas. Business 1 may return a smaller field set inside each schema item based on what the shared Tipe Insentif screen requires.

For Business 1, seeded incentive point records are mapped into schema-style catalogue items so the shared Tipe Insentif screen can consume them from the same API.

**Partner and Business Resolution**

Each partner belongs to one incentive business.

A partner-business mapping table will be maintained.

Expected mapping:

| Field | Description |
| ----- | ----- |
| partner\_id | Partner identifier |
| business\_code | BUSINESS\_1 or BUSINESS\_2 |
| status | active or inactive |

partner\_id is resolved using the same mechanism currently used by Business 2, through X-Partner-Id / existing partner header flow.

The backend uses partner\_id to resolve business\_code.

**Data Source**

| business\_code | Source Table | Behavior |
| ----- | ----- | ----- |
| BUSINESS\_1 | incentive\_point\_metrics | Map Business 1 incentive points into schema-style response |
| BUSINESS\_2 | incentive\_schemas | Return existing Business 2 schema records |

**New Behavior**

1. API remains GET /api/incentives/v1/schemas.  
2. Existing response envelope must remain unchanged: status → data → schemas.  
3. For BUSINESS\_2 partners, API continues to return records from incentive\_schemas.  
4. For BUSINESS\_1 partners, API returns records from incentive\_point\_metrics mapped into the common catalogue response envelope.  
5. Every returned schema item must include business\_code.  
6. Frontend uses business\_code to decide which business-specific API flow to call next.  
7. Business 1 and Business 2 config/detail/create/update/status APIs remain separate.  
8. Frontend must not infer business from schema\_name or id.  
9. Frontend must not hardcode Business 1 incentive point codes.  
10. Backend remains the source of truth for available incentive types.

**Query Parameters**

Keep the existing Business 2 query parameter behavior.

| Parameter | Required | Description |
| ----- | ----- | ----- |
| search | No | Partial match filter applied to schema\_name. Case-insensitive. Min 1 character, max 100 characters. Leading/trailing whitespace is trimmed. |

For Business 1, search should be applied against incentive\_point\_name and/or incentive\_point\_code.

**Business 1 Field Mapping**

| Response Field | Source |
| ----- | ----- |
| id | incentive\_point\_metrics.id |
| schema\_name | incentive\_point\_metrics.incentive\_point\_name |
| description | incentive\_point\_metrics.description |
| applicable\_salesperson\_types | applicable\_salesperson\_type as array |
| applicable\_supervisor\_types | Derived from applicable\_levels; \[\] if N/A |
| slab\_structure | "threshold" for now |
| allowed\_slab\_types | Don't include |
| supervisor\_has\_target | Don't Include |
| salesperson\_has\_target | Don't include |
| supervisor\_has\_own | Don't Include |
| target\_source\_id | Don’t include |
| created\_by / updated\_by | The column is present in table, default value is null |
| business\_code | "BUSINESS\_1" (always included) |

For Business 2, all existing fields continue to come from incentive\_schemas, with business\_code added as BUSINESS\_2.

**Response Structure**

The response envelope must remain the same as Business 2: status → data → schemas

Example response for Business 1 partner:

| {  "status": "success",  "data": {    "schemas": \[      {        "id": "\<uuid\>",        "schema\_name": "Volume Achievement",        "description": "Business 1 volume achievement incentive point",        "slab\_structure": "threshold",        "applicable\_salesperson\_types": \["NON\_TRADER"\],        "applicable\_supervisor\_types": \["LEVEL\_2", "LEVEL\_3"\],        "created\_by": null,        "updated\_by": null,        "business\_code": "BUSINESS\_1"      }    \]  }} |
| :---- |

Example response for Business 2 partner:

| {   "status": "success",   "data": {        "schemas": \[            {                "id": "",                "schema\_name": "call\_plan",                "description": "Daily call plan incentive, summed monthly",                "slab\_structure": "threshold",                "allowed\_slab\_types": \["value", "percentage"\],                "applicable\_salesperson\_types": \["STO", "SFT"\],                "applicable\_supervisor\_types": \["SPV"\],                "supervisor\_has\_target": false,                "salesperson\_has\_target": true,                "supervisor\_has\_own": false,                "target\_source\_id": "T3",                "created\_by": "\<uuid\>",                "updated\_by": "\<uuid\>",                "business\_code": "BUSINESS\_2"            }        \]    }} |
| :---- |

B1 and B2 will have different sets of keys available in the response, to accommodate this we will have to take few fields out of the required list from the ws1 schema file.

| Field | B1 item | B2 item |
| ----- | ----- | ----- |
| allowed\_slab\_types | absent | present |
| supervisor\_has\_target | absent | present |
| salesperson\_has\_target | absent | present |
| supervisor\_has\_own | absent | present |
| target\_source\_id | absent | present |

**Frontend Routing Rule**

Frontend uses business\_code from the selected schema item to decide which API flow to call next.

| business\_code | Frontend Routing |
| ----- | ----- |
| BUSINESS\_1 | Call Business 1 config/detail/create/update/status APIs |
| BUSINESS\_2 | Call existing Business 2 config/detail/create/update/status APIs |

Frontend should pass the selected id as the schema/incentive identifier to the next API flow.

For Business 1, this id maps to incentive\_point\_metrics.id.

For Business 2, this id maps to incentive\_schemas.id.

**Validation Rules**

1. X-Partner-Id must be present.  
2. partner\_id must map to one active business\_code.  
3. If no active mapping exists, return PARTNER\_BUSINESS\_MAPPING\_NOT\_FOUND.  
4. If mapping returns unsupported business\_code, return INVALID\_BUSINESS\_CODE.  
5. If search is provided, it must follow the existing Business 2 validation rules.  
6. business\_code must be included in every returned schema item.  
7. The response envelope must remain status → data → schemas.

**Error Responses**

Partner-business mapping missing:

| {    "status": "error",    "error\_code": "PARTNER\_BUSINESS\_MAPPING\_NOT\_FOUND",    "message": "No active business mapping found for the partner."} |
| :---- |

Invalid business code:

| {    "status": "error",    "error\_code": "INVALID\_BUSINESS\_CODE",    "message": "Partner business\_code is invalid."} |
| :---- |

No records found:

Use the existing Business 2 NOT\_FOUND response structure.

**Notes**

This API is only the common incentive catalogue API.

It does not merge Business 1 and Business 2 configuration logic.

Business-specific APIs remain separate after this API.

Only the common catalogue envelope is shared. Business 1 and Business 2 schema items may have different optional fields. WS1 schema validation should only require the common fields needed by the shared Tipe Insentif screen.

## Incentive Point Slab Configs

### 14.2 GET Incentive Point Slab Config

Endpoint

GET /api/incentives/v1/incentive-points/:incentive\_point\_metric\_id/slab-configs

**Purpose** \- slab config is a row in incentive\_schema\_configs; slab rows in incentive\_point\_slabs reference it via slab\_config\_id

**Path Parameters**

| Parameter | Required | Description |
| ----- | ----- | ----- |
| incentive\_point\_metric\_id | Yes | Incentive point ID |

Query Parameters

| Parameter | Required | Format / Allowed Values | Description |
| ----- | ----- | ----- | ----- |
| page | Yes | Integer | default 1 |
| limit | Yes | Integer | Default 20 |
| valid\_from | No | YYYY-MM | Filters configs starting from this month |
| valid\_to | No | YYYY-MM | Filters configs ending before or at this month |
| status | No | active, inactive | Filters by status |

Response

| {   "status": "success",   "data": {     "incentive\_point\_id": "\<uuid\>",     "incentive\_point\_code": "NT\_VOLUME\_ACHIEVEMENT",     "incentive\_point\_name": "Volume Achievement",     "slab\_configs": \[       {         "slab\_config\_id": "\<uuid\>",         "valid\_from": "2025-10-01",         "valid\_to": "2025-10-31",         "status": "active",         "slab\_count": 6,         "created\_by": "\<uuid\>",         "created\_by\_name": "Mikhael Arthura",         "created\_at": "2025-09-24T10:14:00Z",         "updated\_by": "\<uuid\>",         "updated\_by\_name": "Mikhael Arthura",         "updated\_at": "2025-09-24T10:14:00Z"       }     \],     "pagination": {          "current\_page": 1,          "total\_pages": 5,          "total\_records": 48,          "records\_per\_page": 10,          "has\_next": true,          "has\_previous": false        }   } } |
| :---- |

## **Incentive Point Slab Config Detail**

### 14.3 GET Incentive Point Slab Config Detail

Endpoint

GET /api/incentives/v1/incentive-points/:incentive\_point\_metric\_id/slab-configs/:slab\_config\_id

Purpose

Returns slab rows for one incentive point slab config.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| incentive\_point\_metric\_id | Yes | Incentive point ID |

| SELECT channel, salesperson\_type, level, id, band\_order, operator, value, pointsFROM incentive\_point\_slabsWHERE slab\_config\_id \= :slab\_config\_id AND is\_deprecated \= falseORDER BY channel, salesperson\_type, level, band\_order; |
| :---- |

The API layer groups these flat rows into a single flat groups\[\] → slabs\[\] structure in code. Each group represents one (channel, salesperson\_type, level) combination — or (salesperson\_type, level) when the incentive point does not require a channel. channel is included on a group object only when incentive\_point. requires\_channel \= true. It is omitted entirely (not null) when requires\_channel \= false.

**Response — requires\_channel \= true:**

| {  "status": "success",  "data": {    "incentive\_point": {      "id": "\<uuid\>",      "incentive\_point\_code": "NT\_VOLUME\_ACHIEVEMENT",      "incentive\_point\_name": "Volume Achievement",      "requires\_channel": true,      "applicable\_levels": \[1, 2, 3\]    },    "slab\_config": {      "slab\_config\_id": "\<uuid\>",      "valid\_from": "2025-10-01",      "valid\_to": "2025-10-31",      "status": "active",      "groups": \[        { "channel": "Catering", "salesperson\_type": "NON\_TRADER", "level": 1,          "slabs": \[            { "id": "\<uuid\>", "band\_order": 1, "operator": "\>=", "value": 50, "points": 1 },            { "id": "\<uuid\>", "band\_order": 2, "operator": "\>", "value": 80, "points": 2 }          \]        },        { "channel": "Catering", "salesperson\_type": "NON\_TRADER", "level": 2,          "slabs": \[            { "id": "\<uuid\>", "band\_order": 1, "operator": "\>=", "value": 50, "points": 1 }          \]        }      \]    }  }} |
| :---- |

**Response — requires\_channel \= false:**

| {  "status": "success",  "data": {    "incentive\_point": {      "id": "\<uuid\>",      "incentive\_point\_code": "TR\_STOCK\_BY\_PRODUCT",      "incentive\_point\_name": "Stock Level \- By Product",      "requires\_channel": false,      "applicable\_levels": \[1, 2, 3\]    },    "slab\_config": {      "slab\_config\_id": "\<uuid\>",      "valid\_from": "2025-10-01",      "valid\_to": "2025-10-31",      "status": "active",      "groups": \[        { "salesperson\_type": "TRADER", "level": 1,          "slabs": \[ { "id": "\<uuid\>", "band\_order": 1, "operator": "\>=", "value": 50, "points": 1 } \]        },        { "salesperson\_type": "TRADER", "level": 2,          "slabs": \[ { "id": "\<uuid\>", "band\_order": 1, "operator": "\>=", "value": 50, "points": 1 } \]        }      \]    }  }} |
| :---- |

Note on ordered lookup:

The example may contain rows such as:  
\>= 50 → 1 point  
\> 80 → 2 points

For achievement value 90, both rows match. Backend selects the row with the highest points, so the \> 80 → 2 points row wins.

This is expected behavior and should not be treated as overlapping invalid configuration.

### 14.4 POST Incentive Point Slab Set

Endpoint

POST /api/incentives/v1/incentive-points/:incentive\_point\_metric\_id/slab-configs

**Purpose** \- Creates a slab config for one incentive point, covering one or more channels, each with one or more salesperson types and their slab rows, in a single request.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| incentive\_point\_metric\_id | Yes | Incentive point ID |

**Request — requires\_channel \= true:**

| {  "valid\_from": "2026-06",  "valid\_to": "2026-06",  "groups": \[    { "channel": "Catering", "salesperson\_type": "NON\_TRADER", "level": 1,      "slabs": \[        { "band\_order": 1, "operator": "\>=", "value": 50, "points": 1 },        { "band\_order": 2, "operator": "\>", "value": 80, "points": 2 }      \]    },    { "channel": "Catering", "salesperson\_type": "NON\_TRADER", "level": 2,      "slabs": \[ { "band\_order": 1, "operator": "\>=", "value": 50, "points": 1 } \]    },    { "channel": "Catering", "salesperson\_type": "NON\_TRADER", "level": 3,      "slabs": \[ { "band\_order": 1, "operator": "\>=", "value": 50, "points": 1 } \]    },    { "channel": "QSR", "salesperson\_type": "NON\_TRADER", "level": 1,      "slabs": \[ { "band\_order": 1, "operator": "\>=", "value": 50, "points": 1 } \]    }  \]} |
| :---- |

**Request — requires\_channel \= false:**

| {  "valid\_from": "2026-06",  "valid\_to": "2026-06",  "groups": \[    { "salesperson\_type": "TRADER", "level": 1,      "slabs": \[ { "band\_order": 1, "operator": "\>=", "value": 50, "points": 1 } \]    },    { "salesperson\_type": "TRADER", "level": 2,      "slabs": \[ { "band\_order": 1, "operator": "\>=", "value": 50, "points": 1 } \]    }  \]} |
| :---- |

**Validation Rules**

* incentive\_point\_metric\_id must be a valid UUID.  
* Incentive point must exist.  
* valid\_from and valid\_to must be valid YYYY-MM values.  
* valid\_to must be greater than or equal to valid\_from.  
* If incentive point's requires\_channel \= true: every group object must include a non-null, non-empty "channel" field. Missing it → reject VALIDATION\_ERROR.  
* If incentive point's requires\_channel \= false: no group object may include a "channel" field. Including it → reject VALIDATION\_ERROR.  
* salesperson\_type must be NON\_TRADER or TRADER, and must be a member of the incentive point's applicable\_salesperson\_type array.  
* level must be 1, 2, or 3, and must be a member of the incentive point's applicable\_levels array.  
* slabs must be non-empty for point-producing incentive points.  
* Slab configuration is allowed only when the incentive point's component\_type \= POINT. If component\_type \= DEDUCTION, reject with SLAB\_NOT\_ALLOWED\_FOR\_DEDUCTION\_COMPONENT.  
* operator must be one of: \>, \>=, \=.  
* value must be numeric.  
* points must be an integer and greater than or equal to 0\.  
* band\_order must be unique within the same (channel, salesperson\_type, level) group.  
* Multiple slab rows within the same (channel, salesperson\_type, level) group may match the same achievement value — this is valid because Business 1 uses ordered threshold lookup. The only structural duplicate rejected at create/update time is an exact (operator, value) repeat within that group; rows sharing only a value but with different operators are allowed.  
* When multiple rows match during calculation, backend selects the matching row with the highest points value.  
* If multiple matching rows have the same highest points value, backend uses lowest band\_order as deterministic tie-breaker, then earliest created row/id if still tied.  
* Duplicate operator \+ value rows are not allowed within the same (channel, salesperson\_type, level) group.  
* No duplicate (channel, salesperson\_type, level) combination within the same request.  
* Period must not overlap with another active slab config for the same partner and incentive point. This check is header-level only — it does not consider channel, salesperson\_type, or level, since one config covers the entire slab tree for that incentive point and period. Enforced at both application level (pre-check) and database level via excl\_isc\_no\_active\_overlap.  
* If a concurrent request causes two overlapping configs to be submitted at the same time, the database constraint rejects the losing insert with an exclusion violation.  
* Config changes are rejected when a Business 1 calculation run is pending or processing for the same partner and impacted period.

Response — requires\_channel \= true

| {  "status": "success",  "data": {    "slab\_config\_id": "\<uuid\>",    "incentive\_point\_id": "\<uuid\>",    "incentive\_point\_code": "NT\_VOLUME\_ACHIEVEMENT",    "valid\_from": "2026-06-01",    "valid\_to": "2026-06-30",    "status": "active",    "groups": \[      { "channel": "Catering", "salesperson\_type": "NON\_TRADER", "level": 1,        "slabs": \[          { "id": "\<uuid\>", "band\_order": 1, "operator": "\>=", "value": 50, "points": 1 },          { "id": "\<uuid\>", "band\_order": 2, "operator": "\>", "value": 80, "points": 2 }        \]      },      { "channel": "Catering", "salesperson\_type": "NON\_TRADER", "level": 2,        "slabs": \[ { "id": "\<uuid\>", "band\_order": 1, "operator": "\>=", "value": 50, "points": 1 } \]      },      { "channel": "Catering", "salesperson\_type": "NON\_TRADER", "level": 3,        "slabs": \[ { "id": "\<uuid\>", "band\_order": 1, "operator": "\>=", "value": 50, "points": 1 } \]      },      { "channel": "QSR", "salesperson\_type": "NON\_TRADER", "level": 1,        "slabs": \[ { "id": "\<uuid\>", "band\_order": 1, "operator": "\>=", "value": 50, "points": 1 } \]      }    \]  }} |
| :---- |

**Response — requires\_channel \= false**

| {  "status": "success",  "data": {    "slab\_config\_id": "\<uuid\>",    "incentive\_point\_id": "\<uuid\>",    "incentive\_point\_code": "TR\_STOCK\_BY\_PRODUCT",    "valid\_from": "2026-06-01",    "valid\_to": "2026-06-30",    "status": "active",    "groups": \[      { "salesperson\_type": "TRADER", "level": 1,        "slabs": \[ { "id": "\<uuid\>", "band\_order": 1, "operator": "\>=", "value": 50, "points": 1 } \]      },      { "salesperson\_type": "TRADER", "level": 2,        "slabs": \[ { "id": "\<uuid\>", "band\_order": 1, "operator": "\>=", "value": 50, "points": 1 } \]      }    \]  }} |
| :---- |

### 14.5 PATCH Incentive Point Slab Set

Endpoint

PATCH /api/incentives/v1/incentive-points/:incentive\_point\_metric\_id/slab-configs/:slab\_config\_id

Purpose \- Updates an existing slab config for one incentive point. The slab config is identified directly by slab\_config\_id in the path. is\_config\_updated and is\_slabs\_updated independently control whether the period and/or the slab rows are updated in this call.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| incentive\_point\_metric\_id | Yes | Incentive point ID |
| slab\_config\_id | Yes | Slab config ID (row in incentive\_schema\_configs) |

**Request — requires\_channel \= true**

| {  "is\_config\_updated": false,  "is\_slabs\_updated": true,  "updated\_valid\_from": "2026-06",  "updated\_valid\_to": "2026-06",  "groups": \[    { "channel": "Catering", "salesperson\_type": "NON\_TRADER", "level": 1,      "slabs": \[        { "band\_order": 1, "operator": "\>=", "value": 90, "points": 1 },        { "band\_order": 2, "operator": "\>", "value": 100, "points": 5 }      \]    },    { "channel": "Catering", "salesperson\_type": "NON\_TRADER", "level": 2,      "slabs": \[ { "band\_order": 1, "operator": "\>=", "value": 90, "points": 1 } \]    },    { "channel": "Catering", "salesperson\_type": "NON\_TRADER", "level": 3,      "slabs": \[ { "band\_order": 1, "operator": "\>=", "value": 90, "points": 1 } \]    }  \]} |
| :---- |

**Request — requires\_channel \= false**

| {  "is\_config\_updated": false,  "is\_slabs\_updated": true,  "groups": \[    { "salesperson\_type": "TRADER", "level": 1,      "slabs": \[ { "band\_order": 1, "operator": "\>=", "value": 90, "points": 1 } \]    }  \]} |
| :---- |

groups must contain the complete desired slab tree for this config. Any (channel, salesperson\_type, level) — or (salesperson\_type, level) when requires\_channel \= false — combination that is currently active but is not included in this request will be deprecated with no replacement.

**Request Validation**

* incentive\_point\_metric\_id must be a valid UUID; incentive point must exist. Otherwise reject with INCENTIVE\_POINT\_NOT\_FOUND.  
* slab\_config\_id must be a valid UUID, must exist, and must belong to the given incentive\_point\_metric\_id. Otherwise reject with SLAB\_SET\_NOT\_FOUND.  
* is\_config\_updated and is\_slabs\_updated must be present and must be booleans.  
* At least one of is\_config\_updated or is\_slabs\_updated must be true.  
* If is\_config\_updated \= true → updated\_valid\_from and updated\_valid\_to must be present, in YYYY-MM format, and updated\_valid\_to \>= updated\_valid\_from.  
* If is\_slabs\_updated \= true → groups must be present and must be a non-empty array.  
* If is\_slabs\_updated \= true and requires\_channel \= true: every group must include a non-null, non-empty "channel" field. Missing it → reject VALIDATION\_ERROR.  
* If is\_slabs\_updated \= true and requires\_channel \= false: no group may include a "channel" field. Including it → reject VALIDATION\_ERROR.  
* Failing any of the above → HTTP 400 VALIDATION\_ERROR.

**Standard Edit Rules (applies at header/period level)**

Evaluated against the existing config's period, resolved via slab\_config\_id.

| Case | Config Period | Allowed Action |
| ----- | ----- | ----- |
| Case 1 | valid\_from and valid\_to are current/future | Full edit allowed |
| Case 2 | valid\_from is past, valid\_to is current/future | Only valid\_to can be edited; slabs cannot be edited |
| Case 3 | valid\_from and valid\_to are both past | Edit not permitted for normal users |

**Additional Edit Rules**

* Case 3 → reject with HTTP 400 EDIT\_NOT\_PERMITTED.  
* Case 2 and is\_slabs\_updated \= true → reject with HTTP 400 SLABS\_NOT\_EDITABLE.  
* Case 2 and is\_config\_updated \= true and updated\_valid\_from differs from the existing valid\_from → reject with HTTP 400 VALID\_FROM\_NOT\_EDITABLE.  
* If is\_config\_updated \= true, updated\_valid\_from/updated\_valid\_to are checked for period overlap against other active configs for the same incentive\_point\_metric\_id and partner\_id, excluding the current config. Overlap.  
* This check is backed by excl\_isc\_no\_active\_overlap. If a concurrent update or activation races this one, the database constraint rejects the losing transaction with an exclusion violation.

**Slab Update Rules — full replace**

* If is\_slabs\_updated \= true: all existing incentive\_point\_slabs rows under this slab\_config\_id — across every channel and group, not only those included in the request — are set is\_deprecated \= true. New slab rows are then inserted from the request body. The deprecate \+ insert runs in one transaction.  
* Any (channel, salesperson\_type, level) — or (salesperson\_type, level) when requires\_channel \= false — group that was previously active but is not included in the request ends up with no active slabs after the update completes.  
* If is\_slabs\_updated \= false, slab rows are left untouched entirely.  
* If is\_config\_updated \= true: incentive\_schema\_configs.valid\_from/valid\_to are updated to updated\_valid\_from/updated\_valid\_to, subject to the Standard Edit Rules and Additional Edit Rules above.  
* Update is rejected when a Business 1 calculation run is pending or processing for the same partner and impacted period. Reject with CONFIG\_CHANGE\_RUN\_IN\_PROGRESS.  
* Existing calculated results are not automatically recalculated. Updated slabs apply on the next MANUAL, CRON, or CATCHUP\_CRON run.  
* band\_order must be unique within the same (channel, salesperson\_type, level) group.  
* Duplicate operator \+ value rows are not allowed within the same (channel, salesperson\_type, level) group.  
* Multiple rows may match the same achievement value.  
* During calculation, backend selects the matching row with the highest points.  
* If multiple matching rows have the same highest points, backend uses lowest band\_order as deterministic tie-breaker, then earliest created row/id if still tied.  
* New slab rows must also pass the same field-level validation as create: operator must be one of \>, \>=, \=; value must be numeric; points must be an integer and greater than or equal to 0; band\_order must be unique within the same (channel, salesperson\_type, level) group.  
* Slab update is allowed only when the incentive point's component\_type \= POINT. If component\_type \= DEDUCTION and is\_slabs\_updated \= true, reject with SLAB\_NOT\_ALLOWED\_FOR\_DEDUCTION\_COMPONENT.

**Note — replacement granularity**

Replacement is scoped to the entire slab\_config\_id. If is\_slabs\_updated \= true, all currently active slab rows under the slab\_config\_id are deprecated, and the request body becomes the complete active slab tree for that config. Callers must resend all required groups and slab rows. Any previously active group omitted from the request will have no active slabs after update.

**Response — requires\_channel \= true**

| {  "status": "success",  "data": {    "slab\_config\_id": "\<uuid\>",    "incentive\_point\_id": "\<uuid\>",    "incentive\_point\_code": "NT\_VOLUME\_ACHIEVEMENT",    "valid\_from": "2026-06-01",    "valid\_to": "2026-06-30",    "status": "active",    "message": "Incentive point slab set updated successfully",    "groups": \[      { "channel": "Catering", "salesperson\_type": "NON\_TRADER", "level": 1,        "slabs": \[          { "id": "\<uuid\>", "band\_order": 1, "operator": "\>=", "value": 90, "points": 1 },          { "id": "\<uuid\>", "band\_order": 2, "operator": "\>", "value": 100, "points": 5 }        \]      },      { "channel": "Catering", "salesperson\_type": "NON\_TRADER", "level": 2,        "slabs": \[ { "id": "\<uuid\>", "band\_order": 1, "operator": "\>=", "value": 90, "points": 1 } \]      },      { "channel": "Catering", "salesperson\_type": "NON\_TRADER", "level": 3,        "slabs": \[ { "id": "\<uuid\>", "band\_order": 1, "operator": "\>=", "value": 90, "points": 1 } \]      }    \]  }} |
| :---- |

**Response — requires\_channel \= false**

| {  "status": "success",  "data": {    "slab\_config\_id": "\<uuid\>",    "incentive\_point\_id": "\<uuid\>",    "incentive\_point\_code": "TR\_STOCK\_BY\_PRODUCT",    "valid\_from": "2026-06-01",    "valid\_to": "2026-06-30",    "status": "active",    "message": "Incentive point slab set updated successfully",    "groups": \[      { "salesperson\_type": "TRADER", "level": 1,        "slabs": \[ { "id": "\<uuid\>", "band\_order": 1, "operator": "\>=", "value": 90, "points": 1 } \]      }    \]  }} |
| :---- |

### 14.6 PATCH Incentive Point Slab Config Status

Endpoint

PATCH /api/incentives/v1/incentive-points/:incentive\_point\_metric\_id/slab-configs/:slab\_config\_id/status

Purpose \- Activates or deactivates one slab config in its entirety (all channels, all groups) — the header row in incentive\_schema\_configs. Does not touch incentive\_point\_slabs rows — deactivation only flips the config's status flag, which the calculation engine's slab-resolution already filters on. Per-channel or per-group deactivation is out of scope for this API.

**Path Parameters**

| Parameter | Required | Description |
| ----- | ----- | ----- |
| incentive\_point\_metric\_id | Yes | Incentive point ID |
| slab\_config\_id | Yes | Slab config ID (row in incentive\_schema\_configs) |

Request

| {   "status": "inactive" } |
| :---- |

**Validation Rules**

* incentive\_point\_metric\_id must be a valid UUID; incentive point must exist. Otherwise reject with INCENTIVE\_POINT\_NOT\_FOUND.  
* slab\_config\_id must be a valid UUID, must exist, and must belong to the given incentive\_point\_metric\_id. Otherwise reject with SLAB\_SET\_NOT\_FOUND.  
* status must be active or inactive. Otherwise reject with VALIDATION\_ERROR.  
* Past configs cannot be activated/deactivated by normal users (per Standard Edit Rules, Case 3). Reject with EDIT\_NOT\_PERMITTED.  
* If activating a slab config, backend must check period overlap against other active slab configs for the same partner and incentive point. Overlap → reject with CONFIG\_OVERLAP.  
* This check is backed by excl\_isc\_no\_active\_overlap. If a concurrent activation races this one, the database constraint rejects the losing transaction with an exclusion violation.  
* Status changes are rejected when a Business 1 calculation run is pending or processing for the same partner and impacted period. Reject with CONFIG\_CHANGE\_RUN\_IN\_PROGRESS.  
* Status changes are audited via the existing updated\_by/updated\_at columns on incentive\_schema\_configs.  
* Deactivating a slab config does not touch incentive\_point\_slabs rows (no is\_deprecated change) — it only flips incentive\_schema\_configs.status, which the calculation engine's slab-resolution already filters on.  
* Status change always applies to the entire config. There is no per-channel or per-group deactivation path.

Response

| {  "status": "success",  "data": {    "slab\_config\_id": "\<uuid\>",    "incentive\_point\_id": "\<uuid\>",    "incentive\_point\_code": "NT\_VOLUME\_ACHIEVEMENT",    "valid\_from": "2026-06-01",    "valid\_to": "2026-06-30",    "status": "inactive",    "message": "Incentive point slab config status updated successfully"  }} |
| :---- |

## **Payout Configs**

### 14.7 GET Payout Configs

Endpoint

GET /api/incentives/v1/payout-configs

Purpose \- Returns total points-to-payout configuration list.

**Query Parameters**

| Parameter | Required | Allowed Values / Format | Description |
| ----- | ----- | ----- | ----- |
| page | Yes | Integer, default 1 | Page number |
| limit | Yes | Integer, default 20 | Rows per page |
| salesperson\_type | No | ALL | Filters payout configs by salesperson type |
| status | No | active, inactive | Filters payout configs by status |

Response

| {  "status": "success",  "data": {    "configs": \[      {        "id": "\<uuid\>",        "salesperson\_type": "ALL",        "valid\_from": "2026-06-01",        "valid\_to": "2026-06-30",        "status": "active",        "tier\_count": 15,        "created\_by": "\<uuid\>",        "created\_by\_name": "Mikhael Arthura",        "created\_at": "2025-09-24T10:14:00Z",        "updated\_by": "\<uuid\>",        "updated\_by\_name": "Mikhael Arthura",        "updated\_at": "2025-09-24T10:14:00Z"      }    \],    "pagination": {      "page": 1,      "limit": 20,      "total": 200,      "total\_pages": 10    }  }} |
| :---- |

salesperson\_type \= ALL means the payout config applies to both Trader and Non-Trader.

tier\_count \= distinct total\_points count for this payout\_config\_id, computed via:

| SELECT payout\_config\_id, COUNT(DISTINCT total\_points) AS tier\_countFROM incentive\_score\_payoutsWHERE payout\_config\_id \= ANY(:config\_ids) AND is\_deprecated \= falseGROUP BY payout\_config\_id; |
| :---- |

updated\_by/updated\_by\_name/updated\_at reflect the last edit to either the config header or its payout rows.

The "Cari Berdasarkan Tipe Salesman" search box on the list screen is out of scope for this pass — salesperson\_type filter stays ALL\-only for now.

### 14.8 GET Payout Config Detail

**Endpoint**

GET /api/incentives/v1/payout-configs/:config_id

**Purpose**  
Returns total points-to-payout table, grouped by Skor (total\_points), with each Skor's payout amount per level.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| config\_id | Yes | Payout config ID |

Response

| {  "status": "success",  "data": {    "config": {      "id": "\<uuid\>",      "salesperson\_type": "ALL",      "valid\_from": "2026-06-01",      "valid\_to": "2026-06-30",      "status": "active",      "payout\_rows": \[        {          "total\_points": 1,          "levels": \[            { "level": 1, "payout\_amount": 200000 },            { "level": 2, "payout\_amount": 200000 },            { "level": 3, "payout\_amount": 200000 }          \]        },        {          "total\_points": 2,          "levels": \[            { "level": 1, "payout\_amount": 400000 },            { "level": 2, "payout\_amount": 400000 },            { "level": 3, "payout\_amount": 400000 }          \]        }      \]    }  }} |
| :---- |

Level mapping:

Level 1 \= SALES  
 Level 2 \= SPV / KAO  
 Level 3 \= RSO

total\_points starts at 1 — the total\_points \= 0 case is not stored; it's handled directly by application logic at calculation time.  
Query builds payout\_rows\[\] from incentive\_score\_payouts filtered to is\_deprecated \= false only.

### 14.9 POST Payout Config

**Endpoint**

POST /api/incentives/v1/payout-configs

**Purpose**  
Business 1 uses a single shared payout table for Trader and Non-Trader — no salesperson\_type distinction is stored on incentive\_score\_payouts.

**Request**

| {  "salesperson\_type": "ALL",  "valid\_from": "2026-06",  "valid\_to": "2026-06",  "payout\_rows": \[    {      "total\_points": 1,      "levels": \[        { "level": 1, "payout\_amount": 200000 },        { "level": 2, "payout\_amount": 300000 },        { "level": 3, "payout\_amount": 325000 }      \]    },    {      "total\_points": 2,      "levels": \[        { "level": 1, "payout\_amount": 400000 },        { "level": 2, "payout\_amount": 600000 },        { "level": 3, "payout\_amount": 650000 }      \]    }  \]} |
| :---- |

	  
**Validation Rules**

1. valid\_from and valid\_to must be valid YYYY-MM values.  
2. valid\_to must be greater than or equal to valid\_from.  
3. salesperson\_type must be ALL. Otherwise reject with VALIDATION\_ERROR. ALL means the config applies to both Trader and Non-Trader participants — payout rows are shared, not duplicated per type.  
4. Period must not overlap with another active payout config for the same partner. Since Phase 1 supports only ALL, only one active ALL payout config can exist for the same partner and overlapping period. Overlap → reject with CONFIG\_OVERLAP.  
5. This check is backed by excl\_ispc\_no\_active\_overlap. If a concurrent request races past the lock (e.g. a non-API write), the database constraint rejects the losing transaction with an exclusion violation.  
6. total\_points must be an integer greater than 0\. total\_points \= 0 must **not** be included in the request — reject with VALIDATION\_ERROR if present. (Handled directly by application logic at calculation time, not stored.)  
7. No duplicate total\_points value within the same request. Reject with VALIDATION\_ERROR.  
8. Each payout\_rows entry must include exactly 3 levels objects — one each for level 1, 2, and 3\. Missing or duplicate level within a Skor entry → reject VALIDATION\_ERROR.  
9. level must be 1, 2, or 3\.  
10. payout\_amount must be greater than or equal to 0\.  
11. Backend should validate total\_points continuity from 1 to the highest configured total\_points, so no middle value is missed. Reject with TOTAL\_POINTS\_CONTINUITY\_ERROR.  
12. If payout values are not increasing with total\_points, allow save but return a warning (NON\_MONOTONIC\_PAYOUT).  
13. Config creation is rejected when a Business 1 calculation run is pending or processing for the same partner and impacted period. Reject with CONFIG\_CHANGE\_RUN\_IN\_PROGRESS.

**Response**

| {  "status": "success",  "data": {    "config\_id": "\<uuid\>",    "salesperson\_type": "ALL",    "valid\_from": "2026-06-01",    "valid\_to": "2026-06-30",    "status": "active",    "payout\_rows": \[      {        "total\_points": 1,        "levels": \[          { "level": 1, "payout\_amount": 200000 },          { "level": 2, "payout\_amount": 300000 },          { "level": 3, "payout\_amount": 325000 }        \]      },      {        "total\_points": 2,        "levels": \[          { "level": 1, "payout\_amount": 400000 },          { "level": 2, "payout\_amount": 600000 },          { "level": 3, "payout\_amount": 650000 }        \]      }    \],    "warnings": \[\]  }} |
| :---- |

**Response with Warning**

| {  "status": "success",  "data": {    "config\_id": "\<uuid\>",    "salesperson\_type": "ALL",    "valid\_from": "2026-06-01",    "valid\_to": "2026-06-30",    "status": "active",    "payout\_rows": \[ \],    "warnings": \[      {        "code": "NON\_MONOTONIC\_PAYOUT",        "message": "Payout amount for a higher total\_points value is lower than or equal to a lower total\_points value."      }    \]  }} |
| :---- |

### 14.10 PATCH Payout Config

Endpoint

PATCH /api/incentives/v1/payout-configs/:config\_id

**Purpose**  
Updates an existing payout config, identified by config\_id. is\_config\_updated and is\_points\_updated independently control whether the period and/or the payout rows are updated in this call.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| config\_id | Yes | Payout config ID |

Request

| {  "is\_config\_updated": false,  "is\_points\_updated": true,  "updated\_valid\_from": "2026-06",  "updated\_valid\_to": "2026-06",  "payout\_rows": \[    {      "total\_points": 1,      "levels": \[        { "level": 1, "payout\_amount": 200000 },        { "level": 2, "payout\_amount": 300000 },        { "level": 3, "payout\_amount": 325000 }      \]    },    {      "total\_points": 2,      "levels": \[        { "level": 1, "payout\_amount": 400000 },        { "level": 2, "payout\_amount": 600000 },        { "level": 3, "payout\_amount": 650000 }      \]    }  \]} |
| :---- |

payout\_rows must contain the **complete** desired tier list — this mirrors the UI's own renumbering behavior (deleting Skor 2 shifts Skor 3→2, 4→3, etc.). There is no per-tier patch; the whole set is replaced.

**Request Validation**

* config\_id must be a valid UUID and must exist. Otherwise reject with PAYOUT\_CONFIG\_NOT\_FOUND.  
* is\_config\_updated and is\_points\_updated must be present and must be booleans.  
* At least one of is\_config\_updated or is\_points\_updated must be true.  
* If is\_config\_updated \= true → updated\_valid\_from and updated\_valid\_to must be present, in YYYY-MM format, and updated\_valid\_to \>= updated\_valid\_from.  
* If is\_points\_updated \= true → payout\_rows must be present and a non-empty array, and must pass the same field-level rules as (rules 5–11: no total\_points \= 0, no duplicate total\_points, exactly 3 levels per entry, level in 1/2/3, payout\_amount \>= 0, continuity from 1, NON\_MONOTONIC\_PAYOUT warning).  
* Failing any of the above → HTTP 400 VALIDATION\_ERROR.

**Standard Edit Rules** (applies at header/period level, evaluated against the existing config's period)

| Case | Config Period | Allowed Action |
| ----- | ----- | ----- |
| Case 1 | valid\_from and valid\_to are current/future | Full edit allowed |
| Case 2 | valid\_from is past, valid\_to is current/future | Only valid\_to can be edited; payout\_rows cannot be edited |
| Case 3 | valid\_from and valid\_to are both past | Edit not permitted for normal users |

**Additional Edit Rules**

* Case 3 → reject with HTTP 400 EDIT\_NOT\_PERMITTED.  
* Case 2 and is\_points\_updated \= true → reject with HTTP 400 POINTS\_NOT\_EDITABLE.  
* Case 2 and is\_config\_updated \= true and updated\_valid\_from differs from the existing valid\_from → reject with HTTP 400 VALID\_FROM\_NOT\_EDITABLE.  
* If is\_config\_updated \= true, updated\_valid\_from/updated\_valid\_to are checked for period overlap against other active ALL payout configs for the same partner, excluding the current config.  
* This check is backed by excl\_ispc\_no\_active\_overlap. If a concurrent request races past the lock (e.g. a non-API write), the database constraint rejects the losing transaction with an exclusion violation.

**Payout Rows Update Rules — full replace**

* If is\_points\_updated \= true: all existing active (is\_deprecated \= false) incentive\_score\_payouts rows under this payout\_config\_id are marked is\_deprecated \= true, and new rows are inserted from payout\_rows with is\_deprecated \= false in one transaction.  
* If is\_points\_updated \= false, payout rows are left untouched entirely.  
* If is\_config\_updated \= true: incentive\_score\_payout\_configs.valid\_from/valid\_to are updated to updated\_valid\_from/updated\_valid\_to, subject to the Standard Edit Rules and Additional Edit Rules above.  
* Update is rejected when a Business 1 calculation run is pending or processing for the same partner and impacted period. Reject with CONFIG\_CHANGE\_RUN\_IN\_PROGRESS.  
* Existing calculated results are not automatically recalculated. Updated payout rows apply on the next MANUAL, CRON, or CATCHUP\_CRON run.

Response

| {  "status": "success",  "data": {    "config\_id": "\<uuid\>",    "salesperson\_type": "ALL",    "valid\_from": "2026-06-01",    "valid\_to": "2026-06-30",    "status": "active",    "message": "Payout config updated successfully",    "payout\_rows": \[      {        "total\_points": 1,        "levels": \[          { "level": 1, "payout\_amount": 200000 },          { "level": 2, "payout\_amount": 300000 },          { "level": 3, "payout\_amount": 325000 }        \]      },      {        "total\_points": 2,        "levels": \[          { "level": 1, "payout\_amount": 400000 },          { "level": 2, "payout\_amount": 600000 },          { "level": 3, "payout\_amount": 650000 }        \]      }    \]  }} |
| :---- |

### 14.11 PATCH Payout Config Status

Endpoint

PATCH /api/incentives/v1/payout-configs/:config\_id/status

**Purpose**  
Activates or deactivates a payout config in its entirety, the header row in incentive\_score\_payout\_configs. Does not touch incentive\_score\_payouts rows; deactivation only flips the config's status flag, which the calculation engine's payout lookup already filters on.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| config\_id | Yes | Payout config ID |

Request

| {  "status": "inactive"} |
| :---- |

**Validation Rules**

* config\_id must be a valid UUID and must exist. Otherwise reject with PAYOUT\_CONFIG\_NOT\_FOUND.  
* status must be active or inactive. Otherwise reject with VALIDATION\_ERROR.  
* Past configs cannot be activated/deactivated by normal users (per Standard Edit Rules, Case 3). Reject with EDIT\_NOT\_PERMITTED.  
* If activating a config, the backend must check period overlap against other active payout configs for the same partner. Overlap → reject with CONFIG\_OVERLAP.  
* This check is backed by excl\_ispc\_no\_active\_overlap. If a concurrent request races past the lock (e.g. a non-API write), the database constraint rejects the losing transaction with an exclusion violation.  
* Status changes are rejected when a Business 1 calculation run is pending or processing for the same partner and impacted period. Reject with CONFIG\_CHANGE\_RUN\_IN\_PROGRESS.  
* Status changes are audited via the existing updated\_by/updated\_by\_name/updated\_at columns on incentive\_score\_payout\_configs.  
* Deactivating a payout config does not touch incentive\_score\_payouts rows — it only flips incentive\_score\_payout\_configs.status. Payout rows are shared across Trader and Non-Trader (no per-type distinction), so this single status flag governs both.

Response

| {  "status": "success",  "data": {    "config\_id": "\<uuid\>",    "valid\_from": "2026-06-01",    "valid\_to": "2026-06-30",    "status": "inactive",    "message": "Payout config status updated successfully"  }} |
| :---- |

## **Ageing Deduction**

### 14.12 GET Ageing Deduction Configs

Endpoint \-  
GET /api/incentives/v1/ageing-deduction-configs

Purpose \-  
Returns paginated AR ageing deduction config list for the Overdue Date list screen.

AR ageing config is period-level. One config can contain multiple channels and Non-Trader level groups.

Query Parameters

| Parameter | Required | Allowed Values / Format | Description |
| ----- | ----- | ----- | ----- |
| page | No | Integer, default 1 | Page number |
| limit | No | Integer, default 20 | Rows per page |
| status | No | active, inactive | Filters configs by status |
| valid\_from | No | YYYY-MM | Filters configs whose valid\_from starts from this month |
| valid\_to | No | YYYY-MM | Filters configs whose valid\_to ends before or at this month |

Do not use channel as the primary list filter in Phase 1 because channel is now inside config detail, not on the config header.

Response

| {  "status": "success",  "data": {   "configs": \[    {     "id": "\<uuid\>",     "valid\_from": "2026-06-01",     "valid\_to": "2026-06-30",     "status": "active",     "created\_by": "\<uuid\>",     "created\_by\_name": "Mikhael Arthura",     "created\_at": "2025-09-24T10:14:00Z",     "updated\_by": "\<uuid\>",     "updated\_by\_name": "Mikhael Arthura",     "updated\_at": "2025-09-24T10:14:00Z"   }  \],  "pagination": {   "page": 1,   "limit": 20,   "total": 200,   "total\_pages": 10   }  } } |
| :---- |

Rules:

1. API returns one row per ar\_ageing\_deduction\_configs header.  
2. API does not return one row per channel.  
3. pagination.total and pagination.total\_pages are calculated from config header row count.  
4. Default ordering should be latest created\_at first, unless existing config-list convention uses latest valid\_from first.

Implementation Scope \-   
This is a frontend/admin API and must be implemented in both WS1 and WS2.

Call flow:  
Closio / FE → WS1 → ws2targetsales / incentive service

WS1 responsibilities:

1. Validate cookie/session.  
2. Fetch logged-in user details.  
3. Resolve partner\_id, user\_id, and user\_name.  
4. Validate request shape where applicable.  
5. Forward request to WS2 with S2S headers.

WS1 → WS2 headers:

1. x-client-id  
2. x-client-secret  
3. X-Partner-Id  
4. X-User-Id  
5. X-User-Name

WS2 responsibilities:

1. Validate x-client-id and x-client-secret.  
2. Validate X-Partner-Id.  
3. Apply partner-level access control.  
4. Execute the AR ageing config query or mutation.  
5. Use X-User-Id and X-User-Name for audit fields where applicable.  
6. Return response to WS1.  
7. WS1 forwards the response to frontend.

#### 14.12.1 GET Ageing Deduction Config Options

**Endpoint**

GET /api/incentives/v1/ageing-deduction-configs/options

**Purpose**

Returns metadata required by the **Add/Edit Overdue Date config** screen.

This API is used to populate:

1. Fixed overdue bucket rows.

This API does not create or update AR ageing config. It only returns metadata required by the UI before calling create or update APIs.

**Response**

| {  "status": "success",  "data": {    "buckets": \[      {        "bucket\_code": "OD\_GT\_0",        "bucket\_name": "OD \> 0",        "operator": "\>",        "overdue\_days": 0,        "priority": 5,        "default\_deduction\_percentage": 0      },      {        "bucket\_code": "OD\_GT\_7",        "bucket\_name": "OD \> 7",        "operator": "\>",        "overdue\_days": 7,        "priority": 4,        "default\_deduction\_percentage": 0      },      {        "bucket\_code": "OD\_GT\_14",        "bucket\_name": "OD \> 14",        "operator": "\>",        "overdue\_days": 14,        "priority": 3,        "default\_deduction\_percentage": 0      },      {        "bucket\_code": "OD\_GT\_21",        "bucket\_name": "OD \> 21",        "operator": "\>",        "overdue\_days": 21,        "priority": 2,        "default\_deduction\_percentage": 0      },      {        "bucket\_code": "OD\_GT\_30",        "bucket\_name": "OD \> 30",        "operator": "\>",        "overdue\_days": 30,        "priority": 1,        "default\_deduction\_percentage": 0      }    \]  }} |
| :---- |

**Field Source**

| Response Field | Source |
| ----- | ----- |
| buckets | Backend fixed AR ageing bucket definition. Values must match ar\_ageing\_buckets seed data. |
| default\_deduction\_percentage | Backend default value |

**Bucket Rules**

1. Buckets are fixed AR overdue-day windows.  
2. Bucket rows are not user-created or user-editable.  
3. operator, overdue\_days, and priority are display-only values.  
4. deduction\_percentage is the only editable value in the Add/Edit config screen.  
5. default\_deduction\_percentage is used only to prefill new rows on the Add screen.  
6. Actual deduction\_percentage is saved through:  
   * POST /api/incentives/v1/ageing-deduction-configs  
   * PATCH /api/incentives/v1/ageing-deduction-configs/:config\_id  
7. Bucket rows should be returned ordered by overdue\_days ascending for UI display. Backend calculation still evaluates buckets by priority from highest overdue window to lowest.

**Validation Rules**

1. X-Partner-Id must be present.  
2. partner\_id must be resolved from request headers.  
3. buckets must always return the fixed AR ageing bucket options.  
4. This API does not require valid\_from or valid\_to.  
5. This API does not perform period overlap validation.  
6. Period validation and overlap checks happen only in create, update, and status APIs.

**Error Responses**

**Missing partner header**

| {  "status": "error",  "error\_code": "PARTNER\_ID\_MISSING",  "message": "X-Partner-Id header is required."} |
| :---- |

**Implementation Scope**

This is a frontend/admin API and must be implemented in both WS1 and WS2.

**Call flow:**

Closio / FE → WS1 → ws2targetsales / incentive service

**WS1 Responsibilities**

1. Validate cookie/session.  
2. Fetch logged-in user details.  
3. Resolve partner\_id, user\_id, and user\_name.  
4. Validate request shape where applicable.  
5. Forward request to WS2 with S2S headers.

**WS1 → WS2 Headers**

1. x-client-id  
2. x-client-secret  
3. X-Partner-Id  
4. X-User-Id  
5. X-User-Name

**WS2 Responsibilities**

1. Validate x-client-id and x-client-secret.  
2. Validate X-Partner-Id.  
3. Apply partner-level access control.  
4. Execute the AR ageing config query or mutation.  
5. Use X-User-Id and X-User-Name for audit fields where applicable.  
6. Return response to WS1.  
7. WS1 forwards the response to the frontend.

### 14.13 GET Ageing Deduction Config Detail

**Endpoint**  
GET /api/incentives/v1/ageing-deduction-configs/:config\_id

**Purpose**  
Returns one AR ageing config with all configured channels, Non-Trader level groups, and fixed overdue-day rules.

**Path Parameters**

| Parameter | Required | Description |
| ----- | ----- | ----- |
| config\_id | Yes | AR ageing config ID |

Response

| {  "status": "success",  "data": {    "config": {      "id": "\<uuid\>",      "valid\_from": "2026-06-01",      "valid\_to": "2026-06-30",      "status": "active",      "channels": \[        {          "channel": "Catering",          "salesman\_types": \[            {              "salesperson\_type": "NON\_TRADER",              "level": 1,              "salesman\_type\_label": "Sales Non-Trader",              "rules": \[                {                  "bucket\_code": "OD\_GT\_0",                  "operator": "\>",                  "overdue\_days": 0,                  "priority": 5,                  "deduction\_percentage": 0                },                {                  "bucket\_code": "OD\_GT\_7",                  "operator": "\>",                  "overdue\_days": 7,                  "priority": 4,                  "deduction\_percentage": 5                },                {                  "bucket\_code": "OD\_GT\_14",                  "operator": "\>",                  "overdue\_days": 14,                  "priority": 3,                  "deduction\_percentage": 10                },                {                  "bucket\_code": "OD\_GT\_21",                  "operator": "\>",                  "overdue\_days": 21,                  "priority": 2,                  "deduction\_percentage": 15                },                {                  "bucket\_code": "OD\_GT\_30",                  "operator": "\>",                  "overdue\_days": 30,                  "priority": 1,                  "deduction\_percentage": 20                }              \]            },            {              "salesperson\_type": "NON\_TRADER",              "level": 2,              "salesman\_type\_label": "SPV / KAO Non-Trader",              "rules": \[                {                  "bucket\_code": "OD\_GT\_0",                  "operator": "\>",                  "overdue\_days": 0,                  "priority": 5,                  "deduction\_percentage": 0                },                {                  "bucket\_code": "OD\_GT\_7",                  "operator": "\>",                  "overdue\_days": 7,                  "priority": 4,                  "deduction\_percentage": 5                },                {                  "bucket\_code": "OD\_GT\_14",                  "operator": "\>",                  "overdue\_days": 14,                  "priority": 3,                  "deduction\_percentage": 10                },                {                  "bucket\_code": "OD\_GT\_21",                  "operator": "\>",                  "overdue\_days": 21,                  "priority": 2,                  "deduction\_percentage": 15                },                {                  "bucket\_code": "OD\_GT\_30",                  "operator": "\>",                  "overdue\_days": 30,                  "priority": 1,                  "deduction\_percentage": 20                }              \]            }          \]        }      \]    }  }} |
| :---- |

Rules:

1. Only active rules where is\_deprecated \= false should be returned.  
2. operator, overdue\_days, and priority come from ar\_ageing\_buckets, not from editable config data.  
3. deduction\_percentage comes from ar\_ageing\_deduction\_rules.  
4. salesman\_type\_label is derived by backend for UI display:  
    Level 1 \= Sales Non-Trader  
    Level 2 \= SPV / KAO Non-Trader  
    Level 3 \= RSO Non-Trader  
5. If config\_id does not exist, return AGEING\_CONFIG\_NOT\_FOUND.

Implementation Scope  
This is a frontend/admin API and must be implemented in both WS1 and WS2.

Call flow:  
Closio / FE → WS1 → ws2targetsales / incentive service

WS1 responsibilities:

1. Validate cookie/session.  
2. Fetch logged-in user details.  
3. Resolve partner\_id, user\_id, and user\_name.  
4. Validate request shape where applicable.  
5. Forward request to WS2 with S2S headers.

WS1 → WS2 headers:

1. x-client-id  
2. x-client-secret  
3. X-Partner-Id  
4. X-User-Id  
5. X-User-Name

WS2 responsibilities:

1. Validate x-client-id and x-client-secret.  
2. Validate X-Partner-Id.  
3. Apply partner-level access control.  
4. Execute the AR ageing config query or mutation.  
5. Use X-User-Id and X-User-Name for audit fields where applicable.  
6. Return response to WS1.  
7. WS1 forwards the response to the frontend.

### 14.14 POST Ageing Deduction Config

Endpoint  
POST /api/incentives/v1/ageing-deduction-configs

Purpose  
Creates one period-level AR ageing deduction config with channels, Non-Trader level groups, and deduction percentages for fixed overdue-day windows.

Request

| {  "valid\_from": "2026-06",  "valid\_to": "2026-06",  "channels": \[    {      "channel": "Catering",      "salesman\_types": \[        {          "salesperson\_type": "NON\_TRADER",          "level": 1,          "rules": \[            {              "bucket\_code": "OD\_GT\_0",              "deduction\_percentage": 0            },            {              "bucket\_code": "OD\_GT\_7",              "deduction\_percentage": 5            },            {              "bucket\_code": "OD\_GT\_14",              "deduction\_percentage": 10            },            {              "bucket\_code": "OD\_GT\_21",              "deduction\_percentage": 15            },            {              "bucket\_code": "OD\_GT\_30",              "deduction\_percentage": 20            }          \]        },        {          "salesperson\_type": "NON\_TRADER",          "level": 2,          "rules": \[            {              "bucket\_code": "OD\_GT\_0",              "deduction\_percentage": 0            },            {              "bucket\_code": "OD\_GT\_7",              "deduction\_percentage": 5            },            {              "bucket\_code": "OD\_GT\_14",              "deduction\_percentage": 10            },            {              "bucket\_code": "OD\_GT\_21",              "deduction\_percentage": 15            },            {              "bucket\_code": "OD\_GT\_30",              "deduction\_percentage": 20            }          \]        }      \]    }  \]} |
| :---- |

Request Fields

| Field | Required | Format / Allowed Values | Description |
| ----- | ----- | ----- | ----- |
| valid\_from | Yes | YYYY-MM | Config start month |
| valid\_to | Yes | YYYY-MM | Config end month |
| channels | Yes | Non-empty array | List of channel blocks in this config |
| channels\[\].channel | Yes | Allowed Non-Trader channel | Channel for which rules are configured |
| channels\[\].salesman\_types | Yes | Non-empty array | Non-Trader level groups under the channel |
| channels\[\].salesman\_types\[\].salesperson\_type | Yes | NON\_TRADER | AR ageing applies only to Non-Trader |
| channels\[\].salesman\_types\[\].level | Yes | 1, 2, 3 | Level 1 \= SALES, Level 2 \= SPV / KAO, Level 3 \= RSO |
| channels\[\].salesman\_types\[\].rules | Yes | Exactly 5 rules | Fixed overdue-day bucket rules |
| rules\[\].bucket\_code | Yes | OD\_GT\_0, OD\_GT\_7, OD\_GT\_14, OD\_GT\_21, OD\_GT\_30 | Fixed overdue-day bucket code |
| rules\[\].deduction\_percentage | Yes | 0 to 100 | Positive deduction percentage. Example: 20 means deduct 20% |

Validation Rules

1. valid\_from and valid\_to must be valid YYYY-MM values.  
2. valid\_to must be greater than or equal to valid\_from.  
3. Backend stores valid\_from as first day of month and valid\_to as last day of month.  
4. channels must be a non-empty array.  
5. Duplicate channel within the same request is rejected with DUPLICATE\_AGEING\_CHANNEL.  
6. channel must be one of the allowed Non-Trader channels.  
7. TRADER channel is not allowed for AR ageing.  
8. salesman\_types must be non-empty for each channel.  
9. salesperson\_type must be NON\_TRADER.  
10. level must be 1, 2, or 3\.  
11. Duplicate level under the same channel is rejected with DUPLICATE\_AGEING\_LEVEL.  
12. rules must contain exactly five bucket codes: OD\_GT\_0, OD\_GT\_7, OD\_GT\_14, OD\_GT\_21, OD\_GT\_30.  
13. Duplicate bucket\_code under the same channel \+ level is rejected.  
14. Unsupported bucket\_code is rejected with INVALID\_AGEING\_BUCKET\_CODE.  
15. deduction\_percentage must be between 0 and 100\.  
16. operator, overdue\_days, and priority must not be accepted from request body. Backend derives them from ar\_ageing\_buckets.  
17. Period must not overlap with another active AR ageing config for the same partner. Overlap is checked at config header level, not channel level.  
18. Config creation is rejected when a Business 1 calculation run is pending or processing for the same partner and impacted period.  
19. Config header and all child rules are created in a single transaction.

Response

| {  "status": "success",  "data": {    "config\_id": "\<uuid\>",    "valid\_from": "2026-06-01",    "valid\_to": "2026-06-30",    "status": "active",    "channels": \[      {        "channel": "Catering",        "salesman\_types": \[          {            "salesperson\_type": "NON\_TRADER",            "level": 1,            "salesman\_type\_label": "Sales Non-Trader",            "rules": \[              {                "bucket\_code": "OD\_GT\_0",                "operator": "\>",                "overdue\_days": 0,                "priority": 5,                "deduction\_percentage": 0              },              {                "bucket\_code": "OD\_GT\_7",                "operator": "\>",                "overdue\_days": 7,                "priority": 4,                "deduction\_percentage": 5              },              {                "bucket\_code": "OD\_GT\_14",                "operator": "\>",                "overdue\_days": 14,                "priority": 3,                "deduction\_percentage": 10              },              {                "bucket\_code": "OD\_GT\_21",                "operator": "\>",                "overdue\_days": 21,                "priority": 2,                "deduction\_percentage": 15              },              {                "bucket\_code": "OD\_GT\_30",                "operator": "\>",                "overdue\_days": 30,                "priority": 1,                "deduction\_percentage": 20              }            \]          }        \]      }    \]  }} |
| :---- |

Rules:

1. Response should echo saved structure.  
2. Response should include derived operator, overdue\_days, priority, and salesman\_type\_label.

Implementation Scope  
 This is a frontend/admin API and must be implemented in both WS1 and WS2.

Call flow:  
 Closio / FE → WS1 → ws2targetsales / incentive service

WS1 responsibilities:

1. Validate cookie/session.  
2. Fetch logged-in user details.  
3. Resolve partner\_id, user\_id, and user\_name.  
4. Validate request shape where applicable.  
5. Forward request to WS2 with S2S headers.

WS1 → WS2 headers:

1. x-client-id  
2. x-client-secret  
3. X-Partner-Id  
4. X-User-Id  
5. X-User-Name

WS2 responsibilities:

1. Validate x-client-id and x-client-secret.  
2. Validate X-Partner-Id.  
3. Apply partner-level access control.  
4. Execute the AR ageing config query or mutation.  
5. Use X-User-Id and X-User-Name for audit fields where applicable.  
6. Return response to WS1.  
7. WS1 forwards the response to the frontend.

### 14.15 PATCH Ageing Deduction Config

Endpoint  
PATCH /api/incentives/v1/ageing-deduction-configs/:config\_id

Purpose  
Updates an existing AR ageing config period and/or its channel-level deduction rules.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| config\_id | Yes | AR ageing config ID |

Request

| {  "is\_config\_updated": true,  "is\_rules\_updated": true,  "updated\_valid\_from": "2026-06",  "updated\_valid\_to": "2026-06",  "channels": \[    {      "channel": "Catering",      "salesman\_types": \[        {          "salesperson\_type": "NON\_TRADER",          "level": 1,          "rules": \[            {              "bucket\_code": "OD\_GT\_0",              "deduction\_percentage": 0            },            {              "bucket\_code": "OD\_GT\_7",              "deduction\_percentage": 5            },            {              "bucket\_code": "OD\_GT\_14",              "deduction\_percentage": 10            },            {              "bucket\_code": "OD\_GT\_21",              "deduction\_percentage": 15            },            {              "bucket\_code": "OD\_GT\_30",              "deduction\_percentage": 20            }          \]        }      \]    }  \]} |
| :---- |

Request Fields

| Field | Required | Format / Allowed Values | Description |
| ----- | ----- | ----- | ----- |
| is\_config\_updated | Yes | Boolean | Whether config period is being updated |
| is\_rules\_updated | Yes | Boolean | Whether channel/rule tree is being updated |
| updated\_valid\_from | Required when is\_config\_updated \= true | YYYY-MM | Updated config start month |
| updated\_valid\_to | Required when is\_config\_updated \= true | YYYY-MM | Updated config end month |
| channels | Required when is\_rules\_updated \= true | Non-empty array | Complete desired AR rule tree |
| channels\[\].channel | Yes when is\_rules\_updated \= true | Allowed Non-Trader channel | Channel for which rules are configured |
| channels\[\].salesman\_types | Yes when is\_rules\_updated \= true | Non-empty array | Non-Trader level groups under channel |
| channels\[\].salesman\_types\[\].salesperson\_type | Yes when is\_rules\_updated \= true | NON\_TRADER | AR applies only to Non-Trader |
| channels\[\].salesman\_types\[\].level | Yes when is\_rules\_updated \= true | 1, 2, 3 | Level used for lookup |
| rules\[\].bucket\_code | Yes when is\_rules\_updated \= true | OD\_GT\_0, OD\_GT\_7, OD\_GT\_14, OD\_GT\_21, OD\_GT\_30 | Fixed bucket code |
| rules\[\].deduction\_percentage | Yes when is\_rules\_updated \= true | 0 to 100 | Positive deduction percentage |

Validation Rules

1. config\_id must be valid and must exist. Otherwise reject with AGEING\_CONFIG\_NOT\_FOUND.  
2. is\_config\_updated and is\_rules\_updated must be present and boolean.  
3. At least one of is\_config\_updated or is\_rules\_updated must be true.  
4. If is\_config\_updated \= true, updated\_valid\_from and updated\_valid\_to are required.  
5. updated\_valid\_from and updated\_valid\_to must be valid YYYY-MM.  
6. updated\_valid\_to must be greater than or equal to updated\_valid\_from.  
7. If is\_rules\_updated \= true, channels must be present and must contain the complete desired AR ageing rule tree.  
8. Same create validation applies to channels, levels, bucket codes, and deduction percentages.  
9. operator, overdue\_days, and priority must not be accepted from request body. Backend derives them from ar\_ageing\_buckets.

Standard Edit Rules

| Case | Config Period | Allowed Action |
| ----- | ----- | ----- |
| Case 1 | valid\_from and valid\_to are current/future | Full edit allowed |
| Case 2 | valid\_from is past, valid\_to is current/future | Only valid\_to can be edited; rules cannot be edited |
| Case 3 | valid\_from and valid\_to are both past | Edit not permitted for normal users |

Additional Edit Rules

1. Case 3 rejects with EDIT\_NOT\_PERMITTED.  
2. Case 2 and is\_rules\_updated \= true rejects with RULES\_NOT\_EDITABLE.  
3. Case 2 and updated\_valid\_from differs from existing valid\_from rejects with VALID\_FROM\_NOT\_EDITABLE.  
4. If period is updated, overlap check is done against other active AR ageing configs for the same partner, excluding current config.  
5. Overlap is checked at header level only: partner \+ period.  
6. Config changes are rejected when a Business 1 calculation run is pending or processing for the same partner and impacted period.

Rule Update Behaviour

1. If is\_rules\_updated \= true, replacement is full replace.  
2. Full replace means all existing active ar\_ageing\_deduction\_rules rows under this config are marked is\_deprecated \= true.  
3. New rules from request body are inserted with is\_deprecated \= false.  
4. Old rule rows are not hard-deleted.  
5. If is\_rules\_updated \= false, child rules are left untouched.  
6. Existing calculated results are not automatically recalculated.

Response

| {  "status": "success",  "data": {    "config\_id": "\<uuid\>",    "valid\_from": "2026-06-01",    "valid\_to": "2026-06-30",    "status": "active",    "message": "Ageing deduction config updated successfully",    "channels": \[      {        "channel": "Catering",        "salesman\_types": \[          {            "salesperson\_type": "NON\_TRADER",            "level": 1,            "salesman\_type\_label": "Sales Non-Trader",            "rules": \[              {                "bucket\_code": "OD\_GT\_0",                "operator": "\>",                "overdue\_days": 0,                "priority": 5,                "deduction\_percentage": 0              },              {                "bucket\_code": "OD\_GT\_7",                "operator": "\>",                "overdue\_days": 7,                "priority": 4,                "deduction\_percentage": 5              },              {                "bucket\_code": "OD\_GT\_14",                "operator": "\>",                "overdue\_days": 14,                "priority": 3,                "deduction\_percentage": 10              },              {                "bucket\_code": "OD\_GT\_21",                "operator": "\>",                "overdue\_days": 21,                "priority": 2,                "deduction\_percentage": 15              },              {                "bucket\_code": "OD\_GT\_30",                "operator": "\>",                "overdue\_days": 30,                "priority": 1,                "deduction\_percentage": 20              }            \]          }        \]      }    \]  }} |
| :---- |

Rules:

1. Response should return final current state after update.  
2. Response should include derived operator, overdue\_days, priority, and salesman\_type\_label.

Implementation Scope  
This is a frontend/admin API and must be implemented in both WS1 and WS2.

Call flow:  
Closio / FE → WS1 → ws2targetsales / incentive service

WS1 responsibilities:

1. Validate cookie/session.  
2. Fetch logged-in user details.  
3. Resolve partner\_id, user\_id, and user\_name.  
4. Validate request shape where applicable.  
5. Forward request to WS2 with S2S headers.

WS1 → WS2 headers:

1. x-client-id  
2. x-client-secret  
3. X-Partner-Id  
4. X-User-Id  
5. X-User-Name

WS2 responsibilities:

1. Validate x-client-id and x-client-secret.  
2. Validate X-Partner-Id.  
3. Apply partner-level access control.  
4. Execute the AR ageing config query or mutation.  
5. Use X-User-Id and X-User-Name for audit fields where applicable.  
6. Return response to WS1.  
7. WS1 forwards the response to frontend.

### 14.16 PATCH Ageing Deduction Config Status

Endpoint  
PATCH /api/incentives/v1/ageing-deduction-configs/:config\_id/status

Purpose  
Activates or deactivates one AR ageing config header.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| config\_id | Yes | AR ageing config ID |

Request

| { "status": "inactive"} |
| :---- |

Request Fields

| Field | Required | Allowed Values | Description |
| ----- | ----- | ----- | ----- |
| status | Yes | active, inactive | New config header status |

Validation Rules

1. config\_id must be valid and must exist. Otherwise reject with AGEING\_CONFIG\_NOT\_FOUND.  
2. status must be active or inactive. Otherwise reject with VALIDATION\_ERROR.  
3. Past configs cannot be activated/deactivated by normal users. Reject with EDIT\_NOT\_PERMITTED.  
4. If activating a config, backend must check period overlap against other active AR ageing configs for the same partner.  
5. Overlap check is header-level only: partner \+ period.  
6. Config status change is rejected when a Business 1 calculation run is pending or processing for the same partner and impacted period.  
7. Status changes are audited through updated\_by, updated\_by\_name, and updated\_at.  
8. Status change does not touch ar\_ageing\_deduction\_rules rows.  
9. Deactivation only flips ar\_ageing\_deduction\_configs.status.  
10. Calculation lookup filters active config headers, so inactive config headers are ignored along with their child rules.

Response

| { "status": "success", "data": {   "config\_id": "\<uuid\>",   "valid\_from": "2026-06-01",   "valid\_to": "2026-06-30",   "status": "inactive",   "message": "Ageing deduction config status updated successfully"  } } |
| :---- |

Implementation Scope  
This is a frontend/admin API and must be implemented in both WS1 and WS2.

Call flow:  
Closio / FE → WS1 → ws2targetsales / incentive service

WS1 responsibilities:

1. Validate cookie/session.  
2. Fetch logged-in user details.  
3. Resolve partner\_id, user\_id, and user\_name.  
4. Validate request shape where applicable.  
5. Forward request to WS2 with S2S headers.

WS1 → WS2 headers:

1. x-client-id  
2. x-client-secret  
3. X-Partner-Id  
4. X-User-Id  
5. X-User-Name

WS2 responsibilities:

1. Validate x-client-id and x-client-secret.  
2. Validate X-Partner-Id.  
3. Apply partner-level access control.  
4. Execute the AR ageing config query or mutation.  
5. Use X-User-Id and X-User-Name for audit fields where applicable.  
6. Return response to WS1.  
7. WS1 forwards the response to frontend.

## **14.17 GET Trader Stock Days Multiplier Configs**

Endpoint

GET /api/incentives/v1/trader-stock-days-multiplier-configs

Purpose

Returns Trader stock day multiplier configs.

The day multiplier is used for Trader stock-level incentive points.

Formula:

stock\_level\_days \= stock\_eom / billing\_eom × multiplier\_days

Query Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| status | No | Filters configs by active/inactive status |

Response

{

  "status": "success",

  "data": {

    "configs": \[

      {

        "id": "\<uuid\>",

        "valid\_from": "2026-06-01",

        "valid\_to": null,

        "multiplier\_days": 30,

        "status": "active",

        "created\_by": "\<uuid\>",

        "created\_by\_name": "Admin User",

        "created\_at": "2026-06-01T10:00:00Z"

      }

    \]

  }

}

## **14.18 POST Trader Stock Days Multiplier Config**

Endpoint

POST /api/incentives/v1/trader-stock-days-multiplier-configs

Purpose

Creates Trader stock day multiplier config.

Request

{

  "valid\_from": "2026-06",

  "valid\_to": null,

  "multiplier\_days": 30

}

Validation Rules

1. valid\_from must be a valid YYYY-MM value.  
2. valid\_to must be null or a valid YYYY-MM value.  
3. If valid\_to is provided, it must be greater than or equal to valid\_from.  
4. multiplier\_days must be greater than 0\.  
5. Period overlap is not allowed for active configs.  
6. This check is backed by excl\_tsdmc\_no\_active\_overlap. A concurrent race is caught as an exclusion violation.  
7. Backend should maintain a seeded/default active multiplier config with multiplier\_days \= 30. If no active config exists for the period, calculation should follow missing config behavior and fail the relevant config gate.  
8. multiplier\_days applies only to Trader stock-level incentive points.  
9. multiplier\_days is not level-specific.  
10. multiplier\_days is not channel-specific.  
11. Config creation is rejected when a Business 1 calculation run is pending or processing for the same partner and impacted period.

Response

{

  "status": "success",

  "data": {

    "config\_id": "\<uuid\>",

    "multiplier\_days": 30,

    "status": "active"

  }

}

## **14.19 PATCH Trader Stock Days Multiplier Config**

Endpoint

PATCH /api/incentives/v1/trader-stock-days-multiplier-configs/:config\_id

Purpose

Updates Trader stock day multiplier config.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| config\_id | Yes | Trader stock day multiplier config ID |

Request

{

  "valid\_from": "2026-06",

  "valid\_to": null,

  "multiplier\_days": 31

}

Rules

1. multiplier\_days must be greater than 0\.  
2. Same period edit rules as incentive point slabs.  
3. Past configs cannot be edited by normal users.  
4. If the period is edited, the new valid\_from/valid\_to must be checked for overlap against other active day multiplier configs for the same partner, excluding the current config.  
5. Backed by excl\_tsdmc\_no\_active\_overlap; a race.  
6. Config changes are rejected when a Business 1 calculation run is pending or processing for the same partner and impacted period.  
7. Existing calculated results are not automatically recalculated.

Response

{

  "status": "success",

  "data": {

    "config\_id": "\<uuid\>",

    "message": "Trader stock day multiplier config updated successfully"

  }

}

## **14.20 PATCH Trader Stock Days Multiplier Config Status**

Endpoint

PATCH /api/incentives/v1/trader-stock-days-multiplier-configs/:config\_id/status

Purpose

Activates or deactivates a Trader stock day multiplier config.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| config\_id | Yes | Trader stock day multiplier config ID |

Request

{

  "status": "inactive"

}

Validation Rules

1. status must be active or inactive.  
2. Past configs cannot be activated/deactivated by normal users.  
3. If activating a config, backend must check period overlap against other active day multiplier configs.  
4. Backed by excl\_tsdmc\_no\_active\_overlap; a race.  
5. Config changes are rejected when a Business 1 calculation run is pending or processing for the same partner and impacted period.  
6. Status changes are audited.

Response

{

  "status": "success",

  "data": {

    "config\_id": "\<uuid\>",

    "status": "inactive"

  }

}

# 15\. Feed / Input APIs

Business 1 has three input patterns:

Pull-based monthly refresh:

* Customer Handled

Push-based monthly feed ingestion:

* New Customer Monthly  
* AR Ageing

Admin-uploaded Trader CSV:

* Trader Stock  
* Trader GPM

incentive\_feed\_logs is used for Customer Handled refreshes, New Customer Monthly ingestion, and AR Ageing ingestion.

incentive\_upload\_sessions is used for Trader Stock and Trader GPM uploads.

Trader upload APIs store the original CSV files in S3 and queue asynchronous worker processing.

Customer Handled and New Customer Monthly do not use Trader upload tables or S3.

## **15.1 Common Monthly Input Replacement Rule**

Customer Handled, New Transacted Customers, and AR Ageing use soft monthly replacement. The latest successfully processed dataset becomes active for the partner, period, and input type. Previous rows are retained as replaced/inactive records.

Common replacement sequence:

1. Validate the transport-level request and resolve the partner and period.  
2. Create an incentive\_feed\_logs row.  
3. Fetch or parse the complete incoming dataset.  
4. Validate and normalize the dataset according to its input-specific rules.  
5. Start a database transaction.  
6. Mark previous active rows for the same partner, period, and input type as replaced/inactive.  
7. Insert the latest accepted rows as active.  
8. Update the feed log with status, row counts, completion time, and replacement lineage.  
9. Commit the transaction.

If source retrieval, parsing, validation, or persistence fails before activation is complete, the feed log is marked failed and the previous active dataset remains unchanged.

The original CSV is stored in S3 only for input types whose API contract explicitly requires it, such as AR Ageing. Customer Handled and New Customer Monthly do not use S3.

Customer Handled replacement is all-or-nothing. Any invalid source row fails the complete refresh.

New Customer Monthly is a complete-file replacement flow. The following confirmed exclusions do not fail the remaining valid dataset:

* Rows outside the required incentive month are ignored and reported as rejected.  
* Exact duplicate transaction copies are excluded so they do not contribute more than once.  
* If a customer is assigned to multiple salespeople, all rows for that customer are excluded and flagged. Other valid customers continue processing.

Other structural errors, missing required fields, invalid field types, mixed-partner data, parsing failures, or persistence failures fail the complete New Customer Monthly processing attempt and preserve the previous active dataset.

Replacement does not perform row-by-row comparison against the previous active dataset.

Replacement is rejected while a Business 1 calculation run is pending or processing for the same partner and period.

Customer Handled refresh and New Customer Monthly replacement are additionally rejected after the successful CATCHUP\_CRON run for the period.

Calculation reads only active rows.

## **15.2 Customer Handled Refresh**

Endpoint:

POST /api/incentives/v1/feeds/customer-handled/refresh

Mode:

Admin-triggered pull.

Purpose:

Fetch the current Customer Handled counts from ws2closio and store them as the active monthly Customer Handled snapshot used by Business 1\.

Caller:

An authorized admin triggers the refresh through the frontend/WS1 flow. No scheduled cron automatically invokes this API.

Call flow:

Authorized admin / FE → WS1 → ws2targetsalesincentive → ws2closio

Required WS1 to WS2 headers:

x-client-id  
x-client-secret  
X-Partner-Id  
X-User-Id  
X-User-Name

Request body:

period — Required in YYYY-MM format

Source API:

GET /api/incentives/v1/customer-handled?period=YYYY-MM

Source service:

nodejs-ws2closio

Required source API headers:

x-client-id  
x-client-secret  
X-Partner-Id

Expected source response:

status — success

data.period — Requested period in YYYY-MM format

data.customers — Array containing one row per non-deleted partner user

Each customer row contains:

salesperson\_id — User/salesperson UUID

customer\_count — Integer greater than or equal to zero

Closio selection rules:

* Start with all non-deleted users belonging to X-Partner-Id.  
* Left join the customers table using customers.sales\_id.  
* Count customer rows only when customer\_type \= 'CUSTOMER' and deleted\_at IS NULL.  
* Return one row for every non-deleted partner user, including customer\_count \= 0\.  
* Do not apply incentive level, role, channel, or Trader/Non-Trader filtering.  
* Return each salesperson’s own customer count only.  
* Do not perform hierarchy aggregation.  
* Treat period as snapshot context. It does not filter the Closio customers table because Closio does not maintain monthly customer-ownership history.  
* Do not apply pagination in Phase 1\.

Target Sales processing:

1. Validate X-Partner-Id.  
2. Validate period and convert it into period\_month and period\_year.  
3. Reject the request if a Business 1 run is pending or processing for the same partner and period.  
4. Reject the request if a successful CATCHUP\_CRON run already exists for the same partner and period.  
5. Create an incentive\_feed\_logs row with feed\_type \= CUSTOMER\_HANDLED and status \= processing.  
6. Call the ws2closio Customer Handled API using configuration-based URL and S2S credentials.  
7. Validate that the source period matches the requested period.  
8. Validate the complete customers array.  
9. Reject missing or invalid salesperson\_id.  
10. Reject missing, negative, non-numeric, or non-integer customer\_count.  
11. Reject duplicate salesperson\_id values.  
12. In one database transaction, mark previous active rows as replaced/inactive, insert the latest rows as active, and mark the feed log successful.  
13. If source retrieval, validation, or persistence fails, mark the feed log failed and preserve the previous active snapshot.

A valid empty customers array may succeed only when Closio explicitly returns a valid successful response containing that empty array. A missing response, missing customers field, or malformed customers value is a validation failure.

Success response fields:

status — success

data.feed\_log\_id — Created feed log UUID

data.feed\_type — CUSTOMER\_HANDLED

data.period — Requested period

data.status — success

data.total\_rows — Number of source rows

data.accepted\_rows — Number of inserted rows

data.rejected\_rows — 0

The refresh does not use S3 and does not trigger calculation or recalculation.

## **15.3 New Transacted Monthly Feed**

Endpoint:

POST /api/target/v1/webhooks/new-customer-monthly

Mode:

Push-based S2S monthly CSV feed.

Purpose:

Receive one complete monthly new-customer transaction file, determine which new customers have positive monthly net sales quantity, store the qualifying customers as the active New Transacted Customer snapshot, and update T2 achievement using customer count.

Caller:

The finalized source system calls this endpoint. It is not a frontend/admin API and does not use the Customer Handled refresh flow.

Required headers:

x-client-id  
x-client-secret  
X-Partner-Id

Content type:

multipart/form-data

File field:

file

Supported file type:

CSV

Required CSV columns:

partner\_id  
billing\_date  
billing\_doc  
channel  
delivery\_doc  
sales\_doc  
material  
customer  
sid  
salesperson\_name  
net\_sales\_amount  
net\_sales\_quantity\_kg

Field mapping:

partner\_id — Partner identifier; must match X-Partner-Id

billing\_date — Transaction date and source of the incentive period

billing\_doc — Billing document identifier

channel — Source transaction channel

delivery\_doc — Delivery document identifier

sales\_doc — Sales document identifier

material — Material identifier

customer — Customer identifier

sid — Salesperson identifier; mapped to salesperson\_id

salesperson\_name — Source salesperson name retained where required for validation or audit

net\_sales\_amount — Source amount; not used to determine the New Transacted Customer achievement

net\_sales\_quantity\_kg — Quantity used to determine monthly transacted qualification

Validation rules:

* The file field is required.  
* The uploaded file must be a CSV.  
* All required columns must be present.  
* X-Partner-Id must be valid.  
* Every CSV partner\_id must match X-Partner-Id.  
* The file must not contain rows for multiple partners.  
* Every sid must be a valid UUID.  
* billing\_date must be valid.  
* The document, material, and customer fields must have the expected numeric format.  
* net\_sales\_amount and net\_sales\_quantity\_kg must be valid decimal values.  
* A header-only file remains invalid until the zero-new-customer delivery mechanism is confirmed.

Period rules:

* The intended period is the previous Business 1 incentive month.  
* Each row’s period is derived from billing\_date.  
* Rows for the previous incentive month are processed.  
* Rows for other periods are ignored and reported as rejected.  
* If no valid row remains for the required month, processing fails unless the future zero-new-customer contract explicitly supports the input.

Processing flow:

1. Validate S2S credentials, partner context, file presence, file type, and required headers.  
2. Resolve the partner and incentive period.  
3. Reject ingestion if a Business 1 run is pending or processing for the same partner and period.  
4. Reject replacement if a successful CATCHUP\_CRON run already exists for the same partner and period.  
5. Create an incentive\_feed\_logs row with feed\_type \= NEW\_TRANSACTED\_CUSTOMERS and status \= pending.  
6. Parse and normalize the complete CSV as one logical dataset.  
7. Process the complete dataset as one batch. Per-row jobs must not independently update T2 achievement or activate monthly snapshot rows.  
8. Exclude out-of-period rows and exact duplicate transaction copies.  
9. Detect customers assigned to multiple salespeople and exclude all rows belonging to each affected customer.  
10. Group the remaining rows by partner, period, salesperson, and customer.  
11. Calculate monthly\_net\_sales\_quantity as SUM(net\_sales\_quantity\_kg).  
12. Retain only customer groups whose monthly\_net\_sales\_quantity is greater than zero.  
13. In one database transaction, mark the previous active snapshot as replaced, insert the latest qualifying rows, update the T2 count achievement, and mark the feed log successful.  
14. If processing fails, mark the feed log failed and leave the previous active dataset unchanged.

Success acknowledgement fields:

status — success

message — CSV file received successfully. Processing has begun.

data.feed\_log\_id — Created feed log UUID

data.feed\_type — NEW\_TRANSACTED\_CUSTOMERS

data.period — Resolved period

data.status — pending or processing, according to the existing worker convention

Final status and row counts are available through the feed-status API.

Replacement rules:

* Every delivery is a complete monthly dataset.  
* Incremental and delta files are not supported.  
* A corrected complete file may be sent before successful CATCHUP\_CRON completion.  
* The latest successfully processed complete file becomes active.  
* Input replacement does not automatically trigger Business 1 recalculation.  
* The original file is not stored in S3.  
* Business 1 reads incentive\_new\_transacted\_customer\_activity rather than processed\_new\_customer\_events.  
* Business 1 does not perform another Daily Sales lookup during the incentive-point calculation.

Current implementation changes required:

* Retain the existing route, controller, S2S authentication middleware, and multipart CSV upload middleware where compatible.  
* Change newCustomerMonthlyWebhookService because it currently creates one independent BullMQ job per CSV row.  
* Change newCustomerMonthlyProcessor because it currently appends net\_sales\_quantity to T2 achievement and writes individual rows to processed\_new\_customer\_events.  
* Process each complete file as one logical batch.  
* Add incentive\_feed\_logs lifecycle handling.  
* Add full-month aggregation and soft replacement.  
* Add mixed-period filtering.  
* Add file-scoped exact-event deduplication.  
* Add cross-salesperson customer conflict handling.  
* Add successful CATCHUP\_CRON cutoff validation.  
* Change T2 achievement globally from quantity accumulation to distinct qualifying customer count.  
* Populate incentive\_new\_transacted\_customer\_activity and use it as the Business 1 calculation source.  
* Do not use cumulative processed\_new\_customer\_events deduplication to block a corrected complete-file resubmission.

## **15.4 POST AR Ageing Feed**

Endpoint:

POST /incentive/v1/feeds/ageing

Mode: Push feed

Source: Qlik Sense / finalized finance source

Purpose: Stores AR ageing overdue bucket amounts per salesperson \+ customer \+ period.

This API stores the original AR Ageing CSV file in S3, creates an incentive\_feed\_logs row, queues asynchronous feed processing, and returns after the file is stored and processing is queued.

Implementation Scope  
 This is an external push feed API and must be implemented through the WS1/exposed gateway route and WS2 incentive service endpoint.

Call flow:  
 Qlik Sense / Finance / external source → WS1 / exposed gateway route → ws2targetsales / incentive service

WS1 / gateway responsibilities:

1. Accept the external feed request.  
2. Validate or forward required external authentication headers as per gateway design.  
3. Resolve or forward partner context.  
4. Forward the multipart request to WS2 with required S2S headers.

WS1 → WS2 headers:

1. x-client-id  
2. x-client-secret  
3. X-Partner-Id

WS2 responsibilities:

1. Validate x-client-id and x-client-secret.  
2. Validate X-Partner-Id.  
3. Validate period, file type, and CSV header.  
4. Upload original CSV to S3.  
5. Create incentive\_feed\_logs row.  
6. Queue asynchronous AR ageing feed processing job.  
7. Return pending processing response.

Request format:

multipart/form-data

Fields:

| Field | Required | Description |
| ----- | ----- | ----- |
| period | Yes | Period in YYYY-MM format |
| file | Yes | AR Ageing CSV file |

Expected CSV columns:

1. period  
2. salesperson\_id  
3. channel  
4. customer\_id  
5. total\_overdue  
6. od\_1\_7  
7. od\_8\_14  
8. od\_15\_21  
9. od\_22\_30  
10. od\_gt\_30

Validation Rules:

1. partner\_id must be available from headers.  
2. period must be YYYY-MM.  
3. file is mandatory.  
4. file must be CSV.  
5. CSV header must match expected AR Ageing columns.  
6. Replacement is rejected when a Business 1 calculation run is pending or processing for the same partner and period.

Worker Row Validation Rules:

1. salesperson\_id is required.  
2. channel is required.  
3. customer\_id is required.  
4. total\_overdue is required.  
5. All overdue bucket amounts are required.  
6. Amounts must be greater than or equal to 0\.  
7. Validate total overdue:  
    total\_overdue \= od\_1\_7 \+ od\_8\_14 \+ od\_15\_21 \+ od\_22\_30 \+ od\_gt\_30  
8. Duplicate salesperson\_id \+ customer\_id rows in the same file should be rejected.  
9. If any row-level validation error exists, feed processing fails and previous active AR Ageing rows remain unchanged.

Flow:

1. External source calls AR Ageing feed API.  
2. API validates headers, period, file type, and CSV header.  
3. API uploads original CSV to S3.  
4. API creates incentive\_feed\_logs row with:  
   * feed\_type \= AR\_AGEING  
   * status \= pending  
   * s3\_key \= original file key  
5. API queues feed ingestion worker.  
6. Worker reads CSV from S3.  
7. Worker validates rows.  
8. If processing succeeds, previous active AR Ageing rows for same partner and period are marked replaced/inactive.  
9. All rows from the validated latest dataset are inserted as active.  
10. Feed log is marked success.  
11. If processing fails, feed log is marked failed and previous active AR Ageing rows remain unchanged.

Response:

{

  "status": "success",

  "data": {

    "log\_id": "\<uuid\>",

    "feed\_type": "AR\_AGEING",

    "period": "2026-06",

    "processing\_status": "pending",

    "message": "AR Ageing file uploaded successfully and queued for processing."

  }

}

Example worker validation error stored in feed log / feed status:

{

  "status": "failed",

  "error\_details": \[

    {

      "error\_code": "TOTAL\_OVERDUE\_MISMATCH",

      "message": "total\_overdue must equal sum of overdue bucket amounts.",

      "row\_number": 12,

      "salesperson\_id": "\<uuid\>",

      "customer\_id": "CUST001"

    }

  \]

}

Fields not stored:

1. ar\_ending\_balance  
2. current\_amount  
3. current\_pct

## **15.5 POST Trader Upload**

Endpoint

POST /api/incentives/v1/trader-uploads

Purpose

Uploads a Trader stock or Trader GPM CSV file and queues asynchronous worker processing.

This API does not perform row-level validation.

This API does not activate Trader stock/GPM rows directly.

This API stores the original CSV file in S3, creates an upload session, queues a worker job, and returns immediately.

Supported upload types:

1. TRADER\_STOCK\_BY\_PRODUCT  
2. TRADER\_STOCK\_GRADE  
3. TRADER\_STOCK\_SIDE\_PRODUCT  
4. TRADER\_GPM

Request

Content-Type:

multipart/form-data

Fields:

| Field | Required | Description |
| ----- | ----- | ----- |
| period | Yes | Period month in YYYY-MM format |
| upload\_type | Yes | One of the supported upload types |
| file | Yes | CSV file |

Only CSV files are supported in Phase 1\.

Example logical request:

{

  "period": "2026-06",

  "upload\_type": "TRADER\_GPM",

  "file": ""

}

API Validation Rules

1. partner\_id must be available from headers.  
2. user\_id must be available from headers.  
3. period must be YYYY-MM.  
4. upload\_type must be valid.  
5. file is mandatory.  
6. File must be CSV.  
7. File size must be within configured upload size limit.  
8. Upload is rejected if a Business 1 calculation run is already pending or processing for the same partner and period.  
9. API should not parse the full CSV for row-level validation.  
10. API should not mutate active Trader stock/GPM data.  
11. API should upload original CSV file to S3 before queueing worker processing.  
12. API should return success only after original file is uploaded to S3, upload session is created, and worker job is queued.  
13. If S3 upload succeeds but upload session creation or worker queueing fails, backend should either delete the uploaded S3 object or create/update the upload session with status \= failed and error\_details explaining the failure.

S3 Original File Key

The original file should be stored using this key format:

incentive/trader-uploads/{partner\_id}/{period}/{upload\_type}/{upload\_id}/original.csv

Example:

incentive/trader-uploads/e3d8f926-a1bf-4890-9524-cc2d610152f9/2026-06/TRADER\_GPM/9f0b1d4b-aaaa-bbbb-cccc-123456789000/original.csv

Upload Session Behavior

After successful S3 upload, backend creates incentive\_upload\_sessions row with:

status \= queued

The upload session should store:

1. partner\_id  
2. upload\_type  
3. period\_month  
4. period\_year  
5. original\_filename  
6. s3\_bucket  
7. original\_file\_key  
8. file\_size\_bytes  
9. content\_type  
10. uploaded\_by  
11. uploaded\_by\_name  
12. status \= queued

Worker Job Payload

The queued worker job should contain only metadata and S3 reference.

Example:

{

  "upload\_id": "\<uuid\>",

  "partner\_id": "\<uuid\>",

  "period\_month": 6,

  "period\_year": 2026,

  "upload\_type": "TRADER\_GPM",

  "s3\_bucket": "\<bucket\>",

  "s3\_key": "incentive/trader-uploads/\<partner\_id\>/2026-06/TRADER\_GPM/\<upload\_id\>/original.csv",

  "uploaded\_by": "\<uuid\>"

}

The job payload should not contain CSV row data.

Worker Processing Rules

1. Worker fetches upload session by upload\_id.  
2. Worker locks the upload session row.  
3. Worker validates that status \= queued.  
4. Worker updates status to processing and sets processing\_started\_at.  
5. Worker reads original CSV file from S3.  
6. Worker validates CSV header and file structure.  
7. Worker rejects empty files.  
8. Worker validates row-level mandatory fields.  
9. Worker validates numeric fields.  
10. Worker detects duplicate rows within the same file.  
11. Worker enriches GPM rows using Product Submissions API.  
12. Worker stores rejected rows in incentive\_upload\_errors.  
13. Worker writes valid rows into active Trader stock/GPM activity tables.  
14. Worker generates success CSV.  
15. Worker generates reject CSV if there are rejected rows.  
16. Worker uploads success/reject files to S3.  
17. Worker stores success\_file\_key and reject\_file\_key in incentive\_upload\_sessions.  
18. Worker updates row counts and final status.  
19. Worker should not automatically trigger recalculation.  
20. Updated data will be considered in the next MANUAL, CRON, or CATCHUP\_CRON run.

GPM Upload Validation Rules

1. GPM upload file must contain Period, Sales ID, Cust ID, Prod ID, GP, and Revenue.  
2. GPM upload Prod ID must be a valid Product UUID.  
3. Negative GP is allowed.  
4. Negative Revenue is allowed.  
5. If aggregated revenue is negative, calculated GPM percentage should be negative.  
6. Negative GP and negative Revenue should not cancel each other out and produce a positive GPM percentage.  
7. Backend should resolve product metadata from Product Submissions API using Product ID.  
8. Product API response field category\_label should be stored as product\_category.  
9. GPM rows should be rejected if Product ID is not found.  
10. GPM rows should be rejected if product is inactive.  
11. Product channel validation is not required.  
12. Duplicate GPM rows with the same Period \+ Sales ID \+ Cust ID \+ Prod ID in the same upload should be rejected.  
13. KW / Special Choice exclusion field is pending Product confirmation and should not be hardcoded using grade.

Natural Key

Duplicate stock rows with the same active-row natural key in the same upload should be rejected.

For stock upload types, recommended active-row natural key:

partner\_id \+ period\_month \+ period\_year \+ salesperson\_id \+ unit\_code \+ category \+ grade

For GPM upload, active-row natural key is:

partner\_id \+ period\_month \+ period\_year \+ salesperson\_id \+ customer\_id \+ product\_id

This is derived from the confirmed GPM upload unique identifier:

Period \+ Sales ID \+ Cust ID \+ Prod ID

Duplicate GPM rows with the same natural key in the same upload should be rejected.

If an active row already exists with the same natural key, the worker should follow Trader upload upsert behavior.

Trader Upload Upsert Behavior

Insert case:

If no active row exists for the same natural key, insert a new active row.

Update case:

If an active row exists for the same natural key and uploaded values are different:

Old row:

row\_status \= superseded  
 is\_active \= false  
 superseded\_by \= new\_row\_id

New row:

row\_status \= active  
 is\_active \= true

Unchanged case:

If an active row exists for the same natural key and uploaded values are unchanged, do not insert a new row.

Count the row as unchanged\_rows.

Success File

Worker should generate a success CSV file containing accepted rows.

For each accepted row, success CSV should include action:

1. inserted  
2. updated  
3. unchanged

Success file key format:

incentive/trader-uploads/{partner\_id}/{period}/{upload\_type}/{upload\_id}/success.csv

Reject File

Worker should generate a reject CSV file if there are rejected rows.

Reject CSV should include:

1. row\_number  
2. error\_code  
3. message  
4. details  
5. record

Reject file key format:

incentive/trader-uploads/{partner\_id}/{period}/{upload\_type}/{upload\_id}/reject.csv

Response

{  
  "status": "success",  
  "data": {  
    "upload\_id": "\<uuid\>",  
    "upload\_type": "TRADER\_GPM",  
    "period": "2026-06",  
    "processing\_status": "queued",  
    "message": "File uploaded successfully and queued for processing."  
  }  
}

Error Response  
{  
  "status": "error",  
  "error\_code": "TRADER\_UPLOAD\_FAILED",  
  "message": "Trader upload failed",  
  "details": {  
    "reason": "Could not store file in S3 or queue processing job."  
  }  
}

##   **15.6 GET Trader Upload Status**

Endpoint

GET /api/incentives/v1/trader-uploads/:upload\_id/status

Purpose

Returns processing status, row count summary, sample errors, and backend download URLs for original, success, and reject files.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| upload\_id | Yes | Upload session ID |

Response

{  
  "status": "success",  
  "data": {  
    "upload\_id": "\<uuid\>",  
    "upload\_type": "TRADER\_GPM",  
    "period": "2026-06",  
    "processing\_status": "partial\_success",  
    "original\_filename": "trader\_gpm\_2026\_06.csv",  
    "summary": {  
      "total\_rows": 100,  
      "success\_rows": 92,  
      "insert\_rows": 80,  
      "update\_rows": 10,  
      "unchanged\_rows": 2,  
      "rejected\_rows": 8  
    },  
    "files": {  
      "original\_file": {  
        "available": true,  
        "download\_url": "/api/incentives/v1/trader-uploads/\<upload\_id\>/download?type=original"  
      },  
      "success\_file": {  
        "available": true,  
        "download\_url": "/api/incentives/v1/trader-uploads/\<upload\_id\>/download?type=success"  
      },  
      "reject\_file": {  
        "available": true,  
        "download\_url": "/api/incentives/v1/trader-uploads/\<upload\_id\>/download?type=reject"  
      }  
    },  
    "sample\_errors": \[  
      {  
        "row\_number": 12,  
        "error\_code": "PRODUCT\_NOT\_FOUND",  
        "message": "Product ID was not found in Product API."  
      }  
    \],  
    "processing\_started\_at": "2026-07-31T10:30:00Z",  
    "completed\_at": "2026-07-31T10:31:00Z"  
  }  
}

Rules

1. download\_url should be backend API URL, not raw S3 URL.  
2. Backend should not expose raw S3 keys to frontend.  
3. Backend should not return presigned GET URLs in this response.  
4. If success\_file\_key is null, success\_file.available should be false.  
5. If reject\_file\_key is null, reject\_file.available should be false.  
6. sample\_errors should be fetched from incentive\_upload\_errors.  
7. For queued or processing uploads, success/reject files may not be available yet.

Error Response

{  
  "status": "error",  
  "error\_code": "UPLOAD\_SESSION\_NOT\_FOUND",  
  "message": "Upload session not found."  
}

---

## **15.7 GET Trader Upload History**

Endpoint

GET /api/incentives/v1/trader-uploads

Purpose

Returns Trader upload history for a partner.

Query Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| period | No | Period month in YYYY-MM format |
| upload\_type | No | Filter by upload type |
| status | No | queued, processing, success, partial\_success, failed, cancelled |
| uploaded\_by | No | Filter by uploader user ID |
| page | No | Page number |
| limit | No | Page size |

Response

{  
  "status": "success",  
  "data": {  
    "uploads": \[  
      {  
        "upload\_id": "\<uuid\>",  
        "upload\_type": "TRADER\_GPM",  
        "period": "2026-06",  
        "status": "partial\_success",  
        "original\_filename": "trader\_gpm\_2026\_06.csv",  
        "total\_rows": 100,  
        "success\_rows": 92,  
        "insert\_rows": 80,  
        "update\_rows": 10,  
        "unchanged\_rows": 2,  
        "rejected\_rows": 8,  
        "files": {  
          "original\_file\_available": true,  
          "success\_file\_available": true,  
          "reject\_file\_available": true  
        },  
        "uploaded\_by": "\<uuid\>",  
        "uploaded\_by\_name": "Admin User",  
        "processing\_started\_at": "2026-07-31T10:30:00Z",  
        "completed\_at": "2026-07-31T10:31:00Z",  
        "created\_at": "2026-07-31T10:29:00Z"  
      }  
    \],  
    "pagination": {  
      "page": 1,  
      "limit": 20,  
      "total": 1  
    }  
  }  
}

Rules

1. This API should not return raw S3 keys.  
2. This API may return file availability flags.  
3. Actual file download should use the download API in Section 15.8.  
4. status filter should support queued, processing, success, partial\_success, failed, and cancelled.

---

## **15.8 GET Trader Upload File Download**

Endpoint

GET /api/incentives/v1/trader-uploads/:upload\_id/download?type=original|success|reject

Purpose

Downloads the original, success, or reject CSV file for a Trader upload.

This API does not return a presigned S3 URL.

Backend fetches the file from S3 and streams it to the frontend as a downloadable file.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| upload\_id | Yes | Upload session ID |

Query Parameters

| Parameter | Required | Allowed Values | Description |
| ----- | ----- | ----- | ----- |
| type | Yes | original, success, reject | File type to download |

Backend Rules

1. Validate partner\_id from headers.  
2. Validate upload\_id.  
3. Fetch upload session.  
4. Ensure upload belongs to the authenticated partner.  
5. Select file key based on type.  
6. type \= original uses original\_file\_key.  
7. type \= success uses success\_file\_key.  
8. type \= reject uses reject\_file\_key.  
9. If selected file key is missing, return FILE\_NOT\_FOUND.  
10. Fetch S3 object using stored s3\_bucket and file key.  
11. Stream S3 object to response.  
12. Set Content-Type as text/csv.  
13. Set Content-Disposition as attachment.  
14. Set Cache-Control as no-store.  
15. Do not expose raw S3 key in the response.

Response

This API returns a downloadable CSV file stream.

Example response headers:

Content-Type: text/csv

Content-Disposition: attachment; filename="trader\_gpm\_2026\_06\_reject.csv"

Cache-Control: no-store

Error Response

{

  "status": "error",

  "error\_code": "FILE\_NOT\_FOUND",

  "message": "Requested upload file is not available."

}

## **15.9 GET Active Trader Data**

Endpoint

GET /api/incentives/v1/trader-data/active

Purpose

Returns current active Trader stock/GPM dataset for a selected period and upload type.

This API should show only active rows that were successfully processed by Trader upload worker.

Superseded and deleted rows should not appear unless explicitly requested through a future audit API.

Query Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| period | Yes | Period month in YYYY-MM format |
| upload\_type | Yes | Trader upload type |
| salesperson\_id | No | Filter by salesperson |
| unit\_code | No | Filter by unit / branch code |
| page | No | Page number |
| limit | No | Page size |

Response for Stock Upload Type

{

  "status": "success",

  "data": {

    "period": "2026-06",

    "upload\_type": "TRADER\_STOCK\_BY\_PRODUCT",

    "rows": \[

      {

        "row\_id": "\<uuid\>",

        "salesperson\_id": "\<uuid\>",

        "unit\_code": "U01",

        "category": "BY\_PRODUCT",

        "grade": null,

        "stock\_eom": 533,

        "billing\_eom": 192084,

        "row\_status": "active",

        "upload\_id": "\<uuid\>",

        "created\_at": "2026-07-02T10:30:00Z"

      }

    \],

    "pagination": {

      "page": 1,

      "limit": 20,

      "total": 1

    }

  }

}

Response for GPM Upload Type

{

  "status": "success",

  "data": {

    "period": "2026-06",

    "upload\_type": "TRADER\_GPM",

    "rows": \[

      {

        "row\_id": "\<uuid\>",

        "salesperson\_id": "\<uuid\>",

        "customer\_id": "CUST001",

        "product\_id": "51753d2e-b660-4f3f-92a1-9cc8d88862f4",

        "product\_code": "1050103026",

        "product\_name": "BC CU 8 MCD U01/1.0KG TC",

        "product\_category": "BY PRODUCT",

        "revenue": 980000000,

        "gp\_value": 42000000,

        "row\_status": "active",

        "upload\_id": "\<uuid\>",

        "created\_at": "2026-07-02T10:30:00Z"

      }

    \],

    "pagination": {

      "page": 1,

      "limit": 20,

      "total": 1

    }

  }

}

## **15.10 DELETE Active Trader Data Rows**

Endpoint

DELETE /api/incentives/v1/trader-data/active/rows

Purpose

Marks selected active Trader stock/GPM rows as deleted.

This is a soft delete.

Rows are not physically deleted from the database.

Request

{

  "period": "2026-06",

  "upload\_type": "TRADER\_STOCK\_BY\_PRODUCT",

  "row\_ids": \["\<uuid\>", "\<uuid\>"\],

  "delete\_reason": "Incorrect rows uploaded"

}

Validation Rules

1. period must be YYYY-MM.  
2. upload\_type must be valid.  
3. row\_ids must be non-empty.  
4. delete\_reason is required.  
5. Delete is rejected if a Business 1 calculation run is pending or processing for the same partner and period.  
6. Only active rows can be deleted.  
7. Rows should be soft-deleted by updating row\_status and is\_active.  
8. Delete should not automatically trigger recalculation.  
9. Updated data will be considered in the next MANUAL, CRON, or CATCHUP\_CRON run.

Delete Behavior

For each selected active row:

row\_status \= deleted  
is\_active \= false  
deleted\_by \= current\_user\_id  
deleted\_at \= current timestamp  
delete\_reason \= provided delete reason

Response

{

  "status": "success",

  "data": {

    "period": "2026-06",

    "upload\_type": "TRADER\_STOCK\_BY\_PRODUCT",

    "requested\_rows": 2,

    "deleted\_rows": 2,

    "skipped\_rows": 0

  }

}

Partial Success Response

{

  "status": "success",

  "data": {

    "period": "2026-06",

    "upload\_type": "TRADER\_STOCK\_BY\_PRODUCT",

    "requested\_rows": 2,

    "deleted\_rows": 1,

    "skipped\_rows": 1,

    "skipped\_details": \[

      {

        "row\_id": "\<uuid\>",

        "reason": "Row is already deleted or superseded."

      }

    \]

  }

}

## **15.11 DELETE Active Trader Data Rows by Upload**

Endpoint

DELETE /api/incentives/v1/trader-uploads/:upload\_id/active-rows

Purpose

Marks all active Trader stock/GPM rows created by a specific upload as deleted.

This is a soft delete.

Rows are not physically deleted from the database.

This API is useful when an admin wants to remove the active data impact of an uploaded file.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| upload\_id | Yes | Upload session ID |

Request

{

  "delete\_reason": "Incorrect file uploaded"

}

Validation Rules

1. upload\_id must exist.  
2. Upload session must belong to the authenticated partner.  
3. Upload session must be in success or partial\_success status.  
4. delete\_reason is required.  
5. Delete is rejected if a Business 1 calculation run is pending or processing for the same partner and period.  
6. Only active rows created by the upload\_id are deleted.  
7. Superseded or already deleted rows are skipped.  
8. Delete should not automatically trigger recalculation.  
9. Updated data will be considered in the next MANUAL, CRON, or CATCHUP\_CRON run.  
10. Deleting rows from an upload does not restore older superseded rows.

Delete Behavior

For each active row created by upload\_id:

row\_status \= deleted  
 is\_active \= false  
 deleted\_by \= current\_user\_id  
 deleted\_at \= current timestamp  
 delete\_reason \= provided delete reason

Response

{  
  "status": "success",  
  "data": {  
    "upload\_id": "\<uuid\>",  
    "upload\_type": "TRADER\_GPM",  
    "period": "2026-06",  
    "requested\_rows": 100,  
    "deleted\_rows": 95,  
    "skipped\_rows": 5  
  }  
}  
Partial Success Response  
{  
  "status": "success",  
  "data": {  
    "upload\_id": "\<uuid\>",  
    "upload\_type": "TRADER\_GPM",  
    "period": "2026-06",  
    "requested\_rows": 100,  
    "deleted\_rows": 90,  
    "skipped\_rows": 10,  
    "skipped\_details": \[  
      {  
        "row\_id": "\<uuid\>",  
        "reason": "Row is already deleted or superseded."  
      }  
    \]  
  }  
}

## **15.12 GET Feed Status**

Endpoint

GET /incentive/v1/feeds/status/:log\_id

Purpose

Returns status of monthly input ingestion or refresh.

This endpoint is used for Customer Management refresh logs and AR Ageing feed logs.

Applicable feed types:

1. CUSTOMER\_HANDLED  
2. NEW\_TRANSACTED\_CUSTOMERS  
3. AR\_AGEING

Trader stock and Trader GPM uploads should use Trader upload APIs instead of this feed-status API.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| log\_id | Yes | Feed log ID |

Response

{

  "status": "success",

  "data": {

    "log\_id": "\<uuid\>",

    "feed\_type": "NEW\_TRANSACTED\_CUSTOMERS",

    "period\_month": 6,

    "period\_year": 2026,

    "status": "success",

    "total\_rows": 1000,

    "accepted\_rows": 1000,

    "rejected\_rows": 0,

    "error\_details": \[\]

  }

}

# **16\. Calculation APIs**

Calculation APIs are used by admin users to trigger manual recalculation and view calculation run status.

Business 1 calculation runs are asynchronous.

The API creates a run entry and queues calculation jobs. Actual worker sequencing, BullMQ queues, retries, and DLQ behavior are covered separately in Section 21\.

Business 1 uses incentive\_run\_log for run tracking.

Business 1 does not use Open / Grace / Locked cycle state.

## **16.1 Manual Calculation Trigger**

Endpoint:

POST /api/incentives/v1/calculations/manual

Purpose:

Triggers manual recalculation for a Business 1 period.

Manual recalculation can be triggered even after CATCHUP\_CRON has completed.

Manual recalculation does not lock the period because Business 1 does not use cycle locking.

Manual recalculation is mainly used after:

1. corrected input refresh  
2. corrected AR Ageing feed replacement  
3. completed Trader upload processing  
4. Trader uploaded row deletion  
5. config correction  
6. failed or partial calculation run  
7. business-requested recalculation

Request:

{  
 "period": "2026-06",  
 "salesperson\_ids": \["\<uuid\>", "\<uuid\>"\],  
 "force\_proceed": false  
 }

### 

| Field | Required | Format | Description |
| ----- | ----- | ----- | ----- |
| period | Yes | YYYY-MM | Business 1 period to recalculate |
| salesperson\_ids | No | UUID array | Optional list of salespeople to recalculate |
| force\_proceed | No | Boolean | Allows admin to proceed when backend returns warnings. Default is false |

If salesperson\_ids is empty or not provided, backend recalculates the full period provided in the request.

Rules:

1. Backend uses the period provided in the request. The period must be valid YYYY-MM and is converted internally into period\_month and period\_year.  
2. Manual recalculation is rejected if another Business 1 run is already pending or processing for the same partner and period.  
3. Manual recalculation can be triggered only by configured privileged/admin users.  
4. Privileged user list should be maintained through backend environment/config.  
5. Manual recalculation creates an incentive\_run\_log row with business\_code \= BUSINESS\_1.  
6. Manual recalculation uses run\_type \= MANUAL.  
7. Existing calculated results are not physically deleted.  
8. Result publication and deprecation should follow Section 8.8.  
9. If salesperson\_ids are provided, backend recalculates selected salespeople and impacted hierarchy.  
10. If selected salesperson impacts Level 2 / Level 3 roll-up, impacted Level 2 / Level 3 users should also be recalculated.  
11. If Volume Achievement is recalculated, Team Volume Achievement must also be recalculated.  
12. Manual recalculation is rejected if any required Business 1 input ingestion or Trader upload job is queued or processing for the same partner and period.  
13. period is mandatory for manual calculation.  
14. period must not be before the Business 1 engine launch period.  
15. Manual recalculation for past Business 1 periods is allowed only for periods supported by available input data, config validity, and result retention rules.  
16. Manual recalculation should use configs active for the requested period, not the current date.  
17. Run-in-progress validation must use the requested period.  
18. Input ingestion / Trader upload queued-or-processing validation must use the requested period

Response:

{  
  "status": "success",  
  "data": {  
    "run\_id": "\<uuid\>",  
    "business\_code": "BUSINESS\_1",  
    "run\_type": "MANUAL",  
    "triggered\_by": "MANUAL",  
    "period": "2026-06",  
    "status": "pending",  
    "scope": {  
      "is\_full\_cycle": false,  
      "requested\_salesperson\_ids": \["\<uuid\>", "\<uuid\>"\],  
      "impacted\_salesperson\_ids": \["\<uuid\>", "\<uuid\>", "\<uuid\>"\]  
    }  
  }  
}

Full-period response example:

{  
  "status": "success",  
  "data": {  
    "run\_id": "\<uuid\>",  
    "business\_code": "BUSINESS\_1",  
    "run\_type": "MANUAL",  
    "triggered\_by": "MANUAL",  
    "period": "2026-06",  
    "status": "pending",  
    "scope": {  
      "is\_full\_cycle": true,  
      "requested\_salesperson\_ids": \[\],  
      "impacted\_salesperson\_ids": \[\]  
    }  
  }  
}

Error Response — Run Already In Progress:

{  
  "status": "error",  
  "error\_code": "RUN\_IN\_PROGRESS",  
  "message": "Manual recalculation cannot be triggered while another calculation run is in progress for the same partner and period."  
}

Error Response — Unauthorized User:

{  
  "status": "error",  
  "error\_code": "MANUAL\_RECALCULATION\_NOT\_ALLOWED",  
  "message": "User is not allowed to trigger manual recalculation."  
}

## **16.2 GET Calculation Runs**

Endpoint

GET /api/incentives/v1/calculations/runs

Purpose

Returns Business 1 calculation run history.

This API reads from incentive\_run\_log.

Query Parameters

| Parameter | Required | Allowed Values / Format | Description |
| ----- | ----- | ----- | ----- |
| period | No | YYYY-MM | Filter by calculation period |
| run\_type | No | CRON, CATCHUP\_CRON, MANUAL | Filter by run type |
| status | No | pending, processing, success, partial, failed | Filter by run status |
| triggered\_by | No | CRON, MANUAL | Filter by trigger source |
| page | No | number | Page number |
| limit | No | number | Page size |

Response

**Run API Field Mapping**

| API Field | Source | Notes |
| ----- | ----- | ----- |
| run\_id | incentive\_run\_log.run\_id | Business-facing run identifier exposed in API response. |
| business\_code | incentive\_run\_log.business\_code | BUSINESS\_1 for Business 1 runs. |
| period | incentive\_run\_log.month \+ incentive\_run\_log.year | Backend formats month/year as YYYY-MM. |
| run\_type | incentive\_run\_log.run\_type | CRON, CATCHUP\_CRON, or MANUAL. |
| triggered\_by | incentive\_run\_log.triggered\_by | Existing common trigger field. Use CRON for CRON, CRON for CATCHUP\_CRON, and MANUAL for MANUAL. |
| triggered\_by\_id | incentive\_run\_log.triggered\_by\_id | User ID for manual runs. Can be null for scheduled CRON runs. |
| status | incentive\_run\_log.status | pending, processing, success, partial, or failed. |
| is\_superseded | incentive\_run\_log.is\_superseded | Optional run-level flag. Result visibility is controlled by result-level publication\_status and is\_deprecated. |
| superseded\_by\_run\_id | incentive\_run\_log.superseded\_by\_run\_id | Optional run-level lineage. Scoped result replacement is tracked on result rows. |
| total\_participants | incentive\_run\_log.total | Total participants/jobs considered for the run. |
| processed\_count | incentive\_run\_log.processed | Number of participants/jobs processed. |
| failed\_count | incentive\_run\_log.failed | Number of failed participants/jobs. |
| success\_count | Derived | Prefer deriving from result rows when participant-level accuracy is needed. Otherwise use processed\_count \- failed\_count. |
| started\_at | incentive\_run\_log.created\_at | Use created\_at unless a separate start timestamp is added later. |
| completed\_at | incentive\_run\_log.completed\_at | Completion timestamp from run log. |
| created\_at | incentive\_run\_log.created\_at | Run creation timestamp. |

{  
  "status": "success",  
  "data": {  
    "runs": \[  
      {  
        "run\_id": "\<uuid\>",  
        "business\_code": "BUSINESS\_1",  
        "period": "2026-06",  
        "run\_type": "CRON",  
        "triggered\_by": "CRON",  
        "status": "success",  
        "is\_superseded": false,  
        "superseded\_by\_run\_id": null,  
        "summary": {  
          "total\_participants": 300,  
          "processed\_count": 298,  
          "success\_count": 296,  
          "failed\_count": 2  
        },  
        "started\_at": "2026-07-02T01:00:00Z",  
        "completed\_at": "2026-07-02T01:20:00Z",  
        "created\_at": "2026-07-02T01:00:00Z"  
      }  
    \],  
    "pagination": {  
      "page": 1,  
      "limit": 20,  
      "total": 1  
    }  
  }  
}

Notes:

1. run\_type identifies whether the run is CRON, CATCHUP\_CRON, or MANUAL.  
2. triggered\_by identifies how the run was triggered.  
3. is\_superseded identifies older run outputs replaced by a newer publishable run.  
4. Business 1 does not use cycle locking. A newer publishable run can become the latest current result, subject to Section 8.8 publication and deprecation rules.

## **16.3 GET Calculation Run Detail**

Endpoint

GET /api/incentives/v1/calculations/runs/:run\_id

Purpose

Returns detail for one Business 1 calculation run.

This API should show run summary, participant summary, error summary, and latest status.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| run\_id | Yes | Calculation run ID |

Response

{  
  "status": "success",  
  "data": {  
    "run": {  
      "run\_id": "\<uuid\>",  
      "business\_code": "BUSINESS\_1",  
      "period": "2026-06",  
      "run\_type": "CRON",  
      "triggered\_by": "CRON",  
      "status": "partial",  
      "is\_superseded": false,  
      "superseded\_by\_run\_id": null,  
      "started\_at": "2026-07-02T01:00:00Z",  
      "completed\_at": "2026-07-02T01:20:00Z",  
      "summary": {  
        "total\_participants": 300,  
        "processed\_count": 298,  
        "success\_count": 296,  
        "failed\_count": 2  
      },  
      "breakdown": \[  
        {  
          "salesperson\_type": "NON\_TRADER",  
          "total\_participants": 200,  
          "success\_count": 200,  
          "failed\_count": 0  
        },  
        {  
          "salesperson\_type": "TRADER",  
          "total\_participants": 100,  
          "success\_count": 96,  
          "failed\_count": 2,  
          "skipped\_count": 2  
        }  
      \],  
      "error\_summary": \[  
        {  
          "error\_code": "TRADER\_GPM\_DATA\_MISSING",  
          "count": 2  
        }  
      \],  
      "sample\_errors": \[  
        {  
          "salesperson\_id": "\<uuid\>",  
          "salesperson\_name": "Budi",  
          "salesperson\_type": "TRADER",  
          "level": 1,  
          "original\_role": "SALES",  
          "incentive\_point\_code": "TR\_GPM\_BY\_PRODUCT",  
          "error\_code": "TRADER\_GPM\_DATA\_MISSING",  
          "error\_message": "Trader GPM data is missing for the calculation period."  
        }  
      \]  
    }  
  }  
}

The breakdown section is derived from participant snapshot, result tables, and run errors.

It does not require a separate run-track table.

## **16.4 GET Business 1 Period Action State**

Endpoint:

GET /api/incentives/v1/calculations/period-action-state

Purpose:

Returns whether Business 1 mutating actions are allowed for a period based on active calculation/input processing and action-specific finality rules. Customer Handled refresh and New Customer Monthly replacement have an additional cutoff after successful CATCHUP\_CRON completion.

This API helps frontend decide whether config changes, input refresh, AR Ageing feed replacement, Trader upload, Trader delete, or manual recalculation should be allowed.

Query Parameters:

| Parameter | Required | Format | Description |
| ----- | ----- | ----- | ----- |
| period | No | YYYY-MM | Calculation period. If not provided, backend resolves current Business 1 calculation period |

Response:

{  
 "status": "success",  
 "data": {  
   "period": "2026-06",  
   "run\_in\_progress": false,  
   "input\_processing\_in\_progress": true,  
   "latest\_run": {  
     "run\_id": "\<uuid\>",  
     "run\_type": "CATCHUP\_CRON",  
     "status": "success",  
     "completed\_at": "2026-07-04T01:20:00Z"  
   },  
   "blocking\_processes": \[  
     {  
     "process\_type": "TRADER\_UPLOAD",  
     "reference\_id": "\<upload\_id\>",  
     "upload\_type": "TRADER\_GPM",  
     "status": "processing",  
     "message": "Trader GPM upload is still processing for this period."  
     }  
   \],  
   "allowed\_actions": {  
     "config\_edit": true,  
     "input\_refresh": true,

"customer\_handled\_refresh": false,

     "feed\_replacement": true,

"new\_customer\_monthly\_replacement": false,

     "trader\_upload": true,  
     "trader\_delete": true,  
     "manual\_recalculation": false  
   }  
 }  
}

**Rules**

1. If any Business 1 calculation run is pending or processing for the same partner and period, run\_in\_progress should be true.  
2. If any required input ingestion or upload process is queued or processing for the same partner and period, input\_processing\_in\_progress should be true.  
3. Input processing blockers include:  
   * AR Ageing feed ingestion with status pending or processing  
   * Trader upload session with status queued or processing  
   * Customer Handled refresh with status pending or processing  
4. The response must separately determine whether a successful CATCHUP\_CRON exists for the requested partner and period.

If a successful CATCHUP\_CRON exists:  
customer\_handled\_refresh \= false  
new\_customer\_monthly\_replacement \= false  
These customer-specific fields remain false even when run\_in\_progress \= false.

5. If run\_in\_progress \= true, all mutating actions should be false.  
6. If input\_processing\_in\_progress \= true, manual\_recalculation should be false because calculation should not start while required input data is still being processed.  
7. Other actions such as config edit, input refresh, feed replacement, Trader upload, and Trader delete should still depend on their own API-level validation. This API only exposes the current period state for frontend decision support.  
8. File download APIs and result view APIs are read-only and may remain allowed.  
9. CRON completion does not globally lock the period.  
10. Successful CATCHUP\_CRON completion does not globally lock the period, but it finalizes Customer Handled and New Customer Monthly inputs. Therefore, customer\_handled\_refresh and new\_customer\_monthly\_replacement are false after successful CATCHUP\_CRON completion.  
11. MANUAL can be triggered after CATCHUP\_CRON using the already-finalized inputs, but only when run\_in\_progress \= false and input\_processing\_in\_progress \= false.

# **17\. Result APIs**

Result APIs are used to view Business 1 calculated incentive outputs.

By default, result APIs should return only latest published, non-deprecated results.

Older deprecated results remain available for audit/debugging through run-specific filters if needed.

Business 1 result APIs read from:

1. incentive\_final\_results  
2. incentive\_point\_results  
3. incentive\_ar\_ageing\_deduction\_results  
4. incentive\_participant\_snapshots

## **17.1 GET Final Results**

Endpoint

GET /api/incentives/v1/results

Purpose

Returns final incentive results for a selected period.

This API is used for payout reporting and admin result review.

Query Parameters

| Parameter | Required | Format / Allowed Values | Description |
| ----- | ----- | ----- | ----- |
| period | Yes | YYYY-MM | Calculation period |
| salesperson\_type | No | NON\_TRADER, TRADER | Filter by salesperson type |
| level | No | 1, 2, 3 | Filter by calculation level |
| original\_role | No | string | Filter by source role if required |
| channel | No | string | Mainly applicable for Non-Trader |
| salesperson\_id | No | UUID | Filter one salesperson |
| run\_id | No | UUID | Filter result for a specific run |
| status | No | success, skipped, failed | Filter by result status |
| page | No | number | Page number |
| limit | No | number | Page size |

Response

{  
  "status": "success",  
  "data": {  
    "period": "2026-06",  
    "results": \[  
      {  
        "result\_id": "\<uuid\>",  
        "run\_id": "\<uuid\>",  
        "salesperson\_id": "\<uuid\>",  
        "salesperson\_name": "Budi",  
        "salesperson\_type": "NON\_TRADER",  
        "level": 1,  
        "original\_role": "SALES",  
        "channel": "Catering",  
        "total\_points": 10,  
        "gross\_incentive": 2025000,  
        "deduction\_percentage": 5,  
        "deduction\_amount": 101250,  
        "net\_incentive": 1923750,  
        "status": "success"  
      },  
      {  
        "result\_id": "\<uuid\>",  
        "run\_id": "\<uuid\>",  
        "salesperson\_id": "\<uuid\>",  
        "salesperson\_name": "Andi",  
        "salesperson\_type": "TRADER",  
        "level": 2,  
        "original\_role": "KAO",  
        "channel": null,  
        "total\_points": 8,  
        "gross\_incentive": 1800000,  
        "deduction\_percentage": 0,  
        "deduction\_amount": 0,  
        "net\_incentive": 1800000,  
        "status": "success"  
      }  
    \],  
    "pagination": {  
      "page": 1,  
      "limit": 20,  
      "total": 2  
    }  
  }  
}

Rules:

1. If run\_id is not provided, return latest published, non-deprecated final results for the period.  
2. If run\_id is provided, return results from that specific run.  
3. Trader results should always have deduction\_percentage \= 0 and deduction\_amount \= 0\.  
4. Non-Trader results should include AR ageing deduction where applicable.  
5. Inactive participants should not appear unless they were part of the run snapshot and result was generated before inactive status handling.

## **17.2 GET Final Result Detail**

Endpoint

GET /api/incentives/v1/results/:result\_id

Purpose

Returns detailed final result for one participant.

This API should show:

1. participant details  
2. incentive point results  
3. payout lookup details  
4. AR ageing deduction details, if applicable  
5. calculation audit details

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| result\_id | Yes | Final result ID |

Response

{  
  "status": "success",  
  "data": {  
    "result": {  
      "result\_id": "\<uuid\>",  
      "run\_id": "\<uuid\>",  
      "period": "2026-06",  
      "salesperson\_id": "\<uuid\>",  
      "salesperson\_name": "Budi",  
      "salesperson\_type": "NON\_TRADER",  
      "level": 2,  
      "original\_role": "SPV",  
      "channel": "Catering",  
      "total\_points": 10,  
      "payout": {  
        "payout\_config\_id": "\<uuid\>",  
        "payout\_row\_id": "\<uuid\>",  
        "total\_points": 10,  
        "gross\_incentive": 2025000  
      },  
      "deduction": {  
        "ageing\_deduction\_result\_id": "\<uuid\>",  
        "deduction\_percentage": 5,  
        "deduction\_amount": 101250  
      },  
      "net\_incentive": 1923750,  
      "status": "success",  
      "incentive\_points": \[  
        {  
          "result\_id": "\<uuid\>",  
          "incentive\_point\_code": "NT\_VOLUME\_ACHIEVEMENT",  
          "incentive\_point\_name": "Volume Achievement",  
          "achievement\_value": 1080,  
          "achievement\_percentage": 108,  
          "points": 5,  
          "matched\_slab\_id": "\<uuid\>",  
          "status": "success"  
        },  
        {  
          "result\_id": "\<uuid\>",  
          "incentive\_point\_code": "NT\_TRANSACTED\_OUTLETS",  
          "incentive\_point\_name": "% Transacted Outlets",  
          "achievement\_value": 66,  
          "achievement\_percentage": 66,  
          "points": 2,  
          "matched\_slab\_id": "\<uuid\>",  
          "status": "success"  
        },  
        {  
          "result\_id": "\<uuid\>",  
          "incentive\_point\_code": "NT\_TEAM\_VOLUME\_ACHIEVEMENT",  
          "incentive\_point\_name": "Team Volume Achievement",  
          "achievement\_value": 25,  
          "achievement\_percentage": 25,  
          "points": 3,  
          "matched\_slab\_id": "\<uuid\>",  
          "status": "success"  
        }  
      \],  
      "ageing\_deduction": {  
       "total\_overdue": 192000000,  
        "bucket\_amounts": {  
          "OD\_GT\_0": 41000000,  
          "OD\_GT\_7": 20000000,  
          "OD\_GT\_14": 60000000,  
          "OD\_GT\_21": 30000000,  
          "OD\_GT\_30": 41000000  
        },  
     "final\_bucket\_code": "OD\_GT\_30",  
     "deduction\_percentage": 5,  
     "deduction\_amount": 101250  
      },  
      "calculation\_details": {}  
    }  
  }  
}

For Trader participants:

1. ageing\_deduction should be null.  
2. deduction\_percentage should be 0\.  
3. deduction\_amount should be 0\.  
4. gross\_incentive should equal net\_incentive.

Trader response example:

{  
  "status": "success",  
  "data": {  
    "result": {  
      "result\_id": "\<uuid\>",  
      "run\_id": "\<uuid\>",  
      "period": "2026-06",  
      "salesperson\_id": "\<uuid\>",  
      "salesperson\_name": "Andi",  
      "salesperson\_type": "TRADER",  
      "level": 1,  
      "original\_role": "SALES",  
      "channel": null,  
      "total\_points": 8,  
      "payout": {  
        "payout\_config\_id": "\<uuid\>",  
        "payout\_row\_id": "\<uuid\>",  
        "total\_points": 8,  
        "gross\_incentive": 1800000  
      },  
      "deduction": {  
        "ageing\_deduction\_result\_id": null,  
        "deduction\_percentage": 0,  
        "deduction\_amount": 0  
      },  
      "net\_incentive": 1800000,  
      "status": "success",  
      "incentive\_points": \[  
        {  
          "result\_id": "\<uuid\>",  
          "incentive\_point\_code": "TR\_STOCK\_BY\_PRODUCT",  
          "incentive\_point\_name": "Stock Level — By Product",  
          "achievement\_value": 12.5,  
          "achievement\_percentage": null,  
          "points": 2,  
          "matched\_slab\_id": "\<uuid\>",  
          "status": "success"  
        },  
        {  
          "result\_id": "\<uuid\>",  
          "incentive\_point\_code": "TR\_GPM\_BY\_PRODUCT",  
          "incentive\_point\_name": "GPM by Product",  
          "achievement\_value": 4.28,  
          "achievement\_percentage": 4.28,  
          "points": 3,  
          "matched\_slab\_id": "\<uuid\>",  
          "status": "success"  
        }  
      \],  
      "ageing\_deduction": null,  
      "calculation\_details": {}  
    }  
  }  
}

## **17.3 GET Incentive Point Results for Final Result**

Endpoint

GET /api/incentives/v1/results/:result\_id/incentive-points

Purpose

Returns incentive point-level results used to calculate one final result.

This API is useful when frontend wants to show point breakdown separately from final result detail.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| result\_id | Yes | Final result ID |

Response

{  
  "status": "success",  
  "data": {  
    "result\_id": "\<uuid\>",  
    "salesperson\_id": "\<uuid\>",  
    "salesperson\_name": "Budi",  
    "period": "2026-06",  
    "salesperson\_type": "NON\_TRADER",  
    "level": 1,  
    "original\_role": "SALES",  
    "channel": "Catering",  
    "incentive\_points": \[  
      {  
        "incentive\_point\_result\_id": "\<uuid\>",  
        "incentive\_point\_code": "NT\_VOLUME\_ACHIEVEMENT",  
        "incentive\_point\_name": "Volume Achievement",  
        "achievement\_value": 1080,  
        "achievement\_percentage": 108,  
        "points": 5,  
        "matched\_slab\_id": "\<uuid\>",  
        "status": "success",  
        "calculation\_details": {  
          "actual\_volume": 1080,  
          "target\_volume": 1000,  
          "achievement\_percentage": 108,  
          "level": 1,  
          "channel": "Catering"  
        }  
      },  
      {  
        "incentive\_point\_result\_id": "\<uuid\>",  
        "incentive\_point\_code": "NT\_TRANSACTED\_OUTLETS",  
        "incentive\_point\_name": "% Transacted Outlets",  
        "achievement\_value": 66,  
        "achievement\_percentage": 66,  
        "points": 2,  
        "matched\_slab\_id": "\<uuid\>",  
        "status": "success",  
        "calculation\_details": {  
          "transacted\_customer\_count": 33,  
          "total\_customer\_count": 50,  
          "achievement\_percentage": 66,  
          "level": 1,  
          "channel": "Catering"  
        }  
      }  
    \]  
  }  
}

## **17.4 GET AR Ageing Deduction Result**

Endpoint

GET /api/incentives/v1/results/:result\_id/ageing-deduction

Purpose

Returns AR ageing deduction result for one Non-Trader final result.

Implementation Scope  
 This is a frontend/admin result API and must be implemented in both WS1 and WS2.

Call flow:  
 Closio / FE → WS1 → ws2targetsales / incentive service

WS1 responsibilities:

1. Validate cookie/session.  
2. Fetch logged-in user details.  
3. Resolve partner\_id and user context.  
4. Forward request to WS2 with S2S headers.

WS1 → WS2 headers:

1. x-client-id  
2. x-client-secret  
3. X-Partner-Id  
4. X-User-Id  
5. X-User-Name

WS2 responsibilities:

1. Validate S2S headers.  
2. Validate result\_id access for the partner.  
3. Fetch AR ageing deduction result from published, non-deprecated result tables by default.  
4. Return Non-Trader AR deduction detail or ageing\_deduction \= null for Trader.

For Trader final results, this API should return ageing\_deduction \= null.

Path Parameters

| Parameter | Required | Description |
| ----- | ----- | ----- |
| result\_id | Yes | Final result ID |

Response for Non-Trader:

| { "status": "success", "data": { "result\_id": "\<uuid\>", "salesperson\_id": "\<uuid\>", "salesperson\_name": "Budi", "period": "2026-06", "salesperson\_type": "NON\_TRADER", "level": 1, "original\_role": "SALES", "channel": "Catering", "ageing\_deduction": { "ageing\_deduction\_result\_id": "\<uuid\>", "total\_overdue": 192000000, "bucket\_amounts": { "OD\_GT\_0": 41000000, "OD\_GT\_7": 20000000, "OD\_GT\_14": 60000000, "OD\_GT\_21": 30000000, "OD\_GT\_30": 41000000 }, "final\_bucket\_code": "OD\_GT\_30", "deduction\_percentage": 5, "deduction\_amount": 101250, "status": "success" } } } |
| :---- |

Response for Trader:

{  
"status": "success",  
"data": {  
"result\_id": "\<uuid\>",  
"salesperson\_id": "\<uuid\>",  
"salesperson\_type": "TRADER",  
"ageing\_deduction": null  
}  
}

## **17.5 Result Visibility Rules**

Default result APIs should return only rows where:

| Field | Required value |
| ----- | ----- |
| publication\_status | published |
| is\_deprecated | false |

For run-specific audit/debugging, APIs may allow run\_id filter.

When run\_id is provided, API may return results for that specific run even if those results are draft or deprecated.

Recommended behavior:

1. Result list without run\_id returns latest published, non-deprecated results.  
2. Result list with run\_id returns results from that run.  
3. Result detail by result\_id returns that result if user has access, even if deprecated.  
4. Draft rows should be clearly marked with publication\_status \= draft if returned through run-specific/debug APIs.  
5. Deprecated rows should be clearly marked with is\_deprecated \= true if returned.

# **18\. Common Error Codes**

Business 1 should use consistent error codes across APIs, feed ingestion, upload validation, calculation runs, and result generation.

Not every error code means the full run must fail.

Some errors are:

1. API validation errors  
2. Row-level feed/upload errors  
3. Calculation warnings  
4. Participant-level calculation failures  
5. Run-level failures

The worker should store calculation-related errors in incentive\_run\_errors where applicable.

## **18.1 Config Errors**

| Error Code | Meaning |
| ----- | ----- |
| INCENTIVE\_POINT\_NOT\_FOUND | Incentive point ID or code does not exist |
| INCENTIVE\_POINT\_INACTIVE | Incentive point is inactive |
| SLAB\_SET\_NOT\_FOUND | Incentive point slab set does not exist |
| CONFIG\_OVERLAP | Config period overlaps an existing active config. Raised from application pre-check or from the `excl_isc_no_active_overlap` DB constraint on concurrent writes. |
| INVALID\_PERIOD | Invalid valid\_from / valid\_to / period |
| INVALID\_SALESPERSON\_TYPE | salesperson\_type is invalid |
| INVALID\_LEVEL | level is invalid or not applicable |
| INVALID\_CHANNEL | channel is missing or invalid |
| INVALID\_SLAB | Slab payload is invalid |
| INVALID\_OPERATOR | Slab operator is invalid |
| DUPLICATE\_SLAB\_BAND | Duplicate operator \+ value row exists within the same channel, salesperson\_type, and level group. |
| DUPLICATE\_BAND\_ORDER | band\_order is repeated within the same channel, salesperson\_type, and level group. |
| INVALID\_POINTS | Points value is invalid |
| PAYOUT\_CONFIG\_MISSING | Payout config is missing for period |
| PAYOUT\_ROW\_MISSING | Payout table row is missing for total\_points and level |
| INVALID\_PAYOUT\_TABLE | Payout table payload is invalid |
| AGEING\_CONFIG\_MISSING | No active AR ageing config header exists for partner \+ calculation period. |
| AGEING\_RULE\_MISSING | AR config exists, but no active rule exists for participant channel \+ salesperson\_type \+ level \+ selected bucket\_code. |
| AGEING\_CONFIG\_NOT\_FOUND | Config ID does not exist for detail/update/status APIs |
| INVALID\_AGEING\_RULES | Create/update payload does not contain exactly five fixed bucket rules per channel \+ level group, or contains invalid/duplicate rule rows. |
| DUPLICATE\_AGEING\_CHANNEL | Same channel appears more than once in the request. |
| DUPLICATE\_AGEING\_LEVEL | Same level appears more than once under the same channel. |
| INVALID\_AGEING\_BUCKET\_CODE | Bucket code is not one of `OD_GT_0`, `OD_GT_7`, `OD_GT_14`, `OD_GT_21`, `OD_GT_30`. |
| DAY\_MULTIPLIER\_CONFIG\_MISSING | Trader stock day multiplier config is missing |
| CONFIG\_CHANGE\_RUN\_IN\_PROGRESS | Config change is not allowed because a Business 1 calculation run is pending or processing for the same partner and period. |
| SLAB\_CONFIG\_MISSING | Active slab config is missing for incentive point, partner, period, salesperson\_type, level, and channel where applicable. |
| SLAB\_NOT\_ALLOWED\_FOR\_DEDUCTION\_COMPONENT | Slab configuration was attempted for an incentive point where component\_type \= DEDUCTION. |
| PAYOUT\_CONFIG\_NOT\_FOUND | Payout config ID does not exist for detail/update/status APIs. |
| TOTAL\_POINTS\_CONTINUITY\_ERROR | Payout table total\_points values are not continuous from 1 to the highest configured total\_points. |
| EDIT\_NOT\_PERMITTED | Config cannot be edited because the config period is fully in the past. |
| VALID\_FROM\_NOT\_EDITABLE | valid\_from cannot be edited because the config has already started. |
| SLABS\_NOT\_EDITABLE | Slab rows cannot be edited because the slab config has already started. |
| POINTS\_NOT\_EDITABLE | Payout rows cannot be edited because the payout config has already started. |
| RULES\_NOT\_EDITABLE | AR ageing deduction rules cannot be edited because the AR ageing config has already started. |

## **18.2 Feed / Input Errors**

| Error Code | Meaning |
| ----- | ----- |
| INVALID\_PAYLOAD | Input payload or source response is invalid |
| INVALID\_PERIOD | Input period is invalid |
| MISSING\_FILE | Push feed file is missing |
| INVALID\_FILE\_TYPE | Only CSV files are supported for push feeds |
| INVALID\_FILE\_STRUCTURE | CSV structure does not match expected feed format |
| CSV\_HEADER\_MISMATCH | CSV header does not match expected columns |
| SOURCE\_RESPONSE\_INVALID | Pull source response is invalid |
| SOURCE\_FETCH\_FAILED | Pull source API call failed |
| MISSING\_SALESPERSON\_ID | salesperson\_id is missing |
| INVALID\_SALESPERSON\_ID | salesperson\_id is invalid |
| DUPLICATE\_ROW | Duplicate row found in incoming dataset |
| INPUT\_REPLACEMENT\_RUN\_IN\_PROGRESS | Input replacement is rejected because a Business 1 calculation run is pending or processing for the same partner and period |
| INPUT\_REPLACEMENT\_FAILED | Input replacement failed unexpectedly. Previous active data remains unchanged |
| CUSTOMER\_COUNT\_MISSING | customer\_count is missing |
| INVALID\_CUSTOMER\_COUNT | customer\_count is invalid |
| CUSTOMER\_ID\_MISSING | customer\_id is missing |
| CUSTOMER\_ASSIGNED\_TO\_MULTIPLE\_SALESPEOPLE | Same customer appears under multiple salespeople |
| NEGATIVE\_AMOUNT | Amount cannot be negative |
| AGEING\_BUCKET\_AMOUNT\_MISSING | One or more overdue bucket amounts are missing |
| TOTAL\_OVERDUE\_MISMATCH | total\_overdue does not match sum of overdue buckets |
| CHANNEL\_MISSING | channel is missing where required |
| FEED\_INGESTION\_FAILED | Feed ingestion failed unexpectedly |
| CUSTOMER\_HANDLED\_SOURCE\_FAILED | The ws2closio Customer Handled API call failed |
| CUSTOMER\_HANDLED\_VALIDATION\_FAILED | The Customer Handled source response failed validation |
| DUPLICATE\_CUSTOMER\_HANDLED\_SALESPERSON | The Customer Handled response contains duplicate salesperson\_id values |
| NEW\_TRANSACTED\_VALIDATION\_FAILED | The New Customer Monthly dataset failed validation |
| INPUT\_REPLACEMENT\_WINDOW\_CLOSED | Customer input replacement is not allowed after successful CATCHUP\_CRON completion for the partner and period |

## **18.3 Trader Upload Errors**

| Error Code | Meaning |
| ----- | ----- |
| INVALID\_UPLOAD\_TYPE | upload\_type is invalid |
| FILE\_MISSING | Upload file is missing |
| INVALID\_FILE\_TYPE | Only CSV files are supported |
| FILE\_SIZE\_EXCEEDED | Uploaded file exceeds configured size limit |
| S3\_UPLOAD\_FAILED | Original upload file could not be stored in S3 |
| UPLOAD\_QUEUE\_FAILED | Worker job could not be queued |
| UPLOAD\_SESSION\_NOT\_FOUND | upload\_id does not exist |
| UPLOAD\_SESSION\_INVALID\_STATUS | Upload session status does not allow requested action |
| UPLOAD\_PROCESSING\_FAILED | Upload worker failed while processing file |
| INVALID\_FILE\_STRUCTURE | Uploaded file structure does not match upload\_type |
| EMPTY\_FILE | Uploaded file has no data rows |
| MISSING\_MANDATORY\_FIELD | Mandatory upload field is missing |
| INVALID\_NUMERIC\_VALUE | Numeric value is invalid |
| NEGATIVE\_STOCK\_OR\_BILLING | stock\_eom or billing\_eom is negative |
| ZERO\_BILLING | billing\_eom is zero where calculation requires division |
| INVALID\_CATEGORY | Trader stock category is invalid |
| GRADE\_MISSING | grade is missing where required |
| REVENUE\_MISSING | revenue is missing |
| GP\_VALUE\_MISSING | gp\_value is missing |
| NO\_REVENUE | revenue is zero |
| NO\_REVENUE\_AFTER\_EXCLUSION | revenue is zero after excluding KW / Special Choice rows |
| CUSTOMER\_ID\_MISSING | Cust ID is missing in Trader GPM upload |
| PRODUCT\_ID\_MISSING | Prod ID is missing in Trader GPM upload |
| INVALID\_PRODUCT\_ID | Prod ID is not a valid UUID |
| PRODUCT\_LOOKUP\_FAILED | Product API lookup failed |
| PRODUCT\_NOT\_FOUND | Product ID was not found in Product API |
| PRODUCT\_INACTIVE | Product is inactive |
| PRODUCT\_CATEGORY\_MISSING | Product API response does not contain category\_label |
| DUPLICATE\_GPM\_NATURAL\_KEY | Duplicate Period \+ Sales ID \+ Cust ID \+ Prod ID found in same GPM upload |
| KW\_SPECIAL\_CHOICE\_FIELD\_PENDING | KW / Special Choice exclusion field is not yet confirmed |
| INVALID\_DOWNLOAD\_TYPE | Download type must be original, success, or reject |
| FILE\_NOT\_FOUND | Requested upload file is not available in S3 |
| SUCCESS\_FILE\_NOT\_AVAILABLE | Success file is not available for this upload |
| REJECT\_FILE\_NOT\_AVAILABLE | Reject file is not available for this upload |
| ROW\_NOT\_ACTIVE | Selected row is not active |
| DELETE\_REASON\_MISSING | delete\_reason is missing |
| TRADER\_DATA\_DELETE\_FAILED | Trader data delete failed |
| UPLOAD\_ACTIVE\_ROWS\_DELETE\_FAILED | Failed to delete active rows for upload\_id |

Negative gp\_value is allowed.

Negative revenue is allowed. If aggregated revenue is negative, calculated GPM percentage should also be negative. Negative GP and negative revenue should not cancel each other out and produce a positive GPM percentage. The negative GPM percentage should go through normal slab lookup. If the calculated GPM percentage does not match any configured slab, points \= 0\. No separate low-end slab is required in Phase 1\.

KW / Special Choice exclusion field is still pending Product confirmation. Until the source field is confirmed, backend should not hardcode this exclusion using grade.

The following old preview/commit errors are no longer required because Trader uploads do not use preview \+ commit flow:

1. UPLOAD\_PREVIEW\_FAILED  
2. UPLOAD\_COMMIT\_FAILED  
3. UPLOAD\_STAGED\_ROWS\_MISSING  
4. UPLOAD\_ALREADY\_COMMITTED  
5. UPLOAD\_COMMIT\_LOCK\_FAILED  
6. STAGED\_ROW\_INVALID  
7. ARTIFACT\_NOT\_FOUND

## **18.4 Calculation Errors**

| Error Code | Meaning |
| ----- | ----- |
| USER\_FETCH\_FAILED | Could not fetch users from Users/Salesperson API |
| HIERARCHY\_FETCH\_FAILED | Could not build hierarchy from Users/Salesperson API |
| PARTICIPANT\_SNAPSHOT\_FAILED | Could not create participant snapshot |
| SALESPERSON\_TYPE\_MISSING | salesperson\_type is missing for participant |
| LEVEL\_MISSING | level could not be resolved for participant |
| ORIGINAL\_ROLE\_MISSING | original\_role is missing from source user data |
| CHANNEL\_MISSING | channel is missing for channel-specific Non-Trader calculation |
| TARGET\_MISSING | Target data is missing |
| ZERO\_TARGET | Target is zero |
| SALES\_DATA\_MISSING | Sales data is missing |
| CUSTOMER\_COUNT\_MISSING | Customer handled count is missing |
| NEW\_TRANSACTED\_CUSTOMER\_DATA\_MISSING | New transacted customer data is missing |
| AGEING\_DATA\_MISSING | AR ageing data is missing |
| TRADER\_STOCK\_DATA\_MISSING | Trader stock data is missing |
| TRADER\_GPM\_DATA\_MISSING | Trader GPM data is missing |
| DAY\_MULTIPLIER\_MISSING | Trader stock day multiplier is missing |
| NO\_TEAM | No eligible active reportees found |
| NO\_SLAB | No active slab config or slab group exists for the participant’s incentive point, salesperson\_type, level, channel, and period. Award 0 points and store the flag. |
| PAYOUT\_ROW\_MISSING | Payout row not found for total\_points and level |
| AGEING\_DEDUCTION\_RESULT\_MISSING | AR ageing deduction result is missing for Non-Trader finalization |
| FINAL\_RESULT\_FAILED | Final result calculation failed |
| INCENTIVE\_POINT\_RESULT\_MISSING | Applicable incentive point result is missing during finalization. Finalizer should not silently treat this as 0\. |

## **18.5 Run Errors**

| Error Code | Meaning |
| ----- | ----- |
| RUN\_IN\_PROGRESS | Another Business 1 run is pending or processing for the same partner and period |
| RUN\_NOT\_FOUND | Calculation run does not exist |
| RUN\_ALREADY\_COMPLETED | Run is already completed |
| RUN\_ALREADY\_FAILED | Run has already failed |
| INVALID\_RUN\_TYPE | run\_type is invalid |
| INVALID\_TRIGGERED\_BY | triggered\_by is invalid |
| MANUAL\_RECALCULATION\_NOT\_ALLOWED | User is not allowed to trigger manual recalculation |
| RESULT\_DEPRECATION\_FAILED | Could not deprecate older result rows |
| QUEUE\_JOB\_CREATION\_FAILED | Could not create calculation queue jobs |
| WORKER\_PROCESSING\_FAILED | Worker failed while processing calculation job |

# **19\. Validation Principles**

Business 1 validation should follow the same overall principles across config APIs, feed APIs, upload APIs, calculation jobs, and result APIs.

Detailed field-level validation is documented in the relevant API sections.

This section only captures common validation rules that apply across multiple flows.

## **19.1 Period Handling**

All monthly inputs should use:

YYYY-MM

Example:

2026-06

Backend should convert this into date boundaries where required.

Example:

valid\_from \= 2026-06-01  
valid\_to \= 2026-06-30

For tables that store month and year separately:

period\_month \= 6  
period\_year \= 2026

Manual calculation APIs should not allow users to freely pass historical periods unless explicitly supported later.

## **19.2 Config Edit Rules**

Business 1 should follow the same config edit principles as Business 2\.

Case 1:

Future config  
Full edit allowed.

Case 2:

Config has already started but has not ended  
Only valid\_to can be edited.

Case 3:

Past config  
Edit not allowed for normal users.

Config changes should be rejected when a Business 1 calculation run is pending or processing for the same partner and impacted period.

Business 1 does not block config changes just because CRON or CATCHUP\_CRON has completed.

Config changes do not automatically trigger recalculation. Updated config applies when the next MANUAL, CRON, or CATCHUP\_CRON run is executed.

## **19.3 Run-In-Progress Validation**

Business 1 does not use Open / Grace / Locked cycle states.

Mutating actions are generally rejected when a Business 1 calculation run is pending or processing for the same partner and period. Customer Handled refresh and New Customer Monthly replacement have an additional finality rule and are also rejected after a successful CATCHUP\_CRON run for the same partner and period.

This applies to:

1. config changes  
2. Customer Handled refresh  
3. New Customer Monthly ingestion or replacement  
4. AR Ageing feed replacement  
5. Trader upload  
6. Trader selected-row deletion  
7. Trader upload-level active-row deletion  
8. manual recalculation

This does not apply to read-only actions such as:

1. result view  
2. run history view  
3. feed status view  
4. Trader upload history view  
5. file download

CRON completion does not globally lock the period.

Successful CATCHUP\_CRON completion does not globally lock the period. It specifically closes Customer Handled refresh and New Customer Monthly replacement for the partner and period.

MANUAL can run after CATCHUP\_CRON using the customer inputs already finalized for the period, subject to run-in-progress and input-processing validation.

## **19.4 No Matching Slab**

If achievement value does not match any configured slab:

points \= 0

This is expected behavior and should not fail the calculation.

Admin does not need to configure every possible value if unmatched values should receive 0 points.

## **19.5 Missing Required Config**

Missing required config should not silently default.

Examples:

1. missing payout config  
2. missing AR ageing deduction config  
3. missing Trader stock day multiplier config

Missing active slab config or slab group is handled as NO\_SLAB: points \= 0 and the flag is stored. A configured slab group with no matching row also returns points \= 0 and matched\_slab\_id \= null. These are not config gate failures.

For the required configs listed above, the engine should fail the relevant config gate or participant calculation and store the error.

## **19.6 Precision and Rounding Rules**

Business 1 calculations should use Decimal / NUMERIC arithmetic. Floating-point arithmetic should not be used for incentive calculations.

Aggregation rule:

1\. Aggregate raw values first.  
2\. Calculate percentages after aggregation.  
3\. Do not average row-level percentages.

Percentage precision:

1\. Achievement percentages should be rounded to 4 decimal places.  
2\. GPM percentages should be rounded to 4 decimal places.  
3\. AR ageing bucket percentages are not calculated. AR ageing stores bucket amounts and selected final\_bucket\_code. deduction\_percentage is read from config, and deduction\_amount is rounded to 2 decimal places.  
4\. Slab lookup should use the rounded 4-decimal value.

Monetary precision:

1\. Gross incentive, deduction amount, and net incentive should be rounded to 2 decimal places.  
2\. Points remain integers.

Rounding mode:

Use standard half-up rounding unless the existing backend numeric utility defines a different shared rounding convention.

## **19.7 Calculation Defaults**

The calculation should use consistent fallback behavior.

| Scenario | Treatment |
| ----- | ----- |
| target is missing | points \= 0 |
| target \= 0 | points \= 0 |
| sales data is missing | treat actual as 0 |
| no matching slab | points \= 0 |
| total\_overdue \= 0 | deduction \= 0 |
| all AR overdue bucket amounts are 0 | deduction \= 0 |
| Trader participant | deduction \= 0 |
| inactive participant | do not calculate final incentive |

Missing required config is not part of this defaulting rule.

## **19.8 Auditability and Deprecation**

Every calculation output should be traceable using:

1. run\_id  
2. participant\_snapshot\_id  
3. incentive\_point\_code  
4. matched\_slab\_id  
5. payout\_row\_id  
6. calculation\_details

Recalculation should not physically delete old results.

> payout\_row\_id is null for participants with total\_points \= 0 — this is expected, not a missing-audit-trail gap. Gross incentive of 0 is applied directly by rule, not by table lookup.

Instead:

1. Recalculation should follow the publication and deprecation rules defined in Section 8.8. Previous current rows should not be deprecated until the new run output is ready to publish.  
2. keep older rows for audit/debugging

Default result APIs should return only:

| Field | Required value |
| ----- | ----- |
| publication\_status | published |
| is\_deprecated | false |

Run-specific audit/debug APIs may return draft or deprecated rows when run\_id is provided.

## **19.9 Ordered Slab Lookup**

Business 1 slabs use ordered threshold lookup.

A slab row is evaluated using operator \+ value.

More than one row may match the same achievement value.

When multiple rows match, the selected row is determined as:

1. highest points  
2. then lowest band\_order  
3. then earliest created row/id

If no row matches, points \= 0.

Overlapping threshold conditions are allowed and should not be rejected by validation.

Validation should reject duplicate operator \+ value rows and duplicate band\_order within the same channel \+ salesperson\_type \+ level group.

#   **20\. Pending Decisions / Open Questions**

The following items are still pending.

## **20.1 Zero New Customer Month Delivery**

“The remaining open question is how the source system will explicitly finalize an incentive month containing zero new customers.

The current new-customer-monthly endpoint rejects an empty or header-only CSV. Product confirmation is required on whether a zero-customer month will be represented by:

* a header-only CSV containing explicit period information; or  
* a separate zero-record month-finalization request.

This decision does not block implementation of non-empty monthly ingestion, validation, replacement, snapshot storage, or Business 1 calculation.”

## **20.2 Trader GPM KW / Special Choice Exclusion Field**

Pending confirmation from Product/Japfa team:

1. Which Product API field identifies KW / Special Choice products.  
2. Whether Product API will add a new field for KW / Special Choice.  
3. Final values that should be excluded.  
4. Whether KW / Special Choice exclusion applies to both GPM by Product and GPM All Product.

Until confirmed, implementation should not hardcode KW / Special Choice exclusion using grade.

# **21\. BullMQ Processing / Calculation Orchestration**

Detailed BullMQ processing and CRON orchestration will be maintained separately in the BullMQ design section / Tab 2\.

This section only captures the high-level relationship with the Business 1 tech spec.

Business 1 calculation is asynchronous.

Trader upload API stores the original CSV file in S3 and enqueues a Trader upload worker job. The worker reads the file from S3, validates rows, enriches GPM rows through Product Submissions API, writes valid rows into Trader activity tables, stores rejected rows in incentive\_upload\_errors, generates success/reject CSV files, uploads those files to S3, and updates incentive\_upload\_sessions.

APIs and CRON should create run records and enqueue calculation jobs. Actual worker sequencing, queue design, retry behavior, DLQ handling, and job dependency flow will be covered separately.

High-level principles:

1. One calculation run should have one run\_id.  
2. Business 1 should use incentive\_run\_log for run tracking.  
3. Business 1 should use run\_type to identify CRON, CATCHUP\_CRON, and MANUAL runs.  
4. Participant snapshot should be created at the start of the run.  
5. Calculation jobs should use the same participant snapshot for the run.  
6. Result rows should be linked to run\_id.  
7. Run-in-progress checks should be derived from incentive\_run\_log.  
8. Failed participant-level calculations should be captured in incentive\_run\_errors.  
9. Older result rows should be deprecated during successful recalculation, not physically deleted.  
10. Business 1 does not use Open / Grace / Locked cycle state, and no run type locks the period.

Detailed items to be covered in Tab 2:

1. CRON and CATCHUP\_CRON schedule  
2. Queue list  
3. Job payloads  
4. Worker sequencing  
5. Dependency ordering  
6. Retry policy  
7. DLQ handling  
8. Partial failure behavior  
9. Manual recalculation job flow  
10. Result deprecation timing  
11. Observability and logs  
12. Trader upload queue  
13. Trader upload worker payload  
14. Trader upload worker retry behavior  
15. Trader upload Product API retry behavior  
16. Trader upload success/reject file generation  
17. Trader upload row-level partial success behavior

Calculation run creation should perform a partner-period preflight check.

A CRON, CATCHUP\_CRON, or MANUAL run should not start if any relevant input process is still queued or processing for the same partner and period.

This includes:

1\. AR Ageing feed ingestion  
2\. Trader Stock upload processing  
3\. Trader GPM upload processing  
4\. Customer Management refresh if implemented asynchronously

Input/feed/upload activation should also re-check that no Business 1 run is pending or processing before activating rows.

Run creation, input activation, config mutation, Trader deletion, and result publication must perform their run-in-progress validation and state transition atomically for the same partner and period.

---

# **22\. Summary**

Business 1 should be implemented as a point-based incentive engine.

Core flow:

Incentive point achievement  
→ Point slab lookup  
→ Points  
→ Total points  
→ Payout table lookup  
→ Gross incentive  
→ AR ageing deduction for Non-Trader  
→ Net incentive

Key implementation decisions:

1. Business 1 uses salesperson\_type (Non-Trader / Trader) and level (1=Sales, 2=SPV/KAO, 3=RSO) together to identify participants.  
2. Business 1 uses level for calculation logic.  
3. original\_role is stored for audit and reporting.  
4. KAO is treated as Level 2\.  
5. Incentive point configuration is stored using incentive point terminology.  
6. Point slabs store level-wise points directly.  
7. Payout config maps total points to gross incentive.  
8. AR ageing deduction uses the highest non-zero overdue-day window and configured deduction\_percentage.  
9. Trader stock and GPM files are uploaded through Trader upload API as CSV files. The API stores the original file in S3 under incentive/trader-uploads, queues asynchronous worker processing, and the worker generates success/reject CSV files in S3. Product category for Trader GPM is resolved using Product API category\_label.  
10. Business 1 uses separate result tables because the calculation model is different from Business 2\.  
11. Common run/logging tables should be reused where feasible.  
12. Run history and run-in-progress checks are derived from incentive\_run\_log.  
13. CRON, CATCHUP\_CRON, and MANUAL are the supported Business 1 run types.  
14. CATCHUP\_CRON does not lock the period.  
15. Successful CATCHUP\_CRON completion specifically finalizes Customer Handled and New Customer Monthly inputs and prevents further replacement of those two inputs for the period.  
16. Manual recalculation can run after CATCHUP\_CRON, subject to run-in-progress validation.  
17. Customer Handled is pulled from the ws2closio Customer Handled API. New Transacted Customer data is pushed through POST /api/target/v1/webhooks/new-customer-monthly. Both are stored as replaceable active monthly snapshots, and neither customer flow uses S3.  
18. AR Ageing is push-based feed ingestion. The original AR Ageing CSV is stored in S3, processed asynchronously, and replaces previous active AR Ageing rows through soft replacement.  
19. Input replacement uses soft replacement: previous active rows are marked replaced/inactive, and latest rows are inserted fresh.  
20. Detailed BullMQ orchestration is maintained separately in the BullMQ design section / Tab 2\.

Business 1 should remain auditable through:

1. participant snapshot  
2. incentive point results  
3. AR ageing deduction results  
4. final result snapshot  
5. run logs and run errors

[image1]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAloAAAB9CAYAAAB6bc1NAAAb/0lEQVR4Xu3d95cUVd7H8f0n9uw5C0Mawg7CjICwohgGFFGiAXxWQJFVsmBE5VFA5GBGwADqIgiCiJIEdYkCuyI5ZyRKHFh9/oN6/F72Fre+tzrNVA8zw/uH1+mqm6q6q6b7M1XVXX/44x//GAAAACB5f9AFAAAASAZBCwAAIE8IWgAAAHmSMWgVFhYGxcXFQYsWLQAAAK55koskH+nMFCc2aP35z38OGjdubB4BAAAQz+YlnaXSBi1CFgAAQHYkN/3pT3/y8lRs0CooKPAGAAAAQGpySlFnqtigJQ11ZwAAAKSnM1Vs0OK0IQAAQO50pooNWroTAAAAMtOZiqAFAACQEJ2pCFoAAAAJ0ZmKoAUAAJAQnakIWgAAAAnRmYqgBQAAkBCdqQhaAAAACdGZiqAFAACQEJ2pCFoAAAAJ0ZmKoAUAAJAQnakqLWjVrVs3aNr0Oq/8aqgq6wEAAGoWnakSCVoHDx8NLl76v9DRYye9Nr179zF1uvxqqCrrUVPp13fgwMFBQUEdr51WUnK9ofsDAFBd6EyVWNB64cVR4fyevQeCnzZu8drh2qCD0r79h7w26ej+AABUFzpT5SVotWzZMvywvOeezpGjXW6/EydPh+WnTp8zj1u27gjr3X6zZs+JlHfocEdYt2vPvsi4p89cCOvatm0bli9d9l3sesQt765OnSLl0z+dGdaNfeVVry+ukNeotLR9ZN5OF5eURF5n3Ve3T1XmztujpVazZs28/gAAVAadqfIStIT+YCxq2tQrs/Nyaql+/fqRMmk/eMjQsO35C5eC0vaXP7ylzfKVq71xhISgDT9tiq1LVzZ58ntBUVGRma5Xr16kjUz/7aHeZrpx48ax/XHFwkVLgsVLlpnpgoKCyOsl27Fbt+5mukGDBt5+I+JeX12mt4+ddkM+AACVTWeqKhG07AevWzbx3cnBffc/EJIjXV/Mmx+2cY9UlV36LZyWQCT1cpTDXVbccl0XLv7qtbnttttj2+t5RLVrd0v4Go0eMzZYvWad10Ze20GDBgcbN2316uJeX11m5+32dvcV3RYAgMqiM1VegtZNN93kfdjlGrQ+/mS6txy3TYsWLcN5HZKsR/o96i3T9s9UJvOdO3dJWaf7I0peo0aNGplH90J4mX/s8QHh/KbN22L7Ziqz83I09MDBI157AACuBp2p8hK05Nor99SeyDVo3dyuXXDDDTeE5fO/WhCMe3V82CZV0Dpztizo2/dhbzxXXNmcufNSttHt9Tx869b/GEyaPCXyWtWuXTsy37Fjx6yD1uzZc8NpOeWYbvu41/kBAFCZdKZKLGjJh521fcfusE5fDC/sEQ37ARkXtOz0zl17TZDS5amC1u23327qD/2+Tnv3HQyvFRLuxfCWrbPj/rhho3l8Z+Kk2HWKm4eve/ce5nXatTv6RYWz58rMqV7ZZ3bs3GPajB07ztTpbeO+zrVq1TLzGzZuNo89etwb1kkIk7JVq9eax+UrVnnrAwBAZdCZKpGglU9ycXNhw4ZeeSZyNEwuXNflmXS86y6vDMlq3rx5UKdO5t/ViiNHwXSZdffd93hlAABUJp2pqnzQAgAAqC50piJoAQAAJERnKoIWAABAQnSmImgBAAAkRGcqghYAAEBCdKYiaAEAACREZyqCFgAAQEJ0piJoAQAAJERnKoIWAABAQnSmImjlQG7vUtq+vVdu3dWpEzc4zqC4uDi48ca2Rt26db366kyeU0W2/79/3BgcO/GLV15VyHOzdF155WPMbMkya9o+CODq05mqSgetnj17BecvXPLKr5ZMQatL127cBzEDe19CS248rduUh4zVuXMXr7wyyY3QK7L9q3rQKim53qjIc9QqMmZ5+uj+BC0ASdOZiqCVIIJWZhK0Fi5aEs4n9XrVhKBVXeTjOZZnzPL00f0JWgCSpjNVIkHr8zlfBMtXrg5eenl00KdPX/MGNuW9D0ydvJHJ/MCBg4Nxr44Ptu/YHekrdW++9Xbw2utvBk88MSJo3aaNKZeQNe/Lr0y9lIt77ukc9jny8/Hg7489Hox8/oXIG+7fHupt5h/6/XH48BHBTxu3eMuTUwbPPjfSjKmfSxy7/Lg39vNl/wm2btsZ3HlnR1Mf1wZXpAtaUi77x4gnnzLlt9xya6TvqFEveduutLQ03Dafzvgs3Fbu+KfPXDD7jkz36HFvWLdv/6Hgh7Xrg0cf7W/q3BtW2/1y+YpV3pip2KC1eMmycL+8oXXryJhdu3ULXh49xkzXqlXLlPfq9aAZX9bz6wWLImMePHw0WLR4afDU08+Y9Tx1+lykXsZ59tmR5vHM2bKs1vPdSVPMfvtAz57mObrb4OjxU8F3368I2rfvEOzasy8oKCjw+sft430ffiSY+8WXQadOd5u/B1lvKZfnqNvr+XRlH38yPfjgw2mR+mbNmoXb3G4b+7zr169/+TX5fR+R9xC3n9x0XOZl/5LtLtMELQBJ05kqsaDlvqG5R3bkg+amm28O6/Qbqsx/OHWaN6ZIdURL+kjIihuz7NJv5gMvri5uPhdxfd0yCZJxbXCFPnU4evTYsK5Ll67htISmeV9+Hemb7rWVurgjWm6fhYu+CZZ9+31snYSdn4+eiNSl2i9T0Ue0vv1ueTDzs9lmunfvPmH4EPJBL2HA7T95yvuxQWv69BnhvDv+oEGDgwOHfjbTbdu2Tfv6uHQ7+w+McLeBhCS9jnH948rsOBUJWu66SL2E6kx95FS0vB/Z+YYNG4X9VqxcY4Kb25+gBSBpOlMlFrR279kfzst/we6b4ITX3gjOnb9oyvSbo8y7wciVLmi1aNEynL9w8ddInWaPHNh6PV624vq6ZZw6zEyClhz9bNKkiVcnlnyzLNxumzZvi9TJPqTbW9I+U9Aa+8qrwarVa810mzZ/9fYTt61Mp9ovU9FBa8KE180RMZmeMXOWtyxbZ6UKWkOGDgvn3fHtUVSZHjx4SHDy1JlI31TcMbTCwsJg9Zp14Tq+/8FUr01c/7gyUZGgJUe3t2zdEa5Lv379M/bZs/dA5DUW48dPCOv0a0nQApA0nakSC1ryJmbn3aAl/0Vu3rI9rNNvjjIv/43rMUV5g5Zur/vqsmzF9XXL5LRQXBtcoU8duuS1e+zxAWb6q68XekFLTq3pPm7fXIJWy5Yt026rdPtlKumClhxJkeeu+7hyDVp23sp2ffUYus49knS1glZhw4amTL7JaeuzCVpy6lkuGdDlgqAFoDLoTJVY0HLf9OR6EvuhKOWlpVe+qaffHNN9QMj1Hrq97ZMqaMmplAEDB4Xz8h+x7qvHy1ZcXymzR8w+m/V5bBtckSpo1a5dO/LaybQOWnLtk+5nybVLcu2NLnfHdIOWrpPrldzlpdsvU9FBa+++g2aZts7dT+d/tcCcanb75xq05PSjrKNcl+T2yUTGaNWqVThvn7f8PIk7vpw2zDZoHT12MpyW9XH/7tz2DRo0iO2vy+R6z8NHjplpG9ayCVqyD7j/2BWXlJjTwjItp2DlaJ3bn6AFIGk6UyUWtOQ/djl6JW9ecmrIrT/0+4eFlE+d+pF3UXmmD7Rhw4abD1Fpt3HT1rBPqqAl5EiClEk7fTFv3JtzJtJHs3XyRi0fCLasPONfS1IFLXHfffeb18/Wr1v/YzB27LiwftbsOV4fl4QXvX3caR20xD+XrzRt5sydFymXsnT7ZRwJUytX/WD2P+kvp8zdermIW8pl35QL22350mXfefuXXFAudRK03H8c3OcjXxbQ/YqKirz1iiOvpbQ/e64scopUvnAg5fIPS7169cwRInuESy/LXRchge3yukf/uRFSJnX6dKkeb9pHn4R1cp2elD038nnzd2yDl3X99S2CHTv3eOsiX2qQ4CdlentPnfaxKX/66Wf5HS0AeaEzVaJBS5cDyB8ddL6cv8CEU90OAFB5dKYiaAHVlASt5s2bh/O7du8zP4Wg2wEAKo/OVASt/9KnMIT+zS+gKpGfjJBfkpd9Vb40Ut3/BgGgJtCZKpGgBQAAAIIWAABA3uhMRdACAABIiM5UBC0AAICE6ExF0AIAAEiIzlQELQAAgIToTEXQQrUkP2lQWb/qneq2MQAAaDpTJRK0ln37ffjbU3IzYF2fNPe3rtq37+DVo+rbf+BwsHDRN155Nu5/oGdOwefEydOm/T+mz/DqsiG31cl0Q2irqGnToOzSb2Z5N7Ru7dUDAGo2nakSCVqW3BS3MoKWRdCqfjp0uCMMyeUNWufOXwwee3yAVx5HltP34UfM9PETp4O333nXa5OJjGFvHJ6JtJUbNjdp0iSnMAgAqBl0pqqUoCWnXiZNnhIsWrw0Uv7Rx/8ICgrqhPNyE18ps/Ndu3ULvvt+RfDGm295N4cWBK3qR7aZHPWR7VyeoCWBJ9sAU7t27eDDqVduSdO6TRtztEm3S0du6Cw3XtblqQwf8WQ4LetZWac3AQBVg85UeQ9a9evXNx84zz43MujZs1fkg27ND+uCGTNnhfNyr7bhw0eE8+fL/mPC1sujx8QeVSBoVV/lDVqzP58bLF+52ivPxsOP9AuO/HzcK09H9rH77rvfK8/kwQf/x9wWR5cDAGo2nanyHrTkSJbcC9HOX7j4a1BaWmqmi4qKIkcn3Gm5j5s7zg9r15uw5pYRtKqv8gYt2eZyhFSXZ0P6FhYWeuWp1KtXL+ujZ66t23eaftme3gQA1Bw6U+U9aO3Ze8B86Hyz9NvQwIGDw/qDh4+ao1ifzfo8cv2MHOly+4h3Jk6KjE3Qqr7KE7RkH1m9Zp1Xno3yBCY5+ipHYXV5tkaPHhssXfadVw4AqLl0psp70JKjWVPe+8Bra5W2bx9+S8stH/HkU15bjaBVfZUnaOV6RMrtJ99U1OXp1KlTx9snM5k67eNg0KAr/0Q888xzwYafNnntAAA1l85UiQYtCVRfL1gUKZOvuMsHVuPGjc28TOsLhKVMvkmmx9u6bad5tN/gklCm+8m32HQ/VF3FxcVBy5YtzRHKnzZuMdO6TSq5Bh/bZ8jQYWY5lm4TR36yZP5XC7zydIpLSszyrruuWdC06XVmunPnLl47AEDNpTNVIkHL/R0ty4Yk0bFjx+DosZOXw9J/r89yLVi4OOjb92GvfPqnM00fua7r0Uf7h+V6WeX5AMbVsf5fG8q17f7yl78Ew4YN98rTkX1GLyvb5Uk7+daiLs+ktLS9+d0u+SmJ7t17ePUAgJpNZ6pEghaQbxs2bvbK8km+8arLAADIRGcqghYAAEBCdKYiaAEAACREZyqCFgAAQEJ0piJoAQAAJERnKoIWAABAQnSmImgBAAAkRGcqghYAAEBCdKYiaAEAACREZyqCVg7ktioFBQVeOYCKkb8tXQYA1ZHOVIkGrTZt/uqVZSPXfu7tVCrzptKyPH2/xUyKmjb1yq51cjPpXG6HI85fuJRzn0zsePpG6NnIdZ/V5LZSD/TM7kbXtWrVKtfyrr++hbl1kS5PJ9dbFSWlPMsrz2sCAPmmM1WiQas8b5YV7VeZQas83nzrba/sWibbrH//v0fmdZt0cm2fjfIErYquRy5Bq379+uVa3pof1gVjxrzilWejPMurbNVhHQFce3SmSiRouf8Fu2z99/9cGZY99fQzYfmp0+e8Po/0ezR23B497o1dbi5B6+Dho0FxcXE45vMvvOiNZ93VqVNsuR5TyoYOeyKsr1u3bmw/3X/y5Pci5Q0bNvLGron0a9iu3S3h6djikpLw9Tj1y1mvb1x/cXO7dpHXsl+/6A3I7fTgIUODXXv2ef3jgtah3/cVO97W7TvD8kz77NtvTwzLZ82eEzumHJ3LNmjpZbnPR+w/cDgsT7XPWtdd18zU3XNP50i5HPmKW64uS0fay8207ZhdunYL63r37hNZXrNml9fD9rPixrQ3lnfr5Sb1bj9d777flF36zRsXAPJJZ6pEgpYV92bZp0/f4OSpM5E2ciokUz95M+7WrbuZbtCgQWwbKcs1aMmHnUzLKRV3TAk+RUVFZrpevXoplxdX9s7ESWZ69Zp1wYqVayL1qY5ouWNJ4Nu3/5DXpiaKew0tCSB2m8uH9gsvjvLaxPWXsiZNmphpva+407kEraPHTkbG6NDhjkh93HrIaWK3XJ6PPdXcs2cvb72yCVoi1REt2Wc3btpqpuP22VRHtKSd3de7dOnq9bNtdFk60r5OnTpmWv4m9XO1f/M3tG4dO3aqsr891NtMnz1XFkx47Q2vXvfRr1XctgWAfNKZKu9Ba/2/NgQvvvi/4fymzduCZ555LmM/67bbbg8GDRoc20bKcg1a7hE19wNAjjDosWXZukyP6ZZJSNBt0gWtDz6cFhQWFnp1NZl+feJIKDlw8EgYItL1l6M0uixV+1yClpDQJh/0Msb7H0xNOa418d3JwS9nzgf33f+AsWXrjuCLefNN3YyZs4I5c+dF+lc0aMk+e8cdd0bGdPfZVEHLkiND9misrosrS0e3t/Py+klojqvLpWzcq+ODVavXpqzX5S+PHsMXVwBcFTpT5T1o7dl7IBgydFg4v3zl6mD8+AkZ+zVu3NiU/7hhY/DxJ9Nj20hZrkHLXRfpb4OWHl/m9elK3UaXyekS3SZV0CooqGNOLUl7MWDgIK9NTaRfH9e8L78y9QsWLjaPEsp1G93fnjbU7eLa5xK0pN+xE7+E65RN0JIwJeXfLP02ZI92St2nMz6L9K9o0JKy1m3aRObdfTZV0JIAK20luEjYTzW2LktHt7fz8ve2e8/+2Lpcysa+8mrWQUvC96LFS019qjYAkC86U+U9aD351NPmP3u3jb4eKa6fXAtjp+01GbqNlOUatNxx3Gn3aIOuy7YsLmjJf9a1a9f2+smRj1Tj1GTyPEc+/0JkXh7lNdLbJpugFVem9zd7ZGPZt98Hr73+ptdfBy251qm09Mq3S2WMuKClt6uEPvfI6PyvFpgjMTI9ePCQ4PSZC5H+2QYtWX/9HIXss3INkzumW7/km2XB53O+8Pq57Z59bqTXT7fJhtten8Z0p/V2jmsTV5Zt0JJ/bOSfMzsv12TK+4duBwD5ojNVokFr56695s3PsuVyjZZclHr4yLFg+YpVXr/FS5aFfd57/0NT1qvXg6aPhKMdO/cEBw79HI7pLkMvKx0Za/bnc80bsfSRa6rceimzdfZIRKbludNxQUuOXMX1k6Bl10EeX3/jrUi/mkpOlbqvx7Bhw8M6uQ5HtrmUt2rVyjyOHTvO1Lk/76Bfy1GjXjLzdtvJ/mTrHh8wMFLnroseb+u2nZG6H9auN49ynZXuG7fPip82bjFlErh0H5nfvGW7eZT9MNugJSSk2eXZi9rtmPK6yaO7z4oWLVpGnp+9aF+mz5wtM184WLhoiZmXa7VsnabXJY5tu2HjZvPoBlMJhG5d34cf8fpZehvY6bigler9RqbPl/0ndpsDQL7pTJVo0EpH/iuP+3ZTOs2bNw8vsE2CBC05RVdScr13NMLqeNddXlm+yGuSyxG5mkTCghz50OWyzXVZtjp1utsrs9xv5GXrlltu9cqyVdiwoVcmcv0dtmzItWS6LJMbb2zrlVWEDTTpXrM776y8I0sS6Nu2TfY5AkA2dKaqtKBVFdigpcsBVAxHjgDgMp2palzQOnr8lGfKlPdNHUELyA+CFgBcpjNVjQtacqG9Zk9RyekcuWZK9wFQMfoLLgBwrdKZqsYFLQAAgKtFZyqCFgAAQEJ0piJoAQAAJERnKoIWAABAQnSmImgBAAAkRGcqghYAAEBCdKaq8kFLfp/ny/kLvPJsHTh4xCvD1Se/4p7Lr5PLzcllWya5Pe1406fP8OoqokmTJhXaZ6sqea2KS0q8cgDAFTpT1figxQ8pVi1yix3ZJvbefW+8md09HuUDXm6dlOT2lPGEvql0NtKtR3UPWnJjZrkBty6X5yz3T9TlAIArdKaq8kGrotJ9IKLyyfbo3//vkXndJp1c22cj6aBV3RG0AKD8dKZKJGh9PueLoGfPXuaN2HJ/gf37f64My596+plIX/uBZesf6fdopE688OIob5nusmbNnhOWN2rUKFJnx0fVoLdHu3a3mJtry7QctbLb7NQvZ72+cf3Fze3aRbZ3v379Y9sPHjI02LVnn9c/LmgdOnw0HG/r9p1h+anT57z9K9t99u23J4b17j4rt4YqLi4O686cLfP6akVFRcEPa9d76zL905neugj3ptoyP3TYE2Hd4iXLYvtYbl3v3n3C8pYtCV0AoOlMlVjQct+Qu3TtFs5PmjzF1Nu6Cxd/DUpLS8N5affh1GnemNaGjZu9Dy13WWLtun9H6tz/unVbXF3ptkeXLl3D6U9nfBbM+/Jrr01cf13mjuPW5RK0brr55nB61+59wbPPjYzU62Vqep+VgCLhzc7LPmvHlKDlXid2/MTpYMyYV7wxXRK07DqMe3V8WG7L/v3jxkh7Ka9Vq1Y4LadMdR8r3RGtQYMGm+mOHTt6/QAAeQxau/fsD+flCIV9E5aLmGXaNX78hLCtzMsRCT2mlU3QmjDh9ZR1eh5XV6btseSbZeF+smnzNq9e97dHs3S7uPa5BK0Jr70RnDt/MVyX9z+YmnLcOHqfnTFzlgmP4fi/77PLV6wy0xK0hgwdFtZ9+93y4PU30l+7lilo6fWT+R497k1Z586nC1r8EwMA6elMlVjQkkBl592gtX3H7mD48BFeH0vatW2b+ttn2QQt94JqXafncXXp7fHQQ72DOnUun2aWusceH2CmJfxkE7TatPmrV5aqfS5Ba/OW7ZExKhq0Pv5kejB79txwXvZZG2YqK2h17twlZZ07T9ACgPLTmSqxoOW+6cp1WPKtMpke8eRTkQ8tOaXRq9eD4bz0K0/Qkg9YO3/0+KlInR5fj4mrR7bHyOdfiMzLY+3atSPbSqazCVpxZVu27ojU2WvAJDy89vqbXn8dtOR6ptLS9pEx4oKWrLMey9L7rFyLJqfN7bzss3Jdo0znI2jNmTsv0l6/tqnqxMujx8T+jIa0I2gBQHo6UyUWtOTDoezSb8GRn4+bN+Bbb70trD9x8rT5kJGjWzaAWdI2VdCSOte0jz4x5fbC4b37DppH90Ohe/cepmzf/kNhPz0urp7CwsLINh02bHhYd/ZcmdmHpLxVq1bmcezYcabu/IVL3v5g+40a9ZKZ/3HDRvPoXtz9+ICBkTp3XfR4W7ftjNTZi81L27f3+soybL/33v8w5Zh2nxXyD0fcPitBa8DAQeF8EkHLTtvn/c7ESbFt4ubliyzuc3DbEbQAID2dqRILWnJqRJcDAABcS3SmImgBAAAkRGcqghYAAEBCdKZKJGgBAACAoAUAAJA3OlMRtAAAABKiMxVBCwAAICE6UxG0AAAAEqIzFUELAAAgITpTEbQAAAASojMVQQsAACAhOlPFBq169ep5HQEAAJCezlSxQatZs2ZeRwAAAKSnM1Vs0GratKnXEQAAAKk1btzYC1mxQUvozgAAAEitSZMmXp5KGbSKi4u9AQAAAOCT3KSzVNqgZclpRDkUxgXyAAAAl0kukmvaJSfp7KSlDVoAAAAoP4IWAABAnhC0AAAA8oSgBQAAkCf/D8vzKm0vtbvBAAAAAElFTkSuQmCC>