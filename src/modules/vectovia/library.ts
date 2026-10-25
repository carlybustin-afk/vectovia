// Species and trap library (V-D15; revs 25/25b). Shared reference content,
// reviewed in two stages before councils rely on it. RLS returns published
// pages to everyone with access, and drafts only to the content team.
// Photos are open-licence and credited (photographer, licence, source). Until
// an author copies a photo into the library store, a draft may show it from its
// source (e.g. Wikimedia Commons), always with its credit.
import { supabase } from "@/integrations/supabase/client";
import { BackendError, db, must } from "@/lib/backend";

export type LibImage = { url: string; credit: string; licence: string; source_url: string; caption?: string | null };
export type SpeciesContent = {
  summary: string; identification?: string[]; breeding_habitats?: string[]; activity?: string; season?: string; uk_status?: string;
  diseases?: string[]; best_traps?: string[]; lures?: string[]; notes?: string; images?: LibImage[];
};
export type TrapContent = {
  summary: string; how_it_works?: string; targets?: string[]; life_stages?: string[]; setup?: string[]; placement?: string[];
  servicing?: string; tips?: string[]; common_mistakes?: string[]; images?: LibImage[];
};
export type LibVersion = {
  id: string; kind: "species" | "trap"; taxon_id: string | null; trap_type_id: string | null; version: number;
  content: SpeciesContent & TrapContent; sources: { title: string; url: string }[]; status: string; published_at: string | null; reviewed_at: string | null;
  author_id: string | null; reviewer_id: string | null; review_note: string | null;
};
export type StoredImage = { id: string; version_id: string; storage_path: string; caption: string | null; credit: string; licence: string; source_url: string; sort_order: number };
export type LibNote = { id: string; kind: "species" | "trap"; taxon_id: string | null; trap_type_id: string | null; note: string; created_by: string; updated_at: string };

/** Pages to show: the published version, or (content team only) the latest draft. Null before the library update is applied. */
export async function loadLibrary(): Promise<{ versions: LibVersion[]; images: StoredImage[] } | null> {
  const [v, i] = await Promise.all([
    db.from("vv_library_versions").select("id, kind, taxon_id, trap_type_id, version, content, sources, status, published_at, reviewed_at, author_id, reviewer_id, review_note").order("version", { ascending: false }),
    db.from("vv_library_images").select("id, version_id, storage_path, caption, credit, licence, source_url, sort_order").order("sort_order"),
  ]);
  if (v.error) { try { must(v); } catch (e) { if (e instanceof BackendError && e.kind === "setup-pending") return null; throw e; } }
  return { versions: v.data as LibVersion[], images: (i.data ?? []) as StoredImage[] };
}

export async function loadLibraryNotes(ws: string): Promise<LibNote[]> {
  const { data, error } = await db.from("vv_library_notes").select("id, kind, taxon_id, trap_type_id, note, created_by, updated_at").eq("workspace_id", ws);
  return error ? [] : (data as LibNote[]);
}

export const saveLibraryNote = (id: string, ws: string, kind: "species" | "trap", subject: string, note: string) =>
  db.rpc("vv_save_library_note", { _id: id, _ws: ws, _kind: kind, _subject: subject, _note: note });

export const storedImageUrl = (path: string) => supabase.storage.from("vectovia-library").getPublicUrl(path).data.publicUrl;

/** The page to show for a subject: published first, else the newest draft the content team can see. */
export function pageFor(versions: LibVersion[], kind: "species" | "trap", subject: string) {
  const mine = versions.filter((v) => v.kind === kind && (kind === "species" ? v.taxon_id : v.trap_type_id) === subject);
  return mine.find((v) => v.status === "published") ?? mine.find((v) => ["draft", "in_review", "reviewed"].includes(v.status)) ?? null;
}

/** The newest version still going through review (content team only), shown alongside a published page. */
export function workingVersion(versions: LibVersion[], kind: "species" | "trap", subject: string) {
  return versions.find((v) => v.kind === kind && (kind === "species" ? v.taxon_id : v.trap_type_id) === subject
    && ["draft", "in_review", "reviewed"].includes(v.status)) ?? null;
}

// ---------- Content team (First Line's author, reviewer and final approver; never councils) ----------
export type ContentRoles = { author: boolean; reviewer: boolean; admin: boolean };
export async function loadContentRoles(): Promise<ContentRoles> {
  const has = async (role: "author" | "reviewer" | "content_admin") => {
    const { data, error } = await db.rpc("has_content_role", { _roles: [role] });
    return !error && data === true;
  };
  const [author, reviewer, admin] = await Promise.all([has("author"), has("reviewer"), has("content_admin")]);
  return { author, reviewer, admin };
}

export const libRpc = {
  /** Starts a new draft owned by the signed-in author, copying the page's text and sources. */
  saveDraft: (kind: "species" | "trap", subject: string, content: LibVersion["content"], sources: LibVersion["sources"]) =>
    db.rpc("vv_lib_save_draft", { _kind: kind, _subject: subject, _content: content, _sources: sources }),
  submit: (version: string) => db.rpc("vv_lib_submit", { _version: version }),
  review: (version: string, approve: boolean, note: string) => db.rpc("vv_lib_review", { _version: version, _approve: approve, _note: note }),
  publish: (version: string) => db.rpc("vv_lib_publish", { _version: version }),
};

/** Photos on a draft still shown from their source, not yet held in the library store. */
export const photosToCopy = (page: LibVersion, stored: StoredImage[]) =>
  (page.content.images ?? []).filter((p) => !stored.some((s) => s.version_id === page.id && s.source_url === p.source_url));

const ALLOWED = ["image/jpeg", "image/png", "image/webp"];
/**
 * Copies one credited photo from its source into the library store: registers it
 * against the author's own draft (which fixes the storage path), then uploads it
 * once. Retry-safe: the same id gives the same path, and an existing file counts as done.
 */
export async function copyPhoto(version: string, p: LibImage, sort: number, id: string) {
  const res = await fetch(p.url);
  if (!res.ok) throw new Error(`Couldn't download the photo (${res.status}).`);
  const blob = await res.blob();
  if (!ALLOWED.includes(blob.type)) throw new Error("The photo must be a JPEG, PNG or WebP image.");
  if (blob.size > 5 * 1024 * 1024) throw new Error("The photo is larger than 5 MB.");
  const name = decodeURIComponent(p.url.split("/").pop() ?? "photo").replace(/^\d+px-/, "");
  const path = must(await db.rpc("vv_lib_add_image", {
    _id: id, _version: version, _file_name: name, _caption: p.caption ?? "", _credit: p.credit, _licence: p.licence, _source_url: p.source_url, _sort: sort,
  })) as string;
  const up = await supabase.storage.from("vectovia-library").upload(path, blob, { contentType: blob.type, upsert: false });
  if (up.error && !/exists|duplicate/i.test(up.error.message)) throw up.error;
  return path;
}

export const statusNote = (s: string) =>
  s === "published" ? null : s === "reviewed" ? "Reviewed, awaiting final approval" : s === "in_review" ? "With the reviewer" : "Draft, not yet checked by an entomologist";
