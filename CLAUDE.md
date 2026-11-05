# Kabristan Committee Management System

Private bilingual (English/Urdu) Flutter + Supabase mobile app for a community graveyard committee in Pakistan. It holds sensitive family and financial records for thousands of households.

Read first: `docs/PROJECT_CONTEXT.md` (confirmed requirements), `docs/MASTER_PLAN.md` (architecture and phases), `docs/DECISIONS.md` (open and resolved decisions).

## Non-negotiable rules

1. **Money is integer paisa.** Never use floating point for amounts. Currency is PKR.
2. **The ledger is append-only.** No UPDATE or DELETE on ledger, receipt, or audit tables. Corrections are reversal entries plus a new entry.
3. **Never delete** families, persons, memberships, burials, or ledger history. Close date ranges instead (`valid_to`).
4. **Money logic lives in the database** (SQL functions), not in Flutter. The app calls functions and displays results.
5. **Rules are data.** Contribution rates, grace periods, and burial fees come from the versioned `rule_set` table. Do not hard-code them.
6. **Default-deny RLS** on every table. Every new table ships with policies and pgTAP tests.
7. **Fictional data only** in the repo, local, and staging. Real committee data never enters git or non-production environments.
8. **No secrets in the repo** (keys, keystores, `.env`, signing files).
9. **Applied migrations are immutable.** Add a new migration instead of editing a merged one.
10. **Every user-visible string exists in both English and Urdu** (ARB files), and UI is checked in RTL.

## Do not invent business rules

Anything in `docs/PROJECT_CONTEXT.md` section 16 is unresolved: role permissions, grace-period and arrears calculation, non-member burial fee, burial approval, cash-handover verification, family-transfer approval, Apple distribution method, backup retention and budget. Build these behind configuration or feature flags, record the assumption in `docs/DECISIONS.md`, and ask the owner. Burial eligibility is separate from payment status and is never blocked automatically by arrears.

## Layout

- `app/` Flutter application (generated with `flutter create`, see `app/README.md`)
- `supabase/` migrations, SQL functions, policies, fictional seed data, pgTAP tests
- `tools/` migration and reconciliation tooling (dry-run by default)
- `docs/` plans, data dictionary, finance rules, runbooks
- `.claude/` shared hooks and skills

## Commands

Added as each tool is set up (see `docs/SETUP_WINDOWS.md`):

- Hook tests: `node --test ".claude/hooks/*.test.mjs"`
- Flutter: `cd app && flutter pub get && flutter analyze && flutter test`
- Local database: `supabase start`, `supabase db reset` (local only), `supabase test db`

## Working agreements

- Work on branch `claude/app-creation-du1gfk`. Do not open pull requests unless asked.
- Backend contract first (tables, function signatures, who may call them), then frontend against it.
- Run the relevant tests before saying work is done. State plainly what was and was not verified.
