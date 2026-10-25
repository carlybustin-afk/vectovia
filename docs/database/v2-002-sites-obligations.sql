-- =====================================================================
-- VECTOVIA — v2-002: sites (type, boundary, zone, operational areas, shared
-- sites) and obligation sets (national, reviewed, versioned) with site
-- compliance. Design: docs/vectovia/design-v2.md §3–5, build stage 2.
-- STATUS: APPROVED BY THE OWNER AND APPLIED 2026-10-26 to vectovia-mvp (widvaahmcqanxezfhjqd).
--
-- Rules kept from v2-001: client-generated ids and idempotent writes; every
-- write through a checked function; history in vv_events; nothing deleted;
-- organisations never see each other's records. Shared sites share only the
-- site's name, type, boundary, zone and areas, through vv_shared_site().
-- Obligation content is not written here: it is loaded separately as drafts
-- (docs/vectovia/obligations-draft-load.sql) and must be reviewed and
-- published before any site can adopt it.
-- =====================================================================

-- ---------- Geometry helpers (GeoJSON, WGS84 lon/lat; no PostGIS) ----------
-- A GeoJSON Polygon: up to 10 closed rings, 4+ positions each, 2,000 positions in all.
create function public.vv_valid_polygon(_g jsonb) returns boolean
  language plpgsql immutable set search_path = '' as $$
declare ring jsonb; pt jsonb; n int; total int := 0;
begin
  if _g is null then return true; end if;
  if jsonb_typeof(_g) <> 'object' or coalesce(_g->>'type', '') <> 'Polygon' or jsonb_typeof(_g->'coordinates') is distinct from 'array'
     or jsonb_array_length(_g->'coordinates') not between 1 and 10 then
    return false;
  end if;
  for ring in select r from jsonb_array_elements(_g->'coordinates') r loop
    if jsonb_typeof(ring) <> 'array' then return false; end if;
    n := jsonb_array_length(ring);
    if n < 4 then return false; end if;
    total := total + n;
    for pt in select p from jsonb_array_elements(ring) p loop
      if jsonb_typeof(pt) <> 'array' or jsonb_array_length(pt) <> 2
         or jsonb_typeof(pt->0) <> 'number' or jsonb_typeof(pt->1) <> 'number' then
        return false;
      end if;
      if (pt->>0)::float8 not between -180 and 180 or (pt->>1)::float8 not between -90 and 90 then return false; end if;
    end loop;
    if ring->0 <> ring->(n - 1) then return false; end if;   -- ring must close
  end loop;
  return total <= 2000;
end $$;

-- True if a point is inside the polygon's outer ring or within _zone_m metres of its edge.
-- Distances use a local flat projection: accurate to well under 1% at site scale.
create function public.vv_in_zone(_g jsonb, _zone_m double precision, _lat double precision, _lon double precision) returns boolean
  language plpgsql immutable set search_path = '' as $$
declare ring jsonb; n int; inside boolean := false; best double precision := 'infinity';
  k double precision; px double precision; py double precision;
  x1 double precision; y1 double precision; x2 double precision; y2 double precision;
  dx double precision; dy double precision; t double precision;
begin
  if _g is null or _lat is null or _lon is null then return false; end if;
  ring := _g->'coordinates'->0;
  n := jsonb_array_length(ring);
  k := cos(radians(_lat));
  px := _lon * k * 111320; py := _lat * 110540;
  for i in 0 .. n - 2 loop
    x1 := (ring->i->>0)::float8; y1 := (ring->i->>1)::float8;
    x2 := (ring->(i + 1)->>0)::float8; y2 := (ring->(i + 1)->>1)::float8;
    if (y1 > _lat) <> (y2 > _lat) and _lon < (x2 - x1) * (_lat - y1) / (y2 - y1) + x1 then inside := not inside; end if;
    x1 := x1 * k * 111320; y1 := y1 * 110540; x2 := x2 * k * 111320; y2 := y2 * 110540;
    dx := x2 - x1; dy := y2 - y1;
    t := case when dx = 0 and dy = 0 then 0 else greatest(0, least(1, ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy))) end;
    best := least(best, sqrt(power(px - (x1 + t * dx), 2) + power(py - (y1 + t * dy), 2)));
  end loop;
  return inside or best <= coalesce(_zone_m, 0);
end $$;

-- ---------- Site type, boundary and zone ------------------------------------------------------
alter table public.vv_sites
  add column site_type text not null default 'other'
    constraint vv_sites_site_type_check check (site_type in ('port', 'airport', 'ground_crossing', 'service_station', 'truck_stop',
      'inland_border', 'international_rail', 'community', 'other')),
  add column boundary jsonb constraint vv_sites_boundary_check check (public.vv_valid_polygon(boundary)),
  add column zone_m integer not null default 400 constraint vv_sites_zone_m_check check (zone_m between 0 and 5000),
  add column risk_reason text constraint vv_sites_risk_reason_check check (char_length(risk_reason) <= 500);
-- Points of entry keep at least the 400 m zone around their operational areas (IHR Annex 5).
alter table public.vv_sites add constraint vv_sites_poe_zone_check
  check (site_type not in ('port', 'airport', 'ground_crossing') or zone_m >= 400);

-- Operational areas (terminals, cargo, external areas, service providers); the zone extends from these too.
create table public.vv_site_areas (
  id             uuid primary key,
  workspace_id   uuid not null references public.workspaces(id) on delete restrict,
  site_id        uuid not null,
  kind           text not null check (kind in ('terminal', 'cargo', 'external', 'service_provider', 'other')),
  name           text not null check (char_length(name) between 2 and 120),
  boundary       jsonb check (public.vv_valid_polygon(boundary)),
  created_by     uuid not null,
  created_at     timestamptz not null default now(),
  updated_by     uuid,
  updated_at     timestamptz not null default now(),
  removed_by     uuid,
  removed_at     timestamptz,
  removed_reason text check (char_length(removed_reason) <= 500),
  foreign key (site_id, workspace_id) references public.vv_sites(id, workspace_id) on delete restrict,
  check ((removed_at is null) = (removed_reason is null) and (removed_at is null) = (removed_by is null))
);
create index vv_site_areas_site_idx on public.vv_site_areas (site_id);
create trigger vv_site_areas_immutable before update on public.vv_site_areas
  for each row execute function public.guard_immutable('id', 'workspace_id', 'site_id', 'created_by', 'created_at');
create trigger vv_site_areas_no_delete before delete on public.vv_site_areas for each row execute function public.forbid_update();

-- Inside the site's zone: within zone_m of the site boundary or of any current area boundary.
-- Security invoker: the caller only gets an answer for sites they can see.
create function public.vv_point_in_site_zone(_site uuid, _lat double precision, _lon double precision) returns boolean
  language sql stable set search_path = '' as $$
  select exists (select 1 from public.vv_sites s where s.id = _site and public.vv_in_zone(s.boundary, s.zone_m, _lat, _lon))
      or exists (select 1 from public.vv_site_areas a join public.vv_sites s on s.id = a.site_id
                  where a.site_id = _site and a.removed_at is null and public.vv_in_zone(a.boundary, s.zone_m, _lat, _lon))
$$;

create function public.vv_save_site_geometry(_site uuid, _site_type text, _boundary jsonb, _zone_m integer, _risk_reason text) returns void
  language plpgsql security definer set search_path = '' as $$
declare old public.vv_sites; after public.vv_sites;
begin
  select * into old from public.vv_sites where id = _site for update;
  if old.id is null or not public.vv_has(old.workspace_id, array['manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if not public.vv_valid_polygon(_boundary) then raise exception 'the boundary is not a valid closed shape' using errcode = '22023'; end if;
  update public.vv_sites set site_type = coalesce(_site_type, site_type), boundary = _boundary, zone_m = coalesce(_zone_m, zone_m),
    risk_reason = nullif(trim(_risk_reason), ''), updated_by = auth.uid(), updated_at = now()
   where id = _site
   returning * into after;
  perform public.vv_event(old.workspace_id, 'site', _site, 'geometry_changed',
    public.vv_diff(to_jsonb(old) - 'boundary', to_jsonb(after) - 'boundary')
    || jsonb_build_object('boundary_changed', old.boundary is distinct from after.boundary,
                          'boundary_points', coalesce(jsonb_array_length(after.boundary->'coordinates'->0), 0)));
end $$;

create function public.vv_save_site_area(_id uuid, _site uuid, _kind text, _name text, _boundary jsonb) returns void
  language plpgsql security definer set search_path = '' as $$
declare s public.vv_sites; old public.vv_site_areas;
begin
  select * into s from public.vv_sites where id = _site;
  if _id is null or s.id is null or not public.vv_has(s.workspace_id, array['manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if not public.vv_valid_polygon(_boundary) then raise exception 'the boundary is not a valid closed shape' using errcode = '22023'; end if;
  select * into old from public.vv_site_areas where id = _id for update;
  if old.id is not null and (old.site_id <> _site or old.removed_at is not null) then raise exception 'not allowed' using errcode = '42501'; end if;
  if old.id is null then
    insert into public.vv_site_areas (id, workspace_id, site_id, kind, name, boundary, created_by)
    values (_id, s.workspace_id, _site, _kind, trim(_name), _boundary, auth.uid());
  else
    update public.vv_site_areas set kind = _kind, name = trim(_name), boundary = _boundary, updated_by = auth.uid(), updated_at = now()
     where id = _id;
  end if;
  perform public.vv_event(s.workspace_id, 'site', _site, case when old.id is null then 'area_added' else 'area_changed' end,
    jsonb_build_object('area_id', _id, 'kind', _kind, 'name', trim(_name), 'boundary_changed', old.boundary is distinct from _boundary));
end $$;

create function public.vv_remove_site_area(_id uuid, _reason text) returns void
  language plpgsql security definer set search_path = '' as $$
declare a public.vv_site_areas;
begin
  select * into a from public.vv_site_areas where id = _id for update;
  if a.id is null or not public.vv_has(a.workspace_id, array['manage']) or not public.vv_can_see_site(a.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if a.removed_at is not null then return; end if;
  if char_length(trim(coalesce(_reason, ''))) < 5 then raise exception 'give a reason' using errcode = '22023'; end if;
  update public.vv_site_areas set removed_by = auth.uid(), removed_at = now(), removed_reason = trim(_reason) where id = _id;
  perform public.vv_event(a.workspace_id, 'site', a.site_id, 'area_removed', jsonb_build_object('area_id', _id, 'reason', trim(_reason)));
end $$;

-- ---------- Shared sites ----------------------------------------------------------------
-- Each organisation keeps its own site record (its programmes, traps and finds stay private).
-- A group links the records of one physical site; members see each other's site core only.
create table public.vv_site_groups (
  id           uuid primary key default gen_random_uuid(),
  lead_site_id uuid not null unique references public.vv_sites(id) on delete restrict,
  created_by   uuid not null,
  created_at   timestamptz not null default now(),
  ended_at     timestamptz
);
create table public.vv_site_group_members (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.vv_site_groups(id) on delete restrict,
  site_id      uuid not null,
  workspace_id uuid not null,
  joined_by    uuid not null,
  joined_at    timestamptz not null default now(),
  left_by      uuid,
  left_at      timestamptz,
  left_reason  text check (char_length(left_reason) <= 500),
  foreign key (site_id, workspace_id) references public.vv_sites(id, workspace_id) on delete restrict,
  check ((left_at is null) = (left_by is null))
);
create unique index vv_site_group_members_one_group on public.vv_site_group_members (site_id) where left_at is null;
create unique index vv_site_group_members_one_per_org on public.vv_site_group_members (group_id, workspace_id) where left_at is null;
create table public.vv_site_share_codes (
  id           uuid primary key default gen_random_uuid(),
  group_id     uuid not null references public.vv_site_groups(id) on delete restrict,
  workspace_id uuid not null references public.workspaces(id) on delete restrict,
  token_hash   text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  created_by   uuid not null,
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  used_at      timestamptz,
  used_by      uuid,
  used_site_id uuid
);
create trigger vv_site_groups_immutable before update on public.vv_site_groups
  for each row execute function public.guard_immutable('id', 'lead_site_id', 'created_by', 'created_at');
create trigger vv_site_groups_no_delete before delete on public.vv_site_groups for each row execute function public.forbid_update();
create trigger vv_site_group_members_immutable before update on public.vv_site_group_members
  for each row execute function public.guard_immutable('id', 'group_id', 'site_id', 'workspace_id', 'joined_by', 'joined_at');
create trigger vv_site_group_members_no_delete before delete on public.vv_site_group_members for each row execute function public.forbid_update();
create trigger vv_site_share_codes_immutable before update on public.vv_site_share_codes
  for each row execute function public.guard_immutable('id', 'group_id', 'workspace_id', 'token_hash', 'created_by', 'created_at', 'expires_at');
create trigger vv_site_share_codes_no_delete before delete on public.vv_site_share_codes for each row execute function public.forbid_update();

-- A manager of the lead site creates a one-time code (valid 7 days) to give to the other organisation.
create function public.vv_create_site_share(_site uuid) returns text
  language plpgsql security definer set search_path = '' as $$
declare s public.vv_sites; g uuid; tok text;
begin
  select * into s from public.vv_sites where id = _site;
  if s.id is null or not public.vv_has(s.workspace_id, array['manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select m.group_id into g from public.vv_site_group_members m where m.site_id = _site and m.left_at is null;
  if g is null then
    insert into public.vv_site_groups (lead_site_id, created_by) values (_site, auth.uid())
      on conflict (lead_site_id) do nothing returning id into g;
    if g is null then raise exception 'this site has stopped sharing; it cannot lead a new share' using errcode = '22023'; end if;
    insert into public.vv_site_group_members (group_id, site_id, workspace_id, joined_by) values (g, _site, s.workspace_id, auth.uid());
  elsif not exists (select 1 from public.vv_site_groups where id = g and lead_site_id = _site) then
    raise exception 'only the lead organisation can invite others to this site' using errcode = '42501';
  end if;
  tok := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.vv_site_share_codes (group_id, workspace_id, token_hash, created_by, expires_at)
  values (g, s.workspace_id, encode(extensions.digest(tok, 'sha256'), 'hex'), auth.uid(), now() + interval '7 days');
  perform public.vv_event(s.workspace_id, 'site', _site, 'share_code_created', jsonb_build_object('group_id', g));
  return tok;
end $$;

-- A manager of another organisation joins with the code, linking one of their own sites.
create function public.vv_join_shared_site(_code text, _site uuid) returns void
  language plpgsql security definer set search_path = '' as $$
declare c public.vv_site_share_codes; s public.vv_sites; lead public.vv_sites; org text;
begin
  select * into s from public.vv_sites where id = _site;
  if s.id is null or not public.vv_has(s.workspace_id, array['manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if coalesce(_code, '') !~ '^[0-9a-f]{64}$' then raise exception 'that code is not valid' using errcode = '22023'; end if;
  select * into c from public.vv_site_share_codes where token_hash = encode(extensions.digest(_code, 'sha256'), 'hex') for update;
  if c.id is not null and c.used_site_id = _site then return; end if;   -- retry
  if c.id is null or c.used_at is not null or c.expires_at <= now()
     or exists (select 1 from public.vv_site_groups g where g.id = c.group_id and g.ended_at is not null) then
    raise exception 'that code is not valid' using errcode = '22023';
  end if;
  if exists (select 1 from public.vv_site_group_members where group_id = c.group_id and workspace_id = s.workspace_id and left_at is null) then
    raise exception 'your organisation already shares this site' using errcode = '22023';
  end if;
  if exists (select 1 from public.vv_site_group_members where site_id = _site and left_at is null) then
    raise exception 'that site is already shared with another site' using errcode = '22023';
  end if;
  insert into public.vv_site_group_members (group_id, site_id, workspace_id, joined_by) values (c.group_id, _site, s.workspace_id, auth.uid());
  update public.vv_site_share_codes set used_at = now(), used_by = auth.uid(), used_site_id = _site where id = c.id;
  select l.* into lead from public.vv_site_groups g join public.vv_sites l on l.id = g.lead_site_id where g.id = c.group_id;
  select name into org from public.workspaces where id = s.workspace_id;
  perform public.vv_event(s.workspace_id, 'site', _site, 'shared_site_joined', jsonb_build_object('group_id', c.group_id));
  perform public.vv_event(lead.workspace_id, 'site', lead.id, 'organisation_joined', jsonb_build_object('group_id', c.group_id, 'organisation', org));
end $$;

-- Leave a shared site. If the lead site leaves, sharing ends for everyone.
create function public.vv_leave_shared_site(_site uuid, _reason text) returns void
  language plpgsql security definer set search_path = '' as $$
declare m public.vv_site_group_members; g public.vv_site_groups; x public.vv_site_group_members;
begin
  select * into m from public.vv_site_group_members where site_id = _site and left_at is null for update;
  if m.id is null or not public.vv_has(m.workspace_id, array['manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(_reason, ''))) < 5 then raise exception 'give a reason' using errcode = '22023'; end if;
  select * into g from public.vv_site_groups where id = m.group_id for update;
  for x in select * from public.vv_site_group_members
            where group_id = m.group_id and left_at is null and (g.lead_site_id = _site or site_id = _site) loop
    update public.vv_site_group_members set left_by = auth.uid(), left_at = now(), left_reason = trim(_reason) where id = x.id;
    perform public.vv_event(x.workspace_id, 'site', x.site_id, 'shared_site_left',
      jsonb_build_object('group_id', m.group_id, 'ended', g.lead_site_id = _site, 'reason', case when x.site_id = _site then trim(_reason) end));
  end loop;
  if g.lead_site_id = _site then update public.vv_site_groups set ended_at = now() where id = g.id; end if;
end $$;

-- The shared core of a site's group: each current member's organisation, site name, type, boundary,
-- zone and areas. Nothing else (no programmes, traps, checks or finds) is shared.
create function public.vv_shared_site(_site uuid) returns table(group_id uuid, is_lead boolean, is_you boolean, organisation text,
    site_name text, site_type text, boundary jsonb, zone_m integer, areas jsonb)
  language plpgsql stable security definer set search_path = '' as $$
declare g uuid;
begin
  if not public.vv_can_see_site(_site) then raise exception 'not allowed' using errcode = '42501'; end if;
  select m.group_id into g from public.vv_site_group_members m where m.site_id = _site and m.left_at is null;
  if g is null then return; end if;
  return query
    select g, gr.lead_site_id = s.id, s.id = _site, w.name, s.name, s.site_type, s.boundary, s.zone_m,
           coalesce((select jsonb_agg(jsonb_build_object('kind', a.kind, 'name', a.name, 'boundary', a.boundary) order by a.name)
                       from public.vv_site_areas a where a.site_id = s.id and a.removed_at is null), '[]'::jsonb)
      from public.vv_site_group_members m
      join public.vv_site_groups gr on gr.id = m.group_id
      join public.vv_sites s on s.id = m.site_id
      join public.workspaces w on w.id = m.workspace_id
     where m.group_id = g and m.left_at is null
     order by gr.lead_site_id = s.id desc, w.name;
end $$;

-- ---------- Obligation sets (national, versioned, reviewed) -----------------------------------
create table public.vv_obligation_sets (
  id           uuid primary key default gen_random_uuid(),
  key          text not null unique check (key ~ '^[a-z0-9_]{3,60}$'),
  name         text not null check (char_length(name) between 3 and 200),
  framework    text not null check (framework in ('ihr', 'national_guidance', 'other')),
  jurisdiction text not null check (char_length(jurisdiction) between 2 and 60),
  applies_to   text[] not null default '{}',
  sort_order   integer not null default 0
);
create table public.vv_obligation_versions (
  id           uuid primary key default gen_random_uuid(),
  set_id       uuid not null references public.vv_obligation_sets(id) on delete restrict,
  version      integer not null check (version > 0),
  summary      text not null check (char_length(summary) between 10 and 2000),
  sources      jsonb not null default '[]' check (jsonb_typeof(sources) = 'array'),
  status       public.kp_status not null default 'draft',
  loaded_by    uuid,
  reviewer_id  uuid,
  reviewed_at  timestamptz,
  review_note  text check (char_length(review_note) <= 2000),
  publisher_id uuid,
  published_at timestamptz,
  created_at   timestamptz not null default now(),
  unique (set_id, version)
);
create unique index vv_obligation_one_published on public.vv_obligation_versions (set_id) where status = 'published';
create trigger vv_obligation_versions_guard before update on public.vv_obligation_versions
  for each row execute function public.kp_guard_version();
create trigger vv_obligation_versions_no_delete before delete on public.vv_obligation_versions
  for each row execute function public.forbid_update();

create table public.vv_obligation_requirements (
  id         uuid primary key default gen_random_uuid(),
  version_id uuid not null references public.vv_obligation_versions(id) on delete restrict,
  key        text not null check (key ~ '^[a-z0-9_]{2,60}$'),
  sort_order integer not null,
  title      text not null check (char_length(title) between 3 and 200),
  what       text not null check (char_length(what) between 10 and 2000),
  frequency  text check (char_length(frequency) <= 200),
  evidence   text check (char_length(evidence) <= 1000),
  check_kind text not null default 'assessment' check (check_kind in ('assessment', 'zone', 'checks', 'official_id', 'records')),
  mandatory  boolean not null default true,
  source_ref text check (char_length(source_ref) <= 300),
  unique (version_id, key)
);
-- Requirements change only while their version is a draft.
create function public.vv_guard_requirement() returns trigger
  language plpgsql set search_path = '' as $$
begin
  if exists (select 1 from public.vv_obligation_versions v
              where v.id in (coalesce(new.version_id, old.version_id), coalesce(old.version_id, new.version_id)) and v.status <> 'draft') then
    raise exception 'requirements can only change while the version is a draft' using errcode = '42501';
  end if;
  return coalesce(new, old);
end $$;
create trigger vv_obligation_requirements_guard before insert or update or delete on public.vv_obligation_requirements
  for each row execute function public.vv_guard_requirement();

-- Review: a reviewer (not the person who loaded it) approves or rejects; a content admin who is
-- neither publishes. Publishing supersedes the previous published version.
create function public.vv_obl_review(_version uuid, _approve boolean, _note text) returns void
  language plpgsql security definer set search_path = '' as $$
declare v public.vv_obligation_versions;
begin
  if not public.has_content_role(array['reviewer']::public.content_role[]) then raise exception 'not allowed' using errcode = '42501'; end if;
  if char_length(trim(coalesce(_note, ''))) < 10 then raise exception 'a review note is required' using errcode = '22023'; end if;
  select * into v from public.vv_obligation_versions where id = _version and status = 'in_review' for update;
  if v.id is null or v.loaded_by is not distinct from auth.uid() then raise exception 'not allowed' using errcode = '42501'; end if;
  update public.vv_obligation_versions set status = case when _approve then 'reviewed' else 'rejected' end::public.kp_status,
    reviewer_id = auth.uid(), reviewed_at = now(), review_note = trim(_note) where id = _version;
  perform public.write_audit(null, case when _approve then 'vv_obligations.reviewed' else 'vv_obligations.rejected' end, _version, '{}'::jsonb);
end $$;

create function public.vv_obl_publish(_version uuid) returns void
  language plpgsql security definer set search_path = '' as $$
declare v public.vv_obligation_versions;
begin
  if not public.has_content_role(array['content_admin']::public.content_role[]) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into v from public.vv_obligation_versions where id = _version for update;
  if v.status is distinct from 'reviewed' or auth.uid() = v.reviewer_id or auth.uid() is not distinct from v.loaded_by then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update public.vv_obligation_versions set status = 'superseded' where set_id = v.set_id and status = 'published';
  update public.vv_obligation_versions set status = 'published', publisher_id = auth.uid(), published_at = now() where id = _version;
  perform public.write_audit(null, 'vv_obligations.published', _version, '{}'::jsonb);
end $$;

-- ---------- Obligation sets adopted by a site --------------------------------------------------
create table public.vv_site_obligations (
  id             uuid primary key,
  workspace_id   uuid not null references public.workspaces(id) on delete restrict,
  site_id        uuid not null,
  set_id         uuid not null references public.vv_obligation_sets(id) on delete restrict,
  version_id     uuid not null references public.vv_obligation_versions(id) on delete restrict,
  adopted_by     uuid not null,
  adopted_at     timestamptz not null default now(),
  updated_by     uuid,
  updated_at     timestamptz,
  removed_by     uuid,
  removed_at     timestamptz,
  removed_reason text check (char_length(removed_reason) <= 500),
  unique (id, workspace_id),
  foreign key (site_id, workspace_id) references public.vv_sites(id, workspace_id) on delete restrict,
  check ((removed_at is null) = (removed_reason is null) and (removed_at is null) = (removed_by is null))
);
create unique index vv_site_obligations_one_active on public.vv_site_obligations (site_id, set_id) where removed_at is null;
create trigger vv_site_obligations_immutable before update on public.vv_site_obligations
  for each row execute function public.guard_immutable('id', 'workspace_id', 'site_id', 'set_id', 'adopted_by', 'adopted_at');
create trigger vv_site_obligations_no_delete before delete on public.vv_site_obligations for each row execute function public.forbid_update();

-- Adopt the current published version of a set; adopting again moves the site to the newest version.
create function public.vv_adopt_obligation_set(_id uuid, _site uuid, _set_key text) returns void
  language plpgsql security definer set search_path = '' as $$
declare s public.vv_sites; st public.vv_obligation_sets; v public.vv_obligation_versions; cur public.vv_site_obligations;
begin
  select * into s from public.vv_sites where id = _site;
  if _id is null or s.id is null or not public.vv_has(s.workspace_id, array['manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into st from public.vv_obligation_sets where key = _set_key;
  if st.id is null then raise exception 'unknown obligation set' using errcode = '22023'; end if;
  select * into v from public.vv_obligation_versions where set_id = st.id and status = 'published';
  if v.id is null then raise exception 'this obligation set has not been published yet' using errcode = '22023'; end if;
  select * into cur from public.vv_site_obligations where site_id = _site and set_id = st.id and removed_at is null for update;
  if cur.id is not null then
    if cur.version_id = v.id then return; end if;
    update public.vv_site_obligations set version_id = v.id, updated_by = auth.uid(), updated_at = now() where id = cur.id;
    perform public.vv_event(s.workspace_id, 'site', _site, 'obligation_updated',
      jsonb_build_object('site_obligation_id', cur.id, 'set', st.key, 'version', v.version));
    return;
  end if;
  if exists (select 1 from public.vv_site_obligations where id = _id) then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into public.vv_site_obligations (id, workspace_id, site_id, set_id, version_id, adopted_by)
  values (_id, s.workspace_id, _site, st.id, v.id, auth.uid());
  perform public.vv_event(s.workspace_id, 'site', _site, 'obligation_adopted',
    jsonb_build_object('site_obligation_id', _id, 'set', st.key, 'version', v.version));
end $$;

create function public.vv_remove_site_obligation(_id uuid, _reason text) returns void
  language plpgsql security definer set search_path = '' as $$
declare o public.vv_site_obligations;
begin
  select * into o from public.vv_site_obligations where id = _id for update;
  if o.id is null or not public.vv_has(o.workspace_id, array['manage']) or not public.vv_can_see_site(o.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if o.removed_at is not null then return; end if;
  if char_length(trim(coalesce(_reason, ''))) < 5 then raise exception 'give a reason' using errcode = '22023'; end if;
  update public.vv_site_obligations set removed_by = auth.uid(), removed_at = now(), removed_reason = trim(_reason) where id = _id;
  perform public.vv_event(o.workspace_id, 'site', o.site_id, 'obligation_removed', jsonb_build_object('site_obligation_id', _id, 'reason', trim(_reason)));
end $$;

-- A manager's dated assessment of a requirement that records cannot yet show automatically.
create table public.vv_requirement_assessments (
  id                     uuid primary key,
  workspace_id           uuid not null references public.workspaces(id) on delete restrict,
  site_id                uuid not null,
  site_obligation_id     uuid not null,
  requirement_id         uuid not null references public.vv_obligation_requirements(id) on delete restrict,
  status                 text not null check (status in ('green', 'amber', 'red', 'not_applicable')),
  note                   text not null check (char_length(note) between 5 and 2000),
  review_by              date,
  evidence_attachment_id uuid,
  assessed_by            uuid not null,
  assessed_role          text not null,
  assessed_at            timestamptz not null default clock_timestamp(),
  foreign key (site_id, workspace_id) references public.vv_sites(id, workspace_id) on delete restrict,
  foreign key (site_obligation_id, workspace_id) references public.vv_site_obligations(id, workspace_id) on delete restrict,
  foreign key (evidence_attachment_id, workspace_id) references public.vv_attachments(id, workspace_id) on delete restrict
);
create index vv_requirement_assessments_idx on public.vv_requirement_assessments (site_obligation_id, requirement_id, assessed_at desc);
create trigger vv_requirement_assessments_append_only before update or delete on public.vv_requirement_assessments
  for each row execute function public.forbid_update();

create function public.vv_assess_requirement(_id uuid, _site_obligation uuid, _requirement_key text, _status text, _note text,
    _review_by date, _attachment uuid) returns void
  language plpgsql security definer set search_path = '' as $$
declare o public.vv_site_obligations; r public.vv_obligation_requirements;
begin
  select * into o from public.vv_site_obligations where id = _site_obligation;
  if _id is null or o.id is null or o.removed_at is not null or not public.vv_has(o.workspace_id, array['manage'])
     or not public.vv_can_see_site(o.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if exists (select 1 from public.vv_requirement_assessments where id = _id) then
    if exists (select 1 from public.vv_requirement_assessments where id = _id and site_obligation_id = _site_obligation) then return; end if;
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into r from public.vv_obligation_requirements where version_id = o.version_id and key = _requirement_key;
  if r.id is null then raise exception 'unknown requirement' using errcode = '22023'; end if;
  if r.check_kind <> 'assessment' then raise exception 'this requirement is worked out from records' using errcode = '22023'; end if;
  if _attachment is not null and not exists (select 1 from public.vv_attachments a where a.id = _attachment and a.site_id = o.site_id) then
    raise exception 'the evidence must be a file on this site' using errcode = '22023';
  end if;
  if _review_by is not null and _review_by < (now() at time zone 'Europe/London')::date then
    raise exception 'the review date cannot be in the past' using errcode = '22023';
  end if;
  insert into public.vv_requirement_assessments (id, workspace_id, site_id, site_obligation_id, requirement_id, status, note, review_by,
    evidence_attachment_id, assessed_by, assessed_role)
  values (_id, o.workspace_id, o.site_id, _site_obligation, r.id, _status, trim(_note), _review_by, _attachment, auth.uid(),
    coalesce(public.product_level(o.workspace_id, 'vectovia'), 'unknown') || ' (' || coalesce(public.ws_role_of(o.workspace_id), 'unknown') || ')');
  perform public.vv_event(o.workspace_id, 'site', o.site_id, 'requirement_assessed',
    jsonb_build_object('site_obligation_id', _site_obligation, 'requirement', _requirement_key, 'status', _status));
end $$;

-- ---------- Compliance ---------------------------------------------------------------------
-- Red, amber or green for every requirement of every set a site has adopted. Four checks are
-- worked out from records; the rest come from the latest current assessment, or show not assessed.
-- Security invoker: row level security decides what the caller can see.
create function public.vv_site_compliance(_site uuid) returns table(site_obligation_id uuid, set_key text, set_name text, version integer,
    requirement_key text, sort_order integer, title text, mandatory boolean, check_kind text, status text, detail text,
    assessed_at timestamptz, review_by date)
  language plpgsql stable set search_path = '' as $$
declare s public.vv_sites; today date := (now() at time zone 'Europe/London')::date;
  n_active int; n_inside int; n_overdue int; n_due int; n_waiting int; n_late int; has_boundary boolean;
  o record; r record; st text; dt text; a_status text; a_note text; a_at timestamptz; a_review date;
begin
  select * into s from public.vv_sites x where x.id = _site;
  if s.id is null then return; end if;
  has_boundary := s.boundary is not null
    or exists (select 1 from public.vv_site_areas x where x.site_id = _site and x.removed_at is null and x.boundary is not null);
  select count(*), count(*) filter (where public.vv_point_in_site_zone(_site, d.latitude, d.longitude))
    into n_active, n_inside from public.vv_deployments d where d.site_id = _site and d.ended_at is null;
  select count(*) filter (where v.state = 'overdue'), count(*) filter (where v.state = 'due')
    into n_overdue, n_due from public.vv_visit_schedule(s.workspace_id) v where v.site_id = _site;
  select count(*), count(*) filter (where rv.recorded_at < now() - interval '7 days')
    into n_waiting, n_late
    from public.vv_results x
    join public.vv_result_versions rv on rv.result_id = x.id and rv.version = x.current_version
    join public.vv_taxa t on t.id = rv.taxon_id
   where x.site_id = _site and t.invasive and rv.status = 'provisional';

  for o in select so.id, os.key, os.name, ov.version, so.version_id
             from public.vv_site_obligations so
             join public.vv_obligation_sets os on os.id = so.set_id
             join public.vv_obligation_versions ov on ov.id = so.version_id
            where so.site_id = _site and so.removed_at is null
            order by os.sort_order, os.key loop
    for r in select q.id, q.key, q.sort_order, q.title, q.mandatory, q.check_kind
               from public.vv_obligation_requirements q where q.version_id = o.version_id order by q.sort_order loop
      a_status := null; a_note := null; a_at := null; a_review := null;
      if r.check_kind = 'zone' then
        if not has_boundary then st := 'red'; dt := 'No site or area boundary recorded.';
        elsif n_inside = 0 then st := 'amber'; dt := 'Boundary recorded; no active trap inside the ' || s.zone_m || ' m zone.';
        else st := 'green'; dt := n_inside || ' active trap' || case when n_inside = 1 then '' else 's' end || ' inside the ' || s.zone_m || ' m zone.';
        end if;
      elsif r.check_kind = 'checks' then
        if n_active = 0 then st := 'red'; dt := 'No active traps.';
        elsif n_overdue > 0 then st := 'red'; dt := n_overdue || ' check' || case when n_overdue = 1 then '' else 's' end || ' overdue.';
        elsif n_due > 0 then st := 'amber'; dt := n_due || ' check' || case when n_due = 1 then '' else 's' end || ' due in the next 2 days.';
        else st := 'green'; dt := 'All ' || n_active || ' active trap' || case when n_active = 1 then '' else 's' end || ' checked on schedule.';
        end if;
      elsif r.check_kind = 'official_id' then
        if n_late > 0 then st := 'red'; dt := n_late || ' invasive find' || case when n_late = 1 then '' else 's' end || ' waiting more than 7 days for official identification.';
        elsif n_waiting > 0 then st := 'amber'; dt := n_waiting || ' invasive find' || case when n_waiting = 1 then '' else 's' end || ' awaiting official identification.';
        else st := 'green'; dt := 'No invasive finds awaiting official identification.';
        end if;
      elsif r.check_kind = 'records' then
        st := 'green'; dt := 'Records keep their history, file fingerprints and an audit trail.';
      else
        select ra.status, ra.note, ra.assessed_at, ra.review_by into a_status, a_note, a_at, a_review
          from public.vv_requirement_assessments ra
         where ra.site_obligation_id = o.id and ra.requirement_id = r.id
         order by ra.assessed_at desc limit 1;
        if a_status is null then st := 'not_assessed'; dt := 'Not assessed yet.';
        elsif a_review is not null and a_review < today then st := 'not_assessed'; dt := 'The last assessment was due for review on ' || to_char(a_review, 'DD Mon YYYY') || '.';
        else st := a_status; dt := a_note;
        end if;
      end if;
      site_obligation_id := o.id; set_key := o.key; set_name := o.name; version := o.version;
      requirement_key := r.key; sort_order := r.sort_order; title := r.title; mandatory := r.mandatory; check_kind := r.check_kind;
      status := st; detail := dt;
      assessed_at := a_at; review_by := a_review;
      return next;
    end loop;
  end loop;
end $$;

-- ---------- Row level security ------------------------------------------------------------
alter table public.vv_site_areas enable row level security;
create policy vv_site_areas_read on public.vv_site_areas for select to authenticated using (public.vv_can_see_site(site_id));
alter table public.vv_site_groups enable row level security;
alter table public.vv_site_group_members enable row level security;
create policy vv_site_group_members_read on public.vv_site_group_members for select to authenticated using (public.vv_can_see_site(site_id));
alter table public.vv_site_share_codes enable row level security;
alter table public.vv_obligation_sets enable row level security;
create policy vv_obligation_sets_read on public.vv_obligation_sets for select to authenticated using (true);
alter table public.vv_obligation_versions enable row level security;
create policy vv_obligation_versions_read on public.vv_obligation_versions for select to authenticated
  using (status in ('published', 'superseded') or public.kp_is_editor());
alter table public.vv_obligation_requirements enable row level security;
create policy vv_obligation_requirements_read on public.vv_obligation_requirements for select to authenticated
  using (exists (select 1 from public.vv_obligation_versions v where v.id = version_id));
alter table public.vv_site_obligations enable row level security;
create policy vv_site_obligations_read on public.vv_site_obligations for select to authenticated using (public.vv_can_see_site(site_id));
alter table public.vv_requirement_assessments enable row level security;
create policy vv_requirement_assessments_read on public.vv_requirement_assessments for select to authenticated using (public.vv_can_see_site(site_id));

-- ---------- Grants (by name; Supabase grants new objects to anon and authenticated by default) ----------
revoke all on table public.vv_site_areas, public.vv_site_groups, public.vv_site_group_members, public.vv_site_share_codes,
  public.vv_obligation_sets, public.vv_obligation_versions, public.vv_obligation_requirements, public.vv_site_obligations,
  public.vv_requirement_assessments from anon, authenticated;
grant select on table public.vv_site_areas, public.vv_site_group_members, public.vv_obligation_sets, public.vv_obligation_versions,
  public.vv_obligation_requirements, public.vv_site_obligations, public.vv_requirement_assessments to authenticated;
grant all on table public.vv_site_areas, public.vv_site_groups, public.vv_site_group_members, public.vv_site_share_codes,
  public.vv_obligation_sets, public.vv_obligation_versions, public.vv_obligation_requirements, public.vv_site_obligations,
  public.vv_requirement_assessments to service_role;

revoke all on function public.vv_valid_polygon(jsonb) from public, anon, authenticated;
revoke all on function public.vv_in_zone(jsonb, double precision, double precision, double precision) from public, anon, authenticated;
revoke all on function public.vv_point_in_site_zone(uuid, double precision, double precision) from public, anon, authenticated;
revoke all on function public.vv_save_site_geometry(uuid, text, jsonb, integer, text) from public, anon, authenticated;
revoke all on function public.vv_save_site_area(uuid, uuid, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.vv_remove_site_area(uuid, text) from public, anon, authenticated;
revoke all on function public.vv_create_site_share(uuid) from public, anon, authenticated;
revoke all on function public.vv_join_shared_site(text, uuid) from public, anon, authenticated;
revoke all on function public.vv_leave_shared_site(uuid, text) from public, anon, authenticated;
revoke all on function public.vv_shared_site(uuid) from public, anon, authenticated;
revoke all on function public.vv_guard_requirement() from public, anon, authenticated;
revoke all on function public.vv_obl_review(uuid, boolean, text) from public, anon, authenticated;
revoke all on function public.vv_obl_publish(uuid) from public, anon, authenticated;
revoke all on function public.vv_adopt_obligation_set(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.vv_remove_site_obligation(uuid, text) from public, anon, authenticated;
revoke all on function public.vv_assess_requirement(uuid, uuid, text, text, text, date, uuid) from public, anon, authenticated;
revoke all on function public.vv_site_compliance(uuid) from public, anon, authenticated;

grant execute on function public.vv_valid_polygon(jsonb) to authenticated, service_role;
grant execute on function public.vv_in_zone(jsonb, double precision, double precision, double precision) to authenticated, service_role;
grant execute on function public.vv_point_in_site_zone(uuid, double precision, double precision) to authenticated, service_role;
grant execute on function public.vv_save_site_geometry(uuid, text, jsonb, integer, text) to authenticated, service_role;
grant execute on function public.vv_save_site_area(uuid, uuid, text, text, jsonb) to authenticated, service_role;
grant execute on function public.vv_remove_site_area(uuid, text) to authenticated, service_role;
grant execute on function public.vv_create_site_share(uuid) to authenticated, service_role;
grant execute on function public.vv_join_shared_site(text, uuid) to authenticated, service_role;
grant execute on function public.vv_leave_shared_site(uuid, text) to authenticated, service_role;
grant execute on function public.vv_shared_site(uuid) to authenticated, service_role;
grant execute on function public.vv_guard_requirement() to service_role;
grant execute on function public.vv_obl_review(uuid, boolean, text) to authenticated, service_role;
grant execute on function public.vv_obl_publish(uuid) to authenticated, service_role;
grant execute on function public.vv_adopt_obligation_set(uuid, uuid, text) to authenticated, service_role;
grant execute on function public.vv_remove_site_obligation(uuid, text) to authenticated, service_role;
grant execute on function public.vv_assess_requirement(uuid, uuid, text, text, text, date, uuid) to authenticated, service_role;
grant execute on function public.vv_site_compliance(uuid) to authenticated, service_role;
