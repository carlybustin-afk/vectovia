import { Link } from "@tanstack/react-router";
import { logo } from "@/lib/brand";

export function SiteFooter() {
  return (
    <footer className="border-t border-border bg-secondary">
      <div className="mx-auto grid max-w-6xl gap-8 px-4 py-10 sm:px-6 md:grid-cols-3">
        <div>
          <img src={logo.src} width={logo.width} height={logo.height} alt={logo.alt} className="h-10 w-auto" />
          <p className="mt-3 text-sm text-muted-foreground">
            Vectovia is part of First Line: digital tools for the first line of protection. Built to support
            professional judgement — not replace it.
          </p>
        </div>
        <nav aria-label="Footer" className="text-sm">
          <p className="font-semibold text-primary">Vectovia</p>
          <ul className="mt-2 space-y-1">
            <li><Link className="text-muted-foreground hover:text-primary" to="/">Overview</Link></li>
            <li><Link className="text-muted-foreground hover:text-primary" to="/sign-in">Sign in</Link></li>
          </ul>
        </nav>
        <div className="text-sm">
          <p className="font-semibold text-primary">Company</p>
          <ul className="mt-2 space-y-1">
            <li><Link className="text-muted-foreground hover:text-primary" to="/about">About</Link></li>
            <li><Link className="text-muted-foreground hover:text-primary" to="/contact">Contact</Link></li>
            <li><Link className="text-muted-foreground hover:text-primary" to="/privacy">Privacy</Link></li>
            <li><Link className="text-muted-foreground hover:text-primary" to="/cookies">Cookies</Link></li>
            <li><Link className="text-muted-foreground hover:text-primary" to="/terms">Terms</Link></li>
          </ul>
        </div>
      </div>
      <div className="border-t border-border">
        <p className="mx-auto max-w-6xl px-4 py-4 text-xs text-muted-foreground sm:px-6">
          Vectovia is in development. Features described as planned are not yet available.
        </p>
      </div>
    </footer>
  );
}
