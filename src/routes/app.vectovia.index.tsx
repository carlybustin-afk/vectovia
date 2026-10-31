import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { AppShell, ErrorState, Loading, appHead } from "@/components/app-shell";
import { wsKey } from "@/lib/workspace";
import { trapStatusLabels } from "@/modules/vectovia/api";
import { loadIncursions } from "@/modules/vectovia/incursions";
import { VectoviaMark } from "@/modules/vectovia/brand";
import { SurveillanceMap } from "@/modules/vectovia/map";
import { attentionOf, measureLabels, siteGroupLabels, siteRag, useBenchmarks, useOrgStatus, type SiteStatus } from "@/modules/vectovia/dashboards";
import { SiteRagTag } from "@/modules/vectovia/site-panels";
import type { Site } from "@/modules/vectovia/api";
import { useActions, useFindings, useProgrammes, useSamples, useSchedule, useSites, useTraps, useVv } from "@/modules/vectovia/ui";

export const Route = createFileRoute("/app/vectovia/")({
  head: () => appHead("Vectovia", "Vector surveillance: traps, visits, samples, results, risk assessment and incursion management."),
  component: VectoviaHome,
});

function VectoviaHome() {
  return (
    <AppShell product="vectovia" section="vectovia" title="Surveillance dashboard"
      intro="Trap management, risk assessment, data and analytics, and incursion management. Figures count only the records you can see.">
      <Dashboard />
    </AppShell>
  );
}

function Dashboard() {
  const { ws } = useVv();
  const programmes = useProgrammes(ws);
  const sites = useSites(ws);
  const traps = useTraps(ws);
  const schedule = useSchedule(ws);
  const samples = useSamples(ws);
  const findings = useFindings(ws);
  const actions = useActions(ws);
  const incursions = useQuery({ queryKey: wsKey(ws, "vv", "incursions"), queryFn: () => loadIncursions(ws) });
  if ([programmes, sites, traps, schedule, samples, findings, actions].some((q) => q.isPending) || incursions.isPending) return <Loading what="Loading surveillance" />;
  const err = programmes.error ?? sites.error ?? traps.error ?? schedule.error ?? samples.error ?? findings.error ?? actions.error;
  if (err) return <ErrorState error={err} />;
  const activeSites = sites.data!.filter((s) => s.status === "active");
  const overdue = schedule.data!.filter((r) => r.state === "overdue").length, due = schedule.data!.filter((r) => r.state === "due").length;
  const awaiting = samples.data!.filter((s) => s.status === "awaiting_result").length;
  const tiles: { label: string; n: number | string; detail: string; to?: "/app/vectovia/sites" | "/app/vectovia/traps" | "/app/vectovia/setup" | "/app/vectovia/visits" | "/app/vectovia/results" | "/app/vectovia/risk" | "/app/vectovia/incursions" }[] = [
    { label: "Active programmes", n: programmes.data!.filter((p) => p.status === "active").length, detail: `${programmes.data!.length} in total`, to: "/app/vectovia/setup" },
    { label: "Active sites", n: activeSites.length, detail: `${activeSites.filter((s) => s.latitude === null).length} without a map location`, to: "/app/vectovia/sites" },
    { label: "Traps deployed", n: traps.data!.filter((t) => t.status === "deployed").length, detail: (["available", "damaged"] as const).map((s) => `${traps.data!.filter((t) => t.status === s).length} ${trapStatusLabels[s].toLowerCase()}`).join(" · "), to: "/app/vectovia/traps" },
    { label: "Visits due or overdue", n: overdue + due, detail: overdue ? `▲ ${overdue} overdue` : "None overdue", to: "/app/vectovia/visits" },
    { label: "Samples awaiting results", n: awaiting, detail: "Add identification or lab results", to: "/app/vectovia/results" },
    { label: "Findings awaiting review", n: findings.data!.length, detail: "Provisional or confirmed, not yet assessed", to: "/app/vectovia/risk" },
    { label: "Open follow-up actions", n: actions.data!.filter((a) => a.status === "open").length,
      detail: (() => { const t = new Date().toISOString().slice(0, 10); const o = actions.data!.filter((a) => a.status === "open" && a.due_on && a.due_on < t).length; return o ? `▲ ${o} overdue` : "None overdue"; })(), to: "/app/vectovia/risk" },
    ...(incursions.data ? [{ label: "Active incursions", n: incursions.data.incursions.filter((i) => i.status !== "stood_down").length,
      detail: `${incursions.data.incursions.filter((i) => i.status === "stood_down").length} stood down`, to: "/app/vectovia/incursions" as const }] : []),
  ];
  const circles = (incursions.data?.incursions ?? []).filter((i) => i.status !== "stood_down" && i.response_area)
    .map((i) => ({ id: i.id, lat: i.response_area!.lat, lon: i.response_area!.lon, radius_m: i.response_area!.radius_m, label: `${i.reference} response area` }));
  const points = activeSites.filter((s) => s.latitude !== null).map((s) => ({ id: s.id, lat: s.latitude!, lon: s.longitude!, label: `${s.reference} · ${s.name}` }));
  return (
    <div className="space-y-6">
      <VectoviaMark />
      <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {tiles.map((t) => {
          const body = (
            <>
              <span className="block text-sm text-muted-foreground">{t.label}</span>
              <span className="mt-1 block text-3xl font-bold tracking-tight text-primary">{t.n}</span>
              <span className="mt-1 block text-xs text-muted-foreground">{t.detail}</span>
            </>
          );
          return (
            <li key={t.label}>
              {t.to ? <Link to={t.to} className="block h-full rounded-md border-t-2 border-accent bg-secondary p-4 hover:bg-secondary/70">{body}</Link>
                : <div className="h-full rounded-md border border-dashed border-border p-4">{body}</div>}
            </li>
          );
        })}
      </ul>
      <SiteAttention ws={ws} sites={activeSites} />
      <Compare ws={ws} />
      <section aria-labelledby="dm-h">
        <h2 id="dm-h" className="mb-2 font-semibold text-primary">Active sites</h2>
        <SurveillanceMap label="Map of active sites and incursion response areas" points={points} circles={circles} />
        {points.length === 0 ? <p className="mt-2 text-sm text-muted-foreground">No sites with a map location yet. Add them on the <Link to="/app/vectovia/sites" className="underline">Sites</Link> page.</p> : null}
      </section>
    </div>
  );
}

function SiteAttention({ ws, sites }: { ws: string; sites: Site[] }) {
  const status = useOrgStatus(ws);
  if (status.isPending) return <Loading what="Working out site status" />;
  if (status.error) return <ErrorState error={status.error} />;
  const byId = new Map(sites.map((s) => [s.id, s]));
  const order = { red: 0, amber: 1, green: 2 } as const;
  const rows = status.data.filter((r) => byId.has(r.site_id)).map((r) => ({ r, rag: siteRag(r), items: attentionOf(r) }))
    .sort((a, b) => order[a.rag] - order[b.rag] || b.items.length - a.items.length);
  const need = rows.filter((x) => x.rag !== "green").length;
  return (
    <section aria-labelledby="sa-h" className="space-y-2">
      <h2 id="sa-h" className="font-semibold text-primary">Sites needing attention <span className="font-normal text-muted-foreground">· {need} of {rows.length}</span></h2>
      {rows.length === 0 ? <p className="text-sm text-muted-foreground">No active sites you can see yet.</p> : (
        <ul className="divide-y divide-border rounded-md border border-border">
          {rows.map(({ r, rag, items }) => {
            const s = byId.get(r.site_id)!;
            return (
              <li key={r.site_id} className="flex flex-wrap items-start gap-3 px-3 py-2 text-sm">
                <SiteRagTag status={rag} />
                <div className="min-w-0 flex-1">
                  <Link to="/app/vectovia/sites" className="font-medium text-primary underline">{s.reference} · {s.name}</Link>
                  <p className="text-primary [overflow-wrap:anywhere]">{items.length ? items.join(" · ") : "Nothing needs attention."}</p>
                  <p className="text-xs text-muted-foreground">{summary(r)}</p>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

function summary(r: SiteStatus) {
  const parts = [...(r.requirements ? [`${r.met} of ${r.requirements - r.not_applicable} requirements met`] : []),
    `${r.active_traps} active trap${r.active_traps === 1 ? "" : "s"}`, `${r.positives_12m} positive find${r.positives_12m === 1 ? "" : "s"} in 12 months`];
  if (r.open_surveys) parts.push(`${r.open_surveys} delimiting survey${r.open_surveys === 1 ? "" : "s"} open`);
  return parts.join(" · ");
}

function Compare({ ws }: { ws: string }) {
  const b = useBenchmarks(ws);
  if (b.isPending) return <Loading what="Loading comparisons" />;
  if (b.error) return <ErrorState error={b.error} />;
  return (
    <section aria-labelledby="cmp-h" className="space-y-2">
      <h2 id="cmp-h" className="font-semibold text-primary">How you compare</h2>
      <p className="max-w-3xl text-sm text-muted-foreground">
        Your sites against the average for other organisations&apos; sites of the same kind. No other organisation or site is ever named.
        A comparison is shown only when at least 5 sites from at least 3 other organisations contribute.
      </p>
      {b.data.length === 0 ? <p className="text-sm text-muted-foreground">Nothing to compare yet: add active sites first.</p> : (
        <div className="overflow-x-auto rounded-md border border-border">
          <table className="w-full text-left text-sm">
            <caption className="sr-only">Your figures against the anonymous average</caption>
            <thead className="bg-secondary text-primary">
              <tr>
                <th scope="col" className="px-3 py-2 font-semibold">Measure</th>
                <th scope="col" className="px-3 py-2 font-semibold">Your sites</th>
                <th scope="col" className="px-3 py-2 font-semibold">Others (average)</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {b.data.map((x) => (
                <tr key={x.site_group + x.measure}>
                  <th scope="row" className="px-3 py-2 font-medium text-primary">{measureLabels[x.measure]}<span className="block text-xs font-normal text-muted-foreground">{siteGroupLabels[x.site_group]}</span></th>
                  <td className="px-3 py-2 text-primary">{x.your_value ?? "–"}%<span className="block text-xs text-muted-foreground">{x.your_sites} site{x.your_sites === 1 ? "" : "s"}</span></td>
                  <td className="px-3 py-2 text-primary">{x.benchmark_value === null ? <span className="text-muted-foreground">Not enough sites to compare yet</span>
                    : <>{x.benchmark_value}%<span className="block text-xs text-muted-foreground">{x.benchmark_sites} sites</span></>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
