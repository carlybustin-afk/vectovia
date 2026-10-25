# Vectovia: next build design brief (owner-supplied, 2026-10-12)

Governing brief for Vectovia, kept as supplied. Owner decisions that refine it are in
`docs/vectovia-plan.md` (section "Decisions"). Where they differ, the plan's decisions apply.

## Purpose
Build Vectovia, a specialist vector-surveillance product within the First Line platform.
Users must be able to access and purchase Vectovia independently of First Line's investigation tools. Surveillance records must exist without an investigation case, with optional links where authorised.
Begin by inspecting the existing repository, authentication, organisation permissions and design system. Reuse suitable components and identify any necessary architecture changes before implementation.

## Product structure
First Line is the shared platform. Vectovia is a distinct module with its own navigation, dashboard, records and subscription entitlement.
Share these platform capabilities where they already exist:
- Login and organisation membership.
- Roles, permissions and product access.
- Design system and common interface components.
- File storage, audit infrastructure and export services.
- Billing infrastructure.

Keep surveillance data, business rules and application interfaces separate from investigation functionality. A future standalone deployment should be possible without rewriting the surveillance core; separate hosting is not required for this build.

## First-build outcome
Deliver and test this complete workflow:
Create site → register and deploy trap → record visit → collect sample → record identification/result → review finding → assign follow-up → export surveillance report.
Use fictional demonstration data.
Use mosquito surveillance as the initial demonstration workflow, with configurable species and trap types. Keep the structure extensible for other surveillance programmes without building those workflows now.
Do not add AI-generated risk scoring or scientific response thresholds in this phase. Assessments and response decisions are officer-recorded, with supporting rationale.

## Screens
1. **Product entry.** A Vectovia entry in the First Line product navigation, shown only to entitled users. Vectovia-only users enter its dashboard after login.
2. **Surveillance dashboard.** Active programmes and sites; deployed traps; visits due or overdue; samples awaiting results; findings awaiting review; outstanding follow-up actions. A map and a corresponding list view. Figures respect the user's record permissions.
3. **Sites.** Searchable records: name and reference; address, coordinates and optional property identifier; location description and access instructions; programme membership and responsible team; linked deployments, visits, samples, findings and actions; notes and attachments. An address must not be mandatory (ports, open land, other locations).
4. **Traps and deployments.** Separate the physical trap (identifier, type, operational status) from its deployment history (trap, site, precise location, start/end dates, responsible officer, planned visit schedule). Retain previous deployments when a trap moves.
5. **Visits and samples.** A straightforward field form: visit date/time and officer; trap condition and observations; collection effort including trap exposure dates; sample identifier and collection method; photographs and attachments; samples collected, no catch, or collection not completed, with reasons. Keep "no catch" distinct from "not checked" and "result pending".
6. **Results and findings.** Sample reference; identification or laboratory result; species/taxon, quantity and units; identification method and responsible person/laboratory; result date, status and supporting documents; uncertainty, inconclusive results and corrections. Results may be pending, provisional or confirmed. A detection stays linked to its original sample and collection history.
7. **Assessment and follow-up.** An authorised officer records an assessment, rationale and follow-up actions (owner, due date, status, completion record). Optional link to an existing First Line investigation case where the user has permission; linking must not expand access to either record.
8. **Reports.** Programme, reporting period and filter scope; sites and deployments; visits and collection effort; results and findings; assessments and actions; maps or location tables; author, generation time and version. A usable PDF report and CSV export in this build; preserve a route to editable Word reports through the shared export service.

## Data design
Distinct records for: surveillance programmes; sites; physical traps; trap deployments; visits; samples; results; assessments; follow-up actions; attachments; audit events; optional external or investigation links.
Every operational record belongs to an organisation/workspace. Programme-specific permissions where required. Stable identifiers and explicit relationships; never store deployments, samples or results solely as free-text notes.
Distinguish when an event occurred, when it was entered, who entered it and who later changed it. Authoritative timestamps in UTC; display local time clearly. Preserve corrections and previous values for evidential records.

## Security and audit
Organisation isolation on the server/database and file storage. No access to another council's data through searches, maps, exports, attachments or direct record URLs.
Reuse the platform role system: administrator, surveillance manager, field officer and read-only, without a separate login system.
Record creation, amendments, result changes, assessments, action completion and exports (actor, timestamp, affected record).
Preserve original uploaded files; derived previews, redacted copies and report exports are distinguishable from originals.

## Future offline mobile app
Prepare for client-generated identifiers, separate event and server-received timestamps, retry-safe synchronisation, attachment upload queues, explicit conflict handling and permission checks when synchronising. Never silently overwrite competing evidential changes. Do not claim offline functionality is delivered in this web build.

## Future integrations
A documented module interface for authorised exchange of site/property references, deployment and visit summaries, selected findings and assessments, follow-up actions, reports and external case references. Maintain a mapping between internal and external identifiers. Idox is a potential future target; do not assume its API access or build a connector now. No cross-system sharing without configured permissions and an audit record.

## Interface and branding
Existing approved First Line design system (navy, teal, restrained supporting colours, rounded controls); current typography. A clear Vectovia identity within the shared platform. Practical forms, readable lists, fast field entry. Plain-language labels; clear distinctions between missing information, pending results and confirmed findings.

## Delivery responsibilities
(Owner decision 2026-10-12: Claude Code builds both the data layer and the screens; Lovable is not used for this build.)
Do not publish, purchase services or change production infrastructure as part of this brief. Identify any required production changes separately.

## Acceptance criteria
1. A Vectovia-entitled user can complete the full surveillance workflow without creating an investigation case.
2. A trap can move between deployments while retaining its history.
3. No catch, missed visits, pending results and confirmed detections are represented correctly.
4. Samples and results remain traceable to their site, deployment and collection.
5. Assessments and completed actions retain the responsible user and timestamps.
6. Two test organisations cannot access each other's records or files, including through direct requests and exports.
7. A surveillance report and CSV export can be generated from the recorded data.
8. Optional case links respect permissions on both sides.
9. Existing First Line functionality continues to work.
10. Delivery notes clearly distinguish implemented features, future offline support, local tests and hosted-environment tests.
