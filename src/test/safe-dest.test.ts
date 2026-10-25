// Where sign-in and registration may send someone (src/lib/safe-dest.ts).
import { safeDest } from "@/lib/safe-dest";

describe("safeDest", () => {
  it("keeps invitation links and other signed-in pages, with their query", () => {
    expect(safeDest("/app?invite=" + "a".repeat(64))).toBe("/app?invite=" + "a".repeat(64));
    expect(safeDest("/app/vectovia/incursions?id=abc")).toBe("/app/vectovia/incursions?id=abc");
    expect(safeDest("/app")).toBe("/app");
  });
  it("never sends anyone off the site or outside the signed-in area", () => {
    for (const bad of ["https://evil.example/app", "//evil.example/app", "/apple", "/sign-in", "/app\\..\\x", "/app /x", "", undefined, null]) {
      expect(safeDest(bad)).toBe("/app");
    }
  });
});
