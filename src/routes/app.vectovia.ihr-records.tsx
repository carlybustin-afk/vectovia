import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useRef, useState, type ReactNode } from "react";
import { AppShell, EmptyState, ErrorState, Loading, appHead } from "@/components/app-shell";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { useSession } from "@/lib/session";
import { day, newId, run, when, who, type Site } from "@/modules/vectovia/api";
import {
  auditOutcomeLabels, conveyanceOutcomeLabels, conveyanceReasonLabels, conveyanceTypeLabels, expiry, followUpMethodLabels, ihrRpc, reviewKindLabels,
  useCompetence, useContractors, useConveyances, useEquipment, useIncomingRisks, useSiteReviews,
  type AuditOutcome, type Competence, type Contractor, type Conveyance, type ConveyanceOutcome, type ConveyanceReason, type ConveyanceType, type Equipment,
  type FollowUp, type IncomingRisk, type ReviewKind,
} from "@/modules/vectovia/ihr";
import { Field, StatusTag, selectClass, useSites, useVv } from "@/modules/vectovia/ui";

export const Route = createFileRoute("/app/vectovia/ihr-records")({
  head: () => appHead("IHR records · Vectovia", "Competence, contractors, equipment and chemicals, conveyances, follow-ups, incoming risks and site reviews."),
  component: IhrPage,
});

function IhrPage() {
  return (
    <AppShell product="vectovia" section="vectovia" title="IHR records"
      intro="The registers and logs behind the IHR point-of-entry requirements. Each one feeds the site's compliance automatically, so a lapsed certificate, an unaudited contractor or a missing follow-up shows up there.">
      <Ihr />
    </AppShell>
  );
}

const btn = "rounded-md border border-primary px-3 py-1.5 text-sm font-medium text-primary disabled:opacity-60";
const primaryBtn = "rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy disabled:opacity-60";
const formClass = "space-y-3 rounded-md border-t-2 border-accent bg-secondary p-3";
const todayIso = () => new Date().toISOString().slice(0, 10);
const nowLocal = () => { const d = new Date(); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 16); };
const siteLabel = (s: Site | undefined) => (s ? `${s.reference} · ${s.name}` : "Site");

function useRefresh(ws: string) {
  const qc = useQueryClient();
  return () => void qc.invalidateQueries({ queryKey: ["ws", ws, "vv"] });
}

const tabs = [
  { key: "competence", label: "Competence" }, { key: "contractors", label: "Contractors" }, { key: "equipment", label: "Equipment and chemicals" },
  { key: "conveyances", label: "Conveyances and follow-ups" }, { key: "risks", label: "Incoming risks" }, { key: "reviews", label: "Site reviews" },
] as const;
type Tab = (typeof tabs)[number]["key"];

function Ihr() {
  const { ws, canRecord, canManage } = useVv();
  const { session } = useSession();
  const sites = useSites(ws);
  const [tab, setTab] = useState<Tab>("competence");
  if (sites.isPending) return <Loading />;
  if (sites.error) return <ErrorState error={sites.error} />;
  const ctx: Ctx = { ws, uid: session?.user.id, canRecord, canManage, sites: sites.data.filter((s) => s.status === "active") };
  return (
    <div className="space-y-6">
      <div role="tablist" aria-label="IHR records" className="flex flex-wrap gap-1 border-b border-border">
        {tabs.map((t) => (
          <button key={t.key} type="button" role="tab" aria-selected={tab === t.key} onClick={() => setTab(t.key)}
            className={`-mb-px rounded-t-md border px-3 py-1.5 text-sm ${tab === t.key ? "border-border border-b-background bg-background font-semibold text-primary" : "border-transparent text-muted-foreground hover:text-primary"}`}>
            {t.label}
          </button>
        ))}
      </div>
      <div role="tabpanel">
        {tab === "competence" ? <CompetenceTab {...ctx} /> : tab === "contractors" ? <ContractorsTab {...ctx} /> : tab === "equipment" ? <EquipmentTab {...ctx} />
          : tab === "conveyances" ? <ConveyancesTab {...ctx} /> : tab === "risks" ? <RisksTab {...ctx} /> : <ReviewsTab {...ctx} />}
      </div>
    </div>
  );
}
type Ctx = { ws: string; uid: string | undefined; canRecord: boolean; canManage: boolean; sites: Site[] };

function Section({ title, intro, action, children }: { title: string; intro: string; action?: ReactNode; children: ReactNode }) {
  return (
    <section className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-lg font-semibold text-primary">{title}</h2>
        {action}
      </div>
      <p className="max-w-3xl text-sm text-muted-foreground">{intro}</p>
      {children}
    </section>
  );
}
function ExpiryTag({ date, label = "Expires" }: { date: string | null; label?: string }) {
  const e = expiry(date);
  if (e === "none") return <StatusTag>No expiry</StatusTag>;
  return <StatusTag strong={e !== "ok"}>{e === "expired" ? "▲ Expired " : e === "soon" ? "Due soon: " : `${label} `}{day(date)}</StatusTag>;
}
function Reason({ id, value, onChange }: { id: string; value: string; onChange: (v: string) => void }) {
  return <Field id={id} label="Reason for the change (required)"><Input id={id} className="bg-background" maxLength={500} value={value} onChange={(e) => onChange(e.target.value)} /></Field>;
}

// ---------- Competence ------------------------------------------------------------------------------
function CompetenceTab({ ws, canManage }: Ctx) {
  const q = useCompetence(ws);
  const [editing, setEditing] = useState<Competence | "new" | null>(null);
  const [withdrawing, setWithdrawing] = useState<string | null>(null);
  return (
    <Section title="Competence" intro="Training and competence of the people doing surveillance and control, with renewal dates. A renewal is a new record, so the history stays. Linked to IHR provision 8 and UKHSA training."
      action={canManage && !editing ? <button type="button" className={primaryBtn} onClick={() => setEditing("new")}>Add training</button> : null}>
      {editing ? <CompetenceForm ws={ws} current={editing === "new" ? null : editing} onDone={() => setEditing(null)} /> : null}
      {q.isError ? <ErrorState error={q.error} /> : !q.data ? <Loading /> : q.data.length === 0 ? <EmptyState title="No training recorded">Add the first record with “Add training”.</EmptyState> : (
        <ul className="divide-y divide-border rounded-md border border-border text-sm">
          {q.data.map((c) => (
            <li key={c.id} className={`px-3 py-2 ${c.withdrawn_at ? "opacity-60" : ""}`}>
              <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                {c.withdrawn_at ? <StatusTag>Withdrawn</StatusTag> : <ExpiryTag date={c.expires_on} />}
                <span className="font-medium text-primary">{c.person_name}</span>
                <span className="text-primary">{c.competence}</span>
                <span className="text-xs text-muted-foreground">{[c.provider, `achieved ${day(c.achieved_on)}`, c.certificate_ref].filter(Boolean).join(" · ")}</span>
                {canManage && !c.withdrawn_at ? (
                  <span className="ml-auto flex gap-3">
                    <button type="button" className="text-primary underline" onClick={() => setEditing(c)}>Correct</button>
                    <button type="button" className="text-primary underline" onClick={() => setWithdrawing(c.id)}>Withdraw</button>
                  </span>
                ) : null}
              </div>
              {c.withdrawn_reason ? <p className="text-xs text-muted-foreground">Withdrawn: {c.withdrawn_reason}</p> : null}
              {withdrawing === c.id ? <WithdrawCompetence ws={ws} id={c.id} onDone={() => setWithdrawing(null)} /> : null}
            </li>
          ))}
        </ul>
      )}
    </Section>
  );
}

function CompetenceForm({ ws, current, onDone }: { ws: string; current: Competence | null; onDone: () => void }) {
  const refresh = useRefresh(ws);
  const id = useRef(current?.id ?? newId());
  const [f, setF] = useState({ person_name: current?.person_name ?? "", person_id: current?.person_id ?? "", competence: current?.competence ?? "", provider: current?.provider ?? "",
    achieved_on: current?.achieved_on ?? todayIso(), expires_on: current?.expires_on ?? "", certificate_ref: current?.certificate_ref ?? "" });
  const [reason, setReason] = useState("");
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF((x) => ({ ...x, [k]: e.target.value }));
  const save = useMutation({ mutationFn: () => run(ihrRpc.saveCompetence(id.current, ws, f, reason)), onSuccess: () => { refresh(); onDone(); } });
  const ok = f.person_name.trim().length >= 2 && f.competence.trim().length >= 2 && f.achieved_on && (!f.expires_on || f.expires_on > f.achieved_on) && (!current || reason.trim().length >= 5);
  return (
    <form className={formClass} onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-3 sm:grid-cols-2">
        <Field id="cp-name" label="Person"><Input id="cp-name" className="bg-background" maxLength={120} value={f.person_name} onChange={set("person_name")} /></Field>
        <Field id="cp-comp" label="Competence" hint="For example: mosquito identification, trap handling, pesticide application."><Input id="cp-comp" className="bg-background" maxLength={200} value={f.competence} onChange={set("competence")} /></Field>
        <Field id="cp-prov" label="Provider (optional)"><Input id="cp-prov" className="bg-background" maxLength={200} value={f.provider} onChange={set("provider")} /></Field>
        <Field id="cp-cert" label="Certificate reference (optional)"><Input id="cp-cert" className="bg-background" maxLength={100} value={f.certificate_ref} onChange={set("certificate_ref")} /></Field>
        <Field id="cp-ach" label="Achieved on"><Input id="cp-ach" type="date" max={todayIso()} className="bg-background" value={f.achieved_on} onChange={set("achieved_on")} /></Field>
        <Field id="cp-exp" label="Expires on (optional)"><Input id="cp-exp" type="date" className="bg-background" value={f.expires_on} onChange={set("expires_on")} /></Field>
      </div>
      {current ? <Reason id="cp-why" value={reason} onChange={setReason} /> : null}
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || !ok}>{save.isPending ? "Saving…" : current ? "Save correction" : "Save training"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}

function WithdrawCompetence({ ws, id, onDone }: { ws: string; id: string; onDone: () => void }) {
  const refresh = useRefresh(ws);
  const [why, setWhy] = useState("");
  const go = useMutation({ mutationFn: () => run(ihrRpc.withdrawCompetence(id, why)), onSuccess: () => { refresh(); onDone(); } });
  return (
    <div className="mt-2 flex flex-wrap items-end gap-2">
      <Field id={`wd-${id}`} label="Why withdraw it? (entered in error; required)"><Input id={`wd-${id}`} className="w-72 max-w-full bg-background" maxLength={500} value={why} onChange={(e) => setWhy(e.target.value)} /></Field>
      <button type="button" className={btn} disabled={go.isPending || why.trim().length < 5} onClick={() => go.mutate()}>Withdraw</button>
      <button type="button" className="text-sm text-primary underline" onClick={onDone}>Cancel</button>
      {go.isError ? <ErrorState error={go.error} /> : null}
    </div>
  );
}

// ---------- Contractors -----------------------------------------------------------------------------
function ContractorsTab({ ws, canManage, sites }: Ctx) {
  const q = useContractors(ws);
  const [editing, setEditing] = useState<Contractor | "new" | null>(null);
  const [auditing, setAuditing] = useState<string | null>(null);
  return (
    <Section title="Contractors" intro="Contractors who carry out surveillance or control, the sites they work at, and their audits (at least yearly). Linked to IHR provision 9."
      action={canManage && !editing ? <button type="button" className={primaryBtn} onClick={() => setEditing("new")}>Add a contractor</button> : null}>
      {editing ? <ContractorForm ws={ws} sites={sites} current={editing === "new" ? null : editing} currentSites={editing === "new" ? [] : (q.data?.sites ?? []).filter((x) => x.contractor_id === editing.id).map((x) => x.site_id)}
        onDone={() => setEditing(null)} /> : null}
      {q.isError ? <ErrorState error={q.error} /> : !q.data ? <Loading /> : q.data.contractors.length === 0 ? <EmptyState title="No contractors recorded">If you use contractors, add them with “Add a contractor”.</EmptyState> : (
        <ul className="divide-y divide-border rounded-md border border-border text-sm">
          {q.data.contractors.map((c) => {
            const audits = q.data.audits.filter((a) => a.contractor_id === c.id);
            const where = q.data.sites.filter((x) => x.contractor_id === c.id).map((x) => siteLabel(sites.find((s) => s.id === x.site_id)));
            return (
              <li key={c.id} className={`px-3 py-2 ${c.status === "ended" ? "opacity-60" : ""}`}>
                <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                  {c.status === "ended" ? <StatusTag>Ended</StatusTag> : audits[0] ? <ExpiryTag date={audits[0].next_due} label="Next audit" /> : <StatusTag strong>▲ Not audited</StatusTag>}
                  <span className="font-medium text-primary">{c.name}</span>
                  <span className="text-primary">{c.service}</span>
                  {canManage ? (
                    <span className="ml-auto flex gap-3">
                      {c.status === "active" ? <button type="button" className="text-primary underline" onClick={() => setAuditing(c.id)}>Record an audit</button> : null}
                      <button type="button" className="text-primary underline" onClick={() => setEditing(c)}>Edit</button>
                    </span>
                  ) : null}
                </div>
                <p className="text-xs text-muted-foreground">{where.length ? `Works at: ${where.join("; ")}` : "No sites linked"}{c.contact ? ` · ${c.contact}` : ""}</p>
                {audits.slice(0, 3).map((a) => (
                  <p key={a.id} className="text-xs text-primary">Audit {day(a.audited_on)}: {auditOutcomeLabels[a.outcome]} · {a.findings}</p>
                ))}
                {auditing === c.id ? <AuditForm ws={ws} contractor={c.id} sites={sites.filter((s) => q.data.sites.some((x) => x.contractor_id === c.id && x.site_id === s.id))} onDone={() => setAuditing(null)} /> : null}
              </li>
            );
          })}
        </ul>
      )}
    </Section>
  );
}

function ContractorForm({ ws, sites, current, currentSites, onDone }: { ws: string; sites: Site[]; current: Contractor | null; currentSites: string[]; onDone: () => void }) {
  const refresh = useRefresh(ws);
  const id = useRef(current?.id ?? newId());
  const [f, setF] = useState({ name: current?.name ?? "", service: current?.service ?? "", contact: current?.contact ?? "", status: current?.status ?? ("active" as Contractor["status"]), sites: currentSites });
  const [reason, setReason] = useState("");
  const save = useMutation({ mutationFn: () => run(ihrRpc.saveContractor(id.current, ws, f, reason)), onSuccess: () => { refresh(); onDone(); } });
  const ok = f.name.trim().length >= 2 && f.service.trim().length >= 2 && (!current || reason.trim().length >= 5);
  return (
    <form className={formClass} onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-3 sm:grid-cols-2">
        <Field id="ct-name" label="Contractor"><Input id="ct-name" className="bg-background" maxLength={200} value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} /></Field>
        <Field id="ct-svc" label="Service"><Input id="ct-svc" className="bg-background" maxLength={500} value={f.service} onChange={(e) => setF({ ...f, service: e.target.value })} /></Field>
        <Field id="ct-contact" label="Contact (optional)"><Input id="ct-contact" className="bg-background" maxLength={300} value={f.contact} onChange={(e) => setF({ ...f, contact: e.target.value })} /></Field>
        {current ? <Field id="ct-status" label="Status"><select id="ct-status" className={selectClass} value={f.status} onChange={(e) => setF({ ...f, status: e.target.value as Contractor["status"] })}>
          <option value="active">Active</option><option value="ended">Ended</option></select></Field> : null}
      </div>
      <fieldset>
        <legend className="text-sm font-medium text-primary">Sites they work at</legend>
        <div className="mt-1 flex flex-wrap gap-3">
          {sites.map((s) => (
            <label key={s.id} className="flex items-center gap-2 text-sm"><input type="checkbox" checked={f.sites.includes(s.id)}
              onChange={(e) => setF({ ...f, sites: e.target.checked ? [...f.sites, s.id] : f.sites.filter((x) => x !== s.id) })} />{siteLabel(s)}</label>
          ))}
        </div>
      </fieldset>
      {current ? <Reason id="ct-why" value={reason} onChange={setReason} /> : null}
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || !ok}>{save.isPending ? "Saving…" : "Save contractor"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}

function AuditForm({ ws, contractor, sites, onDone }: { ws: string; contractor: string; sites: Site[]; onDone: () => void }) {
  const refresh = useRefresh(ws);
  const id = useRef(newId());
  const [f, setF] = useState({ site: sites[0]?.id ?? "", audited_on: todayIso(), outcome: "satisfactory" as AuditOutcome, findings: "", next_due: "" });
  const save = useMutation({ mutationFn: () => run(ihrRpc.recordAudit(id.current, contractor, f.site, f)), onSuccess: () => { refresh(); onDone(); } });
  return (
    <form className={`mt-2 ${formClass}`} onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id="au-site" label="Site (optional)"><select id="au-site" className={selectClass} value={f.site} onChange={(e) => setF({ ...f, site: e.target.value })}>
          <option value="">All their work</option>{sites.map((s) => <option key={s.id} value={s.id}>{siteLabel(s)}</option>)}</select></Field>
        <Field id="au-on" label="Audited on"><Input id="au-on" type="date" max={todayIso()} className="bg-background" value={f.audited_on} onChange={(e) => setF({ ...f, audited_on: e.target.value })} /></Field>
        <Field id="au-out" label="Outcome"><select id="au-out" className={selectClass} value={f.outcome} onChange={(e) => setF({ ...f, outcome: e.target.value as AuditOutcome })}>
          {(Object.keys(auditOutcomeLabels) as AuditOutcome[]).map((k) => <option key={k} value={k}>{auditOutcomeLabels[k]}</option>)}</select></Field>
      </div>
      <Field id="au-find" label="Findings"><Textarea id="au-find" className="bg-background" maxLength={5000} value={f.findings} onChange={(e) => setF({ ...f, findings: e.target.value })} /></Field>
      <Field id="au-next" label="Next audit due (optional)" hint="Leave blank for a year from the audit."><Input id="au-next" type="date" className="w-48 bg-background" value={f.next_due} onChange={(e) => setF({ ...f, next_due: e.target.value })} /></Field>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || f.findings.trim().length < 5}>{save.isPending ? "Saving…" : "Save audit"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}

// ---------- Equipment and chemicals -------------------------------------------------------------------
function EquipmentTab({ ws, canManage }: Ctx) {
  const q = useEquipment(ws);
  const [editing, setEditing] = useState<Equipment | "new" | null>(null);
  return (
    <Section title="Equipment and chemicals" intro="Equipment and chemicals in use, with authorisation references and expiry or service dates. Linked to IHR provision 10."
      action={canManage && !editing ? <button type="button" className={primaryBtn} onClick={() => setEditing("new")}>Add an item</button> : null}>
      {editing ? <EquipmentForm ws={ws} current={editing === "new" ? null : editing} onDone={() => setEditing(null)} /> : null}
      {q.isError ? <ErrorState error={q.error} /> : !q.data ? <Loading /> : q.data.length === 0 ? <EmptyState title="Nothing registered">Add equipment and chemicals with “Add an item”.</EmptyState> : (
        <ul className="divide-y divide-border rounded-md border border-border text-sm">
          {q.data.map((e) => (
            <li key={e.id} className={`px-3 py-2 ${e.status === "withdrawn" ? "opacity-60" : ""}`}>
              <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                {e.status === "withdrawn" ? <StatusTag>Withdrawn</StatusTag> : <ExpiryTag date={e.expires_on} />}
                <span className="font-medium text-primary">{e.name}</span>
                <span className="text-primary">{e.kind === "chemical" ? "Chemical" : "Equipment"}</span>
                {e.kind === "chemical" && !e.authorisation_ref && e.status === "in_use" ? <StatusTag strong>▲ No authorisation reference</StatusTag> : null}
                {canManage ? <button type="button" className="ml-auto text-primary underline" onClick={() => setEditing(e)}>Edit</button> : null}
              </div>
              <p className="text-xs text-muted-foreground">{[e.active_substance, e.authorisation_ref && `Authorisation ${e.authorisation_ref}`, e.location, e.quantity, e.notes].filter(Boolean).join(" · ")}</p>
            </li>
          ))}
        </ul>
      )}
    </Section>
  );
}

function EquipmentForm({ ws, current, onDone }: { ws: string; current: Equipment | null; onDone: () => void }) {
  const refresh = useRefresh(ws);
  const id = useRef(current?.id ?? newId());
  const [f, setF] = useState({ kind: current?.kind ?? ("chemical" as Equipment["kind"]), name: current?.name ?? "", substance: current?.active_substance ?? "",
    authorisation: current?.authorisation_ref ?? "", location: current?.location ?? "", quantity: current?.quantity ?? "", expires_on: current?.expires_on ?? "",
    status: current?.status ?? ("in_use" as Equipment["status"]), notes: current?.notes ?? "" });
  const [reason, setReason] = useState("");
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF((x) => ({ ...x, [k]: e.target.value }));
  const save = useMutation({ mutationFn: () => run(ihrRpc.saveEquipment(id.current, ws, f, reason)), onSuccess: () => { refresh(); onDone(); } });
  const ok = f.name.trim().length >= 2 && (!current || reason.trim().length >= 5);
  return (
    <form className={formClass} onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id="eq-kind" label="Kind"><select id="eq-kind" className={selectClass} value={f.kind} disabled={!!current} onChange={set("kind")}>
          <option value="chemical">Chemical</option><option value="equipment">Equipment</option></select></Field>
        <Field id="eq-name" label="Name"><Input id="eq-name" className="bg-background" maxLength={200} value={f.name} onChange={set("name")} /></Field>
        {f.kind === "chemical" ? <Field id="eq-sub" label="Active substance"><Input id="eq-sub" className="bg-background" maxLength={200} value={f.substance} onChange={set("substance")} /></Field> : null}
        {f.kind === "chemical" ? <Field id="eq-auth" label="Authorisation reference"><Input id="eq-auth" className="bg-background" maxLength={100} value={f.authorisation} onChange={set("authorisation")} /></Field> : null}
        <Field id="eq-loc" label="Where it is kept (optional)"><Input id="eq-loc" className="bg-background" maxLength={300} value={f.location} onChange={set("location")} /></Field>
        <Field id="eq-qty" label="Quantity (optional)"><Input id="eq-qty" className="bg-background" maxLength={100} value={f.quantity} onChange={set("quantity")} /></Field>
        <Field id="eq-exp" label={f.kind === "chemical" ? "Expiry date (optional)" : "Service or expiry date (optional)"}><Input id="eq-exp" type="date" className="bg-background" value={f.expires_on} onChange={set("expires_on")} /></Field>
        {current ? <Field id="eq-status" label="Status"><select id="eq-status" className={selectClass} value={f.status} onChange={set("status")}>
          <option value="in_use">In use</option><option value="withdrawn">Withdrawn</option></select></Field> : null}
      </div>
      <Field id="eq-notes" label="Notes (optional)"><Input id="eq-notes" className="bg-background" maxLength={2000} value={f.notes} onChange={set("notes")} /></Field>
      {current ? <Reason id="eq-why" value={reason} onChange={setReason} /> : null}
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || !ok}>{save.isPending ? "Saving…" : "Save item"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}

// ---------- Conveyances and follow-ups ------------------------------------------------------------------
function ConveyancesTab({ ws, uid, canRecord, sites }: Ctx) {
  const q = useConveyances(ws);
  const [open, setOpen] = useState(false);
  const [notice, setNotice] = useState<Conveyance | "new" | null>(null);
  const needsNotice = (c: Conveyance) => c.outcome !== "no_evidence" && !!c.next_destination && !(q.data?.followUps ?? []).some((f) => f.conveyance_id === c.id);
  return (
    <div className="space-y-8">
      <Section title="Conveyance inspections" intro="Inspections of ships, aircraft, vehicles and containers, especially affected or suspect ones. Linked to IHR provisions 13 and 14."
        action={canRecord && !open ? <button type="button" className={primaryBtn} onClick={() => setOpen(true)}>Record an inspection</button> : null}>
        {open ? <ConveyanceForm ws={ws} sites={sites} onDone={() => setOpen(false)} /> : null}
        {q.isError ? <ErrorState error={q.error} /> : !q.data ? <Loading /> : q.data.conveyances.length === 0 ? <EmptyState title="No conveyance inspections yet">Record one with “Record an inspection”.</EmptyState> : (
          <ul className="divide-y divide-border rounded-md border border-border text-sm">
            {q.data.conveyances.map((c) => (
              <li key={c.id} className="px-3 py-2">
                <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                  <StatusTag strong={c.outcome !== "no_evidence"}>{conveyanceOutcomeLabels[c.outcome]}</StatusTag>
                  <span className="font-medium text-primary">{conveyanceTypeLabels[c.conveyance_type]} {c.identifier}</span>
                  <span className="text-primary">{siteLabel(sites.find((s) => s.id === c.site_id))}</span>
                  <span className="text-xs text-muted-foreground">{when(c.inspected_at)} · {who(c.officer_id, uid)} · {conveyanceReasonLabels[c.reason]}</span>
                  {needsNotice(c) ? <StatusTag strong>▲ Next point of entry not told</StatusTag> : null}
                  {canRecord && needsNotice(c) ? <button type="button" className="ml-auto text-primary underline" onClick={() => setNotice(c)}>Send a follow-up notice</button> : null}
                </div>
                <p className="text-xs text-muted-foreground">{[c.arrived_from && `From ${c.arrived_from}`, c.next_destination && `Next: ${c.next_destination}`, c.evidence, c.action_taken && `Action: ${c.action_taken}`].filter(Boolean).join(" · ")}</p>
                {notice !== "new" && notice?.id === c.id ? <FollowUpForm ws={ws} sites={sites} conveyance={c} onDone={() => setNotice(null)} /> : null}
              </li>
            ))}
          </ul>
        )}
      </Section>
      <Section title="Follow-up notices" intro="Notices to the next point of entry about a conveyance with findings, and whether they were acknowledged. Linked to IHR provision 15."
        action={canRecord && notice === null ? <button type="button" className={btn} onClick={() => setNotice("new")}>Send a notice</button> : null}>
        {notice === "new" ? <FollowUpForm ws={ws} sites={sites} conveyance={null} onDone={() => setNotice(null)} /> : null}
        {!q.data ? null : q.data.followUps.length === 0 ? <p className="text-sm text-muted-foreground">No follow-up notices yet.</p> : (
          <ul className="divide-y divide-border rounded-md border border-border text-sm">
            {q.data.followUps.map((f) => <FollowUpRow key={f.id} ws={ws} f={f} canRecord={canRecord} sites={sites} conveyance={q.data.conveyances.find((c) => c.id === f.conveyance_id)} />)}
          </ul>
        )}
      </Section>
    </div>
  );
}

function ConveyanceForm({ ws, sites, onDone }: { ws: string; sites: Site[]; onDone: () => void }) {
  const refresh = useRefresh(ws);
  const id = useRef(newId());
  const [site, setSite] = useState(sites[0]?.id ?? "");
  const [f, setF] = useState({ at: nowLocal(), type: "ship" as ConveyanceType, identifier: "", arrived_from: "", next_destination: "", reason: "routine" as ConveyanceReason,
    outcome: "no_evidence" as ConveyanceOutcome, evidence: "", action: "" });
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF((x) => ({ ...x, [k]: e.target.value }));
  const save = useMutation({ mutationFn: () => run(ihrRpc.recordConveyance(id.current, site, { ...f, inspected_at: new Date(f.at).toISOString() })), onSuccess: () => { refresh(); onDone(); } });
  const ok = site && f.identifier.trim() && (f.outcome === "no_evidence" || f.evidence.trim().length >= 5);
  return (
    <form className={formClass} onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id="cv-site" label="Site"><select id="cv-site" className={selectClass} value={site} onChange={(e) => setSite(e.target.value)}>{sites.map((s) => <option key={s.id} value={s.id}>{siteLabel(s)}</option>)}</select></Field>
        <Field id="cv-at" label="When"><Input id="cv-at" type="datetime-local" max={nowLocal()} className="bg-background" value={f.at} onChange={set("at")} /></Field>
        <Field id="cv-reason" label="Why inspected"><select id="cv-reason" className={selectClass} value={f.reason} onChange={set("reason")}>
          {(Object.keys(conveyanceReasonLabels) as ConveyanceReason[]).map((k) => <option key={k} value={k}>{conveyanceReasonLabels[k]}</option>)}</select></Field>
        <Field id="cv-type" label="Conveyance"><select id="cv-type" className={selectClass} value={f.type} onChange={set("type")}>
          {(Object.keys(conveyanceTypeLabels) as ConveyanceType[]).map((k) => <option key={k} value={k}>{conveyanceTypeLabels[k]}</option>)}</select></Field>
        <Field id="cv-id" label="Name or identifier" hint="Ship name or IMO number, flight number, registration or container number."><Input id="cv-id" className="bg-background" maxLength={120} value={f.identifier} onChange={set("identifier")} /></Field>
        <Field id="cv-from" label="Arrived from (optional)"><Input id="cv-from" className="bg-background" maxLength={200} value={f.arrived_from} onChange={set("arrived_from")} /></Field>
        <Field id="cv-next" label="Next point of entry (optional)"><Input id="cv-next" className="bg-background" maxLength={200} value={f.next_destination} onChange={set("next_destination")} /></Field>
        <Field id="cv-out" label="Outcome"><select id="cv-out" className={selectClass} value={f.outcome} onChange={set("outcome")}>
          {(Object.keys(conveyanceOutcomeLabels) as ConveyanceOutcome[]).map((k) => <option key={k} value={k}>{conveyanceOutcomeLabels[k]}</option>)}</select></Field>
      </div>
      {f.outcome !== "no_evidence" ? <Field id="cv-ev" label="What was found (required)"><Textarea id="cv-ev" className="bg-background" maxLength={2000} value={f.evidence} onChange={set("evidence")} /></Field> : null}
      <Field id="cv-act" label="Action taken (optional)"><Textarea id="cv-act" className="bg-background" maxLength={2000} value={f.action} onChange={set("action")} /></Field>
      <p className="text-xs text-muted-foreground">Inspections are kept as recorded. To correct one, record it again with a note.</p>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || !ok}>{save.isPending ? "Saving…" : "Save inspection"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}

function FollowUpForm({ ws, sites, conveyance, onDone }: { ws: string; sites: Site[]; conveyance: Conveyance | null; onDone: () => void }) {
  const refresh = useRefresh(ws);
  const id = useRef(newId());
  const [site, setSite] = useState(conveyance?.site_id ?? sites[0]?.id ?? "");
  const [f, setF] = useState({ to: conveyance?.next_destination ?? "", sent_on: todayIso(), method: "email" as FollowUp["method"],
    summary: conveyance ? [conveyance.evidence, conveyance.action_taken && `Action: ${conveyance.action_taken}`].filter(Boolean).join(". ") : "" });
  const save = useMutation({ mutationFn: () => run(ihrRpc.sendFollowUp(id.current, site, conveyance?.id ?? null, f)), onSuccess: () => { refresh(); onDone(); } });
  return (
    <form className={`mt-2 ${formClass}`} onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-3 sm:grid-cols-3">
        {conveyance ? null : <Field id="fu-site" label="Site"><select id="fu-site" className={selectClass} value={site} onChange={(e) => setSite(e.target.value)}>{sites.map((s) => <option key={s.id} value={s.id}>{siteLabel(s)}</option>)}</select></Field>}
        <Field id="fu-to" label="To (next point of entry)"><Input id="fu-to" className="bg-background" maxLength={200} value={f.to} onChange={(e) => setF({ ...f, to: e.target.value })} /></Field>
        <Field id="fu-on" label="Sent on"><Input id="fu-on" type="date" max={todayIso()} className="bg-background" value={f.sent_on} onChange={(e) => setF({ ...f, sent_on: e.target.value })} /></Field>
        <Field id="fu-how" label="How"><select id="fu-how" className={selectClass} value={f.method} onChange={(e) => setF({ ...f, method: e.target.value as FollowUp["method"] })}>
          {(Object.keys(followUpMethodLabels) as FollowUp["method"][]).map((k) => <option key={k} value={k}>{followUpMethodLabels[k]}</option>)}</select></Field>
      </div>
      <Field id="fu-sum" label="What was said"><Textarea id="fu-sum" className="bg-background" maxLength={2000} value={f.summary} onChange={(e) => setF({ ...f, summary: e.target.value })} /></Field>
      <p className="text-xs text-muted-foreground">This records a notice you sent yourself. Vectovia does not send it.</p>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || f.to.trim().length < 2 || f.summary.trim().length < 5}>{save.isPending ? "Saving…" : "Save notice"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}

function FollowUpRow({ ws, f, canRecord, sites, conveyance }: { ws: string; f: FollowUp; canRecord: boolean; sites: Site[]; conveyance: Conveyance | undefined }) {
  const refresh = useRefresh(ws);
  const [acking, setAcking] = useState(false);
  const [on, setOn] = useState(todayIso());
  const [note, setNote] = useState("");
  const ack = useMutation({ mutationFn: () => run(ihrRpc.acknowledge(f.id, on, note)), onSuccess: () => { refresh(); setAcking(false); } });
  const late = !f.acknowledged_on && (Date.now() - new Date(f.sent_on).getTime()) / 86_400_000 > 14;
  return (
    <li className="px-3 py-2">
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <StatusTag strong={late}>{f.acknowledged_on ? `Acknowledged ${day(f.acknowledged_on)}` : late ? "▲ Not acknowledged after 14 days" : "Awaiting acknowledgement"}</StatusTag>
        <span className="font-medium text-primary">To {f.to_point_of_entry}</span>
        <span className="text-xs text-muted-foreground">{followUpMethodLabels[f.method]} · sent {day(f.sent_on)} · {siteLabel(sites.find((s) => s.id === f.site_id))}{conveyance ? ` · ${conveyanceTypeLabels[conveyance.conveyance_type]} ${conveyance.identifier}` : ""}</span>
        {canRecord && !f.acknowledged_on && !acking ? <button type="button" className="ml-auto text-primary underline" onClick={() => setAcking(true)}>Record acknowledgement</button> : null}
      </div>
      <p className="text-xs text-primary">{f.summary}</p>
      {acking ? (
        <div className="mt-2 flex flex-wrap items-end gap-2">
          <Field id={`ack-on-${f.id}`} label="Acknowledged on"><Input id={`ack-on-${f.id}`} type="date" min={f.sent_on} max={todayIso()} className="w-44 bg-background" value={on} onChange={(e) => setOn(e.target.value)} /></Field>
          <Field id={`ack-n-${f.id}`} label="Note (optional)"><Input id={`ack-n-${f.id}`} className="w-64 max-w-full bg-background" maxLength={1000} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
          <button type="button" className={btn} disabled={ack.isPending} onClick={() => ack.mutate()}>Save</button>
          <button type="button" className="text-sm text-primary underline" onClick={() => setAcking(false)}>Cancel</button>
          {ack.isError ? <ErrorState error={ack.error} /> : null}
        </div>
      ) : null}
    </li>
  );
}

// ---------- Incoming risks ---------------------------------------------------------------------------
const levelLabels: Record<IncomingRisk["level"], string> = { low: "Low", medium: "Medium", high: "High" };
function RisksTab({ ws, canRecord, sites }: Ctx) {
  const q = useIncomingRisks(ws);
  const [editing, setEditing] = useState<IncomingRisk | "new" | null>(null);
  const [closing, setClosing] = useState<string | null>(null);
  return (
    <Section title="Incoming risks" intro="Risks arriving at the site, for example from conveyances, cargo or alerts, with the action taken and liaison. Linked to IHR provision 12."
      action={canRecord && !editing ? <button type="button" className={primaryBtn} onClick={() => setEditing("new")}>Log a risk</button> : null}>
      {editing ? <RiskForm ws={ws} sites={sites} current={editing === "new" ? null : editing} onDone={() => setEditing(null)} /> : null}
      {q.isError ? <ErrorState error={q.error} /> : !q.data ? <Loading /> : q.data.length === 0 ? <EmptyState title="Nothing logged">Log an incoming risk with “Log a risk”.</EmptyState> : (
        <ul className="divide-y divide-border rounded-md border border-border text-sm">
          {q.data.map((r) => (
            <li key={r.id} className={`px-3 py-2 ${r.status === "closed" ? "opacity-60" : ""}`}>
              <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <StatusTag strong={r.status === "open" && r.level === "high"}>{r.status === "closed" ? `Closed ${day(r.closed_on)}` : `${levelLabels[r.level]} · open`}</StatusTag>
                <span className="font-medium text-primary">{r.source}</span>
                <span className="text-xs text-muted-foreground">{day(r.reported_on)} · {siteLabel(sites.find((s) => s.id === r.site_id))}</span>
                {r.status === "open" && r.level === "high" && !r.action ? <StatusTag strong>▲ No action recorded</StatusTag> : null}
                {canRecord && r.status === "open" ? (
                  <span className="ml-auto flex gap-3">
                    <button type="button" className="text-primary underline" onClick={() => setEditing(r)}>{r.action ? "Update" : "Add the action"}</button>
                    <button type="button" className="text-primary underline" onClick={() => setClosing(r.id)}>Close</button>
                  </span>
                ) : null}
              </div>
              <p className="text-xs text-primary">{r.description}</p>
              {r.action ? <p className="text-xs text-muted-foreground">Action: {r.action}</p> : null}
              {r.closed_note ? <p className="text-xs text-muted-foreground">Resolved: {r.closed_note}</p> : null}
              {closing === r.id ? <CloseRisk ws={ws} risk={r} onDone={() => setClosing(null)} /> : null}
            </li>
          ))}
        </ul>
      )}
    </Section>
  );
}

function RiskForm({ ws, sites, current, onDone }: { ws: string; sites: Site[]; current: IncomingRisk | null; onDone: () => void }) {
  const refresh = useRefresh(ws);
  const id = useRef(current?.id ?? newId());
  const [site, setSite] = useState(current?.site_id ?? sites[0]?.id ?? "");
  const [f, setF] = useState({ reported_on: current?.reported_on ?? todayIso(), source: current?.source ?? "", description: current?.description ?? "",
    level: current?.level ?? ("medium" as IncomingRisk["level"]), action: current?.action ?? "" });
  const [reason, setReason] = useState("");
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF((x) => ({ ...x, [k]: e.target.value }));
  const reported = current && (current.reported_on !== f.reported_on || current.source !== f.source.trim() || current.description !== f.description.trim() || current.level !== f.level);
  const save = useMutation({ mutationFn: () => run(ihrRpc.saveIncomingRisk(id.current, site, f, reason)), onSuccess: () => { refresh(); onDone(); } });
  const ok = site && f.source.trim().length >= 2 && f.description.trim().length >= 5 && (!reported || reason.trim().length >= 5);
  return (
    <form className={formClass} onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-3 sm:grid-cols-3">
        {current ? null : <Field id="ir-site" label="Site"><select id="ir-site" className={selectClass} value={site} onChange={(e) => setSite(e.target.value)}>{sites.map((s) => <option key={s.id} value={s.id}>{siteLabel(s)}</option>)}</select></Field>}
        <Field id="ir-on" label="Reported on"><Input id="ir-on" type="date" max={todayIso()} className="bg-background" value={f.reported_on} onChange={set("reported_on")} /></Field>
        <Field id="ir-src" label="Source" hint="For example: shipping line, UKHSA alert, airline."><Input id="ir-src" className="bg-background" maxLength={200} value={f.source} onChange={set("source")} /></Field>
        <Field id="ir-lvl" label="Level"><select id="ir-lvl" className={selectClass} value={f.level} onChange={set("level")}>
          {(["low", "medium", "high"] as const).map((k) => <option key={k} value={k}>{levelLabels[k]}</option>)}</select></Field>
      </div>
      <Field id="ir-desc" label="What the risk is"><Textarea id="ir-desc" className="bg-background" maxLength={2000} value={f.description} onChange={set("description")} /></Field>
      <Field id="ir-act" label="Action and liaison (optional)"><Textarea id="ir-act" className="bg-background" maxLength={2000} value={f.action} onChange={set("action")} /></Field>
      {reported ? <Reason id="ir-why" value={reason} onChange={setReason} /> : null}
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || !ok}>{save.isPending ? "Saving…" : "Save"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}

function CloseRisk({ ws, risk, onDone }: { ws: string; risk: IncomingRisk; onDone: () => void }) {
  const refresh = useRefresh(ws);
  const [on, setOn] = useState(todayIso());
  const [note, setNote] = useState("");
  const go = useMutation({ mutationFn: () => run(ihrRpc.closeIncomingRisk(risk.id, on, note)), onSuccess: () => { refresh(); onDone(); } });
  return (
    <div className="mt-2 flex flex-wrap items-end gap-2">
      <Field id={`cl-on-${risk.id}`} label="Closed on"><Input id={`cl-on-${risk.id}`} type="date" min={risk.reported_on} max={todayIso()} className="w-44 bg-background" value={on} onChange={(e) => setOn(e.target.value)} /></Field>
      <Field id={`cl-n-${risk.id}`} label="How it was resolved (required)"><Input id={`cl-n-${risk.id}`} className="w-72 max-w-full bg-background" maxLength={1000} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
      <button type="button" className={btn} disabled={go.isPending || note.trim().length < 5} onClick={() => go.mutate()}>Close risk</button>
      <button type="button" className="text-sm text-primary underline" onClick={onDone}>Cancel</button>
      {go.isError ? <ErrorState error={go.error} /> : null}
    </div>
  );
}

// ---------- Site reviews -------------------------------------------------------------------------------
function ReviewsTab({ ws, canManage, sites }: Ctx) {
  const q = useSiteReviews(ws);
  const [open, setOpen] = useState(false);
  return (
    <Section title="Site reviews" intro="Yearly sanitary and vector surveys, wider surveys every 3 years, reports to the site operator and effectiveness reviews with corrective actions. Linked to IHR provisions 2, 7, 11 and 17."
      action={canManage && !open ? <button type="button" className={primaryBtn} onClick={() => setOpen(true)}>Record a review</button> : null}>
      {open ? <ReviewForm ws={ws} sites={sites} onDone={() => setOpen(false)} /> : null}
      {q.isError ? <ErrorState error={q.error} /> : !q.data ? <Loading /> : q.data.length === 0 ? <EmptyState title="No reviews recorded">Record one with “Record a review”.</EmptyState> : (
        <ul className="divide-y divide-border rounded-md border border-border text-sm">
          {q.data.map((r) => (
            <li key={r.id} className="px-3 py-2">
              <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <ExpiryTag date={r.next_due} label="Next due" />
                <span className="font-medium text-primary">{reviewKindLabels[r.kind]}</span>
                <span className="text-xs text-muted-foreground">{day(r.done_on)} · {siteLabel(sites.find((s) => s.id === r.site_id))}</span>
              </div>
              <p className="text-xs text-primary">{r.summary}</p>
              {r.corrective_actions ? <p className="text-xs text-muted-foreground">Corrective actions: {r.corrective_actions}</p> : null}
            </li>
          ))}
        </ul>
      )}
    </Section>
  );
}

function ReviewForm({ ws, sites, onDone }: { ws: string; sites: Site[]; onDone: () => void }) {
  const refresh = useRefresh(ws);
  const id = useRef(newId());
  const [site, setSite] = useState(sites[0]?.id ?? "");
  const [f, setF] = useState({ kind: "sanitary_survey" as ReviewKind, done_on: todayIso(), summary: "", corrective: "", next_due: "" });
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF((x) => ({ ...x, [k]: e.target.value }));
  const save = useMutation({ mutationFn: () => run(ihrRpc.recordReview(id.current, site, f)), onSuccess: () => { refresh(); onDone(); } });
  return (
    <form className={formClass} onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <div className="grid gap-3 sm:grid-cols-3">
        <Field id="rv-site" label="Site"><select id="rv-site" className={selectClass} value={site} onChange={(e) => setSite(e.target.value)}>{sites.map((s) => <option key={s.id} value={s.id}>{siteLabel(s)}</option>)}</select></Field>
        <Field id="rv-kind" label="Kind"><select id="rv-kind" className={selectClass} value={f.kind} onChange={set("kind")}>
          {(Object.keys(reviewKindLabels) as ReviewKind[]).map((k) => <option key={k} value={k}>{reviewKindLabels[k]}</option>)}</select></Field>
        <Field id="rv-on" label="Done on"><Input id="rv-on" type="date" max={todayIso()} className="bg-background" value={f.done_on} onChange={set("done_on")} /></Field>
      </div>
      <Field id="rv-sum" label="Summary"><Textarea id="rv-sum" className="bg-background" maxLength={5000} value={f.summary} onChange={set("summary")} /></Field>
      <Field id="rv-ca" label="Corrective actions (optional)"><Textarea id="rv-ca" className="bg-background" maxLength={5000} value={f.corrective} onChange={set("corrective")} /></Field>
      <Field id="rv-next" label="Next due (optional)" hint="Leave blank for the usual interval: 3 years for a wider survey, otherwise a year."><Input id="rv-next" type="date" className="w-48 bg-background" value={f.next_due} onChange={set("next_due")} /></Field>
      <p className="text-xs text-muted-foreground">Reviews are kept as recorded.</p>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" className={primaryBtn} disabled={save.isPending || !site || f.summary.trim().length < 10}>{save.isPending ? "Saving…" : "Save review"}</button>
        <button type="button" className={btn} onClick={onDone}>Cancel</button>
      </div>
    </form>
  );
}
