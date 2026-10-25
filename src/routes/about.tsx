import { createFileRoute } from "@tanstack/react-router";
import { NodeLine } from "../components/node-line";

export const Route = createFileRoute("/about")({
  head: () => ({
    meta: [
      { title: "About — First Line" },
      {
        name: "description",
        content:
          "Why First Line exists: practical, intelligent software built to support the professional judgement of Environmental Health and Public Health professionals.",
      },
      { property: "og:title", content: "About — First Line" },
      {
        property: "og:description",
        content:
          "Why First Line exists: practical, intelligent software built to support the professional judgement of Environmental Health and Public Health professionals.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: AboutPage,
});

function AboutPage() {
  return (
    <section className="bg-secondary">
      <div className="mx-auto max-w-6xl px-4 py-16 sm:px-6">
        <p className="text-sm font-medium uppercase tracking-wide text-accent">About</p>
        <h1 className="mt-3 max-w-3xl text-3xl font-bold tracking-tight text-primary sm:text-4xl">
          Built to support professional judgement — not replace it
        </h1>
        <div className="mt-6 max-w-2xl space-y-4 border-l-4 border-accent bg-background p-6 text-muted-foreground">
          <p>
            Environmental Health and Public Health professionals are the first
            line of protection for communities. Their work depends on sound
            judgement, applied to evidence, legislation and guidance — often
            under time pressure and with records scattered across systems.
          </p>
          <p>
            First Line is being built to bring that work together in one
            connected platform: assess risk, decide with the relevant
            information at hand, and act through clear records, notices and
            reports.
          </p>
          <p>
            The principle behind every module is the same: the software
            organises, connects and supports. The professional decides.
          </p>
        </div>

        <NodeLine className="mt-10 h-6 w-full max-w-md" />

        <div className="mt-10 grid gap-8 md:grid-cols-3">
          <div className="border-t-2 border-accent pt-5">
            <h2 className="text-lg font-semibold text-primary">Assess</h2>
            <p className="mt-2 text-sm text-muted-foreground">
              Structured tools to help professionals identify and evaluate risk.
            </p>
          </div>
          <div className="border-t-2 border-ring pt-5">
            <h2 className="text-lg font-semibold text-primary">Decide</h2>
            <p className="mt-2 text-sm text-muted-foreground">
              Bring evidence, legislation, guidance and intelligent decision
              support together.
            </p>
          </div>
          <div className="border-t-2 border-primary pt-5">
            <h2 className="text-lg font-semibold text-primary">Act</h2>
            <p className="mt-2 text-sm text-muted-foreground">
              Turn professional judgement into clear actions, records and reports.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
