-- school_cleanup_codex_test_data_round2_20260612.sql
-- Purpose: second one-time cleanup for Codex / v2-test / sandbox test data and data clearly associated with it.
--
-- Run modes:
--   Dry run only:
--     psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -v cleanup_execute=0 -v cleanup_commit=0 -f school_cleanup_codex_test_data_round2_20260612.sql
--   Rollback validation:
--     psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -v cleanup_execute=1 -v cleanup_commit=0 -f school_cleanup_codex_test_data_round2_20260612.sql
--   Commit cleanup:
--     psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -v cleanup_execute=1 -v cleanup_commit=1 -f school_cleanup_codex_test_data_round2_20260612.sql
--
-- Safety:
-- - No truncate/drop.
-- - Candidates are explicit known test IDs, rows with Codex/v2-test/sandbox markers,
--   or records directly related to those test rows.
-- - Ambiguous Chinese-only test-looking rows are reported in manual review and not
--   deleted unless they are also connected to a confirmed candidate.

\set ON_ERROR_STOP on
\if :{?cleanup_execute}
\else
\set cleanup_execute 0
\endif
\if :{?cleanup_commit}
\else
\set cleanup_commit 0
\endif

begin;

create temp table cleanup_ids (
  table_name text not null,
  id uuid not null,
  reason text not null,
  sample text,
  primary key (table_name, id)
) on commit drop;

create temp table cleanup_manual_review (
  table_name text not null,
  id uuid not null,
  reason text not null,
  sample text,
  primary key (table_name, id)
) on commit drop;

create temp table cleanup_storage_objects (
  id uuid not null primary key,
  bucket_id text,
  name text,
  reason text not null,
  sample text
) on commit drop;

-- Explicit IDs supplied by the cleanup request.
insert into cleanup_ids(table_name, id, reason, sample)
values
  ('school_accounts', '3c50704b-4c59-4253-a094-9eac0fea6c73'::uuid, 'explicit recent test account id from request', null),
  ('school_business_entities', '8cbb40db-b6e5-48e1-9fe4-caf536f5efc1'::uuid, 'explicit recent test business entity id from request', null),
  ('school_business_entities', '2efabba9-59e9-49f6-915d-578440123c8d'::uuid, 'explicit recent test business entity id from request', null),
  ('school_accounts', '85ccb922-1a31-4086-a24d-a6c119f7c00c'::uuid, 'explicit test account id from request', null),
  ('school_teachers', '685de03f-267d-4910-acfb-f318dad27784'::uuid, 'explicit test teacher id from request', null),
  ('school_teachers', '2ccde8ba-d868-49bd-ac20-5d5d374f85f1'::uuid, 'explicit test teacher id from request', null),
  ('school_students', 'a4bf5dcb-a792-4776-aaf9-bd769fdb7b25'::uuid, 'explicit test student id from request', null),
  ('school_students', '91f81459-b2ea-411f-b81e-4d1e2006b256'::uuid, 'explicit test student id from request', null),
  ('school_students', '7ea8f407-f84a-4aa7-860c-1b02781f8a55'::uuid, 'explicit test student id from request', null),
  ('school_subjects', '8b5ee3b9-8cc2-4e73-9229-67ba8c2f7698'::uuid, 'explicit test subject id from request', null),
  ('school_teacher_wage_rules', 'cdfc9cf7-d174-48cd-af9e-26972d6aaa10'::uuid, 'explicit test wage rule id from request', null)
on conflict do nothing;

delete from cleanup_ids c
where c.reason like 'explicit%test % id from request'
  and not (
    (c.table_name='school_accounts' and exists (select 1 from public.school_accounts t where t.id=c.id)) or
    (c.table_name='school_business_entities' and exists (select 1 from public.school_business_entities t where t.id=c.id)) or
    (c.table_name='school_teachers' and exists (select 1 from public.school_teachers t where t.id=c.id)) or
    (c.table_name='school_students' and exists (select 1 from public.school_students t where t.id=c.id)) or
    (c.table_name='school_subjects' and exists (select 1 from public.school_subjects t where t.id=c.id)) or
    (c.table_name='school_teacher_wage_rules' and exists (select 1 from public.school_teacher_wage_rules t where t.id=c.id))
  );

-- Confirmed marker patterns. Chinese-only "测试..." rows are manual-review unless
-- they are also connected to confirmed candidates by FK/source relationships.
-- The marker expression is repeated inline to keep the script portable.

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_accounts', id, 'account text marker', concat_ws(' | ', account_code, name, note)
from public.school_accounts
where concat_ws(' ', account_code, name, account_type, note, app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_business_entities', id, 'business-entity text marker', concat_ws(' | ', code, name, note)
from public.school_business_entities
where concat_ws(' ', code, name, entity_type, note) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_accounts', a.id, 'test account under confirmed test business entity', concat_ws(' | ', a.account_code, a.name, a.note)
from public.school_accounts a
where a.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
  and concat_ws(' ', a.account_code, a.name, a.note) ~ '(测试|沙盒)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_teachers', id, 'teacher text marker', concat_ws(' | ', teacher_code, name, display_name, email, phone, wechat, note)
from public.school_teachers
where concat_ws(' ', teacher_code, name, kana_name, display_name, email, phone, wechat, bank_name, bank_branch_name, bank_account_name, alipay_account, wechat_account, note, app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_teachers', t.id, 'test teacher under confirmed test business entity', concat_ws(' | ', t.teacher_code, t.name, t.display_name, t.note)
from public.school_teachers t
where t.default_business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
  and concat_ws(' ', t.teacher_code, t.name, t.display_name, t.note) ~ '(测试|沙盒)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_students', id, 'student text marker', concat_ws(' | ', student_code, name, display_name, email, phone, wechat, parent_name, parent_phone, parent_wechat, note)
from public.school_students
where concat_ws(' ', student_code, name, kana_name, display_name, email, phone, wechat, parent_name, parent_phone, parent_wechat, target_schools, note, app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_subjects', id, 'subject text marker', concat_ws(' | ', name, primary_category, category, tertiary_category, note)
from public.school_subjects
where concat_ws(' ', name, category, primary_category, tertiary_category, note) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_teacher_wage_rules', id, 'wage-rule text marker', note
from public.school_teacher_wage_rules
where concat_ws(' ', settlement_type, note) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

-- Manual-review rows: test-looking Chinese-only labels without Codex/v2-test/sandbox markers.
insert into cleanup_manual_review(table_name, id, reason, sample)
select 'school_business_entities', id, 'Chinese-only test-looking business entity; not auto-deleted unless linked to confirmed candidates', concat_ws(' | ', code, name, note)
from public.school_business_entities
where concat_ws(' ', code, name, note) ~ '(测试|沙盒)'
  and not exists (select 1 from cleanup_ids c where c.table_name='school_business_entities' and c.id=school_business_entities.id)
on conflict do nothing;

insert into cleanup_manual_review(table_name, id, reason, sample)
select 'school_accounts', id, 'Chinese-only test-looking account; not auto-deleted unless linked to confirmed candidates', concat_ws(' | ', account_code, name, note)
from public.school_accounts
where concat_ws(' ', account_code, name, note) ~ '(测试|沙盒)'
  and not exists (select 1 from cleanup_ids c where c.table_name='school_accounts' and c.id=school_accounts.id)
on conflict do nothing;

insert into cleanup_manual_review(table_name, id, reason, sample)
select 'school_teachers', id, 'Chinese-only test-looking teacher; not auto-deleted unless linked to confirmed candidates', concat_ws(' | ', teacher_code, name, display_name, note)
from public.school_teachers
where concat_ws(' ', teacher_code, name, display_name, note) ~ '(测试|沙盒)'
  and not exists (select 1 from cleanup_ids c where c.table_name='school_teachers' and c.id=school_teachers.id)
on conflict do nothing;

insert into cleanup_manual_review(table_name, id, reason, sample)
select 'school_students', id, 'Chinese-only test-looking student; not auto-deleted unless linked to confirmed candidates', concat_ws(' | ', student_code, name, display_name, note)
from public.school_students
where concat_ws(' ', student_code, name, display_name, note) ~ '(测试|沙盒)'
  and not exists (select 1 from cleanup_ids c where c.table_name='school_students' and c.id=school_students.id)
on conflict do nothing;

insert into cleanup_manual_review(table_name, id, reason, sample)
select 'school_subjects', id, 'Chinese-only test-looking subject; not auto-deleted unless linked to confirmed candidates', concat_ws(' | ', name, primary_category, category, tertiary_category, note)
from public.school_subjects
where concat_ws(' ', name, primary_category, category, tertiary_category, note) ~ '(测试|沙盒)'
  and not exists (select 1 from cleanup_ids c where c.table_name='school_subjects' and c.id=school_subjects.id)
on conflict do nothing;

-- Related master/config rows.
insert into cleanup_ids(table_name, id, reason, sample)
select 'school_teacher_wage_rules', r.id, 'wage rule references confirmed test master data', concat_ws(' | ', r.id::text, r.note)
from public.school_teacher_wage_rules r
where r.teacher_id in (select id from cleanup_ids where table_name='school_teachers')
   or r.student_id in (select id from cleanup_ids where table_name='school_students')
   or r.subject_id in (select id from cleanup_ids where table_name='school_subjects')
   or r.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
on conflict do nothing;

-- Lesson/import/schedule related data.
insert into cleanup_ids(table_name, id, reason, sample)
select 'school_lesson_records', l.id, 'lesson references confirmed test master data or marker text', concat_ws(' | ', l.lesson_date::text, l.year_month, l.lesson_content, l.note)
from public.school_lesson_records l
where l.student_id in (select id from cleanup_ids where table_name='school_students')
   or l.teacher_id in (select id from cleanup_ids where table_name='school_teachers')
   or l.subject_id in (select id from cleanup_ids where table_name='school_subjects')
   or l.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or l.planned_lesson_id in (select id from cleanup_ids where table_name='school_lesson_records')
   or concat_ws(' ', l.lesson_content, l.note, l.import_batch_id, l.import_source, l.void_reason, l.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_lesson_records', l.id, 'lesson linked to confirmed test planned lesson', concat_ws(' | ', l.lesson_date::text, l.year_month, l.lesson_content, l.note)
from public.school_lesson_records l
where l.planned_lesson_id in (select id from cleanup_ids where table_name='school_lesson_records')
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_import_batches', b.id, 'import batch text marker or confirmed test business entity', concat_ws(' | ', b.file_name, b.sheet_name, b.note, b.raw_meta::text)
from public.school_import_batches b
where b.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or concat_ws(' ', b.import_type, b.file_name, b.sheet_name, b.raw_meta::text, b.note, b.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_import_errors', e.id, 'import error belongs to confirmed test import batch or marker text', concat_ws(' | ', e.field_name, e.error_message, e.raw_value)
from public.school_import_errors e
where e.import_batch_id in (select id from cleanup_ids where table_name='school_import_batches')
   or concat_ws(' ', e.column_name, e.field_name, e.error_message, e.raw_value, e.severity) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_lesson_schedules', s.id, 'schedule references confirmed test master data or marker text', concat_ws(' | ', s.schedule_date::text, s.title, s.note)
from public.school_lesson_schedules s
where s.teacher_id in (select id from cleanup_ids where table_name='school_teachers')
   or s.subject_id in (select id from cleanup_ids where table_name='school_subjects')
   or s.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or concat_ws(' ', s.title, s.location, s.note, s.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_schedule_students', ss.id, 'schedule student links confirmed test schedule/student', concat_ws(' | ', ss.status, ss.note)
from public.school_schedule_students ss
where ss.schedule_id in (select id from cleanup_ids where table_name='school_lesson_schedules')
   or ss.student_id in (select id from cleanup_ids where table_name='school_students')
   or concat_ws(' ', ss.status, ss.note) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

-- Legacy monthly/payment/lesson tables.
insert into cleanup_ids(table_name, id, reason, sample)
select 'school_student_months', m.id, 'student month references confirmed test master data or marker text', concat_ws(' | ', m.year_month, m.status, m.note)
from public.school_student_months m
where m.student_id in (select id from cleanup_ids where table_name='school_students')
   or m.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or concat_ws(' ', m.year_month, m.status, m.note, m.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_planned_lessons', p.id, 'planned lesson references confirmed test data or marker text', concat_ws(' | ', p.year_month, p.content, p.note)
from public.school_planned_lessons p
where p.student_month_id in (select id from cleanup_ids where table_name='school_student_months')
   or p.student_id in (select id from cleanup_ids where table_name='school_students')
   or p.subject_id in (select id from cleanup_ids where table_name='school_subjects')
   or p.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or concat_ws(' ', p.content, p.note, p.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_actual_lessons', a.id, 'actual lesson references confirmed test data or marker text', concat_ws(' | ', a.year_month, a.content, a.remark)
from public.school_actual_lessons a
where a.student_month_id in (select id from cleanup_ids where table_name='school_student_months')
   or a.student_id in (select id from cleanup_ids where table_name='school_students')
   or a.teacher_id in (select id from cleanup_ids where table_name='school_teachers')
   or a.subject_id in (select id from cleanup_ids where table_name='school_subjects')
   or a.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or concat_ws(' ', a.content, a.remark, a.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_student_payments', p.id, 'student payment references confirmed test data or marker text', concat_ws(' | ', p.year_month, p.payment_type, p.note)
from public.school_student_payments p
where p.student_id in (select id from cleanup_ids where table_name='school_students')
   or p.student_month_id in (select id from cleanup_ids where table_name='school_student_months')
   or p.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or p.account_id in (select id from cleanup_ids where table_name='school_accounts')
   or concat_ws(' ', p.payment_type, p.status, p.note, p.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

-- Student settlement data.
insert into cleanup_ids(table_name, id, reason, sample)
select 'school_student_monthly_settlements', s.id, 'settlement references confirmed test student/business or marker text', concat_ws(' | ', s.year_month, s.settlement_status, s.note)
from public.school_student_monthly_settlements s
where s.student_id in (select id from cleanup_ids where table_name='school_students')
   or s.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or concat_ws(' ', s.year_month, s.adjustment_reason, s.note, s.unlock_reason) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_student_settlement_adjustment_drafts', d.id, 'settlement draft references confirmed test settlement/student/business or marker text', concat_ws(' | ', d.year_month, d.adjustment_reason, d.note)
from public.school_student_settlement_adjustment_drafts d
where d.settlement_id in (select id from cleanup_ids where table_name='school_student_monthly_settlements')
   or d.student_id in (select id from cleanup_ids where table_name='school_students')
   or d.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or concat_ws(' ', d.adjustment_source, d.adjustment_reason, d.note, d.created_by, d.updated_by, d.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_student_settlement_adjustments', a.id, 'settlement adjustment references confirmed test settlement/student/business or marker text', concat_ws(' | ', a.year_month, a.adjustment_reason, a.note)
from public.school_student_settlement_adjustments a
where a.settlement_id in (select id from cleanup_ids where table_name='school_student_monthly_settlements')
   or a.student_id in (select id from cleanup_ids where table_name='school_students')
   or a.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or concat_ws(' ', a.adjustment_source, a.adjustment_reason, a.note, a.created_by, a.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_student_settlement_carryovers', c.id, 'settlement carryover references confirmed test student/settlement or marker text', concat_ws(' | ', c.from_year_month, c.to_year_month, c.note)
from public.school_student_settlement_carryovers c
where c.student_id in (select id from cleanup_ids where table_name='school_students')
   or c.source_settlement_id in (select id from cleanup_ids where table_name='school_student_monthly_settlements')
   or concat_ws(' ', c.from_year_month, c.to_year_month, c.source_settlement_month, c.status, c.note) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

-- Wage snapshot/payment data.
insert into cleanup_ids(table_name, id, reason, sample)
select 'school_teacher_wage_locks', l.id, 'wage lock references confirmed test teacher/business or marker text', concat_ws(' | ', l.settlement_month, l.teacher_name, l.business_name, l.void_reason)
from public.school_teacher_wage_locks l
where l.teacher_id in (select id from cleanup_ids where table_name='school_teachers')
   or l.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or concat_ws(' ', l.settlement_month, l.teacher_name, l.business_name, l.status, l.void_reason, l.voided_by, l.void_source) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_teacher_wage_lock_details', d.id, 'wage detail references confirmed test lock/lesson/master or marker text', concat_ws(' | ', d.lesson_date::text, d.student_name, d.subject_name, d.business_name, d.lesson_content)
from public.school_teacher_wage_lock_details d
where d.lock_id in (select id from cleanup_ids where table_name='school_teacher_wage_locks')
   or d.lesson_record_id in (select id from cleanup_ids where table_name='school_lesson_records')
   or d.student_id in (select id from cleanup_ids where table_name='school_students')
   or d.subject_id in (select id from cleanup_ids where table_name='school_subjects')
   or d.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or concat_ws(' ', d.student_name, d.subject_name, d.business_name, d.lesson_content, d.status) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_teacher_wage_locks', l.id, 'wage lock has confirmed test wage detail', concat_ws(' | ', l.settlement_month, l.teacher_name, l.business_name)
from public.school_teacher_wage_locks l
where exists (
  select 1
  from public.school_teacher_wage_lock_details d
  join cleanup_ids c on c.table_name='school_teacher_wage_lock_details' and c.id=d.id
  where d.lock_id=l.id
)
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_teacher_wage_detail_adjustments', a.id, 'wage detail adjustment references confirmed test lock/detail or marker text', a.reason
from public.school_teacher_wage_detail_adjustments a
where a.wage_lock_id in (select id from cleanup_ids where table_name='school_teacher_wage_locks')
   or a.wage_detail_id in (select id from cleanup_ids where table_name='school_teacher_wage_lock_details')
   or coalesce(a.reason, '') ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_payment_requests', p.id, 'payment request references confirmed test source/payee/business/account/expense/transaction or marker text', concat_ws(' | ', p.source_type, p.request_month, p.payee_name, p.business_name, p.note, p.reversal_reason, p.reissue_reason)
from public.school_payment_requests p
where (p.source_type='teacher_wage' and p.source_id in (select id from cleanup_ids where table_name='school_teacher_wage_locks'))
   or p.payee_id in (select id from cleanup_ids where table_name='school_teachers')
   or p.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or p.account_id in (select id from cleanup_ids where table_name='school_accounts')
   or p.paid_expense_id in (select id from cleanup_ids where table_name='school_expense_records')
   or p.paid_account_transaction_id in (select id from cleanup_ids where table_name='school_account_transactions')
   or p.reversal_transaction_id in (select id from cleanup_ids where table_name='school_account_transactions')
   or p.reissued_from_payment_request_id in (select id from cleanup_ids where table_name='school_payment_requests')
   or p.replacement_payment_request_id in (select id from cleanup_ids where table_name='school_payment_requests')
   or concat_ws(' ', p.source_type, p.payee_type, p.payee_name, p.business_name, p.status, p.note, p.reversal_reason, p.reissue_reason) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

-- Income/expense/reimbursement/account data.
insert into cleanup_ids(table_name, id, reason, sample)
select 'school_salary_payments', s.id, 'salary payment references confirmed test master/account or marker text', concat_ws(' | ', s.year_month, s.salary_item, s.note)
from public.school_salary_payments s
where s.teacher_id in (select id from cleanup_ids where table_name='school_teachers')
   or s.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or s.account_id in (select id from cleanup_ids where table_name='school_accounts')
   or concat_ws(' ', s.year_month, s.salary_item, s.payment_method, s.bank_name, s.bank_account_name, s.alipay_account, s.wechat_account, s.status, s.current_location, s.source_type, s.note, s.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_income_records', i.id, 'income references confirmed test student/payment/account/business or marker text', concat_ws(' | ', i.year_month, i.description, i.note, i.reversal_reason)
from public.school_income_records i
where i.student_id in (select id from cleanup_ids where table_name='school_students')
   or i.student_payment_id in (select id from cleanup_ids where table_name='school_student_payments')
   or i.account_id in (select id from cleanup_ids where table_name='school_accounts')
   or i.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or concat_ws(' ', i.income_category, i.description, i.status, i.note, i.app_type, i.reversal_reason) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_expense_records', e.id, 'expense references confirmed test teacher/student/salary/account/business/payment or marker text', concat_ws(' | ', e.year_month, e.expense_category, e.description, e.note, e.reversal_reason)
from public.school_expense_records e
where e.teacher_id in (select id from cleanup_ids where table_name='school_teachers')
   or e.student_id in (select id from cleanup_ids where table_name='school_students')
   or e.salary_payment_id in (select id from cleanup_ids where table_name='school_salary_payments')
   or e.account_id in (select id from cleanup_ids where table_name='school_accounts')
   or e.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or e.id in (select paid_expense_id from public.school_payment_requests p join cleanup_ids c on c.table_name='school_payment_requests' and c.id=p.id where p.paid_expense_id is not null)
   or concat_ws(' ', e.expense_category, e.description, e.status, e.note, e.app_type, e.reimbursement_note, e.reversal_reason) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_expense_attachments', a.id, 'expense attachment references confirmed test expense or marker text', concat_ws(' | ', a.file_name, a.storage_bucket, a.storage_path, a.note)
from public.school_expense_attachments a
where a.expense_id in (select id from cleanup_ids where table_name='school_expense_records')
   or concat_ws(' ', a.file_name, a.file_type, a.storage_bucket, a.storage_path, a.public_url, a.source_type, a.extracted_text, a.note, a.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_reimbursements', r.id, 'reimbursement references confirmed test account/business or marker text', concat_ws(' | ', r.year_month, r.status, r.note, r.reversal_reason)
from public.school_reimbursements r
where r.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or r.from_account_id in (select id from cleanup_ids where table_name='school_accounts')
   or r.to_account_id in (select id from cleanup_ids where table_name='school_accounts')
   or concat_ws(' ', r.year_month, r.status, r.note, r.app_type, r.reversal_reason) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_reimbursement_items', i.id, 'reimbursement item references confirmed test reimbursement/expense or marker text', i.note
from public.school_reimbursement_items i
where i.reimbursement_id in (select id from cleanup_ids where table_name='school_reimbursements')
   or i.expense_id in (select id from cleanup_ids where table_name='school_expense_records')
   or concat_ws(' ', i.note, i.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_reimbursement_expenses', e.id, 'legacy reimbursement-expense link references confirmed test reimbursement/expense', e.amount::text
from public.school_reimbursement_expenses e
where e.reimbursement_id in (select id from cleanup_ids where table_name='school_reimbursements')
   or e.expense_id in (select id from cleanup_ids where table_name='school_expense_records')
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_reimbursements', r.id, 'reimbursement has confirmed test reimbursement item/link', concat_ws(' | ', r.year_month, r.status, r.note)
from public.school_reimbursements r
where exists (
  select 1
  from public.school_reimbursement_items i
  join cleanup_ids c on c.table_name='school_reimbursement_items' and c.id=i.id
  where i.reimbursement_id=r.id
)
or exists (
  select 1
  from public.school_reimbursement_expenses e
  join cleanup_ids c on c.table_name='school_reimbursement_expenses' and c.id=e.id
  where e.reimbursement_id=r.id
)
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_account_adjustments', a.id, 'account adjustment references confirmed test account/business/transaction or marker text', concat_ws(' | ', a.year_month, a.reason, a.note, a.reversal_reason)
from public.school_account_adjustments a
where a.account_id in (select id from cleanup_ids where table_name='school_accounts')
   or a.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or a.account_transaction_id in (select id from cleanup_ids where table_name='school_account_transactions')
   or a.reversal_account_transaction_id in (select id from cleanup_ids where table_name='school_account_transactions')
   or concat_ws(' ', a.reason, a.note, a.status, a.reversal_reason, a.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_account_transfers', t.id, 'account transfer references confirmed test account/business/transaction or marker text', concat_ws(' | ', t.year_month, t.reason, t.note, t.reversal_reason)
from public.school_account_transfers t
where t.from_account_id in (select id from cleanup_ids where table_name='school_accounts')
   or t.to_account_id in (select id from cleanup_ids where table_name='school_accounts')
   or t.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or t.from_account_transaction_id in (select id from cleanup_ids where table_name='school_account_transactions')
   or t.to_account_transaction_id in (select id from cleanup_ids where table_name='school_account_transactions')
   or t.reversal_from_account_transaction_id in (select id from cleanup_ids where table_name='school_account_transactions')
   or t.reversal_to_account_transaction_id in (select id from cleanup_ids where table_name='school_account_transactions')
   or concat_ws(' ', t.reason, t.note, t.status, t.reversal_reason, t.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_account_transactions', tx.id, 'account transaction references confirmed test account/business/source or marker text', concat_ws(' | ', tx.year_month, tx.transaction_type, tx.related_table, tx.description, tx.note)
from public.school_account_transactions tx
where tx.account_id in (select id from cleanup_ids where table_name='school_accounts')
   or tx.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or (tx.related_table='school_income_records' and tx.related_id in (select id from cleanup_ids where table_name='school_income_records'))
   or (tx.related_table='school_expense_records' and tx.related_id in (select id from cleanup_ids where table_name='school_expense_records'))
   or (tx.related_table='school_reimbursements' and tx.related_id in (select id from cleanup_ids where table_name='school_reimbursements'))
   or (tx.related_table='school_account_adjustments' and tx.related_id in (select id from cleanup_ids where table_name='school_account_adjustments'))
   or (tx.related_table='school_account_transfers' and tx.related_id in (select id from cleanup_ids where table_name='school_account_transfers'))
   or (tx.related_table='school_payment_requests' and tx.related_id in (select id from cleanup_ids where table_name='school_payment_requests'))
   or tx.id in (select reversal_account_transaction_id from public.school_income_records i join cleanup_ids c on c.table_name='school_income_records' and c.id=i.id where i.reversal_account_transaction_id is not null)
   or tx.id in (select reversal_account_transaction_id from public.school_expense_records e join cleanup_ids c on c.table_name='school_expense_records' and c.id=e.id where e.reversal_account_transaction_id is not null)
   or tx.id in (select reversal_from_account_transaction_id from public.school_reimbursements r join cleanup_ids c on c.table_name='school_reimbursements' and c.id=r.id where r.reversal_from_account_transaction_id is not null)
   or tx.id in (select reversal_to_account_transaction_id from public.school_reimbursements r join cleanup_ids c on c.table_name='school_reimbursements' and c.id=r.id where r.reversal_to_account_transaction_id is not null)
   or tx.id in (select account_transaction_id from public.school_account_adjustments a join cleanup_ids c on c.table_name='school_account_adjustments' and c.id=a.id where a.account_transaction_id is not null)
   or tx.id in (select reversal_account_transaction_id from public.school_account_adjustments a join cleanup_ids c on c.table_name='school_account_adjustments' and c.id=a.id where a.reversal_account_transaction_id is not null)
   or tx.id in (select from_account_transaction_id from public.school_account_transfers t join cleanup_ids c on c.table_name='school_account_transfers' and c.id=t.id where t.from_account_transaction_id is not null)
   or tx.id in (select to_account_transaction_id from public.school_account_transfers t join cleanup_ids c on c.table_name='school_account_transfers' and c.id=t.id where t.to_account_transaction_id is not null)
   or tx.id in (select reversal_from_account_transaction_id from public.school_account_transfers t join cleanup_ids c on c.table_name='school_account_transfers' and c.id=t.id where t.reversal_from_account_transaction_id is not null)
   or tx.id in (select reversal_to_account_transaction_id from public.school_account_transfers t join cleanup_ids c on c.table_name='school_account_transfers' and c.id=t.id where t.reversal_to_account_transaction_id is not null)
   or tx.id in (select paid_account_transaction_id from public.school_payment_requests p join cleanup_ids c on c.table_name='school_payment_requests' and c.id=p.id where p.paid_account_transaction_id is not null)
   or tx.id in (select reversal_transaction_id from public.school_payment_requests p join cleanup_ids c on c.table_name='school_payment_requests' and c.id=p.id where p.reversal_transaction_id is not null)
   or concat_ws(' ', tx.transaction_type, tx.related_table, tx.description, tx.note, tx.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

-- Re-run source tables once now that account transaction candidates exist.
insert into cleanup_ids(table_name, id, reason, sample)
select 'school_account_adjustments', a.id, 'account adjustment references confirmed test transaction', concat_ws(' | ', a.year_month, a.reason, a.note)
from public.school_account_adjustments a
where a.account_transaction_id in (select id from cleanup_ids where table_name='school_account_transactions')
   or a.reversal_account_transaction_id in (select id from cleanup_ids where table_name='school_account_transactions')
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_account_transfers', t.id, 'account transfer references confirmed test transaction', concat_ws(' | ', t.year_month, t.reason, t.note)
from public.school_account_transfers t
where t.from_account_transaction_id in (select id from cleanup_ids where table_name='school_account_transactions')
   or t.to_account_transaction_id in (select id from cleanup_ids where table_name='school_account_transactions')
   or t.reversal_from_account_transaction_id in (select id from cleanup_ids where table_name='school_account_transactions')
   or t.reversal_to_account_transaction_id in (select id from cleanup_ids where table_name='school_account_transactions')
on conflict do nothing;

-- Other peripheral tables.
insert into cleanup_ids(table_name, id, reason, sample)
select 'school_monthly_reports', r.id, 'monthly report references confirmed test business or marker text', concat_ws(' | ', r.year_month, r.note, r.report_data::text)
from public.school_monthly_reports r
where r.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or concat_ws(' ', r.year_month, r.report_data::text, r.note, r.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_teacher_work_logs', w.id, 'teacher work log references confirmed test master or marker text', concat_ws(' | ', w.year_month, w.work_content, w.note)
from public.school_teacher_work_logs w
where w.teacher_id in (select id from cleanup_ids where table_name='school_teachers')
   or w.student_id in (select id from cleanup_ids where table_name='school_students')
   or w.subject_id in (select id from cleanup_ids where table_name='school_subjects')
   or w.business_entity_id in (select id from cleanup_ids where table_name='school_business_entities')
   or concat_ws(' ', w.work_content, w.department, w.source_type, w.note, w.app_type) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_ids(table_name, id, reason, sample)
select 'school_settings', s.id, 'setting contains test marker', concat_ws(' | ', s.setting_key, s.setting_value::text, s.note)
from public.school_settings s
where concat_ws(' ', s.setting_key, s.setting_value::text, s.note) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

-- Storage objects: direct marker or referenced by candidate expense attachments.
insert into cleanup_storage_objects(id, bucket_id, name, reason, sample)
select o.id, o.bucket_id, o.name, 'storage object direct marker', concat_ws(' | ', o.bucket_id, o.name, o.metadata::text, o.user_metadata::text)
from storage.objects o
where concat_ws(' ', o.bucket_id, o.name, o.metadata::text, o.user_metadata::text) ~* '(codex|v2-test|sandbox|browser test|commit[[:space:][:alpha:]-]*test|rollback test)'
on conflict do nothing;

insert into cleanup_storage_objects(id, bucket_id, name, reason, sample)
select o.id, o.bucket_id, o.name, 'storage object referenced by candidate expense attachment', concat_ws(' | ', o.bucket_id, o.name)
from storage.objects o
where exists (
  select 1
  from public.school_expense_attachments a
  join cleanup_ids c on c.table_name='school_expense_attachments' and c.id=a.id
  where a.storage_bucket = o.bucket_id
    and a.storage_path = o.name
)
on conflict do nothing;

-- Risk checks: if these return rows, do not commit automatically. For real
-- accounts, only a zero-net candidate transaction set is allowed; non-zero
-- candidate rows would require account balance repair and must stop cleanup.
create temp table cleanup_non_candidate_account_tx_sums as
select tx.account_id, sum(tx.amount) as candidate_amount_sum
from public.school_account_transactions tx
join cleanup_ids c on c.table_name='school_account_transactions' and c.id=tx.id
where tx.account_id not in (select id from cleanup_ids where table_name='school_accounts')
group by tx.account_id;

create temp table cleanup_risks as
select 'candidate account transaction on non-candidate account may require balance repair' as risk_type,
       tx.id,
       concat_ws(' | ', tx.account_id::text, tx.transaction_type, tx.amount::text, tx.description, tx.note) as sample
from public.school_account_transactions tx
join cleanup_ids c on c.table_name='school_account_transactions' and c.id=tx.id
where tx.account_id not in (select id from cleanup_ids where table_name='school_accounts')
  and not exists (
    select 1
    from cleanup_non_candidate_account_tx_sums s
    where s.account_id=tx.account_id and s.candidate_amount_sum=0
  )
union all
select 'candidate income on non-candidate account may require balance repair',
       i.id,
       concat_ws(' | ', i.account_id::text, i.amount::text, i.description, i.note)
from public.school_income_records i
join cleanup_ids c on c.table_name='school_income_records' and c.id=i.id
where i.account_id is not null
  and i.account_id not in (select id from cleanup_ids where table_name='school_accounts')
  and not exists (
    select 1
    from cleanup_non_candidate_account_tx_sums s
    where s.account_id=i.account_id and s.candidate_amount_sum=0
  )
union all
select 'candidate expense on non-candidate account may require balance repair',
       e.id,
       concat_ws(' | ', e.account_id::text, e.amount::text, e.description, e.note)
from public.school_expense_records e
join cleanup_ids c on c.table_name='school_expense_records' and c.id=e.id
where e.account_id is not null
  and e.account_id not in (select id from cleanup_ids where table_name='school_accounts')
  and not exists (
    select 1
    from cleanup_non_candidate_account_tx_sums s
    where s.account_id=e.account_id and s.candidate_amount_sum=0
  )
union all
select 'candidate reimbursement uses non-candidate account may require balance repair',
       r.id,
       concat_ws(' | ', r.from_account_id::text, r.to_account_id::text, r.amount::text, r.note)
from public.school_reimbursements r
join cleanup_ids c on c.table_name='school_reimbursements' and c.id=r.id
where (r.from_account_id is not null and r.from_account_id not in (select id from cleanup_ids where table_name='school_accounts'))
   or (r.to_account_id is not null and r.to_account_id not in (select id from cleanup_ids where table_name='school_accounts'))
union all
select 'candidate transfer uses non-candidate account may require balance repair',
       t.id,
       concat_ws(' | ', t.from_account_id::text, t.to_account_id::text, t.amount::text, t.note)
from public.school_account_transfers t
join cleanup_ids c on c.table_name='school_account_transfers' and c.id=t.id
where (t.from_account_id is not null and t.from_account_id not in (select id from cleanup_ids where table_name='school_accounts'))
   or (t.to_account_id is not null and t.to_account_id not in (select id from cleanup_ids where table_name='school_accounts'))
union all
select 'candidate adjustment uses non-candidate account may require balance repair',
       a.id,
       concat_ws(' | ', a.account_id::text, a.amount::text, a.reason, a.note)
from public.school_account_adjustments a
join cleanup_ids c on c.table_name='school_account_adjustments' and c.id=a.id
where a.account_id is not null
  and a.account_id not in (select id from cleanup_ids where table_name='school_accounts')
  and not exists (
    select 1
    from cleanup_non_candidate_account_tx_sums s
    where s.account_id=a.account_id and s.candidate_amount_sum=0
  );

-- Dry-run outputs.
\echo 'cleanup_mode'
select :'cleanup_execute' as cleanup_execute, :'cleanup_commit' as cleanup_commit;

\echo 'candidate_counts_by_table'
select table_name, count(*) as candidate_count
from cleanup_ids
group by table_name
order by table_name;

\echo 'candidate_sample_ids'
select table_name, id, reason, left(coalesce(sample, ''), 180) as sample
from (
  select c.*, row_number() over (partition by table_name order by id) as rn
  from cleanup_ids c
) s
where rn <= 12
order by table_name, id;

\echo 'storage_candidate_counts'
select bucket_id, count(*) as candidate_count
from cleanup_storage_objects
group by bucket_id
order by bucket_id;

\echo 'storage_candidate_sample'
select id, bucket_id, name, reason, left(coalesce(sample, ''), 180) as sample
from cleanup_storage_objects
order by bucket_id, name
limit 20;

\echo 'manual_review_list'
select table_name, id, reason, left(coalesce(sample, ''), 220) as sample
from cleanup_manual_review
order by table_name, id;

\echo 'risk_list'
select risk_type, id, left(coalesce(sample, ''), 220) as sample
from cleanup_risks
order by risk_type, id;

\echo 'candidate_totals'
select
  (select count(*) from cleanup_ids) as db_candidate_rows,
  (select count(*) from cleanup_storage_objects) as storage_candidate_rows,
  (select count(*) from cleanup_manual_review) as manual_review_rows,
  (select count(*) from cleanup_risks) as risk_rows;

\if :cleanup_execute
\echo 'executing_cleanup_deletes'

-- Guard: do not execute cleanup if deleting financial/account rows would require
-- non-test account balance repair.
do $$
begin
  if exists (select 1 from cleanup_risks) then
    raise exception 'Cleanup risk list is not empty. Stop before delete/commit.';
  end if;
  if exists (select 1 from cleanup_storage_objects) then
    raise exception 'Storage cleanup candidates exist. Stop and clean via the Storage API, not direct storage table delete.';
  end if;
end $$;

create temp table cleanup_deleted_counts(table_name text primary key, deleted_count integer not null) on commit drop;

insert into cleanup_deleted_counts values ('storage.objects', 0);

with deleted as (
  delete from public.school_expense_attachments t
  using cleanup_ids c
  where c.table_name='school_expense_attachments' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_expense_attachments', (select count(*) from deleted));

with deleted as (
  delete from public.school_reimbursement_expenses t
  using cleanup_ids c
  where c.table_name='school_reimbursement_expenses' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_reimbursement_expenses', (select count(*) from deleted));

with deleted as (
  delete from public.school_reimbursement_items t
  using cleanup_ids c
  where c.table_name='school_reimbursement_items' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_reimbursement_items', (select count(*) from deleted));

with deleted as (
  delete from public.school_teacher_wage_detail_adjustments t
  using cleanup_ids c
  where c.table_name='school_teacher_wage_detail_adjustments' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_teacher_wage_detail_adjustments', (select count(*) from deleted));

with deleted as (
  delete from public.school_teacher_wage_lock_details t
  using cleanup_ids c
  where c.table_name='school_teacher_wage_lock_details' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_teacher_wage_lock_details', (select count(*) from deleted));

with deleted as (
  delete from public.school_payment_requests t
  using cleanup_ids c
  where c.table_name='school_payment_requests' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_payment_requests', (select count(*) from deleted));

with deleted as (
  delete from public.school_expense_records t
  using cleanup_ids c
  where c.table_name='school_expense_records' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_expense_records', (select count(*) from deleted));

with deleted as (
  delete from public.school_income_records t
  using cleanup_ids c
  where c.table_name='school_income_records' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_income_records', (select count(*) from deleted));

with deleted as (
  delete from public.school_reimbursements t
  using cleanup_ids c
  where c.table_name='school_reimbursements' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_reimbursements', (select count(*) from deleted));

with deleted as (
  delete from public.school_account_adjustments t
  using cleanup_ids c
  where c.table_name='school_account_adjustments' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_account_adjustments', (select count(*) from deleted));

with deleted as (
  delete from public.school_account_transfers t
  using cleanup_ids c
  where c.table_name='school_account_transfers' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_account_transfers', (select count(*) from deleted));

with deleted as (
  delete from public.school_account_transactions t
  using cleanup_ids c
  where c.table_name='school_account_transactions' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_account_transactions', (select count(*) from deleted));

with deleted as (
  delete from public.school_student_settlement_adjustment_drafts t
  using cleanup_ids c
  where c.table_name='school_student_settlement_adjustment_drafts' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_student_settlement_adjustment_drafts', (select count(*) from deleted));

with deleted as (
  delete from public.school_student_settlement_adjustments t
  using cleanup_ids c
  where c.table_name='school_student_settlement_adjustments' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_student_settlement_adjustments', (select count(*) from deleted));

with deleted as (
  delete from public.school_student_settlement_carryovers t
  using cleanup_ids c
  where c.table_name='school_student_settlement_carryovers' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_student_settlement_carryovers', (select count(*) from deleted));

with deleted as (
  delete from public.school_student_monthly_settlements t
  using cleanup_ids c
  where c.table_name='school_student_monthly_settlements' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_student_monthly_settlements', (select count(*) from deleted));

with deleted as (
  delete from public.school_actual_lessons t
  using cleanup_ids c
  where c.table_name='school_actual_lessons' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_actual_lessons', (select count(*) from deleted));

with deleted as (
  delete from public.school_planned_lessons t
  using cleanup_ids c
  where c.table_name='school_planned_lessons' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_planned_lessons', (select count(*) from deleted));

with deleted as (
  delete from public.school_student_payments t
  using cleanup_ids c
  where c.table_name='school_student_payments' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_student_payments', (select count(*) from deleted));

with deleted as (
  delete from public.school_student_months t
  using cleanup_ids c
  where c.table_name='school_student_months' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_student_months', (select count(*) from deleted));

with deleted as (
  delete from public.school_schedule_students t
  using cleanup_ids c
  where c.table_name='school_schedule_students' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_schedule_students', (select count(*) from deleted));

with deleted as (
  delete from public.school_lesson_schedules t
  using cleanup_ids c
  where c.table_name='school_lesson_schedules' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_lesson_schedules', (select count(*) from deleted));

with deleted as (
  delete from public.school_lesson_records t
  using cleanup_ids c
  where c.table_name='school_lesson_records' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_lesson_records', (select count(*) from deleted));

with deleted as (
  delete from public.school_import_errors t
  using cleanup_ids c
  where c.table_name='school_import_errors' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_import_errors', (select count(*) from deleted));

with deleted as (
  delete from public.school_import_batches t
  using cleanup_ids c
  where c.table_name='school_import_batches' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_import_batches', (select count(*) from deleted));

with deleted as (
  delete from public.school_monthly_reports t
  using cleanup_ids c
  where c.table_name='school_monthly_reports' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_monthly_reports', (select count(*) from deleted));

with deleted as (
  delete from public.school_teacher_work_logs t
  using cleanup_ids c
  where c.table_name='school_teacher_work_logs' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_teacher_work_logs', (select count(*) from deleted));

with deleted as (
  delete from public.school_salary_payments t
  using cleanup_ids c
  where c.table_name='school_salary_payments' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_salary_payments', (select count(*) from deleted));

with deleted as (
  delete from public.school_teacher_wage_locks t
  using cleanup_ids c
  where c.table_name='school_teacher_wage_locks' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_teacher_wage_locks', (select count(*) from deleted));

with deleted as (
  delete from public.school_teacher_wage_rules t
  using cleanup_ids c
  where c.table_name='school_teacher_wage_rules' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_teacher_wage_rules', (select count(*) from deleted));

with deleted as (
  delete from public.school_settings t
  using cleanup_ids c
  where c.table_name='school_settings' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_settings', (select count(*) from deleted));

with deleted as (
  delete from public.school_accounts t
  using cleanup_ids c
  where c.table_name='school_accounts' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_accounts', (select count(*) from deleted));

with deleted as (
  delete from public.school_students t
  using cleanup_ids c
  where c.table_name='school_students' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_students', (select count(*) from deleted));

with deleted as (
  delete from public.school_teachers t
  using cleanup_ids c
  where c.table_name='school_teachers' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_teachers', (select count(*) from deleted));

with deleted as (
  delete from public.school_subjects t
  using cleanup_ids c
  where c.table_name='school_subjects' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_subjects', (select count(*) from deleted));

with deleted as (
  delete from public.school_business_entities t
  using cleanup_ids c
  where c.table_name='school_business_entities' and c.id=t.id
  returning t.id
)
insert into cleanup_deleted_counts values ('school_business_entities', (select count(*) from deleted));

\echo 'deleted_counts'
select * from cleanup_deleted_counts where deleted_count <> 0 order by table_name;

\echo 'post_delete_candidate_residue_before_transaction_end'
select c.table_name, count(*) as still_present_count
from cleanup_ids c
where (
  (c.table_name='school_account_adjustments' and exists (select 1 from public.school_account_adjustments t where t.id=c.id)) or
  (c.table_name='school_account_transactions' and exists (select 1 from public.school_account_transactions t where t.id=c.id)) or
  (c.table_name='school_account_transfers' and exists (select 1 from public.school_account_transfers t where t.id=c.id)) or
  (c.table_name='school_accounts' and exists (select 1 from public.school_accounts t where t.id=c.id)) or
  (c.table_name='school_actual_lessons' and exists (select 1 from public.school_actual_lessons t where t.id=c.id)) or
  (c.table_name='school_business_entities' and exists (select 1 from public.school_business_entities t where t.id=c.id)) or
  (c.table_name='school_expense_attachments' and exists (select 1 from public.school_expense_attachments t where t.id=c.id)) or
  (c.table_name='school_expense_records' and exists (select 1 from public.school_expense_records t where t.id=c.id)) or
  (c.table_name='school_import_batches' and exists (select 1 from public.school_import_batches t where t.id=c.id)) or
  (c.table_name='school_import_errors' and exists (select 1 from public.school_import_errors t where t.id=c.id)) or
  (c.table_name='school_income_records' and exists (select 1 from public.school_income_records t where t.id=c.id)) or
  (c.table_name='school_lesson_records' and exists (select 1 from public.school_lesson_records t where t.id=c.id)) or
  (c.table_name='school_lesson_schedules' and exists (select 1 from public.school_lesson_schedules t where t.id=c.id)) or
  (c.table_name='school_monthly_reports' and exists (select 1 from public.school_monthly_reports t where t.id=c.id)) or
  (c.table_name='school_payment_requests' and exists (select 1 from public.school_payment_requests t where t.id=c.id)) or
  (c.table_name='school_planned_lessons' and exists (select 1 from public.school_planned_lessons t where t.id=c.id)) or
  (c.table_name='school_reimbursement_expenses' and exists (select 1 from public.school_reimbursement_expenses t where t.id=c.id)) or
  (c.table_name='school_reimbursement_items' and exists (select 1 from public.school_reimbursement_items t where t.id=c.id)) or
  (c.table_name='school_reimbursements' and exists (select 1 from public.school_reimbursements t where t.id=c.id)) or
  (c.table_name='school_salary_payments' and exists (select 1 from public.school_salary_payments t where t.id=c.id)) or
  (c.table_name='school_schedule_students' and exists (select 1 from public.school_schedule_students t where t.id=c.id)) or
  (c.table_name='school_settings' and exists (select 1 from public.school_settings t where t.id=c.id)) or
  (c.table_name='school_student_monthly_settlements' and exists (select 1 from public.school_student_monthly_settlements t where t.id=c.id)) or
  (c.table_name='school_student_months' and exists (select 1 from public.school_student_months t where t.id=c.id)) or
  (c.table_name='school_student_payments' and exists (select 1 from public.school_student_payments t where t.id=c.id)) or
  (c.table_name='school_student_settlement_adjustment_drafts' and exists (select 1 from public.school_student_settlement_adjustment_drafts t where t.id=c.id)) or
  (c.table_name='school_student_settlement_adjustments' and exists (select 1 from public.school_student_settlement_adjustments t where t.id=c.id)) or
  (c.table_name='school_student_settlement_carryovers' and exists (select 1 from public.school_student_settlement_carryovers t where t.id=c.id)) or
  (c.table_name='school_students' and exists (select 1 from public.school_students t where t.id=c.id)) or
  (c.table_name='school_subjects' and exists (select 1 from public.school_subjects t where t.id=c.id)) or
  (c.table_name='school_teacher_wage_detail_adjustments' and exists (select 1 from public.school_teacher_wage_detail_adjustments t where t.id=c.id)) or
  (c.table_name='school_teacher_wage_lock_details' and exists (select 1 from public.school_teacher_wage_lock_details t where t.id=c.id)) or
  (c.table_name='school_teacher_wage_locks' and exists (select 1 from public.school_teacher_wage_locks t where t.id=c.id)) or
  (c.table_name='school_teacher_wage_rules' and exists (select 1 from public.school_teacher_wage_rules t where t.id=c.id)) or
  (c.table_name='school_teacher_work_logs' and exists (select 1 from public.school_teacher_work_logs t where t.id=c.id)) or
  (c.table_name='school_teachers' and exists (select 1 from public.school_teachers t where t.id=c.id))
)
group by c.table_name
order by c.table_name;

\echo 'post_delete_storage_residue_before_transaction_end'
select count(*) as storage_candidate_residue
from cleanup_storage_objects c
where exists (select 1 from storage.objects o where o.id=c.id);

\endif

\if :cleanup_commit
commit;
\echo 'transaction_result: committed'
\else
rollback;
\echo 'transaction_result: rolled back'
\endif
