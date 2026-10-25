// Other systems' references for a site or incursion (from plan V6). Vectovia has no case links:
// it holds no case data. No connector to other systems is built: an external reference is a
// recorded ID mapping only.
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRef, useState, type ReactNode } from "react";
import { ErrorState } from "@/components/app-shell";
import { Input } from "@/components/ui/input";
import { db, must } from "@/lib/backend";
import { wsKey } from "@/lib/workspace";
import { newId, run, when, who } from "./api";
import { Field } from "./ui";

export type ExternalRef = { id: string; record_type: string; record_id: string; system: string; external_id: string; note: string | null; created_by: string; created_at: string };

async function loadLinks(ws: string): Promise<{ refs: ExternalRef[] }> {
  return { refs: must(await db.from("vv_external_refs").select("id, record_type, record_id, system, external_id, note, created_by, created_at")
    .eq("workspace_id", ws).is("removed_at", null).order("created_at")) as ExternalRef[] };
}
export const useLinks = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "links"), queryFn: () => loadLinks(ws) });

/** Other systems' references for one site or incursion. */
export function LinksPanel({ ws, recordType, recordId, canManage, uid }: {
  ws: string; recordType: "site" | "incursion"; recordId: string; canManage: boolean; uid: string | undefined;
}) {
  const q = useLinks(ws);
  const [mode, setMode] = useState<"idle" | "ref">("idle");
  if (q.isError) return <ErrorState error={q.error} />;
  if (!q.data) return null;
  const refs = q.data.refs.filter((r) => r.record_type === recordType && r.record_id === recordId);
  if (!canManage && !refs.length) return null;
  return (
    <div className="space-y-2 rounded-md border border-border p-3 text-sm">
      <p className="text-xs font-semibold uppercase tracking-wide text-accent">Other systems' references</p>
      {refs.length ? (
        <ul className="space-y-1">
          {refs.map((r) => <LinkRow key={r.id} ws={ws} label={<><span className="font-medium">{r.system}</span> reference {r.external_id}</>}
            sub={`${r.note ? `${r.note} · ` : ""}recorded by ${who(r.created_by, uid)} ${when(r.created_at)}`} canManage={canManage} remove={(reason) => db.rpc("vv_remove_external_ref", { _id: r.id, _reason: reason })} />)}
        </ul>
      ) : <p className="text-muted-foreground">None recorded.</p>}
      {canManage && mode === "idle" ? (
        <div className="flex flex-wrap gap-2">
          <button type="button" className="rounded-md border border-primary px-3 py-1.5 text-primary" onClick={() => setMode("ref")}>Add another system's reference</button>
        </div>
      ) : null}
      {mode === "ref" ? <ExternalRefForm ws={ws} recordType={recordType} recordId={recordId} onDone={() => setMode("idle")} /> : null}
    </div>
  );
}

function LinkRow({ ws, label, sub, canManage, remove }: {
  ws: string; label: ReactNode; sub: string; canManage: boolean; remove: (reason: string) => PromiseLike<{ data: unknown; error: import("@supabase/supabase-js").PostgrestError | null }>;
}) {
  const qc = useQueryClient();
  const [removing, setRemoving] = useState(false);
  const [reason, setReason] = useState("");
  const act = useMutation({ mutationFn: () => run(remove(reason)), onSuccess: () => qc.invalidateQueries({ queryKey: ["ws", ws, "vv"] }) });
  return (
    <li>
      <span className="text-primary">{label}</span> <span className="text-xs text-muted-foreground">· {sub}</span>
      {canManage && !removing ? <button type="button" className="ml-2 text-xs text-primary underline" onClick={() => setRemoving(true)}>Remove</button> : null}
      {removing ? (
        <span className="mt-1 flex flex-wrap items-center gap-2">
          <Input aria-label="Why remove it?" className="h-8 w-64" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Why remove it?" />
          <button type="button" disabled={reason.trim().length < 5 || act.isPending} className="text-xs text-primary underline disabled:opacity-60" onClick={() => act.mutate()}>Remove</button>
          <button type="button" className="text-xs text-primary underline" onClick={() => setRemoving(false)}>Keep</button>
        </span>
      ) : null}
      {act.isError ? <ErrorState error={act.error} /> : null}
    </li>
  );
}

function LinkError({ error }: { error: unknown }) {
  const msg = error instanceof Error ? error.message : "";
  if (/already linked|duplicate/i.test(msg)) return <p role="alert" className="text-primary">That's already linked.</p>;
  return <ErrorState error={error} />;
}

function ExternalRefForm({ ws, recordType, recordId, onDone }: { ws: string; recordType: "site" | "incursion"; recordId: string; onDone: () => void }) {
  const qc = useQueryClient();
  const id = useRef(newId());
  const [system, setSystem] = useState("");
  const [externalId, setExternalId] = useState("");
  const [note, setNote] = useState("");
  const save = useMutation({
    mutationFn: async () => must(await db.rpc("vv_save_external_ref", { _id: id.current, _record_type: recordType, _record_id: recordId, _system: system, _external_id: externalId, _note: note })),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["ws", ws, "vv"] }); onDone(); },
  });
  return (
    <form className="space-y-2 rounded-md bg-secondary p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-2 sm:grid-cols-3">
        <Field id="er-s" label="System"><Input id="er-s" className="bg-background" maxLength={60} value={system} onChange={(e) => setSystem(e.target.value)} placeholder="Idox" /></Field>
        <Field id="er-i" label="Their reference"><Input id="er-i" className="bg-background" maxLength={120} value={externalId} onChange={(e) => setExternalId(e.target.value)} /></Field>
        <Field id="er-n" label="Note (optional)"><Input id="er-n" className="bg-background" maxLength={500} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
      </div>
      <p className="text-xs text-muted-foreground">This only records the reference. Vectovia doesn't connect to or send anything to that system.</p>
      {save.isError ? <LinkError error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" disabled={save.isPending || system.trim().length < 2 || !externalId.trim()} className="rounded-md bg-signal-teal px-3 py-1.5 font-semibold text-deep-navy disabled:opacity-60">Save reference</button>
        <button type="button" onClick={onDone} className="rounded-md border border-primary px-3 py-1.5 text-primary">Cancel</button>
      </div>
    </form>
  );
}
