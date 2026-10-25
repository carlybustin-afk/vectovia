import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useRef, useState } from "react";
import { AppShell, EmptyState, ErrorState, Loading, appHead } from "@/components/app-shell";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { useSession } from "@/lib/session";
import { newId, programmeStatusLabels, run, vvRpc, type Programme, type Team } from "@/modules/vectovia/api";
import { Field, History, StatusTag, selectClass, useLists, useProgrammes, useTeams, useVv } from "@/modules/vectovia/ui";

export const Route = createFileRoute("/app/vectovia/setup")({
  head: () => appHead("Set-up · Vectovia", "Surveillance programmes, and the species and trap types your council uses."),
  component: SetupPage,
});

function SetupPage() {
  return (
    <AppShell product="vectovia" section="vectovia" title="Set-up"
      intro="Programmes and the lists your officers choose from. Managers make changes; everyone with Vectovia access can see them.">
      <Setup />
    </AppShell>
  );
}

function Setup() {
  const { ws, canManage } = useVv();
  const programmes = useProgrammes(ws);
  const teams = useTeams(ws);
  const [open, setOpen] = useState<string | "new" | null>(null);
  if (programmes.isPending || teams.isPending) return <Loading />;
  if (programmes.isError) return <ErrorState error={programmes.error} />;
  if (teams.isError) return <ErrorState error={teams.error} />;
  return (
    <div className="space-y-10">
      <section aria-labelledby="pr-h" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 id="pr-h" className="text-lg font-semibold text-primary">Programmes</h2>
          {canManage ? <button type="button" onClick={() => setOpen("new")} className="rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy">New programme</button> : null}
        </div>
        <p className="text-sm text-muted-foreground">Each programme is run by one or more teams. Members see the programmes their teams run; owners, admins and Vectovia managers see all of them.</p>
        {open === "new" ? <ProgrammeForm ws={ws} teams={teams.data} onDone={() => setOpen(null)} /> : null}
        {programmes.data.length === 0 ? <EmptyState title="No programmes yet">{canManage ? "Create the first one, for example “Port mosquito surveillance 2026”." : "A manager sets up programmes."}</EmptyState> : (
          <ul className="divide-y divide-border rounded-md border border-border">
            {programmes.data.map((p) => (
              <li key={p.id}>
                <button type="button" aria-expanded={open === p.id} onClick={() => setOpen(open === p.id ? null : p.id)} className="flex w-full flex-wrap items-baseline gap-3 px-3 py-2.5 text-left hover:bg-secondary/60">
                  <span className="font-semibold text-primary">{p.name}</span>
                  <StatusTag strong={p.status === "active"}>{programmeStatusLabels[p.status]}</StatusTag>
                  <span className="text-xs text-muted-foreground">
                    Mosquito · {p.teams.length ? `run by ${p.teams.map((t) => teams.data.find((x) => x.id === t)?.name).filter(Boolean).join(", ")}` : "no team yet (only managers see it)"}
                    {p.starts_on ? ` · from ${p.starts_on}` : ""}{p.ends_on ? ` to ${p.ends_on}` : ""}
                  </span>
                </button>
                {open === p.id ? <ProgrammeDetail ws={ws} programme={p} teams={teams.data} canManage={canManage} /> : null}
              </li>
            ))}
          </ul>
        )}
      </section>
      <Lists />
    </div>
  );
}

function ProgrammeDetail({ ws, programme, teams, canManage }: { ws: string; programme: Programme; teams: Team[]; canManage: boolean }) {
  const { session } = useSession();
  const [editing, setEditing] = useState(false);
  return (
    <div className="space-y-2 border-t border-border bg-background p-3 text-sm">
      {editing ? <ProgrammeForm ws={ws} programme={programme} teams={teams} onDone={() => setEditing(false)} /> : (
        <>
          {programme.description ? <p className="text-primary">{programme.description}</p> : null}
          {canManage ? <button type="button" onClick={() => setEditing(true)} className="rounded-md border border-primary px-3 py-1.5 text-sm font-medium text-primary">Edit programme</button> : null}
        </>
      )}
      <History type="programme" id={programme.id} ws={ws} uid={session?.user.id} labels={{ starts_on: "start", ends_on: "end" }} />
    </div>
  );
}

function ProgrammeForm({ ws, programme, teams, onDone }: { ws: string; programme?: Programme; teams: Team[]; onDone: () => void }) {
  const qc = useQueryClient();
  const id = useRef(programme?.id ?? newId());
  const [v, setV] = useState({
    name: programme?.name ?? "", description: programme?.description ?? "", status: programme?.status ?? ("active" as Programme["status"]),
    starts_on: programme?.starts_on ?? "", ends_on: programme?.ends_on ?? "", teams: programme?.teams ?? [],
  });
  const save = useMutation({
    mutationFn: () => run(vvRpc.saveProgramme(id.current, ws, { ...v, starts_on: v.starts_on || null, ends_on: v.ends_on || null })),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ["ws", ws, "vv"] }); onDone(); },
  });
  return (
    <form className="space-y-3 rounded-md border-t-2 border-accent bg-secondary p-4" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
      <p className="font-semibold text-primary">{programme ? `Edit ${programme.name}` : "New programme"}</p>
      <div className="grid gap-3 sm:grid-cols-2">
        <Field id="pf-name" label="Name"><Input id="pf-name" className="bg-background" maxLength={120} value={v.name} onChange={(e) => setV({ ...v, name: e.target.value })} placeholder="e.g. Port mosquito surveillance 2026" /></Field>
        <Field id="pf-status" label="Status">
          <select id="pf-status" className={selectClass} value={v.status} onChange={(e) => setV({ ...v, status: e.target.value as Programme["status"] })}>
            <option value="active">Active</option><option value="paused">Paused</option><option value="closed">Closed</option>
          </select>
        </Field>
        <Field id="pf-start" label="Starts (optional)"><Input id="pf-start" type="date" className="bg-background" value={v.starts_on} onChange={(e) => setV({ ...v, starts_on: e.target.value })} /></Field>
        <Field id="pf-end" label="Ends (optional)"><Input id="pf-end" type="date" className="bg-background" value={v.ends_on} min={v.starts_on || undefined} onChange={(e) => setV({ ...v, ends_on: e.target.value })} /></Field>
      </div>
      <Field id="pf-desc" label="Description (optional)"><Textarea id="pf-desc" className="bg-background" maxLength={2000} value={v.description} onChange={(e) => setV({ ...v, description: e.target.value })} /></Field>
      <fieldset>
        <legend className="text-sm font-medium text-primary">Run by</legend>
        {!teams.length ? <p className="text-xs text-muted-foreground">Your council has no teams yet. An owner or admin adds them in Council settings → Teams.</p> : (
          <div className="mt-1 flex flex-wrap gap-3">
            {teams.map((t) => (
              <label key={t.id} className="flex items-center gap-2 text-sm">
                <input type="checkbox" checked={v.teams.includes(t.id)} onChange={(e) => { const on = e.target.checked; setV({ ...v, teams: on ? [...v.teams, t.id] : v.teams.filter((x) => x !== t.id) }); }} />{t.name}
              </label>
            ))}
          </div>
        )}
      </fieldset>
      {save.isError ? <ErrorState error={save.error} /> : null}
      <div className="flex gap-2">
        <button type="submit" disabled={save.isPending || v.name.trim().length < 3} className="rounded-md bg-signal-teal px-4 py-2 text-sm font-semibold text-deep-navy disabled:opacity-60">{programme ? "Save changes" : "Create programme"}</button>
        <button type="button" onClick={onDone} className="rounded-md border border-primary px-4 py-2 text-sm text-primary">Cancel</button>
      </div>
    </form>
  );
}

function Lists() {
  const { ws, canManage } = useVv();
  const qc = useQueryClient();
  const lists = useLists(ws);
  const [species, setSpecies] = useState({ scientific: "", common: "" });
  const [trapType, setTrapType] = useState({ name: "", description: "" });
  const ids = useRef({ s: newId(), t: newId() });
  const act = useMutation({
    mutationFn: (fn: () => Promise<unknown>) => fn(),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["ws", ws, "vv"] }),
  });
  if (lists.isPending) return <Loading />;
  if (lists.isError) return <ErrorState error={lists.error} />;
  const l = lists.data;
  const unchecked = l.taxa.some((t) => !t.checked) || l.trapTypes.some((t) => !t.checked);
  return (
    <section aria-labelledby="ls-h" className="space-y-4">
      <h2 id="ls-h" className="text-lg font-semibold text-primary">Species and trap types</h2>
      {unchecked ? (
        <p className="rounded-md border-l-4 border-accent bg-secondary p-3 text-sm text-primary">
          The standard lists are a <strong>starter list, not yet checked</strong> by a qualified entomologist. Use them for set-up and testing; they'll be marked as checked once reviewed.
        </p>
      ) : null}
      {act.isError ? <ErrorState error={act.error} /> : null}
      <div className="grid gap-6 lg:grid-cols-2">
        <div className="space-y-2">
          <h3 className="font-semibold text-primary">Species</h3>
          <ul className="space-y-1 text-sm">
            {l.taxa.map((t) => <li key={t.id}><em>{t.scientific_name}</em>{t.common_name ? ` · ${t.common_name}` : ""}{t.invasive ? <span className="ml-2"><StatusTag strong>Invasive</StatusTag></span> : null}</li>)}
            {l.councilTaxa.map((t) => <li key={t.id}><em>{t.scientific_name}</em>{t.common_name ? ` · ${t.common_name}` : ""} <span className="text-xs text-muted-foreground">(your council{t.active ? "" : ", not in use"})</span></li>)}
          </ul>
          {canManage ? (
            <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); act.mutate(async () => { await run(vvRpc.saveCouncilTaxon(ids.current.s, ws, species.scientific, species.common, true)); ids.current.s = newId(); setSpecies({ scientific: "", common: "" }); }); }}>
              <Field id="ct-s" label="Add a species (your council only)"><Input id="ct-s" className="w-56" maxLength={120} value={species.scientific} onChange={(e) => setSpecies({ ...species, scientific: e.target.value })} placeholder="Scientific name" /></Field>
              <Input aria-label="Common name (optional)" className="w-44" maxLength={120} value={species.common} onChange={(e) => setSpecies({ ...species, common: e.target.value })} placeholder="Common name (optional)" />
              <button type="submit" disabled={species.scientific.trim().length < 3 || act.isPending} className="h-9 rounded-md border border-primary px-3 text-sm text-primary disabled:opacity-60">Add</button>
            </form>
          ) : null}
        </div>
        <div className="space-y-2">
          <h3 className="font-semibold text-primary">Trap types</h3>
          <ul className="space-y-1 text-sm">
            {l.trapTypes.map((t) => <li key={t.id}><strong className="text-primary">{t.name}</strong>{t.description ? <span className="text-muted-foreground"> · {t.description}</span> : null}</li>)}
            {l.councilTrapTypes.map((t) => <li key={t.id}><strong className="text-primary">{t.name}</strong> <span className="text-xs text-muted-foreground">(your council{t.active ? "" : ", not in use"})</span></li>)}
          </ul>
          {canManage ? (
            <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); act.mutate(async () => { await run(vvRpc.saveCouncilTrapType(ids.current.t, ws, trapType.name, trapType.description, true)); ids.current.t = newId(); setTrapType({ name: "", description: "" }); }); }}>
              <Field id="ct-t" label="Add a trap type (your council only)"><Input id="ct-t" className="w-56" maxLength={120} value={trapType.name} onChange={(e) => setTrapType({ ...trapType, name: e.target.value })} placeholder="Name" /></Field>
              <Input aria-label="Description (optional)" className="w-44" maxLength={500} value={trapType.description} onChange={(e) => setTrapType({ ...trapType, description: e.target.value })} placeholder="Description (optional)" />
              <button type="submit" disabled={trapType.name.trim().length < 3 || act.isPending} className="h-9 rounded-md border border-primary px-3 text-sm text-primary disabled:opacity-60">Add</button>
            </form>
          ) : null}
        </div>
      </div>
      <p className="text-xs text-muted-foreground">Your council's additions are private to your council and are never added to the standard lists.</p>
    </section>
  );
}
