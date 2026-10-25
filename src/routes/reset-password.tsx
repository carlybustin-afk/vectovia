import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { AuthPage } from "@/components/auth-form";
import { appHead } from "@/components/app-shell";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/reset-password")({
  head: () => appHead("Reset password", "Reset the password for your First Line account."),
  component: ResetPassword,
});

function ResetPassword() {
  const navigate = useNavigate();
  const [recovery, setRecovery] = useState(false);
  const [sent, setSent] = useState(false);

  useEffect(() => {
    if (window.location.hash.includes("type=recovery")) setRecovery(true);
    const { data } = supabase.auth.onAuthStateChange((event) => { if (event === "PASSWORD_RECOVERY") setRecovery(true); });
    return () => data.subscription.unsubscribe();
  }, []);

  if (recovery) {
    return (
      <AuthPage
        eyebrow="Account access" title="Choose a new password" action="Save new password"
        fields={[{ id: "password", label: "New password (at least 8 characters)", type: "password", autoComplete: "new-password", minLength: 8 }]}
        onSubmit={async ({ password }) => {
          if ((password ?? "").length < 8) return "Use at least 8 characters.";
          const { error } = await supabase.auth.updateUser({ password: password ?? "" });
          if (error) return "The reset link has expired or was already used. Request a new one.";
          navigate({ to: "/app", replace: true });
          return null;
        }}
      />
    );
  }

  return (
    <AuthPage
      eyebrow="Account access" title="Reset your password" action="Send reset link"
      fields={[{ id: "email", label: "Email", type: "email", autoComplete: "email" }]}
      done={sent ? <p role="status" className="mt-6 border-l-4 border-accent bg-background p-4 text-sm text-muted-foreground">If an account exists for that address, a reset link is on its way.</p> : undefined}
      onSubmit={async ({ email }) => {
        const { error } = await supabase.auth.resetPasswordForEmail(email ?? "", { redirectTo: `${window.location.origin}/reset-password` });
        if (error) return "We couldn't send that just now. Please try again shortly.";
        setSent(true);
        return null;
      }}
      footer={<Link to="/sign-in" className="font-medium text-primary underline">Back to sign in</Link>}
    />
  );
}
