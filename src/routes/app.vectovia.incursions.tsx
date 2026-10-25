import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRef, useState, type ReactNode } from "react";
import { z } from "zod";
import { AppShell, EmptyState, ErrorState, Loading, StateMessage, appHead } from "@/components/app-shell";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { useSession } from "@/lib/session";
import { wsKey } from "@/lib/workspace";
import { day, newId, resultStatusLabels, run, when, who, type Lists, type MemberRow, type Result, type ResultVersion, type Site } from "@/modules/vectovia/api";
import {
  canRun, incRpc, incursionStatusLabels, loadIncursions, localToIso, notifyKindLabels, notifyMethodLabels, nowLocal, radiusLabel, steps,
  type Contact, type Incursion, type IncursionData, type IncursionStatus, type NotifyKind, type NotifyMethod, type Step, type StepKey,
} from "@/modules/vectovia/incursions";
import { SurveillanceMap } from "@/modules/vectovia/map";
import { ActionRow, resultLine } from "@/modules/vectovia/risk";
import { LinksPanel } from "@/modules/vectovia/links";
import { IncursionReport } from "@/modules/vectovia/incursion-report";
import { Field, History, StatusTag, selectClass, useLists, useMembersList, useResults, useSites, useVv } from "@/modules/vectovia/ui";

const search = z.object({
  id: z.string().uuid().optional(),
  site: z.string().uuid().optional(),
  findings: z.string().regex(/^[0-9a-f-]{36}(,[0-9a-f-]{36})*$/).optional(),
});

export const Route = createFileRoute("/app/vectovia/incursions")({
  validateSearch: (s) => search.parse(s),
  head: () => appHead("Incursions · Vectovia", "Incursion management: guided response, response area, notifications and stand-down."),
  component: IncursionsPage,
});

function IncursionsPage() {
  return (
    <AppShell product="vectovia" section="vectovia" title="Incursions"
      intro="From a suspected detection of an invasive species, through the response, to stand-down. Each step is recorded with who did what and when. You decide every status change; First Line never sends notifications, it records them.">
      <Incursions />
    </AppShell>
  );
}

const btn = "rounded-md bg-signal-teal px-3 py-1.5 text-sm font-semibold text-deep-navy disabled:opacity-60";
const btn2 = "rounded-md border border-primary px-3 py-1.5 text-sm text-primary disabled:opacity-60";
const useInvalidate = (ws: string) => { const qc = useQueryClient(); return () => qc.invalidateQueries({ queryKey: ["ws", ws, "vv"] }); };

type Ctx = { ws: string; uid: string | undefined; canManage: boolean; canRecord: boolean; sites: Site[]; lists: Lists; members: MemberRow[];
  results: { results: Result[]; versions: ResultVersion[] }; data: IncursionData };

function Incursions() {
  const { session } = useSession();
  const uid = session?.user.id;
  const { ws, canManage, canRecord } = useVv();
  const s = Route.useSearch();
  const inc = useQuery({ queryKey: wsKey(ws, "vv", "incursions"), queryFn: () => loadIncursions(ws) });
  const sites = useSites(ws), lists = useLists(ws), members = useMembersList(ws), results = useResults(ws);
  const all = [inc, sites, lists, members, results];
  if (all.some((q) => q.isPending)) return <Loading what="Loading incursions" />;
  const err = all.find((q) => q.isError)?.error;
  if (err) return <ErrorState error={err} />;
  if (inc.data === null) return <StateMessage title="Incursion management isn't switched on yet">Once the incursion update is applied, incursions appear here.</StateMessage>;
  const ctx: Ctx = { ws, uid, canManage, canRecord, sites: sites.data!, lists: lists.data!, members: members.data!, results: results.data!, data: inc.data! };
  const chosen = s.id ? ctx.data.incursions.find((i) => i.id === s.id) : undefined;
  if (s.id && !chosen) return <EmptyState title="Incursion not found">It may not exist, or you may not have access to its site. <Link to="/app/vectovia/incursions" className="underline">All incursions</Link></EmptyState>;
  return chosen ? <Detail ctx={ctx} i={chosen} /> : <List ctx={ctx} openSite={s.site} openFindings={s.findings?.split(",") ?? []} />;
}

// ---------- helpers ----------------------------------------------------------------------------
const siteLabel = (ctx: Ctx, id: string) => { const x = ctx.sites.find((s) => s.id === id); return x ? `${x.reference} · ${x.name}` : "Site"; };
const species = (ctx: Ctx, i: Pick<Incursion, "taxon_id" | "council_taxon_id">) =>
  ctx.lists.taxa.find((t) => t.id === i.taxon_id)?.scientific_name ?? ctx.lists.councilTaxa.find((t) => t.id === i.council_taxon_id)?.scientific_name ?? null;
const current = (ctx: Ctx, resultId: string) => {
  const r = ctx.results.results.find((x) => x.id === resultId);
  return r ? ctx.results.versions.find((v) => v.result_id === r.id && v.version === r.current_version) : undefined;
};
/** Provisional or confirmed findings, which can start or join an incursion. */
const findingsAt = (ctx: Ctx, site?: string) => ctx.results.results.filter((r) => (!site || r.site_id === site) && ["provisional", "confirmed"].includes(current(ctx, r.id)?.status ?? ""));
const stepsOf = (ctx: Ctx, id: string) => ctx.data.steps.filter((s) => s.incursion_id === id);

// ---------- list -------------------------------------------------------------------------------
function List({ ctx, openSite, openFindings }: { ctx: Ctx; openSite: string | undefined; openFindings: string[] }) {
  const [opening, setOpening] = useState(!!openSite);
  const [show, setShow] = useState<"active" | "all">("active");
  const nav = useNavigate();
  const shown = ctx.data.incursions.filter((i) => show === "all" || i.status !== "stood_down");
  const active = ctx.data.incursions.filter((i) => i.status !== "stood_down");
  const points = active.map((i) => { const s = ctx.sites.find((x) => x.id === i.site_id); return s?.latitude != null && s.longitude != null ? { id: i.id, lat: s.latitude, lon: s.longitude, label: `${i.reference}: ${i.title}` } : null; })
    .filter((p): p is NonNullable<typeof p> => !!p);
  const circles = active.filter((i) => i.response_area).map((i) => ({ id: i.id, lat: i.response_area!.lat, lon: i.response_area!.lon, radius_m: i.response_area!.radius_m, label: `${i.reference} response area` }));
  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div role="group" aria-label="Which incursions" className="flex gap-1">
          {(["active", "all"] as const).map((k) => (
            <button key={k} type="button" aria-pressed={show === k} onClick={() => setShow(k)}
              className={`h-9 rounded-md px-3 text-sm font-medium ${show === k ? "bg-primary text-primary-foreground" : "border border-border text-primary"}`}>
              {k === "active" ? `Active (${active.length})` : `All (${ctx.data.incursions.length})`}
            </button>
          ))}
        </div>
        {ctx.canManage && !opening ? <button type="button" className={btn} onClick={() => setOpening(true)}>Open an incursion</button> : null}
      </div>
      {opening ? <OpenForm ctx={ctx} site={openSite} findings={openFindings} onCancel={() => setOpening(false)}
        onDone={(id) => { setOpening(false); void nav({ to: "/app/vectovia/incursions", search: { id } }); }} /> : null}
      {points.length || circles.length ? <SurveillanceMap points={points} circles={circles} label="Map of active incursions and response areas" height={300}
        onSelect={(id) => void nav({ to: "/app/vectovia/incursions", search: { id } })} /> : null}
      {shown.length === 0 ? (
        <EmptyState title={ctx.data.incursions.length ? "No active incursions" : "No incursions yet"}>
          {ctx.canManage ? "Open one from a provisional or confirmed finding, here or from Risk & actions." : "A Vectovia manager opens incursions from findings."}
        </EmptyState>
      ) : (
        <ul className="divide-y divide-border rounded-md border border-border">
          {shown.map((i) => {
            const st = stepsOf(ctx, i.id);
            const done = st.filter((x) => x.status !== "to_do").length;
            return (
              <li key={i.id}>
                <Link to="/app/vectovia/incursions" search={{ id: i.id }} className="flex flex-wrap items-baseline gap-x-3 gap-y-1 px-3 py-2.5 hover:bg-secondary/60">
                  <span className="font-semibold text-primary">{i.reference}</span>
                  <StatusTag strong={i.status !== "stood_down"}>{incursionStatusLabels[i.status]}</StatusTag>
                  <span className="text-primary">{i.title}</span>
                  <span className="text-xs text-muted-foreground">
                    {[species(ctx, i), siteLabel(ctx, i.site_id), `lead ${who(i.lead_officer_id, ctx.uid)}`, `opened ${when(i.opened_at)}`, `${done} of ${st.length} steps`].filter(Boolean).join(" · ")}
                  </span>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

function OpenForm({ ctx, site: site0, findings: f0, onCancel, onDone }: { ctx: Ctx; site: string | undefined; findings: string[]; onCancel: () => void; onDone: (id: string) => void }) {
  const invalidate = useInvalidate(ctx.ws);
  const id = useRef(newId());
  const withFindings = [...new Set(findingsAt(ctx).map((r) => r.site_id))];
  const [site, setSite] = useState(site0 ?? withFindings[0] ?? "");
  const [picked, setPicked] = useState<string[]>(f0);
  const here = findingsAt(ctx, site);
  const first = current(ctx, picked[0] ?? here[0]?.id ?? "");
  const [taxon, setTaxon] = useState(first?.taxon_id ? `s:${first.taxon_id}` : first?.council_taxon_id ? `c:${first.council_taxon_id}` : "");
  const [title, setTitle] = useState("");
  const [lead, setLead] = useState(ctx.uid ?? "");
  const [status, setStatus] = useState<"suspected" | "confirmed">("suspected");
  const siteName = ctx.sites.find((s) => s.id === site)?.name ?? "";
  const speciesName = taxon.startsWith("s:") ? ctx.lists.taxa.find((t) => t.id === taxon.slice(2))?.scientific_name : ctx.lists.councilTaxa.find((t) => t.id === taxon.slice(2))?.scientific_name;
  const suggested = [speciesName, siteName && `at ${siteName}`].filter(Boolean).join(" ");
  const save = useMutation({
    mutationFn: async () => {
      const chosen = picked.filter((p) => here.some((r) => r.id === p));
      await run(incRpc.open(id.current, site, chosen, (title || suggested).trim(), taxon.startsWith("s:") ? taxon.slice(2) : null,
        taxon.startsWith("c:") ? taxon.slice(2) : null, lead || null, status));
      return id.current;
    },
    onSuccess: (x) => { invalidate(); onDone(x); },
  });
  const chosen = picked.filter((p) => here.some((r) => r.id === p));
  return (
    <form className="space-y-3 rounded-md border-t-2 border-accent bg-secondary p-4 text-sm" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <p className="font-semibold text-primary">Open an incursion</p>
      {withFindings.length === 0 ? <p className="text-muted-foreground">There are no provisional or confirmed findings yet. Record one on the <Link to="/app/vectovia/results" className="underline">Results</Link> page first.</p> : (
        <>
          <Field id="of-site" label="Site where it was found">
            <select id="of-site" className={selectClass} value={site} onChange={(e) => { setSite(e.target.value); setPicked([]); }}>
              {withFindings.map((s) => <option key={s} value={s}>{siteLabel(ctx, s)}</option>)}
            </select>
          </Field>
          <fieldset className="space-y-1">
            <legend className="font-medium text-primary">Findings this incursion is about</legend>
            {here.map((r) => { const v = current(ctx, r.id)!; return (
              <label key={r.id} className="flex items-center gap-2">
                <input type="checkbox" checked={picked.includes(r.id)} onChange={(e) => { const on = e.target.checked; setPicked((p) => (on ? [...p, r.id] : p.filter((x) => x !== r.id))); }} />
                <StatusTag strong>{resultStatusLabels[v.status]}</StatusTag> {resultLine(v, ctx.lists)}{v.result_date ? <span className="text-xs text-muted-foreground"> · {day(v.result_date)}</span> : null}
              </label>
            ); })}
          </fieldset>
          <div className="grid gap-3 sm:grid-cols-2">
            <Field id="of-sp" label="Species">
              <select id="of-sp" className={selectClass} value={taxon} onChange={(e) => setTaxon(e.target.value)}>
                <option value="">Not known yet</option>
                <optgroup label="Standard list">{ctx.lists.taxa.map((t) => <option key={t.id} value={`s:${t.id}`}>{t.scientific_name}{t.invasive ? " (invasive)" : ""}</option>)}</optgroup>
                {ctx.lists.councilTaxa.length ? <optgroup label="Your council's list">{ctx.lists.councilTaxa.map((t) => <option key={t.id} value={`c:${t.id}`}>{t.scientific_name}</option>)}</optgroup> : null}
              </select>
            </Field>
            <Field id="of-t" label="Title" hint={suggested ? `Leave blank to use “${suggested}”.` : undefined}>
              <Input id="of-t" className="bg-background" maxLength={200} value={title} onChange={(e) => setTitle(e.target.value)} />
            </Field>
            <Field id="of-l" label="Lead officer" hint="Needs field officer or manager access to Vectovia.">
              <select id="of-l" className={selectClass} value={lead} onChange={(e) => setLead(e.target.value)}>
                <option value="">Not assigned yet</option>
                {ctx.members.map((m) => <option key={m.user_id} value={m.user_id}>{who(m.user_id, ctx.uid)}</option>)}
              </select>
            </Field>
            <Field id="of-s" label="Status">
              <select id="of-s" className={selectClass} value={status} onChange={(e) => setStatus(e.target.value as "suspected" | "confirmed")}>
                <option value="suspected">Suspected</option><option value="confirmed">Confirmed</option>
              </select>
            </Field>
          </div>
        </>
      )}
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={btn} disabled={save.isPending || !site || chosen.length === 0 || (title || suggested).trim().length < 3}>Open incursion</button>
        <button type="button" className={btn2} onClick={onCancel}>Cancel</button>
      </div>
    </form>
  );
}

// ---------- detail -----------------------------------------------------------------------------
function Detail({ ctx, i }: { ctx: Ctx; i: Incursion }) {
  const runIt = canRun(i, ctx.uid, ctx.canManage, ctx.canRecord) && i.status !== "stood_down";
  const [editing, setEditing] = useState(false);
  const st = stepsOf(ctx, i.id);
  const sp = species(ctx, i);
  return (
    <article className="space-y-6">
      <Link to="/app/vectovia/incursions" className="text-sm text-primary underline">← All incursions</Link>
      <header className="space-y-2">
        <div className="flex flex-wrap items-center gap-3">
          <h2 className="text-2xl font-bold tracking-tight text-primary">{i.reference}</h2>
          <StatusTag strong={i.status !== "stood_down"}>{incursionStatusLabels[i.status]}</StatusTag>
        </div>
        <p className="text-lg text-primary">{i.title}</p>
        <p className="text-sm text-muted-foreground">
          {sp ? <><em>{sp}</em> · </> : "Species not known yet · "}found at {siteLabel(ctx, i.site_id)} · lead officer {who(i.lead_officer_id, ctx.uid)} · opened {when(i.opened_at)} by {who(i.created_by, ctx.uid)}
          {i.taxon_id ? <> · <Link to="/app/vectovia/library" search={{ kind: "species", id: i.taxon_id }} className="text-primary underline">Library page</Link></> : null}
        </p>
        {ctx.canManage && i.status !== "stood_down" && !editing ? <button type="button" className={btn2} onClick={() => setEditing(true)}>Change details or status</button> : null}
        {editing ? <EditForm ctx={ctx} i={i} onDone={() => setEditing(false)} /> : null}
        {!runIt && i.status !== "stood_down" ? <p className="text-xs text-muted-foreground">Only Vectovia managers and the lead officer can record the response.</p> : null}
        <IncursionReport ctx={ctx} i={i} />
        <LinksPanel ws={ctx.ws} recordType="incursion" recordId={i.id} canManage={ctx.canManage} uid={ctx.uid} />
      </header>

      <section aria-labelledby="st-h" className="space-y-3">
        <h3 id="st-h" className="text-lg font-semibold text-primary">Response ({st.filter((x) => x.status !== "to_do").length} of {st.length} steps)</h3>
        <ol className="space-y-3">
          {steps.map((def, n) => {
            const s = st.find((x) => x.step_key === def.key);
            return s ? (
              <StepCard key={def.key} ctx={ctx} i={i} n={n + 1} def={def} s={s} runIt={runIt}>
                {def.key === "notify" ? <Notifications ctx={ctx} i={i} runIt={runIt} /> : null}
                {def.key === "response_area" ? <AreaEditor ctx={ctx} i={i} runIt={runIt} /> : null}
                {def.key === "enhanced_trapping" ? <LinkedSites ctx={ctx} i={i} runIt={runIt} /> : null}
                {def.key === "stand_down" ? <StandDown ctx={ctx} i={i} st={st} /> : null}
              </StepCard>
            ) : null;
          })}
        </ol>
      </section>

      <Findings ctx={ctx} i={i} runIt={runIt} />
      <History type="incursion" id={i.id} ws={ctx.ws} uid={ctx.uid}
        labels={{ lead_officer_id: "lead officer", taxon_id: "species", council_taxon_id: "council species", response_area: "response area" }} />
    </article>
  );
}

function EditForm({ ctx, i, onDone }: { ctx: Ctx; i: Incursion; onDone: () => void }) {
  const invalidate = useInvalidate(ctx.ws);
  const [title, setTitle] = useState(i.title);
  const [taxon, setTaxon] = useState(i.taxon_id ? `s:${i.taxon_id}` : i.council_taxon_id ? `c:${i.council_taxon_id}` : "");
  const [lead, setLead] = useState(i.lead_officer_id ?? "");
  const [status, setStatus] = useState<IncursionStatus>(i.status);
  const [reason, setReason] = useState("");
  const save = useMutation({
    mutationFn: () => run(incRpc.update(i.id, title, taxon.startsWith("s:") ? taxon.slice(2) : null, taxon.startsWith("c:") ? taxon.slice(2) : null, lead || null, status, reason)),
    onSuccess: () => { invalidate(); onDone(); },
  });
  const changed = status !== i.status;
  return (
    <form className="space-y-3 rounded-md border-t-2 border-accent bg-secondary p-4 text-sm" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-3 sm:grid-cols-2">
        <Field id="ef-t" label="Title"><Input id="ef-t" className="bg-background" maxLength={200} value={title} onChange={(e) => setTitle(e.target.value)} /></Field>
        <Field id="ef-sp" label="Species">
          <select id="ef-sp" className={selectClass} value={taxon} onChange={(e) => setTaxon(e.target.value)}>
            <option value="">Not known yet</option>
            <optgroup label="Standard list">{ctx.lists.taxa.map((t) => <option key={t.id} value={`s:${t.id}`}>{t.scientific_name}</option>)}</optgroup>
            {ctx.lists.councilTaxa.length ? <optgroup label="Your council's list">{ctx.lists.councilTaxa.map((t) => <option key={t.id} value={`c:${t.id}`}>{t.scientific_name}</option>)}</optgroup> : null}
          </select>
        </Field>
        <Field id="ef-l" label="Lead officer">
          <select id="ef-l" className={selectClass} value={lead} onChange={(e) => setLead(e.target.value)}>
            <option value="">Not assigned</option>
            {ctx.members.map((m) => <option key={m.user_id} value={m.user_id}>{who(m.user_id, ctx.uid)}</option>)}
          </select>
        </Field>
        <Field id="ef-s" label="Status" hint="Stand-down is recorded in its own step below.">
          <select id="ef-s" className={selectClass} value={status} onChange={(e) => setStatus(e.target.value as IncursionStatus)}>
            {(["suspected", "confirmed", "responding", "monitoring"] as const).map((k) => <option key={k} value={k}>{incursionStatusLabels[k]}</option>)}
          </select>
        </Field>
      </div>
      {changed ? <Field id="ef-r" label="Why is the status changing?"><Input id="ef-r" className="bg-background" maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} /></Field> : null}
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={btn} disabled={save.isPending || title.trim().length < 3 || (changed && reason.trim().length < 5)}>Save</button>
        <button type="button" className={btn2} onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}

function StepCard({ ctx, i, n, def, s, runIt, children }: {
  ctx: Ctx; i: Incursion; n: number; def: (typeof steps)[number]; s: Step; runIt: boolean; children?: ReactNode;
}) {
  const invalidate = useInvalidate(ctx.ws);
  const [mode, setMode] = useState<"idle" | "done" | "skip" | "reopen" | "task">("idle");
  const [note, setNote] = useState("");
  const set = useMutation({
    mutationFn: (status: Step["status"]) => run(incRpc.step(i.id, def.key, status, note)),
    onSuccess: () => { invalidate(); setMode("idle"); setNote(""); },
  });
  const tasks = ctx.data.tasks.filter((t) => t.incursion_id === i.id && t.step_key === def.key);
  const isStand = def.key === "stand_down";
  return (
    <li className={`space-y-2 rounded-md border p-3 text-sm ${s.status === "to_do" ? "border-border" : "border-border bg-secondary/40"}`}>
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <span className="font-semibold text-primary">{n}. {def.title}</span>
        <StatusTag strong={s.status === "to_do"}>{s.status === "to_do" ? "To do" : s.status === "done" ? "Done" : "Skipped"}</StatusTag>
        {s.decided_at ? <span className="text-xs text-muted-foreground">{who(s.decided_by, ctx.uid)} · {when(s.decided_at)}</span> : null}
        {runIt && !isStand && mode === "idle" ? (
          <span className="ml-auto flex flex-wrap gap-2">
            {s.status === "to_do" ? <>
              <button type="button" className={btn} onClick={() => setMode("done")}>Mark done</button>
              <button type="button" className="text-primary underline" onClick={() => setMode("skip")}>Skip</button>
            </> : <button type="button" className="text-primary underline" onClick={() => setMode("reopen")}>Reopen step</button>}
            <button type="button" className="text-primary underline" onClick={() => setMode("task")}>Add task</button>
          </span>
        ) : null}
      </div>
      <p className="text-muted-foreground">{def.guide}</p>
      {s.note && !isStand ? <p className="text-primary">Note: {s.note}</p> : null}
      {mode === "done" || mode === "skip" || mode === "reopen" ? (
        <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); set.mutate(mode === "done" ? "done" : mode === "skip" ? "skipped" : "to_do"); }}>
          <Field id={`sn-${def.key}`} label={mode === "done" ? "Note (optional)" : mode === "skip" ? "Why skip this step?" : "Why reopen it?"}>
            <Input id={`sn-${def.key}`} className="w-80 bg-background" maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
          <button type="submit" className={btn} disabled={set.isPending || (mode !== "done" && note.trim().length < 5)}>
            {mode === "done" ? "Mark done" : mode === "skip" ? "Skip step" : "Reopen step"}
          </button>
          <button type="button" className={btn2} onClick={() => { setMode("idle"); setNote(""); }}>Cancel</button>
        </form>
      ) : null}
      {set.isError ? <ErrorState error={set.error} /> : null}
      {mode === "task" ? <TaskForm ctx={ctx} i={i} step={def.key} onDone={() => setMode("idle")} /> : null}
      {tasks.length ? (
        <ul className="divide-y divide-border rounded-md border border-border bg-background">
          {tasks.map((t) => <ActionRow key={t.id} ws={ctx.ws} a={t} uid={ctx.uid} canManage={ctx.canManage} siteLabel={`Task for ${def.title.toLowerCase()}`} />)}
        </ul>
      ) : null}
      {children}
    </li>
  );
}

function TaskForm({ ctx, i, step, onDone }: { ctx: Ctx; i: Incursion; step: StepKey; onDone: () => void }) {
  const invalidate = useInvalidate(ctx.ws);
  const id = useRef(newId());
  const [title, setTitle] = useState("");
  const [detail, setDetail] = useState("");
  const [owner, setOwner] = useState(ctx.uid ?? "");
  const [due, setDue] = useState("");
  const save = useMutation({
    mutationFn: () => run(incRpc.task(id.current, i.id, step, title, detail, owner || null, due || null)),
    onSuccess: () => { invalidate(); onDone(); },
  });
  return (
    <form className="space-y-2 rounded-md bg-secondary p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-2 sm:grid-cols-[1fr_12rem_10rem]">
        <Field id={`tk-t-${step}`} label="Task"><Input id={`tk-t-${step}`} className="bg-background" maxLength={200} value={title} onChange={(e) => setTitle(e.target.value)} /></Field>
        <Field id={`tk-o-${step}`} label="Owner">
          <select id={`tk-o-${step}`} className={selectClass} value={owner} onChange={(e) => setOwner(e.target.value)}>
            {ctx.members.map((m) => <option key={m.user_id} value={m.user_id}>{who(m.user_id, ctx.uid)}</option>)}
          </select>
        </Field>
        <Field id={`tk-d-${step}`} label="Due"><Input id={`tk-d-${step}`} type="date" className="bg-background" value={due} onChange={(e) => setDue(e.target.value)} /></Field>
      </div>
      <Field id={`tk-x-${step}`} label="Detail (optional)"><Input id={`tk-x-${step}`} className="bg-background" maxLength={2000} value={detail} onChange={(e) => setDetail(e.target.value)} /></Field>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={btn} disabled={save.isPending || title.trim().length < 3}>Add task</button>
        <button type="button" className={btn2} onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}

// ---------- notifications ----------------------------------------------------------------------
function Notifications({ ctx, i, runIt }: { ctx: Ctx; i: Incursion; runIt: boolean }) {
  const list = ctx.data.notifications.filter((n) => n.incursion_id === i.id);
  const [adding, setAdding] = useState(false);
  return (
    <div className="space-y-2 rounded-md border border-border bg-background p-3">
      <p className="text-xs font-semibold uppercase tracking-wide text-accent">Notifications recorded ({list.length})</p>
      {list.length === 0 ? <p className="text-muted-foreground">None recorded yet.</p> : (
        <ul className="space-y-1">
          {list.map((n) => (
            <li key={n.id}>
              <span className="font-medium text-primary">{n.recipient}</span>
              <span className="text-muted-foreground"> · {notifyKindLabels[n.kind]} · {notifyMethodLabels[n.method]} · {when(n.notified_at)}{n.reference ? ` · ref ${n.reference}` : ""}
                {" "}· recorded by {who(n.recorded_by, ctx.uid)} ({n.recorded_role}) {when(n.recorded_at)}</span>
              {n.note ? <p className="text-xs text-primary">{n.note}</p> : null}
            </li>
          ))}
        </ul>
      )}
      {runIt ? (adding ? <NotifyForm ctx={ctx} i={i} onDone={() => setAdding(false)} /> : <button type="button" className={btn2} onClick={() => setAdding(true)}>Record a notification</button>) : null}
      {ctx.canManage ? <Contacts ctx={ctx} /> : null}
    </div>
  );
}

function NotifyForm({ ctx, i, onDone }: { ctx: Ctx; i: Incursion; onDone: () => void }) {
  const invalidate = useInvalidate(ctx.ws);
  const id = useRef(newId());
  const contacts = ctx.data.contacts.filter((c) => c.active);
  const [contact, setContact] = useState("");
  const [kind, setKind] = useState<NotifyKind>("ukhsa");
  const [recipient, setRecipient] = useState("");
  const [method, setMethod] = useState<NotifyMethod>("phone");
  const [at, setAt] = useState(nowLocal());
  const [reference, setReference] = useState("");
  const [note, setNote] = useState("");
  const save = useMutation({
    mutationFn: () => run(incRpc.notify(id.current, i.id, { kind: contact ? null : kind, contact: contact || null, recipient: contact ? "" : recipient, method, at: localToIso(at), reference, note })),
    onSuccess: () => { invalidate(); onDone(); },
  });
  return (
    <form className="space-y-3 rounded-md bg-secondary p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <p className="text-xs text-muted-foreground">This records that you told someone. First Line doesn't send anything.</p>
      <div className="grid gap-3 sm:grid-cols-2">
        {contacts.length ? (
          <Field id="nf-c" label="From your council's list">
            <select id="nf-c" className={selectClass} value={contact} onChange={(e) => setContact(e.target.value)}>
              <option value="">Someone else (type below)</option>
              {contacts.map((c) => <option key={c.id} value={c.id}>{c.name}{c.organisation ? ` (${c.organisation})` : ""}</option>)}
            </select>
          </Field>
        ) : null}
        {!contact ? <>
          <Field id="nf-k" label="Who">
            <select id="nf-k" className={selectClass} value={kind} onChange={(e) => setKind(e.target.value as NotifyKind)}>
              {(Object.keys(notifyKindLabels) as NotifyKind[]).map((k) => <option key={k} value={k}>{notifyKindLabels[k]}</option>)}
            </select>
          </Field>
          <Field id="nf-r" label="Name or team"><Input id="nf-r" className="bg-background" maxLength={200} value={recipient} onChange={(e) => setRecipient(e.target.value)} placeholder="e.g. UKHSA duty desk" /></Field>
        </> : null}
        <Field id="nf-m" label="How">
          <select id="nf-m" className={selectClass} value={method} onChange={(e) => setMethod(e.target.value as NotifyMethod)}>
            {(Object.keys(notifyMethodLabels) as NotifyMethod[]).map((k) => <option key={k} value={k}>{notifyMethodLabels[k]}</option>)}
          </select>
        </Field>
        <Field id="nf-a" label="When"><Input id="nf-a" type="datetime-local" className="bg-background" value={at} max={nowLocal()} onChange={(e) => setAt(e.target.value)} /></Field>
        <Field id="nf-ref" label="Their reference (optional)"><Input id="nf-ref" className="bg-background" maxLength={120} value={reference} onChange={(e) => setReference(e.target.value)} /></Field>
      </div>
      <Field id="nf-n" label="Note (optional)"><Input id="nf-n" className="bg-background" maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={btn} disabled={save.isPending || !at || (!contact && recipient.trim().length < 2)}>Record notification</button>
        <button type="button" className={btn2} onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}

function Contacts({ ctx }: { ctx: Ctx }) {
  const [open, setOpen] = useState<string | "new" | null>(null);
  return (
    <details className="text-sm">
      <summary className="cursor-pointer text-primary underline">Your council's notification list ({ctx.data.contacts.length})</summary>
      <div className="mt-2 space-y-2">
        <p className="text-xs text-muted-foreground">People and organisations your council usually tells. Private to your council.</p>
        {ctx.data.contacts.length ? (
          <ul className="space-y-1">
            {ctx.data.contacts.map((c) => (
              <li key={c.id}>
                {open === c.id ? <ContactForm ctx={ctx} c={c} onDone={() => setOpen(null)} /> : (
                  <span className={c.active ? "text-primary" : "text-muted-foreground"}>
                    {c.name}{c.organisation ? ` (${c.organisation})` : ""} · {notifyKindLabels[c.kind]}{c.detail ? ` · ${c.detail}` : ""}{c.active ? "" : " · not in use"}
                    {" "}<button type="button" className="text-xs underline" onClick={() => setOpen(c.id)}>Edit</button>
                  </span>
                )}
              </li>
            ))}
          </ul>
        ) : null}
        {open === "new" ? <ContactForm ctx={ctx} onDone={() => setOpen(null)} /> : <button type="button" className={btn2} onClick={() => setOpen("new")}>Add to the list</button>}
      </div>
    </details>
  );
}

function ContactForm({ ctx, c, onDone }: { ctx: Ctx; c?: Contact; onDone: () => void }) {
  const invalidate = useInvalidate(ctx.ws);
  const id = useRef(c?.id ?? newId());
  const [name, setName] = useState(c?.name ?? "");
  const [organisation, setOrganisation] = useState(c?.organisation ?? "");
  const [kind, setKind] = useState<NotifyKind>(c?.kind ?? "internal");
  const [detail, setDetail] = useState(c?.detail ?? "");
  const [active, setActive] = useState(c?.active ?? true);
  const save = useMutation({
    mutationFn: () => run(incRpc.contact(id.current, ctx.ws, { name, organisation, kind, detail, active })),
    onSuccess: () => { invalidate(); onDone(); },
  });
  return (
    <form className="space-y-2 rounded-md bg-secondary p-3" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-2 sm:grid-cols-2">
        <Field id="cf-n" label="Name or team"><Input id="cf-n" className="bg-background" maxLength={200} value={name} onChange={(e) => setName(e.target.value)} /></Field>
        <Field id="cf-o" label="Organisation (optional)"><Input id="cf-o" className="bg-background" maxLength={200} value={organisation} onChange={(e) => setOrganisation(e.target.value)} /></Field>
        <Field id="cf-k" label="Type">
          <select id="cf-k" className={selectClass} value={kind} onChange={(e) => setKind(e.target.value as NotifyKind)}>
            {(Object.keys(notifyKindLabels) as NotifyKind[]).map((k) => <option key={k} value={k}>{notifyKindLabels[k]}</option>)}
          </select>
        </Field>
        <Field id="cf-d" label="How to reach them (optional)" hint="A work phone number or shared mailbox, not personal details.">
          <Input id="cf-d" className="bg-background" maxLength={500} value={detail} onChange={(e) => setDetail(e.target.value)} />
        </Field>
      </div>
      {c ? <label className="flex items-center gap-2"><input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} /> In use</label> : null}
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={btn} disabled={save.isPending || name.trim().length < 2}>Save</button>
        <button type="button" className={btn2} onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}

// ---------- response area --------------------------------------------------------------------------
function AreaEditor({ ctx, i, runIt }: { ctx: Ctx; i: Incursion; runIt: boolean }) {
  const invalidate = useInvalidate(ctx.ws);
  const origin = ctx.sites.find((s) => s.id === i.site_id);
  const [editing, setEditing] = useState(false);
  const [centre, setCentre] = useState<{ lat: number; lon: number } | null>(
    i.response_area ? { lat: i.response_area.lat, lon: i.response_area.lon } : origin?.latitude != null && origin.longitude != null ? { lat: origin.latitude, lon: origin.longitude } : null);
  const [radius, setRadius] = useState(String(i.response_area?.radius_m ?? 300));
  const [reason, setReason] = useState("");
  const save = useMutation({
    mutationFn: () => run(incRpc.area(i.id, centre!.lat, centre!.lon, Number(radius), reason)),
    onSuccess: () => { invalidate(); setEditing(false); setReason(""); },
  });
  const sitePoints = i.sites.map((id) => ctx.sites.find((s) => s.id === id)).filter((s): s is Site => !!s && s.latitude != null && s.longitude != null)
    .map((s) => ({ id: s.id, lat: s.latitude!, lon: s.longitude!, label: `${s.reference} · ${s.name}`, muted: s.id !== i.site_id }));
  const r = Number(radius);
  const circle = editing ? (centre && r >= 10 ? [{ id: "draft", lat: centre.lat, lon: centre.lon, radius_m: r, label: "New response area" }] : [])
    : i.response_area ? [{ id: i.id, lat: i.response_area.lat, lon: i.response_area.lon, radius_m: i.response_area.radius_m, label: "Response area" }] : [];
  return (
    <div className="space-y-2 rounded-md border border-border bg-background p-3">
      <p className="text-xs font-semibold uppercase tracking-wide text-accent">Response area</p>
      <p className="text-primary">{i.response_area ? `${radiusLabel(i.response_area.radius_m)} of the point shown (centre ${i.response_area.lat.toFixed(5)}, ${i.response_area.lon.toFixed(5)})` : "Not drawn yet."}</p>
      <SurveillanceMap points={sitePoints} circles={circle} label={`Response area for ${i.reference}`} height={280}
        {...(editing ? { onPick: (lat: number, lon: number) => setCentre({ lat, lon }), picked: centre } : {})} />
      {runIt ? (editing ? (
        <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
          <Field id="ar-r" label="Radius (metres)"><Input id="ar-r" type="number" min={10} max={50000} step={10} className="w-32 bg-background" value={radius} onChange={(e) => setRadius(e.target.value)} /></Field>
          {i.response_area ? <Field id="ar-why" label="Why change it?"><Input id="ar-why" className="w-72 bg-background" maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} /></Field> : null}
          <button type="submit" className={btn} disabled={save.isPending || !centre || !(r >= 10 && r <= 50000) || (!!i.response_area && reason.trim().length < 5)}>Save area</button>
          <button type="button" className={btn2} onClick={() => setEditing(false)}>Cancel</button>
          <p className="w-full text-xs text-muted-foreground">Click the map to move the centre. It starts at the site where the finding was made.</p>
        </form>
      ) : <button type="button" className={btn2} onClick={() => setEditing(true)}>{i.response_area ? "Change the area" : "Draw the area"}</button>) : null}
      {save.isError ? <ErrorState error={save.error} /> : null}
    </div>
  );
}

// ---------- linked sites and findings --------------------------------------------------------------
function LinkedSites({ ctx, i, runIt }: { ctx: Ctx; i: Incursion; runIt: boolean }) {
  const invalidate = useInvalidate(ctx.ws);
  const [site, setSite] = useState("");
  const add = useMutation({ mutationFn: () => run(incRpc.link(i.id, [], [site])), onSuccess: () => { invalidate(); setSite(""); } });
  const others = ctx.sites.filter((s) => s.status === "active" && !i.sites.includes(s.id));
  return (
    <div className="space-y-2 rounded-md border border-border bg-background p-3">
      <p className="text-xs font-semibold uppercase tracking-wide text-accent">Sites in this response ({i.sites.length})</p>
      <ul className="list-disc pl-5">{i.sites.map((s) => <li key={s} className="text-primary">{siteLabel(ctx, s)}{s === i.site_id ? " (where it was found)" : ""}</li>)}</ul>
      {runIt && others.length ? (
        <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); add.mutate(); }}>
          <Field id="ls-s" label="Add a site used for enhanced trapping">
            <select id="ls-s" className={selectClass} value={site} onChange={(e) => setSite(e.target.value)}>
              <option value="">Choose a site</option>
              {others.map((s) => <option key={s.id} value={s.id}>{s.reference} · {s.name}</option>)}
            </select>
          </Field>
          <button type="submit" className={btn2} disabled={!site || add.isPending}>Add site</button>
          <Link to="/app/vectovia/sites" className="text-xs text-primary underline">Create a new site</Link>
        </form>
      ) : null}
      {add.isError ? <ErrorState error={add.error} /> : null}
    </div>
  );
}

function Findings({ ctx, i, runIt }: { ctx: Ctx; i: Incursion; runIt: boolean }) {
  const invalidate = useInvalidate(ctx.ws);
  const [pick, setPick] = useState("");
  const add = useMutation({ mutationFn: () => run(incRpc.link(i.id, [pick], [])), onSuccess: () => { invalidate(); setPick(""); } });
  const more = findingsAt(ctx).filter((r) => !i.findings.includes(r.id));
  return (
    <section aria-labelledby="fi-h" className="space-y-2">
      <h3 id="fi-h" className="text-lg font-semibold text-primary">Findings ({i.findings.length})</h3>
      <ul className="divide-y divide-border rounded-md border border-border text-sm">
        {i.findings.map((id) => { const v = current(ctx, id); const r = ctx.results.results.find((x) => x.id === id); return (
          <li key={id} className="flex flex-wrap items-baseline gap-x-3 gap-y-1 px-3 py-2">
            {v ? <StatusTag strong>{resultStatusLabels[v.status]}</StatusTag> : null}
            <span className="font-medium text-primary">{v ? resultLine(v, ctx.lists) : "Finding"}</span>
            <span className="text-xs text-muted-foreground">{r ? siteLabel(ctx, r.site_id) : ""}{v?.result_date ? ` · ${day(v.result_date)}` : ""}</span>
          </li>
        ); })}
      </ul>
      {runIt && more.length ? (
        <form className="flex flex-wrap items-end gap-2 text-sm" onSubmit={(e) => { e.preventDefault(); add.mutate(); }}>
          <Field id="fi-a" label="Add a later finding">
            <select id="fi-a" className={selectClass} value={pick} onChange={(e) => setPick(e.target.value)}>
              <option value="">Choose a finding</option>
              {more.map((r) => { const v = current(ctx, r.id)!; return <option key={r.id} value={r.id}>{siteLabel(ctx, r.site_id)}: {resultLine(v, ctx.lists)}</option>; })}
            </select>
          </Field>
          <button type="submit" className={btn2} disabled={!pick || add.isPending}>Add finding</button>
        </form>
      ) : null}
      {add.isError ? <ErrorState error={add.error} /> : null}
    </section>
  );
}

// ---------- stand-down -------------------------------------------------------------------------------
function StandDown({ ctx, i, st }: { ctx: Ctx; i: Incursion; st: Step[] }) {
  const invalidate = useInvalidate(ctx.ws);
  const id = useRef(newId());
  const [mode, setMode] = useState<"idle" | "stand" | "reopen">("idle");
  const [text, setText] = useState("");
  const [at, setAt] = useState(nowLocal());
  const [status, setStatus] = useState<IncursionStatus>("responding");
  const history = ctx.data.standDowns.filter((s) => s.incursion_id === i.id);
  const outstanding = st.filter((s) => s.step_key !== "stand_down" && s.status === "to_do").length;
  const act = useMutation({
    mutationFn: () => run(mode === "stand" ? incRpc.standDown(id.current, i.id, localToIso(at), text) : incRpc.reopen(id.current, i.id, status, text)),
    onSuccess: () => { invalidate(); setMode("idle"); setText(""); id.current = newId(); },
  });
  return (
    <div className="space-y-2 rounded-md border border-border bg-background p-3">
      {history.length ? (
        <ol className="space-y-2">
          {history.map((h) => (
            <li key={h.id}>
              <span className="font-medium text-primary">{h.kind === "stand_down" ? "Stood down" : "Reopened"}</span>
              <span className="text-muted-foreground"> · {when(h.decided_at)} · {who(h.decided_by, ctx.uid)} ({h.decided_role})</span>
              <p className="whitespace-pre-wrap text-primary">{h.rationale}</p>
            </li>
          ))}
        </ol>
      ) : <p className="text-muted-foreground">Not stood down.</p>}
      {ctx.canManage && mode === "idle" ? (i.status === "stood_down"
        ? <button type="button" className={btn2} onClick={() => setMode("reopen")}>Reopen the incursion</button>
        : outstanding ? <p className="text-xs text-muted-foreground">{outstanding} step{outstanding > 1 ? "s are" : " is"} still to do. Mark each done or skip it (with a reason) before standing down.</p>
          : <button type="button" className={btn} onClick={() => setMode("stand")}>Stand down</button>) : null}
      {mode !== "idle" ? (
        <form className="space-y-2" onSubmit={(e) => { e.preventDefault(); act.mutate(); }}>
          {mode === "stand" ? (
            <Field id="sd-a" label="When was it decided?"><Input id="sd-a" type="datetime-local" className="w-60 bg-background" value={at} max={nowLocal()} onChange={(e) => setAt(e.target.value)} /></Field>
          ) : (
            <Field id="sd-s" label="Reopen as">
              <select id="sd-s" className={selectClass} value={status} onChange={(e) => setStatus(e.target.value as IncursionStatus)}>
                {(["suspected", "confirmed", "responding", "monitoring"] as const).map((k) => <option key={k} value={k}>{incursionStatusLabels[k]}</option>)}
              </select>
            </Field>
          )}
          <Field id="sd-t" label={mode === "stand" ? "Stand-down decision and the reasons for it" : "Why reopen it?"} hint="At least 10 characters.">
            <Textarea id="sd-t" className="bg-background" maxLength={4000} value={text} onChange={(e) => setText(e.target.value)} />
          </Field>
          {act.isError ? <ErrorState error={act.error} /> : null}
          <div className="flex gap-2">
            <button type="submit" className={btn} disabled={act.isPending || text.trim().length < 10 || (mode === "stand" && !at)}>{mode === "stand" ? "Record stand-down" : "Reopen"}</button>
            <button type="button" className={btn2} onClick={() => setMode("idle")}>Cancel</button>
          </div>
        </form>
      ) : null}
    </div>
  );
}
