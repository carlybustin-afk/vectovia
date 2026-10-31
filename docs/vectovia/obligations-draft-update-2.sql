-- Update to the obligation set drafts after v2-006 (owner-approved; the sets stay unpublished).
-- Requirements now worked out from the new IHR records instead of a manager's assessment.
-- Only versions still waiting for review are changed; anything reviewed or published is left alone.
-- Safe to run twice.

do $update$
declare v uuid;
begin
  for v in select ov.id from public.vv_obligation_versions ov join public.vv_obligation_sets os on os.id = ov.set_id
            where os.key in ('ihr_point_of_entry', 'ukhsa_invasive_aedes_england') and ov.version = 1 and ov.status = 'in_review' loop
    update public.vv_obligation_versions set status = 'draft' where id = v;
    update public.vv_obligation_requirements q set check_kind = m.kind
      from (values ('competent_personnel', 'training'), ('training', 'training'), ('contractors', 'contractors'), ('equipment', 'equipment'),
                   ('sanitary_facilities', 'sanitary_survey'), ('area_covered', 'wider_survey'), ('incoming_risks', 'incoming_risks'),
                   ('conveyances', 'conveyances'), ('follow_up', 'follow_up'), ('treatment_supervision', 'treatment_supervision')) m(key, kind)
     where q.version_id = v and q.key = m.key and q.check_kind = 'assessment';
    update public.vv_obligation_versions set status = 'in_review' where id = v;
  end loop;
end $update$;
