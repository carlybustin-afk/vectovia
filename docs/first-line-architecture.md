# First Line — architecture proposal

Status: PROPOSAL for owner review, 2026-10-11. Nothing here is implemented,
migrated or deployed. Governing brief: `docs/first-line-brief.md`. Standing
rules: `AGENTS.md` (all still apply).

## 1. Current state (inspected at commit 532f12b)

**Applied to the hosted project** `first-line-development`
(rnnguwjlhropyccqjipt). Confirmed by a read-only check on 2026-10-11: all 5
migrations listed, 19 public tables with RLS on, 60 library versions. That
covers Build 02 rev 6 foundation, rev 7 content-admin publishing, rev 8
official-guidance source allow-list and rev 9 AI pilot. `roadmap.md` and the
rev 6 file header still say "not applied"; they are stale.

| Area | What exists | Verdict |
|---|---|---|
| Workspaces | `workspaces` (personal / organisation), `workspace_members` (owner/admin/member), invitations, last-owner and personal-owner guards, operator-only org provisioning | **Reuse as is** |
| Isolation pattern | `is_member` / `has_ws_role` security-definer helpers; child `workspace_id` set by trigger from the parent, pinned by composite FK `(id, workspace_id)`; column-level grants; RLS on every table | **Reuse as the template** for every new module table |
| Audit | `audit_events` append-only, written only by definer functions, readable by owner/admin | **Reuse** for security/admin events. Gap: no actor role snapshot |
| History | `forbid_update()` append-only trigger; immutable `created_by` + separate `custodian_id` with audited recovery | **Reuse** for case notes and corrections |
| Knowledge & Powers library | `legal_records` + `legal_record_versions` (versioned, draft→approved→withdrawn, allow-listed official URLs, independent publication gate, verification dates). Card = source + summary + questions + limits in one `content` jsonb | **Reuse the pipeline; restructure the content model** (conflict C1) |
| Answers | Deterministic server composer (`answer-flow.ts`, `review-flow.ts`) from published current cards only; `answer_versions` + `answer_sources` pin cited legal versions | **Reuse** for case-linked guidance |
| Enquiries | Private-by-default K&P enquiries, named sharing, fact versions | **Keep as K&P records**; do not reuse as cases (conflict C3) |
| AI pilot | Allow-listed user, stop switch, US$5 budget ledger; sends officer conversation text plus published card text to the Lovable AI gateway (`openai/gpt-6-astra`); output validated for citations | **Leave unchanged.** Must not receive case data (conflict C6) |
| App shell | `/app` routes, workspace switcher, `wsKey` cache clearing, fail-closed `setup-pending / denied / signed-out` states | **Reuse** for Cases routes |
| Tool catalogue | Public tool list: Investigation Builder, Evidence & Inspection Toolkit, Vector Surveillance Toolkit (Vectovia), etc. | Naming differs from brief (D9); no change now |
| Tests | 51 vitest tests (49 pass; the 2 legal-boundary tests fail on Windows only because of `\` path separators), pgTAP suites, guarded integration harnesses | **Reuse**; fix the Windows path match separately |

## 2. Conflicts and gaps against the brief

- **C1 — Knowledge model is a single "card".** The brief needs *authoritative
  sources*, *legal powers/pathways* and *practical investigation procedures* as
  separate records with versioned links. Today one card mixes them, and
  `guidanceIds()` in `answer-flow.ts` hard-codes card IDs and keywords for
  routing.
- **C2 — Procedures have no home.** The library accepts only legislation and
  allow-listed official guidance URLs. First Line-authored practical
  procedures (reviewed professional content, no council data) can't pass
  that gate as it stands (D4).
- **C3 — Enquiry visibility is custodian-only.** Owners and admins see nothing
  unless a record is shared by name. That suits private K&P enquiries but not
  council cases, which need team visibility plus restriction (D2). Cases need
  their own access rules, not the enquiry ones.
- **C4 — Roles are coarse.** owner/admin/member only. That's enough for the
  first build; finer roles (manager, read-only, team) come later.
- **C5 — No actor role snapshot.** `docs/architecture/future-evidence-and-property-registry.md`
  requires recording the actor's role at the time of each action. New case tables must store it.
- **C6 — AI data boundary.** The pilot already sends officer free text to an
  external provider. Case descriptions and notes contain personal data, so
  case-linked guidance must use the deterministic composer only, with no AI.
- **C7 — Client-generated IDs.** Enquiries use server defaults and an
  insert-without-RETURNING workaround. New tables should accept client
  UUIDs (mobile-ready, idempotent) and still validate them server-side.
- **C8 — Stale documentation.** `roadmap.md` and the migration headers don't
  match the applied state.

## 3. Module boundaries (one application, one database)

```
platform/   identity, workspaces, membership, teams, confidentiality policy,
            workspace settings, audit, tasks*, documents*, files*
knowledge/  sources, powers & pathways, common procedures, council
            procedure variants*, versioned links, composer
cases/      cases, properties, case locations, notes, case timeline, case links
inbox/      incoming items*            (reserved, not built)
evidence/   evidence items, handling*  (reserved, not built)
vectovia/   sites, traps, visits, samples, detections, responses*  (not built)
exports/    DOCX/PDF with manifests*   (not built)
```
`*` = later phase.

Rules:
- A module owns its tables, its RPCs and its `src/modules/<name>/` code. Other
  modules call its RPCs or service functions, never its tables directly.
- Every module table carries `workspace_id`, set by the database and pinned
  by a composite FK. Shared knowledge content (sources, powers, common
  procedures) is the one exception: it holds no council data and has no
  workspace column, as now. Council procedure variants are council data, so
  they live in a separate workspace-scoped table.
- Cross-module links are explicit link rows (for example `case_guidance`, and
  later `case_links` to evidence, inspections or Vectovia visits), never
  shared tables.
- The **service interface is the database RPC contract.** Web calls it now,
  and the mobile app calls the same RPCs later. Write RPCs take a
  client-generated UUID and are idempotent on it.

## 4. Owner decisions (2026-10-11)

| # | Decision | Effect on the design |
|---|---|---|
| D1 | Revs 6–9 confirmed live (read-only check) | Build on the applied schema; fix stale docs in Phase 0 |
| D2 | **Team-based visibility.** Admins assign cases, and assign people to teams | Adds `teams` and `team_members`; each case has an owning team; access comes from team membership or assignment (§6) |
| D3 | **A personal case list must exist** | Every user gets a "My cases" view (assigned to me or created by me) in each workspace. A personal workspace can also hold its own cases, visible only to its owner (see D11) |
| D4 | **AI-assisted common procedures, with council variants** | Phase 2: First Line keeps common procedures (AI may draft them, a human reviewer publishes them). Councils adapt them or add variants in their own workspace. **Case data is never an AI input** (§9) |
| D5–D7 | **Councils decide confidentiality per field**, and likewise the reference format, statuses and property visibility | Adds per-workspace settings: reference prefix, status list and a field confidentiality policy. Confidential values are stored in rows the database can gate (§5) |
| D8 | No Inbox navigation item until Phase 5 | Model reserved only |
| D9 | **Withdrawn — no renames.** Brand Guidelines v1 fixes the initial module names (Investigation Builder, Vector Surveillance Toolkit, and so on) and keeps Vectovia as a separate enterprise product | Public catalogue unchanged. Inside the app, "Cases" is the working area of the Investigation Builder module (D16) |
| D10 | No address provider now. Revisit PSGA (AddressBase/OS Places) access later | Manual entry plus suggestions from the council's own property records |
| D11 | Personal workspaces may hold cases | Owner-only access; same tables and rules |
| D12 | Owners and admins see every case in their workspace | For assignment and oversight. Confidential fields still need confidential access |
| D13 | One owning team; people and other teams can be added | Adds `case_collaborators` (a user or a team), which grants standard read and write. Confidential fields still need confidential access |
| D14 | No AI learning from cases, ever, from any council | Enforced as a hard boundary (§9), not as a later option |
| D17 | Postcode check via postcodes.io | Only the typed postcode leaves First Line |
| D18 | Multiple categories per case; structured complainant details; follow-up notes; review dates and "My work" | Revs 11–13 |
| D19 | Dashboard: admins see the whole council; everyone else only cases they can see | SECURITY INVOKER counts |
| D20 | Postcode address list from OS Places | Server-side; only the postcode goes to Ordnance Survey; awaiting the owner's key |
| D21 | Evidence built properly (release 2): photos, PDF, Word/Excel, audio up to 50 MB; originals immutable; SHA-256 fingerprint checked server-side; capture vs upload time; append-only handling log of upload, verification, views and downloads | Private storage bucket plus a Supabase edge function (the only component allowed to read the stored file or issue download links); owner approves before either is created |
| D22 | Audio transcription runs on the officer's own device (release 2b) | Audio never goes to an AI provider (keeps D14/B2); the officer checks the transcript, saved as a labelled note linked to the recording |

## 5. Record relationships

```
workspace 1─* workspace_member 1─* team_member *─1 team *─1 workspace
workspace 1─1 workspace_case_settings        (reference prefix, next number)
workspace 1─* case_status                     (council labels → fixed lifecycle: open / closed)
workspace 1─* field_policy                    (field_key → standard | confidential)
team 1─* team_member (can_view_confidential flag)
workspace 1─* property 1─* case_location *─1 case          (many-to-many)
team 1─* case  ;  case 0..1─ assigned_to → workspace_member
case 1─* case_collaborator → (workspace_member | team)   (same workspace only)
case 1─* case_field_value                     (configurable details, each with a level)
case 1─* case_note 1─* case_note_version      (original + corrections)
case 1─* case_event                           (timeline: status, assignment, team, links)
case 1─* case_guidance *─* legal_record_version (pinned citations)
case 1─* case_link → {task, document, correspondence, evidence, inspection,
                      recommendation, decision, outcome, vectovia_visit}   (later)
incoming_item *─0..1 case                     (Phase 5; never auto-created)
knowledge: source_version *─* power_version *─* procedure_version (common)
           procedure_version 1─* council_procedure_variant (workspace-scoped)  (Phase 2)
```

**How field confidentiality works.** RLS works on rows, not columns, so each
configurable detail is a row in `case_field_values` (case_id, field_key,
value, level).
- Each council's `field_policy` sets the default level for each field:
  complaint description, complainant details, additional details, location
  notes, or the address itself.
- An officer can *raise* a field to confidential on one case, but can't lower
  it below the council's policy.
- `standard` rows are readable by anyone who can read the case. `confidential`
  rows also need confidential access, which is an explicit grant (§6). A role
  alone never gives it.
- Hidden fields show as "Confidential — restricted" and are never sent to the
  browser.
- The core list fields are always visible to case readers so the list works:
  reference, status, team, assigned officer, dates.
- A property with a confidential address (for example a refuge) shows only
  its postcode district to readers without confidential access.

First-build tables (drafted in `docs/database/`, not applied):

| Table | Purpose |
|---|---|
| `teams`, `team_members` | Teams per workspace. A team member must be a current workspace member (composite FK, cascade on removal). A team can carry a `can_view_confidential` flag |
| `confidential_access` | Member-level confidential grants (workspace_id, user_id, granted_by, granted_at). Cascades on membership removal; grants and revocations are audited |
| `workspace_case_settings`, `case_statuses`, `field_policies` | Council configuration, seeded with defaults: prefix `FL`, statuses Open / In progress / On hold / Closed, and complainant details set to confidential (everything else standard) |
| `properties` | Client UUID, address lines, town, postcode, optional UPRN, `source` (manual / suggested), `address_level`, created_by |
| `cases` | Client UUID, reference (generated from the settings and unique per workspace), optional council reference, team_id, assigned_to, status_id, created_by (immutable), created_at, updated_at |
| `case_field_values` | The configurable details above; append-only versions, so earlier values are kept |
| `case_locations` | case ↔ property, role (primary / related) |
| `case_collaborators` | case_id plus exactly one of user_id or team_id, added_by, added_at. The user or team must belong to the case's workspace (composite FKs). Owners, admins and the owning team can add or remove collaborators |
| `case_notes`, `case_note_versions` | Append-only. The server sets author, author role and `recorded_at`; `observed_at` is optional and entered by the officer; a correction needs a reason |
| `case_events` | Server-written timeline with actor and actor role |
| `case_guidance`, `case_guidance_sources` | Saved composer output plus pinned approved versions |

All writes go through security-definer RPCs. The server sets identity, role
and timestamps; the browser can't.

## 6. Permission matrix (organisation workspace)

"Case participant" = a member of the owning team, the assigned officer, or a
collaborator (a named user, or a member of a collaborating team).

| Action | owner | admin | case participant | other member | non-member / anon |
|---|---|---|---|---|---|
| Create, rename or delete teams; add or remove team members | ✓ | ✓ | ✗ | ✗ | ✗ |
| Grant or revoke confidential access (audited) | ✓ | ✓ (not to self) | ✗ | ✗ | ✗ |
| Edit council settings (prefix, statuses, field policy) | ✓ | ✓ | ✗ | ✗ | ✗ |
| See case in list or search | all (D12) | all (D12) | ✓ | ✗ (team visibility comes first, even for the creator) | ✗ |
| Create case | ✓ | ✓ | ✓ (owned by one of their teams) | ✗ | ✗ |
| Assign case to team or officer | ✓ | ✓ | ✗ | ✗ | ✗ |
| Add or remove collaborators | ✓ | ✓ | owning team members | ✗ | ✗ |
| Edit details, status | ✓ | ✓ | ✓ | ✗ | ✗ |
| Read standard fields | ✓ | ✓ | ✓ | ✗ | ✗ |
| Read confidential fields | only with confidential access | only with confidential access | only with confidential access | ✗ | ✗ |
| Add note / save guidance | ✓ | ✓ | ✓ | ✗ | ✗ |
| Correct a note | own notes | own notes | own notes | ✗ | ✗ |
| Delete case, note or version | ✗ (close only) | ✗ | ✗ | ✗ | ✗ |
| Property history and counts | only over cases they can read | same | same | same | ✗ |
| Read `audit_events` | ✓ | ✓ | ✗ | ✗ | ✗ |

- **Confidential access** is an explicit grant. It comes either from a
  member-level grant or from membership of a team flagged
  `can_view_confidential`. A role alone (including owner or admin) never
  reveals confidential fields. Every grant and revocation is audited.
- Removing someone from a team, as a collaborator, or from the workspace ends
  their access immediately. Reassignment takes effect at once.
- Personal workspace: the owner can do everything; no one else has access.
- Content roles (knowledge publishing) stay separate from workspace roles.
- Entitlements never widen access.

## 7. Phased implementation

| Phase | Scope | Gate |
|---|---|---|
| 0 | Fix stale roadmap and headers; Windows path fix in the boundary test; these docs and the brand guidelines | Owner review; no schema |
| **1a** | Teams and team management; council settings with defaults; cases with list, search and "My cases"; case workspace; properties with suggest and manual entry; attributed notes with corrections; timeline; field confidentiality using the default policy; case-linked deterministic guidance | Owner approves the migration draft and pgTAP tests |
| 1b | Admin screens to edit the field policy, statuses and reference prefix | After 1a is live |
| 2 | Knowledge restructure: sources / powers & pathways / common procedures with versioned links; AI-drafted, human-reviewed common procedures; council procedure variants; data-driven routing; ordered-procedure output; personal-data check on the AI question box | B2 rules (§9) |
| 3 | Shared tasks, documents, correspondence; inspections, recommendations, decisions, outcomes; AI-proposal vs officer-decision records | |
| 4 | Evidence storage, originals, hashes, handling history; DOCX/PDF exports with manifests | Storage and retention decisions |
| 5 | Inbox & Triage (no mailbox connection until separately approved) | |
| 6 | Vectovia module with explicit case links | Separate scoping |
| 7 | Mobile offline capture using the same RPCs | Separate scoping |

## 8. First build (Phase 1a)

**Screens**: `/app/cases` (list, search, filters: My cases / team / status),
`/app/cases/new`, `/app/cases/$caseId` (details, locations, notes, timeline,
guidance), and `/app/teams` (admins). Navigation adds "Cases" and "Teams".

**Out of scope**: evidence and files, tasks, documents, exports, inbox,
Vectovia, AI on cases, address providers, deletion, admin config screens (1b),
procedures (Phase 2), mobile.

**Dependencies**: owner approval of `docs/database/rev10-cases.sql` and its
pgTAP tests, applied by the owner through Lovable/Supabase.

**Acceptance criteria**
- Nothing in workspace A can be read, searched, counted or linked from
  workspace B (pgTAP plus API harness).
- A member outside a case's team who isn't assigned can't see it, find it in
  search or see it counted in property history. Removing them from the team
  ends access immediately.
- Confidential field values never reach a browser without confidential
  access (tested at the API, not just the UI). An officer can raise a field's
  level but can't lower it below policy.
- Note author, role and `recorded_at` are set by the server; client-supplied
  values are rejected. Notes and versions can't be updated or deleted; a
  correction keeps version 1 and needs a reason.
- `observed_at` and `recorded_at` are stored and shown separately.
- Case references follow the council's settings and are unique per workspace.
- "My cases" shows exactly the cases assigned to or created by the user.
- Saved guidance cites only approved versions and keeps them after a
  withdrawal.
- No case data reaches the AI provider: the B2 boundary test exists and
  passes, and guidance uses the deterministic composer only.
- Collaborators (users or teams) get standard access only, and lose it when
  they're removed. Confidential fields need an explicit grant, even for
  owners and admins.
- New screens follow §8a: existing tokens and fonts only, no raw hex
  colours, status and confidentiality shown in text rather than colour alone,
  keyboard-operable, AA contrast, and usable at mobile width.
- Existing tests stay green; existing tables, grants and AI settings are
  unchanged.

## 8a. Brand and interface rules (all new screens)

Source of truth: **`docs/brand/brand-guidelines-v1.md`** (from the owner's
Brand Guidelines v1 Word document), implemented through the tokens in
`src/styles.css`. The palette in the code already matches the guidelines
exactly. New modules add no new colours, fonts or component libraries.

- **Palette, through the existing tokens only** (`primary`, `secondary`,
  `accent`, `signal-teal`, `deep-navy` and so on; no raw hex values in
  components):
  - Deep Navy `#082B4C`: headings, primary actions.
  - Ink `#172536`: body text.
  - Signal Teal `#14A38B`: accents, active states.
  - Field Mist `#EEF7F5`: soft backgrounds.
  - Data Blue `#287A8B`: focus ring and secondary data accents only.
  - Grey `#647381`: secondary text.
  - White.
  - Never use the logo's green as an interface colour.
- **Contrast**: never white text on Signal Teal for small labels or buttons.
  Use Navy or Ink text on light surfaces (the existing teal buttons already
  use Deep Navy text).
- **Type**: IBM Plex Sans, self-hosted from `public/fonts/`, never a CDN.
  Confirmed by the owner (D15), even though the guidelines name Inter as a
  candidate.
- **Word/PDF exports** (Phase 4): Aptos, per the guidelines.
- **Logo**:
  - The supplied artwork, intact and in proportion, on white or a quiet light
    surface, with clear space of one node diameter.
  - Never stretched, rotated, shadowed, placed over imagery or rebuilt in
    type.
  - Where space is narrow, use plain "First Line" text until an approved
    compact mark exists.
  - The logo's green stays in the logo only.
- **Look**: credible, calm and mostly white, with clear hierarchy and
  generous space.
  - Use the line-and-node motif as the recurring device for pathways and
    progression (the `node-line` component), for example in case timelines
    and the Assess → Decide → Act workflow.
  - Prefer tables, lists and structured work areas for professional tasks.
  - Uppercase only for short labels.
  - Avoid generic government, clinic, consultancy and AI-startup looks:
    no stock images, robot visuals, heavy gradients, glassmorphism, neon,
    excessive animation or all-rounded-card layouts.
- **Components**: reuse the `src/components/ui` primitives and the app-shell
  patterns (`AppShell`, `StateMessage`, `EmptyState`, `ErrorState`, the
  teal left-border status style).
- **Case statuses and confidentiality**:
  - Show status as a text label with a restrained Navy/Teal/Grey treatment,
    never colour alone and never red/amber/green traffic lights.
  - Mark confidential fields with the words "Confidential — restricted" and
    an icon, not just a colour or blur.
- **Labels the brief requires**: "Professional suggestion", "Statutory
  requirement", "AI proposal" and "Officer decision" each get a consistent,
  text-first label style, so people can tell them apart without relying on
  colour.
- **Accessibility**: WCAG 2.2 AA contrast, full keyboard use, visible Data
  Blue focus ring, sensible heading order, form labels and error text, and
  layouts that work on mobile (field officers).
- **Voice and claims**:
  - Plain, professional English with the approved wording.
  - "Support professional judgement", never "decides" or "legal advice".
  - Planned features are labelled planned.
  - No invented data, customers or certifications (for example GDPR or ISO
    27001).
  - Honest empty and "setup pending" states.
- **Ask First Line**: source-grounded decision support, with the actual
  source always visible and AI explanation kept visually distinct from
  legislation and guidance.

## 9. Hard boundaries: council separation and AI (owner decision D14)

These are permanent rules, not options. Each one is enforced in more than one
layer, so no single mistake can break it.

### B1. No council can ever see, or benefit from, another council's cases
| Layer | Enforcement |
|---|---|
| Database | Every case, property, note, team and procedure-variant row carries `workspace_id`, set by the database and pinned by composite FKs. RLS requires current membership of that workspace. There is no cross-workspace query, view, RPC or count |
| Shared knowledge | Common procedures, sources and powers have no workspace column and no write path from any workspace table. Council procedure variants are workspace-scoped and can never be copied, promoted or merged into common content |
| AI | AI is never given case data from any council (B2), so it can't carry one council's cases to another |
| Tests | pgTAP and API tests: a member of workspace A gets nothing from B for every new table, RPC, search and count. A static test checks that no migration creates a view or function joining workspace data across workspaces |

### B2. No case data ever goes to an AI provider
Case data means cases, properties, locations, notes, field values,
collaborators, guidance saved to a case, and later evidence, inspections,
correspondence and inbox items.

| Layer | Enforcement |
|---|---|
| Code boundary | The AI provider (`ai-provider.server.ts`) is called only from Knowledge & Powers code. A boundary test (modelled on `legal-pipeline-boundary.test.ts`) fails the build if any AI module imports `src/modules/cases`, `inbox` or `evidence`, references a case table, or if any case module imports the AI provider |
| Typed input | The prompt builders accept only published knowledge cards plus the officer's own typed question. No function accepts a case object |
| Case guidance | The case guidance panel uses the deterministic composer only and has no AI path. Its question box starts empty, so case text is never copied in automatically |
| Procedure drafting | AI drafting of common procedures runs in the content-admin tool, from published source cards only. It has no workspace connection. Drafts are labelled "AI proposal" until a human reviewer publishes them |
| Learning | No training, fine-tuning, retrieval or analytics over case history, for any council, including a council's own cases. Best practice comes only from published sources and human-reviewed common procedures |
| Documentation | Recorded in `AGENTS.md` and `CLAUDE.md` so every future change (Claude or Lovable) is checked against it |

**One remaining human risk.** Software can't stop an officer from typing case
details into the Knowledge & Powers AI question box themselves. Today that
box is limited to the allow-listed testing pilot, uses synthetic enquiries,
and has a US$5 budget. Before any wider rollout, the box needs a clear warning
not to enter personal or case details, plus an automatic check that blocks
obvious personal data (names, addresses, phone numbers, emails) before
anything is sent. That's listed as a Phase 2 prerequisite.

## 10. Status of decisions

D1–D16 are decided. Brand decisions (2026-10-11):
- **D15** App typeface stays **IBM Plex Sans** (self-hosted).
- **D16** The module keeps the guideline name **Investigation Builder**; the
  in-app navigation label is **"Cases"**. When the Phase 6 module is scoped,
  it must say whether it is Vectovia (enterprise) or the lighter Vector
  Surveillance Toolkit.

The next owner gates are:
- approval of the Phase 0 copy and doc changes before they're pushed to `main`;
- approval of the Phase 1a migration draft and its tests before it's applied
  (drafted: `docs/database/rev10-cases.sql`; review notes in
  `docs/database/rev10-review.md`).
