-- Rollback for v2-002 (sites and obligation sets). Removes everything v2-002 added, including any
-- adoptions, assessments, shared-site links and loaded obligation content. Owner-run only.
-- Site history rows written by v2-002 (vv_events kinds such as geometry_changed) are kept.
begin;
drop function public.vv_site_compliance(uuid);
drop function public.vv_assess_requirement(uuid, uuid, text, text, text, date, uuid);
drop function public.vv_remove_site_obligation(uuid, text);
drop function public.vv_adopt_obligation_set(uuid, uuid, text);
drop function public.vv_obl_publish(uuid);
drop function public.vv_obl_review(uuid, boolean, text);
drop table public.vv_requirement_assessments;
drop table public.vv_site_obligations;
drop table public.vv_obligation_requirements;
drop function public.vv_guard_requirement();
drop table public.vv_obligation_versions;
drop table public.vv_obligation_sets;
drop function public.vv_shared_site(uuid);
drop function public.vv_leave_shared_site(uuid, text);
drop function public.vv_join_shared_site(text, uuid);
drop function public.vv_create_site_share(uuid);
drop table public.vv_site_share_codes;
drop table public.vv_site_group_members;
drop table public.vv_site_groups;
drop function public.vv_remove_site_area(uuid, text);
drop function public.vv_save_site_area(uuid, uuid, text, text, jsonb);
drop function public.vv_save_site_geometry(uuid, text, jsonb, integer, text);
drop function public.vv_point_in_site_zone(uuid, double precision, double precision);
drop table public.vv_site_areas;
alter table public.vv_sites drop constraint vv_sites_poe_zone_check,
  drop column risk_reason, drop column zone_m, drop column boundary, drop column site_type;
drop function public.vv_in_zone(jsonb, double precision, double precision, double precision);
drop function public.vv_valid_polygon(jsonb);
commit;
