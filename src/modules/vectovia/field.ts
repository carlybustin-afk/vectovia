// Field records (v2-004): ad hoc inspections, delimiting surveys, pathogen tests, control actions and
// invasive finds awaiting official identification. Reads go through RLS; writes are checked functions.
import { db, must } from "@/lib/backend";
import type { SampleMethod } from "./api";

export type InspectionKind = "larval_dip" | "container_search" | "visual" | "other";
export const inspectionKindLabels: Record<InspectionKind, string> = {
  larval_dip: "Larval dipping (standing water)", container_search: "Container search", visual: "Visual check", other: "Other",
};
export type InspectionOutcome = "collected" | "nothing_found" | "not_completed";
export const inspectionOutcomeLabels: Record<InspectionOutcome, string> = { collected: "Samples collected", nothing_found: "Nothing found", not_completed: "Not completed" };
export type Inspection = { id: string; site_id: string; survey_id: string | null; occurred_at: string; officer_id: string; kind: InspectionKind;
  latitude: number | null; longitude: number | null; habitat: string | null; outcome: InspectionOutcome; not_completed_reason: string | null; observations: string | null };
export async function loadInspections(ws: string): Promise<Inspection[]> {
  return must(await db.from("vv_inspections").select("id, site_id, survey_id, occurred_at, officer_id, kind, latitude, longitude, habitat, outcome, not_completed_reason, observations")
    .eq("workspace_id", ws).order("occurred_at", { ascending: false }).limit(200)) as Inspection[];
}

export type Survey = { id: string; site_id: string; incursion_id: string | null; result_id: string | null; reference: string; centre_lat: number; centre_lon: number;
  radius_m: number; started_on: string; ended_on: string | null; outcome: string | null };
export async function loadSurveys(ws: string): Promise<{ surveys: Survey[]; traps: { survey_id: string; deployment_id: string }[] }> {
  const [s, t] = await Promise.all([
    db.from("vv_surveys").select("id, site_id, incursion_id, result_id, reference, centre_lat, centre_lon, radius_m, started_on, ended_on, outcome")
      .eq("workspace_id", ws).order("started_on", { ascending: false }),
    db.from("vv_survey_deployments").select("survey_id, deployment_id").eq("workspace_id", ws),
  ]);
  return { surveys: must(s) as Survey[], traps: must(t) as { survey_id: string; deployment_id: string }[] };
}
export type SurveySummary = { inspections: number; traps: number; samples: number; positive_finds: number; invasive_finds: number; negative_finds: number; awaiting_results: number };
export async function loadSurveySummary(survey: string): Promise<SurveySummary | null> {
  return ((must(await db.rpc("vv_survey_summary", { _survey: survey })) as SurveySummary[])[0]) ?? null;
}

export type Pathogen = "dengue" | "chikungunya" | "zika" | "west_nile" | "usutu" | "yellow_fever" | "malaria" | "other";
export const pathogenLabels: Record<Pathogen, string> = {
  dengue: "Dengue virus", chikungunya: "Chikungunya virus", zika: "Zika virus", west_nile: "West Nile virus", usutu: "Usutu virus",
  yellow_fever: "Yellow fever virus", malaria: "Malaria parasites", other: "Other",
};
export type TestStatus = "pending" | "not_detected" | "detected" | "inconclusive";
export const testStatusLabels: Record<TestStatus, string> = { pending: "Pending", not_detected: "Not detected", detected: "Detected", inconclusive: "Inconclusive" };
export type PathogenTest = { id: string; sample_id: string; site_id: string; pathogen: Pathogen; pathogen_other: string | null; method: string | null; laboratory: string | null;
  lab_reference: string | null; status: TestStatus; result_date: string | null; note: string | null; created_at: string; updated_at: string | null };
export async function loadTests(ws: string): Promise<PathogenTest[]> {
  return must(await db.from("vv_pathogen_tests").select("id, sample_id, site_id, pathogen, pathogen_other, method, laboratory, lab_reference, status, result_date, note, created_at, updated_at")
    .eq("workspace_id", ws).order("created_at", { ascending: false })) as PathogenTest[];
}

export type ControlKind = "source_reduction" | "larviciding" | "adulticiding" | "barrier_treatment" | "other";
export const controlKindLabels: Record<ControlKind, string> = {
  source_reduction: "Source reduction (removing breeding sites)", larviciding: "Larviciding", adulticiding: "Adulticiding", barrier_treatment: "Barrier treatment", other: "Other",
};
export const needsProduct = (k: ControlKind) => k === "larviciding" || k === "adulticiding" || k === "barrier_treatment";
export type ControlAction = { id: string; site_id: string; incursion_id: string | null; survey_id: string | null; kind: ControlKind; occurred_on: string; product: string | null;
  active_substance: string | null; quantity: string | null; area_description: string | null; latitude: number | null; longitude: number | null; radius_m: number | null;
  operator: string | null; supervised_by: string | null; notes: string | null; recorded_by: string; recorded_at: string;
  withdrawn_by: string | null; withdrawn_at: string | null; withdrawn_reason: string | null };
export async function loadControls(ws: string): Promise<ControlAction[]> {
  return must(await db.from("vv_control_actions").select("id, site_id, incursion_id, survey_id, kind, occurred_on, product, active_substance, quantity, area_description, latitude, longitude, radius_m, operator, supervised_by, notes, recorded_by, recorded_at, withdrawn_by, withdrawn_at, withdrawn_reason")
    .eq("workspace_id", ws).order("occurred_on", { ascending: false })) as ControlAction[];
}

export type AwaitingOfficial = { result_id: string; sample_id: string; site_id: string; taxon_id: string; recorded_at: string; days_waiting: number };
export async function loadAwaitingOfficial(ws: string): Promise<AwaitingOfficial[]> {
  return must(await db.rpc("vv_awaiting_official_id", { _ws: ws })) as AwaitingOfficial[];
}

export type NewSample = { id: string; method: SampleMethod; notes: string };
export const fieldRpc = {
  recordInspection: (id: string, site: string, occurredAt: string, kind: InspectionKind, lat: number | null, lon: number | null, habitat: string,
      outcome: InspectionOutcome, reason: string, observations: string, survey: string | null, samples: NewSample[]) =>
    db.rpc("vv_record_inspection", { _id: id, _site: site, _occurred_at: occurredAt, _officer: null, _kind: kind, _latitude: lat, _longitude: lon, _habitat: habitat,
      _outcome: outcome, _reason: reason, _observations: observations, _survey: survey, _samples: samples }),
  saveSurvey: (id: string, site: string, result: string | null, lat: number, lon: number, radius: number, startedOn: string, reason: string) =>
    db.rpc("vv_save_survey", { _id: id, _site: site, _incursion: null, _result: result, _lat: lat, _lon: lon, _radius: radius, _started_on: startedOn, _reason: reason }),
  endSurvey: (id: string, endedOn: string, outcome: string) => db.rpc("vv_end_survey", { _id: id, _ended_on: endedOn, _outcome: outcome }),
  linkTrap: (survey: string, deployment: string) => db.rpc("vv_link_survey_trap", { _survey: survey, _deployment: deployment }),
  saveTest: (id: string, sample: string, t: { pathogen: Pathogen; pathogen_other: string; method: string; laboratory: string; lab_reference: string; status: TestStatus;
      result_date: string; note: string }, reason: string) =>
    db.rpc("vv_save_pathogen_test", { _id: id, _sample: sample, _pathogen: t.pathogen, _pathogen_other: t.pathogen_other, _method: t.method, _laboratory: t.laboratory,
      _lab_reference: t.lab_reference, _status: t.status, _result_date: t.result_date || null, _note: t.note, _reason: reason }),
  recordControl: (id: string, site: string, survey: string | null, c: { kind: ControlKind; occurred_on: string; product: string; substance: string; quantity: string;
      area: string; operator: string; supervised_by: string; notes: string }) =>
    db.rpc("vv_record_control", { _id: id, _site: site, _incursion: null, _survey: survey, _kind: c.kind, _occurred_on: c.occurred_on, _product: c.product,
      _substance: c.substance, _quantity: c.quantity, _area: c.area, _lat: null, _lon: null, _radius: null, _operator: c.operator,
      _supervised_by: c.supervised_by || null, _notes: c.notes }),
  withdrawControl: (id: string, reason: string) => db.rpc("vv_withdraw_control", { _id: id, _reason: reason }),
};
