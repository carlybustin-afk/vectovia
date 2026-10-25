# Vectovia integration interface (V6)

Status: documented interface only. **No connector to Idox or any other system is built.** Nothing is sent to another system
until a connection is separately scoped, approved by the owner, and configured per council.

This describes what Vectovia can exchange with an authorised external system, how records are identified, and the
safeguards any future connector must keep (brief: "Integration"; plan V6; rev 27).

## 1. What can be exchanged

| Data | Source (database contract) | Direction | Notes |
|---|---|---|---|
| Site and property references | `vv_sites` (reference, name, address, UPRN, lat/long) | out | Grid reference is worked out from lat/long. |
| Deployment and visit summaries | `vv_deployments`, `vv_visits` | out | Occurred time and server receipt time are separate. |
| Selected findings | `vv_results` + current `vv_result_versions` | out | Only provisional/confirmed/inconclusive results the user chose; earlier versions on request. |
| Assessments | `vv_assessments` + current `vv_assessment_versions` | out | Officer-decided; never recalculated. |
| Follow-up actions | `vv_actions` | out | Owner, due date, status, completion. |
| Reports | Files listed in `vv_exports` (PDF, Word, CSV) | out | Each with SHA-256 fingerprint and scope. |
| External case references | `vv_external_refs` | in / out | The ID mapping below. |

The CSV exports on **Vectovia → Reports and exports** already provide every dataset above with record IDs, so a council
can move data manually today.

## 2. Identifiers and mapping

- Every Vectovia record has a stable UUID (generated on the device) plus a human reference where one exists
  (`VS-0001` sites, `VS-S00001` samples, `VS-I0001` incursions).
- `vv_external_refs` maps a Vectovia record (site, incursion or sample) to another system's identifier:
  `system` (e.g. "Idox"), `external_id`, who recorded it and when. One active mapping per system, record type and
  external ID in a council; removals keep the record and a reason.
- A connector must match on these mappings, never on names or addresses alone.

## 3. Rules any connector must follow

1. **Council isolation (B1).** A connection is configured per council and can only read or write that council's records.
   No query, export or sync may combine councils.
2. **Permissions.** A connector acts for a named, authorised person or service account with an explicit Vectovia access
   level; it never widens what that account can see. Case links stay governed by `can_read_case` on the Investigations side.
3. **No AI (B2).** Surveillance and case data are never sent to an AI provider or used for AI learning.
4. **Audit.** Every exchange is logged like an export (`vv_exports`: who, when, scope, counts, fingerprint), and every
   change to a mapping is recorded in `vv_events`.
5. **No silent overwrite.** Incoming changes become new versions or amendments with a reason; originals are kept.
   Conflicts are shown to a person, never resolved automatically.
6. **Idempotent and retry-safe.** Writes use client-generated IDs, as the existing database functions do.
7. **Owner approval.** Building a connector, sending data to a new destination, or any paid integration service needs the
   owner's explicit approval first.

## 4. Links to Investigations cases

`vv_case_links` links a site or incursion to a case in the **same** council. A link is made only by a Vectovia manager who
can already open the case, stores only the two IDs, and shows only to people who can see both records
(`vv_case_links_for`, `case_surveillance_links`). Removing a link keeps it with a reason.
