-- Rollback for v2-007 (knowledge library). Owner-run only. Removes procedures, forms and the powers
-- register with their pages and local notes, and restores the species-and-trap-only library functions.
-- Pages and notes for the new kinds are deleted first (published pages and notes are owner records:
-- export them before running).
begin;
alter table public.vv_library_versions disable trigger vv_library_versions_no_delete;
delete from public.vv_library_versions where document_id is not null;
alter table public.vv_library_versions enable trigger vv_library_versions_no_delete;
delete from public.vv_library_notes where document_id is not null;
CREATE OR REPLACE FUNCTION public.vv_lib_save_draft(_kind text, _subject uuid, _content jsonb, _sources jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v int; vid uuid;
begin
  if not public.has_content_role(array['author']::public.content_role[]) then raise exception 'not allowed' using errcode = '42501'; end if;
  if _kind = 'species' and not exists (select 1 from public.vv_taxa where id = _subject)
     or _kind = 'trap' and not exists (select 1 from public.vv_trap_types where id = _subject)
     or _kind not in ('species', 'trap') then
    raise exception 'unknown subject' using errcode = '22023';
  end if;
  select coalesce(max(version), 0) + 1 into v from public.vv_library_versions
   where (_kind = 'species' and taxon_id = _subject) or (_kind = 'trap' and trap_type_id = _subject);
  insert into public.vv_library_versions (kind, taxon_id, trap_type_id, version, content, sources, author_id)
  values (_kind, case when _kind = 'species' then _subject end, case when _kind = 'trap' then _subject end, v, _content, coalesce(_sources, '[]'), auth.uid())
  returning id into vid;
  perform public.write_audit(null, 'vv_library.drafted', vid, jsonb_build_object('kind', _kind, 'version', v));
  return vid;
end $$;

CREATE OR REPLACE FUNCTION public.vv_lib_submit(_version uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  update public.vv_library_versions set status = 'in_review' where id = _version and status = 'draft' and author_id = auth.uid();
  if not found then raise exception 'not allowed' using errcode = '42501'; end if;
  perform public.write_audit(null, 'vv_library.submitted', _version, '{}'::jsonb);
end $$;

CREATE OR REPLACE FUNCTION public.vv_lib_publish(_version uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v public.vv_library_versions;
begin
  if not public.has_content_role(array['content_admin']::public.content_role[]) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into v from public.vv_library_versions where id = _version for update;
  if v.status is distinct from 'reviewed' or auth.uid() = v.author_id or auth.uid() = v.reviewer_id then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update public.vv_library_versions set status = 'superseded'
   where status = 'published' and ((v.kind = 'species' and taxon_id = v.taxon_id) or (v.kind = 'trap' and trap_type_id = v.trap_type_id));
  update public.vv_library_versions set status = 'published', publisher_id = auth.uid(), published_at = now() where id = _version;
  perform public.write_audit(null, 'vv_library.published', _version, '{}'::jsonb);
end $$;

CREATE OR REPLACE FUNCTION public.vv_lib_add_image(_id uuid, _version uuid, _file_name text, _caption text, _credit text, _licence text, _source_url text, _sort integer) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v public.vv_library_versions; path text;
begin
  select * into v from public.vv_library_versions where id = _version;
  if v.id is null or v.status <> 'draft' or v.author_id is distinct from auth.uid()
     or not public.has_content_role(array['author']::public.content_role[]) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if exists (select 1 from public.vv_library_images where id = _id) then
    select storage_path into path from public.vv_library_images where id = _id and version_id = _version;
    if path is not null then return path; end if;
    raise exception 'not allowed' using errcode = '42501';
  end if;
  path := v.kind || '/' || coalesce(v.taxon_id, v.trap_type_id)::text || '/' || _id::text || '/' ||
          left(regexp_replace(coalesce(_file_name, 'image'), '[^A-Za-z0-9._-]+', '_', 'g'), 100);
  insert into public.vv_library_images (id, version_id, storage_path, caption, credit, licence, source_url, sort_order, added_by)
  values (_id, _version, path, nullif(trim(_caption), ''), trim(_credit), trim(_licence), trim(_source_url), coalesce(_sort, 0), auth.uid());
  return path;
end $$;

CREATE OR REPLACE FUNCTION public.vv_save_library_note(_id uuid, _ws uuid, _kind text, _subject uuid, _note text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare old public.vv_library_notes;
begin
  if _id is null or not public.vv_has(_ws, array['field', 'manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into old from public.vv_library_notes where id = _id for update;
  if old.id is not null then
    if old.workspace_id <> _ws then raise exception 'not allowed' using errcode = '42501'; end if;
    update public.vv_library_notes set note = trim(_note), updated_at = now() where id = _id;
  else
    insert into public.vv_library_notes (id, workspace_id, kind, taxon_id, trap_type_id, note, created_by)
    values (_id, _ws, _kind, case when _kind = 'species' then _subject end, case when _kind = 'trap' then _subject end, trim(_note), auth.uid());
  end if;
end $$;

alter table public.vv_library_notes drop constraint vv_library_notes_check;
alter table public.vv_library_notes drop constraint vv_library_notes_kind_check;
alter table public.vv_library_notes drop column document_id;
alter table public.vv_library_notes add constraint vv_library_notes_kind_check check (kind in ('species', 'trap'));
alter table public.vv_library_notes add constraint vv_library_notes_check check ((kind = 'species') = (taxon_id is not null) and (kind = 'trap') = (trap_type_id is not null));
drop trigger vv_library_versions_document_kind on public.vv_library_versions;
drop function public.vv_lib_check_document();
drop index public.vv_library_one_published_document;
alter table public.vv_library_versions drop constraint vv_library_versions_document_id_version_key;
alter table public.vv_library_versions drop constraint vv_library_versions_check;
alter table public.vv_library_versions drop constraint vv_library_versions_kind_check;
alter table public.vv_library_versions drop column document_id;
alter table public.vv_library_versions add constraint vv_library_versions_kind_check check (kind in ('species', 'trap'));
alter table public.vv_library_versions add constraint vv_library_versions_check check ((kind = 'species') = (taxon_id is not null) and (kind = 'trap') = (trap_type_id is not null));
drop function public.vv_lib_save_document(uuid, text, text, text, text, integer);
alter table public.vv_library_documents disable trigger vv_library_documents_no_delete;
drop table public.vv_library_documents;
commit;
