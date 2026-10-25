import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { db, must, probeSchema, type Workspace } from "./backend";
import { useSession } from "./session";

type WsState = {
  schema: ReturnType<typeof useQuery<Awaited<ReturnType<typeof probeSchema>>>>;
  workspaces: ReturnType<typeof useQuery<Workspace[]>>;
  current: Workspace | null;
  select: (id: string) => void;
};
const Ctx = createContext<WsState | null>(null);

/** Workspace-scoped query keys all start with ["ws", workspaceId]. */
export const wsKey = (wsId: string | null, ...rest: unknown[]) => ["ws", wsId, ...rest];

export function WorkspaceProvider({ children }: { children: ReactNode }) {
  const qc = useQueryClient();
  const { session } = useSession();
  const uid = session?.user.id ?? null;
  // Selection lives in memory only: never trusted by the server, never stored.
  const [selected, setSelected] = useState<string | null>(null);

  const schema = useQuery({ queryKey: ["schema", uid], queryFn: probeSchema, enabled: !!uid, staleTime: 60_000 });

  const workspaces = useQuery({
    queryKey: ["workspaces", uid],
    enabled: !!uid && schema.data === "ready",
    queryFn: async () => {
      // Idempotent: creates profile + personal workspace on first sign-in.
      must(await db.rpc("ensure_personal_workspace"));
      return must(await db.from("workspaces").select("id, kind, name").order("kind", { ascending: false }).order("name")) as Workspace[];
    },
  });

  const list = workspaces.data ?? [];
  const current = list.find((w) => w.id === selected) ?? null;

  const select = useCallback((id: string) => {
    setSelected((prev) => {
      if (prev && prev !== id) qc.removeQueries({ queryKey: ["ws", prev] }); // clear previous workspace data
      return id;
    });
  }, [qc]);

  // Default to a council workspace (else personal); if the selected one disappears
  // (membership removed), drop its cached data and fall back.
  useEffect(() => {
    if (!workspaces.data) return;
    if (selected && !workspaces.data.some((w) => w.id === selected)) {
      qc.removeQueries({ queryKey: ["ws", selected] });
      setSelected(null);
      return;
    }
    if (!selected && workspaces.data.length) {
      // Open in a council workspace when you belong to one (that's where most work happens).
      setSelected((workspaces.data.find((w) => w.kind === "organisation") ?? workspaces.data.find((w) => w.kind === "personal") ?? workspaces.data[0])!.id);
    }
  }, [workspaces.data, selected, qc]);

  useEffect(() => { if (!uid) setSelected(null); }, [uid]);

  return <Ctx.Provider value={{ schema, workspaces, current, select }}>{children}</Ctx.Provider>;
}

export function useWorkspace() {
  const v = useContext(Ctx);
  if (!v) throw new Error("useWorkspace outside WorkspaceProvider");
  return v;
}
