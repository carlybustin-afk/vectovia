import { createFileRoute } from "@tanstack/react-router";
import { NodeLine } from "../components/node-line";

export const Route = createFileRoute("/contact")({
  head: () => ({
    meta: [
      { title: "Contact — First Line" },
      {
        name: "description",
        content: "Contact the First Line team at info@firstlineeph.com.",
      },
      { property: "og:title", content: "Contact — First Line" },
      {
        property: "og:description",
        content: "Contact the First Line team at info@firstlineeph.com.",
      },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: ContactPage,
});

function ContactPage() {
  return (
    <section className="bg-secondary">
      <div className="mx-auto max-w-6xl px-4 py-16 sm:px-6">
        <p className="text-sm font-medium uppercase tracking-wide text-accent">Contact</p>
        <h1 className="mt-3 max-w-3xl text-3xl font-bold tracking-tight text-primary sm:text-4xl">
          Talk to us
        </h1>
        <p className="mt-5 max-w-2xl text-lg text-muted-foreground">
          Whether you work in Environmental Health, Public Health, or lead a
          team that does, we'd like to hear from you.
        </p>
        <NodeLine className="mt-9 h-6 w-full max-w-sm" />
        <div className="mt-9 border-l-4 border-accent bg-background p-6">
          <h2 className="text-lg font-semibold text-primary">Email</h2>
          <p className="mt-2 text-sm text-muted-foreground">
            The quickest way to reach the team:
          </p>
          <a
            href="mailto:info@firstlineeph.com"
            className="mt-3 inline-block text-lg font-medium text-accent hover:underline"
          >
            info@firstlineeph.com
          </a>
        </div>
      </div>
    </section>
  );
}
