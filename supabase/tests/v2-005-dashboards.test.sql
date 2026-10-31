-- pgTAP tests for docs/database/v2-005-dashboards.sql. Synthetic people and data only; rolls back.
begin;
select no_plan();

-- Organisation A (A1 owner, A2 viewer not in any team); organisations B, C, D (owners B1, C1, D1);
-- P1 platform owner; N1 a person from the national body (no organisation).
insert into auth.users (id, email, email_confirmed_at) values
 ('00000000-0000-0000-0000-0000000205a1','v25a1@test.invalid',now()), ('00000000-0000-0000-0000-0000000205a2','v25a2@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000205b1','v25b1@test.invalid',now()), ('00000000-0000-0000-0000-0000000205c1','v25c1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000205d1','v25d1@test.invalid',now()), ('00000000-0000-0000-0000-0000000205f1','v25p1@test.invalid',now()),
 ('00000000-0000-0000-0000-0000000205e1','v25n1@test.invalid',now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000205f1');
create temp table ids (k text primary key, v uuid);
grant all on ids to authenticated;
insert into ids values
 ('wsA', public.provision_organisation('SYNTHETIC V25 Port Health','00000000-0000-0000-0000-0000000205a1')),
 ('wsB', public.provision_organisation('SYNTHETIC V25 Council B','00000000-0000-0000-0000-0000000205b1')),
 ('wsC', public.provision_organisation('SYNTHETIC V25 Council C','00000000-0000-0000-0000-0000000205c1')),
 ('wsD', public.provision_organisation('SYNTHETIC V25 Council D','00000000-0000-0000-0000-0000000205d1'));
insert into public.workspace_members (workspace_id, user_id, role)
 values ((select v from ids where k='wsA'), '00000000-0000-0000-0000-0000000205a2', 'member');

create function pg_temp.as_user(u text) returns void language sql as $$
  select set_config('role','authenticated',true),
         set_config('request.jwt.claims', json_build_object('sub',u,'role','authenticated')::text, true) $$;
create function pg_temp.ws(k text) returns uuid language sql as $$ select v from ids where ids.k = $1 $$;
create function pg_temp.today() returns date language sql as $$ select (now() at time zone 'Europe/London')::date $$;

-- Organisation A: one site with a trap deployed 20 days ago on a 14-day interval and never checked (overdue).
select pg_temp.as_user('00000000-0000-0000-0000-0000000205a1');
select public.set_product_access(pg_temp.ws('wsA'),'00000000-0000-0000-0000-0000000205a2','vectovia','view');
select public.vv_save_programme('c5100000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC A surveillance',null,null,null,null,null);
select public.vv_save_site('c5000000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYNTHETIC A Quay',null,null,null,null,null,51.121,1.331,null,null,null,
  array['c5100000-0000-0000-0000-000000000001']::uuid[]);
select public.vv_save_trap('c5500000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'SYN-5-1',(select id from public.vv_trap_types where key = 'ovitrap'),null,null,null);
select public.vv_deploy_trap('c5600000-0000-0000-0000-000000000001',pg_temp.ws('wsA'),'c5500000-0000-0000-0000-000000000001',
  'c5000000-0000-0000-0000-000000000001',51.121,1.331,null,now() - interval '20 days',null,14);

-- Organisation B: four sites; organisation C: one site (organisation D adds one later).
select pg_temp.as_user('00000000-0000-0000-0000-0000000205b1');
select public.vv_save_site(('c50000b0-0000-0000-0000-00000000000' || n)::uuid,pg_temp.ws('wsB'),'SYNTHETIC B site ' || n,null,null,null,null,null,52.0 + n / 100.0,0.5,null,null,null,null)
  from generate_series(1, 4) n;
select pg_temp.as_user('00000000-0000-0000-0000-0000000205c1');
select public.vv_save_site('c50000c0-0000-0000-0000-000000000001',pg_temp.ws('wsC'),'SYNTHETIC C site',null,null,null,null,null,53.0,-1.0,null,null,null,null);

-- ---------- Site and organisation status -------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000205a1');
select is((select active_traps || '/' || overdue_checks || '/' || plan_current || '/' || risk_current || '/' || requirements
  from public.vv_site_status('c5000000-0000-0000-0000-000000000001')), '1/1/false/false/0', 'the site status counts the overdue trap, no plan and no risk assessment');
select is((select count(*) from public.vv_org_site_status(pg_temp.ws('wsA')))::int, 1, 'the organisation view lists the organisation''s site');
select pg_temp.as_user('00000000-0000-0000-0000-0000000205a2');
select is((select count(*) from public.vv_org_site_status(pg_temp.ws('wsA')))::int, 0, 'a viewer outside the programme''s team does not see the site');
select pg_temp.as_user('00000000-0000-0000-0000-0000000205b1');
select is((select count(*) from public.vv_site_status('c5000000-0000-0000-0000-000000000001'))::int, 0, 'another organisation gets nothing for A''s site');
select is((select count(*) from public.vv_org_site_status(pg_temp.ws('wsA')))::int, 0, 'nor for A''s organisation view');
select is((select count(*) from public.vv_org_site_status(pg_temp.ws('wsB')))::int, 4, 'B sees its own four sites');
select is((select interval_days from public.vv_site_season('c5000000-0000-0000-0000-000000000001', pg_temp.today())), null,
  'B cannot read A''s season (before any national or benchmark call in the session)');

-- ---------- National viewers -------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000205e1');
select throws_ok($$select * from public.vv_national_sites()$$, '42501', null, 'nobody has the national view until named');
select pg_temp.as_user('00000000-0000-0000-0000-0000000205a1');
select throws_ok($$select public.vv_grant_national('00000000-0000-0000-0000-0000000205e1','SYNTHETIC national body')$$, '42501', null,
  'an organisation owner cannot name a national viewer');
select throws_ok($$select * from public.vv_national_viewer_list()$$, '42501', null, 'nor list them');
select pg_temp.as_user('00000000-0000-0000-0000-0000000205f1');
select throws_ok($$select public.vv_grant_national(gen_random_uuid(),'SYNTHETIC national body')$$, '22023', null, 'the person must exist');
select lives_ok($$select public.vv_grant_national('00000000-0000-0000-0000-0000000205e1','SYNTHETIC national body')$$, 'the platform owner names a national viewer');
select lives_ok($$select public.vv_grant_national('00000000-0000-0000-0000-0000000205e1','SYNTHETIC national body')$$, 'naming them again is harmless');
select is((select count(*) from public.vv_national_viewer_list())::int, 1, 'the platform owner sees the list');
reset role;
select is((select count(*) from public.audit_events where action = 'vv_national.granted')::int, 1, 'the grant is audited once');
select throws_ok($$update public.vv_national_viewers set granted_by = gen_random_uuid()$$, '42501', null, 'who granted it cannot be rewritten');
select throws_ok($$delete from public.vv_national_viewers$$, '42501', null, 'grants cannot be deleted');

select pg_temp.as_user('00000000-0000-0000-0000-0000000205e1');
select ok(public.vv_is_national(), 'the national viewer is recognised');
select is((select count(*) from public.vv_national_sites())::int, 6, 'the national view lists named sites from every organisation');
select is((select organisation || ' / ' || site_name || ' / ' || overdue_checks from public.vv_national_sites() where site_reference is not null and site_name = 'SYNTHETIC A Quay'),
  'SYNTHETIC V25 Port Health / SYNTHETIC A Quay / 1', 'with each site''s organisation and status');
select is(current_setting('vectovia.internal', true), 'off', 'the national view leaves no internal flag on');
select is((select count(*) from public.vv_sites)::int + (select count(*) from public.vv_deployments)::int + (select count(*) from public.vv_results)::int
  + (select count(*) from public.vv_events)::int + (select count(*) from public.workspace_members)::int, 0,
  'national viewers cannot read organisations'' records, history or people directly');
select is((select count(*) from public.vv_org_site_status(pg_temp.ws('wsA')))::int, 0, 'nor use an organisation''s own view');
select throws_ok($$select * from public.vv_benchmarks(pg_temp.ws('wsA'))$$, '42501', null, 'nor its benchmarks');
select throws_ok($$select public.vv_grant_national('00000000-0000-0000-0000-0000000205b1','SYNTHETIC')$$, '42501', null, 'a national viewer cannot name others');

-- Seasons count in the national view: out of season, nothing is overdue.
select pg_temp.as_user('00000000-0000-0000-0000-0000000205a1');
select public.vv_save_season('c5200000-0000-0000-0000-000000000001','c5100000-0000-0000-0000-000000000001','SYNTHETIC later season',
  to_char(date_trunc('month', pg_temp.today() + 70), 'MM-DD'), to_char(date_trunc('month', pg_temp.today() + 70) + interval '20 days', 'MM-DD'), 14);
select is((select overdue_checks from public.vv_site_status('c5000000-0000-0000-0000-000000000001')), 0, 'out of season the organisation sees nothing overdue');
select pg_temp.as_user('00000000-0000-0000-0000-0000000205e1');
select is((select overdue_checks from public.vv_national_sites() where site_name = 'SYNTHETIC A Quay'), 0, 'and so does the national view');
select pg_temp.as_user('00000000-0000-0000-0000-0000000205b1');
select is((select interval_days from public.vv_site_season('c5000000-0000-0000-0000-000000000001', pg_temp.today())), null,
  'another organisation still cannot read A''s season');

-- ---------- Anonymous benchmarking -----------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000205a1');
select is((select your_sites || '/' || your_value || '/' || coalesce(benchmark_sites::text, 'withheld') from public.vv_benchmarks(pg_temp.ws('wsA')) where measure = 'plan_current'),
  '1/0/withheld', 'five other sites from only two other organisations: the benchmark is withheld');
select is(current_setting('vectovia.internal', true), 'off', 'benchmarking leaves no internal flag on');
select pg_temp.as_user('00000000-0000-0000-0000-0000000205d1');
select public.vv_save_site('c50000d0-0000-0000-0000-000000000001',pg_temp.ws('wsD'),'SYNTHETIC D site',null,null,null,null,null,54.0,-2.0,null,null,null,null);
select pg_temp.as_user('00000000-0000-0000-0000-0000000205a1');
select is((select your_value || '/' || benchmark_sites || '/' || benchmark_value from public.vv_benchmarks(pg_temp.ws('wsA')) where measure = 'plan_current'),
  '0/6/0', 'six sites from three other organisations: the benchmark is shown');
select is((select coalesce(benchmark_sites::text, 'withheld') from public.vv_benchmarks(pg_temp.ws('wsA')) where measure = 'checks_on_time'),
  'withheld', 'a measure with too few contributing sites (no traps elsewhere) stays withheld');
select is((select count(*) from public.vv_benchmarks(pg_temp.ws('wsA')) where site_group = 'point_of_entry')::int, 0,
  'no comparison is offered for a kind of site the organisation does not have');
select pg_temp.as_user('00000000-0000-0000-0000-0000000205b1');
select throws_ok($$select * from public.vv_benchmarks(pg_temp.ws('wsA'))$$, '42501', null, 'one organisation cannot read another''s benchmarks');
select is((select count(*) from public.vv_benchmarks(pg_temp.ws('wsB')))::int, 2, 'B gets its own comparisons (plan and risk; no traps or obligations yet)');

-- ---------- Revoking ----------------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-0000000205f1');
select throws_ok($$select public.vv_revoke_national('00000000-0000-0000-0000-0000000205e1','')$$, '22023', null, 'revoking needs a reason');
select lives_ok($$select public.vv_revoke_national('00000000-0000-0000-0000-0000000205e1','SYNTHETIC left the national body')$$, 'the platform owner revokes it');
select throws_ok($$select public.vv_grant_national('00000000-0000-0000-0000-0000000205e1','SYNTHETIC national body')$$, '22023', null,
  'a revoked grant is not silently restored');
select pg_temp.as_user('00000000-0000-0000-0000-0000000205e1');
select throws_ok($$select * from public.vv_national_sites()$$, '42501', null, 'once revoked, the national view is closed');
select is((select count(*) from public.vv_national_viewers where revoked_at is not null)::int, 1, 'they can see their own grant was revoked');
reset role;
select is((select count(*) from public.audit_events where action = 'vv_national.revoked')::int, 1, 'the revoke is audited');

-- ---------- Signed-out visitors ------------------------------------------------------------------
set local role anon;
select throws_ok($$select * from public.vv_national_sites()$$, '42501', null, 'signed-out visitors cannot call the national view');
select throws_ok($$select * from public.vv_benchmarks(gen_random_uuid())$$, '42501', null, 'nor benchmarking');
select throws_ok($$select count(*) from public.vv_national_viewers$$, '42501', null, 'nor read the national viewers');
reset role;

select * from finish();
rollback;
