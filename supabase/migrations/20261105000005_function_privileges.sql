-- Function execute privileges: closes a gap in migrations 1-3.
--
-- THE PROBLEM. Migration 1 ran
--     alter default privileges in schema public revoke execute on functions from public;
-- intending to keep functions private. That statement cannot do it: a schema-specific default
-- can only ADD privileges; it cannot remove the global default under which PUBLIC may execute
-- every new function. Result: every function in `public`, including internal SECURITY DEFINER
-- helpers (_booked_months, _covered_months, _require, month_index ...), was executable by the
-- anon and authenticated roles. The business functions still check permissions inside, so they
-- were not exploitable, but the internal helpers have no permission check and any signed-in
-- client could, for example, read which months a family has paid. (On Supabase, platform
-- default privileges grant EXECUTE to anon/authenticated on new functions as well.)
--
-- THE FIX. Remove execute from PUBLIC, anon and authenticated on every function we own in
-- `public` (extension-owned functions are left alone), then grant back ONLY the functions
-- that clients are meant to call. No function body or table is changed, so the payment
-- ledger and its behaviour are untouched.
--
-- GOING FORWARD. New client-callable functions must be added to this list in their own
-- migration AND to public._client_functions(). Reconciliation check C17 fails if either is
-- forgotten, or if any other function becomes executable by clients.

do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as fn
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind in ('f', 'p')
       and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.fn);
  end loop;
end $$;

-- Global default for functions this role creates from now on (the earlier IN SCHEMA form
-- could not do this).
alter default privileges revoke execute on functions from public;

grant execute on function
  public.has_permission(text),
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
  public.family_balance(uuid, date),
  public.register_burial_for_member(uuid, date, date, text, text),
  public.register_burial_non_member(text, text, date, date, date, text, text, boolean),
  public.update_burial_details(uuid, date, text, text),
  public.correct_non_member_deceased(uuid, text, text, date, date),
  public.void_burial(uuid, text),
  public.record_burial_approval(uuid, text, date, text, text, text),
  public.record_burial_payment(uuid, bigint, public.payment_method, text),
  public.reconciliation_violations(text),
  public.reconciliation_report()
to authenticated;
