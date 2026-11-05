-- Payments, receipts, verification, reversal, balance. All data is fictional.
-- Users: a1 super_admin, a2 collection_officer, a4 treasurer (created here), a5 committee_admin.
-- Amounts: monthly rate PKR 200 = 20000 paisa; annual PKR 2,400 = 240000 paisa.

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000a4', 'treasurer@example.test');
insert into public.committee_user (id, display_name) values ('00000000-0000-0000-0000-0000000000a4', 'Test Treasurer');
insert into public.role_grant (user_id, role) values ('00000000-0000-0000-0000-0000000000a4', 'treasurer');

-- families via the real function ----------------------------------------------------------
select t.login('00000000-0000-0000-0000-0000000000a5');
select public.register_family('Pay Test Father One', null, null, 'father', '2026-01-01') as f1 \gset
select public.register_family('Pay Test Father Two', null, null, 'father', '2026-01-01') as f2 \gset
select public.register_family('Pay Test Father Three', null, null, 'father', '2026-01-01') as f3 \gset
select t.logout();

-- no rule yet -> payment refused, balance says rule not configured -------------------------------
select t.login('00000000-0000-0000-0000-0000000000a2');
select t.throws(format($$select * from public.record_payment(%L, 'membership_contribution', 240000, 'cash')$$, :'f1'),
                'no contribution rule', 'payment refused until a rule exists');
select t.logout();

-- rule: PKR 200/month, grace undecided (null) ------------------------------------------------------
select t.login('00000000-0000-0000-0000-0000000000a1');
select t.lives($$select public.create_rule_set('2000-01-01', 20000, null, false, 'test rule: grace undecided')$$, 'rule created');
select t.logout();

-- record a payment: annual -----------------------------------------------------------------------------
select t.login('00000000-0000-0000-0000-0000000000a2');
select o_entry_id as e1, o_receipt_year as yr, o_receipt_seq as seq1
  from public.record_payment(:'f1', 'membership_contribution', 240000, 'cash', 'annual 2026') \gset
select t.eq((select period_start from public.ledger_entry where id = :'e1'), '2026-01-01'::date, 'annual: starts at membership month');
select t.eq((select period_end from public.ledger_entry where id = :'e1'), '2026-12-01'::date, 'annual: covers 12 months');
select t.eq((select count(*) from public.receipt where entry_id = :'e1'), 1::bigint, 'annual: receipt issued');

-- non-multiples are rejected, never rounded (Q2) ------------------------------------------------------
select t.throws(format($$select * from public.record_payment(%L, 'membership_contribution', 25000, 'cash')$$, :'f1'),
                'exact multiple', 'non-multiple amount rejected');
select t.throws(format($$select * from public.record_payment(%L, 'membership_contribution', 0, 'cash')$$, :'f1'),
                'positive', 'zero amount rejected');
select t.throws(format($$select * from public.record_payment(%L, 'membership_contribution', -20000, 'cash')$$, :'f1'),
                'positive', 'negative amount rejected');

-- stacking: next payment continues after the booked months -------------------------------------------------
select o_entry_id as e2, o_receipt_seq as seq2
  from public.record_payment(:'f1', 'membership_contribution', 20000, 'bank_transfer') \gset
select t.eq((select period_start from public.ledger_entry where id = :'e2'), '2027-01-01'::date, 'stacking: next payment starts after covered months');
select t.eq(:'seq2'::int, :'seq1'::int + 1, 'receipt numbers are sequential');

-- multi-year advance ----------------------------------------------------------------------------------------------
select o_entry_id as e3 from public.record_payment(:'f2', 'membership_contribution', 720000, 'cash', 'three-year advance') \gset
select t.eq((select period_end from public.ledger_entry where id = :'e3'), '2028-12-01'::date, 'three-year advance covers 36 months');

-- other categories ------------------------------------------------------------------------------------------------
select o_entry_id as e4 from public.record_payment(null, 'non_member_burial', 500000, 'cash', 'fictional amount; fee undecided (D3)') \gset
select t.ok((select family_id is null and period_start is null from public.ledger_entry where id = :'e4'), 'non-member burial: no family, no period');
select t.eq((select count(*) from public.family), 6::bigint, 'non-member burial created no membership');
select o_entry_id as e5 from public.record_payment(:'f3', 'voluntary_donation', 123400, 'cash') \gset
select t.ok((select period_start is null from public.ledger_entry where id = :'e5'), 'donation: no period');
select t.logout();

-- balance statuses -----------------------------------------------------------------------------------------------------
select t.login('00000000-0000-0000-0000-0000000000a4');
select t.eq((select status from public.family_balance(:'f1', '2026-12-15')), 'advance', 'f1: advance (13 covered, 12 due)');
select t.eq((select balance_months from public.family_balance(:'f1', '2026-12-15')), 1, 'f1: balance +1 month');
select t.eq((select covered_until from public.family_balance(:'f1', '2026-12-15')), '2027-01-01'::date, 'f1: covered until Jan 2027');
select t.eq((select status from public.family_balance(:'f3', '2026-03-31')), 'rule_not_configured', 'f3: arrears but grace undecided -> rule_not_configured (no guessing)');
select t.eq((select balance_months from public.family_balance(:'f3', '2026-03-31')), -3, 'f3: 3 months in arrears');
select t.logout();

select t.login('00000000-0000-0000-0000-0000000000a1');
select t.lives($$select public.create_rule_set('2026-06-01', 20000, 2, false, 'test rule: 2 months grace')$$, 'second rule version created');
select t.logout();
select t.login('00000000-0000-0000-0000-0000000000a4');
select t.eq((select status from public.family_balance(:'f3', '2026-07-31')), 'overdue', 'f3: 7 months arrears with grace 2 -> overdue');
select t.eq((select grace_months from public.family_balance(:'f3', '2026-07-31')), 2, 'rule version in effect is used');
select t.eq((select status from public.family_balance(:'f3', '2026-03-31')), 'rule_not_configured', 'older date still uses the older rule version');
select t.logout();

-- burial is not affected by arrears: the balance function has no burial gate -------------------------------------------------
select t.ok(not exists (select 1 from pg_proc where proname ilike '%burial_eligib%'), 'no burial-eligibility function derived from arrears');

-- verification and reversal permissions ---------------------------------------------------------------------------------------------
select t.login('00000000-0000-0000-0000-0000000000a2');   -- collector
select t.throws(format($$select public.verify_payment(%L)$$, :'e1'), 'permission denied', 'collector cannot verify');
select t.throws(format($$select public.reverse_payment(%L, 'x')$$, :'e1'), 'permission denied', 'collector cannot reverse');
select t.logout();

select t.login('00000000-0000-0000-0000-0000000000a4');   -- treasurer
select t.lives(format($$select public.verify_payment(%L)$$, :'e1'), 'treasurer can verify');
select t.throws(format($$select public.verify_payment(%L)$$, :'e1'), 'already verified', 'double verification rejected');
select t.eq((select count(*) from public.ledger_verification where entry_id = :'e1'), 1::bigint, 'verification recorded separately');
select t.eq((select amount_paisa from public.ledger_entry where id = :'e1'), 240000::bigint, 'original entry untouched by verification');

-- reversal --------------------------------------------------------------------------------------------------------------------------------
select t.throws(format($$select public.reverse_payment(%L, '   ')$$, :'e2'), 'reason', 'reversal needs a reason');
select public.reverse_payment(:'e2', 'entered by mistake (test)') as r2 \gset
select t.eq((select amount_paisa from public.ledger_entry where id = :'r2'), -20000::bigint, 'reversal is a negative entry');
select t.eq((select reverses_entry_id from public.ledger_entry where id = :'r2'), :'e2'::uuid, 'reversal points at the original');
select t.eq((select amount_paisa from public.ledger_entry where id = :'e2'), 20000::bigint, 'original still on record');
select t.throws(format($$select public.reverse_payment(%L, 'again')$$, :'e2'), 'already been reversed', 'double reversal rejected');
select t.throws(format($$select public.verify_payment(%L)$$, :'e2'), 'reversed', 'cannot verify a reversed payment');
select t.eq((select covered_until from public.family_balance(:'f1', '2026-12-15')), '2026-12-01'::date, 'reversal removes coverage');
select t.eq((select status from public.family_balance(:'f1', '2026-12-15')), 'current', 'f1 back to current after reversal');
select t.eq((select count(*) from public.receipt where entry_id = :'e2'), 1::bigint, 'reversed payment keeps its receipt record');
select t.logout();

-- net ledger for f1 after reversing everything is zero --------------------------------------------------------------------------------
select t.login('00000000-0000-0000-0000-0000000000a4');
select public.reverse_payment(:'e1', 'reverse the rest (test)') as r1 \gset
select t.logout();
select t.eq((select coalesce(sum(amount_paisa), 0)::bigint from public.ledger_entry where family_id = :'f1'), 0::bigint,
            'f1: ledger nets to zero once every payment is reversed');
select t.eq((select count(*) from public.ledger_entry where family_id = :'f1'), 4::bigint, 'f1: all four rows (2 payments + 2 reversals) still on record');

-- a reversed month becomes a gap; later payments fill it but never overlap booked months -----------------------------------------------
select t.login('00000000-0000-0000-0000-0000000000a2');
select o_entry_id as g1 from public.record_payment(:'f3', 'membership_contribution', 20000, 'cash') \gset
select o_entry_id as g2 from public.record_payment(:'f3', 'membership_contribution', 20000, 'cash') \gset
select o_entry_id as g3 from public.record_payment(:'f3', 'membership_contribution', 20000, 'cash') \gset
select t.logout();
select t.login('00000000-0000-0000-0000-0000000000a4');
select public.reverse_payment(:'g1', 'gap test: reverse January') as gr \gset
select t.logout();
select t.login('00000000-0000-0000-0000-0000000000a2');
select t.throws(format($$select * from public.record_payment(%L, 'membership_contribution', 40000, 'cash')$$, :'f3'),
                'overlap', 'two months into a one-month gap is rejected');
select o_entry_id as g4 from public.record_payment(:'f3', 'membership_contribution', 20000, 'cash') \gset
select t.eq((select period_start from public.ledger_entry where id = :'g4'), '2026-01-01'::date, 'gap: single month fills January');
select o_entry_id as g5 from public.record_payment(:'f3', 'membership_contribution', 20000, 'cash') \gset
select t.eq((select period_start from public.ledger_entry where id = :'g5'), '2026-04-01'::date, 'after the gap is filled, stacking resumes at April');
select t.logout();

-- D5 switch: when verification is required for coverage, unverified payments do not count ----------------------------------------------
select t.login('00000000-0000-0000-0000-0000000000a1');
select t.lives($$select public.create_rule_set('2026-09-01', 20000, 2, true, 'test rule: verification required')$$, 'verification-required rule created');
select t.logout();
select t.login('00000000-0000-0000-0000-0000000000a4');
select t.eq((select months_covered from public.family_balance(:'f2', '2026-12-15')), 0, 'f2: unverified advance does not count when verification is required');
select t.eq((select status from public.family_balance(:'f2', '2026-12-15')), 'overdue', 'f2: overdue until verified');
select t.lives(format($$select public.verify_payment(%L)$$, :'e3'), 'f2 advance verified');
select t.eq((select months_covered from public.family_balance(:'f2', '2026-12-15')), 36, 'f2: verified advance counts in full');
select t.eq((select status from public.family_balance(:'f2', '2026-12-15')), 'advance', 'f2: advance once verified');
select t.logout();

-- every positive entry has exactly one receipt; receipts are unique ----------------------------------------------------------------------
select t.eq((select count(*) from public.receipt where entry_id in
              (:'e1', :'e2', :'e3', :'e4', :'e5', :'g1', :'g2', :'g3', :'g4', :'g5')), 10::bigint,
            'receipts: every recorded payment has one receipt');
select t.ok((select count(*) = count(distinct (receipt_year, receipt_seq)) from public.receipt), 'receipt numbers are unique');
select t.ok(not exists (select 1 from public.receipt r join public.ledger_entry e on e.id = r.entry_id where e.amount_paisa < 0),
            'no receipts are issued for reversal entries');
