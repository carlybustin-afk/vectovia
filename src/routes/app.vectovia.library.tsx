import { createFileRoute, Link } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRef, useState, type ReactNode } from "react";
import { z } from "zod";
import { AppShell, EmptyState, ErrorState, Loading, StateMessage, appHead } from "@/components/app-shell";
import { Textarea } from "@/components/ui/textarea";
import { wsKey } from "@/lib/workspace";
import { newId, run } from "@/modules/vectovia/api";
import { useSession } from "@/lib/session";
import {
  copyPhoto, libRpc, loadContentRoles, loadLibrary, loadLibraryNotes, pageFor, photosToCopy, saveLibraryNote, statusNote, storedImageUrl, workingVersion,
  type LibImage, type LibVersion, type StoredImage,
} from "@/modules/vectovia/library";
import { StatusTag, useLists, useVv } from "@/modules/vectovia/ui";

const search = z.object({ kind: z.enum(["species", "trap"]).optional(), id: z.string().uuid().optional() });

export const Route = createFileRoute("/app/vectovia/library")({
  validateSearch: (s) => search.parse(s),
  head: () => appHead("Library · Vectovia", "Species and trap library: identification, breeding habitats, best traps, how traps work."),
  component: LibraryPage,
});

function LibraryPage() {
  return (
    <AppShell product="vectovia" section="vectovia" title="Library"
      intro="Species and trap pages: how to recognise each species, where it breeds, and which traps work best; and how each trap works and is best set. Shared reference content, checked by a qualified entomologist before councils rely on it.">
      <Library />
    </AppShell>
  );
}

function Library() {
  const { ws, canRecord } = useVv();
  const { kind = "species", id } = Route.useSearch();
  const lists = useLists(ws);
  const lib = useQuery({ queryKey: ["vv-library"], queryFn: loadLibrary, staleTime: 5 * 60_000 });
  const notes = useQuery({ queryKey: wsKey(ws, "vv", "library-notes"), queryFn: () => loadLibraryNotes(ws) });
  if (lists.isPending || lib.isPending) return <Loading what="Loading the library" />;
  if (lists.isError) return <ErrorState error={lists.error} />;
  if (lib.isError) return <ErrorState error={lib.error} />;
  if (lib.data === null) return <StateMessage title="The library isn't switched on yet">Once the library update is applied, species and trap pages appear here.</StateMessage>;
  const versions = lib.data.versions;
  const subjects = kind === "species"
    ? lists.data.taxa.map((t) => ({ id: t.id, key: t.key, title: t.scientific_name, sub: t.common_name, flag: t.invasive ? "Invasive" : null }))
    : lists.data.trapTypes.map((t) => ({ id: t.id, key: t.key, title: t.name, sub: null as string | null, flag: null as string | null }));
  const chosen = id ? subjects.find((s) => s.id === id) : undefined;

  return (
    <div className="space-y-5">
      <div role="tablist" aria-label="Library sections" className="flex gap-1 border-b border-border">
        {(["species", "trap"] as const).map((k) => (
          <Link key={k} role="tab" aria-selected={kind === k} to="/app/vectovia/library" search={{ kind: k }}
            className={`-mb-px border-b-2 px-4 py-2 text-sm font-medium ${kind === k ? "border-accent text-primary" : "border-transparent text-muted-foreground hover:text-primary"}`}>
            {k === "species" ? "Species" : "Traps"}
          </Link>
        ))}
      </div>
      {chosen ? (
        <>
          <ContentTeam kind={kind} subject={chosen.id} page={pageFor(versions, kind, chosen.id)} working={workingVersion(versions, kind, chosen.id)} images={lib.data.images} />
          <Page kind={kind} subject={chosen} page={pageFor(versions, kind, chosen.id)} images={lib.data.images} lists={lists.data}
            ws={ws} canRecord={canRecord} note={notes.data?.find((n) => n.kind === kind && (kind === "species" ? n.taxon_id : n.trap_type_id) === chosen.id)} />
        </>
      ) : (
        <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {subjects.map((s) => {
            const page = pageFor(versions, kind, s.id);
            const img = page ? firstImage(page, lib.data!.images) : null;
            return (
              <li key={s.id}>
                <Link to="/app/vectovia/library" search={{ kind, id: s.id }} className="block h-full overflow-hidden rounded-md border border-border hover:border-accent">
                  {img ? <img src={img.url} alt={`${s.title}${img.caption ? `: ${img.caption}` : ""}`} loading="lazy" className="h-40 w-full bg-secondary object-cover" />
                    : <div className="flex h-40 items-center justify-center bg-secondary text-xs text-muted-foreground">No photo yet</div>}
                  <div className="space-y-1 p-3">
                    <p className="font-semibold text-primary">{kind === "species" ? <em>{s.title}</em> : s.title}</p>
                    {s.sub ? <p className="text-sm text-muted-foreground">{s.sub}</p> : null}
                    <div className="flex flex-wrap gap-1">
                      {s.flag ? <StatusTag strong>{s.flag}</StatusTag> : null}
                      {!page ? <StatusTag>Page not written yet</StatusTag> : statusNote(page.status) ? <StatusTag>{statusNote(page.status)}</StatusTag> : null}
                    </div>
                  </div>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

function firstImage(page: LibVersion, stored: StoredImage[]): LibImage | null {
  const s = stored.find((i) => i.version_id === page.id);
  if (s) return { url: storedImageUrl(s.storage_path), credit: s.credit, licence: s.licence, source_url: s.source_url, caption: s.caption };
  return page.content.images?.[0] ?? null;
}

function Page({ kind, subject, page, images, lists, ws, canRecord, note }: {
  kind: "species" | "trap"; subject: { id: string; key: string; title: string; sub: string | null; flag: string | null };
  page: LibVersion | null; images: StoredImage[]; lists: import("@/modules/vectovia/api").Lists; ws: string; canRecord: boolean;
  note: import("@/modules/vectovia/library").LibNote | undefined;
}) {
  const c = page?.content;
  const pics: LibImage[] = page ? [
    ...images.filter((i) => i.version_id === page.id).map((i) => ({ url: storedImageUrl(i.storage_path), credit: i.credit, licence: i.licence, source_url: i.source_url, caption: i.caption })),
    ...photosToCopy(page, images),
  ] : [];
  const trapByKey = (k: string) => lists.trapTypes.find((t) => t.key === k);
  const taxonByKey = (k: string) => lists.taxa.find((t) => t.key === k);
  return (
    <article className="space-y-5">
      <Link to="/app/vectovia/library" search={{ kind }} className="text-sm text-primary underline">← All {kind === "species" ? "species" : "traps"}</Link>
      <header className="space-y-1">
        <h2 className="text-2xl font-bold tracking-tight text-primary">{kind === "species" ? <em>{subject.title}</em> : subject.title}</h2>
        {subject.sub ? <p className="text-muted-foreground">{subject.sub}</p> : null}
        <div className="flex flex-wrap gap-1">
          {subject.flag ? <StatusTag strong>{subject.flag}</StatusTag> : null}
          {page && statusNote(page.status) ? <StatusTag strong>{statusNote(page.status)}</StatusTag> : null}
        </div>
      </header>
      {!page || !c ? <EmptyState title="This page hasn't been written yet">It will appear here once drafted and reviewed.</EmptyState> : (
        <>
          {statusNote(page.status) ? (
            <p className="rounded-md border-l-4 border-accent bg-secondary p-3 text-sm text-primary">This page is a draft for review. Don't rely on it until a qualified entomologist has checked it and First Line has approved it.</p>
          ) : null}
          {pics.length ? (
            <div className="grid gap-3 sm:grid-cols-2">
              {pics.map((p, i) => (
                <figure key={i} className="overflow-hidden rounded-md border border-border">
                  <img src={p.url} alt={`${subject.title}${p.caption ? `: ${p.caption}` : ""}`} loading="lazy" className="max-h-80 w-full bg-secondary object-contain" />
                  <figcaption className="p-2 text-xs text-muted-foreground">
                    {p.caption ? <span className="text-primary">{p.caption}. </span> : null}
                    Photo: {p.credit}, <a href={p.source_url} target="_blank" rel="noreferrer noopener" className="underline">{p.licence}</a>
                  </figcaption>
                </figure>
              ))}
            </div>
          ) : null}
          <p className="text-primary">{c.summary}</p>
          {kind === "species" ? (
            <div className="grid gap-5 md:grid-cols-2">
              <Section title="How to recognise it" items={c.identification} />
              <Section title="Where it breeds" items={c.breeding_habitats} />
              <Section title="When it's active">{[c.activity, c.season].filter(Boolean).map((t) => <p key={t}>{t}</p>)}</Section>
              <Section title="UK status">{c.uk_status ? <p>{c.uk_status}</p> : null}</Section>
              <Section title="Diseases it can carry" items={c.diseases} />
              <Section title="Best traps">
                {c.best_traps?.length ? (
                  <ul className="list-disc space-y-0.5 pl-5">
                    {c.best_traps.map((k) => { const t = trapByKey(k); return <li key={k}>{t ? <Link to="/app/vectovia/library" search={{ kind: "trap", id: t.id }} className="underline">{t.name}</Link> : k}</li>; })}
                  </ul>
                ) : null}
                {c.lures?.length ? <p className="mt-1 text-muted-foreground">Lures: {c.lures.join("; ")}</p> : null}
              </Section>
            </div>
          ) : (
            <div className="grid gap-5 md:grid-cols-2">
              <Section title="How it works">{c.how_it_works ? <p>{c.how_it_works}</p> : null}</Section>
              <Section title="Good for">
                {c.targets?.length ? (
                  <ul className="list-disc space-y-0.5 pl-5">
                    {c.targets.map((k) => { const t = taxonByKey(k); return <li key={k}>{t ? <Link to="/app/vectovia/library" search={{ kind: "species", id: t.id }} className="underline"><em>{t.scientific_name}</em></Link> : k}</li>; })}
                  </ul>
                ) : null}
                {c.life_stages?.length ? <p className="mt-1 text-muted-foreground">Life stages: {c.life_stages.join(", ")}</p> : null}
              </Section>
              <Section title="Setting it up" items={c.setup} />
              <Section title="Where to place it" items={c.placement} />
              <Section title="Servicing">{c.servicing ? <p>{c.servicing}</p> : null}</Section>
              <Section title="Tips" items={c.tips} />
              <Section title="Common mistakes" items={c.common_mistakes} />
            </div>
          )}
          {c.notes ? <p className="text-sm text-muted-foreground">{c.notes}</p> : null}
          {page.sources.length ? (
            <section aria-label="Sources" className="text-xs">
              <p className="font-semibold uppercase tracking-wide text-accent">Sources</p>
              <ul className="mt-1 list-disc space-y-0.5 pl-5">{page.sources.map((s) => <li key={s.url}><a href={s.url} target="_blank" rel="noreferrer noopener" className="underline">{s.title}</a></li>)}</ul>
            </section>
          ) : null}
        </>
      )}
      <CouncilNote ws={ws} kind={kind} subject={subject.id} note={note} canRecord={canRecord} />
    </article>
  );
}

/**
 * First Line's content team only (author, reviewer, final approver), never councils.
 * Same two-stage rule as Knowledge & Powers: the reviewer can't be the author, and
 * the final approver can't be either. The database enforces it; this only offers the next step.
 */
function ContentTeam({ kind, subject, page, working, images }: {
  kind: "species" | "trap"; subject: string; page: LibVersion | null; working: LibVersion | null; images: StoredImage[];
}) {
  const qc = useQueryClient();
  const { session } = useSession();
  const uid = session?.user.id;
  const roles = useQuery({ queryKey: ["content-roles", "vv", uid], enabled: !!uid, staleTime: 5 * 60_000, queryFn: loadContentRoles });
  const [note, setNote] = useState("");
  const [progress, setProgress] = useState<string | null>(null);
  const ids = useRef(new Map<string, string>());
  const refresh = () => qc.invalidateQueries({ queryKey: ["vv-library"] });
  const act = useMutation({
    mutationFn: async (step: "take" | "copy" | "submit" | "approve" | "reject" | "publish") => {
      const v = working ?? page;
      if (step === "take") return run(libRpc.saveDraft(kind, subject, v!.content, v!.sources));
      if (!working) throw new Error("Nothing to act on.");
      if (step === "copy") {
        const todo = photosToCopy(working, images);
        for (const [i, p] of todo.entries()) {
          setProgress(`Copying photo ${i + 1} of ${todo.length}`);
          if (!ids.current.has(p.source_url)) ids.current.set(p.source_url, newId());
          await copyPhoto(working.id, p, i, ids.current.get(p.source_url)!);
        }
        return;
      }
      if (step === "submit") return run(libRpc.submit(working.id));
      if (step === "publish") return run(libRpc.publish(working.id));
      return run(libRpc.review(working.id, step === "approve", note));
    },
    onSettled: () => { setProgress(null); refresh(); },
    onSuccess: () => setNote(""),
  });
  const r = roles.data;
  if (!r || !(r.author || r.reviewer || r.admin)) return null;
  const w = working;
  const mine = !!w && w.author_id === uid;
  const toCopy = w ? photosToCopy(w, images).length : 0;
  const btn = "rounded-md bg-signal-teal px-3 py-1.5 text-sm font-semibold text-deep-navy disabled:opacity-60";
  const btn2 = "rounded-md border border-primary px-3 py-1.5 text-sm text-primary disabled:opacity-60";
  let body: ReactNode = null;
  if (!w) {
    body = page && r.author
      ? <><p>This page is published. To change it, start a new draft from it.</p><button type="button" className={btn} disabled={act.isPending} onClick={() => act.mutate("take")}>Start a new draft</button></>
      : <p>{page ? "Published. No changes in progress." : "No draft for this page yet."}</p>;
  } else if (w.status === "draft" && !mine) {
    body = <>
      <p>Version {w.version} is a starter draft {w.author_id ? "written by someone else" : "loaded by First Line, with no author yet"}. An author needs to take it on before it can go for review.</p>
      {r.author ? <button type="button" className={btn} disabled={act.isPending} onClick={() => act.mutate("take")}>Take on this draft</button> : <p className="text-muted-foreground">Only an author can do this.</p>}
    </>;
  } else if (w.status === "draft") {
    body = <>
      <p>Your draft (version {w.version}).{toCopy ? ` ${toCopy} photo${toCopy > 1 ? "s are" : " is"} still shown from the source website. Copy ${toCopy > 1 ? "them" : "it"} into the library store before sending it for review, so the page doesn't depend on another website.` : " All photos are held in the library store."}</p>
      <div className="flex flex-wrap gap-2">
        {toCopy ? <button type="button" className={btn} disabled={act.isPending} onClick={() => act.mutate("copy")}>Copy {toCopy > 1 ? `${toCopy} photos` : "photo"} into the library</button> : null}
        <button type="button" className={toCopy ? btn2 : btn} disabled={act.isPending || toCopy > 0} onClick={() => act.mutate("submit")}>Send for review</button>
      </div>
      <p className="text-xs text-muted-foreground">Editing the page text on screen isn't built yet.</p>
    </>;
  } else if (w.status === "in_review") {
    body = r.reviewer && !mine ? <>
      <p>Version {w.version} is waiting for your review. Check the text, the photos and their credits, and the sources.</p>
      <label htmlFor="lib-note" className="block font-medium">Review note (required, at least 10 characters)</label>
      <Textarea id="lib-note" maxLength={4000} value={note} onChange={(e) => setNote(e.target.value)} className="bg-background" />
      <div className="flex flex-wrap gap-2">
        <button type="button" className={btn} disabled={act.isPending || note.trim().length < 10} onClick={() => act.mutate("approve")}>Approve</button>
        <button type="button" className={btn2} disabled={act.isPending || note.trim().length < 10} onClick={() => act.mutate("reject")}>Send back</button>
      </div>
    </> : <p>Version {w.version} is with the reviewer.{mine ? " You wrote it, so someone else must review it." : ""}</p>;
  } else if (w.status === "reviewed") {
    const can = r.admin && uid !== w.author_id && uid !== w.reviewer_id;
    body = <>
      <p>Version {w.version} has been reviewed.{w.review_note ? ` Reviewer's note: “${w.review_note}”` : ""}</p>
      {can ? <button type="button" className={btn} disabled={act.isPending} onClick={() => act.mutate("publish")}>Publish to councils</button>
        : <p className="text-muted-foreground">Final approval must come from a content admin who neither wrote nor reviewed it.</p>}
    </>;
  }
  return (
    <section aria-labelledby="ct-h" className="space-y-2 rounded-md border-l-4 border-accent bg-secondary p-3 text-sm text-primary">
      <h3 id="ct-h" className="font-semibold">Content team <span className="font-normal text-muted-foreground">(only First Line's content team sees this)</span></h3>
      {body}
      {progress ? <p role="status">{progress}…</p> : null}
      {act.isError ? <ErrorState error={act.error} /> : null}
    </section>
  );
}

function Section({ title, items, children }: { title: string; items?: string[] | undefined; children?: ReactNode }) {
  const body = items?.length ? <ul className="list-disc space-y-0.5 pl-5">{items.map((i) => <li key={i}>{i}</li>)}</ul> : children;
  if (!body || (Array.isArray(body) && !body.length)) return null;
  return (
    <section className="space-y-1 text-sm text-primary">
      <h3 className="text-xs font-semibold uppercase tracking-wide text-accent">{title}</h3>
      {body}
    </section>
  );
}

function CouncilNote({ ws, kind, subject, note, canRecord }: { ws: string; kind: "species" | "trap"; subject: string; note?: import("@/modules/vectovia/library").LibNote | undefined; canRecord: boolean }) {
  const qc = useQueryClient();
  const id = useRef(note?.id ?? newId());
  const [editing, setEditing] = useState(false);
  const [text, setText] = useState(note?.note ?? "");
  const save = useMutation({
    mutationFn: () => run(saveLibraryNote(id.current, ws, kind, subject, text)),
    onSuccess: () => { qc.invalidateQueries({ queryKey: wsKey(ws, "vv", "library-notes") }); setEditing(false); },
  });
  return (
    <section aria-labelledby="cn-h" className="rounded-md border border-border p-3 text-sm">
      <h3 id="cn-h" className="font-semibold text-primary">Your council's notes</h3>
      <p className="text-xs text-muted-foreground">Private to your council, for example where you keep these traps or local breeding spots. Never shared.</p>
      {editing ? (
        <form className="mt-2 space-y-2" onSubmit={(e) => { e.preventDefault(); save.mutate(); }}>
          <Textarea aria-label="Council notes" maxLength={4000} value={text} onChange={(e) => setText(e.target.value)} />
          {save.isError ? <ErrorState error={save.error} /> : null}
          <div className="flex gap-2">
            <button type="submit" disabled={save.isPending || text.trim().length < 2} className="rounded-md bg-signal-teal px-3 py-1.5 font-semibold text-deep-navy disabled:opacity-60">Save</button>
            <button type="button" onClick={() => setEditing(false)} className="rounded-md border border-primary px-3 py-1.5 text-primary">Cancel</button>
          </div>
        </form>
      ) : (
        <>
          {note ? <p className="mt-2 whitespace-pre-wrap text-primary">{note.note}</p> : <p className="mt-2 text-muted-foreground">No notes yet.</p>}
          {canRecord ? <button type="button" className="mt-2 text-primary underline" onClick={() => setEditing(true)}>{note ? "Edit notes" : "Add notes"}</button> : null}
        </>
      )}
    </section>
  );
}
