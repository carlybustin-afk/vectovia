import { createFileRoute, Link } from "@tanstack/react-router";
import { useState } from "react";
import { AppShell, EmptyState, ErrorState, Loading, appHead } from "@/components/app-shell";
import { useSession } from "@/lib/session";
import { day, levelLabels, resultStatusLabels, riskFactors, when, who, type Site } from "@/modules/vectovia/api";
import { ActionForm, ActionRow, AssessmentForm, LevelTag, RiskMatrix, resultLine } from "@/modules/vectovia/risk";
import {
  History, StatusTag, useActions, useAssessments, useFindings, useLists, useMembersList, useResults, useSamples, useSites, useVv,
} from "@/modules/vectovia/ui";

export const Route = createFileRoute("/app/vectovia/risk")({
  head: () => appHead("Risk & actions · Vectovia", "Findings awaiting review, structured risk assessments and follow-up actions."),
  component: RiskPage,
});

function RiskPage() {
  return (
    <AppShell product="vectovia" section="vectovia" title="Risk & actions"
      intro="Review findings, record a structured risk assessment, and assign follow-up actions. The assessment is your professional judgement: First Line never calculates or suggests the risk.">
      <Risk />
    </AppShell>
  );
}

function Risk() {
  const { session } = useSession();
  const uid = session?.user.id;
  const { ws, canManage, canRecord } = useVv();
  const findings = useFindings(ws), assessments = useAssessments(ws), actions = useActions(ws), results = useResults(ws),
    samples = useSamples(ws), sites = useSites(ws), lists = useLists(ws), members = useMembersList(ws);
  const [chosen, setChosen] = useState<string[]>([]);
  const [assessing, setAssessing] = useState<string | null>(null);   // site id
  const all = [findings, assessments, actions, results, samples, sites, lists, members];
  if (all.some((q) => q.isPending)) return <Loading what="Loading findings" />;
  const err = all.find((q) => q.isError)?.error;
  if (err) return <ErrorState error={err} />;
  const site = (id: string) => sites.data!.find((s) => s.id === id);
  const siteLabel = (id: string) => { const s = site(id); return s ? `${s.reference} · ${s.name}` : "Site"; };
  const sample = (id: string) => samples.data!.find((s) => s.id === id);
  const curVersion = (resultId: string) => {
    const r = results.data!.results.find((x) => x.id === resultId);
    return r ? results.data!.versions.find((v) => v.result_id === r.id && v.version === r.current_version) : undefined;
  };
  const bySite = new Map<string, typeof findings.data>();
  for (const f of findings.data!) bySite.set(f.site_id, [...(bySite.get(f.site_id) ?? []), f]);
  const openActions = actions.data!.filter((a) => a.status === "open");
  const myActions = openActions.filter((a) => a.owner_id === uid);

  return (
    <div className="space-y-10">
      <section aria-labelledby="fr-h" className="space-y-3">
        <h2 id="fr-h" className="text-lg font-semibold text-primary">Findings awaiting review ({findings.data!.length})</h2>
        <p className="text-sm text-muted-foreground">Provisional and confirmed results not yet covered by a risk assessment.{canManage ? " Tick the findings at one site, then assess." : " A Vectovia manager assesses them."}</p>
        {findings.data!.length === 0 ? <EmptyState title="Nothing awaiting review">Findings appear here once results are recorded on the <Link to="/app/vectovia/results" className="underline">Results</Link> page.</EmptyState> : (
          [...bySite.entries()].map(([siteId, fs]) => (
            <div key={siteId} className="rounded-md border border-border">
              <div className="flex flex-wrap items-center justify-between gap-2 border-b border-border bg-secondary px-3 py-2">
                <span className="font-semibold text-primary">{siteLabel(siteId)}</span>
                {canManage && assessing !== siteId ? (
                  <button type="button" disabled={!chosen.some((c) => fs!.some((f) => f.result_id === c))}
                    onClick={() => setAssessing(siteId)} className="rounded-md bg-signal-teal px-3 py-1.5 text-sm font-semibold text-deep-navy disabled:opacity-60">Assess risk</button>
                ) : null}
              </div>
              <ul className="divide-y divide-border">
                {fs!.map((f) => {
                  const v = curVersion(f.result_id);
                  return (
                    <li key={f.result_id} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-3 py-2 text-sm">
                      {canManage ? <input type="checkbox" aria-label="Include this finding" checked={chosen.includes(f.result_id)}
                        onChange={(e) => { const on = e.target.checked; setChosen((c) => (on ? [...c, f.result_id] : c.filter((x) => x !== f.result_id))); }} /> : null}
                      <StatusTag strong>{resultStatusLabels[f.status]}</StatusTag>
                      <span className="font-medium text-primary">{v ? resultLine(v, lists.data!) : "Result"}</span>
                      <span className="text-xs text-muted-foreground">sample {sample(f.sample_id)?.reference ?? ""}{f.result_date ? ` · ${day(f.result_date)}` : ""}</span>
                      {(() => { const t = lists.data!.taxa.find((x) => x.id === f.taxon_id); return t?.invasive ? <StatusTag strong>Invasive species</StatusTag> : null; })()}
                    </li>
                  );
                })}
              </ul>
              {assessing === siteId ? (
                <div className="border-t border-border p-3">
                  <AssessmentForm ws={ws} siteId={siteId} findingIds={chosen.filter((c) => fs!.some((f) => f.result_id === c))}
                    onDone={() => { setAssessing(null); setChosen([]); }} />
                </div>
              ) : null}
            </div>
          ))
        )}
      </section>

      <section aria-labelledby="ac-h" className="space-y-3">
        <h2 id="ac-h" className="text-lg font-semibold text-primary">Open actions ({openActions.length}{myActions.length ? `, ${myActions.length} yours` : ""})</h2>
        {openActions.length === 0 ? <p className="text-sm text-muted-foreground">No open actions.</p> : (
          <ul className="divide-y divide-border rounded-md border border-border">
            {openActions.map((a) => <ActionRow key={a.id} ws={ws} a={a} uid={uid} canManage={canManage} siteLabel={siteLabel(a.site_id)} />)}
          </ul>
        )}
      </section>

      <section aria-labelledby="as-h" className="space-y-3">
        <h2 id="as-h" className="text-lg font-semibold text-primary">Risk assessments ({assessments.data!.assessments.length})</h2>
        {assessments.data!.assessments.length === 0 ? <p className="text-sm text-muted-foreground">None yet.</p> : (
          <ul className="space-y-3">
            {assessments.data!.assessments.map((a) => (
              <AssessmentCard key={a.id} ws={ws} a={a} versions={assessments.data!.versions.filter((v) => v.assessment_id === a.id)}
                site={site(a.site_id)} uid={uid} canManage={canManage} canRecord={canRecord}
                findings={a.results.map((r) => { const v = curVersion(r); return v ? resultLine(v, lists.data!) : "Result"; })}
                actions={actions.data!.filter((x) => x.assessment_id === a.id)} members={members.data!} siteLabel={siteLabel(a.site_id)} />
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

function AssessmentCard({ ws, a, versions, site, uid, canManage, findings, actions, members, siteLabel }: {
  ws: string; a: { id: string; site_id: string; current_version: number; results: string[] }; versions: import("@/modules/vectovia/api").AssessmentVersion[];
  site: Site | undefined; uid: string | undefined; canManage: boolean; canRecord: boolean; findings: string[];
  actions: import("@/modules/vectovia/api").Action[]; members: import("@/modules/vectovia/api").MemberRow[]; siteLabel: string;
}) {
  const cur = versions.find((v) => v.version === a.current_version)!;
  const [mode, setMode] = useState<"idle" | "revise" | "action">("idle");
  const factorLabel = (k: string) => riskFactors.find(([x]) => x === k)?.[1] ?? k;
  return (
    <li className="space-y-3 rounded-md border border-border p-3 text-sm">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
        <LevelTag level={cur.final_level} />
        <span className="font-semibold text-primary">{site ? `${site.reference} · ${site.name}` : "Site"}</span>
        <span className="text-xs text-muted-foreground">by {who(cur.author_id, uid)} ({cur.author_role}) · {when(cur.recorded_at)}{a.current_version > 1 ? ` · version ${a.current_version}` : ""}</span>
      </div>
      <p className="text-xs text-muted-foreground">Findings: {findings.join("; ")}</p>
      <div className="grid gap-3 lg:grid-cols-[auto_1fr]">
        <RiskMatrix likelihood={cur.likelihood} consequence={cur.consequence} />
        <dl className="space-y-1">
          <div><dt className="inline text-muted-foreground">Likelihood × consequence: </dt><dd className="inline text-primary">{cur.likelihood} × {cur.consequence} → matrix {levelLabels[cur.matrix_level]}</dd></div>
          <div><dt className="inline text-muted-foreground">Final level: </dt><dd className="inline text-primary">{levelLabels[cur.final_level]}{cur.override_reason ? ` (changed from the matrix: ${cur.override_reason})` : ""}</dd></div>
          {cur.factors.length ? <div><dt className="inline text-muted-foreground">Factors considered: </dt><dd className="inline text-primary">{cur.factors.map(factorLabel).join("; ")}</dd></div> : null}
          <div><dt className="text-muted-foreground">Rationale</dt><dd className="whitespace-pre-wrap text-primary">{cur.rationale}</dd></div>
          {cur.reason ? <div><dt className="inline text-muted-foreground">Why revised: </dt><dd className="inline text-primary">{cur.reason}</dd></div> : null}
        </dl>
      </div>
      {actions.length ? (
        <div>
          <p className="text-xs font-semibold uppercase tracking-wide text-accent">Actions</p>
          <ul className="divide-y divide-border rounded-md border border-border">{actions.map((x) => <ActionRow key={x.id} ws={ws} a={x} uid={uid} canManage={canManage} siteLabel={siteLabel} />)}</ul>
        </div>
      ) : null}
      {mode === "revise" ? <AssessmentForm ws={ws} siteId={a.site_id} findingIds={[]} current={cur} assessmentId={a.id} onDone={() => setMode("idle")} />
        : mode === "action" ? <ActionForm ws={ws} siteId={a.site_id} assessmentId={a.id} members={members} uid={uid} onDone={() => setMode("idle")} />
        : canManage ? (
          <div className="flex gap-2">
            <button type="button" onClick={() => setMode("action")} className="rounded-md bg-signal-teal px-3 py-1.5 text-sm font-semibold text-deep-navy">Add a follow-up action</button>
            <button type="button" onClick={() => setMode("revise")} className="rounded-md border border-primary px-3 py-1.5 text-sm text-primary">Revise assessment</button>
            <Link to="/app/vectovia/incursions" search={{ site: a.site_id, findings: a.results.join(",") }} className="rounded-md border border-primary px-3 py-1.5 text-sm text-primary">Open an incursion</Link>
          </div>
        ) : null}
      {versions.length > 1 ? (
        <details className="text-xs">
          <summary className="cursor-pointer text-primary underline">Earlier versions ({versions.length - 1})</summary>
          <ol className="mt-1 space-y-0.5 border-l-2 border-accent pl-3 text-muted-foreground">
            {versions.filter((v) => v.version !== a.current_version).reverse().map((v) => (
              <li key={v.version}>v{v.version}: {levelLabels[v.final_level]} ({v.likelihood} × {v.consequence}) · {who(v.author_id, uid)} · {when(v.recorded_at)}</li>
            ))}
          </ol>
        </details>
      ) : null}
      <History type="assessment" id={a.id} ws={ws} uid={uid} />
    </li>
  );
}
