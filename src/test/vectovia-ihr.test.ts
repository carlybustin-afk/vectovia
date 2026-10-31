import { describe, expect, it } from "vitest";
import { expiry } from "@/modules/vectovia/ihr";

describe("register expiry", () => {
  const today = "2026-11-01";
  it("flags expired, due within 30 days, in date and no expiry", () => {
    expect(expiry("2026-10-31", today)).toBe("expired");
    expect(expiry("2026-11-01", today)).toBe("soon");
    expect(expiry("2026-12-01", today)).toBe("soon");
    expect(expiry("2026-12-02", today)).toBe("ok");
    expect(expiry(null, today)).toBe("none");
  });
});
