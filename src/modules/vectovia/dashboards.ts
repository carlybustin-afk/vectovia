// Compliance and dashboards (v2-005): site and organisation status, the national view and anonymous
// benchmarking. Organisation figures go through RLS; the national view and benchmarks are checked
// database functions that never return another organisation's records.
import { useQuery } from "@tanstack/react-query";
import { db, must } from "@/lib/backend";
import { useSession } from "@/lib/session";
import { wsKey } from "@/lib/workspace";

export type SiteStatus = { site_id: string; requirements: number; met: number; partly: number; not_met: number; not_assessed: number; not_applicable: number;
  active_traps: number; overdue_checks: number; due_checks: number; plan_current: boolean; risk_current: boolean; invasive_awaiting: number;
  positives_12m: number; invasive_12m: number; open_surveys: number; open_incursions: number };

/** What needs attention at a site, most urgent first. Empty means nothing needs attention. */
type Attention = Pick<SiteStatus, "not_met" | "overdue_checks" | "invasive_awaiting" | "plan_current" | "risk_current" | "partly" | "not_assessed" | "open_incursions" | "requirements" | "active_traps"> & { due_checks?: number };
export function attentionOf(s: Attention): string[] {
  const out: string[] = [];
  if (s.open_incursions) out.push(`${s.open_incursions} incursion${s.open_incursions === 1 ? "" : "s"} open`);
  if (s.invasive_awaiting) out.push(`${s.invasive_awaiting} invasive find${s.invasive_awaiting === 1 ? "" : "s"} awaiting official ID`);
  if (s.overdue_checks) out.push(`${s.overdue_checks} check${s.overdue_checks === 1 ? "" : "s"} overdue`);
  if (s.not_met) out.push(`${s.not_met} requirement${s.not_met === 1 ? "" : "s"} not met`);
  if (!s.plan_current) out.push("No current approved plan");
  if (!s.risk_current) out.push("Risk assessment missing or overdue");
  if (!s.requirements) out.push("No obligation sets adopted");
  if (!s.active_traps) out.push("No active traps");
  if (s.partly) out.push(`${s.partly} partly met`);
  if (s.not_assessed) out.push(`${s.not_assessed} not assessed`);
  if (s.due_checks) out.push(`${s.due_checks} check${s.due_checks === 1 ? "" : "s"} due soon`);
  return out;
}
/** Red when anything is overdue, not met, or an invasive find or incursion is open; amber for the rest. */
export function siteRag(s: Attention): "red" | "amber" | "green" {
  if (s.open_incursions || s.invasive_awaiting || s.overdue_checks || s.not_met || !s.plan_current || !s.risk_current) return "red";
  return attentionOf(s).length ? "amber" : "green";
}

export const useOrgStatus = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "org-status"),
  queryFn: async () => must(await db.rpc("vv_org_site_status", { _ws: ws })) as SiteStatus[] });

export type Benchmark = { site_group: "point_of_entry" | "other"; measure: Measure; your_sites: number; your_value: number | null;
  benchmark_sites: number | null; benchmark_value: number | null };
export type Measure = "requirements_met" | "checks_on_time" | "plan_current" | "risk_current";
export const measureLabels: Record<Measure, string> = {
  requirements_met: "Requirements met", checks_on_time: "Sites with no overdue checks", plan_current: "Sites with a current approved plan",
  risk_current: "Sites with a current risk assessment",
};
export const siteGroupLabels: Record<Benchmark["site_group"], string> = { point_of_entry: "Points of entry", other: "Other sites" };
export const useBenchmarks = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "benchmarks"),
  queryFn: async () => must(await db.rpc("vv_benchmarks", { _ws: ws })) as Benchmark[] });

export type NationalSite = Omit<SiteStatus, "site_id" | "due_checks" | "not_applicable"> & { organisation: string; site_reference: string; site_name: string;
  site_type: string; latitude: number | null; longitude: number | null; zone_m: number; obligation_sets: string | null };

export function useIsNational() {
  const { session } = useSession();
  const uid = session?.user.id;
  return useQuery({ queryKey: ["vv-national", uid], enabled: !!uid, staleTime: 5 * 60_000,
    queryFn: async () => must(await db.rpc("vv_is_national")) as boolean }).data ?? false;
}
export const useNationalSites = (enabled: boolean) => useQuery({ queryKey: ["vv-national-sites"], enabled,
  queryFn: async () => must(await db.rpc("vv_national_sites")) as NationalSite[] });

export type NationalViewer = { user_id: string; email: string; body: string; granted_at: string; revoked_at: string | null };
export const nationalRpc = {
  list: async () => must(await db.rpc("vv_national_viewer_list")) as NationalViewer[],
  grant: (user: string, body: string) => db.rpc("vv_grant_national", { _user: user, _body: body }),
  revoke: (user: string, reason: string) => db.rpc("vv_revoke_national", { _user: user, _reason: reason }),
};

/** The national return as CSV: one row per named site. Text cells are quoted; formula-like text is neutralised. */
export function nationalCsv(rows: NationalSite[]): string {
  const cols: [string, (r: NationalSite) => string | number | boolean | null][] = [
    ["Organisation", (r) => r.organisation], ["Site reference", (r) => r.site_reference], ["Site", (r) => r.site_name], ["Site type", (r) => r.site_type],
    ["Latitude", (r) => r.latitude], ["Longitude", (r) => r.longitude], ["Zone (m)", (r) => r.zone_m], ["Obligation sets", (r) => r.obligation_sets],
    ["Requirements", (r) => r.requirements], ["Met", (r) => r.met], ["Partly met", (r) => r.partly], ["Not met", (r) => r.not_met], ["Not assessed", (r) => r.not_assessed],
    ["Active traps", (r) => r.active_traps], ["Overdue checks", (r) => r.overdue_checks], ["Plan current", (r) => r.plan_current], ["Risk assessment current", (r) => r.risk_current],
    ["Invasive finds awaiting official ID", (r) => r.invasive_awaiting], ["Positive finds (12 months)", (r) => r.positives_12m],
    ["Invasive finds (12 months)", (r) => r.invasive_12m], ["Open delimiting surveys", (r) => r.open_surveys], ["Open incursions", (r) => r.open_incursions],
  ];
  const cell = (v: string | number | boolean | null) => {
    if (v === null) return "";
    if (typeof v === "number") return String(v);
    if (typeof v === "boolean") return v ? "Yes" : "No";
    const t = /^[=+\-@\t\r]/.test(v) ? `'${v}` : v;
    return `"${t.replace(/"/g, '""')}"`;
  };
  return [cols.map(([h]) => cell(h)).join(","), ...rows.map((r) => cols.map(([, f]) => cell(f(r))).join(","))].join("\r\n");
}
