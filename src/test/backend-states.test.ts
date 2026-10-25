import { classify } from "@/lib/backend";

// Fail-closed mapping of backend errors to what the screens show.
describe("backend error classification", () => {
  it("treats missing tables/functions as setup pending, never as empty data", () => {
    expect(classify({ code: "PGRST205", message: "Could not find the table" })).toBe("setup-pending");
    expect(classify({ code: "PGRST202", message: "Could not find the function" })).toBe("setup-pending");
    expect(classify({ code: "42P01", message: "relation does not exist" })).toBe("setup-pending");
  });
  it("maps permission refusals to denied", () => {
    expect(classify({ code: "42501", message: "not allowed" })).toBe("denied");
  });
  it("maps expired tokens to signed-out", () => {
    expect(classify({ code: "PGRST303", message: "JWT expired" })).toBe("signed-out");
  });
  it("anything unknown is an error, not success", () => {
    expect(classify({ code: "XX000", message: "boom" })).toBe("error");
    expect(classify(null)).toBe("error");
  });
});
