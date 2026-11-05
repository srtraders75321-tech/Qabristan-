# Supabase backend

On the developer machine, run `supabase init` from the repository root to create `config.toml` (see `docs/SETUP_WINDOWS.md`, section 4). The migrations and tests here do not depend on it.

## Structure

```
migrations/   numbered SQL migrations; never edit a merged migration
seed/         fictional / placeholder data only
tests/        plain-SQL tests plus the runner (run_local.sh)
functions/    Edge Functions (receipt PDF, scheduled reconciliation) - not built yet
```

## What exists

- `20261105000001_core_schema.sql`: tables, enums, append-only and never-delete guards, audit trigger, default-deny RLS.
- `20261105000002_functions.sql`: the only way to write data. Family registration and transfers, staff roles, rule versions, payments, verification, reversal, balance.

## How it is protected

- Clients (`authenticated`) have SELECT only, filtered by RLS; `anon` has nothing. Every write is a `SECURITY DEFINER` function that checks `has_permission(...)` first.
- `ledger_entry`, `ledger_verification`, `receipt`, `rule_set`, `audit_log` reject UPDATE, DELETE and TRUNCATE for every role.
- `person`, `family`, `family_member`, `committee_user`, `role_grant` can never be deleted. A family membership is ended by closing it (`valid_to`).
- A person cannot be in two families at the same time (exclusion constraint).
- Permissions live in `role_permission` (data). `seed/placeholder_permissions.sql` is a **placeholder, not the approved matrix** (D1).

## Creating the first Super Admin

The functions need an existing Super Admin, so the first one is created once, by the project owner, with the database owner/service role (never from the app): insert the user into `committee_user`, then a `super_admin` row into `role_grant`, and load the approved permissions into `role_permission`.

## Running the tests

```
bash supabase/tests/run_local.sh
```

Needs a PostgreSQL 16 server you can create databases on. `_shim_supabase.sql` stands in for Supabase's `auth` schema and roles during tests only. All test data is fictional.

## Rules

- Every table has RLS enabled with default deny, and tests for each role.
- Money is integer paisa. Corrections are reversal entries.
- Seed and test data are fictional. Never place real names or records here.
