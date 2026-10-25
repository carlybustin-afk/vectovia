// Vectovia photos and attachments (V2b; revs 23/23b). Same proven flow as
// case evidence, kept entirely separate so Vectovia can stand alone:
//  1. fingerprint the file on the device (SHA-256), and read a photo's capture
//     time from its metadata where present;
//  2. vv_register_attachment() -> the only storage path the file may go to;
//  3. upload the original to the private "vectovia-files" store (no overwrite);
//  4. the vectovia-files edge function fingerprints the STORED file.
// Viewing and downloading go through the edge function, which logs them and
// returns a link that expires in 5 minutes. No AI reads files.
import { supabase } from "@/integrations/supabase/client";
import { db, must } from "@/lib/backend";
import { newId } from "./api";

export const MAX_BYTES = 25 * 1024 * 1024;
export const ACCEPT: Record<string, string> = {
  "image/jpeg": "Photo", "image/png": "Image", "image/heic": "Photo", "image/heif": "Photo", "application/pdf": "PDF",
  "application/msword": "Word", "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "Word",
  "application/vnd.ms-excel": "Excel", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "Excel", "text/csv": "CSV",
};
export const acceptAttr = [...Object.keys(ACCEPT), ".heic", ".heif", ".csv"].join(",");

export type Attachment = {
  id: string; record_type: "site" | "visit" | "sample"; record_id: string; site_id: string; kind: "photo" | "document" | "spreadsheet";
  file_name: string; mime_type: string; size_bytes: number; sha256_reported: string; sha256_stored: string | null;
  status: "pending" | "verified" | "mismatch"; caption: string | null; captured_at: string | null;
  capture_source: "device_metadata" | "officer" | "unknown"; uploaded_by: string; received_at: string; verified_at: string | null;
};

export async function loadAttachments(ws: string): Promise<Attachment[]> {
  const rows = must(await db.from("vv_attachments").select("id, record_type, record_id, site_id, kind, file_name, mime_type, size_bytes, sha256_reported, sha256_stored, status, caption, captured_at, capture_source, uploaded_by, received_at, verified_at")
    .eq("workspace_id", ws).order("received_at", { ascending: false })) as Attachment[];
  return rows.map((r) => ({ ...r, size_bytes: Number(r.size_bytes) }));
}

/** SHA-256 of the file's exact bytes, as lowercase hex. */
export async function fingerprint(file: Blob): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", await file.arrayBuffer());
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Capture time from a JPEG's EXIF metadata (DateTimeOriginal), if present.
 * EXIF stores local camera time without a time zone; it's read as local time
 * on this device. Returns null when absent (the officer can enter it).
 */
export async function readCaptureTime(file: Blob): Promise<Date | null> {
  if (file.type !== "image/jpeg") return null;
  const v = new DataView(await file.slice(0, 256 * 1024).arrayBuffer());
  if (v.byteLength < 4 || v.getUint16(0) !== 0xffd8) return null;
  let off = 2;
  while (off + 4 <= v.byteLength) {
    const marker = v.getUint16(off);
    const len = v.getUint16(off + 2);
    if (marker === 0xffe1 && v.getUint32(off + 4) === 0x45786966) return parseExif(v, off + 10);
    if ((marker & 0xff00) !== 0xff00 || len < 2) return null;
    off += 2 + len;
  }
  return null;
}

function parseExif(v: DataView, tiff: number): Date | null {
  if (tiff + 8 > v.byteLength) return null;
  const le = v.getUint16(tiff) === 0x4949;
  const u16 = (o: number) => v.getUint16(o, le);
  const u32 = (o: number) => v.getUint32(o, le);
  const findTag = (ifd: number, tag: number) => {
    if (ifd + 2 > v.byteLength) return null;
    const n = u16(ifd);
    for (let i = 0; i < n; i++) {
      const e = ifd + 2 + i * 12;
      if (e + 12 > v.byteLength) return null;
      if (u16(e) === tag) return e;
    }
    return null;
  };
  const exifPtr = findTag(tiff + u32(tiff + 4), 0x8769);
  if (exifPtr === null) return null;
  const dto = findTag(tiff + u32(exifPtr + 8), 0x9003);
  if (dto === null || u32(dto + 4) < 19) return null;
  const at = tiff + u32(dto + 8);
  if (at + 19 > v.byteLength) return null;
  const s = String.fromCharCode(...new Uint8Array(v.buffer, v.byteOffset + at, 19));
  const m = /^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$/.exec(s);
  if (!m) return null;
  const d = new Date(+m[1]!, +m[2]! - 1, +m[3]!, +m[4]!, +m[5]!, +m[6]!);
  return Number.isNaN(d.getTime()) || d.getTime() > Date.now() + 5 * 60_000 ? null : d;
}


/** Browsers often report HEIC/CSV with an empty type; fall back to the extension. */
export function mimeOf(file: File): string {
  if (file.type && ACCEPT[file.type]) return file.type;
  const ext = file.name.toLowerCase().split(".").pop() ?? "";
  return ({ heic: "image/heic", heif: "image/heif", jpg: "image/jpeg", jpeg: "image/jpeg", pdf: "application/pdf", csv: "text/csv" } as Record<string, string>)[ext] ?? file.type;
}

async function invoke<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke("vectovia-files", { body });
  if (error) throw new Error(error.message || "The file service didn't respond.");
  return data as T;
}

export type UploadResult = { id: string; status: "verified" | "mismatch" | "pending" };

export async function uploadAttachment(recordType: Attachment["record_type"], recordId: string, file: File, caption: string,
  onStep: (s: string) => void): Promise<UploadResult> {
  const mime = mimeOf(file);
  if (!ACCEPT[mime]) throw new Error("This type of file can't be added. Use a photo, PDF, Word, Excel or CSV file.");
  if (file.size > MAX_BYTES) throw new Error("Files must be 25 MB or smaller.");
  const id = newId();
  onStep("Fingerprinting on this device");
  const sha = await fingerprint(file);
  const captured = await readCaptureTime(file);
  onStep("Registering");
  const path = must(await db.rpc("vv_register_attachment", {
    _id: id, _record_type: recordType, _record_id: recordId, _file_name: file.name, _mime_type: mime, _size_bytes: file.size, _sha256: sha,
    _caption: caption || null, _captured_at: captured?.toISOString() ?? null, _capture_source: captured ? "device_metadata" : "unknown",
  })) as string;
  onStep("Uploading the original");
  const up = await supabase.storage.from("vectovia-files").upload(path, file, { upsert: false, contentType: mime, cacheControl: "0" });
  if (up.error) throw new Error(`Upload failed: ${up.error.message}`);
  onStep("Checking the stored file's fingerprint");
  try {
    const r = await invoke<{ status: UploadResult["status"] }>({ action: "verify", id });
    return { id, status: r.status };
  } catch {
    return { id, status: "pending" };   // stored safely; the check can be re-run
  }
}

export const recheckAttachment = (id: string) => invoke<{ status: UploadResult["status"] }>({ action: "verify", id });

/** Logged, short-lived link (5 minutes) to view or download an original. */
export async function openAttachment(id: string, mode: "view" | "download") {
  const w = window.open("", "_blank");
  if (w) w.opener = null;
  try {
    const r = await invoke<{ url: string }>({ action: "link", id, mode });
    if (w) w.location.href = r.url; else window.location.href = r.url;
  } catch (e) {
    w?.close();
    throw e;
  }
}

export const correctAttachment = (id: string, caption: string, capturedAt: string | null, source: Attachment["capture_source"], why: string) =>
  db.rpc("vv_correct_attachment", { _id: id, _caption: caption, _captured_at: capturedAt, _capture_source: source, _why: why });

export const formatBytes = (n: number) => (n < 1024 ? `${n} B` : n < 1024 * 1024 ? `${(n / 1024).toFixed(0)} KB` : `${(n / 1024 / 1024).toFixed(1)} MB`);
