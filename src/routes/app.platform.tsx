import { createFileRoute } from "@tanstack/react-router";
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
