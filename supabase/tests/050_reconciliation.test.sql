-- Reconciliation tests: baseline, API security, read-only guarantee, and deliberate corruption.
-- Every check must (1) pass on clean data and (2) catch the failure it exists for.
-- All data is fictional. Runs after 010-040 and uses the data they leave behind.
-- Users: a1 super_admin, a2 collection_officer, a3 not staff, a4 treasurer, a5 committee_admin,
-- a6 general_member. Placeholder matrix: reconcile.run is held by super_admin and treasurer.

-- ============================================================ fixture repair
-- Test 010 inserted ledger entry d1 directly (bypassing record_payment), so it has no receipt;
-- check C2 correctly reports that. Give it one the way record_payment would.
insert into public.receipt_counter as c (receipt_year, last_seq)
values (extract(year from (now() at time zone 'Asia/Karachi'))::int, 1)
on conflict (receipt_year) do update set last_seq = c.last_seq + 1;
insert into public.receipt (receipt_year, receipt_seq, entry_id, issued_by)
select rc.receipt_year, rc.last_seq, '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a1'
  from public.receipt_counter rc
 where rc.receipt_year = extract(year from (now() at time zone 'Asia/Karachi'))::int;

-- ============================================================ lookups for the corruption tests
select id as rev_id, reverses_entry_id as rev_orig from public.ledger_entry where reverses_entry_id is not null order by created_at limit 1 \gset
select entry_id as ver_e from public.ledger_verification order by verified_at limit 1 \gset
select e.id as unlinked from public.ledger_entry e where e.category = 'non_member_burial' and e.amount_paisa > 0 and e.reverses_entry_id is null and not exists (select 1 from public.burial_payment p where p.entry_id = e.id) limit 1 \gset
select id as mbur from public.burial_record where kind = 'registered_person' limit 1 \gset
select burial_id as nmbur, entry_id as linked_e from public.burial_payment order by linked_at limit 1 \gset
select id as plain_e from public.ledger_entry e where e.amount_paisa > 0 and e.category = 'membership_contribution' and e.id <> '00000000-0000-0000-0000-0000000000d1' and not exists (select 1 from public.ledger_entry r where r.reverses_entry_id = e.id) limit 1 \gset
select id as unver_e from public.ledger_entry e where e.amount_paisa > 0 and e.reverses_entry_id is null and not exists (select 1 from public.ledger_verification v where v.entry_id = e.id) and not exists (select 1 from public.ledger_entry r where r.reverses_entry_id = e.id) limit 1 \gset

-- ============================================================ baseline: clean data passes
select t.eq((select count(*) from public._recon_run() where severity <> 'info'), 0::bigint,
            'baseline: no critical, high or medium violations on data created through the real functions');
select t.eq((select count(*) from public._recon_catalog()), 16::bigint, 'catalog lists 16 checks');
select t.eq((select count(distinct check_id) from public._recon_catalog()), 16::bigint, 'catalog ids are unique');
select t.throws($$select * from public._recon_run('C99')$$, 'unknown reconciliation check', 'unknown check id rejected');
select t.ok((select count(*) from public._recon_run('C11A')) > 0, 'baseline: raw-inserted fixtures show as info observations (no actor)');
select t.ok((select count(*) from public._recon_run('C8')) = 1 and (select severity from public._recon_run('C8')) = 'info', 'baseline: unlinked non-member payment is only an observation (Q7 open)');

-- ============================================================ API: permission-checked
select t.login('00000000-0000-0000-0000-0000000000a4');   -- treasurer (placeholder: reconcile.run)
select t.eq((select count(*) from public.reconciliation_report()), 16::bigint, 'treasurer: report has one row per check');
select t.eq((select count(*) from public.reconciliation_report() where status = 'fail'), 0::bigint, 'treasurer: no failing check on clean data');
select t.ok((select count(*) from public.reconciliation_report() where status = 'pass') >= 13, 'treasurer: most checks report pass');
select t.eq((select status from public.reconciliation_report() where check_id = 'C11A'), 'info', 'treasurer: observation-only check reports info, not fail');
select t.eq((select count(*) from public.reconciliation_violations('C2')), 0::bigint, 'treasurer: violations for one check');
select t.throws($$select * from public.reconciliation_violations('nope')$$, 'unknown reconciliation check', 'api: unknown check rejected');
select t.logout();

select t.login('00000000-0000-0000-0000-0000000000a1');
select t.eq((select count(*) from public.reconciliation_report()), 16::bigint, 'super admin: can run reconciliation');
select t.logout();

select t.login('00000000-0000-0000-0000-0000000000a2');   -- collection officer
select t.throws($$select * from public.reconciliation_report()$$, 'permission denied', 'collection officer cannot run reconciliation');
select t.throws($$select * from public.reconciliation_violations()$$, 'permission denied', 'collection officer cannot read violations');
select t.logout();
select t.login('00000000-0000-0000-0000-0000000000a5');   -- committee admin
select t.throws($$select * from public.reconciliation_report()$$, 'permission denied', 'committee admin cannot run reconciliation (placeholder matrix)');
select t.logout();
select t.login('00000000-0000-0000-0000-0000000000a6');   -- general member
select t.throws($$select * from public.reconciliation_report()$$, 'permission denied', 'general member cannot run reconciliation');
select t.logout();
select t.login('00000000-0000-0000-0000-0000000000a3');   -- not staff
select t.throws($$select * from public.reconciliation_report()$$, 'permission denied', 'non-staff cannot run reconciliation');
select t.throws($$select * from public._recon_run()$$, 'permission denied', 'internal runner is not callable by clients');
select t.throws($$select * from public._recon_c1()$$, 'permission denied', 'internal check functions are not callable by clients');
select t.logout();
set role anon;
select t.throws($$select * from public.reconciliation_report()$$, 'permission denied', 'anon cannot run reconciliation');
reset role;

-- the permission matrix is data: removing the key takes effect at once, restoring it works again
delete from public.role_permission where role = 'treasurer' and permission = 'reconcile.run';
select t.login('00000000-0000-0000-0000-0000000000a4');
select t.throws($$select * from public.reconciliation_report()$$, 'permission denied', 'matrix: removing reconcile.run blocks the treasurer immediately');
select t.logout();
insert into public.role_permission (role, permission) values ('treasurer', 'reconcile.run');
select t.login('00000000-0000-0000-0000-0000000000a4');
select t.lives($$select * from public.reconciliation_report()$$, 'matrix: restored permission works again');
select t.logout();

-- ============================================================ function privileges (C17)
select t.eq((select count(*) from public._recon_run('C17')), 0::bigint, 'C17 baseline: only approved functions are executable by clients');
select t.eq((select count(*) from public._client_functions()), 21::bigint, 'approved client-function list has 21 entries');
select t.ok(not exists (select 1 from public._client_functions() cf where not exists (select 1 from pg_proc p where p.proname = cf.fname and p.pronamespace = 'public'::regnamespace)),
            'every approved client function exists');
select t.ok(not exists (select 1 from public._client_functions() cf join pg_proc p on p.proname = cf.fname and p.pronamespace = 'public'::regnamespace where not has_function_privilege('authenticated', p.oid, 'EXECUTE')),
            'every approved client function is executable by signed-in clients');
select t.login('00000000-0000-0000-0000-0000000000a3');
select t.throws($$select * from public._booked_months('00000000-0000-0000-0000-0000000000c1')$$, 'permission denied', 'clients cannot call the internal booked-months helper (payment.read bypass closed)');
select t.throws($$select * from public._covered_months('00000000-0000-0000-0000-0000000000c1', false)$$, 'permission denied', 'clients cannot call the internal covered-months helper');
select t.throws($$select public._require('family.read')$$, 'permission denied', 'clients cannot call the internal permission helper');
select t.throws($$select public.month_index(current_date)$$, 'permission denied', 'clients cannot call internal date helpers');
select t.throws($$select * from public._client_functions()$$, 'permission denied', 'clients cannot read the approved-function list');
select t.logout();
set role anon;
select t.throws($$select public.has_permission('family.read')$$, 'permission denied', 'anon cannot execute has_permission');
select t.throws($$select public.register_family('Nope', null, null, 'father', '2026-01-01')$$, 'permission denied', 'anon cannot execute register_family');
select t.throws($$select * from public.record_payment(null, 'voluntary_donation', 100, 'cash')$$, 'permission denied', 'anon cannot execute record_payment');
select t.throws($$select * from public.family_balance('00000000-0000-0000-0000-0000000000c1')$$, 'permission denied', 'anon cannot execute family_balance');
reset role;
select t.corrupt($$grant execute on function public._booked_months(uuid) to authenticated$$,
  'C17', 'C17 catches an internal helper exposed to signed-in clients', false);
select t.corrupt($$grant execute on function public.has_permission(text) to anon$$,
  'C17', 'C17 catches a function exposed to the anonymous role', false);
select t.corrupt($$grant execute on function public._require(text) to public$$,
  'C17', 'C17 catches a function exposed to PUBLIC', false);
-- a platform default (e.g. Supabase's) that grants new functions to clients is caught
select t.corrupt($$create function public.new_unreviewed_helper() returns int language sql as 'select 1'; grant execute on function public.new_unreviewed_helper() to authenticated$$,
  'C17', 'C17 catches a new, unreviewed function that clients can execute', false);

-- and with our global default privileges, a new function starts out private
do $$
declare priv boolean;
begin
  begin
    create function public.zz_probe() returns int language sql as 'select 1';
    priv := has_function_privilege('authenticated', 'public.zz_probe()', 'EXECUTE')
         or has_function_privilege('anon', 'public.zz_probe()', 'EXECUTE');
    raise exception 't_rollback';
  exception when others then
    if sqlerrm <> 't_rollback' then
      insert into t.results values ('new functions start private', false, sqlerrm);
      return;
    end if;
  end;
  insert into t.results values ('new functions start private (not executable by clients by default)', not priv, null);
end $$;

-- ============================================================ read-only guarantee
select t.eq((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and (p.proname like '\_recon\_%' or p.proname like 'reconciliation%')
                and p.provolatile <> 's' and p.proname <> '_recon_catalog'),
            0::bigint, 'every reconciliation function is STABLE (PostgreSQL itself forbids writes inside)');
select t.ok((select provolatile = 'i' from pg_proc where proname = '_recon_catalog'), 'catalog is immutable (a constant list)');
select t.eq((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and (p.proname like '\_recon\_%' or p.proname like 'reconciliation%')
                and p.prosrc ~* '(insert\s+into|delete\s+from|update\s+public\.|truncate\s+|drop\s+(table|function|trigger)|alter\s+table|create\s+(table|index))'),
            0::bigint, 'no reconciliation function contains a data-changing statement');
select t.eq((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and (p.proname like '\_recon\_%' or p.proname like 'reconciliation%')
                and p.prosrc ~* 'family_balance|burial_eligib'),
            0::bigint, 'reconciliation never derives burial eligibility from balances');

-- run everything as authorised users, then prove nothing changed anywhere.
-- (counters are re-read here: the permission-matrix toggle above legitimately wrote audit rows)
select count(*) as n_ledger from public.ledger_entry \gset
select count(*) as n_receipt from public.receipt \gset
select count(*) as n_audit from public.audit_log \gset
select count(*) as n_verif from public.ledger_verification \gset
select count(*) as n_burial from public.burial_record \gset
select coalesce(sum(last_seq), 0) as counter_sum from public.receipt_counter \gset
select t.login('00000000-0000-0000-0000-0000000000a4');
select count(*) from public.reconciliation_report() \gset
select count(*) from public.reconciliation_violations() \gset
select t.logout();
select t.eq((select count(*) from public.ledger_entry), :n_ledger::bigint, 'read-only: ledger_entry unchanged by running reconciliation');
select t.eq((select count(*) from public.receipt), :n_receipt::bigint, 'read-only: receipt unchanged');
select t.eq((select count(*) from public.audit_log), :n_audit::bigint, 'read-only: audit_log unchanged (running reconciliation writes nothing)');
select t.eq((select count(*) from public.ledger_verification), :n_verif::bigint, 'read-only: ledger_verification unchanged');
select t.eq((select count(*) from public.burial_record), :n_burial::bigint, 'read-only: burial_record unchanged');
select t.eq((select coalesce(sum(last_seq), 0) from public.receipt_counter), :counter_sum::bigint, 'read-only: receipt counter unchanged');

-- the append-only protections still hold alongside the new functions
select t.throws($$update public.ledger_entry set amount_paisa = amount_paisa$$, 'append-only', 'ledger still rejects UPDATE');
select t.throws($$delete from public.receipt$$, 'append-only', 'receipt still rejects DELETE');
select t.throws($$delete from public.audit_log$$, 'append-only', 'audit_log still rejects DELETE');

-- ============================================================ deliberate corruption: every check catches its failure
-- Each row: the corruption is applied in a rolled-back sub-transaction; the named check must
-- report strictly more violations afterwards than before.

-- C1: reversals
select t.corrupt(format($$insert into public.ledger_entry (family_id, category, amount_paisa, period_start, period_end, payment_method, collected_by, reverses_entry_id) select family_id, category, -1, period_start, period_end, payment_method, collected_by, id from public.ledger_entry where id = '00000000-0000-0000-0000-0000000000d1'$$),
  'C1', 'C1 catches a reversal whose amount does not negate the original');
select t.corrupt(format($$insert into public.ledger_entry (family_id, category, amount_paisa, period_start, period_end, payment_method, collected_by, reverses_entry_id) select family_id, category, -5, period_start, period_end, payment_method, collected_by, %L from public.ledger_entry where id = %L$$, :'rev_id', :'rev_id'),
  'C1', 'C1 catches a reversal of a reversal');
select t.corrupt($$insert into public.ledger_entry (family_id, category, amount_paisa, period_start, period_end, payment_method, collected_by, reverses_entry_id) select (select id from public.family where id <> '00000000-0000-0000-0000-0000000000c1' limit 1), category, -amount_paisa, period_start, period_end, payment_method, collected_by, id from public.ledger_entry where id = '00000000-0000-0000-0000-0000000000d1'$$,
  'C1', 'C1 catches a reversal booked to a different family');
select t.corrupt($$insert into public.ledger_entry (family_id, category, amount_paisa, period_start, period_end, payment_method, collected_by, reverses_entry_id) select family_id, category, -amount_paisa, '2030-01-01', '2030-02-01', payment_method, collected_by, id from public.ledger_entry where id = '00000000-0000-0000-0000-0000000000d1'$$,
  'C1', 'C1 catches a reversal with a different period');
select t.corrupt($$insert into public.ledger_entry (family_id, category, amount_paisa, payment_method, collected_by, reverses_entry_id) values (null, 'voluntary_donation', -5, 'cash', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000beef')$$,
  'C1', 'C1 catches a reversal of a payment that does not exist');

-- C2: receipts
select t.corrupt(format($$delete from public.receipt where entry_id = %L$$, :'plain_e'),
  'C2', 'C2 catches a payment whose receipt was deleted');
select t.corrupt(format($$alter table public.receipt drop constraint receipt_entry_id_key; insert into public.receipt (receipt_year, receipt_seq, entry_id, issued_by) values (2099, 1, %L, '00000000-0000-0000-0000-0000000000a1')$$, :'plain_e'),
  'C2', 'C2 catches a payment with two receipts');
select t.corrupt(format($$insert into public.receipt (receipt_year, receipt_seq, entry_id, issued_by) values (2099, 1, %L, '00000000-0000-0000-0000-0000000000a1')$$, :'rev_id'),
  'C2', 'C2 catches a receipt issued for a reversal');

-- C3: receipt numbering
select t.corrupt(format($$alter table public.receipt drop constraint receipt_receipt_year_receipt_seq_key; insert into public.receipt (receipt_year, receipt_seq, entry_id, issued_by) select receipt_year, receipt_seq, %L, issued_by from public.receipt where entry_id = '00000000-0000-0000-0000-0000000000d1'$$, :'rev_id'),
  'C3', 'C3 catches a duplicated receipt number');
-- the counter is moved along with the receipt, so ONLY the gap detector can notice this one
select t.corrupt($$update public.receipt set receipt_seq = receipt_seq + 5 where entry_id = '00000000-0000-0000-0000-0000000000d1'; update public.receipt_counter set last_seq = last_seq + 5 where receipt_year = (select receipt_year from public.receipt where entry_id = '00000000-0000-0000-0000-0000000000d1')$$,
  'C3', 'C3 catches a gap in receipt numbering (counter kept consistent)');
select t.corrupt($$update public.receipt_counter set last_seq = 0$$,
  'C3', 'C3 catches a receipt counter that fell behind (next receipt would collide)', false);
select t.corrupt($$update public.receipt_counter set last_seq = last_seq + 7$$,
  'C3', 'C3 catches a receipt counter that ran ahead of the receipts', false);

-- C4: verifications
select t.corrupt(format($$insert into public.ledger_verification (entry_id, verified_by) values (%L, '00000000-0000-0000-0000-0000000000a4')$$, :'rev_id'),
  'C4', 'C4 catches the verification of a reversal entry');
select t.corrupt(format($$insert into public.ledger_verification (entry_id, verified_by, verified_at) values (%L, '00000000-0000-0000-0000-0000000000a4', now() - interval '30 days')$$, :'unver_e'),
  'C4', 'C4 catches a verification dated before the payment existed');
select t.corrupt(format($$insert into public.ledger_verification (entry_id, verified_by, verified_at) values (%L, '00000000-0000-0000-0000-0000000000a4', now() + interval '1 day')$$, :'rev_orig'),
  'C4', 'C4 catches the verification of a payment that was already reversed');

-- C5: independent coverage recomputation vs production derivation
select t.corrupt($c$create or replace function public._covered_months(p_family_id uuid, p_verified_only boolean) returns table (m date) language sql stable as $f$ select null::date where false $f$$c$,
  'C5', 'C5 catches a production derivation that loses coverage');
select t.corrupt($c$create or replace function public._covered_months(p_family_id uuid, p_verified_only boolean) returns table (m date) language sql stable as $f$ select (gs + interval '1 month')::date from public.ledger_entry e cross join lateral generate_series(e.period_start, e.period_end, interval '1 month') gs where e.family_id = p_family_id and e.category = 'membership_contribution' and e.amount_paisa > 0 and e.reverses_entry_id is null and not exists (select 1 from public.ledger_entry r where r.reverses_entry_id = e.id) $f$$c$,
  'C5', 'C5 catches a production derivation that is off by one month');
select t.corrupt($c$create or replace function public._covered_months(p_family_id uuid, p_verified_only boolean) returns table (m date) language sql stable as $f$ select distinct gs::date from public.ledger_entry e cross join lateral generate_series(e.period_start, e.period_end, interval '1 month') gs where e.family_id = p_family_id and e.category = 'membership_contribution' and e.amount_paisa > 0 $f$$c$,
  'C5', 'C5 catches a production derivation that counts reversed payments');

-- C6: payment shape
select t.corrupt(format($$insert into public.ledger_entry (family_id, category, amount_paisa, period_start, period_end, payment_method, collected_by) values ('00000000-0000-0000-0000-0000000000c1', 'membership_contribution', 30000, '2031-01-01', '2031-01-01', 'cash', '00000000-0000-0000-0000-0000000000a2')$$),
  'C6', 'C6 catches an amount that is not whole months at the rate');
select t.corrupt($$insert into public.ledger_entry (family_id, category, amount_paisa, period_start, period_end, payment_method, collected_by) values ('00000000-0000-0000-0000-0000000000c1', 'membership_contribution', 20000, '2020-01-01', '2020-01-01', 'cash', '00000000-0000-0000-0000-0000000000a2')$$,
  'C6', 'C6 catches months before the family joined');
select t.corrupt($$insert into public.ledger_entry (family_id, category, amount_paisa, period_start, period_end, payment_method, collected_by) values ('00000000-0000-0000-0000-0000000000c1', 'membership_contribution', 20000, '2032-01-01', '2032-01-01', 'cash', '00000000-0000-0000-0000-0000000000a2'); delete from public.rule_set where effective_from <= current_date$$,
  'C6', 'C6 catches a payment made when no rule was in effect');

-- C7: double booking
select t.corrupt($$insert into public.ledger_entry (family_id, category, amount_paisa, period_start, period_end, payment_method, collected_by) values ('00000000-0000-0000-0000-0000000000c1', 'membership_contribution', 20000, '2026-03-01', '2026-03-01', 'cash', '00000000-0000-0000-0000-0000000000a2')$$,
  'C7', 'C7 catches a month booked twice for one family');
select t.corrupt($$insert into public.ledger_entry (family_id, category, amount_paisa, period_start, period_end, payment_method, collected_by) values ('00000000-0000-0000-0000-0000000000c1', 'membership_contribution', 240000, '2026-12-01', '2027-11-01', 'cash', '00000000-0000-0000-0000-0000000000a2')$$,
  'C7', 'C7 catches an advance period that overlaps an existing one at its edge');

-- C8: non-member burial payments
select t.corrupt($$insert into public.ledger_entry (family_id, category, amount_paisa, payment_method, collected_by) values ('00000000-0000-0000-0000-0000000000c1', 'non_member_burial', 100, 'cash', '00000000-0000-0000-0000-0000000000a2')$$,
  'C8', 'C8 catches a non-member burial payment attached to a family');
select t.corrupt($$insert into public.ledger_entry (family_id, category, amount_paisa, period_start, period_end, payment_method, collected_by) values (null, 'non_member_burial', 100, '2026-01-01', '2026-01-01', 'cash', '00000000-0000-0000-0000-0000000000a2')$$,
  'C8', 'C8 catches a non-member burial payment carrying a contribution period');
select t.corrupt($$insert into public.ledger_entry (family_id, category, amount_paisa, payment_method, collected_by) values (null, 'non_member_burial', 100, 'cash', '00000000-0000-0000-0000-0000000000a2')$$,
  'C8', 'C8 lists a new unlinked non-member burial payment (observation)');

-- C9: burial payment links
select t.corrupt(format($$insert into public.burial_payment (burial_id, entry_id, linked_by) values (%L, '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a1')$$, :'nmbur'),
  'C9', 'C9 catches a burial linked to a membership payment');
select t.corrupt(format($$insert into public.burial_payment (burial_id, entry_id, linked_by) values (%L, %L, '00000000-0000-0000-0000-0000000000a1')$$, :'mbur', :'unlinked'),
  'C9', 'C9 catches a non-member payment linked to a registered member burial');
select t.corrupt(format($$update public.ledger_entry set family_id = '00000000-0000-0000-0000-0000000000c1' where id = %L$$, :'linked_e'),
  'C9', 'C9 catches a linked burial payment that was moved onto a family');
select t.corrupt(format($$alter table public.burial_record drop constraint burial_record_check; alter table public.burial_record drop constraint burial_record_check1; update public.burial_record set person_id = (select id from public.person limit 1), kind = 'non_member' where id = %L$$, :'mbur'),
  'C9', 'C9 catches a non-member burial that is attached to a person');

-- C10: category totals
select t.corrupt($$insert into public.ledger_entry (family_id, category, amount_paisa, period_start, period_end, payment_method, collected_by, reverses_entry_id) select family_id, category, -1, period_start, period_end, payment_method, collected_by, id from public.ledger_entry where id = '00000000-0000-0000-0000-0000000000d1'$$,
  'C10', 'C10 catches category totals that no longer net out after a bad reversal');

-- C11: ledger vs audit log
select t.corrupt(format($$update public.ledger_entry set amount_paisa = amount_paisa + 100 where id = %L$$, :'plain_e'),
  'C11', 'C11 catches a ledger amount changed after it was audited');
select t.corrupt(format($$delete from public.receipt where entry_id = %L; delete from public.ledger_entry where id = %L$$, :'plain_e', :'plain_e'),
  'C11', 'C11 catches a ledger row deleted after it was audited');
select t.corrupt($$insert into public.ledger_entry (family_id, category, amount_paisa, payment_method, collected_by) values (null, 'voluntary_donation', 777, 'cash', '00000000-0000-0000-0000-0000000000a2')$$,
  'C11', 'C11 catches a ledger row with no audit record of its creation');
select t.corrupt(format($$insert into public.audit_log (actor, action, table_name, record_id) values ('00000000-0000-0000-0000-0000000000a1', 'UPDATE', 'ledger_entry', %L)$$, :'plain_e'),
  'C11', 'C11 catches an audit record of a change to an append-only table');
select t.corrupt(format($$insert into public.audit_log (actor, action, table_name, record_id, new_data) select actor, action, table_name, record_id, new_data from public.audit_log where table_name = 'ledger_entry' and record_id = %L and action = 'INSERT'$$, :'plain_e'),
  'C11', 'C11 catches a duplicated creation record in the audit log');
select t.corrupt(format($$update public.receipt set receipt_seq = receipt_seq where false; update public.burial_record set burial_no = burial_no + 1000000 where id = %L$$, :'mbur'),
  'C11', 'C11 catches a burial register number changed after creation');
select t.corrupt($$insert into public.ledger_entry (family_id, category, amount_paisa, payment_method, collected_by) values (null, 'voluntary_donation', 5, 'cash', '00000000-0000-0000-0000-0000000000a2')$$,
  'C11A', 'C11A reports a ledger row created without an actor (observation)', false);

-- C13: protective triggers
select t.corrupt($$alter table public.ledger_entry disable trigger ledger_entry_no_mutation$$,
  'C13', 'C13 catches a disabled append-only trigger on the ledger', false);
select t.corrupt($$drop trigger receipt_audit on public.receipt$$,
  'C13', 'C13 catches a removed audit trigger', false);
select t.corrupt($$alter table public.family disable trigger family_no_delete$$,
  'C13', 'C13 catches a disabled never-delete trigger', false);
select t.corrupt($$drop trigger burial_payment_check on public.burial_payment$$,
  'C13', 'C13 catches a removed burial payment link validation trigger', false);

-- C14: row level security and privileges
select t.corrupt($$alter table public.ledger_entry disable row level security$$,
  'C14', 'C14 catches row level security switched off', false);
select t.corrupt($$grant insert on public.ledger_entry to authenticated$$,
  'C14', 'C14 catches direct write access granted to signed-in clients', false);
select t.corrupt($$grant select on public.family to anon$$,
  'C14', 'C14 catches table access granted to the anonymous role', false);
select t.corrupt($$grant update on public.receipt_counter to authenticated$$,
  'C14', 'C14 catches write access to the receipt counter', false);

-- C16: duplicate allocation
select t.corrupt(format($$alter table public.ledger_entry drop constraint ledger_entry_reverses_entry_id_key; insert into public.ledger_entry (family_id, category, amount_paisa, period_start, period_end, payment_method, collected_by, reverses_entry_id) select family_id, category, amount_paisa, period_start, period_end, payment_method, collected_by, reverses_entry_id from public.ledger_entry where id = %L$$, :'rev_id'),
  'C16', 'C16 catches a payment reversed twice');
select t.corrupt(format($$alter table public.ledger_verification drop constraint ledger_verification_entry_id_key; insert into public.ledger_verification (entry_id, verified_by) select entry_id, verified_by from public.ledger_verification where entry_id = %L$$, :'ver_e'),
  'C16', 'C16 catches a payment verified twice');
select t.corrupt(format($$alter table public.burial_payment drop constraint burial_payment_entry_id_key; insert into public.burial_payment (burial_id, entry_id, linked_by) select burial_id, entry_id, linked_by from public.burial_payment where entry_id = %L$$, :'linked_e'),
  'C16', 'C16 catches one payment allocated to a burial twice');

-- through the permission-checked API: a corruption is visible to an authorised user
select t.corrupt(format($$delete from public.receipt where entry_id = %L$$, :'plain_e'),
  'C2', 'API: an authorised user sees the C2 violation through reconciliation_violations()',
  true, '00000000-0000-0000-0000-0000000000a4');

-- ============================================================ all corruption was rolled back
select t.eq((select count(*) from public._recon_run() where severity <> 'info'), 0::bigint, 'after all corruption tests: data is clean again (everything rolled back)');
select t.eq((select count(*) from public.ledger_entry), :n_ledger::bigint, 'after corruption tests: ledger_entry row count restored');
select t.eq((select count(*) from public.receipt), :n_receipt::bigint, 'after corruption tests: receipt row count restored');
select t.eq((select count(*) from public.audit_log), :n_audit::bigint, 'after corruption tests: audit_log row count restored');
select t.eq((select amount_paisa from public.ledger_entry where id = '00000000-0000-0000-0000-0000000000d1'), 240000::bigint, 'after corruption tests: ledger amounts restored');
select t.ok((select relrowsecurity from pg_class where oid = 'public.ledger_entry'::regclass), 'after corruption tests: row level security still on');
select t.ok(not has_table_privilege('authenticated', 'public.ledger_entry', 'INSERT'), 'after corruption tests: no client write grant remains');
select t.eq((select count(*) from pg_trigger where tgname = 'receipt_audit'), 1::bigint, 'after corruption tests: dropped trigger was restored');
