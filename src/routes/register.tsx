import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { AuthPage } from "@/components/auth-form";
import { appHead } from "@/components/app-shell";
import { z } from "zod";
import { supabase } from "@/integrations/supabase/client";
import { safeDest } from "@/lib/safe-dest";

const search = z.object({ redirect: z.string().optional() });

export const Route = createFileRoute("/register")({
  validateSearch: (s) => search.parse(s),
  head: () => appHead("Create an account", "Register for a First Line account."),
  component: Register,
});

function Register() {
  const navigate = useNavigate();
  const { redirect } = Route.useSearch();
  const dest = safeDest(redirect);
  const invited = dest.includes("invite=");
  return (
    <AuthPage
      eyebrow="Account access"
      title="Create an account"
      intro={<p>{invited ? "Create your account with the email address your invitation was sent to. You'll join the council once you've confirmed it." : "You get a personal workspace. Council workspaces are joined by invitation only."}</p>}
      action="Create account"
      fields={[
        { id: "email", label: "Email", type: "email", autoComplete: "email" },
        { id: "password", label: "Password (at least 8 characters)", type: "password", autoComplete: "new-password", minLength: 8 },
      ]}
      onSubmit={async ({ email, password }) => {
        if ((password ?? "").length < 8) return "Use at least 8 characters.";
        const { data, error } = await supabase.auth.signUp({
          email: email ?? "", password: password ?? "", options: { emailRedirectTo: `${window.location.origin}${dest}` },
        });
        if (error) return "We couldn't create that account. Check the details and try again.";
        // With email confirmation on, there is no session until the link is used.
        if (data.session) navigate({ href: dest, replace: true });
        else navigate({ to: "/verify-email", replace: true });
        return null;
      }}
      footer={<Link to="/sign-in" search={redirect ? { redirect } : {}} className="font-medium text-primary underline">Already registered? Sign in</Link>}
    />
  );
}
