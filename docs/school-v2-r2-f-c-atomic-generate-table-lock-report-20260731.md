# School V2 R2-F-C Atomic Generate Table-Lock Report

Date: 2026-07-31
Status: database DDL and rollback-only acceptance complete; R0 remains blocked

## Scope and baseline

R2-F-C closes the R2-F-B candidate/carryover phantom window for the current low-volume V2 operation without modifying the 25 existing lesson/settlement writers. The only deployed object change is `school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)`.

Baseline and final historical fingerprints:

| Object | Rows | Full-row fingerprint |
|---|---:|---|
| `school_student_tuition_bills` | 9 | `0f0323b79e7ff1c47ff6b90c75477a2d` |
| `school_income_records` | 42 | `2a4897b752f272b1f192045418b4940c` |
| `school_student_tuition_bill_lessons` | 121 | `285172fedeb923c67ea9a179480d8692` |
| `school_student_tuition_billing_identities` | 7 | `4d91a5a1074f90389822fc367a7e5467` |
| `school_student_monthly_settlements` | 15 | `8d40d937d45c64eca0ec0ba7b1c5e65d` |

## Lock contract

The existing-identity idempotent branch is unchanged. Only the new-generation branch obtains locks, after identity absence is known and before the first canonical candidate or carryover-evidence read.

The owner-only core temporarily sets transaction-local `lock_timeout` to `8s`, takes these transaction table locks in fixed order, and restores the caller's previous timeout immediately after acquisition:

1. `LOCK TABLE public.school_lesson_records IN SHARE MODE`
2. `LOCK TABLE public.school_student_monthly_settlements IN SHARE MODE`
3. `LOCK TABLE public.school_student_settlement_carryovers IN SHARE MODE`
4. `LOCK TABLE public.school_student_settlement_adjustment_drafts IN SHARE MODE`

The locks remain held until the outer transaction commits or rolls back. PostgreSQL `SHARE` is compatible with ordinary `ACCESS SHARE` reads and conflicts with the `ROW EXCLUSIVE` lock acquired by INSERT/UPDATE/DELETE. Existing student/entity/month advisory locks, deterministic lesson row locks, uniqueness constraints, manifests and validators remain unchanged.

Lock timeout or deadlock in this block fails closed with SQLSTATE `55P03` and:

`R2_F_C_TUITION_SOURCE_BUSY: 课时或月结数据正在更新，请稍后重新预览并生成。`

No global timeout, retry queue, monitoring table or background task was added.

## Rehearsal and formal DDL

The same cutover bytes were first executed inside explicit `BEGIN`, followed by the complete R2-F-B eight-group matrix plus R2-F-C lock assertions, and explicit `ROLLBACK`. After rollback the deployed core MD5 returned to `a6f456a1303272e26aa841bf79a89bdf`; fixtures were absent and all five fingerprints matched.

The unchanged cutover bytes were then executed once under explicit `BEGIN` / `COMMIT`. Formal output was one `CREATE FUNCTION`, one owner-only privilege reassertion and a comment. It contained no executed business DML, schema/table/trigger/policy change or R0 change.

Final core definition MD5: `c6bd995a4703306d049ea30a9fb2ae17`.

## Single-session rollback acceptance

The R2-F-C rollback script includes the complete R2-F-B matrix and adds table-lock assertions. Results:

- R2-F-B manifest, carryover, validator, fee, month, failure atomicity, permission and idempotency groups: 8/8 passed.
- Four granted `ShareLock` rows were visible in `pg_locks` for the exact target relations.
- SELECT probes on all four locked tables completed normally.
- The caller's prior `lock_timeout=10s` was restored after lock acquisition.
- Normal generate produced bill + identity + normalized relation + pending income; exact-manifest retry returned idempotently.
- All fixtures were explicitly rolled back; `persisted_fixture_rows=0` and writer context residue was 0.

Final standalone rollback transient IDs were `b8fd21b1-2c37-45a7-8d41-22ab8834a8b8`, `fba4bfc2-8b5b-4951-94bb-2b78430591d0`, and `ece7c283-5ed4-4bbc-af80-f17c39013da0`, plus the fixed `f2fb...a001` through `f2fb...a005` whitelist students.

## Two-session acceptance

### Generate holds SHARE; writers wait

Session A created only uncommitted whitelist fixtures, performed a normal atomic generate, and retained all four `ShareLock` locks. The isolated normal four-object generate statement completed in `103.472 ms` and returned transient bill `0bfa891f-bc9b-4c1e-a1b8-3fa234ea64fd`, identity `bc765b94-3272-4465-9946-13857dfdb91d`, and income `4c254ebf-ca59-43ca-bb98-8e6dfd6bf442`.

While Session A remained open:

- Session B SELECTed all four tables immediately.
- Zero-row lesson INSERT and UPDATE each failed after the local `500ms` lock timeout.
- Zero-row settlement, carryover and adjustment-draft UPDATE each failed after the local `500ms` lock timeout.
- Every failure was PostgreSQL `canceling statement due to lock timeout`; no row was written.

After Session A rolled back, the same four zero-row writers completed immediately as `UPDATE 0` and rolled back.

### Writer holds ROW EXCLUSIVE; generate times out

Session A created uncommitted timeout fixture student `f2fc0000-0000-4000-8000-00000000a001` and planned lesson `d041bed3-8d76-4ada-ad54-3665b6fac2f7`. Session B executed settlement `UPDATE ... WHERE false`, held a granted `RowExclusiveLock`, and wrote no row.

Session A's atomic core waited `8097.936 ms`, then returned the exact `R2_F_C_TUITION_SOURCE_BUSY` message. Both sessions rolled back. Final residue was 0 for the fixture student, lesson, bill, identity, relation, income and writer context.

## ACL/RLS debt

All four target relations exist as ordinary tables. Current ACLs still grant broad table privileges to `anon`, `authenticated` and `service_role`; three have RLS enabled but not forced, while `school_student_settlement_adjustment_drafts` has RLS disabled. R2-F-C does not enlarge those privileges and adds no direct DML entry point. Because table-level `SHARE` conflicts with database DML regardless of entry path, this accepted V2 debt does not reopen the generate phantom window while the generate transaction is active. A future security phase may narrow ACL/RLS independently.

## SQL/RPC and database-write classification

- Persisted School DB write: function DDL only, through `school_tuition_r2_f_c_atomic_generate_table_lock_cutover.sql`.
- Rollback-only RPC calls included validation preview, planned/actual lesson fixture writers, owner-only atomic core, public blocked wrapper, cancellation compatibility and existing validators through the inherited R2-F-B matrix.
- Dual-session writer probes used zero-row INSERT/UPDATE and were rolled back or timed out.
- No real generate, business bill/income, fixture, Cash request or historical change was committed.
- Cash DB was not connected.

## Files

| File | SHA-256 |
|---|---|
| `sql/current/school_tuition_r2_f_c_atomic_generate_table_lock_cutover.sql` | `9b8bd07e7c5a815d77abd1d1f2b135bde4aa3d4ad33e729380e547d5687522bf` |
| `sql/current/school_tuition_r2_f_c_atomic_generate_table_lock_postdeploy.sql` | `4f4d7921f073c5c5dca75e8682125eeadcc8c0fda8988909c2b92ab57bc19870` |
| `sql/current/school_tuition_r2_f_c_atomic_generate_table_lock_rollback_tests.sql` | `666f1e34137b593e8da6ea6d720dbd8896630fee8350d5188f2098c92524aa91` |

## Stop state

R0 remains:

- `student_tuition_preview = validation_preview_only`
- `student_tuition_generate = blocked`
- `student_tuition_cash_submit = blocked`

No frontend file, existing business writer, cancellation/regeneration workflow, Cash integration or historical canonicalization was changed. No Git add, commit or push was performed. The phase stops at the R2-F-C coarse-grained concurrency database acceptance review point.
