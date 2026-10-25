-- Minimal stand-in for the parts of Supabase the migrations and pgTAP tests rely on.
-- For a THROWAWAY local PostgreSQL 17 only (see run-db-tests.ps1). It isn't real
-- Supabase: no GoTrue, PostgREST, Supabase default privileges or event triggers.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon')          then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role')  then create role service_role nologin bypassrls; end if;
end $$;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create schema if not exists auth;
create table if not exists auth.users (
  id                 uuid primary key,
  email              text,
  email_confirmed_at timestamptz
);
-- Same contract as Supabase: the caller's id from the request JWT claims.
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::json ->> 'sub', '')::uuid
$$;

grant usage on schema public, auth, extensions to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

-- Minimal stand-in for Supabase Storage tables (bucket config + object rows),
-- enough to test the evidence upload rules. Real Storage also checks file size
-- and type itself; here the policies are what's being tested.
create schema if not exists storage;
create table if not exists storage.buckets (
  id text primary key, name text not null, public boolean not null default false,
  file_size_limit bigint, allowed_mime_types text[]
);
create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name text not null,
  owner uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (bucket_id, name)
);
alter table storage.objects enable row level security;
grant usage on schema storage to anon, authenticated, service_role;
grant select, insert, update, delete on storage.objects to authenticated;
grant all on storage.objects, storage.buckets to service_role;
