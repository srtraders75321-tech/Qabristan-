# Supabase backend

Run `supabase init` from the repository root on the developer machine to create `config.toml` (see `docs/SETUP_WINDOWS.md`, section 4).

## Structure

```
migrations/   numbered SQL migrations; never edit a merged migration
seed/         fictional seed data only
tests/        pgTAP tests for RLS, constraints, ledger rules
functions/    Edge Functions (receipt PDF, scheduled reconciliation)
```

## Rules

- Every table has RLS enabled with default deny, and tests for each role.
- Money operations are SQL functions that check the caller's role and write the audit row in the same transaction.
- `ledger_entry`, `receipt`, and `audit_log` reject UPDATE and DELETE for every role.
- Seed data is fictional. Never place real names or records here.
