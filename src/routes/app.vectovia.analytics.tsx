import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { useMemo, useState, type ReactNode } from "react";
import { AppShell, ErrorState, Loading, appHead } from "@/components/app-shell";
import { Input } from "@/components/ui/input";
import { wsKey } from "@/lib/workspace";
import type { ResultVersion, Site } from "@/modules/vectovia/api";
import {
  currentFindings, effort, findings, fmtDays, loadAnalytics, monthLabel, pct, performance, ukDate, type Filter, type Spread,
} from "@/modules/vectovia/analytics";
import { loadIncursions } from "@/modules/vectovia/incursions";
import { SurveillanceMap, type MapCircle, type MapPoint } from "@/modules/vectovia/map";
import { Field, selectClass, useLists, useProgrammes, useSites, useVv } from "@/modules/vectovia/ui";

export const Route = createFileRoute("/app/vectovia/analytics")({
  head: () => appHead("Analytics · Vectovia", "Trap effort and coverage, findings over time, map views and response performance."),
  component: AnalyticsPage,
});

function AnalyticsPage() {
  return (
    <AppShell product="vectovia" section="vectovia" title="Analytics"
      intro="Trap effort and coverage, findings over time, map views and how quickly findings are dealt with. Every figure is worked out from the records you can see; nothing is typed in or estimated.">
      <Analytics />
    </AppShell>
  );
}

const today = () => ukDate(new Date().toISOString());
const monthsAgo = (n: number) => { const d = new Date(); d.setMonth(d.getMonth() - n); return ukDate(d.toISOString()); };
const presets = [
  { key: "3m", label: "Last 3 months", from: () => monthsAgo(3) },
  { key: "12m", label: "Last 12 months", from: () => monthsAgo(12) },
  { key: "year", label: "This year", from: () => `${today().slice(0, 4)}-01-01` },
  { key: "custom", label: "Choose dates", from: () => monthsAgo(12) },
] as const;

function Analytics() {
  const { ws } = useVv();
  const data = useQuery({ queryKey: wsKey(ws, "vv", "analytics"), queryFn: () => loadAnalytics(ws), staleTime: 60_000 });
  const inc = useQuery({ queryKey: wsKey(ws, "vv", "incursions"), queryFn: () => loadIncursions(ws) });
  const sites = useSites(ws), lists = useLists(ws), programmes = useProgrammes(ws);
  const [preset, setPreset] = useState<(typeof presets)[number]["key"]>("12m");
  const [from, setFrom] = useState(monthsAgo(12));
  const [to, setTo] = useState(today());
  const [programme, setProgramme] = useState("");
  const [site, setSite] = useState("");
  const [mapView, setMapView] = useState<"findings" | "effort" | "incursions">("findings");

  const all = [data, inc, sites, lists, programmes];
  const ready = all.every((q) => q.data !== undefined);
  const filter: Filter = useMemo(() => {
    const p = presets.find((x) => x.key === preset)!;
    const f = preset === "custom" ? from : p.from(), t = preset === "custom" ? to : today();
    const chosen = site ? new Set([site]) : programme && sites.data ? new Set(sites.data.filter((s) => s.programmes.includes(programme)).map((s) => s.id)) : null;
    return { from: f <= t ? f : t, to: t, sites: chosen };
  }, [preset, from, to, programme, site, sites.data]);

  const figures = useMemo(() => {
    if (!data.data || !lists.data) return null;
    const taxonOf = (v: ResultVersion) =>
      lists.data!.taxa.find((t) => t.id === v.taxon_id)?.scientific_name ?? lists.data!.councilTaxa.find((t) => t.id === v.council_taxon_id)?.scientific_name ?? "Not identified";
    const rows = currentFindings(data.data, filter, taxonOf);
    return { e: effort(data.data, filter), f: findings(data.data, filter, rows), p: performance(data.data, filter) };
  }, [data.data, lists.data, filter]);

  if (all.some((q) => q.isPending)) return <Loading what="Working out the figures" />;
  const err = all.find((q) => q.isError)?.error;
  if (err) return <ErrorState error={err} />;
  if (!ready || !figures) return null;
  const { e, f, p } = figures;
  const siteList = sites.data!;
  const shownSites = filter.sites ? siteList.filter((s) => filter.sites!.has(s.id)) : siteList;
  const siteName = (id: string) => { const s = siteList.find((x) => x.id === id); return s ? `${s.reference} · ${s.name}` : "Site"; };
  const coverage = e.visitsPlanned ? Math.min(1, (e.visitsDone - e.notCompleted) / e.visitsPlanned) : null;

  const located = (s: Site) => s.latitude !== null && s.longitude !== null;
  let points: MapPoint[] = [], circles: MapCircle[] = [], mapNote = "";
  if (mapView === "findings") {
    points = shownSites.filter(located).map((s) => { const x = f.bySite.get(s.id); return { id: s.id, lat: s.latitude!, lon: s.longitude!, label: `${s.reference} · ${s.name}: ${x?.findings ?? 0} findings from ${x?.samples ?? 0} samples`, muted: !x?.findings }; });
    mapNote = "Filled markers: sites with provisional or confirmed findings in the period. Hollow: none.";
  } else if (mapView === "effort") {
    points = shownSites.filter(located).map((s) => { const x = e.bySite.get(s.id); return { id: s.id, lat: s.latitude!, lon: s.longitude!, label: `${s.reference} · ${s.name}: ${x?.trapNights ?? 0} trap-nights, ${x?.visits ?? 0} of ${x?.planned ?? 0} planned visits`, muted: !x?.trapNights }; });
    mapNote = "Filled markers: sites with traps out in the period. Hover for trap-nights and visits.";
  } else {
    const active = (inc.data?.incursions ?? []).filter((i) => i.status !== "stood_down" && (!filter.sites || i.sites.some((s) => filter.sites!.has(s))));
    circles = active.filter((i) => i.response_area).map((i) => ({ id: i.id, lat: i.response_area!.lat, lon: i.response_area!.lon, radius_m: i.response_area!.radius_m, label: `${i.reference}: ${i.title}` }));
    points = active.map((i) => siteList.find((s) => s.id === i.site_id)).filter((s): s is Site => !!s && located(s)).map((s) => ({ id: s.id, lat: s.latitude!, lon: s.longitude!, label: siteName(s.id) }));
    mapNote = inc.data === null ? "Incursion management isn't switched on yet." : `${active.length} active incursion${active.length === 1 ? "" : "s"}; dashed circles are response areas.`;
  }

  return (
    <div className="space-y-10">
      <form className="grid gap-3 rounded-md bg-secondary p-4 sm:grid-cols-2 lg:grid-cols-4" onSubmit={(ev) => ev.preventDefault()} aria-label="Filters">
        <Field id="an-p" label="Period">
          <select id="an-p" className={selectClass} value={preset} onChange={(ev) => setPreset(ev.target.value as typeof preset)}>
            {presets.map((x) => <option key={x.key} value={x.key}>{x.label}</option>)}
          </select>
        </Field>
        {preset === "custom" ? (
          <div className="grid grid-cols-2 gap-2">
            <Field id="an-f" label="From"><Input id="an-f" type="date" className="bg-background" value={from} max={to} onChange={(ev) => setFrom(ev.target.value)} /></Field>
            <Field id="an-t" label="To"><Input id="an-t" type="date" className="bg-background" value={to} min={from} max={today()} onChange={(ev) => setTo(ev.target.value)} /></Field>
          </div>
        ) : null}
        <Field id="an-pr" label="Programme">
          <select id="an-pr" className={selectClass} value={programme} onChange={(ev) => { setProgramme(ev.target.value); setSite(""); }}>
            <option value="">All you can see</option>
            {programmes.data!.map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
          </select>
        </Field>
        <Field id="an-s" label="Site">
          <select id="an-s" className={selectClass} value={site} onChange={(ev) => setSite(ev.target.value)}>
            <option value="">All{programme ? " in this programme" : " you can see"}</option>
            {(programme ? siteList.filter((s) => s.programmes.includes(programme)) : siteList).map((s) => <option key={s.id} value={s.id}>{s.reference} · {s.name}</option>)}
          </select>
        </Field>
        <p className="text-xs text-muted-foreground sm:col-span-2 lg:col-span-4">
          {filter.from} to {filter.to} (UK dates) · {filter.sites ? `${filter.sites.size} site${filter.sites.size === 1 ? "" : "s"}` : `all ${siteList.length} site${siteList.length === 1 ? "" : "s"} you can see`}
          {data.data!.capped ? " · ▲ Very large council: only the first 50,000 records of each kind are counted." : ""}
        </p>
      </form>

      <Section id="ef" title="Trap effort and coverage" note="Trap-nights are counted from deployment dates (an open deployment counts up to today). Planned visits are whole visit intervals while the trap was out; missed visits are planned visits with no record.">
        <Tiles items={[
          ["Trap-nights", e.trapNights.toLocaleString("en-GB"), ""],
          ["Visits recorded", String(e.visitsDone), `${e.visitsPlanned} planned · ${e.completed} completed · ${e.notCompleted} not completed`],
          ["Coverage", pct(coverage), "Completed visits ÷ planned visits"],
          ["Missed visits", String(e.missed), "Planned, with no visit recorded"],
        ]} />
        <MonthTable rows={e.byMonth.map((m) => ({ month: m.month, a: m.trapNights, b: m.visits }))} aLabel="Trap-nights" bLabel="Visits" caption="Trap effort by month" />
      </Section>

      <Section id="fi" title="Findings over time" note="Dated by when the sample was collected. Uses each result's latest version. Positivity: samples with at least one provisional or confirmed finding, out of samples whose results are all in (none pending).">
        <Tiles items={[
          ["Samples collected", String(f.samples), `${f.samples - f.samplesResulted} still awaiting results`],
          ["Samples with findings", String(f.samplesPositive), `of ${f.samplesResulted} with results`],
          ["Positivity", pct(f.positivity), ""],
          ["Species found", String(f.bySpecies.length), f.bySpecies[0] ? `Most often: ${f.bySpecies[0].taxon}` : ""],
        ]} />
        <MonthTable rows={f.byMonth.map((m) => ({ month: m.month, a: m.samples, b: m.positive }))} aLabel="Samples" bLabel="With findings" caption="Samples and findings by month" />
        <div className="grid gap-6 lg:grid-cols-2">
          <SimpleTable caption="Findings by species" head={["Species", "Findings", "Confirmed", "Sites"]}
            rows={f.bySpecies.map((x) => [<em key="t">{x.taxon}</em>, x.findings, x.confirmed, x.sites])} empty="No provisional or confirmed findings in this period." />
          <SimpleTable caption="Findings by site" head={["Site", "Samples", "Findings"]}
            rows={[...f.bySite.entries()].sort((a, b) => b[1].findings - a[1].findings).map(([id, x]) => [siteName(id), x.samples, x.findings])} empty="No samples in this period." />
        </div>
      </Section>

      <Section id="mp" title="Map" note={mapNote}>
        <div role="group" aria-label="Map view" className="flex flex-wrap gap-1">
          {(["findings", "effort", "incursions"] as const).map((k) => (
            <button key={k} type="button" aria-pressed={mapView === k} onClick={() => setMapView(k)}
              className={`h-9 rounded-md px-3 text-sm font-medium ${mapView === k ? "bg-primary text-primary-foreground" : "border border-border text-primary"}`}>
              {k === "findings" ? "Findings" : k === "effort" ? "Trap effort" : "Active incursions"}
            </button>
          ))}
        </div>
        <SurveillanceMap points={points} circles={circles} label={`Map of ${mapView}`} height={380} />
      </Section>

      <Section id="rp" title="Response performance" note="Collection to result: from the visit to the first identification or lab result (not “pending”). Result to assessment: from that first result to the first risk assessment covering it (provisional or confirmed findings only). Actions are counted by due date in the period.">
        <div className="grid gap-4 sm:grid-cols-3">
          <SpreadTile label="Collection → result" s={p.collectionToResult} />
          <SpreadTile label="Result → risk assessment" s={p.resultToAssessment} />
          <SpreadTile label="Collection → risk assessment" s={p.collectionToAssessment} />
        </div>
        <SimpleTable caption="Follow-up actions" head={["", "Number"]} rows={[
          ["Done on time", p.actions.doneOnTime], ["Done late", p.actions.doneLate], ["Done (no due date)", p.actions.doneNoDue],
          ["Open and overdue", p.actions.openOverdue], ["Open, not yet due", p.actions.openInTime], ["Cancelled", p.actions.cancelled],
        ]} empty="" />
      </Section>
    </div>
  );
}

function Section({ id, title, note, children }: { id: string; title: string; note?: string; children: ReactNode }) {
  return (
    <section aria-labelledby={`${id}-h`} className="space-y-4">
      <div>
        <h2 id={`${id}-h`} className="text-lg font-semibold text-primary">{title}</h2>
        {note ? <p className="mt-1 max-w-3xl text-xs text-muted-foreground">{note}</p> : null}
      </div>
      {children}
    </section>
  );
}

function Tiles({ items }: { items: [string, string, string][] }) {
  return (
    <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
      {items.map(([label, n, detail]) => (
        <li key={label} className="rounded-md border-t-2 border-accent bg-secondary p-4">
          <span className="block text-sm text-muted-foreground">{label}</span>
          <span className="mt-1 block text-2xl font-bold tracking-tight text-primary">{n}</span>
          {detail ? <span className="mt-1 block text-xs text-muted-foreground">{detail}</span> : null}
        </li>
      ))}
    </ul>
  );
}

function SpreadTile({ label, s }: { label: string; s: Spread }) {
  return (
    <div className="rounded-md border-t-2 border-accent bg-secondary p-4">
      <span className="block text-sm text-muted-foreground">{label}</span>
      <span className="mt-1 block text-2xl font-bold tracking-tight text-primary">{fmtDays(s.median)}</span>
      <span className="mt-1 block text-xs text-muted-foreground">{s.n ? `Middle value of ${s.n} · fastest ${fmtDays(s.min)} · slowest ${fmtDays(s.max)}` : "Nothing to measure in this period"}</span>
    </div>
  );
}

/** Two figures per month: the numbers are in the table; the bars only repeat them visually. */
function MonthTable({ rows, aLabel, bLabel, caption }: { rows: { month: string; a: number; b: number }[]; aLabel: string; bLabel: string; caption: string }) {
  const maxA = Math.max(1, ...rows.map((r) => r.a)), maxB = Math.max(1, ...rows.map((r) => r.b));
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[28rem] text-sm">
        <caption className="mb-1 text-left text-xs font-semibold uppercase tracking-wide text-accent">{caption}</caption>
        <thead><tr className="border-b border-border text-left text-muted-foreground"><th className="py-1 pr-3 font-medium">Month</th><th className="py-1 pr-3 font-medium">{aLabel}</th><th className="py-1 font-medium">{bLabel}</th></tr></thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.month} className="border-b border-border/60">
              <td className="whitespace-nowrap py-1 pr-3 text-primary">{monthLabel(r.month)}</td>
              <td className="w-1/2 py-1 pr-3"><Bar n={r.a} max={maxA} strong /></td>
              <td className="w-1/2 py-1"><Bar n={r.b} max={maxB} /></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
function Bar({ n, max, strong }: { n: number; max: number; strong?: boolean }) {
  return (
    <span className="flex items-center gap-2">
      <span className="w-10 shrink-0 text-right tabular-nums text-primary">{n.toLocaleString("en-GB")}</span>
      <span aria-hidden="true" className="h-2.5 flex-1 rounded-sm bg-border/50">
        <span className={`block h-full rounded-sm ${strong ? "bg-primary" : "bg-accent"}`} style={{ width: `${(n / max) * 100}%` }} />
      </span>
    </span>
  );
}

function SimpleTable({ caption, head, rows, empty }: { caption: string; head: string[]; rows: ReactNode[][]; empty: string }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <caption className="mb-1 text-left text-xs font-semibold uppercase tracking-wide text-accent">{caption}</caption>
        <thead><tr className="border-b border-border text-left text-muted-foreground">{head.map((h, i) => <th key={i} className={`py-1 pr-3 font-medium ${i ? "text-right" : ""}`}>{h}</th>)}</tr></thead>
        <tbody>
          {rows.length === 0 ? <tr><td colSpan={head.length} className="py-2 text-muted-foreground">{empty}</td></tr>
            : rows.map((r, i) => <tr key={i} className="border-b border-border/60">{r.map((c, j) => <td key={j} className={`py-1 pr-3 ${j ? "text-right tabular-nums" : ""} text-primary`}>{c}</td>)}</tr>)}
        </tbody>
      </table>
    </div>
  );
}
