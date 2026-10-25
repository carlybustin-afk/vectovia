// Send-invitation edge function (rev 28; owner decision 2026-10-18: Resend, from
// no-reply@firstlineeph.com). Plain TypeScript with its dependencies passed in, so
// the same logic is unit-tested locally and runs unchanged in Supabase (index.ts).
//
//   POST { token }  -> emails the one-time invitation link to the invited address
//
// The signed-in inviter's browser sends the link it was just given. The database
// checks it AS THE INVITER (invitation_for_email): it must match a pending,
// unexpired invitation they may still send, within the sending limits. Only then
// is the email sent, and every attempt is recorded (record_invitation_email).
// Sent to Resend: the recipient's address, council name, role, inviter's email and
// the link. Nothing else; no case data; no AI.

export type Invitation = { invitation_id: string; workspace_name: string; email: string; role: string; expires_at: string; inviter_email: string | null };
export type Config = { apiKey: string | undefined; from: string | undefined; appUrl: string | undefined };
export type Deps = {
  userId(authHeader: string): Promise<string | null>;
  /** invitation_for_email(token) with the USER's permissions; throws { code } on refusal. */
  invitation(authHeader: string, token: string): Promise<Invitation>;
  /** Sends through the provider; returns its message id or throws. */
  send(msg: { from: string; to: string; subject: string; html: string; text: string }): Promise<string>;
  /** Service role: record_invitation_email. */
  record(invitationId: string, user: string, status: "sent" | "failed", messageId: string | null, error: string | null): Promise<void>;
  config: Config;
};

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
const ukDate = (iso: string) => new Date(iso).toLocaleDateString("en-GB", { timeZone: "Europe/London", day: "numeric", month: "long", year: "numeric" });

/** The invitation email, plain and branded (brand guidelines: navy text, teal action, no green). */
export function invitationEmail(i: Invitation, link: string) {
  const role = i.role === "admin" ? "an admin" : "a member";
  const by = i.inviter_email ? ` by ${i.inviter_email}` : "";
  const subject = `You're invited to join ${i.workspace_name} on First Line`;
  const text = [
    `You've been invited${by} to join ${i.workspace_name} on First Line as ${role}.`, "",
    "Open this link to accept. If you don't have a First Line account yet, create one with this email address:", link, "",
    `The link works once and expires on ${ukDate(i.expires_at)}.`, "",
    "If you weren't expecting this, you can ignore this email.",
    "This is an automatic message from First Line. Replies to this address aren't read; contact your council's owner or admin instead.",
  ].join("\n");
  const html = `<!doctype html><html lang="en"><body style="margin:0;padding:0;background:#f4f7f8;font-family:Arial,Helvetica,sans-serif;color:#082b4c">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f7f8;padding:24px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-top:4px solid #14a38b">
<tr><td style="padding:28px 28px 8px"><p style="margin:0;font-size:20px;font-weight:bold;letter-spacing:1px;color:#082b4c">FIRST LINE</p>
<p style="margin:2px 0 0;font-size:11px;letter-spacing:2px;color:#5b6770">ENVIRONMENTAL + PUBLIC HEALTH</p></td></tr>
<tr><td style="padding:16px 28px 0;font-size:16px;line-height:1.5">
<p style="margin:0 0 12px">You've been invited${esc(by)} to join <strong>${esc(i.workspace_name)}</strong> on First Line as ${role}.</p>
<p style="margin:0 0 20px">If you don't have a First Line account yet, you'll be asked to create one. Use this email address.</p>
<p style="margin:0 0 24px"><a href="${esc(link)}" style="display:inline-block;background:#14a38b;color:#082b4c;font-weight:bold;text-decoration:none;padding:12px 20px">Accept the invitation</a></p>
<p style="margin:0 0 8px;font-size:13px;color:#5b6770">Or copy this link: <span style="word-break:break-all">${esc(link)}</span></p>
<p style="margin:0 0 20px;font-size:13px;color:#5b6770">The link works once and expires on ${esc(ukDate(i.expires_at))}.</p></td></tr>
<tr><td style="padding:16px 28px 28px;border-top:1px solid #e3e8ea;font-size:12px;line-height:1.5;color:#5b6770">
If you weren't expecting this, you can ignore this email. This is an automatic message from First Line; replies to this address aren't read. Contact your council's owner or admin instead.</td></tr>
</table></td></tr></table></body></html>`;
  return { subject, text, html };
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method not allowed" });
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json(401, { error: "sign in required" });
  const user = await deps.userId(auth);
  if (!user) return json(401, { error: "sign in required" });

  let body: { token?: unknown };
  try { body = await req.json(); } catch { return json(400, { error: "invalid request" }); }
  const token = typeof body.token === "string" && /^[0-9a-f]{64}$/.test(body.token) ? body.token : null;
  if (!token) return json(400, { error: "invalid request" });

  const { apiKey, from, appUrl } = deps.config;
  if (!apiKey || !from || !appUrl || !/^https:\/\/[^/]+$/.test(appUrl)) return json(503, { error: "email not set up" });

  let inv: Invitation;
  try { inv = await deps.invitation(auth, token); }
  catch (e) {
    const code = (e as { code?: string }).code;
    return code === "54000" ? json(429, { error: "too many invitation emails; try again later" }) : json(403, { error: "not allowed" });
  }

  const link = `${appUrl}/app?invite=${token}`;
  const msg = invitationEmail(inv, link);
  try {
    const id = await deps.send({ from, to: inv.email, ...msg });
    await deps.record(inv.invitation_id, user, "sent", id, null);
    return json(200, { status: "sent", to: inv.email });
  } catch (e) {
    await deps.record(inv.invitation_id, user, "failed", null, String((e as Error)?.message ?? e).slice(0, 300)).catch(() => {});
    return json(502, { error: "the email could not be sent" });
  }
}
