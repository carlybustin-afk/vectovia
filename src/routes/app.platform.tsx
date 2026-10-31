import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { useSession } from "@/lib/session";
import { nationalRpc } from "@/modules/vectovia/dashboards";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { AppShell, EmptyState, ErrorState, Loading, StateMessage, appHead } from "@/components/app-shell";
import { db, must } from "@/lib/backend";
import { productLabels, useIsPlatformAdmin, type Product } from "@/lib/products";

export const Route = createFileRoute("/app/platform")({
  head: () => appHead("Platform", "Switch products on or off for each council (platform owner only)."),
  component: PlatformPage,
});

function PlatformPage() {
  return (
    <AppShell needsWorkspace={false} title="Platform"
      intro="Switch products on or off for each council. Every change is recorded. Switching a product on only makes it available: each person's access is still set by the council on its Members page. No payments are taken here.">
      <Platform />
      <NationalViewers />
    </AppShell>
  );
}

type Row = { id: string; name: string; investigations: boolean; vectovia: boolean; members: number };

function Platform() {
  const isAdmin = useIsPlatformAdmin();
  const qc = useQueryClient();
  const list = useQuery({
    queryKey: ["platform", "workspaces"], enabled: isAdmin,
    queryFn: async () => must(await db.rpc("platform_workspaces")) as Row[],
  });
  const toggle = useMutation({
    mutationFn: async ({ ws, product, on }: { ws: string; product: Product; on: boolean }) =>
      must(await db.rpc("set_workspace_product", { _ws: ws, _product: product, _enabled: on })),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["platform"] }); qc.invalidateQueries({ queryKey: ["products"] }); },
  });
  if (!isAdmin) return <StateMessage title="Platform owner only">This page is for the people who run First Line.</StateMessage>;
  if (list.isPending) return <Loading what="Loading councils" />;
  if (list.isError) return <ErrorState error={list.error} />;
  if (!list.data.length) return <EmptyState title="No councils yet">Councils appear here once they're set up.</EmptyState>;
  return (
    <div className="space-y-3">
      {toggle.isError ? <ErrorState error={toggle.error} /> : null}
      <div className="overflow-x-auto rounded-md border border-border">
        <table className="w-full text-left text-sm">
          <caption className="sr-only">Councils and their products</caption>
          <thead className="bg-secondary text-primary">
            <tr>
              <th scope="col" className="px-3 py-2 font-semibold">Council</th>
              <th scope="col" className="px-3 py-2 font-semibold">Members</th>
              {(["investigations", "vectovia"] as Product[]).map((p) => <th key={p} scope="col" className="px-3 py-2 font-semibold">{productLabels[p]}</th>)}
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {list.data.map((w) => (
              <tr key={w.id}>
                <td className="px-3 py-2 font-medium text-primary">{w.name}</td>
                <td className="px-3 py-2">{Number(w.members)}</td>
                {(["investigations", "vectovia"] as Product[]).map((p) => (
                  <td key={p} className="px-3 py-2">
                    <label className="flex items-center gap-2">
                      <input type="checkbox" checked={w[p]} disabled={toggle.isPending}
                        onChange={(e) => { const on = e.target.checked; toggle.mutate({ ws: w.id, product: p, on }); }} />
                      <span>{w[p] ? "On" : "Off"}</span>
                    </label>
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

/** National viewers (v2-005): named by the platform owner; every grant and revoke is audited. */
function NationalViewers() {
  const isAdmin = useIsPlatformAdmin();
  const { session } = useSession();
  const qc = useQueryClient();
  const [revoking, setRevoking] = useState<string | null>(null);
  const [why, setWhy] = useState("");
  const list = useQuery({ queryKey: ["platform", "national"], enabled: isAdmin, queryFn: nationalRpc.list });
  const done = () => { setRevoking(null); setWhy(""); qc.invalidateQueries({ queryKey: ["platform", "national"] }); qc.invalidateQueries({ queryKey: ["vv-national"] }); };
  const grantSelf = useMutation({ mutationFn: async () => must(await nationalRpc.grant(session!.user.id, "Platform owner (demonstration)")), onSuccess: done });
  const revoke = useMutation({ mutationFn: async (u: string) => must(await nationalRpc.revoke(u, why)), onSuccess: done });
  if (!isAdmin) return null;
  const me = session?.user.id;
  const mine = list.data?.find((v) => v.user_id === me);
  return (
    <section aria-labelledby="nv-h" className="mt-8 space-y-3">
      <h2 id="nv-h" className="font-semibold text-primary">National viewers</h2>
      <p className="max-w-3xl text-sm text-muted-foreground">
        National viewers see the Vectovia national view: named sites across every organisation, with their compliance and findings. They cannot open any
        organisation&apos;s records, people or history. Removing someone is permanent for that account, so they can&apos;t be quietly added back.
      </p>
      {list.isPending ? <Loading what="Loading national viewers" /> : list.isError ? <ErrorState error={list.error} /> : (
        <>
          {list.data.length === 0 ? <p className="text-sm text-muted-foreground">No national viewers yet.</p> : (
            <ul className="divide-y divide-border rounded-md border border-border text-sm">
              {list.data.map((v) => (
                <li key={v.user_id} className="px-3 py-2">
                  <div className="flex flex-wrap items-baseline gap-2">
                    <span className="font-medium text-primary">{v.email}</span>
                    <span className="text-muted-foreground">{v.body} · added {new Date(v.granted_at).toLocaleDateString("en-GB")}{v.revoked_at ? ` · removed ${new Date(v.revoked_at).toLocaleDateString("en-GB")}` : ""}</span>
                    {!v.revoked_at && revoking !== v.user_id ? <button type="button" className="ml-auto text-primary underline" onClick={() => setRevoking(v.user_id)}>Remove</button> : null}
                  </div>
                  {revoking === v.user_id ? (
                    <div className="mt-2 flex flex-wrap items-end gap-2">
                      <label className="flex flex-col gap-1"><span className="text-muted-foreground">Why? (required; this cannot be undone for this account)</span>
                        <input className="h-9 w-72 max-w-full rounded-md border border-input bg-background px-2" maxLength={500} value={why} onChange={(e) => setWhy(e.target.value)} /></label>
                      <button type="button" className="h-9 rounded-md border border-primary px-3 font-medium text-primary disabled:opacity-60" disabled={revoke.isPending || why.trim().length < 5} onClick={() => revoke.mutate(v.user_id)}>Remove national view</button>
                      <button type="button" className="text-primary underline" onClick={() => setRevoking(null)}>Cancel</button>
                    </div>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
          {!mine ? <button type="button" className="rounded-md border border-primary px-3 py-1.5 text-sm font-medium text-primary disabled:opacity-60" disabled={grantSelf.isPending} onClick={() => grantSelf.mutate()}>Give my account the national view (for demonstrations)</button> : null}
          <p className="text-xs text-muted-foreground">Adding someone from the national body by email is not built yet.</p>
          {grantSelf.isError ? <ErrorState error={grantSelf.error} /> : null}
          {revoke.isError ? <ErrorState error={revoke.error} /> : null}
        </>
      )}
    </section>
  );
}
