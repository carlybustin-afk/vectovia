import { createFileRoute, Link } from "@tanstack/react-router";
import { NodeLine } from "../components/node-line";
import { VectoviaMark } from "@/modules/vectovia/brand";

// Vectovia public front page. Wording follows the brand guidelines: plain, professional, and honest
// about feature status ("being built" until something is available).
export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Vectovia — vector surveillance, by First Line" },
      { name: "description", content: "One consistent way to plan, run and evidence mosquito surveillance at ports, airports and council sites, in line with the International Health Regulations and UK guidance." },
      { property: "og:title", content: "Vectovia — vector surveillance, by First Line" },
      { property: "og:type", content: "website" },
    ],
  }),
  component: HomePage,
});

const workflow = [
  { step: "Assess", text: "Site risk assessments, surveillance plans and the obligations that apply to each site." },
  { step: "Decide", text: "Findings, identification and official results brought together, with clear next steps." },
  { step: "Act", text: "Scheduled trap checks, delimiting surveys, control actions and evidence that stands up." },
] as const;

const levels = [
  { title: "Sites", text: "Points of entry and council sites, each with its boundary, 400 m zone, programmes and traps." },
  { title: "Organisations", text: "Councils, port health and port or airport operators see which of their sites need attention." },
  { title: "National", text: "A single view of surveillance across the country: traps, checks, positives and compliance." },
] as const;

function HomePage() {
  return (
    <>
      <section className="border-b border-border bg-background">
        <div className="mx-auto max-w-6xl px-4 py-16 sm:px-6 sm:py-24">
          <VectoviaMark />
          <h1 className="mt-8 max-w-3xl text-4xl font-bold tracking-tight text-primary sm:text-5xl">
            Nationally consistent vector surveillance.
          </h1>
          <p className="mt-6 max-w-2xl text-lg text-muted-foreground">
            One way to plan, run and evidence mosquito surveillance at ports, airports and council sites, in line with
            the International Health Regulations and UK guidance.
          </p>
          <div className="mt-8 flex flex-wrap gap-3">
            <Link to="/sign-in" className="rounded-md bg-primary px-5 py-3 text-sm font-medium text-primary-foreground hover:bg-primary/90">
              Sign in
            </Link>
            <Link to="/contact" className="rounded-md border border-accent bg-background px-5 py-3 text-sm font-medium text-primary hover:bg-secondary">
              Talk to us
            </Link>
          </div>
          <p className="mt-6 text-sm text-muted-foreground">Vectovia is being built. Access is by invitation.</p>
        </div>
      </section>

      <section className="border-b border-border bg-secondary">
        <div className="mx-auto max-w-6xl px-4 py-16 sm:px-6">
          <h2 className="text-2xl font-semibold tracking-tight text-primary">Assess → Decide → Act</h2>
          <p className="mt-3 max-w-2xl text-muted-foreground">Built to support professional judgement — not replace it.</p>
          <NodeLine className="mt-8 h-6 w-full max-w-md" />
          <div className="mt-8 grid gap-8 md:grid-cols-3">
            {workflow.map((item) => (
              <div key={item.step}>
                <h3 className="text-lg font-semibold text-primary">{item.step}</h3>
                <p className="mt-2 text-sm text-muted-foreground">{item.text}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="bg-background">
        <div className="mx-auto max-w-6xl px-4 py-16 sm:px-6">
          <h2 className="text-2xl font-semibold tracking-tight text-primary">From one trap to the national picture</h2>
          <div className="mt-10 grid gap-6 md:grid-cols-3">
            {levels.map((l) => (
              <div key={l.title} className="border-l-4 border-accent bg-secondary p-6">
                <h3 className="text-lg font-semibold text-primary">{l.title}</h3>
                <p className="mt-2 text-sm text-muted-foreground">{l.text}</p>
              </div>
            ))}
          </div>
        </div>
      </section>
    </>
  );
}
