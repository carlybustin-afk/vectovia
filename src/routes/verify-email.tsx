import { createFileRoute, Link } from "@tanstack/react-router";
import { appHead } from "@/components/app-shell";

export const Route = createFileRoute("/verify-email")({
  head: () => appHead("Check your email", "Confirm your email address to finish creating your First Line account."),
  component: () => (
    <section className="bg-secondary">
      <div className="mx-auto max-w-md px-4 py-16 sm:px-6">
        <p className="text-sm font-medium uppercase tracking-wide text-accent">Account access</p>
        <h1 className="mt-2 text-3xl font-bold tracking-tight text-primary">Check your email</h1>
        <div className="mt-6 border-l-4 border-accent bg-background p-4 text-sm text-muted-foreground">
          <p>If the address can be registered, we've sent a confirmation link to it. Open the link to finish, then sign in.</p>
          <p className="mt-2">Nothing arrived after a few minutes? Check spam, or try registering again.</p>
        </div>
        <Link to="/sign-in" className="mt-6 inline-block text-sm font-medium text-primary underline">Back to sign in</Link>
      </div>
    </section>
  ),
});
