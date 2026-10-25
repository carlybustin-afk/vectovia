import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { AppShell, ErrorState, Loading, appHead } from "@/components/app-shell";
import { wsKey } from "@/lib/workspace";
import { trapStatusLabels } from "@/modules/vectovia/api";
import { loadIncursions } from "@/modules/vectovia/incursions";
import { VectoviaMark } from "@/modules/vectovia/brand";
import { SurveillanceMap } from "@/modules/vectovia/map";
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
      <section aria-labelledby="dm-h">
        <h2 id="dm-h" className="mb-2 font-semibold text-primary">Active sites</h2>
        <SurveillanceMap label="Map of active sites and incursion response areas" points={points} circles={circles} />
        {points.length === 0 ? <p className="mt-2 text-sm text-muted-foreground">No sites with a map location yet. Add them on the <Link to="/app/vectovia/sites" className="underline">Sites</Link> page.</p> : null}
      </section>
    </div>
  );
}
