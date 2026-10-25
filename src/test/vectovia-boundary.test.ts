// Vectovia module boundary (docs/vectovia-plan.md §2). Vectovia must stay
// separable from the investigation tools so it can be sold, and later hosted,
// on its own: Vectovia code never imports case code or touches case tables,
// case code never imports Vectovia, and neither imports any AI module.
// The only connection allowed later is the audited "link to a case" function.
import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";

const SRC = path.resolve(__dirname, "..");
const rel = (f: string) => path.relative(SRC, f).split(path.sep).join("/");
function files(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const full = path.join(dir, name);
    if (statSync(full).isDirectory()) return name === "test" ? [] : files(full);
    return /\.(ts|tsx)$/.test(name) && !name.endsWith(".gen.ts") ? [full] : [];
  });
}
const all = files(SRC).map((f) => ({ path: rel(f), text: readFileSync(f, "utf8") }));

const isVectovia = (p: string) => p.startsWith("modules/vectovia/") || /^routes\/app\.vectovia[^/]*\.tsx$/.test(p);
const isCase = (p: string) => p.startsWith("modules/cases/") || /^routes\/app\.(cases[^/]*|teams|templates)\.tsx$/.test(p);

const CASE_TABLES = /["'`](cases|case_[a-z_]+|properties|property_addresses|letters|letter_[a-z_]+|evidence_[a-z_]+)["'`]/;
const AI = /from\s+["'`][^"'`]*(ai-provider|ai-pilot|answer-pilot|pilot-conversation)[^"'`]*["'`]|lovableProvider|ai\.gateway|LOVABLE_API_KEY/;

describe("Vectovia module boundary", () => {
  const vv = all.filter((f) => isVectovia(f.path));
  const cases = all.filter((f) => isCase(f.path));

  it("finds the Vectovia module", () => {
    expect(vv.map((f) => f.path)).toEqual(expect.arrayContaining(["modules/vectovia/brand.tsx", "routes/app.vectovia.index.tsx"]));
  });

  it("Vectovia never imports case code or reads case tables", () => {
    const offenders = vv.filter((f) => /modules\/cases|modules\/knowledge/.test(f.text) || CASE_TABLES.test(f.text));
    expect(offenders.map((f) => f.path)).toEqual([]);
  });

  it("case code never imports Vectovia", () => {
    expect(cases.filter((f) => /modules\/vectovia/.test(f.text)).map((f) => f.path)).toEqual([]);
  });

  it("Vectovia never imports or calls an AI module", () => {
    expect(vv.filter((f) => AI.test(f.text)).map((f) => f.path)).toEqual([]);
  });

  it("Vectovia database objects are prefixed vv_", () => {
    const tables = vv.flatMap((f) => [...f.text.matchAll(/\.from\(["'`]([a-z_]+)["'`]\)/g)].map((m) => m[1] ?? ""));
    const shared = new Set(["workspace_members", "workspace_products", "product_access", "teams", "team_members", "profiles"]);
    expect(tables.filter((t) => !t.startsWith("vv_") && !shared.has(t))).toEqual([]);
  });
});
