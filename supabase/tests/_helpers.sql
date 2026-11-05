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
