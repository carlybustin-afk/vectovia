-- Update to the obligation set drafts after v2-003 (owner-approved; the sets stay unpublished).
-- Requirements about the plan and the yearly risk review are now worked out from the site's plan
-- and risk assessment records instead of a manager's assessment. Only versions still waiting for
-- review are changed; anything reviewed or published is left alone. Safe to run twice.

do $update$
declare v uuid;
begin
  for v in select ov.id from public.vv_obligation_versions ov join public.vv_obligation_sets os on os.id = ov.set_id
            where os.key in ('ihr_point_of_entry', 'ukhsa_invasive_aedes_england') and ov.version = 1 and ov.status = 'in_review' loop
    update public.vv_obligation_versions set status = 'draft' where id = v;
    update public.vv_obligation_requirements set check_kind = 'plan'
     where version_id = v and key in ('integrated_programme', 'local_plan') and check_kind = 'assessment';
    update public.vv_obligation_requirements set check_kind = 'risk'
     where version_id = v and key = 'effectiveness' and check_kind = 'assessment';
    update public.vv_obligation_versions set status = 'in_review' where id = v;
  end loop;
end $update$;
