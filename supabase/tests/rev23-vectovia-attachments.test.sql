-- pgTAP tests for docs/database/rev23-vectovia-attachments.sql.
-- Requires revs 6–23. Synthetic people and data only; everything rolls back.
begin;
select no_plan();

-- Council A (Vectovia on): A1 owner; A3 field officer (Port team); A4 field officer (River team); A5 view only (Port team). Council B: B1 owner.
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000023f1','r23p1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000023a1','r23a1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000023a3','r23a3@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000023a4','r23a4@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000023a5','r23a5@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000023b1','r23b1@test.invalid',now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000023f1');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values
 ('wsA', public.provision_organisation('SYNTHETIC R23 Council A','00000000-0000-0000-0000-0000000023a1')),
 ('wsB', public.provision_organisation('SYNTHETIC R23 Council B','00000000-0000-0000-0000-0000000023b1'));
insert into public.workspace_members (workspace_id, user_id, role)
 select (select v from ids where k='wsA'), u::uuid, 'member'::public.workspace_role
   from unnest(array['00000000-0000-0000-0000-0000000023a3','00000000-0000-0000-0000-0000000023a4','00000000-0000-0000-0000-0000000023a5']) u;

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.ws(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000023f1');
select public.set_workspace_product(pg_temp.ws('wsA'),'vectovia',true);
select public.set_workspace_product(pg_temp.ws('wsB'),'vectovia',true);
select pg_temp.as_user('00000000-0000-0000-0000-0000000023a1');
insert into ids values ('tPort', public.create_team(pg_temp.ws('wsA'),'SYNTHETIC Port')), ('tRiver', public.create_team(pg_temp.ws('wsA'),'SYNTHETIC River'));
select public.add_team_member(pg_temp.ws('tPort'),'00000000-0000-0000-0000-0000000023a3');
select public.add_team_member(pg_temp.ws('tRiver'),'00000000-0000-0000-0000-0000000023a4');
select public.add_team_member(pg_temp.ws('tPort'),'00000000-0000-0000-0000-0000000023a5');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000023a3','vectovia','field');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000023a4','vectovia','field');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000023a5','vectovia','view');
select public.vv_save_programme('71000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Port',null,'active',null,null,array[pg_temp.ws('tPort')]);
select public.vv_save_site('72000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Dock 4',null,null,null,null,null,51.95,1.30,null,null,null,
  array['71000000-0000-0000-0000-000000000001'::uuid]);
select public.vv_save_trap('73000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'BG-01',(select id from public.vv_trap_types where key='bg_sentinel'),null,null,null);
select public.vv_deploy_trap('74000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'73000000-0000-0000-0000-000000000001',
  '72000000-0000-0000-0000-000000000001',null,null,null,now() - interval '7 days',null,7);
select public.vv_record_visit('75000000-0000-0000-0000-000000000001','74000000-0000-0000-0000-000000000001',now() - interval '1 hour',null,
  'collected',null,'working',null,null,null,'[{"id":"76000000-0000-0000-0000-000000000001","reference":"T-1","method":"adult_trap_catch"}]');

create temp table paths (k text, p text); grant all on paths to authenticated;

-- ---------- Registering ----------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000023a5');
select throws_ok($$select public.vv_register_attachment('77000000-0000-0000-0000-000000000001','visit','75000000-0000-0000-0000-000000000001',
  'trap.jpg','image/jpeg',10,repeat('a',64),null,null,'unknown')$$, '42501', null, 'view-only cannot add files');
select pg_temp.as_user('00000000-0000-0000-0000-0000000023a4');
select throws_ok($$select public.vv_register_attachment('77000000-0000-0000-0000-000000000001','visit','75000000-0000-0000-0000-000000000001',
  'trap.jpg','image/jpeg',10,repeat('a',64),null,null,'unknown')$$, '42501', null, 'nor can someone who cannot see the site');
select pg_temp.as_user('00000000-0000-0000-0000-0000000023a3');
insert into paths select 'visit', public.vv_register_attachment('77000000-0000-0000-0000-000000000001','visit','75000000-0000-0000-0000-000000000001',
  'Trap photo 1.jpg','image/jpeg',10,repeat('a',64),'SYNTHETIC trap on fence',now() - interval '1 hour','device_metadata');
select matches((select p from paths where k='visit'), '^[0-9a-f-]{36}/visit/75000000-0000-0000-0000-000000000001/77000000-0000-0000-0000-000000000001/Trap_photo_1.jpg$',
  'the server chooses the storage path (council / record / item / safe name)');
select is(public.vv_register_attachment('77000000-0000-0000-0000-000000000001','visit','75000000-0000-0000-0000-000000000001',
  'Trap photo 1.jpg','image/jpeg',10,repeat('a',64),null,null,'unknown'), (select p from paths where k='visit'), 'registering again is retry-safe');
select is((select kind || '/' || status || '/' || capture_source from public.vv_attachments where id='77000000-0000-0000-0000-000000000001'),
  'photo/pending/device_metadata', 'a photo, pending its fingerprint check, with capture time from the device');
select ok((select captured_at < received_at from public.vv_attachments where id='77000000-0000-0000-0000-000000000001'),
  'capture time is kept separate from when the server received it');
insert into paths select 'sample', public.vv_register_attachment('77000000-0000-0000-0000-000000000002','sample','76000000-0000-0000-0000-000000000001',
  'lab form.pdf','application/pdf',20,repeat('b',64),null,null,'unknown');
insert into paths select 'site', public.vv_register_attachment('77000000-0000-0000-0000-000000000003','site','72000000-0000-0000-0000-000000000001',
  'access map.png','image/png',30,repeat('c',64),null,null,'unknown');
select is((select count(*) from public.vv_attachments)::int, 3, 'files on a visit, a sample and a site');
select throws_ok($$select public.vv_register_attachment('77000000-0000-0000-0000-000000000004','visit','75000000-0000-0000-0000-000000000001',
  'virus.exe','application/x-msdownload',10,repeat('a',64),null,null,'unknown')$$, '23514', null, 'only the agreed file types');
select throws_ok($$select public.vv_register_attachment('77000000-0000-0000-0000-000000000004','visit','75000000-0000-0000-0000-000000000001',
  'huge.jpg','image/jpeg',30000000,repeat('a',64),null,null,'unknown')$$, '23514', null, 'files up to 25 MB');
select throws_ok($$update public.vv_attachments set status = 'verified'$$, '42501', null, 'nobody can mark their own upload verified');

-- ---------- Fingerprint check (service role only) ------------------------------------------
select throws_ok($$select public.vv_confirm_attachment('77000000-0000-0000-0000-000000000001', repeat('a',64), 10)$$, '42501', null,
  'a signed-in user cannot confirm a fingerprint');
reset role;
set local role service_role;
select is(public.vv_confirm_attachment('77000000-0000-0000-0000-000000000001', repeat('a',64), 10), 'verified', 'matching file is verified');
select is(public.vv_confirm_attachment('77000000-0000-0000-0000-000000000002', repeat('f',64), 20), 'mismatch', 'a different file is a mismatch');
select is(public.vv_confirm_attachment('77000000-0000-0000-0000-000000000002', repeat('b',64), 20), 'mismatch', 'and the decision is never re-made');
select lives_ok($$select public.vv_log_attachment_access('77000000-0000-0000-0000-000000000001','viewed','00000000-0000-0000-0000-0000000023a5')$$, 'a view is logged');
reset role;

-- ---------- Reading and corrections -------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000023a5');
select is((select count(*) from public.vv_attachments)::int, 3, 'view-only Port member sees the files');
select is((select string_agg(action, ',' order by id) from public.vv_attachment_events where attachment_id='77000000-0000-0000-0000-000000000001'),
  'registered,verified,viewed', 'and their handling log');
select throws_ok($$select public.vv_correct_attachment('77000000-0000-0000-0000-000000000001','x',null,'unknown','SYNTHETIC fix')$$, '42501', null,
  'but cannot change them');
select pg_temp.as_user('00000000-0000-0000-0000-0000000023a3');
select throws_ok($$select public.vv_correct_attachment('77000000-0000-0000-0000-000000000001','SYNTHETIC new caption',null,'unknown','')$$, '22023', null,
  'a correction needs a reason');
select lives_ok($$select public.vv_correct_attachment('77000000-0000-0000-0000-000000000001','SYNTHETIC trap on north fence',now() - interval '2 hours','officer','SYNTHETIC wrong fence')$$,
  'correct the caption and capture time');
select is((select detail->'from'->>'caption' from public.vv_attachment_events where action='caption_corrected'), 'SYNTHETIC trap on fence', 'the previous caption is kept');
select pg_temp.as_user('00000000-0000-0000-0000-0000000023a4');
select is((select count(*) from public.vv_attachments)::int + (select count(*) from public.vv_attachment_events)::int, 0, 'River officer sees no Port files');
select pg_temp.as_user('00000000-0000-0000-0000-0000000023b1');
select is((select count(*) from public.vv_attachments)::int, 0, 'another council sees no files');
select ok(not public.vv_can_read_attachment('77000000-0000-0000-0000-000000000001'), 'nor can read one by its ID');
select throws_ok($$select public.vv_register_attachment('77000000-0000-0000-0000-000000000009','site','72000000-0000-0000-0000-000000000001',
  'x.jpg','image/jpeg',10,repeat('a',64),null,null,'unknown')$$, '42501', null, 'nor add files to our site');
reset role;
select throws_ok($$delete from public.vv_attachments$$, '42501', null, 'originals are never deleted');
select throws_ok($$delete from public.vv_attachment_events$$, '42501', null, 'the handling log is append-only');

select * from finish();
rollback;
