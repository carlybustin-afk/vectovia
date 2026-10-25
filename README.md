# Vectovia (by First Line)

Nationally consistent vector surveillance for points of entry (International Health Regulations) and council
sites (UK guidance). Design: `docs/vectovia/design-v2.md`.

## Run locally

1. Install Node.js 22+, then `npm install`.
2. `.env` holds the Supabase project URL and publishable (browser) key for the `vectovia-mvp` project in London.
3. `npm run dev` — opens on http://localhost:8080.

Checks: `npx tsc --noEmit`, `npm test`, `npm run build`.

## Hosting

Builds for Cloudflare Workers by default (`nitro` preset `cloudflare-module`). Set `NITRO_PRESET` (for example
`vercel` or `aws-lambda`) to build for another host.
