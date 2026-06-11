# Teacher Wage Generation Rule Investigation

Date: 2026-06-11

Scope: read-only investigation for wage-generation prerequisites and a codex-test wage-rule mismatch. This document does not change wage formulas, student settlement rules, payment rules, or account rules.

## Student Settlement Dependency

Current DB/RPC facts:

- `school_student_monthly_settlements` has `student_id`, `year_month`, `business_entity_id`, `settlement_status`, `locked_at`, and `unlocked_at`.
- Student settlement status currently uses `locked` and `unlocked`.
- Lesson create/edit flows already guard against locked student settlement months.
- `school_generate_teacher_monthly_wage` does not read `school_student_monthly_settlements`.
- Teacher wage generation currently reads actual lessons by `teacher_settlement_month` / `year_month`, requires actual `completed` / `makeup_completed`, ignores `is_billable`, and matches one active wage rule by exact teacher + student + subject + business entity.

Observed 2026-06 facts:

- Current 2026-06 candidate actuals include students with no locked student settlement row.
- The codex-test student `92981b7a-7fec-4982-9684-21b1f5a96eeb` has a 2026-06 settlement row in `unlocked` state.

Business risk if teacher wages are generated before student settlement:

- Wage snapshot generation locks teacher wage side for the source actual lessons. Later corrections to actual lesson time/content/business/student/subject may be blocked by wage snapshot guards until the wage snapshot is voided.
- Student settlement amounts and teacher wage amounts are separate business outputs: teacher wage ignores student `is_billable`, while student settlement follows tuition/receipt logic.
- Requiring all student settlements to be locked before teacher wage generation could block legitimate teacher pay for students/months that intentionally have no student settlement row or where student settlement timing differs from payroll timing.

Recommendation:

- Do not add a hard DB/RPC prerequisite in this pass.
- Add a future UI/read-only warning before wage generation: show candidate students whose same `student_id + year_month` settlement is missing or not `locked`.
- If the business later wants a hard rule, design it separately by student + month, with an explicit policy for no-settlement students, non-billable actuals, cross-month makeup, and business-entity mismatch.
- This should not change the existing teacher wage formula, snapshot granularity, payment request flow, or account/payment chain.

## codex-test v2.45.0 Browser Teacher Wage Rule Error

User-facing error:

```text
存在没有启用工资规则的 actual 课时，不能生成工资。
```

Current actual candidate:

- Teacher: `21d53107-abd8-442d-a63c-e099ec0f42ba` / `codex-test v2.45.0 browser 老师 20260606`
- Student: `92981b7a-7fec-4982-9684-21b1f5a96eeb` / `codex-test v2.45.0 browser 学生`
- Subject: `3c36adcf-ecf6-49e7-8645-7cb912d4ddfe` / `codex-test v2.44.0 browser 科目 20260606`
- Actual lesson: `159d64ee-6b7a-460c-b26d-6042211ccf69`, `2026-06-11`, `completed`, duration `2`, `actual_minutes = 120`, `is_billable = true`, content `测试课时`
- Actual business entity: `2fa5bd72-7ba5-48f3-91dd-b56f978c56e6` / `codex-test v2.47.0 browser 测试业务归属`

Current wage rule:

- Rule: `91fb2803-6071-4a84-9b7a-ea43b1ba6a5a`
- Same teacher, student, and subject as the actual lesson.
- `is_active = true`
- `settlement_type = jpy_hourly`
- `hourly_rate_jpy = 1600`
- Rule business entity: `648fc486-bb10-47fa-9734-6ca41dd04a47`

Root cause:

- `school_generate_teacher_monthly_wage` matches active wage rules by exact `teacher_id + student_id + subject_id + business_entity_id`.
- The actual lesson business entity is `2fa5bd72-...`; the active wage rule business entity is `648fc486-...`.
- Matching active rule count for the actual candidate is `0`, so the current RPC correctly raises the missing active wage rule error under the existing口径.
- `school_teacher_wage_rules` has no course classification or effective-date columns in the current schema; this is not an effective-date or classification mismatch.

Recommendation:

- Treat this as codex-test master/config data mismatch, not a wage-generation RPC bug.
- Do not auto-create or auto-edit wage rules in this pass.
- Future UX improvement: when wage generation fails due missing wage rules, show the unmatched candidate lesson groups and their teacher/student/subject/business entity names so the user can fix the wage rule deliberately.
