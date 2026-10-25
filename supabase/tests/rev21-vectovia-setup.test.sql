-- pgTAP tests for docs/database/rev21-vectovia-setup.sql.
-- Requires revs 6–21. Synthetic people and data only; everything rolls back.
begin;
select no_plan();

-- Council A (Vectovia on): A1 owner; A2 manager; A3 field officer (Port team); A4 field officer (River team);
-- A5 view only (Port team); A6 member with no Vectovia access. Council B (Vectovia on): B1 owner.
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000021f1','r21p1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000021a1','r21a1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000021a2','r21a2@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000021a3','r21a3@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000021a4','r21a4@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000021a5','r21a5@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000021a6','r21a6@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000021b1','r21b1@test.invalid',now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000021f1');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values
 ('wsA', public.provision_organisation('SYNTHETIC R21 Council A','00000000-0000-0000-0000-0000000021a1')),
 ('wsB', public.provision_organisation('SYNTHETIC R21 Council B','00000000-0000-0000-0000-0000000021b1'));
insert into public.workspace_members (workspace_id, user_id, role)
 select (select v from ids where k='wsA'), u::uuid, 'member'::public.workspace_role
   from unnest(array['00000000-0000-0000-0000-0000000021a2','00000000-0000-0000-0000-0000000021a3','00000000-0000-0000-0000-0000000021a4',
                     '00000000-0000-0000-0000-0000000021a5','00000000-0000-0000-0000-0000000021a6']) u;

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.ws(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;

select pg_temp.as_user('00000000-0000-0000-0000-0000000021f1');
select public.set_workspace_product(pg_temp.ws('wsA'),'vectovia',true);
select public.set_workspace_product(pg_temp.ws('wsB'),'vectovia',true);
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a1');
insert into ids values ('tPort', public.create_team(pg_temp.ws('wsA'),'SYNTHETIC Port')), ('tRiver', public.create_team(pg_temp.ws('wsA'),'SYNTHETIC River'));
select public.add_team_member(pg_temp.ws('tPort'),'00000000-0000-0000-0000-0000000021a3');
select public.add_team_member(pg_temp.ws('tRiver'),'00000000-0000-0000-0000-0000000021a4');
select public.add_team_member(pg_temp.ws('tPort'),'00000000-0000-0000-0000-0000000021a5');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000021a2','vectovia','manage');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000021a3','vectovia','field');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000021a4','vectovia','field');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000021a5','vectovia','view');

-- ---------- Shared lists ------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a6');
select ok((select count(*) from public.vv_taxa) >= 10, 'starter species list is readable');
select is((select count(*) from public.vv_taxa where checked)::int, 0, 'starter list is marked not yet checked');
select is((select count(*) from information_schema.columns where table_schema='public' and table_name in ('vv_taxa','vv_trap_types') and column_name='workspace_id')::int,
  0, 'shared lists have no council column');
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a2');
select throws_ok($$insert into public.vv_taxa (key, scientific_name) values ('synthetic_x','SYNTHETIC x')$$, '42501', null, 'nobody writes the shared list directly');

-- ---------- Programmes ---------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a3');
select throws_ok($$select public.vv_save_programme('51000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Port mosquito',null,null,null,null,null)$$,
  '42501', null, 'field officers cannot create programmes');
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a2');
select lives_ok($$select public.vv_save_programme('51000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Port mosquito','SYNTHETIC',
  'active',current_date,null,array[pg_temp.ws('tPort')])$$, 'manager creates the Port programme, run by the Port team');
select lives_ok($$select public.vv_save_programme('51000000-0000-0000-0000-000000000002',pg_temp.ws('wsA'),'SYNTHETIC River mosquito',null,
  'active',null,null,array[pg_temp.ws('tRiver')])$$, 'and the River programme');
select lives_ok($$select public.vv_save_programme('51000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Port mosquito 2026','SYNTHETIC',
  'active',current_date,null,array[pg_temp.ws('tPort')])$$, 'saving again updates it');
select is((select detail->'name'->>'to' from public.vv_events where record_id='51000000-0000-0000-0000-000000000001' and kind='changed'),
  'SYNTHETIC Port mosquito 2026', 'the change is audited with before and after');
select throws_ok($$select public.vv_save_programme('51000000-0000-0000-0000-000000000003',pg_temp.ws('wsA'),'SYNTHETIC bad',null,null,null,null,
  array['00000000-0000-0000-0000-000000000099'::uuid])$$, '22023', null, 'only this council''s teams');
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a3');
select is((select string_agg(name, ',') from public.vv_programmes), 'SYNTHETIC Port mosquito 2026', 'A3 (Port team) sees only the Port programme');
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a2');
select is((select count(*) from public.vv_programmes)::int, 2, 'the manager sees every programme');
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a6');
select is((select count(*) from public.vv_programmes)::int, 0, 'someone without Vectovia access sees none');

-- ---------- Sites ----------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a3');
select throws_ok($$select public.vv_save_site('52000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Dock 4',null,null,null,null,null,
  51.95,1.30,'SYNTHETIC east quay',null,null,null)$$, '22023', null, 'a field officer must put a site in one of their programmes');
select throws_ok($$select public.vv_save_site('52000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Dock 4',null,null,null,null,null,
  51.95,1.30,'SYNTHETIC east quay',null,null,array['51000000-0000-0000-0000-000000000002'::uuid])$$, '22023', null,
  'and not in a programme they cannot see');
select is(public.vv_save_site('52000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Dock 4',null,null,null,null,null,
  51.95,1.30,'SYNTHETIC east quay, no postal address','SYNTHETIC ask at gate 2',null,array['51000000-0000-0000-0000-000000000001'::uuid]),
  'VS-0001', 'a port site with coordinates and no address gets the next reference');
select is(public.vv_save_site('52000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Dock 4',null,null,null,null,null,
  51.95,1.30,'SYNTHETIC east quay, no postal address','SYNTHETIC ask at gate 2',null,array['51000000-0000-0000-0000-000000000001'::uuid]),
  'VS-0001', 'saving again is retry-safe');
select throws_ok($$select public.vv_save_site('52000000-0000-0000-0000-000000000002',pg_temp.ws('wsA'),'SYNTHETIC nowhere',null,null,null,null,null,
  null,null,null,null,null,array['51000000-0000-0000-0000-000000000001'::uuid])$$, '23514', null,
  'a site needs coordinates, an address line or a description');
select throws_ok($$select public.vv_save_site('52000000-0000-0000-0000-000000000002',pg_temp.ws('wsA'),'SYNTHETIC half',null,null,null,null,null,
  51.9,null,'x',null,null,array['51000000-0000-0000-0000-000000000001'::uuid])$$, '23514', null, 'latitude and longitude go together');
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a4');
select is((select count(*) from public.vv_sites)::int, 0, 'A4 (River team) cannot see a Port site');
select throws_ok($$select public.vv_save_site('52000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC hijack',null,null,null,null,null,
  51.95,1.30,'x',null,null,array['51000000-0000-0000-0000-000000000002'::uuid])$$, '42501', null, 'nor change it');
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a5');
select is((select reference from public.vv_sites), 'VS-0001', 'view-only Port member can see it');
select throws_ok($$select public.vv_save_site('52000000-0000-0000-0000-000000000003',pg_temp.ws('wsA'),'SYNTHETIC x',null,null,null,null,null,
  51.9,1.3,null,null,null,array['51000000-0000-0000-0000-000000000001'::uuid])$$, '42501', null, 'but view-only cannot record');
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a3');
select is(public.vv_save_site('52000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC Dock 4 east',null,null,null,null,null,
  51.951,1.301,'SYNTHETIC east quay, no postal address','SYNTHETIC ask at gate 2',null,array['51000000-0000-0000-0000-000000000001'::uuid]),
  'VS-0001', 'field officer corrects the location');
select ok((select detail ? 'latitude' and detail ? 'name' from public.vv_events where record_id='52000000-0000-0000-0000-000000000001' and kind='changed'
  order by id desc limit 1), 'previous values are kept in the audit trail');
select throws_ok($$update public.vv_sites set reference='VS-9999'$$, '42501', null, 'no direct edits');
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a2');
select is(public.vv_save_site('52000000-0000-0000-0000-000000000004',pg_temp.ws('wsA'),'SYNTHETIC depot',
  '1 SYNTHETIC Road',null,'Testtown','zz1 1zz',null,null,null,null,null,null,null), 'VS-0002', 'a manager can add a site with just an address and no programme');
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a4');
select is((select reference from public.vv_sites), 'VS-0002', 'a site in no programme is visible to every Vectovia user in the council');

-- ---------- Council lists and traps --------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a3');
select throws_ok($$select public.vv_save_council_trap_type('53000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC tyre trap',null,true)$$,
  '42501', null, 'field officers cannot change the council''s lists');
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a2');
select lives_ok($$select public.vv_save_council_trap_type('53000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC tyre trap',null,true)$$,
  'manager adds a council trap type');
select lives_ok($$select public.vv_save_council_taxon('54000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC species',null,true)$$,
  'and a council species');
select is((select count(*) from public.vv_taxa where scientific_name like 'SYNTHETIC%')::int, 0, 'council additions never reach the shared list');
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a3');
select lives_ok($$select public.vv_save_trap('55000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'BG-01',
  (select id from public.vv_trap_types where key='bg_sentinel'),null,null,null)$$, 'field officer registers a BG-Sentinel trap');
select lives_ok($$select public.vv_save_trap('55000000-0000-0000-0000-000000000002',pg_temp.ws('wsA'),'TT-01',null,
  '53000000-0000-0000-0000-000000000001',null,null)$$, 'and a trap of the council''s own type');
select throws_ok($$select public.vv_save_trap('55000000-0000-0000-0000-000000000003',pg_temp.ws('wsA'),'BG-01',
  (select id from public.vv_trap_types where key='bg_sentinel'),null,null,null)$$, '23505', null, 'trap identifiers are unique in the council');
select throws_ok($$select public.vv_save_trap('55000000-0000-0000-0000-000000000003',pg_temp.ws('wsA'),'BG-02',
  (select id from public.vv_trap_types where key='bg_sentinel'),null,'deployed',null)$$, '22023', null, 'deployed is set by a deployment, not by hand');
select lives_ok($$select public.vv_save_trap('55000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'BG-01',
  (select id from public.vv_trap_types where key='bg_sentinel'),null,'damaged','SYNTHETIC fan broken')$$, 'mark it damaged');
select is((select detail->'status'->>'from' from public.vv_events where record_id='55000000-0000-0000-0000-000000000001' and kind='changed'),
  'available', 'status change audited');

-- ---------- Councils are separate ------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000021b1');
select is((select count(*) from public.vv_programmes)::int + (select count(*) from public.vv_sites)::int + (select count(*) from public.vv_traps)::int
  + (select count(*) from public.vv_council_trap_types)::int + (select count(*) from public.vv_council_taxa)::int + (select count(*) from public.vv_events)::int,
  0, 'another council sees none of our programmes, sites, traps, lists or history');
select throws_ok($$select public.vv_save_site('52000000-0000-0000-0000-000000000001',pg_temp.ws('wsB'),'SYNTHETIC grab',null,null,null,null,null,
  51.9,1.3,null,null,null,null)$$, '42501', null, 'cannot take over our site by its ID');
select throws_ok($$select public.vv_save_trap('55000000-0000-0000-0000-000000000002',pg_temp.ws('wsB'),'TT-01',null,null,null,null)$$, '42501', null,
  'or our trap');
select is(public.vv_save_site('52000000-0000-0000-0000-000000000009',pg_temp.ws('wsB'),'SYNTHETIC B site',null,null,null,null,null,
  52.0,1.0,null,null,null,null), 'VS-0001', 'each council has its own site numbering');
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a1');
select is((select count(*) from public.vv_sites)::int, 2, 'and we still see only ours');

-- ---------- Switching Vectovia off hides everything (access never widened) -------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000021f1');
select public.set_workspace_product(pg_temp.ws('wsA'),'vectovia',false);
select pg_temp.as_user('00000000-0000-0000-0000-0000000021a1');
select is((select count(*) from public.vv_sites)::int, 0, 'with Vectovia switched off, even the owner sees no surveillance records');
reset role;
select throws_ok($$delete from public.vv_events$$, '42501', null, 'the audit trail is append-only, even for the server');
select throws_ok($$delete from public.vv_sites$$, '42501', null, 'sites are never deleted');

select * from finish();
rollback;
