// Vectovia analytics (src/modules/vectovia/analytics.ts): figures worked out from records.
import { effort, findings, currentFindings, monthKey, monthsIn, performance, spread, ukDayStart, ukDate, type AnalyticsData, type Filter } from "@/modules/vectovia/analytics";
import type { Action, Deployment, Result, ResultVersion, Sample, Visit } from "@/modules/vectovia/api";

const dep = (id: string, site: string, start: string, end: string | null, interval = 7) =>
  ({ id, trap_id: `t-${id}`, site_id: site, started_at: start, ended_at: end, visit_interval_days: interval }) as Deployment;
const visit = (id: string, d: string, site: string, at: string, outcome: Visit["outcome"] = "collected") =>
  ({ id, deployment_id: d, site_id: site, occurred_at: at, outcome }) as Visit;
const sample = (id: string, v: string, site: string) => ({ id, visit_id: v, site_id: site }) as Sample;
const result = (id: string, s: string, site: string, current = 1) => ({ id, sample_id: s, site_id: site, current_version: current }) as Result;
const ver = (r: string, version: number, status: ResultVersion["status"], at: string, taxon: string | null = null) =>
  ({ result_id: r, version, status, taxon_id: taxon, council_taxon_id: null, quantity: 1, recorded_at: at }) as ResultVersion;

const data: AnalyticsData = {
  deployments: [dep("d1", "s1", "2026-06-01T09:00:00Z", "2026-06-29T09:00:00Z"), dep("d2", "s2", "2026-06-15T09:00:00Z", null, 14)],
  visits: [
    visit("v1", "d1", "s1", "2026-06-08T09:00:00Z"), visit("v2", "d1", "s1", "2026-06-15T09:00:00Z"),
    visit("v3", "d1", "s1", "2026-06-22T09:00:00Z", "not_completed"), visit("v4", "d2", "s2", "2026-07-01T09:00:00Z"),
  ],
  samples: [sample("x1", "v1", "s1"), sample("x2", "v2", "s1"), sample("x3", "v4", "s2")],
  results: [result("r1", "x1", "s1", 2), result("r2", "x2", "s1"), result("r3", "x3", "s2")],
  versions: [
    ver("r1", 1, "pending", "2026-06-09T09:00:00Z"), ver("r1", 2, "confirmed", "2026-06-11T09:00:00Z", "albo"),
    ver("r2", 1, "inconclusive", "2026-06-16T09:00:00Z"), ver("r3", 1, "pending", "2026-07-02T09:00:00Z"),
  ],
  assessmentLinks: [{ assessment_id: "a1", result_id: "r1", created_at: "2026-06-12T09:00:00Z" }],
  actions: [
    { id: "ac1", site_id: "s1", due_on: "2026-06-20", status: "done", completed_at: "2026-06-19T10:00:00Z", created_at: "2026-06-12T09:00:00Z" },
    { id: "ac2", site_id: "s1", due_on: "2026-06-20", status: "done", completed_at: "2026-06-25T10:00:00Z", created_at: "2026-06-12T09:00:00Z" },
    { id: "ac3", site_id: "s1", due_on: "2026-06-25", status: "open", completed_at: null, created_at: "2026-06-12T09:00:00Z" },
  ] as Action[],
  capped: false,
};
const f: Filter = { from: "2026-06-01", to: "2026-07-31", sites: null };
const now = Date.parse("2026-07-13T09:00:00Z");

describe("dates", () => {
  it("groups by UK month and day, including summer time", () => {
    expect(monthKey("2026-06-30T23:30:00Z")).toBe("2026-07"); // 00:30 on 1 July in London
    expect(ukDate("2026-03-31T23:30:00Z")).toBe("2026-04-01");
    expect(new Date(ukDayStart("2026-07-01")).toISOString()).toBe("2026-06-30T23:00:00.000Z");
    expect(new Date(ukDayStart("2026-01-01")).toISOString()).toBe("2026-01-01T00:00:00.000Z");
    expect(monthsIn({ from: "2025-11-10", to: "2026-02-01", sites: null })).toEqual(["2025-11", "2025-12", "2026-01", "2026-02"]);
  });
});

describe("effort and coverage", () => {
  it("counts trap-nights, planned, done and missed visits", () => {
    const e = effort(data, f, now);
    expect(e.trapNights).toBe(28 + 28); // d1: 1–29 June; d2: 15 June to 13 July (now)
    expect(e.visitsPlanned).toBe(4 + 2);
    expect(e.visitsDone).toBe(4);
    expect(e.completed).toBe(3);
    expect(e.notCompleted).toBe(1);
    expect(e.missed).toBe(1 + 1); // d1 planned 4, 3 recorded; d2 planned 2, 1 recorded
    expect(e.byMonth.find((m) => m.month === "2026-06")?.visits).toBe(3);
  });
  it("only counts the chosen sites and period", () => {
    expect(effort(data, { ...f, sites: new Set(["s2"]) }, now).visitsDone).toBe(1);
    expect(effort(data, { from: "2026-07-01", to: "2026-07-31", sites: null }, now).trapNights).toBe(12); // d2 only, 1–13 July
  });
});

describe("findings", () => {
  const rows = currentFindings(data, f, (v) => v.taxon_id ?? "unknown");
  it("uses the current version, dated by collection", () => {
    expect(rows.map((r) => [r.result_id, r.status])).toEqual([["r1", "confirmed"], ["r2", "inconclusive"], ["r3", "pending"]]);
  });
  it("works out positivity from samples with a final result", () => {
    const x = findings(data, f, rows);
    expect(x.samples).toBe(3);
    expect(x.samplesResulted).toBe(2); // x3 still pending
    expect(x.samplesPositive).toBe(1);
    expect(x.positivity).toBe(0.5);
    expect(x.bySpecies).toEqual([{ taxon: "albo", findings: 1, confirmed: 1, sites: 1 }]);
  });
});

describe("response performance", () => {
  it("measures collection to result and result to assessment", () => {
    const p = performance(data, f, "2026-07-13");
    expect(p.collectionToResult.n).toBe(2); // r1 (3 days, first non-pending) and r2 (1 day); r3 pending
    expect(p.collectionToResult.median).toBe(2);
    expect(p.resultToAssessment).toEqual({ n: 1, median: 1, min: 1, max: 1 });
    expect(p.actions).toEqual({ doneOnTime: 1, doneLate: 1, doneNoDue: 0, openOverdue: 1, openInTime: 0, cancelled: 0 });
  });
  it("summarises a spread", () => {
    expect(spread([])).toEqual({ n: 0, median: null, min: null, max: null });
    expect(spread([5, 1, 3, 9])).toEqual({ n: 4, median: 4, min: 1, max: 9 });
  });
});
