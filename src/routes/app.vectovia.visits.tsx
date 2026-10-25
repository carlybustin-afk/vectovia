import { createFileRoute, Link } from "@tanstack/react-router";
import { useState } from "react";
import { AppShell, EmptyState, ErrorState, Loading, appHead } from "@/components/app-shell";
import { useSession } from "@/lib/session";
import { day, outcomeLabels, when, who, type Outcome } from "@/modules/vectovia/api";
import { VisitForm, VisitRecord } from "@/modules/vectovia/fieldwork";
import { StatusTag, useDeployments, useMembersList, useSamples, useSchedule, useSites, useTraps, useVisits, useVv } from "@/modules/vectovia/ui";

export const Route = createFileRoute("/app/vectovia/visits")({
  head: () => appHead("Field work · Vectovia", "Visits due and overdue, recording visits and samples."),
  component: VisitsPage,
});

function VisitsPage() {
  return (
    <AppShell product="vectovia" section="vectovia" title="Field work"
      intro="Every deployed trap and when its next visit is due. A trap with no visit recorded by its due date shows as overdue: it is never assumed to have been checked.">
      <FieldWork />
    </AppShell>
  );
}

const stateText = { overdue: "Overdue", due: "Due now", scheduled: "Scheduled", off_season: "Out of season" } as const;

function FieldWork() {
  const { session } = useSession();
  const uid = session?.user.id;
  const { ws, canRecord } = useVv();
  const schedule = useSchedule(ws);
  const deployments = useDeployments(ws);
  const visits = useVisits(ws);
  const samples = useSamples(ws);
  const sites = useSites(ws);
  const traps = useTraps(ws);
  const members = useMembersList(ws);
  const [recording, setRecording] = useState<string | null>(null);
  const [outcome, setOutcome] = useState<"" | Outcome>("");
  const all = [schedule, deployments, visits, samples, sites, traps, members];
  if (all.some((q) => q.isPending)) return <Loading what="Loading field work" />;
  const err = all.find((q) => q.isError)?.error;
  if (err) return <ErrorState error={err} />;
  const site = (id: string) => sites.data!.find((s) => s.id === id);
  const trap = (id: string) => traps.data!.find((t) => t.id === id);
  const dep = (id: string) => deployments.data!.find((d) => d.id === id);
  const counts = { overdue: schedule.data!.filter((r) => r.state === "overdue").length, due: schedule.data!.filter((r) => r.state === "due").length };
  const recent = visits.data!.filter((v) => !outcome || v.outcome === outcome).slice(0, 50);
  return (
    <div className="space-y-8">
      <section aria-labelledby="due-h" className="space-y-3">
        <h2 id="due-h" className="text-lg font-semibold text-primary">
          Deployed traps <span className="font-normal text-muted-foreground">({schedule.data!.length}{counts.overdue ? `, ${counts.overdue} overdue` : ""}{counts.due ? `, ${counts.due} due` : ""})</span>
        </h2>
        {schedule.data!.length === 0 ? (
          <EmptyState title="No traps deployed">Deploy a trap from the <Link to="/app/vectovia/traps" className="underline">Traps</Link> page.</EmptyState>
        ) : (
          <ul className="divide-y divide-border rounded-md border border-border">
            {schedule.data!.map((r) => {
              const s = site(r.site_id), t = trap(r.trap_id), d = dep(r.deployment_id);
              return (
                <li key={r.deployment_id} className="px-3 py-2.5">
                  <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
                    <StatusTag strong={r.state === "overdue" || r.state === "due"}>{r.state === "overdue" ? "▲ " : ""}{stateText[r.state]}</StatusTag>
                    <span className="font-semibold text-primary">{t?.identifier ?? "Trap"}</span>
                    <span className="text-primary">{s ? `${s.reference} · ${s.name}` : "Site"}</span>
                    <span className="text-xs text-muted-foreground">
                      {r.next_due_on ? `next due ${day(r.next_due_on)} · every ${r.visit_interval_days} days` : "no checks due until the next season starts"} · {r.last_visit_at ? `last visit ${when(r.last_visit_at)}` : "not visited yet"} · {who(r.responsible_officer, uid)}
                    </span>
                    {canRecord && recording !== r.deployment_id ? (
                      <button type="button" onClick={() => setRecording(r.deployment_id)} className="ml-auto rounded-md bg-signal-teal px-3 py-1.5 text-sm font-semibold text-deep-navy">Record visit</button>
                    ) : null}
                  </div>
                  {recording === r.deployment_id && d ? (
                    <div className="mt-3">
                      <VisitForm ws={ws} deployment={d} lastVisitAt={r.last_visit_at} members={members.data!} uid={uid}
                        trapLabel={t?.identifier ?? "Trap"} siteLabel={s ? `${s.reference} · ${s.name}` : ""} onDone={() => setRecording(null)} />
                    </div>
                  ) : null}
                </li>
              );
            })}
          </ul>
        )}
      </section>

      <section aria-labelledby="rv-h" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 id="rv-h" className="text-lg font-semibold text-primary">Recent visits</h2>
          <div role="group" aria-label="Filter by outcome" className="flex flex-wrap gap-1">
            {(["", "collected", "no_catch", "not_completed"] as const).map((o) => (
              <button key={o || "all"} type="button" aria-pressed={outcome === o} onClick={() => setOutcome(o)}
                className={`h-8 rounded-md px-3 text-xs font-medium ${outcome === o ? "bg-primary text-primary-foreground" : "border border-border text-primary"}`}>{o ? outcomeLabels[o] : "All"}</button>
            ))}
          </div>
        </div>
        {recent.length === 0 ? <EmptyState title="No visits yet">Visits appear here once they're recorded.</EmptyState> : (
          <ul className="divide-y divide-border rounded-md border border-border">
            {recent.map((v) => {
              const d = dep(v.deployment_id), s = site(v.site_id), t = d ? trap(d.trap_id) : undefined;
              return <VisitRecord key={v.id} ws={ws} visit={v} samples={samples.data!} members={members.data!} uid={uid} canRecord={canRecord}
                label={`${t?.identifier ?? "Trap"} at ${s ? s.reference : "site"}`} />;
            })}
          </ul>
        )}
      </section>
    </div>
  );
}
