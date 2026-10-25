// Incursion management (plan V-D12, V-D13; rev 26). A manager opens an incursion
// from one or more findings; a guided response tracks each step with tasks; the
// response area is a circle drawn on the map; notifications are RECORDED only
// (First Line never sends anything); stand-down and reopening keep their history.
// People decide every status change: nothing is worked out from the data.
// Module boundary: no case code, no case tables, no AI.
import { BackendError, db, must } from "@/lib/backend";
import type { Action } from "./api";

export type IncursionStatus = "suspected" | "confirmed" | "responding" | "monitoring" | "stood_down";
export const incursionStatusLabels: Record<IncursionStatus, string> = {
  suspected: "Suspected", confirmed: "Confirmed", responding: "Responding", monitoring: "Monitoring", stood_down: "Stood down",
};
export type ResponseArea = { type: "circle"; lat: number; lon: number; radius_m: number };
export type Incursion = {
  id: string; reference: string; site_id: string; title: string; taxon_id: string | null; council_taxon_id: string | null;
  status: IncursionStatus; lead_officer_id: string | null; response_area: ResponseArea | null; opened_at: string;
  created_by: string; updated_at: string; findings: string[]; sites: string[];
};
export type StepKey = "notify" | "confirm_id" | "response_area" | "enhanced_trapping" | "control" | "communications" | "review" | "stand_down";
export type Step = { incursion_id: string; step_key: StepKey; sort_order: number; status: "to_do" | "done" | "skipped"; note: string | null; decided_by: string | null; decided_at: string | null };
export type NotifyKind = "ukhsa" | "port_health" | "apha" | "internal" | "other";
export const notifyKindLabels: Record<NotifyKind, string> = {
  ukhsa: "UKHSA", port_health: "Port health", apha: "APHA", internal: "Internal (managers, communications, councillors)", other: "Other",
};
export type NotifyMethod = "phone" | "email" | "letter" | "meeting" | "other";
export const notifyMethodLabels: Record<NotifyMethod, string> = { phone: "Phone", email: "Email", letter: "Letter", meeting: "Meeting", other: "Other" };
export type Notification = {
  id: string; incursion_id: string; kind: NotifyKind; contact_id: string | null; recipient: string; method: NotifyMethod; notified_at: string;
  reference: string | null; note: string | null; recorded_by: string; recorded_role: string; recorded_at: string;
};
export type Contact = { id: string; name: string; organisation: string | null; kind: NotifyKind; detail: string | null; active: boolean };
export type StandDown = { id: string; incursion_id: string; kind: "stand_down" | "reopen"; decided_at: string; rationale: string; decided_by: string; decided_role: string; recorded_at: string };
export type IncursionTask = Action & { incursion_id: string; step_key: StepKey };

/** The guided response (V-D12). The wording is First Line's process guidance, not legal advice. */
export const steps: { key: StepKey; title: string; guide: string }[] = [
  { key: "notify", title: "Notify", guide: "Tell the people who need to know and record each one below: UKHSA, port health or APHA where relevant, and internal contacts. First Line records notifications; it never sends them." },
  { key: "confirm_id", title: "Confirm identification", guide: "Get the identification confirmed (for example by a laboratory or entomologist) and record the result on the Results page." },
  { key: "response_area", title: "Response area", guide: "Draw the area around the finding where enhanced surveillance and any control will happen." },
  { key: "enhanced_trapping", title: "Enhanced trapping", guide: "Add traps or visit more often within the response area. Link the sites used, so their results stay with this incursion." },
  { key: "control", title: "Control measures", guide: "Record any control carried out (for example removing breeding sites or treatment), who did it and when. Skip with a reason if none is needed." },
  { key: "communications", title: "Communications", guide: "Record what was said to residents, businesses or the media, and when." },
  { key: "review", title: "Review", guide: "Review the response with the team: what was found, what was done, and whether surveillance should continue." },
  { key: "stand_down", title: "Stand-down", guide: "When every other step is done or skipped, a manager records the stand-down decision and the reasons for it." },
];

/** Null before the incursion update is applied (shows "not switched on yet"). */
export async function loadIncursions(ws: string) {
  const [i, f, s, st, n, c, sd, t] = await Promise.all([
    db.from("vv_incursions").select("id, reference, site_id, title, taxon_id, council_taxon_id, status, lead_officer_id, response_area, opened_at, created_by, updated_at")
      .eq("workspace_id", ws).order("opened_at", { ascending: false }),
    db.from("vv_incursion_findings").select("incursion_id, result_id").eq("workspace_id", ws),
    db.from("vv_incursion_sites").select("incursion_id, site_id").eq("workspace_id", ws),
    db.from("vv_incursion_steps").select("incursion_id, step_key, sort_order, status, note, decided_by, decided_at").eq("workspace_id", ws).order("sort_order"),
    db.from("vv_notifications").select("id, incursion_id, kind, contact_id, recipient, method, notified_at, reference, note, recorded_by, recorded_role, recorded_at")
      .eq("workspace_id", ws).order("notified_at"),
    db.from("vv_notify_contacts").select("id, name, organisation, kind, detail, active").eq("workspace_id", ws).order("name"),
    db.from("vv_stand_downs").select("id, incursion_id, kind, decided_at, rationale, decided_by, decided_role, recorded_at").eq("workspace_id", ws).order("recorded_at"),
    db.from("vv_actions").select("id, site_id, assessment_id, incursion_id, step_key, title, detail, owner_id, due_on, status, completion_note, completed_by, completed_at, created_by, created_at")
      .eq("workspace_id", ws).not("incursion_id", "is", null).order("created_at"),
  ]);
  if (i.error) { try { must(i); } catch (e) { if (e instanceof BackendError && e.kind === "setup-pending") return null; throw e; } }
  const fl = must(f) as { incursion_id: string; result_id: string }[];
  const sl = must(s) as { incursion_id: string; site_id: string }[];
  return {
    incursions: (must(i) as Omit<Incursion, "findings" | "sites">[]).map((x) => ({
      ...x, findings: fl.filter((l) => l.incursion_id === x.id).map((l) => l.result_id), sites: sl.filter((l) => l.incursion_id === x.id).map((l) => l.site_id),
    })) as Incursion[],
    steps: must(st) as Step[], notifications: must(n) as Notification[], contacts: must(c) as Contact[],
    standDowns: must(sd) as StandDown[], tasks: must(t) as IncursionTask[],
  };
}
export type IncursionData = NonNullable<Awaited<ReturnType<typeof loadIncursions>>>;

export const incRpc = {
  open: (id: string, site: string, results: string[], title: string, taxon: string | null, councilTaxon: string | null, lead: string | null, status: "suspected" | "confirmed") =>
    db.rpc("vv_open_incursion", { _id: id, _site: site, _results: results, _title: title, _taxon: taxon, _council_taxon: councilTaxon, _lead: lead, _status: status }),
  update: (id: string, title: string, taxon: string | null, councilTaxon: string | null, lead: string | null, status: IncursionStatus, reason: string) =>
    db.rpc("vv_update_incursion", { _id: id, _title: title, _taxon: taxon, _council_taxon: councilTaxon, _lead: lead, _status: status, _reason: reason }),
  area: (id: string, lat: number | null, lon: number | null, radius: number | null, reason: string) =>
    db.rpc("vv_set_response_area", { _id: id, _lat: lat, _lon: lon, _radius_m: radius, _reason: reason }),
  link: (id: string, results: string[], sites: string[]) => db.rpc("vv_link_incursion", { _id: id, _results: results, _sites: sites }),
  step: (id: string, step: StepKey, status: Step["status"], note: string) => db.rpc("vv_set_incursion_step", { _id: id, _step: step, _status: status, _note: note }),
  task: (id: string, incursion: string, step: StepKey, title: string, detail: string, owner: string | null, due: string | null) =>
    db.rpc("vv_save_incursion_task", { _id: id, _incursion: incursion, _step: step, _title: title, _detail: detail, _owner: owner, _due: due }),
  notify: (id: string, incursion: string, n: { kind: NotifyKind | null; contact: string | null; recipient: string; method: NotifyMethod; at: string; reference: string; note: string }) =>
    db.rpc("vv_record_notification", { _id: id, _incursion: incursion, _kind: n.kind, _contact: n.contact, _recipient: n.recipient, _method: n.method,
      _notified_at: n.at, _reference: n.reference, _note: n.note }),
  contact: (id: string, ws: string, c: { name: string; organisation: string; kind: NotifyKind; detail: string; active: boolean }) =>
    db.rpc("vv_save_notify_contact", { _id: id, _ws: ws, _name: c.name, _organisation: c.organisation, _kind: c.kind, _detail: c.detail, _active: c.active }),
  standDown: (id: string, incursion: string, at: string, rationale: string) =>
    db.rpc("vv_stand_down", { _id: id, _incursion: incursion, _decided_at: at, _rationale: rationale }),
  reopen: (id: string, incursion: string, status: IncursionStatus, reason: string) =>
    db.rpc("vv_reopen_incursion", { _id: id, _incursion: incursion, _status: status, _reason: reason }),
};

/** Can this person run the incursion (managers, or the lead officer with field access)? Mirrors vv_can_run_incursion. */
export const canRun = (i: Incursion, uid: string | undefined, canManage: boolean, canRecord: boolean) =>
  canManage || (!!uid && i.lead_officer_id === uid && canRecord);

/** "Within 300 m" / "within 1.2 km". */
export const radiusLabel = (m: number) => (m >= 1000 ? `within ${(m / 1000).toFixed(m % 1000 ? 1 : 0)} km` : `within ${Math.round(m)} m`);

/** Local datetime-input value → ISO, and now as a datetime-input value (UK time on the device). */
export const nowLocal = () => { const d = new Date(); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 16); };
export const localToIso = (v: string) => new Date(v).toISOString();
