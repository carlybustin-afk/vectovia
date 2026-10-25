// Photos and attachments on a site, visit or sample (V2b). Originals are
// fingerprinted and never changed; views and downloads are logged.
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { Paperclip } from "lucide-react";
import { ErrorState } from "@/components/app-shell";
import { Input } from "@/components/ui/input";
import { wsKey } from "@/lib/workspace";
import { run, when, who } from "./api";
import { acceptAttr, correctAttachment, formatBytes, loadAttachments, openAttachment, recheckAttachment, uploadAttachment, type Attachment } from "./files";
import { StatusTag } from "./ui";

export const useAttachments = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "attachments"), queryFn: () => loadAttachments(ws), retry: false });

const statusText: Record<Attachment["status"], string> = { verified: "Fingerprint checked", mismatch: "▲ Fingerprint mismatch", pending: "Check pending" };

export function Attachments({ ws, recordType, recordId, canRecord, uid, compact }: {
  ws: string; recordType: Attachment["record_type"]; recordId: string; canRecord: boolean; uid: string | undefined; compact?: boolean;
}) {
  const qc = useQueryClient();
  const list = useAttachments(ws);
  const [adding, setAdding] = useState(false);
  const [err, setErr] = useState<unknown>(null);
  const act = useMutation({
    mutationFn: (fn: () => Promise<unknown>) => fn(),
    onSuccess: () => { setErr(null); qc.invalidateQueries({ queryKey: ["ws", ws, "vv", "attachments"] }); },
    onError: (e) => setErr(e),
  });
  if (list.isError) return null;   // before the attachments update is applied
  const items = (list.data ?? []).filter((a) => a.record_type === recordType && a.record_id === recordId);
  return (
    <div className="space-y-1 text-xs">
      {items.length || !compact ? <p className="font-semibold uppercase tracking-wide text-accent">Photos and files ({items.length})</p> : null}
      {err ? <ErrorState error={err} /> : null}
      {items.length ? (
        <ul className="divide-y divide-border rounded-md border border-border">
          {items.map((a) => <AttachmentRow key={a.id} ws={ws} a={a} uid={uid} canRecord={canRecord} act={(fn) => act.mutate(fn)} />)}
        </ul>
      ) : null}
      {canRecord ? (adding ? <Uploader ws={ws} recordType={recordType} recordId={recordId} onDone={() => setAdding(false)} /> : (
        <button type="button" className="inline-flex items-center gap-1 font-medium text-primary underline" onClick={() => setAdding(true)}>
          <Paperclip className="h-3.5 w-3.5" aria-hidden="true" />Add photos or files
        </button>
      )) : null}
    </div>
  );
}

function AttachmentRow({ ws, a, uid, canRecord, act }: { ws: string; a: Attachment; uid: string | undefined; canRecord: boolean; act: (fn: () => Promise<unknown>) => void }) {
  const [editing, setEditing] = useState(false);
  return (
    <li className="space-y-1 px-2 py-1.5">
      <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
        <span className="font-medium text-primary [overflow-wrap:anywhere]">{a.caption || a.file_name}</span>
        <StatusTag strong={a.status !== "verified"}>{statusText[a.status]}</StatusTag>
        <span className="text-muted-foreground">
          {a.kind} · {formatBytes(a.size_bytes)} · added {when(a.received_at)} by {who(a.uploaded_by, uid)}
          {a.captured_at ? ` · taken ${when(a.captured_at)}${a.capture_source === "officer" ? " (entered by officer)" : ""}` : ""}
        </span>
        <span className="ml-auto flex gap-2">
          <button type="button" className="text-primary underline" onClick={() => act(() => openAttachment(a.id, "view"))}>View</button>
          <button type="button" className="text-primary underline" onClick={() => act(() => openAttachment(a.id, "download"))}>Download</button>
          {a.status === "pending" ? <button type="button" className="text-primary underline" onClick={() => act(() => recheckAttachment(a.id))}>Check again</button> : null}
          {canRecord && !editing ? <button type="button" className="text-primary underline" onClick={() => setEditing(true)}>Edit caption</button> : null}
        </span>
      </div>
      {editing ? <CaptionForm ws={ws} a={a} onDone={() => setEditing(false)} /> : null}
    </li>
  );
}

function CaptionForm({ ws, a, onDone }: { ws: string; a: Attachment; onDone: () => void }) {
  const qc = useQueryClient();
  const [caption, setCaption] = useState(a.caption ?? "");
  const [why, setWhy] = useState("");
  const save = useMutation({
    mutationFn: () => run(correctAttachment(a.id, caption, a.captured_at, a.capture_source, why)),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["ws", ws, "vv", "attachments"] }); onDone(); },
  });
  return (
    <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <Input aria-label="Caption" className="h-8 w-56" maxLength={500} value={caption} onChange={(e) => setCaption(e.target.value)} placeholder="Caption" />
      <Input aria-label="Why are you changing it?" className="h-8 w-56" maxLength={500} value={why} onChange={(e) => setWhy(e.target.value)} placeholder="Why are you changing it?" />
      <button type="submit" disabled={why.trim().length < 5 || save.isPending} className="h-8 rounded-md border border-primary px-2 text-primary disabled:opacity-60">Save</button>
      <button type="button" className="h-8 text-primary underline" onClick={onDone}>Cancel</button>
      {save.isError ? <ErrorState error={save.error} /> : null}
    </form>
  );
}

function Uploader({ ws, recordType, recordId, onDone }: { ws: string; recordType: Attachment["record_type"]; recordId: string; onDone: () => void }) {
  const qc = useQueryClient();
  const [files, setFiles] = useState<File[]>([]);
  const [caption, setCaption] = useState("");
  const [step, setStep] = useState("");
  const up = useMutation({
    mutationFn: () => uploadMany(recordType, recordId, files, caption, setStep),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["ws", ws, "vv", "attachments"] }); onDone(); },
  });
  return (
    <form className="space-y-2 rounded-md bg-secondary p-2" onSubmit={(e) => { e.preventDefault(); up.mutate(); }}>
      <input type="file" multiple accept={acceptAttr} capture="environment" aria-label="Choose photos or files"
        onChange={(e) => setFiles([...(e.target.files ?? [])])} className="block text-sm" />
      <Input aria-label="Caption (optional)" className="h-8 bg-background" maxLength={500} value={caption} onChange={(e) => setCaption(e.target.value)} placeholder="Caption (optional)" />
      <p className="text-muted-foreground">Photos, PDF, Word, Excel or CSV, up to 25 MB each. Each original is fingerprinted and never changed.</p>
      {up.isError ? <ErrorState error={up.error} /> : null}
      {up.isPending ? <p role="status" className="text-primary">{step}…</p> : null}
      <div className="flex gap-2">
        <button type="submit" disabled={!files.length || up.isPending} className="h-8 rounded-md bg-signal-teal px-3 font-semibold text-deep-navy disabled:opacity-60">Upload {files.length || ""}</button>
        <button type="button" className="h-8 text-primary underline" onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}

/** Uploads one after another; stops at the first failure (earlier ones are safely stored). */
export async function uploadMany(recordType: Attachment["record_type"], recordId: string, files: File[], caption: string, onStep: (s: string) => void) {
  const results = [];
  for (const [i, f] of files.entries()) {
    results.push(await uploadAttachment(recordType, recordId, f, caption, (s) => onStep(files.length > 1 ? `${i + 1} of ${files.length}: ${s}` : s)));
  }
  return results;
}
