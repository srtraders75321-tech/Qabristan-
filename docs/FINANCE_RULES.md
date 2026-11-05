# Finance Rules

Source of truth for how money and balances are calculated. Anything marked **Proposed** or **Open** must not be treated as final. Open items are tracked in `DECISIONS.md`.

## Confirmed (PROJECT_CONTEXT section 4)

- Monthly equivalent: PKR 200 per family.
- Annual contribution: PKR 2,400 per family (12 x 200).
- Two-year advance: PKR 4,800. Three-year advance: PKR 7,200.
- Monthly payments are optional.
- Payment history, advance payments, and outstanding contributions must be supported.
- Burial eligibility and financial status are separate concepts. Arrears never automatically block burial.

## Representation

- Amounts are stored as integer paisa (PKR 200 = 20000). No floating point.
- Rates live in the versioned `rule_set` table (`effective_from`), not in code.
- Ledger entries are append-only. Corrections are reversal entries.

## Proposed calculation

```
months_covered = amount_paisa / monthly_rate_paisa      (must divide exactly)
covered_until  = end of the last month covered by verified, non-reversed contribution entries
months_due     = months from membership_start to as_of (inclusive)
balance_months = months_covered_total - months_due
```

- `balance_months > 0`: advance. `= 0`: current. `< 0`: arrears of `|balance_months|` months.
- Status becomes "overdue" only when arrears exceed `grace_months` from the active `rule_set`.
- Payments stack: coverage begins the month after the current `covered_until`.

## Open items

- **D2** grace-period and arrears calculation (months vs money, start of counting, treatment of partial years).
- **Q2** payments that are not an exact multiple of PKR 200.
- **D5** when a collected payment counts as verified for coverage purposes.
- **D3** non-member burial fee.

## Worked examples (illustrative, fictional)

| Case | Payments (verified) | As-of | Result |
|---|---|---|---|
| Annual payer | PKR 2,400 for Jan-Dec 2026 | 2026-11-05 | Covered until 2026-12, balance 0 or advance depending on membership start |
| Three-year advance | PKR 7,200 on 2026-01-10 | 2026-11-05 | Covered 36 months from period start |
| Reversal | Entry of PKR 2,400, later reversed | any | Net coverage 0 |

These examples become golden-file tests in Phase 3 once D2 and D5 are decided.
