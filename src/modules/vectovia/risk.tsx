// Results, structured risk assessment and follow-up actions (V3).
// The officer decides the risk: they choose likelihood and consequence, the
// visible matrix shows the level, and they may set a different final level with
// a reason. First Line never calculates or suggests the risk from the data.
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useRef, useState } from "react";
import { ErrorState } from "@/components/app-shell";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import {
  consequenceLabels, day, idMethodLabels, levelLabels, likelihoodLabels, matrixLevel, newId, resultStatusLabels, riskFactors, riskRpc, run,
  unitLabels, when, who,
  type Action, type AssessmentVersion, type IdMethod, type Level, type Lists, type MemberRow, type ResultInput, type ResultStatus, type ResultVersion, type Unit,
} from "./api";
import { Field, History, StatusTag, selectClass } from "./ui";

const invalidate = (qc: ReturnType<typeof useQueryClient>, ws: string) => qc.invalidateQueries({ queryKey: ["ws", ws, "vv"] });

export const taxonName = (v: Pick<ResultVersion, "taxon_id" | "council_taxon_id">, lists: Lists) =>
  lists.taxa.find((t) => t.id === v.taxon_id)?.scientific_name ?? lists.councilTaxa.find((t) => t.id === v.council_taxon_id)?.scientific_name ?? null;

/** One line describing a result version: "3 females Aedes albopictus · Provisional". */
export function resultLine(v: ResultVersion, lists: Lists) {
  const name = taxonName(v, lists);
  const qty = v.quantity !== null && v.unit ? (v.unit === "presence" ? "present" : `${v.quantity} ${unitLabels[v.unit]}`) : null;
  return [qty, name].filter(Boolean).join(" ") || (v.status === "pending" ? "Awaiting identification" : "Nothing identified");
}

export function ResultForm({ ws, sampleId, lists, current, resultId, onDone }: {
  ws: string; sampleId: string; lists: Lists; current?: ResultVersion; resultId?: string; onDone: () => void;
}) {
  const qc = useQueryClient();
  const id = useRef(resultId ?? newId());
  const [v, setV] = useState<ResultInput>({
    status: current?.status ?? "confirmed",
    taxon: current?.taxon_id ? `s:${current.taxon_id}` : current?.council_taxon_id ? `c:${current.council_taxon_id}` : "",
    quantity: current?.quantity != null ? String(current.quantity) : "", unit: current?.unit ?? "individuals", method: current?.method ?? "morphology",
    identified_by: current?.identified_by ?? "", laboratory: current?.laboratory ?? "", lab_reference: current?.lab_reference ?? "",
    result_date: current?.result_date ?? new Date().toISOString().slice(0, 10), uncertainty: current?.uncertainty ?? "",
  });
  const [reason, setReason] = useState("");
  const save = useMutation({
    mutationFn: () => run(riskRpc.saveResult(id.current, sampleId, v, current ? reason : null)),
    onSuccess: () => { invalidate(qc, ws); onDone(); },
  });
  const needsTaxon = (v.status === "provisional" || v.status === "confirmed") && !v.taxon;
  const set = <K extends keyof ResultInput>(k: K, x: ResultInput[K]) => setV((s) => ({ ...s, [k]: x }));
  return (
    <form className="space-y-3 rounded-md border-2 border-accent bg-background p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <p className="text-sm font-semibold text-primary">{current ? "Correct this result (a new version; the earlier one is kept)" : "Add a result"}</p>
      <fieldset>
        <legend className="text-sm font-medium text-primary">Status</legend>
        <div className="mt-1 flex flex-wrap gap-2">
          {(Object.keys(resultStatusLabels) as ResultStatus[]).map((s) => (
            <button key={s} type="button" aria-pressed={v.status === s} onClick={() => set("status", s)}
              className={`rounded-md px-3 py-1.5 text-sm font-medium ${v.status === s ? "bg-primary text-primary-foreground" : "border border-border text-primary"}`}>{resultStatusLabels[s]}</button>
          ))}
        </div>
        <p className="mt-1 text-xs text-muted-foreground">Pending: sent for identification. Provisional: an early identification. Confirmed: final. Inconclusive: couldn't be identified.</p>
      </fieldset>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id="rf-t" label={v.status === "pending" ? "Species (if known)" : "Species"}>
          <select id="rf-t" className={selectClass} value={v.taxon} onChange={(e) => set("taxon", e.target.value)}>
            <option value="">{v.status === "pending" || v.status === "inconclusive" ? "Not identified" : "Choose a species"}</option>
            <optgroup label="Standard list">{lists.taxa.map((t) => <option key={t.id} value={`s:${t.id}`}>{t.scientific_name}{t.invasive ? " (invasive)" : ""}</option>)}</optgroup>
            {lists.councilTaxa.length ? <optgroup label="Your council's list">{lists.councilTaxa.filter((t) => t.active || `c:${t.id}` === v.taxon).map((t) => <option key={t.id} value={`c:${t.id}`}>{t.scientific_name}</option>)}</optgroup> : null}
          </select>
        </Field>
        <Field id="rf-q" label="Quantity"><Input id="rf-q" type="number" min={0} step="any" value={v.quantity} disabled={v.unit === "presence"} onChange={(e) => set("quantity", e.target.value)} /></Field>
        <Field id="rf-u" label="Unit">
          <select id="rf-u" className={selectClass} value={v.unit} onChange={(e) => set("unit", e.target.value as Unit)}>
            {(Object.keys(unitLabels) as Unit[]).map((u) => <option key={u} value={u}>{unitLabels[u]}</option>)}
          </select>
        </Field>
        <Field id="rf-m" label="Identified by method">
          <select id="rf-m" className={selectClass} value={v.method} onChange={(e) => set("method", e.target.value as IdMethod)}>
            {(Object.keys(idMethodLabels) as IdMethod[]).map((m) => <option key={m} value={m}>{idMethodLabels[m]}</option>)}
          </select>
        </Field>
        <Field id="rf-who" label="Identified by (person)"><Input id="rf-who" maxLength={200} value={v.identified_by} onChange={(e) => set("identified_by", e.target.value)} /></Field>
        <Field id="rf-lab" label="Laboratory (if any)"><Input id="rf-lab" maxLength={200} value={v.laboratory} onChange={(e) => set("laboratory", e.target.value)} /></Field>
        <Field id="rf-ref" label="Lab reference"><Input id="rf-ref" maxLength={100} value={v.lab_reference} onChange={(e) => set("lab_reference", e.target.value)} /></Field>
        <Field id="rf-d" label="Result date"><Input id="rf-d" type="date" value={v.result_date} onChange={(e) => set("result_date", e.target.value)} /></Field>
      </div>
      <Field id="rf-un" label="Uncertainty or notes (optional)" hint="e.g. damaged specimens, needs molecular confirmation."><Input id="rf-un" maxLength={1000} value={v.uncertainty} onChange={(e) => set("uncertainty", e.target.value)} /></Field>
      {current ? <Field id="rf-r" label="Why are you changing it? (required)"><Input id="rf-r" maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. lab confirmed the identification" /></Field> : null}
      <p className="text-xs text-muted-foreground">Add lab reports as files on the sample.</p>
      {needsTaxon ? <p className="text-sm text-primary">A provisional or confirmed result needs a species.</p> : null}
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" disabled={save.isPending || needsTaxon || (!!current && reason.trim().length < 5)} className="rounded-md bg-signal-teal px-3 py-1.5 text-sm font-semibold text-deep-navy disabled:opacity-60">Save result</button>
        <button type="button" onClick={onDone} className="rounded-md border border-primary px-3 py-1.5 text-sm text-primary">Cancel</button>
      </div>
    </form>
  );
}

/** The visible matrix: likelihood down, consequence across; the chosen cell is outlined. Levels are labelled in words. */
export function RiskMatrix({ likelihood, consequence, onPick }: { likelihood: number; consequence: number; onPick?: (l: number, c: number) => void }) {
  const tone: Record<Level, string> = { low: "bg-secondary", medium: "bg-accent/20", high: "bg-accent/45", very_high: "bg-primary text-primary-foreground" };
  return (
    <div className="overflow-x-auto">
      <table className="border-separate border-spacing-1 text-[11px]">
        <caption className="mb-1 text-left text-xs text-muted-foreground">Risk matrix (default, 5 × 5). Likelihood down, consequence across.</caption>
        <thead><tr><th scope="col" className="sr-only">Likelihood</th>{[1, 2, 3, 4, 5].map((c) => <th key={c} scope="col" className="px-1 font-medium text-primary">{c} {consequenceLabels[c]}</th>)}</tr></thead>
        <tbody>
          {[5, 4, 3, 2, 1].map((l) => (
            <tr key={l}>
              <th scope="row" className="pr-1 text-right font-medium text-primary">{l} {likelihoodLabels[l]}</th>
              {[1, 2, 3, 4, 5].map((c) => {
                const lvl = matrixLevel(l, c), on = l === likelihood && c === consequence;
                return (
                  <td key={c}>
                    <button type="button" disabled={!onPick} aria-pressed={on} aria-label={`Likelihood ${l}, consequence ${c}: ${levelLabels[lvl]}`}
                      onClick={() => onPick?.(l, c)}
                      className={`h-9 w-20 rounded ${tone[lvl]} ${on ? "outline outline-3 outline-offset-1 outline-primary font-bold" : ""}`}>{levelLabels[lvl]}</button>
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function AssessmentForm({ ws, siteId, findingIds, current, assessmentId, onDone }: {
  ws: string; siteId: string; findingIds: string[]; current?: AssessmentVersion; assessmentId?: string; onDone: () => void;
}) {
  const qc = useQueryClient();
  const id = useRef(assessmentId ?? newId());
  const [l, setL] = useState(current?.likelihood ?? 0);
  const [c, setC] = useState(current?.consequence ?? 0);
  const matrix = l && c ? matrixLevel(l, c) : null;
  const [final, setFinal] = useState<Level | "">(current?.final_level ?? "");
  const [override, setOverride] = useState(current?.override_reason ?? "");
  const [factors, setFactors] = useState<string[]>(current?.factors ?? []);
  const [rationale, setRationale] = useState(current?.rationale ?? "");
  const [reason, setReason] = useState("");
  const finalLevel = (final || matrix) as Level | null;
  const save = useMutation({
    mutationFn: () => run(riskRpc.saveAssessment(id.current, siteId, current ? null : findingIds,
      { likelihood: l, consequence: c, final_level: finalLevel!, override_reason: override, factors, rationale }, current ? reason : null)),
    onSuccess: () => { invalidate(qc, ws); onDone(); },
  });
  const problems = [
    !matrix ? "Choose the likelihood and consequence on the matrix." : null,
    matrix && finalLevel !== matrix && override.trim().length < 5 ? "Say why the final level differs from the matrix." : null,
    rationale.trim().length < 10 ? "Write the rationale." : null,
    current && reason.trim().length < 5 ? "Say why you are revising it." : null,
  ].filter(Boolean) as string[];
  return (
    <form className="space-y-4 rounded-md border-2 border-accent bg-background p-4" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div>
        <p className="font-semibold text-primary">{current ? "Revise the risk assessment" : `Assess risk (${findingIds.length} finding${findingIds.length === 1 ? "" : "s"})`}</p>
        <p className="text-xs text-muted-foreground">Your professional judgement. First Line doesn't calculate or suggest the risk; the matrix only shows how your two choices combine.</p>
      </div>
      <RiskMatrix likelihood={l} consequence={c} onPick={(a, b) => { setL(a); setC(b); setFinal(""); }} />
      {matrix ? (
        <div className="grid gap-3 sm:grid-cols-2">
          <Field id="af-f" label="Final risk level" hint={`The matrix gives ${levelLabels[matrix]}. Change it only with a reason.`}>
            <select id="af-f" className={selectClass} value={finalLevel ?? ""} onChange={(e) => setFinal(e.target.value as Level)}>
              {(Object.keys(levelLabels) as Level[]).map((x) => <option key={x} value={x}>{levelLabels[x]}{x === matrix ? " (matrix)" : ""}</option>)}
            </select>
          </Field>
          {finalLevel !== matrix ? <Field id="af-o" label="Why is it different from the matrix?"><Input id="af-o" maxLength={1000} value={override} onChange={(e) => setOverride(e.target.value)} /></Field> : null}
        </div>
      ) : null}
      <fieldset>
        <legend className="text-sm font-medium text-primary">Factors you considered</legend>
        <div className="mt-1 grid gap-1 sm:grid-cols-2">
          {riskFactors.map(([k, label]) => (
            <label key={k} className="flex items-center gap-2 text-sm"><input type="checkbox" checked={factors.includes(k)}
              onChange={(e) => { const on = e.target.checked; setFactors((f) => (on ? [...f, k] : f.filter((x) => x !== k))); }} />{label}</label>
          ))}
        </div>
      </fieldset>
      <Field id="af-r" label="Rationale" hint="Why you reached this level: the evidence, the context, and what you weighed."><Textarea id="af-r" className="min-h-28" maxLength={4000} value={rationale} onChange={(e) => setRationale(e.target.value)} /></Field>
      {current ? <Field id="af-why" label="Why are you revising it? (required)"><Input id="af-why" maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. lab confirmed the species" /></Field> : null}
      {problems.length ? <ul className="list-disc pl-5 text-sm text-primary">{problems.map((p) => <li key={p}>{p}</li>)}</ul> : null}
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" disabled={save.isPending || problems.length > 0} className="rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy disabled:opacity-60">{current ? "Save new version" : "Record assessment"}</button>
        <button type="button" onClick={onDone} className="rounded-md border border-primary px-4 py-2 text-sm text-primary">Cancel</button>
      </div>
    </form>
  );
}

export function LevelTag({ level }: { level: Level }) {
  return <StatusTag strong={level === "high" || level === "very_high"}>{level === "very_high" ? "▲▲ " : level === "high" ? "▲ " : ""}{levelLabels[level]} risk</StatusTag>;
}

export function ActionForm({ ws, siteId, assessmentId, members, uid, onDone }: {
  ws: string; siteId: string; assessmentId: string | null; members: MemberRow[]; uid: string | undefined; onDone: () => void;
}) {
  const qc = useQueryClient();
  const id = useRef(newId());
  const [title, setTitle] = useState("");
  const [detail, setDetail] = useState("");
  const [owner, setOwner] = useState(uid ?? "");
  const [due, setDue] = useState("");
  const save = useMutation({
    mutationFn: () => run(riskRpc.saveAction(id.current, siteId, assessmentId, title, detail, owner || null, due || null)),
    onSuccess: () => { invalidate(qc, ws); onDone(); },
  });
  return (
    <form className="space-y-2 rounded-md bg-secondary p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-2 sm:grid-cols-[1fr_12rem_10rem]">
        <Field id="ac-t" label="Follow-up action"><Input id="ac-t" className="bg-background" maxLength={200} value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. Enhanced trapping within 200 m" /></Field>
        <Field id="ac-o" label="Owner">
          <select id="ac-o" className={selectClass} value={owner} onChange={(e) => setOwner(e.target.value)}>
            {members.map((m) => <option key={m.user_id} value={m.user_id}>{who(m.user_id, uid)}</option>)}
          </select>
        </Field>
        <Field id="ac-d" label="Due"><Input id="ac-d" type="date" className="bg-background" value={due} onChange={(e) => setDue(e.target.value)} /></Field>
      </div>
      <Field id="ac-x" label="Detail (optional)"><Input id="ac-x" className="bg-background" maxLength={2000} value={detail} onChange={(e) => setDetail(e.target.value)} /></Field>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" disabled={save.isPending || title.trim().length < 3} className="rounded-md bg-signal-teal px-3 py-1.5 text-sm font-semibold text-deep-navy disabled:opacity-60">Add action</button>
        <button type="button" onClick={onDone} className="rounded-md border border-primary px-3 py-1.5 text-sm text-primary">Cancel</button>
      </div>
    </form>
  );
}

export function ActionRow({ ws, a, uid, canManage, siteLabel }: { ws: string; a: Action; uid: string | undefined; canManage: boolean; siteLabel: string }) {
  const qc = useQueryClient();
  const [cancelling, setCancelling] = useState(false);
  const [note, setNote] = useState("");
  const act = useMutation({
    mutationFn: (x: { status: Action["status"]; note: string | null }) => run(riskRpc.actionStatus(a.id, x.status, x.note)),
    onSuccess: () => { invalidate(qc, ws); setCancelling(false); },
  });
  const canChange = canManage || a.owner_id === uid;
  const overdue = a.status === "open" && a.due_on && a.due_on < new Date().toISOString().slice(0, 10);
  return (
    <li className="space-y-1 px-3 py-2 text-sm">
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <StatusTag strong={a.status === "open"}>{a.status === "open" ? (overdue ? "▲ Overdue" : "Open") : a.status === "done" ? "Done" : "Cancelled"}</StatusTag>
        <span className="font-medium text-primary">{a.title}</span>
        <span className="text-xs text-muted-foreground">{siteLabel} · {who(a.owner_id, uid)}{a.due_on ? ` · due ${day(a.due_on)}` : ""}
          {a.completed_at ? ` · ${a.status === "done" ? "completed" : "cancelled"} ${when(a.completed_at)} by ${who(a.completed_by, uid)}` : ""}</span>
        {a.status === "open" && canChange && !cancelling ? (
          <span className="ml-auto flex gap-2">
            <button type="button" disabled={act.isPending} className="rounded-md border border-primary px-2 py-0.5 text-primary" onClick={() => act.mutate({ status: "done", note: null })}>Done</button>
            <button type="button" className="text-primary underline" onClick={() => setCancelling(true)}>Cancel</button>
          </span>
        ) : null}
      </div>
      {a.detail ? <p className="text-xs text-muted-foreground">{a.detail}</p> : null}
      {a.completion_note ? <p className="text-xs text-primary">Note: {a.completion_note}</p> : null}
      {cancelling ? (
        <span className="flex flex-wrap items-center gap-2">
          <Input aria-label="Why cancel?" className="h-8 w-64" value={note} onChange={(e) => setNote(e.target.value)} placeholder="Why cancel?" />
          <button type="button" disabled={note.trim().length < 5 || act.isPending} className="text-primary underline disabled:opacity-60" onClick={() => act.mutate({ status: "cancelled", note })}>Cancel action</button>
          <button type="button" className="text-primary underline" onClick={() => setCancelling(false)}>Keep</button>
        </span>
      ) : null}
      {act.isError ? <ErrorState error={act.error} /> : null}
      <History type="action" id={a.id} ws={ws} uid={uid} labels={{ owner_id: "owner", due_on: "due" }} />
    </li>
  );
}
