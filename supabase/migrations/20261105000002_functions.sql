-- Business functions. Clients have no direct write access to tables; every write
-- goes through one of these SECURITY DEFINER functions, which check the caller's
-- permission (from role_permission) and write inside a single transaction.
--
-- PROPOSED / OPEN rules are marked. See docs/DECISIONS.md and docs/FINANCE_RULES.md:
--   D1 permission matrix  -> permissions are data, not code
--   D2 grace period       -> read from rule_set.grace_months; null = "rule_not_configured"
--   D5 verification       -> rule_set.require_verification_for_coverage (default false)
--   Q2 non-multiple amounts -> rejected (never rounded)

-- ---------------------------------------------------------------- internal helpers (not client-callable)
create function public.month_index(d date)
returns integer language sql immutable as
$$ select extract(year from d)::int * 12 + extract(month from d)::int - 1 $$;

create function public._require(p_permission text)
returns void language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if not public.has_permission(p_permission) then
    raise exception 'permission denied: % required', p_permission using errcode = '42501';
  end if;
end $$;

-- Months already booked for membership contributions (reversed entries excluded).
-- Used to decide where the next payment starts, so months are never double-booked.
create function public._booked_months(p_family_id uuid)
returns table (m date)
language sql stable security definer
set search_path = public, pg_temp
as $$
  select distinct gs::date
  from public.ledger_entry e
  cross join lateral generate_series(e.period_start, e.period_end, interval '1 month') gs
  where e.family_id = p_family_id
    and e.category = 'membership_contribution'
    and e.reverses_entry_id is null
    and not exists (select 1 from public.ledger_entry r where r.reverses_entry_id = e.id)
$$;

-- Months that count as covered. With p_verified_only, entries must have a verification row (D5).
create function public._covered_months(p_family_id uuid, p_verified_only boolean)
returns table (m date)
language sql stable security definer
set search_path = public, pg_temp
as $$
  select distinct gs::date
  from public.ledger_entry e
  cross join lateral generate_series(e.period_start, e.period_end, interval '1 month') gs
  where e.family_id = p_family_id
    and e.category = 'membership_contribution'
    and e.reverses_entry_id is null
    and not exists (select 1 from public.ledger_entry r where r.reverses_entry_id = e.id)
    and (not p_verified_only
         or exists (select 1 from public.ledger_verification v where v.entry_id = e.id))
$$;

-- ---------------------------------------------------------------- staff and roles
create function public.create_committee_user(p_auth_user_id uuid, p_display_name text)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  perform public._require('role.manage');
  insert into public.committee_user (id, display_name) values (p_auth_user_id, p_display_name);
  return p_auth_user_id;
end $$;

create function public.grant_role(p_user_id uuid, p_role public.committee_role)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare new_id uuid;
begin
  perform public._require('role.manage');
  if not exists (select 1 from public.committee_user where id = p_user_id and active) then
    raise exception 'user is not an active committee user';
  end if;
  insert into public.role_grant (user_id, role, granted_by)
  values (p_user_id, p_role, auth.uid())
  returning id into new_id;
  return new_id;
end $$;

create function public.revoke_role(p_user_id uuid, p_role public.committee_role)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  perform public._require('role.manage');
  -- Never leave the system without a Super Admin.
  if p_role = 'super_admin' and not exists (
       select 1 from public.role_grant
       where role = 'super_admin' and revoked_at is null and user_id <> p_user_id) then
    raise exception 'cannot revoke the last active super_admin';
  end if;
  update public.role_grant
     set revoked_at = now(), revoked_by = auth.uid()
   where user_id = p_user_id and role = p_role and revoked_at is null;
  if not found then
    raise exception 'no active % grant for that user', p_role;
  end if;
end $$;

-- ---------------------------------------------------------------- rules
create function public.create_rule_set(
  p_effective_from date,
  p_monthly_rate_paisa bigint,
  p_grace_months integer default null,
  p_require_verification boolean default false,
  p_note text default null)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare new_id uuid;
begin
  perform public._require('rule.manage');
  insert into public.rule_set (effective_from, monthly_rate_paisa, grace_months,
                               require_verification_for_coverage, note, created_by)
  values (p_effective_from, p_monthly_rate_paisa, p_grace_months,
          p_require_verification, p_note, auth.uid())
  returning id into new_id;
  return new_id;
end $$;

-- ---------------------------------------------------------------- families and members
create function public.register_family(
  p_full_name text,
  p_father_name text,
  p_date_of_birth date,
  p_relation text,
  p_membership_start date)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare pid uuid; fid uuid;
begin
  perform public._require('family.write');
  if p_relation not in ('father', 'mother') then
    raise exception 'the head of a family must be registered as father or mother';
  end if;
  insert into public.person (full_name, father_name, date_of_birth, created_by)
  values (p_full_name, p_father_name, p_date_of_birth, auth.uid())
  returning id into pid;
  insert into public.family (membership_start, head_person_id, created_by)
  values (p_membership_start, pid, auth.uid())
  returning id into fid;
  insert into public.family_member (family_id, person_id, relation, valid_from, created_by)
  values (fid, pid, p_relation, p_membership_start, auth.uid());
  return fid;
end $$;

create function public.add_family_member(
  p_family_id uuid,
  p_full_name text,
  p_father_name text,
  p_date_of_birth date,
  p_relation text,
  p_valid_from date)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare pid uuid;
begin
  perform public._require('family.write');
  if not exists (select 1 from public.family where id = p_family_id and status <> 'closed') then
    raise exception 'family not found or closed';
  end if;
  insert into public.person (full_name, father_name, date_of_birth, created_by)
  values (p_full_name, p_father_name, p_date_of_birth, auth.uid())
  returning id into pid;
  insert into public.family_member (family_id, person_id, relation, valid_from, created_by)
  values (p_family_id, pid, p_relation, p_valid_from, auth.uid());
  return pid;
end $$;

-- Moves a person to another family, or into a brand-new household, from p_effective.
-- The old membership row is closed (never deleted); history is preserved.
-- Approval workflow (D6) is NOT enforced yet.
create function public.transfer_member(
  p_person_id uuid,
  p_effective date,
  p_new_relation text,
  p_to_family_id uuid default null)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare cur public.family_member; target uuid;
begin
  perform public._require('family.write');
  select * into cur from public.family_member
   where person_id = p_person_id and valid_to is null for update;
  if not found then
    raise exception 'person has no current family membership';
  end if;
  if p_effective <= cur.valid_from then
    raise exception 'transfer date must be after the current membership start (%)', cur.valid_from;
  end if;

  if p_to_family_id is null then
    if p_new_relation not in ('father', 'mother') then
      raise exception 'the head of a new household must be registered as father or mother';
    end if;
    insert into public.family (membership_start, head_person_id, created_by)
    values (p_effective, p_person_id, auth.uid())
    returning id into target;
  else
    if p_to_family_id = cur.family_id then
      raise exception 'person is already in that family';
    end if;
    if not exists (select 1 from public.family where id = p_to_family_id and status = 'active') then
      raise exception 'target family not found or not active';
    end if;
    target := p_to_family_id;
  end if;

  update public.family_member set valid_to = p_effective where id = cur.id;
  insert into public.family_member (family_id, person_id, relation, valid_from, created_by)
  values (target, p_person_id, p_new_relation, p_effective, auth.uid());
  return target;
end $$;

-- ---------------------------------------------------------------- payments
-- Membership contributions (PROPOSED rule): the amount must be an exact multiple of the
-- monthly rate; coverage starts at the first month not already booked; it may not overlap
-- booked months. Receipt numbers are sequential per year (Asia/Karachi) and never reused.
create function public.record_payment(
  p_family_id uuid,
  p_category public.ledger_category,
  p_amount_paisa bigint,
  p_method public.payment_method,
  p_note text default null)
returns table (o_entry_id uuid, o_receipt_year integer, o_receipt_seq integer)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  rule public.rule_set;
  fam public.family;
  n_months integer;
  start_m date;
  end_m date;
  booked_count integer;
  entry uuid;
  yr integer := extract(year from (now() at time zone 'Asia/Karachi'))::int;
  seq integer;
begin
  perform public._require('payment.record');
  if p_amount_paisa is null or p_amount_paisa <= 0 then
    raise exception 'amount must be positive';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(coalesce(p_family_id::text, 'no-family'), 0));

  if p_category = 'membership_contribution' then
    if p_family_id is null then
      raise exception 'a family is required for membership contributions';
    end if;
    select * into fam from public.family where id = p_family_id;
    if not found or fam.status = 'closed' then
      raise exception 'family not found or closed';
    end if;
    select * into rule from public.rule_set
     where effective_from <= current_date order by effective_from desc limit 1;
    if not found then
      raise exception 'no contribution rule is in effect; create a rule_set first';
    end if;
    if p_amount_paisa % rule.monthly_rate_paisa <> 0 then
      raise exception 'amount must be an exact multiple of the monthly rate (% paisa)',
        rule.monthly_rate_paisa;
    end if;
    n_months := (p_amount_paisa / rule.monthly_rate_paisa)::int;

    start_m := date_trunc('month', fam.membership_start)::date;
    select count(*) into booked_count from public._booked_months(p_family_id);
    select min(g::date) into start_m
      from generate_series(start_m, start_m + ((booked_count + 1) * interval '1 month'), interval '1 month') g
     where g::date not in (select m from public._booked_months(p_family_id));
    end_m := (start_m + ((n_months - 1) * interval '1 month'))::date;

    if exists (select 1 from public._booked_months(p_family_id) b where b.m between start_m and end_m) then
      raise exception 'payment would overlap months that are already booked; pay the open gap first';
    end if;

    insert into public.ledger_entry (family_id, category, amount_paisa, period_start, period_end,
                                     payment_method, collected_by, note)
    values (p_family_id, p_category, p_amount_paisa, start_m, end_m, p_method, auth.uid(), p_note)
    returning id into entry;
  else
    if p_family_id is not null
       and not exists (select 1 from public.family where id = p_family_id) then
      raise exception 'family not found';
    end if;
    insert into public.ledger_entry (family_id, category, amount_paisa, payment_method, collected_by, note)
    values (p_family_id, p_category, p_amount_paisa, p_method, auth.uid(), p_note)
    returning id into entry;
  end if;

  insert into public.receipt_counter as c (receipt_year, last_seq) values (yr, 1)
  on conflict (receipt_year) do update set last_seq = c.last_seq + 1
  returning c.last_seq into seq;
  insert into public.receipt (receipt_year, receipt_seq, entry_id, issued_by)
  values (yr, seq, entry, auth.uid());

  return query select entry, yr, seq;
end $$;

create function public.verify_payment(p_entry_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare e public.ledger_entry;
begin
  perform public._require('payment.verify');
  select * into e from public.ledger_entry where id = p_entry_id;
  if not found or e.amount_paisa <= 0 then
    raise exception 'payment not found';
  end if;
  if exists (select 1 from public.ledger_entry where reverses_entry_id = p_entry_id) then
    raise exception 'payment has been reversed';
  end if;
  if exists (select 1 from public.ledger_verification where entry_id = p_entry_id) then
    raise exception 'payment is already verified';
  end if;
  insert into public.ledger_verification (entry_id, verified_by) values (p_entry_id, auth.uid());
end $$;

-- Corrections are reversal entries, never edits. Returns the reversal entry id.
create function public.reverse_payment(p_entry_id uuid, p_reason text)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare e public.ledger_entry; rid uuid;
begin
  perform public._require('payment.reverse');
  if p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'a reason is required';
  end if;
  select * into e from public.ledger_entry where id = p_entry_id for update;
  if not found or e.amount_paisa <= 0 then
    raise exception 'payment not found';
  end if;
  if exists (select 1 from public.ledger_entry where reverses_entry_id = p_entry_id) then
    raise exception 'payment has already been reversed';
  end if;
  insert into public.ledger_entry (family_id, category, amount_paisa, period_start, period_end,
                                   payment_method, collected_by, reverses_entry_id, note)
  values (e.family_id, e.category, -e.amount_paisa, e.period_start, e.period_end,
          e.payment_method, auth.uid(), e.id, p_reason)
  returning id into rid;
  return rid;
end $$;

-- ---------------------------------------------------------------- balance
create type public.family_balance_row as (
  months_due      integer,
  months_covered  integer,
  balance_months  integer,
  covered_until   date,
  status          text,     -- advance | current | within_grace | overdue | rule_not_configured
  grace_months    integer
);

-- months_due is measured at p_as_of; covered months are everything booked in the ledger.
-- Burial eligibility is NOT derived from this status (separate concept, PROJECT_CONTEXT 4).
create function public.family_balance(p_family_id uuid, p_as_of date default current_date)
returns public.family_balance_row
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  fam public.family;
  rule public.rule_set;
  res public.family_balance_row;
begin
  perform public._require('payment.read');
  select * into fam from public.family where id = p_family_id;
  if not found then
    raise exception 'family not found';
  end if;
  select * into rule from public.rule_set
   where effective_from <= p_as_of order by effective_from desc limit 1;

  res.months_due := greatest(0, public.month_index(p_as_of) - public.month_index(fam.membership_start) + 1);
  select count(*)::int, max(m)
    into res.months_covered, res.covered_until
    from public._covered_months(p_family_id, coalesce(rule.require_verification_for_coverage, false));
  res.balance_months := res.months_covered - res.months_due;
  res.grace_months := rule.grace_months;

  res.status :=
    case
      when rule.id is null then 'rule_not_configured'
      when res.balance_months > 0 then 'advance'
      when res.balance_months = 0 then 'current'
      when rule.grace_months is null then 'rule_not_configured'
      when -res.balance_months <= rule.grace_months then 'within_grace'
      else 'overdue'
    end;
  return res;
end $$;

-- ---------------------------------------------------------------- client access
grant execute on function
  public.create_committee_user(uuid, text),
  public.grant_role(uuid, public.committee_role),
  public.revoke_role(uuid, public.committee_role),
  public.create_rule_set(date, bigint, integer, boolean, text),
  public.register_family(text, text, date, text, date),
  public.add_family_member(uuid, text, text, date, text, date),
  public.transfer_member(uuid, date, text, uuid),
  public.record_payment(uuid, public.ledger_category, bigint, public.payment_method, text),
  public.verify_payment(uuid),
  public.reverse_payment(uuid, text),
  public.family_balance(uuid, date)
to authenticated;
