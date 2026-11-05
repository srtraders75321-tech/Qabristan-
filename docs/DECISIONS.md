# Decision Log

Status values: **Open** (needs the committee or owner), **Assumed** (working assumption, behind configuration), **Resolved**.
Update this file whenever a decision is made. Add the date and who decided.

## Open decisions (from PROJECT_CONTEXT section 16)

| # | Decision | Status | Blocks | Working approach until decided |
|---|---|---|---|---|
| D1 | Final role-based permission matrix | Open | Phase 1 onward | Placeholder roles in one config file; matrix tests are generated from `docs/ROLES_MATRIX.md` once approved |
| D2 | Constitutional payment allowance and grace-period calculation | Open | Phase 3 | `grace_months` read from `rule_set`; default stored as unset and surfaced in the UI as "rule not configured" |
| D3 | Non-member burial charge | Open | Phase 5 | Fee field behind a feature flag; category `non_member_burial` kept separate |
| D4 | Burial approval procedure | Open | Phase 5 | Record approver fields; no enforced workflow |
| D5 | Financial verification and cash-handover procedure | Open | Phase 3-4 | Separate "collected" and "verified" states recorded as distinct rows |
| D6 | Family transfer approval procedure | Open | Phase 2 | Transfer recorded with requester and approver fields; approval step configurable |
| D7 | Apple private distribution method | Open | Phase 8 | Android APK first; decide before Phase 8 |
| D8 | Backup retention and operating budget | Open | Phase 8 | Proposed nightly encrypted dump to a second provider; retention to be set |

## New questions raised during planning

| # | Question | Status | Notes |
|---|---|---|---|
| Q1 | Target scale: 250-300 people (PROJECT_CONTEXT 9) vs thousands of families (owner, planning) | Open | Plan assumes up to 5,000 families / 50,000 individuals. Confirm before schema freeze |
| Q2 | Payment amounts that are not an exact multiple of PKR 200 | Open | Proposed: reject or record as donation. Needs committee ruling |
| Q3 | Identifier for detecting duplicate persons (CNIC or other) | Open | Collecting national ID numbers raises privacy cost. Default: name + father's name + family, with staff confirmation |
| Q4 | App bundle / application ID and organization name | Open | Needed at `flutter create` time and for Apple enrollment |
| Q5 | Committee branding assets (logo, mosque illustration) | Open | Approved dashboard reference exists but assets are not in the repo |

## Resolved / confirmed

| Date | Decision | By |
|---|---|---|
| 2026-11-05 | Family-based membership; PKR 200/month equivalent, PKR 2,400/year per family | Owner brief |
| 2026-11-05 | Installed Android and iOS app required; private distribution preferred | Owner brief |
| 2026-11-05 | Visual theme: Emerald & Ivory, light mode | Owner brief |
| 2026-11-05 | English and Urdu (RTL) required | Owner brief |
| 2026-11-05 | Proposed stack Flutter + Supabase/PostgreSQL + Codemagic for iOS (to be validated) | Owner brief |

## Phase 0 notes

- Stop hook (run tests before finishing) is deferred until there are tests to run.
- Flutter SDK is not installed in the cloud session. The Flutter project is generated on the developer machine (`app/README.md`).
