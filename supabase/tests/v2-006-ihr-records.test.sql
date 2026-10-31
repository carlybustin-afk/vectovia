-- pgTAP tests for docs/database/v2-006-ihr-records.sql. Synthetic people and data only; rolls back.
begin;
select no_plan();

-- Organisation A: A1 owner, A2 manager, A3 field officer, A4 viewer (A3, A4 in the programme's team). Organisation B: B1 owner.
-- R1 reviewer and P1 content admin publish a synthetic obligation set using the new checks.
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000206a1','v26a1@test.invalid',now()), ('00000000-0000-0000-0000-0000000206a2','v26a2@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000206a3','v26a3@test.invalid',now()), ('00000000-0000-0000-0000-0000000206a4','v26a4@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000206b1','v26b1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000206e1','v26r@test.invalid',now()),  ('00000000-0000-0000-0000-0000000206e2','v26p@test.invalid',now());
insert into public.content_roles (user_id, role) values
 ('00000000-0000-0000-0000-0000000206e1','reviewer'), ('00000000-0000-0000-0000-0000000206e2','content_admin');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values
 ('wsA', public.provision_organisation('SYNTHETIC V26 Port Health','00000000-0000-0000-0000-0000000206a1')),
 ('wsB', public.provision_organisation('SYNTHETIC V26 Council','00000000-0000-0000-0000-0000000206b1'));
insert into public.workspace_members (workspace_id, user_id, role)
 select (select v from ids where k='wsA'), u::uuid, 'member'::public.workspace_role
   from unnest(array['00000000-0000-0000-0000-0000000206a2','00000000-0000-0000-0000-0000000206a3','00000000-0000-0000-0000-0000000206a4']) u;

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.ws(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;
create function pg_temp.today() returns date language sql as $$ select (now() at time zone 'Europe/London')::date $$;
create function pg_temp.square() returns jsonb language sql as $$
  select '{"type":"Polygon","coordinates":[[[1.330,51.120],[1.332,51.120],[1.332,51.122],[1.330,51.122],[1.330,51.120]]]}'::jsonb $$;
create function pg_temp.status(k text) returns text language sql as $$
  select status || ': ' || detail from public.vv_site_compliance('c6000000-0000-0000-0000-000000000001') where requirement_key = $1 $$;

-- A synthetic set with one requirement per new check, published through review.
insert into public.vv_obligation_sets (id, key, name, framework, jurisdiction, applies_to) values
  ('c6300000-0000-0000-0000-000000000001', 'synthetic_v26', 'SYNTHETIC IHR records set', 'ihr', 'International', '{port}');
insert into public.vv_obligation_versions (id, set_id, version, summary, status) values
  ('c6310000-0000-0000-0000-000000000001', 'c6300000-0000-0000-0000-000000000001', 1, 'SYNTHETIC version one of the records set.', 'draft');
insert into public.vv_obligation_requirements (version_id, key, sort_order, title, what, check_kind)
  select 'c6310000-0000-0000-0000-000000000001', k, n, 'SYNTHETIC ' || k, 'SYNTHETIC requirement ' || k || '.', k
    from unnest(array['zone', 'training', 'contractors', 'equipment', 'sanitary_survey', 'wider_survey', 'incoming_risks', 'conveyances',
                      'follow_up', 'treatment_supervision']) with ordinality as t(k, n);
update public.vv_obligation_versions set status = 'in_review' where id = 'c6310000-0000-0000-0000-000000000001';
select pg_temp.as_user('00000000-0000-0000-0000-0000000206e1');
select public.vv_obl_review('c6310000-0000-0000-0000-000000000001', true, 'SYNTHETIC checked against the source');
select pg_temp.as_user('00000000-0000-0000-0000-0000000206e2');
select public.vv_obl_publish('c6310000-0000-0000-0000-000000000001');

-- Organisation A: a port with a boundary, a programme with a team, one trap inside the zone; the set adopted.
select pg_temp.as_user('00000000-0000-0000-0000-0000000206a1');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000206a2','vectovia','manage');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000206a3','vectovia','field');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000206a4','vectovia','view');
insert into ids values ('tPort', public.create_team(pg_temp.ws('wsA'),'SYNTHETIC Port team'));
select public.add_team_member(pg_temp.ws('tPort'), u) from unnest(array['00000000-0000-0000-0000-0000000206a3','00000000-0000-0000-0000-0000000206a4']::uuid[]) u;
select public.vv_save_programme('c6100000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Port surveillance',null,null,null,null,array[pg_temp.ws('tPort')]);
select public.vv_save_site('c6000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Quay',null,null,null,null,null,51.121,1.331,null,null,null,
  array['c6100000-0000-0000-0000-000000000001']::uuid[]);
select public.vv_save_site_geometry('c6000000-0000-0000-0000-000000000001','port',pg_temp.square(),400,'SYNTHETIC international freight');
select public.vv_save_trap('c6500000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYN-6-1',(select id from public.vv_trap_types where key = 'ovitrap'),null,null,null);
select public.vv_deploy_trap('c6600000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'c6500000-0000-0000-0000-000000000001',
  'c6000000-0000-0000-0000-000000000001',51.121,1.331,null,now() - interval '2 days',null,14);
select public.vv_adopt_obligation_set('c6400000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001','synthetic_v26');

-- ---------- Zones under 400 m --------------------------------------------------------------------------
select is(pg_temp.status('zone'), 'green: 1 active trap inside the 400 m zone.', 'a 400 m zone at a port is met');
select lives_ok($$select public.vv_save_site_geometry('c6000000-0000-0000-0000-000000000001','port',pg_temp.square(),250,'SYNTHETIC international freight')$$,
  'a point of entry may now have a zone under 400 m');
select is(pg_temp.status('zone'), 'amber: The zone is 250 m, under the 400 m IHR recommendation; 1 active trap inside it.', 'and the shortfall shows as partly met');
select public.vv_save_site_geometry('c6000000-0000-0000-0000-000000000001','port',pg_temp.square(),400,'SYNTHETIC international freight');

-- ---------- Starting position: nothing recorded ------------------------------------------------------
select is((select string_agg(requirement_key || '=' || status, ',' order by sort_order) from public.vv_site_compliance('c6000000-0000-0000-0000-000000000001')),
  'zone=green,training=red,contractors=not_applicable,equipment=red,sanitary_survey=red,wider_survey=red,incoming_risks=green,conveyances=green,follow_up=green,treatment_supervision=not_applicable',
  'with no records: training, equipment and surveys are not met; contractors and treatments do not apply');

-- ---------- Competence ------------------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000206a3');
select throws_ok($$select public.vv_save_competence('c6700000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Officer',null,'Mosquito identification',
  null,pg_temp.today() - 30,null,null,null)$$, '42501', null, 'a field officer cannot keep the competence register');
select pg_temp.as_user('00000000-0000-0000-0000-0000000206a2');
select throws_ok($$select public.vv_save_competence('c6700000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Officer','00000000-0000-0000-0000-0000000206b1',
  'Mosquito identification',null,pg_temp.today() - 30,null,null,null)$$, '22023', null, 'a linked person must be in the organisation');
select throws_ok($$select public.vv_save_competence('c6700000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Officer',null,'Mosquito identification',
  null,pg_temp.today() + 1,null,null,null)$$, '22023', null, 'the date achieved cannot be in the future');
select lives_ok($$select public.vv_save_competence('c6700000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Officer','00000000-0000-0000-0000-0000000206a3',
  'Mosquito identification','SYNTHETIC UKHSA course',pg_temp.today() - 400,pg_temp.today() - 35,'SYN-CERT-1',null)$$, 'a manager records training that has since expired');
select lives_ok($$select public.vv_save_competence('c6700000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Officer','00000000-0000-0000-0000-0000000206a3',
  'Mosquito identification','SYNTHETIC UKHSA course',pg_temp.today() - 400,pg_temp.today() - 35,'SYN-CERT-1',null)$$, 'saving the same again is harmless');
select is(pg_temp.status('training'), 'red: No current training or competence records.', 'lapsed training alone is not met');
select lives_ok($$select public.vv_save_competence('c6700000-0000-0000-0000-000000000002',pg_temp.ws('wsA'),'SYNTHETIC Officer','00000000-0000-0000-0000-0000000206a3',
  'Mosquito identification','SYNTHETIC UKHSA course',pg_temp.today() - 30,pg_temp.today() + 700,'SYN-CERT-2',null)$$, 'the renewal is a new record');
select lives_ok($$select public.vv_save_competence('c6700000-0000-0000-0000-000000000003',pg_temp.ws('wsA'),'SYNTHETIC Second Officer',null,
  'Pesticide application',null,pg_temp.today() - 300,pg_temp.today() + 10,null,null)$$, 'another person''s training expires soon');
select is(pg_temp.status('training'), 'amber: 1 competence record expiring within 30 days.', 'the renewal counts; the expiring one is flagged');
select throws_ok($$select public.vv_save_competence('c6700000-0000-0000-0000-000000000003',pg_temp.ws('wsA'),'SYNTHETIC Second Officer',null,
  'Pesticide application',null,pg_temp.today() - 300,pg_temp.today() + 400,null,'')$$, '22023', null, 'changing a record needs a reason');
select lives_ok($$select public.vv_withdraw_competence('c6700000-0000-0000-0000-000000000003','SYNTHETIC entered against the wrong person')$$, 'a record entered in error is withdrawn');
select is(pg_temp.status('training'), 'green: 1 current competence record.', 'withdrawn records no longer count');
select pg_temp.as_user('00000000-0000-0000-0000-0000000206a4');
select is((select count(*) from public.vv_competence)::int, 3, 'a viewer can read the register, with its history');

-- ---------- Contractors ----------------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000206a2');
select throws_ok($$select public.vv_save_contractor('c6800000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Pest Co','Larviciding at the quay',null,null,
  array[gen_random_uuid()],null)$$, '22023', null, 'a contractor can only be linked to the organisation''s own sites');
select lives_ok($$select public.vv_save_contractor('c6800000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Pest Co','Larviciding at the quay','SYNTHETIC contact',null,
  array['c6000000-0000-0000-0000-000000000001']::uuid[],null)$$, 'a manager records a contractor working at the site');
select is(pg_temp.status('contractors'), 'red: 1 contractor without a current audit.', 'an unaudited contractor is not met');
select throws_ok($$select public.vv_record_contractor_audit('c6810000-0000-0000-0000-000000000001','c6800000-0000-0000-0000-000000000001',gen_random_uuid(),
  pg_temp.today(),'satisfactory','SYNTHETIC all work to standard',null)$$, '22023', null, 'an audit must be at a site the contractor works at');
select lives_ok($$select public.vv_record_contractor_audit('c6810000-0000-0000-0000-000000000001','c6800000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001',
  pg_temp.today() - 10,'satisfactory','SYNTHETIC all work to standard',null)$$, 'the manager records an audit');
select lives_ok($$select public.vv_record_contractor_audit('c6810000-0000-0000-0000-000000000001','c6800000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001',
  pg_temp.today() - 10,'satisfactory','SYNTHETIC all work to standard',null)$$, 'retrying is safe');
select is((select next_due - audited_on from public.vv_contractor_audits), 365, 'the next audit is due in a year by default');
select is(pg_temp.status('contractors'), 'green: All 1 contractor audited and in date.', 'an audited contractor is met');
select throws_ok($$select public.vv_save_contractor('c6800000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Pest Co','Larviciding at the quay','SYNTHETIC contact','ended',
  array['c6000000-0000-0000-0000-000000000001']::uuid[],null)$$, '22023', null, 'ending a contract needs a reason');
reset role;
select throws_ok($$update public.vv_contractor_audits set outcome = 'unsatisfactory'$$, '42501', null, 'audits cannot be rewritten');

-- ---------- Equipment and chemicals --------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000206a2');
select lives_ok($$select public.vv_save_equipment('c6900000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'chemical','SYNTHETIC larvicide','Bti',null,'Store A','5 kg',
  pg_temp.today() + 200,null,null,null)$$, 'a manager registers a chemical');
select is(pg_temp.status('equipment'), 'amber: 1 chemical without an authorisation reference.', 'a chemical without its authorisation is flagged');
select lives_ok($$select public.vv_save_equipment('c6900000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'chemical','SYNTHETIC larvicide','Bti','SYN-HSE-1','Store A','5 kg',
  pg_temp.today() + 200,null,null,'SYNTHETIC authorisation found')$$, 'the authorisation is added with a reason');
select lives_ok($$select public.vv_save_equipment('c6900000-0000-0000-0000-000000000002',pg_temp.ws('wsA'),'equipment','SYNTHETIC backpack sprayer',null,null,'Store A',null,
  pg_temp.today() - 1,null,null,null)$$, 'and equipment past its service date');
select is(pg_temp.status('equipment'), 'red: 1 item in use past the expiry date.', 'an expired item in use is not met');
select lives_ok($$select public.vv_save_equipment('c6900000-0000-0000-0000-000000000002',pg_temp.ws('wsA'),'equipment','SYNTHETIC backpack sprayer',null,null,'Store A',null,
  pg_temp.today() - 1,'withdrawn',null,'SYNTHETIC taken out of use')$$, 'it is withdrawn');
select is(pg_temp.status('equipment'), 'green: 1 item registered and in date.', 'withdrawn items no longer count');
select throws_ok($$select public.vv_save_equipment('c6900000-0000-0000-0000-000000000002',pg_temp.ws('wsA'),'chemical','SYNTHETIC backpack sprayer',null,null,'Store A',null,
  null,'withdrawn',null,'SYNTHETIC kind')$$, '42501', null, 'an item''s kind cannot change');

-- ---------- Site reviews -----------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000206a3');
select throws_ok($$select public.vv_record_site_review('c6a00000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001','sanitary_survey',
  pg_temp.today(),'SYNTHETIC survey of drains and water butts',null,null)$$, '42501', null, 'a field officer cannot record a site review');
select pg_temp.as_user('00000000-0000-0000-0000-0000000206a2');
select lives_ok($$select public.vv_record_site_review('c6a00000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001','sanitary_survey',
  pg_temp.today() - 5,'SYNTHETIC survey of drains and water butts','SYNTHETIC cover the water butts',null)$$, 'a manager records the sanitary survey');
select ok(pg_temp.status('sanitary_survey') like 'green: Last sanitary and vector survey %', 'the sanitary survey is met');
select lives_ok($$select public.vv_record_site_review('c6a00000-0000-0000-0000-000000000002','c6000000-0000-0000-0000-000000000001','wider_survey',
  pg_temp.today() - 400,'SYNTHETIC wider survey of the port estate',null,null)$$, 'and an older wider survey');
select is((select next_due - done_on from public.vv_site_reviews where kind = 'wider_survey') between 1090 and 1100, true, 'a wider survey is due every 3 years');
select ok(pg_temp.status('wider_survey') like 'amber: Last wider survey % No operational areas recorded yet.', 'with no operational areas recorded it is partly met');
select lives_ok($$select public.vv_save_site_area('c6b00000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001','cargo','SYNTHETIC cargo yard',null)$$,
  'an operational area is added');
select ok(pg_temp.status('wider_survey') like 'green:%', 'then the wider survey is met');
reset role;
select throws_ok($$update public.vv_site_reviews set summary = 'SYNTHETIC rewritten summary'$$, '42501', null, 'reviews cannot be rewritten');

-- ---------- Incoming risks ----------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000206a3');
select lives_ok($$select public.vv_save_incoming_risk('c6c00000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001',pg_temp.today(),
  'SYNTHETIC shipping line','SYNTHETIC used tyres arriving from an area with Aedes albopictus','high',null,null)$$, 'a field officer logs a high incoming risk');
select is(pg_temp.status('incoming_risks'), 'red: 1 open high-level incoming risk with no action recorded.', 'with no action it is not met');
select lives_ok($$select public.vv_save_incoming_risk('c6c00000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001',pg_temp.today(),
  'SYNTHETIC shipping line','SYNTHETIC used tyres arriving from an area with Aedes albopictus','high','SYNTHETIC inspect on arrival; ovitraps by the yard',null)$$,
  'adding the action needs no reason');
select throws_ok($$select public.vv_save_incoming_risk('c6c00000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001',pg_temp.today(),
  'SYNTHETIC shipping line','SYNTHETIC used tyres','low','SYNTHETIC inspect on arrival; ovitraps by the yard',null)$$, '22023', null,
  'changing what was reported needs a reason');
select is(pg_temp.status('incoming_risks'), 'amber: 1 incoming risk still open.', 'once acted on it is partly met while open');
select throws_ok($$select public.vv_close_incoming_risk('c6c00000-0000-0000-0000-000000000001',pg_temp.today(),'')$$, '22023', null, 'closing needs a note');
select lives_ok($$select public.vv_close_incoming_risk('c6c00000-0000-0000-0000-000000000001',pg_temp.today(),'SYNTHETIC tyres inspected, nothing found')$$, 'it is closed');
select is(pg_temp.status('incoming_risks'), 'green: No open incoming risks.', 'then met');

-- ---------- Conveyances and follow-ups ------------------------------------------------------------------
select throws_ok($$select public.vv_record_conveyance('c6d00000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001',now(),'ship','SYNTHETIC VESSEL',
  'SYNTHETIC origin','SYNTHETIC next port','suspect','evidence_found',null,null)$$, '23514', null, 'evidence found must be described');
select lives_ok($$select public.vv_record_conveyance('c6d00000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001',now() - interval '1 hour','ship',
  'SYNTHETIC VESSEL','SYNTHETIC origin','SYNTHETIC next port','suspect','evidence_found','SYNTHETIC larvae in a deck container',null)$$,
  'a field officer records a suspect ship with larvae on board');
select lives_ok($$select public.vv_record_conveyance('c6d00000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001',now() - interval '1 hour','ship',
  'SYNTHETIC VESSEL','SYNTHETIC origin','SYNTHETIC next port','suspect','evidence_found','SYNTHETIC larvae in a deck container',null)$$, 'retrying is safe');
select is(pg_temp.status('conveyances'), 'red: 1 conveyance with evidence of vectors and no action recorded.', 'evidence with no action is not met');
select is(pg_temp.status('follow_up'), 'red: 1 conveyance with findings and a next destination but no follow-up notice.', 'and the next port has not been told');
select lives_ok($$select public.vv_record_conveyance('c6d00000-0000-0000-0000-000000000002','c6000000-0000-0000-0000-000000000001',now(),'ship',
  'SYNTHETIC VESSEL','SYNTHETIC origin','SYNTHETIC next port','suspect','treated','SYNTHETIC larvae in a deck container','SYNTHETIC container emptied and treated')$$,
  'a second record shows the treatment');
select throws_ok($$select public.vv_send_follow_up('c6e00000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001',gen_random_uuid(),'SYNTHETIC next port',
  pg_temp.today(),'email','SYNTHETIC larvae found and treated')$$, '22023', null, 'a notice must link to a conveyance at this site');
select lives_ok($$select public.vv_send_follow_up('c6e00000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001','c6d00000-0000-0000-0000-000000000001',
  'SYNTHETIC next port',pg_temp.today(),'email','SYNTHETIC larvae found; container emptied and treated')$$, 'a follow-up notice goes to the next port');
select lives_ok($$select public.vv_send_follow_up('c6e00000-0000-0000-0000-000000000002','c6000000-0000-0000-0000-000000000001','c6d00000-0000-0000-0000-000000000002',
  'SYNTHETIC next port',pg_temp.today(),'email','SYNTHETIC larvae found; container emptied and treated')$$, 'and for the second record');
select is(pg_temp.status('follow_up'), 'green: Follow-up notices sent where needed.', 'every conveyance with findings has a notice');
select lives_ok($$select public.vv_acknowledge_follow_up('c6e00000-0000-0000-0000-000000000001',pg_temp.today(),'SYNTHETIC received')$$, 'the acknowledgement is recorded');
select lives_ok($$select public.vv_acknowledge_follow_up('c6e00000-0000-0000-0000-000000000001',pg_temp.today(),'SYNTHETIC received')$$, 'retrying is safe');
reset role;
select throws_ok($$update public.vv_follow_ups set summary = 'SYNTHETIC rewritten'$$, '42501', null, 'what a notice said cannot be rewritten');
select throws_ok($$update public.vv_conveyances set outcome = 'no_evidence'$$, '42501', null, 'conveyance inspections cannot be rewritten');

-- ---------- Treatment supervision ------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000206a3');
select public.vv_record_control('c6f00000-0000-0000-0000-000000000001','c6000000-0000-0000-0000-000000000001',null,null,'larviciding',pg_temp.today(),
  'SYNTHETIC larvicide','Bti','1 kg','SYNTHETIC drains',null,null,null,'SYNTHETIC operator',null,null);
select is(pg_temp.status('treatment_supervision'), 'red: 1 chemical treatment without a named supervisor.', 'an unsupervised chemical treatment is not met');
select public.vv_record_control('c6f00000-0000-0000-0000-000000000002','c6000000-0000-0000-0000-000000000001',null,null,'larviciding',pg_temp.today(),
  'SYNTHETIC larvicide','Bti','1 kg','SYNTHETIC drains',null,null,null,'SYNTHETIC operator','00000000-0000-0000-0000-0000000206a2',null);
select pg_temp.as_user('00000000-0000-0000-0000-0000000206a2');
select public.vv_withdraw_control('c6f00000-0000-0000-0000-000000000001','SYNTHETIC recorded again with the supervisor');
select is(pg_temp.status('treatment_supervision'), 'green: All 1 chemical treatment supervised.', 'once supervised it is met');

-- ---------- Separation between organisations -----------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000206b1');
select is((select count(*) from public.vv_competence)::int + (select count(*) from public.vv_contractors)::int + (select count(*) from public.vv_contractor_sites)::int
  + (select count(*) from public.vv_contractor_audits)::int + (select count(*) from public.vv_equipment)::int + (select count(*) from public.vv_conveyances)::int
  + (select count(*) from public.vv_follow_ups)::int + (select count(*) from public.vv_incoming_risks)::int + (select count(*) from public.vv_site_reviews)::int, 0,
  'another organisation sees none of these records');
select throws_ok($$select public.vv_save_competence(gen_random_uuid(),pg_temp.ws('wsA'),'SYNTHETIC Intruder',null,'Anything',null,pg_temp.today(),null,null,null)$$,
  '42501', null, 'nor writes to the register');
select throws_ok($$select public.vv_record_conveyance(gen_random_uuid(),'c6000000-0000-0000-0000-000000000001',now(),'ship','SYNTHETIC',null,null,'routine','no_evidence',null,null)$$,
  '42501', null, 'nor records at its sites');
select throws_ok($$select public.vv_close_incoming_risk('c6c00000-0000-0000-0000-000000000001',pg_temp.today(),'SYNTHETIC intruder closing')$$, '42501', null,
  'nor closes its risks');
select is((select count(*) from public.vv_site_compliance('c6000000-0000-0000-0000-000000000001'))::int, 0, 'nor sees its compliance');
reset role;
select is((select count(*) from public.vv_events where record_type in ('competence', 'contractor', 'contractor_audit', 'equipment', 'conveyance', 'follow_up',
  'incoming_risk', 'site_review'))::int > 15, true, 'every change is in the history');

-- ---------- Signed-out visitors ------------------------------------------------------------------
set local role anon;
select throws_ok($$select count(*) from public.vv_competence$$, '42501', null, 'signed-out visitors cannot read the registers');
select throws_ok($$select public.vv_record_conveyance(gen_random_uuid(),gen_random_uuid(),now(),'ship','X',null,null,'routine','no_evidence',null,null)$$, '42501', null,
  'nor call the record functions');
reset role;

select * from finish();
rollback;
