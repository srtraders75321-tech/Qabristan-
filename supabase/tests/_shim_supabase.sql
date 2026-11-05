-- Minimal stand-in for the parts of Supabase that migrations rely on.
-- FOR LOCAL PLAIN-POSTGRES TESTING ONLY. Real Supabase provides all of this.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end $$;

create schema if not exists auth;
grant usage on schema auth to anon, authenticated;

create table if not exists auth.users (
  id    uuid primary key,
  email text
);

-- Same contract as Supabase: reads the user id from the request JWT claim setting.
create or replace function auth.uid()
returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant execute on function auth.uid() to anon, authenticated;

grant usage on schema public to anon, authenticated;
