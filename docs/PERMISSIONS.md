# Permission Keys

The permission **matrix** (which role holds which key) is undecided (D1) and stored as data in `role_permission`. This file lists only what each key **gates**. `supabase/seed/placeholder_permissions.sql` is a development placeholder, not the committee's decision.

To change who can do what, edit `role_permission` rows (through a reviewed migration or an authorised admin operation). No code change is needed, and the change applies immediately.

| Key | Gates |
|---|---|
| `family.read` | SELECT on `person`, `family`, `family_member` |
| `family.write` | `register_family`, `add_family_member`, `transfer_member` |
| `payment.read` | SELECT on `rule_set`, `ledger_entry`, `ledger_verification`, `receipt`; `family_balance` |
| `payment.record` | `record_payment`; also required by `record_burial_payment` |
| `payment.verify` | `verify_payment` |
| `payment.reverse` | `reverse_payment` |
| `rule.manage` | `create_rule_set` |
| `role.manage` | `create_committee_user`, `grant_role`, `revoke_role`; reading staff, grants, and the matrix |
| `audit.read` | SELECT on `audit_log` |
| `burial.read` | SELECT on `burial_record`, `burial_approval`, `burial_payment`, `burial_overview`; also required by `record_burial_payment` |
| `burial.write` | `register_burial_for_member`, `register_burial_non_member`, `update_burial_details`, `correct_non_member_deceased` |
| `burial.approve` | `record_burial_approval` |
| `burial.void` | `void_burial` |

Proposed for the reports phase (not implemented): `report.read`, `reconcile.run`, `reconcile.read`.

Notes:
- A user who has `burial.read` but not `payment.read` can see that a payment is linked to a burial (the entry id) but not its amount.
- Deactivating a staff member or revoking a role grant removes all of these immediately.
