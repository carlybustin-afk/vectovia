-- =====================================================================
-- VECTOVIA — v2-007: knowledge library (design v2 build stage 7).
--   * The reviewed library grows beyond species and traps: procedures, forms (for example survey
--     checklists) and a powers and obligations register (IHR articles and annexes, UK legislation and
--     guidance, and what non-compliance can mean).
--   * Same review route as species and traps: an author drafts, a different reviewer approves, and a
--     content admin who is neither publishes. Procedures and powers need at least one source to go to review.
--   * Organisations add their own private local arrangements to any entry. They stay with that
--     organisation: never visible to another, never copied into the shared library.
-- STATUS: APPLIED 2026-11-01 to vectovia-mvp (widvaahmcqanxezfhjqd), with owner approval.
-- =====================================================================

-- ---------- Library documents (the subjects of procedure, form and power pages) -------------------
create table public.vv_library_documents (
  id         uuid primary key,
  kind       text not null check (kind in ('procedure', 'form', 'power')),
  key        text not null unique check (key ~ '^[a-z0-9_]{3,60}$'),
  title      text not null check (char_length(title) between 3 and 200),
  category   text check (char_length(category) <= 100),
  sort_order integer not null default 0,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_by uuid,
  updated_at timestamptz
);
create trigger vv_library_documents_immutable before update on public.vv_library_documents
  for each row execute function public.guard_immutable('id', 'kind', 'key', 'created_by', 'created_at');
create trigger vv_library_documents_no_delete before delete on public.vv_library_documents for each row execute function public.forbid_update();

-- An author adds an entry to the library, or renames it. Retry-safe.
create function public.vv_lib_save_document(_id uuid, _kind text, _key text, _title text, _category text, _sort integer) returns void
  language plpgsql security definer set search_path = '' as $$
declare old public.vv_library_documents;
begin
  if _id is null or not public.has_content_role(array['author', 'content_admin']::public.content_role[]) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into old from public.vv_library_documents where id = _id for update;
  if old.id is null then
    insert into public.vv_library_documents (id, kind, key, title, category, sort_order, created_by)
    values (_id, _kind, _key, trim(_title), nullif(trim(_category), ''), coalesce(_sort, 0), auth.uid());
    perform public.write_audit(null, 'vv_library.document_added', _id, jsonb_build_object('kind', _kind, 'key', _key, 'title', trim(_title)));
    return;
  end if;
  if old.kind <> _kind or old.key <> _key then raise exception 'the kind and key of an entry cannot change' using errcode = '22023'; end if;
  if (old.title, old.category, old.sort_order) is not distinct from (trim(_title), nullif(trim(_category), ''), coalesce(_sort, old.sort_order)) then return; end if;
  update public.vv_library_documents set title = trim(_title), category = nullif(trim(_category), ''), sort_order = coalesce(_sort, sort_order),
    updated_by = auth.uid(), updated_at = now() where id = _id;
  perform public.write_audit(null, 'vv_library.document_renamed', _id,
    jsonb_build_object('from', jsonb_build_object('title', old.title, 'category', old.category), 'to', jsonb_build_object('title', trim(_title), 'category', nullif(trim(_category), ''))));
end $$;

-- ---------- Versions: one table for every kind of page ---------------------------------------------
alter table public.vv_library_versions add column document_id uuid references public.vv_library_documents(id) on delete restrict;
alter table public.vv_library_versions drop constraint vv_library_versions_kind_check;
alter table public.vv_library_versions add constraint vv_library_versions_kind_check check (kind in ('species', 'trap', 'procedure', 'form', 'power'));
alter table public.vv_library_versions drop constraint vv_library_versions_check;
alter table public.vv_library_versions add constraint vv_library_versions_check check (
  (kind = 'species') = (taxon_id is not null) and (kind = 'trap') = (trap_type_id is not null)
  and (kind in ('procedure', 'form', 'power')) = (document_id is not null));
alter table public.vv_library_versions add constraint vv_library_versions_document_id_version_key unique (document_id, version);
create unique index vv_library_one_published_document on public.vv_library_versions (document_id) where status = 'published';

-- The kind of a version must match its document's kind.
create function public.vv_lib_check_document() returns trigger
  language plpgsql set search_path = '' as $$
begin
  if new.document_id is not null and not exists (select 1 from public.vv_library_documents d where d.id = new.document_id and d.kind = new.kind) then
    raise exception 'the page kind does not match the library entry' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger vv_library_versions_document_kind before insert on public.vv_library_versions
  for each row execute function public.vv_lib_check_document();

create or replace function public.vv_lib_save_draft(_kind text, _subject uuid, _content jsonb, _sources jsonb) returns uuid
  language plpgsql security definer set search_path = '' as $$
declare v int; vid uuid;
begin
  if not public.has_content_role(array['author']::public.content_role[]) then raise exception 'not allowed' using errcode = '42501'; end if;
  if _kind = 'species' and not exists (select 1 from public.vv_taxa where id = _subject)
     or _kind = 'trap' and not exists (select 1 from public.vv_trap_types where id = _subject)
     or _kind in ('procedure', 'form', 'power') and not exists (select 1 from public.vv_library_documents where id = _subject and kind = _kind)
     or _kind not in ('species', 'trap', 'procedure', 'form', 'power') then
    raise exception 'unknown subject' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(_sources, '[]')) <> 'array'
     or exists (select 1 from jsonb_array_elements(coalesce(_sources, '[]')) s
                 where coalesce(s->>'url', '') !~ '^https://' or char_length(coalesce(s->>'title', '')) not between 2 and 300) then
    raise exception 'each source needs a title and an https link' using errcode = '22023';
  end if;
  select coalesce(max(version), 0) + 1 into v from public.vv_library_versions
   where (_kind = 'species' and taxon_id = _subject) or (_kind = 'trap' and trap_type_id = _subject) or (document_id = _subject);
  insert into public.vv_library_versions (kind, taxon_id, trap_type_id, document_id, version, content, sources, author_id)
  values (_kind, case when _kind = 'species' then _subject end, case when _kind = 'trap' then _subject end,
          case when _kind in ('procedure', 'form', 'power') then _subject end, v, _content, coalesce(_sources, '[]'), auth.uid())
  returning id into vid;
  perform public.write_audit(null, 'vv_library.drafted', vid, jsonb_build_object('kind', _kind, 'version', v));
  return vid;
end $$;

-- Procedures and powers go to review only with at least one source.
create or replace function public.vv_lib_submit(_version uuid) returns void
  language plpgsql security definer set search_path = '' as $$
declare v public.vv_library_versions;
begin
  select * into v from public.vv_library_versions where id = _version for update;
  if v.id is null or v.status <> 'draft' or v.author_id is distinct from auth.uid() then raise exception 'not allowed' using errcode = '42501'; end if;
  if v.kind in ('procedure', 'power') and jsonb_array_length(v.sources) = 0 then
    raise exception 'add at least one source before sending for review' using errcode = '22023';
  end if;
  update public.vv_library_versions set status = 'in_review' where id = _version;
  perform public.write_audit(null, 'vv_library.submitted', _version, '{}'::jsonb);
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

-- Photos stay with species and trap pages.
create or replace function public.vv_lib_add_image(_id uuid, _version uuid, _file_name text, _caption text, _credit text, _licence text, _source_url text, _sort integer) returns text
  language plpgsql security definer set search_path = '' as $$
declare v public.vv_library_versions; path text;
begin
  select * into v from public.vv_library_versions where id = _version;
  if v.id is null or v.status <> 'draft' or v.author_id is distinct from auth.uid() or v.kind not in ('species', 'trap')
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

-- ---------- Local arrangements (each organisation's own notes) --------------------------------------
alter table public.vv_library_notes add column document_id uuid references public.vv_library_documents(id) on delete restrict;
alter table public.vv_library_notes drop constraint vv_library_notes_kind_check;
alter table public.vv_library_notes add constraint vv_library_notes_kind_check check (kind in ('species', 'trap', 'procedure', 'form', 'power'));
alter table public.vv_library_notes drop constraint vv_library_notes_check;
alter table public.vv_library_notes add constraint vv_library_notes_check check (
  (kind = 'species') = (taxon_id is not null) and (kind = 'trap') = (trap_type_id is not null)
  and (kind in ('procedure', 'form', 'power')) = (document_id is not null));

create or replace function public.vv_save_library_note(_id uuid, _ws uuid, _kind text, _subject uuid, _note text) returns void
  language plpgsql security definer set search_path = '' as $$
declare old public.vv_library_notes;
begin
  if _id is null or not public.vv_has(_ws, array['field', 'manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  if _kind in ('procedure', 'form', 'power') and not exists (select 1 from public.vv_library_documents where id = _subject and kind = _kind) then
    raise exception 'unknown subject' using errcode = '22023';
  end if;
  select * into old from public.vv_library_notes where id = _id for update;
  if old.id is not null then
    if old.workspace_id <> _ws then raise exception 'not allowed' using errcode = '42501'; end if;
    update public.vv_library_notes set note = trim(_note), updated_at = now() where id = _id;
  else
    insert into public.vv_library_notes (id, workspace_id, kind, taxon_id, trap_type_id, document_id, note, created_by)
    values (_id, _ws, _kind, case when _kind = 'species' then _subject end, case when _kind = 'trap' then _subject end,
            case when _kind in ('procedure', 'form', 'power') then _subject end, trim(_note), auth.uid());
  end if;
end $$;

-- ---------- Row level security and grants -------------------------------------------------------------
-- Library entries are shared reference: every signed-in person can see the list; pages stay gated by status.
alter table public.vv_library_documents enable row level security;
create policy vv_library_documents_read on public.vv_library_documents for select to authenticated using (true);
revoke all on table public.vv_library_documents from anon, authenticated;
grant select on table public.vv_library_documents to authenticated;
grant all on table public.vv_library_documents to service_role;

revoke all on function public.vv_lib_save_document(uuid, text, text, text, text, integer) from public, anon, authenticated;
revoke all on function public.vv_lib_check_document() from public, anon, authenticated;
revoke all on function public.vv_lib_save_draft(text, uuid, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.vv_lib_submit(uuid) from public, anon, authenticated;
revoke all on function public.vv_lib_publish(uuid) from public, anon, authenticated;
revoke all on function public.vv_lib_add_image(uuid, uuid, text, text, text, text, text, integer) from public, anon, authenticated;
revoke all on function public.vv_save_library_note(uuid, uuid, text, uuid, text) from public, anon, authenticated;

grant execute on function public.vv_lib_save_document(uuid, text, text, text, text, integer) to authenticated, service_role;
grant execute on function public.vv_lib_save_draft(text, uuid, jsonb, jsonb) to authenticated, service_role;
grant execute on function public.vv_lib_submit(uuid) to authenticated, service_role;
grant execute on function public.vv_lib_publish(uuid) to authenticated, service_role;
grant execute on function public.vv_lib_add_image(uuid, uuid, text, text, text, text, text, integer) to authenticated, service_role;
grant execute on function public.vv_save_library_note(uuid, uuid, text, uuid, text) to authenticated, service_role;
