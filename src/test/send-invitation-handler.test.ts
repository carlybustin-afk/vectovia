// Unit tests for the send-invitation edge function logic (supabase/functions/send-invitation/handler.ts),
// with Supabase and Resend replaced by in-memory fakes.
import { handle, invitationEmail, type Deps, type Invitation } from "../../supabase/functions/send-invitation/handler";

const USER = "00000000-0000-0000-0000-0000000028a2";
const TOKEN = "a".repeat(64);
const INV: Invitation = { invitation_id: "inv-1", workspace_name: "SYNTHETIC <Council> & Co", email: "new.member@test.invalid", role: "member",
  expires_at: "2026-10-25T09:00:00Z", inviter_email: "admin@test.invalid" };

function fakes(over: Partial<Deps> = {}) {
  const calls: string[] = [];
  const sent: { to: string; subject: string; html: string; text: string }[] = [];
  const deps: Deps = {
    config: { apiKey: "re_test", from: "First Line <no-reply@firstlineeph.com>", appUrl: "https://app.example.test" },
    userId: async (h) => (h === "Bearer good" ? USER : null),
    invitation: async (_h, t) => { calls.push(`check ${t.slice(0, 4)}`); return INV; },
    send: async (m) => { sent.push(m); calls.push(`send ${m.to}`); return "re_msg_1"; },
    record: async (id, u, status, mid) => { calls.push(`record ${id} ${u} ${status} ${mid}`); },
    ...over,
  };
  return { deps, calls, sent };
}
const post = (body: unknown, auth = "Bearer good") =>
  new Request("https://fn.test/send-invitation", { method: "POST", headers: { Authorization: auth, "Content-Type": "application/json" }, body: JSON.stringify(body) });

describe("send-invitation", () => {
  it("checks the link as the inviter, sends, then records", async () => {
    const f = fakes();
    const res = await handle(post({ token: TOKEN }), f.deps);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ status: "sent", to: "new.member@test.invalid" });
    expect(f.calls).toEqual(["check aaaa", "send new.member@test.invalid", `record inv-1 ${USER} sent re_msg_1`]);
    expect(f.sent[0]!.text).toContain(`https://app.example.test/app?invite=${TOKEN}`);
  });
  it("needs a signed-in user and a well-formed link", async () => {
    expect((await handle(post({ token: TOKEN }, "Bearer bad"), fakes().deps)).status).toBe(401);
    expect((await handle(post({ token: "nope" }), fakes().deps)).status).toBe(400);
    expect((await handle(post({}), fakes().deps)).status).toBe(400);
  });
  it("sends nothing when the database refuses", async () => {
    const f = fakes({ invitation: async () => { throw { code: "42501" }; } });
    expect((await handle(post({ token: TOKEN }), f.deps)).status).toBe(403);
    expect(f.sent).toHaveLength(0);
    const g = fakes({ invitation: async () => { throw { code: "54000" }; } });
    expect((await handle(post({ token: TOKEN }), g.deps)).status).toBe(429);
    expect(g.sent).toHaveLength(0);
  });
  it("says email isn't set up until the owner adds the settings, and never checks or sends", async () => {
    for (const config of [{ apiKey: undefined, from: "x", appUrl: "https://a.test" }, { apiKey: "k", from: "x", appUrl: undefined },
      { apiKey: "k", from: "x", appUrl: "http://insecure.test" }]) {
      const f = fakes({ config });
      expect((await handle(post({ token: TOKEN }), f.deps)).status).toBe(503);
      expect(f.calls).toEqual([]);
    }
  });
  it("records a failed send and says so", async () => {
    const f = fakes({ send: async () => { throw new Error("Resend 422: domain not verified"); } });
    const res = await handle(post({ token: TOKEN }), f.deps);
    expect(res.status).toBe(502);
    expect(f.calls.at(-1)).toBe(`record inv-1 ${USER} failed null`);
  });
  it("escapes the council name in the email", () => {
    const m = invitationEmail(INV, `https://app.example.test/app?invite=${TOKEN}`);
    expect(m.html).toContain("SYNTHETIC &lt;Council&gt; &amp; Co");
    expect(m.html).not.toContain("<Council>");
    expect(m.subject).toBe("You're invited to join SYNTHETIC <Council> & Co on First Line");
    expect(m.text).toContain("expires on 25 October 2026");
  });
});
