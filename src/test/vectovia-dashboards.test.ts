import { describe, expect, it } from "vitest";
import { attentionOf, nationalCsv, siteRag, type NationalSite } from "@/modules/vectovia/dashboards";

const ok = { requirements: 9, met: 9, partly: 0, not_met: 0, not_assessed: 0, active_traps: 3, overdue_checks: 0, due_checks: 0,
  plan_current: true, risk_current: true, invasive_awaiting: 0, open_incursions: 0 };

describe("site status", () => {
  it("is on track only when nothing needs attention", () => {
    expect(siteRag(ok)).toBe("green");
    expect(attentionOf(ok)).toEqual([]);
  });
  it("flags missing obligation sets and traps as gaps, not as met", () => {
    expect(siteRag({ ...ok, requirements: 0, active_traps: 0 })).toBe("amber");
    expect(attentionOf({ ...ok, requirements: 0, active_traps: 0 })).toEqual(["No obligation sets adopted", "No active traps"]);
  });
  it("needs action for overdue checks, unmet requirements, invasive finds or a lapsed plan", () => {
    for (const bad of [{ overdue_checks: 1 }, { not_met: 1 }, { invasive_awaiting: 1 }, { plan_current: false }, { risk_current: false }, { open_incursions: 1 }])
      expect(siteRag({ ...ok, ...bad })).toBe("red");
  });
});

describe("national return", () => {
  it("quotes text and neutralises formula-like cells", () => {
    const row = { ...ok, organisation: '=HYPERLINK("x")', site_reference: "VS-0001", site_name: 'Quay "East"', site_type: "port", latitude: 51.1, longitude: 1.3,
      zone_m: 400, obligation_sets: null, positives_12m: 0, invasive_12m: 0, open_surveys: 0 } as NationalSite;
    const [head = "", line = ""] = nationalCsv([row]).split("\r\n");
    expect(head.startsWith('"Organisation","Site reference"')).toBe(true);
    expect(line.startsWith(`"'=HYPERLINK(""x"")","VS-0001","Quay ""East""","port",51.1,1.3,400,,9,`)).toBe(true);
    expect(line).toContain(",Yes,Yes,");
  });
});
