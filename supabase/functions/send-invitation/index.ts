// Supabase Edge Function entry point (Deno) for invitation emails. Wires the tested
// handler to Supabase and Resend. Secrets set by the owner in Supabase (never in code):
//   RESEND_API_KEY  the Resend API key
//   EMAIL_FROM      e.g. First Line <no-reply@firstlineeph.com>
//   APP_URL         the site's address, e.g. https://app.firstlineeph.com (no trailing slash)
// Until all three are set, the function replies "email not set up" and the screen
// keeps offering the copy-link and own-email options.
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { corsHeaders, handle, type Deps, type Invitation } from "./handler.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const asUser = (authHeader: string) =>
  createClient(url, anonKey, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } });

const deps: Deps = {
  config: { apiKey: Deno.env.get("RESEND_API_KEY"), from: Deno.env.get("EMAIL_FROM"), appUrl: Deno.env.get("APP_URL")?.replace(/\/+$/, "") },
  async userId(authHeader) {
    const { data, error } = await asUser(authHeader).auth.getUser(authHeader.replace(/^Bearer\s+/i, ""));
    return error || !data.user ? null : data.user.id;
  },
  async invitation(authHeader, token) {
    const { data, error } = await asUser(authHeader).rpc("invitation_for_email", { _token: token });
    if (error) throw { code: error.code };
    const row = (data as Invitation[] | null)?.[0];
    if (!row) throw { code: "42501" };
    return row;
  },
  async send(msg) {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${deps.config.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: msg.from, to: [msg.to], subject: msg.subject, html: msg.html, text: msg.text }),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok || !body?.id) throw new Error(`Resend ${res.status}: ${String(body?.message ?? "error").slice(0, 200)}`);
    return String(body.id);
  },
  async record(invitationId, user, status, messageId, err) {
    const { error } = await service.rpc("record_invitation_email",
      { _invitation: invitationId, _sent_by: user, _status: status, _provider_message_id: messageId, _error: err });
    if (error) throw error;
  },
};

Deno.serve((req) => handle(req, deps).catch(() =>
  new Response(JSON.stringify({ error: "something went wrong" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } })));
