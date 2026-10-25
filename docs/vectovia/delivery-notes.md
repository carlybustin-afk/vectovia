# Vectovia: delivery notes (first build, V0–V7)

Status at 2026-10-18. Brief: `docs/vectovia-brief.md`. Plan and decisions: `docs/vectovia-plan.md` (V-D1–V-D15).
This note separates what is **built**, what is **future offline support**, what was **tested locally**, and what was
**tested on the hosted environment** (brief, acceptance criterion 10).

## 1. Built (live on the owner's Supabase project; screens in this repository)

| Area | What works | Database |
|---|---|---|
| Products and access | Vectovia switched on per council by the platform owner; per-person level (no access / view / field officer / manager) on the Members page; owners and admins have full access | rev 20 |
| Set-up | Programmes run by teams; sites with map (OpenStreetMap), GPS and British National Grid; traps; shared species and trap lists plus council additions | rev 21 |
| Field work | Deploy, move (history kept), end; visits with outcome collected / no catch / not completed; samples with references; visit schedule with due and overdue worked out | rev 22 |
| Photos and files | Fingerprinted originals (SHA-256 on the device, checked by the server), private bucket, 5-minute logged links | revs 23, 23b, `vectovia-files` function |
| Results and risk | Pending, provisional, confirmed, inconclusive, with every correction kept; officer-decided 5×5 risk assessment (First Line never calculates risk); follow-up actions | rev 24 |
| Species and trap library | 17 draft pages with credited open-licence photos (editors only until reviewed); two-stage review and publish; council-private notes | revs 25, 25b |
| Incursions | Opened from findings; eight guided steps with tasks; response area on the map; notifications recorded (never sent); council notification list; stand-down and reopening with reasons | rev 26 |
| Analytics | Effort and coverage, findings over time, map views, response performance; filters by period, programme and site; worked out from the records the person can see | none (browser) |
| Reports and links | Surveillance report (PDF and Word), incursion report, seven CSV exports, export log with fingerprints; links to Investigations cases shown only to people who can see both; external references; integration interface documented | rev 27 |
| Layout | Slim top bar and a side menu grouped by product | none |

Boundaries in place: councils never see each other's data (B1); no case or surveillance data goes to any AI provider, and
Vectovia contains no AI (B2); Vectovia code never imports case code or AI (boundary test).

## 2. Future offline support (not built)

The mobile app for offline capture is a later, separately scoped build. The web build is ready for it:
- every record has an ID generated on the device, and every save can be retried safely;
- capture time and server receipt time are stored separately;
- corrections are new versions with reasons, never silent overwrites; originals of files are kept and fingerprinted;
- access is checked against current membership at the moment of upload.

Still to design for offline: conflict screens, sync queue, device storage and encryption, and background upload.

## 3. Tested locally (throwaway PostgreSQL; `tests/local/run-db-tests.ps1`)

- Every revision's tests, its rollback (functions restored exactly), and the previous revision's tests again after rollback.
  Vectovia counts: rev 20 39, rev 21 46, rev 22 43, rev 23 27, rev 23b 10, rev 24 37, rev 25 23, rev 25b 7, rev 26 64, rev 27 47.
- **V7 proof** (`supabase/tests/v7-vectovia-proof.test.sql`, 65 checks): the whole workflow in a synthetic council without any
  case (criteria 1–5, 7); a second council doing its own work; a sweep of **every** Vectovia table with a council column in both
  directions and for someone in neither council (no rows visible); no signed-out reads and no direct browser writes on any
  Vectovia table; direct requests with the other council's IDs refused for sites, traps, visits, moves, results, assessments,
  actions, incursions, files, storage paths, exports, external references, library notes and case links (criteria 6, 8);
  Investigations still working alongside (criterion 9).
- Full rollback of every revision back to the starting point, then everything re-applies cleanly.
- 113 browser-code unit tests, including the module boundary tests, analytics calculations (with UK summer time),
  CSV formula safety, SHA-256 fingerprints and the PDF and Word writers.

## 4. Tested on the hosted environment (owner's Supabase project, Test Council (made-up))

- Each update applied only with the owner's approval; after each: row security on, no direct browser writes, no signed-out
  reads, storage settings checked.
- Read-only isolation check (2026-10-18, inside a transaction that was rolled back): someone outside Test Council sees 0 rows in
  all 31 Vectovia tables with a council column; the owner sees 63 rows in 25 of them.
- Every Vectovia security-definer function has a locked search path; none can be run signed out.
- Supabase security advisor: no Vectovia findings beyond the expected "signed-in users can call these functions" (all writes
  go through checked functions by design).
- In the browser: deploy, visits, photo upload with fingerprint check, results, risk assessment, action, incursion through
  stand-down, analytics, PDF report and CSV download with the logged fingerprint matching the file, incursion Word report,
  external reference, case-link refusal for an unknown reference.

**Not yet tested on the hosted environment:** a successful case link (Test Council has no cases), the library photo copy and
publish steps (need an author account that isn't the owner's and an entomologist reviewer), and a second real council.

## 5. Open items for the owner

- Entomologist reviewer for the starter lists and library pages (V-O2, K-D1), and an author account that isn't the owner's.
- Demo council (V-O3): a separate "Demo Port Health (made-up)" council, or keep using Test Council.
- Logo: now in the project (public/brand/first-line-logo.webp for the site; master artwork docs/brand/first-line-logo-master.png from the brand guidelines document). Still wanted from the designer: vector artwork, a transparent PNG and a compact mark (brand guidelines, production recommendations).
- Colleague names: people are shown as "Member" plus a short ID until member names are readable council-wide.
- Production changes to raise separately: Mapbox key and cost, invitation emails (sending service and DNS), hosting after
  Lovable, billing.
- Outside Vectovia, from the security advisor: leaked-password protection is off in Supabase Auth (a setting for the owner);
  one platform function `rls_auto_enable` is callable signed out and should be reviewed.
