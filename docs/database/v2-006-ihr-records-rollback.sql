-- Rollback for v2-006 (other IHR records). Owner-run only. Removes the registers, logs and reviews with their
-- records, and restores the v2-003 compliance rules. Before running: obligation requirements using the new
-- checks must be returned to 'assessment' (only possible while a version is a draft), history entries for the
-- new record types removed or kept aside, and any point of entry with a zone under 400 m widened to 400 m.
begin;
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
drop function public.vv_review_status(uuid, text, text);
alter table public.vv_obligation_requirements drop constraint vv_obligation_requirements_check_kind_check;
alter table public.vv_obligation_requirements add constraint vv_obligation_requirements_check_kind_check
  check (check_kind in ('assessment', 'zone', 'checks', 'official_id', 'records', 'plan', 'risk'));
drop function public.vv_record_site_review(uuid, uuid, text, date, text, text, date);
drop function public.vv_review_interval(text);
drop table public.vv_site_reviews;
drop function public.vv_close_incoming_risk(uuid, date, text);
drop function public.vv_save_incoming_risk(uuid, uuid, date, text, text, text, text, text);
drop table public.vv_incoming_risks;
drop function public.vv_acknowledge_follow_up(uuid, date, text);
drop function public.vv_send_follow_up(uuid, uuid, uuid, text, date, text, text);
drop table public.vv_follow_ups;
drop function public.vv_record_conveyance(uuid, uuid, timestamptz, text, text, text, text, text, text, text, text);
drop table public.vv_conveyances;
drop function public.vv_save_equipment(uuid, uuid, text, text, text, text, text, text, date, text, text, text);
drop table public.vv_equipment;
drop function public.vv_record_contractor_audit(uuid, uuid, uuid, date, text, text, date);
drop function public.vv_save_contractor(uuid, uuid, text, text, text, text, uuid[], text);
drop table public.vv_contractor_audits;
drop table public.vv_contractor_sites;
drop table public.vv_contractors;
drop function public.vv_withdraw_competence(uuid, text);
drop function public.vv_save_competence(uuid, uuid, text, uuid, text, text, date, date, text, text);
drop table public.vv_competence;
drop function public.vv_today();
alter table public.vv_events drop constraint vv_events_record_type_check;
alter table public.vv_events add constraint vv_events_record_type_check check (record_type in ('programme', 'site', 'trap', 'council_taxon',
  'council_trap_type', 'deployment', 'visit', 'sample', 'result', 'assessment', 'action', 'incursion', 'notify_contact',
  'inspection', 'survey', 'pathogen_test', 'control_action'));
alter table public.vv_sites add constraint vv_sites_poe_zone_check
  check (site_type not in ('port', 'airport', 'ground_crossing') or zone_m >= 400);
commit;
