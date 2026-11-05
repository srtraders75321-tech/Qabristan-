# Financial Reports and Ledger Reconciliation: Requirements

Status: **requirements draft for committee review. Nothing here is built.** Items marked **Proposed** are suggestions; items marked **Open** need a committee decision and must not be assumed. Source of confirmed facts: `PROJECT_CONTEXT.md` (sections 4, 6, 7, 9, 14).

## 1. Goals

1. Give authorised committee members accurate, explainable financial and burial summaries.
2. Prove, on a schedule and on demand, that stored data is internally consistent: balances, receipts, verification, reversals, and audit history all agree with the ledger.
3. Make every figure traceable to the underlying ledger entries, with no figure that cannot be reproduced.

Scale: about 250-300 people initially, designed to grow to thousands of families and years of history. Reports must stay correct and responsive at that size.

## 2. Principles

- **Derived, never typed.** All totals come from `ledger_entry` (and related append-only tables). No report stores an editable total.
- **Reproducible.** A report states its parameters (period, as-of date, rule version) so re-running gives the same numbers.
- **Burial eligibility is never reported as derived from balance.** Burial reports are separate from payment-status reports.
- **Read-only and audited.** Reports do not change data. Exporting personal or financial data is logged.
- **Least data.** Reports show only fields the viewer's role may see (RLS applies).

## 3. Data available today (from the built backend)

`ledger_entry` (signed integer paisa; reversals are negative rows pointing at originals), `ledger_verification`, `receipt` (sequential per year), `rule_set` (versioned), `family`, `family_member` (history), `person`, `burial_record`, `burial_approval`, `burial_payment`, `audit_log`, `committee_user`, `role_grant`. Functions: `family_balance` (months due, months covered, balance, status).

## 4. Report requirements

Each report needs: parameters, definition of every column, role access, export format, and a worked fictional example agreed with the Treasurer. Candidate list (**Proposed**; committee to confirm which are needed):

| ID | Report | Purpose | Key definitions to confirm |
|---|---|---|---|
| R1 | Collections summary by period | Totals by category (membership, donation, non-member burial, other) and payment method | Net of reversals; period by collection date or by contribution period (Open); gross vs net display |
| R2 | Payment register | Every payment with receipt number, collector, verification state | Include reversals as separate rows (Proposed) |
| R3 | Family statement | One family's payments, coverage, balance, and history across transfers | How to present payments made under a former family after a transfer (Open) |
| R4 | Outstanding and advance list | Families in arrears or ahead, by months | Arrears wording depends on **D2** (grace period); until decided, show months only and "rule not configured" |
| R5 | Collector summary | Collected vs verified per collection officer | Depends on **D5** (verification and cash-handover procedure) |
| R6 | Unverified payments | Payments awaiting verification, with age | Same as R5 |
| R7 | Reversals and adjustments | Every reversal with reason and actor | none |
| R8 | Non-member burial payments | Payments linked to burials, with burial numbers | Fee is **D3** (Open); report whatever was recorded |
| R9 | Burial register | Burials by period, kind (member/non-member), approval records count, voided records | No approval-rule status; report records only (**D4**) |
| R10 | Dashboard figures | Registered families, annual collection, pending accounts, burial count, recent payments (PROJECT_CONTEXT 13) | "Pending accounts" definition depends on D2 |
| R11 | Receipt register and gaps | All receipt numbers, flagged if any number is missing | Gap meaning (see 5.4) |
| R12 | Audit extract | Who changed what, filtered by table, actor, date | Access restricted to `audit.read` |

Open for all: currency display (PKR, whole rupees from paisa), calendar (Gregorian assumed; Hijri display is **Open**), year definition (calendar vs committee financial year is **Open**), languages (English and Urdu, RTL, required for every report).

## 5. Ledger reconciliation requirements

Reconciliation is a set of automated checks that read the database and report differences. A check never modifies data. Each check has an ID, a precise query, a severity, and a documented response.

### 5.1 Invariants to verify (**Proposed**; all follow from the built schema)

| ID | Invariant | Severity |
|---|---|---|
| C1 | Every reversal row has a matching original with the exact negated amount, same family, category and period; each original is reversed at most once | Critical |
| C2 | Every positive ledger entry has exactly one receipt; no receipt exists for a reversal | Critical |
| C3 | Receipt numbers are unique per year; report gaps in each year's sequence (a gap is expected only if an insert rolled back; investigate every gap) | High |
| C4 | Every verification points to a positive entry, once, and not to a reversed entry created before it | High |
| C5 | Recomputed coverage for every family (from the ledger, per the active rule) equals what `family_balance` returns | Critical |
| C6 | Membership contribution amounts equal whole months x the rate in effect on the payment date | High |
| C7 | No booked month appears in two non-reversed entries for one family (no double booking) | Critical |
| C8 | `non_member_burial` entries have no family; every one is either linked to a burial or listed as unlinked (**Open**: whether an unlinked one is an error) | Medium |
| C9 | Every `burial_payment` link points to a non-member, non-voided-or-voided burial and a `non_member_burial` entry | High |
| C10 | Sum of ledger by category equals sum of receipts net of reversals | Critical |
| C11 | Audit completeness: every ledger, verification, receipt, rule, burial, approval and link row has a matching `INSERT` audit row with an actor | High |
| C12 | No person is in two families on the same date; every family has at most one open head membership as designed | High |
| C13 | Append-only guards are present and enabled on all protected tables (inspect triggers) | Critical |
| C14 | RLS is enabled on every table in `public`; no table grants write access to `anon` or `authenticated` | Critical |
| C15 | No active staff member lacks a role grant; no revoked grant is still effective | Medium |

### 5.2 Execution

- **Proposed**: run all checks nightly on production and on demand; run on staging before every release; store each run (time, checks, pass/fail, counts, difference details) in an append-only `reconciliation_run` table.
- A failing Critical check alerts the Super Admin and the Treasurer immediately; the run result is visible in the app to authorised roles.
- Checks must be idempotent and complete in minutes at the target scale.
- Results must show the offending record ids, never just a count.

### 5.3 Corrections

Reconciliation never repairs data. A discrepancy is fixed by an authorised reversal/adjustment entry (existing functions) with a reason, and the run is repeated. The fix and the original run result both stay on record.

### 5.4 Open questions for the committee

1. Reporting period: calendar year or financial year? Does a payment belong to the month collected or the months it covers?
2. Which roles read which reports (**D1**)? Who may run or view reconciliation?
3. Cash handover and verification timing (**D5**) affects R5, R6 and whether unverified payments count in totals.
4. Grace-period and arrears wording (**D2**) affects R4 and "pending accounts".
5. Are unlinked `non_member_burial` payments an error or acceptable (C8)?
6. Retention of reconciliation results and exports (**D8**).
7. Export formats needed (on-screen, PDF, spreadsheet) and who may export.
8. Hijri dates required alongside Gregorian?

## 6. Non-functional requirements

- **Security:** report and reconciliation access via permission keys (`report.read`, `reconcile.run`, `reconcile.read` proposed); RLS applies; exports audited; no real data outside production.
- **Performance:** target a few seconds for any report at 5,000 families and 1 million ledger rows; add indexes or materialised summaries only if measured necessary, and verify summaries against recomputation (C5, C10).
- **Correctness:** golden-file tests with hand-calculated fictional data signed off by the Treasurer; property tests (reverse everything -> zero); mutation tests that deliberately corrupt data must make the matching check fail.
- **Localisation:** every label, heading and message in English and Urdu.
- **Retention:** nothing is deleted; reports are regenerated from history.

## 7. Suggested delivery order (when approved)

1. Committee answers 5.4 and confirms the report list (section 4).
2. Reconciliation checks C1-C15 as SQL functions plus tests, including deliberate-corruption tests.
3. Core reports R1, R2, R7, R11 (no open dependency).
4. Reports depending on decisions (R4, R5, R6, R10) once D2/D5 are decided.
5. Burial reports R8, R9.
6. Flutter screens come after the backend reports exist.
