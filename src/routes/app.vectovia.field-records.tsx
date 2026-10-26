import { createFileRoute, Link } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo, useRef, useState } from "react";
import { AppShell, EmptyState, ErrorState, Loading, appHead } from "@/components/app-shell";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { useSession } from "@/lib/session";
import { wsKey } from "@/lib/workspace";
import { day, methodLabels, newId, run, when, who, type Lists, type Sample, type SampleMethod, type Site } from "@/modules/vectovia/api";
import {
  controlKindLabels, fieldRpc, inspectionKindLabels, inspectionOutcomeLabels, loadAwaitingOfficial, loadControls, loadInspections, loadSurveySummary, loadSurveys, loadTests,
  needsProduct, pathogenLabels, testStatusLabels,
  type ControlKind, type InspectionKind, type InspectionOutcome, type Pathogen, type PathogenTest, type Survey, type TestStatus,
} from "@/modules/vectovia/field";
import { SurveillanceMap } from "@/modules/vectovia/map";
import { Field, StatusTag, selectClass, useDeployments, useLists, useMembersList, useResults, useSamples, useSites, useTraps, useVv } from "@/modules/vectovia/ui";

export const Route = createFileRoute("/app/vectovia/field-records")({
  head: () => appHead("Inspections and surveys · Vectovia", "Ad hoc inspections, delimiting surveys, pathogen tests and control actions."),
  component: FieldRecordsPage,
});

function FieldRecordsPage() {
  return (
    <AppShell product="vectovia" section="vectovia" title="Inspections and surveys"
      intro="Field work beyond routine trap checks: inspections such as larval dipping, delimiting surveys after a positive find, pathogen tests and control actions.">
      <FieldRecords />
    </AppShell>
  );
}

const btn = "rounded-md border border-primary px-3 py-1.5 text-sm font-medium text-primary disabled:opacity-60";
const primaryBtn = "rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy disabled:opacity-60";
const todayIso = () => new Date().toISOString().slice(0, 10);
const nowLocal = () => { const d = new Date(); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 16); };
const siteLabel = (s: Site | undefined) => (s ? `${s.reference} · ${s.name}` : "Site");

function useRefresh(ws: string) {
  const qc = useQueryClient();
  return () => void qc.invalidateQueries({ queryKey: ["ws", ws, "vv"] });
}

function FieldRecords() {
  const { ws, canRecord, canManage } = useVv();
  const { session } = useSession();
  const uid = session?.user.id;
  const sites = useSites(ws), lists = useLists(ws), samples = useSamples(ws);
  if (sites.isPending || lists.isPending || samples.isPending) return <Loading />;
  const err = sites.error ?? lists.error ?? samples.error;
  if (err) return <ErrorState error={err} />;
  const ctx = { ws, uid, canRecord, canManage, sites: sites.data!, lists: lists.data!, samples: samples.data! };
  return (
    <div className="space-y-10">
      <AwaitingOfficial {...ctx} />
      <Inspections {...ctx} />
      <Surveys {...ctx} />
      <Tests {...ctx} />
      <Controls {...ctx} />
    </div>
  );
}
type Ctx = { ws: string; uid: string | undefined; canRecord: boolean; canManage: boolean; sites: Site[]; lists: Lists; samples: Sample[] };

// ---------- Invasive finds awaiting official identification -----------------------------------------
function AwaitingOfficial({ ws, sites, lists, samples }: Ctx) {
  const q = useQuery({ queryKey: wsKey(ws, "vv", "awaiting-official"), queryFn: () => loadAwaitingOfficial(ws) });
  if (!q.data) return null;
  return (
    <section aria-labelledby="ao-h" className="space-y-2">
      <h2 id="ao-h" className="text-lg font-semibold text-primary">Invasive finds awaiting official identification <span className="font-normal text-muted-foreground">({q.data.length})</span></h2>
      {q.data.length === 0 ? <p className="text-sm text-muted-foreground">None. A provisional find of an invasive species appears here until its official (confirmed) identification is recorded.</p> : (
        <ul className="divide-y divide-border rounded-md border border-primary">
          {q.data.map((a) => (
            <li key={a.result_id} className="flex flex-wrap items-baseline gap-x-3 gap-y-1 px-3 py-2 text-sm">
              <StatusTag strong>{a.days_waiting > 7 ? "▲ " : ""}{a.days_waiting} day{a.days_waiting === 1 ? "" : "s"} waiting</StatusTag>
              <span className="font-medium text-primary"><i>{lists.taxa.find((t) => t.id === a.taxon_id)?.scientific_name}</i></span>
              <span className="text-primary">{samples.find((s) => s.id === a.sample_id)?.reference} · {siteLabel(sites.find((s) => s.id === a.site_id))}</span>
              <Link to="/app/vectovia/results" className="ml-auto text-primary underline">Record the official result</Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

// ---------- Inspections ----------------------------------------------------------------------------
function Inspections(ctx: Ctx) {
  const { ws, uid, canRecord, sites } = ctx;
  const q = useQuery({ queryKey: wsKey(ws, "vv", "inspections"), queryFn: () => loadInspections(ws) });
  const [open, setOpen] = useState(false);
  return (
    <section aria-labelledby="in-h" className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 id="in-h" className="text-lg font-semibold text-primary">Inspections</h2>
        {canRecord && !open ? <button type="button" className={primaryBtn} onClick={() => setOpen(true)}>Record an inspection</button> : null}
      </div>
      <p className="text-sm text-muted-foreground">Checks without a trap: dipping standing water, searching containers, visual checks. Samples taken here go to Results like trap samples.</p>
      {open ? <InspectionForm {...ctx} onDone={() => setOpen(false)} /> : null}
      {q.isError ? <ErrorState error={q.error} /> : !q.data ? <Loading /> : q.data.length === 0 ? <EmptyState title="No inspections yet">Record one with “Record an inspection”.</EmptyState> : (
        <ul className="divide-y divide-border rounded-md border border-border text-sm">
          {q.data.slice(0, 50).map((i) => (
            <li key={i.id} className="px-3 py-2">
              <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <StatusTag strong={i.outcome === "collected"}>{inspectionOutcomeLabels[i.outcome]}</StatusTag>
                <span className="font-medium text-primary">{inspectionKindLabels[i.kind]}</span>
                <span className="text-primary">{siteLabel(sites.find((s) => s.id === i.site_id))}</span>
                <span className="text-xs text-muted-foreground">{when(i.occurred_at)} · {who(i.officer_id, uid)}{i.survey_id ? " · part of a delimiting survey" : ""}</span>
              </div>
              {i.habitat || i.observations || i.not_completed_reason ? <p className="text-xs text-muted-foreground">{[i.habitat, i.observations, i.not_completed_reason].filter(Boolean).join(" · ")}</p> : null}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function InspectionForm({ ws, sites, onDone }: Ctx & { onDone: () => void }) {
  const refresh = useRefresh(ws);
  const surveys = useQuery({ queryKey: wsKey(ws, "vv", "surveys"), queryFn: () => loadSurveys(ws) });
  const id = useRef(newId());
  const active = sites.filter((s) => s.status === "active");
  const [site, setSite] = useState(active[0]?.id ?? "");
  const [at, setAt] = useState(nowLocal());
  const [kind, setKind] = useState<InspectionKind>("larval_dip");
  const [point, setPoint] = useState<{ lat: number; lon: number } | null>(null);
  const [habitat, setHabitat] = useState("");
  const [outcome, setOutcome] = useState<InspectionOutcome>("nothing_found");
  const [reason, setReason] = useState("");
  const [observations, setObservations] = useState("");
  const [survey, setSurvey] = useState("");
  const [samples, setSamples] = useState<{ id: string; method: SampleMethod; notes: string }[]>([]);
  const openSurveys = (surveys.data?.surveys ?? []).filter((s) => s.site_id === site && !s.ended_on);
  const s = sites.find((x) => x.id === site);
  const save = useMutation({
    mutationFn: () => run(fieldRpc.recordInspection(id.current, site, new Date(at).toISOString(), kind, point?.lat ?? null, point?.lon ?? null, habitat, outcome, reason, observations,
      survey || null, outcome === "collected" ? samples : [])),
    onSuccess: () => { refresh(); onDone(); },
  });
  const ok = site && at && (outcome !== "collected" || samples.length > 0) && (outcome !== "not_completed" || reason.trim().length >= 3);
  return (
    <form className="space-y-3 rounded-md border-t-2 border-accent bg-secondary p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id="ins-site" label="Site"><select id="ins-site" className={selectClass} value={site} onChange={(e) => { setSite(e.target.value); setSurvey(""); }}>
          {active.map((x) => <option key={x.id} value={x.id}>{siteLabel(x)}</option>)}</select></Field>
        <Field id="ins-kind" label="What kind"><select id="ins-kind" className={selectClass} value={kind} onChange={(e) => setKind(e.target.value as InspectionKind)}>
          {(Object.keys(inspectionKindLabels) as InspectionKind[]).map((k) => <option key={k} value={k}>{inspectionKindLabels[k]}</option>)}</select></Field>
        <Field id="ins-at" label="When"><Input id="ins-at" type="datetime-local" max={nowLocal()} className="bg-background" value={at} onChange={(e) => setAt(e.target.value)} /></Field>
      </div>
      {openSurveys.length ? (
        <Field id="ins-sv" label="Part of a delimiting survey? (optional)"><select id="ins-sv" className={selectClass} value={survey} onChange={(e) => setSurvey(e.target.value)}>
          <option value="">No</option>{openSurveys.map((x) => <option key={x.id} value={x.id}>{x.reference} ({x.radius_m} m)</option>)}</select></Field>
      ) : null}
      <fieldset className="space-y-1">
        <legend className="text-sm font-medium text-primary">Where (optional)</legend>
        <div className="flex flex-wrap items-center gap-2">
          <button type="button" className={btn} onClick={() => navigator.geolocation?.getCurrentPosition((p) => setPoint({ lat: +p.coords.latitude.toFixed(6), lon: +p.coords.longitude.toFixed(6) }))}>Use my location</button>
          {point ? <span className="text-xs text-primary">{point.lat}, {point.lon} <button type="button" className="underline" onClick={() => setPoint(null)}>Clear</button></span> : <span className="text-xs text-muted-foreground">or click the map</span>}
        </div>
        <SurveillanceMap label="Where the inspection was" height={220} keepView points={s && s.latitude !== null ? [{ id: "site", lat: s.latitude, lon: s.longitude!, label: s.name, muted: true }] : []}
          picked={point} onPick={(lat, lon) => setPoint({ lat: +lat.toFixed(6), lon: +lon.toFixed(6) })} pickHint="Click where the inspection was." />
      </fieldset>
      <Field id="ins-hab" label="Habitat (optional)" hint="For example: tyre stack with standing water, blocked gutter, plant-pot saucers."><Input id="ins-hab" className="bg-background" maxLength={1000} value={habitat} onChange={(e) => setHabitat(e.target.value)} /></Field>
      <fieldset>
        <legend className="text-sm font-medium text-primary">Outcome</legend>
        <div className="mt-1 flex flex-wrap gap-3">
          {(Object.keys(inspectionOutcomeLabels) as InspectionOutcome[]).map((o) => (
            <label key={o} className="flex items-center gap-2 text-sm"><input type="radio" name="ins-out" checked={outcome === o}
              onChange={() => { setOutcome(o); if (o === "collected" && !samples.length) setSamples([{ id: newId(), method: "larvae", notes: "" }]); }} />{inspectionOutcomeLabels[o]}</label>
          ))}
        </div>
      </fieldset>
      {outcome === "not_completed" ? <Field id="ins-why" label="Why not completed? (required)"><Input id="ins-why" className="bg-background" maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)} /></Field> : null}
      {outcome === "collected" ? (
        <fieldset className="space-y-2">
          <legend className="text-sm font-medium text-primary">Samples</legend>
          {samples.map((x, i) => (
            <div key={x.id} className="flex flex-wrap items-end gap-2">
              <Field id={`ins-sm-${i}`} label={`Sample ${i + 1}`}><select id={`ins-sm-${i}`} className={`${selectClass} w-48`} value={x.method}
                onChange={(e) => setSamples((a) => a.map((y, j) => (j === i ? { ...y, method: e.target.value as SampleMethod } : y)))}>
                {(Object.keys(methodLabels) as SampleMethod[]).map((m) => <option key={m} value={m}>{methodLabels[m]}</option>)}</select></Field>
              <Field id={`ins-sn-${i}`} label="Notes (optional)"><Input id={`ins-sn-${i}`} className="w-full max-w-xs bg-background" maxLength={1000} value={x.notes}
                onChange={(e) => setSamples((a) => a.map((y, j) => (j === i ? { ...y, notes: e.target.value } : y)))} /></Field>
              <button type="button" className="h-9 text-sm text-primary underline" onClick={() => setSamples((a) => a.filter((_, j) => j !== i))}>Remove</button>
            </div>
          ))}
          <button type="button" className={btn} onClick={() => setSamples((a) => [...a, { id: newId(), method: "larvae", notes: "" }])}>Add a sample</button>
        </fieldset>
      ) : null}
      <Field id="ins-obs" label="Observations (optional)"><Textarea id="ins-obs" className="bg-background" maxLength={4000} value={observations} onChange={(e) => setObservations(e.target.value)} /></Field>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || !ok}>{save.isPending ? "Saving…" : "Save inspection"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}

// ---------- Delimiting surveys -------------------------------------------------------------------------
function Surveys(ctx: Ctx) {
  const { ws, canManage, sites } = ctx;
  const q = useQuery({ queryKey: wsKey(ws, "vv", "surveys"), queryFn: () => loadSurveys(ws) });
  const [open, setOpen] = useState<string | "new" | null>(null);
  return (
    <section aria-labelledby="sv-h" className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 id="sv-h" className="text-lg font-semibold text-primary">Delimiting surveys</h2>
        {canManage && open !== "new" ? <button type="button" className={primaryBtn} onClick={() => setOpen("new")}>Start a delimiting survey</button> : null}
      </div>
      <p className="text-sm text-muted-foreground">After a positive find: survey the area around it to see how far the species has spread. UKHSA's plan uses a 200 to 300 m buffer at the first level of response.</p>
      {open === "new" ? <SurveyForm {...ctx} onDone={() => setOpen(null)} /> : null}
      {q.isError ? <ErrorState error={q.error} /> : !q.data ? <Loading /> : q.data.surveys.length === 0 ? <EmptyState title="No delimiting surveys">Start one after a positive find.</EmptyState> : (
        <ul className="divide-y divide-border rounded-md border border-border text-sm">
          {q.data.surveys.map((s) => (
            <li key={s.id}>
              <button type="button" aria-expanded={open === s.id} onClick={() => setOpen(open === s.id ? null : s.id)} className="flex w-full flex-wrap items-baseline gap-x-3 gap-y-1 px-3 py-2 text-left hover:bg-secondary/60">
                <StatusTag strong={!s.ended_on}>{s.ended_on ? "Ended" : "Open"}</StatusTag>
                <span className="font-semibold text-primary">{s.reference}</span>
                <span className="text-primary">{siteLabel(sites.find((x) => x.id === s.site_id))}</span>
                <span className="text-xs text-muted-foreground">{s.radius_m} m · from {day(s.started_on)}{s.ended_on ? ` to ${day(s.ended_on)}` : ""}</span>
              </button>
              {open === s.id ? <SurveyDetail {...ctx} survey={s} traps={q.data.traps.filter((t) => t.survey_id === s.id).map((t) => t.deployment_id)} /> : null}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function SurveyForm({ ws, sites, lists, onDone }: Ctx & { onDone: () => void }) {
  const refresh = useRefresh(ws);
  const results = useResults(ws);
  const samples = useSamples(ws);
  const id = useRef(newId());
  const active = sites.filter((s) => s.status === "active");
  const [site, setSite] = useState(active[0]?.id ?? "");
  const s = sites.find((x) => x.id === site);
  const [centre, setCentre] = useState<{ lat: number; lon: number } | null>(s && s.latitude !== null ? { lat: s.latitude, lon: s.longitude! } : null);
  const [radius, setRadius] = useState(300);
  const [start, setStart] = useState(todayIso());
  const [find, setFind] = useState("");
  const finds = useMemo(() => (results.data?.results ?? []).filter((r) => r.site_id === site).flatMap((r) => {
    const v = results.data!.versions.find((x) => x.result_id === r.id && x.version === r.current_version);
    return v && (v.status === "provisional" || v.status === "confirmed") ? [{ id: r.id, label: `${samples.data?.find((x) => x.id === r.sample_id)?.reference ?? "Sample"}: ${lists.taxa.find((t) => t.id === v.taxon_id)?.scientific_name ?? "species"}` }] : [];
  }), [results.data, samples.data, site, lists.taxa]);
  const save = useMutation({ mutationFn: () => run(fieldRpc.saveSurvey(id.current, site, find || null, centre!.lat, centre!.lon, radius, start, "")), onSuccess: () => { refresh(); onDone(); } });
  return (
    <form className="space-y-3 rounded-md border-t-2 border-accent bg-secondary p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id="sv-site" label="Site"><select id="sv-site" className={selectClass} value={site} onChange={(e) => { const v = e.target.value; setSite(v); setFind("");
          const x = sites.find((y) => y.id === v); setCentre(x && x.latitude !== null ? { lat: x.latitude, lon: x.longitude! } : null); }}>
          {active.map((x) => <option key={x.id} value={x.id}>{siteLabel(x)}</option>)}</select></Field>
        <Field id="sv-find" label="Positive find it follows (optional)"><select id="sv-find" className={selectClass} value={find} onChange={(e) => setFind(e.target.value)}>
          <option value="">Not linked</option>{finds.map((f) => <option key={f.id} value={f.id}>{f.label}</option>)}</select></Field>
        <Field id="sv-start" label="Starts"><Input id="sv-start" type="date" className="bg-background" value={start} onChange={(e) => setStart(e.target.value)} /></Field>
      </div>
      <Field id="sv-r" label={`Radius: ${radius} m`} hint="200 to 300 m is the usual first buffer; widen it if further positives are found.">
        <input id="sv-r" type="range" min={50} max={2000} step={25} value={radius} onChange={(e) => setRadius(Number(e.target.value))} className="w-full accent-[var(--signal-teal)]" />
      </Field>
      <p className="text-xs text-muted-foreground">Click the map to set the centre (usually where the positive was found).</p>
      <SurveillanceMap label="Delimiting survey area" height={280} keepView points={[]} picked={centre}
        circles={centre ? [{ id: "c", lat: centre.lat, lon: centre.lon, radius_m: radius, label: `${radius} m survey area` }] : []}
        onPick={(lat, lon) => setCentre({ lat: +lat.toFixed(6), lon: +lon.toFixed(6) })} pickHint="Click to set the centre of the survey." />
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || !site || !centre}>{save.isPending ? "Starting…" : "Start survey"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}

function SurveyDetail({ ws, survey, traps, canRecord, canManage }: Ctx & { survey: Survey; traps: string[] }) {
  const refresh = useRefresh(ws);
  const summary = useQuery({ queryKey: wsKey(ws, "vv", "survey-summary", survey.id), queryFn: () => loadSurveySummary(survey.id) });
  const deployments = useDeployments(ws), trapList = useTraps(ws);
  const [dep, setDep] = useState("");
  const [ending, setEnding] = useState(false);
  const [endOn, setEndOn] = useState(todayIso());
  const [outcome, setOutcome] = useState("");
  const link = useMutation({ mutationFn: () => run(fieldRpc.linkTrap(survey.id, dep)), onSuccess: () => { setDep(""); refresh(); } });
  const end = useMutation({ mutationFn: () => run(fieldRpc.endSurvey(survey.id, endOn, outcome)), onSuccess: refresh });
  const activeDeps = (deployments.data ?? []).filter((d) => !d.ended_at && !traps.includes(d.id));
  const trapName = (depId: string) => trapList.data?.find((t) => t.id === deployments.data?.find((d) => d.id === depId)?.trap_id)?.identifier ?? "Trap";
  const sm = summary.data;
  return (
    <div className="space-y-3 border-t border-border bg-background p-3 text-sm">
      {sm ? (
        <p className="text-primary">{sm.inspections} inspection{sm.inspections === 1 ? "" : "s"} · {sm.traps} trap{sm.traps === 1 ? "" : "s"} · {sm.samples} sample{sm.samples === 1 ? "" : "s"}:
          {" "}{sm.positive_finds} positive{sm.invasive_finds ? ` (${sm.invasive_finds} invasive)` : ""}, {sm.negative_finds} negative, {sm.awaiting_results} awaiting results</p>
      ) : null}
      <SurveillanceMap label={`${survey.reference} survey area`} height={240} points={[]} circles={[{ id: survey.id, lat: survey.centre_lat, lon: survey.centre_lon, radius_m: survey.radius_m, label: `${survey.radius_m} m` }]} />
      {traps.length ? <p className="text-xs text-muted-foreground">Traps in the survey: {traps.map(trapName).join(", ")}. Their samples from the start date on count towards it.</p> : null}
      {survey.outcome ? <p className="text-primary">Outcome: {survey.outcome}</p> : null}
      {!survey.ended_on && canRecord && activeDeps.length ? (
        <div className="flex flex-wrap items-end gap-2">
          <Field id={`sv-dep-${survey.id}`} label="Add a deployed trap to this survey"><select id={`sv-dep-${survey.id}`} className={`${selectClass} w-60`} value={dep} onChange={(e) => setDep(e.target.value)}>
            <option value="">Choose a trap</option>{activeDeps.map((d) => <option key={d.id} value={d.id}>{trapName(d.id)}</option>)}</select></Field>
          <button type="button" className={btn} disabled={!dep || link.isPending} onClick={() => link.mutate()}>Add</button>
          {link.isError ? <ErrorState error={link.error} /> : null}
        </div>
      ) : null}
      {!survey.ended_on && canManage ? (ending ? (
        <div className="space-y-2 rounded-md border border-border p-2">
          <Field id={`sv-end-${survey.id}`} label="Ended on"><Input id={`sv-end-${survey.id}`} type="date" className="w-44" min={survey.started_on} max={todayIso()} value={endOn} onChange={(e) => setEndOn(e.target.value)} /></Field>
          <Field id={`sv-out-${survey.id}`} label="Outcome (required)" hint="What the survey found, and why it can end."><Textarea id={`sv-out-${survey.id}`} maxLength={4000} value={outcome} onChange={(e) => setOutcome(e.target.value)} /></Field>
          {end.isError ? <ErrorState error={end.error} /> : null}
          <button type="button" className={btn} disabled={end.isPending || outcome.trim().length < 10} onClick={() => end.mutate()}>End survey</button>
        </div>
      ) : <button type="button" className="text-sm text-primary underline" onClick={() => setEnding(true)}>End this survey</button>) : null}
    </div>
  );
}

// ---------- Pathogen tests --------------------------------------------------------------------------
function Tests(ctx: Ctx) {
  const { ws, canRecord, samples, sites } = ctx;
  const q = useQuery({ queryKey: wsKey(ws, "vv", "pathogen-tests"), queryFn: () => loadTests(ws) });
  const [open, setOpen] = useState<string | "new" | null>(null);
  return (
    <section aria-labelledby="pt-h" className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 id="pt-h" className="text-lg font-semibold text-primary">Pathogen tests</h2>
        {canRecord && open !== "new" ? <button type="button" className={primaryBtn} onClick={() => setOpen("new")}>Record a test</button> : null}
      </div>
      {open === "new" ? <TestForm {...ctx} onDone={() => setOpen(null)} /> : null}
      {q.isError ? <ErrorState error={q.error} /> : !q.data ? <Loading /> : q.data.length === 0 ? <p className="text-sm text-muted-foreground">No pathogen tests recorded.</p> : (
        <ul className="divide-y divide-border rounded-md border border-border text-sm">
          {q.data.map((t) => (
            <li key={t.id} className="px-3 py-2">
              <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <StatusTag strong={t.status === "detected"}>{t.status === "detected" ? "▲ " : ""}{testStatusLabels[t.status]}</StatusTag>
                <span className="font-medium text-primary">{t.pathogen === "other" ? t.pathogen_other : pathogenLabels[t.pathogen]}</span>
                <span className="text-primary">{samples.find((s) => s.id === t.sample_id)?.reference} · {siteLabel(sites.find((s) => s.id === t.site_id))}</span>
                <span className="text-xs text-muted-foreground">{[t.method, t.laboratory, t.lab_reference].filter(Boolean).join(" · ")}{t.result_date ? ` · ${day(t.result_date)}` : ""}</span>
                {canRecord && open !== t.id ? <button type="button" className="ml-auto text-sm text-primary underline" onClick={() => setOpen(t.id)}>Update</button> : null}
              </div>
              {open === t.id ? <TestForm {...ctx} test={t} onDone={() => setOpen(null)} /> : null}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function TestForm({ ws, samples, test, onDone }: Ctx & { test?: PathogenTest; onDone: () => void }) {
  const refresh = useRefresh(ws);
  const id = useRef(test?.id ?? newId());
  const [sample, setSample] = useState(test?.sample_id ?? samples[0]?.id ?? "");
  const [v, setV] = useState({ pathogen: (test?.pathogen ?? "dengue") as Pathogen, pathogen_other: test?.pathogen_other ?? "", method: test?.method ?? "", laboratory: test?.laboratory ?? "",
    lab_reference: test?.lab_reference ?? "", status: (test?.status ?? "pending") as TestStatus, result_date: test?.result_date ?? "", note: test?.note ?? "" });
  const [reason, setReason] = useState("");
  const set = <K extends keyof typeof v>(k: K, x: (typeof v)[K]) => setV((y) => ({ ...y, [k]: x }));
  const save = useMutation({ mutationFn: () => run(fieldRpc.saveTest(id.current, sample, v, reason)), onSuccess: () => { refresh(); onDone(); } });
  const changingResult = !!test && test.status !== "pending";
  const ok = sample && (v.pathogen !== "other" || v.pathogen_other.trim().length >= 2) && (v.status === "pending" || v.result_date) && (!changingResult || reason.trim().length >= 5);
  return (
    <form className="mt-2 space-y-3 rounded-md border-t-2 border-accent bg-secondary p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id={`pt-s-${id.current}`} label="Sample"><select id={`pt-s-${id.current}`} className={selectClass} value={sample} disabled={!!test} onChange={(e) => setSample(e.target.value)}>
          {samples.map((s) => <option key={s.id} value={s.id}>{s.reference} · {methodLabels[s.method]}</option>)}</select></Field>
        <Field id={`pt-p-${id.current}`} label="Pathogen"><select id={`pt-p-${id.current}`} className={selectClass} value={v.pathogen} disabled={!!test} onChange={(e) => set("pathogen", e.target.value as Pathogen)}>
          {(Object.keys(pathogenLabels) as Pathogen[]).map((p) => <option key={p} value={p}>{pathogenLabels[p]}</option>)}</select></Field>
        {v.pathogen === "other" ? <Field id={`pt-o-${id.current}`} label="Which pathogen?"><Input id={`pt-o-${id.current}`} className="bg-background" maxLength={120} disabled={!!test} value={v.pathogen_other} onChange={(e) => set("pathogen_other", e.target.value)} /></Field> : null}
        <Field id={`pt-m-${id.current}`} label="Method (optional)"><Input id={`pt-m-${id.current}`} className="bg-background" maxLength={200} value={v.method} onChange={(e) => set("method", e.target.value)} placeholder="e.g. RT-PCR" /></Field>
        <Field id={`pt-l-${id.current}`} label="Laboratory (optional)"><Input id={`pt-l-${id.current}`} className="bg-background" maxLength={200} value={v.laboratory} onChange={(e) => set("laboratory", e.target.value)} /></Field>
        <Field id={`pt-r-${id.current}`} label="Lab reference (optional)"><Input id={`pt-r-${id.current}`} className="bg-background" maxLength={100} value={v.lab_reference} onChange={(e) => set("lab_reference", e.target.value)} /></Field>
        <Field id={`pt-st-${id.current}`} label="Result"><select id={`pt-st-${id.current}`} className={selectClass} value={v.status} onChange={(e) => set("status", e.target.value as TestStatus)}>
          {(Object.keys(testStatusLabels) as TestStatus[]).map((s) => <option key={s} value={s}>{testStatusLabels[s]}</option>)}</select></Field>
        {v.status !== "pending" ? <Field id={`pt-d-${id.current}`} label="Result date"><Input id={`pt-d-${id.current}`} type="date" max={todayIso()} className="bg-background" value={v.result_date} onChange={(e) => set("result_date", e.target.value)} /></Field> : null}
      </div>
      <Field id={`pt-n-${id.current}`} label="Note (optional)"><Input id={`pt-n-${id.current}`} className="bg-background" maxLength={2000} value={v.note} onChange={(e) => set("note", e.target.value)} /></Field>
      {changingResult ? <Field id={`pt-why-${id.current}`} label="Why is the result changing? (required)"><Input id={`pt-why-${id.current}`} className="bg-background" maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} /></Field> : null}
      <p className="text-xs text-muted-foreground">Attach the lab report to the sample on the Results page. Every change keeps the earlier result in the history.</p>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || !ok}>{save.isPending ? "Saving…" : test ? "Save result" : "Record test"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}

// ---------- Control actions --------------------------------------------------------------------------
function Controls(ctx: Ctx) {
  const { ws, uid, canRecord, canManage, sites } = ctx;
  const refresh = useRefresh(ws);
  const q = useQuery({ queryKey: wsKey(ws, "vv", "controls"), queryFn: () => loadControls(ws) });
  const [open, setOpen] = useState(false);
  const [withdrawing, setWithdrawing] = useState<string | null>(null);
  const [why, setWhy] = useState("");
  const withdraw = useMutation({ mutationFn: (id: string) => run(fieldRpc.withdrawControl(id, why)), onSuccess: () => { setWithdrawing(null); setWhy(""); refresh(); } });
  return (
    <section aria-labelledby="ca-h" className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 id="ca-h" className="text-lg font-semibold text-primary">Control actions</h2>
        {canRecord && !open ? <button type="button" className={primaryBtn} onClick={() => setOpen(true)}>Record a control action</button> : null}
      </div>
      {open ? <ControlForm {...ctx} onDone={() => setOpen(false)} /> : null}
      {q.isError ? <ErrorState error={q.error} /> : !q.data ? <Loading /> : q.data.length === 0 ? <p className="text-sm text-muted-foreground">No control actions recorded.</p> : (
        <ul className="divide-y divide-border rounded-md border border-border text-sm">
          {q.data.map((c) => (
            <li key={c.id} className={`px-3 py-2 ${c.withdrawn_at ? "opacity-70" : ""}`}>
              <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                {c.withdrawn_at ? <StatusTag>Withdrawn</StatusTag> : null}
                <span className="font-medium text-primary">{controlKindLabels[c.kind]}</span>
                <span className="text-primary">{siteLabel(sites.find((s) => s.id === c.site_id))} · {day(c.occurred_on)}</span>
                <span className="text-xs text-muted-foreground">{[c.product, c.active_substance, c.quantity, c.area_description, c.operator].filter(Boolean).join(" · ")}
                  {c.supervised_by ? ` · supervised by ${who(c.supervised_by, uid)}` : ""} · recorded by {who(c.recorded_by, uid)}</span>
                {canManage && !c.withdrawn_at && withdrawing !== c.id ? <button type="button" className="ml-auto text-sm text-primary underline" onClick={() => setWithdrawing(c.id)}>Withdraw</button> : null}
              </div>
              {c.withdrawn_at ? <p className="text-xs text-muted-foreground">Withdrawn {when(c.withdrawn_at)}: {c.withdrawn_reason}</p> : null}
              {withdrawing === c.id ? (
                <div className="mt-1 flex flex-wrap items-end gap-2">
                  <Field id={`ca-w-${c.id}`} label="Why withdraw it? (required)"><Input id={`ca-w-${c.id}`} className="w-full max-w-sm" maxLength={500} value={why} onChange={(e) => setWhy(e.target.value)} /></Field>
                  <button type="button" className={btn} disabled={withdraw.isPending || why.trim().length < 5} onClick={() => withdraw.mutate(c.id)}>Withdraw</button>
                  <button type="button" className="text-sm text-primary underline" onClick={() => setWithdrawing(null)}>Cancel</button>
                  {withdraw.isError ? <ErrorState error={withdraw.error} /> : null}
                </div>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function ControlForm({ ws, uid, sites, onDone }: Ctx & { onDone: () => void }) {
  const refresh = useRefresh(ws);
  const members = useMembersList(ws);
  const surveys = useQuery({ queryKey: wsKey(ws, "vv", "surveys"), queryFn: () => loadSurveys(ws) });
  const id = useRef(newId());
  const active = sites.filter((s) => s.status === "active");
  const [site, setSite] = useState(active[0]?.id ?? "");
  const [survey, setSurvey] = useState("");
  const [v, setV] = useState({ kind: "source_reduction" as ControlKind, occurred_on: todayIso(), product: "", substance: "", quantity: "", area: "", operator: "", supervised_by: "", notes: "" });
  const set = <K extends keyof typeof v>(k: K, x: (typeof v)[K]) => setV((y) => ({ ...y, [k]: x }));
  const save = useMutation({ mutationFn: () => run(fieldRpc.recordControl(id.current, site, survey || null, v)), onSuccess: () => { refresh(); onDone(); } });
  const openSurveys = (surveys.data?.surveys ?? []).filter((s) => s.site_id === site);
  const ok = site && v.occurred_on && (!needsProduct(v.kind) || v.product.trim().length >= 2);
  return (
    <form className="space-y-3 rounded-md border-t-2 border-accent bg-secondary p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id="ca-site" label="Site"><select id="ca-site" className={selectClass} value={site} onChange={(e) => { setSite(e.target.value); setSurvey(""); }}>
          {active.map((x) => <option key={x.id} value={x.id}>{siteLabel(x)}</option>)}</select></Field>
        <Field id="ca-kind" label="What was done"><select id="ca-kind" className={selectClass} value={v.kind} onChange={(e) => set("kind", e.target.value as ControlKind)}>
          {(Object.keys(controlKindLabels) as ControlKind[]).map((k) => <option key={k} value={k}>{controlKindLabels[k]}</option>)}</select></Field>
        <Field id="ca-on" label="Date"><Input id="ca-on" type="date" max={todayIso()} className="bg-background" value={v.occurred_on} onChange={(e) => set("occurred_on", e.target.value)} /></Field>
        <Field id="ca-p" label={needsProduct(v.kind) ? "Product (required)" : "Product (optional)"}><Input id="ca-p" className="bg-background" maxLength={200} value={v.product} onChange={(e) => set("product", e.target.value)} /></Field>
        <Field id="ca-s" label="Active substance (optional)"><Input id="ca-s" className="bg-background" maxLength={200} value={v.substance} onChange={(e) => set("substance", e.target.value)} /></Field>
        <Field id="ca-q" label="Quantity (optional)"><Input id="ca-q" className="bg-background" maxLength={200} value={v.quantity} onChange={(e) => set("quantity", e.target.value)} placeholder="e.g. 2 kg" /></Field>
        <Field id="ca-o" label="Done by (optional)" hint="Officer or contractor."><Input id="ca-o" className="bg-background" maxLength={200} value={v.operator} onChange={(e) => set("operator", e.target.value)} /></Field>
        <Field id="ca-sup" label="Supervised by (optional)"><select id="ca-sup" className={selectClass} value={v.supervised_by} onChange={(e) => set("supervised_by", e.target.value)}>
          <option value="">No one recorded</option>{(members.data ?? []).map((m) => <option key={m.user_id} value={m.user_id}>{who(m.user_id, uid)} ({m.role})</option>)}</select></Field>
        {openSurveys.length ? <Field id="ca-sv" label="Part of a delimiting survey? (optional)"><select id="ca-sv" className={selectClass} value={survey} onChange={(e) => setSurvey(e.target.value)}>
          <option value="">No</option>{openSurveys.map((x) => <option key={x.id} value={x.id}>{x.reference}</option>)}</select></Field> : null}
      </div>
      <Field id="ca-a" label="Area treated (optional)"><Input id="ca-a" className="bg-background" maxLength={1000} value={v.area} onChange={(e) => set("area", e.target.value)} placeholder="e.g. drains and tyre stack by gate 3" /></Field>
      <Field id="ca-n" label="Notes (optional)"><Textarea id="ca-n" className="bg-background" maxLength={2000} value={v.notes} onChange={(e) => set("notes", e.target.value)} /></Field>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || !ok}>{save.isPending ? "Saving…" : "Save control action"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
      </div>
      <p className="text-xs text-muted-foreground">Records can't be edited. If something was recorded in error, a manager withdraws it with a reason; it stays in the history.</p>
    </form>
  );
}
