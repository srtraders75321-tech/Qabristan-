# Burial Records Module (backend)

Migration: `supabase/migrations/20261105000003_burial.sql`. Tests: `supabase/tests/040_burial.test.sql`.
The payment ledger and its functions were **not modified**; this module only calls `record_payment`.

## What it does

| Need | How |
|---|---|
| Registered persons | `register_burial_for_member`. Details are copied from the person record; the family is the membership in effect **on the date of death**, taken from `family_member` history (null if none covered that date). The burial never closes or edits a membership. |
| Non-registered persons | `register_burial_non_member`. Stored standalone: no `person`, `family`, or `family_member` row is ever created. |
| Non-member payments | `record_burial_payment` calls the existing `record_payment` (category `non_member_burial`, no family), then links the ledger entry in `burial_payment`. Receipt numbering, audit and append-only rules are the ledger's own. |
| Burial details | Burial date, grave reference, notes, deceased snapshot (name, father's name, date of birth, date of death), `burial_no` (permanent register number, never reused), family number snapshot. |
| Approvals | `record_burial_approval` appends a record: decision (`approved`/`rejected`), decision date, approver names (free text), reference (e.g. meeting), note, who recorded it. **No rule is enforced.** |
| Corrections | `update_burial_details` (date, grave, notes), `correct_non_member_deceased` (typing mistakes for non-members). Registered persons are corrected on the person record. All changes are audited with old and new values. |
| Mistaken records | `void_burial` with a mandatory reason. The record stays; a voided record cannot be edited, approved, restored, or paid. Voiding does **not** touch a linked payment: the treasurer reverses it in the ledger if needed. |

## Rules deliberately not invented

- **Burial eligibility** is never computed. No burial function reads the ledger, balances, or rules (a test inspects the function source). A family in arrears can have a burial recorded.
- **Approval** (D4): there is no requirement for an approval before, during, or after a burial; no minimum count; no restriction on who may be named as approver. Several records per burial are allowed. Which role may record approvals is data (`burial.approve`).
- **Non-member fee** (D3): any positive amount is accepted; more than one payment may be linked. Nothing enforces a fee or a "paid" state.
- **Members' burials** carry no payment in this module (the brief defines a payment only for non-members). `record_burial_payment` refuses them. Revisit if the committee decides otherwise.

## Integrity and security

- Clients (`authenticated`) have SELECT only, filtered by RLS on `burial.read`. `anon` has nothing. All writes are `SECURITY DEFINER` functions that call `_require(<permission>)` first.
- `burial_record`: never deleted or truncated; only `burial_date`, `grave_reference`, `notes`, non-member deceased details, and a one-way `recorded` -> `voided` change are allowed. Identity and link fields (`burial_no`, `kind`, `person_id`, `family_id`, `family_no_at_burial`, `created_*`) are immutable.
- `burial_approval`, `burial_payment`: append-only (no update, delete, truncate), including for the database owner.
- One active burial per registered person (partial unique index); a voided record frees the person.
- Non-member duplicate check (same name, father, date of death; case and spacing ignored) requires explicit confirmation (`p_confirm_possible_duplicate`). This is a warning, not a block.
- A trigger only lets a positive, family-less `non_member_burial` ledger entry be linked, to a non-member burial, once.
- All three tables write to `audit_log` (actor, old and new values).
- `burial_overview` (a `security_invoker` view) lists burials with approval count and latest decision. It contains no money or balance, and respects the caller's RLS.

## Permission keys

`burial.read`, `burial.write`, `burial.approve`, `burial.void`, plus `payment.record` and `burial.read` for `record_burial_payment`. Who holds them is configuration (see `PERMISSIONS.md`).

## Growth

Indexed on burial date, family, and lower-cased name. The test suite loads 3,000 extra burials and re-checks duplicate detection. Volumes (a few hundred burials a year at most) are far below what PostgreSQL handles comfortably.

## Not included yet

Grave map or plot inventory (no brief for it), deceased gender or cause of death (not requested; data minimisation), document attachments, and the burial-approval workflow (D4). Reports on burials belong to the reports phase.
