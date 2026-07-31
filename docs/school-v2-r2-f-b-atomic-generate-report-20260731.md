# School V2 R2-F-B Atomic Tuition Generate Report

Date: 2026-07-31
Status: database implementation and acceptance complete; R0 remains blocked

## Baseline and fingerprint method

The repeatable fingerprint is `md5(string_agg(md5(to_jsonb(row)::text), '' order by primary_key::text))`. Earlier report hashes that differed used narrower projections; no unexplained business mutation was found.

| Object | Rows | Full-row fingerprint |
|---|---:|---|
| `school_student_tuition_bills` | 9 | `0f0323b79e7ff1c47ff6b90c75477a2d` |
| `school_income_records` | 42 | `2a4897b752f272b1f192045418b4940c` |
| `school_student_tuition_bill_lessons` | 121 | `285172fedeb923c67ea9a179480d8692` |
| `school_student_tuition_billing_identities` | 7 | `4d91a5a1074f90389822fc367a7e5467` |
| `school_student_monthly_settlements` | 15 | `8d40d937d45c64eca0ec0ba7b1c5e65d` |

The same counts and fingerprints matched before rehearsal, after rehearsal rollback, after formal COMMIT, after postdeploy and after rollback tests.

## Deployed objects and authority boundary

- Public RPC: `school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)`.
- Owner-only core: `school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)`; no `anon`, `authenticated` or `service_role` execute permission.
- Owner-only snapshot builder: `school_build_student_tuition_generation_snapshot(uuid,text,numeric)`.
- Validation preview details now returns `generation_manifest_sha256` while retaining the existing candidate summary/detail contract.
- Relation validator has an exact `student_tuition_atomic_generate_v1` branch and a business-semantics-preserving historical branch for the existing 121 relations.
- `school_tuition_atomic_writer_context` is a private, normally empty transaction capability. It prevents direct DML from imitating the authoritative writer.
- Bill `INSERT/UPDATE/DELETE/TRUNCATE` is revoked from client roles; SELECT remains available.
- Income RLS is split into operational SELECT and non-tuition INSERT/UPDATE/DELETE policies. Direct tuition income mutation is additionally rejected by the R0/writer-context trigger. Authenticated ordinary income insert/update/delete passed rollback testing.
- Generic pending-income cancellation rejects the new atomic source with `TUITION_ATOMIC_CANCEL_FORBIDDEN`. The legacy tuition branch remains behind the generate gate and ordinary non-tuition cancellation is unchanged.
- The two legacy generate overloads and standalone bill-to-income RPC remain R0 fail-closed stubs.

Deployed definition MD5 values:

| Function | MD5 |
|---|---|
| snapshot builder | `3ec44f91bce3493c15663d59226e1dd1` |
| atomic core | `a6f456a1303272e26aa841bf79a89bdf` |
| public wrapper | `36bdadc9af59637c9d336ce68d9afb4c` |
| validation preview details | `c203b2d21385bf3425a6ae74ef9515e3` |
| relation validator | `3f8141bfe8541c984e157a337f61813b` |
| cancellation RPC | `816cdadf85b9604aca56c8767326f22a` |

## Generation manifest and transaction flow

The pre-hardening candidate JSON already retained full row evidence, but `candidate_manifest_sha256` covered only aggregate fields and an ordered UUID hash. It did not cryptographically commit to `complete_row_hash`, `candidate_line_hash`, teacher, subject, venue and all other frozen line facts. A stale preview could therefore remain hash-equivalent after a non-amount candidate change. This was a real manifest-coverage defect even though the canonical candidate reread and normalized snapshots were otherwise correct.

The hardened builder first constructs one canonical JSON line and SHA-256 for each candidate. Every line includes planned lesson UUID, student, business entity, billing month, billing week start, lesson date, teacher, subject, lesson count, duration, unit price, base fee, aircon rate, billable hours, aircon fee, course total, fee policy/version, venue id/code, source lesson `updated_at`, `complete_row_hash`, plus the resulting `candidate_line_hash`. `candidate_manifest_sha256` is then the SHA-256 of the newline-delimited line hashes ordered by billing week, lesson date and planned UUID. The generation manifest continues to cover that candidate manifest, ordered candidate UUID evidence, counts, duration, totals, exchange rate, carryover evidence and final CNY notification amount.

Bill JSON, identity evidence, income JSON and every normalized relation source snapshot now carry the same candidate/generation manifest pair. The atomic relation validator recomputes every line hash after removing `candidate_line_hash`, compares `complete_row_hash` and `candidate_line_hash` between bill JSON and relation JSON, verifies the relation JSON line is otherwise byte-equivalent, recomputes the ordered candidate manifest, and requires identity/bill/relation manifests to agree.

Exchange rate validation now occurs before the existing-identity branch. Existing identity return requires a non-null positive rate exactly equal to the frozen bill and JSON rate, request/student/entity/month identity consistency, equal bill/income/identity manifests, frozen JPY/CNY/carryover evidence consistency and all three validators. Any mismatch is normalized to `R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE`; null, zero and negative rates remain `R2_F_B_EXCHANGE_RATE_INVALID`. Identical parameters return the original bill, identity and income IDs.

Carryover evidence now has its own SHA-256 copied into bill JSON, income JSON and identity evidence. Existing-identity return recomputes that SHA, validates the locked-settlement or proven-zero evidence fields against frozen bill columns, checks income settlement month/id/carryover, and rejects malformed evidence through the same idempotency-conflict error. A rollback test mutates only the frozen zero-evidence payload and proves the old idempotent return is rejected.

For a new identity the core acquires transaction advisory locks for the previous/current operation months, reads candidate UUIDs, locks source lesson rows in deterministic UUID order, locks the student and settlement rows, rereads the canonical candidate reader and rebuilds the manifest. It then creates a draft bill only as an uncommitted FK bridge, followed by identity, normalized relations, pending income and the final `income_created` bill update. All consistency validators run before return. Any exception rolls the whole transaction back.

Each normalized relation and ordered bill JSON line freeze planned UUID, student/entity/month/week/date, lesson count, duration, unit price, base fee, aircon rate, aircon billable hours, aircon fee, course total, fee policy/version, source hashes and generation manifest. `lesson_fee` on the source lesson remains base-only; relation `lesson_fee_jpy_snapshot` remains the frozen bill-line course total and is checked against base plus aircon.

## Carryover and overage

- A previous locked settlement freezes its id, timestamps, status and rounded carryover into the manifest.
- With no locked settlement, zero is allowed only after proving there is no settlement row, active bill, settlement income, carryover, adjustment draft, planned settlement fee, received settlement amount or authoritative overage contribution.
- Any pending previous-month contribution raises `R2_F_B_PREVIOUS_SETTLEMENT_REQUIRED`.
- Generate never recomputes actual overage. Only the existing settlement consumer can freeze it into carryover.
- The fixed historical 19 legacy duration differences remain excluded and were not modified or backfilled.

## Rehearsal and formal deployment

The successful same-byte rehearsal executed explicit `BEGIN`, the complete cutover file, rollback-only fixtures and actual owner-core calls, all eight acceptance groups, then explicit `ROLLBACK`.

Successful rehearsal transient IDs included bill `ed5f71fb-c519-4b3b-a3e3-3e2062ec1e2e`, identity `bc372735-9341-434b-921d-a3a7db0e2df6`, and income `6d860be9-543f-4aad-91f3-0614d2e2b8ac`. After rollback the new objects were absent, the old preview definition MD5 returned to `b2b111670954f06a40f16d20163ab3d7`, all fixtures were absent and the five business fingerprints matched.

The pre-hardening deployment bytes (`SHA-256 6629a6d40e7473206fd41fad3bb5b27da9a2b33a913581e485aab201dd441701`) were executed once under explicit `BEGIN` and `COMMIT`. They persisted only DDL, functions, constraint, trigger guard, ACL/RLS and comments; no business row or fixture was committed. The original source file is now corrected for clean future deployment and therefore has a new hash listed below; it was not replayed as a full cutover.

The commit-review hardening was deployed through the independent history file `school_tuition_r2_f_b_atomic_generate_manifest_idempotency_hardening.sql`. It sets the source cutover's `r2_f_b_hardening_only` mode, so the same corrected source bytes execute only `CREATE OR REPLACE` for the snapshot builder, relation validator and atomic core. It does not replay the already-committed schema, policy, trigger or constraint section.

The first hardening rehearsal exposed a fixture issue: all fixture rows had been created in one transaction and the ordinary `updated_at` trigger uses transaction `now()`, so assigning `updated_at + 1 second` was overwritten back to the same timestamp. The transaction aborted and automatically restored all three old function MD5 values; writer context was 0. The test was corrected to change same-month `lesson_date`, another frozen field that leaves amounts unchanged.

The successful hardening rehearsal then executed explicit `BEGIN`, the independent hardening file, the complete 8-group rollback matrix and explicit `ROLLBACK`. The function MD5 values returned to the old definitions after rollback and the five business fingerprints remained unchanged. Without changing either the corrected cutover or independent hardening file, the same driver bytes were executed under explicit `BEGIN` and `COMMIT`. Formal output was `CREATE FUNCTION` for exactly three functions, followed by `R2_F_B_HARDENING_FORMAL_COMMIT_COMPLETE`; no business DML was included.

A final idempotency audit then found that carryover JSON was only type-checked. The first manifest hardening definitions remained valid and deployed, but the same target core was tightened to persist/recompute carryover-evidence SHA and validate the income settlement evidence. Two syntax-only rehearsal attempts failed while compiling the new core and automatically rolled back before tests or COMMIT. After rewriting the equivalent boolean expression, the final source bytes passed the complete rehearsal and explicit rollback, then the same bytes formally replaced the same three functions under a second explicit `BEGIN` / `COMMIT`. This second bounded deployment was necessary to complete the reviewed idempotency contract; it did not replay the original cutover and did not write business rows.

## Acceptance results

Postdeploy passed owner, SECURITY DEFINER, search path, ACL, internal-core isolation, writer-context emptiness, old fail-closed entry points, R0, Cash gate, historical validator and full-row fingerprint assertions.

Rollback tests passed 8/8:

- atomic four-object consistency and JSON/relation validation;
- rate-sensitive generation manifest; teacher-only, subject-only, amount-neutral venue-only and amount-neutral lesson-date stale rejection; public R0 blocking; identical-parameter idempotency; same-manifest different-rate conflict; null/zero/negative-rate rejection;
- base/aircon/course-total formula and exclusion of actual/partial/makeup/cancelled rows;
- zero carryover, locked carryover and unlocked-overage rejection;
- injected post-relation failure with zero four-object residue;
- atomic cancellation rejection and ordinary income compatibility;
- advisory locks plus identity, planned UUID and income uniqueness backstops;
- 2026 cross-month natural-week boundaries and historical 19-overage exclusion.

The final hardening rollback run used whitelist student IDs `f2fb0000-0000-4000-8000-00000000a001` through `...a005` and transient generated IDs `816447d0-fded-45fb-91f8-8c91c5e3665a`, `c30193ef-c922-4bf1-9a08-bda6f3de611f`, and `e4e05d99-3618-4752-ab96-9e54566b3eb4`. It explicitly rolled back and reported `persisted_fixture_rows = 0`.

A two-session test with one side COMMIT was intentionally not performed because it would require committing test business rows. Instead the rollback transaction verified advisory locks were held and the three database uniqueness backstops independently rejected duplicate identity, planned UUID and income. This is the documented zero-persistence limitation.

## Read-only concurrency writer audit

The deployed atomic core locks `hashtextextended('student_tuition_operation_v1|student_id|business_entity_id|billing_month', 0)` for the previous and current months. The read-only audit found no other business writer using that exact key. Two legacy cores do use advisory locks, but only for their own batch/import idempotency IDs; those locks do not serialize with tuition generation. No R2-F-B change was made to these writers in this hardening round.

| Function signature | Fact changed | Same operation key | Phantom after generate reread | Recommended future hardening |
|---|---|---:|---:|---|
| `school_backfill_actual_minutes_from_duration(text)` | actual minutes / possible overage evidence | no | yes | Historical-only guard; if retained, lock each affected student/entity/settlement month before update. |
| `school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)` | actual row, planned fulfillment, authoritative overage | no | yes | Lock source planned billing month and affected overage settlement month(s), deterministic order. |
| `school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)` | cancellation row and planned candidate qualification | no | yes | Lock the source planned student/entity/billing month before qualification changes. |
| `school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)` | makeup row and fulfillment evidence | no | yes | Lock the source planned billing identity month and any affected settlement month. |
| `school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)` | partial row and planned candidate qualification | no | yes | Lock the source planned student/entity/billing month. |
| `school_create_planned_lesson_record_r1d_f1_legacy_core(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)` | new planned candidate and attribution | no | yes | Acquire the exact operation key for the derived billing month before insert. |
| `school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer)` | new planned candidate, venue, fee facts | no | yes | Same exact operation key for the derived billing month. |
| `school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text)` | legacy overload for new planned candidate | no | yes | Delegate only after the exact operation key is held. |
| `school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,integer)` | new planned candidate | no | yes | Acquire the exact operation key for the derived billing month. |
| `school_delete_fresh_planned_lesson(uuid,timestamptz,boolean)` | physical removal of candidate | no | yes | Resolve old identity and lock its exact operation key before delete eligibility/reread. |
| `school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text)` | batch planned candidates | no; batch-id lock only | yes | Derive all affected months, acquire exact operation keys in sorted order, retain batch-id lock for idempotency. |
| `school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text)` | batch wrapper with venue | no | yes | Wrapper/core contract must ensure sorted operation locks are held before writes. |
| `school_generate_planned_lessons_batch(uuid,uuid,uuid,date,date,jsonb,jsonb,text)` | batch wrapper | no | yes | Same as batch-with-venue wrapper. |
| `school_import_lesson_records_batch_r1d_f1_legacy_core(uuid,text,text,jsonb,text)` | historical planned import candidates | no; import-batch lock only | yes | If retained, derive all affected months and acquire exact operation keys in sorted order. |
| `school_import_lesson_records_batch_with_venue(uuid,text,text,jsonb,text)` | historical import wrapper | no | yes | Require core to hold exact operation locks; preserve historical-only scope. |
| `school_import_lesson_records_batch(uuid,text,text,jsonb,text)` | historical import wrapper | no | yes | Same as import-with-venue wrapper. |
| `school_lock_student_monthly_settlement(uuid,text,text)` | settlement lock and adjustment snapshot | no | yes | Acquire exact operation key for the settlement month before evidence calculation/write. |
| `school_relock_student_monthly_settlement(uuid,text)` | replacement settlement lock and adjustment snapshot | no | yes | Same settlement-month operation key; lock all old/new evidence deterministically. |
| `school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)` | adjustment draft / future carryover evidence | no | yes | Acquire exact operation key for that student/entity/month before draft mutation. |
| `school_unlock_student_monthly_settlement(uuid,text)` | removes locked carryover authority | no | yes | Acquire exact operation key for the settlement month before unlock. |
| `school_update_lesson_record_guarded_with_venue(uuid,timestamptz,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text,integer)` | candidate facts, attribution, venue and fees | no | yes | Lock both old and new derived operation keys in sorted order before update. |
| `school_update_lesson_record_guarded_with_venue(uuid,timestamptz,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)` | legacy venue overload | no | yes | Delegate only after old/new operation keys are held. |
| `school_update_lesson_record_guarded(uuid,timestamptz,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,integer)` | candidate facts and attribution | no | yes | Lock both old and new derived operation keys in sorted order. |
| `school_update_lesson_record_guarded(uuid,timestamptz,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)` | legacy guarded overload | no | yes | Delegate only after old/new operation keys are held. |
| `school_void_planned_lesson(uuid,timestamptz,text)` | void/exclusion of candidate | no | yes | Resolve and lock the old exact operation key before void eligibility/reread. |

Six `school_lesson_records` BEFORE triggers also derive or mutate candidate/overage facts without the operation key: `school_sync_lesson_actual_minutes()`, `school_lesson_inherit_schedule_venue()`, `school_enforce_r1d_e_b2_actual_attribution()`, `school_enforce_r1d_f1_planned_attribution()`, `school_enforce_r2_e_planned_aircon()`, and `school_set_updated_at()`. Trigger-level protection or a shared lock helper is required so direct or future writers cannot bypass wrapper locks.

No deployed function containing DML against `school_student_settlement_carryovers` was found. However, current table ACLs permit `anon`, `authenticated` and `service_role` to insert/update/delete both `school_lesson_records` and `school_student_settlement_carryovers`. Therefore direct table DML remains a phantom path even if all named RPCs are later hardened. A separate authorized phase should combine RPC-only write ACL/RLS with a trigger/shared-helper exact-key guard; this round intentionally did not broaden permissions or change other writers.

## Files

| File | SHA-256 |
|---|---|
| `sql/current/school_tuition_r2_f_b_atomic_generate_cutover.sql` | `8281fdf2fe9690812113895221b14370515aac80da34475a5834c4956f485377` |
| `sql/current/school_tuition_r2_f_b_atomic_generate_manifest_idempotency_hardening.sql` | `c4cf08ea35600fa78f6a67de465c41705d852e54c9cc2cb53e422c50b8519473` |
| `sql/current/school_tuition_r2_f_b_atomic_generate_postdeploy.sql` | `82fb3babdbf91aba57221d47046bc9d0a91a9a1aab68c0cd24713a0c176d35c1` |
| `sql/current/school_tuition_r2_f_b_atomic_generate_rollback_tests.sql` | `d348a72e497cb753913aab08da662db2e458a9e74c7d716cd6ef415c6192ef82` |

## Stop state

R0 remains `student_tuition_preview = validation_preview_only`, `student_tuition_generate = blocked`, and `student_tuition_cash_submit = blocked`.

No frontend file was modified. No Cash connection or request occurred. No real generate call was made, and no historical canonicalization or Git delivery was performed. The writer-lock audit is design-only and no non-target writer or permission was changed. The phase stops at the R2-F-B atomic generate database acceptance review point pending review.
