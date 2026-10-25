// Plans and risk (v2-003): programme seasons, national templates, site surveillance plans and
// yearly site risk assessments. Reads go through RLS; writes are checked database functions.
import { db, must } from "@/lib/backend";
import type { Level } from "./api";

export type Season = { id: string; programme_id: string; name: string; starts_md: string; ends_md: string; interval_days: number };
export async function loadSeasons(ws: string): Promise<Season[]> {
  return must(await db.from("vv_programme_seasons").select("id, programme_id, name, starts_md, ends_md, interval_days")
    .eq("workspace_id", ws).is("removed_at", null).order("starts_md")) as Season[];
}

const months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
export const mdLabel = (md: string) => `${Number(md.slice(3))} ${months[Number(md.slice(0, 2)) - 1]}`;
export const monthOptions = months.map((m, i) => ({ value: String(i + 1).padStart(2, "0"), label: m }));
/** Days in a month for a yearly season (February allows 29). */
export const daysIn = (mm: string) => [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][Number(mm) - 1] ?? 31;

export type TemplateSection = { key: string; title: string; guidance?: string; required?: boolean };
export type Template = { id: string; key: string; kind: "surveillance_plan" | "risk_assessment"; name: string };
export type TemplateVersion = { id: string; template_id: string; version: number; summary: string; sections: TemplateSection[]; sources: { title: string; url: string }[];
  status: "draft" | "in_review" | "reviewed" | "published" | "superseded" | "rejected" | "withdrawn";
  loaded_by: string | null; reviewer_id: string | null; reviewed_at: string | null; review_note: string | null; published_at: string | null };
export async function loadTemplates() {
  const [t, v] = await Promise.all([
    db.from("vv_templates").select("id, key, kind, name").order("sort_order"),
    db.from("vv_template_versions").select("id, template_id, version, summary, sections, sources, status, loaded_by, reviewer_id, reviewed_at, review_note, published_at")
      .order("version", { ascending: false }),
  ]);
  return { templates: must(t) as Template[], versions: must(v) as TemplateVersion[] };
}

export type PlanSection = { key: string; title: string; text: string };
export type Plan = { id: string; site_id: string; template_version_id: string | null; current_version: number; created_at: string };
export type PlanVersion = { id: string; plan_id: string; version: number; title: string; sections: PlanSection[]; reason: string | null; author_id: string;
  author_role: string; recorded_at: string; approved_by: string | null; approved_at: string | null; review_by: string | null };
export type PlanActivity = { id: string; plan_id: string; kind: "review" | "exercise"; occurred_on: string; note: string; recorded_by: string; recorded_at: string };
export async function loadPlan(ws: string, site: string) {
  const plan = (must(await db.from("vv_site_plans").select("id, site_id, template_version_id, current_version, created_at")
    .eq("workspace_id", ws).eq("site_id", site).maybeSingle()) as Plan | null);
  if (!plan) return { plan: null, versions: [] as PlanVersion[], activity: [] as PlanActivity[] };
  const [v, a] = await Promise.all([
    db.from("vv_site_plan_versions").select("id, plan_id, version, title, sections, reason, author_id, author_role, recorded_at, approved_by, approved_at, review_by")
      .eq("plan_id", plan.id).order("version", { ascending: false }),
    db.from("vv_plan_activity").select("id, plan_id, kind, occurred_on, note, recorded_by, recorded_at").eq("plan_id", plan.id).order("occurred_on", { ascending: false }),
  ]);
  return { plan, versions: must(v) as PlanVersion[], activity: must(a) as PlanActivity[] };
}

export type SiteRiskVersion = { id: string; risk_id: string; version: number; assessed_on: string; next_due: string; likelihood: number; consequence: number;
  matrix_level: Level; final_level: Level; override_reason: string | null; vectors: string | null; pathways: string | null; habitats: string | null;
  controls: string | null; rationale: string; reason: string | null; author_id: string; author_role: string; recorded_at: string };
export async function loadSiteRisk(ws: string, site: string) {
  const risk = must(await db.from("vv_site_risk").select("id, current_version").eq("workspace_id", ws).eq("site_id", site).maybeSingle()) as { id: string; current_version: number } | null;
  if (!risk) return { risk: null, versions: [] as SiteRiskVersion[] };
  const v = must(await db.from("vv_site_risk_versions").select("id, risk_id, version, assessed_on, next_due, likelihood, consequence, matrix_level, final_level, override_reason, vectors, pathways, habitats, controls, rationale, reason, author_id, author_role, recorded_at")
    .eq("risk_id", risk.id).order("version", { ascending: false })) as SiteRiskVersion[];
  return { risk, versions: v };
}

export type SiteRiskInput = { assessed_on: string; next_due: string; likelihood: number; consequence: number; final_level: Level; override_reason: string;
  vectors: string; pathways: string; habitats: string; controls: string; rationale: string; reason: string };

export const planRpc = {
  saveSeason: (id: string, programme: string, name: string, starts: string, ends: string, interval: number) =>
    db.rpc("vv_save_season", { _id: id, _programme: programme, _name: name, _starts: starts, _ends: ends, _interval: interval }),
  removeSeason: (id: string, reason: string) => db.rpc("vv_remove_season", { _id: id, _reason: reason }),
  savePlan: (versionId: string, plan: string, site: string, templateVersion: string | null, title: string, sections: PlanSection[], reason: string) =>
    db.rpc("vv_save_plan", { _version_id: versionId, _plan: plan, _site: site, _template_version: templateVersion, _title: title, _sections: sections, _reason: reason }),
  approvePlan: (plan: string, version: number, reviewBy: string) => db.rpc("vv_approve_plan", { _plan: plan, _version: version, _review_by: reviewBy }),
  recordActivity: (id: string, plan: string, kind: "review" | "exercise", occurredOn: string, note: string) =>
    db.rpc("vv_record_plan_activity", { _id: id, _plan: plan, _kind: kind, _occurred_on: occurredOn, _note: note }),
  saveSiteRisk: (versionId: string, risk: string, site: string, v: SiteRiskInput) =>
    db.rpc("vv_save_site_risk", { _version_id: versionId, _risk: risk, _site: site, _assessed_on: v.assessed_on, _next_due: v.next_due || null,
      _likelihood: v.likelihood, _consequence: v.consequence, _final_level: v.final_level, _override_reason: v.override_reason, _vectors: v.vectors,
      _pathways: v.pathways, _habitats: v.habitats, _controls: v.controls, _rationale: v.rationale, _reason: v.reason }),
  reviewTemplate: (version: string, approve: boolean, note: string) => db.rpc("vv_tpl_review", { _version: version, _approve: approve, _note: note }),
  publishTemplate: (version: string) => db.rpc("vv_tpl_publish", { _version: version }),
};
