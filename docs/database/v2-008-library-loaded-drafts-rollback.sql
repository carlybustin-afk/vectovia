-- Rollback for v2-008. Owner-run only. Restores the library review rule that refuses drafts with no named author
-- (loaded drafts then wait until an author resubmits them as their own) and the v2-007 publish function.
begin;
CREATE OR REPLACE FUNCTION public.vv_lib_review(_version uuid, _approve boolean, _note text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare author uuid;
begin
  if not public.has_content_role(array['reviewer']::public.content_role[]) then raise exception 'not allowed' using errcode = '42501'; end if;
  if char_length(trim(coalesce(_note, ''))) < 10 then raise exception 'a review note is required' using errcode = '22023'; end if;
  select author_id into author from public.vv_library_versions where id = _version and status = 'in_review' for update;
  if author is null or author = auth.uid() then raise exception 'not allowed' using errcode = '42501'; end if;
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
  if v.status is distinct from 'reviewed' or auth.uid() = v.author_id or auth.uid() = v.reviewer_id then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update public.vv_library_versions set status = 'superseded'
   where status = 'published' and ((v.kind = 'species' and taxon_id = v.taxon_id) or (v.kind = 'trap' and trap_type_id = v.trap_type_id)
                                    or (v.document_id is not null and document_id = v.document_id));
  update public.vv_library_versions set status = 'published', publisher_id = auth.uid(), published_at = now() where id = _version;
  perform public.write_audit(null, 'vv_library.published', _version, '{}'::jsonb);
end $$;
commit;
