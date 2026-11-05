# Financial Reconciliation (backend)

Migrations: `20261105000004_reconciliation.sql` (checks) and `20261105000005_function_privileges.sql` (privilege fix, see below).
Tests: `supabase/tests/050_reconciliation.test.sql`. Requirements it implements: `REPORTS_AND_RECONCILIATION_REQUIREMENTS.md` section 5.
The payment and burial migrations and their functions were **not modified**.

## What it is

A set of automated, **read-only** checks that look for inconsistencies in financial and burial data. Each check returns one row per violation: `(check_id, severity, record_type, record_id, detail)`. No rows means the check passes. Severities: `critical`, `high`, `medium`, and `info` (an observation that depends on an undecided policy, never a failure).

Entry points (both require the permission `reconcile.run`, which the permission matrix grants to roles as data; nothing is hard-coded):

| Function | Returns |
|---|---|
| `reconciliation_report()` | One row per check: name, worst severity found, violation count, status (`pass`, `fail`, or `info`) |
| `reconciliation_violations(check_id default null)` | The offending records for one check, or for all |

## Read-only by construction

- Every reconciliation function is declared `STABLE`. PostgreSQL itself refuses `INSERT`, `UPDATE`, `DELETE`, and DDL inside a stable function, so a check cannot change data even by mistake.
- Tests verify: all functions are stable; no function text contains a data-changing statement; running the report and the violation list as an authorised user leaves row counts of the ledger, receipts, verifications, audit log, burial records, and the receipt counter unchanged (the audit log gains no row).
- Reconciliation never repairs data. A discrepancy is corrected only through the existing append-only functions (`reverse_payment`, etc.) with a reason, and the check is run again. The original finding and the correction both stay on record.
- The internal `_recon_*` functions are not callable by clients; only the two entry points above are, and only with `reconcile.run`.

## Checks implemented

| ID | Verifies | Severity |
|---|---|---|
| C1 | Every reversal references an existing original and exactly negates it (amount, family, category, period); no reversal of a reversal; no negative entry without an original; reversal not dated before its original | critical |
| C2 | Every payment has exactly one receipt; no receipt for a reversal; no receipt for a missing entry | critical |
| C3 | Receipt numbers unique per year; no gaps; the receipt counter is neither behind (next receipt would collide) nor ahead | critical / high |
| C4 | Every verification points to a real positive payment, is not dated before the payment, and is not applied to an already reversed payment | high |
| C5 | **Independent recomputation** of each family's covered months and covered-until month, using plain integer month arithmetic and none of the production helpers, compared with what the production derivation returns | critical |
| C6 | Each membership payment equals whole months times the rate in effect on the payment date, and starts no earlier than the family's joining month | high |
| C7 | **Double booking**: no month is booked by two live (un-reversed) membership payments for one family | critical |
| C8 | Non-member burial payments have no family and no period; unlinked ones are listed as observations (Q7 open) | high / info |
| C9 | Every burial payment link points at a real non-member burial and a real, positive, family-less non-member burial payment; non-member burial records carry no person or family | high |
| C10 | Net ledger total per category equals the total of un-reversed payments | critical |
| C11 | Ledger, receipt, verification, rule, burial, approval and link rows each have an audit record of their creation that still matches; no audited row has since been deleted; no audit record of an update or delete on an append-only table; no duplicated creation record | critical / high / medium |
| C11A | Creation audited with no actor (expected only for service-role or setup operations) | info |
| C13 | The protective triggers (append-only, never-delete, audit, validation) exist and are enabled | critical |
| C14 | Row-level security is on for every table in `public`; `anon` has no table privileges; signed-in clients cannot write tables directly | critical |
| C16 | No payment is reversed, verified, or allocated to a burial more than once (**duplicate allocation**) | critical |
| C17 | Only the approved client functions are executable by clients; none by `anon` or `PUBLIC` | critical |

### Not implemented in this phase

- **C12** (membership overlap): already enforced by a database exclusion constraint; a separate check adds little.
- **C15** (staff and role consistency): not a financial check; deferred.
- **Stored balance comparison**: balances are never stored (always derived), so there is nothing stored to compare. C5 compares an independent recomputation with the production derivation instead. If summary tables are introduced for reports, add a check that compares them with a recomputation.
- **Persisted run history** (an append-only `reconciliation_run` table): deferred, to keep this phase strictly read-only. Add it with the reports phase, as a separate write function with its own permission.
- Heuristic checks (for example, two near-identical payments close together) are not included: whether they are errors is a committee policy question.

## A defect found and fixed during this phase

While testing check access, the new tests showed that **internal functions were executable by signed-in clients and by the anonymous role**. Cause: migration 1 used `alter default privileges in schema public revoke execute ... from public`, which cannot remove PostgreSQL's global default (a schema-specific default can only add privileges).

Impact: the business functions check permissions internally, so they were not exploitable. The internal `SECURITY DEFINER` helpers `_booked_months` and `_covered_months` have no permission check, so any signed-in client who knew a family's id could read which months that family had paid, bypassing `payment.read`.

Fix (migration 5): revoke execute on every function we own in `public` from `PUBLIC`, `anon`, and `authenticated`; grant back only the approved client functions; set a global default so new functions start private. No function body or table changed. Check **C17** now detects any regression, including a platform default (such as Supabase's) that grants new functions to clients.

Rule for developers: a new client-callable function must be added to `public._client_functions()` and granted to `authenticated` explicitly in its own migration.

## Assumptions and unresolved decisions

- **No committee policy was invented.** Checks reuse the proposed rules already documented (whole months at the monthly rate, stacking, no overlap). C6 and C5 inherit Q2 (odd amounts rejected) and D5 (whether coverage requires verification, read from the active rule; the check follows the same flag).
- **Payment date and time zone (C6):** the rate is matched on the payment date evaluated in UTC and in Asia/Karachi, and either match is accepted, because the server's session time zone is not guaranteed.
- **Q7 (unlinked non-member burial payment):** reported as `info`, not as a failure.
- **D1 (permission matrix):** `reconcile.run` is a permission key; `seed/placeholder_permissions.sql` grants it to Super Admin and Treasurer as a placeholder only.
- **D8 (retention):** nothing is stored, so no retention decision is needed yet.
- **C11A:** raw data inserted by the database owner shows as an observation, by design.
- **Audit completeness assumes** the audit trigger is the only writer of `audit_log` rows with action `INSERT` for these tables. A database owner can forge audit rows; C11 detects mismatches and duplicates but cannot prove authenticity. Independent encrypted backups (D8) remain the defence against a malicious owner.

## Testing

`050_reconciliation.test.sql` runs after the other suites on their leftover data:

1. **Baseline:** no critical, high or medium violation on data created through the real functions.
2. **API security:** allowed for roles holding `reconcile.run`; denied for others, non-staff, and `anon`; the matrix change takes effect immediately.
3. **Read-only proof** (see above) and a check that the append-only protections still hold.
4. **Function privileges** (C17 and the defect above).
5. **Deliberate corruption:** 54 corruptions (every one of the 16 checks has at least one), each applied inside a sub-transaction that is always rolled back, including tampering with protected tables as a database owner could (user triggers bypassed), dropping constraints and triggers, and replacing a production function with a buggy one. Each must make the targeted check report more violations than before. At the end the suite proves everything was restored.
6. **Mutation testing** of the checks themselves: `tools/mutation/reconciliation_mutations.py` runs 29 mutations on scratch copies: each of the 16 checks silenced entirely, 11 subtle partial breaks, a check declared VOLATILE, a check that tries to write, and the original privilege defect (migration 5 omitted). The suite must fail every time. First full run: 28 killed, 1 survived (the C3 gap detector was masked by a second C3 sub-check firing on the same corruption); the test was tightened and that mutation then died.

## Running it

```
bash supabase/tests/run_local.sh                      # whole database suite
python3 tools/mutation/reconciliation_mutations.py    # mutation tests (several minutes)
```

In the app (later phase), call `reconciliation_report()` nightly and on demand as a user with `reconcile.run`.
