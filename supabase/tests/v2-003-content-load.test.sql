-- Checks the stage 3 content loads (template draft and obligation draft update). Rolls back.
begin;
select no_plan();
\ir ../../docs/vectovia/obligations-draft-load.sql
\ir ../../docs/vectovia/templates-draft-load.sql
\ir ../../docs/vectovia/templates-draft-load.sql
\ir ../../docs/vectovia/obligations-draft-update-1.sql
\ir ../../docs/vectovia/obligations-draft-update-1.sql

select is((select count(*) from public.vv_template_versions)::int, 1, 'one plan template loads, and loading twice adds nothing');
select is((select status::text from public.vv_template_versions), 'in_review', 'it waits for review');
select is((select count(*) from public.vv_template_versions, jsonb_array_elements(sections) s where (s->>'required')::boolean)::int, 7, 'with 7 required sections');
select is((select string_agg(r.key || '=' || r.check_kind, ',' order by r.key) from public.vv_obligation_requirements r
  where r.key in ('integrated_programme', 'local_plan', 'effectiveness')),
  'effectiveness=risk,integrated_programme=plan,local_plan=plan', 'plan and yearly review requirements now come from records');
select is((select string_agg(distinct status::text, ',') from public.vv_obligation_versions), 'in_review', 'both sets still wait for review');
select is((select count(*) from public.vv_obligation_requirements)::int, 27, 'no requirements added or lost');

select * from finish();
rollback;
