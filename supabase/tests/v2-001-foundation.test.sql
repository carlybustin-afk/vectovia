-- pgTAP tests for docs/database/v2-001-foundation.sql: organisations, products,
-- access levels, teams and the platform owner. Synthetic people only; rolls back.
begin;
select no_plan();

-- P1 platform owner. Organisation A: A1 owner, A2 admin, A3 and A4 members. Organisation B: B1 owner.
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000201f1','v2p1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000201a1','v2a1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000201a2','v2a2@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000201a3','v2a3@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000201a4','v2a4@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000201b1','v2b1@test.invalid',now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000201f1');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values
 ('wsA', public.provision_organisation('SYNTHETIC V2 Organisation A','00000000-0000-0000-0000-0000000201a1')),
 ('wsB', public.provision_organisation('SYNTHETIC V2 Organisation B','00000000-0000-0000-0000-0000000201b1'));
insert into public.workspace_members (workspace_id, user_id, role)
 select v,'00000000-0000-0000-0000-0000000201a2'::uuid,'admin'::public.workspace_role from ids where k='wsA' union all
 select v,'00000000-0000-0000-0000-0000000201a3'::uuid,'member'::public.workspace_role from ids where k='wsA' union all
 select v,'00000000-0000-0000-0000-0000000201a4'::uuid,'member'::public.workspace_role from ids where k='wsA';

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.ws(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;

-- ---------- Nothing from Investigations remains ------------------------------------------
select is((select count(*) from pg_catalog.pg_tables where schemaname = 'public'
  and (tablename like 'case%' or tablename like 'enquir%' or tablename like 'legal%' or tablename like 'letter%'
       or tablename in ('entitlements', 'confidential_access', 'field_policies', 'vv_case_links')))::int, 0,
  'no case, enquiry, legal, letter or entitlement tables');
select is((select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and (p.proname like '%case%' or p.proname like '%enquir%' or p.proname like '%legal%'
                                  or p.proname like '%confidential%' or p.proname like 'ai\_%')
    and p.proname not in ('guard_immutable'))::int, 0, 'no case, enquiry, legal, confidential or AI functions');
select hasnt_column('public', 'teams', 'can_view_confidential', 'teams have no confidential-case flag');

-- ---------- Organisations get Vectovia by default ------------------------------------------
select is((select count(*) from public.workspace_products where workspace_id in (pg_temp.ws('wsA'), pg_temp.ws('wsB'))
  and product = 'vectovia' and enabled)::int, 2, 'new organisations get Vectovia');
select is((select count(*) from public.workspace_products where product <> 'vectovia')::int, 0, 'and no other product');
select is((select count(*) from public.workspace_members where workspace_id = pg_temp.ws('wsA') and role = 'owner')::int, 1,
  'provisioning makes one owner');
select is((select count(*) from public.audit_events where workspace_id = pg_temp.ws('wsA') and action = 'workspace.provisioned')::int, 1,
  'and is audited');
select pg_temp.as_user('00000000-0000-0000-0000-0000000201a1');
select throws_ok($$select public.provision_organisation('SYNTHETIC rogue','00000000-0000-0000-0000-0000000201a1')$$, '42501', null,
  'signed-in users cannot provision organisations');

-- ---------- Personal workspace ---------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000201a3');
insert into ids values ('wsP', public.ensure_personal_workspace());
select is(public.ensure_personal_workspace(), pg_temp.ws('wsP'), 'personal workspace is created once');
select is((select role::text from public.workspace_members where workspace_id = pg_temp.ws('wsP')), 'owner', 'with its user as owner');

-- ---------- Teams: owners and admins only, members of this organisation only ----------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000201a3');
select throws_ok($$select public.create_team(pg_temp.ws('wsA'),'SYNTHETIC rogue')$$, '42501', null, 'members cannot create teams');
select pg_temp.as_user('00000000-0000-0000-0000-0000000201a2');
insert into ids values ('tPort', public.create_team(pg_temp.ws('wsA'),'  SYNTHETIC Port  '));
select is((select name from public.teams where id = pg_temp.ws('tPort')), 'SYNTHETIC Port', 'an admin creates a team (name trimmed)');
select throws_ok($$select public.create_team(pg_temp.ws('wsP'),'SYNTHETIC personal')$$, '42501', null,
  'teams belong to organisations only');
select lives_ok($$select public.add_team_member(pg_temp.ws('tPort'),'00000000-0000-0000-0000-0000000201a3')$$, 'A3 joins Port');
select lives_ok($$select public.add_team_member(pg_temp.ws('tPort'),'00000000-0000-0000-0000-0000000201a3')$$, 'adding twice is harmless');
select is((select count(*) from public.team_members where team_id = pg_temp.ws('tPort'))::int, 1, 'one membership row');
select throws_ok($$select public.add_team_member(pg_temp.ws('tPort'),'00000000-0000-0000-0000-0000000201b1')$$, '23503', null,
  'people outside the organisation cannot join its teams');
select lives_ok($$select public.update_team(pg_temp.ws('tPort'),'SYNTHETIC Port team')$$, 'admin renames the team');
select lives_ok($$select public.update_team(pg_temp.ws('tPort'),'   ')$$, 'a blank name is ignored');
select is((select name from public.teams where id = pg_temp.ws('tPort')), 'SYNTHETIC Port team', 'so the name is kept');
select pg_temp.as_user('00000000-0000-0000-0000-0000000201b1');
select throws_ok($$select public.update_team(pg_temp.ws('tPort'),'SYNTHETIC taken over')$$, '42501', null, 'another organisation cannot rename it');
select throws_ok($$select public.add_team_member(pg_temp.ws('tPort'),'00000000-0000-0000-0000-0000000201b1')$$, '42501', null,
  'nor add people');
select throws_ok($$select public.remove_team_member(pg_temp.ws('tPort'),'00000000-0000-0000-0000-0000000201a3')$$, '42501', null,
  'nor remove people');
select is((select count(*) from public.teams)::int, 0, 'nor see its teams');
select is((select count(*) from public.team_members)::int, 0, 'or their members');
select throws_ok($$insert into public.teams (workspace_id, name) values (pg_temp.ws('wsA'),'SYNTHETIC direct')$$, '42501', null,
  'no direct writes to teams');
select pg_temp.as_user('00000000-0000-0000-0000-0000000201a1');
select lives_ok($$select public.remove_team_member(pg_temp.ws('tPort'),'00000000-0000-0000-0000-0000000201a3')$$, 'the owner removes A3');
select is((select count(*) from public.audit_events where workspace_id = pg_temp.ws('wsA') and action like 'team.%')::int, 5,
  'team changes are audited (created, added twice, renamed once, removed)');

-- ---------- Products: platform owner only --------------------------------------------------
select throws_ok($$select public.set_workspace_product(pg_temp.ws('wsA'),'vectovia',false)$$, '42501', null,
  'an organisation owner cannot switch products');
select throws_ok($$select * from public.platform_workspaces()$$, '42501', null, 'nor list other organisations');
select throws_ok($$insert into public.workspace_products (workspace_id, product, enabled) values (pg_temp.ws('wsA'),'vectovia',true)$$,
  '42501', null, 'no direct product writes');
select pg_temp.as_user('00000000-0000-0000-0000-0000000201f1');
select ok((select vectovia from public.platform_workspaces() where id = pg_temp.ws('wsA')), 'the platform owner sees A has Vectovia');
select throws_ok($$select public.set_workspace_product(pg_temp.ws('wsA'),'spaceship',true)$$, '22023', null, 'unknown products are refused');

-- ---------- Access levels ------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000201a1');
select is(public.product_level(pg_temp.ws('wsA'),'vectovia'), 'manage', 'owners have full access automatically');
select pg_temp.as_user('00000000-0000-0000-0000-0000000201a2');
select is(public.product_level(pg_temp.ws('wsA'),'vectovia'), 'manage', 'so do admins');
select pg_temp.as_user('00000000-0000-0000-0000-0000000201a3');
select is(public.product_level(pg_temp.ws('wsA'),'vectovia'), 'none', 'members have no access until given it');
select throws_ok($$select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000201a3','vectovia','manage')$$, '42501', null,
  'members cannot give themselves access');
select pg_temp.as_user('00000000-0000-0000-0000-0000000201a2');
select lives_ok($$select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000201a3','vectovia','field')$$,
  'an admin makes A3 a field officer');
select lives_ok($$select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000201a4','vectovia','view')$$,
  'and A4 view-only');
select throws_ok($$select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000201a1','vectovia','view')$$, '22023', null,
  'owners and admins always keep full access');
select throws_ok($$select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000201b1','vectovia','view')$$, '22023', null,
  'only members of this organisation');
select throws_ok($$select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000201a3','vectovia','superuser')$$, '22023', null,
  'unknown levels are refused');
select pg_temp.as_user('00000000-0000-0000-0000-0000000201b1');
select throws_ok($$select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000201a3','vectovia','manage')$$, '42501', null,
  'another organisation cannot change our access');
select is((select count(*) from public.product_access)::int, 0, 'nor read it');
select pg_temp.as_user('00000000-0000-0000-0000-0000000201a3');
select is(public.product_level(pg_temp.ws('wsA'),'vectovia'), 'field', 'A3 is now a field officer');
select is((select level from public.my_products() where workspace_id = pg_temp.ws('wsA') and product = 'vectovia'), 'field',
  'and sees it in their products');
select ok(public.has_product_access(pg_temp.ws('wsA'),'vectovia',array['field','manage']), 'access check works');
select pg_temp.as_user('00000000-0000-0000-0000-0000000201a4');
select ok(not public.has_product_access(pg_temp.ws('wsA'),'vectovia',array['field','manage']), 'view-only is not field access');

-- ---------- Switching a product off removes it --------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000201f1');
select lives_ok($$select public.set_workspace_product(pg_temp.ws('wsB'),'vectovia',false)$$, 'the platform owner switches Vectovia off for B');
reset role;
select is((select count(*) from public.workspace_product_events where workspace_id = pg_temp.ws('wsB'))::int, 1, 'the change is logged');
select pg_temp.as_user('00000000-0000-0000-0000-0000000201b1');
select is(public.product_level(pg_temp.ws('wsB'),'vectovia'), null, 'B''s owner then has no Vectovia');
select throws_ok($$select public.set_product_access(pg_temp.ws('wsB'),'00000000-0000-0000-0000-0000000201b1','vectovia','view')$$, '22023', null,
  'and cannot give Vectovia access');

-- ---------- Leaving the organisation removes access rows -------------------------------------
reset role;
delete from public.workspace_members where workspace_id = pg_temp.ws('wsA') and user_id = '00000000-0000-0000-0000-0000000201a3';
select is((select count(*) from public.product_access where user_id = '00000000-0000-0000-0000-0000000201a3')::int, 0,
  'leaving removes their product access');
select pg_temp.as_user('00000000-0000-0000-0000-0000000201a3');
select is(public.product_level(pg_temp.ws('wsA'),'vectovia'), null, 'and they have no level there');

-- ---------- The platform owner does not see organisation data -------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000201f1');
select is((select count(*) from public.workspace_members where workspace_id = pg_temp.ws('wsA'))::int, 0, 'the platform owner sees no members');
select is((select count(*) from public.teams)::int, 0, 'nor teams');
select is((select count(*) from public.audit_events where workspace_id = pg_temp.ws('wsA'))::int, 0, 'nor the audit trail');

select * from finish();
rollback;
