# Vectovia — rules for anyone (or any agent) changing this code

- **Organisations are separate.** Every record belongs to one organisation; isolation is enforced in Postgres
  row-level security through narrow security-definer helpers, never by trusting a browser-supplied ID. No query,
  view, function, count, search, export or AI context may combine or expose one organisation's records to another.
  The national role sees named sites by design; benchmarking for organisations uses anonymous averages only, with
  a minimum group size of 5.
- **Shared sites.** A site may have several participating organisations; the site itself is shared, but each
  organisation's programmes, traps, checks and finds stay private to it unless deliberately shared.
- **Writes go through checked database functions.** Browsers read under RLS and never write tables directly.
  Grants and revokes name specific objects (functions by signature), never whole schemas.
- **Evidence-grade records.** Client-generated IDs, idempotent writes, corrections as new versions with reasons,
  append-only audit, capture time kept separate from server receipt time, fingerprinted original files. Never
  silent overwrite. The mobile app will sync offline records, so the schema must not assume server-generated IDs
  or last-write-wins.
- **AI suggests, people decide.** Only trap images and species/trap context may go to an AI service — never names,
  addresses, personal data or case data. Every suggestion and the officer's decision is logged; only official
  identification marks a species confirmed.
- **Guidance comes from reviewed sources.** Obligation sets, procedures and the powers register are built from
  their source documents (IHR, WHO, UKHSA, UK legislation) and reviewed before publication; never invent legal or
  guidance content in code.
- **Hosting stays portable.** No hosting-specific services (keep the app movable between Cloudflare, Vercel and
  AWS); settings live in environment variables; data stays in London.
- **Database changes** are drafted in `docs/database/` with tests and a rollback, run locally, and applied only
  with the owner's approval.
