-- Privilege sentinel for v2-001. Supabase grants every new public table, sequence
-- and function to anon and authenticated by default (mirrored in the local
-- stand-in), so each object must be locked down by name. Rolls back.
begin;
select no_plan();

-- ---------- Signed-out visitors reach nothing --------------------------------------
select is((select count(*) from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'p', 'v')
    and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('anon', c.oid, 'insert')
         or has_table_privilege('anon', c.oid, 'update') or has_table_privilege('anon', c.oid, 'delete')
         or has_table_privilege('anon', c.oid, 'truncate') or has_any_column_privilege('anon', c.oid, 'select')))::int, 0,
  'signed-out visitors have no access to any table');
select is((select count(*) from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'S' and case when c.relkind = 'S' then has_sequence_privilege('anon', c.oid, 'usage') end)::int, 0,
  'or any sequence');
select is((select string_agg(p.oid::regprocedure::text, ', ') from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')), null,
  'or any function');

-- ---------- Signed-in users write only through checked functions ---------------------
select is((select string_agg(c.relname, ', ') from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r'
    and (has_table_privilege('authenticated', c.oid, 'insert') or has_table_privilege('authenticated', c.oid, 'update')
         or has_table_privilege('authenticated', c.oid, 'delete') or has_table_privilege('authenticated', c.oid, 'truncate'))), null,
  'browsers cannot insert, update, delete or truncate any table directly');
select is((select string_agg(c.relname, ', ') from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity), null, 'every table has row level security');
select is((select string_agg(c.relname, ', ') from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'S' and case when c.relkind = 'S' then has_sequence_privilege('authenticated', c.oid, 'usage') end), null,
  'browsers cannot use sequences directly');
select ok(has_column_privilege('authenticated', 'public.profiles', 'display_name', 'update'), 'people can still change their own display name');

-- Internal and service-only functions.
select is((select string_agg(f, ', ') from unnest(array[
    'public.provision_organisation(text, uuid)', 'public.record_invitation_email(uuid, uuid, text, text, text)',
    'public.vv_confirm_attachment(uuid, text, bigint)', 'public.vv_log_attachment_access(uuid, text, uuid)',
    'public.role_in(uuid, uuid)', 'public.may_invite(uuid, public.workspace_role)', 'public.vv_check_time(timestamp with time zone, text)',
    'public.vv_record_workspace(text, uuid)', 'public.forbid_update()', 'public.guard_immutable()', 'public.guard_membership()',
    'public.touch_updated_at()', 'public.default_workspace_products()', 'public.kp_guard_version()']) f
  where has_function_privilege('authenticated', f::regprocedure, 'execute')), null,
  'browsers cannot call internal or service-only functions');
select ok(has_function_privilege('service_role', 'public.record_invitation_email(uuid, uuid, text, text, text)', 'execute'),
  'the invitation email service still can');
select ok(has_function_privilege('authenticated', 'public.create_team(uuid, text)', 'execute'), 'browsers can call the checked team functions');

-- Every security-definer function sets an empty search path.
select is((select string_agg(p.proname, ', ') from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef and not ('search_path=""' = any(coalesce(p.proconfig, '{}')))), null,
  'every security-definer function pins search_path');

select * from finish();
rollback;
