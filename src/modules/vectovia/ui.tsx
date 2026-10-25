// Shared Vectovia screen pieces: data hooks, the person's level, and small UI parts.
import { useQuery } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { canUse, levelIn, useMyProducts, type Level } from "@/lib/products";
import { useWorkspace, wsKey } from "@/lib/workspace";
import { loadActions, loadAssessments, loadFindings, loadResults, loadDeployments, loadHistory, loadLists, loadMembers, loadProgrammes, loadSamples, loadSchedule, loadSites, loadTeams, loadTraps, loadVisits, who, when, type VvEvent } from "./api";

export function useVv() {
  const { current } = useWorkspace();
  const ws = current!.id;
  const products = useMyProducts();
  const level: Level | null = levelIn(products.data, ws, "vectovia");
  return {
    ws, level,
    canView: canUse(level), canRecord: level === "field" || level === "manage", canManage: level === "manage",
  };
}

export const useProgrammes = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "programmes"), queryFn: () => loadProgrammes(ws) });
export const useSites = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "sites"), queryFn: () => loadSites(ws) });
export const useTraps = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "traps"), queryFn: () => loadTraps(ws) });
export const useLists = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "lists"), queryFn: () => loadLists(ws), staleTime: 60_000 });
export const useTeams = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "teams"), queryFn: () => loadTeams(ws), staleTime: 60_000 });

export function StatusTag({ children, strong }: { children: ReactNode; strong?: boolean }) {
  return <span className={`rounded border px-1.5 py-0.5 text-[11px] font-semibold uppercase tracking-wide ${strong ? "border-primary text-primary" : "border-border text-muted-foreground"}`}>{children}</span>;
}

/** Audit trail for a record: what changed, who, when (before → after). */
export function History({ type, id, ws, uid, labels = {} }: { type: "site" | "trap" | "programme" | "visit" | "deployment" | "result" | "assessment" | "action" | "incursion"; id: string; ws: string; uid: string | undefined; labels?: Record<string, string> }) {
  const q = useQuery({ queryKey: wsKey(ws, "vv", "history", type, id), queryFn: () => loadHistory(type, id) });
  if (!q.data?.length) return null;
  return (
    <details className="text-xs">
      <summary className="cursor-pointer text-primary underline">History ({q.data.length})</summary>
      <ol className="mt-2 space-y-1 border-l-2 border-accent pl-3">
        {q.data.map((e) => <li key={e.id}><HistoryLine e={e} uid={uid} labels={labels} /></li>)}
      </ol>
    </details>
  );
}

const kindLabels: Record<string, string> = {
  created: "Created", changed: "Changed", corrected: "Corrected", recorded: "Recorded", started: "Deployed", ended: "Deployment ended",
  deployed: "Deployed", deployment_ended: "Deployment ended", condition_reported: "Condition reported", collected: "Collected",
  opened: "Opened", notified: "Notification recorded", step: "Step", response_area: "Response area set", linked: "Findings or sites linked",
  stood_down: "Stood down", reopened: "Reopened",
};
const stepNames: Record<string, string> = {
  notify: "Notify", confirm_id: "Confirm identification", response_area: "Response area", enhanced_trapping: "Enhanced trapping",
  control: "Control measures", communications: "Communications", review: "Review", stand_down: "Stand-down",
};
const stepStates: Record<string, string> = { to_do: "to do", done: "done", skipped: "skipped" };
const show = (v: unknown) => (v === null || v === undefined || v === "" ? "—" : Array.isArray(v) ? `${v.length} selected` : String(v));
function HistoryLine({ e, uid, labels }: { e: VvEvent; uid: string | undefined; labels: Record<string, string> }) {
  const changes = e.kind === "changed" || e.kind === "corrected" ? Object.entries(e.detail).filter(([, v]) => v && typeof v === "object" && "from" in (v as object)) : [];
  return (
    <span>
      <span className="text-primary">{kindLabels[e.kind] ?? e.kind.replace(/_/g, " ")}</span>
      {e.kind === "step" ? `: ${stepNames[String(e.detail["step"])] ?? ""} ${stepStates[String(e.detail["from"])] ?? ""} → ${stepStates[String(e.detail["to"])] ?? ""}${e.detail["note"] ? ` (${String(e.detail["note"])})` : ""}` : ""}
      {e.detail["reason"] && e.kind !== "step" ? ` (reason: ${String(e.detail["reason"])})` : ""}
      {changes.length ? `: ${changes.map(([k, v]) => `${labels[k] ?? k.replace(/_/g, " ")} ${show((v as { from: unknown }).from)} → ${show((v as { to: unknown }).to)}`).join("; ")}` : ""}
      <span className="text-muted-foreground"> · {who(e.actor_id, uid)}{e.actor_role ? ` (${e.actor_role})` : ""} · {when(e.recorded_at)}</span>
    </span>
  );
}

export function Field({ id, label, hint, children }: { id: string; label: string; hint?: string | undefined; children: ReactNode }) {
  return (
    <div>
      <label htmlFor={id} className="text-sm font-medium text-primary">{label}</label>
      {hint ? <p className="text-xs text-muted-foreground">{hint}</p> : null}
      <div className="mt-1">{children}</div>
    </div>
  );
}

export const selectClass = "block h-9 w-full rounded-md border border-input bg-background px-2 text-sm";

export const useDeployments = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "deployments"), queryFn: () => loadDeployments(ws) });
export const useVisits = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "visits"), queryFn: () => loadVisits(ws) });
export const useSamples = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "samples"), queryFn: () => loadSamples(ws) });
export const useSchedule = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "schedule"), queryFn: () => loadSchedule(ws) });
export const useMembersList = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "members"), queryFn: () => loadMembers(ws), staleTime: 60_000 });

export const useResults = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "results"), queryFn: () => loadResults(ws) });
export const useAssessments = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "assessments"), queryFn: () => loadAssessments(ws) });
export const useActions = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "actions"), queryFn: () => loadActions(ws) });
export const useFindings = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "findings"), queryFn: () => loadFindings(ws) });
