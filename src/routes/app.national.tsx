import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { AppShell, ErrorState, Loading, StateMessage, appHead } from "@/components/app-shell";
import { attentionOf, nationalCsv, siteRag, useIsNational, useNationalSites, type NationalSite } from "@/modules/vectovia/dashboards";
import { SurveillanceMap } from "@/modules/vectovia/map";
import { pointOfEntryTypes, siteTypeLabels, type SiteType } from "@/modules/vectovia/obligations";
import { SiteRagTag } from "@/modules/vectovia/site-panels";

export const Route = createFileRoute("/app/national")({
  head: () => appHead("National view", "Named sites, their compliance and findings, and national totals (national viewers only)."),
  component: NationalPage,
});

function NationalPage() {
  return (
    <AppShell needsWorkspace={false} title="National view"
      intro="Named sites across every organisation, with their compliance and findings, and national totals. This view is read-only: it shows each site's status, never an organisation's records, people or history.">
      <National />
    </AppShell>
  );
}

const typeLabel = (t: string) => siteTypeLabels[t as SiteType] ?? t;
const n = (count: number, one: string, many = `${one}s`) => `${count} ${count === 1 ? one : many}`;

function National() {
  const isNational = useIsNational();
  const sites = useNationalSites(isNational);
  const [org, setOrg] = useState("");
  const [onlyAttention, setOnlyAttention] = useState(false);
  const all = sites.data ?? [];
  const orgs = useMemo(() => [...new Set(all.map((s) => s.organisation))].sort(), [all]);
  if (!isNational) return <StateMessage title="National viewers only">This page is for people named by the platform owner as national viewers.</StateMessage>;
  if (sites.isPending) return <Loading what="Loading the national picture" />;
  if (sites.error) return <ErrorState error={sites.error} />;
  const shown = all.filter((s) => (!org || s.organisation === org) && (!onlyAttention || siteRag(s) !== "green"));
  const sum = (f: (s: NationalSite) => number) => all.reduce((n, s) => n + f(s), 0);
  const tiles = [
    { label: "Named sites", n: all.length, detail: `${n(all.filter((s) => pointOfEntryTypes.includes(s.site_type as SiteType)).length, "point of entry", "points of entry")} · ${n(orgs.length, "organisation")}` },
    { label: "Traps deployed", n: sum((s) => s.active_traps), detail: `${n(all.filter((s) => s.active_traps === 0).length, "site")} with none` },
    { label: "Checks overdue", n: sum((s) => s.overdue_checks), detail: `at ${n(all.filter((s) => s.overdue_checks > 0).length, "site")}` },
    { label: "Positive finds (12 months)", n: sum((s) => s.positives_12m), detail: `${sum((s) => s.invasive_12m)} of an invasive species` },
    { label: "Awaiting official identification", n: sum((s) => s.invasive_awaiting), detail: "Provisional invasive finds" },
    { label: "Delimiting surveys open", n: sum((s) => s.open_surveys), detail: `${sum((s) => s.open_incursions)} incursion${sum((s) => s.open_incursions) === 1 ? "" : "s"} open` },
  ];
  const bySet = new Map<string, { sites: number; red: number; amber: number; green: number }>();
  for (const s of all) for (const name of (s.obligation_sets ?? "").split("; ").filter(Boolean)) {
    const x = bySet.get(name) ?? { sites: 0, red: 0, amber: 0, green: 0 };
    x.sites++; x[siteRag(s)]++; bySet.set(name, x);
  }
  const download = () => {
    const blob = new Blob(["﻿" + nationalCsv(all)], { type: "text/csv;charset=utf-8" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob); a.download = `vectovia-national-return-${new Date().toISOString().slice(0, 10)}.csv`; a.click();
    URL.revokeObjectURL(a.href);
  };
  const points = shown.filter((s) => s.latitude !== null).map((s) => ({ id: s.site_reference + s.organisation, lat: s.latitude!, lon: s.longitude!, label: `${s.organisation}: ${s.site_name}` }));
  return (
    <div className="space-y-6">
      <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {tiles.map((t) => (
          <li key={t.label} className="rounded-md border-t-2 border-accent bg-secondary p-4">
            <span className="block text-sm text-muted-foreground">{t.label}</span>
            <span className="mt-1 block text-3xl font-bold tracking-tight text-primary">{t.n}</span>
            <span className="mt-1 block text-xs text-muted-foreground">{t.detail}</span>
          </li>
        ))}
      </ul>

      <section aria-labelledby="cs-h" className="space-y-2">
        <h2 id="cs-h" className="font-semibold text-primary">Compliance by obligation set</h2>
        {bySet.size === 0 ? <p className="text-sm text-muted-foreground">No site has adopted an obligation set yet.</p> : (
          <div className="overflow-x-auto rounded-md border border-border">
            <table className="w-full text-left text-sm">
              <caption className="sr-only">Sites under each obligation set, by overall status</caption>
              <thead className="bg-secondary text-primary">
                <tr>{["Obligation set", "Sites", "Needs action", "Some gaps", "All met"].map((h) => <th key={h} scope="col" className="px-3 py-2 font-semibold">{h}</th>)}</tr>
              </thead>
              <tbody className="divide-y divide-border">
                {[...bySet].sort(([a], [b]) => a.localeCompare(b)).map(([name, x]) => (
                  <tr key={name}><th scope="row" className="px-3 py-2 font-medium text-primary">{name}</th><td className="px-3 py-2">{x.sites}</td>
                    <td className="px-3 py-2">{x.red}</td><td className="px-3 py-2">{x.amber}</td><td className="px-3 py-2">{x.green}</td></tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section aria-labelledby="ns-h" className="space-y-3">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <h2 id="ns-h" className="font-semibold text-primary">Named sites <span className="font-normal text-muted-foreground">· {shown.length} shown</span></h2>
          <div className="flex flex-wrap items-end gap-3 text-sm">
            <label className="flex flex-col gap-1"><span className="text-muted-foreground">Organisation</span>
              <select className="h-9 rounded-md border border-input bg-background px-2" value={org} onChange={(e) => setOrg(e.target.value)}>
                <option value="">All organisations</option>
                {orgs.map((o) => <option key={o} value={o}>{o}</option>)}
              </select>
            </label>
            <label className="flex h-9 items-center gap-2"><input type="checkbox" checked={onlyAttention} onChange={(e) => setOnlyAttention(e.target.checked)} />Needing attention only</label>
            <button type="button" onClick={download} className="h-9 rounded-md border border-primary px-3 font-medium text-primary">Download national return (CSV)</button>
          </div>
        </div>
        <SurveillanceMap label="Map of named sites" points={points} />
        <ul className="divide-y divide-border rounded-md border border-border">
          {shown.map((s) => {
            const items = attentionOf(s);
            return (
              <li key={s.organisation + s.site_reference} className="flex flex-wrap items-start gap-3 px-3 py-2 text-sm">
                <SiteRagTag status={siteRag(s)} />
                <div className="min-w-0 flex-1">
                  <p className="font-medium text-primary">{s.site_name} <span className="font-normal text-muted-foreground">· {s.site_reference} · {typeLabel(s.site_type)} · {s.organisation}</span></p>
                  <p className="text-primary [overflow-wrap:anywhere]">{items.length ? items.join(" · ") : "Nothing needs attention."}</p>
                  <p className="text-xs text-muted-foreground">
                    {[s.obligation_sets, s.requirements ? `${s.met} of ${s.requirements} requirements met` : null, n(s.active_traps, "active trap"),
                      `${n(s.positives_12m, "positive find")} in 12 months`].filter(Boolean).join(" · ")}
                  </p>
                </div>
              </li>
            );
          })}
        </ul>
      </section>
    </div>
  );
}
