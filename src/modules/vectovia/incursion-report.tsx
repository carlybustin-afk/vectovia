// Incursion report (PDF or Word): the whole response on one document, fingerprinted and logged.
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { ErrorState } from "@/components/app-shell";
import { useSession } from "@/lib/session";
import { useWorkspace, wsKey } from "@/lib/workspace";
import { loadHistory, newId } from "./api";
import { loadAnalytics, ukDate } from "./analytics";
import { FORMAT, logAndDownload, safeName } from "./export-doc";
import type { Incursion, IncursionData } from "./incursions";
import { incursionReport, type ReportContext } from "./reports";
import { useAssessments, useLists, useProgrammes, useSites, useTraps } from "./ui";

export function IncursionReport({ ctx, i }: { ctx: { ws: string; data: IncursionData }; i: Incursion }) {
  const qc = useQueryClient();
  const { session } = useSession();
  const { current } = useWorkspace();
  const ws = ctx.ws;
  const data = useQuery({ queryKey: wsKey(ws, "vv", "analytics"), queryFn: () => loadAnalytics(ws), staleTime: 60_000 });
  const sites = useSites(ws), traps = useTraps(ws), lists = useLists(ws), programmes = useProgrammes(ws), assessments = useAssessments(ws);
  const [done, setDone] = useState<string | null>(null);
  const ready = [data, sites, traps, lists, programmes, assessments].every((q) => q.data);
  const make = useMutation({
    mutationFn: async (kind: "pdf" | "docx") => {
      const today = ukDate(new Date().toISOString());
      const rc: ReportContext = {
        council: current?.name ?? "Council", me: { id: session?.user.id, email: session?.user.email }, reportId: newId(), generatedAt: new Date(),
        data: data.data!, sites: sites.data!, traps: traps.data!, programmes: programmes.data!, lists: lists.data!, assessments: assessments.data!,
        incursions: ctx.data, filter: { from: today, to: today, sites: null }, programmeId: "", siteId: "",
      };
      const history = await loadHistory("incursion", i.id);
      const { doc, counts } = incursionReport(rc, i, history);
      const { toPdf, toDocx } = await import("./export-writers");
      const blob = kind === "pdf" ? await toPdf(doc) : await toDocx(doc);
      const name = `vectovia-${safeName(i.reference)}-incursion-report-${today}.${kind}`;
      const sha = await logAndDownload({ id: rc.reportId, ws, kind: kind === "pdf" ? "incursion_pdf" : "incursion_docx", scope: { incursion_id: i.id, reference: i.reference },
        counts, fileName: name, blob, format: FORMAT.incursion });
      return `${name} · fingerprint ${sha.slice(0, 12)}…`;
    },
    onSuccess: (m) => { setDone(m); qc.invalidateQueries({ queryKey: wsKey(ws, "vv", "exports") }); },
  });
  return (
    <div className="space-y-1">
      <div className="flex flex-wrap items-center gap-2 text-sm">
        <span className="text-muted-foreground">Incursion report:</span>
        <button type="button" disabled={!ready || make.isPending} onClick={() => make.mutate("pdf")} className="rounded-md border border-primary px-3 py-1 text-primary disabled:opacity-60">PDF</button>
        <button type="button" disabled={!ready || make.isPending} onClick={() => make.mutate("docx")} className="rounded-md border border-primary px-3 py-1 text-primary disabled:opacity-60">Word</button>
        {make.isPending ? <span role="status" className="text-xs text-muted-foreground">Preparing…</span> : null}
      </div>
      {done && !make.isPending && !make.isError ? <p role="status" className="text-xs text-primary">Downloaded and logged: {done}</p> : null}
      {make.isError ? <ErrorState error={make.error} /> : null}
    </div>
  );
}
