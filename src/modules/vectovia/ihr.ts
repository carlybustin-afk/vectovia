// Other IHR records (v2-006): competence, contractors, equipment and chemicals, conveyance inspections,
// follow-up notices, the incoming-risk log and site reviews. Reads go through RLS; writes are checked functions.
import { useQuery } from "@tanstack/react-query";
import { db, must } from "@/lib/backend";
import { wsKey } from "@/lib/workspace";

export type Competence = { id: string; person_name: string; person_id: string | null; competence: string; provider: string | null; achieved_on: string;
  expires_on: string | null; certificate_ref: string | null; withdrawn_at: string | null; withdrawn_reason: string | null };
export type Contractor = { id: string; name: string; service: string; contact: string | null; status: "active" | "ended" };
export type ContractorAudit = { id: string; contractor_id: string; site_id: string | null; audited_on: string; outcome: AuditOutcome; findings: string; next_due: string };
export type AuditOutcome = "satisfactory" | "actions_needed" | "unsatisfactory";
export const auditOutcomeLabels: Record<AuditOutcome, string> = { satisfactory: "Satisfactory", actions_needed: "Actions needed", unsatisfactory: "Unsatisfactory" };
export type Equipment = { id: string; kind: "equipment" | "chemical"; name: string; active_substance: string | null; authorisation_ref: string | null; location: string | null;
  quantity: string | null; expires_on: string | null; status: "in_use" | "withdrawn"; notes: string | null };

export type ConveyanceType = "ship" | "aircraft" | "road_vehicle" | "train" | "container" | "other";
export const conveyanceTypeLabels: Record<ConveyanceType, string> = { ship: "Ship", aircraft: "Aircraft", road_vehicle: "Road vehicle", train: "Train", container: "Container", other: "Other" };
export type ConveyanceReason = "routine" | "affected" | "suspect";
export const conveyanceReasonLabels: Record<ConveyanceReason, string> = { routine: "Routine", affected: "Affected", suspect: "Suspect" };
export const conveyanceOutcomeLabels = { no_evidence: "No evidence of vectors", evidence_found: "Evidence found", treated: "Treated", referred: "Referred" } as const;
export type ConveyanceOutcome = keyof typeof conveyanceOutcomeLabels;
export type Conveyance = { id: string; site_id: string; inspected_at: string; officer_id: string; conveyance_type: ConveyanceType; identifier: string; arrived_from: string | null;
  next_destination: string | null; reason: ConveyanceReason; outcome: ConveyanceOutcome; evidence: string | null; action_taken: string | null };
export type FollowUp = { id: string; site_id: string; conveyance_id: string | null; to_point_of_entry: string; sent_on: string; method: "email" | "phone" | "letter" | "other";
  summary: string; acknowledged_on: string | null; ack_note: string | null };
export const followUpMethodLabels: Record<FollowUp["method"], string> = { email: "Email", phone: "Phone", letter: "Letter", other: "Other" };
export type IncomingRisk = { id: string; site_id: string; reported_on: string; source: string; description: string; level: "low" | "medium" | "high"; action: string | null;
  status: "open" | "closed"; closed_on: string | null; closed_note: string | null };
export type ReviewKind = "sanitary_survey" | "wider_survey" | "operator_report" | "effectiveness_review";
export const reviewKindLabels: Record<ReviewKind, string> = {
  sanitary_survey: "Sanitary and vector survey (yearly)", wider_survey: "Wider survey (every 3 years)", operator_report: "Report to the site operator (yearly)",
  effectiveness_review: "Effectiveness review (yearly)",
};
export type SiteReview = { id: string; site_id: string; kind: ReviewKind; done_on: string; summary: string; corrective_actions: string | null; next_due: string };

const load = async <T,>(q: PromiseLike<{ data: unknown; error: import("@supabase/supabase-js").PostgrestError | null }>) => must(await q) as T;
export const useCompetence = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "competence"),
  queryFn: () => load<Competence[]>(db.from("vv_competence").select("id, person_name, person_id, competence, provider, achieved_on, expires_on, certificate_ref, withdrawn_at, withdrawn_reason")
    .eq("workspace_id", ws).order("person_name").order("achieved_on", { ascending: false })) });
export const useContractors = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "contractors"),
  queryFn: async () => {
    const [c, s, a] = await Promise.all([
      load<Contractor[]>(db.from("vv_contractors").select("id, name, service, contact, status").eq("workspace_id", ws).order("name")),
      load<{ contractor_id: string; site_id: string }[]>(db.from("vv_contractor_sites").select("contractor_id, site_id").eq("workspace_id", ws)),
      load<ContractorAudit[]>(db.from("vv_contractor_audits").select("id, contractor_id, site_id, audited_on, outcome, findings, next_due").eq("workspace_id", ws).order("audited_on", { ascending: false })),
    ]);
    return { contractors: c, sites: s, audits: a };
  } });
export const useEquipment = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "equipment"),
  queryFn: () => load<Equipment[]>(db.from("vv_equipment").select("id, kind, name, active_substance, authorisation_ref, location, quantity, expires_on, status, notes")
    .eq("workspace_id", ws).order("status").order("name")) });
export const useConveyances = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "conveyances"),
  queryFn: async () => {
    const [c, f] = await Promise.all([
      load<Conveyance[]>(db.from("vv_conveyances").select("id, site_id, inspected_at, officer_id, conveyance_type, identifier, arrived_from, next_destination, reason, outcome, evidence, action_taken")
        .eq("workspace_id", ws).order("inspected_at", { ascending: false }).limit(200)),
      load<FollowUp[]>(db.from("vv_follow_ups").select("id, site_id, conveyance_id, to_point_of_entry, sent_on, method, summary, acknowledged_on, ack_note")
        .eq("workspace_id", ws).order("sent_on", { ascending: false })),
    ]);
    return { conveyances: c, followUps: f };
  } });
export const useIncomingRisks = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "incoming-risks"),
  queryFn: () => load<IncomingRisk[]>(db.from("vv_incoming_risks").select("id, site_id, reported_on, source, description, level, action, status, closed_on, closed_note")
    .eq("workspace_id", ws).order("status", { ascending: false }).order("reported_on", { ascending: false })) });
export const useSiteReviews = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "site-reviews"),
  queryFn: () => load<SiteReview[]>(db.from("vv_site_reviews").select("id, site_id, kind, done_on, summary, corrective_actions, next_due")
    .eq("workspace_id", ws).order("done_on", { ascending: false })) });

const blank = (v: string) => v.trim() || null;
export const ihrRpc = {
  saveCompetence: (id: string, ws: string, c: { person_name: string; person_id: string; competence: string; provider: string; achieved_on: string; expires_on: string; certificate_ref: string }, reason: string) =>
    db.rpc("vv_save_competence", { _id: id, _ws: ws, _person_name: c.person_name, _person: c.person_id || null, _competence: c.competence, _provider: c.provider,
      _achieved_on: c.achieved_on, _expires_on: c.expires_on || null, _certificate_ref: c.certificate_ref, _reason: reason }),
  withdrawCompetence: (id: string, reason: string) => db.rpc("vv_withdraw_competence", { _id: id, _reason: reason }),
  saveContractor: (id: string, ws: string, c: { name: string; service: string; contact: string; status: Contractor["status"]; sites: string[] }, reason: string) =>
    db.rpc("vv_save_contractor", { _id: id, _ws: ws, _name: c.name, _service: c.service, _contact: c.contact, _status: c.status, _sites: c.sites, _reason: reason }),
  recordAudit: (id: string, contractor: string, site: string, a: { audited_on: string; outcome: AuditOutcome; findings: string; next_due: string }) =>
    db.rpc("vv_record_contractor_audit", { _id: id, _contractor: contractor, _site: site || null, _audited_on: a.audited_on, _outcome: a.outcome, _findings: a.findings,
      _next_due: a.next_due || null }),
  saveEquipment: (id: string, ws: string, e: { kind: Equipment["kind"]; name: string; substance: string; authorisation: string; location: string; quantity: string;
      expires_on: string; status: Equipment["status"]; notes: string }, reason: string) =>
    db.rpc("vv_save_equipment", { _id: id, _ws: ws, _kind: e.kind, _name: e.name, _substance: e.substance, _authorisation: e.authorisation, _location: e.location,
      _quantity: e.quantity, _expires_on: e.expires_on || null, _status: e.status, _notes: e.notes, _reason: reason }),
  recordConveyance: (id: string, site: string, c: { inspected_at: string; type: ConveyanceType; identifier: string; arrived_from: string; next_destination: string;
      reason: ConveyanceReason; outcome: ConveyanceOutcome; evidence: string; action: string }) =>
    db.rpc("vv_record_conveyance", { _id: id, _site: site, _inspected_at: c.inspected_at, _type: c.type, _identifier: c.identifier, _arrived_from: c.arrived_from,
      _next_destination: c.next_destination, _reason: c.reason, _outcome: c.outcome, _evidence: blank(c.evidence), _action: blank(c.action) }),
  sendFollowUp: (id: string, site: string, conveyance: string | null, f: { to: string; sent_on: string; method: FollowUp["method"]; summary: string }) =>
    db.rpc("vv_send_follow_up", { _id: id, _site: site, _conveyance: conveyance, _to: f.to, _sent_on: f.sent_on, _method: f.method, _summary: f.summary }),
  acknowledge: (id: string, on: string, note: string) => db.rpc("vv_acknowledge_follow_up", { _id: id, _on: on, _note: note }),
  saveIncomingRisk: (id: string, site: string, r: { reported_on: string; source: string; description: string; level: IncomingRisk["level"]; action: string }, reason: string) =>
    db.rpc("vv_save_incoming_risk", { _id: id, _site: site, _reported_on: r.reported_on, _source: r.source, _description: r.description, _level: r.level, _action: r.action, _reason: reason }),
  closeIncomingRisk: (id: string, on: string, note: string) => db.rpc("vv_close_incoming_risk", { _id: id, _closed_on: on, _note: note }),
  recordReview: (id: string, site: string, r: { kind: ReviewKind; done_on: string; summary: string; corrective: string; next_due: string }) =>
    db.rpc("vv_record_site_review", { _id: id, _site: site, _kind: r.kind, _done_on: r.done_on, _summary: r.summary, _corrective: r.corrective, _next_due: r.next_due || null }),
};

/** Expiry state for registers: overdue, due within 30 days, or fine. */
export function expiry(date: string | null, today = new Date().toISOString().slice(0, 10)): "expired" | "soon" | "ok" | "none" {
  if (!date) return "none";
  if (date < today) return "expired";
  const soon = new Date(today); soon.setDate(soon.getDate() + 30);
  return date <= soon.toISOString().slice(0, 10) ? "soon" : "ok";
}
