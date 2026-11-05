# Tools

- `migration/`: import of existing records. Dry-run by default. Input files go in `migration/input/`, which is git-ignored, because they contain real data.
- `reconcile/`: standalone checker that recomputes balances from the ledger and compares them to stored summaries.

Both are built in later phases (Phase 3 and Phase 7).
