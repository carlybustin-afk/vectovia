-- =====================================================================
-- VECTOVIA — v2-008: reviewing loaded library drafts.
-- Library drafts loaded from the drafting pack (procedures, forms, powers) have no named author, like the
-- obligation set drafts. A reviewer can review them and a content admin who is not the reviewer can
-- publish them. Drafts written in the app keep their author, who still cannot review or publish their own.
-- STATUS: APPLIED 2026-11-01 to vectovia-mvp (widvaahmcqanxezfhjqd), with owner approval.
-- =====================================================================

create or replace function public.vv_lib_review(_version uuid, _approve boolean, _note text) returns void
  language plpgsql security definer set search_path = '' as $$
declare v public.vv_library_versions;
begin
  if not public.has_content_role(array['reviewer']::public.content_role[]) then raise exception 'not allowed' using errcode = '42501'; end if;
  if char_length(trim(coalesce(_note, ''))) < 10 then raise exception 'a review note is required' using errcode = '22023'; end if;
  select * into v from public.vv_library_versions where id = _version and status = 'in_review' for update;
  if v.id is null or v.author_id is not distinct from auth.uid() then raise exception 'not allowed' using errcode = '42501'; end if;
  update public.vv_library_versions set status = case when _approve then 'reviewed' else 'rejected' end::public.kp_status,
    reviewer_id = auth.uid(), reviewed_at = now(), review_note = trim(_note) where id = _version;
  perform public.write_audit(null, case when _approve then 'vv_library.reviewed' else 'vv_library.rejected' end, _version, '{}'::jsonb);
end $$;

create or replace function public.vv_lib_publish(_version uuid) returns void
  language plpgsql security definer set search_path = '' as $$
declare v public.vv_library_versions;
begin
  if not public.has_content_role(array['content_admin']::public.content_role[]) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into v from public.vv_library_versions where id = _version for update;
  if v.status is distinct from 'reviewed' or auth.uid() is not distinct from v.author_id or auth.uid() is not distinct from v.reviewer_id then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update public.vv_library_versions set status = 'superseded'
   where status = 'published' and ((v.kind = 'species' and taxon_id = v.taxon_id) or (v.kind = 'trap' and trap_type_id = v.trap_type_id)
                                    or (v.document_id is not null and document_id = v.document_id));
  update public.vv_library_versions set status = 'published', publisher_id = auth.uid(), published_at = now() where id = _version;
  perform public.write_audit(null, 'vv_library.published', _version, '{}'::jsonb);
end $$;

revoke all on function public.vv_lib_review(uuid, boolean, text) from public, anon, authenticated;
revoke all on function public.vv_lib_publish(uuid) from public, anon, authenticated;
grant execute on function public.vv_lib_review(uuid, boolean, text) to authenticated, service_role;
grant execute on function public.vv_lib_publish(uuid) to authenticated, service_role;
