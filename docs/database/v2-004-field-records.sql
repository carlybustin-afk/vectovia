-- =====================================================================
-- VECTOVIA — v2-004: field records (design v2 build stage 4).
--   * Finds: a result can now be negative (target species not found).
--   * Ad hoc inspections (dipping standing water, visual checks) with samples, no trap needed.
--   * Delimiting surveys after a positive: centre, radius, linked inspections and traps, summary.
--   * Pathogen tests on samples, with every change kept in the history.
--   * Control actions (source reduction, larviciding, adulticiding); withdrawn with a reason, never deleted.
--   * Invasive finds awaiting official identification, listed for follow-up.
-- AI identification is not part of this stage (design stage 8; needs owner approval for the provider).
-- STATUS: PROPOSED FOR OWNER REVIEW. NOT APPLIED. Target: vectovia-mvp (widvaahmcqanxezfhjqd).
-- Rules as before: client-generated ids, retry-safe writes, checked functions only, history in
-- vv_events, nothing deleted, organisations never see each other's records.
-- =====================================================================

-- ---------- Record types for the history ------------------------------------------------------
alter table public.vv_events drop constraint vv_events_record_type_check;
alter table public.vv_events add constraint vv_events_record_type_check check (record_type in ('programme', 'site', 'trap', 'council_taxon',
  'council_trap_type', 'deployment', 'visit', 'sample', 'result', 'assessment', 'action', 'incursion', 'notify_contact',
  'inspection', 'survey', 'pathogen_test', 'control_action'));

-- ---------- Negative finds ----------------------------------------------------------------------
alter table public.vv_result_versions drop constraint vv_result_versions_status_check;
alter table public.vv_result_versions add constraint vv_result_versions_status_check
  check (status in ('pending', 'provisional', 'confirmed', 'inconclusive', 'negative'));
-- A negative find names no species.
alter table public.vv_result_versions add constraint vv_result_versions_negative_check
  check (status <> 'negative' or (taxon_id is null and council_taxon_id is null and quantity is null));

-- ---------- Delimiting surveys ------------------------------------------------------------------
alter table public.vv_workspace_settings add column next_survey_no integer not null default 1 constraint vv_workspace_settings_next_survey_no_check check (next_survey_no > 0);
create table public.vv_surveys (
  id            uuid primary key,
  workspace_id  uuid not null references public.workspaces(id) on delete restrict,
  site_id       uuid not null,
  incursion_id  uuid,
  result_id     uuid,
  reference     text not null,
  centre_lat    double precision not null check (centre_lat between -90 and 90),
  centre_lon    double precision not null check (centre_lon between -180 and 180),
  radius_m      integer not null default 300 check (radius_m between 10 and 5000),
  started_on    date not null,
  ended_on      date,
  outcome       text check (char_length(outcome) <= 4000),
  created_by    uuid not null,
  created_at    timestamptz not null default now(),
  updated_by    uuid,
  updated_at    timestamptz,
  unique (id, workspace_id),
  unique (workspace_id, reference),
  foreign key (site_id, workspace_id) references public.vv_sites(id, workspace_id) on delete restrict,
  foreign key (incursion_id, workspace_id) references public.vv_incursions(id, workspace_id) on delete restrict,
  foreign key (result_id, workspace_id) references public.vv_results(id, workspace_id) on delete restrict,
  check (ended_on is null or ended_on >= started_on),
  check ((ended_on is null) = (outcome is null))
);
create trigger vv_surveys_immutable before update on public.vv_surveys
  for each row execute function public.guard_immutable('id', 'workspace_id', 'site_id', 'reference', 'created_by', 'created_at');
create trigger vv_surveys_no_delete before delete on public.vv_surveys for each row execute function public.forbid_update();

create table public.vv_survey_deployments (
  survey_id     uuid not null,
  deployment_id uuid not null,
  workspace_id  uuid not null,
  added_by      uuid not null,
  added_at      timestamptz not null default now(),
  primary key (survey_id, deployment_id),
  foreign key (survey_id, workspace_id) references public.vv_surveys(id, workspace_id) on delete restrict,
  foreign key (deployment_id, workspace_id) references public.vv_deployments(id, workspace_id) on delete restrict
);
create trigger vv_survey_deployments_append_only before update or delete on public.vv_survey_deployments for each row execute function public.forbid_update();

-- ---------- Ad hoc inspections -------------------------------------------------------------------
create table public.vv_inspections (
  id           uuid primary key,
  workspace_id uuid not null references public.workspaces(id) on delete restrict,
  site_id      uuid not null,
  survey_id    uuid,
  occurred_at  timestamptz not null,
  recorded_at  timestamptz not null default now(),
  officer_id   uuid not null,
  kind         text not null check (kind in ('larval_dip', 'container_search', 'visual', 'other')),
  latitude     double precision check (latitude between -90 and 90),
  longitude    double precision check (longitude between -180 and 180),
  habitat      text check (char_length(habitat) <= 1000),
  outcome      text not null check (outcome in ('collected', 'nothing_found', 'not_completed')),
  not_completed_reason text check (char_length(not_completed_reason) <= 1000),
  observations text check (char_length(observations) <= 4000),
  created_by   uuid not null,
  unique (id, workspace_id),
  foreign key (site_id, workspace_id) references public.vv_sites(id, workspace_id) on delete restrict,
  foreign key (survey_id, workspace_id) references public.vv_surveys(id, workspace_id) on delete restrict,
  check ((latitude is null) = (longitude is null)),
  check (outcome <> 'not_completed' or char_length(trim(coalesce(not_completed_reason, ''))) >= 3)
);
create index vv_inspections_site_idx on public.vv_inspections (site_id, occurred_at desc);
create trigger vv_inspections_append_only before update or delete on public.vv_inspections for each row execute function public.forbid_update();

-- Samples now come from a trap visit or an inspection (exactly one).
alter table public.vv_samples alter column visit_id drop not null;
alter table public.vv_samples add column inspection_id uuid;
alter table public.vv_samples add constraint vv_samples_inspection_fkey foreign key (inspection_id, workspace_id)
  references public.vv_inspections(id, workspace_id) on delete restrict;
alter table public.vv_samples add constraint vv_samples_source_check check (num_nonnulls(visit_id, inspection_id) = 1);
create index vv_samples_inspection_idx on public.vv_samples (inspection_id);
drop trigger vv_samples_immutable on public.vv_samples;
create trigger vv_samples_immutable before update on public.vv_samples
  for each row execute function public.guard_immutable('id', 'workspace_id', 'visit_id', 'inspection_id', 'site_id', 'reference', 'created_by', 'recorded_at');

create function public.vv_record_inspection(_id uuid, _site uuid, _occurred_at timestamptz, _officer uuid, _kind text, _latitude double precision,
    _longitude double precision, _habitat text, _outcome text, _reason text, _observations text, _survey uuid, _samples jsonb) returns void
  language plpgsql security definer set search_path = '' as $$
declare s public.vv_sites; sv public.vv_surveys; x jsonb; ref text; st public.vv_workspace_settings; n int;
begin
  select * into s from public.vv_sites where id = _site;
  if _id is null or s.id is null or not public.vv_has(s.workspace_id, array['field', 'manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if exists (select 1 from public.vv_inspections where id = _id) then
    if exists (select 1 from public.vv_inspections where id = _id and site_id = _site) then return; end if;
    raise exception 'inspection id already used' using errcode = '23505';
  end if;
  if _occurred_at is null then raise exception 'when did the inspection happen?' using errcode = '22023'; end if;
  perform public.vv_check_time(_occurred_at, 'the inspection time');
  if _officer is not null and not exists (select 1 from public.workspace_members where workspace_id = s.workspace_id and user_id = _officer) then
    raise exception 'unknown officer' using errcode = '22023';
  end if;
  if _survey is not null then
    select * into sv from public.vv_surveys where id = _survey and site_id = _site;
    if sv.id is null then raise exception 'unknown survey' using errcode = '22023'; end if;
    if sv.ended_on is not null then raise exception 'that survey has ended' using errcode = '22023'; end if;
  end if;
  n := jsonb_array_length(coalesce(_samples, '[]'));
  if _outcome = 'collected' and n = 0 then raise exception 'add at least one sample, or record nothing found' using errcode = '22023'; end if;
  if _outcome in ('nothing_found', 'not_completed') and n > 0 then raise exception 'samples can only be added when they were collected' using errcode = '22023'; end if;
  insert into public.vv_inspections (id, workspace_id, site_id, survey_id, occurred_at, officer_id, kind, latitude, longitude, habitat, outcome,
    not_completed_reason, observations, created_by)
  values (_id, s.workspace_id, _site, _survey, _occurred_at, coalesce(_officer, auth.uid()), _kind, _latitude, _longitude, nullif(trim(_habitat), ''),
    _outcome, case when _outcome = 'not_completed' then nullif(trim(_reason), '') end, nullif(trim(_observations), ''), auth.uid());
  for x in select * from jsonb_array_elements(coalesce(_samples, '[]')) loop
    ref := nullif(trim(x->>'reference'), '');
    if ref is null then
      insert into public.vv_workspace_settings (workspace_id) values (s.workspace_id) on conflict do nothing;
      select * into st from public.vv_workspace_settings where workspace_id = s.workspace_id for update;
      ref := st.site_prefix || '-S' || lpad(st.next_sample_no::text, 5, '0');
      update public.vv_workspace_settings set next_sample_no = next_sample_no + 1 where workspace_id = s.workspace_id;
    end if;
    insert into public.vv_samples (id, workspace_id, inspection_id, site_id, reference, method, notes, created_by)
    values ((x->>'id')::uuid, s.workspace_id, _id, _site, ref, coalesce(x->>'method', 'larvae'), nullif(trim(x->>'notes'), ''), auth.uid());
    perform public.vv_event(s.workspace_id, 'sample', (x->>'id')::uuid, 'collected', jsonb_build_object('reference', ref, 'inspection_id', _id));
  end loop;
  perform public.vv_event(s.workspace_id, 'inspection', _id, 'recorded',
    jsonb_build_object('site_id', _site, 'kind', _kind, 'outcome', _outcome, 'samples', n, 'survey_id', _survey));
end $$;

-- ---------- Delimiting survey functions -------------------------------------------------------------
create function public.vv_save_survey(_id uuid, _site uuid, _incursion uuid, _result uuid, _lat double precision, _lon double precision,
    _radius integer, _started_on date, _reason text) returns text
  language plpgsql security definer set search_path = '' as $$
declare s public.vv_sites; old public.vv_surveys; st public.vv_workspace_settings; ref text; after jsonb;
begin
  select * into s from public.vv_sites where id = _site;
  if _id is null or s.id is null or not public.vv_has(s.workspace_id, array['manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if _incursion is not null and not exists (select 1 from public.vv_incursions where id = _incursion and workspace_id = s.workspace_id) then
    raise exception 'unknown incursion' using errcode = '22023';
  end if;
  if _result is not null and not exists (select 1 from public.vv_results where id = _result and workspace_id = s.workspace_id) then
    raise exception 'unknown find' using errcode = '22023';
  end if;
  if _started_on is null or _started_on > (now() at time zone 'Europe/London')::date + 30 then
    raise exception 'give a start date (at most 30 days ahead)' using errcode = '22023';
  end if;
  select * into old from public.vv_surveys where id = _id for update;
  if old.id is null then
    insert into public.vv_workspace_settings (workspace_id) values (s.workspace_id) on conflict do nothing;
    select * into st from public.vv_workspace_settings where workspace_id = s.workspace_id for update;
    ref := st.site_prefix || '-D' || lpad(st.next_survey_no::text, 4, '0');
    update public.vv_workspace_settings set next_survey_no = next_survey_no + 1 where workspace_id = s.workspace_id;
    insert into public.vv_surveys (id, workspace_id, site_id, incursion_id, result_id, reference, centre_lat, centre_lon, radius_m, started_on, created_by)
    values (_id, s.workspace_id, _site, _incursion, _result, ref, _lat, _lon, coalesce(_radius, 300), _started_on, auth.uid());
    perform public.vv_event(s.workspace_id, 'survey', _id, 'started',
      jsonb_build_object('reference', ref, 'site_id', _site, 'incursion_id', _incursion, 'result_id', _result, 'radius_m', coalesce(_radius, 300)));
    return ref;
  end if;
  if old.site_id <> _site then raise exception 'not allowed' using errcode = '42501'; end if;
  if old.ended_on is not null then raise exception 'that survey has ended' using errcode = '22023'; end if;
  if (old.centre_lat, old.centre_lon, old.radius_m, old.started_on, old.incursion_id, old.result_id)
     is not distinct from (_lat, _lon, coalesce(_radius, 300), _started_on, _incursion, _result) then
    return old.reference;
  end if;
  if char_length(trim(coalesce(_reason, ''))) < 5 then raise exception 'give a reason for the change' using errcode = '22023'; end if;
  update public.vv_surveys set incursion_id = _incursion, result_id = _result, centre_lat = _lat, centre_lon = _lon, radius_m = coalesce(_radius, 300),
    started_on = _started_on, updated_by = auth.uid(), updated_at = now() where id = _id;
  select to_jsonb(x) into after from public.vv_surveys x where x.id = _id;
  perform public.vv_event(s.workspace_id, 'survey', _id, 'changed', public.vv_diff(to_jsonb(old), after) || jsonb_build_object('reason', trim(_reason)));
  return old.reference;
end $$;

create function public.vv_end_survey(_id uuid, _ended_on date, _outcome text) returns void
  language plpgsql security definer set search_path = '' as $$
declare sv public.vv_surveys;
begin
  select * into sv from public.vv_surveys where id = _id for update;
  if sv.id is null or not public.vv_has(sv.workspace_id, array['manage']) or not public.vv_can_see_site(sv.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if sv.ended_on is not null then return; end if;
  if _ended_on is null or _ended_on < sv.started_on or _ended_on > (now() at time zone 'Europe/London')::date then
    raise exception 'the end date must be between the start and today' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(_outcome, ''))) < 10 then raise exception 'describe the outcome' using errcode = '22023'; end if;
  update public.vv_surveys set ended_on = _ended_on, outcome = trim(_outcome), updated_by = auth.uid(), updated_at = now() where id = _id;
  perform public.vv_event(sv.workspace_id, 'survey', _id, 'ended', jsonb_build_object('ended_on', _ended_on));
end $$;

create function public.vv_link_survey_trap(_survey uuid, _deployment uuid) returns void
  language plpgsql security definer set search_path = '' as $$
declare sv public.vv_surveys; d public.vv_deployments;
begin
  select * into sv from public.vv_surveys where id = _survey;
  if sv.id is null or not public.vv_has(sv.workspace_id, array['field', 'manage']) or not public.vv_can_see_site(sv.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if sv.ended_on is not null then raise exception 'that survey has ended' using errcode = '22023'; end if;
  select * into d from public.vv_deployments where id = _deployment and workspace_id = sv.workspace_id;
  if d.id is null or not public.vv_can_see_site(d.site_id) then raise exception 'unknown trap deployment' using errcode = '22023'; end if;
  insert into public.vv_survey_deployments (survey_id, deployment_id, workspace_id, added_by) values (_survey, _deployment, sv.workspace_id, auth.uid())
  on conflict do nothing;
  if found then perform public.vv_event(sv.workspace_id, 'survey', _survey, 'trap_linked', jsonb_build_object('deployment_id', _deployment)); end if;
end $$;

-- What a survey has found so far. Security invoker: row level security applies.
create function public.vv_survey_summary(_survey uuid) returns table(inspections integer, traps integer, samples integer, positive_finds integer,
    invasive_finds integer, negative_finds integer, awaiting_results integer)
  language sql stable set search_path = '' as $$
  with smp as (
    select s.id from public.vv_samples s join public.vv_inspections i on i.id = s.inspection_id where i.survey_id = _survey
    union
    select s.id from public.vv_samples s join public.vv_visits v on v.id = s.visit_id
      join public.vv_survey_deployments sd on sd.deployment_id = v.deployment_id
      join public.vv_surveys sv on sv.id = sd.survey_id
     where sd.survey_id = _survey and v.occurred_at::date >= sv.started_on
  ),
  res as (
    select rv.status, t.invasive from public.vv_results r
      join public.vv_result_versions rv on rv.result_id = r.id and rv.version = r.current_version
      left join public.vv_taxa t on t.id = rv.taxon_id
     where r.sample_id in (select id from smp)
  )
  select (select count(*) from public.vv_inspections where survey_id = _survey)::int,
         (select count(*) from public.vv_survey_deployments where survey_id = _survey)::int,
         (select count(*) from smp)::int,
         (select count(*) from res where status in ('provisional', 'confirmed'))::int,
         (select count(*) from res where status in ('provisional', 'confirmed') and invasive)::int,
         (select count(*) from res where status = 'negative')::int,
         (select count(*) from public.vv_samples s where s.id in (select id from smp) and s.status = 'awaiting_result')::int
$$;

-- ---------- Pathogen tests --------------------------------------------------------------------------
create table public.vv_pathogen_tests (
  id            uuid primary key,
  workspace_id  uuid not null references public.workspaces(id) on delete restrict,
  sample_id     uuid not null,
  site_id       uuid not null,
  pathogen      text not null check (pathogen in ('dengue', 'chikungunya', 'zika', 'west_nile', 'usutu', 'yellow_fever', 'malaria', 'other')),
  pathogen_other text check (char_length(pathogen_other) <= 120),
  method        text check (char_length(method) <= 200),
  laboratory    text check (char_length(laboratory) <= 200),
  lab_reference text check (char_length(lab_reference) <= 100),
  status        text not null default 'pending' check (status in ('pending', 'not_detected', 'detected', 'inconclusive')),
  result_date   date,
  note          text check (char_length(note) <= 2000),
  created_by    uuid not null,
  created_at    timestamptz not null default now(),
  updated_by    uuid,
  updated_at    timestamptz,
  foreign key (sample_id, workspace_id) references public.vv_samples(id, workspace_id) on delete restrict,
  foreign key (site_id, workspace_id) references public.vv_sites(id, workspace_id) on delete restrict,
  check (pathogen <> 'other' or char_length(trim(coalesce(pathogen_other, ''))) >= 2),
  check (status = 'pending' or result_date is not null)
);
create index vv_pathogen_tests_sample_idx on public.vv_pathogen_tests (sample_id);
create trigger vv_pathogen_tests_immutable before update on public.vv_pathogen_tests
  for each row execute function public.guard_immutable('id', 'workspace_id', 'sample_id', 'site_id', 'pathogen', 'pathogen_other', 'created_by', 'created_at');
create trigger vv_pathogen_tests_no_delete before delete on public.vv_pathogen_tests for each row execute function public.forbid_update();

-- Record a test, or update its result (the change and the reason go into the history).
create function public.vv_save_pathogen_test(_id uuid, _sample uuid, _pathogen text, _pathogen_other text, _method text, _laboratory text,
    _lab_reference text, _status text, _result_date date, _note text, _reason text) returns void
  language plpgsql security definer set search_path = '' as $$
declare s public.vv_samples; old public.vv_pathogen_tests; after jsonb;
begin
  select * into s from public.vv_samples where id = _sample;
  if _id is null or s.id is null or not public.vv_has(s.workspace_id, array['field', 'manage']) or not public.vv_can_see_site(s.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if _result_date is not null and _result_date > (now() at time zone 'Europe/London')::date then
    raise exception 'the result date cannot be in the future' using errcode = '22023';
  end if;
  select * into old from public.vv_pathogen_tests where id = _id for update;
  if old.id is null then
    insert into public.vv_pathogen_tests (id, workspace_id, sample_id, site_id, pathogen, pathogen_other, method, laboratory, lab_reference, status,
      result_date, note, created_by)
    values (_id, s.workspace_id, _sample, s.site_id, _pathogen, nullif(trim(_pathogen_other), ''), nullif(trim(_method), ''), nullif(trim(_laboratory), ''),
      nullif(trim(_lab_reference), ''), coalesce(_status, 'pending'), _result_date, nullif(trim(_note), ''), auth.uid());
    perform public.vv_event(s.workspace_id, 'pathogen_test', _id, 'recorded',
      jsonb_build_object('sample_id', _sample, 'pathogen', _pathogen, 'status', coalesce(_status, 'pending')));
    return;
  end if;
  if old.sample_id <> _sample then raise exception 'not allowed' using errcode = '42501'; end if;
  if (old.method, old.laboratory, old.lab_reference, old.status, old.result_date, old.note)
     is not distinct from (nullif(trim(_method), ''), nullif(trim(_laboratory), ''), nullif(trim(_lab_reference), ''), coalesce(_status, old.status), _result_date, nullif(trim(_note), '')) then
    return;   -- retry
  end if;
  if old.status <> 'pending' and char_length(trim(coalesce(_reason, ''))) < 5 then raise exception 'give a reason for changing a result' using errcode = '22023'; end if;
  update public.vv_pathogen_tests set method = nullif(trim(_method), ''), laboratory = nullif(trim(_laboratory), ''), lab_reference = nullif(trim(_lab_reference), ''),
    status = coalesce(_status, status), result_date = _result_date, note = nullif(trim(_note), ''), updated_by = auth.uid(), updated_at = now() where id = _id;
  select to_jsonb(x) into after from public.vv_pathogen_tests x where x.id = _id;
  perform public.vv_event(s.workspace_id, 'pathogen_test', _id, 'changed',
    public.vv_diff(to_jsonb(old), after) || case when nullif(trim(_reason), '') is null then '{}'::jsonb else jsonb_build_object('reason', trim(_reason)) end);
end $$;

-- ---------- Control actions -----------------------------------------------------------------------
create table public.vv_control_actions (
  id                uuid primary key,
  workspace_id      uuid not null references public.workspaces(id) on delete restrict,
  site_id           uuid not null,
  incursion_id      uuid,
  survey_id         uuid,
  kind              text not null check (kind in ('source_reduction', 'larviciding', 'adulticiding', 'barrier_treatment', 'other')),
  occurred_on       date not null,
  product           text check (char_length(product) <= 200),
  active_substance  text check (char_length(active_substance) <= 200),
  quantity          text check (char_length(quantity) <= 200),
  area_description  text check (char_length(area_description) <= 1000),
  latitude          double precision check (latitude between -90 and 90),
  longitude         double precision check (longitude between -180 and 180),
  radius_m          integer check (radius_m between 1 and 5000),
  operator          text check (char_length(operator) <= 200),
  supervised_by     uuid,
  notes             text check (char_length(notes) <= 2000),
  recorded_by       uuid not null,
  recorded_role     text not null,
  recorded_at       timestamptz not null default now(),
  withdrawn_by      uuid,
  withdrawn_at      timestamptz,
  withdrawn_reason  text check (char_length(withdrawn_reason) <= 500),
  foreign key (site_id, workspace_id) references public.vv_sites(id, workspace_id) on delete restrict,
  foreign key (incursion_id, workspace_id) references public.vv_incursions(id, workspace_id) on delete restrict,
  foreign key (survey_id, workspace_id) references public.vv_surveys(id, workspace_id) on delete restrict,
  foreign key (workspace_id, supervised_by) references public.workspace_members(workspace_id, user_id) on delete set null (supervised_by),
  check ((latitude is null) = (longitude is null)),
  check (kind not in ('larviciding', 'adulticiding', 'barrier_treatment') or char_length(trim(coalesce(product, ''))) >= 2),
  check ((withdrawn_at is null) = (withdrawn_reason is null) and (withdrawn_at is null) = (withdrawn_by is null))
);
create index vv_control_actions_site_idx on public.vv_control_actions (site_id, occurred_on desc);
create trigger vv_control_actions_immutable before update on public.vv_control_actions
  for each row execute function public.guard_immutable('id', 'workspace_id', 'site_id', 'incursion_id', 'survey_id', 'kind', 'occurred_on', 'product',
    'active_substance', 'quantity', 'area_description', 'latitude', 'longitude', 'radius_m', 'operator', 'supervised_by', 'notes', 'recorded_by', 'recorded_role', 'recorded_at');
create trigger vv_control_actions_no_delete before delete on public.vv_control_actions for each row execute function public.forbid_update();

create function public.vv_record_control(_id uuid, _site uuid, _incursion uuid, _survey uuid, _kind text, _occurred_on date, _product text,
    _substance text, _quantity text, _area text, _lat double precision, _lon double precision, _radius integer, _operator text, _supervised_by uuid,
    _notes text) returns void
  language plpgsql security definer set search_path = '' as $$
declare s public.vv_sites;
begin
  select * into s from public.vv_sites where id = _site;
  if _id is null or s.id is null or not public.vv_has(s.workspace_id, array['field', 'manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if exists (select 1 from public.vv_control_actions where id = _id) then
    if exists (select 1 from public.vv_control_actions where id = _id and site_id = _site) then return; end if;
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if _occurred_on is null or _occurred_on > (now() at time zone 'Europe/London')::date then raise exception 'the date cannot be in the future' using errcode = '22023'; end if;
  if _incursion is not null and not exists (select 1 from public.vv_incursions where id = _incursion and workspace_id = s.workspace_id) then
    raise exception 'unknown incursion' using errcode = '22023';
  end if;
  if _survey is not null and not exists (select 1 from public.vv_surveys where id = _survey and site_id = _site) then
    raise exception 'unknown survey' using errcode = '22023';
  end if;
  if _supervised_by is not null and not exists (select 1 from public.workspace_members where workspace_id = s.workspace_id and user_id = _supervised_by) then
    raise exception 'unknown supervisor' using errcode = '22023';
  end if;
  insert into public.vv_control_actions (id, workspace_id, site_id, incursion_id, survey_id, kind, occurred_on, product, active_substance, quantity,
    area_description, latitude, longitude, radius_m, operator, supervised_by, notes, recorded_by, recorded_role)
  values (_id, s.workspace_id, _site, _incursion, _survey, _kind, _occurred_on, nullif(trim(_product), ''), nullif(trim(_substance), ''),
    nullif(trim(_quantity), ''), nullif(trim(_area), ''), _lat, _lon, _radius, nullif(trim(_operator), ''), _supervised_by, nullif(trim(_notes), ''),
    auth.uid(), coalesce(public.product_level(s.workspace_id, 'vectovia'), 'unknown') || ' (' || coalesce(public.ws_role_of(s.workspace_id), 'unknown') || ')');
  perform public.vv_event(s.workspace_id, 'control_action', _id, 'recorded',
    jsonb_build_object('site_id', _site, 'kind', _kind, 'occurred_on', _occurred_on, 'incursion_id', _incursion, 'survey_id', _survey));
end $$;

create function public.vv_withdraw_control(_id uuid, _reason text) returns void
  language plpgsql security definer set search_path = '' as $$
declare c public.vv_control_actions;
begin
  select * into c from public.vv_control_actions where id = _id for update;
  if c.id is null or not public.vv_has(c.workspace_id, array['manage']) or not public.vv_can_see_site(c.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if c.withdrawn_at is not null then return; end if;
  if char_length(trim(coalesce(_reason, ''))) < 5 then raise exception 'give a reason' using errcode = '22023'; end if;
  update public.vv_control_actions set withdrawn_by = auth.uid(), withdrawn_at = now(), withdrawn_reason = trim(_reason) where id = _id;
  perform public.vv_event(c.workspace_id, 'control_action', _id, 'withdrawn', jsonb_build_object('reason', trim(_reason)));
end $$;

-- ---------- Invasive finds awaiting official identification -------------------------------------
-- Provisional finds of an invasive species: flagged until a confirmed (official) result is recorded.
-- Security invoker: row level security applies.
create function public.vv_awaiting_official_id(_ws uuid) returns table(result_id uuid, sample_id uuid, site_id uuid, taxon_id uuid, recorded_at timestamptz, days_waiting integer)
  language sql stable set search_path = '' as $$
  select r.id, r.sample_id, r.site_id, rv.taxon_id, rv.recorded_at, ((now() at time zone 'Europe/London')::date - (rv.recorded_at at time zone 'Europe/London')::date)::int
    from public.vv_results r
    join public.vv_result_versions rv on rv.result_id = r.id and rv.version = r.current_version
    join public.vv_taxa t on t.id = rv.taxon_id
   where r.workspace_id = _ws and t.invasive and rv.status = 'provisional'
   order by rv.recorded_at
$$;

-- ---------- Row level security -----------------------------------------------------------------------
alter table public.vv_surveys enable row level security;
create policy vv_surveys_read on public.vv_surveys for select to authenticated using (public.vv_can_see_site(site_id));
alter table public.vv_survey_deployments enable row level security;
create policy vv_survey_deployments_read on public.vv_survey_deployments for select to authenticated
  using (exists (select 1 from public.vv_surveys s where s.id = survey_id));
alter table public.vv_inspections enable row level security;
create policy vv_inspections_read on public.vv_inspections for select to authenticated using (public.vv_can_see_site(site_id));
alter table public.vv_pathogen_tests enable row level security;
create policy vv_pathogen_tests_read on public.vv_pathogen_tests for select to authenticated using (public.vv_can_see_site(site_id));
alter table public.vv_control_actions enable row level security;
create policy vv_control_actions_read on public.vv_control_actions for select to authenticated using (public.vv_can_see_site(site_id));

-- ---------- Grants (by name) ----------------------------------------------------------------------
revoke all on table public.vv_surveys, public.vv_survey_deployments, public.vv_inspections, public.vv_pathogen_tests, public.vv_control_actions
  from anon, authenticated;
grant select on table public.vv_surveys, public.vv_survey_deployments, public.vv_inspections, public.vv_pathogen_tests, public.vv_control_actions
  to authenticated;
grant all on table public.vv_surveys, public.vv_survey_deployments, public.vv_inspections, public.vv_pathogen_tests, public.vv_control_actions
  to service_role;

revoke all on function public.vv_record_inspection(uuid, uuid, timestamptz, uuid, text, double precision, double precision, text, text, text, text, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.vv_save_survey(uuid, uuid, uuid, uuid, double precision, double precision, integer, date, text) from public, anon, authenticated;
revoke all on function public.vv_end_survey(uuid, date, text) from public, anon, authenticated;
revoke all on function public.vv_link_survey_trap(uuid, uuid) from public, anon, authenticated;
revoke all on function public.vv_survey_summary(uuid) from public, anon, authenticated;
revoke all on function public.vv_save_pathogen_test(uuid, uuid, text, text, text, text, text, text, date, text, text) from public, anon, authenticated;
revoke all on function public.vv_record_control(uuid, uuid, uuid, uuid, text, date, text, text, text, text, double precision, double precision, integer, text, uuid, text) from public, anon, authenticated;
revoke all on function public.vv_withdraw_control(uuid, text) from public, anon, authenticated;
revoke all on function public.vv_awaiting_official_id(uuid) from public, anon, authenticated;

grant execute on function public.vv_record_inspection(uuid, uuid, timestamptz, uuid, text, double precision, double precision, text, text, text, text, uuid, jsonb) to authenticated, service_role;
grant execute on function public.vv_save_survey(uuid, uuid, uuid, uuid, double precision, double precision, integer, date, text) to authenticated, service_role;
grant execute on function public.vv_end_survey(uuid, date, text) to authenticated, service_role;
grant execute on function public.vv_link_survey_trap(uuid, uuid) to authenticated, service_role;
grant execute on function public.vv_survey_summary(uuid) to authenticated, service_role;
grant execute on function public.vv_save_pathogen_test(uuid, uuid, text, text, text, text, text, text, date, text, text) to authenticated, service_role;
grant execute on function public.vv_record_control(uuid, uuid, uuid, uuid, text, date, text, text, text, text, double precision, double precision, integer, text, uuid, text) to authenticated, service_role;
grant execute on function public.vv_withdraw_control(uuid, text) to authenticated, service_role;
grant execute on function public.vv_awaiting_official_id(uuid) to authenticated, service_role;
