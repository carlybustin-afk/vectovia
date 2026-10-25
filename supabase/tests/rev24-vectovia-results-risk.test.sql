-- pgTAP tests for docs/database/rev24-vectovia-results-risk.sql.
-- Requires revs 6–24. Synthetic people and data only; everything rolls back.
begin;
select no_plan();

-- Council A: A1 owner; A2 manager; A3 field officer (Port team); A5 view only (Port team). Council B: B1 owner.
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000025f1','r24p1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000025a1','r24a1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000025a2','r24a2@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000025a3','r24a3@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000025a5','r24a5@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000025b1','r24b1@test.invalid',now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000025f1');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values
 ('wsA', public.provision_organisation('SYNTHETIC R24 Council A','00000000-0000-0000-0000-0000000025a1')),
 ('wsB', public.provision_organisation('SYNTHETIC R24 Council B','00000000-0000-0000-0000-0000000025b1'));
insert into public.workspace_members (workspace_id, user_id, role)
 select (select v from ids where k='wsA'), u::uuid, 'member'::public.workspace_role
   from unnest(array['00000000-0000-0000-0000-0000000025a2','00000000-0000-0000-0000-0000000025a3','00000000-0000-0000-0000-0000000025a5']) u;

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.ws(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;
create function pg_temp.taxon(k text) returns uuid language sql as $$ select id from public.vv_taxa where key = $1 $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000025f1');
select public.set_workspace_product(pg_temp.ws('wsA'),'vectovia',true);
select public.set_workspace_product(pg_temp.ws('wsB'),'vectovia',true);
select pg_temp.as_user('00000000-0000-0000-0000-0000000025a1');
insert into ids values ('tPort', public.create_team(pg_temp.ws('wsA'),'SYNTHETIC Port'));
select public.add_team_member(pg_temp.ws('tPort'),'00000000-0000-0000-0000-0000000025a3');
select public.add_team_member(pg_temp.ws('tPort'),'00000000-0000-0000-0000-0000000025a5');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000025a2','vectovia','manage');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000025a3','vectovia','field');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000025a5','vectovia','view');
select public.vv_save_programme('91000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Port',null,'active',null,null,array[pg_temp.ws('tPort')]);
select public.vv_save_site('92000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Dock 4',null,null,null,null,null,51.95,1.30,null,null,null,
  array['91000000-0000-0000-0000-000000000001'::uuid]);
select public.vv_save_trap('93000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'BG-01',(select id from public.vv_trap_types where key='bg_sentinel'),null,null,null);
select public.vv_deploy_trap('94000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'93000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001',null,null,null,now() - interval '7 days',null,7);
select public.vv_record_visit('95000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000001',now() - interval '1 day',null,
  'collected',null,'working',null,now() - interval '7 days',now() - interval '1 day',
  '[{"id":"96000000-0000-0000-0000-000000000001","reference":"T-1","method":"adult_trap_catch"}]');

-- ---------- Results -------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000025a5');
select throws_ok($$select public.vv_save_result('97000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001','pending',
  null,null,null,null,null,null,'SYNTHETIC Lab',null,null,null,null)$$, '42501', null, 'view-only cannot record results');
select pg_temp.as_user('00000000-0000-0000-0000-0000000025a3');
select is(public.vv_save_result('97000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001','pending',
  null,null,null,null,null,null,'SYNTHETIC Lab','LAB-1',null,null,null), 1, 'sent to the lab: result pending');
select is((select status from public.vv_samples), 'awaiting_result', 'a pending result keeps the sample awaiting results');
select throws_ok($$select public.vv_save_result('97000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001','confirmed',
  null,null,3,'females','morphology',null,'SYNTHETIC Lab','LAB-1',current_date,null,'SYNTHETIC lab reported')$$, '23514', null,
  'a confirmed result must say what was found');
select throws_ok($$select public.vv_save_result('97000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001','provisional',
  pg_temp.taxon('aedes_albopictus'),null,3,'females','morphology','SYNTHETIC Officer',null,null,current_date,'SYNTHETIC worn specimens','')$$, '23514', null,
  'a change needs a reason');
select is(public.vv_save_result('97000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001','provisional',
  pg_temp.taxon('aedes_albopictus'),null,3,'females','morphology','SYNTHETIC Officer',null,null,current_date,'SYNTHETIC worn specimens','SYNTHETIC first look by officer'),
  2, 'provisional identification');
select is(public.vv_save_result('97000000-0000-0000-0000-000000000002','96000000-0000-0000-0000-000000000001','confirmed',
  pg_temp.taxon('culex_pipiens_sl'),null,12,'individuals','morphology','SYNTHETIC Officer',null,null,current_date,null,null), 1,
  'a second taxon in the same sample');
select is((select status from public.vv_samples), 'resulted', 'with no pending results the sample is resulted');
select is((select count(*) from public.vv_result_versions where result_id='97000000-0000-0000-0000-000000000001')::int, 2, 'earlier versions are kept');
select is((select count(*) from public.vv_findings_awaiting_review(pg_temp.ws('wsA')))::int, 2, 'both are findings awaiting review');
select throws_ok($$update public.vv_result_versions set status = 'confirmed'$$, '42501', null, 'result versions cannot be rewritten');
select throws_ok($$select public.vv_save_result('97000000-0000-0000-0000-000000000003','96000000-0000-0000-0000-000000000001','confirmed',
  pg_temp.taxon('aedes_aegypti'),null,1,'individuals','morphology',null,null,null,current_date + 5,null,null)$$, '22023', null,
  'a result date cannot be in the future');

-- ---------- Risk assessment (managers) ------------------------------------------------------
select is(public.vv_matrix_level(2,2), 'low', 'matrix: 2 x 2 is low');
select is(public.vv_matrix_level(3,3), 'medium', 'matrix: 3 x 3 is medium');
select is(public.vv_matrix_level(4,4), 'high', 'matrix: 4 x 4 is high');
select is(public.vv_matrix_level(5,4), 'very_high', 'matrix: 5 x 4 is very high');
select throws_ok($$select public.vv_save_assessment('98000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001',
  array['97000000-0000-0000-0000-000000000001'::uuid],4,4,null,null,'[]','SYNTHETIC rationale text',null)$$, '42501', null,
  'field officers cannot record assessments');
select pg_temp.as_user('00000000-0000-0000-0000-0000000025a2');
select throws_ok($$select public.vv_save_assessment('98000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001',
  array['97000000-0000-0000-0000-000000000001'::uuid],4,4,null,null,'[]','short',null)$$, '23514', null, 'a rationale is required');
select throws_ok($$select public.vv_save_assessment('98000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001',
  array['97000000-0000-0000-0000-000000000001'::uuid],4,4,'very_high',null,'[]','SYNTHETIC rationale text',null)$$, '23514', null,
  'changing the matrix level needs a reason');
select is(public.vv_save_assessment('98000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001',
  array['97000000-0000-0000-0000-000000000001'::uuid],4,4,'very_high','SYNTHETIC first detection at a port of entry',
  '["invasive_species","port_of_entry","season"]','SYNTHETIC provisional Aedes albopictus at the port; females found',null), 1, 'manager records the assessment');
select is((select matrix_level || '/' || final_level from public.vv_assessment_versions), 'high/very_high',
  'the matrix level and the officer''s final level are both kept');
select is((select count(*) from public.vv_findings_awaiting_review(pg_temp.ws('wsA')))::int, 1, 'the assessed finding leaves the review list');
select is(public.vv_save_assessment('98000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001',
  null,4,5,null,null,'["invasive_species","port_of_entry"]','SYNTHETIC confirmed by the lab; very high',
  'SYNTHETIC lab confirmed'), 2, 'the assessment is revised as a new version');
select is((select count(*) from public.vv_assessment_versions)::int, 2, 'both versions are kept');

-- ---------- Actions ----------------------------------------------------------------------------
select lives_ok($$select public.vv_save_action('99000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001',
  '98000000-0000-0000-0000-000000000001','SYNTHETIC enhanced trapping within 200 m',null,'00000000-0000-0000-0000-0000000025a3',current_date + 3)$$,
  'manager assigns an action to the field officer');
select pg_temp.as_user('00000000-0000-0000-0000-0000000025a3');
select throws_ok($$select public.vv_save_action('99000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000001',
  null,'SYNTHETIC self-assigned',null,null,null)$$, '42501', null, 'field officers cannot create actions');
select lives_ok($$select public.vv_set_action_status('99000000-0000-0000-0000-000000000001','done','SYNTHETIC 6 extra traps set')$$,
  'the owner completes their action');
select is((select completed_by from public.vv_actions), '00000000-0000-0000-0000-0000000025a3'::uuid, 'who completed it is recorded');
select ok((select completed_at is not null from public.vv_actions), 'and when');
select pg_temp.as_user('00000000-0000-0000-0000-0000000025a5');
select throws_ok($$select public.vv_set_action_status('99000000-0000-0000-0000-000000000001','open',null)$$, '42501', null,
  'view-only cannot change actions');
select is((select count(*) from public.vv_results)::int + (select count(*) from public.vv_assessments)::int + (select count(*) from public.vv_actions)::int, 4,
  'view-only Port member sees results, assessments and actions');
select pg_temp.as_user('00000000-0000-0000-0000-0000000025a2');
select throws_ok($$select public.vv_set_action_status('99000000-0000-0000-0000-000000000001','cancelled','')$$, '23514', null,
  'cancelling needs a note');

-- ---------- Councils are separate --------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000025b1');
select is((select count(*) from public.vv_results)::int + (select count(*) from public.vv_result_versions)::int + (select count(*) from public.vv_assessments)::int
  + (select count(*) from public.vv_assessment_versions)::int + (select count(*) from public.vv_actions)::int, 0, 'another council sees nothing');
select is((select count(*) from public.vv_findings_awaiting_review(pg_temp.ws('wsA')))::int, 0, 'not even through the review list');
select throws_ok($$select public.vv_save_result('97000000-0000-0000-0000-000000000009','96000000-0000-0000-0000-000000000001','pending',
  null,null,null,null,null,null,null,null,null,null,null)$$, '42501', null, 'nor adds results to our samples');
reset role;
select throws_ok($$delete from public.vv_results$$, '42501', null, 'results are never deleted');
select throws_ok($$delete from public.vv_assessment_versions$$, '42501', null, 'assessment history is never deleted');

select * from finish();
rollback;
