-- pgTAP tests for docs/database/rev26-vectovia-incursions.sql.
-- Requires revs 6–26. Synthetic people and data only; everything rolls back.
begin;
select no_plan();

-- Council A: A1 owner; A2 manager; A3 field officer (Port team, the lead); A4 field officer (Port team, not the lead);
-- A5 view only (Port team); A6 field officer not in the Port team. Council B: B1 owner.
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000026f1','r26p1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000026a1','r26a1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000026a2','r26a2@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000026a3','r26a3@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000026a4','r26a4@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000026a5','r26a5@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000026a6','r26a6@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000026b1','r26b1@test.invalid',now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000026f1');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values
 ('wsA', public.provision_organisation('SYNTHETIC R26 Council A','00000000-0000-0000-0000-0000000026a1')),
 ('wsB', public.provision_organisation('SYNTHETIC R26 Council B','00000000-0000-0000-0000-0000000026b1'));
insert into public.workspace_members (workspace_id, user_id, role)
 select (select v from ids where k='wsA'), u::uuid, 'member'::public.workspace_role
   from unnest(array['00000000-0000-0000-0000-0000000026a2','00000000-0000-0000-0000-0000000026a3','00000000-0000-0000-0000-0000000026a4',
                     '00000000-0000-0000-0000-0000000026a5','00000000-0000-0000-0000-0000000026a6']) u;

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.ws(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;
create function pg_temp.taxon(k text) returns uuid language sql as $$ select id from public.vv_taxa where key = $1 $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000026f1');
select public.set_workspace_product(pg_temp.ws('wsA'),'vectovia',true);
select public.set_workspace_product(pg_temp.ws('wsB'),'vectovia',true);
select pg_temp.as_user('00000000-0000-0000-0000-0000000026a1');
insert into ids values ('tPort', public.create_team(pg_temp.ws('wsA'),'SYNTHETIC Port'));
select public.add_team_member(pg_temp.ws('tPort'), u) from unnest(array['00000000-0000-0000-0000-0000000026a3',
  '00000000-0000-0000-0000-0000000026a4','00000000-0000-0000-0000-0000000026a5']::uuid[]) u;
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000026a2','vectovia','manage');
select public.set_product_access(pg_temp.ws('wsA'), u::uuid,'vectovia','field')
  from unnest(array['00000000-0000-0000-0000-0000000026a3','00000000-0000-0000-0000-0000000026a4','00000000-0000-0000-0000-0000000026a6']) u;
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000026a5','vectovia','view');
select public.vv_save_programme('a1000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Port',null,'active',null,null,array[pg_temp.ws('tPort')]);
select public.vv_save_site('a2000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Dock 4',null,null,null,null,null,51.95,1.30,null,null,null,
  array['a1000000-0000-0000-0000-000000000001'::uuid]);
select public.vv_save_site('a2000000-0000-0000-0000-000000000002',pg_temp.ws('wsA'),'SYNTHETIC Dock 5',null,null,null,null,null,51.96,1.31,null,null,null,
  array['a1000000-0000-0000-0000-000000000001'::uuid]);
select public.vv_save_trap('a3000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'BG-01',(select id from public.vv_trap_types where key='bg_sentinel'),null,null,null);
select public.vv_deploy_trap('a4000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'a3000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000001',null,null,null,now() - interval '7 days',null,7);
select public.vv_record_visit('a5000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001',now() - interval '1 day',null,
  'collected',null,'working',null,now() - interval '7 days',now() - interval '1 day',
  '[{"id":"a6000000-0000-0000-0000-000000000001","reference":"T-1","method":"adult_trap_catch"}]');
select public.vv_save_result('a7000000-0000-0000-0000-000000000001','a6000000-0000-0000-0000-000000000001','provisional',
  pg_temp.taxon('aedes_albopictus'),null,3,'females','morphology','SYNTHETIC Officer',null,null,current_date,null,null);

-- ---------- Opening -----------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000026a3');
select throws_ok($$select public.vv_open_incursion('a8000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001',
  array['a7000000-0000-0000-0000-000000000001'::uuid],'SYNTHETIC Albopictus at Dock 4',pg_temp.taxon('aedes_albopictus'),null,null,'suspected')$$,
  '42501', null, 'a field officer cannot open an incursion');
select pg_temp.as_user('00000000-0000-0000-0000-0000000026a2');
select throws_ok($$select public.vv_open_incursion('a8000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001',
  '{}','SYNTHETIC Albopictus at Dock 4',pg_temp.taxon('aedes_albopictus'),null,null,'suspected')$$, '22023', null, 'it must come from a finding');
select throws_ok($$select public.vv_open_incursion('a8000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001',
  array['a7000000-0000-0000-0000-000000000001'::uuid],'SYNTHETIC Albopictus at Dock 4',pg_temp.taxon('aedes_albopictus'),null,
  '00000000-0000-0000-0000-0000000026a5','suspected')$$, '22023', null, 'a view-only member cannot be the lead officer');
select throws_ok($$select public.vv_open_incursion('a8000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001',
  array['a7000000-0000-0000-0000-000000000001'::uuid],'SYNTHETIC Albopictus at Dock 4',pg_temp.taxon('aedes_albopictus'),null,null,'stood_down')$$,
  '22023', null, 'it opens as suspected or confirmed');
select is(public.vv_open_incursion('a8000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001',
  array['a7000000-0000-0000-0000-000000000001'::uuid],'SYNTHETIC Albopictus at Dock 4',pg_temp.taxon('aedes_albopictus'),null,
  '00000000-0000-0000-0000-0000000026a3','suspected'), 'VS-I0001', 'a manager opens an incursion with a reference');
select is(public.vv_open_incursion('a8000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001',
  array['a7000000-0000-0000-0000-000000000001'::uuid],'SYNTHETIC again',null,null,null,'suspected'), 'VS-I0001', 'retrying gives the same incursion');
select is((select count(*) from public.vv_incursions)::int, 1, 'only one incursion');
select is((select string_agg(step_key, ',' order by sort_order) from public.vv_incursion_steps),
  'notify,confirm_id,response_area,enhanced_trapping,control,communications,review,stand_down', 'the guided steps are created in order');
select is((select count(*) from public.vv_incursion_findings)::int, 1, 'the finding is linked');
select is((select count(*) from public.vv_incursion_sites)::int, 1, 'and its site');

-- ---------- Who sees it ----------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000026a5');
select is((select count(*) from public.vv_incursions)::int, 1, 'view-only in the team can see it');
select is((select count(*) from public.vv_incursion_steps)::int, 8, 'and its steps');
select throws_ok($$select public.vv_set_incursion_step('a8000000-0000-0000-0000-000000000001','notify','done',null)$$, '42501', null,
  'view-only cannot act on it');
select pg_temp.as_user('00000000-0000-0000-0000-0000000026a6');
select is((select count(*) from public.vv_incursions)::int, 0, 'a field officer outside the team cannot see it');
select is((select count(*) from public.vv_events where record_type = 'incursion')::int, 0, 'nor its history');

-- ---------- Lead officer: steps, tasks, notifications, area ------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000026a4');
select throws_ok($$select public.vv_set_incursion_step('a8000000-0000-0000-0000-000000000001','notify','done',null)$$, '42501', null,
  'a field officer who is not the lead cannot record steps');
select pg_temp.as_user('00000000-0000-0000-0000-0000000026a3');
select lives_ok($$select public.vv_set_incursion_step('a8000000-0000-0000-0000-000000000001','confirm_id','done','SYNTHETIC sent to lab')$$,
  'the lead officer marks a step done');
select throws_ok($$select public.vv_set_incursion_step('a8000000-0000-0000-0000-000000000001','control','skipped','')$$, '22023', null,
  'skipping needs a reason');
select throws_ok($$select public.vv_set_incursion_step('a8000000-0000-0000-0000-000000000001','stand_down','done','SYNTHETIC')$$, '22023', null,
  'the stand-down step is only completed by standing down');
select throws_ok($$select public.vv_set_incursion_step('a8000000-0000-0000-0000-000000000001','confirm_id','to_do','')$$, '22023', null,
  'reopening a step needs a reason');
select lives_ok($$select public.vv_save_incursion_task('a9000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',
  'enhanced_trapping','SYNTHETIC Deploy 6 ovitraps around Dock 4',null,'00000000-0000-0000-0000-0000000026a4',current_date + 3)$$,
  'the lead officer adds a task to a step');
select is((select step_key from public.vv_actions where id = 'a9000000-0000-0000-0000-000000000001'), 'enhanced_trapping', 'the task belongs to its step');
select throws_ok($$update public.vv_actions set incursion_id = null, step_key = null$$, '42501', null, 'a task cannot be moved off its incursion');
select throws_ok($$select public.vv_record_notification('aa000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',
  'ukhsa',null,'SYNTHETIC UKHSA duty desk','phone',now() + interval '1 day',null,null)$$, '22023', null, 'notification time cannot be in the future');
select lives_ok($$select public.vv_record_notification('aa000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',
  'ukhsa',null,'SYNTHETIC UKHSA duty desk','phone',now() - interval '1 hour','SYNTHETIC-REF-1',null)$$, 'a notification is recorded');
select lives_ok($$select public.vv_record_notification('aa000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',
  'ukhsa',null,'SYNTHETIC UKHSA duty desk','phone',now() - interval '1 hour','SYNTHETIC-REF-1',null)$$, 'recording it again is safe');
select is((select count(*) from public.vv_notifications)::int, 1, 'and it is not duplicated');
select is((select recorded_by from public.vv_notifications), '00000000-0000-0000-0000-0000000026a3'::uuid, 'who recorded it is kept');
select throws_ok($$update public.vv_notifications set recipient = 'SYNTHETIC someone else'$$, '42501', null, 'notifications cannot be rewritten');
select lives_ok($$select public.vv_set_response_area('a8000000-0000-0000-0000-000000000001',51.95,1.30,300,null)$$, 'the lead officer draws the response area');
select throws_ok($$select public.vv_set_response_area('a8000000-0000-0000-0000-000000000001',51.95,1.30,1000,null)$$, '22023', null,
  'changing it needs a reason');
select lives_ok($$select public.vv_set_response_area('a8000000-0000-0000-0000-000000000001',51.95,1.30,1000,'SYNTHETIC second find nearby')$$,
  'changed with a reason');
select is((select (response_area->>'radius_m')::int from public.vv_incursions), 1000, 'the new radius is stored');
select throws_ok($$select public.vv_set_response_area('a8000000-0000-0000-0000-000000000001',51.95,1.30,5,'SYNTHETIC tiny')$$, '23514', null,
  'a response area must be at least 10 m');
select lives_ok($$select public.vv_link_incursion('a8000000-0000-0000-0000-000000000001',null,array['a2000000-0000-0000-0000-000000000002'::uuid])$$,
  'another site is linked for enhanced trapping');
select throws_ok($$select public.vv_update_incursion('a8000000-0000-0000-0000-000000000001','SYNTHETIC x',null,null,null,'confirmed','SYNTHETIC lab')$$,
  '42501', null, 'only managers change the status');

-- ---------- Manager: status, stand-down, reopen ------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000026a2');
select throws_ok($$select public.vv_update_incursion('a8000000-0000-0000-0000-000000000001','SYNTHETIC Albopictus at Dock 4',
  pg_temp.taxon('aedes_albopictus'),null,'00000000-0000-0000-0000-0000000026a3','confirmed',null)$$, '22023', null, 'a status change needs a reason');
select lives_ok($$select public.vv_update_incursion('a8000000-0000-0000-0000-000000000001','SYNTHETIC Albopictus at Dock 4',
  pg_temp.taxon('aedes_albopictus'),null,'00000000-0000-0000-0000-0000000026a3','confirmed','SYNTHETIC lab confirmed')$$, 'confirmed with a reason');
select ok((select detail->'status' is not null and detail->>'reason' = 'SYNTHETIC lab confirmed' from public.vv_events
  where record_type = 'incursion' and kind = 'changed'), 'the change and its reason are in the history');
select throws_ok($$select public.vv_stand_down('ab000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',now(),
  'SYNTHETIC no further finds after 4 weeks')$$, '22023', null, 'cannot stand down with steps still to do');
select public.vv_set_incursion_step('a8000000-0000-0000-0000-000000000001', k, 'done', 'SYNTHETIC done')
  from unnest(array['notify','response_area','enhanced_trapping','communications','review']) k;
select public.vv_set_incursion_step('a8000000-0000-0000-0000-000000000001','control','skipped','SYNTHETIC not needed');
select throws_ok($$select public.vv_stand_down('ab000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',now(),'short')$$,
  '23514', null, 'a stand-down needs a rationale');
select pg_temp.as_user('00000000-0000-0000-0000-0000000026a3');
select throws_ok($$select public.vv_stand_down('ab000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',now(),
  'SYNTHETIC no further finds after 4 weeks')$$, '42501', null, 'the lead officer cannot stand down (managers only)');
select pg_temp.as_user('00000000-0000-0000-0000-0000000026a2');
select lives_ok($$select public.vv_stand_down('ab000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',now(),
  'SYNTHETIC no further finds after 4 weeks')$$, 'a manager stands down');
select is((select status from public.vv_incursions), 'stood_down', 'the incursion is stood down');
select is((select status from public.vv_incursion_steps where step_key = 'stand_down'), 'done', 'and the stand-down step is done');
select throws_ok($$select public.vv_set_response_area('a8000000-0000-0000-0000-000000000001',null,null,null,'SYNTHETIC clear')$$, '42501', null,
  'a stood-down incursion is closed to changes');
select throws_ok($$select public.vv_reopen_incursion('ac000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001','responding','')$$,
  '23514', null, 'reopening needs a reason');
select lives_ok($$select public.vv_reopen_incursion('ac000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001','responding',
  'SYNTHETIC new find in the response area')$$, 'reopened with a reason');
select is((select status from public.vv_incursions), 'responding', 'back to responding');
select is((select count(*) from public.vv_stand_downs)::int, 2, 'the stand-down and the reopening are both kept');
select throws_ok($$delete from public.vv_stand_downs$$, '42501', null, 'stand-down history cannot be deleted');
select throws_ok($$delete from public.vv_incursions$$, '42501', null, 'incursions are never deleted');

-- ---------- Council notification list -------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000026a3');
select throws_ok($$select public.vv_save_notify_contact('ad000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Comms team',null,
  'internal',null,true)$$, '42501', null, 'only managers keep the notification list');
select pg_temp.as_user('00000000-0000-0000-0000-0000000026a2');
select lives_ok($$select public.vv_save_notify_contact('ad000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Comms team',
  'SYNTHETIC Council','internal',null,true)$$, 'a manager adds a contact');
select lives_ok($$select public.vv_record_notification('aa000000-0000-0000-0000-000000000002','a8000000-0000-0000-0000-000000000001',
  null,'ad000000-0000-0000-0000-000000000001',null,'email',now(),null,null)$$, 'notify someone from the list');
select is((select recipient from public.vv_notifications where id = 'aa000000-0000-0000-0000-000000000002'),
  'SYNTHETIC Comms team (SYNTHETIC Council)', 'the recipient comes from the list');

-- ---------- Councils are separate -----------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000026b1');
select is((select count(*) from public.vv_incursions)::int + (select count(*) from public.vv_incursion_steps)::int
  + (select count(*) from public.vv_notifications)::int + (select count(*) from public.vv_stand_downs)::int
  + (select count(*) from public.vv_notify_contacts)::int + (select count(*) from public.vv_incursion_findings)::int, 0,
  'another council sees none of it');
select throws_ok($$select public.vv_set_incursion_step('a8000000-0000-0000-0000-000000000001','notify','to_do','SYNTHETIC x')$$, '42501', null,
  'and cannot act on it');
select throws_ok($$select public.vv_record_notification('aa000000-0000-0000-0000-000000000003','a8000000-0000-0000-0000-000000000001',
  'ukhsa',null,'SYNTHETIC','phone',now(),null,null)$$, '42501', null, 'or record notifications on it');
select throws_ok($$select public.vv_open_incursion('a8000000-0000-0000-0000-000000000009','a2000000-0000-0000-0000-000000000001',
  array['a7000000-0000-0000-0000-000000000001'::uuid],'SYNTHETIC',null,null,null,'suspected')$$, '42501', null, 'or open one on its site');
select throws_ok($$select public.vv_save_notify_contact('ad000000-0000-0000-0000-000000000001',pg_temp.ws('wsB'),'SYNTHETIC take over',null,
  'internal',null,true)$$, '42501', null, 'or take over its contacts');

-- ---------- Grants ---------------------------------------------------------------------------
reset role;
select ok(not has_table_privilege('authenticated', 'public.vv_incursions', 'insert'), 'browsers cannot write incursions directly');
select ok(not has_table_privilege('anon', 'public.vv_notifications', 'select'), 'signed-out visitors cannot read notifications');
select ok(not has_function_privilege('anon', 'public.vv_open_incursion(uuid, uuid, uuid[], text, uuid, uuid, uuid, text)', 'execute'),
  'signed-out visitors cannot open incursions');

select * from finish();
rollback;
