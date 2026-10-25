import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import type { Session } from "@supabase/supabase-js";
import type { QueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

type SessionState = { session: Session | null; ready: boolean; expired: boolean };
const Ctx = createContext<SessionState>({ session: null, ready: false, expired: false });

/** Single auth listener for the app (mounted once in the root route). */
export function SessionProvider({ queryClient, children }: { queryClient: QueryClient; children: ReactNode }) {
  const [state, setState] = useState<SessionState>({ session: null, ready: false, expired: false });

  useEffect(() => {
    const { data } = supabase.auth.onAuthStateChange((event, session) => {
      setState((prev) => ({
        session,
        ready: true,
        // Signed out without the user asking (token could not refresh).
        expired: event === "SIGNED_OUT" && prev.session !== null && !manualSignOut.current,
      }));
      if (event === "SIGNED_OUT") {
        queryClient.cancelQueries();
        queryClient.clear(); // never keep workspace data after sign-out
        manualSignOut.current = false;
      } else if (event === "SIGNED_IN" || event === "USER_UPDATED") {
        queryClient.invalidateQueries();
      }
    });
    supabase.auth.getSession().then(({ data: d }) => setState((s) => (s.ready ? s : { session: d.session, ready: true, expired: false })));
    return () => data.subscription.unsubscribe();
  }, [queryClient]);

  return <Ctx.Provider value={state}>{children}</Ctx.Provider>;
}

const manualSignOut = { current: false };

export function useSession() {
  return useContext(Ctx);
}

export async function signOutAndClear(queryClient: QueryClient) {
  manualSignOut.current = true;
  await queryClient.cancelQueries();
  queryClient.clear();
  await supabase.auth.signOut();
}
