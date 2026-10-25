// Unit tests for the Vectovia files edge function logic (supabase/functions/vectovia-files/handler.ts),
// with Supabase replaced by in-memory fakes.
import { handle, sha256Hex, LINK_SECONDS, type Deps } from "../../supabase/functions/vectovia-files/handler";

const ID = "54000000-0000-0000-0000-000000000001";
const USER = "00000000-0000-0000-0000-0000000004a3";
const bytes = new TextEncoder().encode("SYNTHETIC evidence file");

function fakes(over: Partial<Deps> & { status?: string; allowed?: boolean; stored?: Uint8Array | null } = {}) {
  const calls: string[] = [];
  const deps: Deps = {
    userId: async (h) => (h === "Bearer good" ? USER : null),
    canRead: async () => over.allowed ?? true,
    getItem: async () => ({ storage_path: `ws/case/${ID}/photo.jpg`, file_name: "photo.jpg", status: over.status ?? "pending" }),
    download: async () => (over.stored === undefined ? bytes : over.stored),
    confirm: async (_id, sha, size) => { calls.push(`confirm:${sha}:${size}`); return "verified"; },
    logAccess: async (_id, action, user) => { calls.push(`log:${action}:${user}`); },
    signedUrl: async (_p, seconds, name) => { calls.push(`sign:${seconds}:${name}`); return "https://signed.example/x"; },
    ...over,
  };
  return { deps, calls };
}
const post = (body: unknown, auth = "Bearer good") =>
  new Request("https://fn.example/evidence", { method: "POST", headers: { Authorization: auth, "Content-Type": "application/json" }, body: JSON.stringify(body) });

describe("vectovia-files edge function", () => {
  it("computes a standard SHA-256 fingerprint", async () => {
    expect(await sha256Hex(new TextEncoder().encode("abc"))).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  });

  it("refuses requests without a valid sign-in", async () => {
    const { deps, calls } = fakes();
    expect((await handle(post({ action: "verify", id: ID }, ""), deps)).status).toBe(401);
    expect((await handle(post({ action: "verify", id: ID }, "Bearer forged"), deps)).status).toBe(401);
    expect(calls).toEqual([]);
  });

  it("refuses users who cannot see the evidence, before touching the file", async () => {
    const { deps, calls } = fakes({ allowed: false });
    expect((await handle(post({ action: "link", id: ID, mode: "download" }), deps)).status).toBe(403);
    expect(calls).toEqual([]);
  });

  it("rejects malformed requests", async () => {
    const { deps } = fakes();
    expect((await handle(post({ action: "delete", id: ID }), deps)).status).toBe(400);
    expect((await handle(post({ action: "verify", id: "../../etc" }), deps)).status).toBe(400);
  });

  it("fingerprints the STORED file, not the browser's claim", async () => {
    const { deps, calls } = fakes();
    const res = await handle(post({ action: "verify", id: ID }), deps);
    expect(res.status).toBe(200);
    expect(calls).toEqual([`confirm:${await sha256Hex(bytes)}:${bytes.byteLength}`]);
  });

  it("does not re-check an item that has already been decided", async () => {
    const { deps, calls } = fakes({ status: "verified" });
    expect(await (await handle(post({ action: "verify", id: ID }), deps)).json()).toEqual({ status: "verified" });
    expect(calls).toEqual([]);
  });

  it("reports when the file has not been uploaded yet", async () => {
    const { deps } = fakes({ stored: null });
    expect((await handle(post({ action: "verify", id: ID }), deps)).status).toBe(409);
  });

  it("logs a download before issuing a short-lived link", async () => {
    const { deps, calls } = fakes();
    const res = await handle(post({ action: "link", id: ID, mode: "download" }), deps);
    expect(await res.json()).toEqual({ url: "https://signed.example/x", expiresIn: LINK_SECONDS });
    expect(calls).toEqual([`log:downloaded:${USER}`, `sign:${LINK_SECONDS}:photo.jpg`]);
    expect(LINK_SECONDS).toBeLessThanOrEqual(300);
  });

  it("logs views separately from downloads", async () => {
    const { deps, calls } = fakes();
    await handle(post({ action: "link", id: ID, mode: "view" }), deps);
    expect(calls).toEqual([`log:viewed:${USER}`, `sign:${LINK_SECONDS}:null`]);
  });

  it("issues no link if the access cannot be logged", async () => {
    const { deps, calls } = fakes({ logAccess: async () => { throw new Error("log failed"); } });
    await expect(handle(post({ action: "link", id: ID, mode: "view" }), deps)).rejects.toThrow("log failed");
    expect(calls).toEqual([]);
  });
});
