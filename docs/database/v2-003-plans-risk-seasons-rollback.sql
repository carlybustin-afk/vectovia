-- Rollback for v2-003 (plans, risk and seasons). Owner-run only. Removes seasons, templates, site plans
-- and site risk assessments (and their records), restores the v2-001 visit schedule and the v2-002
-- compliance check. Generated from those files so the restored definitions match them exactly.
-- Obligation requirements using the 'plan' or 'risk' checks must be removed or changed first.
begin;
CREATE OR REPLACE FUNCTION public.vv_visit_schedule(_ws uuid) RETURNS TABLE(deployment_id uuid, trap_id uuid, site_id uuid, started_at timestamp with time zone, responsible_officer uuid, visit_interval_days integer, last_visit_at timestamp with time zone, next_due_on date, state text)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  with base as (
    select d.id, d.trap_id, d.site_id, d.started_at, d.responsible_officer, d.visit_interval_days,
           (select max(v.occurred_at) from public.vv_visits v where v.deployment_id = d.id) as last_visit_at
      from public.vv_deployments d
     where d.workspace_id = _ws and d.ended_at is null
  )
  select b.id, b.trap_id, b.site_id, b.started_at, b.responsible_officer, b.visit_interval_days, b.last_visit_at,
         ((coalesce(b.last_visit_at, b.started_at) at time zone 'Europe/London')::date + b.visit_interval_days) as next_due_on,
         case
           when ((coalesce(b.last_visit_at, b.started_at) at time zone 'Europe/London')::date + b.visit_interval_days) < (now() at time zone 'Europe/London')::date then 'overdue'
           when ((coalesce(b.last_visit_at, b.started_at) at time zone 'Europe/London')::date + b.visit_interval_days) <= (now() at time zone 'Europe/London')::date + 2 then 'due'
           else 'scheduled'
         end
    from base b
   order by 8, 1
$$;

create or replace function public.vv_site_compliance(_site uuid) returns table(site_obligation_id uuid, set_key text, set_name text, version integer,
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

alter table public.vv_obligation_requirements drop constraint vv_obligation_requirements_check_kind_check;
alter table public.vv_obligation_requirements add constraint vv_obligation_requirements_check_kind_check
  check (check_kind in ('assessment', 'zone', 'checks', 'official_id', 'records'));

drop function public.vv_save_site_risk(uuid, uuid, uuid, date, date, integer, integer, text, text, text, text, text, text, text, text);
drop table public.vv_site_risk_versions;
drop table public.vv_site_risk;
drop function public.vv_record_plan_activity(uuid, uuid, text, date, text);
drop function public.vv_approve_plan(uuid, integer, date);
drop function public.vv_save_plan(uuid, uuid, uuid, uuid, text, jsonb, text);
drop table public.vv_plan_activity;
drop table public.vv_site_plan_versions;
drop function public.vv_guard_plan_version();
drop table public.vv_site_plans;
drop function public.vv_tpl_publish(uuid);
drop function public.vv_tpl_review(uuid, boolean, text);
drop table public.vv_template_versions;
drop table public.vv_templates;
drop function public.vv_valid_sections(jsonb, boolean);
drop function public.vv_site_season(uuid, date);
drop function public.vv_remove_season(uuid, text);
drop function public.vv_save_season(uuid, uuid, text, text, text, integer);
drop table public.vv_programme_seasons;
drop function public.vv_md_on_or_before(date, text);
drop function public.vv_md_in(date, text, text);
drop function public.vv_valid_md(text);
commit;
