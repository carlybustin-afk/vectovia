import type { FormEvent, ReactNode } from "react";
import { useState } from "react";
import { Input } from "./ui/input";
import { Label } from "./ui/label";

export type Field = { id: string; label: string; type: string; autoComplete?: string; minLength?: number };

/** Real account form. Shows only outcomes the backend actually returned. */
export function AuthPage({ eyebrow, title, intro, fields, action, onSubmit, footer, done }: {
  eyebrow: string;
  title: string;
  intro?: ReactNode;
  fields: Field[];
  action: string;
  onSubmit: (values: Record<string, string>) => Promise<string | null>; // returns error message or null
  footer?: ReactNode;
  done?: ReactNode;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const values = Object.fromEntries(new FormData(e.currentTarget).entries()) as Record<string, string>;
    setBusy(true); setError(null);
    try { setError(await onSubmit(values)); }
    catch { setError("That didn't work. Please try again."); }
    finally { setBusy(false); }
  }

  return (
    <section className="bg-secondary">
      <div className="mx-auto max-w-md px-4 py-16 sm:px-6">
        <p className="text-sm font-medium uppercase tracking-wide text-accent">{eyebrow}</p>
        <h1 className="mt-2 text-3xl font-bold tracking-tight text-primary">{title}</h1>
        {intro ? <div className="mt-4 text-sm text-muted-foreground">{intro}</div> : null}
        {done ?? (
          <form className="mt-6 space-y-4 rounded-md bg-background p-6" onSubmit={submit} noValidate={false}>
            {fields.map((f) => (
              <div key={f.id} className="space-y-1.5">
                <Label htmlFor={f.id}>{f.label}</Label>
                <Input id={f.id} name={f.id} type={f.type} required autoComplete={f.autoComplete} minLength={f.minLength} />
              </div>
            ))}
            {error ? <p role="alert" className="text-sm text-destructive">{error}</p> : null}
            <button type="submit" disabled={busy} className="w-full rounded-md bg-signal-teal px-4 py-2.5 text-sm font-semibold text-deep-navy disabled:opacity-60">
              {busy ? "Please wait…" : action}
            </button>
          </form>
        )}
        <div className="mt-6 flex flex-wrap gap-4 text-sm">{footer}</div>
      </div>
    </section>
  );
}
