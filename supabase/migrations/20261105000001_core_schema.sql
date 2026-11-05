-- Core schema: people, families, roles, rules, ledger, receipts, audit.
-- Conventions (see CLAUDE.md):
--   * money is integer paisa (PKR 200 = 20000)
--   * ledger_entry, ledger_verification, receipt, rule_set, audit_log are append-only
--   * nothing is deleted; family_member rows are closed with valid_to
--   * default-deny RLS; clients get SELECT only, all writes go through functions
--   * permissions are data (role_permission) because the role matrix (D1) is unresolved

create extension if not exists btree_gist;

-- Functions are not executable by PUBLIC/anon unless explicitly granted.
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema public revoke all on tables from anon, authenticated;

-- ---------------------------------------------------------------- types
-- Role names are PROPOSED, not approved (D1).
create type public.committee_role as enum
  ('super_admin', 'committee_admin', 'treasurer', 'collection_officer', 'general_member');
create type public.family_status as enum ('active', 'inactive', 'closed');
create type public.ledger_category as enum
  ('membership_contribution', 'voluntary_donation', 'non_member_burial', 'other_collection');
create type public.payment_method as enum
  ('cash', 'bank_transfer', 'mobile_wallet', 'cheque', 'other');

-- ---------------------------------------------------------------- staff and permissions
create table public.committee_user (
  id           uuid primary key references auth.users (id),
  display_name text not null check (length(btrim(display_name)) > 0),
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

create table public.role_grant (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.committee_user (id),
  role       public.committee_role not null,
  granted_by uuid references public.committee_user (id),
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references public.committee_user (id)
);
create unique index role_grant_one_active
  on public.role_grant (user_id, role) where revoked_at is null;

-- Which role holds which permission. This IS the permission matrix, kept as data
-- so decision D1 can change without code changes.
create table public.role_permission (
  role       public.committee_role not null,
  permission text not null check (length(permission) > 0),
  primary key (role, permission)
);

create function public.has_permission(p_permission text)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.role_grant g
    join public.committee_user u on u.id = g.user_id and u.active
    join public.role_permission rp on rp.role = g.role
    where g.user_id = auth.uid()
      and g.revoked_at is null
      and rp.permission = p_permission
  );
$$;
grant execute on function public.has_permission(text) to authenticated;

-- ---------------------------------------------------------------- people and families
create table public.person (
  id            uuid primary key default gen_random_uuid(),
  full_name     text not null check (length(btrim(full_name)) > 0),
  father_name   text,
  date_of_birth date,
  date_of_death date,
  created_at    timestamptz not null default now(),
  created_by    uuid references public.committee_user (id),
  check (date_of_death is null or date_of_birth is null or date_of_death >= date_of_birth)
);

create sequence public.family_no_seq;

create table public.family (
  id               uuid primary key default gen_random_uuid(),
  family_no        bigint not null unique default nextval('public.family_no_seq'),
  status           public.family_status not null default 'active',
  membership_start date not null,
  head_person_id   uuid references public.person (id),
  created_at       timestamptz not null default now(),
  created_by       uuid references public.committee_user (id)
);

-- A person belongs to at most one family at any time. valid_to is EXCLUSIVE
-- (the first day the person is no longer in that family); null = current.
create table public.family_member (
  id         uuid primary key default gen_random_uuid(),
  family_id  uuid not null references public.family (id),
  person_id  uuid not null references public.person (id),
  relation   text not null check (relation in ('father', 'mother', 'son', 'daughter', 'other')),
  valid_from date not null,
  valid_to   date,
  created_at timestamptz not null default now(),
  created_by uuid references public.committee_user (id),
  check (valid_to is null or valid_to > valid_from),
  exclude using gist (person_id with =, daterange(valid_from, valid_to, '[)') with &&)
);
create index family_member_family_idx on public.family_member (family_id);
create index family_member_person_idx on public.family_member (person_id);

-- ---------------------------------------------------------------- rules (versioned, append-only)
create table public.rule_set (
  id                                 uuid primary key default gen_random_uuid(),
  effective_from                     date not null unique,
  monthly_rate_paisa                 bigint not null check (monthly_rate_paisa > 0),
  grace_months                       integer check (grace_months is null or grace_months >= 0), -- null = D2 undecided
  require_verification_for_coverage  boolean not null default false,                            -- D5 undecided
  note                               text,
  created_at                         timestamptz not null default now(),
  created_by                         uuid references public.committee_user (id)
);

-- ---------------------------------------------------------------- ledger (append-only)
create table public.ledger_entry (
  id                uuid primary key default gen_random_uuid(),
  family_id         uuid references public.family (id),
  category          public.ledger_category not null,
  amount_paisa      bigint not null check (amount_paisa <> 0),
  period_start      date check (period_start is null or period_start = date_trunc('month', period_start)::date),
  period_end        date check (period_end is null or period_end = date_trunc('month', period_end)::date),
  payment_method    public.payment_method,
  collected_by      uuid not null references public.committee_user (id),
  collected_at      timestamptz not null default now(),
  reverses_entry_id uuid unique references public.ledger_entry (id),
  note              text,
  created_at        timestamptz not null default now(),
  -- originals are positive, reversals are negative
  check ((reverses_entry_id is null and amount_paisa > 0)
      or (reverses_entry_id is not null and amount_paisa < 0)),
  check ((period_start is null) = (period_end is null)),
  check (period_end is null or period_end >= period_start),
  check (category <> 'membership_contribution' or (family_id is not null and period_start is not null))
);
create index ledger_entry_family_idx on public.ledger_entry (family_id);

-- Verification is its own fact; it never rewrites the original entry.
create table public.ledger_verification (
  id          uuid primary key default gen_random_uuid(),
  entry_id    uuid not null unique references public.ledger_entry (id),
  verified_by uuid not null references public.committee_user (id),
  verified_at timestamptz not null default now()
);

create table public.receipt_counter (   -- internal; no client access
  receipt_year integer primary key,
  last_seq     integer not null
);

create table public.receipt (
  id           uuid primary key default gen_random_uuid(),
  receipt_year integer not null,
  receipt_seq  integer not null check (receipt_seq > 0),
  entry_id     uuid not null unique references public.ledger_entry (id),
  issued_by    uuid not null references public.committee_user (id),
  issued_at    timestamptz not null default now(),
  unique (receipt_year, receipt_seq)
);

-- ---------------------------------------------------------------- audit (append-only)
create table public.audit_log (
  id         bigint generated always as identity primary key,
  at         timestamptz not null default now(),
  actor      uuid,
  action     text not null,
  table_name text not null,
  record_id  text,
  old_data   jsonb,
  new_data   jsonb
);

-- ---------------------------------------------------------------- guards
create function public.reject_mutation()
returns trigger language plpgsql as $$
begin
  raise exception '% on % is not allowed: this table is append-only', tg_op, tg_table_name
    using errcode = '42501';
end $$;

create function public.reject_delete()
returns trigger language plpgsql as $$
begin
  raise exception 'DELETE on % is not allowed: records are never deleted', tg_table_name
    using errcode = '42501';
end $$;

-- Append-only tables: no UPDATE, DELETE, or TRUNCATE for anyone.
do $$
declare t text;
begin
  foreach t in array array['ledger_entry', 'ledger_verification', 'receipt', 'rule_set', 'audit_log']
  loop
    execute format('create trigger %I before update or delete on public.%I
                    for each row execute function public.reject_mutation()', t || '_no_mutation', t);
    execute format('create trigger %I before truncate on public.%I
                    for each statement execute function public.reject_mutation()', t || '_no_truncate', t);
  end loop;
  -- Never-delete tables: updates are allowed (status, valid_to), deletes are not.
  foreach t in array array['committee_user', 'role_grant', 'person', 'family', 'family_member']
  loop
    execute format('create trigger %I before delete on public.%I
                    for each row execute function public.reject_delete()', t || '_no_delete', t);
    execute format('create trigger %I before truncate on public.%I
                    for each statement execute function public.reject_delete()', t || '_no_truncate', t);
  end loop;
end $$;

-- A family_member row can only be closed (valid_to set once); nothing else changes.
create function public.family_member_close_only()
returns trigger language plpgsql as $$
begin
  if old.valid_to is not null
     or new.id is distinct from old.id
     or new.family_id is distinct from old.family_id
     or new.person_id is distinct from old.person_id
     or new.relation is distinct from old.relation
     or new.valid_from is distinct from old.valid_from
     or new.created_at is distinct from old.created_at
     or new.created_by is distinct from old.created_by then
    raise exception 'family_member rows can only be closed by setting valid_to once'
      using errcode = '42501';
  end if;
  return new;
end $$;
create trigger family_member_close_only
  before update on public.family_member
  for each row execute function public.family_member_close_only();

-- Generic row audit. Runs as table owner so clients cannot interfere with it.
create function public.audit_row()
returns trigger language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  j jsonb := to_jsonb(coalesce(new, old));
begin
  insert into public.audit_log (actor, action, table_name, record_id, old_data, new_data)
  values (auth.uid(), tg_op, tg_table_name, j ->> 'id',
          case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['committee_user', 'role_grant', 'role_permission', 'person', 'family',
                           'family_member', 'rule_set', 'ledger_entry', 'ledger_verification', 'receipt']
  loop
    execute format('create trigger %I after insert or update or delete on public.%I
                    for each row execute function public.audit_row()', t || '_audit', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- RLS: default deny
alter table public.committee_user       enable row level security;
alter table public.role_grant           enable row level security;
alter table public.role_permission      enable row level security;
alter table public.person               enable row level security;
alter table public.family               enable row level security;
alter table public.family_member        enable row level security;
alter table public.rule_set             enable row level security;
alter table public.ledger_entry         enable row level security;
alter table public.ledger_verification  enable row level security;
alter table public.receipt              enable row level security;
alter table public.receipt_counter      enable row level security;
alter table public.audit_log            enable row level security;

-- Read policies only. There are deliberately no INSERT/UPDATE/DELETE policies:
-- all writes happen inside the SECURITY DEFINER functions.
create policy committee_user_read on public.committee_user for select to authenticated
  using (id = auth.uid() or public.has_permission('role.manage'));
create policy role_grant_read on public.role_grant for select to authenticated
  using (user_id = auth.uid() or public.has_permission('role.manage'));
create policy role_permission_read on public.role_permission for select to authenticated
  using (public.has_permission('role.manage'));
create policy person_read on public.person for select to authenticated
  using (public.has_permission('family.read'));
create policy family_read on public.family for select to authenticated
  using (public.has_permission('family.read'));
create policy family_member_read on public.family_member for select to authenticated
  using (public.has_permission('family.read'));
create policy rule_set_read on public.rule_set for select to authenticated
  using (public.has_permission('payment.read'));
create policy ledger_entry_read on public.ledger_entry for select to authenticated
  using (public.has_permission('payment.read'));
create policy ledger_verification_read on public.ledger_verification for select to authenticated
  using (public.has_permission('payment.read'));
create policy receipt_read on public.receipt for select to authenticated
  using (public.has_permission('payment.read'));
create policy audit_log_read on public.audit_log for select to authenticated
  using (public.has_permission('audit.read'));
-- receipt_counter: RLS on, no policy, no grants.

grant select on
  public.committee_user, public.role_grant, public.role_permission, public.person, public.family,
  public.family_member, public.rule_set, public.ledger_entry, public.ledger_verification,
  public.receipt, public.audit_log
to authenticated;
