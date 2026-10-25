// Report and CSV contents (brief §8; plan V6). Built only from records the
// person can already read: the database's row rules decide what's in a file,
// exactly as they decide what's on screen. Councils' data never mixes.
import { day, levelLabels, resultStatusLabels, outcomeLabels, methodLabels, unitLabels, when, type Assessment, type AssessmentVersion, type Lists, type Programme, type ResultVersion, type Site, type Trap, type VvEvent } from "./api";
import { currentFindings, effort, findings, fmtDays, isPositive, monthLabel, pct, performance, ukDate, type AnalyticsData, type Filter } from "./analytics";
import { FORMAT, type Block, type ExportDoc } from "./export-doc";
import { toGridRef } from "./grid";
import { incursionStatusLabels, notifyKindLabels, notifyMethodLabels, radiusLabel, steps, type Incursion, type IncursionData } from "./incursions";

/** People are shown as they are on screen; the person generating the file by their email. */
export const person = (id: string | null | undefined, me: { id: string | undefined; email: string | undefined }) =>
  !id ? "—" : id === me.id ? (me.email ?? "You") : `Member ${id.slice(0, 8)}`;

export type ReportContext = {
  council: string; me: { id: string | undefined; email: string | undefined }; reportId: string; generatedAt: Date;
  data: AnalyticsData; sites: Site[]; traps: Trap[]; programmes: Programme[]; lists: Lists;
  assessments: { assessments: Assessment[]; versions: AssessmentVersion[] }; incursions: IncursionData | null;
  filter: Filter; programmeId: string; siteId: string;
};

const taxonName = (lists: Lists) => (v: Pick<ResultVersion, "taxon_id" | "council_taxon_id">) =>
  lists.taxa.find((t) => t.id === v.taxon_id)?.scientific_name ?? lists.councilTaxa.find((t) => t.id === v.council_taxon_id)?.scientific_name ?? "Not identified";
const inPeriod = (iso: string, f: Filter) => { const d = ukDate(iso); return d >= f.from && d <= f.to; };
const grid = (s: Site) => (s.latitude !== null && s.longitude !== null ? toGridRef(s.latitude, s.longitude, 10) ?? "" : "");

export function scopeOf(c: Pick<ReportContext, "filter" | "programmeId" | "siteId">) {
  return { from: c.filter.from, to: c.filter.to, programme_id: c.programmeId || null, site_id: c.siteId || null,
    sites: c.filter.sites ? [...c.filter.sites] : "all visible" };
}
function scopeText(c: ReportContext) {
  const prog = c.programmes.find((p) => p.id === c.programmeId)?.name;
  const site = c.sites.find((s) => s.id === c.siteId);
  return site ? `Site ${site.reference} · ${site.name}` : prog ? `Programme: ${prog}` : "All programmes and sites visible to the author";
}

// ---------- Surveillance report ---------------------------------------------------------------------
export function surveillanceReport(c: ReportContext): { doc: ExportDoc; counts: Record<string, number> } {
  const f = c.filter, tx = taxonName(c.lists);
  const e = effort(c.data, f), rows = currentFindings(c.data, f, tx), fi = findings(c.data, f, rows), p = performance(c.data, f);
  const siteOk = (id: string) => !f.sites || f.sites.has(id);
  const sites = c.sites.filter((s) => siteOk(s.id));
  const siteLabel = (id: string) => { const s = c.sites.find((x) => x.id === id); return s ? `${s.reference} · ${s.name}` : "Site"; };
  const deps = c.data.deployments.filter((d) => siteOk(d.site_id) && ukDate(d.started_at) <= f.to && (!d.ended_at || ukDate(d.ended_at) >= f.from));
  const visitOf = new Map(c.data.visits.map((v) => [v.id, v]));
  const sampleOf = new Map(c.data.samples.map((s) => [s.id, s]));
  const versionOf = (rid: string) => { const r = c.data.results.find((x) => x.id === rid)!; return c.data.versions.find((v) => v.result_id === rid && v.version === r.current_version)!; };
  const assessments = c.assessments.assessments.filter((a) => siteOk(a.site_id) && inPeriod(a.created_at, f));
  const actions = c.data.actions.filter((a) => siteOk(a.site_id) && (inPeriod(a.created_at, f) || (a.due_on && a.due_on >= f.from && a.due_on <= f.to) || a.status === "open"));
  const incs = (c.incursions?.incursions ?? []).filter((i) => (!f.sites || i.sites.some((s) => f.sites!.has(s))) && (inPeriod(i.opened_at, f) || i.status !== "stood_down"));
  const trap = (id: string) => c.traps.find((t) => t.id === id)?.identifier ?? "Trap";

  const blocks: Block[] = [
    { t: "h1", text: "Summary" },
    { t: "kv", rows: [
      ["Sites in scope", String(sites.length)], ["Trap deployments in period", String(deps.length)], ["Trap-nights", String(e.trapNights)],
      ["Visits recorded", `${e.visitsDone} (${e.completed} completed, ${e.notCompleted} not completed; ${e.visitsPlanned} planned; ${e.missed} missed)`],
      ["Samples collected", `${fi.samples} (${fi.samples - fi.samplesResulted} awaiting results)`],
      ["Samples with findings", `${fi.samplesPositive} of ${fi.samplesResulted} with results · positivity ${pct(fi.positivity)}`],
      ["Species found", fi.bySpecies.map((x) => `${x.taxon} (${x.findings})`).join("; ") || "None"],
      ["Collection → result", `${fmtDays(p.collectionToResult.median)} (middle of ${p.collectionToResult.n})`],
      ["Result → risk assessment", `${fmtDays(p.resultToAssessment.median)} (middle of ${p.resultToAssessment.n})`],
      ["Follow-up actions", actionSummary(actions)],
      ["Incursions", incs.length ? incs.map((i) => `${i.reference} (${incursionStatusLabels[i.status]})`).join("; ") : "None"],
    ] },
    { t: "note", text: "Figures are worked out from the records, never typed in. Trap-nights come from deployment dates; planned visits are whole visit intervals while a trap was out; positivity is samples with a provisional or confirmed finding out of samples whose results are all in." },

    { t: "h1", text: "Sites and deployments" },
    { t: "table", caption: "Sites", head: ["Site", "Grid reference", "Programmes", "Trap-nights", "Visits / planned", "Samples", "Findings"],
      rows: sites.map((s) => { const x = e.bySite.get(s.id), y = fi.bySite.get(s.id); return [`${s.reference} · ${s.name}`, grid(s),
        s.programmes.map((id) => c.programmes.find((pr) => pr.id === id)?.name ?? "").filter(Boolean).join(", "),
        String(x?.trapNights ?? 0), `${x?.visits ?? 0} / ${x?.planned ?? 0}`, String(y?.samples ?? 0), String(y?.findings ?? 0)]; }) },
    { t: "table", caption: "Deployments active in the period", head: ["Trap", "Site", "From", "To", "Visit every"],
      rows: deps.map((d) => [trap(d.trap_id), siteLabel(d.site_id), day(d.started_at), d.ended_at ? day(d.ended_at) : "Still deployed", `${d.visit_interval_days} days`]) },

    { t: "h1", text: "Visits and collection effort" },
    { t: "table", caption: "By month", head: ["Month", "Trap-nights", "Visits", "Samples", "Samples with findings"],
      rows: e.byMonth.map((m, i) => [monthLabel(m.month), String(m.trapNights), String(m.visits), String(fi.byMonth[i]?.samples ?? 0), String(fi.byMonth[i]?.positive ?? 0)]) },

    { t: "h1", text: "Results and findings" },
    { t: "table", head: ["Sample", "Site", "Collected", "Status", "Species", "Quantity", "Identified by / laboratory", "Result date"],
      rows: rows.map((r) => { const v = versionOf(r.result_id), s = sampleOf.get(r.sample_id);
        return [s?.reference ?? "", siteLabel(r.site_id), when(r.collected_at), resultStatusLabels[r.status], v.status === "pending" ? "" : r.taxon,
          v.quantity !== null && v.unit ? (v.unit === "presence" ? "present" : `${v.quantity} ${unitLabels[v.unit]}`) : "",
          [v.identified_by, v.laboratory].filter(Boolean).join(" / "), v.result_date ? day(v.result_date) : ""]; }) },

    { t: "h1", text: "Risk assessments and follow-up actions" },
    { t: "table", caption: "Assessments recorded in the period (officer-decided; First Line does not calculate risk)",
      head: ["Site", "Recorded", "Likelihood × consequence", "Matrix", "Final level", "Rationale"],
      rows: assessments.map((a) => { const v = c.assessments.versions.find((x) => x.assessment_id === a.id && x.version === a.current_version)!;
        return [siteLabel(a.site_id), when(v.recorded_at), `${v.likelihood} × ${v.consequence}`, levelLabels[v.matrix_level],
          `${levelLabels[v.final_level]}${v.override_reason ? ` (changed: ${v.override_reason})` : ""}`, v.rationale]; }), widths: [30, 24, 22, 16, 22, 66] },
    { t: "table", caption: "Follow-up actions", head: ["Action", "Site", "Owner", "Due", "Status"],
      rows: actions.map((a) => [a.title, siteLabel(a.site_id), person(a.owner_id, c.me), a.due_on ? day(a.due_on) : "",
        a.status === "open" ? (a.due_on && a.due_on < ukDate(new Date().toISOString()) ? "Open, overdue" : "Open") : `${a.status === "done" ? "Done" : "Cancelled"} ${a.completed_at ? day(a.completed_at) : ""}`]) },

    { t: "h1", text: "Incursions" },
    { t: "table", head: ["Reference", "Title", "Status", "Opened", "Response area"],
      rows: incs.map((i) => [i.reference, i.title, incursionStatusLabels[i.status], day(i.opened_at), i.response_area ? radiusLabel(i.response_area.radius_m) : "Not drawn"]) },

    { t: "h1", text: "Locations" },
    { t: "note", text: "Maps aren't included in report files. Locations are given as coordinates (WGS84) and British National Grid references." },
    { t: "table", head: ["Site", "Latitude", "Longitude", "Grid reference", "Description"],
      rows: sites.map((s) => [`${s.reference} · ${s.name}`, s.latitude?.toFixed(6) ?? "", s.longitude?.toFixed(6) ?? "", grid(s), s.location_description ?? ""]) },
  ];
  const doc: ExportDoc = {
    title: "Vector surveillance report", subtitle: `${c.council} · ${day(f.from)} to ${day(f.to)}`,
    meta: [["Council", c.council], ["Period", `${day(f.from)} to ${day(f.to)} (UK dates)`], ["Scope", scopeText(c)],
      ["Generated by", c.me.email ?? "—"], ["Generated", when(c.generatedAt.toISOString())], ["Report ID", c.reportId], ["Format", FORMAT.report]],
    blocks, footer: `Vectovia by First Line · ${c.council} · Report ${c.reportId.slice(0, 8)} · Generated from records visible to its author`,
  };
  return { doc, counts: { sites: sites.length, deployments: deps.length, visits: e.visitsDone, samples: fi.samples, results: rows.length,
    assessments: assessments.length, actions: actions.length, incursions: incs.length } };
}

/** Counts the same actions the report's table lists, so the summary and the table always agree. */
function actionSummary(actions: AnalyticsData["actions"]) {
  const today = ukDate(new Date().toISOString());
  const done = actions.filter((a) => a.status === "done");
  const onTime = done.filter((a) => a.due_on && a.completed_at && ukDate(a.completed_at) <= a.due_on).length;
  const late = done.filter((a) => a.due_on && a.completed_at && ukDate(a.completed_at) > a.due_on).length;
  const open = actions.filter((a) => a.status === "open");
  const overdue = open.filter((a) => a.due_on && a.due_on < today).length;
  return `${actions.length} in this report: ${open.length} open (${overdue} overdue), ${done.length} done (${onTime} on time, ${late} late), ${actions.filter((a) => a.status === "cancelled").length} cancelled`;
}

// ---------- Incursion report ------------------------------------------------------------------------
export function incursionReport(c: ReportContext, i: Incursion, history: VvEvent[]): { doc: ExportDoc; counts: Record<string, number> } {
  const d = c.incursions!, tx = taxonName(c.lists);
  const siteLabel = (id: string) => { const s = c.sites.find((x) => x.id === id); return s ? `${s.reference} · ${s.name}` : "Site"; };
  const st = d.steps.filter((s) => s.incursion_id === i.id);
  const tasks = d.tasks.filter((t) => t.incursion_id === i.id);
  const notes = d.notifications.filter((n) => n.incursion_id === i.id);
  const sds = d.standDowns.filter((s) => s.incursion_id === i.id);
  const sampleOf = new Map(c.data.samples.map((s) => [s.id, s]));
  const visitOf = new Map(c.data.visits.map((v) => [v.id, v]));
  const findingRows = i.findings.map((rid) => {
    const r = c.data.results.find((x) => x.id === rid); const v = r && c.data.versions.find((x) => x.result_id === rid && x.version === r.current_version);
    const s = r && sampleOf.get(r.sample_id), visit = s && visitOf.get(s.visit_id);
    return [s?.reference ?? "", r ? siteLabel(r.site_id) : "", visit ? when(visit.occurred_at) : "", v ? resultStatusLabels[v.status] : "", v && isPositive(v.status) ? tx(v) : "",
      v?.quantity !== null && v?.unit ? `${v.quantity} ${unitLabels[v.unit]}` : "", [v?.identified_by, v?.laboratory].filter(Boolean).join(" / ")];
  });
  const sp = c.lists.taxa.find((t) => t.id === i.taxon_id)?.scientific_name ?? c.lists.councilTaxa.find((t) => t.id === i.council_taxon_id)?.scientific_name ?? "Not known";
  const blocks: Block[] = [
    { t: "h1", text: "Summary" },
    { t: "kv", rows: [["Status", incursionStatusLabels[i.status]], ["Species", sp], ["Found at", siteLabel(i.site_id)], ["Lead officer", person(i.lead_officer_id, c.me)],
      ["Opened", `${when(i.opened_at)} by ${person(i.created_by, c.me)}`],
      ["Response area", i.response_area ? `${radiusLabel(i.response_area.radius_m)} of ${i.response_area.lat.toFixed(5)}, ${i.response_area.lon.toFixed(5)} (${toGridRef(i.response_area.lat, i.response_area.lon, 10) ?? ""})` : "Not drawn"],
      ["Steps", `${st.filter((s) => s.status !== "to_do").length} of ${st.length} done or skipped`]] },
    { t: "h1", text: "Findings" },
    { t: "table", head: ["Sample", "Site", "Collected", "Status", "Species", "Quantity", "Identified by / laboratory"], rows: findingRows },
    { t: "h1", text: "Response steps" },
    { t: "table", head: ["Step", "Status", "By", "When", "Note"], widths: [34, 18, 30, 30, 68],
      rows: steps.map((def) => { const s = st.find((x) => x.step_key === def.key);
        return [def.title, s ? (s.status === "to_do" ? "To do" : s.status === "done" ? "Done" : "Skipped") : "", person(s?.decided_by, c.me), s?.decided_at ? when(s.decided_at) : "", s?.note ?? ""]; }) },
    { t: "table", caption: "Tasks", head: ["Step", "Task", "Owner", "Due", "Status"],
      rows: tasks.map((t) => [steps.find((x) => x.key === t.step_key)?.title ?? "", t.title, person(t.owner_id, c.me), t.due_on ? day(t.due_on) : "",
        t.status === "open" ? "Open" : `${t.status === "done" ? "Done" : "Cancelled"}${t.completed_at ? ` ${day(t.completed_at)}` : ""}`]) },
    { t: "h1", text: "Notifications" },
    { t: "note", text: "Recorded by officers. First Line does not send notifications." },
    { t: "table", head: ["Who", "Type", "How", "When", "Their reference", "Recorded by"],
      rows: notes.map((n) => [n.recipient, notifyKindLabels[n.kind], notifyMethodLabels[n.method], when(n.notified_at), n.reference ?? "", `${person(n.recorded_by, c.me)} (${n.recorded_role})`]) },
    { t: "h1", text: "Sites in the response" },
    { t: "table", head: ["Site", "Grid reference", "Role"],
      rows: i.sites.map((id) => { const s = c.sites.find((x) => x.id === id); return [siteLabel(id), s ? grid(s) : "", id === i.site_id ? "Where it was found" : "Enhanced trapping"]; }) },
    { t: "h1", text: "Stand-down" },
    { t: "table", head: ["Decision", "When", "By", "Reasons"], widths: [26, 32, 40, 82],
      rows: sds.map((s) => [s.kind === "stand_down" ? "Stood down" : "Reopened", when(s.decided_at), `${person(s.decided_by, c.me)} (${s.decided_role})`, s.rationale]) },
    { t: "h1", text: "History" },
    { t: "table", head: ["When", "What", "Who"],
      rows: [...history].reverse().map((h) => [when(h.recorded_at), historyText(h), `${person(h.actor_id, c.me)}${h.actor_role ? ` (${h.actor_role})` : ""}`]) },
  ];
  const doc: ExportDoc = {
    title: `Incursion report: ${i.reference}`, subtitle: `${c.council} · ${i.title}`,
    meta: [["Council", c.council], ["Incursion", `${i.reference} · ${i.title}`], ["Generated by", c.me.email ?? "—"], ["Generated", when(c.generatedAt.toISOString())],
      ["Report ID", c.reportId], ["Format", FORMAT.incursion]],
    blocks, footer: `Vectovia by First Line · ${c.council} · ${i.reference} · Report ${c.reportId.slice(0, 8)}`,
  };
  return { doc, counts: { findings: i.findings.length, steps: st.length, tasks: tasks.length, notifications: notes.length, sites: i.sites.length, history: history.length } };
}

const stepTitle = (k: unknown) => steps.find((s) => s.key === k)?.title ?? String(k ?? "");
const state = (s: unknown) => (s === "to_do" ? "to do" : String(s ?? ""));
function historyText(h: VvEvent): string {
  const x = h.detail as Record<string, unknown>;
  switch (h.kind) {
    case "opened": return `Opened as ${String(x["status"] ?? "")}`;
    case "step": return `${stepTitle(x["step"])}: ${state(x["from"])} -> ${state(x["to"])}${x["note"] ? ` (${String(x["note"])})` : ""}`;
    case "notified": return "Notification recorded";
    case "response_area": return `Response area set${x["reason"] ? ` (${String(x["reason"])})` : ""}`;
    case "linked": return "Findings or sites linked";
    case "stood_down": return "Stood down";
    case "reopened": return `Reopened as ${String(x["to"] ?? "")}`;
    case "changed": return `Changed: ${Object.keys(x).filter((k) => k !== "reason").join(", ")}${x["reason"] ? ` (reason: ${String(x["reason"])})` : ""}`;
    default: return h.kind.replace(/_/g, " ");
  }
}

// ---------- CSV datasets -----------------------------------------------------------------------------
export type CsvSet = "sites" | "deployments" | "visits" | "findings" | "assessments" | "actions" | "incursions";
export const csvSets: { key: CsvSet; label: string }[] = [
  { key: "sites", label: "Sites" }, { key: "deployments", label: "Deployments" }, { key: "visits", label: "Visits" },
  { key: "findings", label: "Samples and results" }, { key: "assessments", label: "Risk assessments" },
  { key: "actions", label: "Follow-up actions" }, { key: "incursions", label: "Incursions" },
];
/** Rows for one CSV, with the record IDs so data can be matched up again later. Times are UTC (ISO 8601). */
export function csvRows(c: ReportContext, set: CsvSet): { head: string[]; rows: (string | number | null)[][] } {
  const f = c.filter, siteOk = (id: string) => !f.sites || f.sites.has(id), tx = taxonName(c.lists);
  const ref = (id: string) => c.sites.find((s) => s.id === id)?.reference ?? "";
  if (set === "sites") return { head: ["site_id", "reference", "name", "address", "postcode", "uprn", "latitude", "longitude", "grid_reference", "status", "programmes"],
    rows: c.sites.filter((s) => siteOk(s.id)).map((s) => [s.id, s.reference, s.name, [s.line_1, s.line_2, s.town].filter(Boolean).join(", "), s.postcode, s.uprn,
      s.latitude, s.longitude, grid(s), s.status, s.programmes.map((id) => c.programmes.find((p) => p.id === id)?.name ?? id).join("; ")]) };
  if (set === "deployments") return { head: ["deployment_id", "trap", "site_reference", "started_at", "ended_at", "end_reason", "visit_interval_days", "latitude", "longitude"],
    rows: c.data.deployments.filter((d) => siteOk(d.site_id) && ukDate(d.started_at) <= f.to && (!d.ended_at || ukDate(d.ended_at) >= f.from))
      .map((d) => [d.id, c.traps.find((t) => t.id === d.trap_id)?.identifier ?? d.trap_id, ref(d.site_id), d.started_at, d.ended_at, d.end_reason, d.visit_interval_days, d.latitude, d.longitude]) };
  if (set === "visits") return { head: ["visit_id", "deployment_id", "site_reference", "occurred_at", "recorded_at", "outcome", "not_completed_reason", "trap_condition", "exposure_start", "exposure_end"],
    rows: c.data.visits.filter((v) => siteOk(v.site_id) && inPeriod(v.occurred_at, f))
      .map((v) => [v.id, v.deployment_id, ref(v.site_id), v.occurred_at, v.recorded_at, outcomeLabels[v.outcome], v.not_completed_reason, v.trap_condition, v.exposure_started_at, v.exposure_ended_at]) };
  if (set === "findings") {
    const visitOf = new Map(c.data.visits.map((v) => [v.id, v]));
    const out: (string | number | null)[][] = [];
    for (const s of c.data.samples) {
      const visit = visitOf.get(s.visit_id);
      if (!siteOk(s.site_id) || !visit || !inPeriod(visit.occurred_at, f)) continue;
      const rs = c.data.results.filter((r) => r.sample_id === s.id);
      if (!rs.length) out.push([s.id, s.reference, ref(s.site_id), visit.occurred_at, methodLabels[s.method], "", "", "No result yet", "", "", "", "", "", "", ""]);
      for (const r of rs) {
        const v = c.data.versions.find((x) => x.result_id === r.id && x.version === r.current_version)!;
        out.push([s.id, s.reference, ref(s.site_id), visit.occurred_at, methodLabels[s.method], r.id, r.current_version, resultStatusLabels[v.status],
          v.status === "pending" ? "" : tx(v), v.quantity, v.unit, v.method, v.identified_by, v.laboratory, v.result_date]);
      }
    }
    return { head: ["sample_id", "sample_reference", "site_reference", "collected_at", "sample_method", "result_id", "result_version", "status", "species", "quantity", "unit", "id_method", "identified_by", "laboratory", "result_date"], rows: out };
  }
  if (set === "assessments") return { head: ["assessment_id", "site_reference", "version", "recorded_at", "likelihood", "consequence", "matrix_level", "final_level", "override_reason", "factors", "rationale", "results"],
    rows: c.assessments.assessments.filter((a) => siteOk(a.site_id) && inPeriod(a.created_at, f)).map((a) => {
      const v = c.assessments.versions.find((x) => x.assessment_id === a.id && x.version === a.current_version)!;
      return [a.id, ref(a.site_id), v.version, v.recorded_at, v.likelihood, v.consequence, v.matrix_level, v.final_level, v.override_reason, v.factors.join("; "), v.rationale, a.results.join("; ")];
    }) };
  if (set === "actions") return { head: ["action_id", "site_reference", "assessment_id", "title", "owner", "due_on", "status", "completed_at", "completion_note", "created_at"],
    rows: c.data.actions.filter((a) => siteOk(a.site_id) && (inPeriod(a.created_at, f) || a.status === "open"))
      .map((a) => [a.id, ref(a.site_id), a.assessment_id, a.title, person(a.owner_id, c.me), a.due_on, a.status, a.completed_at, a.completion_note, a.created_at]) };
  return { head: ["incursion_id", "reference", "title", "status", "species", "site_reference", "opened_at", "lead_officer", "response_radius_m", "response_lat", "response_lon", "findings", "steps_done"],
    rows: (c.incursions?.incursions ?? []).filter((i) => (!f.sites || i.sites.some((s) => f.sites!.has(s))) && (inPeriod(i.opened_at, f) || i.status !== "stood_down"))
      .map((i) => [i.id, i.reference, i.title, i.status, c.lists.taxa.find((t) => t.id === i.taxon_id)?.scientific_name ?? "", ref(i.site_id), i.opened_at,
        person(i.lead_officer_id, c.me), i.response_area?.radius_m ?? null, i.response_area?.lat ?? null, i.response_area?.lon ?? null, i.findings.length,
        c.incursions!.steps.filter((s) => s.incursion_id === i.id && s.status !== "to_do").length]) };
}
