import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useMemo, useState } from "react";
import { AppShell, ErrorState, Loading, StateMessage, appHead } from "@/components/app-shell";
import { Input } from "@/components/ui/input";
import { useSession } from "@/lib/session";
import { useWorkspace, wsKey } from "@/lib/workspace";
import { newId, when, who } from "@/modules/vectovia/api";
import { loadAnalytics, ukDate, type Filter } from "@/modules/vectovia/analytics";
import { FORMAT, csvBlob, fileStamp, loadExportLog, logAndDownload, safeName, toCsv, type ExportKind } from "@/modules/vectovia/export-doc";
import { loadIncursions } from "@/modules/vectovia/incursions";
import { csvRows, csvSets, scopeOf, surveillanceReport, type CsvSet, type ReportContext } from "@/modules/vectovia/reports";
import { Field, selectClass, useAssessments, useLists, useProgrammes, useSites, useTraps, useVv } from "@/modules/vectovia/ui";

export const Route = createFileRoute("/app/vectovia/reports")({
  head: () => appHead("Reports · Vectovia", "Surveillance reports (PDF and Word) and CSV exports, fingerprinted and logged."),
  component: ReportsPage,
});

function ReportsPage() {
  return (
    <AppShell product="vectovia" section="vectovia" title="Reports and exports"
      intro="Download a surveillance report as PDF or Word, or the records as CSV files. Every file is fingerprinted and logged with who made it, when and what it covered, and contains only records you can see.">
      <Reports />
    </AppShell>
  );
}

const today = () => ukDate(new Date().toISOString());
const monthsAgo = (n: number) => { const d = new Date(); d.setMonth(d.getMonth() - n); return ukDate(d.toISOString()); };
const kindLabels: Record<ExportKind, string> = {
  report_pdf: "Report (PDF)", report_docx: "Report (Word)", incursion_pdf: "Incursion report (PDF)", incursion_docx: "Incursion report (Word)", csv: "CSV",
};

function Reports() {
  const qc = useQueryClient();
  const { session } = useSession();
  const { current } = useWorkspace();
  const { ws, canManage } = useVv();
  const data = useQuery({ queryKey: wsKey(ws, "vv", "analytics"), queryFn: () => loadAnalytics(ws), staleTime: 60_000 });
  const inc = useQuery({ queryKey: wsKey(ws, "vv", "incursions"), queryFn: () => loadIncursions(ws) });
  const log = useQuery({ queryKey: wsKey(ws, "vv", "exports"), queryFn: () => loadExportLog(ws) });
  const sites = useSites(ws), traps = useTraps(ws), lists = useLists(ws), programmes = useProgrammes(ws), assessments = useAssessments(ws);
  const [from, setFrom] = useState(monthsAgo(12));
  const [to, setTo] = useState(today());
  const [programme, setProgramme] = useState("");
  const [site, setSite] = useState("");
  const [done, setDone] = useState<string | null>(null);

  const filter: Filter = useMemo(() => {
    const chosen = site ? new Set([site]) : programme && sites.data ? new Set(sites.data.filter((s) => s.programmes.includes(programme)).map((s) => s.id)) : null;
    return { from: from <= to ? from : to, to, sites: chosen };
  }, [from, to, programme, site, sites.data]);

  const make = useMutation({
    mutationFn: async (what: { kind: "pdf" | "docx" } | { kind: "csv"; set: CsvSet }) => {
      const ctx: ReportContext = {
        council: current?.name ?? "Council", me: { id: session?.user.id, email: session?.user.email }, reportId: newId(), generatedAt: new Date(),
        data: data.data!, sites: sites.data!, traps: traps.data!, programmes: programmes.data!, lists: lists.data!, assessments: assessments.data!,
        incursions: inc.data ?? null, filter, programmeId: programme, siteId: site,
      };
      const base = `vectovia-${safeName(ctx.council)}-${filter.from}-to-${filter.to}`;
      if (what.kind === "csv") {
        const { head, rows } = csvRows(ctx, what.set);
        const name = `${base}-${what.set}.csv`;
        const sha = await logAndDownload({ id: ctx.reportId, ws, kind: "csv", scope: { ...scopeOf(ctx), dataset: what.set }, counts: { rows: rows.length },
          fileName: name, blob: csvBlob(toCsv(head, rows)), format: FORMAT.csv });
        return `${name} (${rows.length} rows) · fingerprint ${sha.slice(0, 12)}…`;
      }
      const { doc, counts } = surveillanceReport(ctx);
      const { toPdf, toDocx } = await import("@/modules/vectovia/export-writers");
      const blob = what.kind === "pdf" ? await toPdf(doc) : await toDocx(doc);
      const name = `${base}-report.${what.kind}`;
      const sha = await logAndDownload({ id: ctx.reportId, ws, kind: what.kind === "pdf" ? "report_pdf" : "report_docx", scope: scopeOf(ctx), counts,
        fileName: name, blob, format: FORMAT.report });
      return `${name} · fingerprint ${sha.slice(0, 12)}…`;
    },
    onSuccess: (msg) => { setDone(msg); qc.invalidateQueries({ queryKey: wsKey(ws, "vv", "exports") }); },
  });

  const all = [data, inc, log, sites, traps, lists, programmes, assessments];
  if (all.some((q) => q.isPending)) return <Loading what="Loading records" />;
  const err = all.find((q) => q.isError)?.error;
  if (err) return <ErrorState error={err} />;
  if (log.data === null) return <StateMessage title="Reports aren't switched on yet">Once the reports update is applied, you can download reports and CSV files here.</StateMessage>;
  const siteList = sites.data!;
  const btn = "rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy disabled:opacity-60";
  const btn2 = "rounded-md border border-primary px-3 py-1.5 text-sm text-primary disabled:opacity-60";

  return (
    <div className="space-y-10">
      <form className="grid gap-3 rounded-md bg-secondary p-4 sm:grid-cols-2 lg:grid-cols-4" aria-label="What to include" onSubmit={(e) => e.preventDefault()}>
        <Field id="rp-f" label="From"><Input id="rp-f" type="date" className="bg-background" value={from} max={to} onChange={(e) => setFrom(e.target.value)} /></Field>
        <Field id="rp-t" label="To"><Input id="rp-t" type="date" className="bg-background" value={to} min={from} max={today()} onChange={(e) => setTo(e.target.value)} /></Field>
        <Field id="rp-p" label="Programme">
          <select id="rp-p" className={selectClass} value={programme} onChange={(e) => { setProgramme(e.target.value); setSite(""); }}>
            <option value="">All you can see</option>
            {programmes.data!.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </Field>
        <Field id="rp-s" label="Site">
          <select id="rp-s" className={selectClass} value={site} onChange={(e) => setSite(e.target.value)}>
            <option value="">All{programme ? " in this programme" : " you can see"}</option>
            {(programme ? siteList.filter((s) => s.programmes.includes(programme)) : siteList).map((s) => <option key={s.id} value={s.id}>{s.reference} · {s.name}</option>)}
          </select>
        </Field>
      </form>

      <section aria-labelledby="rr-h" className="space-y-3">
        <h2 id="rr-h" className="text-lg font-semibold text-primary">Surveillance report</h2>
        <p className="max-w-3xl text-sm text-muted-foreground">
          Summary figures; sites and deployments; visits and collection effort; results and findings; risk assessments and follow-up actions; incursions; and a location table
          with coordinates and grid references. Maps aren't included in files. The Word version can be edited; the PDF can't.
        </p>
        <div className="flex flex-wrap gap-2">
          <button type="button" className={btn} disabled={make.isPending} onClick={() => make.mutate({ kind: "pdf" })}>Download PDF report</button>
          <button type="button" className={btn2} disabled={make.isPending} onClick={() => make.mutate({ kind: "docx" })}>Download Word report</button>
        </div>
      </section>

      <section aria-labelledby="rc-h" className="space-y-3">
        <h2 id="rc-h" className="text-lg font-semibold text-primary">CSV exports</h2>
        <p className="max-w-3xl text-sm text-muted-foreground">One file per kind of record, with record IDs so data can be matched up later. Times are in UTC. Opens in Excel.</p>
        <div className="flex flex-wrap gap-2">
          {csvSets.map((s) => <button key={s.key} type="button" className={btn2} disabled={make.isPending} onClick={() => make.mutate({ kind: "csv", set: s.key })}>{s.label}</button>)}
        </div>
      </section>

      <div aria-live="polite">
        {make.isPending ? <p role="status" className="text-sm text-muted-foreground">Preparing the file…</p> : null}
        {done && !make.isPending && !make.isError ? <p role="status" className="text-sm text-primary">Downloaded and logged: {done}</p> : null}
        {make.isError ? <ErrorState error={make.error} /> : null}
      </div>

      <section aria-labelledby="rl-h" className="space-y-3">
        <h2 id="rl-h" className="text-lg font-semibold text-primary">Export log</h2>
        <p className="text-sm text-muted-foreground">{canManage ? "Every report and CSV made in your council." : "The reports and CSV files you've made. Managers see the whole council's log."}</p>
        {log.data!.length === 0 ? <p className="text-sm text-muted-foreground">Nothing exported yet.</p> : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[40rem] text-sm">
              <thead><tr className="border-b border-border text-left text-muted-foreground">
                <th className="py-1 pr-3 font-medium">When</th><th className="py-1 pr-3 font-medium">What</th><th className="py-1 pr-3 font-medium">File</th>
                <th className="py-1 pr-3 font-medium">Who</th><th className="py-1 font-medium">Fingerprint (SHA-256)</th>
              </tr></thead>
              <tbody>
                {log.data!.map((r) => (
                  <tr key={r.id} className="border-b border-border/60 align-top">
                    <td className="whitespace-nowrap py-1 pr-3 text-primary">{when(r.created_at)}</td>
                    <td className="py-1 pr-3 text-primary">{kindLabels[r.kind]}{r.scope["dataset"] ? `: ${String(r.scope["dataset"])}` : ""}</td>
                    <td className="py-1 pr-3 text-primary">{r.file_name} <span className="text-xs text-muted-foreground">({Math.max(1, Math.round(r.size_bytes / 1024))} KB)</span></td>
                    <td className="py-1 pr-3 text-primary">{who(r.created_by, session?.user.id)} <span className="text-xs text-muted-foreground">({r.created_role})</span></td>
                    <td className="py-1 font-mono text-xs text-muted-foreground" title={r.sha256}>{r.sha256.slice(0, 16)}…</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
