// Where to go after signing in or registering. Only same-site paths inside the
// signed-in area are allowed, so a link can never send someone to another site.
// The query is kept, so invitation links (/app?invite=...) survive sign-in and registration.
export function safeDest(p?: string | null): string {
  return p && /^\/app(?:[/?#]|$)/.test(p) && !p.startsWith("//") && !/[\\\s]/.test(p) ? p : "/app";
}
