-- Checks the stage 6 obligation draft update (requirements worked out from the new IHR records). Rolls back.
begin;
select no_plan();
\ir ../../docs/vectovia/obligations-draft-load.sql
\ir ../../docs/vectovia/obligations-draft-update-1.sql
\ir ../../docs/vectovia/obligations-draft-update-2.sql
\ir ../../docs/vectovia/obligations-draft-update-2.sql

select is((select string_agg(r.key || '=' || r.check_kind, ',' order by r.key) from public.vv_obligation_requirements r
   join public.vv_obligation_versions v on v.id = r.version_id join public.vv_obligation_sets s on s.id = v.set_id where s.key = 'ihr_point_of_entry'
   and r.check_kind not in ('assessment')),
  'area_covered=wider_survey,competent_personnel=training,contractors=contractors,conveyances=conveyances,effectiveness=risk,equipment=equipment,'
  || 'follow_up=follow_up,identification=official_id,incoming_risks=incoming_risks,integrated_programme=plan,records=records,sanitary_facilities=sanitary_survey,'
  || 'surveillance=checks,treatment_supervision=treatment_supervision,zone_400m=zone',
  'fifteen of the 18 IHR requirements are now worked out from records');
select is((select string_agg(r.key, ',' order by r.key) from public.vv_obligation_requirements r
   join public.vv_obligation_versions v on v.id = r.version_id join public.vv_obligation_sets s on s.id = v.set_id where s.key = 'ihr_point_of_entry'
   and r.check_kind = 'assessment'), 'control_action,national_information,pathogen_testing', 'three stay as a manager''s assessment');
select is((select r.check_kind from public.vv_obligation_requirements r join public.vv_obligation_versions v on v.id = r.version_id
   join public.vv_obligation_sets s on s.id = v.set_id where s.key = 'ukhsa_invasive_aedes_england' and r.key = 'training'), 'training', 'UKHSA training uses the competence register');
select is((select string_agg(distinct status::text, ',') from public.vv_obligation_versions), 'in_review', 'both sets still wait for review');
select is((select count(*) from public.vv_obligation_requirements)::int, 27, 'no requirements added or lost');

select * from finish();
rollback;
