// Typed-loose access to the Build 02 (revision 6) API contract.
// The generated types only describe tables that exist on the hosted project;
// until the reviewed migration is applied there are none, so we use an
// untyped view of the same connected client. Every call is still subject to
// the database's RLS and grants — the browser decides nothing about access.
import type { SupabaseClient, PostgrestError } from "@supabase/supabase-js";
import { supabase } from "@/integrations/supabase/client";

export const db = supabase as unknown as SupabaseClient;

export type Failure = "setup-pending" | "signed-out" | "denied" | "error";

export class BackendError extends Error {
  constructor(public kind: Failure, message: string) {
    super(message);
  }
}

/** Map a PostgREST/Auth error to a fail-closed category. */
export function classify(err: Pick<PostgrestError, "code" | "message"> | null | undefined): Failure {
  if (!err) return "error";
  const code = err.code ?? "";
  // Table / function missing from the schema cache: migration not applied.
  if (code === "PGRST205" || code === "PGRST202" || code === "42P01" || code === "42883") return "setup-pending";
  if (code === "PGRST301" || code === "PGRST303" || /jwt|expired/i.test(err.message ?? "")) return "signed-out";
  if (code === "42501" || code === "PGRST116") return "denied";
  return "error";
}

export function fail(err: PostgrestError | null): never {
  throw new BackendError(classify(err), err?.message ?? "Request failed");
}

/** Throws a BackendError unless the result succeeded. */
export function must<T>(res: { data: T | null; error: PostgrestError | null }): T {
  if (res.error) fail(res.error);
  return res.data as T;
}

/** Cheap, read-only probe: does the reviewed schema exist on the backend? */
export async function probeSchema(): Promise<"ready" | Failure> {
  const { error } = await db.from("workspaces").select("id").limit(1);
  if (!error) return "ready";
  return classify(error);
}

export type Workspace = { id: string; kind: "personal" | "organisation"; name: string };
export type Member = { user_id: string; role: "owner" | "admin" | "member"; created_at: string };
export type Enquiry = {
  id: string; workspace_id: string; title: string | null; visibility: "private" | "shared";
  created_by: string; custodian_id: string | null; current_fact_version: number; updated_at: string;
};
export type FactVersion = {
  version: number; facts: Record<string, unknown>; intents: string[]; practice_areas: string[];
  author_id: string | null; created_at: string;
};
