import { Link } from "@tanstack/react-router";

export function LegalPlaceholder({
  label,
  title,
  points,
}: {
  label: string;
  title: string;
  points: string[];
}) {
  return (
    <section className="bg-secondary">
      <div className="mx-auto max-w-3xl px-4 py-16 sm:px-6">
        <p className="text-sm font-medium uppercase tracking-wide text-accent">{label}</p>
        <h1 className="mt-3 text-3xl font-bold tracking-tight text-primary sm:text-4xl">{title}</h1>
        <div className="mt-6 border-l-4 border-accent bg-background p-5 text-sm text-foreground">
          <p className="font-semibold">Development preview placeholder</p>
          <p className="mt-1 text-muted-foreground">
            This is not a final notice. An accurate, reviewed notice will be completed before the
            website is publicly launched.
          </p>
        </div>
        <h2 className="mt-10 text-lg font-semibold text-primary">What is known at this stage</h2>
        <ul className="mt-3 list-disc space-y-2 pl-5 text-muted-foreground">
          {points.map((p) => (
            <li key={p}>{p}</li>
          ))}
        </ul>
        <p className="mt-10 text-sm text-muted-foreground">
          Questions can be sent to{" "}
          <a className="text-accent underline" href="mailto:info@firstlineeph.com">
            info@firstlineeph.com
          </a>
          . <Link to="/contact" className="text-accent underline">Contact page</Link>
        </p>
      </div>
    </section>
  );
}

export function legalHead(title: string, description: string) {
  return {
    meta: [
      { title },
      { name: "description", content: description },
      { name: "robots", content: "noindex" },
      { property: "og:title", content: title },
      { property: "og:description", content: description },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  };
}
