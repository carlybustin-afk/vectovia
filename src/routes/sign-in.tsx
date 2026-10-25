import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { z } from "zod";
import { AuthPage } from "@/components/auth-form";
import { appHead } from "@/components/app-shell";
import { supabase } from "@/integrations/supabase/client";
import { safeDest } from "@/lib/safe-dest";

const search = z.object({ redirect: z.string().optional() });

export const Route = createFileRoute("/sign-in")({
  validateSearch: (s) => search.parse(s),
  head: () => appHead("Sign in", "Sign in to your First Line account."),
  component: SignIn,
});


function SignIn() {
  const navigate = useNavigate();
  const { redirect } = Route.useSearch();
  return (
    <AuthPage
      eyebrow="Account access"
      title="Sign in"
      action="Sign in"
      fields={[
        { id: "email", label: "Email", type: "email", autoComplete: "email" },
        { id: "password", label: "Password", type: "password", autoComplete: "current-password" },
      ]}
      onSubmit={async ({ email, password }) => {
        const { error } = await supabase.auth.signInWithPassword({ email: email ?? "", password: password ?? "" });
        if (error) return /confirm/i.test(error.message) ? "Please confirm your email address first, using the link we sent you." : "Email or password not recognised.";
        navigate({ href: safeDest(redirect), replace: true });
        return null;
      }}
      footer={<>
        <Link to="/register" search={redirect ? { redirect } : {}} className="font-medium text-primary underline">Create an account</Link>
        <Link to="/reset-password" className="font-medium text-primary underline">Forgotten password</Link>
      </>}
    />
  );
}
