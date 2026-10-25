// Invitation emails (rev 28, send-invitation edge function). The browser hands the
// one-time link it was just given to the function; the database checks it as the
// inviter before anything is sent. Until the owner switches email on, this reports
// "not set up" and the screen offers the copy-link and own-email options instead.
import { supabase } from "@/integrations/supabase/client";
import { db } from "@/lib/backend";

export type SendResult = { ok: true; to: string } | { ok: false; reason: "not_set_up" | "too_many" | "denied" | "failed" };

export async function sendInvitationEmail(token: string): Promise<SendResult> {
  const { data, error } = await supabase.functions.invoke("send-invitation", { body: { token } });
  if (!error) return { ok: true, to: String((data as { to?: string })?.to ?? "") };
  const status = (error as { context?: Response }).context?.status;
  if (status === 503 || status === 404 || status === undefined) return { ok: false, reason: "not_set_up" };
  if (status === 429) return { ok: false, reason: "too_many" };
  if (status === 403 || status === 401) return { ok: false, reason: "denied" };
  return { ok: false, reason: "failed" };
}

export const sendFailureText: Record<Exclude<SendResult, { ok: true }>["reason"], string> = {
  not_set_up: "Automatic emails aren't switched on yet, so send them this link yourself.",
  too_many: "Too many invitation emails have been sent recently. Try again later, or send them this link yourself.",
  denied: "You can't email this invitation. Send them this link yourself, or ask your council's owner.",
  failed: "The email couldn't be sent. Send them this link yourself, or try again later.",
};

export type InvitationEmail = { invitation_id: string; status: "sent" | "failed"; created_at: string };
/** The latest email per invitation, for owners and admins. Empty until rev 28 is applied. */
export async function loadInvitationEmails(ws: string): Promise<Map<string, InvitationEmail>> {
  const { data, error } = await db.from("invitation_emails").select("invitation_id, status, created_at").eq("workspace_id", ws).order("created_at");
  const out = new Map<string, InvitationEmail>();
  if (error) return out;
  for (const r of data as InvitationEmail[]) out.set(r.invitation_id, r);
  return out;
}
