import { createMiddleware } from "@tanstack/react-start";
import { supabase } from "@/integrations/supabase/client";

// Attaches the signed-in user's token to server function calls; the server re-validates it.
export const attachSupabaseAuth = createMiddleware({ type: "function" }).client(async ({ next }) => {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  return next({ headers: token ? { Authorization: `Bearer ${token}` } : {} });
});
