-- Burial module tests. All data is fictional.
-- Users (earlier test files): a1 super_admin, a2 collection_officer, a3 outsider (not staff),
-- a4 treasurer, a5 committee_admin, a6 general_member. Placeholder permission matrix.
-- Dates assume the test runs on or after 2026-11-05.

-- ============================================================ fixtures: families and people
select t.login('00000000-0000-0000-0000-0000000000a5');
select public.register_family('Burial Test Father A', null, null, 'father', '2026-01-01') as fa \gset
select public.add_family_member(:'fa', 'Burial Test Son S', 'Burial Test Father A', '2000-01-01', 'son', '2026-01-01') as ps \gset
select public.add_family_member(:'fa', 'Burial Test Son T', 'Burial Test Father A', '2001-01-01', 'son', '2026-01-01') as pt \gset
select public.add_family_member(:'fa', 'Burial Test Person N', null, null, 'other', '2026-06-01') as pn \gset
select public.add_family_member(:'fa', 'Burial Test Person Q', null, null, 'other', '2026-01-01') as pq \gset
select public.add_family_member(:'fa', 'Burial Test Person R', null, '2026-06-01', 'other', '2026-06-01') as pr \gset
select public.add_family_member(:'fa', 'Burial Test Person V', null, null, 'other', '2026-01-01') as pv \gset
select public.transfer_member(:'ps', '2026-07-01', 'father') as fb \gset
select public.transfer_member(:'pt', '2026-07-01', 'father') as fc \gset
select t.logout();
update public.person set date_of_death = '2026-05-01' where id = :'pq';

-- ============================================================ registered persons and history
select t.login('00000000-0000-0000-0000-0000000000a5');
select public.register_burial_for_member(:'ps', '2026-09-01', '2026-09-02', 'Section A / Row 1 / Grave 7', 'fictional note') as bs \gset
select public.register_burial_for_member(:'pt', '2026-03-01', '2026-03-02', 'Section A / Row 1 / Grave 8') as bt \gset
select public.register_burial_for_member(:'pn', '2026-02-01', '2026-02-02') as bn \gset
select t.logout();

select t.eq((select kind from public.burial_record where id = :'bs'), 'registered_person', 'member burial: kind');
select t.eq((select family_id from public.burial_record where id = :'bs'), :'fb'::uuid, 'member burial: family is the membership on the date of death (after transfer)');
select t.eq((select family_no_at_burial from public.burial_record where id = :'bs'), (select family_no from public.family where id = :'fb'), 'member burial: family number snapshot');
select t.eq((select deceased_name from public.burial_record where id = :'bs'), 'Burial Test Son S', 'member burial: name snapshot from person record');
select t.eq((select date_of_death from public.person where id = :'ps'), '2026-09-01'::date, 'member burial: date of death written to the person record');
select t.eq((select family_id from public.burial_record where id = :'bt'), :'fa'::uuid, 'member burial: death before a later transfer links the earlier family (history respected)');
select t.eq((select count(*) from public.family_member where person_id = :'pt'), 2::bigint, 'member burial: membership history untouched');
select t.ok((select valid_to is null from public.family_member where person_id = :'ps' and family_id = :'fb'), 'member burial: membership is not closed or deleted by a burial');
select t.ok((select family_id is null and family_no_at_burial is null from public.burial_record where id = :'bn'), 'member burial: no membership on that date -> family left null, burial still recorded');

-- ============================================================ validation and edge cases
select t.login('00000000-0000-0000-0000-0000000000a5');
select t.throws(format($$select public.register_burial_for_member(%L, '2026-09-01', '2026-09-02')$$, :'ps'), 'already has a burial', 'duplicate burial for the same person rejected');
select t.throws(format($$select public.register_burial_for_member(%L, '2026-05-02', '2026-05-03')$$, :'pq'), 'different date of death', 'conflicting date of death on person record rejected');
select t.lives(format($$select public.register_burial_for_member(%L, '2026-05-01', '2026-05-01')$$, :'pq'), 'matching date of death accepted; burial on the day of death accepted');
select t.throws(format($$select public.register_burial_for_member(%L, current_date + 1, current_date + 2)$$, :'pv'), 'future', 'future date of death rejected');
select t.throws(format($$select public.register_burial_for_member(%L, '2026-04-30', '2026-04-29')$$, :'pv'), 'check constraint', 'burial before death rejected');
select t.throws(format($$select public.register_burial_for_member(%L, '2026-05-01', '2026-05-02')$$, :'pr'), 'check constraint', 'death before birth rejected');
select t.throws($$select public.register_burial_for_member('00000000-0000-0000-0000-00000000dead', '2026-05-01', '2026-05-02')$$, 'person not found', 'unknown person rejected');
select t.throws(format($$select public.register_burial_for_member(%L, '2026-05-01', '2026-05-02', '   ')$$, :'pv'), 'check constraint', 'blank grave reference rejected');
select t.lives(format($$select public.register_burial_for_member(%L, current_date, current_date)$$, :'pv'), 'death and burial today accepted');
select t.logout();

-- void frees the person; re-registration allowed, original kept
select t.login('00000000-0000-0000-0000-0000000000a1');
select id as bv from public.burial_record where person_id = :'pv' \gset
select t.throws(format($$select public.void_burial(%L, '  ')$$, :'bv'), 'reason', 'void needs a reason');
select t.lives(format($$select public.void_burial(%L, 'entered against the wrong person (test)')$$, :'bv'), 'super admin can void');
select t.throws(format($$select public.void_burial(%L, 'again')$$, :'bv'), 'not found or already voided', 'double void rejected');
select t.logout();
select t.login('00000000-0000-0000-0000-0000000000a5');
select t.lives(format($$select public.register_burial_for_member(%L, current_date, current_date)$$, :'pv'), 'person can be re-registered after the old record was voided');
select t.throws(format($$select public.update_burial_details(%L, current_date, 'x', null)$$, :'bv'), 'not found or voided', 'voided record cannot be updated');
select t.throws(format($$select public.record_burial_approval(%L, 'approved')$$, :'bv'), 'not found or voided', 'voided record cannot be approved');
select t.logout();
select t.eq((select count(*) from public.burial_record where person_id = :'pv'), 2::bigint, 'voided record is kept alongside the new one');
select t.eq((select status from public.burial_record where id = :'bv'), 'voided', 'voided status stored');

-- ============================================================ burial is independent of financial balance
select t.login('00000000-0000-0000-0000-0000000000a5');
select public.register_family('Burial Test Father Arrears', null, null, 'father', '2026-01-01') as fo \gset
select public.add_family_member(:'fo', 'Burial Test Member O', null, null, 'other', '2026-01-01') as po \gset
select t.logout();
select t.login('00000000-0000-0000-0000-0000000000a4');
select t.eq((select status from public.family_balance(:'fo', current_date)), 'overdue', 'arrears family is overdue');
select t.logout();
select t.login('00000000-0000-0000-0000-0000000000a5');
select t.lives(format($$select public.register_burial_for_member(%L, '2026-10-01', '2026-10-02')$$, :'po'), 'burial is recorded for a family in arrears (no automatic eligibility rule)');
select t.logout();
select t.ok(not exists (
    select 1 from pg_proc
     where proname in ('register_burial_for_member', 'register_burial_non_member', 'update_burial_details',
                       'correct_non_member_deceased', 'void_burial', 'record_burial_approval')
       and prosrc ~* 'ledger|family_balance|_covered_months|_booked_months|rule_set'),
  'burial functions never read the ledger, balances, or rules');

-- ============================================================ non-members
select count(*) as n_person from public.person \gset
select count(*) as n_family from public.family \gset
select count(*) as n_member from public.family_member \gset

select t.login('00000000-0000-0000-0000-0000000000a5');
select public.register_burial_non_member('Fictional Stranger One', 'Fictional Father X', '1950-02-02', '2026-10-10', '2026-10-11', 'Section B / Row 2 / Grave 1') as nm1 \gset
select t.throws($$select public.register_burial_non_member('  fictional STRANGER one ', 'fictional father x', null, '2026-10-10', '2026-10-11')$$, 'possible duplicate', 'duplicate non-member detected (case and spacing ignored)');
select t.lives($$select public.register_burial_non_member('Fictional Stranger One', 'Fictional Father X', null, '2026-10-10', '2026-10-11', null, 'confirmed by staff', true)$$, 'duplicate can be recorded once explicitly confirmed');
select t.lives($$select public.register_burial_non_member('Fictional Stranger One', 'Fictional Father X', null, '2026-10-12', '2026-10-12')$$, 'different date of death is not a duplicate');
select t.lives($$select public.register_burial_non_member('Fictional Stranger One', 'Someone Else', null, '2026-10-10', '2026-10-11')$$, 'different father is not a duplicate');
select t.throws($$select public.register_burial_non_member('Fictional Stranger Two', null, null, current_date + 1, current_date + 1)$$, 'future', 'non-member: future death rejected');
select t.logout();

select t.eq((select count(*) from public.person), :n_person::bigint, 'non-member burials create no person');
select t.eq((select count(*) from public.family), :n_family::bigint, 'non-member burials create no family');
select t.eq((select count(*) from public.family_member), :n_member::bigint, 'non-member burials create no membership');
select t.ok((select person_id is null and family_id is null from public.burial_record where id = :'nm1'), 'non-member record has no person or family');

-- ============================================================ non-member payments
select t.login('00000000-0000-0000-0000-0000000000a2');
select o_entry_id as pe1, o_receipt_year as py, o_receipt_seq as pseq from public.record_burial_payment(:'nm1', 500000, 'cash', 'fictional amount; fee undecided') \gset
select t.logout();
select t.eq((select category::text from public.ledger_entry where id = :'pe1'), 'non_member_burial', 'payment recorded as non_member_burial');
select t.ok((select family_id is null from public.ledger_entry where id = :'pe1'), 'payment has no family');
select t.eq((select count(*) from public.receipt where entry_id = :'pe1'), 1::bigint, 'payment received a receipt');
select t.eq((select count(*) from public.burial_payment where burial_id = :'nm1' and entry_id = :'pe1'), 1::bigint, 'payment linked to the burial');
select t.eq((select count(*) from public.family), :n_family::bigint, 'payment created no family');
select t.eq((select count(*) from public.person), :n_person::bigint, 'payment created no person');

select t.login('00000000-0000-0000-0000-0000000000a2');
select t.throws(format($$select * from public.record_burial_payment(%L, 0, 'cash')$$, :'nm1'), 'positive', 'zero payment rejected');
select t.throws(format($$select * from public.record_burial_payment(%L, -100, 'cash')$$, :'nm1'), 'positive', 'negative payment rejected');
select t.throws(format($$select * from public.record_burial_payment(%L, 100000, 'cash')$$, :'bs'), 'only recorded here for non-member', 'no payment is recorded against a registered member burial');
select t.lives(format($$select * from public.record_burial_payment(%L, 100000, 'bank_transfer')$$, :'nm1'), 'a second payment can be linked (no amount or count rule invented)');
select t.logout();

select t.login('00000000-0000-0000-0000-0000000000a5');   -- committee admin: no payment.record
select t.throws(format($$select * from public.record_burial_payment(%L, 100000, 'cash')$$, :'nm1'), 'permission denied', 'committee admin cannot record payments (placeholder matrix)');
select t.logout();
select t.login('00000000-0000-0000-0000-0000000000a6');
select t.throws(format($$select * from public.record_burial_payment(%L, 100000, 'cash')$$, :'nm1'), 'permission denied', 'general member cannot record payments');
select t.logout();

-- link integrity (superuser, bypassing functions)
select t.login('00000000-0000-0000-0000-0000000000a2');
select o_entry_id as don from public.record_payment(null, 'voluntary_donation', 1000, 'cash') \gset
select t.logout();
select t.throws(format($$insert into public.burial_payment (burial_id, entry_id, linked_by) values (%L, %L, '00000000-0000-0000-0000-0000000000a1')$$, :'nm1', :'don'), 'only a positive non_member_burial', 'a donation entry cannot be linked to a burial');
select t.throws(format($$insert into public.burial_payment (burial_id, entry_id, linked_by) values (%L, %L, '00000000-0000-0000-0000-0000000000a1')$$, :'nm1', :'pe1'), 'duplicate|unique', 'a ledger entry cannot be linked twice');
select t.throws(format($$insert into public.burial_payment (burial_id, entry_id, linked_by) values (%L, '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a1')$$, :'nm1'), 'only a positive non_member_burial', 'only non_member_burial ledger entries can be linked');
select t.throws(format($$insert into public.burial_payment (burial_id, entry_id, linked_by) values (%L, %L, '00000000-0000-0000-0000-0000000000a1')$$, :'bs', :'pe1'), 'duplicate|unique|non-member', 'payments cannot be linked to a member burial');

-- reversing the payment leaves the burial and the link intact
select t.login('00000000-0000-0000-0000-0000000000a4');
select t.lives(format($$select public.reverse_payment(%L, 'test reversal')$$, :'pe1'), 'treasurer can reverse a burial payment in the ledger');
select t.logout();
select t.eq((select count(*) from public.burial_payment where entry_id = :'pe1'), 1::bigint, 'link survives reversal (history kept)');
select t.eq((select status from public.burial_record where id = :'nm1'), 'recorded', 'burial not affected by payment reversal');

-- ============================================================ approvals (records only)
select t.login('00000000-0000-0000-0000-0000000000a5');
select count(*) as n_before from public.burial_overview where latest_decision is null and id = :'nm1' \gset
select t.eq(:n_before::bigint, 1::bigint, 'burial exists with no approval (no approval rule enforced)');
select t.lives(format($$select public.update_burial_details(%L, '2026-10-11', 'Section B / Row 2 / Grave 2', 'moved')$$, :'nm1'), 'burial can be edited without any approval');
select public.record_burial_approval(:'nm1', 'rejected', '2026-10-11', 'Fictional Chairman', 'Meeting 12', 'test') as ap1 \gset
select public.record_burial_approval(:'nm1', 'approved', '2026-10-12', 'Fictional Chairman; Fictional Secretary', 'Meeting 13', null) as ap2 \gset
select t.throws(format($$select public.record_burial_approval(%L, 'maybe')$$, :'nm1'), 'check constraint', 'unknown decision value rejected');
select t.throws(format($$select public.record_burial_approval(%L, 'approved', current_date, '   ')$$, :'nm1'), 'check constraint', 'blank approver names rejected');
select t.logout();
select t.eq((select count(*) from public.burial_approval where burial_id = :'nm1'), 2::bigint, 'multiple approval records kept (no limit invented)');
select t.eq((select latest_decision from public.burial_overview where id = :'nm1'), 'approved', 'overview shows the latest decision');
select t.eq((select approval_count from public.burial_overview where id = :'nm1'), 2::bigint, 'overview counts approval records');
select t.eq((select status from public.burial_record where id = :'nm1'), 'recorded', 'approval or rejection does not change burial status');
select t.throws(format($$update public.burial_approval set decision = 'approved' where id = %L$$, :'ap1'), 'append-only', 'approval record cannot be edited');
select t.throws($$delete from public.burial_approval$$, 'append-only', 'approval record cannot be deleted');
select t.throws($$truncate public.burial_approval$$, 'append-only', 'approval table cannot be truncated');

select t.login('00000000-0000-0000-0000-0000000000a2');
select t.throws(format($$select public.record_burial_approval(%L, 'approved')$$, :'nm1'), 'permission denied', 'collection officer cannot record approvals');
select t.logout();
select t.login('00000000-0000-0000-0000-0000000000a4');
select t.throws(format($$select public.record_burial_approval(%L, 'approved')$$, :'nm1'), 'permission denied', 'treasurer cannot record approvals (placeholder matrix)');
select t.logout();

-- ============================================================ corrections and audit
select t.login('00000000-0000-0000-0000-0000000000a5');
select t.lives(format($$select public.correct_non_member_deceased(%L, 'Fictional Stranger One (corrected)', 'Fictional Father X', '1950-02-02', '2026-10-10')$$, :'nm1'), 'non-member details can be corrected');
select t.throws(format($$select public.correct_non_member_deceased(%L, 'X', null, null, '2026-10-10')$$, :'bs'), 'not found or voided', 'registered-person details cannot be corrected through the non-member function');
select t.throws(format($$select public.update_burial_details(%L, '2026-10-09', null, null)$$, :'nm1'), 'check constraint', 'burial date before death rejected on update');
select t.logout();
select t.eq((select deceased_name from public.burial_record where id = :'nm1'), 'Fictional Stranger One (corrected)', 'correction stored');

select t.ok(exists (select 1 from public.audit_log
                     where table_name = 'burial_record' and action = 'UPDATE' and record_id = :'nm1'
                       and old_data ->> 'deceased_name' = 'Fictional Stranger One'
                       and new_data ->> 'deceased_name' = 'Fictional Stranger One (corrected)'
                       and actor = '00000000-0000-0000-0000-0000000000a5'),
  'audit: correction recorded with old and new values and the actor');
select t.ok(exists (select 1 from public.audit_log
                     where table_name = 'burial_record' and action = 'UPDATE' and record_id = :'nm1'
                       and old_data ->> 'grave_reference' = 'Section B / Row 2 / Grave 1'
                       and new_data ->> 'grave_reference' = 'Section B / Row 2 / Grave 2'),
  'audit: grave reference change recorded');
select t.ok(exists (select 1 from public.audit_log where table_name = 'burial_approval' and action = 'INSERT' and record_id = :'ap2'), 'audit: approval recorded');
select t.ok(exists (select 1 from public.audit_log where table_name = 'burial_payment' and action = 'INSERT'), 'audit: payment link recorded');
select t.ok(exists (select 1 from public.audit_log where table_name = 'burial_record' and action = 'UPDATE' and new_data ->> 'status' = 'voided' and old_data ->> 'status' = 'recorded'), 'audit: void recorded');
select t.eq((select count(*) from public.audit_log where table_name = 'burial_record' and action = 'INSERT' and actor is null), 0::bigint, 'audit: every burial insert has an actor');

-- ============================================================ immutability (even for the database owner)
select t.throws($$delete from public.burial_record$$, 'never deleted', 'burial_record: DELETE rejected');
select t.throws(format($$delete from public.burial_record where id = %L$$, :'bn'), 'never deleted', 'burial_record: DELETE rejected even for a record with no linked rows');
select t.throws($$truncate public.burial_record cascade$$, 'never deleted', 'burial_record: TRUNCATE rejected');
select t.throws(format($$update public.burial_record set kind = 'non_member' where id = %L$$, :'bs'), 'immutable|check constraint', 'kind cannot change');
select t.throws(format($$update public.burial_record set person_id = %L where id = %L$$, :'pt', :'bs'), 'immutable|duplicate|unique', 'person link cannot change');
select t.throws(format($$update public.burial_record set burial_no = 999999 where id = %L$$, :'bs'), 'immutable', 'burial number cannot change');
select t.throws(format($$update public.burial_record set family_id = %L where id = %L$$, :'fa', :'bs'), 'immutable', 'family snapshot cannot change');
select t.throws(format($$update public.burial_record set deceased_name = 'Renamed' where id = %L$$, :'bs'), 'come from the person record', 'registered person details cannot be edited on the burial');
select t.throws(format($$update public.burial_record set status = 'voided' where id = %L$$, :'bs'), 'check constraint', 'void without reason/actor rejected by constraint');
select t.throws(format($$update public.burial_record set status = 'recorded', void_reason = null, voided_by = null, voided_at = null where id = %L$$, :'bv'), 'voided burial record cannot be changed', 'a voided record cannot be restored');
select t.throws($$update public.burial_payment set burial_id = burial_id$$, 'append-only', 'burial_payment: UPDATE rejected');
select t.throws($$delete from public.burial_payment$$, 'append-only', 'burial_payment: DELETE rejected');

-- ============================================================ authorization and RLS
select t.login('00000000-0000-0000-0000-0000000000a6');   -- general member: read-only
select t.ok((select count(*) from public.burial_record) > 0, 'general member can read burial records (placeholder matrix)');
select t.eq((select count(*) from public.ledger_entry), 0::bigint, 'general member cannot read the ledger');
select t.throws($$select public.register_burial_non_member('Nope', null, null, '2026-10-10', '2026-10-11')$$, 'permission denied', 'general member cannot register burials');
select t.throws(format($$select public.register_burial_for_member(%L, '2026-10-10', '2026-10-11')$$, :'pr'), 'permission denied', 'general member cannot register member burials');
select t.throws(format($$select public.update_burial_details(%L, '2026-10-11', null, null)$$, :'nm1'), 'permission denied', 'general member cannot update');
select t.throws(format($$select public.void_burial(%L, 'x')$$, :'nm1'), 'permission denied', 'general member cannot void');
select t.logout();

select t.login('00000000-0000-0000-0000-0000000000a5');   -- committee admin cannot void (placeholder)
select t.throws(format($$select public.void_burial(%L, 'x')$$, :'nm1'), 'permission denied', 'committee admin cannot void (needs burial.void)');
select t.logout();

select t.login('00000000-0000-0000-0000-0000000000a3');   -- not staff
select t.eq((select count(*) from public.burial_record), 0::bigint, 'non-staff sees no burial records');
select t.eq((select count(*) from public.burial_approval), 0::bigint, 'non-staff sees no approvals');
select t.eq((select count(*) from public.burial_payment), 0::bigint, 'non-staff sees no payment links');
select t.eq((select count(*) from public.burial_overview), 0::bigint, 'non-staff sees nothing through the overview');
select t.throws($$select public.register_burial_non_member('Nope', null, null, '2026-10-10', '2026-10-11')$$, 'permission denied', 'non-staff cannot register burials');
select t.logout();

select t.login('00000000-0000-0000-0000-0000000000a5');   -- direct DML is not possible even for staff
select t.throws($$insert into public.burial_record (kind, deceased_name, date_of_death, burial_date, created_by) values ('non_member', 'Direct', '2026-01-01', '2026-01-01', '00000000-0000-0000-0000-0000000000a5')$$, 'permission denied', 'staff cannot INSERT burial rows directly');
select t.throws(format($$update public.burial_record set notes = 'x' where id = %L$$, :'nm1'), 'permission denied', 'staff cannot UPDATE burial rows directly');
select t.throws($$delete from public.burial_record$$, 'permission denied', 'staff cannot DELETE burial rows');
select t.throws($$insert into public.burial_approval (burial_id, decision, recorded_by) values (null, 'approved', null)$$, 'permission denied', 'staff cannot INSERT approvals directly');
select t.logout();

set role anon;
select t.throws($$select * from public.burial_record$$, 'permission denied', 'anon: no access to burial records');
select t.throws($$select * from public.burial_overview$$, 'permission denied', 'anon: no access to the overview');
reset role;

-- permission matrix is configurable: removing a permission takes effect immediately
delete from public.role_permission where role = 'committee_admin' and permission = 'burial.write';
select t.login('00000000-0000-0000-0000-0000000000a5');
select t.throws($$select public.register_burial_non_member('Matrix Test', null, null, '2026-10-10', '2026-10-11')$$, 'permission denied', 'matrix: removed permission blocks the write immediately');
select t.logout();
insert into public.role_permission (role, permission) values ('committee_admin', 'burial.write');
select t.login('00000000-0000-0000-0000-0000000000a5');
select t.lives($$select public.register_burial_non_member('Matrix Test', null, null, '2026-10-10', '2026-10-11')$$, 'matrix: restored permission works again');
select t.logout();

-- deactivated staff
update public.committee_user set active = false where id = '00000000-0000-0000-0000-0000000000a5';
select t.login('00000000-0000-0000-0000-0000000000a5');
select t.throws($$select public.register_burial_non_member('Inactive', null, null, '2026-10-10', '2026-10-11')$$, 'permission denied', 'deactivated user cannot register burials');
select t.eq((select count(*) from public.burial_record), 0::bigint, 'deactivated user sees no burials');
select t.logout();
update public.committee_user set active = true where id = '00000000-0000-0000-0000-0000000000a5';

-- ============================================================ numbering and growth
select t.ok((select count(*) = count(distinct burial_no) from public.burial_record), 'burial numbers are unique');
select t.ok((select max(burial_no) - min(burial_no) + 1 >= count(*) from public.burial_record), 'burial numbers are never reused');
insert into public.burial_record (kind, deceased_name, date_of_death, burial_date, created_by)
select 'non_member', 'Bulk Fictional ' || g, date '2025-01-01', date '2025-01-02', '00000000-0000-0000-0000-0000000000a5'
  from generate_series(1, 3000) g;
select t.login('00000000-0000-0000-0000-0000000000a5');
select t.throws($$select public.register_burial_non_member('bulk fictional 1500', null, null, '2025-01-01', '2025-01-02')$$, 'possible duplicate', 'duplicate detection still works with thousands of records');
select t.logout();
select t.ok(exists (select 1 from pg_indexes where indexname = 'burial_record_name_idx'), 'name lookup is indexed');
