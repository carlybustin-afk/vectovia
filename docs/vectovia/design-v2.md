# Vectovia design v2 (draft for owner approval)

Status: draft, 2026-10-26. Nothing in this document is built until the owner approves it and each stage.
Replaces the first-build plan (`docs/vectovia-plan.md`) where they differ; the first build's working parts are
reused (section 12).

## 1. Purpose

A nationally consistent vector surveillance and monitoring programme across every place that must monitor
vectors: points of entry under the International Health Regulations (IHR 2005) and council areas under their
own duties. Bought centrally by UK Government and free to every obligated organisation. UK first; designed so
any WHO member state can use it later.

## 2. Principles

1. **Generic, not IHR-only.** A site carries one or more **obligation sets** (IHR point of entry, council
   surveillance duty, others later). Screens, schedules, compliance and dashboards work the same for all.
2. **Follow the guidance exactly.** Each obligation set is built from its source (IHR Annex 1B, Annex 5,
   Articles 19 and 22; WHO guidance; UK guidance and law), reviewed before publication, never invented in code.
3. **Published nationally, adapted slightly locally.** UK Government publishes standard procedures and
   templates; organisations can add to them but not remove mandatory parts.
4. **Generic wording.** "Organisation", "site", "obligation". Framework-specific terms (for example
   "competent authority") appear only inside that framework.
5. **Evidence-grade records.** Corrections keep earlier versions; files fingerprinted; actions attributed and
   timed; nothing silently overwritten (all kept from the first build).
6. **People decide; AI suggests.** AI helps with first-line identification and next steps from trap images only;
   an officer confirms; only official identification marks a species confirmed.
7. **Offline first.** Phones and tablets with about 50% signal: everything recorded in the field works offline
   and syncs safely.
8. **Separate, UK-hosted, assured.** Its own system, data in London, ISO 27001-aligned, Cyber Essentials Plus,
   suitable for G-Cloud.

## 3. Who uses it

| Role | Who | Sees |
|---|---|---|
| Platform owner | First Line operations | Runs the system, adds organisations and users (SSO later) |
| National | UK Government (body to be named) | **Named sites**, their compliance and findings, national totals |
| Organisation | Councils, port health authorities, airport and port operators | Their own sites and records only |
| Organisation roles | Organisation admin, manager, field officer, viewer | As now: admins manage people; managers run programmes; officers record |
| Contractor | Pest/vector control or survey providers | Only the sites and tasks they're given; their work is audited |

Organisations never see each other's records. Benchmarking uses **anonymous averages only**, and only where
enough sites contribute that none can be identified (minimum group size to agree, suggested 5).

**Shared sites.** A site can have more than one participating organisation (for example port health for IHR
surveillance and the council for its own traps nearby). The site itself (name, boundary, zones) is shared;
each organisation's programmes, traps, checks and finds stay private to it unless the participants agree to
share a programme. The national view sees all of it. *(Visibility rule to confirm, section 14.)*

## 4. The hierarchy

```
Organisation
└── Site (point of entry, council site, or other; may be shared)
    ├── Boundary, operational areas, and zones (400 m from PoE operational areas, extendable)
    ├── Obligation sets (e.g. IHR point of entry v1, council surveillance v1)
    ├── Surveillance plan (from national template; versioned; reviewed after surveys)
    ├── Site risk assessment (at least yearly; versioned)
    ├── Programme(s) (season-aware schedules: e.g. weekly in summer, fortnightly in winter)
    │   └── Trap locations (fixed points inside the zone)
    │       └── Deployments → scheduled checks → samples → finds
    ├── Ad hoc inspections (e.g. dipping standing water) → samples → finds
    ├── Delimiting surveys (after a positive; several per site or trap)
    ├── Incursions and control actions
    └── Surveys (annual; wider survey every 2–3 years) and reports to the site operator
```

A **find** is positive or negative for the target species: field identification, optional AI suggestion,
official identification (lab report attached, species officially categorised), and pathogen tests where done.
A suggested or confirmed invasive species automatically flags the find for official identification.

## 5. Obligation sets

Each set lists requirements; each requirement says what must happen, how often, what evidence proves it, and
how its status (red, amber, green) is worked out from records. Sets are versioned and published nationally.

**IHR point of entry v1** (from the owner's analysis of IHR core capacity 5, 18 provisions) maps to records:

| Provision | Evidence in Vectovia |
|---|---|
| 1 Integrated programme | Surveillance plan incl. interception and incursion plan; response capacity |
| 2 Area covered | Site areas (terminals, cargo, external, service providers); wider survey every 2–3 years; plan review |
| 3 400 m zone | Site boundary and zones; traps inside the zone; risk assessment of high-risk vectors |
| 4 Surveillance | Check schedule met (weekly/fortnightly); links to wider surveillance |
| 5 Identification route | Named identification providers; official identification on finds |
| 6 Pathogen testing | Pathogen test records |
| 7 Control action | Control action records; annual survey report to the site operator |
| 8 Competent personnel | Training and competence records with renewal dates |
| 9 Contractors supervised | Contractor access and annual audits |
| 10 Equipment and facilities | Equipment and chemicals register, permissions and expiry |
| 11 Sanitary facilities | Annual sanitary/vector survey |
| 12 Incoming risks | Incoming-risk log and liaison |
| 13 Supervising treatments | Treatment supervision records |
| 14 Affected or suspect conveyances | Conveyance inspections |
| 15 Follow-up between PoEs | Follow-up notices to the next point of entry |
| 16 Records and evidence | Already strong: audit trails, fingerprints, exports |
| 17 Reviewing effectiveness | Annual PoE risk assessment; effectiveness review; corrective actions |
| 18 National and WHO information | National view; national return output |

**Invasive Aedes surveillance (England) v1** (councils and port health), drafted from UKHSA's *National
contingency plan for invasive Aedes mosquitoes in England* (published 21 May 2026, supersedes 2020). To be
checked against the full plan and its annexes, and reviewed by a specialist, before publication. Scotland,
Wales and Northern Ireland have their own arrangements and need separate sets.

| Requirement (from the plan) | Evidence in Vectovia |
|---|---|
| Trap at high-risk sites, coordinated by UKHSA (Level 0): highway service stations, truck stops, inland border facilities, Eurostar stations, June to October, checked every 2 weeks | Sites by type; season-aware schedule; checks done vs planned |
| Ports and airports with international links (Level 0): ovitraps and, where possible, BG traps, April to November, every 2 weeks, by port health officers | Same, on point-of-entry sites (aligns with the IHR set) |
| At-risk communities: targeted traps where modelling shows suitable climate and habitat; trappers trained by UKHSA | Sites with a "modelled risk" reason; training records |
| Samples to UKHSA's medical entomology (MEZE) team for identification | Official identification route; lab report and species recorded |
| Report detections and negative results to UKHSA as soon as practicable; invasive finds immediately | Reporting record and timestamps; national view |
| Engage with UKHSA training (surveillance, incident response, control) | Training and competence records |
| Maintain and exercise a local plan or SOP, proportionate to local risk | Surveillance/contingency plan with review and exercise dates |
| Reduce litter and breeding sites at ports of entry and high-risk sites | Control actions (source reduction) |
| Response by risk level 0–4: e.g. Level 1 control within a 200–300 m buffer (source reduction, larviciding), LA organises and funds with MEZE advice; enhanced surveillance with adult traps, ovitraps and larval sampling | Risk level on incursions; delimiting surveys; buffer zones on the map; control actions |
| Powers cited: EPA 1990 s79–80 (statutory nuisance, abatement notices), Clean Neighbourhoods and Environment Act 2005 s101 (insects), Wildlife and Countryside Act 1981 Sch 9A, Health Protection (Part 2A Orders) Regulations 2010 | Powers and obligations register (knowledge library) |

Source: [UKHSA national contingency plan](https://www.gov.uk/guidance/national-contingency-plan-for-invasive-aedes-mosquitoes-in-england);
[invasive mosquito surveillance](https://www.gov.uk/guidance/invasive-mosquito-surveillance).

## 6. Knowledge library

One reviewed library for Vectovia: **species** (built, awaiting review), **traps**, **procedures and templates**
(plan, risk assessment, survey forms), and a **powers and obligations register** (IHR articles and annexes, UK
legislation and guidance, and what non-compliance can mean, for example a point of entry's designation). Same
two-stage review as now (specialist reviewer, then owner); only reviewed sources.

## 7. Dashboards

- **Site:** risk status, compliance against each obligation set, checks due/overdue, recent finds, open
  actions and surveys.
- **Organisation:** which sites need attention; anonymous benchmarking against national averages.
- **National:** named sites; traps deployed, checks done vs planned, positives, official identifications,
  delimiting surveys and incursions open; compliance by obligation set; national return output.

## 8. Mobile app (phones and tablets, iOS and Android)

Scheduled checks, ad hoc inspections, delimiting survey work, photos, samples and finds, all offline with safe
sync (device-generated IDs, conflict detection, capture time kept separate from receipt time). AI
identification for adults, larvae and eggs from the trap image; shows a suggestion and confidence, suggests
next steps (for example send for official identification); the officer accepts or changes it; every
suggestion and decision is logged. **AI boundary (owner decision 2026-10-26):** only trap images and
species/trap context go to the AI; no names, addresses, case data or personal data; provider under a data
processing agreement, UK/EU processing.

**Approach (easiest and most cost-effective first):** start with a ready-made vision AI model called
through a UK/EU-hosted service (for example through AWS in London), guided by the species library. No
training needed, pennies per image. Every suggestion is logged against the official identification, so
accuracy is measured from day one; if it isn't good enough for a species or life stage, train a custom (and
possibly on-device) model later using the images collected. Realistic expectations: adults photographed well
are the most reliable; larvae need close-up photos; eggs generally can't be identified to species from a photo,
so for eggs the AI counts and flags, and identification goes to the lab.

## 9. Laboratories

Now: attach the lab report and officially record the species (and pathogen results). Later: automatic results
from laboratories through an agreed interface.

## 10. Access and identity

Platform owner adds organisations and users now; single sign-on later through Microsoft Entra ID (SAML/OIDC).
Multi-factor sign-in required for admins and the platform owner from the start.

## 11. Separate system, hosting and assurance

- Its own system: separate database project (Supabase, London) and its own app deployment, on a First Line
  address, e.g. `vectovia.firstlineeph.com` (and `.co.uk`). No case data and no link to Investigations at first.
- Development and production kept separate; backups and point-in-time recovery.
- ISO 27001-aligned controls, Cyber Essentials Plus, WCAG 2.2 AA accessibility, DPIA and supplier DPAs,
  penetration test before go-live; evidence suitable for a G-Cloud listing (see
  `docs/security/security-compliance-plan.md`).

## 12. What changes from the first build

| Keep (reuse) | Change | New |
|---|---|---|
| Fieldwork: deployments, visits, samples | Site-first hierarchy and screens | Site boundary, areas, 400 m zones |
| Results with versions, lab fields, attachments | Risk assessment moves to site level, yearly, versioned | Obligation sets and compliance view |
| Fingerprinted files, audit trails, exports | Incursions linked to delimiting surveys | Surveillance plans, surveys, reviews |
| Species and trap library | "Council" wording becomes generic | Ad hoc inspections, delimiting surveys, pathogen tests |
| Analytics and reports | Schedules become season-aware | Training, contractors, equipment and chemicals, conveyances, follow-ups, incoming risks |
| Isolation tests and security patterns | Moves into its own system | National view, anonymous benchmarking, mobile app, AI identification, SSO |

## 13. Build stages (each approved before it starts)

1. **Set-up:** separate system, domain, environments, sign-in with MFA, roles, platform-owner admin.
2. **Sites:** boundary, areas, zones, shared sites, obligation sets (IHR v1).
3. **Plans and risk:** national templates, surveillance plans, site risk assessments, season-aware programmes.
4. **Field records:** checks, finds (positive/negative, official ID placeholder), ad hoc inspections,
   delimiting surveys, pathogen tests, control actions.
5. **Compliance and dashboards:** site, organisation and national views; anonymous benchmarking.
6. **Other IHR records:** training, contractors, equipment and chemicals, conveyances, follow-ups, incoming
   risks, surveys and reviews, national return.
7. **Knowledge library:** procedures, templates, powers register (reviewed sources).
8. **Mobile app:** offline field app, then AI identification.
9. **Assurance:** penetration test, Cyber Essentials Plus, ISO 27001 evidence, SSO with Entra ID.

## 14. Decisions (owner, 2026-10-26)

1. Council obligations: drafted from UKHSA's 2026 contingency plan (section 5); specialist review pending.
2. Shared sites: each organisation's records private unless shared. **Agreed.**
3. National body: probably UKHSA; to confirm.
4. Benchmarking minimum group size: **5.**
5. AI: easiest and most cost-effective first (section 8).
6. Address: **`vectovia.firstlineeph.com`.**
7. Start the new system clean. **Agreed.**
8. Build away from Lovable (section 15).

## 15. Building away from Lovable

Vectovia v2 is built as its own system, outside Lovable, from the start:
- its own GitHub repository, seeded from the existing Vectovia code and the shared sign-in/organisation pieces,
  with Lovable-specific parts removed;
- its own database projects (development and production, London);
- its own hosting, on `vectovia.firstlineeph.com` (records added in GoDaddy);
- automatic checks on every change, and changes through pull requests the owner approves.
