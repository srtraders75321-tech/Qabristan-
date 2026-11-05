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
| burial_record | One burial, linked to a registered person's family or standalone (non-member) | Sensitive | Never deleted; voided with a reason |
| committee_user / role_grant | Staff accounts and roles | Internal | Deactivated, not deleted |
| burial_approval | Committee approval/rejection records for a burial | Sensitive | Append-only |
| burial_payment | Link from a non-member burial to its ledger entry | Financial | Append-only |
| audit_log | Record of changes | Internal | Append-only; Super Admin read |

## Burial fields (implemented)

| Field | Meaning | Notes |
|---|---|---|
| burial_no | Permanent register number | Never reused |
| kind | `registered_person` or `non_member` | |
| person_id | Link to the person record | Registered persons only |
| family_id, family_no_at_burial | Membership in effect on the date of death | Snapshot; null if none |
| deceased_name, father_name, date_of_birth, date_of_death | Deceased details | Snapshot; registered persons are changed on the person record |
| burial_date, grave_reference, notes | Burial details | Grave reference is free text (Q9) |
| status, void_reason, voided_by, voided_at | Voiding | Records are never deleted |
| burial_approval: decision, decision_date, approver_names, reference, note, recorded_by | Approval record | No approval rule (D4) |

Not collected: gender, cause of death, national ID numbers (data minimisation; see Q3).

## Field lists

To be completed per entity during Phase 2 and Phase 3, before the migration for that entity is written. Open question Q3 (identity numbers for duplicate detection) must be answered before the `person` field list is final.

## Handling rules

- Fictional data only outside production.
- Export of personal data only through audited functions.
- Fields hidden from roles that do not need them through restricted views.
