# Data Dictionary

Draft. Every field must be listed here before it is added to the database. The aim is to collect only what the committee needs.

Sensitivity levels: **Public** (none stored), **Internal** (committee staff), **Sensitive** (restricted roles), **Financial** (restricted roles, audited).

## Entities (names are proposed)

| Entity | Purpose | Sensitivity | Deletion policy |
|---|---|---|---|
| family | A household and its membership card number | Sensitive | Never deleted; status changes only |
| person | One individual | Sensitive | Never deleted |
| family_member | Person's membership in a family for a date range | Sensitive | Never deleted; `valid_to` closes the row |
| membership_card | Card issued to a family | Internal | Never deleted; replaced by newer card row |
| rule_set | Contribution rates and parameters, versioned | Internal | Never deleted |
| ledger_entry | Money movements | Financial | Append-only |
| receipt | Proof of payment with sequential number | Financial | Append-only |
| burial_record | One burial, linked to family or standalone | Sensitive | Never deleted |
| committee_user / role_grant | Staff accounts and roles | Internal | Deactivated, not deleted |
| audit_log | Record of changes | Internal | Append-only; Super Admin read |

## Field lists

To be completed per entity during Phase 2 and Phase 3, before the migration for that entity is written. Open question Q3 (identity numbers for duplicate detection) must be answered before the `person` field list is final.

## Handling rules

- Fictional data only outside production.
- Export of personal data only through audited functions.
- Fields hidden from roles that do not need them through restricted views.
