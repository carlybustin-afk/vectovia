-- =====================================================================
-- VECTOVIA — v2-003: plans and risk (design v2 build stage 3).
--   * Season-aware programmes: check intervals by season; no checks due out of season.
--   * National templates (surveillance plan, site risk assessment): versioned, reviewed, published.
--   * Site surveillance plans: versioned, approved with a review date; reviews and exercises logged.
--   * Site risk assessments: at least yearly, versioned.
--   * Compliance: plan and risk requirements worked out from records.
-- STATUS: PROPOSED FOR OWNER REVIEW. NOT APPLIED. Target: vectovia-mvp (widvaahmcqanxezfhjqd).
-- Rules as before: client-generated ids, retry-safe writes, checked functions only, history in
-- vv_events, nothing deleted, organisations never see each other's records.
-- =====================================================================

-- ---------- Seasons ---------------------------------------------------------------------------
create function public.vv_valid_md(_md text) returns boolean
  language sql immutable set search_path = '' as $$
  select _md ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'
     and (substr(_md, 4, 2))::int <= extract(day from (make_date(2000, substr(_md, 1, 2)::int, 1) + interval '1 month - 1 day'))::int
$$;

-- Is a date inside a yearly season (month-day to month-day; may run over the new year)?
create function public.vv_md_in(_d date, _starts text, _ends text) returns boolean
  language sql immutable set search_path = '' as $$
  select case when _starts <= _ends then to_char(_d, 'MM-DD') between _starts and _ends
              else to_char(_d, 'MM-DD') >= _starts or to_char(_d, 'MM-DD') <= _ends end
$$;

-- The most recent date on or before _d that falls on month-day _md (29 February becomes 1 March in other years).
create function public.vv_md_on_or_before(_d date, _md text) returns date
  language sql immutable set search_path = '' as $$
  select case when x <= _d then x
              else make_date(extract(year from _d)::int - 1, substr(_md, 1, 2)::int, 1) + (substr(_md, 4, 2)::int - 1) end
    from (select make_date(extract(year from _d)::int, substr(_md, 1, 2)::int, 1) + (substr(_md, 4, 2)::int - 1) as x) y
$$;

create table public.vv_programme_seasons (
  id             uuid primary key,
  workspace_id   uuid not null references public.workspaces(id) on delete restrict,
  programme_id   uuid not null,
  name           text not null check (char_length(name) between 2 and 60),
  starts_md      text not null check (public.vv_valid_md(starts_md)),
  ends_md        text not null check (public.vv_valid_md(ends_md)),
  interval_days  integer not null check (interval_days between 1 and 60),
  created_by     uuid not null,
  created_at     timestamptz not null default now(),
  updated_by     uuid,
  updated_at     timestamptz,
  removed_by     uuid,
  removed_at     timestamptz,
  removed_reason text check (char_length(removed_reason) <= 500),
  foreign key (programme_id, workspace_id) references public.vv_programmes(id, workspace_id) on delete restrict,
  check ((removed_at is null) = (removed_reason is null) and (removed_at is null) = (removed_by is null))
);
create index vv_programme_seasons_programme_idx on public.vv_programme_seasons (programme_id);
create trigger vv_programme_seasons_immutable before update on public.vv_programme_seasons
  for each row execute function public.guard_immutable('id', 'workspace_id', 'programme_id', 'created_by', 'created_at');
create trigger vv_programme_seasons_no_delete before delete on public.vv_programme_seasons for each row execute function public.forbid_update();

create function public.vv_save_season(_id uuid, _programme uuid, _name text, _starts text, _ends text, _interval integer) returns void
  language plpgsql security definer set search_path = '' as $$
declare p public.vv_programmes; old public.vv_programme_seasons;
begin
  select * into p from public.vv_programmes where id = _programme;
  if _id is null or p.id is null or not public.vv_has(p.workspace_id, array['manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  if not public.vv_valid_md(_starts) or not public.vv_valid_md(_ends) then raise exception 'give the season dates as day and month' using errcode = '22023'; end if;
  select * into old from public.vv_programme_seasons where id = _id for update;
  if old.id is not null and (old.programme_id <> _programme or old.removed_at is not null) then raise exception 'not allowed' using errcode = '42501'; end if;
  if old.id is null then
    insert into public.vv_programme_seasons (id, workspace_id, programme_id, name, starts_md, ends_md, interval_days, created_by)
    values (_id, p.workspace_id, _programme, trim(_name), _starts, _ends, _interval, auth.uid());
  else
    update public.vv_programme_seasons set name = trim(_name), starts_md = _starts, ends_md = _ends, interval_days = _interval,
      updated_by = auth.uid(), updated_at = now() where id = _id;
  end if;
  perform public.vv_event(p.workspace_id, 'programme', _programme, case when old.id is null then 'season_added' else 'season_changed' end,
    jsonb_build_object('season_id', _id, 'name', trim(_name), 'from', _starts, 'to', _ends, 'interval_days', _interval));
end $$;

create function public.vv_remove_season(_id uuid, _reason text) returns void
  language plpgsql security definer set search_path = '' as $$
declare s public.vv_programme_seasons;
begin
  select * into s from public.vv_programme_seasons where id = _id for update;
  if s.id is null or not public.vv_has(s.workspace_id, array['manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  if s.removed_at is not null then return; end if;
  if char_length(trim(coalesce(_reason, ''))) < 5 then raise exception 'give a reason' using errcode = '22023'; end if;
  update public.vv_programme_seasons set removed_by = auth.uid(), removed_at = now(), removed_reason = trim(_reason) where id = _id;
  perform public.vv_event(s.workspace_id, 'programme', s.programme_id, 'season_removed', jsonb_build_object('season_id', _id, 'reason', trim(_reason)));
end $$;

-- The season rule for a site on a date, from the seasons of every programme the site is in.
-- interval_days: null = no seasons set (use the trap's own interval); 0 = out of season (no checks due).
-- season_start: when the current season began (checks are counted from then, not from last year).
-- Security definer so a field officer's schedule uses every programme's seasons for the site, even
-- programmes they cannot see; it returns only the interval and start date, for sites the caller can see.
create function public.vv_site_season(_site uuid, _d date, out interval_days integer, out season_start date)
  language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.vv_can_see_site(_site) then interval_days := null; season_start := null; return; end if;
  if not exists (select 1 from public.vv_programme_seasons ps join public.vv_site_programmes sp on sp.programme_id = ps.programme_id
                  where sp.site_id = _site and ps.removed_at is null) then
    interval_days := null; season_start := null; return;
  end if;
  select min(ps.interval_days), max(public.vv_md_on_or_before(_d, ps.starts_md))
    into interval_days, season_start
    from public.vv_programme_seasons ps join public.vv_site_programmes sp on sp.programme_id = ps.programme_id
   where sp.site_id = _site and ps.removed_at is null and public.vv_md_in(_d, ps.starts_md, ps.ends_md);
  interval_days := coalesce(interval_days, 0);
end $$;

-- The visit schedule, now season-aware. Same columns as before; state gains 'off_season'.
create or replace function public.vv_visit_schedule(_ws uuid) returns table(deployment_id uuid, trap_id uuid, site_id uuid, started_at timestamp with time zone,
    responsible_officer uuid, visit_interval_days integer, last_visit_at timestamp with time zone, next_due_on date, state text)
  language sql stable set search_path = '' as $$
  with today as (select (now() at time zone 'Europe/London')::date as d),
  base as (
    select d.id, d.trap_id, d.site_id, d.started_at, d.responsible_officer, d.visit_interval_days,
           (select max(v.occurred_at) from public.vv_visits v where v.deployment_id = d.id) as last_visit_at,
           s.interval_days as season_interval, s.season_start
      from public.vv_deployments d
      cross join today
      cross join lateral public.vv_site_season(d.site_id, today.d) s
     where d.workspace_id = _ws and d.ended_at is null
  ),
  due as (
    select b.*, coalesce(nullif(b.season_interval, 0), b.visit_interval_days) as interval_days,
           case when b.season_interval = 0 then null
                else greatest((coalesce(b.last_visit_at, b.started_at) at time zone 'Europe/London')::date,
                              coalesce(b.season_start - coalesce(nullif(b.season_interval, 0), b.visit_interval_days), '-infinity'::date))
                     + coalesce(nullif(b.season_interval, 0), b.visit_interval_days) end as next_due
      from base b
  )
  select x.id, x.trap_id, x.site_id, x.started_at, x.responsible_officer, x.interval_days, x.last_visit_at, x.next_due,
         case when x.season_interval = 0 then 'off_season'
              when x.next_due < (select d from today) then 'overdue'
              when x.next_due <= (select d from today) + 2 then 'due'
              else 'scheduled' end
    from due x
   order by 8 nulls last, 1
$$;

-- ---------- National templates ------------------------------------------------------------------
-- Sections: [{"key": "zone", "title": "Zone and trap locations", "guidance": "...", "required": true}, ...]
create function public.vv_valid_sections(_s jsonb, _with_text boolean) returns boolean
  language plpgsql immutable set search_path = '' as $$
declare x jsonb; keys text[] := '{}';
begin
  if jsonb_typeof(_s) is distinct from 'array' or jsonb_array_length(_s) not between 1 and 40 then return false; end if;
  for x in select e from jsonb_array_elements(_s) e loop
    if jsonb_typeof(x) <> 'object' or coalesce(x->>'key', '') !~ '^[a-z0-9_]{2,60}$' or x->>'key' = any(keys)
       or char_length(coalesce(x->>'title', '')) not between 3 and 200 then
      return false;
    end if;
    if _with_text then
      if jsonb_typeof(x->'text') is distinct from 'string' or char_length(x->>'text') > 20000 then return false; end if;
    else
      if char_length(coalesce(x->>'guidance', '')) > 2000 or jsonb_typeof(coalesce(x->'required', 'false')) <> 'boolean' then return false; end if;
    end if;
    keys := keys || (x->>'key');
  end loop;
  return true;
end $$;

create table public.vv_templates (
  id         uuid primary key default gen_random_uuid(),
  key        text not null unique check (key ~ '^[a-z0-9_]{3,60}$'),
  kind       text not null check (kind in ('surveillance_plan', 'risk_assessment')),
  name       text not null check (char_length(name) between 3 and 200),
  sort_order integer not null default 0
);
create table public.vv_template_versions (
  id           uuid primary key default gen_random_uuid(),
  template_id  uuid not null references public.vv_templates(id) on delete restrict,
  version      integer not null check (version > 0),
  summary      text not null check (char_length(summary) between 10 and 2000),
  sections     jsonb not null check (public.vv_valid_sections(sections, false)),
  sources      jsonb not null default '[]' check (jsonb_typeof(sources) = 'array'),
  status       public.kp_status not null default 'draft',
  loaded_by    uuid,
  reviewer_id  uuid,
  reviewed_at  timestamptz,
  review_note  text check (char_length(review_note) <= 2000),
  publisher_id uuid,
  published_at timestamptz,
  created_at   timestamptz not null default now(),
  unique (template_id, version)
);
create unique index vv_template_one_published on public.vv_template_versions (template_id) where status = 'published';
create trigger vv_template_versions_guard before update on public.vv_template_versions for each row execute function public.kp_guard_version();
create trigger vv_template_versions_no_delete before delete on public.vv_template_versions for each row execute function public.forbid_update();

create function public.vv_tpl_review(_version uuid, _approve boolean, _note text) returns void
  language plpgsql security definer set search_path = '' as $$
declare v public.vv_template_versions;
begin
  if not public.has_content_role(array['reviewer']::public.content_role[]) then raise exception 'not allowed' using errcode = '42501'; end if;
  if char_length(trim(coalesce(_note, ''))) < 10 then raise exception 'a review note is required' using errcode = '22023'; end if;
  select * into v from public.vv_template_versions where id = _version and status = 'in_review' for update;
  if v.id is null or v.loaded_by is not distinct from auth.uid() then raise exception 'not allowed' using errcode = '42501'; end if;
  update public.vv_template_versions set status = case when _approve then 'reviewed' else 'rejected' end::public.kp_status,
    reviewer_id = auth.uid(), reviewed_at = now(), review_note = trim(_note) where id = _version;
  perform public.write_audit(null, case when _approve then 'vv_templates.reviewed' else 'vv_templates.rejected' end, _version, '{}'::jsonb);
end $$;

create function public.vv_tpl_publish(_version uuid) returns void
  language plpgsql security definer set search_path = '' as $$
declare v public.vv_template_versions;
begin
  if not public.has_content_role(array['content_admin']::public.content_role[]) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into v from public.vv_template_versions where id = _version for update;
  if v.status is distinct from 'reviewed' or auth.uid() = v.reviewer_id or auth.uid() is not distinct from v.loaded_by then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update public.vv_template_versions set status = 'superseded' where template_id = v.template_id and status = 'published';
  update public.vv_template_versions set status = 'published', publisher_id = auth.uid(), published_at = now() where id = _version;
  perform public.write_audit(null, 'vv_templates.published', _version, '{}'::jsonb);
end $$;

-- ---------- Site surveillance plans --------------------------------------------------------------
create table public.vv_site_plans (
  id                  uuid primary key,
  workspace_id        uuid not null references public.workspaces(id) on delete restrict,
  site_id             uuid not null unique,
  template_version_id uuid references public.vv_template_versions(id) on delete restrict,
  current_version     integer not null default 1,
  created_by          uuid not null,
  created_at          timestamptz not null default now(),
  unique (id, workspace_id),
  foreign key (site_id, workspace_id) references public.vv_sites(id, workspace_id) on delete restrict
);
create trigger vv_site_plans_immutable before update on public.vv_site_plans
  for each row execute function public.guard_immutable('id', 'workspace_id', 'site_id', 'template_version_id', 'created_by', 'created_at');
create trigger vv_site_plans_no_delete before delete on public.vv_site_plans for each row execute function public.forbid_update();

create table public.vv_site_plan_versions (
  id            uuid primary key,
  plan_id       uuid not null,
  workspace_id  uuid not null,
  version       integer not null check (version > 0),
  title         text not null check (char_length(title) between 3 and 200),
  sections      jsonb not null check (public.vv_valid_sections(sections, true)),
  reason        text check (char_length(reason) <= 500),
  author_id     uuid not null,
  author_role   text not null,
  recorded_at   timestamptz not null default clock_timestamp(),
  approved_by   uuid,
  approved_role text,
  approved_at   timestamptz,
  review_by     date,
  unique (plan_id, version),
  foreign key (plan_id, workspace_id) references public.vv_site_plans(id, workspace_id) on delete restrict,
  check (version = 1 or char_length(trim(coalesce(reason, ''))) >= 5),
  check ((approved_at is null) = (approved_by is null) and (approved_at is null) = (review_by is null))
);
-- A version's content never changes; approval is recorded once.
create function public.vv_guard_plan_version() returns trigger
  language plpgsql set search_path = '' as $$
begin
  if (to_jsonb(new) - array['approved_by', 'approved_role', 'approved_at', 'review_by'])
     is distinct from (to_jsonb(old) - array['approved_by', 'approved_role', 'approved_at', 'review_by']) then
    raise exception 'plan versions cannot be changed; save a new version' using errcode = '42501';
  end if;
  if old.approved_at is not null then raise exception 'the approval is final' using errcode = '42501'; end if;
  return new;
end $$;
create trigger vv_site_plan_versions_guard before update on public.vv_site_plan_versions for each row execute function public.vv_guard_plan_version();
create trigger vv_site_plan_versions_no_delete before delete on public.vv_site_plan_versions for each row execute function public.forbid_update();

create table public.vv_plan_activity (
  id           uuid primary key,
  workspace_id uuid not null,
  plan_id      uuid not null,
  kind         text not null check (kind in ('review', 'exercise')),
  occurred_on  date not null,
  note         text not null check (char_length(note) between 5 and 2000),
  recorded_by  uuid not null,
  recorded_role text not null,
  recorded_at  timestamptz not null default clock_timestamp(),
  foreign key (plan_id, workspace_id) references public.vv_site_plans(id, workspace_id) on delete restrict
);
create trigger vv_plan_activity_append_only before update or delete on public.vv_plan_activity for each row execute function public.forbid_update();

-- Save the plan's content as a new version (the first save creates the plan). Retry-safe on _version_id.
create function public.vv_save_plan(_version_id uuid, _plan uuid, _site uuid, _template_version uuid, _title text, _sections jsonb, _reason text) returns integer
  language plpgsql security definer set search_path = '' as $$
declare s public.vv_sites; p public.vv_site_plans; t public.vv_template_versions; v int; role text;
begin
  select * into s from public.vv_sites where id = _site;
  if _version_id is null or _plan is null or s.id is null or not public.vv_has(s.workspace_id, array['manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if exists (select 1 from public.vv_site_plan_versions where id = _version_id) then
    select version into v from public.vv_site_plan_versions where id = _version_id and plan_id = _plan;
    if v is null then raise exception 'not allowed' using errcode = '42501'; end if;
    return v;
  end if;
  if not public.vv_valid_sections(_sections, true) then raise exception 'the plan sections are not valid' using errcode = '22023'; end if;
  role := coalesce(public.product_level(s.workspace_id, 'vectovia'), 'unknown') || ' (' || coalesce(public.ws_role_of(s.workspace_id), 'unknown') || ')';
  select * into p from public.vv_site_plans where site_id = _site for update;
  if p.id is null then
    if exists (select 1 from public.vv_site_plans where id = _plan) then raise exception 'not allowed' using errcode = '42501'; end if;
    if _template_version is not null then
      select tv.* into t from public.vv_template_versions tv join public.vv_templates tp on tp.id = tv.template_id
       where tv.id = _template_version and tv.status = 'published' and tp.kind = 'surveillance_plan';
      if t.id is null then raise exception 'choose a published surveillance plan template' using errcode = '22023'; end if;
    end if;
    insert into public.vv_site_plans (id, workspace_id, site_id, template_version_id, created_by) values (_plan, s.workspace_id, _site, _template_version, auth.uid());
    v := 1;
  else
    if p.id <> _plan then raise exception 'this site already has a plan' using errcode = '22023'; end if;
    v := p.current_version + 1;
    update public.vv_site_plans set current_version = v where id = p.id;
  end if;
  insert into public.vv_site_plan_versions (id, plan_id, workspace_id, version, title, sections, reason, author_id, author_role)
  values (_version_id, _plan, s.workspace_id, v, trim(_title), _sections, case when v = 1 then null else trim(_reason) end, auth.uid(), role);
  perform public.vv_event(s.workspace_id, 'site', _site, 'plan_saved', jsonb_build_object('plan_id', _plan, 'version', v));
  return v;
end $$;

-- Approve the latest version. Every required section of the plan's template must have text.
create function public.vv_approve_plan(_plan uuid, _version integer, _review_by date) returns void
  language plpgsql security definer set search_path = '' as $$
declare p public.vv_site_plans; pv public.vv_site_plan_versions; today date := (now() at time zone 'Europe/London')::date; missing text;
begin
  select * into p from public.vv_site_plans where id = _plan;
  if p.id is null or not public.vv_has(p.workspace_id, array['manage']) or not public.vv_can_see_site(p.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into pv from public.vv_site_plan_versions where plan_id = _plan and version = _version for update;
  if pv.id is null then raise exception 'unknown version' using errcode = '22023'; end if;
  if pv.approved_at is not null then return; end if;
  if _version <> p.current_version then raise exception 'only the latest version can be approved' using errcode = '22023'; end if;
  if _review_by is null or _review_by <= today or _review_by > today + interval '3 years' then
    raise exception 'set a review date within the next 3 years' using errcode = '22023';
  end if;
  if p.template_version_id is not null then
    select string_agg(ts->>'title', ', ') into missing
      from public.vv_template_versions tv, jsonb_array_elements(tv.sections) ts
     where tv.id = p.template_version_id and coalesce((ts->>'required')::boolean, false)
       and not exists (select 1 from jsonb_array_elements(pv.sections) ps where ps->>'key' = ts->>'key' and char_length(trim(ps->>'text')) > 0);
    if missing is not null then raise exception 'complete the required sections first: %', missing using errcode = '22023'; end if;
  end if;
  update public.vv_site_plan_versions set approved_by = auth.uid(), approved_at = now(), review_by = _review_by,
    approved_role = coalesce(public.product_level(p.workspace_id, 'vectovia'), 'unknown') || ' (' || coalesce(public.ws_role_of(p.workspace_id), 'unknown') || ')'
   where id = pv.id;
  perform public.vv_event(p.workspace_id, 'site', p.site_id, 'plan_approved', jsonb_build_object('plan_id', _plan, 'version', _version, 'review_by', _review_by));
end $$;

create function public.vv_record_plan_activity(_id uuid, _plan uuid, _kind text, _occurred_on date, _note text) returns void
  language plpgsql security definer set search_path = '' as $$
declare p public.vv_site_plans;
begin
  select * into p from public.vv_site_plans where id = _plan;
  if _id is null or p.id is null or not public.vv_has(p.workspace_id, array['manage']) or not public.vv_can_see_site(p.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if exists (select 1 from public.vv_plan_activity where id = _id) then
    if exists (select 1 from public.vv_plan_activity where id = _id and plan_id = _plan) then return; end if;
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if _occurred_on is null or _occurred_on > (now() at time zone 'Europe/London')::date then raise exception 'the date cannot be in the future' using errcode = '22023'; end if;
  insert into public.vv_plan_activity (id, workspace_id, plan_id, kind, occurred_on, note, recorded_by, recorded_role)
  values (_id, p.workspace_id, _plan, _kind, _occurred_on, trim(_note), auth.uid(),
    coalesce(public.product_level(p.workspace_id, 'vectovia'), 'unknown') || ' (' || coalesce(public.ws_role_of(p.workspace_id), 'unknown') || ')');
  perform public.vv_event(p.workspace_id, 'site', p.site_id, 'plan_' || _kind, jsonb_build_object('plan_id', _plan, 'occurred_on', _occurred_on));
end $$;

-- ---------- Site risk assessments (at least yearly) ----------------------------------------------
create table public.vv_site_risk (
  id              uuid primary key,
  workspace_id    uuid not null references public.workspaces(id) on delete restrict,
  site_id         uuid not null unique,
  current_version integer not null default 1,
  created_by      uuid not null,
  created_at      timestamptz not null default now(),
  unique (id, workspace_id),
  foreign key (site_id, workspace_id) references public.vv_sites(id, workspace_id) on delete restrict
);
create trigger vv_site_risk_immutable before update on public.vv_site_risk
  for each row execute function public.guard_immutable('id', 'workspace_id', 'site_id', 'created_by', 'created_at');
create trigger vv_site_risk_no_delete before delete on public.vv_site_risk for each row execute function public.forbid_update();

create table public.vv_site_risk_versions (
  id              uuid primary key,
  risk_id         uuid not null,
  workspace_id    uuid not null,
  version         integer not null check (version > 0),
  assessed_on     date not null,
  next_due        date not null,
  likelihood      integer not null check (likelihood between 1 and 5),
  consequence     integer not null check (consequence between 1 and 5),
  matrix_version  text not null,
  matrix_level    text not null check (matrix_level in ('low', 'medium', 'high', 'very_high')),
  final_level     text not null check (final_level in ('low', 'medium', 'high', 'very_high')),
  override_reason text check (char_length(override_reason) <= 1000),
  vectors         text check (char_length(vectors) <= 2000),
  pathways        text check (char_length(pathways) <= 2000),
  habitats        text check (char_length(habitats) <= 2000),
  controls        text check (char_length(controls) <= 2000),
  rationale       text not null check (char_length(rationale) between 10 and 4000),
  reason          text check (char_length(reason) <= 500),
  author_id       uuid not null,
  author_role     text not null,
  recorded_at     timestamptz not null default clock_timestamp(),
  unique (risk_id, version),
  foreign key (risk_id, workspace_id) references public.vv_site_risk(id, workspace_id) on delete restrict,
  check (next_due > assessed_on and next_due <= assessed_on + interval '1 year'),
  check (final_level = matrix_level or char_length(trim(coalesce(override_reason, ''))) >= 5),
  check (version = 1 or char_length(trim(coalesce(reason, ''))) >= 5)
);
create trigger vv_site_risk_versions_append_only before update or delete on public.vv_site_risk_versions for each row execute function public.forbid_update();

create function public.vv_save_site_risk(_version_id uuid, _risk uuid, _site uuid, _assessed_on date, _next_due date, _likelihood integer, _consequence integer,
    _final_level text, _override_reason text, _vectors text, _pathways text, _habitats text, _controls text, _rationale text, _reason text) returns integer
  language plpgsql security definer set search_path = '' as $$
declare s public.vv_sites; r public.vv_site_risk; v int; lvl text; due date;
begin
  select * into s from public.vv_sites where id = _site;
  if _version_id is null or _risk is null or s.id is null or not public.vv_has(s.workspace_id, array['manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if exists (select 1 from public.vv_site_risk_versions where id = _version_id) then
    select version into v from public.vv_site_risk_versions where id = _version_id and risk_id = _risk;
    if v is null then raise exception 'not allowed' using errcode = '42501'; end if;
    return v;
  end if;
  if _assessed_on is null or _assessed_on > (now() at time zone 'Europe/London')::date then
    raise exception 'the assessment date cannot be in the future' using errcode = '22023';
  end if;
  due := coalesce(_next_due, (_assessed_on + interval '1 year')::date);
  if due <= _assessed_on or due > _assessed_on + interval '1 year' then raise exception 'the next assessment must be due within a year' using errcode = '22023'; end if;
  lvl := public.vv_matrix_level(_likelihood, _consequence);
  select * into r from public.vv_site_risk where site_id = _site for update;
  if r.id is null then
    if exists (select 1 from public.vv_site_risk where id = _risk) then raise exception 'not allowed' using errcode = '42501'; end if;
    insert into public.vv_site_risk (id, workspace_id, site_id, created_by) values (_risk, s.workspace_id, _site, auth.uid());
    v := 1;
  else
    if r.id <> _risk then raise exception 'this site already has a risk assessment' using errcode = '22023'; end if;
    v := r.current_version + 1;
    update public.vv_site_risk set current_version = v where id = r.id;
  end if;
  insert into public.vv_site_risk_versions (id, risk_id, workspace_id, version, assessed_on, next_due, likelihood, consequence, matrix_version, matrix_level,
    final_level, override_reason, vectors, pathways, habitats, controls, rationale, reason, author_id, author_role)
  values (_version_id, _risk, s.workspace_id, v, _assessed_on, due, _likelihood, _consequence, 'default-5x5-v1', lvl, coalesce(_final_level, lvl),
    case when coalesce(_final_level, lvl) = lvl then null else trim(_override_reason) end, nullif(trim(_vectors), ''), nullif(trim(_pathways), ''),
    nullif(trim(_habitats), ''), nullif(trim(_controls), ''), trim(_rationale), case when v = 1 then null else trim(_reason) end, auth.uid(),
    coalesce(public.product_level(s.workspace_id, 'vectovia'), 'unknown') || ' (' || coalesce(public.ws_role_of(s.workspace_id), 'unknown') || ')');
  perform public.vv_event(s.workspace_id, 'site', _site, 'site_risk_assessed',
    jsonb_build_object('risk_id', _risk, 'version', v, 'level', coalesce(_final_level, lvl), 'next_due', due));
  return v;
end $$;

-- ---------- Compliance: plan and risk worked out from records ------------------------------------------
alter table public.vv_obligation_requirements drop constraint vv_obligation_requirements_check_kind_check;
alter table public.vv_obligation_requirements add constraint vv_obligation_requirements_check_kind_check
  check (check_kind in ('assessment', 'zone', 'checks', 'official_id', 'records', 'plan', 'risk'));

create or replace function public.vv_site_compliance(_site uuid) returns table(site_obligation_id uuid, set_key text, set_name text, version integer,
    requirement_key text, sort_order integer, title text, mandatory boolean, check_kind text, status text, detail text,
    assessed_at timestamptz, review_by date)
  language plpgsql stable set search_path = '' as $$
declare s public.vv_sites; today date := (now() at time zone 'Europe/London')::date;
  n_active int; n_inside int; n_overdue int; n_due int; n_off int; n_waiting int; n_late int; has_boundary boolean;
  pl_any boolean; pl_version int; pl_approved_at timestamptz; pl_review date; pl_pending boolean;
  rk_on date; rk_due date; rk_level text;
  o record; r record; st text; dt text; a_status text; a_note text; a_at timestamptz; a_review date;
begin
  select * into s from public.vv_sites x where x.id = _site;
  if s.id is null then return; end if;
  has_boundary := s.boundary is not null
    or exists (select 1 from public.vv_site_areas x where x.site_id = _site and x.removed_at is null and x.boundary is not null);
  select count(*), count(*) filter (where public.vv_point_in_site_zone(_site, d.latitude, d.longitude))
    into n_active, n_inside from public.vv_deployments d where d.site_id = _site and d.ended_at is null;
  select count(*) filter (where v.state = 'overdue'), count(*) filter (where v.state = 'due'), count(*) filter (where v.state = 'off_season')
    into n_overdue, n_due, n_off from public.vv_visit_schedule(s.workspace_id) v where v.site_id = _site;
  select count(*), count(*) filter (where rv.recorded_at < now() - interval '7 days')
    into n_waiting, n_late
    from public.vv_results x
    join public.vv_result_versions rv on rv.result_id = x.id and rv.version = x.current_version
    join public.vv_taxa t on t.id = rv.taxon_id
   where x.site_id = _site and t.invasive and rv.status = 'provisional';
  pl_any := exists (select 1 from public.vv_site_plans p where p.site_id = _site);
  select pv.version, pv.approved_at, pv.review_by into pl_version, pl_approved_at, pl_review
    from public.vv_site_plan_versions pv join public.vv_site_plans p on p.id = pv.plan_id
   where p.site_id = _site and pv.approved_at is not null order by pv.version desc limit 1;
  pl_pending := exists (select 1 from public.vv_site_plan_versions pv join public.vv_site_plans p on p.id = pv.plan_id
                         where p.site_id = _site and pv.approved_at is null and pv.version > coalesce(pl_version, 0));
  select rv.assessed_on, rv.next_due, rv.final_level into rk_on, rk_due, rk_level
    from public.vv_site_risk_versions rv join public.vv_site_risk k on k.id = rv.risk_id
   where k.site_id = _site order by rv.version desc limit 1;

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
        elsif n_off = n_active then st := 'green'; dt := 'Out of season: no checks are due now.';
        else st := 'green'; dt := 'All ' || (n_active - n_off) || ' trap' || case when n_active - n_off = 1 then '' else 's' end || ' in season checked on schedule.';
        end if;
      elsif r.check_kind = 'official_id' then
        if n_late > 0 then st := 'red'; dt := n_late || ' invasive find' || case when n_late = 1 then '' else 's' end || ' waiting more than 7 days for official identification.';
        elsif n_waiting > 0 then st := 'amber'; dt := n_waiting || ' invasive find' || case when n_waiting = 1 then '' else 's' end || ' awaiting official identification.';
        else st := 'green'; dt := 'No invasive finds awaiting official identification.';
        end if;
      elsif r.check_kind = 'records' then
        st := 'green'; dt := 'Records keep their history, file fingerprints and an audit trail.';
      elsif r.check_kind = 'plan' then
        if pl_approved_at is null then
          st := case when pl_any then 'amber' else 'red' end;
          dt := case when pl_any then 'A surveillance plan is drafted but not yet approved.' else 'No surveillance plan.' end;
        elsif pl_review < today then st := 'red'; dt := 'The approved plan was due for review on ' || to_char(pl_review, 'DD Mon YYYY') || '.';
        else st := 'green'; dt := 'Plan version ' || pl_version || ' approved ' || to_char(pl_approved_at at time zone 'Europe/London', 'DD Mon YYYY')
          || '; review by ' || to_char(pl_review, 'DD Mon YYYY') || '.' || case when pl_pending then ' A newer draft is waiting for approval.' else '' end;
        end if;
      elsif r.check_kind = 'risk' then
        if rk_on is null then st := 'red'; dt := 'No site risk assessment.';
        elsif rk_due < today then st := 'red'; dt := 'The site risk assessment was due on ' || to_char(rk_due, 'DD Mon YYYY') || '.';
        elsif rk_due <= today + 30 then st := 'amber'; dt := 'The site risk assessment is due on ' || to_char(rk_due, 'DD Mon YYYY') || '.';
        else st := 'green'; dt := 'Assessed ' || to_char(rk_on, 'DD Mon YYYY') || ' (' || replace(rk_level, '_', ' ') || ' risk); next due ' || to_char(rk_due, 'DD Mon YYYY') || '.';
        end if;
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

-- ---------- Row level security ------------------------------------------------------------------
alter table public.vv_programme_seasons enable row level security;
create policy vv_programme_seasons_read on public.vv_programme_seasons for select to authenticated using (public.vv_can_see_programme(programme_id));
alter table public.vv_templates enable row level security;
create policy vv_templates_read on public.vv_templates for select to authenticated using (true);
alter table public.vv_template_versions enable row level security;
create policy vv_template_versions_read on public.vv_template_versions for select to authenticated
  using (status in ('published', 'superseded') or public.kp_is_editor());
alter table public.vv_site_plans enable row level security;
create policy vv_site_plans_read on public.vv_site_plans for select to authenticated using (public.vv_can_see_site(site_id));
alter table public.vv_site_plan_versions enable row level security;
create policy vv_site_plan_versions_read on public.vv_site_plan_versions for select to authenticated
  using (exists (select 1 from public.vv_site_plans p where p.id = plan_id));
alter table public.vv_plan_activity enable row level security;
create policy vv_plan_activity_read on public.vv_plan_activity for select to authenticated
  using (exists (select 1 from public.vv_site_plans p where p.id = plan_id));
alter table public.vv_site_risk enable row level security;
create policy vv_site_risk_read on public.vv_site_risk for select to authenticated using (public.vv_can_see_site(site_id));
alter table public.vv_site_risk_versions enable row level security;
create policy vv_site_risk_versions_read on public.vv_site_risk_versions for select to authenticated
  using (exists (select 1 from public.vv_site_risk k where k.id = risk_id));

-- ---------- Grants (by name) ----------------------------------------------------------------------
revoke all on table public.vv_programme_seasons, public.vv_templates, public.vv_template_versions, public.vv_site_plans,
  public.vv_site_plan_versions, public.vv_plan_activity, public.vv_site_risk, public.vv_site_risk_versions from anon, authenticated;
grant select on table public.vv_programme_seasons, public.vv_templates, public.vv_template_versions, public.vv_site_plans,
  public.vv_site_plan_versions, public.vv_plan_activity, public.vv_site_risk, public.vv_site_risk_versions to authenticated;
grant all on table public.vv_programme_seasons, public.vv_templates, public.vv_template_versions, public.vv_site_plans,
  public.vv_site_plan_versions, public.vv_plan_activity, public.vv_site_risk, public.vv_site_risk_versions to service_role;

revoke all on function public.vv_valid_md(text) from public, anon, authenticated;
revoke all on function public.vv_md_in(date, text, text) from public, anon, authenticated;
revoke all on function public.vv_md_on_or_before(date, text) from public, anon, authenticated;
revoke all on function public.vv_save_season(uuid, uuid, text, text, text, integer) from public, anon, authenticated;
revoke all on function public.vv_remove_season(uuid, text) from public, anon, authenticated;
revoke all on function public.vv_site_season(uuid, date) from public, anon, authenticated;
revoke all on function public.vv_valid_sections(jsonb, boolean) from public, anon, authenticated;
revoke all on function public.vv_tpl_review(uuid, boolean, text) from public, anon, authenticated;
revoke all on function public.vv_tpl_publish(uuid) from public, anon, authenticated;
revoke all on function public.vv_guard_plan_version() from public, anon, authenticated;
revoke all on function public.vv_save_plan(uuid, uuid, uuid, uuid, text, jsonb, text) from public, anon, authenticated;
revoke all on function public.vv_approve_plan(uuid, integer, date) from public, anon, authenticated;
revoke all on function public.vv_record_plan_activity(uuid, uuid, text, date, text) from public, anon, authenticated;
revoke all on function public.vv_save_site_risk(uuid, uuid, uuid, date, date, integer, integer, text, text, text, text, text, text, text, text) from public, anon, authenticated;

grant execute on function public.vv_valid_md(text) to authenticated, service_role;
grant execute on function public.vv_md_in(date, text, text) to authenticated, service_role;
grant execute on function public.vv_md_on_or_before(date, text) to authenticated, service_role;
grant execute on function public.vv_save_season(uuid, uuid, text, text, text, integer) to authenticated, service_role;
grant execute on function public.vv_remove_season(uuid, text) to authenticated, service_role;
grant execute on function public.vv_site_season(uuid, date) to authenticated, service_role;
grant execute on function public.vv_valid_sections(jsonb, boolean) to authenticated, service_role;
grant execute on function public.vv_tpl_review(uuid, boolean, text) to authenticated, service_role;
grant execute on function public.vv_tpl_publish(uuid) to authenticated, service_role;
grant execute on function public.vv_guard_plan_version() to service_role;
grant execute on function public.vv_save_plan(uuid, uuid, uuid, uuid, text, jsonb, text) to authenticated, service_role;
grant execute on function public.vv_approve_plan(uuid, integer, date) to authenticated, service_role;
grant execute on function public.vv_record_plan_activity(uuid, uuid, text, date, text) to authenticated, service_role;
grant execute on function public.vv_save_site_risk(uuid, uuid, uuid, date, date, integer, integer, text, text, text, text, text, text, text, text) to authenticated, service_role;
