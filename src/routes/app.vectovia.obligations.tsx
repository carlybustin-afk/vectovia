import { createFileRoute } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { AppShell, EmptyState, ErrorState, Loading, appHead } from "@/components/app-shell";
import { Textarea } from "@/components/ui/textarea";
import { useSession } from "@/lib/session";
import { run, when } from "@/modules/vectovia/api";
import { loadContentRoles } from "@/modules/vectovia/library";
import { checkKindLabels, obligationRpc, siteTypeLabels, type ObligationSet, type ObligationVersion, type Obligations } from "@/modules/vectovia/obligations";
import { useObligations } from "@/modules/vectovia/site-panels";
import { Field, StatusTag } from "@/modules/vectovia/ui";

export const Route = createFileRoute("/app/vectovia/obligations")({
  head: () => appHead("Obligation sets · Vectovia", "National obligation sets: what each type of site must do, and how Vectovia shows it."),
  component: ObligationsPage,
});

function ObligationsPage() {
  return (
    <AppShell product="vectovia" section="vectovia" title="Obligation sets"
      intro="What each type of site must do, published nationally and reviewed before use. Sites adopt a set on their site page.">
      <ObligationSets />
    </AppShell>
  );
}

const statusText: Record<ObligationVersion["status"], string> = {
  draft: "Draft", in_review: "Waiting for review", reviewed: "Reviewed, waiting to publish", published: "Published",
  superseded: "Replaced by a newer version", rejected: "Sent back", withdrawn: "Withdrawn",
};

function ObligationSets() {
  const { session } = useSession();
  const uid = session?.user.id;
  const ob = useObligations();
  const roles = useQuery({ queryKey: ["content-roles", "vv", uid], enabled: !!uid, staleTime: 5 * 60_000, queryFn: loadContentRoles });
  if (ob.isPending) return <Loading what="Loading obligation sets" />;
  if (ob.isError) return <ErrorState error={ob.error} />;
  const visible = ob.data.sets.filter((s) => ob.data.versions.some((v) => v.set_id === s.id));
  if (!visible.length) return <EmptyState title="No obligation sets published yet">Sets appear here once the content team has reviewed and published them.</EmptyState>;
  return (
    <div className="space-y-6">
      {roles.data && (roles.data.reviewer || roles.data.admin)
        ? <p className="rounded-md border border-accent bg-secondary p-3 text-sm text-primary">You're on the content team, so you also see drafts. A reviewer checks a draft against its sources; a different content admin publishes it. Only published versions can be adopted by sites.</p>
        : null}
      {visible.map((s) => <SetCard key={s.id} set={s} data={ob.data} uid={uid} reviewer={!!roles.data?.reviewer} admin={!!roles.data?.admin} />)}
    </div>
  );
}

function SetCard({ set, data, uid, reviewer, admin }: { set: ObligationSet; data: Obligations; uid: string | undefined; reviewer: boolean; admin: boolean }) {
  const versions = data.versions.filter((v) => v.set_id === set.id);
  const [shown, setShown] = useState(versions[0]!.id);
  const v = versions.find((x) => x.id === shown) ?? versions[0]!;
  const reqs = data.requirements.filter((r) => r.version_id === v.id);
  return (
    <section aria-labelledby={`set-${set.id}`} className="rounded-md border border-border">
      <div className="space-y-1 border-b border-border bg-secondary/60 p-3">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h2 id={`set-${set.id}`} className="text-lg font-semibold text-primary">{set.name}</h2>
          <div className="flex flex-wrap gap-2">
            <StatusTag>{set.jurisdiction}</StatusTag>
            <StatusTag strong={v.status === "published"}>Version {v.version}: {statusText[v.status]}</StatusTag>
          </div>
        </div>
        <p className="text-sm text-primary">{v.summary}</p>
        <p className="text-xs text-muted-foreground">Suggested for: {set.applies_to.map((t) => siteTypeLabels[t]).join(", ") || "any site"}</p>
        {versions.length > 1 ? (
          <div className="flex flex-wrap gap-2 pt-1 text-xs">
            {versions.map((x) => <button key={x.id} type="button" aria-pressed={x.id === v.id} onClick={() => setShown(x.id)}
              className={`rounded border px-2 py-0.5 ${x.id === v.id ? "border-primary text-primary" : "border-border text-muted-foreground"}`}>Version {x.version} · {statusText[x.status]}</button>)}
          </div>
        ) : null}
      </div>
      <ol className="divide-y divide-border">
        {reqs.map((r) => (
          <li key={r.id} className="grid gap-1 p-3 text-sm sm:grid-cols-[2rem_1fr]">
            <span className="font-semibold text-accent">{r.sort_order}</span>
            <div className="space-y-0.5">
              <p className="font-medium text-primary">{r.title}{r.mandatory ? "" : <span className="font-normal text-muted-foreground"> (where it applies)</span>}</p>
              <p className="text-primary">{r.what}</p>
              <p className="text-xs text-muted-foreground">
                {r.frequency ? `How often: ${r.frequency}. ` : ""}{r.evidence ? `Evidence: ${r.evidence}. ` : ""}{checkKindLabels[r.check_kind]}.{r.source_ref ? ` Source: ${r.source_ref}.` : ""}
              </p>
            </div>
          </li>
        ))}
      </ol>
      <div className="space-y-2 border-t border-border p-3 text-xs text-muted-foreground">
        {v.sources.length ? <p>Sources: {v.sources.map((s, i) => <span key={s.url}>{i ? "; " : ""}<a className="text-primary underline" href={s.url} target="_blank" rel="noreferrer">{s.title}</a></span>)}</p> : null}
        {v.reviewed_at ? <p>Reviewed {when(v.reviewed_at)}{v.review_note ? `: “${v.review_note}”` : ""}</p> : null}
        {v.published_at ? <p>Published {when(v.published_at)}</p> : null}
        <ReviewActions version={v} uid={uid} reviewer={reviewer} admin={admin} />
      </div>
    </section>
  );
}

function ReviewActions({ version, uid, reviewer, admin }: { version: ObligationVersion; uid: string | undefined; reviewer: boolean; admin: boolean }) {
  const qc = useQueryClient();
  const [note, setNote] = useState("");
  const done = () => { setNote(""); void qc.invalidateQueries({ queryKey: ["vv-obligations"] }); };
  const review = useMutation({ mutationFn: (approve: boolean) => run(obligationRpc.review(version.id, approve, note)), onSuccess: done });
  const publish = useMutation({ mutationFn: () => run(obligationRpc.publish(version.id)), onSuccess: done });
  if (version.status === "in_review" && reviewer) {
    if (version.loaded_by === uid) return <p className="text-primary">You loaded this version, so someone else must review it.</p>;
    return (
      <div className="space-y-2 rounded-md border border-accent bg-secondary p-2 text-sm">
        <Field id={`rn-${version.id}`} label="Review note (required)" hint="Say what you checked it against, and anything that must change if you send it back.">
          <Textarea id={`rn-${version.id}`} className="bg-background" maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} />
        </Field>
        {review.isError ? <ErrorState error={review.error} /> : null}
        <div className="flex flex-wrap gap-2">
          <button type="button" disabled={review.isPending || note.trim().length < 10} onClick={() => review.mutate(true)} className="rounded-md bg-signal-teal px-4 py-2 font-semibold text-deep-navy disabled:opacity-60">Approve for publishing</button>
          <button type="button" disabled={review.isPending || note.trim().length < 10} onClick={() => review.mutate(false)} className="rounded-md border border-primary px-4 py-2 text-primary disabled:opacity-60">Send back</button>
        </div>
      </div>
    );
  }
  if (version.status === "reviewed" && admin) {
    if (version.reviewer_id === uid || version.loaded_by === uid) return <p className="text-primary">You reviewed or loaded this version, so a different content admin must publish it.</p>;
    return (
      <div className="space-y-2 text-sm">
        {publish.isError ? <ErrorState error={publish.error} /> : null}
        <button type="button" disabled={publish.isPending} onClick={() => publish.mutate()} className="rounded-md bg-signal-teal px-4 py-2 font-semibold text-deep-navy disabled:opacity-60">{publish.isPending ? "Publishing…" : "Publish this version"}</button>
        <p>Publishing replaces any earlier published version. Sites stay on the version they adopted until a manager moves them.</p>
      </div>
    );
  }
  return null;
}
