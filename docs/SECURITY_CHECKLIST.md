# Security Checklist (pre-release)

A second person reviews this list before any release that touches real data. Mark each item with the date and reviewer.

## Authentication and sessions
- [ ] Only invited committee users can sign in; open sign-up disabled
- [ ] MFA enforced for Super Admin, Committee Admin, and Treasurer
- [ ] Session timeout configured; refresh tokens revocable
- [ ] Lost-device revocation tested

## Authorization
- [ ] RLS enabled on every table; default deny
- [ ] Role matrix tests pass for every role (D1 decided)
- [ ] No table readable by the anonymous role
- [ ] Money functions check the caller's role inside the function
- [ ] Only approved functions are executable by clients; none by `anon` or `PUBLIC` (reconciliation check C17 reports no violations)

## Data integrity
- [ ] UPDATE/DELETE blocked on ledger, receipt, and audit tables for all roles
- [ ] Receipt numbers unique and never reused
- [ ] Reconciliation (`reconciliation_report()`) shows no failing check on staging
- [ ] Reconciliation mutation tests pass (`tools/mutation/reconciliation_mutations.py`)

## Secrets and supply chain
- [ ] No keys or keystores in git history
- [ ] Service-role key never shipped in the app
- [ ] Dependencies pinned and reviewed

## Privacy
- [ ] Only fields in the data dictionary are collected
- [ ] No real data in staging or local environments
- [ ] Private storage buckets only; no public URLs for receipts or documents

## Backup and recovery
- [ ] Independent encrypted backup running
- [ ] Restore drill performed and logged
- [ ] Backup key custody documented
