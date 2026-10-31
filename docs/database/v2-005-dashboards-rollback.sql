-- Rollback for v2-005 (dashboards). Owner-run only. Removes the national view, status summaries and
-- benchmarking, and restores the v2-003 season rule. National viewer grants are removed with their table
-- (the audit events remain).
begin;
drop function public.vv_benchmarks(uuid);
drop function public.vv_national_sites();
drop function public.vv_org_site_status(uuid);
drop function public.vv_site_status(uuid);
create or replace function public.vv_site_season(_site uuid, _d date, out interval_days integer, out season_start date)
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
drop function public.vv_national_viewer_list();
drop function public.vv_revoke_national(uuid, text);
drop function public.vv_grant_national(uuid, text);
drop function public.vv_is_national();
drop table public.vv_national_viewers;
commit;
