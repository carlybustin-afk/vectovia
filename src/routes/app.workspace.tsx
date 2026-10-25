import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { AppShell, EmptyState, ErrorState, Loading, StateMessage, appHead } from "@/components/app-shell";
import { Input } from "@/components/ui/input";
import { db, must, type Member } from "@/lib/backend";
import { useSession } from "@/lib/session";
import { useWorkspace, wsKey } from "@/lib/workspace";
import { levelLabels, productLabels, type Level, type Product } from "@/lib/products";
import { loadInvitationEmails, sendFailureText, sendInvitationEmail, type SendResult } from "@/lib/invitations";

export const Route = createFileRoute("/app/workspace")({
  head: () => appHead("Workspace members", "Members, invitations and roles for a council workspace."),
  component: MembersPage,
});

type Invite = { id: string; email: string; role: string; expires_at: string; accepted_at: string | null; revoked_at: string | null };

function MembersPage() {
  return (
    <AppShell section="settings" title="Members and invitations" intro="Being a member never gives access to someone else's private enquiries. Removing a member ends their access straight away.">
      <Members />
    </AppShell>
  );
}

function Members() {
  const qc = useQueryClient();
  const { session } = useSession();
  const { current, workspaces, select } = useWorkspace();
  const ws = current!;
  const uid = session?.user.id;

  const members = useQuery({
    queryKey: wsKey(ws.id, "members"),
    queryFn: async () => must(await db.from("workspace_members").select("user_id, role, created_at").eq("workspace_id", ws.id).order("created_at")) as Member[],
  });
  const myRole = members.data?.find((m) => m.user_id === uid)?.role;
  const canManage = ws.kind === "organisation" && (myRole === "owner" || myRole === "admin");

  const invites = useQuery({
    queryKey: wsKey(ws.id, "invites"),
    enabled: canManage,
    queryFn: async () => must(await db.from("workspace_invitations").select("id, email, role, expires_at, accepted_at, revoked_at")
      .eq("workspace_id", ws.id).is("accepted_at", null).is("revoked_at", null).order("created_at", { ascending: false })) as Invite[],
  });

  const emails = useQuery({ queryKey: wsKey(ws.id, "invitation-emails"), enabled: canManage, queryFn: () => loadInvitationEmails(ws.id) });

  const refresh = () => qc.invalidateQueries({ queryKey: ["ws", ws.id] });
  const [actionError, setActionError] = useState<unknown>(null);
  const act = useMutation({
    mutationFn: async (fn: () => Promise<unknown>) => fn(),
    onSuccess: () => { setActionError(null); refresh(); },
    onError: (e) => setActionError(e),
  });

  const [link, setLink] = useState<string | null>(null);
  const [invited, setInvited] = useState<{ email: string; role: string } | null>(null);
  const [sendResult, setSendResult] = useState<SendResult | null>(null);
  /** Email the link (if email is switched on), and keep it on screen as a fallback either way. */
  const deliver = async (token: string, to: { email: string; role: string }) => {
    setLink(`${window.location.origin}/app?invite=${encodeURIComponent(token)}`);
    setInvited(to);
    setSendResult(await sendInvitationEmail(token));
  };
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<"member" | "admin">("member");

  if (members.isPending) return <Loading what="Loading members" />;
  if (members.isError) return <ErrorState error={members.error} />;
  if (!myRole) return <StateMessage title="No longer a member">You are not a member of this workspace any more. Its data has been cleared from this page.</StateMessage>;

  if (ws.kind === "personal") {
    const councils = (workspaces.data ?? []).filter((w) => w.kind === "organisation");
    return (
      <EmptyState title="You're in your personal workspace">
        <p>Only you can be in a personal workspace, so there's no one to invite here. Members and invitations belong to a council workspace.</p>
        {councils.length ? (
          <div className="mt-3 flex flex-wrap gap-2">
            {councils.map((c) => (
              <button key={c.id} type="button" onClick={() => select(c.id)} className="rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy">
                Switch to {c.name}
              </button>
            ))}
          </div>
        ) : <p className="mt-2">You're not in a council workspace yet. Council workspaces are set up by First Line.</p>}
      </EmptyState>
    );
  }

  return (
    <div className="space-y-8">
      {actionError ? <ErrorState error={actionError} /> : null}
      {canManage ? (
        <section aria-labelledby="invite-h" className="rounded-md border-t-2 border-accent bg-secondary p-4">
          <h2 id="invite-h" className="font-semibold text-primary">Invite someone to {ws.name}</h2>
          <p className="mt-1 text-sm text-muted-foreground">They'll get a one-time link to join. Owners can invite admins; owners and admins can invite members.</p>
          <form className="mt-3 flex flex-wrap items-end gap-3" onSubmit={(e) => {
            e.preventDefault(); setLink(null); setSendResult(null);
            act.mutate(async () => {
              const to = { email: email.trim().toLowerCase(), role };
              const token = must(await db.rpc("create_invitation", { _ws: ws.id, _email: to.email, _role: role })) as string;
              setEmail("");
              await deliver(token, to);
            });
          }}>
            <label className="text-sm">Email<Input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} className="mt-1 w-64 bg-background" /></label>
            <label className="text-sm">Role
              <select value={role} onChange={(e) => setRole(e.target.value as "member" | "admin")} className="mt-1 block h-9 rounded-md border border-input bg-background px-2">
                <option value="member">member</option>{myRole === "owner" ? <option value="admin">admin</option> : null}
              </select>
            </label>
            <button type="submit" disabled={act.isPending} className="rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy disabled:opacity-60">{act.isPending ? "Sending…" : "Send invitation"}</button>
          </form>
          {link && sendResult?.ok ? (
            <div role="status" className="mt-3 border-l-4 border-accent bg-secondary p-3 text-sm">
              <p className="text-primary">Invitation emailed to <strong>{invited?.email}</strong>. It comes from no-reply@firstlineeph.com; ask them to check their junk folder if it doesn't arrive.</p>
              <details className="mt-1 text-xs">
                <summary className="cursor-pointer text-primary underline">Show the link instead</summary>
                <code className="mt-1 block break-all">{link}</code>
                <button type="button" className="mt-1 rounded-md border border-primary px-3 py-1 text-xs font-medium text-primary" onClick={() => void navigator.clipboard?.writeText(link)}>Copy link</button>
              </details>
            </div>
          ) : link ? (
            <div role="status" className="mt-3 border-l-4 border-accent bg-secondary p-3 text-sm">
              <p className="text-primary">Invitation created{invited ? <> for <strong>{invited.email}</strong></> : null}. {sendResult && !sendResult.ok ? sendFailureText[sendResult.reason] : "Send them this one-time link:"}</p>
              <code className="mt-1 block break-all text-xs">{link}</code>
              <div className="mt-2 flex flex-wrap gap-2">
                {invited ? (
                  <a href={inviteMailto(invited.email, ws.name, invited.role, link)}
                    className="rounded-md bg-signal-teal px-3 py-1.5 text-xs font-semibold text-deep-navy">Send by email</a>
                ) : null}
                <button type="button" className="rounded-md border border-primary px-3 py-1.5 text-xs font-medium text-primary"
                  onClick={() => void navigator.clipboard?.writeText(link)}>Copy link</button>
              </div>
              <p className="mt-1 text-xs text-muted-foreground">“Send by email” opens your own email program with the invitation written for you. It's sent from your address when you press Send.</p>
              <p className="mt-1 text-xs text-muted-foreground">It is shown once only and works only for that email address.</p>
            </div>
          ) : null}
          <h3 className="mt-6 text-sm font-semibold text-primary">Pending invitations</h3>
          {invites.isPending ? <Loading /> : invites.isError ? <ErrorState error={invites.error} /> : invites.data.length === 0 ? (
            <p className="mt-1 text-sm text-muted-foreground">None.</p>
          ) : (
            <ul className="mt-2 space-y-2 text-sm">
              {invites.data.map((i) => (
                <li key={i.id} className="flex flex-wrap items-center gap-3">
                  <span>{i.email} · {i.role} · expires {new Date(i.expires_at).toLocaleDateString("en-GB")}
                    {(() => { const m = emails.data?.get(i.id); return m ? <span className="text-xs text-muted-foreground"> · {m.status === "sent" ? "emailed" : "email failed"} {new Date(m.created_at).toLocaleString("en-GB", { dateStyle: "medium", timeStyle: "short" })}</span> : null; })()}
                  </span>
                  <button type="button" className="rounded-md border border-primary px-2 py-1" disabled={act.isPending}
                    title="Sends a new link; the old one stops working"
                    onClick={() => act.mutate(async () => { const token = must(await db.rpc("reissue_invitation", { _invitation: i.id })) as string; await deliver(token, { email: i.email, role: i.role }); })}>Send again</button>
                  <button type="button" className="rounded-md border border-primary px-2 py-1"
                    onClick={() => act.mutate(async () => must(await db.rpc("revoke_invitation", { _invitation: i.id })))}>Cancel</button>
                </li>
              ))}
            </ul>
          )}
        </section>
      ) : <p className="text-sm text-muted-foreground">Only owners and admins can invite or remove members.</p>}
      <section>
        <h2 className="font-semibold text-primary">Members ({members.data.length})</h2>
        <ul className="mt-3 divide-y divide-border rounded-md border border-border">
          {members.data.map((m) => (
            <li key={m.user_id} className="flex flex-wrap items-center justify-between gap-2 p-3 text-sm">
              <span className="text-primary">{m.user_id === uid ? "You" : `Member ${m.user_id.slice(0, 8)}`} · <strong>{m.role}</strong></span>
              <ProductAccess ws={ws.id} member={m} canManage={canManage} />
              {myRole === "owner" && m.user_id !== uid ? (
                <span className="flex flex-wrap gap-2">
                  <select aria-label={`Role for ${m.user_id.slice(0, 8)}`} value={m.role} className="h-8 rounded-md border border-input bg-background px-2"
                    onChange={(e) => { const role = e.target.value; act.mutate(async () => must(await db.rpc("set_member_role", { _ws: ws.id, _user: m.user_id, _role: role }))); }}>
                    <option value="member">member</option><option value="admin">admin</option><option value="owner">owner</option>
                  </select>
                  <button type="button" className="rounded-md border border-primary px-2 py-1"
                    onClick={() => confirm("Transfer ownership? You will become an admin.") && act.mutate(async () => must(await db.rpc("transfer_ownership", { _ws: ws.id, _to: m.user_id })))}>Make owner</button>
                </span>
              ) : null}
              {canManage && m.user_id !== uid && m.role !== "owner" ? (
                <button type="button" className="rounded-md border border-destructive px-2 py-1 text-destructive"
                  onClick={() => confirm("Remove this member? Their access ends straight away.") && act.mutate(async () => must(await db.rpc("remove_member", { _ws: ws.id, _user: m.user_id })))}>Remove</button>
              ) : null}
            </li>
          ))}
        </ul>
      </section>

    </div>
  );
}

/** A ready-written invitation for the user's own email program (nothing is sent by First Line). */
function inviteMailto(to: string, council: string, role: string, link: string) {
  const subject = `Invitation to join ${council} on First Line`;
  const body = [
    "Hello,", "",
    `You've been invited to join ${council} on First Line as ${role === "admin" ? "an admin" : "a member"}.`, "",
    "To accept, open this link and sign in or create an account using this email address:", link, "",
    "The link works once, only for this email address, and expires in 7 days.",
  ].join("\n");
  return `mailto:${encodeURIComponent(to)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
}

type ProductRow = { product: Product; enabled: boolean };
type AccessRow = { user_id: string; product: Product; level: Level };

/** One access level per product the council has (rev 20). Owners and admins always have full access. */
function ProductAccess({ ws, member, canManage }: { ws: string; member: Member; canManage: boolean }) {
  const qc = useQueryClient();
  const products = useQuery({
    queryKey: wsKey(ws, "products"), retry: false,
    queryFn: async () => must(await db.from("workspace_products").select("product, enabled").eq("workspace_id", ws).eq("enabled", true)) as ProductRow[],
  });
  const access = useQuery({
    queryKey: wsKey(ws, "product-access"), retry: false,
    queryFn: async () => must(await db.from("product_access").select("user_id, product, level").eq("workspace_id", ws)) as AccessRow[],
  });
  const set = useMutation({
    mutationFn: async ({ product, level }: { product: Product; level: Level }) =>
      must(await db.rpc("set_product_access", { _ws: ws, _user: member.user_id, _product: product, _level: level })),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["ws", ws] }); qc.invalidateQueries({ queryKey: ["products"] }); },
  });
  if (!products.data || !access.data) return null; // before the products update, or still loading
  const full = member.role === "owner" || member.role === "admin";
  return (
    <span className="flex w-full flex-wrap items-center gap-3 text-xs">
      {products.data.map(({ product }) => {
        // Investigations: a member with no setting keeps full access (as before rev 20).
        const level = full ? "manage" : access.data.find((a) => a.user_id === member.user_id && a.product === product)?.level
          ?? (product === "investigations" ? "field" : "none");
        // Investigations offers None or Full for now; read-only Investigations comes later.
        const options: Level[] = product === "investigations" ? ["none", "field"] : ["none", "view", "field", "manage"];
        const label = (l: Level) => (product === "investigations" ? (l === "none" ? "No access" : "Full access") : levelLabels[l]);
        return (
          <label key={product} className="flex items-center gap-1">
            <span className="text-muted-foreground">{productLabels[product]}:</span>
            {full || !canManage ? <strong className="text-primary">{full ? "Full access (owner or admin)" : label(level)}</strong> : (
              <select aria-label={`${productLabels[product]} access for member ${member.user_id.slice(0, 8)}`} value={level} disabled={set.isPending}
                className="h-7 rounded-md border border-input bg-background px-1"
                onChange={(e) => { const v = e.target.value as Level; set.mutate({ product, level: v }); }}>
                {options.map((l) => <option key={l} value={l}>{label(l)}</option>)}
              </select>
            )}
          </label>
        );
      })}
      {set.isError ? <span role="alert" className="text-primary">Not saved: {set.error.message}</span> : null}
    </span>
  );
}
