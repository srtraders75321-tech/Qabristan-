---
name: finance-calc
description: Use when implementing or testing contribution coverage, arrears, advance, or status calculations in the Kabristan app. Holds the confirmed figures, the proposed formulas, and which parts are still undecided.
---

# Finance calculation

Read `docs/FINANCE_RULES.md` first. It is the source of truth.

## Confirmed
- PKR 200/month equivalent, PKR 2,400/year per family. Multi-year advances (2 or 3 years) are allowed. Monthly payment is optional.
- Burial eligibility is separate from payment status. Never block a burial because of arrears.

## Proposed (implement behind `rule_set`, label as proposed in code comments)
- Coverage in whole months: `amount_paisa / monthly_rate_paisa`, must divide exactly.
- Payments stack from the month after the current `covered_until`.
- `balance_months = months_covered_total - months_due(as_of)`; positive = advance, zero = current, negative = arrears.
- "Overdue" only when arrears exceed `grace_months` from the active rule set.

## Still undecided (do not invent)
- D2 grace-period and arrears rule. Read `grace_months` from `rule_set`; if unset, return status "rule not configured" rather than guessing.
- Q2 handling of amounts that are not a multiple of the monthly rate. Reject by default and surface the error; do not round.
- D5 when a payment becomes verified for coverage.
- D3 non-member burial fee.

## Test requirements
- Unit tests per rule: exact months, non-divisible amount rejected, stacking, advance, reversal, rule-version change mid-period.
- Property tests: balance equals the sum of ledger entries; reversing everything restores the starting state.
- Golden files: hand-calculated fictional families. Updating a golden file requires a deliberate, reviewed commit.
