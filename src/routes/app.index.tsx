import { createFileRoute, Navigate, useNavigate } from "@tanstack/react-router";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { AppShell, ErrorState, StateMessage, appHead } from "@/components/app-shell";
import { db, must } from "@/lib/backend";
import { useWorkspace } from "@/lib/workspace";
import { useSession } from "@/lib/session";
import { canUse, levelIn, useMyProducts } from "@/lib/products";

const search = z.object({ invite: z.string().min(16).max(200).optional() });

export const Route = createFileRoute("/app/")({
  validateSearch: (s) => search.parse(s),
  head: () => appHead("Workspaces", "Your personal workspace and council workspaces you've been invited to."),
  component: WorkspacesPage,
});

function AcceptInvite({ token }: { token: string }) {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const { session } = useSession();
  const { select } = useWorkspace();
  const accept = useMutation({
    mutationFn: async () => must(await db.rpc("accept_invitation", { _token: token })) as string,
    onSuccess: async (wsId) => {
      await qc.invalidateQueries({ queryKey: ["workspaces", session?.user.id] });
      select(wsId);
      navigate({ to: "/app", search: {}, replace: true });
    },
  });
  return (
    <div className="mb-6 rounded-md border-t-2 border-accent bg-secondary p-5">
      <p className="font-semibold text-primary">You've been invited to a council workspace</p>
      <p className="mt-1 text-sm text-muted-foreground">The invitation must be for {session?.user.email}. It works once and expires.</p>
      <button type="button" disabled={accept.isPending} onClick={() => accept.mutate()}
        className="mt-3 rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy disabled:opacity-60">
        {accept.isPending ? "Joining…" : "Accept invitation"}
      </button>
      {accept.isError ? <div className="mt-3"><StateMessage title="Invitation not accepted">It may be expired, cancelled, already used, or for a different email address. Ask the workspace owner or admin for a new one.</StateMessage></div> : null}
    </div>
  );
}

// No longer in the menu (the header switcher changes workspace). Kept so
// invitation links (/app?invite=...) still work; otherwise opens Cases.
function WorkspacesPage() {
  const { invite } = Route.useSearch();
  const { current } = useWorkspace();
  const products = useMyProducts();
  if (invite) return <WorkspacesWithInvite invite={invite} />;
  if (products.isPending || !current) return null;
  // People with Vectovia but not Investigations in this workspace start in Vectovia.
  const investigations = canUse(levelIn(products.data, current.id, "investigations"));
  const vectovia = canUse(levelIn(products.data, current.id, "vectovia"));
  return <Navigate to="/app/vectovia" replace />;
}

function WorkspacesWithInvite({ invite }: { invite: string }) {
  const { workspaces, current, select } = useWorkspace();
  const list = workspaces.data ?? [];
  return (
    <AppShell title="Your workspaces" intro="Each person has a personal workspace and can join council workspaces by invitation only. Switching workspace clears what was shown from the previous one.">
      <AcceptInvite token={invite} />
      {workspaces.isError ? <ErrorState error={workspaces.error} /> : (
        <ul className="grid gap-4 md:grid-cols-2">
          {list.map((w) => (
            <li key={w.id} className={`rounded-md p-5 ${w.id === current?.id ? "border-t-2 border-accent bg-secondary" : "border border-border"}`}>
              <p className="text-sm font-medium text-accent">{w.kind === "personal" ? "Personal workspace" : "Council workspace"}</p>
              <p className="mt-1 font-semibold text-primary">{w.kind === "personal" ? "Only you" : w.name}</p>
              {w.id === current?.id ? <p className="mt-3 text-sm text-muted-foreground">Currently open</p> : (
                <button type="button" onClick={() => select(w.id)} className="mt-3 rounded-md border border-primary px-3 py-1.5 text-sm font-medium text-primary">Open</button>
              )}
            </li>
          ))}
          {list.filter((w) => w.kind === "organisation").length === 0 ? (
            <li className="rounded-md border border-dashed border-border p-5 text-sm text-muted-foreground">
              No council workspaces. Council workspaces are set up by First Line and joined by an invitation link from their owner or admin.
            </li>
          ) : null}
        </ul>
      )}
    </AppShell>
  );
}
