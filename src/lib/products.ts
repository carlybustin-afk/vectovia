// Products per council and each person's access (Vectovia plan V0, rev 20).
// Menus and landing pages use this; the database enforces access on its own.
// A product being on never widens data access (AGENTS.md).
import { useQuery } from "@tanstack/react-query";
import { BackendError, db, must } from "@/lib/backend";
import { useSession } from "@/lib/session";

export type Product = "investigations" | "vectovia";
export type Level = "none" | "view" | "field" | "manage";
export const productLabels: Record<Product, string> = { investigations: "Investigations", vectovia: "Vectovia" };
export const levelLabels: Record<Level, string> = { none: "No access", view: "View only", field: "Field officer", manage: "Manager" };

type Row = { workspace_id: string; product: Product; level: Level | null };

/** The signed-in person's products in every workspace (null before the products update is applied). */
export function useMyProducts() {
  const { session } = useSession();
  const uid = session?.user.id;
  return useQuery({
    queryKey: ["products", uid], enabled: !!uid, staleTime: 60_000,
    queryFn: async (): Promise<Row[] | null> => {
      const { data, error } = await db.rpc("my_products");
      if (error) { try { must({ data: null, error }); } catch (e) { if (e instanceof BackendError && e.kind === "setup-pending") return null; throw e; } }
      return data as Row[];
    },
  });
}

/** Access level for a product in a workspace: null = not available. Before rev 20, Investigations is assumed (as before). */
export function levelIn(rows: Row[] | null | undefined, ws: string | undefined, product: Product): Level | null {
  if (rows === null) return product === "investigations" ? "field" : null;
  const r = rows?.find((x) => x.workspace_id === ws && x.product === product);
  return r?.level ?? null;
}
export const canUse = (l: Level | null) => !!l && l !== "none";

export function useIsPlatformAdmin() {
  const { session } = useSession();
  const uid = session?.user.id;
  return useQuery({
    queryKey: ["platform-admin", uid], enabled: !!uid, staleTime: 5 * 60_000,
    queryFn: async () => {
      const { data, error } = await db.from("platform_admins").select("user_id").eq("user_id", uid!);
      return !error && (data ?? []).length > 0;
    },
  }).data ?? false;
}
