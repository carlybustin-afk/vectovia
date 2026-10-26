import { createFileRoute, Link } from "@tanstack/react-router";
import { useState } from "react";
import { AppShell, EmptyState, ErrorState, Loading, appHead } from "@/components/app-shell";
import { useSession } from "@/lib/session";
import { day, methodLabels, resultStatusLabels, when, who, type Lists, type Result, type ResultVersion, type Sample } from "@/modules/vectovia/api";
import { Attachments } from "@/modules/vectovia/attachments";
import { ResultForm, resultLine } from "@/modules/vectovia/risk";
import { History, StatusTag, useDeployments, useLists, useResults, useSamples, useSites, useTraps, useVisits, useVv } from "@/modules/vectovia/ui";

export const Route = createFileRoute("/app/vectovia/results")({
  head: () => appHead("Results · Vectovia", "Identification and laboratory results for each sample."),
  component: ResultsPage,
});

function ResultsPage() {
  return (
    <AppShell product="vectovia" section="vectovia" title="Results"
      intro="Identification or laboratory results for each sample. Pending, provisional, confirmed and inconclusive are kept distinct, and every correction keeps the earlier version.">
      <Results />
    </AppShell>
  );
}

function Results() {
  const { session } = useSession();
  const uid = session?.user.id;
  const { ws, canRecord } = useVv();
  const samples = useSamples(ws), results = useResults(ws), lists = useLists(ws), visits = useVisits(ws), sites = useSites(ws), deployments = useDeployments(ws), traps = useTraps(ws);
  const [show, setShow] = useState<"awaiting" | "all">("awaiting");
  const [open, setOpen] = useState<string | null>(null);
  const all = [samples, results, lists, visits, sites, deployments, traps];
  if (all.some((q) => q.isPending)) return <Loading what="Loading results" />;
  const err = all.find((q) => q.isError)?.error;
  if (err) return <ErrorState error={err} />;
  const list = samples.data!.filter((s) => show === "all" || s.status === "awaiting_result");
  return (
    <div className="space-y-4">
      <div role="group" aria-label="Which samples" className="flex gap-1">
        {([["awaiting", `Awaiting results (${samples.data!.filter((s) => s.status === "awaiting_result").length})`], ["all", `All samples (${samples.data!.length})`]] as const).map(([k, label]) => (
          <button key={k} type="button" aria-pressed={show === k} onClick={() => setShow(k)}
            className={`h-9 rounded-md px-3 text-sm font-medium ${show === k ? "bg-primary text-primary-foreground" : "border border-border text-primary"}`}>{label}</button>
        ))}
      </div>
      {list.length === 0 ? <EmptyState title={show === "awaiting" ? "Nothing awaiting results" : "No samples yet"}>Samples appear here once a visit with samples is recorded.</EmptyState> : (
        <ul className="divide-y divide-border rounded-md border border-border">
          {list.map((s) => {
            const visit = visits.data!.find((v) => v.id === s.visit_id);
            const site = sites.data!.find((x) => x.id === s.site_id);
            const dep = visit && deployments.data!.find((d) => d.id === visit.deployment_id);
            const trap = dep && traps.data!.find((t) => t.id === dep.trap_id);
            const mine = results.data!.results.filter((r) => r.sample_id === s.id);
            return (
              <li key={s.id}>
                <button type="button" aria-expanded={open === s.id} onClick={() => setOpen(open === s.id ? null : s.id)} className="flex w-full flex-wrap items-baseline gap-x-3 gap-y-1 px-3 py-2.5 text-left hover:bg-secondary/60">
                  <span className="font-semibold text-primary">{s.reference}</span>
                  <StatusTag strong={s.status === "awaiting_result"}>{s.status === "awaiting_result" ? "Awaiting results" : "Resulted"}</StatusTag>
                  <span className="text-xs text-muted-foreground">
                    {methodLabels[s.method]} · {s.inspection_id ? "inspection" : trap?.identifier ?? "trap"} at {site ? `${site.reference} · ${site.name}` : "site"} · collected {visit ? when(visit.occurred_at) : when(s.recorded_at)}
                    {mine.length ? ` · ${mine.length} result${mine.length === 1 ? "" : "s"}` : ""}
                  </span>
                </button>
                {open === s.id ? <SampleResults ws={ws} sample={s} results={mine} versions={results.data!.versions} lists={lists.data!} canRecord={canRecord} uid={uid} /> : null}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

function SampleResults({ ws, sample, results, versions, lists, canRecord, uid }: {
  ws: string; sample: Sample; results: Result[]; versions: ResultVersion[]; lists: Lists; canRecord: boolean; uid: string | undefined;
}) {
  const [adding, setAdding] = useState(false);
  const [correcting, setCorrecting] = useState<string | null>(null);
  return (
    <div className="space-y-3 border-t border-border bg-background p-3 text-sm">
      {results.length === 0 ? <p className="text-muted-foreground">No results yet. Add one per species identified, or a pending result when it goes to the lab.</p> : (
        <ul className="space-y-2">
          {results.map((r) => {
            const vs = versions.filter((v) => v.result_id === r.id);
            const cur = vs.find((v) => v.version === r.current_version)!;
            return (
              <li key={r.id} className="rounded-md border border-border p-2">
                <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                  <StatusTag strong={cur.status === "confirmed" || cur.status === "provisional"}>{resultStatusLabels[cur.status]}</StatusTag>
                  <span className="font-medium text-primary">{resultLine(cur, lists)}</span>
                  {cur.taxon_id ? <Link to="/app/vectovia/library" search={{ kind: "species", id: cur.taxon_id }} className="text-xs text-primary underline">Library page</Link> : null}
                  <span className="text-xs text-muted-foreground">
                    {[cur.identified_by, cur.laboratory, cur.lab_reference && `ref ${cur.lab_reference}`, cur.result_date && day(cur.result_date)].filter(Boolean).join(" · ")}
                    {r.current_version > 1 ? ` · version ${r.current_version}` : ""}
                  </span>
                  {canRecord && correcting !== r.id ? <button type="button" className="ml-auto text-xs text-primary underline" onClick={() => setCorrecting(r.id)}>Correct or update</button> : null}
                </div>
                {cur.uncertainty ? <p className="text-xs text-primary">Uncertainty: {cur.uncertainty}</p> : null}
                {vs.length > 1 ? (
                  <details className="text-xs">
                    <summary className="cursor-pointer text-primary underline">Earlier versions ({vs.length - 1})</summary>
                    <ol className="mt-1 space-y-0.5 border-l-2 border-accent pl-3 text-muted-foreground">
                      {[...vs].reverse().filter((v) => v.version !== r.current_version).map((v) => (
                        <li key={v.version}>v{v.version}: {resultStatusLabels[v.status]} · {resultLine(v, lists)} · {who(v.author_id, uid)} · {when(v.recorded_at)}</li>
                      ))}
                      <li className="text-primary">Latest change: {cur.reason ?? "—"} ({who(cur.author_id, uid)}, {when(cur.recorded_at)})</li>
                    </ol>
                  </details>
                ) : null}
                {correcting === r.id ? <div className="mt-2"><ResultForm ws={ws} sampleId={sample.id} lists={lists} current={cur} resultId={r.id} onDone={() => setCorrecting(null)} /></div> : null}
                <History type="result" id={r.id} ws={ws} uid={uid} />
              </li>
            );
          })}
        </ul>
      )}
      {canRecord ? (adding ? <ResultForm ws={ws} sampleId={sample.id} lists={lists} onDone={() => setAdding(false)} /> : (
        <button type="button" onClick={() => setAdding(true)} className="rounded-md bg-signal-teal px-3 py-1.5 text-sm font-semibold text-deep-navy">Add a result</button>
      )) : null}
      <Attachments ws={ws} recordType="sample" recordId={sample.id} canRecord={canRecord} uid={uid} />
    </div>
  );
}
