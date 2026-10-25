import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useMemo, useRef, useState } from "react";
import { AppShell, EmptyState, ErrorState, Loading, appHead } from "@/components/app-shell";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { useSession } from "@/lib/session";
import { newId, run, siteAddress, vvRpc, when, type Programme, type Site, type SiteInput } from "@/modules/vectovia/api";
import { fromGridRef, toGridRef } from "@/modules/vectovia/grid";
import { SurveillanceMap } from "@/modules/vectovia/map";
import { Field, History, StatusTag, selectClass, useDeployments, useProgrammes, useSamples, useSites, useTraps, useVisits, useVv } from "@/modules/vectovia/ui";
import { deploymentLine } from "@/modules/vectovia/fieldwork";
import { Attachments } from "@/modules/vectovia/attachments";
import { LinksPanel } from "@/modules/vectovia/links";
import { outcomeLabels } from "@/modules/vectovia/api";
import { AreasPanel, BoundaryPanel, CompliancePanel, SharingPanel, siteShapes, useAreas } from "@/modules/vectovia/site-panels";
import { siteTypeLabels } from "@/modules/vectovia/obligations";

export const Route = createFileRoute("/app/vectovia/sites")({
  head: () => appHead("Sites · Vectovia", "Surveillance sites: map and list, locations, access and programmes."),
  component: SitesPage,
});

function SitesPage() {
  return (
    <AppShell product="vectovia" section="vectovia" title="Sites"
      intro="Where surveillance happens. An address is optional: ports, open land and other places can be located by GPS or grid reference.">
      <Sites />
    </AppShell>
  );
}

function Sites() {
  const { ws, canRecord, canManage } = useVv();
  const sites = useSites(ws);
  const programmes = useProgrammes(ws);
  const areas = useAreas(ws);
  const [q, setQ] = useState("");
  const [programme, setProgramme] = useState("");
  const [open, setOpen] = useState<string | "new" | null>(null);
  const shown = useMemo(() => (sites.data ?? []).filter((s) =>
    (!programme || s.programmes.includes(programme))
    && (!q.trim() || `${s.reference} ${s.name} ${siteAddress(s)} ${s.location_description ?? ""}`.toLowerCase().includes(q.trim().toLowerCase()))), [sites.data, q, programme]);

  if (sites.isPending || programmes.isPending) return <Loading what="Loading sites" />;
  if (sites.isError) return <ErrorState error={sites.error} />;
  if (programmes.isError) return <ErrorState error={programmes.error} />;
  const points = shown.filter((s) => s.latitude !== null).map((s) => ({ id: s.id, lat: s.latitude!, lon: s.longitude!, label: `${s.reference} · ${s.name}`, muted: s.status === "inactive" }));
  const progName = new Map(programmes.data.map((p) => [p.id, p.name]));

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="flex flex-wrap items-end gap-3">
          <Field id="s-q" label="Search"><Input id="s-q" className="w-64" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Reference, name or address" /></Field>
          <Field id="s-p" label="Programme">
            <select id="s-p" className={selectClass} value={programme} onChange={(e) => setProgramme(e.target.value)}>
              <option value="">All programmes</option>
              {programmes.data.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </Field>
        </div>
        {canRecord ? <button type="button" onClick={() => setOpen("new")} className="rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy">New site</button> : null}
      </div>
      {open === "new" ? <SiteForm ws={ws} programmes={programmes.data} canManage={canManage} onDone={(id) => setOpen(id)} onCancel={() => setOpen(null)} /> : null}
      <SurveillanceMap label="Map of sites" points={points} onSelect={(id) => setOpen(id)} shapes={shown.flatMap((s) => siteShapes(s, areas.data ?? []))} />
      {shown.length === 0 ? (
        <EmptyState title={sites.data.length ? "No matching sites" : "No sites yet"}>
          {sites.data.length ? "Try a different search or programme." : canRecord ? "Add the first one with “New site”." : "Sites appear here once a field officer or manager adds them."}
        </EmptyState>
      ) : (
        <ul className="divide-y divide-border rounded-md border border-border">
          {shown.map((s) => (
            <li key={s.id}>
              <button type="button" aria-expanded={open === s.id} onClick={() => setOpen(open === s.id ? null : s.id)} className="flex w-full flex-wrap items-baseline gap-x-3 gap-y-1 px-3 py-2.5 text-left hover:bg-secondary/60">
                <span className="font-semibold text-primary">{s.reference}</span>
                <span className="text-primary">{s.name}</span>
                {s.site_type !== "other" ? <StatusTag>{siteTypeLabels[s.site_type]}</StatusTag> : null}
                {s.status === "inactive" ? <StatusTag>Inactive</StatusTag> : null}
                <span className="text-xs text-muted-foreground">
                  {s.latitude !== null ? toGridRef(s.latitude, s.longitude!) ?? `${s.latitude.toFixed(5)}, ${s.longitude!.toFixed(5)}` : "No coordinates"}
                  {siteAddress(s) ? ` · ${siteAddress(s)}` : ""}
                  {s.programmes.length ? ` · ${s.programmes.map((p) => progName.get(p)).filter(Boolean).join(", ")}` : " · No programme"}
                </span>
              </button>
              {open === s.id ? <SiteDetail ws={ws} site={s} programmes={programmes.data} canRecord={canRecord} canManage={canManage} /> : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function SiteDetail({ ws, site, programmes, canRecord, canManage }: { ws: string; site: Site; programmes: Programme[]; canRecord: boolean; canManage: boolean }) {
  const { session } = useSession();
  const [editing, setEditing] = useState(false);
  if (editing) return <div className="border-t border-border p-3"><SiteForm ws={ws} site={site} programmes={programmes} canManage={canManage} onDone={() => setEditing(false)} onCancel={() => setEditing(false)} /></div>;
  return (
    <div className="space-y-5 border-t border-border bg-background p-3">
    <div className="grid gap-3 text-sm sm:grid-cols-2">
      <dl className="space-y-1.5">
        <Row k="Location">{site.latitude !== null ? <>{toGridRef(site.latitude, site.longitude!, 10) ?? "Outside the National Grid"} <span className="text-muted-foreground">({site.latitude.toFixed(6)}, {site.longitude!.toFixed(6)})</span></> : "Not recorded"}</Row>
        <Row k="Address">{siteAddress(site) || "None (not needed)"}</Row>
        {site.uprn ? <Row k="UPRN">{site.uprn}</Row> : null}
        <Row k="Description">{site.location_description || "—"}</Row>
        <Row k="Access">{site.access_instructions || "—"}</Row>
        <Row k="Programmes">{site.programmes.length ? site.programmes.map((p) => programmes.find((x) => x.id === p)?.name).filter(Boolean).join(", ") : "None"}</Row>
        <Row k="Last changed">{when(site.updated_at)}</Row>
      </dl>
      <div className="space-y-2">
        {canRecord ? <button type="button" onClick={() => setEditing(true)} className="rounded-md border border-primary px-3 py-1.5 text-sm font-medium text-primary">Edit site</button> : null}
        <SiteActivity ws={ws} site={site} />
        <Attachments ws={ws} recordType="site" recordId={site.id} canRecord={canRecord} uid={session?.user.id} />
        <LinksPanel ws={ws} recordType="site" recordId={site.id} canManage={canManage} uid={session?.user.id} />
        <History type="site" id={site.id} ws={ws} uid={session?.user.id}
          labels={{ latitude: "latitude", longitude: "longitude", location_description: "description", access_instructions: "access", line_1: "address line 1",
            site_type: "type of site", zone_m: "zone (m)", risk_reason: "why monitored" }} />
      </div>
    </div>
      <BoundaryPanel ws={ws} site={site} canManage={canManage} />
      <AreasPanel ws={ws} site={site} canManage={canManage} />
      <CompliancePanel ws={ws} site={site} canManage={canManage} />
      <SharingPanel ws={ws} site={site} canManage={canManage} />
    </div>
  );
}

function Row({ k, children }: { k: string; children: React.ReactNode }) {
  return <div className="grid grid-cols-[7rem_1fr] gap-2"><dt className="text-muted-foreground">{k}</dt><dd className="text-primary [overflow-wrap:anywhere]">{children}</dd></div>;
}

const blank: SiteInput = { name: "", line_1: "", line_2: "", town: "", postcode: "", uprn: "", latitude: null, longitude: null, location_description: "", access_instructions: "", status: "active", programmes: [] };

function SiteForm({ ws, site, programmes, canManage, onDone, onCancel }: {
  ws: string; site?: Site; programmes: Programme[]; canManage: boolean; onDone: (id: string) => void; onCancel: () => void;
}) {
  const qc = useQueryClient();
  const id = useRef(site?.id ?? newId());
  const [v, setV] = useState<SiteInput>(site ? {
    name: site.name, line_1: site.line_1 ?? "", line_2: site.line_2 ?? "", town: site.town ?? "", postcode: site.postcode ?? "", uprn: site.uprn ?? "",
    latitude: site.latitude, longitude: site.longitude, location_description: site.location_description ?? "", access_instructions: site.access_instructions ?? "",
    status: site.status, programmes: site.programmes,
  } : { ...blank, programmes: programmes.length === 1 ? [programmes[0]!.id] : [] });
  const [grid, setGrid] = useState(site?.latitude != null ? toGridRef(site.latitude, site.longitude!, 10) ?? "" : "");
  const [gridError, setGridError] = useState<string | null>(null);
  const [locating, setLocating] = useState(false);
  const set = <K extends keyof SiteInput>(k: K, val: SiteInput[K]) => setV((x) => ({ ...x, [k]: val }));
  const setPoint = (lat: number, lon: number) => { setV((x) => ({ ...x, latitude: +lat.toFixed(6), longitude: +lon.toFixed(6) })); setGrid(toGridRef(lat, lon, 10) ?? ""); setGridError(null); };
  const save = useMutation({
    mutationFn: () => run(vvRpc.saveSite(id.current, ws, v)),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["ws", ws, "vv"] }); onDone(id.current); },
  });
  const hasLocation = v.latitude !== null || !!v.line_1.trim() || !!v.location_description.trim();
  const needsProgramme = !canManage && v.programmes.length === 0;
  return (
    <form className="space-y-4 rounded-md border-t-2 border-accent bg-secondary p-4" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <p className="font-semibold text-primary">{site ? `Edit ${site.reference}` : "New site"}</p>
      <Field id="sf-name" label="Site name"><Input id="sf-name" className="bg-background" maxLength={120} value={v.name} onChange={(e) => set("name", e.target.value)} placeholder="e.g. Dock 4, east quay" /></Field>

      <fieldset className="space-y-2">
        <legend className="text-sm font-medium text-primary">Location</legend>
        <p className="text-xs text-muted-foreground">Use your device's location, type a grid reference or coordinates, or click the map. You need a location, an address or a description.</p>
        <div className="flex flex-wrap items-end gap-3">
          <button type="button" disabled={locating || typeof navigator === "undefined" || !navigator.geolocation}
            onClick={() => { setLocating(true); navigator.geolocation.getCurrentPosition((p) => { setPoint(p.coords.latitude, p.coords.longitude); setLocating(false); }, () => setLocating(false), { enableHighAccuracy: true, timeout: 15000 }); }}
            className="h-9 rounded-md border border-primary bg-background px-3 text-sm font-medium text-primary disabled:opacity-60">{locating ? "Finding you…" : "Use my location"}</button>
          <Field id="sf-grid" label="Grid reference">
            <Input id="sf-grid" className="w-44 bg-background" value={grid} placeholder="TM 27350 34800" onChange={(e) => setGrid(e.target.value)}
              onBlur={() => { if (!grid.trim()) return; const p = fromGridRef(grid); if (p) { setPoint(p.lat, p.lon); } else setGridError("That isn't a valid grid reference."); }} />
          </Field>
          <Field id="sf-lat" label="Latitude"><Input id="sf-lat" className="w-32 bg-background" inputMode="decimal" value={v.latitude ?? ""}
            onChange={(e) => { const n = e.target.value === "" ? null : Number(e.target.value); set("latitude", Number.isFinite(n) ? n : null); }} onBlur={() => v.latitude !== null && v.longitude !== null && setPoint(v.latitude, v.longitude)} /></Field>
          <Field id="sf-lon" label="Longitude"><Input id="sf-lon" className="w-32 bg-background" inputMode="decimal" value={v.longitude ?? ""}
            onChange={(e) => { const n = e.target.value === "" ? null : Number(e.target.value); set("longitude", Number.isFinite(n) ? n : null); }} onBlur={() => v.latitude !== null && v.longitude !== null && setPoint(v.latitude, v.longitude)} /></Field>
          {v.latitude !== null ? <button type="button" className="h-9 text-sm text-primary underline" onClick={() => { setV((x) => ({ ...x, latitude: null, longitude: null })); setGrid(""); }}>Clear location</button> : null}
        </div>
        {gridError ? <p role="alert" className="text-sm text-primary">{gridError}</p> : null}
        <SurveillanceMap label="Choose the site's location" points={[]} height={260} onPick={setPoint}
          picked={v.latitude !== null && v.longitude !== null ? { lat: v.latitude, lon: v.longitude } : null} />
      </fieldset>

      <details open={!!(site?.line_1 || site?.postcode)}>
        <summary className="cursor-pointer text-sm font-medium text-primary">Address (optional)</summary>
        <div className="mt-2 grid gap-3 sm:grid-cols-2">
          <Field id="sf-l1" label="Address line 1"><Input id="sf-l1" className="bg-background" maxLength={200} value={v.line_1} onChange={(e) => set("line_1", e.target.value)} /></Field>
          <Field id="sf-l2" label="Address line 2"><Input id="sf-l2" className="bg-background" maxLength={200} value={v.line_2} onChange={(e) => set("line_2", e.target.value)} /></Field>
          <Field id="sf-town" label="Town"><Input id="sf-town" className="bg-background" maxLength={100} value={v.town} onChange={(e) => set("town", e.target.value)} /></Field>
          <Field id="sf-pc" label="Postcode"><Input id="sf-pc" className="bg-background" maxLength={10} value={v.postcode} onChange={(e) => set("postcode", e.target.value)} /></Field>
          <Field id="sf-uprn" label="UPRN (property identifier, optional)"><Input id="sf-uprn" className="bg-background" inputMode="numeric" maxLength={12} value={v.uprn} onChange={(e) => set("uprn", e.target.value.replace(/\D/g, ""))} /></Field>
        </div>
      </details>

      <Field id="sf-desc" label="Location description" hint="How to find it: landmarks, what's there."><Textarea id="sf-desc" className="bg-background" maxLength={2000} value={v.location_description} onChange={(e) => set("location_description", e.target.value)} /></Field>
      <Field id="sf-acc" label="Access instructions" hint="Gates, keys, contacts, safety, permits."><Textarea id="sf-acc" className="bg-background" maxLength={2000} value={v.access_instructions} onChange={(e) => set("access_instructions", e.target.value)} /></Field>

      <fieldset>
        <legend className="text-sm font-medium text-primary">Programmes</legend>
        {!programmes.length ? <p className="text-xs text-muted-foreground">No programmes you can add sites to yet. A manager sets them up in Vectovia → Set-up.</p> : (
          <div className="mt-1 flex flex-wrap gap-3">
            {programmes.map((p) => (
              <label key={p.id} className="flex items-center gap-2 text-sm">
                <input type="checkbox" checked={v.programmes.includes(p.id)}
                  onChange={(e) => { const on = e.target.checked; set("programmes", on ? [...v.programmes, p.id] : v.programmes.filter((x) => x !== p.id)); }} />{p.name}
              </label>
            ))}
          </div>
        )}
      </fieldset>

      {site ? (
        <Field id="sf-status" label="Status">
          <select id="sf-status" className={`${selectClass} max-w-xs`} value={v.status} onChange={(e) => set("status", e.target.value as Site["status"])}>
            <option value="active">Active</option><option value="inactive">Inactive (no longer used)</option>
          </select>
        </Field>
      ) : null}

      {!hasLocation ? <p className="text-sm text-primary">Add a location, an address line or a description.</p> : null}
      {needsProgramme ? <p className="text-sm text-primary">Choose at least one of your programmes.</p> : null}
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" disabled={save.isPending || v.name.trim().length < 2 || !hasLocation || needsProgramme}
          className="rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy disabled:opacity-60">{save.isPending ? "Saving…" : site ? "Save changes" : "Add site"}</button>
        <button type="button" onClick={onCancel} className="rounded-md border border-primary px-4 py-2 text-sm text-primary">Cancel</button>
      </div>
    </form>
  );
}

function SiteActivity({ ws, site }: { ws: string; site: Site }) {
  const deployments = useDeployments(ws), visits = useVisits(ws), samples = useSamples(ws), traps = useTraps(ws);
  if (!deployments.data || !visits.data || !samples.data || !traps.data) return null;
  const deps = deployments.data.filter((d) => d.site_id === site.id);
  const vs = visits.data.filter((v) => v.site_id === site.id);
  const ss = samples.data.filter((s) => s.site_id === site.id);
  return (
    <div className="space-y-1 text-xs">
      <p className="font-semibold uppercase tracking-wide text-accent">Activity</p>
      {deps.length === 0 ? <p className="text-muted-foreground">No traps deployed here yet.</p> : (
        <ul className="space-y-0.5">{deps.map((d) => <li key={d.id} className={d.ended_at ? "text-muted-foreground" : "text-primary"}>{traps.data.find((t) => t.id === d.trap_id)?.identifier ?? "Trap"}: {deploymentLine(d, site).split(" · ").slice(2).join(" · ")}</li>)}</ul>
      )}
      <p className="text-muted-foreground">
        {vs.length} visit{vs.length === 1 ? "" : "s"} ({(["collected", "no_catch", "not_completed"] as const).map((o) => `${vs.filter((v) => v.outcome === o).length} ${outcomeLabels[o].toLowerCase()}`).join(", ")}) · {ss.length} sample{ss.length === 1 ? "" : "s"}, {ss.filter((s) => s.status === "awaiting_result").length} awaiting results
      </p>
      <p className="text-muted-foreground">Findings and actions appear here once results are built.</p>
    </div>
  );
}
