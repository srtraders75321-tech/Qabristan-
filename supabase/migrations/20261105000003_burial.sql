-- Burial records module.
--
-- Principles (see CLAUDE.md and docs/BURIAL_MODULE.md):
--   * burial records are never deleted; a mistaken record is VOIDED with a reason
--   * registered persons link to person/family history; non-members are stored as
--     standalone records and never get a person, family, or membership
--   * a non-member burial payment is a normal ledger entry (category non_member_burial)
--     linked to the burial; this module does not modify the payment ledger
--   * approvals are append-only RECORDS. No approval rule is enforced (D4 is open):
--     a burial can exist with no approval, one, or many
--   * burial eligibility is never derived from financial balance
--   * all writes are permission-checked functions; clients have SELECT only (RLS)

create sequence public.burial_no_seq;

create table public.burial_record (
  id                  uuid primary key default gen_random_uuid(),
  burial_no           bigint not null unique default nextval('public.burial_no_seq'),
  kind                text not null check (kind in ('registered_person', 'non_member')),
  person_id           uuid references public.person (id),
  -- Membership as of the date of death, copied at registration so the record stays
  -- readable even if memberships change later. Null when none covered that date.
  family_id           uuid references public.family (id),
  family_no_at_burial bigint,
  -- Deceased details are a snapshot (for registered persons, taken from the person record).
  deceased_name       text not null check (length(btrim(deceased_name)) > 0),
  father_name         text,
  date_of_birth       date,
  date_of_death       date not null,
  burial_date         date not null,
  grave_reference     text check (grave_reference is null or length(btrim(grave_reference)) > 0),
  notes               text,
  status              text not null default 'recorded' check (status in ('recorded', 'voided')),
  void_reason         text,
  voided_by           uuid references public.committee_user (id),
  voided_at           timestamptz,
  created_at          timestamptz not null default now(),
  created_by          uuid not null references public.committee_user (id),
  check ((kind = 'registered_person') = (person_id is not null)),
  check (kind = 'registered_person' or (family_id is null and family_no_at_burial is null)),
  check ((family_id is null) = (family_no_at_burial is null)),
  check (burial_date >= date_of_death),
  check (date_of_birth is null or date_of_birth <= date_of_death),
  check ((status = 'voided') = (void_reason is not null and voided_by is not null and voided_at is not null)),
  check (void_reason is null or length(btrim(void_reason)) > 0)
);
-- A person can have only one active burial record (a voided one frees them).
create unique index burial_record_one_active_per_person
  on public.burial_record (person_id) where person_id is not null and status = 'recorded';
create index burial_record_burial_date_idx on public.burial_record (burial_date);
create index burial_record_family_idx on public.burial_record (family_id);
create index burial_record_name_idx on public.burial_record (lower(btrim(deceased_name)));

-- Committee approval RECORDS. Who must approve, how many, and when is undecided (D4);
-- nothing here blocks or gates a burial.
create table public.burial_approval (
  id             uuid primary key default gen_random_uuid(),
  burial_id      uuid not null references public.burial_record (id),
  decision       text not null check (decision in ('approved', 'rejected')),
  decision_date  date not null default current_date,
  approver_names text,                       -- free text: who gave the approval
  reference      text,                       -- e.g. meeting or resolution reference
  note           text,
  recorded_by    uuid not null references public.committee_user (id),
  recorded_at    timestamptz not null default now(),
  check (approver_names is null or length(btrim(approver_names)) > 0),
  check (reference is null or length(btrim(reference)) > 0)
);
create index burial_approval_burial_idx on public.burial_approval (burial_id);

-- Links a non-member burial to its ledger payment entr(ies). The money itself lives only
-- in ledger_entry; reversing a payment there never removes this link.
create table public.burial_payment (
  id        uuid primary key default gen_random_uuid(),
  burial_id uuid not null references public.burial_record (id),
  entry_id  uuid not null unique references public.ledger_entry (id),
  linked_by uuid not null references public.committee_user (id),
  linked_at timestamptz not null default now()
);
create index burial_payment_burial_idx on public.burial_payment (burial_id);

-- ---------------------------------------------------------------- guards
create function public.burial_payment_check()
returns trigger language plpgsql as $$
declare e public.ledger_entry; b public.burial_record;
begin
  select * into e from public.ledger_entry where id = new.entry_id;
  if e.category <> 'non_member_burial' or e.amount_paisa <= 0 then
    raise exception 'only a positive non_member_burial ledger entry can be linked to a burial';
  end if;
  if e.family_id is not null then
    raise exception 'a non-member burial payment must not belong to a family';
  end if;
  select * into b from public.burial_record where id = new.burial_id;
  if b.kind <> 'non_member' then
    raise exception 'payments can only be linked to non-member burials';
  end if;
  return new;
end $$;
create trigger burial_payment_check before insert on public.burial_payment
  for each row execute function public.burial_payment_check();

create function public.burial_record_guard()
returns trigger language plpgsql as $$
begin
  if old.status = 'voided' then
    raise exception 'a voided burial record cannot be changed' using errcode = '42501';
  end if;
  if new.id is distinct from old.id
     or new.burial_no is distinct from old.burial_no
     or new.kind is distinct from old.kind
     or new.person_id is distinct from old.person_id
     or new.family_id is distinct from old.family_id
     or new.family_no_at_burial is distinct from old.family_no_at_burial
     or new.created_at is distinct from old.created_at
     or new.created_by is distinct from old.created_by then
    raise exception 'identity and link fields of a burial record are immutable' using errcode = '42501';
  end if;
  if old.kind = 'registered_person'
     and (new.deceased_name is distinct from old.deceased_name
          or new.father_name is distinct from old.father_name
          or new.date_of_birth is distinct from old.date_of_birth
          or new.date_of_death is distinct from old.date_of_death) then
    raise exception 'deceased details of a registered person come from the person record and cannot be changed here'
      using errcode = '42501';
  end if;
  if new.status is distinct from old.status and not (old.status = 'recorded' and new.status = 'voided') then
    raise exception 'invalid status change' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger burial_record_guard before update on public.burial_record
  for each row execute function public.burial_record_guard();

-- burial_record: never deleted.  burial_approval / burial_payment: append-only.
create trigger burial_record_no_delete before delete on public.burial_record
  for each row execute function public.reject_delete();
create trigger burial_record_no_truncate before truncate on public.burial_record
  for each statement execute function public.reject_delete();
do $$
declare t text;
begin
  foreach t in array array['burial_approval', 'burial_payment']
  loop
    execute format('create trigger %I before update or delete on public.%I
                    for each row execute function public.reject_mutation()', t || '_no_mutation', t);
    execute format('create trigger %I before truncate on public.%I
                    for each statement execute function public.reject_mutation()', t || '_no_truncate', t);
  end loop;
  foreach t in array array['burial_record', 'burial_approval', 'burial_payment']
  loop
    execute format('create trigger %I after insert or update or delete on public.%I
                    for each row execute function public.audit_row()', t || '_audit', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- RLS: default deny
alter table public.burial_record   enable row level security;
alter table public.burial_approval enable row level security;
alter table public.burial_payment  enable row level security;

create policy burial_record_read on public.burial_record for select to authenticated
  using (public.has_permission('burial.read'));
create policy burial_approval_read on public.burial_approval for select to authenticated
  using (public.has_permission('burial.read'));
create policy burial_payment_read on public.burial_payment for select to authenticated
  using (public.has_permission('burial.read'));

grant select on public.burial_record, public.burial_approval, public.burial_payment to authenticated;

-- Convenience view for lists. security_invoker: the caller's own RLS applies.
-- It deliberately contains no money and no financial status.
create view public.burial_overview with (security_invoker = true) as
select b.*,
       (select count(*) from public.burial_approval a where a.burial_id = b.id)            as approval_count,
       (select a.decision from public.burial_approval a where a.burial_id = b.id
         order by a.recorded_at desc, a.id desc limit 1)                                   as latest_decision,
       (select count(*) from public.burial_payment p where p.burial_id = b.id)             as payment_link_count
from public.burial_record b;
grant select on public.burial_overview to authenticated;

-- ---------------------------------------------------------------- functions
-- Registered person. Details come from the person record; family is the membership in
-- effect on the date of death (from history), or null if none covers that date.
-- Financial balance is deliberately NOT consulted.
create function public.register_burial_for_member(
  p_person_id uuid,
  p_date_of_death date,
  p_burial_date date,
  p_grave_reference text default null,
  p_notes text default null)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare per public.person; fm public.family_member; fam public.family; new_id uuid;
begin
  perform public._require('burial.write');
  if p_date_of_death is null or p_date_of_death > current_date then
    raise exception 'date of death is required and cannot be in the future';
  end if;
  select * into per from public.person where id = p_person_id for update;
  if not found then
    raise exception 'person not found';
  end if;
  if exists (select 1 from public.burial_record where person_id = p_person_id and status = 'recorded') then
    raise exception 'this person already has a burial record';
  end if;
  if per.date_of_death is not null and per.date_of_death <> p_date_of_death then
    raise exception 'person record already has a different date of death (%)', per.date_of_death;
  end if;

  select * into fm from public.family_member
   where person_id = p_person_id
     and valid_from <= p_date_of_death
     and (valid_to is null or valid_to > p_date_of_death)
   order by valid_from desc limit 1;
  if found then
    select * into fam from public.family where id = fm.family_id;
  end if;

  if per.date_of_death is null then
    update public.person set date_of_death = p_date_of_death where id = p_person_id;
  end if;

  insert into public.burial_record (kind, person_id, family_id, family_no_at_burial, deceased_name,
                                    father_name, date_of_birth, date_of_death, burial_date,
                                    grave_reference, notes, created_by)
  values ('registered_person', p_person_id, fam.id, fam.family_no, per.full_name, per.father_name,
          per.date_of_birth, p_date_of_death, p_burial_date, p_grave_reference, p_notes, auth.uid())
  returning id into new_id;
  return new_id;
end $$;

-- Non-member: stored standalone. No person, family, or membership is created.
-- A likely duplicate (same name, father, date of death) must be explicitly confirmed.
create function public.register_burial_non_member(
  p_full_name text,
  p_father_name text,
  p_date_of_birth date,
  p_date_of_death date,
  p_burial_date date,
  p_grave_reference text default null,
  p_notes text default null,
  p_confirm_possible_duplicate boolean default false)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare dup bigint; new_id uuid;
begin
  perform public._require('burial.write');
  if p_date_of_death is null or p_date_of_death > current_date then
    raise exception 'date of death is required and cannot be in the future';
  end if;
  select burial_no into dup from public.burial_record
   where status = 'recorded' and kind = 'non_member'
     and lower(btrim(deceased_name)) = lower(btrim(p_full_name))
     and date_of_death = p_date_of_death
     and coalesce(lower(btrim(father_name)), '') = coalesce(lower(btrim(p_father_name)), '')
   limit 1;
  if dup is not null and not p_confirm_possible_duplicate then
    raise exception 'possible duplicate of burial no. %; confirm to record anyway', dup;
  end if;
  insert into public.burial_record (kind, deceased_name, father_name, date_of_birth, date_of_death,
                                    burial_date, grave_reference, notes, created_by)
  values ('non_member', p_full_name, p_father_name, p_date_of_birth, p_date_of_death,
          p_burial_date, p_grave_reference, p_notes, auth.uid())
  returning id into new_id;
  return new_id;
end $$;

-- Burial date, grave reference and notes may be corrected. Every change is audited with
-- old and new values.
create function public.update_burial_details(
  p_burial_id uuid,
  p_burial_date date,
  p_grave_reference text,
  p_notes text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  perform public._require('burial.write');
  perform 1 from public.burial_record where id = p_burial_id and status = 'recorded' for update;
  if not found then
    raise exception 'burial record not found or voided';
  end if;
  update public.burial_record
     set burial_date = p_burial_date, grave_reference = p_grave_reference, notes = p_notes
   where id = p_burial_id;
end $$;

-- Fix a typing mistake in a non-member's details. Registered persons are corrected on the
-- person record, not here.
create function public.correct_non_member_deceased(
  p_burial_id uuid,
  p_full_name text,
  p_father_name text,
  p_date_of_birth date,
  p_date_of_death date)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  perform public._require('burial.write');
  if p_date_of_death is null or p_date_of_death > current_date then
    raise exception 'date of death is required and cannot be in the future';
  end if;
  perform 1 from public.burial_record
   where id = p_burial_id and status = 'recorded' and kind = 'non_member' for update;
  if not found then
    raise exception 'non-member burial record not found or voided';
  end if;
  update public.burial_record
     set deceased_name = p_full_name, father_name = p_father_name,
         date_of_birth = p_date_of_birth, date_of_death = p_date_of_death
   where id = p_burial_id;
end $$;

-- A record entered by mistake is voided with a reason; it is never deleted. A linked
-- payment is NOT touched: the treasurer reverses it in the ledger if required.
create function public.void_burial(p_burial_id uuid, p_reason text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  perform public._require('burial.void');
  if p_reason is null or length(btrim(p_reason)) = 0 then
    raise exception 'a reason is required';
  end if;
  perform 1 from public.burial_record where id = p_burial_id and status = 'recorded' for update;
  if not found then
    raise exception 'burial record not found or already voided';
  end if;
  update public.burial_record
     set status = 'voided', void_reason = p_reason, voided_by = auth.uid(), voided_at = now()
   where id = p_burial_id;
end $$;

-- Record a committee decision. Records only; enforces no rule about who or how many (D4).
create function public.record_burial_approval(
  p_burial_id uuid,
  p_decision text,
  p_decision_date date default current_date,
  p_approver_names text default null,
  p_reference text default null,
  p_note text default null)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare new_id uuid;
begin
  perform public._require('burial.approve');
  perform 1 from public.burial_record where id = p_burial_id and status = 'recorded';
  if not found then
    raise exception 'burial record not found or voided';
  end if;
  insert into public.burial_approval (burial_id, decision, decision_date, approver_names,
                                      reference, note, recorded_by)
  values (p_burial_id, p_decision, coalesce(p_decision_date, current_date), p_approver_names,
          p_reference, p_note, auth.uid())
  returning id into new_id;
  return new_id;
end $$;

-- Records a non-member burial payment through the existing ledger function (so receipt
-- numbering, audit and append-only rules are identical), then links it to the burial.
-- No amount is enforced: the fee is undecided (D3). Creates no family or membership.
create function public.record_burial_payment(
  p_burial_id uuid,
  p_amount_paisa bigint,
  p_method public.payment_method,
  p_note text default null)
returns table (o_entry_id uuid, o_receipt_year integer, o_receipt_seq integer)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare b public.burial_record; eid uuid; yr integer; seq integer;
begin
  perform public._require('payment.record');
  perform public._require('burial.read');
  select * into b from public.burial_record where id = p_burial_id for update;
  if not found or b.status <> 'recorded' then
    raise exception 'burial record not found or voided';
  end if;
  if b.kind <> 'non_member' then
    raise exception 'payments are only recorded here for non-member burials';
  end if;
  select r.o_entry_id, r.o_receipt_year, r.o_receipt_seq into eid, yr, seq
    from public.record_payment(null, 'non_member_burial', p_amount_paisa, p_method, p_note) r;
  insert into public.burial_payment (burial_id, entry_id, linked_by) values (p_burial_id, eid, auth.uid());
  return query select eid, yr, seq;
end $$;

grant execute on function
  public.register_burial_for_member(uuid, date, date, text, text),
  public.register_burial_non_member(text, text, date, date, date, text, text, boolean),
  public.update_burial_details(uuid, date, text, text),
  public.correct_non_member_deceased(uuid, text, text, date, date),
  public.void_burial(uuid, text),
  public.record_burial_approval(uuid, text, date, text, text, text),
  public.record_burial_payment(uuid, bigint, public.payment_method, text)
to authenticated;
