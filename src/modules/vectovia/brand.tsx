// Vectovia identity within the shared platform (plan V-D9): a wordmark in the
// existing typeface and palette until a logo is supplied. No new colours.
// Module boundary: Vectovia code never imports case code or any AI module
// (enforced by src/test/vectovia-boundary.test.ts).
export function VectoviaMark({ size = "lg" }: { size?: "sm" | "lg" }) {
  return (
    <p className={`flex items-baseline gap-2 ${size === "lg" ? "" : "text-sm"}`}>
      <span className={`font-bold tracking-tight text-primary ${size === "lg" ? "text-3xl" : "text-base"}`}>
        Vecto<span className="text-accent">via</span>
      </span>
      <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">by First Line</span>
    </p>
  );
}
