-- Tiny assertion helpers (pgTAP is not available in every environment).
-- Each test file runs as superuser and switches identity with t.login()/t.logout().

create schema if not exists t;
grant usage on schema t to anon, authenticated;

create table if not exists t.results (name text, ok boolean, detail text);
grant all on t.results to anon, authenticated;

create or replace function t.ok(p_cond boolean, p_name text)
returns void language plpgsql as $$
begin
  insert into t.results values (p_name, coalesce(p_cond, false), null);
end $$;

create or replace function t.eq(p_actual anyelement, p_expected anyelement, p_name text)
returns void language plpgsql as $$
begin
  insert into t.results values (p_name, p_actual is not distinct from p_expected,
    case when p_actual is not distinct from p_expected then null
         else format('expected %L, got %L', p_expected, p_actual) end);
end $$;

-- Runs SQL and records pass when it raises an error whose message matches p_pattern.
create or replace function t.throws(p_sql text, p_pattern text, p_name text)
returns void language plpgsql as $$
declare msg text;
begin
  begin
    execute p_sql;
    insert into t.results values (p_name, false, 'no error raised');
  exception when others then
    get stacked diagnostics msg = message_text;
    insert into t.results values (p_name, msg ~* p_pattern,
      case when msg ~* p_pattern then null else 'error was: ' || msg end);
  end;
end $$;

-- Runs SQL and records pass when it succeeds.
create or replace function t.lives(p_sql text, p_name text)
returns void language plpgsql as $$
declare msg text;
begin
  begin
    execute p_sql;
    insert into t.results values (p_name, true, null);
  exception when others then
    get stacked diagnostics msg = message_text;
    insert into t.results values (p_name, false, 'unexpected error: ' || msg);
  end;
end $$;

-- Act as a signed-in user (authenticated role + JWT subject) or go back to superuser.
create or replace function t.login(p_user uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_user::text, false);
  execute 'set role authenticated';
end $$;

create or replace function t.logout()
returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', false);
end $$;

-- ------------------------------------------------------------------------------------------
-- Deliberate-corruption helper for the reconciliation tests.
-- Applies p_sql inside a sub-transaction (with user triggers bypassed unless p_replica is
-- false, so protected tables can be corrupted the way a bug or a database owner could),
-- then checks that check p_check reports MORE violations than before. The corruption is
-- always rolled back. Records one result row.
--   p_user: when given, the count is taken through the permission-checked public API as that
--           user instead of the internal runner.
create or replace function t.corrupt(
  p_sql text, p_check text, p_name text,
  p_replica boolean default true, p_user uuid default null)
returns void language plpgsql as $$
declare base int; after_n int; err text;
begin
  select count(*) into base from public._recon_run(p_check);
  begin
    if p_replica then perform set_config('session_replication_role', 'replica', true); end if;
    execute p_sql;
    perform set_config('session_replication_role', 'origin', true);
    if p_user is not null then
      perform set_config('request.jwt.claim.sub', p_user::text, true);
      execute 'set local role authenticated';
      select count(*) into after_n from public.reconciliation_violations(p_check);
    else
      select count(*) into after_n from public._recon_run(p_check);
    end if;
    raise exception 't_rollback';
  exception when others then
    get stacked diagnostics err = message_text;
    if err <> 't_rollback' then
      insert into t.results values (p_name, false, 'corruption step failed: ' || err);
      return;
    end if;
  end;
  insert into t.results values (p_name, after_n > base,
    case when after_n > base then null else format('violations before=%s after=%s', base, after_n) end);
end $$;

-- Test helpers only. Production functions are NOT executable by clients unless approved
-- (see migration 20261105000005 and reconciliation check C17).
grant execute on all functions in schema t to anon, authenticated;
