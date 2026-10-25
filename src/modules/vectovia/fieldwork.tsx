// Field work screens (V2a): deploying and moving traps, the visit form, and
// visit records. Built for fast entry in the field: sensible defaults (now,
// you, working, exposure since the last visit), big tap targets, and a clear
// choice between "samples collected", "no catch" and "not completed".
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useRef, useState } from "react";
import { ErrorState } from "@/components/app-shell";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import {
  conditionLabels, day, endReasonLabels, fieldRpc, fromLocalInput, methodLabels, newId, outcomeLabels, run, toLocalInput, when, who,
  type Condition, type Deployment, type EndReason, type MemberRow, type Outcome, type Sample, type SampleMethod, type Site, type Trap, type Visit,
} from "./api";
import { toGridRef } from "./grid";
import { SurveillanceMap } from "./map";
import { Field, History, StatusTag, selectClass } from "./ui";
import { Attachments, uploadMany } from "./attachments";
import { acceptAttr } from "./files";

const invalidate = (qc: ReturnType<typeof useQueryClient>, ws: string) => qc.invalidateQueries({ queryKey: ["ws", ws, "vv"] });

function OfficerSelect({ id, value, onChange, members, uid }: { id: string; value: string; onChange: (v: string) => void; members: MemberRow[]; uid: string | undefined }) {
  return (
    <select id={id} className={selectClass} value={value} onChange={(e) => onChange(e.target.value)}>
      {members.map((m) => <option key={m.user_id} value={m.user_id}>{who(m.user_id, uid)}</option>)}
    </select>
  );
}

/** Deploy a trap at a site, or (with `from`) move it from its current deployment. */
export function DeployForm({ ws, trap, sites, members, uid, from, onDone }: {
  ws: string; trap: Trap; sites: Site[]; members: MemberRow[]; uid: string | undefined; from?: Deployment; onDone: () => void;
}) {
  const qc = useQueryClient();
  const id = useRef(newId());
  const active = sites.filter((s) => s.status === "active" && s.id !== from?.site_id);
  const [site, setSite] = useState(active[0]?.id ?? "");
  const chosen = sites.find((s) => s.id === site);
  const [point, setPoint] = useState<{ lat: number; lon: number } | null>(null);
  const [placement, setPlacement] = useState("");
  const [at, setAt] = useState(toLocalInput(null));
  const [officer, setOfficer] = useState(uid ?? "");
  const [interval, setInterval] = useState(from?.visit_interval_days ?? 7);
  const save = useMutation({
    mutationFn: () => run(from
      ? fieldRpc.move(from.id, id.current, site, point?.lat ?? null, point?.lon ?? null, placement, fromLocalInput(at)!, officer || null, interval)
      : fieldRpc.deploy(id.current, ws, trap.id, site, point?.lat ?? null, point?.lon ?? null, placement, fromLocalInput(at)!, officer || null, interval)),
    onSuccess: () => { invalidate(qc, ws); onDone(); },
  });
  const sitePoint = chosen?.latitude != null ? { lat: chosen.latitude, lon: chosen.longitude! } : null;
  return (
    <form className="space-y-3 rounded-md border-t-2 border-accent bg-secondary p-4" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <p className="font-semibold text-primary">{from ? `Move ${trap.identifier} to another site` : `Deploy ${trap.identifier}`}</p>
      {from ? <p className="text-sm text-muted-foreground">Its current deployment ends as “moved” and a new one starts. Both are kept in its history.</p> : null}
      <div className="grid gap-3 sm:grid-cols-2">
        <Field id="df-site" label="Site">
          <select id="df-site" className={selectClass} value={site} onChange={(e) => { setSite(e.target.value); setPoint(null); }}>
            {active.length ? active.map((s) => <option key={s.id} value={s.id}>{s.reference} · {s.name}</option>) : <option value="">No active sites</option>}
          </select>
        </Field>
        <Field id="df-at" label={from ? "Moved at" : "Deployed at"}><Input id="df-at" type="datetime-local" className="bg-background" value={at} max={toLocalInput(null)} onChange={(e) => setAt(e.target.value)} /></Field>
        <Field id="df-off" label="Responsible officer"><OfficerSelect id="df-off" value={officer} onChange={setOfficer} members={members} uid={uid} /></Field>
        <Field id="df-int" label="Visit every (days)" hint="Used to show when a visit is due."><Input id="df-int" type="number" min={1} max={60} className="bg-background" value={interval} onChange={(e) => setInterval(Math.max(1, Math.min(60, Number(e.target.value) || 7)))} /></Field>
      </div>
      <Field id="df-place" label="Exact placement (optional)" hint="e.g. north fence, 1 m above ground, in shade."><Input id="df-place" className="bg-background" maxLength={1000} value={placement} onChange={(e) => setPlacement(e.target.value)} /></Field>
      <div>
        <p className="text-sm font-medium text-primary">Precise location</p>
        <p className="text-xs text-muted-foreground">{point ? `Set: ${toGridRef(point.lat, point.lon, 10) ?? `${point.lat.toFixed(5)}, ${point.lon.toFixed(5)}`}` : "Uses the site's location unless you click the map or use your location."}</p>
        <div className="mt-1 flex gap-2">
          <button type="button" className="h-8 rounded-md border border-primary bg-background px-3 text-sm text-primary"
            onClick={() => navigator.geolocation?.getCurrentPosition((p) => setPoint({ lat: +p.coords.latitude.toFixed(6), lon: +p.coords.longitude.toFixed(6) }), undefined, { enableHighAccuracy: true, timeout: 15000 })}>Use my location</button>
          {point ? <button type="button" className="h-8 text-sm text-primary underline" onClick={() => setPoint(null)}>Use the site's location</button> : null}
        </div>
        <div className="mt-2"><SurveillanceMap label="Trap location" height={220} points={sitePoint ? [{ id: "site", lat: sitePoint.lat, lon: sitePoint.lon, label: "Site", muted: true }] : []}
          picked={point} onPick={(lat, lon) => setPoint({ lat: +lat.toFixed(6), lon: +lon.toFixed(6) })} /></div>
      </div>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" disabled={save.isPending || !site || !at} className="rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy disabled:opacity-60">{from ? "Move trap" : "Deploy trap"}</button>
        <button type="button" onClick={onDone} className="rounded-md border border-primary px-4 py-2 text-sm text-primary">Cancel</button>
      </div>
    </form>
  );
}

export function EndDeploymentForm({ ws, deployment, onDone }: { ws: string; deployment: Deployment; onDone: () => void }) {
  const qc = useQueryClient();
  const [reason, setReason] = useState<EndReason>("removed");
  const [at, setAt] = useState(toLocalInput(null));
  const [note, setNote] = useState("");
  const save = useMutation({
    mutationFn: () => run(fieldRpc.end(deployment.id, fromLocalInput(at)!, reason, note)),
    onSuccess: () => { invalidate(qc, ws); onDone(); },
  });
  return (
    <form className="space-y-3 rounded-md border-t-2 border-accent bg-secondary p-4" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <p className="font-semibold text-primary">End this deployment</p>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id="ed-r" label="Why">
          <select id="ed-r" className={selectClass} value={reason} onChange={(e) => setReason(e.target.value as EndReason)}>
            {(["removed", "damaged", "lost", "programme_ended"] as EndReason[]).map((r) => <option key={r} value={r}>{endReasonLabels[r]}</option>)}
          </select>
        </Field>
        <Field id="ed-at" label="Ended at"><Input id="ed-at" type="datetime-local" className="bg-background" value={at} max={toLocalInput(null)} onChange={(e) => setAt(e.target.value)} /></Field>
        <Field id="ed-n" label="Note (optional)"><Input id="ed-n" className="bg-background" maxLength={1000} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
      </div>
      <p className="text-xs text-muted-foreground">To take the trap to another site, use “Move” instead. A damaged trap is marked damaged; a lost one is retired.</p>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" disabled={save.isPending} className="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground disabled:opacity-60">End deployment</button>
        <button type="button" onClick={onDone} className="rounded-md border border-primary px-4 py-2 text-sm text-primary">Cancel</button>
      </div>
    </form>
  );
}

type SampleRow = { id: string; reference: string; method: SampleMethod; notes: string };
const emptySample = (): SampleRow => ({ id: newId(), reference: "", method: "adult_trap_catch", notes: "" });

/** The field visit form. Defaults: now, you, working, exposure since the last visit (or deployment). */
export function VisitForm({ ws, deployment, lastVisitAt, members, uid, trapLabel, siteLabel, onDone }: {
  ws: string; deployment: Deployment; lastVisitAt: string | null; members: MemberRow[]; uid: string | undefined;
  trapLabel: string; siteLabel: string; onDone: () => void;
}) {
  const qc = useQueryClient();
  const id = useRef(newId());
  const [at, setAt] = useState(toLocalInput(null));
  const [officer, setOfficer] = useState(uid ?? "");
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [reason, setReason] = useState("");
  const [condition, setCondition] = useState<Condition>("working");
  const [observations, setObservations] = useState("");
  const [expStart, setExpStart] = useState(toLocalInput(lastVisitAt ?? deployment.started_at));
  const [samples, setSamples] = useState<SampleRow[]>([emptySample()]);
  const [photos, setPhotos] = useState<File[]>([]);
  const [step, setStep] = useState("");
  const save = useMutation({
    mutationFn: async () => {
      setStep("Saving the visit");
      await run(fieldRpc.recordVisit(id.current, deployment.id, {
      occurred_at: fromLocalInput(at)!, officer: officer || null, outcome: outcome!, reason, condition, observations,
      exposure_start: outcome === "not_completed" ? null : fromLocalInput(expStart), exposure_end: outcome === "not_completed" ? null : fromLocalInput(at),
      samples: outcome === "collected" ? samples : [],
      }));
      // The visit is saved first; photos follow. If an upload fails, the visit is still recorded.
      if (photos.length) await uploadMany("visit", id.current, photos, "", setStep);
    },
    onSuccess: () => { invalidate(qc, ws); onDone(); },
    onError: () => invalidate(qc, ws),
  });
  const problems = [
    !outcome ? "Choose what happened." : null,
    outcome === "not_completed" && reason.trim().length < 3 ? "Say why collection wasn't completed." : null,
    outcome === "collected" && !samples.length ? "Add at least one sample." : null,
    outcome !== "not_completed" && expStart && at && expStart > at ? "Exposure can't start after the visit." : null,
  ].filter(Boolean) as string[];
  const choice = (o: Outcome, hint: string) => (
    <button type="button" aria-pressed={outcome === o} onClick={() => setOutcome(o)}
      className={`flex-1 rounded-md px-3 py-3 text-left text-sm ${outcome === o ? "bg-primary text-primary-foreground" : "border border-border bg-background text-primary hover:border-accent"}`}>
      <span className="block font-semibold">{outcomeLabels[o]}</span><span className={`block text-xs ${outcome === o ? "" : "text-muted-foreground"}`}>{hint}</span>
    </button>
  );
  return (
    <form className="space-y-4 rounded-md border-2 border-accent bg-background p-4" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div>
        <p className="font-semibold text-primary">Record a visit · {trapLabel}</p>
        <p className="text-xs text-muted-foreground">{siteLabel}{lastVisitAt ? ` · last visit ${when(lastVisitAt)}` : ` · deployed ${when(deployment.started_at)}`}</p>
      </div>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id="vf-at" label="Visited at"><Input id="vf-at" type="datetime-local" className="bg-background" value={at} max={toLocalInput(null)} onChange={(e) => setAt(e.target.value)} /></Field>
        <Field id="vf-off" label="Officer"><OfficerSelect id="vf-off" value={officer} onChange={setOfficer} members={members} uid={uid} /></Field>
        <Field id="vf-cond" label="Trap condition">
          <select id="vf-cond" className={selectClass} value={condition} onChange={(e) => setCondition(e.target.value as Condition)}>
            {(Object.keys(conditionLabels) as Condition[]).map((c) => <option key={c} value={c}>{conditionLabels[c]}</option>)}
          </select>
        </Field>
      </div>
      <fieldset>
        <legend className="text-sm font-medium text-primary">What happened?</legend>
        <div className="mt-1 flex flex-col gap-2 sm:flex-row">
          {choice("collected", "Something was collected to identify")}
          {choice("no_catch", "Checked: nothing caught")}
          {choice("not_completed", "Couldn't collect (say why)")}
        </div>
      </fieldset>
      {outcome === "not_completed" ? (
        <Field id="vf-why" label="Why wasn't collection completed?"><Input id="vf-why" className="bg-background" maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. gate locked, trap missing, unsafe" /></Field>
      ) : outcome ? (
        <Field id="vf-exp" label="Trap exposed since" hint="Collection effort: from when the trap was last emptied (or deployed) until this visit.">
          <Input id="vf-exp" type="datetime-local" className="max-w-xs bg-background" value={expStart} max={at} onChange={(e) => setExpStart(e.target.value)} />
        </Field>
      ) : null}
      {outcome === "collected" ? (
        <fieldset className="space-y-2">
          <legend className="text-sm font-medium text-primary">Samples</legend>
          <p className="text-xs text-muted-foreground">Leave the reference blank to have one numbered for you, or type the label on the tube.</p>
          {samples.map((s, i) => (
            <div key={s.id} className="grid gap-2 sm:grid-cols-[10rem_12rem_1fr_auto] sm:items-end">
              <Field id={`vs-r-${i}`} label={`Sample ${i + 1} reference`}><Input id={`vs-r-${i}`} className="bg-background" maxLength={60} value={s.reference} placeholder="Auto"
                onChange={(e) => { const v = e.target.value; setSamples((x) => x.map((y) => (y.id === s.id ? { ...y, reference: v } : y))); }} /></Field>
              <Field id={`vs-m-${i}`} label="Method">
                <select id={`vs-m-${i}`} className={selectClass} value={s.method} onChange={(e) => { const v = e.target.value as SampleMethod; setSamples((x) => x.map((y) => (y.id === s.id ? { ...y, method: v } : y))); }}>
                  {(Object.keys(methodLabels) as SampleMethod[]).map((m) => <option key={m} value={m}>{methodLabels[m]}</option>)}
                </select>
              </Field>
              <Field id={`vs-n-${i}`} label="Note (optional)"><Input id={`vs-n-${i}`} className="bg-background" maxLength={1000} value={s.notes}
                onChange={(e) => { const v = e.target.value; setSamples((x) => x.map((y) => (y.id === s.id ? { ...y, notes: v } : y))); }} /></Field>
              {samples.length > 1 ? <button type="button" className="h-9 text-sm text-primary underline" onClick={() => setSamples((x) => x.filter((y) => y.id !== s.id))}>Remove</button> : <span />}
            </div>
          ))}
          <button type="button" className="text-sm font-medium text-primary underline" onClick={() => setSamples((x) => [...x, emptySample()])}>Add another sample</button>
        </fieldset>
      ) : null}
      <Field id="vf-obs" label="Observations (optional)" hint="Weather, standing water, activity, anything unusual."><Textarea id="vf-obs" className="min-h-20 bg-background" maxLength={4000} value={observations} onChange={(e) => setObservations(e.target.value)} /></Field>
      <Field id="vf-photos" label="Photos or files (optional)" hint="Taken now or chosen from the device. Each original is fingerprinted and never changed.">
        <input id="vf-photos" type="file" multiple accept={acceptAttr} capture="environment" className="block text-sm" onChange={(e) => setPhotos([...(e.target.files ?? [])])} />
      </Field>
      {problems.length && outcome ? <ul className="list-disc pl-5 text-sm text-primary">{problems.map((p) => <li key={p}>{p}</li>)}</ul> : null}
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" disabled={save.isPending || problems.length > 0} className="rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy disabled:opacity-60">{save.isPending ? `${step}…` : "Save visit"}</button>
        <button type="button" onClick={onDone} className="rounded-md border border-primary px-4 py-2 text-sm text-primary">Cancel</button>
      </div>
    </form>
  );
}

/** A visit as a record: outcome, effort, samples, condition; correction with a reason. */
export function VisitRecord({ ws, visit, samples, members, uid, canRecord, label }: {
  ws: string; visit: Visit; samples: Sample[]; members: MemberRow[]; uid: string | undefined; canRecord: boolean; label: string;
}) {
  const [open, setOpen] = useState(false);
  const [correcting, setCorrecting] = useState(false);
  const mine = samples.filter((s) => s.visit_id === visit.id);
  return (
    <li className="text-sm">
      <button type="button" aria-expanded={open} onClick={() => setOpen(!open)} className="flex w-full flex-wrap items-baseline gap-x-3 gap-y-1 px-3 py-2 text-left hover:bg-secondary/60">
        <span className="text-primary">{when(visit.occurred_at)}</span>
        <StatusTag strong={visit.outcome === "collected"}>{outcomeLabels[visit.outcome]}</StatusTag>
        <span className="text-muted-foreground">{label}{mine.length ? ` · ${mine.length} sample${mine.length === 1 ? "" : "s"}` : ""}{visit.trap_condition !== "working" ? ` · trap ${conditionLabels[visit.trap_condition].toLowerCase()}` : ""}</span>
      </button>
      {open ? (
        <div className="space-y-2 border-t border-border bg-background px-3 py-3">
          <dl className="grid gap-1 sm:grid-cols-2">
            <div><dt className="inline text-muted-foreground">Officer: </dt><dd className="inline text-primary">{who(visit.officer_id, uid)}</dd></div>
            <div><dt className="inline text-muted-foreground">Entered: </dt><dd className="inline text-primary">{when(visit.recorded_at)}</dd></div>
            {visit.exposure_started_at ? <div className="sm:col-span-2"><dt className="inline text-muted-foreground">Trap exposed: </dt><dd className="inline text-primary">{when(visit.exposure_started_at)} to {when(visit.exposure_ended_at)}</dd></div> : null}
            {visit.not_completed_reason ? <div className="sm:col-span-2"><dt className="inline text-muted-foreground">Not completed because: </dt><dd className="inline text-primary">{visit.not_completed_reason}</dd></div> : null}
            {visit.observations ? <div className="sm:col-span-2"><dt className="inline text-muted-foreground">Observations: </dt><dd className="inline text-primary">{visit.observations}</dd></div> : null}
          </dl>
          {mine.length ? (
            <ul className="space-y-0.5">
              {mine.map((s) => <li key={s.id}><strong className="text-primary">{s.reference}</strong> · {methodLabels[s.method]} · <StatusTag>{s.status === "awaiting_result" ? "Result pending" : "Resulted"}</StatusTag>{s.notes ? ` · ${s.notes}` : ""}</li>)}
            </ul>
          ) : null}
          <Attachments ws={ws} recordType="visit" recordId={visit.id} canRecord={canRecord} uid={uid} />
          {mine.map((s) => <div key={s.id}><p className="text-xs text-muted-foreground">Sample {s.reference}:</p><Attachments ws={ws} recordType="sample" recordId={s.id} canRecord={canRecord} uid={uid} compact /></div>)}
          {correcting ? <CorrectVisitForm ws={ws} visit={visit} members={members} uid={uid} onDone={() => setCorrecting(false)} />
            : canRecord ? <button type="button" className="text-xs text-primary underline" onClick={() => setCorrecting(true)}>Correct details</button> : null}
          <History type="visit" id={visit.id} ws={ws} uid={uid} labels={{ trap_condition: "condition", occurred_at: "visited at", officer_id: "officer" }} />
        </div>
      ) : null}
    </li>
  );
}

function CorrectVisitForm({ ws, visit, members, uid, onDone }: { ws: string; visit: Visit; members: MemberRow[]; uid: string | undefined; onDone: () => void }) {
  const qc = useQueryClient();
  const [v, setV] = useState({
    at: toLocalInput(visit.occurred_at), officer: visit.officer_id, condition: visit.trap_condition, observations: visit.observations ?? "",
    expStart: visit.exposure_started_at ? toLocalInput(visit.exposure_started_at) : "", expEnd: visit.exposure_ended_at ? toLocalInput(visit.exposure_ended_at) : "",
    reason: visit.not_completed_reason ?? "", why: "",
  });
  const save = useMutation({
    mutationFn: () => run(fieldRpc.correctVisit(visit.id, {
      occurred_at: fromLocalInput(v.at)!, officer: v.officer, condition: v.condition, observations: v.observations,
      exposure_start: fromLocalInput(v.expStart), exposure_end: fromLocalInput(v.expEnd), reason: v.reason,
    }, v.why)),
    onSuccess: () => { invalidate(qc, ws); onDone(); },
  });
  return (
    <form className="space-y-2 rounded-md border-2 border-accent p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <p className="text-sm font-semibold text-primary">Correct this visit</p>
      <p className="text-xs text-muted-foreground">The previous values are kept. To change what happened (for example, samples were collected after all), record a new visit.</p>
      <div className="grid gap-2 sm:grid-cols-3">
        <Field id="cv-at" label="Visited at"><Input id="cv-at" type="datetime-local" value={v.at} onChange={(e) => setV({ ...v, at: e.target.value })} /></Field>
        <Field id="cv-off" label="Officer"><OfficerSelect id="cv-off" value={v.officer} onChange={(x) => setV({ ...v, officer: x })} members={members} uid={uid} /></Field>
        <Field id="cv-c" label="Trap condition">
          <select id="cv-c" className={selectClass} value={v.condition} onChange={(e) => setV({ ...v, condition: e.target.value as Condition })}>
            {(Object.keys(conditionLabels) as Condition[]).map((c) => <option key={c} value={c}>{conditionLabels[c]}</option>)}
          </select>
        </Field>
        {visit.outcome !== "not_completed" ? <>
          <Field id="cv-es" label="Exposed from"><Input id="cv-es" type="datetime-local" value={v.expStart} onChange={(e) => setV({ ...v, expStart: e.target.value })} /></Field>
          <Field id="cv-ee" label="Exposed until"><Input id="cv-ee" type="datetime-local" value={v.expEnd} onChange={(e) => setV({ ...v, expEnd: e.target.value })} /></Field>
        </> : <Field id="cv-r" label="Why not completed"><Input id="cv-r" value={v.reason} onChange={(e) => setV({ ...v, reason: e.target.value })} /></Field>}
      </div>
      <Field id="cv-o" label="Observations"><Textarea id="cv-o" maxLength={4000} value={v.observations} onChange={(e) => setV({ ...v, observations: e.target.value })} /></Field>
      <Field id="cv-w" label="Why are you correcting it? (required)"><Input id="cv-w" maxLength={500} value={v.why} onChange={(e) => setV({ ...v, why: e.target.value })} /></Field>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" disabled={save.isPending || v.why.trim().length < 5} className="rounded-md bg-signal-teal px-3 py-1.5 text-sm font-semibold text-deep-navy disabled:opacity-60">Save correction</button>
        <button type="button" onClick={onDone} className="rounded-md border border-primary px-3 py-1.5 text-sm text-primary">Cancel</button>
      </div>
    </form>
  );
}

export const deploymentLine = (d: Deployment, site: Site | undefined) =>
  `${site ? `${site.reference} · ${site.name}` : "Site not visible to you"} · ${day(d.started_at)}${d.ended_at ? ` to ${day(d.ended_at)} (${endReasonLabels[d.end_reason!].toLowerCase()})` : " · active"}`;
