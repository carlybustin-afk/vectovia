import { Link, useNavigate, useRouterState } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Menu as MenuIcon, User, X } from "lucide-react";
import { useState, type ReactNode } from "react";
import { logo } from "@/lib/brand";
import { BackendError, db } from "@/lib/backend";
import { signOutAndClear, useSession } from "@/lib/session";
import { useWorkspace } from "@/lib/workspace";
import type { Workspace } from "@/lib/backend";
import { canUse, levelIn, productLabels, useIsPlatformAdmin, useMyProducts, type Product } from "@/lib/products";

// Side menu, grouped by product (owner decision 2026-10-17: one slim top bar
// and a side menu). A group shows only to people who can use it: products by
// access level (rev 20), content review to First Line's content team, Platform
// to platform admins. The menu only hides links; the database decides access.
type MenuLink = { to: string; label: string; exact?: boolean; also?: readonly string[] };
type MenuGroup = { key: string; label: string; product?: Product; who?: "reviewer" | "platform"; parts: readonly { heading?: string; links: readonly MenuLink[] }[] };
const menu: readonly MenuGroup[] = [
  { key: "vectovia", label: "Vectovia", product: "vectovia", parts: [
    { links: [{ to: "/app/vectovia", label: "Dashboard", exact: true }] },
    { heading: "Field", links: [{ to: "/app/vectovia/visits", label: "Field work" }, { to: "/app/vectovia/results", label: "Results" }] },
    { heading: "Response", links: [{ to: "/app/vectovia/risk", label: "Risk and actions" }, { to: "/app/vectovia/incursions", label: "Incursions" }] },
    { heading: "Insight", links: [{ to: "/app/vectovia/analytics", label: "Analytics" }, { to: "/app/vectovia/reports", label: "Reports and exports" }] },
    { heading: "Set-up", links: [{ to: "/app/vectovia/sites", label: "Sites" }, { to: "/app/vectovia/traps", label: "Traps" },
      { to: "/app/vectovia/library", label: "Species and trap library" }, { to: "/app/vectovia/setup", label: "Programmes and lists" }] },
  ] },
  { key: "settings", label: "Organisation settings", parts: [
    { links: [{ to: "/app/workspace", label: "Members" }, { to: "/app", label: "Your organisations", exact: true }] },
  ] },
  { key: "platform", label: "Platform", who: "platform", parts: [{ links: [{ to: "/app/platform", label: "Organisations" }] }] },
];
const isOn = (path: string, l: MenuLink) => (l.exact ? path === l.to : path === l.to || path.startsWith(`${l.to}/`)) || !!l.also?.some((a) => path.startsWith(a));
/** The most specific link matching the path (so "/app/vectovia" doesn't also light up on its sub-pages). */
function activeLink(path: string, groups: readonly MenuGroup[]) {
  let best: MenuLink | null = null;
  for (const g of groups) for (const p of g.parts) for (const l of p.links) if (isOn(path, l) && (!best || l.to.length > best.to.length)) best = l;
  return best;
}

function SideMenu({ groups, path, onNavigate }: { groups: readonly MenuGroup[]; path: string; onNavigate?: () => void }) {
  const active = activeLink(path, groups);
  const activeGroup = groups.find((g) => g.parts.some((p) => p.links.includes(active!)))?.key;
  const [open, setOpen] = useState<Record<string, boolean>>({});
  const isOpen = (k: string) => open[k] ?? (k === activeGroup || groups.length <= 2);
  return (
    <nav aria-label="Main menu" className="space-y-1 text-sm">
      {groups.map((g) => (
        <div key={g.key}>
          <button type="button" aria-expanded={isOpen(g.key)} onClick={() => setOpen((o) => ({ ...o, [g.key]: !isOpen(g.key) }))}
            className="flex w-full items-center justify-between rounded-md px-2 py-1.5 text-left font-semibold text-primary hover:bg-secondary">
            {g.label}<span aria-hidden="true" className="text-muted-foreground">{isOpen(g.key) ? "▾" : "▸"}</span>
          </button>
          {isOpen(g.key) ? (
            <div className="mb-2 ml-2 border-l border-border pl-2">
              {g.parts.map((p, i) => (
                <div key={i} className={p.heading ? "mt-2" : ""}>
                  {p.heading ? <p className="px-2 pb-0.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{p.heading}</p> : null}
                  <ul>
                    {p.links.map((l) => {
                      const on = l === active;
                      return (
                        <li key={l.to}>
                          <Link to={l.to} aria-current={on ? "page" : undefined} onClick={onNavigate}
                            className={`block px-2 py-1.5 text-primary hover:bg-secondary ${on ? "border-l-4 border-accent bg-secondary font-medium" : "rounded-md"}`}>
                            {l.label}
                          </Link>
                        </li>
                      );
                    })}
                  </ul>
                </div>
              ))}
            </div>
          ) : null}
        </div>
      ))}
    </nav>
  );
}

/** The account menu: who is signed in, a way back to the public site, and sign out. */
function AccountMenu({ email, onSignOut }: { email: string | undefined; onSignOut: () => void }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="relative">
      <button type="button" aria-expanded={open} aria-controls="account-menu" onClick={() => setOpen((o) => !o)}
        className="flex h-9 items-center gap-1 rounded-md border border-border px-2 text-sm text-primary hover:bg-secondary">
        <User aria-hidden="true" className="h-4 w-4" /><span className="sr-only">Your account</span><span aria-hidden="true" className="text-muted-foreground">▾</span>
      </button>
      {open ? (
        <div id="account-menu" className="absolute right-0 z-50 mt-1 w-64 rounded-md border border-border bg-background p-2 text-sm shadow-md">
          {email ? <p className="truncate px-2 py-1 text-xs text-muted-foreground" title={email}>Signed in as {email}</p> : null}
          <Link to="/" className="block rounded-md px-2 py-1.5 text-primary hover:bg-secondary">Public website</Link>
          <button type="button" onClick={onSignOut} className="block w-full rounded-md px-2 py-1.5 text-left text-primary hover:bg-secondary">Sign out</button>
        </div>
      ) : null}
    </div>
  );
}

/** One-line summary, with anything longer behind "About this page". */
function Intro({ text }: { text: string }) {
  const m = text.match(/^(.+?[.!?])\s+(.+)$/s);
  if (!m) return <p className="mt-1 max-w-3xl text-muted-foreground">{text}</p>;
  return (
    <div className="mt-1 max-w-3xl">
      <p className="text-muted-foreground">{m[1]}</p>
      <details className="mt-1 text-sm">
        <summary className="cursor-pointer text-primary underline">About this page</summary>
        <p className="mt-1 text-muted-foreground">{m[2]}</p>
      </details>
    </div>
  );
}

/** Source review is for First Line content reviewers only; councils never see it. */
function useIsContentReviewer(uid: string | undefined) {
  return useQuery({
    queryKey: ["content-roles", uid],
    enabled: !!uid,
    staleTime: 5 * 60_000,
    queryFn: async () => {
      const { data } = await db.from("content_roles").select("role").eq("user_id", uid!);
      return (data ?? []).length > 0;
    },
  }).data ?? false;
}

export function SetupPending() {
  return (
    <div role="status" className="border-l-4 border-accent bg-secondary p-5">
      <p className="font-semibold text-primary">Setup pending</p>
      <p className="mt-1 text-sm text-muted-foreground">
        You are signed in, but the secure workspace database has not been switched on yet. Nothing can be
        saved or shown until it is. No sample or made-up council data is displayed.
      </p>
    </div>
  );
}

export function StateMessage({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div role="status" className="border-l-4 border-accent bg-secondary p-5">
      <p className="font-semibold text-primary">{title}</p>
      <div className="mt-1 text-sm text-muted-foreground">{children}</div>
    </div>
  );
}

export function Loading({ what = "Loading" }: { what?: string }) {
  return <p role="status" aria-live="polite" className="text-sm text-muted-foreground">{what}…</p>;
}

/** Fail-closed rendering of a query error. */
export function ErrorState({ error }: { error: unknown }) {
  const kind = error instanceof BackendError ? error.kind : "error";
  if (kind === "setup-pending") return <SetupPending />;
  if (kind === "denied") return <StateMessage title="Access denied">You don't have access to this. If you were removed from the workspace, your access ended straight away.</StateMessage>;
  if (kind === "signed-out") return <StateMessage title="Your session has expired">Please <Link to="/sign-in" className="underline">sign in again</Link>.</StateMessage>;
  return <StateMessage title="Something went wrong">It didn't load and nothing was changed. Try again shortly.</StateMessage>;
}

function WorkspaceSwitcher({ list, current, onSelect }: { list: Workspace[]; current: Workspace | null; onSelect: (id: string) => void }) {
  if (!list.length) return null;
  return (
    <label className="flex items-center gap-2 text-sm">
      <span className="sr-only">Workspace</span>
      <select aria-label="Current workspace" className="h-9 max-w-[10rem] rounded-md border border-input bg-background px-2 text-sm sm:max-w-[16rem]"
        value={current?.id ?? ""} onChange={(e) => onSelect(e.target.value)}>
        {list.map((w) => <option key={w.id} value={w.id}>{w.kind === "personal" ? "Personal workspace" : w.name}</option>)}
      </select>
    </label>
  );
}

/**
 * Signed-in page frame. `children` renders only when the schema is ready and
 * a workspace is selected (unless `needsWorkspace` is false).
 */
export function AppShell({ title, intro, children, needsWorkspace = true, product }: {
  title: string; intro?: string; children: ReactNode; needsWorkspace?: boolean;
  /** Kept for existing pages; the side menu now works out where you are from the address. */
  section?: "knowledge" | "settings" | "review" | "vectovia";
  /** The page belongs to this product: people without access see a plain message instead. */
  product?: Product;
}) {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const { session, expired } = useSession();
  const path = useRouterState({ select: (s) => s.location.pathname });
  const isReviewer = useIsContentReviewer(session?.user.id);
  const { schema, workspaces, current, select } = useWorkspace();
  const products = useMyProducts();
  const isPlatformAdmin = useIsPlatformAdmin();
  const [menuOpen, setMenuOpen] = useState(false);
  const has = (p: Product) => canUse(levelIn(products.data, current?.id, p));
  const groups = menu.filter((g) => (g.product ? has(g.product) : g.who === "reviewer" ? isReviewer : g.who === "platform" ? isPlatformAdmin : true));
  const signOut = async () => { await signOutAndClear(qc); navigate({ to: "/sign-in", replace: true }); };

  let body: ReactNode;
  if (expired || (!session && schema.isFetched)) body = <StateMessage title="Your session has expired">Please <Link to="/sign-in" className="underline">sign in again</Link>. Workspace data has been cleared from this page.</StateMessage>;
  else if (schema.isPending) body = <Loading what="Checking secure workspace" />;
  else if (schema.data && schema.data !== "ready") body = schema.data === "setup-pending" ? <SetupPending /> : <ErrorState error={new BackendError(schema.data, "")} />;
  else if (schema.isError) body = <ErrorState error={schema.error} />;
  else if (workspaces.isError) body = <ErrorState error={workspaces.error} />;
  else if (workspaces.isPending) body = <Loading what="Loading workspaces" />;
  else if (needsWorkspace && !current) body = <Loading what="Opening workspace" />;
  else if (product && products.isPending) body = <Loading />;
  else if (product && !has(product)) body = <StateMessage title={`${productLabels[product]} isn't available here`}>Your council doesn't have {productLabels[product]} in this workspace, or you haven't been given access. Ask your council's owner or admin.</StateMessage>;
  else body = children;

  return (
    <div>
      <header className="border-b border-border bg-background">
        <div className="mx-auto flex max-w-7xl items-center gap-2 px-4 py-2 sm:px-6">
          <button type="button" aria-expanded={menuOpen} aria-controls="main-menu-mobile" onClick={() => setMenuOpen((o) => !o)}
            className="flex h-9 items-center gap-1 rounded-md border border-border px-2 text-sm text-primary md:hidden">
            {menuOpen ? <X aria-hidden="true" className="h-4 w-4" /> : <MenuIcon aria-hidden="true" className="h-4 w-4" />}Menu
          </button>
          <Link to="/app" className="flex shrink-0 items-center" aria-label="First Line workspace home">
            <img src={logo.src} width={logo.width} height={logo.height} alt="First Line — Environmental + Public Health" className="hidden h-8 w-auto sm:block" />
            <span className="text-sm font-semibold text-primary sm:hidden">First Line</span>
          </Link>
          <div className="min-w-0 flex-1" />
          <WorkspaceSwitcher list={workspaces.data ?? []} current={current} onSelect={select} />
          <AccountMenu email={session?.user.email} onSignOut={signOut} />
        </div>
        {menuOpen ? (
          <div id="main-menu-mobile" className="border-t border-border px-4 py-3 md:hidden">
            <SideMenu groups={groups} path={path} onNavigate={() => setMenuOpen(false)} />
          </div>
        ) : null}
      </header>
      <div className="mx-auto flex max-w-7xl gap-8 px-4 py-6 sm:px-6">
        <aside className="hidden w-56 shrink-0 md:block">
          <div className="sticky top-4"><SideMenu groups={groups} path={path} /></div>
        </aside>
        <div className="min-w-0 flex-1">
          <h1 className="text-2xl font-bold tracking-tight text-primary sm:text-3xl">{title}</h1>
          {intro ? <Intro text={intro} /> : null}
          <div className="mt-6">{body}</div>
        </div>
      </div>
    </div>
  );
}

export function Unavailable({ children }: { children: ReactNode }) {
  return <p className="mt-2 text-sm text-muted-foreground">Unavailable: {children}</p>;
}

export function EmptyState({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="rounded-md border border-dashed border-border bg-background p-6">
      <p className="font-semibold text-primary">{title}</p>
      <div className="mt-1 text-sm text-muted-foreground">{children}</div>
    </div>
  );
}

export function appHead(title: string, description: string) {
  return {
    meta: [
      { title: `${title} — First Line` },
      { name: "description", content: description },
      { name: "robots", content: "noindex" },
      { property: "og:title", content: `${title} — First Line` },
      { property: "og:description", content: description },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  };
}
