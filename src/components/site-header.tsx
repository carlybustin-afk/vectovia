import { Link } from "@tanstack/react-router";
import { Menu, X } from "lucide-react";
import { useState } from "react";
import { VectoviaMark } from "@/modules/vectovia/brand";
import { Button } from "./ui/button";
import { useSession } from "../lib/session";

// Public header for Vectovia (by First Line). The Vectovia wordmark uses the agreed palette
// and typeface (brand guidelines; plan V-D9). The First Line logo appears in the footer.
export function SiteHeader() {
  const [open, setOpen] = useState(false);
  const { session } = useSession();

  return (
    <header className="relative z-40 border-b border-border bg-background">
      <div className="mx-auto flex max-w-6xl items-center gap-2 px-4 py-3 sm:px-6">
        <Link to="/" className="flex shrink-0 items-center" aria-label="Vectovia home">
          <VectoviaMark size="sm" />
        </Link>
        <div className="min-w-0 flex-1" aria-hidden="true" />
        <div className="flex shrink-0 items-center gap-2">
          <Button asChild className="h-10 bg-signal-teal px-4 text-sm text-deep-navy shadow-none hover:bg-signal-teal">
            {session ? <Link to="/app">Open Vectovia</Link> : <Link to="/sign-in">Sign in</Link>}
          </Button>
          <Button type="button" variant="ghost" size="icon" className="h-10 w-10 shrink-0 text-primary"
            aria-expanded={open} aria-controls="site-menu" onClick={() => setOpen((value) => !value)}>
            <span className="sr-only">{open ? "Close menu" : "Open menu"}</span>
            {open ? <X aria-hidden="true" /> : <Menu aria-hidden="true" />}
          </Button>
        </div>
      </div>
      {open ? (
        <nav id="site-menu" aria-label="Site" className="border-t border-border bg-background">
          <div className="mx-auto grid max-w-6xl grid-cols-3 gap-2 px-4 py-4 sm:px-6">
            <Link to="/" onClick={() => setOpen(false)} className="rounded-md px-3 py-2 text-center text-sm font-medium text-primary hover:bg-secondary">Home</Link>
            <Link to="/about" onClick={() => setOpen(false)} className="rounded-md px-3 py-2 text-center text-sm font-medium text-primary hover:bg-secondary">About</Link>
            <Link to="/contact" onClick={() => setOpen(false)} className="rounded-md px-3 py-2 text-center text-sm font-medium text-primary hover:bg-secondary">Contact</Link>
          </div>
        </nav>
      ) : null}
    </header>
  );
}
