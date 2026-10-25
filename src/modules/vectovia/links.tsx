// Case links and other systems' references (plan V6, rev 27). A link to an
// Investigations case stores only the two IDs; it shows only to people who can
// see both records, so it never widens access. Vectovia never reads case
// records: the database returns just the case reference, and only when the
// person can already open that case. No connector to other systems is built:
// external references are a recorded ID mapping.
import { Link } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRef, useState, type ReactNode } from "react";
import { ErrorState } from "@/components/app-shell";
import { Input } from "@/components/ui/input";
import { db, must } from "@/lib/backend";
import { wsKey } from "@/lib/workspace";
import { newId, run, when, who } from "./api";
import { Field } from "./ui";

export type CaseLink = { link_id: string; record_type: "site" | "incursion"; record_id: string; case_id: string; case_reference: string; note: string | null; created_by: string; created_at: string };
export type ExternalRef = { id: string; record_type: string; record_id: string; system: string; external_id: string; note: string | null; created_by: string; created_at: string };

/** Null when the update isn't applied yet. */
async function loadLinks(ws: string): Promise<{ links: CaseLink[]; refs: ExternalRef[] } | null> {
  const [l, r] = await Promise.all([
    db.rpc("vv_case_links_for", { _ws: ws }),
    db.from("vv_external_refs").select("id, record_type, record_id, system, external_id, note, created_by, created_at").eq("workspace_id", ws).is("removed_at", null).order("created_at"),
  ]);
  if (l.error || r.error) return null;
  return { links: l.data as CaseLink[], refs: r.data as ExternalRef[] };
}
export const useLinks = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "links"), queryFn: () => loadLinks(ws) });

/** Linked cases and other systems' references for one site or incursion. */
export function LinksPanel({ ws, recordType, recordId, canManage, uid }: {
  ws: string; recordType: "site" | "incursion"; recordId: string; canManage: boolean; uid: string | undefined;
}) {
  const q = useLinks(ws);
  const [mode, setMode] = useState<"idle" | "case" | "ref">("idle");
  if (!q.data) return null; // loading, or not switched on yet
  const links = q.data.links.filter((l) => l.record_type === recordType && l.record_id === recordId);
  const refs = q.data.refs.filter((r) => r.record_type === recordType && r.record_id === recordId);
  if (!canManage && !links.length && !refs.length) return null;
  return (
    <div className="space-y-2 rounded-md border border-border p-3 text-sm">
      <p className="text-xs font-semibold uppercase tracking-wide text-accent">Links</p>
      {links.length || refs.length ? (
        <ul className="space-y-1">
          {links.map((l) => <LinkRow key={l.link_id} ws={ws} label={<>Case <span className="font-medium">{l.case_reference}</span></>}
            sub={`${l.note ? `${l.note} · ` : ""}linked by ${who(l.created_by, uid)} ${when(l.created_at)}`} canManage={canManage} remove={(reason) => db.rpc("vv_unlink_case", { _id: l.link_id, _reason: reason })} />)}
          {refs.map((r) => <LinkRow key={r.id} ws={ws} label={<><span className="font-medium">{r.system}</span> reference {r.external_id}</>}
            sub={`${r.note ? `${r.note} · ` : ""}recorded by ${who(r.created_by, uid)} ${when(r.created_at)}`} canManage={canManage} remove={(reason) => db.rpc("vv_remove_external_ref", { _id: r.id, _reason: reason })} />)}
        </ul>
      ) : <p className="text-muted-foreground">No linked cases or other references.</p>}
      <p className="text-xs text-muted-foreground">A linked case shows only to people who can open both records. Linking never gives anyone access they didn't already have.</p>
      {canManage && mode === "idle" ? (
        <div className="flex flex-wrap gap-2">
          <button type="button" className="rounded-md border border-primary px-3 py-1.5 text-primary" onClick={() => setMode("case")}>Link to a case</button>
          <button type="button" className="rounded-md border border-primary px-3 py-1.5 text-primary" onClick={() => setMode("ref")}>Add another system's reference</button>
        </div>
      ) : null}
      {mode === "case" ? <LinkCaseForm ws={ws} recordType={recordType} recordId={recordId} onDone={() => setMode("idle")} /> : null}
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

function LinkCaseForm({ ws, recordType, recordId, onDone }: { ws: string; recordType: "site" | "incursion"; recordId: string; onDone: () => void }) {
  const qc = useQueryClient();
  const id = useRef(newId());
  const [reference, setReference] = useState("");
  const [note, setNote] = useState("");
  const save = useMutation({
    mutationFn: async () => must(await db.rpc("vv_link_case", { _id: id.current, _record_type: recordType, _record_id: recordId, _case_reference: reference, _note: note })),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["ws", ws, "vv"] }); onDone(); },
  });
  return (
    <form className="space-y-2 rounded-md bg-secondary p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-2 sm:grid-cols-2">
        <Field id="lc-r" label="Case reference" hint="A case in this council that you can already open."><Input id="lc-r" className="bg-background" maxLength={60} value={reference} onChange={(e) => setReference(e.target.value)} /></Field>
        <Field id="lc-n" label="Why they're linked (optional)"><Input id="lc-n" className="bg-background" maxLength={500} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
      </div>
      {save.isError ? <LinkError error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" disabled={save.isPending || !reference.trim()} className="rounded-md bg-signal-teal px-3 py-1.5 font-semibold text-deep-navy disabled:opacity-60">Link case</button>
        <button type="button" onClick={onDone} className="rounded-md border border-primary px-3 py-1.5 text-primary">Cancel</button>
      </div>
    </form>
  );
}
function LinkError({ error }: { error: unknown }) {
  const msg = error instanceof Error ? error.message : "";
  if (/no case with that reference/i.test(msg)) return <p role="alert" className="text-primary">There's no case with that reference that you can open.</p>;
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
      <p className="text-xs text-muted-foreground">This only records the reference. First Line doesn't connect to or send anything to that system.</p>
      {save.isError ? <LinkError error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" disabled={save.isPending || system.trim().length < 2 || !externalId.trim()} className="rounded-md bg-signal-teal px-3 py-1.5 font-semibold text-deep-navy disabled:opacity-60">Save reference</button>
        <button type="button" onClick={onDone} className="rounded-md border border-primary px-3 py-1.5 text-primary">Cancel</button>
      </div>
    </form>
  );
}
