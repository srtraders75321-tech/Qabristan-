# Decision Log

Status values: **Open** (needs the committee or owner), **Assumed** (working assumption, behind configuration), **Resolved**.
Update this file whenever a decision is made. Add the date and who decided.

## Open decisions (from PROJECT_CONTEXT section 16)

| # | Decision | Status | Blocks | Working approach until decided |
|---|---|---|---|---|
| D1 | Final role-based permission matrix | Open | Phase 1 onward | Placeholder roles in one config file; matrix tests are generated from `docs/ROLES_MATRIX.md` once approved |
| D2 | Constitutional payment allowance and grace-period calculation | Open | Phase 3 | `grace_months` read from `rule_set`; default stored as unset and surfaced in the UI as "rule not configured" |
| D3 | Non-member burial charge | Open | Phase 5 | Built: payments accepted in any positive amount, category `non_member_burial` kept separate and linked to the burial; no fee enforced |
| D4 | Burial approval procedure | Open | Phase 5 | Built: append-only approval records (decision, date, approver names, reference); no rule enforced, burial never gated on approval |
| D5 | Financial verification and cash-handover procedure | Open | Phase 3-4 | Separate "collected" and "verified" states recorded as distinct rows |
| D6 | Family transfer approval procedure | Open | Phase 2 | Built: transfers recorded with history and the acting user (audit log). **No requester/approver fields and no approval step exist yet**; add once the procedure is decided |
| D7 | Apple private distribution method | Open | Phase 8 | Android APK first; decide before Phase 8 |
| D8 | Backup retention and operating budget | Open | Phase 8 | Proposed nightly encrypted dump to a second provider; retention to be set |

## New questions raised during planning

| # | Question | Status | Notes |
|---|---|---|---|
| Q1 | Target scale | **Resolved 2026-11-05** | Owner: 250-300 people initially; design for future growth to thousands of families. Planning figure kept at up to 5,000 families / 50,000 individuals |
| Q2 | Payment amounts that are not an exact multiple of PKR 200 | Open | Proposed: reject or record as donation. Needs committee ruling |
| Q3 | Identifier for detecting duplicate persons (CNIC or other) | Open | Collecting national ID numbers raises privacy cost. Default: name + father's name + family, with staff confirmation |
| Q4 | App bundle / application ID and organization name | Open | Needed at `flutter create` time and for Apple enrollment |
| Q5 | Committee branding assets (logo, mosque illustration) | Open | Approved dashboard reference exists but assets are not in the repo |
| Q6 | Should a registered member's burial carry any payment? | Open | Brief defines a payment only for non-members; `record_burial_payment` refuses member burials |
| Q7 | Is a `non_member_burial` payment with no linked burial an error? | Open | Currently allowed (the ledger function accepts it); reconciliation check C8 |
| Q8 | Reporting period: calendar or financial year; Hijri dates? | Open | Needed before reports are built |
| Q9 | Grave reference format and whether a grave may hold several burials | Open | Stored as free text, uniqueness not enforced; nothing invented |

## Resolved / confirmed

| Date | Decision | By |
|---|---|---|
| 2026-11-05 | Family-based membership; PKR 200/month equivalent, PKR 2,400/year per family | Owner brief |
| 2026-11-05 | Installed Android and iOS app required; private distribution preferred | Owner brief |
| 2026-11-05 | Visual theme: Emerald & Ivory, light mode | Owner brief |
| 2026-11-05 | English and Urdu (RTL) required | Owner brief |
| 2026-11-05 | Proposed stack Flutter + Supabase/PostgreSQL + Codemagic for iOS (to be validated) | Owner brief |
| 2026-11-05 | Scale: 250-300 people initially; design for thousands of families (Q1) | Owner |
| 2026-11-05 | Burial eligibility is never derived automatically from financial balance | Owner |
| 2026-11-05 | Permission matrix must remain configurable | Owner |

## Assumptions built into the backend (reversible; none are final)

| Area | Assumption in code | Related |
|---|---|---|
| Permissions | `role_permission` table holds the matrix; the seed file is a placeholder | D1 |
| Grace period | `rule_set.grace_months`; when null, arrears report `rule_not_configured` instead of guessing | D2 |
| Verification | `rule_set.require_verification_for_coverage` defaults to false; collected and verified are separate records | D5 |
| Odd amounts | Membership payments must be an exact multiple of the monthly rate; otherwise rejected, never rounded | Q2 |
| Coverage start | A membership payment starts at the first month not already booked and may not overlap booked months | Proposed |
| Transfers | Recorded with history; no approval step enforced yet | D6 |
| Non-member burial | Accepted as a separate category with any positive amount; no fee is set or enforced | D3 |
| Burial eligibility | Not derived from balance anywhere; a test inspects burial function source for ledger/balance/rule access | PROJECT_CONTEXT 4 |
| Burial membership link | Registered person's family = membership in effect on the date of death (from history); null if none; the burial never changes a membership | Proposed |
| Burial voiding | Mistaken burial records are voided with a reason, never deleted; a linked payment is not auto-reversed | Proposed |
| Burial duplicates | One active burial per registered person (hard); non-member duplicates need explicit confirmation (soft) | Proposed |
| Member burial payments | Refused by `record_burial_payment` | Q6 |
| Burial numbers | Permanent register number, never reused | Proposed |
| Receipt numbering | Sequential per calendar year in Asia/Karachi; never reused; none issued for reversals | Proposed |
| First admin | Created manually by the owner with the service role; app cannot create the first Super Admin | Proposed |

## Phase 0 notes

- Stop hook (run tests before finishing) can now be added: database tests exist (`supabase/tests/run_local.sh`).
- Flutter SDK is not installed in the cloud session. The Flutter project is generated on the developer machine (`app/README.md`).
- The database tests are plain SQL (pgTAP is not available here). They can be ported to pgTAP later if wanted.

## Review log

- **2026-11-05 review.** Unresolved: D1-D8, Q2-Q9. Resolved this review: Q1. Built behind configuration or as records only (not decided): D1, D2, D3, D4, D5, partly D6. D7 and D8 have no code impact yet. Correction made: D6 previously overstated what the transfer function stores.
