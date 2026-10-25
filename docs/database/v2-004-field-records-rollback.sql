-- Rollback for v2-004 (field records). Owner-run only. Removes inspections, delimiting surveys,
-- pathogen tests and control actions with their records. Samples taken on inspections, their results,
-- and any negative results must be dealt with first: the restored rules do not allow them.
begin;
drop function public.vv_awaiting_official_id(uuid);
drop function public.vv_withdraw_control(uuid, text);
drop function public.vv_record_control(uuid, uuid, uuid, uuid, text, date, text, text, text, text, double precision, double precision, integer, text, uuid, text);
drop table public.vv_control_actions;
drop function public.vv_save_pathogen_test(uuid, uuid, text, text, text, text, text, text, date, text, text);
drop table public.vv_pathogen_tests;
drop function public.vv_survey_summary(uuid);
drop function public.vv_link_survey_trap(uuid, uuid);
drop function public.vv_end_survey(uuid, date, text);
drop function public.vv_save_survey(uuid, uuid, uuid, uuid, double precision, double precision, integer, date, text);
drop function public.vv_record_inspection(uuid, uuid, timestamptz, uuid, text, double precision, double precision, text, text, text, text, uuid, jsonb);
drop trigger vv_samples_immutable on public.vv_samples;
create trigger vv_samples_immutable before update on public.vv_samples
  for each row execute function public.guard_immutable('id', 'workspace_id', 'visit_id', 'site_id', 'reference', 'created_by', 'recorded_at');
drop index public.vv_samples_inspection_idx;
alter table public.vv_samples drop constraint vv_samples_source_check;
alter table public.vv_samples drop constraint vv_samples_inspection_fkey;
alter table public.vv_samples drop column inspection_id;
alter table public.vv_samples alter column visit_id set not null;
drop table public.vv_inspections;
drop table public.vv_survey_deployments;
drop table public.vv_surveys;
alter table public.vv_workspace_settings drop column next_survey_no;
alter table public.vv_result_versions drop constraint vv_result_versions_negative_check;
alter table public.vv_result_versions drop constraint vv_result_versions_status_check;
alter table public.vv_result_versions add constraint vv_result_versions_status_check
  check (status in ('pending', 'provisional', 'confirmed', 'inconclusive'));
alter table public.vv_events drop constraint vv_events_record_type_check;
alter table public.vv_events add constraint vv_events_record_type_check check (record_type in ('programme', 'site', 'trap', 'council_taxon',
  'council_trap_type', 'deployment', 'visit', 'sample', 'result', 'assessment', 'action', 'incursion', 'notify_contact'));
commit;
