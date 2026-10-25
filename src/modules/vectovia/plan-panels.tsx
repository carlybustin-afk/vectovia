// Screens for design v2 stage 3: programme seasons, the site surveillance plan, the yearly site risk
// assessment, and template review for the content team. The database decides who may do what.
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRef, useState } from "react";
import { ErrorState, Loading } from "@/components/app-shell";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { wsKey } from "@/lib/workspace";
import { consequenceLabels, day, levelLabels, likelihoodLabels, matrixLevel, newId, run, when, who, type Level, type Site } from "./api";
import {
  daysIn, loadPlan, loadSeasons, loadSiteRisk, loadTemplates, mdLabel, monthOptions, planRpc,
  type PlanSection, type PlanVersion, type Season, type SiteRiskInput, type SiteRiskVersion, type TemplateVersion,
} from "./plans";
import { LevelTag, RiskMatrix } from "./risk";
import { Field, StatusTag, selectClass } from "./ui";

const btn = "rounded-md border border-primary px-3 py-1.5 text-sm font-medium text-primary disabled:opacity-60";
const primaryBtn = "rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy disabled:opacity-60";
const heading = "text-xs font-semibold uppercase tracking-wide text-accent";
const todayIso = () => new Date().toISOString().slice(0, 10);
const plusDays = (iso: string, n: number) => { const d = new Date(`${iso}T12:00:00Z`); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const plusYear = (iso: string) => { const d = new Date(`${iso}T12:00:00Z`); d.setUTCFullYear(d.getUTCFullYear() + 1); return d.toISOString().slice(0, 10); };

export const useSeasons = (ws: string) => useQuery({ queryKey: wsKey(ws, "vv", "seasons"), queryFn: () => loadSeasons(ws) });
export const useTemplates = () => useQuery({ queryKey: ["vv-templates"], queryFn: loadTemplates, staleTime: 60_000 });
function useRefresh(ws?: string) {
  const qc = useQueryClient();
  return () => { if (ws) void qc.invalidateQueries({ queryKey: ["ws", ws, "vv"] }); void qc.invalidateQueries({ queryKey: ["vv-templates"] }); };
}

// ---------- Seasons ---------------------------------------------------------------------------
export function SeasonsPanel({ ws, programme, canManage }: { ws: string; programme: string; canManage: boolean }) {
  const seasons = useSeasons(ws);
  const [open, setOpen] = useState<string | "new" | null>(null);
  if (!seasons.data) return null;
  const mine = seasons.data.filter((s) => s.programme_id === programme);
  return (
    <section className="space-y-2">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <p className={heading}>Seasons and check frequency</p>
        {canManage && open !== "new" ? <button type="button" className={btn} onClick={() => setOpen("new")}>Add a season</button> : null}
      </div>
      <p className="text-xs text-muted-foreground">
        {mine.length ? "Traps at this programme's sites are checked at the season's frequency. Outside every season no checks are due, so nothing shows as overdue."
          : "No seasons: each trap is checked at the interval set when it was deployed. Add seasons for, say, weekly checks in summer and none in winter."}
      </p>
      {open === "new" ? <SeasonForm ws={ws} programme={programme} onDone={() => setOpen(null)} /> : null}
      {mine.length ? (
        <ul className="space-y-1 text-sm">
          {mine.map((s) => (
            <li key={s.id} className="rounded-md border border-border p-2">
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <span className="text-primary"><span className="font-medium">{s.name}</span> · {mdLabel(s.starts_md)} to {mdLabel(s.ends_md)} · every {s.interval_days} day{s.interval_days === 1 ? "" : "s"}</span>
                {canManage && open !== s.id ? <button type="button" className="text-sm text-primary underline" onClick={() => setOpen(s.id)}>Change</button> : null}
              </div>
              {open === s.id ? <SeasonForm ws={ws} programme={programme} season={s} onDone={() => setOpen(null)} /> : null}
            </li>
          ))}
        </ul>
      ) : null}
    </section>
  );
}

function MonthDay({ id, label, value, onChange }: { id: string; label: string; value: string; onChange: (md: string) => void }) {
  const [mm, dd] = value.split("-") as [string, string];
  const days = daysIn(mm);
  return (
    <fieldset>
      <legend className="text-sm font-medium text-primary">{label}</legend>
      <div className="mt-1 flex gap-2">
        <label htmlFor={`${id}-d`} className="sr-only">Day</label>
        <select id={`${id}-d`} className={`${selectClass} w-20`} value={dd} onChange={(e) => onChange(`${mm}-${e.target.value}`)}>
          {Array.from({ length: days }, (_, i) => String(i + 1).padStart(2, "0")).map((d) => <option key={d} value={d}>{Number(d)}</option>)}
        </select>
        <label htmlFor={`${id}-m`} className="sr-only">Month</label>
        <select id={`${id}-m`} className={`${selectClass} w-36`} value={mm}
          onChange={(e) => { const m = e.target.value; onChange(`${m}-${String(Math.min(Number(dd), daysIn(m))).padStart(2, "0")}`); }}>
          {monthOptions.map((m) => <option key={m.value} value={m.value}>{m.label}</option>)}
        </select>
      </div>
    </fieldset>
  );
}

function SeasonForm({ ws, programme, season, onDone }: { ws: string; programme: string; season?: Season; onDone: () => void }) {
  const refresh = useRefresh(ws);
  const id = useRef(season?.id ?? newId());
  const [name, setName] = useState(season?.name ?? "");
  const [starts, setStarts] = useState(season?.starts_md ?? "06-01");
  const [ends, setEnds] = useState(season?.ends_md ?? "10-31");
  const [every, setEvery] = useState(String(season?.interval_days ?? 14));
  const [removing, setRemoving] = useState(false);
  const [why, setWhy] = useState("");
  const n = Number(every);
  const ok = name.trim().length >= 2 && Number.isInteger(n) && n >= 1 && n <= 60;
  const save = useMutation({ mutationFn: () => run(planRpc.saveSeason(id.current, programme, name, starts, ends, n)), onSuccess: () => { refresh(); onDone(); } });
  const remove = useMutation({ mutationFn: () => run(planRpc.removeSeason(id.current, why)), onSuccess: () => { refresh(); onDone(); } });
  return (
    <form className="mt-2 space-y-3 rounded-md border-t-2 border-accent bg-secondary p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-3 sm:grid-cols-2">
        <Field id={`sn-${id.current}`} label="Name"><Input id={`sn-${id.current}`} className="bg-background" maxLength={60} value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Active season" /></Field>
        <Field id={`se-${id.current}`} label="Check every (days)"><Input id={`se-${id.current}`} className="w-28 bg-background" inputMode="numeric" value={every} onChange={(e) => setEvery(e.target.value.replace(/\D/g, ""))} /></Field>
      </div>
      <div className="flex flex-wrap gap-6">
        <MonthDay id={`ss-${id.current}`} label="Starts" value={starts} onChange={setStarts} />
        <MonthDay id={`sf-${id.current}`} label="Ends" value={ends} onChange={setEnds} />
      </div>
      <p className="text-xs text-muted-foreground">Every year from {mdLabel(starts)} to {mdLabel(ends)}{starts > ends ? " (running over the new year)" : ""}. The first check of each season is due on its first day.</p>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex flex-wrap gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || !ok}>{save.isPending ? "Saving…" : season ? "Save season" : "Add season"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
        {season && !removing ? <button type="button" className="text-sm text-primary underline" onClick={() => setRemoving(true)}>Remove this season</button> : null}
      </div>
      {removing ? (
        <div className="flex flex-wrap items-end gap-2 rounded-md border border-border bg-background p-2">
          <Field id={`sw-${id.current}`} label="Why are you removing it? (required)"><Input id={`sw-${id.current}`} className="w-full max-w-sm" maxLength={500} value={why} onChange={(e) => setWhy(e.target.value)} /></Field>
          <button type="button" className={btn} disabled={remove.isPending || why.trim().length < 5} onClick={() => remove.mutate()}>Remove season</button>
          {remove.isError ? <ErrorState error={remove.error} /> : null}
        </div>
      ) : null}
    </form>
  );
}

// ---------- Surveillance plan ------------------------------------------------------------------
export function PlanPanel({ ws, site, canManage, uid }: { ws: string; site: Site; canManage: boolean; uid: string | undefined }) {
  const data = useQuery({ queryKey: wsKey(ws, "vv", "plan", site.id), queryFn: () => loadPlan(ws, site.id) });
  const templates = useTemplates();
  const [editing, setEditing] = useState(false);
  const [shown, setShown] = useState<number | null>(null);
  if (data.isPending) return <Loading what="Loading the surveillance plan" />;
  if (data.isError) return <ErrorState error={data.error} />;
  const { plan, versions, activity } = data.data;
  const latest = versions[0];
  const approved = versions.find((v) => v.approved_at);
  const template = templates.data?.versions.find((v) => v.id === plan?.template_version_id);
  const view = versions.find((v) => v.version === shown) ?? approved ?? latest;
  return (
    <section className="space-y-2">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <p className={heading}>Surveillance plan</p>
        {canManage && !editing ? <button type="button" className={btn} onClick={() => setEditing(true)}>{plan ? "Write a new version" : "Start the plan"}</button> : null}
      </div>
      {editing ? <PlanForm ws={ws} site={site} planId={plan?.id} latest={latest} templateVersion={template} onDone={() => setEditing(false)} /> : null}
      {!plan ? <p className="text-sm text-muted-foreground">No surveillance plan yet.</p> : (
        <>
          <p className="text-sm text-primary">
            {approved ? <>Version {approved.version} approved {when(approved.approved_at)} · review by {day(approved.review_by)}</> : "Not approved yet"}
            {latest && latest !== approved ? ` · version ${latest.version} is a draft` : ""}
            {template ? <span className="text-muted-foreground"> · from the national template, version {template.version}</span> : null}
          </p>
          {canManage && latest && !latest.approved_at ? <ApproveForm ws={ws} planId={plan.id} version={latest.version} /> : null}
          {versions.length > 1 ? (
            <div className="flex flex-wrap gap-2 text-xs">
              {versions.map((v) => <button key={v.id} type="button" aria-pressed={view?.id === v.id} onClick={() => setShown(v.version)}
                className={`rounded border px-2 py-0.5 ${view?.id === v.id ? "border-primary text-primary" : "border-border text-muted-foreground"}`}>Version {v.version}{v.approved_at ? " · approved" : " · draft"}</button>)}
            </div>
          ) : null}
          {view ? <PlanView v={view} uid={uid} /> : null}
          <PlanActivityPanel ws={ws} planId={plan.id} activity={activity} canManage={canManage} uid={uid} />
        </>
      )}
    </section>
  );
}

function PlanView({ v, uid }: { v: PlanVersion; uid: string | undefined }) {
  return (
    <details className="rounded-md border border-border p-2 text-sm">
      <summary className="cursor-pointer font-medium text-primary">{v.title} (version {v.version})</summary>
      <div className="mt-2 space-y-2">
        {v.sections.map((s) => (
          <div key={s.key}><p className="font-medium text-primary">{s.title}</p><p className="whitespace-pre-wrap text-primary">{s.text || <span className="text-muted-foreground">Not written yet.</span>}</p></div>
        ))}
        <p className="text-xs text-muted-foreground">Written by {who(v.author_id, uid)} ({v.author_role}) · {when(v.recorded_at)}{v.reason ? ` · why: ${v.reason}` : ""}</p>
      </div>
    </details>
  );
}

function PlanForm({ ws, site, planId, latest, templateVersion, onDone }: {
  ws: string; site: Site; planId: string | undefined; latest: PlanVersion | undefined; templateVersion: TemplateVersion | undefined; onDone: () => void;
}) {
  const refresh = useRefresh(ws);
  const templates = useTemplates();
  const ids = useRef({ plan: planId ?? newId(), version: newId() });
  const published = templates.data?.versions.filter((v) => v.status === "published" && templates.data.templates.find((t) => t.id === v.template_id)?.kind === "surveillance_plan") ?? [];
  const [tplId, setTplId] = useState<string>(templateVersion?.id ?? "");
  const tpl = templateVersion ?? published.find((v) => v.id === tplId);
  const start = (): PlanSection[] => latest?.sections ?? (tpl ? tpl.sections.map((s) => ({ key: s.key, title: s.title, text: "" })) : [{ key: "plan", title: "Plan", text: "" }]);
  const [title, setTitle] = useState(latest?.title ?? `${site.name}: surveillance plan`);
  const [sections, setSections] = useState<PlanSection[]>(start);
  const [reason, setReason] = useState("");
  const save = useMutation({ mutationFn: () => run(planRpc.savePlan(ids.current.version, ids.current.plan, site.id, planId ? null : (tpl?.id ?? null), title, sections, reason)),
    onSuccess: () => { refresh(); onDone(); } });
  const guidance = (key: string) => tpl?.sections.find((s) => s.key === key);
  return (
    <form className="space-y-3 rounded-md border-t-2 border-accent bg-secondary p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      {!planId ? (
        <Field id="pf-tpl" label="Start from a national template" hint={published.length ? "Recommended: the template lists what the plan must cover." : "No template has been published yet; you can write the plan in your own sections."}>
          <select id="pf-tpl" className={selectClass} value={tplId} disabled={!published.length}
            onChange={(e) => { const id = e.target.value; setTplId(id); const t = published.find((v) => v.id === id);
              setSections(t ? t.sections.map((s) => ({ key: s.key, title: s.title, text: "" })) : [{ key: "plan", title: "Plan", text: "" }]); }}>
            <option value="">No template</option>
            {published.map((v) => <option key={v.id} value={v.id}>{templates.data!.templates.find((t) => t.id === v.template_id)?.name} (version {v.version})</option>)}
          </select>
        </Field>
      ) : null}
      <Field id="pf-title" label="Title"><Input id="pf-title" className="bg-background" maxLength={200} value={title} onChange={(e) => setTitle(e.target.value)} /></Field>
      {sections.map((s, i) => {
        const g = guidance(s.key);
        return (
          <Field key={s.key} id={`pf-${s.key}`} label={`${s.title}${g?.required ? " (required to approve)" : ""}`} hint={g?.guidance}>
            <Textarea id={`pf-${s.key}`} className="min-h-24 bg-background" maxLength={20000} value={s.text}
              onChange={(e) => setSections((x) => x.map((y, j) => (j === i ? { ...y, text: e.target.value } : y)))} />
          </Field>
        );
      })}
      {latest ? <Field id="pf-why" label="What has changed? (required)"><Input id="pf-why" className="bg-background" maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. yearly review; new freight area added" /></Field> : null}
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || title.trim().length < 3 || (!!latest && reason.trim().length < 5)}>{save.isPending ? "Saving…" : latest ? `Save as version ${latest.version + 1}` : "Save the first draft"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
      </div>
      <p className="text-xs text-muted-foreground">Each save is a new version; earlier versions are kept. A manager then approves it with a review date.</p>
    </form>
  );
}

function ApproveForm({ ws, planId, version }: { ws: string; planId: string; version: number }) {
  const refresh = useRefresh(ws);
  const [reviewBy, setReviewBy] = useState(plusYear(todayIso()));
  const approve = useMutation({ mutationFn: () => run(planRpc.approvePlan(planId, version, reviewBy)), onSuccess: refresh });
  return (
    <div className="flex flex-wrap items-end gap-2 rounded-md border border-accent bg-secondary p-2 text-sm">
      <Field id={`ap-${planId}`} label={`Approve version ${version}: review by`}>
        <Input id={`ap-${planId}`} type="date" className="w-48 bg-background" min={plusDays(todayIso(), 1)} value={reviewBy} onChange={(e) => setReviewBy(e.target.value)} />
      </Field>
      <button type="button" className={primaryBtn} disabled={approve.isPending || !reviewBy} onClick={() => approve.mutate()}>{approve.isPending ? "Approving…" : "Approve"}</button>
      {approve.isError ? <ErrorState error={approve.error} /> : null}
    </div>
  );
}

function PlanActivityPanel({ ws, planId, activity, canManage, uid }: { ws: string; planId: string; activity: { id: string; kind: "review" | "exercise"; occurred_on: string; note: string; recorded_by: string }[]; canManage: boolean; uid: string | undefined }) {
  const refresh = useRefresh(ws);
  const id = useRef(newId());
  const [open, setOpen] = useState(false);
  const [kind, setKind] = useState<"review" | "exercise">("exercise");
  const [on, setOn] = useState(todayIso());
  const [note, setNote] = useState("");
  const save = useMutation({ mutationFn: () => run(planRpc.recordActivity(id.current, planId, kind, on, note)),
    onSuccess: () => { id.current = newId(); setNote(""); setOpen(false); refresh(); } });
  return (
    <div className="space-y-1 text-sm">
      <p className="font-medium text-primary">Reviews and exercises</p>
      {activity.length ? (
        <ul className="space-y-0.5 text-xs">
          {activity.map((a) => <li key={a.id} className="text-primary">{day(a.occurred_on)} · {a.kind === "exercise" ? "Exercise" : "Review"}: {a.note} <span className="text-muted-foreground">({who(a.recorded_by, uid)})</span></li>)}
        </ul>
      ) : <p className="text-xs text-muted-foreground">None recorded yet.</p>}
      {canManage ? (open ? (
        <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
          <Field id={`pa-k-${planId}`} label="What">
            <select id={`pa-k-${planId}`} className={`${selectClass} w-36`} value={kind} onChange={(e) => setKind(e.target.value as "review" | "exercise")}>
              <option value="exercise">Exercise</option><option value="review">Review</option>
            </select>
          </Field>
          <Field id={`pa-d-${planId}`} label="When"><Input id={`pa-d-${planId}`} type="date" max={todayIso()} className="w-44" value={on} onChange={(e) => setOn(e.target.value)} /></Field>
          <Field id={`pa-n-${planId}`} label="What happened (required)"><Input id={`pa-n-${planId}`} className="w-full max-w-md" maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. table-top exercise with UKHSA" /></Field>
          <button type="submit" className={btn} disabled={save.isPending || note.trim().length < 5}>Record</button>
          {save.isError ? <ErrorState error={save.error} /> : null}
        </form>
      ) : <button type="button" className="text-sm text-primary underline" onClick={() => setOpen(true)}>Record a review or exercise</button>) : null}
    </div>
  );
}

// ---------- Site risk assessment -----------------------------------------------------------------
export function SiteRiskPanel({ ws, site, canManage, uid }: { ws: string; site: Site; canManage: boolean; uid: string | undefined }) {
  const data = useQuery({ queryKey: wsKey(ws, "vv", "site-risk", site.id), queryFn: () => loadSiteRisk(ws, site.id) });
  const [editing, setEditing] = useState(false);
  if (data.isPending) return <Loading what="Loading the site risk assessment" />;
  if (data.isError) return <ErrorState error={data.error} />;
  const { risk, versions } = data.data;
  const cur = versions[0];
  const today = todayIso();
  const state = !cur ? "none" : cur.next_due < today ? "overdue" : cur.next_due <= plusDays(today, 30) ? "soon" : "current";
  return (
    <section className="space-y-2">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <p className={heading}>Site risk assessment (at least yearly)</p>
        {canManage && !editing ? <button type="button" className={btn} onClick={() => setEditing(true)}>{cur ? "Record a new assessment" : "Assess the site"}</button> : null}
      </div>
      {editing ? <SiteRiskForm ws={ws} site={site} riskId={risk?.id} current={cur} onDone={() => setEditing(false)} /> : null}
      {!cur ? <p className="text-sm text-muted-foreground">No site risk assessment yet.</p> : (
        <div className="space-y-1 text-sm">
          <div className="flex flex-wrap items-center gap-2">
            <LevelTag level={cur.final_level} />
            <span className="text-primary">Assessed {day(cur.assessed_on)} · next due {day(cur.next_due)}</span>
            {state === "overdue" ? <StatusTag strong>▲ Overdue</StatusTag> : state === "soon" ? <StatusTag strong>Due soon</StatusTag> : null}
          </div>
          <RiskDetail v={cur} uid={uid} />
          {versions.length > 1 ? (
            <details className="text-xs"><summary className="cursor-pointer text-primary underline">Earlier assessments ({versions.length - 1})</summary>
              <ul className="mt-1 space-y-1">{versions.slice(1).map((v) => <li key={v.id}><RiskDetail v={v} uid={uid} /></li>)}</ul>
            </details>
          ) : null}
        </div>
      )}
    </section>
  );
}

function RiskDetail({ v, uid }: { v: SiteRiskVersion; uid: string | undefined }) {
  const rows: [string, string | null][] = [["High-risk vectors", v.vectors], ["Pathways and incoming risks", v.pathways], ["Habitats and breeding sites", v.habitats], ["Controls in place", v.controls]];
  return (
    <div className="rounded-md border border-border p-2 text-sm">
      <p className="text-primary">Version {v.version}: likelihood {v.likelihood} ({likelihoodLabels[v.likelihood]}) × consequence {v.consequence} ({consequenceLabels[v.consequence]}) = {levelLabels[v.matrix_level]}
        {v.final_level !== v.matrix_level ? `; set to ${levelLabels[v.final_level]} because ${v.override_reason}` : ""}</p>
      <dl className="mt-1 space-y-0.5">
        {rows.filter(([, t]) => t).map(([k, t]) => <div key={k} className="grid gap-1 sm:grid-cols-[12rem_1fr]"><dt className="text-muted-foreground">{k}</dt><dd className="text-primary">{t}</dd></div>)}
        <div className="grid gap-1 sm:grid-cols-[12rem_1fr]"><dt className="text-muted-foreground">Rationale</dt><dd className="text-primary">{v.rationale}</dd></div>
      </dl>
      <p className="mt-1 text-xs text-muted-foreground">By {who(v.author_id, uid)} ({v.author_role}) · {when(v.recorded_at)}{v.reason ? ` · why a new version: ${v.reason}` : ""}</p>
    </div>
  );
}

function SiteRiskForm({ ws, site, riskId, current, onDone }: { ws: string; site: Site; riskId: string | undefined; current: SiteRiskVersion | undefined; onDone: () => void }) {
  const refresh = useRefresh(ws);
  const ids = useRef({ risk: riskId ?? newId(), version: newId() });
  const today = todayIso();
  const [v, setV] = useState<SiteRiskInput>({
    assessed_on: today, next_due: plusYear(today), likelihood: current?.likelihood ?? 3, consequence: current?.consequence ?? 3,
    final_level: current?.final_level ?? matrixLevel(3, 3), override_reason: "", vectors: current?.vectors ?? "", pathways: current?.pathways ?? "",
    habitats: current?.habitats ?? "", controls: current?.controls ?? "", rationale: "", reason: "",
  });
  const set = <K extends keyof SiteRiskInput>(k: K, x: SiteRiskInput[K]) => setV((y) => ({ ...y, [k]: x }));
  const matrix = matrixLevel(v.likelihood, v.consequence);
  const maxDue = plusYear(v.assessed_on);
  const ok = v.rationale.trim().length >= 10 && (v.final_level === matrix || v.override_reason.trim().length >= 5) && (!current || v.reason.trim().length >= 5)
    && v.assessed_on <= today && v.next_due > v.assessed_on && v.next_due <= maxDue;
  const save = useMutation({ mutationFn: () => run(planRpc.saveSiteRisk(ids.current.version, ids.current.risk, site.id, v)), onSuccess: () => { refresh(); onDone(); } });
  return (
    <form className="space-y-3 rounded-md border-t-2 border-accent bg-secondary p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="flex flex-wrap gap-3">
        <Field id="sr-on" label="Assessed on"><Input id="sr-on" type="date" max={today} className="w-44 bg-background" value={v.assessed_on}
          onChange={(e) => { const d = e.target.value; setV((y) => ({ ...y, assessed_on: d, next_due: plusYear(d) })); }} /></Field>
        <Field id="sr-due" label="Next assessment due" hint="At most a year later."><Input id="sr-due" type="date" min={plusDays(v.assessed_on, 1)} max={maxDue} className="w-44 bg-background" value={v.next_due} onChange={(e) => set("next_due", e.target.value)} /></Field>
      </div>
      <div>
        <p className="text-sm font-medium text-primary">Likelihood and consequence</p>
        <p className="text-xs text-muted-foreground">Choose a cell. Likelihood: how likely invasive vectors are to arrive or establish here. Consequence: the public health impact if they do.</p>
        <RiskMatrix likelihood={v.likelihood} consequence={v.consequence} onPick={(l, c) => setV((y) => ({ ...y, likelihood: l, consequence: c, final_level: matrixLevel(l, c), override_reason: "" }))} />
      </div>
      <Field id="sr-final" label="Risk level" hint={`The matrix gives ${levelLabels[matrix]}. Change it only with a reason.`}>
        <select id="sr-final" className={`${selectClass} max-w-xs`} value={v.final_level} onChange={(e) => set("final_level", e.target.value as Level)}>
          {(Object.keys(levelLabels) as Level[]).map((x) => <option key={x} value={x}>{levelLabels[x]}{x === matrix ? " (matrix)" : ""}</option>)}
        </select>
      </Field>
      {v.final_level !== matrix ? <Field id="sr-or" label="Why a different level? (required)"><Input id="sr-or" className="bg-background" maxLength={1000} value={v.override_reason} onChange={(e) => set("override_reason", e.target.value)} /></Field> : null}
      <div className="grid gap-3 sm:grid-cols-2">
        <Field id="sr-vec" label="High-risk vectors"><Textarea id="sr-vec" className="bg-background" maxLength={2000} value={v.vectors} onChange={(e) => set("vectors", e.target.value)} placeholder="e.g. Aedes albopictus" /></Field>
        <Field id="sr-path" label="Pathways and incoming risks"><Textarea id="sr-path" className="bg-background" maxLength={2000} value={v.pathways} onChange={(e) => set("pathways", e.target.value)} placeholder="e.g. used tyres, freight from southern Europe" /></Field>
        <Field id="sr-hab" label="Habitats and breeding sites"><Textarea id="sr-hab" className="bg-background" maxLength={2000} value={v.habitats} onChange={(e) => set("habitats", e.target.value)} /></Field>
        <Field id="sr-ctl" label="Controls in place"><Textarea id="sr-ctl" className="bg-background" maxLength={2000} value={v.controls} onChange={(e) => set("controls", e.target.value)} /></Field>
      </div>
      <Field id="sr-rat" label="Rationale (required)" hint="Why you reached this level."><Textarea id="sr-rat" className="bg-background" maxLength={4000} value={v.rationale} onChange={(e) => set("rationale", e.target.value)} /></Field>
      {current ? <Field id="sr-why" label="Why a new assessment? (required)"><Input id="sr-why" className="bg-background" maxLength={500} value={v.reason} onChange={(e) => set("reason", e.target.value)} placeholder="e.g. yearly review" /></Field> : null}
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || !ok}>{save.isPending ? "Saving…" : "Save assessment"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
      </div>
      <p className="text-xs text-muted-foreground">Assessments are never changed; a new one becomes the current version and earlier ones stay in the history.</p>
    </form>
  );
}

// ---------- Template review (content team) ---------------------------------------------------------
export function TemplatesSection({ uid, reviewer, admin }: { uid: string | undefined; reviewer: boolean; admin: boolean }) {
  const t = useTemplates();
  if (!t.data || !t.data.versions.length) return null;
  return (
    <section aria-labelledby="tpl-h" className="space-y-3">
      <h2 id="tpl-h" className="text-lg font-semibold text-primary">Templates</h2>
      <p className="text-sm text-muted-foreground">National templates that sites start their surveillance plan from. Reviewed and published like the obligation sets.</p>
      {t.data.templates.map((tp) => {
        const v = t.data.versions.find((x) => x.template_id === tp.id);
        if (!v) return null;
        return (
          <div key={tp.id} className="rounded-md border border-border">
            <div className="flex flex-wrap items-baseline justify-between gap-2 border-b border-border bg-secondary/60 p-3">
              <p className="font-semibold text-primary">{tp.name}</p>
              <StatusTag strong={v.status === "published"}>Version {v.version}: {v.status.replace("_", " ")}</StatusTag>
            </div>
            <p className="px-3 pt-2 text-sm text-primary">{v.summary}</p>
            <ol className="list-decimal space-y-1 px-8 py-2 text-sm">
              {v.sections.map((s) => <li key={s.key} className="text-primary"><span className="font-medium">{s.title}</span>{s.required ? "" : <span className="text-muted-foreground"> (optional)</span>}{s.guidance ? <span className="block text-xs text-muted-foreground">{s.guidance}</span> : null}</li>)}
            </ol>
            <div className="border-t border-border p-3 text-xs text-muted-foreground"><TemplateActions v={v} uid={uid} reviewer={reviewer} admin={admin} /></div>
          </div>
        );
      })}
    </section>
  );
}

function TemplateActions({ v, uid, reviewer, admin }: { v: TemplateVersion; uid: string | undefined; reviewer: boolean; admin: boolean }) {
  const refresh = useRefresh();
  const [note, setNote] = useState("");
  const review = useMutation({ mutationFn: (ok: boolean) => run(planRpc.reviewTemplate(v.id, ok, note)), onSuccess: () => { setNote(""); refresh(); } });
  const publish = useMutation({ mutationFn: () => run(planRpc.publishTemplate(v.id)), onSuccess: refresh });
  if (v.status === "in_review" && reviewer) {
    if (v.loaded_by === uid) return <p className="text-primary">You loaded this version, so someone else must review it.</p>;
    return (
      <div className="space-y-2 text-sm">
        <Field id={`tr-${v.id}`} label="Review note (required)"><Textarea id={`tr-${v.id}`} className="bg-background" maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        {review.isError ? <ErrorState error={review.error} /> : null}
        <div className="flex gap-2">
          <button type="button" className={primaryBtn} disabled={review.isPending || note.trim().length < 10} onClick={() => review.mutate(true)}>Approve for publishing</button>
          <button type="button" className={btn} disabled={review.isPending || note.trim().length < 10} onClick={() => review.mutate(false)}>Send back</button>
        </div>
      </div>
    );
  }
  if (v.status === "reviewed" && admin) {
    if (v.reviewer_id === uid || v.loaded_by === uid) return <p className="text-primary">You reviewed or loaded this version, so a different content admin must publish it.</p>;
    return (
      <div className="space-y-2 text-sm">
        {publish.isError ? <ErrorState error={publish.error} /> : null}
        <button type="button" className={primaryBtn} disabled={publish.isPending} onClick={() => publish.mutate()}>{publish.isPending ? "Publishing…" : "Publish this version"}</button>
      </div>
    );
  }
  return v.reviewed_at ? <p>Reviewed {when(v.reviewed_at)}{v.review_note ? `: “${v.review_note}”` : ""}</p> : <p>Waiting for a reviewer.</p>;
}
