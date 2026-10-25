# Vectovia: plan

Status: **proposal for owner approval**, 2026-10-12. Governing brief: `docs/vectovia-brief.md`.
Hard rules unchanged and extended to Vectovia: councils never see or benefit from each
other's data (B1); no AI in this phase, and no case or surveillance data goes to an AI
provider (B2).

## 0. The outcome (owner, 2026-10-12)

A **user-friendly system** that supports officers in:
1. **Trap management**: knowing where every trap is, what's due, what's overdue, with fast field entry.
2. **Risk assessment**: a structured, officer-recorded assessment with rationale (no automatic scoring or thresholds in this phase).
3. **Good data and analytics**: clean, traceable records and clear views of trends, effort and findings.
4. **Incursion management**: a good process from a suspected detection of an invasive species through response to stand-down.

Every phase below is judged against these four outcomes, not just the brief's checklist.

## 1. Decisions (owner, 2026-10-12)

| # | Decision |
|---|---|
| V-D1 | **Claude Code builds everything** (data, permissions, screens, exports), pushed through GitHub. Lovable is not used for this build. |
| V-D2 | **Both parts are products.** Each council has "Investigations" and/or "Vectovia" switched on. Existing councils keep Investigations. A Vectovia-only council sees only Vectovia and lands on its dashboard after sign-in. |
| V-D3 | **The platform owner switches products on or off** (audited). No payments in this build. |
| V-D4 | **One place for roles: the Members page.** Council role (Owner, Admin, Member) is unchanged; owners and admins have full access to every product the council has. Each member gets one access level per product: *No access, View only, Field officer, Manager*. Existing members keep Investigations access as now. Teams still decide which cases (and which programmes) a person sees. |
| V-D5 | **Map: switchable provider.** OpenStreetMap tiles in development; Mapbox once the owner adds a key. Mapbox is a paid service above its free tier and needs owner approval before live council use. The map provider learns which area is being viewed, never record details. |
| V-D6 | **Locations:** stored as latitude/longitude (WGS84, from GPS or entered); also shown and enterable as a British National Grid reference. Address optional. |
| V-D7 | **Programmes are run by teams.** Members see the programmes their teams run; owners, admins and Vectovia managers see all. |
| V-D8 | **Species and trap types:** a shared, reviewed starter list maintained by First Line; each council can add private entries, never copied into the shared list. |
| V-D9 | **Identity:** "Vectovia" wordmark with "by First Line", in the existing typeface and palette, until a logo is supplied. |
| V-D10 | **Plan first**, then database updates (each tested locally and approved before applying), then screens. |
| V-D11 | **Structured risk assessment, officer-decided.** The officer chooses likelihood and consequence from set levels; a visible risk matrix gives the overall level, which the officer can change with a reason. Factors considered (e.g. species, location, season, nearby population) and a written rationale are recorded. First Line never calculates or suggests the risk. Councils can adjust the matrix wording later. |
| V-D12 | **Incursion management.** A manager opens an *incursion* from a finding. A guided response turns each step into a task: notify, confirm identification, draw a response area on the map, enhanced trapping, control measures, communications, review, and **stand-down** (recorded decision and rationale). Same "plan, then check and confirm" pattern as Knowledge & Powers, built separately inside Vectovia. |
| V-D13 | **Notifications recorded (never sent by First Line):** UKHSA; port health / APHA where relevant; internal (managers, communications, councillors); plus each council's own list. Each notification records who, when, how and by whom. |
| V-D15 | **Species and trap library** (owner, 2026-10-12): species pages (photos, identification, breeding habitats, activity and season, UK status, diseases, best traps) and trap pages (photo, how it works, target species and life stages, set-up, placement, servicing, tips), linked both ways and from Results and Traps. Shared content, council-private notes. **Photos: open-licence, credited** (photographer, licence, source on each). **Checked by the same two-stage review** (qualified entomologist, then owner approval); shown as draft until then. Built next, before incursion management. |
| V-D14 | **Analytics in the first version:** trap effort and coverage (trap-nights, visits done vs planned, missed visits); findings over time (by species, month, site; positivity); map views (findings, effort, active incursions and response areas); response performance (collection → result → assessment times; actions on time). All figures respect permissions and are worked out from the records, never typed in. |

## 2. How it fits the platform

```
Shared platform (exists)                       Investigations (exists)        Vectovia (new, separate)
──────────────────────────────                 ──────────────────────         ─────────────────────────────
Sign-in, councils, members, teams              cases, notes, letters,         vv_ tables, vv_ functions,
Products per council  (new: V0)                evidence, plans, tasks         src/modules/vectovia,
Access level per person per product (new: V0)  src/modules/cases             /app/vectovia/* screens,
Audit, file storage pattern, design system                                    own file bucket
Export helpers (Word/PDF/CSV)                          ▲                              │
                                                       └──── optional case link ──────┘
                                                             (checked both sides; never widens access)
```

**Module boundary (enforced by a test, like the AI boundary):**
- Vectovia code lives in `src/modules/vectovia/` and `src/routes/app.vectovia.*`; tables and functions are prefixed `vv_`.
- Vectovia never imports the cases module or reads case tables. The only connection is a narrow,
  audited "link to a case" function that checks the person can see the case, and stores just the link.
- Cases code never imports Vectovia. Neither imports any AI module.
- Vectovia files go in their own private storage bucket, not the case evidence bucket.
- So Vectovia could later be hosted separately by moving its module and `vv_` tables, without rewriting it.

**Entitlements never widen data access** (AGENTS.md): a product being switched on only *allows* access;
what each person sees is still decided by their access level, teams and the database's row rules.

## 3. Records (database outline)

| Record | Key points |
|---|---|
| `workspace_products` (+ log) | Which products a council has; changes audited. Platform owner only. |
| `product_access` | Per member, per product: view / field / manage. Owners and admins implied "manage". |
| `vv_programmes`, `vv_programme_teams` | e.g. "Port mosquito surveillance 2026"; kind = mosquito (extensible). |
| `vv_taxa`, `vv_trap_types` | Shared reviewed starter lists (no council data). |
| `vv_council_taxa`, `vv_council_trap_types` | Council-private additions. |
| `vv_sites` (+ versions) | Reference, name, optional address and UPRN, lat/long (+ grid ref), description, access instructions; linked to programmes. |
| `vv_traps` | Identifier, type, status (available, deployed, damaged, retired). |
| `vv_deployments` | Trap → site, exact location, start/end, responsible officer, visit interval. One active deployment per trap; history kept when it moves. |
| `vv_visits` | When it happened vs when entered, officer, trap condition, observations, exposure start/end, **outcome**: samples collected · no catch · not completed (reason). A planned visit with no record shows as **not checked / overdue** (worked out, never invented). |
| `vv_samples` | Sample ID, method; status: awaiting result / resulted. Always linked to its visit → deployment → site. |
| `vv_results` (versions) | Pending · provisional · confirmed · inconclusive; taxon, quantity and unit, method, identified by / laboratory, result date, uncertainty. Corrections add a new version with a reason; earlier versions kept. |
| `vv_assessments` (versions) | Structured risk assessment on one or more results (manager level): likelihood, consequence, matrix level, officer's final level (+ reason if changed), factors, rationale. No automatic scoring. |
| `vv_risk_matrix` | The levels and matrix used (a default, adjustable per council); each assessment records the matrix version it used. |
| `vv_incursions` | Opened from a finding: species, status (suspected, confirmed, responding, monitoring, stood down), lead officer, response area (drawn on the map), linked findings, sites and traps. |
| `vv_incursion_steps` | The guided response steps and their progress (done/skipped with reason), each with tasks (`vv_actions`). |
| `vv_notifications` | Who was notified (UKHSA, port health/APHA, internal, council list), when, how, by whom, with any reference. Recorded only. |
| `vv_stand_downs` | The stand-down decision, rationale, who and when; reopening kept as history. |
| `vv_actions` | Follow-up: owner, due date, status, completion note, who completed and when. |
| `vv_attachments` | Fingerprinted originals in the Vectovia bucket; derived copies labelled as derived. |
| `vv_events` | Append-only audit: create, change, result change, assessment, action completion, export (who, when, what). |
| `vv_links` | Links to a First Line case or an external system (e.g. a future Idox reference), with internal ↔ external ID mapping. |
| `vv_exports` | Log of every report/CSV generated (scope, author, time, version). |

All operational records: council-owned, client-generated IDs (offline-ready), `occurred_at` (when it
happened) separate from `recorded_at` (when the server received it), who entered and who changed it,
UTC stored and UK time shown, idempotent writes, corrections preserved, no silent overwrite.

## 4. Who can do what (Vectovia)

| | View only | Field officer | Manager | Owner / admin |
|---|---|---|---|---|
| See programmes run by their teams | ✓ | ✓ | all | all |
| Sites, traps, deployments | view | create and edit | ✓ | ✓ |
| Visits, samples, results | view | record and correct | ✓ | ✓ |
| Assessments, assign actions | view | — | ✓ | ✓ |
| Complete an action assigned to them | — | ✓ | ✓ | ✓ |
| Reports and CSV export | ✓ | ✓ | ✓ | ✓ |
| Programmes, council species/trap lists | — | — | ✓ | ✓ |
| Product access for members | — | — | — | ✓ (Members page) |

## 5. Phases (each tested locally, then approved before it's applied)

| Phase | What |
|---|---|
| **V0 Products and access** | Products per council (platform owner switch), access levels on the Members page, Vectovia menu entry and landing for Vectovia-only users, Investigations gated as a product (existing councils unchanged). Boundary test. |
| **V1 Set-up** | Programmes and teams, shared + council species and trap-type lists (starter list for review), sites (with map and list), traps. |
| **V2 Field work** | Deployments and moving traps, visit form (fast entry, "use my location"), samples, photos and attachments. |
| **V3 Results and risk assessment** | Results with statuses and corrections, findings awaiting review, structured risk assessment, actions, dashboard (map + list, figures respect permissions). *Outcome 1 and 2.* |
| **V4 Incursion management** | Open an incursion from a finding, guided response steps with tasks, response area on the map, enhanced trapping, notifications record, stand-down and reopening. *Outcome 4.* |
| **V5 Analytics** | Effort and coverage, findings over time, map views, response performance; filters by programme, site, period. *Outcome 3.* |
| **V6 Reports and links** | PDF report and CSV export (logged), incursion report, optional case link, external ID mapping, documented integration interface (no Idox connector). |
| **V7 Proof** | Full workflow (including an incursion) with fictional data in a demo council; two-council isolation tests (records, files, maps, exports, direct URLs); delivery notes separating built / future offline / local tests / hosted tests. |

Phases V0–V3 and V6–V7 complete the brief's first-build workflow; V4 and V5 deliver the incursion and analytics outcomes. V4 can come before V5 if incursions are more urgent.

## 6. Production changes to raise separately (not part of this build)
- Mapbox account and key, and its cost above the free tier (V-D5).
- Billing and payments for products.
- Any separate hosting for a standalone Vectovia.

## 7. Open points (sensible defaults used until decided)
- **V-O1:** Product names on screen: "Investigations" and "Vectovia". (Default as written.)
- **V-O2:** The starter species and trap-type list needs a check by someone qualified in entomology before councils rely on it. Who?
- **V-O3:** Demo data lives in a new made-up council ("Demo Port Health (made-up)") so it never mixes with the test council.
