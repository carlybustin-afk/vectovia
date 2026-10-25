-- Checks the obligation set drafts load (docs/vectovia/obligations-draft-load.sql). Rolls back.
begin;
select no_plan();
\ir ../../docs/vectovia/obligations-draft-load.sql
\ir ../../docs/vectovia/obligations-draft-load.sql

select is((select count(*) from public.vv_obligation_sets)::int, 2, 'two sets load, and loading twice adds nothing');
select is((select count(*) from public.vv_obligation_requirements r join public.vv_obligation_versions v on v.id = r.version_id
  join public.vv_obligation_sets s on s.id = v.set_id where s.key = 'ihr_point_of_entry')::int, 18, 'IHR point of entry has 18 requirements');
select is((select count(*) from public.vv_obligation_requirements r join public.vv_obligation_versions v on v.id = r.version_id
  join public.vv_obligation_sets s on s.id = v.set_id where s.key = 'ukhsa_invasive_aedes_england')::int, 9, 'the England Aedes set has 9');
select is((select string_agg(distinct status::text, ',') from public.vv_obligation_versions), 'in_review', 'both wait for review; nothing is published');
select is((select string_agg(r.key || '=' || r.check_kind, ',' order by r.sort_order) from public.vv_obligation_requirements r
  join public.vv_obligation_versions v on v.id = r.version_id join public.vv_obligation_sets s on s.id = v.set_id
  where s.key = 'ihr_point_of_entry' and r.check_kind <> 'assessment'),
  'zone_400m=zone,surveillance=checks,identification=official_id,records=records', 'four IHR requirements are worked out from records');

insert into auth.users (id, email, email_confirmed_at) values ('00000000-0000-0000-0000-0000000202f9','v22load@test.invalid',now());
select set_config('role','authenticated',true),
       set_config('request.jwt.claims', json_build_object('sub','00000000-0000-0000-0000-0000000202f9','role','authenticated')::text, true);
select is((select count(*) from public.vv_obligation_requirements)::int, 0, 'organisations cannot see the drafts');

select * from finish();
rollback;
