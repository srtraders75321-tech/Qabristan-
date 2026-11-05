-- Financial reconciliation checks.
--
-- READ-ONLY by construction: every function here is declared STABLE, and PostgreSQL
-- rejects INSERT/UPDATE/DELETE/DDL inside a STABLE function. Nothing in this migration
-- changes, and nothing here is able to change, ledger, receipt, audit, or burial data.
-- A discrepancy is repaired only through the existing append-only functions
-- (reverse_payment etc.), never by reconciliation itself.
--
-- Each check returns one row per violation: (check_id, severity, record_type, record_id, detail).
-- An empty result means the check passes. Severities: critical, high, medium, info.
-- 'info' rows are observations that depend on an undecided committee policy.
--
-- Access: reconciliation_report() and reconciliation_violations() require the permission
-- 'reconcile.run' (held by whichever roles the permission matrix, role_permission, grants it
-- to; D1 is undecided). The _recon_* functions are internal and not callable by clients.
--
-- Not implemented in this phase (see docs/RECONCILIATION.md): C12 (family membership
-- overlap, already enforced by an exclusion constraint) and C15 (staff/role consistency).

-- Reconciliation joins the audit log by (table, record) on every run.
create index if not exists audit_log_table_record_idx on public.audit_log (table_name, record_id);

-- ---------------------------------------------------------------- C1 reversals
create function public._recon_c1()
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language sql stable security definer set search_path = public, pg_temp
as $$
  select 'C1', 'critical', 'ledger_entry', x.id::text, x.problem
  from (
    select r.id,
           case
             when r.reverses_entry_id is null and r.amount_paisa < 0 then 'negative entry without an original'
             when r.reverses_entry_id is not null and r.amount_paisa >= 0 then 'reversal with a non-negative amount'
             when o.id is null then 'reversal references a missing original'
             when o.reverses_entry_id is not null then 'reversal points at another reversal'
             when o.amount_paisa <= 0 then 'original is not a positive payment'
             when r.amount_paisa <> -o.amount_paisa
               then format('amount %s does not negate the original %s', r.amount_paisa, o.amount_paisa)
             when r.family_id is distinct from o.family_id then 'family differs from the original'
             when r.category <> o.category then 'category differs from the original'
             when r.period_start is distinct from o.period_start
               or r.period_end is distinct from o.period_end then 'period differs from the original'
             when r.created_at < o.created_at then 'reversal predates its original'
           end as problem
    from public.ledger_entry r
    left join public.ledger_entry o on o.id = r.reverses_entry_id
    where r.reverses_entry_id is not null or r.amount_paisa < 0
  ) x
  where x.problem is not null
$$;

-- ---------------------------------------------------------------- C2 receipts match payments
create function public._recon_c2()
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language sql stable security definer set search_path = public, pg_temp
as $$
  select 'C2', 'critical', 'ledger_entry', p.id::text,
         format('payment has %s receipts (expected exactly 1)', p.n)
  from (select e.id, count(rc.id) as n
          from public.ledger_entry e
          left join public.receipt rc on rc.entry_id = e.id
         where e.amount_paisa > 0
         group by e.id) p
  where p.n <> 1
  union all
  select 'C2', 'critical', 'receipt', rc.id::text,
         case when e.id is null then 'receipt references a missing ledger entry'
              else 'receipt was issued for a reversal entry' end
  from public.receipt rc
  left join public.ledger_entry e on e.id = rc.entry_id
  where e.id is null or e.amount_paisa <= 0
$$;

-- ---------------------------------------------------------------- C3 receipt numbering
create function public._recon_c3()
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language sql stable security definer set search_path = public, pg_temp
as $$
  select 'C3', 'critical', 'receipt', rc.receipt_year::text || '/' || rc.receipt_seq::text,
         format('receipt number issued %s times', count(*))
  from public.receipt rc
  group by rc.receipt_year, rc.receipt_seq
  having count(*) > 1
  union all
  select 'C3', 'high', 'receipt_year', y.receipt_year::text,
         format('numbering gap: %s distinct numbers but the highest is %s', y.n, y.mx)
  from (select receipt_year, count(distinct receipt_seq) as n, max(receipt_seq) as mx
          from public.receipt group by receipt_year) y
  where y.n <> y.mx
  union all
  select 'C3', 'critical', 'receipt_counter', y.receipt_year::text,
         case when c.receipt_year is null then 'no counter row for a year that has receipts'
              else format('counter %s is behind the highest receipt number %s (the next receipt would collide)',
                          c.last_seq, y.mx) end
  from (select receipt_year, max(receipt_seq) as mx from public.receipt group by receipt_year) y
  left join public.receipt_counter c on c.receipt_year = y.receipt_year
  where c.receipt_year is null or c.last_seq < y.mx
  union all
  select 'C3', 'high', 'receipt_counter', y.receipt_year::text,
         format('counter %s is ahead of the highest receipt number %s', c.last_seq, y.mx)
  from (select receipt_year, max(receipt_seq) as mx from public.receipt group by receipt_year) y
  join public.receipt_counter c on c.receipt_year = y.receipt_year
  where c.last_seq > y.mx
$$;

-- ---------------------------------------------------------------- C4 verifications
create function public._recon_c4()
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language sql stable security definer set search_path = public, pg_temp
as $$
  select 'C4', 'high', 'ledger_verification', x.id::text, x.problem
  from (
    select v.id,
           case
             when e.id is null then 'verification of a missing entry'
             when e.amount_paisa <= 0 then 'verification of a reversal entry'
             when v.verified_at < e.created_at then 'verified before the payment was collected'
             when exists (select 1 from public.ledger_entry r
                           where r.reverses_entry_id = e.id and r.created_at <= v.verified_at)
               then 'payment had already been reversed when it was verified'
           end as problem
    from public.ledger_verification v
    left join public.ledger_entry e on e.id = v.entry_id
  ) x
  where x.problem is not null
$$;

-- ---------------------------------------------------------------- C5 independent coverage recomputation
-- Recomputes each family's covered months WITHOUT calling the production helpers
-- (_covered_months / month_index): month numbers are plain integers (year*12+month) and the
-- set of months is built with integer generate_series. The result is compared with what the
-- production derivation returns. NOTE: balances are never stored (they are derived), so there
-- is no stored balance to compare against; if summary tables are added later, add a check.
create function public._recon_c5()
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language sql stable security definer set search_path = public, pg_temp
as $$
  with flag as (
    select coalesce((select r.require_verification_for_coverage
                       from public.rule_set r
                      where r.effective_from <= current_date
                      order by r.effective_from desc limit 1), false) as needs_verification
  ),
  live as (
    select e.id, e.family_id,
           extract(year from e.period_start)::int * 12 + extract(month from e.period_start)::int as a,
           extract(year from e.period_end)::int * 12 + extract(month from e.period_end)::int as b
      from public.ledger_entry e
      cross join flag
     where e.category = 'membership_contribution'
       and e.amount_paisa > 0
       and e.reverses_entry_id is null
       and e.family_id is not null
       and e.period_start is not null
       and not exists (select 1 from public.ledger_entry r where r.reverses_entry_id = e.id)
       and (not flag.needs_verification
            or exists (select 1 from public.ledger_verification lv where lv.entry_id = e.id))
  ),
  indep as (
    select l.family_id, count(distinct g) as months, max(g) as last_idx
      from live l
      cross join lateral generate_series(l.a, l.b) g
     group by l.family_id
  ),
  fams as (
    select distinct e.family_id
      from public.ledger_entry e
     where e.category = 'membership_contribution' and e.family_id is not null
  )
  select 'C5', 'critical', 'family', f.family_id::text,
         format('production derivation: %s months until %s; independent recomputation: %s months until %s',
                p.c, p.u, coalesce(i.months, 0),
                case when i.last_idx is null then null
                     else make_date(((i.last_idx - 1) / 12)::int, ((i.last_idx - 1) % 12)::int + 1, 1) end)
    from fams f
    cross join flag
    cross join lateral (select count(*) as c, max(cm.m) as u
                          from public._covered_months(f.family_id, flag.needs_verification) cm) p
    left join indep i on i.family_id = f.family_id
   where p.c <> coalesce(i.months, 0)
      or p.u is distinct from (case when i.last_idx is null then null
                                    else make_date(((i.last_idx - 1) / 12)::int, ((i.last_idx - 1) % 12)::int + 1, 1) end)
$$;

-- ---------------------------------------------------------------- C6 membership payment shape
-- PROPOSED rule (Q2 / FINANCE_RULES): amount = whole months x the monthly rate in effect on the
-- payment date. The date is evaluated in UTC and in Asia/Karachi; matching either is accepted,
-- because the server's session time zone is not guaranteed.
create function public._recon_c6()
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language sql stable security definer set search_path = public, pg_temp
as $$
  select 'C6', 'high', 'ledger_entry', x.id::text, x.problem
  from (
    select m.id,
           case
             when m.family_id is null or m.period_start is null
               then 'membership contribution without a family or period'
             when m.rate_utc is null and m.rate_pk is null
               then 'no contribution rule was in effect on the payment date'
             when m.amount_paisa <> m.n * coalesce(m.rate_utc, -1)
              and m.amount_paisa <> m.n * coalesce(m.rate_pk, -1)
               then format('amount %s is not %s whole months at the rate in effect (%s)',
                           m.amount_paisa, m.n, coalesce(m.rate_utc, m.rate_pk))
             when m.period_start < date_trunc('month', m.membership_start)::date
               then 'covers months before the family joined'
           end as problem
    from (
      select e.id, e.family_id, e.amount_paisa, e.period_start, f.membership_start,
             (extract(year from e.period_end)::int * 12 + extract(month from e.period_end)::int)
               - (extract(year from e.period_start)::int * 12 + extract(month from e.period_start)::int) + 1 as n,
             (select r.monthly_rate_paisa from public.rule_set r
               where r.effective_from <= (e.collected_at at time zone 'UTC')::date
               order by r.effective_from desc limit 1) as rate_utc,
             (select r.monthly_rate_paisa from public.rule_set r
               where r.effective_from <= (e.collected_at at time zone 'Asia/Karachi')::date
               order by r.effective_from desc limit 1) as rate_pk
        from public.ledger_entry e
        left join public.family f on f.id = e.family_id
       where e.category = 'membership_contribution'
         and e.amount_paisa > 0
         and e.reverses_entry_id is null
    ) m
  ) x
  where x.problem is not null
$$;

-- ---------------------------------------------------------------- C7 double booking
create function public._recon_c7()
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language sql stable security definer set search_path = public, pg_temp
as $$
  with live as (
    select e.id, e.family_id, e.period_start, e.period_end
      from public.ledger_entry e
     where e.category = 'membership_contribution'
       and e.amount_paisa > 0
       and e.reverses_entry_id is null
       and e.family_id is not null
       and e.period_start is not null
       and not exists (select 1 from public.ledger_entry r where r.reverses_entry_id = e.id)
  )
  select 'C7', 'critical', 'ledger_entry', a.id::text,
         format('books months (%s to %s) that entry %s also books',
                greatest(a.period_start, b.period_start), least(a.period_end, b.period_end), b.id)
    from live a
    join live b on a.family_id = b.family_id
               and a.id < b.id
               and a.period_start <= b.period_end
               and b.period_start <= a.period_end
$$;

-- ---------------------------------------------------------------- C8 non-member burial payments
create function public._recon_c8()
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language sql stable security definer set search_path = public, pg_temp
as $$
  select 'C8', 'high', 'ledger_entry', e.id::text, 'non-member burial payment belongs to a family'
    from public.ledger_entry e
   where e.category = 'non_member_burial' and e.family_id is not null
  union all
  select 'C8', 'high', 'ledger_entry', e.id::text, 'non-member burial payment has a contribution period'
    from public.ledger_entry e
   where e.category = 'non_member_burial' and (e.period_start is not null or e.period_end is not null)
  union all
  -- Open question Q7: an unlinked payment may be acceptable, so this is an observation only.
  select 'C8', 'info', 'ledger_entry', e.id::text,
         'non-member burial payment is not linked to any burial (open question Q7: may be acceptable)'
    from public.ledger_entry e
   where e.category = 'non_member_burial'
     and e.amount_paisa > 0
     and e.reverses_entry_id is null
     and not exists (select 1 from public.burial_payment p where p.entry_id = e.id)
     and not exists (select 1 from public.ledger_entry r where r.reverses_entry_id = e.id)
$$;

-- ---------------------------------------------------------------- C9 burial payment links
create function public._recon_c9()
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language sql stable security definer set search_path = public, pg_temp
as $$
  select 'C9', 'high', 'burial_payment', x.id::text, x.problem
  from (
    select p.id,
           case
             when e.id is null then 'link to a missing ledger entry'
             when e.category <> 'non_member_burial' then 'linked entry is not a non-member burial payment'
             when e.amount_paisa <= 0 then 'linked entry is not a positive payment'
             when e.family_id is not null then 'linked entry belongs to a family'
             when b.id is null then 'link to a missing burial record'
             when b.kind <> 'non_member' then 'linked burial is not a non-member burial'
           end as problem
      from public.burial_payment p
      left join public.ledger_entry e on e.id = p.entry_id
      left join public.burial_record b on b.id = p.burial_id
  ) x
  where x.problem is not null
  union all
  select 'C9', 'high', 'burial_record', b.id::text, 'non-member burial is linked to a person or family'
    from public.burial_record b
   where b.kind = 'non_member'
     and (b.person_id is not null or b.family_id is not null or b.family_no_at_burial is not null)
$$;

-- ---------------------------------------------------------------- C10 category totals
create function public._recon_c10()
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language sql stable security definer set search_path = public, pg_temp
as $$
  select 'C10', 'critical', 'ledger_category', t.category::text,
         format('net total %s differs from the total of un-reversed payments %s', t.net, coalesce(t.live_total, 0))
    from (
      select s.category,
             sum(s.amount_paisa) as net,
             sum(s.amount_paisa) filter (where s.is_live) as live_total
        from (
          select e.category, e.amount_paisa,
                 (e.amount_paisa > 0
                  and e.reverses_entry_id is null
                  and not exists (select 1 from public.ledger_entry r where r.reverses_entry_id = e.id)) as is_live
            from public.ledger_entry e
        ) s
       group by s.category
    ) t
   where t.net <> coalesce(t.live_total, 0)
$$;

-- ---------------------------------------------------------------- C11 ledger vs audit log
create function public._recon_c11()
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language sql stable security definer set search_path = public, pg_temp
as $$
  with src as (
    select 'ledger_entry'::text as tbl, id::text as rid,
           jsonb_build_object('amount_paisa', amount_paisa, 'family_id', family_id,
                              'category', category, 'reverses_entry_id', reverses_entry_id) as k
      from public.ledger_entry
    union all
    select 'ledger_verification', id::text,
           jsonb_build_object('entry_id', entry_id, 'verified_by', verified_by)
      from public.ledger_verification
    union all
    select 'receipt', id::text,
           jsonb_build_object('entry_id', entry_id, 'receipt_year', receipt_year, 'receipt_seq', receipt_seq)
      from public.receipt
    union all
    select 'rule_set', id::text,
           jsonb_build_object('effective_from', effective_from, 'monthly_rate_paisa', monthly_rate_paisa)
      from public.rule_set
    union all
    select 'burial_record', id::text,
           jsonb_build_object('burial_no', burial_no, 'kind', kind, 'person_id', person_id,
                              'family_id', family_id, 'created_by', created_by)
      from public.burial_record
    union all
    select 'burial_approval', id::text,
           jsonb_build_object('burial_id', burial_id, 'decision', decision, 'recorded_by', recorded_by)
      from public.burial_approval
    union all
    select 'burial_payment', id::text,
           jsonb_build_object('burial_id', burial_id, 'entry_id', entry_id)
      from public.burial_payment
  ),
  ins as (
    select a.table_name as tbl, a.record_id as rid, a.new_data,
           count(*) over (partition by a.table_name, a.record_id) as n
      from public.audit_log a
     where a.action = 'INSERT'
       and a.table_name in ('ledger_entry', 'ledger_verification', 'receipt', 'rule_set',
                            'burial_record', 'burial_approval', 'burial_payment')
  )
  select 'C11', 'high', s.tbl, s.rid, 'no audit record of this row''s creation'
    from src s
   where not exists (select 1 from ins i where i.tbl = s.tbl and i.rid = s.rid)
  union all
  select distinct 'C11', 'critical', s.tbl, s.rid,
         'row no longer matches the audit record of its creation (possible tampering)'
    from src s
    join ins i on i.tbl = s.tbl and i.rid = s.rid
   where not (i.new_data @> s.k)
  union all
  select distinct 'C11', 'critical', i.tbl, i.rid, 'audited row no longer exists (deleted after creation)'
    from ins i
   where not exists (select 1 from src s where s.tbl = i.tbl and s.rid = i.rid)
  union all
  select distinct 'C11', 'medium', i.tbl, i.rid, format('%s creation audit records exist for one row', i.n)
    from ins i
   where i.n > 1
  union all
  select 'C11', 'critical', a.table_name, a.record_id,
         format('audit log records a %s on an append-only table', a.action)
    from public.audit_log a
   where a.action in ('UPDATE', 'DELETE')
     and a.table_name in ('ledger_entry', 'ledger_verification', 'receipt', 'rule_set',
                          'burial_approval', 'burial_payment')
$$;

-- C11A: creation audited without an actor. Expected for service-role or setup operations;
-- unexpected for anything done through the app. Observation only.
create function public._recon_c11a()
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language sql stable security definer set search_path = public, pg_temp
as $$
  select 'C11A', 'info', a.table_name, a.record_id,
         'creation was audited without an actor (service-role or setup operation)'
    from public.audit_log a
   where a.action = 'INSERT'
     and a.actor is null
     and a.table_name in ('ledger_entry', 'ledger_verification', 'receipt', 'rule_set',
                          'burial_record', 'burial_approval', 'burial_payment')
$$;

-- ---------------------------------------------------------------- C13 protective triggers
create function public._recon_c13()
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language sql stable security definer set search_path = public, pg_temp
as $$
  with expected as (
    select t as tbl, t || '_no_mutation' as trg
      from unnest(array['ledger_entry', 'ledger_verification', 'receipt', 'rule_set', 'audit_log',
                        'burial_approval', 'burial_payment']) t
    union all
    select t, t || '_no_truncate'
      from unnest(array['ledger_entry', 'ledger_verification', 'receipt', 'rule_set', 'audit_log',
                        'burial_approval', 'burial_payment']) t
    union all
    select t, t || '_no_delete'
      from unnest(array['committee_user', 'role_grant', 'person', 'family', 'family_member', 'burial_record']) t
    union all
    select t, t || '_no_truncate'
      from unnest(array['committee_user', 'role_grant', 'person', 'family', 'family_member', 'burial_record']) t
    union all
    select t, t || '_audit'
      from unnest(array['committee_user', 'role_grant', 'role_permission', 'person', 'family', 'family_member',
                        'rule_set', 'ledger_entry', 'ledger_verification', 'receipt',
                        'burial_record', 'burial_approval', 'burial_payment']) t
    union all
    select 'family_member', 'family_member_close_only'
    union all
    select 'burial_record', 'burial_record_guard'
    union all
    select 'burial_payment', 'burial_payment_check'
  ),
  actual as (
    select c.relname::text as tbl, tg.tgname::text as trg, tg.tgenabled
      from pg_trigger tg
      join pg_class c on c.oid = tg.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and not tg.tgisinternal
  )
  select 'C13', 'critical', 'trigger', e.tbl || '.' || e.trg,
         case when a.trg is null then 'protective trigger is missing'
              else 'protective trigger is disabled' end
    from expected e
    left join actual a on a.tbl = e.tbl and a.trg = e.trg
   where a.trg is null or a.tgenabled <> 'O'
$$;

-- ---------------------------------------------------------------- C14 RLS and client privileges
create function public._recon_c14()
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language sql stable security definer set search_path = public, pg_temp
as $$
  with tbls as (
    select c.oid, c.relname::text as relname, c.relrowsecurity
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
  )
  select 'C14', 'critical', 'table', t.relname, 'row level security is disabled'
    from tbls t
   where not t.relrowsecurity
  union all
  select 'C14', 'critical', 'table', t.relname, 'the anon role has privileges on this table'
    from tbls t
   where case when exists (select 1 from pg_roles where rolname = 'anon')
              then has_table_privilege('anon', t.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
              else false end
  union all
  select 'C14', 'critical', 'table', t.relname, 'the authenticated role can write to this table directly'
    from tbls t
   where case when exists (select 1 from pg_roles where rolname = 'authenticated')
              then has_table_privilege('authenticated', t.oid, 'INSERT,UPDATE,DELETE,TRUNCATE')
              else false end
$$;

-- ---------------------------------------------------------------- C16 duplicate allocation
create function public._recon_c16()
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language sql stable security definer set search_path = public, pg_temp
as $$
  select 'C16', 'critical', 'ledger_entry', e.reverses_entry_id::text,
         format('payment has been reversed %s times', count(*))
    from public.ledger_entry e
   where e.reverses_entry_id is not null
   group by e.reverses_entry_id
  having count(*) > 1
  union all
  select 'C16', 'critical', 'ledger_entry', v.entry_id::text,
         format('payment has been verified %s times', count(*))
    from public.ledger_verification v
   group by v.entry_id
  having count(*) > 1
  union all
  select 'C16', 'critical', 'ledger_entry', p.entry_id::text,
         format('payment is allocated to %s burial links', count(*))
    from public.burial_payment p
   group by p.entry_id
  having count(*) > 1
$$;

-- ---------------------------------------------------------------- C17 function privileges
-- Only the functions on this list may be executed by signed-in clients, and none by anon or
-- PUBLIC. Every other function (internal helpers, SECURITY DEFINER internals, trigger
-- functions) must be unreachable from the API. A NEW client-callable function must be added
-- here AND granted explicitly; forgetting either makes this check or the feature fail loudly.
create function public._client_functions()
returns table (fname text)
language sql immutable
as $$
  select * from unnest(array[
    'has_permission',
    'create_committee_user', 'grant_role', 'revoke_role', 'create_rule_set',
    'register_family', 'add_family_member', 'transfer_member',
    'record_payment', 'verify_payment', 'reverse_payment', 'family_balance',
    'register_burial_for_member', 'register_burial_non_member', 'update_burial_details',
    'correct_non_member_deceased', 'void_burial', 'record_burial_approval', 'record_burial_payment',
    'reconciliation_violations', 'reconciliation_report'
  ])
$$;

create function public._recon_c17()
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language sql stable security definer set search_path = public, pg_temp
as $$
  with fns as (
    select p.oid, p.proname, p.proacl, p.oid::regprocedure::text as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind in ('f', 'p')
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')  -- skip extension members
  )
  select 'C17', 'critical', 'function', f.sig, 'executable by PUBLIC (every role)'
    from fns f
   where f.proacl is null
      or exists (select 1 from aclexplode(f.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')
  union all
  select 'C17', 'critical', 'function', f.sig, 'executable by the anon role'
    from fns f
   where case when exists (select 1 from pg_roles where rolname = 'anon')
              then has_function_privilege('anon', f.oid, 'EXECUTE') else false end
  union all
  select 'C17', 'critical', 'function', f.sig,
         'executable by signed-in clients but not on the approved client-function list'
    from fns f
   where f.proname not in (select cf.fname from public._client_functions() cf)
     and case when exists (select 1 from pg_roles where rolname = 'authenticated')
              then has_function_privilege('authenticated', f.oid, 'EXECUTE') else false end
$$;

-- ---------------------------------------------------------------- catalog and runner (internal)
create function public._recon_catalog()
returns table (check_id text, check_name text, default_severity text)
language sql immutable
as $$
  select * from (values
    ('C1',   'Every reversal references and exactly negates its original payment', 'critical'),
    ('C2',   'Every payment has exactly one receipt; none exist for reversals', 'critical'),
    ('C3',   'Receipt numbers are unique, gap-free, and consistent with the counter', 'critical'),
    ('C4',   'Verifications refer to valid, un-reversed payments', 'high'),
    ('C5',   'Independent coverage recomputation matches the production derivation', 'critical'),
    ('C6',   'Membership payments are whole months at the rule rate, after joining', 'high'),
    ('C7',   'No month is booked twice for a family (no double allocation)', 'critical'),
    ('C8',   'Non-member burial payments have no family or period; unlinked ones listed', 'high'),
    ('C9',   'Burial payment links and non-member burial records are valid', 'high'),
    ('C10',  'Net ledger totals by category agree with un-reversed payments', 'critical'),
    ('C11',  'Ledger and burial rows match their audit records; no audited change or deletion', 'critical'),
    ('C11A', 'Creation audited without an actor (observation)', 'info'),
    ('C13',  'Protective triggers are present and enabled', 'critical'),
    ('C14',  'Row level security everywhere; clients cannot write tables directly', 'critical'),
    ('C16',  'No payment is reversed, verified, or linked more than once', 'critical'),
    ('C17',  'Only approved functions are executable by clients; none by anon or PUBLIC', 'critical')
  ) as c (check_id, check_name, default_severity)
$$;

create function public._recon_run(p_check_id text default null)
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare want text := upper(p_check_id);
begin
  if want is not null and not exists (select 1 from public._recon_catalog() c where c.check_id = want) then
    raise exception 'unknown reconciliation check: %', p_check_id;
  end if;
  if want is null or want = 'C1'   then return query select * from public._recon_c1();   end if;
  if want is null or want = 'C2'   then return query select * from public._recon_c2();   end if;
  if want is null or want = 'C3'   then return query select * from public._recon_c3();   end if;
  if want is null or want = 'C4'   then return query select * from public._recon_c4();   end if;
  if want is null or want = 'C5'   then return query select * from public._recon_c5();   end if;
  if want is null or want = 'C6'   then return query select * from public._recon_c6();   end if;
  if want is null or want = 'C7'   then return query select * from public._recon_c7();   end if;
  if want is null or want = 'C8'   then return query select * from public._recon_c8();   end if;
  if want is null or want = 'C9'   then return query select * from public._recon_c9();   end if;
  if want is null or want = 'C10'  then return query select * from public._recon_c10();  end if;
  if want is null or want = 'C11'  then return query select * from public._recon_c11();  end if;
  if want is null or want = 'C11A' then return query select * from public._recon_c11a(); end if;
  if want is null or want = 'C13'  then return query select * from public._recon_c13();  end if;
  if want is null or want = 'C14'  then return query select * from public._recon_c14();  end if;
  if want is null or want = 'C16'  then return query select * from public._recon_c16();  end if;
  if want is null or want = 'C17'  then return query select * from public._recon_c17();  end if;
end $$;

-- ---------------------------------------------------------------- client entry points
-- Violation details for one check (or all). Requires permission 'reconcile.run'.
create function public.reconciliation_violations(p_check_id text default null)
returns table (check_id text, severity text, record_type text, record_id text, detail text)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  perform public._require('reconcile.run');
  return query select * from public._recon_run(p_check_id);
end $$;

-- One row per check: how many violations, the worst severity found, and a status:
--   pass = none; fail = at least one critical/high/medium; info = only observations.
create function public.reconciliation_report()
returns table (check_id text, check_name text, severity text, violation_count bigint, status text)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  perform public._require('reconcile.run');
  return query
    with v as (select * from public._recon_run(null)),
    g as (
      select v.check_id as cid,
             count(*) as total,
             count(*) filter (where v.severity <> 'info') as failing,
             (array_agg(v.severity order by case v.severity
                          when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end))[1] as worst
        from v group by v.check_id
    )
    select c.check_id, c.check_name,
           coalesce(g.worst, c.default_severity),
           coalesce(g.total, 0),
           case when coalesce(g.failing, 0) > 0 then 'fail'
                when coalesce(g.total, 0) > 0 then 'info'
                else 'pass' end
      from public._recon_catalog() c
      left join g on g.cid = c.check_id
     order by c.check_id;
end $$;

grant execute on function
  public.reconciliation_violations(text),
  public.reconciliation_report()
to authenticated;
