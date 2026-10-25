-- pgTAP tests for docs/database/v2-004-field-records.sql. Synthetic people and data only; rolls back.
begin;
select no_plan();

-- Organisation A: A1 owner, A2 manager, A3 field officer, A4 viewer (A3 and A4 in the programme's team). Organisation B: B1 owner.
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000204a1','v24a1@test.invalid',now()), ('00000000-0000-0000-0000-0000000204a2','v24a2@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000204a3','v24a3@test.invalid',now()), ('00000000-0000-0000-0000-0000000204a4','v24a4@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000204b1','v24b1@test.invalid',now());
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values
 ('wsA', public.provision_organisation('SYNTHETIC V24 Port Health','00000000-0000-0000-0000-0000000204a1')),
 ('wsB', public.provision_organisation('SYNTHETIC V24 Council','00000000-0000-0000-0000-0000000204b1'));
insert into public.workspace_members (workspace_id, user_id, role)
 select (select v from ids where k='wsA'), u::uuid, 'member'::public.workspace_role
   from unnest(array['00000000-0000-0000-0000-0000000204a2','00000000-0000-0000-0000-0000000204a3','00000000-0000-0000-0000-0000000204a4']) u;

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.ws(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;
create function pg_temp.today() returns date language sql as $$ select (now() at time zone 'Europe/London')::date $$;
create function pg_temp.taxon(k text) returns uuid language sql as $$ select id from public.vv_taxa where key = $1 $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000204a1');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000204a2','vectovia','manage');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000204a3','vectovia','field');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000204a4','vectovia','view');
insert into ids values ('tPort', public.create_team(pg_temp.ws('wsA'),'SYNTHETIC Port team'));
select public.add_team_member(pg_temp.ws('tPort'), u) from unnest(array['00000000-0000-0000-0000-0000000204a3','00000000-0000-0000-0000-0000000204a4']::uuid[]) u;
select public.vv_save_programme('c4100000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Port surveillance',null,null,null,null,array[pg_temp.ws('tPort')]);
select public.vv_save_site('c4000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Quay',null,null,null,null,null,51.121,1.331,null,null,null,
  array['c4100000-0000-0000-0000-000000000001']::uuid[]);
select public.vv_save_trap('c4500000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYN-4-1',(select id from public.vv_trap_types where key = 'ovitrap'),null,null,null);
select public.vv_deploy_trap('c4600000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'c4500000-0000-0000-0000-000000000001',
  'c4000000-0000-0000-0000-000000000001',51.121,1.331,null,now() - interval '10 days',null,14);
select public.vv_record_visit('c4700000-0000-0000-0000-000000000001','c4600000-0000-0000-0000-000000000001',now() - interval '3 days',null,'collected',null,'working',null,null,null,
  '[{"id":"c4800000-0000-0000-0000-000000000001"},{"id":"c4800000-0000-0000-0000-000000000002"}]');

-- ---------- Negative finds -------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000204a3');
select throws_ok($$select public.vv_save_result('c4900000-0000-0000-0000-000000000001','c4800000-0000-0000-0000-000000000001','negative',
  pg_temp.taxon('aedes_albopictus'),null,null,null,'morphology','SYNTHETIC officer',null,null,pg_temp.today(),null,null)$$, '23514', null, 'a negative find names no species');
select lives_ok($$select public.vv_save_result('c4900000-0000-0000-0000-000000000001','c4800000-0000-0000-0000-000000000001','negative',
  null,null,null,null,'morphology','SYNTHETIC officer',null,null,pg_temp.today(),null,null)$$, 'a field officer records a negative find');
select is((select status from public.vv_samples where id = 'c4800000-0000-0000-0000-000000000001'), 'resulted', 'the sample counts as resulted');
select lives_ok($$select public.vv_save_result('c4900000-0000-0000-0000-000000000002','c4800000-0000-0000-0000-000000000002','provisional',
  pg_temp.taxon('aedes_albopictus'),null,4,'eggs','morphology','SYNTHETIC officer',null,null,pg_temp.today(),null,null)$$, 'and a provisional invasive find');
select is((select count(*) from public.vv_awaiting_official_id(pg_temp.ws('wsA')))::int, 1, 'the invasive find is flagged for official identification');
select is((select days_waiting from public.vv_awaiting_official_id(pg_temp.ws('wsA'))), 0, 'with how long it has waited');

-- ---------- Inspections --------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000204a4');
select throws_ok($$select public.vv_record_inspection('c4a00000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',now(),null,'larval_dip',
  51.1212,1.3315,'SYNTHETIC tyre stack','nothing_found',null,null,null,'[]')$$, '42501', null, 'a viewer cannot record an inspection');
select pg_temp.as_user('00000000-0000-0000-0000-0000000204b1');
select throws_ok($$select public.vv_record_inspection('c4a00000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',now(),null,'larval_dip',
  51.1212,1.3315,'SYNTHETIC tyre stack','nothing_found',null,null,null,'[]')$$, '42501', null, 'nor can another organisation');
select pg_temp.as_user('00000000-0000-0000-0000-0000000204a3');
select throws_ok($$select public.vv_record_inspection('c4a00000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',now() + interval '1 hour',null,'larval_dip',
  null,null,null,'nothing_found',null,null,null,'[]')$$, '22023', null, 'an inspection cannot be in the future');
select throws_ok($$select public.vv_record_inspection('c4a00000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',now(),null,'larval_dip',
  null,null,null,'collected',null,null,null,'[]')$$, '22023', null, 'collected needs a sample');
select throws_ok($$select public.vv_record_inspection('c4a00000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',now(),null,'larval_dip',
  null,null,null,'not_completed','',null,null,'[]')$$, '23514', null, 'not completed needs a reason');
select lives_ok($$select public.vv_record_inspection('c4a00000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',now() - interval '1 hour',null,'larval_dip',
  51.1212,1.3315,'SYNTHETIC tyre stack with standing water','collected',null,'SYNTHETIC larvae seen',null,'[{"id":"c4800000-0000-0000-0000-000000000011"}]')$$,
  'a field officer records a larval dip with a sample, no trap needed');
select lives_ok($$select public.vv_record_inspection('c4a00000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',now() - interval '1 hour',null,'larval_dip',
  51.1212,1.3315,'SYNTHETIC','collected',null,null,null,'[{"id":"c4800000-0000-0000-0000-000000000011"}]')$$, 'retrying is safe');
select is((select method || ':' || coalesce(visit_id::text, 'no visit') from public.vv_samples where id = 'c4800000-0000-0000-0000-000000000011'), 'larvae:no visit',
  'the sample belongs to the inspection, as larvae');
select ok((select reference ~ '^VS-S[0-9]{5}$' from public.vv_samples where id = 'c4800000-0000-0000-0000-000000000011'), 'and gets a sample reference');
select lives_ok($$select public.vv_save_result('c4900000-0000-0000-0000-000000000011','c4800000-0000-0000-0000-000000000011','provisional',
  pg_temp.taxon('aedes_albopictus'),null,12,'larvae','morphology','SYNTHETIC officer',null,null,pg_temp.today(),null,null)$$, 'its sample gets a result like any other');
reset role;
select throws_ok($$update public.vv_inspections set habitat = 'changed'$$, '42501', null, 'inspections cannot be rewritten');
select throws_ok($$insert into public.vv_samples (id, workspace_id, site_id, reference, method, created_by)
  values (gen_random_uuid(), (select workspace_id from public.vv_sites where id = 'c4000000-0000-0000-0000-000000000001'), 'c4000000-0000-0000-0000-000000000001', 'SYN-X', 'larvae', gen_random_uuid())$$,
  '23514', null, 'a sample must come from a visit or an inspection');

-- ---------- Delimiting surveys ----------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000204a3');
select throws_ok($$select public.vv_save_survey('c4b00000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',null,'c4900000-0000-0000-0000-000000000002',
  51.121,1.331,null,pg_temp.today(),null)$$, '42501', null, 'a field officer cannot start a delimiting survey');
select pg_temp.as_user('00000000-0000-0000-0000-0000000204a2');
select is(public.vv_save_survey('c4b00000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',null,'c4900000-0000-0000-0000-000000000002',
  51.121,1.331,null,pg_temp.today(),null), 'VS-D0001', 'a manager starts one from the positive find');
select is((select radius_m from public.vv_surveys), 300, 'with a 300 m radius by default');
select is(public.vv_save_survey('c4b00000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',null,'c4900000-0000-0000-0000-000000000002',
  51.121,1.331,null,pg_temp.today(),null), 'VS-D0001', 'saving the same again is harmless');
select throws_ok($$select public.vv_save_survey('c4b00000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',null,'c4900000-0000-0000-0000-000000000002',
  51.121,1.331,500,pg_temp.today(),'')$$, '22023', null, 'changing the radius needs a reason');
select lives_ok($$select public.vv_save_survey('c4b00000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',null,'c4900000-0000-0000-0000-000000000002',
  51.121,1.331,500,pg_temp.today(),'SYNTHETIC second positive nearby')$$, 'it is widened with a reason');
select pg_temp.as_user('00000000-0000-0000-0000-0000000204a3');
select lives_ok($$select public.vv_record_inspection('c4a00000-0000-0000-0000-000000000002','c4000000-0000-0000-0000-000000000001',now(),null,'container_search',
  51.122,1.333,'SYNTHETIC plant pots','collected',null,null,'c4b00000-0000-0000-0000-000000000001','[{"id":"c4800000-0000-0000-0000-000000000021"}]')$$,
  'a field officer records an inspection as part of the survey');
select lives_ok($$select public.vv_record_inspection('c4a00000-0000-0000-0000-000000000003','c4000000-0000-0000-0000-000000000001',now(),null,'visual',
  51.123,1.334,null,'nothing_found',null,null,'c4b00000-0000-0000-0000-000000000001','[]')$$, 'and another that found nothing');
select lives_ok($$select public.vv_link_survey_trap('c4b00000-0000-0000-0000-000000000001','c4600000-0000-0000-0000-000000000001')$$, 'a trap is added to the survey');
select lives_ok($$select public.vv_link_survey_trap('c4b00000-0000-0000-0000-000000000001','c4600000-0000-0000-0000-000000000001')$$, 'adding again is safe');
select public.vv_save_result('c4900000-0000-0000-0000-000000000021','c4800000-0000-0000-0000-000000000021','negative',null,null,null,null,'morphology','SYNTHETIC',null,null,pg_temp.today(),null,null);
select is((select inspections || '/' || traps || '/' || samples || '/' || positive_finds || '/' || negative_finds || '/' || awaiting_results
  from public.vv_survey_summary('c4b00000-0000-0000-0000-000000000001')), '2/1/1/0/1/0',
  'the summary counts 2 inspections, 1 trap, 1 sample and its negative result (trap samples from before the survey are not counted)');
select pg_temp.as_user('00000000-0000-0000-0000-0000000204a2');
select throws_ok($$select public.vv_end_survey('c4b00000-0000-0000-0000-000000000001',pg_temp.today(),'short')$$, '22023', null, 'ending needs an outcome');
select lives_ok($$select public.vv_end_survey('c4b00000-0000-0000-0000-000000000001',pg_temp.today(),'SYNTHETIC no further positives within 500 m.')$$, 'the manager ends the survey');
select pg_temp.as_user('00000000-0000-0000-0000-0000000204a3');
select throws_ok($$select public.vv_record_inspection('c4a00000-0000-0000-0000-000000000004','c4000000-0000-0000-0000-000000000001',now(),null,'visual',
  null,null,null,'nothing_found',null,null,'c4b00000-0000-0000-0000-000000000001','[]')$$, '22023', 'that survey has ended', 'no more inspections once it has ended');
select pg_temp.as_user('00000000-0000-0000-0000-0000000204a4');
select is((select count(*) from public.vv_surveys)::int + (select count(*) from public.vv_inspections)::int, 4, 'a viewer sees the survey and inspections');
select pg_temp.as_user('00000000-0000-0000-0000-0000000204b1');
select is((select count(*) from public.vv_surveys)::int + (select count(*) from public.vv_inspections)::int + (select count(*) from public.vv_survey_deployments)::int, 0,
  'another organisation sees none of it');
select is((select count(*) from public.vv_awaiting_official_id(pg_temp.ws('wsA')))::int, 0, 'nor organisation A''s flagged finds');

-- ---------- Pathogen tests ---------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000204a3');
select throws_ok($$select public.vv_save_pathogen_test('c4c00000-0000-0000-0000-000000000001','c4800000-0000-0000-0000-000000000002','other',null,null,null,null,null,null,null,null)$$,
  '23514', null, '"other" needs the pathogen named');
select lives_ok($$select public.vv_save_pathogen_test('c4c00000-0000-0000-0000-000000000001','c4800000-0000-0000-0000-000000000002','dengue',null,'RT-PCR','SYNTHETIC lab',null,null,null,null,null)$$,
  'a field officer records a pending dengue test');
select throws_ok($$select public.vv_save_pathogen_test('c4c00000-0000-0000-0000-000000000001','c4800000-0000-0000-0000-000000000002','dengue',null,'RT-PCR','SYNTHETIC lab','SYN-1','not_detected',null,null,null)$$,
  '23514', null, 'a result needs a result date');
select lives_ok($$select public.vv_save_pathogen_test('c4c00000-0000-0000-0000-000000000001','c4800000-0000-0000-0000-000000000002','dengue',null,'RT-PCR','SYNTHETIC lab','SYN-1','not_detected',pg_temp.today(),null,null)$$,
  'the result comes back: not detected');
select lives_ok($$select public.vv_save_pathogen_test('c4c00000-0000-0000-0000-000000000001','c4800000-0000-0000-0000-000000000002','dengue',null,'RT-PCR','SYNTHETIC lab','SYN-1','not_detected',pg_temp.today(),null,null)$$,
  'retrying is safe');
select throws_ok($$select public.vv_save_pathogen_test('c4c00000-0000-0000-0000-000000000001','c4800000-0000-0000-0000-000000000002','dengue',null,'RT-PCR','SYNTHETIC lab','SYN-1','detected',pg_temp.today(),null,'')$$,
  '22023', null, 'changing a result needs a reason');
select lives_ok($$select public.vv_save_pathogen_test('c4c00000-0000-0000-0000-000000000001','c4800000-0000-0000-0000-000000000002','dengue',null,'RT-PCR','SYNTHETIC lab','SYN-1','inconclusive',pg_temp.today(),null,'SYNTHETIC lab reissued the report')$$,
  'and is corrected with a reason');
reset role;
select is((select detail -> 'status' ->> 'from' from public.vv_events where record_type = 'pathogen_test' and detail ? 'reason'), 'not_detected', 'the earlier result stays in the history');
select throws_ok($$update public.vv_pathogen_tests set pathogen = 'zika'$$, '42501', null, 'the pathogen tested cannot be changed');
select throws_ok($$delete from public.vv_pathogen_tests$$, '42501', null, 'tests are never deleted');

-- ---------- Control actions ---------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000204a3');
select throws_ok($$select public.vv_record_control('c4d00000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',null,'c4b00000-0000-0000-0000-000000000001',
  'larviciding',pg_temp.today(),null,null,null,'SYNTHETIC drains',null,null,null,null,null,null)$$, '23514', null, 'a treatment needs the product');
select throws_ok($$select public.vv_record_control('c4d00000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',null,null,
  'source_reduction',pg_temp.today() + 1,null,null,null,null,null,null,null,null,null,null)$$, '22023', null, 'the date cannot be in the future');
select lives_ok($$select public.vv_record_control('c4d00000-0000-0000-0000-000000000001','c4000000-0000-0000-0000-000000000001',null,'c4b00000-0000-0000-0000-000000000001',
  'larviciding',pg_temp.today(),'SYNTHETIC Bti granules','Bacillus thuringiensis israelensis','2 kg','SYNTHETIC drains and tyre stack',51.121,1.331,300,'SYNTHETIC Pest Co',
  '00000000-0000-0000-0000-0000000204a2',null)$$, 'a field officer records larviciding, supervised by the manager');
select lives_ok($$select public.vv_record_control('c4d00000-0000-0000-0000-000000000002','c4000000-0000-0000-0000-000000000001',null,null,
  'source_reduction',pg_temp.today(),null,null,null,'SYNTHETIC removed 40 tyres',null,null,null,null,null,null)$$, 'and source reduction');
select throws_ok($$select public.vv_withdraw_control('c4d00000-0000-0000-0000-000000000002','SYNTHETIC wrong site')$$, '42501', null, 'a field officer cannot withdraw a record');
select pg_temp.as_user('00000000-0000-0000-0000-0000000204a2');
select throws_ok($$select public.vv_withdraw_control('c4d00000-0000-0000-0000-000000000002','')$$, '22023', null, 'withdrawing needs a reason');
select lives_ok($$select public.vv_withdraw_control('c4d00000-0000-0000-0000-000000000002','SYNTHETIC recorded on the wrong site')$$, 'a manager withdraws it with a reason');
reset role;
select is((select count(*) from public.vv_control_actions)::int, 2, 'the withdrawn record is kept');
select throws_ok($$update public.vv_control_actions set product = 'changed'$$, '42501', null, 'control records cannot be rewritten');
select pg_temp.as_user('00000000-0000-0000-0000-0000000204b1');
select is((select count(*) from public.vv_control_actions)::int + (select count(*) from public.vv_pathogen_tests)::int, 0, 'another organisation sees neither');
reset role;
select is((select count(*) from public.vv_events where record_type in ('inspection','survey','pathogen_test','control_action'))::int, 13,
  'inspections, surveys, tests and control actions are all in the history');

select * from finish();
rollback;
