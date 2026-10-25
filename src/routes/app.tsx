import { createFileRoute, Outlet, redirect } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { WorkspaceProvider } from "@/lib/workspace";

// Signed-in area. Client-only because the session lives in browser storage.
// This guard only protects the screens; every read/write is enforced by the
// database (RLS + grants), never by this check.
export const Route = createFileRoute("/app")({
  ssr: false,
  beforeLoad: async ({ location }) => {
    const { data, error } = await supabase.auth.getUser();
    if (error || !data.user) throw redirect({ to: "/sign-in", search: { redirect: location.href } });
    return { user: data.user };
  },
  component: () => (
    <WorkspaceProvider>
      <Outlet />
    </WorkspaceProvider>
  ),
});
