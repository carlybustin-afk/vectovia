// Site panels for design v2 stage 2: boundary and zone, operational areas, obligations and
// compliance, and sharing a site with another organisation. Writes go through checked database
// functions; the database decides who may do what, and these screens only hide what would be refused.
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo, useRef, useState } from "react";
import { ErrorState, Loading } from "@/components/app-shell";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { wsKey } from "@/lib/workspace";
import { newId, run, when, type Site } from "./api";
import { hectares, inSiteZone, polygonFrom, ringOf, zoneOutline, type LatLon, type Polygon } from "./geo";
import { SurveillanceMap, type MapPoint, type MapShape } from "./map";
import {
  areaKindLabels, checkKindLabels, loadAreas, loadCompliance, loadObligations, loadShared, loadSiteObligations, obligationRpc,
  pointOfEntryTypes, publishedVersion, ragLabels, siteTypeLabels, summarise,
  type AreaKind, type ComplianceRow, type Rag, type SiteArea, type SiteType,
} from "./obligations";
import { Field, selectClass, useDeployments, useTraps } from "./ui";

export const useAreas = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "areas"), queryFn: () => loadAreas(ws) });
export const useSiteObligations = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "site-obligations"), queryFn: () => loadSiteObligations(ws) });
export const useObligations = () => useQuery({ queryKey: ["vv-obligations"], queryFn: loadObligations, staleTime: 60_000 });
const useCompliance = (ws: string, site: string) => useQuery({ queryKey: wsKey(ws, "vv", "compliance", site), queryFn: () => loadCompliance(site) });

const btn = "rounded-md border border-primary px-3 py-1.5 text-sm font-medium text-primary disabled:opacity-60";
const primaryBtn = "rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy disabled:opacity-60";
const heading = "text-xs font-semibold uppercase tracking-wide text-accent";

function useRefresh(ws: string) {
  const qc = useQueryClient();
  return () => { void qc.invalidateQueries({ queryKey: ["ws", ws, "vv"] }); void qc.invalidateQueries({ queryKey: ["vv-obligations"] }); };
}

/** Map shapes for a site: its boundary, its areas and the zone around them. */
export function siteShapes(site: Site, areas: SiteArea[]): MapShape[] {
  const mine = areas.filter((a) => a.site_id === site.id);
  const outlines = [site.boundary, ...mine.map((a) => a.boundary)].filter(Boolean) as Polygon[];
  const shapes: MapShape[] = [];
  if (outlines.length && site.zone_m > 0) shapes.push({ id: `${site.id}-zone`, points: zoneOutline(outlines, site.zone_m), label: `${site.zone_m} m zone`, style: "zone" });
  if (site.boundary) shapes.push({ id: `${site.id}-boundary`, points: ringOf(site.boundary), label: `${site.name}: site boundary`, style: "boundary" });
  for (const a of mine) if (a.boundary) shapes.push({ id: a.id, points: ringOf(a.boundary), label: `${areaKindLabels[a.kind]}: ${a.name}`, style: "area" });
  return shapes;
}

// ---------- Boundary and zone ----------------------------------------------------------------
export function BoundaryPanel({ ws, site, canManage }: { ws: string; site: Site; canManage: boolean }) {
  const areas = useAreas(ws), deployments = useDeployments(ws), traps = useTraps(ws);
  const [editing, setEditing] = useState(false);
  if (areas.isPending) return <Loading what="Loading the site boundary" />;
  if (areas.isError) return <ErrorState error={areas.error} />;
  const mine = areas.data.filter((a) => a.site_id === site.id);
  const outlines = [site.boundary, ...mine.map((a) => a.boundary)];
  const active = (deployments.data ?? []).filter((d) => d.site_id === site.id && !d.ended_at && d.latitude !== null && d.longitude !== null);
  const points: MapPoint[] = active.map((d) => {
    const inside = inSiteZone(outlines, site.zone_m, d.latitude!, d.longitude!);
    const trap = traps.data?.find((t) => t.id === d.trap_id)?.identifier ?? "Trap";
    return { id: d.id, lat: d.latitude!, lon: d.longitude!, label: `${trap}: ${inside ? "inside" : "outside"} the zone`, muted: !inside };
  });
  const inside = points.filter((p) => !p.muted).length;
  const sitePoint: MapPoint[] = site.latitude !== null && site.longitude !== null ? [{ id: `site-${site.id}`, lat: site.latitude, lon: site.longitude, label: `${site.name}: site location`, muted: true }] : [];
  if (editing) return <BoundaryForm ws={ws} site={site} areas={mine} onDone={() => setEditing(false)} />;
  return (
    <section aria-labelledby={`b-${site.id}`} className="space-y-2">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <p id={`b-${site.id}`} className={heading}>Boundary and zone</p>
        {canManage ? <button type="button" className={btn} onClick={() => setEditing(true)}>{site.boundary ? "Change boundary and zone" : "Draw the site boundary"}</button> : null}
      </div>
      <p className="text-sm text-primary">
        {siteTypeLabels[site.site_type]} · {site.zone_m} m zone
        {site.boundary ? ` · boundary about ${hectares(site.boundary).toFixed(1)} ha` : " · no boundary yet"}
        {mine.length ? ` · ${mine.length} operational area${mine.length === 1 ? "" : "s"}` : ""}
      </p>
      {site.risk_reason ? <p className="text-xs text-muted-foreground">Why this site: {site.risk_reason}</p> : null}
      <SurveillanceMap label={`Map of ${site.name}: boundary, areas, zone and traps`} height={300} points={[...sitePoint, ...points]} shapes={siteShapes(site, areas.data)} />
      <p className="text-xs text-muted-foreground">
        {active.length === 0 ? "No active traps here." : `${inside} of ${active.length} active trap${active.length === 1 ? "" : "s"} inside the zone (filled markers); hollow markers are outside it.`}
        {" "}The zone is drawn from the site boundary and every area; the compliance check below uses the same measure.
      </p>
    </section>
  );
}

function useDraft(initial: Polygon | null) {
  const [pts, setPts] = useState<LatLon[]>(ringOf(initial));
  return { pts, add: (lat: number, lon: number) => setPts((p) => [...p, [lat, lon]]), undo: () => setPts((p) => p.slice(0, -1)), clear: () => setPts([]) };
}

function DrawControls({ draft, label }: { draft: ReturnType<typeof useDraft>; label: string }) {
  return (
    <div className="flex flex-wrap items-center gap-3 text-sm">
      <span className="text-muted-foreground" aria-live="polite">{draft.pts.length} point{draft.pts.length === 1 ? "" : "s"}{draft.pts.length > 0 && draft.pts.length < 3 ? " (at least 3 needed)" : ""}</span>
      <button type="button" className={btn} disabled={!draft.pts.length} onClick={draft.undo}>Undo last point</button>
      <button type="button" className={btn} disabled={!draft.pts.length} onClick={draft.clear}>Clear {label}</button>
    </div>
  );
}

function BoundaryForm({ ws, site, areas, onDone }: { ws: string; site: Site; areas: SiteArea[]; onDone: () => void }) {
  const refresh = useRefresh(ws);
  const draft = useDraft(site.boundary);
  const [type, setType] = useState<SiteType>(site.site_type);
  const [zone, setZone] = useState(String(site.zone_m));
  const [reason, setReason] = useState(site.risk_reason ?? "");
  const poe = pointOfEntryTypes.includes(type);
  const zoneM = Number(zone);
  const zoneOk = Number.isInteger(zoneM) && zoneM >= (poe ? 400 : 0) && zoneM <= 5000;
  const boundary = polygonFrom(draft.pts);
  const save = useMutation({
    mutationFn: () => run(obligationRpc.saveGeometry(site.id, type, boundary, zoneM, reason)),
    onSuccess: () => { refresh(); onDone(); },
  });
  const preview: Site = { ...site, boundary: null, zone_m: zoneOk ? zoneM : site.zone_m };
  const shapes: MapShape[] = [
    ...siteShapes(preview, areas).filter((s) => s.style !== "boundary"),
    ...(boundary && zoneOk && zoneM > 0 ? [{ id: "zone-draft", points: zoneOutline([boundary, ...areas.map((a) => a.boundary)], zoneM), label: `${zoneM} m zone`, style: "zone" as const }] : []),
    { id: "draft", points: draft.pts, label: "New boundary", style: "draft" },
  ];
  return (
    <form className="space-y-3 rounded-md border-t-2 border-accent bg-secondary p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <p className="font-semibold text-primary">Boundary and zone: {site.name}</p>
      <div className="grid gap-3 sm:grid-cols-2">
        <Field id="bf-type" label="Type of site">
          <select id="bf-type" className={selectClass} value={type} onChange={(e) => { const t = e.target.value as SiteType; setType(t); if (pointOfEntryTypes.includes(t) && zoneM < 400) setZone("400"); }}>
            {(Object.keys(siteTypeLabels) as SiteType[]).map((t) => <option key={t} value={t}>{siteTypeLabels[t]}</option>)}
          </select>
        </Field>
        <Field id="bf-zone" label="Zone around the site (metres)" hint={poe ? "Points of entry need at least 400 m around their operational areas." : "0 to 5,000 m."}>
          <Input id="bf-zone" className="bg-background" inputMode="numeric" value={zone} onChange={(e) => setZone(e.target.value.replace(/\D/g, ""))} />
        </Field>
      </div>
      {!zoneOk ? <p role="alert" className="text-sm text-primary">{poe ? "Enter a zone of 400 to 5,000 metres." : "Enter a zone of 0 to 5,000 metres."}</p> : null}
      <Field id="bf-why" label="Why this site is monitored (optional)" hint="For example: international freight, modelled climate risk, previous detection.">
        <Input id="bf-why" className="bg-background" maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} />
      </Field>
      <fieldset className="space-y-2">
        <legend className="text-sm font-medium text-primary">Site boundary</legend>
        <p className="text-xs text-muted-foreground">Click the map at each corner of the site, in order. The shape closes itself. Operational areas are added separately below.</p>
        <SurveillanceMap label="Draw the site boundary" height={340} keepView points={site.latitude !== null ? [{ id: "site", lat: site.latitude, lon: site.longitude!, label: "Site location", muted: true }] : []}
          shapes={shapes} onPick={draft.add} pickHint="Click to add a corner of the boundary." />
        <DrawControls draft={draft} label="boundary" />
        {boundary ? <p className="text-xs text-muted-foreground">About {hectares(boundary).toFixed(1)} ha.</p> : null}
      </fieldset>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || !zoneOk || (draft.pts.length > 0 && !boundary)}>{save.isPending ? "Saving…" : "Save boundary and zone"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}

// ---------- Operational areas ----------------------------------------------------------------
export function AreasPanel({ ws, site, canManage }: { ws: string; site: Site; canManage: boolean }) {
  const areas = useAreas(ws);
  const [open, setOpen] = useState<string | "new" | null>(null);
  if (!areas.data) return null;
  const mine = areas.data.filter((a) => a.site_id === site.id);
  return (
    <section className="space-y-2">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <p className={heading}>Operational areas</p>
        {canManage && open !== "new" ? <button type="button" className={btn} onClick={() => setOpen("new")}>Add an area</button> : null}
      </div>
      {open === "new" ? <AreaForm ws={ws} site={site} areas={mine} onDone={() => setOpen(null)} /> : null}
      {mine.length === 0 ? <p className="text-xs text-muted-foreground">None recorded. For a point of entry, add terminals, cargo areas, external areas and service providers: the zone extends from each.</p> : (
        <ul className="space-y-1 text-sm">
          {mine.map((a) => (
            <li key={a.id} className="rounded-md border border-border p-2">
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <span className="text-primary"><span className="font-medium">{a.name}</span> · {areaKindLabels[a.kind]}{a.boundary ? ` · about ${hectares(a.boundary).toFixed(1)} ha` : " · no outline"}</span>
                {canManage && open !== a.id ? <button type="button" className="text-sm text-primary underline" onClick={() => setOpen(a.id)}>Change</button> : null}
              </div>
              {open === a.id ? <AreaForm ws={ws} site={site} areas={mine} area={a} onDone={() => setOpen(null)} /> : null}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function AreaForm({ ws, site, areas, area, onDone }: { ws: string; site: Site; areas: SiteArea[]; area?: SiteArea; onDone: () => void }) {
  const refresh = useRefresh(ws);
  const id = useRef(area?.id ?? newId());
  const draft = useDraft(area?.boundary ?? null);
  const [kind, setKind] = useState<AreaKind>(area?.kind ?? "terminal");
  const [name, setName] = useState(area?.name ?? "");
  const [removing, setRemoving] = useState(false);
  const [why, setWhy] = useState("");
  const boundary = polygonFrom(draft.pts);
  const save = useMutation({ mutationFn: () => run(obligationRpc.saveArea(id.current, site.id, kind, name, boundary)), onSuccess: () => { refresh(); onDone(); } });
  const remove = useMutation({ mutationFn: () => run(obligationRpc.removeArea(id.current, why)), onSuccess: () => { refresh(); onDone(); } });
  const others = siteShapes(site, areas.filter((a) => a.id !== area?.id));
  return (
    <form className="mt-2 space-y-3 rounded-md border-t-2 border-accent bg-secondary p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-3 sm:grid-cols-2">
        <Field id={`af-k-${id.current}`} label="Kind of area">
          <select id={`af-k-${id.current}`} className={selectClass} value={kind} onChange={(e) => setKind(e.target.value as AreaKind)}>
            {(Object.keys(areaKindLabels) as AreaKind[]).map((k) => <option key={k} value={k}>{areaKindLabels[k]}</option>)}
          </select>
        </Field>
        <Field id={`af-n-${id.current}`} label="Name"><Input id={`af-n-${id.current}`} className="bg-background" maxLength={120} value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Freight yard" /></Field>
      </div>
      <p className="text-xs text-muted-foreground">Click the map at each corner of the area (optional, but the zone only extends from areas with an outline).</p>
      <SurveillanceMap label="Draw the area outline" height={280} keepView points={[]} shapes={[...others, { id: "draft", points: draft.pts, label: "Area outline", style: "draft" }]}
        onPick={draft.add} pickHint="Click to add a corner of the area." />
      <DrawControls draft={draft} label="outline" />
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex flex-wrap gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || name.trim().length < 2 || (draft.pts.length > 0 && !boundary)}>{save.isPending ? "Saving…" : area ? "Save area" : "Add area"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
        {area && !removing ? <button type="button" className="text-sm text-primary underline" onClick={() => setRemoving(true)}>Remove this area</button> : null}
      </div>
      {removing ? (
        <div className="space-y-2 rounded-md border border-border bg-background p-2">
          <Field id={`af-why-${id.current}`} label="Why are you removing it? (required)"><Input id={`af-why-${id.current}`} maxLength={500} value={why} onChange={(e) => setWhy(e.target.value)} /></Field>
          {remove.isError ? <ErrorState error={remove.error} /> : null}
          <button type="button" className={btn} disabled={remove.isPending || why.trim().length < 5} onClick={() => remove.mutate()}>{remove.isPending ? "Removing…" : "Remove area"}</button>
          <p className="text-xs text-muted-foreground">The area and the reason stay in the site history.</p>
        </div>
      ) : null}
    </form>
  );
}

// ---------- Obligations and compliance -------------------------------------------------------
export function RagTag({ status }: { status: Rag }) {
  const r = ragLabels[status];
  return <span className={`inline-flex shrink-0 items-center gap-1 rounded border px-1.5 py-0.5 text-[11px] font-semibold uppercase tracking-wide ${r.tone}`}><span aria-hidden="true">{r.mark}</span>{r.label}</span>;
}

export function CompliancePanel({ ws, site, canManage }: { ws: string; site: Site; canManage: boolean }) {
  const obligations = useObligations(), adopted = useSiteObligations(ws), compliance = useCompliance(ws, site.id);
  const refresh = useRefresh(ws);
  const [assessing, setAssessing] = useState<string | null>(null);
  const [removing, setRemoving] = useState<string | null>(null);
  const [why, setWhy] = useState("");
  const adopt = useMutation({ mutationFn: (key: string) => run(obligationRpc.adopt(newId(), site.id, key)), onSuccess: refresh });
  const remove = useMutation({ mutationFn: (id: string) => run(obligationRpc.removeObligation(id, why)), onSuccess: () => { setRemoving(null); setWhy(""); refresh(); } });
  const bySet = useMemo(() => {
    const m = new Map<string, ComplianceRow[]>();
    for (const r of compliance.data ?? []) m.set(r.site_obligation_id, [...(m.get(r.site_obligation_id) ?? []), r]);
    return m;
  }, [compliance.data]);
  if (obligations.isPending || adopted.isPending || compliance.isPending) return <Loading what="Loading obligations" />;
  const err = obligations.error ?? adopted.error ?? compliance.error;
  if (err) return <ErrorState error={err} />;
  const mine = adopted.data!.filter((a) => a.site_id === site.id);
  const available = obligations.data!.sets.filter((s) => publishedVersion(obligations.data!, s.id) && !mine.some((a) => a.set_id === s.id));
  return (
    <section className="space-y-3">
      <p className={heading}>Obligations and compliance</p>
      {mine.length === 0 ? <p className="text-sm text-muted-foreground">No obligation sets adopted for this site yet.</p> : null}
      {mine.map((a) => {
        const set = obligations.data!.sets.find((s) => s.id === a.set_id)!;
        const rows = bySet.get(a.id) ?? [];
        const sum = summarise(rows);
        const latest = publishedVersion(obligations.data!, a.set_id);
        const current = obligations.data!.versions.find((v) => v.id === a.version_id);
        return (
          <div key={a.id} className="rounded-md border border-border">
            <div className="flex flex-wrap items-baseline justify-between gap-2 border-b border-border bg-secondary/60 px-3 py-2">
              <p className="font-semibold text-primary">{set.name} <span className="font-normal text-muted-foreground">· version {current?.version ?? rows[0]?.version}</span></p>
              <p className="text-xs text-primary">{sum.green} met · {sum.amber} partly · {sum.red} not met · {sum.notAssessed} not assessed{sum.notApplicable ? ` · ${sum.notApplicable} not applicable` : ""}</p>
            </div>
            {canManage && latest && latest.id !== a.version_id ? (
              <div className="flex flex-wrap items-center gap-2 border-b border-border px-3 py-2 text-sm">
                <span className="text-primary">Version {latest.version} has been published.</span>
                <button type="button" className={btn} disabled={adopt.isPending} onClick={() => adopt.mutate(set.key)}>Move to version {latest.version}</button>
                <span className="text-xs text-muted-foreground">Assessments made against the old version stay in its history.</span>
              </div>
            ) : null}
            <ol className="divide-y divide-border">
              {rows.map((r) => (
                <li key={r.requirement_key} className="px-3 py-2 text-sm">
                  <div className="flex flex-wrap items-start gap-2">
                    <RagTag status={r.status} />
                    <div className="min-w-0 flex-1">
                      <p className="font-medium text-primary">{r.sort_order}. {r.title}{r.mandatory ? "" : <span className="font-normal text-muted-foreground"> (where it applies)</span>}</p>
                      <p className="text-primary [overflow-wrap:anywhere]">{r.detail}</p>
                      <p className="text-xs text-muted-foreground">{checkKindLabels[r.check_kind]}{r.assessed_at ? ` · ${when(r.assessed_at)}` : ""}{r.review_by ? ` · review by ${new Date(r.review_by).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" })}` : ""}</p>
                    </div>
                    {canManage && r.check_kind === "assessment" && assessing !== r.requirement_key ? <button type="button" className="text-sm text-primary underline" onClick={() => setAssessing(r.requirement_key)}>Assess</button> : null}
                  </div>
                  {assessing === r.requirement_key ? <AssessForm ws={ws} siteObligation={a.id} row={r} onDone={() => setAssessing(null)} /> : null}
                </li>
              ))}
            </ol>
            {canManage ? (
              <div className="border-t border-border px-3 py-2 text-sm">
                {removing === a.id ? (
                  <div className="flex flex-wrap items-end gap-2">
                    <Field id={`ro-${a.id}`} label="Why is this set no longer needed here? (required)"><Input id={`ro-${a.id}`} className="w-full max-w-sm" maxLength={500} value={why} onChange={(e) => setWhy(e.target.value)} /></Field>
                    <button type="button" className={btn} disabled={remove.isPending || why.trim().length < 5} onClick={() => remove.mutate(a.id)}>Remove set</button>
                    <button type="button" className="text-sm text-primary underline" onClick={() => setRemoving(null)}>Cancel</button>
                    {remove.isError ? <ErrorState error={remove.error} /> : null}
                  </div>
                ) : <button type="button" className="text-sm text-primary underline" onClick={() => setRemoving(a.id)}>Remove this set from the site</button>}
              </div>
            ) : null}
          </div>
        );
      })}
      {canManage ? (
        available.length ? (
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <span className="text-primary">Adopt an obligation set:</span>
            {available.map((s) => (
              <button key={s.id} type="button" className={s.applies_to.includes(site.site_type) ? primaryBtn : btn} disabled={adopt.isPending} onClick={() => adopt.mutate(s.key)}>
                {s.name}{s.applies_to.includes(site.site_type) ? " (suggested for this type of site)" : ""}
              </button>
            ))}
          </div>
        ) : mine.length === 0 ? <p className="text-xs text-muted-foreground">No obligation sets have been published yet. Drafts appear under Obligation sets once the content team reviews and publishes them.</p> : null
      ) : null}
      {adopt.isError ? <ErrorState error={adopt.error} /> : null}
    </section>
  );
}

function AssessForm({ ws, siteObligation, row, onDone }: { ws: string; siteObligation: string; row: ComplianceRow; onDone: () => void }) {
  const refresh = useRefresh(ws);
  const id = useRef(newId());
  const [status, setStatus] = useState<Exclude<Rag, "not_assessed">>(row.status === "not_assessed" ? "green" : row.status);
  const [note, setNote] = useState("");
  const [reviewBy, setReviewBy] = useState("");
  const today = new Date().toISOString().slice(0, 10);
  const save = useMutation({ mutationFn: () => run(obligationRpc.assess(id.current, siteObligation, row.requirement_key, status, note, reviewBy || null)), onSuccess: () => { refresh(); onDone(); } });
  return (
    <form className="mt-2 space-y-2 rounded-md border-t-2 border-accent bg-secondary p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <fieldset>
        <legend className="text-sm font-medium text-primary">Where does this stand?</legend>
        <div className="mt-1 flex flex-wrap gap-3">
          {(["green", "amber", "red", "not_applicable"] as const).map((s) => (
            <label key={s} className="flex items-center gap-2 text-sm"><input type="radio" name={`as-${id.current}`} checked={status === s} onChange={() => setStatus(s)} /><RagTag status={s} /></label>
          ))}
        </div>
      </fieldset>
      <Field id={`as-n-${id.current}`} label="What is the evidence? (required)" hint="Say what you checked, for example the plan's date and who signed it off.">
        <Textarea id={`as-n-${id.current}`} className="bg-background" maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} />
      </Field>
      <Field id={`as-r-${id.current}`} label="Review by (optional)" hint="After this date the requirement shows as not assessed until someone looks again.">
        <Input id={`as-r-${id.current}`} type="date" min={today} className="w-48 bg-background" value={reviewBy} onChange={(e) => setReviewBy(e.target.value)} />
      </Field>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || note.trim().length < 5}>{save.isPending ? "Saving…" : "Record assessment"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
      </div>
      <p className="text-xs text-muted-foreground">Earlier assessments are kept; the latest one counts.</p>
    </form>
  );
}

// ---------- Sharing ---------------------------------------------------------------------------
export function SharingPanel({ ws, site, canManage }: { ws: string; site: Site; canManage: boolean }) {
  const shared = useQuery({ queryKey: wsKey(ws, "vv", "shared", site.id), queryFn: () => loadShared(site.id) });
  const refresh = useRefresh(ws);
  const [code, setCode] = useState<string | null>(null);
  const [joinCode, setJoinCode] = useState("");
  const [leaving, setLeaving] = useState(false);
  const [why, setWhy] = useState("");
  const create = useMutation({ mutationFn: async () => (await run(obligationRpc.createShare(site.id))) as string, onSuccess: (c) => { setCode(c); refresh(); } });
  const join = useMutation({ mutationFn: () => run(obligationRpc.joinShare(joinCode.trim().toLowerCase(), site.id)), onSuccess: () => { setJoinCode(""); refresh(); } });
  const leave = useMutation({ mutationFn: () => run(obligationRpc.leaveShare(site.id, why)), onSuccess: () => { setLeaving(false); setWhy(""); setCode(null); refresh(); } });
  if (shared.isPending) return <Loading what="Checking sharing" />;
  if (shared.isError) return <ErrorState error={shared.error} />;
  const members = shared.data;
  const you = members.find((m) => m.is_you);
  const others = members.filter((m) => !m.is_you);
  const shapes: MapShape[] = others.flatMap((m, i) => [
    ...(m.boundary ? [{ id: `sh-${i}`, points: ringOf(m.boundary), label: `${m.organisation}: ${m.site_name}`, style: "shared" as const }] : []),
    ...m.areas.filter((a) => a.boundary).map((a, j) => ({ id: `sh-${i}-${j}`, points: ringOf(a.boundary), label: `${m.organisation}: ${a.name}`, style: "shared" as const })),
  ]);
  return (
    <section className="space-y-2">
      <p className={heading}>Sharing this site</p>
      {members.length > 1 || (you && others.length === 0 && members.length === 1) ? (
        <>
          {others.length ? (
            <ul className="space-y-1 text-sm">
              {others.map((m) => <li key={m.organisation} className="text-primary"><span className="font-medium">{m.organisation}</span> · {m.site_name} · {siteTypeLabels[m.site_type]}{m.is_lead ? " · lead" : ""}</li>)}
            </ul>
          ) : <p className="text-sm text-primary">Waiting for another organisation to join with your code.</p>}
          <p className="text-xs text-muted-foreground">Shared: each organisation's site name, type, boundary, zone and areas. Not shared: programmes, traps, checks, finds and history.</p>
          {shapes.length ? <SurveillanceMap label="Shared site: other organisations' boundaries" height={240} points={[]} shapes={[...shapes]} /> : null}
        </>
      ) : <p className="text-sm text-muted-foreground">Not shared. If another organisation also works at this site (for example port health and the council), you can link your site records so you both see the same boundary and zone. Your own records stay private.</p>}

      {canManage ? (
        <div className="space-y-2">
          {(!you || you.is_lead) ? (
            <div className="space-y-1">
              <button type="button" className={btn} disabled={create.isPending} onClick={() => create.mutate()}>{create.isPending ? "Creating…" : "Create a share code"}</button>
              {code ? (
                <div className="rounded-md border border-accent bg-secondary p-2 text-sm">
                  <p className="text-primary">Give this code to a manager at the other organisation. It works once and expires in 7 days. It won't be shown again.</p>
                  <p className="mt-1 break-all font-mono text-xs text-primary">{code}</p>
                  <button type="button" className="mt-1 text-sm text-primary underline" onClick={() => void navigator.clipboard?.writeText(code)}>Copy code</button>
                </div>
              ) : null}
              {create.isError ? <ErrorState error={create.error} /> : null}
            </div>
          ) : null}
          {!you ? (
            <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); join.mutate(); }}>
              <Field id={`join-${site.id}`} label="Joining another organisation's site? Enter their code"><Input id={`join-${site.id}`} className="w-full max-w-md font-mono" value={joinCode} onChange={(e) => setJoinCode(e.target.value)} /></Field>
              <button type="submit" className={btn} disabled={join.isPending || !/^[0-9a-f]{64}$/i.test(joinCode.trim())}>{join.isPending ? "Joining…" : "Join"}</button>
              {join.isError ? <ErrorState error={join.error} /> : null}
            </form>
          ) : null}
          {you ? (
            leaving ? (
              <div className="flex flex-wrap items-end gap-2">
                <Field id={`leave-${site.id}`} label="Why are you stopping? (required)"><Input id={`leave-${site.id}`} className="w-full max-w-sm" maxLength={500} value={why} onChange={(e) => setWhy(e.target.value)} /></Field>
                <button type="button" className={btn} disabled={leave.isPending || why.trim().length < 5} onClick={() => leave.mutate()}>{you.is_lead ? "End sharing for everyone" : "Stop sharing"}</button>
                <button type="button" className="text-sm text-primary underline" onClick={() => setLeaving(false)}>Cancel</button>
                {leave.isError ? <ErrorState error={leave.error} /> : null}
              </div>
            ) : <button type="button" className="text-sm text-primary underline" onClick={() => setLeaving(true)}>{you.is_lead ? "End sharing" : "Stop sharing"}</button>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}
