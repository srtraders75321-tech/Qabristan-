# Tools

- `migration/`: import of existing records. Dry-run by default. Input files go in `migration/input/`, which is git-ignored, because they contain real data.
- `reconcile/`: reserved for a standalone reconciliation runner; the checks themselves live in the database (`docs/RECONCILIATION.md`).
- `mutation/reconciliation_mutations.py`: breaks each reconciliation check on scratch copies and confirms the database tests fail. Run it after changing any check.

`migration/` is built in a later phase.
