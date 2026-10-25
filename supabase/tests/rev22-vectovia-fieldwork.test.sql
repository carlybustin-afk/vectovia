-- pgTAP tests for docs/database/rev22-vectovia-fieldwork.sql.
-- Requires revs 6–22. Synthetic people and data only; everything rolls back.
begin;
select no_plan();

-- Council A (Vectovia on): A1 owner; A3 field officer (Port team); A4 field officer (River team); A5 view only (Port team).
-- Council B (Vectovia on): B1 owner.
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000022f1','r22p1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000022a1','r22a1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000022a3','r22a3@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000022a4','r22a4@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000022a5','r22a5@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000022b1','r22b1@test.invalid',now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000022f1');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values
 ('wsA', public.provision_organisation('SYNTHETIC R22 Council A','00000000-0000-0000-0000-0000000022a1')),
 ('wsB', public.provision_organisation('SYNTHETIC R22 Council B','00000000-0000-0000-0000-0000000022b1'));
insert into public.workspace_members (workspace_id, user_id, role)
 select (select v from ids where k='wsA'), u::uuid, 'member'::public.workspace_role
   from unnest(array['00000000-0000-0000-0000-0000000022a3','00000000-0000-0000-0000-0000000022a4','00000000-0000-0000-0000-0000000022a5']) u;

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.ws(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000022f1');
select public.set_workspace_product(pg_temp.ws('wsA'),'vectovia',true);
select public.set_workspace_product(pg_temp.ws('wsB'),'vectovia',true);
select pg_temp.as_user('00000000-0000-0000-0000-0000000022a1');
insert into ids values ('tPort', public.create_team(pg_temp.ws('wsA'),'SYNTHETIC Port')), ('tRiver', public.create_team(pg_temp.ws('wsA'),'SYNTHETIC River'));
select public.add_team_member(pg_temp.ws('tPort'),'00000000-0000-0000-0000-0000000022a3');
select public.add_team_member(pg_temp.ws('tRiver'),'00000000-0000-0000-0000-0000000022a4');
select public.add_team_member(pg_temp.ws('tPort'),'00000000-0000-0000-0000-0000000022a5');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000022a3','vectovia','field');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000022a4','vectovia','field');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000022a5','vectovia','view');
select public.vv_save_programme('61000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Port',null,'active',null,null,array[pg_temp.ws('tPort')]);
select public.vv_save_site('62000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Dock 4',null,null,null,null,null,51.95,1.30,null,null,null,
  array['61000000-0000-0000-0000-000000000001'::uuid]);
select public.vv_save_site('62000000-0000-0000-0000-000000000002',pg_temp.ws('wsA'),'SYNTHETIC Dock 7',null,null,null,null,null,51.96,1.31,null,null,null,
  array['61000000-0000-0000-0000-000000000001'::uuid]);
select public.vv_save_trap('63000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'BG-01',(select id from public.vv_trap_types where key='bg_sentinel'),null,null,null);

-- ---------- Deploying ---------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000022a5');
select throws_ok($$select public.vv_deploy_trap('64000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'63000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000001',null,null,null,now() - interval '20 days',null,7)$$, '42501', null, 'view-only cannot deploy');
select pg_temp.as_user('00000000-0000-0000-0000-0000000022a4');
select throws_ok($$select public.vv_deploy_trap('64000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'63000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000001',null,null,null,now() - interval '20 days',null,7)$$, '22023', null, 'nor at a site you cannot see');
select pg_temp.as_user('00000000-0000-0000-0000-0000000022a3');
select throws_ok($$select public.vv_deploy_trap('64000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'63000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000001',null,null,null,now() + interval '2 days',null,7)$$, '22023', null, 'a deployment cannot start in the future');
select lives_ok($$select public.vv_deploy_trap('64000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'63000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000001',null,null,'SYNTHETIC on the fence',now() - interval '20 days',null,7)$$, 'field officer deploys BG-01 at Dock 4');
select lives_ok($$select public.vv_deploy_trap('64000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'63000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000001',null,null,'SYNTHETIC on the fence',now() - interval '20 days',null,7)$$, 'retrying is harmless');
select is((select status from public.vv_traps where id='63000000-0000-0000-0000-000000000001'), 'deployed', 'the trap is now deployed');
select is((select latitude from public.vv_deployments where id='64000000-0000-0000-0000-000000000001'), 51.95::double precision, 'location defaults to the site''s');
select throws_ok($$select public.vv_deploy_trap('64000000-0000-0000-0000-000000000002',pg_temp.ws('wsA'),'63000000-0000-0000-0000-000000000001',
  '62000000-0000-0000-0000-000000000002',null,null,null,now(),null,7)$$, '22023', null, 'a deployed trap cannot be deployed twice');

-- ---------- Schedule: overdue when nobody has visited ------------------------------------
select is((select state from public.vv_visit_schedule(pg_temp.ws('wsA'))), 'overdue', 'no visit 20 days after deployment shows as overdue (not checked)');

-- ---------- Visits ------------------------------------------------------------------------
select throws_ok($$select public.vv_record_visit('65000000-0000-0000-0000-000000000001','64000000-0000-0000-0000-000000000001',now() - interval '13 days',null,
  'collected',null,'working',null,now() - interval '20 days',now() - interval '13 days','[]')$$, '22023', null, 'collected needs at least one sample');
select throws_ok($$select public.vv_record_visit('65000000-0000-0000-0000-000000000001','64000000-0000-0000-0000-000000000001',now() - interval '13 days',null,
  'no_catch',null,'working',null,null,null,'[{"id":"66000000-0000-0000-0000-000000000009","method":"adult_trap_catch"}]')$$, '22023', null,
  'no catch has no samples');
select throws_ok($$select public.vv_record_visit('65000000-0000-0000-0000-000000000001','64000000-0000-0000-0000-000000000001',now() - interval '13 days',null,
  'not_completed','','working',null,null,null,'[]')$$, '23514', null, 'not completed needs a reason');
select throws_ok($$select public.vv_record_visit('65000000-0000-0000-0000-000000000001','64000000-0000-0000-0000-000000000001',now() - interval '30 days',null,
  'no_catch',null,'working',null,null,null,'[]')$$, '22023', null, 'a visit cannot be before the deployment');
select lives_ok($$select public.vv_record_visit('65000000-0000-0000-0000-000000000001','64000000-0000-0000-0000-000000000001',now() - interval '13 days',null,
  'collected',null,'working','SYNTHETIC lots of activity',now() - interval '20 days',now() - interval '13 days',
  '[{"id":"66000000-0000-0000-0000-000000000001","reference":"","method":"adult_trap_catch"},{"id":"66000000-0000-0000-0000-000000000002","reference":"TUBE-7","method":"adult_trap_catch","notes":"SYNTHETIC"}]')$$,
  'visit with two samples (one numbered by the council, one typed)');
select lives_ok($$select public.vv_record_visit('65000000-0000-0000-0000-000000000001','64000000-0000-0000-0000-000000000001',now() - interval '13 days',null,
  'collected',null,'working','SYNTHETIC lots of activity',now() - interval '20 days',now() - interval '13 days',
  '[{"id":"66000000-0000-0000-0000-000000000001","reference":"","method":"adult_trap_catch"},{"id":"66000000-0000-0000-0000-000000000002","reference":"TUBE-7","method":"adult_trap_catch","notes":"SYNTHETIC"}]')$$,
  'sending the same visit again (e.g. offline retry) is harmless');
select is((select string_agg(reference, ',' order by reference) from public.vv_samples), 'TUBE-7,VS-S00001', 'sample references');
select is((select count(*) from public.vv_samples where status = 'awaiting_result')::int, 2, 'both samples are awaiting results');
select is((select v.occurred_at < v.recorded_at from public.vv_visits v where id = '65000000-0000-0000-0000-000000000001'), true,
  'when it happened is kept separate from when it was entered');
select lives_ok($$select public.vv_record_visit('65000000-0000-0000-0000-000000000002','64000000-0000-0000-0000-000000000001',now() - interval '6 days',null,
  'no_catch',null,'working',null,now() - interval '13 days',now() - interval '6 days','[]')$$, 'a no-catch visit');
select lives_ok($$select public.vv_record_visit('65000000-0000-0000-0000-000000000003','64000000-0000-0000-0000-000000000001',now() - interval '1 day',null,
  'not_completed','SYNTHETIC gate locked','working',null,null,null,'[]')$$, 'a visit where collection was not completed');
select is((select string_agg(outcome, ',' order by occurred_at) from public.vv_visits), 'collected,no_catch,not_completed',
  'collected, no catch and not completed are recorded distinctly');
select is((select state from public.vv_visit_schedule(pg_temp.ws('wsA'))), 'scheduled', 'after a recent visit the trap is back on schedule');
select throws_ok($$update public.vv_visits set outcome = 'no_catch'$$, '42501', null, 'no direct edits to visits');

-- Corrections keep previous values.
select throws_ok($$select public.vv_correct_visit('65000000-0000-0000-0000-000000000002',null,null,'damaged',null,null,null,null,'')$$, '22023', null,
  'a correction needs a reason');
select lives_ok($$select public.vv_correct_visit('65000000-0000-0000-0000-000000000002',null,null,'damaged','SYNTHETIC fan cracked',null,null,null,'SYNTHETIC missed this')$$,
  'correct a visit');
select is((select detail->'trap_condition'->>'from' from public.vv_events where record_id='65000000-0000-0000-0000-000000000002' and kind='corrected'),
  'working', 'the previous value is kept');
select is((select outcome from public.vv_visits where id='65000000-0000-0000-0000-000000000002'), 'no_catch', 'the outcome itself is unchanged');

-- ---------- Moving a trap keeps its history ---------------------------------------------------
select lives_ok($$select public.vv_move_trap('64000000-0000-0000-0000-000000000001','64000000-0000-0000-0000-000000000002',
  '62000000-0000-0000-0000-000000000002',null,null,'SYNTHETIC new spot',now(),null,14)$$, 'move BG-01 to Dock 7');
select lives_ok($$select public.vv_move_trap('64000000-0000-0000-0000-000000000001','64000000-0000-0000-0000-000000000002',
  '62000000-0000-0000-0000-000000000002',null,null,'SYNTHETIC new spot',now(),null,14)$$, 'retrying the move is harmless');
select is((select count(*) from public.vv_deployments where trap_id='63000000-0000-0000-0000-000000000001')::int, 2, 'both deployments are kept');
select is((select end_reason from public.vv_deployments where id='64000000-0000-0000-0000-000000000001'), 'moved', 'the first ended as moved');
select is((select count(*) from public.vv_visits where deployment_id='64000000-0000-0000-0000-000000000001')::int, 3,
  'its visits stay with the old deployment');
select is((select status from public.vv_traps where id='63000000-0000-0000-0000-000000000001'), 'deployed', 'the trap is deployed at its new site');
select lives_ok($$select public.vv_end_deployment('64000000-0000-0000-0000-000000000002',now(),'damaged','SYNTHETIC storm')$$, 'end the new deployment as damaged');
select is((select status from public.vv_traps where id='63000000-0000-0000-0000-000000000001'), 'damaged', 'the trap is marked damaged');
select is((select count(*) from public.vv_visit_schedule(pg_temp.ws('wsA')))::int, 0, 'no active deployments left on the schedule');

-- ---------- Who can see what ---------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000022a5');
select is((select count(*) from public.vv_samples)::int, 2, 'view-only Port member sees the samples');
select throws_ok($$select public.vv_record_visit('65000000-0000-0000-0000-000000000009','64000000-0000-0000-0000-000000000002',now(),null,
  'no_catch',null,'working',null,null,null,'[]')$$, '42501', null, 'but cannot record visits');
select pg_temp.as_user('00000000-0000-0000-0000-0000000022a4');
select is((select count(*) from public.vv_deployments)::int + (select count(*) from public.vv_visits)::int + (select count(*) from public.vv_samples)::int, 0,
  'River officer sees nothing at Port sites');
select pg_temp.as_user('00000000-0000-0000-0000-0000000022b1');
select is((select count(*) from public.vv_deployments)::int + (select count(*) from public.vv_visits)::int + (select count(*) from public.vv_samples)::int, 0,
  'another council sees nothing');
select throws_ok($$select public.vv_end_deployment('64000000-0000-0000-0000-000000000001',now(),'removed',null)$$, '42501', null, 'nor ends our deployments');
select is((select count(*) from public.vv_visit_schedule(pg_temp.ws('wsA')))::int, 0, 'nor sees our schedule');
reset role;
select throws_ok($$delete from public.vv_samples$$, '42501', null, 'samples are never deleted');

select * from finish();
rollback;
