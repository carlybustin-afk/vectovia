-- =====================================================================
-- VECTOVIA — v2-005: compliance and dashboards (design v2 build stage 5).
--   * Site status: one summary row per site (compliance, traps, checks, plan, risk, finds, surveys, incursions).
--   * Organisation view: the status of every site the person can see.
--   * National view: named sites across all organisations, read-only, for people the platform owner
--     names as national viewers (design §3: probably UKHSA). No table is opened to them: they see only
--     what vv_national_sites() returns, never organisations' records, people or history.
--   * Anonymous benchmarking: an organisation's figures against the average of other organisations'
--     sites of the same kind, shown only when at least 5 such sites from at least 3 other organisations
--     contribute (design §14 decision 4, plus the 3-organisation rule).
-- STATUS: APPLIED 2026-11-01 to vectovia-mvp (widvaahmcqanxezfhjqd), with owner approval.
-- =====================================================================

-- ---------- National viewers ---------------------------------------------------------------------
create table public.vv_national_viewers (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  body           text not null check (char_length(body) between 2 and 120),
  granted_by     uuid not null,
  granted_at     timestamptz not null default now(),
  revoked_by     uuid,
  revoked_at     timestamptz,
  revoked_reason text check (char_length(revoked_reason) <= 500),
  check ((revoked_at is null) = (revoked_by is null) and (revoked_at is null) = (revoked_reason is null))
);
create trigger vv_national_viewers_immutable before update on public.vv_national_viewers
  for each row execute function public.guard_immutable('user_id', 'granted_by', 'granted_at');
create trigger vv_national_viewers_no_delete before delete on public.vv_national_viewers for each row execute function public.forbid_update();

create function public.vv_is_national() returns boolean
  language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.vv_national_viewers where user_id = auth.uid() and revoked_at is null)
$$;

-- The platform owner names national viewers (granting again after a revoke is a fresh grant).
create function public.vv_grant_national(_user uuid, _body text) returns void
  language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from auth.users where id = _user) then raise exception 'unknown user' using errcode = '22023'; end if;
  if exists (select 1 from public.vv_national_viewers where user_id = _user and revoked_at is null) then return; end if;
  if exists (select 1 from public.vv_national_viewers where user_id = _user) then
    raise exception 'this person had national access before; ask for it to be restored through set-up' using errcode = '22023';
  end if;
  insert into public.vv_national_viewers (user_id, body, granted_by) values (_user, trim(_body), auth.uid());
  perform public.write_audit(null, 'vv_national.granted', _user, jsonb_build_object('body', trim(_body)));
end $$;

create function public.vv_revoke_national(_user uuid, _reason text) returns void
  language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  if char_length(trim(coalesce(_reason, ''))) < 5 then raise exception 'give a reason' using errcode = '22023'; end if;
  update public.vv_national_viewers set revoked_by = auth.uid(), revoked_at = now(), revoked_reason = trim(_reason)
   where user_id = _user and revoked_at is null;
  if found then perform public.write_audit(null, 'vv_national.revoked', _user, jsonb_build_object('reason', trim(_reason))); end if;
end $$;

create function public.vv_national_viewer_list() returns table(user_id uuid, email text, body text, granted_at timestamptz, revoked_at timestamptz)
  language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return query select n.user_id, u.email::text, n.body, n.granted_at, n.revoked_at
    from public.vv_national_viewers n join auth.users u on u.id = n.user_id order by n.granted_at desc;
end $$;

-- Seasons count for the national view and benchmarking too (they work out every site's schedule).
-- 'vectovia.internal' is set only inside the two functions below, for their own transaction.
create or replace function public.vv_site_season(_site uuid, _d date, out interval_days integer, out season_start date)
  language plpgsql stable security definer set search_path = '' as $$
begin
  if not (public.vv_can_see_site(_site) or public.vv_is_national() or coalesce(current_setting('vectovia.internal', true), '') = 'on') then
    interval_days := null; season_start := null; return;
  end if;
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

-- ---------- Site status --------------------------------------------------------------------------
-- One summary row for a site. Security invoker: for an organisation member, row level security
-- decides what it sees; the national and benchmark functions call it with full access.
create function public.vv_site_status(_site uuid) returns table(site_id uuid, requirements integer, met integer, partly integer, not_met integer,
    not_assessed integer, not_applicable integer, active_traps integer, overdue_checks integer, due_checks integer, plan_current boolean, risk_current boolean,
    invasive_awaiting integer, positives_12m integer, invasive_12m integer, open_surveys integer, open_incursions integer)
  language plpgsql stable set search_path = '' as $$
declare s public.vv_sites; today date := (now() at time zone 'Europe/London')::date;
begin
  select * into s from public.vv_sites x where x.id = _site;
  if s.id is null then return; end if;
  site_id := s.id;
  select count(*)::int, count(*) filter (where c.status = 'green')::int, count(*) filter (where c.status = 'amber')::int,
         count(*) filter (where c.status = 'red')::int, count(*) filter (where c.status = 'not_assessed')::int, count(*) filter (where c.status = 'not_applicable')::int
    into requirements, met, partly, not_met, not_assessed, not_applicable
    from public.vv_site_compliance(_site) c;
  select count(*)::int, count(*) filter (where v.state = 'overdue')::int, count(*) filter (where v.state = 'due')::int
    into active_traps, overdue_checks, due_checks
    from public.vv_visit_schedule(s.workspace_id) v where v.site_id = _site;
  plan_current := exists (select 1 from public.vv_site_plan_versions pv join public.vv_site_plans p on p.id = pv.plan_id
                           where p.site_id = _site and pv.approved_at is not null and pv.review_by >= today);
  risk_current := coalesce((select rv.next_due >= today from public.vv_site_risk_versions rv join public.vv_site_risk k on k.id = rv.risk_id
                             where k.site_id = _site order by rv.version desc limit 1), false);
  select count(*) filter (where rv.status = 'provisional' and t.invasive)::int,
         count(*) filter (where rv.status in ('provisional', 'confirmed') and rv.recorded_at > now() - interval '365 days')::int,
         count(*) filter (where rv.status in ('provisional', 'confirmed') and t.invasive and rv.recorded_at > now() - interval '365 days')::int
    into invasive_awaiting, positives_12m, invasive_12m
    from public.vv_results r
    join public.vv_result_versions rv on rv.result_id = r.id and rv.version = r.current_version
    left join public.vv_taxa t on t.id = rv.taxon_id
   where r.site_id = _site;
  open_surveys := (select count(*)::int from public.vv_surveys v where v.site_id = _site and v.ended_on is null);
  open_incursions := (select count(*)::int from public.vv_incursions i where i.site_id = _site and i.status <> 'stood_down');
  return next;
end $$;

-- The organisation view: every active site the person can see in their organisation.
create function public.vv_org_site_status(_ws uuid) returns table(site_id uuid, requirements integer, met integer, partly integer, not_met integer,
    not_assessed integer, not_applicable integer, active_traps integer, overdue_checks integer, due_checks integer, plan_current boolean, risk_current boolean,
    invasive_awaiting integer, positives_12m integer, invasive_12m integer, open_surveys integer, open_incursions integer)
  language sql stable set search_path = '' as $$
  select st.* from public.vv_sites s cross join lateral public.vv_site_status(s.id) st
   where s.workspace_id = _ws and s.status = 'active' order by s.reference
$$;

-- ---------- National view ------------------------------------------------------------------------
create function public.vv_national_sites() returns table(organisation text, site_reference text, site_name text, site_type text,
    latitude double precision, longitude double precision, zone_m integer, obligation_sets text, requirements integer, met integer, partly integer,
    not_met integer, not_assessed integer, active_traps integer, overdue_checks integer, plan_current boolean, risk_current boolean,
    invasive_awaiting integer, positives_12m integer, invasive_12m integer, open_surveys integer, open_incursions integer)
  language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.vv_is_national() then raise exception 'not allowed' using errcode = '42501'; end if;
  perform set_config('vectovia.internal', 'on', true);
  return query
    select w.name, s.reference, s.name, s.site_type, s.latitude, s.longitude, s.zone_m,
           (select string_agg(os.name, '; ' order by os.sort_order) from public.vv_site_obligations so join public.vv_obligation_sets os on os.id = so.set_id
             where so.site_id = s.id and so.removed_at is null),
           st.requirements, st.met, st.partly, st.not_met, st.not_assessed, st.active_traps, st.overdue_checks, st.plan_current, st.risk_current,
           st.invasive_awaiting, st.positives_12m, st.invasive_12m, st.open_surveys, st.open_incursions
      from public.vv_sites s
      join public.workspaces w on w.id = s.workspace_id
      cross join lateral public.vv_site_status(s.id) st
     where s.status = 'active' and w.kind = 'organisation'
     order by w.name, s.reference;
  perform set_config('vectovia.internal', 'off', true);
end $$;

-- ---------- Anonymous benchmarking ---------------------------------------------------------------------
-- For each kind of site (points of entry; other sites) and each measure: the organisation's own value
-- and the average across OTHER organisations' active sites of that kind. The benchmark is withheld
-- (null) unless at least 5 such sites from at least 3 other organisations contribute, so no single
-- organisation can be picked out.
-- Never returns any per-site or per-organisation figures.
create function public.vv_benchmarks(_ws uuid) returns table(site_group text, measure text, your_sites integer, your_value numeric,
    benchmark_sites integer, benchmark_value numeric)
  language plpgsql stable security definer set search_path = '' as $$
declare min_sites constant int := 5; min_orgs constant int := 3;
begin
  if not public.vv_has(_ws, array['view', 'field', 'manage']) then raise exception 'not allowed' using errcode = '42501'; end if;
  perform set_config('vectovia.internal', 'on', true);
  return query
    with base as (
      select s.workspace_id = _ws as mine, s.workspace_id as org,
             case when s.site_type in ('port', 'airport', 'ground_crossing') then 'point_of_entry' else 'other' end as grp,
             st.*
        from public.vv_sites s
        join public.workspaces w on w.id = s.workspace_id and w.kind = 'organisation'
        cross join lateral public.vv_site_status(s.id) st
       where s.status = 'active'
    ),
    m as (
      select b.mine, b.org, b.grp, 'requirements_met'::text as measure,
             case when b.requirements - b.not_applicable > 0 then b.met::numeric / (b.requirements - b.not_applicable) end as v from base b
      union all
      select b.mine, b.org, b.grp, 'checks_on_time', case when b.active_traps > 0 then (b.overdue_checks = 0)::int::numeric end from base b
      union all
      select b.mine, b.org, b.grp, 'plan_current', b.plan_current::int::numeric from base b
      union all
      select b.mine, b.org, b.grp, 'risk_current', b.risk_current::int::numeric from base b
    ),
    agg as (
      select g.grp, g.measure,
             count(*) filter (where g.mine and g.v is not null)::int as ys,
             avg(g.v) filter (where g.mine) as yv,
             count(*) filter (where not g.mine and g.v is not null)::int as bs,
             count(distinct g.org) filter (where not g.mine and g.v is not null)::int as bo,
             avg(g.v) filter (where not g.mine) as bv
        from m g group by g.grp, g.measure
    )
    select a.grp, a.measure, a.ys, round(a.yv * 100, 0),
           case when a.bs >= min_sites and a.bo >= min_orgs then a.bs end,
           case when a.bs >= min_sites and a.bo >= min_orgs then round(a.bv * 100, 0) end
      from agg a
     where a.ys > 0
     order by a.grp, a.measure;
  perform set_config('vectovia.internal', 'off', true);
end $$;

-- ---------- Row level security and grants --------------------------------------------------------
alter table public.vv_national_viewers enable row level security;
create policy vv_national_viewers_self on public.vv_national_viewers for select to authenticated using (user_id = auth.uid());
revoke all on table public.vv_national_viewers from anon, authenticated;
grant select on table public.vv_national_viewers to authenticated;
grant all on table public.vv_national_viewers to service_role;

revoke all on function public.vv_is_national() from public, anon, authenticated;
revoke all on function public.vv_grant_national(uuid, text) from public, anon, authenticated;
revoke all on function public.vv_revoke_national(uuid, text) from public, anon, authenticated;
revoke all on function public.vv_national_viewer_list() from public, anon, authenticated;
revoke all on function public.vv_site_status(uuid) from public, anon, authenticated;
revoke all on function public.vv_org_site_status(uuid) from public, anon, authenticated;
revoke all on function public.vv_national_sites() from public, anon, authenticated;
revoke all on function public.vv_benchmarks(uuid) from public, anon, authenticated;

grant execute on function public.vv_is_national() to authenticated, service_role;
grant execute on function public.vv_grant_national(uuid, text) to authenticated, service_role;
grant execute on function public.vv_revoke_national(uuid, text) to authenticated, service_role;
grant execute on function public.vv_national_viewer_list() to authenticated, service_role;
grant execute on function public.vv_site_status(uuid) to authenticated, service_role;
grant execute on function public.vv_org_site_status(uuid) to authenticated, service_role;
grant execute on function public.vv_national_sites() to authenticated, service_role;
grant execute on function public.vv_benchmarks(uuid) to authenticated, service_role;
