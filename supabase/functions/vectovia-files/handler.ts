// Vectovia files edge function: the only component that can read stored
// Vectovia files or issue view/download links (Vectovia plan V2b). A separate
// copy of the tested evidence function, kept apart so Vectovia can stand alone.
// Plain TypeScript with its dependencies passed in, so the same logic is
// unit-tested locally and runs unchanged in Supabase's Deno runtime (see index.ts).
//
//   POST { action: "verify", id }               -> fingerprint the STORED file, record verified/mismatch
//   POST { action: "link", id, mode: "view" | "download" } -> log the access, return a 5-minute link
//
// Every request must carry the signed-in user's token. Access is checked with
// the USER's permissions (vv_can_read_attachment, RLS); only then does the
// service role read the file or sign a link. Nothing is sent outside Supabase,
// and no AI is involved.

export type AttachmentRecord = { storage_path: string; file_name: string; status: string };

export type Deps = {
  /** The signed-in user's id from their token, or null if the token is invalid. */
  userId(authHeader: string): Promise<string | null>;
  /** vv_can_read_attachment(id), evaluated with the user's own permissions. */
  canRead(authHeader: string, id: string): Promise<boolean>;
  /** Service role: the item's storage facts. */
  getItem(id: string): Promise<AttachmentRecord | null>;
  /** Service role: the stored file's bytes. */
  download(path: string): Promise<Uint8Array | null>;
  /** Service role: vv_confirm_attachment(id, sha256, size) -> 'verified' | 'mismatch' | 'pending'. */
  confirm(id: string, sha256: string, size: number): Promise<string>;
  /** Service role: vv_log_attachment_access(id, 'viewed' | 'downloaded', user). */
  logAccess(id: string, action: "viewed" | "downloaded", user: string): Promise<void>;
  /** Service role: a signed URL valid for `seconds`; downloadName forces a download with that file name. */
  signedUrl(path: string, seconds: number, downloadName: string | null): Promise<string | null>;
};

export const LINK_SECONDS = 300;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes as BufferSource);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method not allowed" });

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "sign in required" });
  const user = await deps.userId(auth);
  if (!user) return json(401, { error: "sign in required" });

  let body: { action?: unknown; id?: unknown; mode?: unknown };
  try { body = await req.json(); } catch { return json(400, { error: "invalid request" }); }
  const id = typeof body.id === "string" && UUID.test(body.id) ? body.id : null;
  if (!id || (body.action !== "verify" && body.action !== "link")) return json(400, { error: "invalid request" });

  // Access is decided by the user's own permissions, never by the service role.
  if (!(await deps.canRead(auth, id))) return json(403, { error: "not allowed" });
  const item = await deps.getItem(id);
  if (!item) return json(404, { error: "not found" });

  if (body.action === "verify") {
    if (item.status !== "pending") return json(200, { status: item.status });
    const bytes = await deps.download(item.storage_path);
    if (!bytes) return json(409, { error: "file not uploaded yet", status: "pending" });
    const status = await deps.confirm(id, await sha256Hex(bytes), bytes.byteLength);
    return json(200, { status });
  }

  const mode = body.mode === "download" ? "download" : "view";
  // Log first: if logging fails, no link is issued.
  await deps.logAccess(id, mode === "download" ? "downloaded" : "viewed", user);
  const url = await deps.signedUrl(item.storage_path, LINK_SECONDS, mode === "download" ? item.file_name : null);
  if (!url) return json(404, { error: "file not available" });
  return json(200, { url, expiresIn: LINK_SECONDS });
}
