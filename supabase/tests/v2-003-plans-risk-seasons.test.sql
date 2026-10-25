-- pgTAP tests for docs/database/v2-003-plans-risk-seasons.sql. Synthetic people and data only; rolls back.
begin;
select no_plan();

-- Organisation A: A1 owner, A2 manager, A3 field officer, A4 viewer. Organisation B: B1 owner. Content team: R reviewer, P publisher.
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000203a1','v23a1@test.invalid',now()), ('00000000-0000-0000-0000-0000000203a2','v23a2@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000203a3','v23a3@test.invalid',now()), ('00000000-0000-0000-0000-0000000203a4','v23a4@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000203b1','v23b1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000203e1','v23r@test.invalid',now()),  ('00000000-0000-0000-0000-0000000203e2','v23p@test.invalid',now());
insert into public.content_roles (user_id, role) values
 ('00000000-0000-0000-0000-0000000203e1','reviewer'), ('00000000-0000-0000-0000-0000000203e2','content_admin');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values
 ('wsA', public.provision_organisation('SYNTHETIC V23 Port Health','00000000-0000-0000-0000-0000000203a1')),
 ('wsB', public.provision_organisation('SYNTHETIC V23 Council','00000000-0000-0000-0000-0000000203b1'));
insert into public.workspace_members (workspace_id, user_id, role)
 select (select v from ids where k='wsA'), u::uuid, 'member'::public.workspace_role
   from unnest(array['00000000-0000-0000-0000-0000000203a2','00000000-0000-0000-0000-0000000203a3','00000000-0000-0000-0000-0000000203a4']) u;

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.ws(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;
create function pg_temp.today() returns date language sql as $$ select (now() at time zone 'Europe/London')::date $$;
create function pg_temp.md(d date) returns text language sql as $$ select to_char(d, 'MM-DD') $$;
create function pg_temp.state() returns text language sql as $$
  select state from public.vv_visit_schedule(pg_temp.ws('wsA')) where deployment_id = 'c3600000-0000-0000-0000-000000000001' $$;
create function pg_temp.status(_req text) returns text language sql as $$
  select status from public.vv_site_compliance('c3000000-0000-0000-0000-000000000001') where requirement_key = _req $$;
create function pg_temp.detail(_req text) returns text language sql as $$
  select detail from public.vv_site_compliance('c3000000-0000-0000-0000-000000000001') where requirement_key = _req $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000203a1');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000203a2','vectovia','manage');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000203a3','vectovia','field');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000203a4','vectovia','view');
insert into ids values ('tPort', public.create_team(pg_temp.ws('wsA'),'SYNTHETIC Port team'));
select public.add_team_member(pg_temp.ws('tPort'), u) from unnest(array['00000000-0000-0000-0000-0000000203a3','00000000-0000-0000-0000-0000000203a4']::uuid[]) u;
select public.vv_save_programme('c3100000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Port surveillance',null,null,null,null,array[pg_temp.ws('tPort')]);
select public.vv_save_site('c3000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Quay',null,null,null,null,null,51.121,1.331,null,null,null,
  array['c3100000-0000-0000-0000-000000000001']::uuid[]);
select public.vv_save_trap('c3500000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYN-3-1',(select id from public.vv_trap_types where key = 'ovitrap'),null,null,null);
select public.vv_deploy_trap('c3600000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'c3500000-0000-0000-0000-000000000001',
  'c3000000-0000-0000-0000-000000000001',51.121,1.331,null,now() - interval '20 days',null,14);

-- ---------- Date helpers -----------------------------------------------------------------------
select ok(public.vv_valid_md('02-29') and public.vv_valid_md('12-31'), '29 February and 31 December are valid season dates');
select ok(not public.vv_valid_md('02-30') and not public.vv_valid_md('13-01') and not public.vv_valid_md('6-1'), 'impossible dates are refused');
select ok(public.vv_md_in('2026-12-15', '11-01', '03-31') and public.vv_md_in('2027-01-10', '11-01', '03-31'), 'a winter season runs over the new year');
select ok(not public.vv_md_in('2026-06-01', '11-01', '03-31'), 'and not through summer');
select is(public.vv_md_on_or_before('2026-03-10', '11-01'), '2025-11-01'::date, 'the season that began last November');
select is(public.vv_md_on_or_before('2027-03-01', '02-29'), '2027-03-01'::date, '29 February counts as 1 March in other years');

-- ---------- Seasons ----------------------------------------------------------------------------
select is(pg_temp.state(), 'overdue', 'without seasons the trap''s own 14-day interval applies (started 20 days ago)');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203a3');
select throws_ok($$select public.vv_save_season('c3200000-0000-0000-0000-000000000001','c3100000-0000-0000-0000-000000000001','SYNTHETIC Summer',
  pg_temp.md(pg_temp.today()), pg_temp.md(pg_temp.today() + 60), 7)$$, '42501', null, 'a field officer cannot set seasons');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203b1');
select throws_ok($$select public.vv_save_season('c3200000-0000-0000-0000-000000000001','c3100000-0000-0000-0000-000000000001','SYNTHETIC Summer',
  pg_temp.md(pg_temp.today()), pg_temp.md(pg_temp.today() + 60), 7)$$, '42501', null, 'nor can another organisation');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203a2');
select throws_ok($$select public.vv_save_season('c3200000-0000-0000-0000-000000000001','c3100000-0000-0000-0000-000000000001','SYNTHETIC Summer','06-31','10-31',7)$$,
  '22023', null, 'an impossible date is refused');
select lives_ok($$select public.vv_save_season('c3200000-0000-0000-0000-000000000001','c3100000-0000-0000-0000-000000000001','SYNTHETIC Summer',
  pg_temp.md(pg_temp.today()), pg_temp.md(pg_temp.today() + 60), 7)$$, 'a manager adds a season starting today, checks every 7 days');
select lives_ok($$select public.vv_save_season('c3200000-0000-0000-0000-000000000001','c3100000-0000-0000-0000-000000000001','SYNTHETIC Summer',
  pg_temp.md(pg_temp.today()), pg_temp.md(pg_temp.today() + 60), 7)$$, 'saving again is safe');
select is(pg_temp.state(), 'due', 'a new season starts the clock: the first check is due on its first day, not overdue from last year');
select is((select visit_interval_days from public.vv_visit_schedule(pg_temp.ws('wsA'))), 7, 'and the season''s interval is used');
select lives_ok($$select public.vv_save_season('c3200000-0000-0000-0000-000000000002','c3100000-0000-0000-0000-000000000001','SYNTHETIC Peak',
  pg_temp.md(pg_temp.today()), pg_temp.md(pg_temp.today() + 30), 3)$$, 'a second, overlapping season');
select is((select visit_interval_days from public.vv_visit_schedule(pg_temp.ws('wsA'))), 3, 'overlapping seasons use the shortest interval');
select throws_ok($$select public.vv_remove_season('c3200000-0000-0000-0000-000000000001','')$$, '22023', null, 'removing a season needs a reason');
select lives_ok($$select public.vv_remove_season('c3200000-0000-0000-0000-000000000001','SYNTHETIC replaced')$$, 'a season is removed with a reason');
select lives_ok($$select public.vv_remove_season('c3200000-0000-0000-0000-000000000002','SYNTHETIC replaced')$$, 'and the other');
select lives_ok($$select public.vv_save_season('c3200000-0000-0000-0000-000000000003','c3100000-0000-0000-0000-000000000001','SYNTHETIC Later',
  pg_temp.md(pg_temp.today() + 30), pg_temp.md(pg_temp.today() + 90), 14)$$, 'a season that has not started yet');
select is(pg_temp.state(), 'off_season', 'out of season no check is due');
select is((select next_due_on from public.vv_visit_schedule(pg_temp.ws('wsA'))), null, 'and there is no due date');
select is((select count(*) from public.vv_events where record_id = 'c3100000-0000-0000-0000-000000000001' and kind like 'season_%')::int, 6,
  'season changes are in the programme history');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203a3');
select is(pg_temp.state(), 'off_season', 'a field officer sees the same schedule');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203b1');
select is((select count(*) from public.vv_programme_seasons)::int, 0, 'another organisation sees no seasons');
select is((select interval_days from public.vv_site_season('c3000000-0000-0000-0000-000000000001', pg_temp.today())), null, 'nor can it ask about them');

-- ---------- Templates ----------------------------------------------------------------------------
reset role;
select throws_ok($$insert into public.vv_template_versions (template_id, version, summary, sections)
  select gen_random_uuid(), 1, 'SYNTHETIC bad', '[{"key":"a1","title":"One"},{"key":"a1","title":"Two"}]'$$, '23514', null, 'duplicate section keys are refused');
insert into public.vv_templates (id, key, kind, name) values ('c3300000-0000-0000-0000-000000000001', 'synthetic_plan', 'surveillance_plan', 'SYNTHETIC plan template');
insert into public.vv_template_versions (id, template_id, version, summary, sections, status) values
  ('c3310000-0000-0000-0000-000000000001', 'c3300000-0000-0000-0000-000000000001', 1, 'SYNTHETIC plan template version one.',
   '[{"key":"scope","title":"Scope and areas","guidance":"What the plan covers.","required":true},
     {"key":"response","title":"Incursion response","required":true},{"key":"notes","title":"Other notes","required":false}]', 'in_review');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203a2');
select is((select count(*) from public.vv_template_versions)::int, 0, 'unpublished templates are hidden from organisations');
select throws_ok($$select public.vv_save_plan('c3700000-0000-0000-0000-000000000001','c3710000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
  'c3310000-0000-0000-0000-000000000001','SYNTHETIC plan','[{"key":"scope","title":"Scope","text":"x"}]',null)$$, '22023', null,
  'a plan cannot use an unpublished template');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203e1');
select lives_ok($$select public.vv_tpl_review('c3310000-0000-0000-0000-000000000001', true, 'SYNTHETIC checked against guidance')$$, 'the reviewer approves the template');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203e2');
select lives_ok($$select public.vv_tpl_publish('c3310000-0000-0000-0000-000000000001')$$, 'a different content admin publishes it');
reset role;
select throws_ok($$update public.vv_template_versions set sections = '[{"key":"x","title":"Changed"}]' where id = 'c3310000-0000-0000-0000-000000000001'$$,
  '42501', null, 'a published template cannot be rewritten');

-- An obligation set that uses the new plan and risk checks.
insert into public.vv_obligation_sets (id, key, name, framework, jurisdiction) values ('c3400000-0000-0000-0000-000000000001', 'synthetic_plans', 'SYNTHETIC plans set', 'other', 'Test');
insert into public.vv_obligation_versions (id, set_id, version, summary, status) values
  ('c3410000-0000-0000-0000-000000000001', 'c3400000-0000-0000-0000-000000000001', 1, 'SYNTHETIC set using plan and risk checks.', 'draft');
insert into public.vv_obligation_requirements (version_id, key, sort_order, title, what, check_kind) values
  ('c3410000-0000-0000-0000-000000000001', 'plan', 1, 'SYNTHETIC plan', 'Keep an approved surveillance plan.', 'plan'),
  ('c3410000-0000-0000-0000-000000000001', 'risk', 2, 'SYNTHETIC risk', 'Assess site risk at least yearly.', 'risk'),
  ('c3410000-0000-0000-0000-000000000001', 'checks', 3, 'SYNTHETIC checks', 'Check traps on schedule.', 'checks');
update public.vv_obligation_versions set status = 'in_review' where id = 'c3410000-0000-0000-0000-000000000001';
select pg_temp.as_user('00000000-0000-0000-0000-0000000203e1');
select public.vv_obl_review('c3410000-0000-0000-0000-000000000001', true, 'SYNTHETIC checked set');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203e2');
select public.vv_obl_publish('c3410000-0000-0000-0000-000000000001');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203a2');
select public.vv_adopt_obligation_set('c3420000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001','synthetic_plans');
select is(pg_temp.status('checks'), 'green', 'out of season, checks are green');
select is(pg_temp.detail('checks'), 'Out of season: no checks are due now.', 'and say why');
select is(pg_temp.status('plan'), 'red', 'no plan: red');
select is(pg_temp.status('risk'), 'red', 'no risk assessment: red');

-- ---------- Surveillance plans --------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000203a3');
select throws_ok($$select public.vv_save_plan('c3700000-0000-0000-0000-000000000001','c3710000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
  'c3310000-0000-0000-0000-000000000001','SYNTHETIC plan','[{"key":"scope","title":"Scope","text":"x"}]',null)$$, '42501', null, 'a field officer cannot write the plan');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203a2');
select throws_ok($$select public.vv_save_plan('c3700000-0000-0000-0000-000000000001','c3710000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
  null,'SYNTHETIC plan','[{"key":"scope","title":"Scope"}]',null)$$, '22023', null, 'sections need text');
select is(public.vv_save_plan('c3700000-0000-0000-0000-000000000001','c3710000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
  'c3310000-0000-0000-0000-000000000001','SYNTHETIC Quay surveillance plan',
  '[{"key":"scope","title":"Scope and areas","text":"SYNTHETIC quay and freight yard."},{"key":"response","title":"Incursion response","text":""}]',null), 1,
  'a manager drafts the plan from the template');
select is(public.vv_save_plan('c3700000-0000-0000-0000-000000000001','c3710000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
  null,'ignored','[{"key":"scope","title":"Scope","text":"ignored"}]',null), 1, 'retrying the same save is safe');
select is(pg_temp.status('plan'), 'amber', 'a draft plan is amber');
select throws_ok($$select public.vv_approve_plan('c3710000-0000-0000-0000-000000000001', 1, pg_temp.today() + 365)$$, '22023',
  'complete the required sections first: Incursion response', 'required template sections must be filled before approval');
select throws_ok($$select public.vv_save_plan('c3700000-0000-0000-0000-000000000002','c3710000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
  null,'SYNTHETIC Quay surveillance plan','[{"key":"scope","title":"Scope and areas","text":"SYNTHETIC."}]','')$$, '23514', null, 'a new version needs a reason');
select is(public.vv_save_plan('c3700000-0000-0000-0000-000000000002','c3710000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
  null,'SYNTHETIC Quay surveillance plan',
  '[{"key":"scope","title":"Scope and areas","text":"SYNTHETIC quay and freight yard."},{"key":"response","title":"Incursion response","text":"SYNTHETIC call UKHSA; delimit 300 m."}]',
  'SYNTHETIC added the response section'), 2, 'version 2 completes it');
select throws_ok($$select public.vv_save_plan('c3700000-0000-0000-0000-000000000009','c3710000-0000-0000-0000-000000000009','c3000000-0000-0000-0000-000000000001',
  null,'SYNTHETIC second plan','[{"key":"scope","title":"Scope","text":"x"}]','SYNTHETIC second')$$, '22023', 'this site already has a plan', 'one plan per site');
select throws_ok($$select public.vv_approve_plan('c3710000-0000-0000-0000-000000000001', 1, pg_temp.today() + 365)$$, '22023', null, 'only the latest version can be approved');
select throws_ok($$select public.vv_approve_plan('c3710000-0000-0000-0000-000000000001', 2, pg_temp.today())$$, '22023', null, 'the review date must be in the future');
select throws_ok($$select public.vv_approve_plan('c3710000-0000-0000-0000-000000000001', 2, pg_temp.today() + 1200)$$, '22023', null, 'and within 3 years');
select lives_ok($$select public.vv_approve_plan('c3710000-0000-0000-0000-000000000001', 2, pg_temp.today() + 365)$$, 'a manager approves version 2');
select lives_ok($$select public.vv_approve_plan('c3710000-0000-0000-0000-000000000001', 2, pg_temp.today() + 100)$$, 'approving again changes nothing');
select is((select review_by from public.vv_site_plan_versions where version = 2), pg_temp.today() + 365, 'the first approval stands');
select is(pg_temp.status('plan'), 'green', 'an approved, current plan is green');
select is(public.vv_save_plan('c3700000-0000-0000-0000-000000000003','c3710000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
  null,'SYNTHETIC Quay surveillance plan','[{"key":"scope","title":"Scope and areas","text":"SYNTHETIC wider."},{"key":"response","title":"Incursion response","text":"SYNTHETIC."}]',
  'SYNTHETIC yearly update'), 3, 'a newer draft');
select is(pg_temp.status('plan'), 'green', 'the approved plan still counts while the new draft waits');
select ok(pg_temp.detail('plan') like '%newer draft is waiting for approval%', 'and compliance says a draft is waiting');
reset role;
select throws_ok($$update public.vv_site_plan_versions set sections = '[{"key":"scope","title":"Scope","text":"rewritten"}]' where version = 2$$, '42501', null,
  'an approved version cannot be rewritten');
select throws_ok($$update public.vv_site_plan_versions set review_by = review_by + 30 where version = 2$$, '42501', null, 'nor its approval changed');
select throws_ok($$delete from public.vv_site_plan_versions$$, '42501', null, 'versions are never deleted');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203a2');
select throws_ok($$select public.vv_record_plan_activity('c3720000-0000-0000-0000-000000000001','c3710000-0000-0000-0000-000000000001','exercise',pg_temp.today() + 1,'SYNTHETIC table-top')$$,
  '22023', null, 'an exercise cannot be dated in the future');
select lives_ok($$select public.vv_record_plan_activity('c3720000-0000-0000-0000-000000000001','c3710000-0000-0000-0000-000000000001','exercise',pg_temp.today(),'SYNTHETIC table-top with UKHSA')$$,
  'an exercise of the plan is recorded');
select lives_ok($$select public.vv_record_plan_activity('c3720000-0000-0000-0000-000000000001','c3710000-0000-0000-0000-000000000001','exercise',pg_temp.today(),'SYNTHETIC table-top with UKHSA')$$,
  'retrying is safe');
select is((select count(*) from public.vv_plan_activity)::int, 1, 'one exercise');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203a4');
select is((select count(*) from public.vv_site_plan_versions)::int, 3, 'a viewer can read every plan version');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203b1');
select is((select count(*) from public.vv_site_plans)::int + (select count(*) from public.vv_site_plan_versions)::int + (select count(*) from public.vv_plan_activity)::int, 0,
  'another organisation sees none of it');
select throws_ok($$select public.vv_approve_plan('c3710000-0000-0000-0000-000000000001', 3, pg_temp.today() + 365)$$, '42501', null, 'nor can approve it');

-- ---------- Site risk assessments -----------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000203a3');
select throws_ok($$select public.vv_save_site_risk('c3800000-0000-0000-0000-000000000001','c3810000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
  pg_temp.today(),null,3,4,null,null,null,null,null,null,'SYNTHETIC rationale text',null)$$, '42501', null, 'a field officer cannot assess site risk');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203a2');
select throws_ok($$select public.vv_save_site_risk('c3800000-0000-0000-0000-000000000001','c3810000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
  pg_temp.today() + 1,null,3,4,null,null,null,null,null,null,'SYNTHETIC rationale text',null)$$, '22023', null, 'the assessment date cannot be in the future');
select throws_ok($$select public.vv_save_site_risk('c3800000-0000-0000-0000-000000000001','c3810000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
  pg_temp.today(),pg_temp.today() + 400,3,4,null,null,null,null,null,null,'SYNTHETIC rationale text',null)$$, '22023', 'the next assessment must be due within a year',
  'assessments are at least yearly');
select throws_ok($$select public.vv_save_site_risk('c3800000-0000-0000-0000-000000000001','c3810000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
  pg_temp.today(),null,3,4,'low',null,null,null,null,null,'SYNTHETIC rationale text',null)$$, '23514', null, 'changing the matrix level needs a reason');
select is(public.vv_save_site_risk('c3800000-0000-0000-0000-000000000001','c3810000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
  pg_temp.today(),null,3,4,null,null,'SYNTHETIC Aedes albopictus','SYNTHETIC freight from southern Europe','SYNTHETIC tyres, standing water','SYNTHETIC ovitraps',
  'SYNTHETIC freight links and suitable habitat.',null), 1, 'a manager records the yearly site risk assessment');
select is(public.vv_save_site_risk('c3800000-0000-0000-0000-000000000001','c3810000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
  pg_temp.today(),null,1,1,null,null,null,null,null,null,'SYNTHETIC ignored',null), 1, 'retrying is safe');
select is((select next_due from public.vv_site_risk_versions), (pg_temp.today() + interval '1 year')::date, 'next due defaults to a year later');
select is((select matrix_level from public.vv_site_risk_versions), 'high', '3 x 4 on the matrix is high');
select is(pg_temp.status('risk'), 'green', 'a current risk assessment is green');
select is(public.vv_save_site_risk('c3800000-0000-0000-0000-000000000002','c3810000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
  pg_temp.today() - 350,pg_temp.today() + 15,3,4,null,null,null,null,null,null,'SYNTHETIC backdated record of an earlier assessment.','SYNTHETIC entering the paper record'),
  2, 'a later version');
select is(pg_temp.status('risk'), 'amber', 'due within 30 days: amber');
select is(public.vv_save_site_risk('c3800000-0000-0000-0000-000000000003','c3810000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001',
  pg_temp.today() - 400,pg_temp.today() - 40,3,4,null,null,null,null,null,null,'SYNTHETIC older paper record entered.','SYNTHETIC correcting the date'),
  3, 'another version');
select is(pg_temp.status('risk'), 'red', 'overdue: red');
reset role;
select throws_ok($$update public.vv_site_risk_versions set rationale = 'rewritten rationale'$$, '42501', null, 'risk versions cannot be rewritten');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203a4');
select is((select count(*) from public.vv_site_risk_versions)::int, 3, 'a viewer sees every version');
select pg_temp.as_user('00000000-0000-0000-0000-0000000203b1');
select is((select count(*) from public.vv_site_risk)::int + (select count(*) from public.vv_site_risk_versions)::int, 0, 'another organisation sees none');
select is((select count(*) from public.vv_site_compliance('c3000000-0000-0000-0000-000000000001'))::int, 0, 'nor the compliance');
reset role;
select is((select count(*) from public.vv_events where record_id = 'c3000000-0000-0000-0000-000000000001' and kind in ('plan_saved','plan_approved','plan_exercise','site_risk_assessed'))::int,
  8, 'plans, approvals, exercises and risk assessments are in the site history');

select * from finish();
rollback;
