// Analytics (plan V-D14, phase V5). Every figure is worked out here from the
// records the person can already read (the database's row rules decide which),
// never typed in and never stored. Nothing leaves the browser; no AI (B2).
// Dates are grouped by UK month (Europe/London).
import { db, must } from "@/lib/backend";
import type { Action, Deployment, Result, ResultStatus, ResultVersion, Sample, Visit } from "./api";

// ---------- loading (all pages, not just the first 1,000 rows) ----------------------------------
const PAGE = 1000, CAP = 50_000;
async function all<T>(make: (from: number, to: number) => PromiseLike<{ data: unknown; error: import("@supabase/supabase-js").PostgrestError | null }>) {
  const out: T[] = [];
  for (let from = 0; from < CAP; from += PAGE) {
    const rows = must(await make(from, from + PAGE - 1)) as T[];
    out.push(...rows);
    if (rows.length < PAGE) return { rows: out, capped: false };
  }
  return { rows: out, capped: true };
}

export type AnalyticsData = {
  deployments: Deployment[]; visits: Visit[]; samples: Sample[]; results: Result[]; versions: ResultVersion[];
  assessmentLinks: { assessment_id: string; result_id: string; created_at: string }[]; actions: Action[]; capped: boolean;
};

export async function loadAnalytics(ws: string): Promise<AnalyticsData> {
  const [d, v, s, r, rv, a, ar, ac] = await Promise.all([
    all<Deployment>((f, t) => db.from("vv_deployments").select("id, trap_id, site_id, latitude, longitude, placement, started_at, ended_at, end_reason, end_note, responsible_officer, visit_interval_days, created_by, recorded_at, ended_by").eq("workspace_id", ws).order("id").range(f, t)),
    all<Visit>((f, t) => db.from("vv_visits").select("id, deployment_id, site_id, occurred_at, recorded_at, officer_id, outcome, not_completed_reason, trap_condition, observations, exposure_started_at, exposure_ended_at, created_by, updated_by, updated_at").eq("workspace_id", ws).order("id").range(f, t)),
    all<Sample>((f, t) => db.from("vv_samples").select("id, visit_id, site_id, reference, method, notes, status, created_by, recorded_at").eq("workspace_id", ws).order("id").range(f, t)),
    all<Result>((f, t) => db.from("vv_results").select("id, sample_id, site_id, current_version, created_by, created_at").eq("workspace_id", ws).order("id").range(f, t)),
    all<ResultVersion>((f, t) => db.from("vv_result_versions").select("result_id, version, status, taxon_id, council_taxon_id, quantity, unit, method, identified_by, laboratory, lab_reference, result_date, uncertainty, reason, author_id, author_role, recorded_at").eq("workspace_id", ws).order("result_id").order("version").range(f, t)),
    all<{ id: string; created_at: string }>((f, t) => db.from("vv_assessments").select("id, created_at").eq("workspace_id", ws).order("id").range(f, t)),
    all<{ assessment_id: string; result_id: string }>((f, t) => db.from("vv_assessment_results").select("assessment_id, result_id").eq("workspace_id", ws).order("assessment_id").order("result_id").range(f, t)),
    all<Action>((f, t) => db.from("vv_actions").select("id, site_id, assessment_id, title, detail, owner_id, due_on, status, completion_note, completed_by, completed_at, created_by, created_at").eq("workspace_id", ws).order("id").range(f, t)),
  ]);
  const created = new Map(a.rows.map((x) => [x.id, x.created_at]));
  return {
    deployments: d.rows, visits: v.rows, samples: s.rows, results: r.rows,
    versions: rv.rows.map((x) => ({ ...x, quantity: x.quantity === null ? null : Number(x.quantity) })),
    assessmentLinks: ar.rows.map((x) => ({ ...x, created_at: created.get(x.assessment_id) ?? "" })).filter((x) => x.created_at),
    actions: ac.rows, capped: [d, v, s, r, rv, a, ar, ac].some((x) => x.capped),
  };
}

// ---------- filters ---------------------------------------------------------------------------
export type Filter = { from: string; to: string; sites: Set<string> | null }; // from/to: YYYY-MM-DD (UK dates, inclusive); sites: null = all visible
const DAY = 86_400_000;
/** Start of a UK calendar day as a timestamp (handles BST). */
export function ukDayStart(ymd: string): number {
  const [y, m, d] = ymd.split("-").map(Number) as [number, number, number];
  const guess = Date.UTC(y, m - 1, d);
  const offsetMin = (t: number) => {
    const p = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/London", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(new Date(t));
    const h = Number(p.find((x) => x.type === "hour")?.value), mi = Number(p.find((x) => x.type === "minute")?.value);
    return (h * 60 + mi + 12 * 60) % (24 * 60) - 12 * 60; // London clock at 00:00 UTC is 00:00 or 01:00
  };
  return guess - offsetMin(guess) * 60_000;
}
const range = (f: Filter) => ({ start: ukDayStart(f.from), end: ukDayStart(f.to) + DAY });
const inRange = (iso: string | null | undefined, f: Filter) => { if (!iso) return false; const t = Date.parse(iso); const r = range(f); return t >= r.start && t < r.end; };
const siteOk = (site: string, f: Filter) => !f.sites || f.sites.has(site);

/** "2026-10" for a timestamp, in UK time. */
export function monthKey(iso: string): string {
  const p = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/London", year: "numeric", month: "2-digit" }).formatToParts(new Date(iso));
  return `${p.find((x) => x.type === "year")?.value}-${p.find((x) => x.type === "month")?.value}`;
}
/** Every month from the filter's start to its end, so empty months still show. */
export function monthsIn(f: Filter): string[] {
  const out: string[] = [];
  let [y, m] = f.from.slice(0, 7).split("-").map(Number) as [number, number];
  const last = f.to.slice(0, 7);
  for (let i = 0; i < 240; i++) {
    const k = `${y}-${String(m).padStart(2, "0")}`;
    out.push(k);
    if (k >= last) break;
    m++; if (m > 12) { m = 1; y++; }
  }
  return out;
}
export const monthLabel = (k: string) => new Date(`${k}-15T12:00:00Z`).toLocaleDateString("en-GB", { month: "short", year: "numeric" });

// ---------- 1. Effort and coverage ------------------------------------------------------------------
export type Effort = {
  trapNights: number; visitsPlanned: number; visitsDone: number; completed: number; notCompleted: number; missed: number;
  byMonth: { month: string; trapNights: number; visits: number }[];
  bySite: Map<string, { trapNights: number; visits: number; planned: number }>;
};
/**
 * Trap-nights: nights each deployment was out within the period (from deployment dates; an open
 * deployment counts up to now). Planned visits: whole visit intervals within that time. Missed:
 * planned minus visits recorded, per deployment, never below zero.
 */
export function effort(d: AnalyticsData, f: Filter, now = Date.now()): Effort {
  const r = range(f), end = Math.min(r.end, now);
  const months = new Map(monthsIn(f).map((m) => [m, { month: m, trapNights: 0, visits: 0 }]));
  const bySite = new Map<string, { trapNights: number; visits: number; planned: number }>();
  const site = (id: string) => { let x = bySite.get(id); if (!x) { x = { trapNights: 0, visits: 0, planned: 0 }; bySite.set(id, x); } return x; };
  let trapNights = 0, planned = 0, missed = 0;
  const visitsByDep = new Map<string, number>();
  for (const v of d.visits) if (siteOk(v.site_id, f) && inRange(v.occurred_at, f)) visitsByDep.set(v.deployment_id, (visitsByDep.get(v.deployment_id) ?? 0) + 1);
  for (const dep of d.deployments) {
    if (!siteOk(dep.site_id, f)) continue;
    const a = Math.max(Date.parse(dep.started_at), r.start), b = Math.min(dep.ended_at ? Date.parse(dep.ended_at) : now, end);
    if (b <= a) continue;
    const nights = Math.floor((b - a) / DAY);
    trapNights += nights; site(dep.site_id).trapNights += nights;
    // Spread nights over the months they fall in.
    for (let t = a; t + DAY <= b; t += DAY) { const m = months.get(monthKey(new Date(t).toISOString())); if (m) m.trapNights++; }
    const p = Math.floor(nights / Math.max(1, dep.visit_interval_days));
    planned += p; site(dep.site_id).planned += p;
    missed += Math.max(0, p - (visitsByDep.get(dep.id) ?? 0));
  }
  let done = 0, completed = 0, notCompleted = 0;
  for (const v of d.visits) {
    if (!siteOk(v.site_id, f) || !inRange(v.occurred_at, f)) continue;
    done++; if (v.outcome === "not_completed") notCompleted++; else completed++;
    site(v.site_id).visits++;
    const m = months.get(monthKey(v.occurred_at)); if (m) m.visits++;
  }
  return { trapNights, visitsPlanned: planned, visitsDone: done, completed, notCompleted, missed, byMonth: [...months.values()], bySite };
}

// ---------- 2. Findings over time --------------------------------------------------------------------
export type FindingRow = { result_id: string; site_id: string; sample_id: string; collected_at: string; status: ResultStatus; taxon: string; quantity: number | null };
/** Current version of each result, dated by when its sample was collected (the visit). */
export function currentFindings(d: AnalyticsData, f: Filter, taxonOf: (v: ResultVersion) => string): FindingRow[] {
  const visitOf = new Map(d.visits.map((v) => [v.id, v]));
  const sampleOf = new Map(d.samples.map((s) => [s.id, s]));
  const out: FindingRow[] = [];
  for (const r of d.results) {
    if (!siteOk(r.site_id, f)) continue;
    const v = d.versions.find((x) => x.result_id === r.id && x.version === r.current_version);
    const s = sampleOf.get(r.sample_id), visit = s && visitOf.get(s.visit_id);
    if (!v || !visit || !inRange(visit.occurred_at, f)) continue;
    out.push({ result_id: r.id, site_id: r.site_id, sample_id: r.sample_id, collected_at: visit.occurred_at, status: v.status, taxon: taxonOf(v), quantity: v.quantity });
  }
  return out;
}
export const isPositive = (s: ResultStatus) => s === "provisional" || s === "confirmed";

export type Findings = {
  samples: number; samplesResulted: number; samplesPositive: number; positivity: number | null;
  byMonth: { month: string; samples: number; positive: number }[];
  bySpecies: { taxon: string; findings: number; confirmed: number; sites: number }[];
  bySite: Map<string, { findings: number; samples: number }>;
};
/** Positivity: samples with at least one provisional or confirmed finding, out of samples with a final result (none pending). */
export function findings(d: AnalyticsData, f: Filter, rows: FindingRow[]): Findings {
  const visitOf = new Map(d.visits.map((v) => [v.id, v]));
  const samples = d.samples.filter((s) => siteOk(s.site_id, f) && inRange(visitOf.get(s.visit_id)?.occurred_at, f));
  const bySample = new Map<string, FindingRow[]>();
  for (const r of rows) bySample.set(r.sample_id, [...(bySample.get(r.sample_id) ?? []), r]);
  const resulted = samples.filter((s) => { const rs = bySample.get(s.id) ?? []; return rs.length > 0 && rs.every((x) => x.status !== "pending"); });
  const positive = resulted.filter((s) => (bySample.get(s.id) ?? []).some((x) => isPositive(x.status)));
  const months = new Map(monthsIn(f).map((m) => [m, { month: m, samples: 0, positive: 0 }]));
  for (const s of samples) { const m = months.get(monthKey(visitOf.get(s.visit_id)!.occurred_at)); if (m) m.samples++; }
  for (const s of positive) { const m = months.get(monthKey(visitOf.get(s.visit_id)!.occurred_at)); if (m) m.positive++; }
  const species = new Map<string, { taxon: string; findings: number; confirmed: number; sites: Set<string> }>();
  const bySite = new Map<string, { findings: number; samples: number }>();
  for (const s of samples) { const x = bySite.get(s.site_id) ?? { findings: 0, samples: 0 }; x.samples++; bySite.set(s.site_id, x); }
  for (const r of rows.filter((x) => isPositive(x.status))) {
    const x = species.get(r.taxon) ?? { taxon: r.taxon, findings: 0, confirmed: 0, sites: new Set<string>() };
    x.findings++; if (r.status === "confirmed") x.confirmed++; x.sites.add(r.site_id); species.set(r.taxon, x);
    const y = bySite.get(r.site_id) ?? { findings: 0, samples: 0 }; y.findings++; bySite.set(r.site_id, y);
  }
  return {
    samples: samples.length, samplesResulted: resulted.length, samplesPositive: positive.length,
    positivity: resulted.length ? positive.length / resulted.length : null,
    byMonth: [...months.values()],
    bySpecies: [...species.values()].map((x) => ({ taxon: x.taxon, findings: x.findings, confirmed: x.confirmed, sites: x.sites.size })).sort((a, b) => b.findings - a.findings),
    bySite,
  };
}

// ---------- 4. Response performance ---------------------------------------------------------------
export type Spread = { n: number; median: number | null; min: number | null; max: number | null };
export function spread(days: number[]): Spread {
  if (!days.length) return { n: 0, median: null, min: null, max: null };
  const s = [...days].sort((a, b) => a - b), mid = Math.floor(s.length / 2);
  return { n: s.length, median: s.length % 2 ? s[mid]! : (s[mid - 1]! + s[mid]!) / 2, min: s[0]!, max: s[s.length - 1]! };
}
const daysBetween = (a: string, b: string) => Math.max(0, (Date.parse(b) - Date.parse(a)) / DAY);

export type Performance = {
  collectionToResult: Spread; resultToAssessment: Spread; collectionToAssessment: Spread;
  actions: { doneOnTime: number; doneLate: number; doneNoDue: number; openOverdue: number; openInTime: number; cancelled: number };
};
/**
 * Collection → result: from the visit to the first provisional, confirmed or inconclusive version.
 * Result → assessment: from that first result to the first assessment covering it (positive findings only).
 * Actions: due within the period (or created in it when no due date).
 */
export function performance(d: AnalyticsData, f: Filter, today = new Date().toISOString().slice(0, 10)): Performance {
  const visitOf = new Map(d.visits.map((v) => [v.id, v]));
  const sampleOf = new Map(d.samples.map((s) => [s.id, s]));
  const c2r: number[] = [], r2a: number[] = [], c2a: number[] = [];
  for (const r of d.results) {
    if (!siteOk(r.site_id, f)) continue;
    const s = sampleOf.get(r.sample_id), visit = s && visitOf.get(s.visit_id);
    if (!visit || !inRange(visit.occurred_at, f)) continue;
    const first = d.versions.filter((v) => v.result_id === r.id && v.status !== "pending").sort((a, b) => a.version - b.version)[0];
    if (!first) continue;
    c2r.push(daysBetween(visit.occurred_at, first.recorded_at));
    if (!d.versions.some((v) => v.result_id === r.id && isPositive(v.status))) continue;
    const assessed = d.assessmentLinks.filter((l) => l.result_id === r.id).map((l) => l.created_at).sort()[0];
    if (assessed) { r2a.push(daysBetween(first.recorded_at, assessed)); c2a.push(daysBetween(visit.occurred_at, assessed)); }
  }
  const a = { doneOnTime: 0, doneLate: 0, doneNoDue: 0, openOverdue: 0, openInTime: 0, cancelled: 0 };
  for (const x of d.actions) {
    if (!siteOk(x.site_id, f)) continue;
    const when = x.due_on ? `${x.due_on}T12:00:00Z` : x.created_at;
    if (!inRange(when, f)) continue;
    if (x.status === "cancelled") a.cancelled++;
    else if (x.status === "done") { if (!x.due_on) a.doneNoDue++; else if (ukDate(x.completed_at!) <= x.due_on) a.doneOnTime++; else a.doneLate++; }
    else if (x.due_on && x.due_on < today) a.openOverdue++;
    else a.openInTime++;
  }
  return { collectionToResult: spread(c2r), resultToAssessment: spread(r2a), collectionToAssessment: spread(c2a), actions: a };
}
/** UK calendar date (YYYY-MM-DD) of a timestamp. */
export function ukDate(iso: string): string {
  const p = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/London", year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date(iso));
  return `${p.find((x) => x.type === "year")?.value}-${p.find((x) => x.type === "month")?.value}-${p.find((x) => x.type === "day")?.value}`;
}

export const fmtDays = (n: number | null) => (n === null ? "—" : n < 1 ? `${Math.round(n * 24)} h` : `${n.toFixed(n < 10 ? 1 : 0)} days`);
export const pct = (x: number | null) => (x === null ? "—" : `${Math.round(x * 100)}%`);
