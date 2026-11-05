---
name: ledger-rules
description: Use when adding or changing anything that records, reverses, verifies, or reads money in the Kabristan app (ledger tables, payment functions, receipts, reports, balances). Enforces integer paisa, append-only entries, and the reversal pattern.
---

# Ledger rules

1. **Integer paisa.** PKR 200 is stored as `20000`. Never use float, double, or numeric-with-fraction math for amounts. In Dart, use `int` and format only for display.
2. **Append-only.** `ledger_entry`, `receipt`, and `audit_log` accept INSERT only. UPDATE and DELETE are rejected by trigger for every role, including Super Admin. A new migration that touches these tables must keep the triggers and extend the pgTAP tests.
3. **Corrections = reversal + new entry.** A reversal is a new row with a negative amount and `reverses_entry_id` pointing at the original. Then insert the corrected entry. Both stay visible in history.
4. **Collected vs verified are separate facts.** Verification is recorded as its own row or status event with `verified_by` and `verified_at`. Do not overwrite the original row (open decision D5 defines who verifies and when).
5. **One transaction.** Every money function writes the ledger rows and the audit row together, after checking the caller's role inside the function.
6. **Receipts.** Sequential per year, unique `(receipt_year, receipt_seq)`, never reused, even when the payment is later reversed.
7. **Categories stay separate:** membership contribution, voluntary donation, non-member burial, other approved collection. Non-member burial payments never create membership.
8. **Rules are data.** Rates and grace periods come from the active `rule_set`. Do not hard-code them.

## Before finishing a change

- pgTAP tests cover: allowed insert, blocked update, blocked delete, reversal, role checks.
- Golden-file tests in `supabase/tests/` still pass, or were updated deliberately in a reviewed commit.
- `docs/FINANCE_RULES.md` and `docs/DECISIONS.md` reflect any new assumption.
