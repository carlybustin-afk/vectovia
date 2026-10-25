import { createFileRoute, Link } from "@tanstack/react-router";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useRef, useState } from "react";
import { AppShell, EmptyState, ErrorState, Loading, appHead } from "@/components/app-shell";
import { Input } from "@/components/ui/input";
import { useSession } from "@/lib/session";
import { newId, run, trapStatusLabels, vvRpc, when, type Lists, type Trap } from "@/modules/vectovia/api";
import { Field, History, StatusTag, selectClass, useDeployments, useLists, useMembersList, useSites, useTraps, useVv } from "@/modules/vectovia/ui";
import { DeployForm, EndDeploymentForm, deploymentLine } from "@/modules/vectovia/fieldwork";
import type { Deployment, MemberRow, Site } from "@/modules/vectovia/api";

export const Route = createFileRoute("/app/vectovia/traps")({
  head: () => appHead("Traps · Vectovia", "The council's physical traps: identifier, type and status."),
  component: TrapsPage,
});

function TrapsPage() {
  return (
    <AppShell product="vectovia" section="vectovia" title="Traps"
      intro="Each physical trap, kept separate from where it's deployed. A trap's deployments and history stay with it when it moves (deployments arrive in the next stage).">
      <Traps />
    </AppShell>
  );
}

const typeName = (t: Trap, lists: Lists) =>
  lists.trapTypes.find((x) => x.id === t.trap_type_id)?.name ?? lists.councilTrapTypes.find((x) => x.id === t.council_trap_type_id)?.name ?? "—";

function Traps() {
  const { ws, canRecord } = useVv();
  const traps = useTraps(ws);
  const lists = useLists(ws);
  const deployments = useDeployments(ws);
  const sites = useSites(ws);
  const members = useMembersList(ws);
  const [status, setStatus] = useState<"" | Trap["status"]>("");
  const [open, setOpen] = useState<string | "new" | null>(null);
  const all = [traps, lists, deployments, sites, members];
  if (all.some((q) => q.isPending)) return <Loading what="Loading traps" />;
  const err = all.find((q) => q.isError)?.error;
  if (err) return <ErrorState error={err} />;
  if (!traps.data || !lists.data || !deployments.data || !sites.data || !members.data) return null;
  const shown = traps.data.filter((t) => !status || t.status === status);
  const count = (s: Trap["status"]) => traps.data.filter((t) => t.status === s).length;
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div role="group" aria-label="Filter by status" className="flex flex-wrap gap-1">
          {(["", "available", "deployed", "damaged", "retired"] as const).map((s) => (
            <button key={s || "all"} type="button" aria-pressed={status === s} onClick={() => setStatus(s)}
              className={`h-9 rounded-md px-3 text-sm font-medium ${status === s ? "bg-primary text-primary-foreground" : "border border-border text-primary"}`}>
              {s ? `${trapStatusLabels[s]} (${count(s)})` : `All (${traps.data.length})`}
            </button>
          ))}
        </div>
        {canRecord ? <button type="button" onClick={() => setOpen("new")} className="rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy">Register a trap</button> : null}
      </div>
      {open === "new" ? <TrapForm ws={ws} lists={lists.data} onDone={() => setOpen(null)} onCancel={() => setOpen(null)} /> : null}
      {shown.length === 0 ? (
        <EmptyState title={traps.data.length ? "No traps with this status" : "No traps yet"}>{canRecord && !traps.data.length ? "Register the first one with “Register a trap”." : "Try another status."}</EmptyState>
      ) : (
        <ul className="divide-y divide-border rounded-md border border-border">
          {shown.map((t) => (
            <li key={t.id}>
              <button type="button" aria-expanded={open === t.id} onClick={() => setOpen(open === t.id ? null : t.id)} className="flex w-full flex-wrap items-baseline gap-3 px-3 py-2.5 text-left hover:bg-secondary/60">
                <span className="font-semibold text-primary">{t.identifier}</span>
                <span className="text-primary">{typeName(t, lists.data)}</span>
                <StatusTag strong={t.status === "deployed"}>{trapStatusLabels[t.status]}</StatusTag>
                {(() => { const d = deployments.data.find((x) => x.trap_id === t.id && !x.ended_at); const s = d && sites.data.find((x) => x.id === d.site_id); return d ? <span className="text-xs text-primary">at {s ? `${s.reference} · ${s.name}` : "a site"}</span> : null; })()}
                {t.notes ? <span className="text-xs text-muted-foreground">{t.notes}</span> : null}
              </button>
              {open === t.id ? <TrapDetail ws={ws} trap={t} lists={lists.data} canRecord={canRecord}
                deployments={deployments.data.filter((d) => d.trap_id === t.id)} sites={sites.data} members={members.data} /> : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function TrapDetail({ ws, trap, lists, canRecord, deployments, sites, members }: {
  ws: string; trap: Trap; lists: Lists; canRecord: boolean; deployments: Deployment[]; sites: Site[]; members: MemberRow[];
}) {
  const { session } = useSession();
  const [mode, setMode] = useState<"idle" | "edit" | "deploy" | "move" | "end">("idle");
  const active = deployments.find((d) => !d.ended_at);
  const done = () => setMode("idle");
  return (
    <div className="space-y-3 border-t border-border bg-background p-3 text-sm">
      {mode === "edit" ? <TrapForm ws={ws} trap={trap} lists={lists} onDone={done} onCancel={done} />
        : mode === "deploy" ? <DeployForm ws={ws} trap={trap} sites={sites} members={members} uid={session?.user.id} onDone={done} />
        : mode === "move" && active ? <DeployForm ws={ws} trap={trap} sites={sites} members={members} uid={session?.user.id} from={active} onDone={done} />
        : mode === "end" && active ? <EndDeploymentForm ws={ws} deployment={active} onDone={done} /> : (
        <>
          <p className="text-muted-foreground">
            Registered {when(trap.created_at)} · last changed {when(trap.updated_at)}
            {trap.trap_type_id ? <> · <Link to="/app/vectovia/library" search={{ kind: "trap", id: trap.trap_type_id }} className="text-primary underline">How this trap works</Link></> : null}
          </p>
          {canRecord ? (
            <div className="flex flex-wrap gap-2">
              {trap.status === "available" ? <button type="button" onClick={() => setMode("deploy")} className="rounded-md bg-signal-teal px-3 py-1.5 text-sm font-semibold text-deep-navy">Deploy at a site</button> : null}
              {active ? <button type="button" onClick={() => setMode("move")} className="rounded-md bg-signal-teal px-3 py-1.5 text-sm font-semibold text-deep-navy">Move to another site</button> : null}
              {active ? <button type="button" onClick={() => setMode("end")} className="rounded-md border border-primary px-3 py-1.5 text-sm font-medium text-primary">End deployment</button> : null}
              <button type="button" onClick={() => setMode("edit")} className="rounded-md border border-primary px-3 py-1.5 text-sm font-medium text-primary">Edit trap</button>
            </div>
          ) : null}
        </>
      )}
      <div>
        <p className="text-xs font-semibold uppercase tracking-wide text-accent">Deployments ({deployments.length})</p>
        {deployments.length === 0 ? <p className="text-xs text-muted-foreground">Not deployed yet.</p> : (
          <ol className="mt-1 space-y-0.5 text-xs">
            {deployments.map((d) => <li key={d.id} className={d.ended_at ? "text-muted-foreground" : "font-medium text-primary"}>{deploymentLine(d, sites.find((s) => s.id === d.site_id))}</li>)}
          </ol>
        )}
      </div>
      <History type="trap" id={trap.id} ws={ws} uid={session?.user.id} labels={{ trap_type_id: "type", council_trap_type_id: "council type" }} />
    </div>
  );
}

function TrapForm({ ws, trap, lists, onDone, onCancel }: { ws: string; trap?: Trap; lists: Lists; onDone: () => void; onCancel: () => void }) {
  const qc = useQueryClient();
  const id = useRef(trap?.id ?? newId());
  const [identifier, setIdentifier] = useState(trap?.identifier ?? "");
  const [type, setType] = useState(trap?.trap_type_id ? `s:${trap.trap_type_id}` : trap?.council_trap_type_id ? `c:${trap.council_trap_type_id}` : "");
  const [status, setStatus] = useState<Trap["status"]>(trap?.status ?? "available");
  const [notes, setNotes] = useState(trap?.notes ?? "");
  const save = useMutation({
    mutationFn: () => run(vvRpc.saveTrap(id.current, ws, {
      identifier, trap_type_id: type.startsWith("s:") ? type.slice(2) : null, council_trap_type_id: type.startsWith("c:") ? type.slice(2) : null, status, notes,
    })),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["ws", ws, "vv"] }); onDone(); },
  });
  const deployed = trap?.status === "deployed";
  return (
    <form className="space-y-3 rounded-md border-t-2 border-accent bg-secondary p-4" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <p className="font-semibold text-primary">{trap ? `Edit ${trap.identifier}` : "Register a trap"}</p>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id="tf-id" label="Identifier" hint="As written on the trap."><Input id="tf-id" className="bg-background" maxLength={60} value={identifier} onChange={(e) => setIdentifier(e.target.value)} placeholder="e.g. BG-01" /></Field>
        <Field id="tf-type" label="Type">
          <select id="tf-type" className={selectClass} value={type} onChange={(e) => setType(e.target.value)}>
            <option value="">Choose a type</option>
            <optgroup label="Standard types">{lists.trapTypes.map((t) => <option key={t.id} value={`s:${t.id}`}>{t.name}</option>)}</optgroup>
            {lists.councilTrapTypes.filter((t) => t.active || `c:${t.id}` === type).length ? (
              <optgroup label="Your council's types">{lists.councilTrapTypes.filter((t) => t.active || `c:${t.id}` === type).map((t) => <option key={t.id} value={`c:${t.id}`}>{t.name}</option>)}</optgroup>
            ) : null}
          </select>
        </Field>
        <Field id="tf-status" label="Status" hint={deployed ? "End its deployment to change this." : undefined}>
          <select id="tf-status" className={selectClass} value={status} disabled={deployed} onChange={(e) => setStatus(e.target.value as Trap["status"])}>
            {deployed ? <option value="deployed">Deployed</option> : null}
            <option value="available">Available</option><option value="damaged">Damaged</option><option value="retired">Retired</option>
          </select>
        </Field>
      </div>
      <Field id="tf-notes" label="Notes (optional)"><Input id="tf-notes" className="bg-background" maxLength={2000} value={notes} onChange={(e) => setNotes(e.target.value)} /></Field>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" disabled={save.isPending || !identifier.trim() || !type} className="rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy disabled:opacity-60">{trap ? "Save changes" : "Register trap"}</button>
        <button type="button" onClick={onCancel} className="rounded-md border border-primary px-4 py-2 text-sm text-primary">Cancel</button>
      </div>
    </form>
  );
}
