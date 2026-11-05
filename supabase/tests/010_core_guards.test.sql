-- Core guards: default-deny RLS, append-only tables, never-delete tables.
-- All people here are fictional.

-- fixtures (superuser) ------------------------------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'admin@example.test'),
  ('00000000-0000-0000-0000-0000000000a2', 'collector@example.test'),
  ('00000000-0000-0000-0000-0000000000a3', 'outsider@example.test');

insert into public.committee_user (id, display_name) values
  ('00000000-0000-0000-0000-0000000000a1', 'Test Super Admin'),
  ('00000000-0000-0000-0000-0000000000a2', 'Test Collector');
-- a3 has an auth account but is NOT a committee user.

insert into public.role_grant (user_id, role) values
  ('00000000-0000-0000-0000-0000000000a1', 'super_admin'),
  ('00000000-0000-0000-0000-0000000000a2', 'collection_officer');

insert into public.person (id, full_name) values
  ('00000000-0000-0000-0000-0000000000b1', 'Fictional Person One');
insert into public.family (id, membership_start, head_person_id) values
  ('00000000-0000-0000-0000-0000000000c1', '2026-01-01', '00000000-0000-0000-0000-0000000000b1');
insert into public.family_member (family_id, person_id, relation, valid_from) values
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b1', 'father', '2026-01-01');
-- far-future effective date: exists for the append-only test but is never in effect
insert into public.rule_set (effective_from, monthly_rate_paisa) values ('2999-01-01', 20000);
insert into public.ledger_entry (id, family_id, category, amount_paisa, period_start, period_end, collected_by) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000c1',
   'membership_contribution', 240000, '2026-01-01', '2026-12-01', '00000000-0000-0000-0000-0000000000a2');

-- append-only tables reject changes, even for the superuser -----------------
select t.throws($$update public.ledger_entry set amount_paisa = 1$$, 'append-only', 'ledger_entry: UPDATE rejected');
select t.throws($$delete from public.ledger_entry$$, 'append-only', 'ledger_entry: DELETE rejected');
select t.throws($$truncate public.ledger_entry cascade$$, 'append-only', 'ledger_entry: TRUNCATE rejected');
select t.throws($$update public.audit_log set action = 'x'$$, 'append-only', 'audit_log: UPDATE rejected');
select t.throws($$delete from public.audit_log$$, 'append-only', 'audit_log: DELETE rejected');
select t.throws($$update public.rule_set set monthly_rate_paisa = 1$$, 'append-only', 'rule_set: UPDATE rejected');

-- never-delete tables --------------------------------------------------------
select t.throws($$delete from public.family$$, 'never deleted', 'family: DELETE rejected');
select t.throws($$delete from public.person$$, 'never deleted', 'person: DELETE rejected');
select t.throws($$delete from public.family_member$$, 'never deleted', 'family_member: DELETE rejected');
select t.throws($$truncate public.person cascade$$, 'never deleted', 'person: TRUNCATE rejected');

-- family_member can only be closed, once --------------------------------------
select t.throws($$update public.family_member set relation = 'son'$$, 'only be closed', 'family_member: relation cannot change');
select t.lives($$update public.family_member set valid_to = '2026-06-01'$$, 'family_member: can be closed');
select t.throws($$update public.family_member set valid_to = '2026-07-01'$$, 'only be closed', 'family_member: cannot be re-closed');

-- audit rows were written automatically ---------------------------------------
select t.ok((select count(*) from public.audit_log where table_name = 'ledger_entry' and action = 'INSERT') >= 1,
  'audit: ledger insert recorded');

-- RLS: default deny ---------------------------------------------------------------
select t.login('00000000-0000-0000-0000-0000000000a3');   -- not a committee user
select t.eq((select count(*) from public.family), 0::bigint, 'RLS: non-staff sees no families');
select t.eq((select count(*) from public.ledger_entry), 0::bigint, 'RLS: non-staff sees no ledger');
select t.eq((select count(*) from public.audit_log), 0::bigint, 'RLS: non-staff sees no audit log');
select t.logout();

select t.login('00000000-0000-0000-0000-0000000000a2');   -- collection officer (placeholder matrix)
select t.eq((select count(*) from public.family), 1::bigint, 'RLS: collector can read families');
select t.eq((select count(*) from public.ledger_entry), 1::bigint, 'RLS: collector can read ledger');
select t.eq((select count(*) from public.audit_log), 0::bigint, 'RLS: collector cannot read audit log');
select t.throws($$insert into public.person (full_name) values ('Direct Insert')$$, 'permission denied', 'client cannot INSERT directly');
select t.throws($$update public.family set status = 'closed'$$, 'permission denied', 'client cannot UPDATE directly');
select t.throws($$select * from public.receipt_counter$$, 'permission denied', 'receipt_counter hidden from clients');
select t.logout();

select t.login('00000000-0000-0000-0000-0000000000a1');   -- super admin
select t.ok((select count(*) from public.audit_log) > 0, 'RLS: super admin can read audit log');
select t.logout();

-- anon sees nothing at all ------------------------------------------------------------
set role anon;
select t.throws($$select * from public.family$$, 'permission denied', 'anon: no access to family');
reset role;
