-- =====================================================================
-- VECTOVIA — v2-006: other IHR records (design v2 build stage 6).
--   * Points of entry may now have a zone under 400 m (owner decision 2026-11-01). The database no longer
--     refuses it; the zone requirement shows "partly met" so the shortfall stays visible.
--   * Registers kept by the organisation: competence (training, with expiry), contractors (with the sites
--     they work at and their audits), equipment and chemicals (authorisations and expiry).
--   * Site records: conveyance inspections, follow-up notices to the next point of entry, the incoming-risk
--     log, and site reviews (sanitary survey, wider survey, operator report, effectiveness review).
--   * Compliance: new checks worked out from these records (training, contractors, equipment, sanitary
--     survey, wider survey, incoming risks, conveyances, follow-ups, treatment supervision).
-- All records belong to one organisation; nothing here is visible to another organisation or used for AI.
-- STATUS: APPLIED 2026-11-01 to vectovia-mvp (widvaahmcqanxezfhjqd), with owner approval.
-- =====================================================================

-- ---------- Zones under 400 m at points of entry ---------------------------------------------------
alter table public.vv_sites drop constraint vv_sites_poe_zone_check;

-- ---------- History for the new record types -------------------------------------------------------
alter table public.vv_events drop constraint vv_events_record_type_check;
alter table public.vv_events add constraint vv_events_record_type_check check (record_type in ('programme', 'site', 'trap', 'council_taxon',
  'council_trap_type', 'deployment', 'visit', 'sample', 'result', 'assessment', 'action', 'incursion', 'notify_contact',
  'inspection', 'survey', 'pathogen_test', 'control_action',
  'competence', 'contractor', 'contractor_audit', 'equipment', 'conveyance', 'follow_up', 'incoming_risk', 'site_review'));

create function public.vv_today() returns date language sql stable set search_path = '' as $$ select (now() at time zone 'Europe/London')::date $$;

-- ---------- Competence (training) --------------------------------------------------------------------
-- One record per person per competence achieved. A renewal is a new record; the old one stays as history.
create table public.vv_competence (
  id              uuid primary key,
  workspace_id    uuid not null references public.workspaces(id) on delete restrict,
  person_name     text not null check (char_length(person_name) between 2 and 120),
  person_id       uuid,
  competence      text not null check (char_length(competence) between 2 and 200),
  provider        text check (char_length(provider) <= 200),
  achieved_on     date not null,
  expires_on      date check (expires_on is null or expires_on > achieved_on),
  certificate_ref text check (char_length(certificate_ref) <= 100),
  created_by      uuid not null,
  created_at      timestamptz not null default now(),
  updated_by      uuid,
  updated_at      timestamptz,
  withdrawn_by    uuid,
  withdrawn_at    timestamptz,
  withdrawn_reason text check (char_length(withdrawn_reason) <= 500)
);
create index vv_competence_ws on public.vv_competence (workspace_id);
create trigger vv_competence_immutable before update on public.vv_competence
  for each row execute function public.guard_immutable('id', 'workspace_id', 'created_by', 'created_at');
create trigger vv_competence_no_delete before delete on public.vv_competence for each row execute function public.forbid_update();

create function public.vv_save_competence(_id uuid, _ws uuid, _person_name text, _person uuid, _competence text, _provider text,
    _achieved_on date, _expires_on date, _certificate_ref text, _reason text) returns void
  language plpgsql security definer set search_path = '' as $$
declare old public.vv_competence; after jsonb;
begin
  if _id is null or not public.vv_has(_ws, array['manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  if _person is not null and not exists (select 1 from public.workspace_members m where m.workspace_id = _ws and m.user_id = _person) then
    raise exception 'that person is not in this organisation' using errcode = '22023';
  end if;
  if _achieved_on > public.vv_today() then raise exception 'the date achieved cannot be in the future' using errcode = '22023'; end if;
  select * into old from public.vv_competence where id = _id for update;
  if old.id is null then
    insert into public.vv_competence (id, workspace_id, person_name, person_id, competence, provider, achieved_on, expires_on, certificate_ref, created_by)
    values (_id, _ws, trim(_person_name), _person, trim(_competence), nullif(trim(_provider), ''), _achieved_on, _expires_on, nullif(trim(_certificate_ref), ''), auth.uid());
    perform public.vv_event(_ws, 'competence', _id, 'recorded', jsonb_build_object('competence', trim(_competence), 'expires_on', _expires_on));
    return;
  end if;
  if old.workspace_id <> _ws or old.withdrawn_at is not null then raise exception 'not allowed' using errcode = '42501'; end if;
  if (old.person_name, old.person_id, old.competence, old.provider, old.achieved_on, old.expires_on, old.certificate_ref)
     is not distinct from (trim(_person_name), _person, trim(_competence), nullif(trim(_provider), ''), _achieved_on, _expires_on, nullif(trim(_certificate_ref), '')) then
    return;
  end if;
  if char_length(trim(coalesce(_reason, ''))) < 5 then raise exception 'give a reason for the change' using errcode = '22023'; end if;
  update public.vv_competence set person_name = trim(_person_name), person_id = _person, competence = trim(_competence), provider = nullif(trim(_provider), ''),
    achieved_on = _achieved_on, expires_on = _expires_on, certificate_ref = nullif(trim(_certificate_ref), ''), updated_by = auth.uid(), updated_at = now()
   where id = _id;
  select to_jsonb(x) into after from public.vv_competence x where x.id = _id;
  perform public.vv_event(_ws, 'competence', _id, 'changed', public.vv_diff(to_jsonb(old), after) || jsonb_build_object('reason', trim(_reason)));
end $$;

-- Withdraw a record entered in error (it stays in the history).
create function public.vv_withdraw_competence(_id uuid, _reason text) returns void
  language plpgsql security definer set search_path = '' as $$
declare c public.vv_competence;
begin
  select * into c from public.vv_competence where id = _id for update;
  if c.id is null or not public.vv_has(c.workspace_id, array['manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  if c.withdrawn_at is not null then return; end if;
  if char_length(trim(coalesce(_reason, ''))) < 5 then raise exception 'give a reason' using errcode = '22023'; end if;
  update public.vv_competence set withdrawn_by = auth.uid(), withdrawn_at = now(), withdrawn_reason = trim(_reason) where id = _id;
  perform public.vv_event(c.workspace_id, 'competence', _id, 'withdrawn', jsonb_build_object('reason', trim(_reason)));
end $$;

-- ---------- Contractors ---------------------------------------------------------------------------
create table public.vv_contractors (
  id           uuid primary key,
  workspace_id uuid not null references public.workspaces(id) on delete restrict,
  name         text not null check (char_length(name) between 2 and 200),
  service      text not null check (char_length(service) between 2 and 500),
  contact      text check (char_length(contact) <= 300),
  status       text not null default 'active' check (status in ('active', 'ended')),
  created_by   uuid not null,
  created_at   timestamptz not null default now(),
  updated_by   uuid,
  updated_at   timestamptz
);
create index vv_contractors_ws on public.vv_contractors (workspace_id);
create trigger vv_contractors_immutable before update on public.vv_contractors
  for each row execute function public.guard_immutable('id', 'workspace_id', 'created_by', 'created_at');
create trigger vv_contractors_no_delete before delete on public.vv_contractors for each row execute function public.forbid_update();

create table public.vv_contractor_sites (
  contractor_id uuid not null references public.vv_contractors(id) on delete restrict,
  site_id       uuid not null references public.vv_sites(id) on delete restrict,
  workspace_id  uuid not null references public.workspaces(id) on delete restrict,
  primary key (contractor_id, site_id)
);

create table public.vv_contractor_audits (
  id            uuid primary key,
  workspace_id  uuid not null references public.workspaces(id) on delete restrict,
  contractor_id uuid not null references public.vv_contractors(id) on delete restrict,
  site_id       uuid references public.vv_sites(id) on delete restrict,
  audited_on    date not null,
  outcome       text not null check (outcome in ('satisfactory', 'actions_needed', 'unsatisfactory')),
  findings      text not null check (char_length(findings) between 5 and 5000),
  next_due      date not null,
  recorded_by   uuid not null,
  recorded_at   timestamptz not null default now(),
  check (next_due > audited_on)
);
create index vv_contractor_audits_c on public.vv_contractor_audits (contractor_id, audited_on desc);
create trigger vv_contractor_audits_no_update before update or delete on public.vv_contractor_audits for each row execute function public.forbid_update();

-- Sites: the full list of sites the contractor works at (replaces the previous list).
create function public.vv_save_contractor(_id uuid, _ws uuid, _name text, _service text, _contact text, _status text, _sites uuid[], _reason text) returns void
  language plpgsql security definer set search_path = '' as $$
declare old public.vv_contractors; after jsonb; old_sites uuid[]; new_sites uuid[];
begin
  if _id is null or not public.vv_has(_ws, array['manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  select coalesce(array_agg(distinct x order by x), '{}') into new_sites from unnest(coalesce(_sites, '{}')) x;
  if exists (select 1 from unnest(new_sites) x where not exists (select 1 from public.vv_sites s where s.id = x and s.workspace_id = _ws)) then
    raise exception 'a site is not in this organisation' using errcode = '22023';
  end if;
  select * into old from public.vv_contractors where id = _id for update;
  if old.id is null then
    insert into public.vv_contractors (id, workspace_id, name, service, contact, status, created_by)
    values (_id, _ws, trim(_name), trim(_service), nullif(trim(_contact), ''), coalesce(_status, 'active'), auth.uid());
    insert into public.vv_contractor_sites (contractor_id, site_id, workspace_id) select _id, x, _ws from unnest(new_sites) x;
    perform public.vv_event(_ws, 'contractor', _id, 'recorded', jsonb_build_object('name', trim(_name), 'sites', to_jsonb(new_sites)));
    return;
  end if;
  if old.workspace_id <> _ws then raise exception 'not allowed' using errcode = '42501'; end if;
  select coalesce(array_agg(site_id order by site_id), '{}') into old_sites from public.vv_contractor_sites where contractor_id = _id;
  if (old.name, old.service, old.contact, old.status, old_sites)
     is not distinct from (trim(_name), trim(_service), nullif(trim(_contact), ''), coalesce(_status, old.status), new_sites) then
    return;
  end if;
  if char_length(trim(coalesce(_reason, ''))) < 5 then raise exception 'give a reason for the change' using errcode = '22023'; end if;
  update public.vv_contractors set name = trim(_name), service = trim(_service), contact = nullif(trim(_contact), ''), status = coalesce(_status, status),
    updated_by = auth.uid(), updated_at = now() where id = _id;
  delete from public.vv_contractor_sites where contractor_id = _id and site_id <> all(new_sites);
  insert into public.vv_contractor_sites (contractor_id, site_id, workspace_id) select _id, x, _ws from unnest(new_sites) x on conflict do nothing;
  select to_jsonb(x) into after from public.vv_contractors x where x.id = _id;
  perform public.vv_event(_ws, 'contractor', _id, 'changed', public.vv_diff(to_jsonb(old), after)
    || case when old_sites is distinct from new_sites then jsonb_build_object('sites', jsonb_build_object('from', to_jsonb(old_sites), 'to', to_jsonb(new_sites))) else '{}'::jsonb end
    || jsonb_build_object('reason', trim(_reason)));
end $$;

create function public.vv_record_contractor_audit(_id uuid, _contractor uuid, _site uuid, _audited_on date, _outcome text, _findings text, _next_due date) returns void
  language plpgsql security definer set search_path = '' as $$
declare c public.vv_contractors; old public.vv_contractor_audits;
begin
  select * into c from public.vv_contractors where id = _contractor;
  if _id is null or c.id is null or not public.vv_has(c.workspace_id, array['manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  if _site is not null and not exists (select 1 from public.vv_contractor_sites x where x.contractor_id = _contractor and x.site_id = _site) then
    raise exception 'the contractor does not work at that site' using errcode = '22023';
  end if;
  if _audited_on > public.vv_today() then raise exception 'the audit date cannot be in the future' using errcode = '22023'; end if;
  select * into old from public.vv_contractor_audits where id = _id;
  if old.id is not null then
    if old.contractor_id <> _contractor then raise exception 'not allowed' using errcode = '42501'; end if;
    return;   -- retry
  end if;
  insert into public.vv_contractor_audits (id, workspace_id, contractor_id, site_id, audited_on, outcome, findings, next_due, recorded_by)
  values (_id, c.workspace_id, _contractor, _site, _audited_on, _outcome, trim(_findings), coalesce(_next_due, _audited_on + 365), auth.uid());
  perform public.vv_event(c.workspace_id, 'contractor_audit', _id, 'recorded',
    jsonb_build_object('contractor_id', _contractor, 'site_id', _site, 'outcome', _outcome));
end $$;

-- ---------- Equipment and chemicals ------------------------------------------------------------------
create table public.vv_equipment (
  id                uuid primary key,
  workspace_id      uuid not null references public.workspaces(id) on delete restrict,
  kind              text not null check (kind in ('equipment', 'chemical')),
  name              text not null check (char_length(name) between 2 and 200),
  active_substance  text check (char_length(active_substance) <= 200),
  authorisation_ref text check (char_length(authorisation_ref) <= 100),
  location          text check (char_length(location) <= 300),
  quantity          text check (char_length(quantity) <= 100),
  expires_on        date,
  status            text not null default 'in_use' check (status in ('in_use', 'withdrawn')),
  notes             text check (char_length(notes) <= 2000),
  created_by        uuid not null,
  created_at        timestamptz not null default now(),
  updated_by        uuid,
  updated_at        timestamptz
);
create index vv_equipment_ws on public.vv_equipment (workspace_id);
create trigger vv_equipment_immutable before update on public.vv_equipment
  for each row execute function public.guard_immutable('id', 'workspace_id', 'kind', 'created_by', 'created_at');
create trigger vv_equipment_no_delete before delete on public.vv_equipment for each row execute function public.forbid_update();

create function public.vv_save_equipment(_id uuid, _ws uuid, _kind text, _name text, _substance text, _authorisation text, _location text,
    _quantity text, _expires_on date, _status text, _notes text, _reason text) returns void
  language plpgsql security definer set search_path = '' as $$
declare old public.vv_equipment; after jsonb;
begin
  if _id is null or not public.vv_has(_ws, array['manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  select * into old from public.vv_equipment where id = _id for update;
  if old.id is null then
    insert into public.vv_equipment (id, workspace_id, kind, name, active_substance, authorisation_ref, location, quantity, expires_on, status, notes, created_by)
    values (_id, _ws, _kind, trim(_name), nullif(trim(_substance), ''), nullif(trim(_authorisation), ''), nullif(trim(_location), ''), nullif(trim(_quantity), ''),
      _expires_on, coalesce(_status, 'in_use'), nullif(trim(_notes), ''), auth.uid());
    perform public.vv_event(_ws, 'equipment', _id, 'recorded', jsonb_build_object('kind', _kind, 'name', trim(_name), 'expires_on', _expires_on));
    return;
  end if;
  if old.workspace_id <> _ws or old.kind <> _kind then raise exception 'not allowed' using errcode = '42501'; end if;
  if (old.name, old.active_substance, old.authorisation_ref, old.location, old.quantity, old.expires_on, old.status, old.notes)
     is not distinct from (trim(_name), nullif(trim(_substance), ''), nullif(trim(_authorisation), ''), nullif(trim(_location), ''), nullif(trim(_quantity), ''),
       _expires_on, coalesce(_status, old.status), nullif(trim(_notes), '')) then
    return;
  end if;
  if char_length(trim(coalesce(_reason, ''))) < 5 then raise exception 'give a reason for the change' using errcode = '22023'; end if;
  update public.vv_equipment set name = trim(_name), active_substance = nullif(trim(_substance), ''), authorisation_ref = nullif(trim(_authorisation), ''),
    location = nullif(trim(_location), ''), quantity = nullif(trim(_quantity), ''), expires_on = _expires_on, status = coalesce(_status, status),
    notes = nullif(trim(_notes), ''), updated_by = auth.uid(), updated_at = now() where id = _id;
  select to_jsonb(x) into after from public.vv_equipment x where x.id = _id;
  perform public.vv_event(_ws, 'equipment', _id, 'changed', public.vv_diff(to_jsonb(old), after) || jsonb_build_object('reason', trim(_reason)));
end $$;

-- ---------- Conveyance inspections ----------------------------------------------------------------
-- Recorded once and kept as recorded (like inspections); corrections are a new record with a note.
create table public.vv_conveyances (
  id               uuid primary key,
  workspace_id     uuid not null references public.workspaces(id) on delete restrict,
  site_id          uuid not null references public.vv_sites(id) on delete restrict,
  inspected_at     timestamptz not null,
  officer_id       uuid not null,
  conveyance_type  text not null check (conveyance_type in ('ship', 'aircraft', 'road_vehicle', 'train', 'container', 'other')),
  identifier       text not null check (char_length(identifier) between 1 and 120),
  arrived_from     text check (char_length(arrived_from) <= 200),
  next_destination text check (char_length(next_destination) <= 200),
  reason           text not null check (reason in ('routine', 'affected', 'suspect')),
  outcome          text not null check (outcome in ('no_evidence', 'evidence_found', 'treated', 'referred')),
  evidence         text check (char_length(evidence) <= 2000),
  action_taken     text check (char_length(action_taken) <= 2000),
  recorded_at      timestamptz not null default now(),
  check (outcome = 'no_evidence' or char_length(coalesce(evidence, '')) >= 5)
);
create index vv_conveyances_site on public.vv_conveyances (site_id, inspected_at desc);
create trigger vv_conveyances_no_update before update or delete on public.vv_conveyances for each row execute function public.forbid_update();

create function public.vv_record_conveyance(_id uuid, _site uuid, _inspected_at timestamptz, _type text, _identifier text, _arrived_from text,
    _next_destination text, _reason text, _outcome text, _evidence text, _action text) returns void
  language plpgsql security definer set search_path = '' as $$
declare s public.vv_sites; old public.vv_conveyances;
begin
  select * into s from public.vv_sites where id = _site;
  if _id is null or s.id is null or not public.vv_has(s.workspace_id, array['field', 'manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if _inspected_at > now() + interval '5 minutes' then raise exception 'an inspection cannot be in the future' using errcode = '22023'; end if;
  select * into old from public.vv_conveyances where id = _id;
  if old.id is not null then
    if old.site_id <> _site then raise exception 'not allowed' using errcode = '42501'; end if;
    return;
  end if;
  insert into public.vv_conveyances (id, workspace_id, site_id, inspected_at, officer_id, conveyance_type, identifier, arrived_from, next_destination,
    reason, outcome, evidence, action_taken)
  values (_id, s.workspace_id, _site, _inspected_at, auth.uid(), _type, trim(_identifier), nullif(trim(_arrived_from), ''), nullif(trim(_next_destination), ''),
    coalesce(_reason, 'routine'), _outcome, nullif(trim(_evidence), ''), nullif(trim(_action), ''));
  perform public.vv_event(s.workspace_id, 'conveyance', _id, 'recorded',
    jsonb_build_object('site_id', _site, 'type', _type, 'outcome', _outcome, 'reason', coalesce(_reason, 'routine')));
end $$;

-- ---------- Follow-up notices to the next point of entry -------------------------------------------
create table public.vv_follow_ups (
  id              uuid primary key,
  workspace_id    uuid not null references public.workspaces(id) on delete restrict,
  site_id         uuid not null references public.vv_sites(id) on delete restrict,
  conveyance_id   uuid references public.vv_conveyances(id) on delete restrict,
  to_point_of_entry text not null check (char_length(to_point_of_entry) between 2 and 200),
  sent_on         date not null,
  method          text not null check (method in ('email', 'phone', 'letter', 'other')),
  summary         text not null check (char_length(summary) between 5 and 2000),
  acknowledged_on date,
  ack_note        text check (char_length(ack_note) <= 1000),
  recorded_by     uuid not null,
  recorded_at     timestamptz not null default now(),
  check (acknowledged_on is null or acknowledged_on >= sent_on)
);
create index vv_follow_ups_site on public.vv_follow_ups (site_id, sent_on desc);
create unique index vv_follow_ups_conveyance on public.vv_follow_ups (conveyance_id, to_point_of_entry) where conveyance_id is not null;
create trigger vv_follow_ups_immutable before update on public.vv_follow_ups
  for each row execute function public.guard_immutable('id', 'workspace_id', 'site_id', 'conveyance_id', 'to_point_of_entry', 'sent_on', 'method',
    'summary', 'recorded_by', 'recorded_at');
create trigger vv_follow_ups_no_delete before delete on public.vv_follow_ups for each row execute function public.forbid_update();

create function public.vv_send_follow_up(_id uuid, _site uuid, _conveyance uuid, _to text, _sent_on date, _method text, _summary text) returns void
  language plpgsql security definer set search_path = '' as $$
declare s public.vv_sites; old public.vv_follow_ups;
begin
  select * into s from public.vv_sites where id = _site;
  if _id is null or s.id is null or not public.vv_has(s.workspace_id, array['field', 'manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if _conveyance is not null and not exists (select 1 from public.vv_conveyances c where c.id = _conveyance and c.site_id = _site) then
    raise exception 'that conveyance inspection is not at this site' using errcode = '22023';
  end if;
  if _sent_on > public.vv_today() then raise exception 'the date sent cannot be in the future' using errcode = '22023'; end if;
  select * into old from public.vv_follow_ups where id = _id;
  if old.id is not null then
    if old.site_id <> _site then raise exception 'not allowed' using errcode = '42501'; end if;
    return;
  end if;
  insert into public.vv_follow_ups (id, workspace_id, site_id, conveyance_id, to_point_of_entry, sent_on, method, summary, recorded_by)
  values (_id, s.workspace_id, _site, _conveyance, trim(_to), _sent_on, _method, trim(_summary), auth.uid());
  perform public.vv_event(s.workspace_id, 'follow_up', _id, 'sent', jsonb_build_object('site_id', _site, 'conveyance_id', _conveyance, 'to', trim(_to)));
end $$;

create function public.vv_acknowledge_follow_up(_id uuid, _on date, _note text) returns void
  language plpgsql security definer set search_path = '' as $$
declare f public.vv_follow_ups;
begin
  select * into f from public.vv_follow_ups where id = _id for update;
  if f.id is null or not public.vv_has(f.workspace_id, array['field', 'manage']) or not public.vv_can_see_site(f.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if f.acknowledged_on is not null then
    if f.acknowledged_on = _on then return; end if;
    raise exception 'already acknowledged' using errcode = '22023';
  end if;
  if _on > public.vv_today() or _on < f.sent_on then raise exception 'check the date acknowledged' using errcode = '22023'; end if;
  update public.vv_follow_ups set acknowledged_on = _on, ack_note = nullif(trim(_note), '') where id = _id;
  perform public.vv_event(f.workspace_id, 'follow_up', _id, 'acknowledged', jsonb_build_object('on', _on));
end $$;

-- ---------- Incoming-risk log ---------------------------------------------------------------------
create table public.vv_incoming_risks (
  id           uuid primary key,
  workspace_id uuid not null references public.workspaces(id) on delete restrict,
  site_id      uuid not null references public.vv_sites(id) on delete restrict,
  reported_on  date not null,
  source       text not null check (char_length(source) between 2 and 200),
  description  text not null check (char_length(description) between 5 and 2000),
  level        text not null check (level in ('low', 'medium', 'high')),
  action       text check (char_length(action) <= 2000),
  status       text not null default 'open' check (status in ('open', 'closed')),
  closed_on    date,
  closed_note  text check (char_length(closed_note) <= 1000),
  created_by   uuid not null,
  created_at   timestamptz not null default now(),
  updated_by   uuid,
  updated_at   timestamptz,
  check ((status = 'closed') = (closed_on is not null))
);
create index vv_incoming_risks_site on public.vv_incoming_risks (site_id, reported_on desc);
create trigger vv_incoming_risks_immutable before update on public.vv_incoming_risks
  for each row execute function public.guard_immutable('id', 'workspace_id', 'site_id', 'created_by', 'created_at');
create trigger vv_incoming_risks_no_delete before delete on public.vv_incoming_risks for each row execute function public.forbid_update();

create function public.vv_save_incoming_risk(_id uuid, _site uuid, _reported_on date, _source text, _description text, _level text, _action text, _reason text) returns void
  language plpgsql security definer set search_path = '' as $$
declare s public.vv_sites; old public.vv_incoming_risks; after jsonb;
begin
  select * into s from public.vv_sites where id = _site;
  if _id is null or s.id is null or not public.vv_has(s.workspace_id, array['field', 'manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if _reported_on > public.vv_today() then raise exception 'the date reported cannot be in the future' using errcode = '22023'; end if;
  select * into old from public.vv_incoming_risks where id = _id for update;
  if old.id is null then
    insert into public.vv_incoming_risks (id, workspace_id, site_id, reported_on, source, description, level, action, created_by)
    values (_id, s.workspace_id, _site, _reported_on, trim(_source), trim(_description), _level, nullif(trim(_action), ''), auth.uid());
    perform public.vv_event(s.workspace_id, 'incoming_risk', _id, 'recorded', jsonb_build_object('site_id', _site, 'level', _level));
    return;
  end if;
  if old.site_id <> _site or old.status = 'closed' then raise exception 'not allowed' using errcode = '42501'; end if;
  if (old.reported_on, old.source, old.description, old.level, old.action)
     is not distinct from (_reported_on, trim(_source), trim(_description), _level, nullif(trim(_action), '')) then
    return;
  end if;
  -- Adding or updating the action taken is routine; changing what was reported needs a reason.
  if (old.reported_on, old.source, old.description, old.level) is distinct from (_reported_on, trim(_source), trim(_description), _level)
     and char_length(trim(coalesce(_reason, ''))) < 5 then
    raise exception 'give a reason for changing what was reported' using errcode = '22023';
  end if;
  update public.vv_incoming_risks set reported_on = _reported_on, source = trim(_source), description = trim(_description), level = _level,
    action = nullif(trim(_action), ''), updated_by = auth.uid(), updated_at = now() where id = _id;
  select to_jsonb(x) into after from public.vv_incoming_risks x where x.id = _id;
  perform public.vv_event(s.workspace_id, 'incoming_risk', _id, 'changed',
    public.vv_diff(to_jsonb(old), after) || case when nullif(trim(_reason), '') is null then '{}'::jsonb else jsonb_build_object('reason', trim(_reason)) end);
end $$;

create function public.vv_close_incoming_risk(_id uuid, _closed_on date, _note text) returns void
  language plpgsql security definer set search_path = '' as $$
declare r public.vv_incoming_risks;
begin
  select * into r from public.vv_incoming_risks where id = _id for update;
  if r.id is null or not public.vv_has(r.workspace_id, array['field', 'manage']) or not public.vv_can_see_site(r.site_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if r.status = 'closed' then return; end if;
  if char_length(trim(coalesce(_note, ''))) < 5 then raise exception 'say how it was resolved' using errcode = '22023'; end if;
  if _closed_on > public.vv_today() or _closed_on < r.reported_on then raise exception 'check the date closed' using errcode = '22023'; end if;
  update public.vv_incoming_risks set status = 'closed', closed_on = _closed_on, closed_note = trim(_note), updated_by = auth.uid(), updated_at = now() where id = _id;
  perform public.vv_event(r.workspace_id, 'incoming_risk', _id, 'closed', jsonb_build_object('note', trim(_note)));
end $$;

-- ---------- Site reviews and surveys ----------------------------------------------------------------
create table public.vv_site_reviews (
  id                 uuid primary key,
  workspace_id       uuid not null references public.workspaces(id) on delete restrict,
  site_id            uuid not null references public.vv_sites(id) on delete restrict,
  kind               text not null check (kind in ('sanitary_survey', 'wider_survey', 'operator_report', 'effectiveness_review')),
  done_on            date not null,
  summary            text not null check (char_length(summary) between 10 and 5000),
  corrective_actions text check (char_length(corrective_actions) <= 5000),
  next_due           date not null,
  recorded_by        uuid not null,
  recorded_at        timestamptz not null default now(),
  check (next_due > done_on)
);
create index vv_site_reviews_site on public.vv_site_reviews (site_id, kind, done_on desc);
create trigger vv_site_reviews_no_update before update or delete on public.vv_site_reviews for each row execute function public.forbid_update();

-- How often each kind is due by default (a manager can set a different next date).
create function public.vv_review_interval(_kind text) returns interval language sql immutable set search_path = '' as $$
  select case _kind when 'wider_survey' then interval '3 years' else interval '1 year' end
$$;

create function public.vv_record_site_review(_id uuid, _site uuid, _kind text, _done_on date, _summary text, _corrective text, _next_due date) returns void
  language plpgsql security definer set search_path = '' as $$
declare s public.vv_sites; old public.vv_site_reviews;
begin
  select * into s from public.vv_sites where id = _site;
  if _id is null or s.id is null or not public.vv_has(s.workspace_id, array['manage']) or not public.vv_can_see_site(_site) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if _done_on > public.vv_today() then raise exception 'the date cannot be in the future' using errcode = '22023'; end if;
  select * into old from public.vv_site_reviews where id = _id;
  if old.id is not null then
    if old.site_id <> _site then raise exception 'not allowed' using errcode = '42501'; end if;
    return;
  end if;
  insert into public.vv_site_reviews (id, workspace_id, site_id, kind, done_on, summary, corrective_actions, next_due, recorded_by)
  values (_id, s.workspace_id, _site, _kind, _done_on, trim(_summary), nullif(trim(_corrective), ''),
    coalesce(_next_due, (_done_on + public.vv_review_interval(_kind))::date), auth.uid());
  perform public.vv_event(s.workspace_id, 'site_review', _id, 'recorded', jsonb_build_object('site_id', _site, 'kind', _kind, 'done_on', _done_on));
end $$;

-- ---------- Compliance: checks worked out from the new records -----------------------------------
alter table public.vv_obligation_requirements drop constraint vv_obligation_requirements_check_kind_check;
alter table public.vv_obligation_requirements add constraint vv_obligation_requirements_check_kind_check
  check (check_kind in ('assessment', 'zone', 'checks', 'official_id', 'records', 'plan', 'risk',
    'training', 'contractors', 'equipment', 'sanitary_survey', 'wider_survey', 'incoming_risks', 'conveyances', 'follow_up', 'treatment_supervision'));

-- The latest review of a kind at a site, judged against its next due date.
create function public.vv_review_status(_site uuid, _kind text, _what text, out status text, out detail text)
  language plpgsql stable set search_path = '' as $$
declare r public.vv_site_reviews; today date := public.vv_today();
begin
  select * into r from public.vv_site_reviews x where x.site_id = _site and x.kind = _kind order by x.done_on desc, x.recorded_at desc limit 1;
  if r.id is null then status := 'red'; detail := 'No ' || _what || ' recorded.';
  elsif r.next_due < today then status := 'red'; detail := 'The ' || _what || ' was due on ' || to_char(r.next_due, 'DD Mon YYYY') || '.';
  elsif r.next_due <= today + 30 then status := 'amber'; detail := 'The ' || _what || ' is due on ' || to_char(r.next_due, 'DD Mon YYYY') || '.';
  else status := 'green'; detail := 'Last ' || _what || ' ' || to_char(r.done_on, 'DD Mon YYYY') || '; next due ' || to_char(r.next_due, 'DD Mon YYYY') || '.';
  end if;
end $$;

create or replace function public.vv_site_compliance(_site uuid) returns table(site_obligation_id uuid, set_key text, set_name text, version integer,
    requirement_key text, sort_order integer, title text, mandatory boolean, check_kind text, status text, detail text,
    assessed_at timestamptz, review_by date)
  language plpgsql stable set search_path = '' as $$
declare s public.vv_sites; today date := public.vv_today(); poe boolean;
  n_active int; n_inside int; n_overdue int; n_due int; n_off int; n_waiting int; n_late int; has_boundary boolean;
  pl_any boolean; pl_version int; pl_approved_at timestamptz; pl_review date; pl_pending boolean;
  rk_on date; rk_due date; rk_level text;
  tr_current int; tr_lapsed int; tr_soon int;
  ct_active int; ct_overdue int; ct_soon int;
  eq_any int; eq_expired int; eq_soon int; eq_unauth int;
  ir_open int; ir_high int;
  cv_12m int; cv_found int;
  fu_missing int; fu_unacked int;
  ts_needed int; ts_missing int; n_areas int;
  o record; r record; st text; dt text; a_status text; a_note text; a_at timestamptz; a_review date;
begin
  select * into s from public.vv_sites x where x.id = _site;
  if s.id is null then return; end if;
  poe := s.site_type in ('port', 'airport', 'ground_crossing');
  n_areas := (select count(*) from public.vv_site_areas x where x.site_id = _site and x.removed_at is null);
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

  with latest as (
    select distinct on (lower(c.person_name), lower(c.competence)) c.expires_on
      from public.vv_competence c where c.workspace_id = s.workspace_id and c.withdrawn_at is null
     order by lower(c.person_name), lower(c.competence), c.achieved_on desc
  )
  select count(*) filter (where expires_on is null or expires_on >= today), count(*) filter (where expires_on < today),
         count(*) filter (where expires_on between today and today + 30)
    into tr_current, tr_lapsed, tr_soon from latest;
  select count(*), count(*) filter (where la.next_due is null or la.next_due < today), count(*) filter (where la.next_due between today and today + 30)
    into ct_active, ct_overdue, ct_soon
    from public.vv_contractors c
    join public.vv_contractor_sites cs on cs.contractor_id = c.id and cs.site_id = _site
    left join lateral (select a.next_due from public.vv_contractor_audits a where a.contractor_id = c.id order by a.audited_on desc, a.recorded_at desc limit 1) la on true
   where c.status = 'active';
  select count(*), count(*) filter (where e.expires_on < today), count(*) filter (where e.expires_on between today and today + 30),
         count(*) filter (where e.kind = 'chemical' and e.authorisation_ref is null)
    into eq_any, eq_expired, eq_soon, eq_unauth
    from public.vv_equipment e where e.workspace_id = s.workspace_id and e.status = 'in_use';
  select count(*), count(*) filter (where i.level = 'high' and i.action is null)
    into ir_open, ir_high from public.vv_incoming_risks i where i.site_id = _site and i.status = 'open';
  select count(*) filter (where c.inspected_at > now() - interval '365 days'),
         count(*) filter (where c.outcome = 'evidence_found' and c.action_taken is null)
    into cv_12m, cv_found from public.vv_conveyances c where c.site_id = _site;
  fu_missing := (select count(*) from public.vv_conveyances c
                  where c.site_id = _site and c.outcome <> 'no_evidence' and c.next_destination is not null
                    and not exists (select 1 from public.vv_follow_ups f where f.conveyance_id = c.id));
  fu_unacked := (select count(*) from public.vv_follow_ups f where f.site_id = _site and f.acknowledged_on is null and f.sent_on < today - 14);
  select count(*), count(*) filter (where c.supervised_by is null)
    into ts_needed, ts_missing
    from public.vv_control_actions c
   where c.site_id = _site and c.withdrawn_at is null and c.kind in ('larviciding', 'adulticiding', 'barrier_treatment')
     and c.occurred_on > today - 365;

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
        elsif poe and s.zone_m < 400 then st := 'amber';
          dt := 'The zone is ' || s.zone_m || ' m, under the 400 m IHR recommendation; ' || n_inside || ' active trap' || case when n_inside = 1 then '' else 's' end || ' inside it.';
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
      elsif r.check_kind = 'training' then
        if tr_current = 0 then st := 'red'; dt := 'No current training or competence records.';
        elsif tr_lapsed > 0 then st := 'amber'; dt := tr_lapsed || ' competence record' || case when tr_lapsed = 1 then '' else 's' end || ' lapsed without renewal; ' || tr_current || ' current.';
        elsif tr_soon > 0 then st := 'amber'; dt := tr_soon || ' competence record' || case when tr_soon = 1 then '' else 's' end || ' expiring within 30 days.';
        else st := 'green'; dt := tr_current || ' current competence record' || case when tr_current = 1 then '' else 's' end || '.';
        end if;
      elsif r.check_kind = 'contractors' then
        if ct_active = 0 then st := 'not_applicable'; dt := 'No contractors recorded as working at this site.';
        elsif ct_overdue > 0 then st := 'red'; dt := ct_overdue || ' contractor' || case when ct_overdue = 1 then '' else 's' end || ' without a current audit.';
        elsif ct_soon > 0 then st := 'amber'; dt := ct_soon || ' contractor audit' || case when ct_soon = 1 then '' else 's' end || ' due within 30 days.';
        else st := 'green'; dt := 'All ' || ct_active || ' contractor' || case when ct_active = 1 then '' else 's' end || ' audited and in date.';
        end if;
      elsif r.check_kind = 'equipment' then
        if eq_any = 0 then st := 'red'; dt := 'No equipment or chemicals registered.';
        elsif eq_expired > 0 then st := 'red'; dt := eq_expired || ' item' || case when eq_expired = 1 then '' else 's' end || ' in use past the expiry date.';
        elsif eq_unauth > 0 then st := 'amber'; dt := eq_unauth || ' chemical' || case when eq_unauth = 1 then '' else 's' end || ' without an authorisation reference.';
        elsif eq_soon > 0 then st := 'amber'; dt := eq_soon || ' item' || case when eq_soon = 1 then '' else 's' end || ' expiring within 30 days.';
        else st := 'green'; dt := eq_any || ' item' || case when eq_any = 1 then '' else 's' end || ' registered and in date.';
        end if;
      elsif r.check_kind = 'sanitary_survey' then
        select x.status, x.detail into st, dt from public.vv_review_status(_site, 'sanitary_survey', 'sanitary and vector survey') x;
      elsif r.check_kind = 'wider_survey' then
        select x.status, x.detail into st, dt from public.vv_review_status(_site, 'wider_survey', 'wider survey') x;
        if n_areas = 0 and st = 'green' then st := 'amber'; dt := dt || ' No operational areas recorded yet.'; end if;
      elsif r.check_kind = 'incoming_risks' then
        if ir_high > 0 then st := 'red'; dt := ir_high || ' open high-level incoming risk' || case when ir_high = 1 then '' else 's' end || ' with no action recorded.';
        elsif ir_open > 0 then st := 'amber'; dt := ir_open || ' incoming risk' || case when ir_open = 1 then '' else 's' end || ' still open.';
        else st := 'green'; dt := 'No open incoming risks.';
        end if;
      elsif r.check_kind = 'conveyances' then
        if cv_found > 0 then st := 'red'; dt := cv_found || ' conveyance' || case when cv_found = 1 then '' else 's' end || ' with evidence of vectors and no action recorded.';
        else st := 'green'; dt := cv_12m || ' conveyance inspection' || case when cv_12m = 1 then '' else 's' end || ' in the last 12 months.';
        end if;
      elsif r.check_kind = 'follow_up' then
        if fu_missing > 0 then st := 'red'; dt := fu_missing || ' conveyance' || case when fu_missing = 1 then '' else 's' end || ' with findings and a next destination but no follow-up notice.';
        elsif fu_unacked > 0 then st := 'amber'; dt := fu_unacked || ' follow-up notice' || case when fu_unacked = 1 then '' else 's' end || ' not acknowledged after 14 days.';
        else st := 'green'; dt := 'Follow-up notices sent where needed.';
        end if;
      elsif r.check_kind = 'treatment_supervision' then
        if ts_needed = 0 then st := 'not_applicable'; dt := 'No chemical treatments in the last 12 months.';
        elsif ts_missing > 0 then st := 'red'; dt := ts_missing || ' chemical treatment' || case when ts_missing = 1 then '' else 's' end || ' without a named supervisor.';
        else st := 'green'; dt := 'All ' || ts_needed || ' chemical treatment' || case when ts_needed = 1 then '' else 's' end || ' supervised.';
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

-- ---------- Row level security ---------------------------------------------------------------------
alter table public.vv_competence enable row level security;
create policy vv_competence_read on public.vv_competence for select to authenticated using (public.vv_has(workspace_id, array['view', 'field', 'manage']));
alter table public.vv_contractors enable row level security;
create policy vv_contractors_read on public.vv_contractors for select to authenticated using (public.vv_has(workspace_id, array['view', 'field', 'manage']));
alter table public.vv_contractor_sites enable row level security;
create policy vv_contractor_sites_read on public.vv_contractor_sites for select to authenticated using (public.vv_can_see_site(site_id));
alter table public.vv_contractor_audits enable row level security;
create policy vv_contractor_audits_read on public.vv_contractor_audits for select to authenticated
  using (public.vv_has(workspace_id, array['view', 'field', 'manage']) and (site_id is null or public.vv_can_see_site(site_id)));
alter table public.vv_equipment enable row level security;
create policy vv_equipment_read on public.vv_equipment for select to authenticated using (public.vv_has(workspace_id, array['view', 'field', 'manage']));
alter table public.vv_conveyances enable row level security;
create policy vv_conveyances_read on public.vv_conveyances for select to authenticated using (public.vv_can_see_site(site_id));
alter table public.vv_follow_ups enable row level security;
create policy vv_follow_ups_read on public.vv_follow_ups for select to authenticated using (public.vv_can_see_site(site_id));
alter table public.vv_incoming_risks enable row level security;
create policy vv_incoming_risks_read on public.vv_incoming_risks for select to authenticated using (public.vv_can_see_site(site_id));
alter table public.vv_site_reviews enable row level security;
create policy vv_site_reviews_read on public.vv_site_reviews for select to authenticated using (public.vv_can_see_site(site_id));

-- ---------- Grants (by name) ------------------------------------------------------------------------
revoke all on table public.vv_competence, public.vv_contractors, public.vv_contractor_sites, public.vv_contractor_audits, public.vv_equipment,
  public.vv_conveyances, public.vv_follow_ups, public.vv_incoming_risks, public.vv_site_reviews from anon, authenticated;
grant select on table public.vv_competence, public.vv_contractors, public.vv_contractor_sites, public.vv_contractor_audits, public.vv_equipment,
  public.vv_conveyances, public.vv_follow_ups, public.vv_incoming_risks, public.vv_site_reviews to authenticated;
grant all on table public.vv_competence, public.vv_contractors, public.vv_contractor_sites, public.vv_contractor_audits, public.vv_equipment,
  public.vv_conveyances, public.vv_follow_ups, public.vv_incoming_risks, public.vv_site_reviews to service_role;

revoke all on function public.vv_today() from public, anon, authenticated;
revoke all on function public.vv_save_competence(uuid, uuid, text, uuid, text, text, date, date, text, text) from public, anon, authenticated;
revoke all on function public.vv_withdraw_competence(uuid, text) from public, anon, authenticated;
revoke all on function public.vv_save_contractor(uuid, uuid, text, text, text, text, uuid[], text) from public, anon, authenticated;
revoke all on function public.vv_record_contractor_audit(uuid, uuid, uuid, date, text, text, date) from public, anon, authenticated;
revoke all on function public.vv_save_equipment(uuid, uuid, text, text, text, text, text, text, date, text, text, text) from public, anon, authenticated;
revoke all on function public.vv_record_conveyance(uuid, uuid, timestamptz, text, text, text, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.vv_send_follow_up(uuid, uuid, uuid, text, date, text, text) from public, anon, authenticated;
revoke all on function public.vv_acknowledge_follow_up(uuid, date, text) from public, anon, authenticated;
revoke all on function public.vv_save_incoming_risk(uuid, uuid, date, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.vv_close_incoming_risk(uuid, date, text) from public, anon, authenticated;
revoke all on function public.vv_review_interval(text) from public, anon, authenticated;
revoke all on function public.vv_record_site_review(uuid, uuid, text, date, text, text, date) from public, anon, authenticated;
revoke all on function public.vv_review_status(uuid, text, text) from public, anon, authenticated;

grant execute on function public.vv_today() to authenticated, service_role;
grant execute on function public.vv_save_competence(uuid, uuid, text, uuid, text, text, date, date, text, text) to authenticated, service_role;
grant execute on function public.vv_withdraw_competence(uuid, text) to authenticated, service_role;
grant execute on function public.vv_save_contractor(uuid, uuid, text, text, text, text, uuid[], text) to authenticated, service_role;
grant execute on function public.vv_record_contractor_audit(uuid, uuid, uuid, date, text, text, date) to authenticated, service_role;
grant execute on function public.vv_save_equipment(uuid, uuid, text, text, text, text, text, text, date, text, text, text) to authenticated, service_role;
grant execute on function public.vv_record_conveyance(uuid, uuid, timestamptz, text, text, text, text, text, text, text, text) to authenticated, service_role;
grant execute on function public.vv_send_follow_up(uuid, uuid, uuid, text, date, text, text) to authenticated, service_role;
grant execute on function public.vv_acknowledge_follow_up(uuid, date, text) to authenticated, service_role;
grant execute on function public.vv_save_incoming_risk(uuid, uuid, date, text, text, text, text, text) to authenticated, service_role;
grant execute on function public.vv_close_incoming_risk(uuid, date, text) to authenticated, service_role;
grant execute on function public.vv_review_interval(text) to authenticated, service_role;
grant execute on function public.vv_record_site_review(uuid, uuid, text, date, text, text, date) to authenticated, service_role;
grant execute on function public.vv_review_status(uuid, text, text) to authenticated, service_role;
