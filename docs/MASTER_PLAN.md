# Kabristan Committee Management System — Grand Execution Plan

Status: **Draft for review.** Companion to `docs/PROJECT_CONTEXT.md`, which holds the confirmed requirements. Where this plan proposes something, it is labelled *Proposed*. Anything in `PROJECT_CONTEXT.md` section 16 stays open until the committee chairman decides it.

---

## 0. Scope and scale

| Item | Value | Source |
|---|---|---|
| Initial stated scale | ~250–300 people | PROJECT_CONTEXT §9 |
| Target scale (this plan) | Thousands of families, tens of thousands of individuals, many years of history | Owner, this session |
| Expected transactions | Low: roughly one to a few payments per family per year, plus burials | Derived from §4 |

**Scale discrepancy to confirm:** the master context says 250–300 people; the owner now describes thousands of houses. This plan is designed for the larger figure. The volume is still small for PostgreSQL, so the real design challenges are **integrity, auditability, and correct calculations**, not throughput. Confirm the target number before the schema is frozen.

Design target used below: **5,000 families, 50,000 individuals, 20 years of payment history, under 1 million financial rows.** That is comfortably within a single managed PostgreSQL instance.

---

## 1. Guiding principles

1. **The ledger is the truth.** Balances and statuses are derived from immutable transactions. They are never typed in by hand.
2. **Nothing is deleted.** Corrections are reversal or adjustment entries. Family transfers create new relationship rows and close old ones.
3. **Rules are data, not code.** Contribution amounts, grace periods, and burial fees live in a versioned rules table, so the committee's constitution can change without a code release.
4. **Money is integers.** PKR amounts are stored as integer paisa. No floating-point arithmetic anywhere in the money path.
5. **Security is enforced in the database.** Row-Level Security and protected functions decide access, not the Flutter client.
6. **Fictional data until sign-off.** No real family data enters any environment before the committee approves the build.
7. **Keep it boring and cheap.** Managed services, minimal moving parts, low running cost.

---

## 2. Target architecture

```
 ┌──────────────────────────┐
 │ Flutter app (Android/iOS)│  English + Urdu (RTL), emerald theme
 │ - UI only, no money math │
 └────────────┬─────────────┘
              │ HTTPS (TLS), Supabase Auth JWT (+MFA for privileged roles)
 ┌────────────▼─────────────────────────────────────────────┐
 │ Supabase                                                 │
 │  ├─ Auth (email/phone, MFA, session revocation)          │
 │  ├─ PostgreSQL                                           │
 │  │    ├─ schema: families, members, memberships,         │
 │  │    │          transfers, rules, ledger, receipts,     │
 │  │    │          burials, roles, audit_log               │
 │  │    ├─ Row-Level Security on every table              │
 │  │    └─ SQL functions (RPC) for all money operations    │
 │  ├─ Edge Functions (receipt PDF, scheduled reconciliation)│
 │  └─ Storage (private bucket: receipts, burial documents) │
 └────────────┬─────────────────────────────────────────────┘
              │ nightly
 ┌────────────▼─────────────┐
 │ Independent encrypted    │  Proposed: encrypted dump to a second
 │ backup (off-platform)    │  provider; restore tested monthly
 └──────────────────────────┘

 Builds:  Windows dev laptop → Android APK (signed) locally or in CI
          Codemagic (cloud macOS) → iOS build + signing
```

### 2.1 Why the money logic lives in PostgreSQL

Every payment, reversal, and rule change goes through a database function that runs inside one transaction. The function checks the caller's role, writes the ledger rows, and writes the audit row together. A bug in the app, or a stolen token without the right role, cannot write a half-finished financial entry or bypass the checks. The app just calls the function.

### 2.2 Environments

| Environment | Data | Purpose |
|---|---|---|
| `local` | Fictional seed data | Daily development, Supabase local stack |
| `staging` | Fictional data only | Integration testing, committee demos, UAT |
| `production` | Real data, only after sign-off | Live use |

No production credentials on developer laptops after go-live. The production database is reachable only through the app and the admin console.

---

## 3. Data architecture (critical)

This is the part of the system where a mistake is hardest to undo, so it gets the most care.

### 3.1 Core entities

| Entity | Purpose | Key rules |
|---|---|---|
| `family` | One household with a membership card | Has a permanent `family_no` (never reused). Holds a `status` |
| `person` | One individual | Belongs to people, not to families directly |
| `family_member` | Links a person to a family for a date range | `valid_from`, `valid_to` (null = current). Marriage transfers close one row and open another |
| `membership_card` | Card issued to a family | Versioned; a re-issue creates a new card row and retires the old one |
| `rule_set` | Constitution parameters | Versioned with `effective_from`. Old versions are kept |
| `ledger_entry` | Every money movement | Append-only. Positive or negative amount, category, period covered, status |
| `receipt` | Printable proof of a payment | Sequential number per year, never reused, linked to one or more ledger entries |
| `burial_record` | One burial | May reference a family or stand alone (non-member). Fee is a ledger entry |
| `committee_user` | Staff account | Linked to Supabase Auth; has roles |
| `role_grant` | Role assignment | Time-bounded, revocable, recorded |
| `audit_log` | Who did what, when | Written by triggers and functions. Append-only, readable only by Super Admin |

### 3.2 Family identity

A family keeps the same `family_no` for life. A married son who forms a new household receives a **new** `family_no` and a new card; his old membership row is closed, not deleted. Each person has exactly one `person_id` forever, so historical records always resolve to the same individual.

### 3.3 Ledger design

- `ledger_entry` rows are **insert-only**. The database rejects `UPDATE` and `DELETE` on this table for every role, including Super Admin.
- Each entry carries: `entry_id`, `family_id` (nullable for non-member burials), `category`, `amount_paisa` (signed), `period_start`, `period_end`, `payment_method`, `collected_by`, `verified_by`, `verified_at`, `reverses_entry_id` (nullable), `created_at`.
- A correction is a **reversal entry** (negative amount pointing at the original), followed by a new correct entry. Both stay visible.
- Verification is a separate status change recorded as its own row, so "collected" and "verified" are both historically visible.

### 3.4 Derived balances

Balances are computed, not stored as the truth:

- `covered_until` for a family = the latest period end covered by verified, non-reversed contribution entries, with the period logic from §5.
- Outstanding or advance = difference between the months due (from membership start to the as-of date) and the months covered.
- Materialized views refresh after each ledger write, so the dashboard reads quickly. A nightly job recomputes everything from scratch and compares the results. Any mismatch raises an alert.

### 3.5 Data integrity controls

| Control | Mechanism |
|---|---|
| No silent edits | Triggers block `UPDATE`/`DELETE` on ledger, audit, and receipt tables |
| No duplicate receipts | Unique constraint on `(receipt_year, receipt_seq)`; sequence values are never reused |
| No duplicate family numbers | Unique `family_no`, generated by a sequence |
| Possible duplicate people | Warning on create when name, father's name and family match an existing person. Staff confirm or reject |
| Totals always reconcile | Nightly reconciliation: sum of ledger = sum of receipts + unreceipted items + reversals |
| Who changed what | `audit_log` written in the same transaction as each change |
| Time integrity | All timestamps in UTC with time zone stored; display in Asia/Karachi |
| Bad input rejected | Constraints in the database (amount > 0 where required, period_end ≥ period_start, dates in valid range) |

### 3.6 Backup and recovery

- Supabase managed backups (retention depends on the plan, to be checked).
- **Proposed:** a nightly encrypted logical dump (`pg_dump`, encrypted with a key held by the chairman's nominated custodian), stored with a second provider.
- **Monthly restore drill:** restore into a scratch database and run the reconciliation check. The drill is logged.
- Retention period and budget: **unresolved** (PROJECT_CONTEXT §16.8).

### 3.7 Data migration from existing records

Existing manual records will be the hardest data work in the project. The plan:

1. **Collect** the existing registers, in whatever form they exist (paper, spreadsheets, notebooks). Keep the originals.
2. **Transcribe** into a staging spreadsheet using one fixed template: one row per family, one row per person, one row per payment.
3. **Clean** with scripts: trim, normalize names and transliteration, flag duplicates, flag missing mandatory fields.
4. **Validate** against the committee's known totals (e.g. "total collected in year X was Y"). Every difference is investigated and signed off.
5. **Import** through the same database functions the app uses, so migration rules match live rules. No direct SQL inserts into production.
6. **Reconcile** after import and get the chairman's written sign-off on the totals.

Each step is repeatable. The importer is run against staging first, many times, until the reconciliation is clean.

---

## 4. Financial calculations

### 4.1 Confirmed inputs (PROJECT_CONTEXT §4)

- Monthly equivalent: **PKR 200** per family.
- Annual: **PKR 2,400** per family (= 12 × 200).
- Two-year advance: PKR 4,800. Three-year advance: PKR 7,200.
- Monthly payments are optional.

### 4.2 Coverage calculation (*Proposed*)

A payment covers whole months at the monthly rate:

```
months_covered = amount_paisa / (monthly_rate_paisa)     -- must divide exactly
```

- A payment that does not divide exactly into whole months is **rejected**, or recorded as a donation, pending a committee decision. It is never silently rounded.
- Coverage starts at the first month after the family's current `covered_until`, so payments stack in order.
- Advance payments extend `covered_until` further into the future.

### 4.3 Status calculation (*Proposed; grace period is unresolved*)

```
months_due(as_of)     = months from membership_start to as_of (inclusive)
months_covered        = months from membership_start to covered_until
balance_months        = months_covered - months_due(as_of)

if balance_months >= 0          → "current" (or "advance" if > 0)
if balance_months < 0           → "arrears" of |balance_months| months
grace_months                    → rule parameter, from rule_set
status                          → "current" if arrears <= grace_months, otherwise "overdue"
```

The grace period value and whether it applies to arrears in months or in money are **unresolved** (PROJECT_CONTEXT §16.2). The code reads `grace_months` from `rule_set`. It is not hard-coded.

### 4.4 Burial eligibility (kept separate)

Per PROJECT_CONTEXT §4: burial eligibility is a separate concept from payment status. The system shows status but **never blocks** a burial because of arrears. The rule that does govern burial eligibility, if any, comes from the constitution and will be added as its own rule later.

### 4.5 Non-member burial fee

Amount **unresolved** (§16.3). The system stores it in `rule_set` under `non_member_burial_fee`, and the category is `non_member_burial`, kept separate from membership contributions.

### 4.6 Calculation test plan

The calculation engine is tested before anything else is built on it.

- **Unit tests** for each rule: exact months, partial months (rejected), stacking, advances, reversals, rule-version changes mid-year.
- **Property tests** (randomized sequences of payments and reversals): balance must always equal the sum of ledger entries; reversing everything returns to the starting state.
- **Golden-file tests**: a fixed set of fictional families with hand-calculated expected statuses. Any change to rules must update the golden file deliberately, in a reviewed commit.
- **Reconciliation test**: run the nightly reconciliation job against seeded data with deliberately injected errors. It must catch every one.

---

## 5. Security plan

| Area | Measure | Phase |
|---|---|---|
| Authentication | Supabase Auth, strong password policy, email verification | 1 |
| Privileged MFA | TOTP enforced for Super Admin, Committee Admin, Treasurer | 1 |
| Authorization | RLS on every table; default deny; role checks inside functions | 1–2 |
| Money operations | Only via SECURITY DEFINER functions with explicit role checks | 3 |
| Sensitive reads | Views that hide columns a role does not need | 2 |
| Transport | TLS only; certificate pinning considered for the app | 1 |
| Device | Session timeout, revocation of sessions from the admin console, app lock option | 6 |
| Lost device | Super Admin can revoke all sessions for a user immediately | 6 |
| Logging | Audit log for every create, change, verify, reverse, and role change | 3 |
| Secrets | No secrets in the repo. Supabase keys in CI secret store; service keys never in the app | 0 |
| Dependency hygiene | Dependabot or equivalent; pinned Flutter and package versions | 0 |
| Penetration review | Internal review by a second person using the checklist in `docs/SECURITY_CHECKLIST.md`, before go-live | 8 |
| Data minimization | Only fields listed in the data dictionary are collected | 2 |

Access tests: a role-matrix test suite logs in as each role and attempts every operation. Allowed and denied results must match the approved matrix exactly. The matrix is blocked until §16.1 is decided.

---

## 6. Roles and permissions

The role names are proposed. The permission matrix is **unresolved** (§16.1). Development uses placeholder roles behind a single config file so the matrix can change without touching feature code.

| Role (proposed) | Typical capability (to confirm) |
|---|---|
| Super Admin | Everything, including role management and audit log |
| Committee Admin | Family and member records; approve transfers |
| Treasurer | Verify payments, financial reports |
| Collection Officer | Record payments and issue receipts |
| General Committee Member | Read-only dashboards and reports |

---

## 7. Repository layout (proposed)

```
Qabristan-/
├─ CLAUDE.md                     # Project memory for Claude Code (rules, commands, conventions)
├─ README.md                     # Human entry point
├─ docs/
│  ├─ PROJECT_CONTEXT.md         # Confirmed requirements (owner's brief)
│  ├─ MASTER_PLAN.md             # This document
│  ├─ DECISIONS.md               # Log of resolved and open decisions with dates
│  ├─ DATA_DICTIONARY.md         # Every field, its meaning, and who may see it
│  ├─ FINANCE_RULES.md           # Calculation rules, examples, worked figures
│  ├─ SECURITY_CHECKLIST.md      # Pre-release security review list
│  ├─ MIGRATION_RUNBOOK.md       # Steps to import existing records
│  ├─ BACKUP_RUNBOOK.md          # Backup, encryption, restore drill
│  └─ ROLES_MATRIX.md            # Permission matrix (once approved)
├─ app/                          # Flutter application
│  ├─ lib/
│  │  ├─ core/                   # theme, routing, config, l10n
│  │  ├─ features/               # families, members, payments, receipts, burials, admin
│  │  └─ data/                   # Supabase repositories (no money math)
│  ├─ l10n/                      # app_en.arb, app_ur.arb
│  └─ test/
├─ supabase/
│  ├─ migrations/                # Numbered SQL migrations, never edited after merge
│  ├─ functions/                 # SQL RPC for money and role operations
│  ├─ policies/                  # RLS policies (also in migrations)
│  ├─ seed/fictional/            # Fictional data only
│  ├─ tests/                     # pgTAP tests for RLS and ledger rules
│  └─ edge/                      # Edge Functions (receipts PDF, reconciliation)
├─ tools/
│  ├─ migration/                 # Import scripts (dry-run by default)
│  └─ reconcile/                 # Standalone reconciliation checker
├─ .claude/
│  ├─ settings.json              # Hooks and permissions (shared, committed)
│  ├─ skills/                    # Project skills (see §8)
│  └─ agents/                    # Optional review subagents
└─ .github/workflows/            # CI: analyze, test, pgTAP, build
```

---

## 8. Claude Code setup: CLAUDE.md, skills, hooks, plugins

### 8.1 `CLAUDE.md` (project memory, short and strict)

Contents, in order:
1. Project summary and link to `docs/PROJECT_CONTEXT.md`.
2. Non-negotiable rules: integer paisa money; ledger is append-only; no deletes of families, persons, ledger, receipts, or audit rows; no secrets in repo; fictional data only outside production.
3. Commands: how to run the app, tests, pgTAP, analyzer, reconciliation.
4. Conventions: migration naming, RPC naming, l10n keys, RTL testing.
5. "Ask first" list: anything touching rules, roles, or unresolved decisions in PROJECT_CONTEXT §16.

### 8.2 Skills (`.claude/skills/`)

Each skill is a short, focused instruction file Claude loads when relevant.

| Skill | When it applies | What it contains |
|---|---|---|
| `ledger-rules` | Any change to payment or balance code | The integer-paisa rule, append-only rule, reversal pattern, golden-file update procedure |
| `finance-calc` | Changes to coverage or status logic | Formulas from §4, grace-period handling via `rule_set`, worked examples |
| `rls-review` | Any new table or policy | Default-deny checklist, role matrix check, pgTAP test template |
| `l10n-urdu` | Any new user-visible string | ARB key naming, both languages required, RTL layout checklist |
| `family-transfer` | Marriage transfers | Close-and-open pattern, new family_no, history preservation |
| `data-import` | Work in `tools/migration` | Dry-run first, reconciliation output, no direct SQL inserts |
| `burial-records` | Burial module | Non-member flow, separate category, no eligibility blocking by arrears |
| `release-build` | Building APK or iOS | Signing steps, Codemagic config, version bump rules |

### 8.3 Hooks (`.claude/settings.json`, committed)

Hooks run automatically on tool events. They are the place to enforce rules that must never be skipped.

| Event | Hook | Purpose |
|---|---|---|
| `PreToolUse` on Edit/Write | Block edits to applied migration files | Migrations are immutable once merged |
| `PreToolUse` on Edit/Write | Block writes to `supabase/seed/` containing names that look like real data | Guards against real data entering the repo; checked by pattern and reviewed |
| `PreToolUse` on Bash | Block commands containing `DROP`, `TRUNCATE`, or `DELETE FROM` against the production project reference | Protects production |
| `PostToolUse` on Edit of `.dart` | Run `dart format` and `flutter analyze` on the file | Fast feedback |
| `PostToolUse` on Edit of `.sql` | Run `pgTAP` on the local stack when available | Catches RLS and ledger regressions early |
| `Stop` | Run the fast test set and report results | No "done" claim without a test run |

Exact commands are added during Phase 0, after the tooling is installed. Hook scripts are kept in `.claude/hooks/` and tested by hand before being committed.

### 8.4 Plugins

A project plugin bundles the skills and hooks above so they can be installed in another repo or on another machine with one step. It is optional for Phase 0 and becomes useful once a second project or a second developer exists. Plugin packaging is considered in Phase 9.

### 8.5 Subagents (optional)

- **Finance reviewer:** reviews any diff touching money logic against `finance-calc` and `ledger-rules`.
- **Security reviewer:** reviews any diff touching RLS, functions, or auth against `rls-review`.

These are invoked on demand, not on every change.

---

## 9. Testing strategy

| Layer | Tool | Gate |
|---|---|---|
| Dart unit and widget tests | `flutter test` | Every PR |
| Money and rule unit tests | `flutter test` + golden files | Every PR |
| Database tests (RLS, constraints, triggers) | pgTAP on local Supabase | Every PR touching `supabase/` |
| Role matrix | Scripted logins as each role | Every PR touching auth or policies |
| Reconciliation | Nightly job on staging | Must pass before release |
| Localization | Golden tests in English and Urdu, RTL check | Every PR touching UI |
| Manual UAT | Committee members on fictional data in staging | Before each release |
| Backup restore | Monthly drill, logged | Before go-live and monthly after |

---

## 10. Delivery plan (phases)

Each phase ends with an exit gate. The next phase does not start until the gate is met.

### Phase 0 — Governance and foundations (1–2 weeks)
- **Decisions:** owner meets the chairman; resolve or schedule §16 items; record outcomes in `docs/DECISIONS.md`.
- **Repo:** create the layout in §7; add `CLAUDE.md`, README, `.gitignore`, secret handling.
- **Tooling:** Flutter on Windows, Supabase CLI, local Supabase stack, CI skeleton.
- **Claude setup:** `.claude/settings.json` with first hooks; first two skills (`ledger-rules`, `finance-calc`).
- **Exit gate:** `flutter doctor` clean; local Supabase starts; CI runs on an empty test; decisions log exists.

### Phase 1 — Authentication and roles skeleton (2 weeks)
- Supabase Auth, staff accounts, MFA for privileged roles.
- Roles and `role_grant` tables; default-deny RLS on all tables.
- Login screen, session handling, session revocation.
- Localization scaffolding (EN/UR), theme tokens from PROJECT_CONTEXT §13.
- **Exit gate:** role matrix test passes for the placeholder matrix; MFA enforced for privileged roles.

### Phase 2 — Families and members (3 weeks)
- Family registration, `family_no` sequence, person records, `family_member` date ranges.
- Duplicate-person warning.
- Family transfer flow (married son and daughter) with history preserved.
- Membership card generation (printable/PDF).
- **Exit gate:** transfers tested with history; no delete path exists in the UI or the API; data dictionary complete.

### Phase 3 — Ledger and calculation engine (3 weeks)
- `ledger_entry`, rules table, coverage and status functions.
- Payment recording functions (contribution, donation, other), reversal function, verification function.
- Audit logging on every write.
- Golden-file and property tests.
- **Exit gate:** calculation tests pass; reconciliation job catches seeded errors; no UPDATE/DELETE path on ledger.

### Phase 4 — Payments, receipts and dashboard (3 weeks)
- Payment collection screens, payment history, receipt generation with sequential numbers.
- Dashboard tiles from PROJECT_CONTEXT §13: family stats, annual collection, pending accounts, burial stats, recent payments.
- Financial reports: monthly, annual, outstanding, advances.
- **Exit gate:** receipts reconcile to ledger; dashboard figures match the reconciliation report.

### Phase 5 — Burial records (2 weeks)
- Burial registration for registered and non-registered families.
- Non-member fee path as a separate category, once the fee is decided. Until then the fee field is hidden behind a feature flag.
- Burial history and search.
- **Exit gate:** non-member burial creates no membership; eligibility is never blocked by arrears.

### Phase 6 — Administration and security hardening (2 weeks)
- Committee administration screens; role assignment with audit.
- Session revocation for lost devices; app lock option.
- Audit log viewer for Super Admin.
- **Exit gate:** lost-device revocation tested; audit log complete for all write paths.

### Phase 7 — Migration rehearsal (2–3 weeks, runs in parallel with Phases 4–6 once the data template is agreed)
- Collect and transcribe existing registers into the template.
- Run the importer against staging repeatedly until reconciliation is clean.
- Committee validates totals.
- **Exit gate:** written sign-off from the chairman on migrated totals, using fictional-equivalent dry-runs first and the real import only after approval.

### Phase 8 — Release readiness (2 weeks)
- Security checklist complete; second-person review.
- Backup restore drill passed (logged).
- Android signed APK build; iOS build and signing through Codemagic with the chosen Apple distribution method (§16.7).
- Committee UAT on staging.
- **Exit gate:** UAT sign-off; drill logged; both builds installable on test devices.

### Phase 9 — Go-live and operations (ongoing)
- Production import after sign-off.
- Monthly restore drill, monthly reconciliation review, quarterly access review.
- Plugin packaging of Claude Code setup if useful.

Rough total: **about 5–6 months** of focused work, depending on how quickly the committee decides the §16 items. The decisions are the most likely cause of delay, not the code.

---

## 11. Immediate next steps

1. **Owner:** confirm the target scale (250–300 people vs thousands of families).
2. **Owner + chairman:** schedule the decision meeting for §16 items, starting with the grace period and the role matrix, since both block Phases 1 and 3.
3. **Owner:** collect a sample of the existing registers (a few pages, anonymized or fictional-equivalent) so the migration template can be designed.
4. **Claude (on approval):** Phase 0 setup: repo layout, `CLAUDE.md`, `DECISIONS.md`, Flutter skeleton, first skills and hooks.

---

## 12. Open risks

| Risk | Impact | Mitigation |
|---|---|---|
| Grace-period and arrears rules change late | Rework in Phase 3 | Rules in data, golden files updated deliberately |
| Role matrix disputed | Rework in Phase 1 and every screen | Single config; matrix tests |
| Paper records incomplete or inconsistent | Migration delays | Dry-run importer; committee totals as the reference |
| Single developer / single point of knowledge | Continuity risk | Docs, `DECISIONS.md`, runbooks, Claude setup in repo |
| iOS distribution method not chosen | iOS install blocked | Decide before Phase 8; Codemagic supports signing |
| Supabase plan limits or pricing change | Cost or backup gaps | Check plan at Phase 0; independent backup in §3.6 |
| Personal data exposure | Serious harm to families | RLS, default deny, audit, minimal collection, fictional data until sign-off |
