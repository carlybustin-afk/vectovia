// Reports and exports (plan V6; owner decision 2026-10-17: PDF and Word built in
// the browser, fingerprinted and logged). A report is described once as a simple
// document (headings, paragraphs, label/value lists, tables) and written out as
// PDF or Word from that one description, so both say exactly the same thing.
// Every file is fingerprinted (SHA-256) and logged in vv_exports BEFORE it is
// offered for download: if the log can't be written, nothing is downloaded.
// Nothing is sent to any outside service; no AI (B2).
import { db, must } from "@/lib/backend";

export type Block =
  | { t: "h1" | "h2" | "p" | "note"; text: string }
  | { t: "kv"; rows: [string, string][] }
  | { t: "table"; caption?: string; head: string[]; rows: string[][]; widths?: number[] };
export type ExportDoc = { title: string; subtitle: string; meta: [string, string][]; blocks: Block[]; footer: string };

export const FORMAT = { report: "vectovia-report-v1", incursion: "vectovia-incursion-v1", csv: "vectovia-csv-v1" } as const;

/** A file's bytes (with a fallback for environments whose Blob lacks arrayBuffer). */
export async function blobBytes(blob: Blob): Promise<ArrayBuffer> {
  if (typeof blob.arrayBuffer === "function") return blob.arrayBuffer();
  return new Promise((resolve, reject) => { const r = new FileReader(); r.onload = () => resolve(r.result as ArrayBuffer); r.onerror = () => reject(r.error); r.readAsArrayBuffer(blob); });
}

export async function sha256Hex(blob: Blob): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", await blobBytes(blob));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export type ExportKind = "report_pdf" | "report_docx" | "incursion_pdf" | "incursion_docx" | "csv";
/** Fingerprint, log, then download. Returns the fingerprint. */
export async function logAndDownload(o: {
  id: string; ws: string; kind: ExportKind; scope: Record<string, unknown>; counts: Record<string, number>; fileName: string; blob: Blob; format: string;
}): Promise<string> {
  const sha = await sha256Hex(o.blob);
  must(await db.rpc("vv_log_export", {
    _id: o.id, _ws: o.ws, _kind: o.kind, _scope: o.scope, _counts: o.counts, _file_name: o.fileName, _size: o.blob.size, _sha256: sha, _format_version: o.format,
  }));
  const url = URL.createObjectURL(o.blob);
  const a = document.createElement("a");
  a.href = url; a.download = o.fileName; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
  return sha;
}

export type ExportLogRow = {
  id: string; kind: ExportKind; scope: Record<string, unknown>; counts: Record<string, number>; file_name: string; size_bytes: number;
  sha256: string; format_version: string; created_by: string; created_role: string; created_at: string;
};
export async function loadExportLog(ws: string): Promise<ExportLogRow[] | null> {
  const { data, error } = await db.from("vv_exports").select("id, kind, scope, counts, file_name, size_bytes, sha256, format_version, created_by, created_role, created_at")
    .eq("workspace_id", ws).order("created_at", { ascending: false }).limit(200);
  if (error) return null; // not switched on yet
  return data as ExportLogRow[];
}

// ---------- CSV ---------------------------------------------------------------------------------
/**
 * RFC 4180 CSV with a UTF-8 byte-order mark (so Excel reads it correctly). Cells that a
 * spreadsheet would run as a formula (starting =, +, -, @, tab or return) get a leading
 * apostrophe so opening the file can never run anything.
 */
export function toCsv(head: string[], rows: (string | number | null | undefined)[][]): string {
  const cell = (v: string | number | null | undefined) => {
    let s = v === null || v === undefined ? "" : String(v);
    if (/^[=+\-@\t\r]/.test(s) && !/^-?\d+(\.\d+)?$/.test(s)) s = `'${s}`;
    return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return "﻿" + [head, ...rows].map((r) => r.map(cell).join(",")).join("\r\n") + "\r\n";
}
export const csvBlob = (text: string) => new Blob([text], { type: "text/csv;charset=utf-8" });

/** Safe file names: "vectovia-report-2026-10-17.pdf". */
export const fileStamp = () => new Date().toISOString().slice(0, 10);
export const safeName = (s: string) => s.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "").slice(0, 120);
