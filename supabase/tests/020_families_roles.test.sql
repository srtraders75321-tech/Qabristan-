-- Families, transfers, and role management. All data is fictional.
-- Fixture users from 010_core_guards: a1 super_admin, a2 collection_officer.

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a5', 'cadmin@example.test'),
  ('00000000-0000-0000-0000-0000000000a6', 'general@example.test');
insert into public.committee_user (id, display_name) values
  ('00000000-0000-0000-0000-0000000000a5', 'Test Committee Admin'),
  ('00000000-0000-0000-0000-0000000000a6', 'Test General Member');
insert into public.role_grant (user_id, role) values
  ('00000000-0000-0000-0000-0000000000a5', 'committee_admin'),
  ('00000000-0000-0000-0000-0000000000a6', 'general_member');

-- committee admin registers a family and members --------------------------------
select t.login('00000000-0000-0000-0000-0000000000a5');
select public.register_family('Fictional Father', 'Fictional Grandfather', '1970-05-01', 'father', '2026-01-01') as fam \gset
select public.add_family_member(:'fam', 'Fictional Son', 'Fictional Father', '2000-03-03', 'son', '2026-01-01') as son \gset
select public.add_family_member(:'fam', 'Fictional Daughter', 'Fictional Father', '2002-04-04', 'daughter', '2026-01-01') as dau \gset
select t.logout();

select t.eq((select count(*) from public.family_member where family_id = :'fam'), 3::bigint, 'family has 3 members');
select t.ok((select head_person_id is not null from public.family where id = :'fam'), 'family has a head');
select t.eq((select family_no from public.family where id = :'fam') > 0, true, 'family_no assigned');

-- married son starts a new household ---------------------------------------------------
select t.login('00000000-0000-0000-0000-0000000000a5');
select public.transfer_member(:'son', '2026-07-01', 'father') as son_family \gset
select t.logout();

select t.eq((select count(*) from public.family_member where person_id = :'son'), 2::bigint, 'son: history keeps 2 rows');
select t.eq((select valid_to from public.family_member where person_id = :'son' and family_id = :'fam'),
            '2026-07-01'::date, 'son: old membership closed at transfer date');
select t.ok((select valid_to is null from public.family_member where person_id = :'son' and family_id = :'son_family'),
            'son: new membership is current');
select t.ok(:'son_family' <> :'fam', 'son: received a different family');
select t.eq((select head_person_id from public.family where id = :'son_family'), :'son'::uuid, 'son: heads the new household');
select t.ok((select family_no from public.family where id = :'son_family') > (select family_no from public.family where id = :'fam'),
            'son: new family number issued');

-- married daughter joins an existing family --------------------------------------------
select t.login('00000000-0000-0000-0000-0000000000a5');
select t.lives(format($$select public.transfer_member(%L, '2026-08-01', 'mother', %L)$$, :'dau', :'son_family'),
               'daughter: transfer to existing family works');
select t.throws(format($$select public.transfer_member(%L, '2026-09-01', 'mother', %L)$$, :'dau', :'son_family'),
                'already in that family', 'transfer: same family rejected');
select t.throws(format($$select public.transfer_member(%L, '2026-01-01', 'father')$$, :'son'),
                'after the current membership start', 'transfer: date before membership start rejected');
select t.logout();
select t.eq((select count(*) from public.family_member where person_id = :'dau'), 2::bigint, 'daughter: history keeps 2 rows');

-- a person can never be in two families at once (database-level) ------------------------
select t.throws(format($$insert into public.family_member (family_id, person_id, relation, valid_from)
                         values (%L, %L, 'other', '2026-09-01')$$, :'fam', :'son'),
                'conflicting key|exclusion', 'overlapping family membership rejected by constraint');

-- permissions ------------------------------------------------------------------------------
select t.login('00000000-0000-0000-0000-0000000000a6');   -- general member
select t.throws($$select public.register_family('Nope', null, null, 'father', '2026-01-01')$$,
                'permission denied', 'general member cannot register families');
select t.eq((select count(*) from public.family), 3::bigint, 'general member can read families (placeholder matrix)');
select t.logout();

select t.login('00000000-0000-0000-0000-0000000000a2');   -- collection officer
select t.throws($$select public.register_family('Nope', null, null, 'father', '2026-01-01')$$,
                'permission denied', 'collection officer cannot register families');
select t.throws($$select public.grant_role('00000000-0000-0000-0000-0000000000a6', 'treasurer')$$,
                'permission denied', 'collection officer cannot grant roles');
select t.logout();

-- roles -----------------------------------------------------------------------------------------
select t.login('00000000-0000-0000-0000-0000000000a1');   -- super admin
select t.lives($$select public.grant_role('00000000-0000-0000-0000-0000000000a6', 'treasurer')$$, 'super admin can grant a role');
select t.throws($$select public.grant_role('00000000-0000-0000-0000-0000000000a6', 'treasurer')$$,
                'duplicate|unique', 'duplicate active grant rejected');
select t.lives($$select public.revoke_role('00000000-0000-0000-0000-0000000000a6', 'treasurer')$$, 'super admin can revoke a role');
select t.throws($$select public.revoke_role('00000000-0000-0000-0000-0000000000a1', 'super_admin')$$,
                'last active super_admin', 'cannot revoke the last super admin');
select t.logout();

-- revoked role loses access immediately -----------------------------------------------------------
select t.login('00000000-0000-0000-0000-0000000000a6');
select t.throws($$select public.verify_payment('00000000-0000-0000-0000-000000000000')$$,
                'permission denied', 'revoked treasurer role has no payment.verify');
select t.logout();

-- deactivated staff lose access --------------------------------------------------------------------
update public.committee_user set active = false where id = '00000000-0000-0000-0000-0000000000a5';
select t.login('00000000-0000-0000-0000-0000000000a5');
select t.throws($$select public.register_family('Nope', null, null, 'father', '2026-01-01')$$,
                'permission denied', 'deactivated user cannot write');
select t.eq((select count(*) from public.family), 0::bigint, 'deactivated user sees nothing');
select t.logout();
update public.committee_user set active = true where id = '00000000-0000-0000-0000-0000000000a5';
