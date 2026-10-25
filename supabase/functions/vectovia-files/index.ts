// Supabase Edge Function entry point (Deno) for Vectovia files. Wires the tested handler to
// Supabase: a client acting as the signed-in user (for permission checks) and
// a service-role client (to read stored files, record fingerprints, write the
// handling log and sign short-lived links). SUPABASE_URL, SUPABASE_ANON_KEY and
// SUPABASE_SERVICE_ROLE_KEY are provided by Supabase to every edge function.
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { corsHeaders, handle, type Deps } from "./handler.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const asUser = (authHeader: string) =>
  createClient(url, anonKey, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } });

const deps: Deps = {
  async userId(authHeader) {
    const { data, error } = await asUser(authHeader).auth.getUser(authHeader.replace(/^Bearer\s+/i, ""));
    return error || !data.user ? null : data.user.id;
  },
  async canRead(authHeader, id) {
    const { data, error } = await asUser(authHeader).rpc("vv_can_read_attachment", { _id: id });
    return !error && data === true;
  },
  async getItem(id) {
    const { data } = await service.from("vv_attachments").select("storage_path, file_name, status").eq("id", id).maybeSingle();
    return data ?? null;
  },
  async download(path) {
    const { data, error } = await service.storage.from("vectovia-files").download(path);
    return error || !data ? null : new Uint8Array(await data.arrayBuffer());
  },
  async confirm(id, sha256, size) {
    const { data, error } = await service.rpc("vv_confirm_attachment", { _id: id, _sha256: sha256, _size_bytes: size });
    if (error) throw error;
    return String(data);
  },
  async logAccess(id, action, user) {
    const { error } = await service.rpc("vv_log_attachment_access", { _id: id, _action: action, _actor: user });
    if (error) throw error;
  },
  async signedUrl(path, seconds, downloadName) {
    const { data, error } = await service.storage.from("vectovia-files")
      .createSignedUrl(path, seconds, downloadName ? { download: downloadName } : undefined);
    return error || !data ? null : data.signedUrl;
  },
};

Deno.serve((req) => handle(req, deps).catch(() =>
  new Response(JSON.stringify({ error: "something went wrong" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })));
