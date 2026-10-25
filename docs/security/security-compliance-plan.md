# First Line: security and compliance plan (SOC 2 principles, ISO 27001)

Status: draft for the owner, 2026-10-18. A plan, not a certificate. Neither SOC 2 nor ISO 27001 can be
"built in" by code alone: both need written policies, records kept over time, and an independent auditor.
This plan shows what First Line already does, what's missing, and the order to close the gaps so that
an audit becomes straightforward.

## 1. The standards in brief

- **SOC 2** (American, widely recognised): an auditor reports on your controls against the Trust Services
  Criteria: **Security** (required), plus optionally **Availability**, **Confidentiality**, **Processing
  integrity** and **Privacy**. Type 1 = controls designed properly at a point in time; Type 2 = controls
  worked over a period (usually 3–12 months).
- **ISO/IEC 27001:2022** (international, common in UK public sector): you run an **information security
  management system (ISMS)**: scope, risk assessment, a Statement of Applicability covering the 93 Annex A
  controls (organisational, people, physical, technological), internal audit and management review, then
  certification by an accredited body.
- **What UK councils usually ask for first:** **Cyber Essentials** (then **Plus**), UK GDPR compliance with a
  data processing agreement and DPIA, data held in the UK, a penetration test, and the NCSC Cloud Security
  Principles. ISO 27001 is often "preferred"; SOC 2 is less common in UK councils but useful for wider sales.

Recommended order: **Cyber Essentials → ISO 27001 → SOC 2 Type 2** (most controls overlap, so SOC 2 then
reuses the ISO 27001 evidence).

## 2. What's already strong (built into the product)

| Area | What First Line does | Maps to |
|---|---|---|
| Council separation | Every record belongs to one council; isolation enforced by the database (row-level security), never by the browser; proven by tests including a sweep of every Vectovia table and direct cross-council requests (`supabase/tests/v7-vectovia-proof.test.sql`) | SOC 2 CC6.1; ISO 8.3, 8.15 |
| Least privilege | Browsers can only read; every change goes through a checked database function; permissions granted to named functions only (`tests/integration/permission-sentinel.sh`); product access never widens data access | CC6.1, CC6.3; ISO 5.15, 5.18, 8.2 |
| Audit trails | Append-only histories for cases, Vectovia records, exports, invitation emails and confidential-field access; corrections keep earlier versions with reasons | CC7.2, PI1; ISO 8.15, 5.28 |
| Evidence integrity | Files fingerprinted (SHA-256) on the device and checked by the server; originals preserved; reports and exports fingerprinted and logged | PI1; ISO 5.28, 8.24 |
| Confidential data | Confidential case fields need an explicit, audited grant; never sent to a browser without access | C1; ISO 5.12, 8.3 |
| AI boundaries | Case and surveillance data never sent to an AI provider or used for AI learning; enforced by boundary tests | C1, P; ISO 5.34 |
| Secrets | No secrets in code; keys held in Supabase settings; one-time invitation links stored only as a hash | CC6.1; ISO 8.24, 5.17 |
| UK data location | Database, sign-in and files on AWS London (`eu-west-2`); email via Resend EU (Ireland) | P, C1; ISO 5.34 |
| Change history | Every database change is a reviewed file in Git with tests and a rollback, applied only with owner approval | CC8.1; ISO 8.32 |
| Dependencies | No known vulnerable packages in production dependencies (npm audit, 2026-10-18) | CC7.1; ISO 8.8 |

Inherited from providers (confirm with their current reports): encryption at rest and in transit, physical
security of data centres, and the providers' own SOC 2 / ISO 27001 controls (Supabase, Vercel and AWS publish
these; check Resend's).

## 3. Gaps, in priority order

### A. Before any council uses real data (must have)

| # | Gap | Action | Who | Maps to |
|---|---|---|---|---|
| A1 | Free Supabase plan: projects pause when idle; no restorable backups | Supabase **Pro** with daily backups; consider point-in-time recovery | Owner (cost ~$25/month) | A1.2; ISO 8.13, 5.30 |
| A2 | Test and real data in one project ("first-line-development") | Separate **production** project in London, built from the Git migrations; keep this one for testing | Owner approves, Claude builds | CC8.1; ISO 8.31 |
| A3 | No two-step sign-in (MFA) | MFA (authenticator app) **required** for platform admins, council owners/admins and content team; offered to everyone | Claude builds | CC6.1; ISO 8.5 |
| A4 | Password rules weak (8 characters; leaked-password check off) | At least 12 characters; turn on Supabase leaked-password protection | Claude (code) + owner (setting) | CC6.1; ISO 5.17 |
| A5 | No security headers on the site | Content Security Policy, HSTS, frame protection, referrer and permissions policies at the host | Claude builds | CC6.6; ISO 8.20, 8.23 |
| A6 | No automated checks on GitHub | CI on every push: type-check, unit tests, database tests, dependency audit, secret scanning; Dependabot alerts | Claude builds, owner enables in GitHub | CC8.1, CC7.1; ISO 8.25, 8.29, 8.8 |
| A7 | Code changes go straight to `main` | Protect `main`: changes via pull request with checks passing; owner approves (Claude can't approve its own) | Owner setting, Claude works via PRs | CC8.1; ISO 8.32, 5.3 |
| A8 | Data protection paperwork | DPAs with Supabase, Vercel, Resend (and Lovable while used); a DPIA; privacy notice; record of processing | Owner (templates from Claude) | P; ISO 5.31, 5.34 |
| A9 | Monitoring | Error monitoring, uptime alerts, alerts on failed sign-in spikes; longer log retention (Pro plan) | Claude builds, owner chooses tools | CC7.2, A1; ISO 8.16 |

### B. Within the first months (to pass Cyber Essentials and start ISO 27001)

| # | Gap | Action | Maps to |
|---|---|---|---|
| B1 | No written policies | Information security policy, acceptable use, access control, incident response, business continuity, supplier management, secure development, data retention | CC1–CC2, CC5; ISO 5.1, 5.24–5.30, 8.25 |
| B2 | No risk register or asset list | Risk register (likelihood × impact, owners, treatments) and asset/data inventory | CC3; ISO 6.1.2, 5.9 |
| B3 | No incident plan tested | Incident response plan incl. 72-hour ICO reporting and telling councils; a tabletop exercise | CC7.3–7.5; ISO 5.24–5.27 |
| B4 | Backups never restored | Restore drill each quarter; agree recovery targets (e.g. RPO 24 h, RTO 8 h) | A1.3; ISO 5.30, 8.13 |
| B5 | Access reviews | Quarterly review of platform admins, content roles and provider accounts; offboarding checklist | CC6.2–6.3; ISO 5.18 |
| B6 | Retention and deletion | Retention schedule agreed with councils (records are append-only by design, so deletion needs a defined, audited process) | C1.2, P4; ISO 5.33, 8.10 |
| B7 | Your own devices and accounts | MFA on GoDaddy, GitHub, Supabase, Vercel, Resend, Lovable; password manager; updated devices (also needed for Cyber Essentials) | CC6; ISO 8.1, 5.17 |
| B8 | Independent testing | Penetration test before the first council goes live, then yearly | CC4; ISO 8.8 |
| B9 | Cyber Essentials | Self-assessment, then Plus | — |

### C. Towards certification (6–12 months)

- ISO 27001: define the ISMS scope, Statement of Applicability, internal audit, management review, then a
  Stage 1 and Stage 2 audit by an accredited body.
- SOC 2: choose criteria (Security + Availability + Confidentiality recommended; Privacy later), readiness
  assessment, Type 1, then a 3–6 month Type 2 period.
- A compliance tool (for example Vanta, Drata or Secureframe) can collect evidence automatically from
  GitHub, Supabase and Vercel; worth considering when the audit starts (paid).
- Security awareness training records for anyone with access.

## 4. Things to decide

1. Order of certifications (recommended above).
2. Budget: Supabase Pro and Vercel Pro (~$45/month), penetration test, Cyber Essentials, later audits and an
   optional compliance tool.
3. Who besides the owner gets production access (keep it to as few people as possible, all with MFA).

## 5. What Claude can do next (each with owner approval)

- Build A3 (MFA), A4 (password rules), A5 (security headers) and A6 (GitHub checks).
- Draft the policies (B1), risk register (B2), incident plan (B3) and DPIA (A8) as editable documents.
- Set up the production project (A2) once Supabase Pro is in place.
