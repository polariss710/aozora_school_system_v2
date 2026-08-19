# School V2 × Cash Phase 3C3-B fixed attempt/request entry

Status date: 2026-08-19
Result: School DB, home DB and two Edge functions deployed; both fixed gates remain closed and all production fixed counts remain zero.

## Baseline

- School baseline: `main` `c0dc65e1194e7059e24026b1943ad1605635768f`, equal to origin; page `v10.5.54`.
- Cash baseline: `main` `3880722c6b3da48a3012a17622429b9ded58e9d8`, equal to origin; page `20260819-accounting-scope-filter-2`.
- Before deployment: 53 School expenses, 24 immediate attempts, 50 home requests, 0 fixed attempts/requests/projections/cycles/School fixed items. School fixed Gate blocked; card route false.
- Pre-existing School untracked files and home ignored SQL were not moved, overwritten or cleaned.

## School database contract

- The existing 36-column attempt table is sufficient. `cash_funding_account_id` is route-conditional: required for immediate, forbidden for fixed.
- Fixed SHA-256 evidence covers expense/attempt, route, event/idempotency, card, charge date, suggested/target month, funding date, original and settlement amount/currency, and canonical external reference. Funding account is absent.
- Allowed status vocabulary is prepared, submitted, approved_immediate, approved_fixed, funded_fixed, rejected and corrected. In this phase fixed rows can only move prepared→submitted→rejected; direct approved_fixed/funded_fixed/corrected mutations are trigger-blocked.
- The independent fixed prepare writer locks the expense, derives amount/currency from School DB, generates identity/fingerprint and atomically updates the latest-state mirror. Exact prepared or submitted retries reuse the same attempt; rejected retries create the next attempt number.
- Submitted/rejected wrappers require the complete home request evidence, null accounts and no transaction/projection. The core is postgres-only; wrappers are service-only with fixed search paths.

## Home and Edge saga

- Edge first calls the service-only home schedule wrapper. JS does not calculate month, funding date, amount or fingerprint.
- After a successful School prepare, Edge calls the independent home fixed writer; on success it rereads the full request and writes submitted evidence back to School.
- A home-writer failure leaves a recoverable prepared attempt. A submitted writeback failure retries the same School identity and same home request.
- Sync routes fixed rejection to the dedicated wrapper. Fixed approval returns `HOME_FIXED_REQUEST_APPROVAL_REQUIRES_FIXED_WRITER` and never calls the immediate approved wrapper.
- Deployed Edge: request v6, SHA `1f3b0464c062afe9d74671d9bcf9540a0e2f54a3ac93668fb3ff162a8e2df68c`, JWT true; sync v10, SHA `2895b2f42bc976f1130848f299a42cca47e396db0d40b366002636922c6871b6`, JWT false. Both OPTIONS returned 204.

## Tests and postcheck

- School core SHA-256: `b8dde7c751c6d8ee475f15eec6d5e2931b93876791d03005998f723d147fc007`.
- Exact-body production ROLLBACK first ran the full Phase 3C2-R immediate matrix, then fixed Gate, prepare/replay/conflict, submitted/rejected/retry, forbidden future states, ACL and forced second-half failure tests.
- Local isolated PostgreSQL two-session tests passed immediate serialization, approved/rejected race, fixed prepare race, fixed submitted/rejected overlap and home fixed request-create race.
- Formal postcheck: 53 expenses, 24 attempts, 0 fixed attempts, 50 home requests, 0 fixed requests/projections/cycles/School items, 0 2099 residue. Fingerprints remained School expense `ab992261cb75923472a8e52f546cbe9c`, School attempt `54e997329f80bb423adb655f0e37fc7a`, home request `7885061cf09eee37b62e39670286cc4e`, home account `af7a367cfc163b1a5f4a053887ceb8ce`.
- The 202,991 JPY expense/request/transaction chain remains paid/approved on transaction `01e910b8-bf54-486c-a13a-597ca9dbf684`; no correction was performed.

## Stop boundary

No UI entry exists. School fixed Gate remains blocked and `西武卡.is_school_fixed_route_enabled=false`. Phase 3D approval, projection/item creation, statement cycle, funding/allocation, correction and the 202,991 JPY business correction are not part of this deployment.
