// Sites (boundary, zone, areas, sharing) and obligation sets (v2-002). Every read goes through RLS;
// every write is a checked database function. Client-generated ids keep saves retry-safe.
import { db, must } from "@/lib/backend";
import type { Polygon } from "./geo";

export type SiteType = "port" | "airport" | "ground_crossing" | "service_station" | "truck_stop" | "inland_border" | "international_rail" | "community" | "other";
export const siteTypeLabels: Record<SiteType, string> = {
  port: "Port", airport: "Airport", ground_crossing: "Ground crossing", service_station: "Highway service station", truck_stop: "Truck stop",
  inland_border: "Inland border facility", international_rail: "International rail station", community: "Community (modelled risk)", other: "Other",
};
export const pointOfEntryTypes: SiteType[] = ["port", "airport", "ground_crossing"];

export type AreaKind = "terminal" | "cargo" | "external" | "service_provider" | "other";
export const areaKindLabels: Record<AreaKind, string> = {
  terminal: "Terminal", cargo: "Cargo", external: "External area", service_provider: "Service provider", other: "Other",
};
export type SiteArea = { id: string; site_id: string; kind: AreaKind; name: string; boundary: Polygon | null; updated_at: string };

export async function loadAreas(ws: string): Promise<SiteArea[]> {
  return must(await db.from("vv_site_areas").select("id, site_id, kind, name, boundary, updated_at")
    .eq("workspace_id", ws).is("removed_at", null).order("name")) as SiteArea[];
}

export type SharedMember = { group_id: string; is_lead: boolean; is_you: boolean; organisation: string; site_name: string; site_type: SiteType;
  boundary: Polygon | null; zone_m: number; areas: { kind: AreaKind; name: string; boundary: Polygon | null }[] };
export async function loadShared(site: string): Promise<SharedMember[]> {
  return must(await db.rpc("vv_shared_site", { _site: site })) as SharedMember[];
}

export type ObligationSet = { id: string; key: string; name: string; framework: "ihr" | "national_guidance" | "other"; jurisdiction: string; applies_to: SiteType[]; sort_order: number };
export type ObligationVersion = { id: string; set_id: string; version: number; summary: string; sources: { title: string; url: string }[];
  status: "draft" | "in_review" | "reviewed" | "published" | "superseded" | "rejected" | "withdrawn";
  loaded_by: string | null; reviewer_id: string | null; reviewed_at: string | null; review_note: string | null; publisher_id: string | null; published_at: string | null };
export type CheckKind = "assessment" | "zone" | "checks" | "official_id" | "records";
export type Requirement = { id: string; version_id: string; key: string; sort_order: number; title: string; what: string; frequency: string | null;
  evidence: string | null; check_kind: CheckKind; mandatory: boolean; source_ref: string | null };

/** Sets, the versions this person may see (published for everyone; drafts for the content team) and their requirements. */
export async function loadObligations() {
  const [s, v, r] = await Promise.all([
    db.from("vv_obligation_sets").select("id, key, name, framework, jurisdiction, applies_to, sort_order").order("sort_order"),
    db.from("vv_obligation_versions").select("id, set_id, version, summary, sources, status, loaded_by, reviewer_id, reviewed_at, review_note, publisher_id, published_at").order("version", { ascending: false }),
    db.from("vv_obligation_requirements").select("id, version_id, key, sort_order, title, what, frequency, evidence, check_kind, mandatory, source_ref").order("sort_order"),
  ]);
  return { sets: must(s) as ObligationSet[], versions: must(v) as ObligationVersion[], requirements: must(r) as Requirement[] };
}
export type Obligations = Awaited<ReturnType<typeof loadObligations>>;
export const publishedVersion = (o: Obligations, setId: string) => o.versions.find((v) => v.set_id === setId && v.status === "published");

export type SiteObligation = { id: string; site_id: string; set_id: string; version_id: string; adopted_at: string; updated_at: string | null };
export async function loadSiteObligations(ws: string): Promise<SiteObligation[]> {
  return must(await db.from("vv_site_obligations").select("id, site_id, set_id, version_id, adopted_at, updated_at")
    .eq("workspace_id", ws).is("removed_at", null)) as SiteObligation[];
}

export type Rag = "green" | "amber" | "red" | "not_applicable" | "not_assessed";
export type ComplianceRow = { site_obligation_id: string; set_key: string; set_name: string; version: number; requirement_key: string; sort_order: number;
  title: string; mandatory: boolean; check_kind: CheckKind; status: Rag; detail: string; assessed_at: string | null; review_by: string | null };
export async function loadCompliance(site: string): Promise<ComplianceRow[]> {
  return must(await db.rpc("vv_site_compliance", { _site: site })) as ComplianceRow[];
}

/** Plain words and a shape for each status: never colour alone. */
export const ragLabels: Record<Rag, { label: string; mark: string; tone: string }> = {
  green: { label: "Met", mark: "✓", tone: "bg-secondary text-primary border-border" },
  amber: { label: "Partly met", mark: "◐", tone: "bg-accent/20 text-primary border-accent" },
  red: { label: "Not met", mark: "✕", tone: "bg-primary text-primary-foreground border-primary" },
  not_assessed: { label: "Not assessed", mark: "?", tone: "bg-background text-muted-foreground border-dashed border-border" },
  not_applicable: { label: "Not applicable", mark: "–", tone: "bg-background text-muted-foreground border-border" },
};
export const checkKindLabels: Record<CheckKind, string> = {
  assessment: "Assessed by a manager", zone: "Worked out from the boundary and traps", checks: "Worked out from the check schedule",
  official_id: "Worked out from finds", records: "Worked out from the system",
};
export function summarise(rows: ComplianceRow[]) {
  const n = (s: Rag) => rows.filter((r) => r.status === s).length;
  return { total: rows.length, green: n("green"), amber: n("amber"), red: n("red"), notAssessed: n("not_assessed"), notApplicable: n("not_applicable") };
}

export const obligationRpc = {
  saveGeometry: (site: string, type: SiteType, boundary: Polygon | null, zoneM: number, riskReason: string) =>
    db.rpc("vv_save_site_geometry", { _site: site, _site_type: type, _boundary: boundary, _zone_m: zoneM, _risk_reason: riskReason }),
  saveArea: (id: string, site: string, kind: AreaKind, name: string, boundary: Polygon | null) =>
    db.rpc("vv_save_site_area", { _id: id, _site: site, _kind: kind, _name: name, _boundary: boundary }),
  removeArea: (id: string, reason: string) => db.rpc("vv_remove_site_area", { _id: id, _reason: reason }),
  createShare: (site: string) => db.rpc("vv_create_site_share", { _site: site }),
  joinShare: (code: string, site: string) => db.rpc("vv_join_shared_site", { _code: code, _site: site }),
  leaveShare: (site: string, reason: string) => db.rpc("vv_leave_shared_site", { _site: site, _reason: reason }),
  adopt: (id: string, site: string, setKey: string) => db.rpc("vv_adopt_obligation_set", { _id: id, _site: site, _set_key: setKey }),
  removeObligation: (id: string, reason: string) => db.rpc("vv_remove_site_obligation", { _id: id, _reason: reason }),
  assess: (id: string, siteObligation: string, requirementKey: string, status: Exclude<Rag, "not_assessed">, note: string, reviewBy: string | null) =>
    db.rpc("vv_assess_requirement", { _id: id, _site_obligation: siteObligation, _requirement_key: requirementKey, _status: status, _note: note,
      _review_by: reviewBy, _attachment: null }),
  review: (version: string, approve: boolean, note: string) => db.rpc("vv_obl_review", { _version: version, _approve: approve, _note: note }),
  publish: (version: string) => db.rpc("vv_obl_publish", { _version: version }),
};
