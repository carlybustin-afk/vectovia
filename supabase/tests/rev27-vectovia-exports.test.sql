-- pgTAP tests for the export log and external references (from First Line rev27,
-- without case links). Synthetic people and data only; everything rolls back.
begin;
select no_plan();

-- Organisation A: A1 owner; A2 and A3 Vectovia managers; A4 field officer; A5 view only. Organisation B: B1 owner.
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000027f1','r27p1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000027a1','r27a1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000027a2','r27a2@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000027a3','r27a3@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000027a4','r27a4@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000027a5','r27a5@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000027b1','r27b1@test.invalid',now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000027f1');
create temp table ids (k text primary key, v uuid);
create temp table refs (k text primary key, v text);
grant all on ids, refs to authenticated;
insert into ids values
 ('wsA', public.provision_organisation('SYNTHETIC R27 Organisation A','00000000-0000-0000-0000-0000000027a1')),
 ('wsB', public.provision_organisation('SYNTHETIC R27 Organisation B','00000000-0000-0000-0000-0000000027b1'));
insert into public.workspace_members (workspace_id, user_id, role)
 select (select v from ids where k='wsA'), u::uuid, 'member'::public.workspace_role
   from unnest(array['00000000-0000-0000-0000-0000000027a2','00000000-0000-0000-0000-0000000027a3','00000000-0000-0000-0000-0000000027a4',
                     '00000000-0000-0000-0000-0000000027a5']) u;

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.ws(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;
create function pg_temp.ref(k text) returns text language sql as $$ select v from refs where refs.k = $1 $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000027f1');
select public.set_workspace_product(pg_temp.ws('wsA'),'vectovia',true);
select public.set_workspace_product(pg_temp.ws('wsB'),'vectovia',true);
select pg_temp.as_user('00000000-0000-0000-0000-0000000027a1');
insert into ids values ('tPort', public.create_team(pg_temp.ws('wsA'),'SYNTHETIC Port'));
select public.add_team_member(pg_temp.ws('tPort'), u) from unnest(array['00000000-0000-0000-0000-0000000027a3',
  '00000000-0000-0000-0000-0000000027a4']::uuid[]) u;
select public.set_product_access(pg_temp.ws('wsA'), u::uuid,'vectovia','manage')
  from unnest(array['00000000-0000-0000-0000-0000000027a2','00000000-0000-0000-0000-0000000027a3']) u;
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000027a4','vectovia','field');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000027a5','vectovia','view');
select public.vv_save_site('b2000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Dock 4',null,null,null,null,null,51.95,1.30,null,null,null,'{}');

-- ---------- Export log ------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000027a5');
select lives_ok($$select public.vv_log_export('b3000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'report_pdf',
  '{"from":"2026-01-01","to":"2026-10-17"}','{"sites":1}','vectovia-report.pdf',1234,repeat('a',64),'report-v1')$$, 'view-only can log a report');
select lives_ok($$select public.vv_log_export('b3000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'report_pdf',
  '{}','{}','vectovia-report.pdf',1234,repeat('a',64),'report-v1')$$, 'logging again is safe');
select throws_ok($$select public.vv_log_export('b3000000-0000-0000-0000-000000000002',pg_temp.ws('wsA'),'csv',
  '{}','{}','x.csv',10,'not-a-fingerprint','csv-v1')$$, '23514', null, 'the fingerprint must be a SHA-256');
select is((select count(*) from public.vv_exports)::int, 1, 'they see their own export');
select is((select created_role from public.vv_exports), 'view (member)', 'with their role at the time');
select throws_ok($$update public.vv_exports set file_name = 'changed.pdf'$$, '42501', null, 'the export log cannot be changed');
select pg_temp.as_user('00000000-0000-0000-0000-0000000027a4');
select is((select count(*) from public.vv_exports)::int, 0, 'a field officer does not see other people''s exports');
select pg_temp.as_user('00000000-0000-0000-0000-0000000027a2');
select is((select count(*) from public.vv_exports)::int, 1, 'a manager sees the organisation''s export log');
select pg_temp.as_user('00000000-0000-0000-0000-0000000027b1');
select throws_ok($$select public.vv_log_export('b3000000-0000-0000-0000-000000000003',pg_temp.ws('wsA'),'csv',
  '{}','{}','x.csv',10,repeat('b',64),'csv-v1')$$, '42501', null, 'another organisation cannot log exports here');
select is((select count(*) from public.vv_exports)::int, 0, 'or see the log');

-- ---------- External references -----------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000027a4');
select throws_ok($$select public.vv_save_external_ref('b5000000-0000-0000-0000-000000000001','site','b2000000-0000-0000-0000-000000000001',
  'Idox','SYN/123',null)$$, '42501', null, 'a field officer cannot add external references');
select pg_temp.as_user('00000000-0000-0000-0000-0000000027a2');
select lives_ok($$select public.vv_save_external_ref('b5000000-0000-0000-0000-000000000001','site','b2000000-0000-0000-0000-000000000001',
  'Idox','SYN/123','SYNTHETIC premises record')$$, 'a manager records another system''s reference');
select throws_ok($$select public.vv_save_external_ref('b5000000-0000-0000-0000-000000000002','site','b2000000-0000-0000-0000-000000000001',
  'idox','SYN/123',null)$$, '23505', null, 'the same external reference cannot be recorded twice');
select pg_temp.as_user('00000000-0000-0000-0000-0000000027a5');
select is((select external_id from public.vv_external_refs), 'SYN/123', 'anyone who can see the site sees it');
select pg_temp.as_user('00000000-0000-0000-0000-0000000027b1');
select is((select count(*) from public.vv_external_refs)::int, 0, 'another organisation does not');
select pg_temp.as_user('00000000-0000-0000-0000-0000000027a2');
select throws_ok($$select public.vv_remove_external_ref('b5000000-0000-0000-0000-000000000001','')$$, '22023', null, 'removing needs a reason');
select lives_ok($$select public.vv_remove_external_ref('b5000000-0000-0000-0000-000000000001','SYNTHETIC wrong premises')$$, 'removed with a reason');
select throws_ok($$update public.vv_external_refs set external_id = 'SYN/999'$$, '42501', null, 'references cannot be rewritten');

-- ---------- Grants ---------------------------------------------------------------------------
reset role;
select ok(not has_table_privilege('anon', 'public.vv_exports', 'select'), 'signed-out visitors cannot read the export log');
select ok(not has_function_privilege('authenticated', 'public.vv_record_workspace(text, uuid)', 'execute'), 'the internal helper is not callable');

select * from finish();
rollback;
