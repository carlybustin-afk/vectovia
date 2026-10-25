// Vectovia data access (plan V1). Calls Vectovia's own database contract
// (vv_ tables and functions) through the signed-in client: RLS decides every
// read; every write is a function that takes identity, role and time from the
// server. Module boundary: no case code, no case tables, no AI
// (src/test/vectovia-boundary.test.ts). Client-generated IDs: every save is retry-safe.
import { db, must } from "@/lib/backend";

export const newId = () => crypto.randomUUID();

export type Taxon = { id: string; key: string; scientific_name: string; common_name: string | null; invasive: boolean; checked: boolean; sort_order: number };
export type TrapType = { id: string; key: string; name: string; description: string | null; checked: boolean; sort_order: number };
export type CouncilTaxon = { id: string; scientific_name: string; common_name: string | null; active: boolean };
export type CouncilTrapType = { id: string; name: string; description: string | null; active: boolean };
export type Programme = {
  id: string; name: string; vector_group: string; description: string | null; status: "active" | "paused" | "closed";
  starts_on: string | null; ends_on: string | null; created_at: string; teams: string[];
};
export type Site = {
  id: string; reference: string; name: string; line_1: string | null; line_2: string | null; town: string | null; postcode: string | null;
  uprn: string | null; latitude: number | null; longitude: number | null; location_description: string | null; access_instructions: string | null;
  status: "active" | "inactive"; created_by: string; created_at: string; updated_at: string; programmes: string[];
  site_type: import("./obligations").SiteType; boundary: import("./geo").Polygon | null; zone_m: number; risk_reason: string | null;
};
export type Trap = {
  id: string; identifier: string; trap_type_id: string | null; council_trap_type_id: string | null;
  status: "available" | "deployed" | "damaged" | "retired"; notes: string | null; created_at: string; updated_at: string;
};
export type VvEvent = { id: number; record_type: string; record_id: string; kind: string; detail: Record<string, { from: unknown; to: unknown }> & Record<string, unknown>; actor_id: string | null; actor_role: string | null; recorded_at: string };
export type Team = { id: string; name: string };

export async function loadLists(ws: string) {
  const [t, tt, ct, ctt] = await Promise.all([
    db.from("vv_taxa").select("id, key, scientific_name, common_name, invasive, checked, sort_order").order("sort_order"),
    db.from("vv_trap_types").select("id, key, name, description, checked, sort_order").order("sort_order"),
    db.from("vv_council_taxa").select("id, scientific_name, common_name, active").eq("workspace_id", ws).order("scientific_name"),
    db.from("vv_council_trap_types").select("id, name, description, active").eq("workspace_id", ws).order("name"),
  ]);
  return {
    taxa: must(t) as Taxon[], trapTypes: must(tt) as TrapType[],
    councilTaxa: must(ct) as CouncilTaxon[], councilTrapTypes: must(ctt) as CouncilTrapType[],
  };
}
export type Lists = Awaited<ReturnType<typeof loadLists>>;

export async function loadProgrammes(ws: string): Promise<Programme[]> {
  const [p, pt] = await Promise.all([
    db.from("vv_programmes").select("id, name, vector_group, description, status, starts_on, ends_on, created_at").eq("workspace_id", ws).order("name"),
    db.from("vv_programme_teams").select("programme_id, team_id").eq("workspace_id", ws),
  ]);
  const links = must(pt) as { programme_id: string; team_id: string }[];
  return (must(p) as Omit<Programme, "teams">[]).map((x) => ({ ...x, teams: links.filter((l) => l.programme_id === x.id).map((l) => l.team_id) }));
}

export async function loadSites(ws: string): Promise<Site[]> {
  const [s, sp] = await Promise.all([
    db.from("vv_sites").select("id, reference, name, line_1, line_2, town, postcode, uprn, latitude, longitude, location_description, access_instructions, status, created_by, created_at, updated_at, site_type, boundary, zone_m, risk_reason")
      .eq("workspace_id", ws).order("reference"),
    db.from("vv_site_programmes").select("site_id, programme_id").eq("workspace_id", ws),
  ]);
  const links = must(sp) as { site_id: string; programme_id: string }[];
  return (must(s) as Omit<Site, "programmes">[]).map((x) => ({ ...x, programmes: links.filter((l) => l.site_id === x.id).map((l) => l.programme_id) }));
}

export async function loadTraps(ws: string): Promise<Trap[]> {
  return must(await db.from("vv_traps").select("id, identifier, trap_type_id, council_trap_type_id, status, notes, created_at, updated_at")
    .eq("workspace_id", ws).order("identifier")) as Trap[];
}

export async function loadHistory(type: "site" | "trap" | "programme" | "visit" | "deployment" | "result" | "assessment" | "action" | "incursion", id: string): Promise<VvEvent[]> {
  return must(await db.from("vv_events").select("id, record_type, record_id, kind, detail, actor_id, actor_role, recorded_at")
    .eq("record_type", type).eq("record_id", id).order("id", { ascending: false })) as VvEvent[];
}

/** The council's teams (shared platform data: names only). */
export async function loadTeams(ws: string): Promise<Team[]> {
  return must(await db.from("teams").select("id, name").eq("workspace_id", ws).order("name")) as Team[];
}

export type SiteInput = {
  name: string; line_1: string; line_2: string; town: string; postcode: string; uprn: string;
  latitude: number | null; longitude: number | null; location_description: string; access_instructions: string;
  status: Site["status"]; programmes: string[];
};

export const vvRpc = {
  saveProgramme: (id: string, ws: string, p: { name: string; description: string; status: Programme["status"]; starts_on: string | null; ends_on: string | null; teams: string[] }) =>
    db.rpc("vv_save_programme", { _id: id, _ws: ws, _name: p.name, _description: p.description, _status: p.status, _starts: p.starts_on, _ends: p.ends_on, _teams: p.teams }),
  saveSite: (id: string, ws: string, s: SiteInput) =>
    db.rpc("vv_save_site", { _id: id, _ws: ws, _name: s.name, _line_1: s.line_1, _line_2: s.line_2, _town: s.town, _postcode: s.postcode, _uprn: s.uprn,
      _latitude: s.latitude, _longitude: s.longitude, _description: s.location_description, _access: s.access_instructions, _status: s.status, _programmes: s.programmes }),
  saveTrap: (id: string, ws: string, t: { identifier: string; trap_type_id: string | null; council_trap_type_id: string | null; status: Trap["status"]; notes: string }) =>
    db.rpc("vv_save_trap", { _id: id, _ws: ws, _identifier: t.identifier, _trap_type: t.trap_type_id, _council_trap_type: t.council_trap_type_id, _status: t.status, _notes: t.notes }),
  saveCouncilTaxon: (id: string, ws: string, scientific: string, common: string, active: boolean) =>
    db.rpc("vv_save_council_taxon", { _id: id, _ws: ws, _scientific: scientific, _common: common, _active: active }),
  saveCouncilTrapType: (id: string, ws: string, name: string, description: string, active: boolean) =>
    db.rpc("vv_save_council_trap_type", { _id: id, _ws: ws, _name: name, _description: description, _active: active }),
};

export async function run(p: PromiseLike<{ data: unknown; error: import("@supabase/supabase-js").PostgrestError | null }>) {
  return must(await p);
}

export const trapStatusLabels: Record<Trap["status"], string> = { available: "Available", deployed: "Deployed", damaged: "Damaged", retired: "Retired" };
export const programmeStatusLabels: Record<Programme["status"], string> = { active: "Active", paused: "Paused", closed: "Closed" };

export const who = (id: string | null | undefined, uid: string | undefined) => (!id ? "System" : id === uid ? "You" : `Member ${id.slice(0, 8)}`);
export const when = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleString("en-GB", { timeZone: "Europe/London", dateStyle: "medium", timeStyle: "short" }) : "—";
export const siteAddress = (s: Pick<Site, "line_1" | "line_2" | "town" | "postcode">) => [s.line_1, s.line_2, s.town, s.postcode].filter(Boolean).join(", ");

// ---------- Field work (V2a, rev 22) -------------------------------------------------------
export type Deployment = {
  id: string; trap_id: string; site_id: string; latitude: number | null; longitude: number | null; placement: string | null;
  started_at: string; ended_at: string | null; end_reason: EndReason | null; end_note: string | null;
  responsible_officer: string | null; visit_interval_days: number; created_by: string; recorded_at: string; ended_by: string | null;
};
export type EndReason = "moved" | "removed" | "damaged" | "lost" | "programme_ended";
export const endReasonLabels: Record<EndReason, string> = {
  moved: "Moved to another site", removed: "Removed (back in store)", damaged: "Damaged", lost: "Lost or stolen", programme_ended: "Programme ended",
};
export type Outcome = "collected" | "no_catch" | "not_completed";
export const outcomeLabels: Record<Outcome, string> = { collected: "Samples collected", no_catch: "No catch", not_completed: "Not completed" };
export type Condition = "working" | "not_working" | "damaged" | "missing";
export const conditionLabels: Record<Condition, string> = { working: "Working", not_working: "Not working", damaged: "Damaged", missing: "Missing" };
export type SampleMethod = "adult_trap_catch" | "egg_paper" | "larvae" | "pupae" | "other";
export const methodLabels: Record<SampleMethod, string> = {
  adult_trap_catch: "Adult trap catch", egg_paper: "Egg paper / ovitrap", larvae: "Larvae", pupae: "Pupae", other: "Other",
};
export type Visit = {
  id: string; deployment_id: string; site_id: string; occurred_at: string; recorded_at: string; officer_id: string; outcome: Outcome;
  not_completed_reason: string | null; trap_condition: Condition; observations: string | null;
  exposure_started_at: string | null; exposure_ended_at: string | null; created_by: string; updated_by: string | null; updated_at: string | null;
};
export type Sample = {
  id: string; visit_id: string; site_id: string; reference: string; method: SampleMethod; notes: string | null;
  status: "awaiting_result" | "resulted"; created_by: string; recorded_at: string;
};
export type ScheduleRow = {
  deployment_id: string; trap_id: string; site_id: string; started_at: string; responsible_officer: string | null;
  visit_interval_days: number; last_visit_at: string | null; next_due_on: string | null; state: "overdue" | "due" | "scheduled" | "off_season";
};
export type MemberRow = { user_id: string; role: string };

export async function loadDeployments(ws: string): Promise<Deployment[]> {
  return must(await db.from("vv_deployments").select("id, trap_id, site_id, latitude, longitude, placement, started_at, ended_at, end_reason, end_note, responsible_officer, visit_interval_days, created_by, recorded_at, ended_by")
    .eq("workspace_id", ws).order("started_at", { ascending: false })) as Deployment[];
}
export async function loadVisits(ws: string): Promise<Visit[]> {
  return must(await db.from("vv_visits").select("id, deployment_id, site_id, occurred_at, recorded_at, officer_id, outcome, not_completed_reason, trap_condition, observations, exposure_started_at, exposure_ended_at, created_by, updated_by, updated_at")
    .eq("workspace_id", ws).order("occurred_at", { ascending: false }).limit(500)) as Visit[];
}
export async function loadSamples(ws: string): Promise<Sample[]> {
  return must(await db.from("vv_samples").select("id, visit_id, site_id, reference, method, notes, status, created_by, recorded_at")
    .eq("workspace_id", ws).order("recorded_at", { ascending: false }).limit(1000)) as Sample[];
}
export async function loadSchedule(ws: string): Promise<ScheduleRow[]> {
  return must(await db.rpc("vv_visit_schedule", { _ws: ws })) as ScheduleRow[];
}
/** Council members (shared platform data: IDs and roles only) for choosing an officer. */
export async function loadMembers(ws: string): Promise<MemberRow[]> {
  return must(await db.from("workspace_members").select("user_id, role").eq("workspace_id", ws)) as MemberRow[];
}

export type VisitInput = {
  occurred_at: string; officer: string | null; outcome: Outcome; reason: string; condition: Condition; observations: string;
  exposure_start: string | null; exposure_end: string | null; samples: { id: string; reference: string; method: SampleMethod; notes: string }[];
};
export const fieldRpc = {
  deploy: (id: string, ws: string, trap: string, site: string, lat: number | null, lon: number | null, placement: string, startedAt: string, officer: string | null, interval: number) =>
    db.rpc("vv_deploy_trap", { _id: id, _ws: ws, _trap: trap, _site: site, _latitude: lat, _longitude: lon, _placement: placement, _started_at: startedAt, _officer: officer, _interval: interval }),
  end: (deployment: string, endedAt: string, reason: EndReason, note: string) =>
    db.rpc("vv_end_deployment", { _deployment: deployment, _ended_at: endedAt, _reason: reason, _note: note }),
  move: (deployment: string, newId: string, site: string, lat: number | null, lon: number | null, placement: string, movedAt: string, officer: string | null, interval: number) =>
    db.rpc("vv_move_trap", { _deployment: deployment, _new_id: newId, _site: site, _latitude: lat, _longitude: lon, _placement: placement, _moved_at: movedAt, _officer: officer, _interval: interval }),
  recordVisit: (id: string, deployment: string, v: VisitInput) =>
    db.rpc("vv_record_visit", { _id: id, _deployment: deployment, _occurred_at: v.occurred_at, _officer: v.officer, _outcome: v.outcome, _reason: v.reason,
      _condition: v.condition, _observations: v.observations, _exposure_start: v.exposure_start, _exposure_end: v.exposure_end, _samples: v.samples }),
  correctVisit: (visit: string, v: { occurred_at: string; officer: string | null; condition: Condition; observations: string; exposure_start: string | null; exposure_end: string | null; reason: string }, why: string) =>
    db.rpc("vv_correct_visit", { _visit: visit, _occurred_at: v.occurred_at, _officer: v.officer, _condition: v.condition, _observations: v.observations,
      _exposure_start: v.exposure_start, _exposure_end: v.exposure_end, _not_completed_reason: v.reason, _why: why }),
};

/** A local date-time input value (yyyy-mm-ddThh:mm) for an ISO time, and back. Inputs use the device's local time. */
export const toLocalInput = (iso: string | null | undefined) => {
  const d = iso ? new Date(iso) : new Date();
  d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
  return d.toISOString().slice(0, 16);
};
export const fromLocalInput = (v: string) => (v ? new Date(v).toISOString() : null);
export const day = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleDateString("en-GB", { timeZone: "Europe/London", day: "numeric", month: "short", year: "numeric" }) : "—";

// ---------- Results, risk assessment and actions (V3, rev 24) -------------------------------
export type ResultStatus = "pending" | "provisional" | "confirmed" | "inconclusive";
export const resultStatusLabels: Record<ResultStatus, string> = {
  pending: "Result pending", provisional: "Provisional", confirmed: "Confirmed", inconclusive: "Inconclusive",
};
export type Unit = "individuals" | "females" | "males" | "eggs" | "larvae" | "pupae" | "presence";
export const unitLabels: Record<Unit, string> = {
  individuals: "individuals", females: "females", males: "males", eggs: "eggs", larvae: "larvae", pupae: "pupae", presence: "present (not counted)",
};
export type IdMethod = "morphology" | "molecular" | "other";
export const idMethodLabels: Record<IdMethod, string> = { morphology: "Microscope (morphology)", molecular: "Molecular (e.g. PCR)", other: "Other" };
export type Result = { id: string; sample_id: string; site_id: string; current_version: number; created_by: string; created_at: string };
export type ResultVersion = {
  result_id: string; version: number; status: ResultStatus; taxon_id: string | null; council_taxon_id: string | null; quantity: number | null;
  unit: Unit | null; method: IdMethod | null; identified_by: string | null; laboratory: string | null; lab_reference: string | null;
  result_date: string | null; uncertainty: string | null; reason: string | null; author_id: string; author_role: string; recorded_at: string;
};
export type Level = "low" | "medium" | "high" | "very_high";
export const levelLabels: Record<Level, string> = { low: "Low", medium: "Medium", high: "High", very_high: "Very high" };
/** The default matrix shown to officers (matches vv_matrix_level in the database). */
export const matrixLevel = (l: number, c: number): Level => (l * c <= 4 ? "low" : l * c <= 9 ? "medium" : l * c <= 16 ? "high" : "very_high");
export const likelihoodLabels = ["", "Rare", "Unlikely", "Possible", "Likely", "Almost certain"];
export const consequenceLabels = ["", "Negligible", "Minor", "Moderate", "Major", "Severe"];
export const riskFactors: [string, string][] = [
  ["invasive_species", "Invasive or vector species found"], ["port_of_entry", "Port, airport or other point of entry"],
  ["near_homes", "Homes, schools or care settings nearby"], ["breeding_habitat", "Suitable breeding habitat nearby"],
  ["season", "Season and temperature favour activity"], ["abundance", "Numbers found"], ["previous_detections", "Previous detections here or nearby"],
  ["identification_certainty", "How certain the identification is"],
];
export type Assessment = { id: string; site_id: string; current_version: number; created_by: string; created_at: string; results: string[] };
export type AssessmentVersion = {
  assessment_id: string; version: number; likelihood: number; consequence: number; matrix_version: string; matrix_level: Level; final_level: Level;
  override_reason: string | null; factors: string[]; rationale: string; reason: string | null; author_id: string; author_role: string; recorded_at: string;
};
export type Action = {
  id: string; site_id: string; assessment_id: string | null; title: string; detail: string | null; owner_id: string | null; due_on: string | null;
  status: "open" | "done" | "cancelled"; completion_note: string | null; completed_by: string | null; completed_at: string | null; created_by: string; created_at: string;
};
export type Finding = { result_id: string; sample_id: string; site_id: string; status: ResultStatus; taxon_id: string | null; council_taxon_id: string | null; quantity: number | null; unit: Unit | null; result_date: string | null };

export async function loadResults(ws: string) {
  const [r, v] = await Promise.all([
    db.from("vv_results").select("id, sample_id, site_id, current_version, created_by, created_at").eq("workspace_id", ws).order("created_at"),
    db.from("vv_result_versions").select("result_id, version, status, taxon_id, council_taxon_id, quantity, unit, method, identified_by, laboratory, lab_reference, result_date, uncertainty, reason, author_id, author_role, recorded_at")
      .eq("workspace_id", ws).order("version"),
  ]);
  return { results: must(r) as Result[], versions: (must(v) as ResultVersion[]).map((x) => ({ ...x, quantity: x.quantity === null ? null : Number(x.quantity) })) };
}
export async function loadAssessments(ws: string) {
  const [a, ar, v] = await Promise.all([
    db.from("vv_assessments").select("id, site_id, current_version, created_by, created_at").eq("workspace_id", ws).order("created_at", { ascending: false }),
    db.from("vv_assessment_results").select("assessment_id, result_id").eq("workspace_id", ws),
    db.from("vv_assessment_versions").select("assessment_id, version, likelihood, consequence, matrix_version, matrix_level, final_level, override_reason, factors, rationale, reason, author_id, author_role, recorded_at")
      .eq("workspace_id", ws).order("version"),
  ]);
  const links = must(ar) as { assessment_id: string; result_id: string }[];
  return {
    assessments: (must(a) as Omit<Assessment, "results">[]).map((x) => ({ ...x, results: links.filter((l) => l.assessment_id === x.id).map((l) => l.result_id) })),
    versions: must(v) as AssessmentVersion[],
  };
}
export async function loadActions(ws: string): Promise<Action[]> {
  return must(await db.from("vv_actions").select("id, site_id, assessment_id, title, detail, owner_id, due_on, status, completion_note, completed_by, completed_at, created_by, created_at")
    .eq("workspace_id", ws).order("due_on", { ascending: true, nullsFirst: false })) as Action[];
}
export async function loadFindings(ws: string): Promise<Finding[]> {
  return (must(await db.rpc("vv_findings_awaiting_review", { _ws: ws })) as Finding[]).map((x) => ({ ...x, quantity: x.quantity === null ? null : Number(x.quantity) }));
}

export type ResultInput = {
  status: ResultStatus; taxon: string; quantity: string; unit: Unit | ""; method: IdMethod | ""; identified_by: string; laboratory: string;
  lab_reference: string; result_date: string; uncertainty: string;
};
export const riskRpc = {
  saveResult: (id: string, sample: string, r: ResultInput, reason: string | null) =>
    db.rpc("vv_save_result", {
      _id: id, _sample: sample, _status: r.status,
      _taxon: r.taxon.startsWith("s:") ? r.taxon.slice(2) : null, _council_taxon: r.taxon.startsWith("c:") ? r.taxon.slice(2) : null,
      _quantity: r.quantity === "" ? null : Number(r.quantity), _unit: r.unit || null, _method: r.method || null,
      _identified_by: r.identified_by, _laboratory: r.laboratory, _lab_reference: r.lab_reference, _result_date: r.result_date || null,
      _uncertainty: r.uncertainty, _reason: reason,
    }),
  saveAssessment: (id: string, site: string, results: string[] | null, a: { likelihood: number; consequence: number; final_level: Level; override_reason: string; factors: string[]; rationale: string }, reason: string | null) =>
    db.rpc("vv_save_assessment", { _id: id, _site: site, _results: results, _likelihood: a.likelihood, _consequence: a.consequence,
      _final_level: a.final_level, _override_reason: a.override_reason, _factors: a.factors, _rationale: a.rationale, _reason: reason }),
  saveAction: (id: string, site: string, assessment: string | null, title: string, detail: string, owner: string | null, due: string | null) =>
    db.rpc("vv_save_action", { _id: id, _site: site, _assessment: assessment, _title: title, _detail: detail, _owner: owner, _due: due }),
  actionStatus: (id: string, status: Action["status"], note: string | null) => db.rpc("vv_set_action_status", { _id: id, _status: status, _note: note }),
};
