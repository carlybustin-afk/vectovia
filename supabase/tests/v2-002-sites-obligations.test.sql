-- pgTAP tests for docs/database/v2-002-sites-obligations.sql. Synthetic people and data only; rolls back.
begin;
select no_plan();

-- Organisation A (port health): A1 owner, A2 manager, A3 field officer, A4 viewer.
-- Organisation B (council): B1 owner. Organisation C: C1 owner. Content team: R reviewer, P publisher.
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000202a1','v22a1@test.invalid',now()), ('00000000-0000-0000-0000-0000000202a2','v22a2@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000202a3','v22a3@test.invalid',now()), ('00000000-0000-0000-0000-0000000202a4','v22a4@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000202b1','v22b1@test.invalid',now()), ('00000000-0000-0000-0000-0000000202c1','v22c1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000202e1','v22r@test.invalid',now()),  ('00000000-0000-0000-0000-0000000202e2','v22p@test.invalid',now());
insert into public.content_roles (user_id, role) values
 ('00000000-0000-0000-0000-0000000202e1','reviewer'), ('00000000-0000-0000-0000-0000000202e2','content_admin');
create temp table ids (k text primary key, v uuid);
create temp table toks (k text primary key, v text);
grant all on ids, toks to authenticated;
insert into ids values
 ('wsA', public.provision_organisation('SYNTHETIC V22 Port Health','00000000-0000-0000-0000-0000000202a1')),
 ('wsB', public.provision_organisation('SYNTHETIC V22 Council','00000000-0000-0000-0000-0000000202b1')),
 ('wsC', public.provision_organisation('SYNTHETIC V22 Other','00000000-0000-0000-0000-0000000202c1'));
insert into public.workspace_members (workspace_id, user_id, role)
 select (select v from ids where k='wsA'), u::uuid, 'member'::public.workspace_role
   from unnest(array['00000000-0000-0000-0000-0000000202a2','00000000-0000-0000-0000-0000000202a3','00000000-0000-0000-0000-0000000202a4']) u;

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.ws(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;
create function pg_temp.tok(k text) returns text language sql as $$ select v from toks where toks.k = $1 $$;
create function pg_temp.status(_site uuid, _req text) returns text language sql as $$
  select status from public.vv_site_compliance(_site) where requirement_key = _req $$;
-- A square of about 140 m by 220 m near 51.12 N, 1.33 E.
create function pg_temp.square() returns jsonb language sql as $$
  select '{"type":"Polygon","coordinates":[[[1.330,51.120],[1.332,51.120],[1.332,51.122],[1.330,51.122],[1.330,51.120]]]}'::jsonb $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000202a1');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000202a2','vectovia','manage');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000202a3','vectovia','field');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000202a4','vectovia','view');
select public.vv_save_site('c2000000-0000-0000-0000-00000000000a',pg_temp.ws('wsA'),'SYNTHETIC Dock Gate',null,null,null,null,null,51.121,1.331,null,null,null,'{}');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202b1');
select public.vv_save_site('c2000000-0000-0000-0000-00000000000b',pg_temp.ws('wsB'),'SYNTHETIC Dock Gate (council)',null,null,null,null,null,51.121,1.331,null,null,null,'{}');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202c1');
select public.vv_save_site('c2000000-0000-0000-0000-00000000000c',pg_temp.ws('wsC'),'SYNTHETIC Other Site',null,null,null,null,null,52.0,1.0,null,null,null,'{}');

-- ---------- Geometry ------------------------------------------------------------------------
select ok(public.vv_valid_polygon(pg_temp.square()), 'a closed square is a valid boundary');
select ok(not public.vv_valid_polygon('{"type":"Polygon","coordinates":[[[1,51],[1.1,51],[1.1,51.1],[1,51.1]]]}'), 'an unclosed ring is refused');
select ok(not public.vv_valid_polygon('{"type":"Polygon","coordinates":[[[200,51],[1.1,51],[1.1,51.1],[200,51]]]}'), 'longitude out of range is refused');
select ok(not public.vv_valid_polygon('{"type":"Point","coordinates":[1,51]}'), 'a point is not a boundary');
select ok(not public.vv_valid_polygon('{"type":"Polygon","coordinates":[[[1,51],[1.1,51],[1,51]]]}'), 'a ring needs at least four positions');
select ok(public.vv_in_zone(pg_temp.square(), 400, 51.121, 1.331), 'a point inside the boundary is in the zone');
select ok(public.vv_in_zone(pg_temp.square(), 400, 51.121, 1.3363), 'a point about 300 m outside is inside the 400 m zone');
select ok(not public.vv_in_zone(pg_temp.square(), 400, 51.121, 1.3463), 'a point about 1 km outside is not');
select ok(not public.vv_in_zone(pg_temp.square(), 200, 51.121, 1.3363), 'and 300 m is outside a 200 m zone');

select pg_temp.as_user('00000000-0000-0000-0000-0000000202a3');
select throws_ok($$select public.vv_save_site_geometry('c2000000-0000-0000-0000-00000000000a','port',pg_temp.square(),400,null)$$, '42501', null,
  'a field officer cannot change the boundary');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202b1');
select throws_ok($$select public.vv_save_site_geometry('c2000000-0000-0000-0000-00000000000a','port',pg_temp.square(),400,null)$$, '42501', null,
  'another organisation cannot change it');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202a2');
select throws_ok($$select public.vv_save_site_geometry('c2000000-0000-0000-0000-00000000000a','port','{"type":"Polygon","coordinates":[[[1,51],[2,51],[2,52]]]}',400,null)$$,
  '22023', null, 'an invalid boundary is refused');
select throws_ok($$select public.vv_save_site_geometry('c2000000-0000-0000-0000-00000000000a','port',pg_temp.square(),300,null)$$, '23514', null,
  'a point of entry cannot have a zone under 400 m');
select lives_ok($$select public.vv_save_site_geometry('c2000000-0000-0000-0000-00000000000a','port',pg_temp.square(),400,'SYNTHETIC international freight')$$,
  'a manager records the type, boundary and 400 m zone');
select is((select site_type || ':' || zone_m from public.vv_sites where id = 'c2000000-0000-0000-0000-00000000000a'), 'port:400', 'they are saved');
select is((select detail ->> 'boundary_changed' from public.vv_events where record_id = 'c2000000-0000-0000-0000-00000000000a' and kind = 'geometry_changed'),
  'true', 'the change is in the site history');
select ok(public.vv_point_in_site_zone('c2000000-0000-0000-0000-00000000000a', 51.121, 1.3363), 'the site zone check works');

-- Operational areas
select lives_ok($$select public.vv_save_site_area('c2200000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-00000000000a','cargo','SYNTHETIC Freight yard',
  '{"type":"Polygon","coordinates":[[[1.340,51.120],[1.341,51.120],[1.341,51.121],[1.340,51.121],[1.340,51.120]]]}')$$, 'a manager adds an operational area');
select lives_ok($$select public.vv_save_site_area('c2200000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-00000000000a','cargo','SYNTHETIC Freight yard',
  '{"type":"Polygon","coordinates":[[[1.340,51.120],[1.341,51.120],[1.341,51.121],[1.340,51.121],[1.340,51.120]]]}')$$, 'saving again is safe');
select ok(public.vv_point_in_site_zone('c2000000-0000-0000-0000-00000000000a', 51.1205, 1.3463), 'the zone extends 400 m from the area too');
select throws_ok($$select public.vv_remove_site_area('c2200000-0000-0000-0000-000000000001','')$$, '22023', null, 'removing an area needs a reason');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202a4');
select is((select count(*) from public.vv_site_areas)::int, 1, 'a viewer sees the area');
select throws_ok($$select public.vv_save_site_area('c2200000-0000-0000-0000-000000000002','c2000000-0000-0000-0000-00000000000a','terminal','SYNTHETIC T1',null)$$,
  '42501', null, 'but cannot add one');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202b1');
select is((select count(*) from public.vv_site_areas)::int, 0, 'another organisation sees no areas');
select throws_ok($$update public.vv_site_areas set name = 'x'$$, '42501', null, 'areas cannot be edited directly');

-- ---------- Shared sites -------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000202a3');
select throws_ok($$select public.vv_create_site_share('c2000000-0000-0000-0000-00000000000a')$$, '42501', null, 'a field officer cannot share a site');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202a2');
insert into toks values ('t1', public.vv_create_site_share('c2000000-0000-0000-0000-00000000000a'));
select ok(pg_temp.tok('t1') ~ '^[0-9a-f]{64}$', 'a manager gets a one-time share code');
reset role;
select is((select count(*) from public.vv_site_share_codes where token_hash = pg_temp.tok('t1'))::int, 0, 'only a fingerprint of the code is stored');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202a2');
select throws_ok($$select public.vv_join_shared_site(pg_temp.tok('t1'),'c2000000-0000-0000-0000-00000000000a')$$, '22023', null,
  'an organisation cannot join its own share');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202b1');
select throws_ok($$select public.vv_join_shared_site(repeat('0',64),'c2000000-0000-0000-0000-00000000000b')$$, '22023', 'that code is not valid',
  'a wrong code is refused');
select throws_ok($$select public.vv_join_shared_site(pg_temp.tok('t1'),'c2000000-0000-0000-0000-00000000000a')$$, '42501', null,
  'the council cannot link port health''s site record');
select lives_ok($$select public.vv_join_shared_site(pg_temp.tok('t1'),'c2000000-0000-0000-0000-00000000000b')$$, 'the council joins with its own site');
select lives_ok($$select public.vv_join_shared_site(pg_temp.tok('t1'),'c2000000-0000-0000-0000-00000000000b')$$, 'retrying is safe');
select is((select count(*) from public.vv_shared_site('c2000000-0000-0000-0000-00000000000b'))::int, 2, 'the council sees both members');
select is((select organisation from public.vv_shared_site('c2000000-0000-0000-0000-00000000000b') where is_lead), 'SYNTHETIC V22 Port Health',
  'with port health as the lead');
select ok((select boundary = pg_temp.square() from public.vv_shared_site('c2000000-0000-0000-0000-00000000000b') where is_lead),
  'and its boundary');
select is((select jsonb_array_length(areas) from public.vv_shared_site('c2000000-0000-0000-0000-00000000000b') where is_lead), 1, 'and its areas');
select is((select count(*) from public.vv_sites where id = 'c2000000-0000-0000-0000-00000000000a')::int, 0,
  'but not port health''s site record');
select is((select count(*) from public.vv_site_areas)::int, 0, 'nor its area records directly');
select is((select count(*) from public.vv_events where record_id = 'c2000000-0000-0000-0000-00000000000a')::int, 0, 'nor its history');
select throws_ok($$select * from public.vv_shared_site('c2000000-0000-0000-0000-00000000000a')$$, '42501', null,
  'and cannot ask about port health''s site directly');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202c1');
select throws_ok($$select public.vv_join_shared_site(pg_temp.tok('t1'),'c2000000-0000-0000-0000-00000000000c')$$, '22023', 'that code is not valid',
  'a used code cannot be used again');
select throws_ok($$select * from public.vv_shared_site('c2000000-0000-0000-0000-00000000000b')$$, '42501', null, 'outsiders see nothing');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202a4');
select is((select organisation from public.vv_shared_site('c2000000-0000-0000-0000-00000000000a') where not is_lead), 'SYNTHETIC V22 Council',
  'port health sees the council has joined');
select is((select detail ->> 'organisation' from public.vv_events where record_id = 'c2000000-0000-0000-0000-00000000000a' and kind = 'organisation_joined'),
  'SYNTHETIC V22 Council', 'and it is in the site history');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202b1');
select throws_ok($$select public.vv_create_site_share('c2000000-0000-0000-0000-00000000000b')$$, '42501', null, 'only the lead can invite others');
select throws_ok($$select public.vv_leave_shared_site('c2000000-0000-0000-0000-00000000000b','')$$, '22023', null, 'leaving needs a reason');
select lives_ok($$select public.vv_leave_shared_site('c2000000-0000-0000-0000-00000000000b','SYNTHETIC no longer needed')$$, 'the council leaves');
select is((select count(*) from public.vv_shared_site('c2000000-0000-0000-0000-00000000000b'))::int, 0, 'and no longer sees the shared site');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202a2');
select is((select count(*) from public.vv_shared_site('c2000000-0000-0000-0000-00000000000a'))::int, 1, 'port health is left on its own');
insert into toks values ('t2', public.vv_create_site_share('c2000000-0000-0000-0000-00000000000a'));
select pg_temp.as_user('00000000-0000-0000-0000-0000000202c1');
select lives_ok($$select public.vv_join_shared_site(pg_temp.tok('t2'),'c2000000-0000-0000-0000-00000000000c')$$, 'a new code lets another organisation join');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202a2');
select lives_ok($$select public.vv_leave_shared_site('c2000000-0000-0000-0000-00000000000a','SYNTHETIC ending the share')$$, 'when the lead leaves');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202c1');
select is((select count(*) from public.vv_shared_site('c2000000-0000-0000-0000-00000000000c'))::int, 0, 'sharing ends for everyone');
reset role;
select is((select count(*) from public.vv_site_group_members)::int, 3, 'membership history is kept');
select throws_ok($$delete from public.vv_site_group_members$$, '42501', null, 'and never deleted');

-- ---------- Obligation sets ------------------------------------------------------------------
insert into public.vv_obligation_sets (id, key, name, framework, jurisdiction, applies_to) values
  ('c2300000-0000-0000-0000-000000000001', 'synthetic_poe', 'SYNTHETIC point of entry set', 'ihr', 'International', '{port,airport}');
insert into public.vv_obligation_versions (id, set_id, version, summary, status) values
  ('c2310000-0000-0000-0000-000000000001', 'c2300000-0000-0000-0000-000000000001', 1, 'SYNTHETIC version one of the test set.', 'draft');
insert into public.vv_obligation_requirements (version_id, key, sort_order, title, what, check_kind) values
  ('c2310000-0000-0000-0000-000000000001', 'zone', 1, 'SYNTHETIC zone', 'Traps inside the zone around the site.', 'zone'),
  ('c2310000-0000-0000-0000-000000000001', 'checks', 2, 'SYNTHETIC checks', 'Checks done on schedule.', 'checks'),
  ('c2310000-0000-0000-0000-000000000001', 'official_id', 3, 'SYNTHETIC identification', 'Finds officially identified.', 'official_id'),
  ('c2310000-0000-0000-0000-000000000001', 'records', 4, 'SYNTHETIC records', 'Records kept with evidence.', 'records'),
  ('c2310000-0000-0000-0000-000000000001', 'plan', 5, 'SYNTHETIC plan', 'A current surveillance plan.', 'assessment');
update public.vv_obligation_versions set status = 'in_review' where id = 'c2310000-0000-0000-0000-000000000001';
select throws_ok($$update public.vv_obligation_requirements set title = 'changed' where key = 'plan'$$, '42501', null,
  'requirements are fixed once the version leaves draft');
select throws_ok($$insert into public.vv_obligation_requirements (version_id, key, sort_order, title, what)
  values ('c2310000-0000-0000-0000-000000000001', 'extra', 9, 'SYNTHETIC extra', 'Added after review.')$$, '42501', null, 'and cannot be added to');

select pg_temp.as_user('00000000-0000-0000-0000-0000000202a2');
select is((select count(*) from public.vv_obligation_versions)::int, 0, 'unpublished versions are hidden from organisations');
select is((select count(*) from public.vv_obligation_requirements)::int, 0, 'and so are their requirements');
select throws_ok($$select public.vv_adopt_obligation_set('c2400000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-00000000000a','synthetic_poe')$$,
  '22023', 'this obligation set has not been published yet', 'a site cannot adopt an unpublished set');
select throws_ok($$select public.vv_obl_review('c2310000-0000-0000-0000-000000000001', true, 'SYNTHETIC looks right')$$, '42501', null,
  'an organisation manager cannot review');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202e2');
select throws_ok($$select public.vv_obl_publish('c2310000-0000-0000-0000-000000000001')$$, '42501', null, 'nothing is published before review');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202e1');
select is((select count(*) from public.vv_obligation_requirements)::int, 5, 'the reviewer sees the draft requirements');
select throws_ok($$select public.vv_obl_review('c2310000-0000-0000-0000-000000000001', true, 'short')$$, '22023', null, 'a review needs a proper note');
select lives_ok($$select public.vv_obl_review('c2310000-0000-0000-0000-000000000001', true, 'SYNTHETIC checked against the source')$$, 'the reviewer approves');
select throws_ok($$select public.vv_obl_publish('c2310000-0000-0000-0000-000000000001')$$, '42501', null, 'the reviewer cannot also publish');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202e2');
select lives_ok($$select public.vv_obl_publish('c2310000-0000-0000-0000-000000000001')$$, 'a different content admin publishes');
reset role;
select throws_ok($$update public.vv_obligation_versions set summary = 'SYNTHETIC rewritten after publishing.' where id = 'c2310000-0000-0000-0000-000000000001'$$,
  '42501', null, 'a published version cannot be rewritten');

-- ---------- Adoption and compliance ------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000202a3');
select throws_ok($$select public.vv_adopt_obligation_set('c2400000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-00000000000a','synthetic_poe')$$,
  '42501', null, 'a field officer cannot adopt a set');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202a2');
select lives_ok($$select public.vv_adopt_obligation_set('c2400000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-00000000000a','synthetic_poe')$$,
  'a manager adopts the published set');
select lives_ok($$select public.vv_adopt_obligation_set('c2400000-0000-0000-0000-000000000009','c2000000-0000-0000-0000-00000000000a','synthetic_poe')$$,
  'adopting again is harmless');
select is((select count(*) from public.vv_site_obligations)::int, 1, 'one adoption');
select is((select count(*) from public.vv_site_compliance('c2000000-0000-0000-0000-00000000000a'))::int, 5, 'compliance lists every requirement');
select is(pg_temp.status('c2000000-0000-0000-0000-00000000000a','zone'), 'amber', 'boundary but no traps: zone is amber');
select is(pg_temp.status('c2000000-0000-0000-0000-00000000000a','checks'), 'red', 'no active traps: checks are red');
select is(pg_temp.status('c2000000-0000-0000-0000-00000000000a','official_id'), 'green', 'nothing awaiting identification: green');
select is(pg_temp.status('c2000000-0000-0000-0000-00000000000a','records'), 'green', 'records: green');
select is(pg_temp.status('c2000000-0000-0000-0000-00000000000a','plan'), 'not_assessed', 'the plan is not assessed yet');

-- A trap deployed inside the zone, checked on schedule.
select public.vv_save_trap('c2500000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYN-A-1',(select id from public.vv_trap_types where key = 'ovitrap'),null,null,null);
select public.vv_deploy_trap('c2600000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'c2500000-0000-0000-0000-000000000001',
  'c2000000-0000-0000-0000-00000000000a',51.121,1.3363,null,now(),null,14);
select is(pg_temp.status('c2000000-0000-0000-0000-00000000000a','zone'), 'green', 'a trap inside the zone turns it green');
select is(pg_temp.status('c2000000-0000-0000-0000-00000000000a','checks'), 'green', 'and checks are on schedule');
-- A second trap far outside the zone and overdue.
select public.vv_save_trap('c2500000-0000-0000-0000-000000000002',pg_temp.ws('wsA'),'SYN-A-2',(select id from public.vv_trap_types where key = 'ovitrap'),null,null,null);
select public.vv_deploy_trap('c2600000-0000-0000-0000-000000000002',pg_temp.ws('wsA'),'c2500000-0000-0000-0000-000000000002',
  'c2000000-0000-0000-0000-00000000000a',51.2,1.5,null,now() - interval '20 days',null,7);
select is((select detail from public.vv_site_compliance('c2000000-0000-0000-0000-00000000000a') where requirement_key = 'zone'),
  '1 active trap inside the 400 m zone.', 'only the trap inside the zone counts');
select is(pg_temp.status('c2000000-0000-0000-0000-00000000000a','checks'), 'red', 'an overdue check turns checks red');
-- An invasive species found, not yet officially identified.
select public.vv_record_visit('c2700000-0000-0000-0000-000000000001','c2600000-0000-0000-0000-000000000001',now(),null,'collected',null,'working',null,null,null,
  '[{"id":"c2800000-0000-0000-0000-000000000001"}]');
select public.vv_save_result('c2900000-0000-0000-0000-000000000001','c2800000-0000-0000-0000-000000000001','provisional',
  (select id from public.vv_taxa where key = 'aedes_albopictus'),null,1,'eggs','morphology','SYNTHETIC officer',null,null,current_date,null,null);
select is(pg_temp.status('c2000000-0000-0000-0000-00000000000a','official_id'), 'amber', 'a provisional invasive find is amber until officially identified');
select public.vv_save_result('c2900000-0000-0000-0000-000000000001','c2800000-0000-0000-0000-000000000001','confirmed',
  (select id from public.vv_taxa where key = 'aedes_albopictus'),null,1,'eggs','molecular',null,'SYNTHETIC lab','SYN-1',current_date,null,'SYNTHETIC official result');
select is(pg_temp.status('c2000000-0000-0000-0000-00000000000a','official_id'), 'green', 'and green once officially confirmed');

-- Assessments
select pg_temp.as_user('00000000-0000-0000-0000-0000000202a3');
select throws_ok($$select public.vv_assess_requirement('c2a00000-0000-0000-0000-000000000001','c2400000-0000-0000-0000-000000000001','plan','green','SYNTHETIC plan in place',null,null)$$,
  '42501', null, 'a field officer cannot assess');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202a2');
select throws_ok($$select public.vv_assess_requirement('c2a00000-0000-0000-0000-000000000001','c2400000-0000-0000-0000-000000000001','zone','green','SYNTHETIC',null,null)$$,
  '22023', 'this requirement is worked out from records', 'record-based requirements cannot be overridden');
select throws_ok($$select public.vv_assess_requirement('c2a00000-0000-0000-0000-000000000001','c2400000-0000-0000-0000-000000000001','plan','green','SYNTHETIC plan',(now() at time zone 'Europe/London')::date - 1,null)$$,
  '22023', null, 'the review date cannot be in the past');
select lives_ok($$select public.vv_assess_requirement('c2a00000-0000-0000-0000-000000000001','c2400000-0000-0000-0000-000000000001','plan','amber',
  'SYNTHETIC plan drafted, awaiting sign-off',current_date + 30,null)$$, 'a manager records an assessment with a review date');
select is(pg_temp.status('c2000000-0000-0000-0000-00000000000a','plan'), 'amber', 'it shows in compliance');
select lives_ok($$select public.vv_assess_requirement('c2a00000-0000-0000-0000-000000000002','c2400000-0000-0000-0000-000000000001','plan','green',
  'SYNTHETIC plan signed off',current_date + 365,null)$$, 'a later assessment');
select is(pg_temp.status('c2000000-0000-0000-0000-00000000000a','plan'), 'green', 'the latest one counts');
select is((select count(*) from public.vv_requirement_assessments)::int, 2, 'earlier assessments are kept');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202a4');
select is(pg_temp.status('c2000000-0000-0000-0000-00000000000a','plan'), 'green', 'a viewer sees compliance');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202b1');
select is((select count(*) from public.vv_site_compliance('c2000000-0000-0000-0000-00000000000a'))::int, 0, 'another organisation sees no compliance');
select is((select count(*) from public.vv_site_obligations)::int + (select count(*) from public.vv_requirement_assessments)::int, 0,
  'nor adoptions or assessments');
select throws_ok($$select public.vv_adopt_obligation_set('c2400000-0000-0000-0000-000000000002','c2000000-0000-0000-0000-00000000000a','synthetic_poe')$$,
  '42501', null, 'nor adopt sets for it');
select is((select count(*) from public.vv_obligation_requirements)::int, 5, 'but everyone can read published requirements');

-- A new version: the site moves to it when re-adopted; old assessments stay with the old requirements.
reset role;
insert into public.vv_obligation_versions (id, set_id, version, summary, status) values
  ('c2310000-0000-0000-0000-000000000002', 'c2300000-0000-0000-0000-000000000001', 2, 'SYNTHETIC version two of the test set.', 'draft');
insert into public.vv_obligation_requirements (version_id, key, sort_order, title, what, check_kind) values
  ('c2310000-0000-0000-0000-000000000002', 'plan', 1, 'SYNTHETIC plan v2', 'A current surveillance plan, reviewed yearly.', 'assessment');
update public.vv_obligation_versions set status = 'in_review' where id = 'c2310000-0000-0000-0000-000000000002';
select pg_temp.as_user('00000000-0000-0000-0000-0000000202e1');
select public.vv_obl_review('c2310000-0000-0000-0000-000000000002', true, 'SYNTHETIC checked version two');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202e2');
select public.vv_obl_publish('c2310000-0000-0000-0000-000000000002');
select is((select status::text from public.vv_obligation_versions where version = 1), 'superseded', 'publishing v2 supersedes v1');
select pg_temp.as_user('00000000-0000-0000-0000-0000000202a2');
select is((select version from public.vv_site_compliance('c2000000-0000-0000-0000-00000000000a') limit 1), 1, 'the site stays on v1 until updated');
select lives_ok($$select public.vv_adopt_obligation_set('c2400000-0000-0000-0000-000000000003','c2000000-0000-0000-0000-00000000000a','synthetic_poe')$$,
  'the manager updates to the new version');
select is((select version || ':' || status from public.vv_site_compliance('c2000000-0000-0000-0000-00000000000a')), '2:not_assessed',
  'the new requirement needs assessing');
select is((select count(*) from public.vv_events where kind = 'obligation_updated')::int, 1, 'the update is in the site history');
select throws_ok($$select public.vv_remove_site_obligation('c2400000-0000-0000-0000-000000000001','')$$, '22023', null, 'removing a set needs a reason');
select lives_ok($$select public.vv_remove_site_obligation('c2400000-0000-0000-0000-000000000001','SYNTHETIC wrong set')$$, 'a manager removes it');
select is((select count(*) from public.vv_site_compliance('c2000000-0000-0000-0000-00000000000a'))::int, 0, 'it leaves compliance');
reset role;
select is((select count(*) from public.vv_site_obligations)::int, 1, 'but the record is kept');

select * from finish();
rollback;
