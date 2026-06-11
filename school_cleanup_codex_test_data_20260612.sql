-- Cleanup clearly marked codex/test/测试 data and its derived records.
--
-- Usage:
--   Dry-run / rollback test:
--     psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -v cleanup_commit=false -f school_cleanup_codex_test_data_20260612.sql
--   Verified commit:
--     psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -v cleanup_commit=true -f school_cleanup_codex_test_data_20260612.sql
--
-- Safety model:
-- - Target roots are clearly marked test master data or data under clearly marked
--   test business/account/teacher/student/subject records.
-- - Account transactions are only deletable when they are on a target test account.
-- - If a target chain would touch a non-target account or non-target account
--   transaction dependency, the script raises an exception before deleting.
-- - No schema/RPC/function is created or changed.

\if :{?cleanup_commit}
\else
\set cleanup_commit false
\endif

\echo cleanup_commit=:cleanup_commit

begin;

create temp table cleanup_marker(rx text not null) on commit drop;
insert into cleanup_marker values
  ('(codex|v2-test|sandbox|测试|(^|[^[:alnum:]])test([^[:alnum:]]|$))');

create temp table target_business_entities as
select distinct id
from school_business_entities
where concat_ws(' ', code, name, entity_type, default_currency, note) ~* (select rx from cleanup_marker);

create temp table target_accounts as
select distinct a.id
from school_accounts a
left join target_business_entities be on be.id = a.business_entity_id
where be.id is not null
   or concat_ws(' ', a.account_code, a.name, a.account_type, a.currency, a.note, a.app_type) ~* (select rx from cleanup_marker);

create temp table target_subjects as
select distinct id
from school_subjects
where concat_ws(' ', name, category, primary_category, tertiary_category, color, note) ~* (select rx from cleanup_marker);

create temp table target_teachers as
select distinct t.id
from school_teachers t
left join target_business_entities be on be.id = t.default_business_entity_id
where be.id is not null
   or concat_ws(
        ' ',
        t.teacher_code, t.name, t.kana_name, t.display_name, t.department,
        t.default_currency, t.default_payment_currency, t.default_payment_method,
        t.default_account_name, t.phone, t.email, t.wechat, t.status, t.note, t.app_type
      ) ~* (select rx from cleanup_marker);

create temp table candidate_students as
select distinct s.id
from school_students s
left join target_business_entities be on be.id = s.business_entity_id
where be.id is not null
   or concat_ws(
        ' ',
        s.student_code, s.name, s.kana_name, s.display_name, s.gender,
        s.phone, s.email, s.wechat, s.parent_name, s.parent_phone, s.parent_wechat,
        s.target_type, s.target_schools, s.status, s.default_currency,
        s.course_track, s.note, s.app_type
      ) ~* (select rx from cleanup_marker);

create temp table protected_students as
select distinct cs.id
from candidate_students cs
where exists (
  select 1
  from school_income_records i
  left join target_accounts ta on ta.id = i.account_id
  where i.student_id = cs.id
    and i.account_id is not null
    and ta.id is null
)
or exists (
  select 1
  from school_expense_records e
  left join target_accounts ta on ta.id = e.account_id
  where e.student_id = cs.id
    and e.account_id is not null
    and ta.id is null
)
or exists (
  select 1
  from school_student_payments sp
  left join target_accounts ta on ta.id = sp.account_id
  where sp.student_id = cs.id
    and sp.account_id is not null
    and ta.id is null
);

create temp table target_students as
select id from candidate_students
except
select id from protected_students;

create temp table protected_business_entities as
select distinct s.business_entity_id as id
from school_students s
join protected_students ps on ps.id = s.id
where s.business_entity_id is not null;

delete from target_business_entities be
using protected_business_entities pbe
where be.id = pbe.id;

delete from target_accounts ta
using school_accounts a, protected_business_entities pbe
where ta.id = a.id
  and a.business_entity_id = pbe.id
  and not (concat_ws(' ', a.account_code, a.name, a.account_type, a.currency, a.note, a.app_type) ~* (select rx from cleanup_marker));

delete from target_teachers tt
using school_teachers t, protected_business_entities pbe
where tt.id = t.id
  and t.default_business_entity_id = pbe.id
  and not (
    concat_ws(
      ' ',
      t.teacher_code, t.name, t.kana_name, t.display_name, t.department,
      t.default_currency, t.default_payment_currency, t.default_payment_method,
      t.default_account_name, t.phone, t.email, t.wechat, t.status, t.note, t.app_type
    ) ~* (select rx from cleanup_marker)
  );

delete from target_students ts
using school_students s, protected_business_entities pbe
where ts.id = s.id
  and s.business_entity_id = pbe.id
  and not (
    concat_ws(
      ' ',
      s.student_code, s.name, s.kana_name, s.display_name, s.gender,
      s.phone, s.email, s.wechat, s.parent_name, s.parent_phone, s.parent_wechat,
      s.target_type, s.target_schools, s.status, s.default_currency,
      s.course_track, s.note, s.app_type
    ) ~* (select rx from cleanup_marker)
  );

create temp table target_import_batches as
select distinct b.id
from school_import_batches b
left join target_business_entities be on be.id = b.business_entity_id
where be.id is not null
   or concat_ws(' ', b.import_type, b.file_name, b.sheet_name, b.year_month, b.status, b.raw_meta::text, b.note, b.app_type) ~* (select rx from cleanup_marker);

create temp table target_lesson_schedules as
select distinct ls.id
from school_lesson_schedules ls
left join target_business_entities be on be.id = ls.business_entity_id
left join target_subjects sub on sub.id = ls.subject_id
left join target_teachers tt on tt.id = ls.teacher_id
where be.id is not null
   or sub.id is not null
   or tt.id is not null;

create temp table target_schedule_students as
select distinct ss.id
from school_schedule_students ss
left join target_lesson_schedules tls on tls.id = ss.schedule_id
left join target_students ts on ts.id = ss.student_id
where tls.id is not null
   or ts.id is not null;

create temp table target_student_months as
select distinct sm.id
from school_student_months sm
left join target_students ts on ts.id = sm.student_id
left join target_business_entities be on be.id = sm.business_entity_id
where ts.id is not null
   or be.id is not null;

create temp table target_student_payments as
select distinct sp.id
from school_student_payments sp
left join target_students ts on ts.id = sp.student_id
left join target_student_months tsm on tsm.id = sp.student_month_id
left join target_business_entities be on be.id = sp.business_entity_id
left join target_accounts ta on ta.id = sp.account_id
where ts.id is not null
   or tsm.id is not null
   or be.id is not null
   or ta.id is not null;

create temp table target_student_monthly_settlements as
select distinct sms.id
from school_student_monthly_settlements sms
left join target_students ts on ts.id = sms.student_id
left join target_business_entities be on be.id = sms.business_entity_id
where ts.id is not null
   or be.id is not null;

create temp table target_student_settlement_adjustments as
select distinct a.id
from school_student_settlement_adjustments a
left join target_student_monthly_settlements tsms on tsms.id = a.settlement_id
left join target_students ts on ts.id = a.student_id
left join target_business_entities be on be.id = a.business_entity_id
where tsms.id is not null
   or ts.id is not null
   or be.id is not null;

create temp table target_student_settlement_adjustment_drafts as
select distinct d.id
from school_student_settlement_adjustment_drafts d
left join target_student_monthly_settlements tsms on tsms.id = d.settlement_id
left join target_students ts on ts.id = d.student_id
left join target_business_entities be on be.id = d.business_entity_id
where tsms.id is not null
   or ts.id is not null
   or be.id is not null;

create temp table target_student_settlement_carryovers as
select distinct c.id
from school_student_settlement_carryovers c
left join target_students ts on ts.id = c.student_id
left join target_student_monthly_settlements tsms on tsms.id = c.source_settlement_id
where ts.id is not null
   or tsms.id is not null;

create temp table target_planned_lessons as
select distinct pl.id
from school_planned_lessons pl
left join target_student_months tsm on tsm.id = pl.student_month_id
left join target_students ts on ts.id = pl.student_id
left join target_business_entities be on be.id = pl.business_entity_id
left join target_subjects sub on sub.id = pl.subject_id
where tsm.id is not null
   or ts.id is not null
   or be.id is not null
   or sub.id is not null;

create temp table target_actual_lessons as
select distinct al.id
from school_actual_lessons al
left join target_student_months tsm on tsm.id = al.student_month_id
left join target_students ts on ts.id = al.student_id
left join target_teachers tt on tt.id = al.teacher_id
left join target_business_entities be on be.id = al.business_entity_id
left join target_subjects sub on sub.id = al.subject_id
where tsm.id is not null
   or ts.id is not null
   or tt.id is not null
   or be.id is not null
   or sub.id is not null;

create temp table target_lesson_records as
select distinct lr.id
from school_lesson_records lr
left join target_students ts on ts.id = lr.student_id
left join target_teachers tt on tt.id = lr.teacher_id
left join target_subjects sub on sub.id = lr.subject_id
left join target_business_entities be on be.id = lr.business_entity_id
left join target_import_batches tib on tib.id::text = lr.import_batch_id
where ts.id is not null
   or tt.id is not null
   or sub.id is not null
   or be.id is not null
   or tib.id is not null;

insert into target_lesson_records
select distinct child.id
from school_lesson_records child
join target_lesson_records parent on parent.id = child.planned_lesson_id
left join target_lesson_records existing on existing.id = child.id
where existing.id is null;

create temp table target_teacher_work_logs as
select distinct wl.id
from school_teacher_work_logs wl
left join target_teachers tt on tt.id = wl.teacher_id
left join target_students ts on ts.id = wl.student_id
left join target_business_entities be on be.id = wl.business_entity_id
left join target_subjects sub on sub.id = wl.subject_id
where tt.id is not null
   or ts.id is not null
   or be.id is not null
   or sub.id is not null;

create temp table target_salary_payments as
select distinct sp.id
from school_salary_payments sp
left join target_teachers tt on tt.id = sp.teacher_id
left join target_business_entities be on be.id = sp.business_entity_id
left join target_accounts ta on ta.id = sp.account_id
left join target_import_batches tib on tib.id = sp.source_import_batch_id
where tt.id is not null
   or be.id is not null
   or ta.id is not null
   or tib.id is not null;

create temp table target_wage_rules as
select distinct wr.id
from school_teacher_wage_rules wr
left join target_teachers tt on tt.id = wr.teacher_id
left join target_students ts on ts.id = wr.student_id
left join target_subjects sub on sub.id = wr.subject_id
left join target_business_entities be on be.id = wr.business_entity_id
where tt.id is not null
   or ts.id is not null
   or sub.id is not null
   or be.id is not null;

create temp table target_wage_locks as
select distinct wl.id
from school_teacher_wage_locks wl
left join target_teachers tt on tt.id = wl.teacher_id
left join target_business_entities be on be.id = wl.business_entity_id
where tt.id is not null
   or be.id is not null;

create temp table target_wage_lock_details as
select distinct d.id
from school_teacher_wage_lock_details d
left join target_wage_locks twl on twl.id = d.lock_id
left join target_lesson_records tlr on tlr.id = d.lesson_record_id
left join target_students ts on ts.id = d.student_id
left join target_subjects sub on sub.id = d.subject_id
left join target_business_entities be on be.id = d.business_entity_id
where twl.id is not null
   or tlr.id is not null
   or ts.id is not null
   or sub.id is not null
   or be.id is not null;

insert into target_wage_locks
select distinct d.lock_id
from school_teacher_wage_lock_details d
join target_wage_lock_details td on td.id = d.id
left join target_wage_locks twl on twl.id = d.lock_id
where twl.id is null;

create temp table target_wage_detail_adjustments as
select distinct a.id
from school_teacher_wage_detail_adjustments a
left join target_wage_locks twl on twl.id = a.wage_lock_id
left join target_wage_lock_details td on td.id = a.wage_detail_id
where twl.id is not null
   or td.id is not null;

create temp table target_payment_requests as
select distinct pr.id
from school_payment_requests pr
left join target_wage_locks twl on pr.source_type = 'teacher_wage' and twl.id = pr.source_id
left join target_teachers tt on pr.payee_type = 'teacher' and tt.id = pr.payee_id
left join target_business_entities be on be.id = pr.business_entity_id
left join target_accounts ta on ta.id = pr.account_id
where twl.id is not null
   or tt.id is not null
   or be.id is not null
   or ta.id is not null;

create temp table target_expense_records as
select distinct e.id
from school_expense_records e
left join target_business_entities be on be.id = e.business_entity_id
left join target_teachers tt on tt.id = e.teacher_id
left join target_students ts on ts.id = e.student_id
left join target_salary_payments tsp on tsp.id = e.salary_payment_id
left join target_accounts ta on ta.id = e.account_id
left join school_payment_requests pr on pr.paid_expense_id = e.id
left join target_payment_requests tpr on tpr.id = pr.id
where be.id is not null
   or tt.id is not null
   or ts.id is not null
   or tsp.id is not null
   or ta.id is not null
   or tpr.id is not null;

insert into target_payment_requests
select distinct pr.id
from school_payment_requests pr
join target_expense_records te on te.id = pr.paid_expense_id
left join target_payment_requests existing on existing.id = pr.id
where existing.id is null;

create temp table target_expense_attachments as
select distinct ea.id
from school_expense_attachments ea
left join target_expense_records te on te.id = ea.expense_id
where te.id is not null
;

create temp table target_reimbursements as
select distinct r.id
from school_reimbursements r
left join target_business_entities be on be.id = r.business_entity_id
left join target_accounts fa on fa.id = r.from_account_id
left join target_accounts ta on ta.id = r.to_account_id
where be.id is not null
   or fa.id is not null
   or ta.id is not null;

create temp table target_reimbursement_items as
select distinct ri.id
from school_reimbursement_items ri
left join target_reimbursements tr on tr.id = ri.reimbursement_id
left join target_expense_records te on te.id = ri.expense_id
where tr.id is not null
   or te.id is not null;

insert into target_reimbursements
select distinct ri.reimbursement_id
from school_reimbursement_items ri
join target_reimbursement_items tri on tri.id = ri.id
left join target_reimbursements existing on existing.id = ri.reimbursement_id
where existing.id is null;

create temp table target_reimbursement_expenses as
select distinct re.id
from school_reimbursement_expenses re
left join target_reimbursements tr on tr.id = re.reimbursement_id
left join target_expense_records te on te.id = re.expense_id
where tr.id is not null
   or te.id is not null;

create temp table target_income_records as
select distinct i.id
from school_income_records i
left join target_business_entities be on be.id = i.business_entity_id
left join target_students ts on ts.id = i.student_id
left join target_student_payments tsp on tsp.id = i.student_payment_id
left join target_accounts ta on ta.id = i.account_id
where be.id is not null
   or ts.id is not null
   or tsp.id is not null
   or ta.id is not null;

create temp table target_account_adjustments as
select distinct aa.id
from school_account_adjustments aa
left join target_business_entities be on be.id = aa.business_entity_id
left join target_accounts ta on ta.id = aa.account_id
where be.id is not null
   or ta.id is not null;

create temp table target_account_transfers as
select distinct at.id
from school_account_transfers at
left join target_business_entities be on be.id = at.business_entity_id
left join target_accounts fa on fa.id = at.from_account_id
left join target_accounts ta on ta.id = at.to_account_id
where be.id is not null
   or fa.id is not null
   or ta.id is not null;

create temp table target_monthly_reports as
select distinct mr.id
from school_monthly_reports mr
left join target_business_entities be on be.id = mr.business_entity_id
where be.id is not null
;

create temp table target_account_transactions as
select distinct tx.id
from school_account_transactions tx
left join target_accounts ta on ta.id = tx.account_id
left join target_business_entities be on be.id = tx.business_entity_id
left join target_expense_records te on tx.related_table = 'school_expense_records' and tx.related_id = te.id
left join target_income_records ti on tx.related_table = 'school_income_records' and tx.related_id = ti.id
left join target_payment_requests tpr on tx.related_table = 'school_payment_requests' and tx.related_id = tpr.id
left join target_reimbursements tr on tx.related_table = 'school_reimbursements' and tx.related_id = tr.id
left join target_account_transfers tat on tx.related_table = 'school_account_transfers' and tx.related_id = tat.id
left join target_account_adjustments taa on tx.related_table = 'school_account_adjustments' and tx.related_id = taa.id
where ta.id is not null
   or be.id is not null
   or te.id is not null
   or ti.id is not null
   or tpr.id is not null
   or tr.id is not null
   or tat.id is not null
   or taa.id is not null;

create temp table cleanup_target_counts(table_name text primary key, target_count bigint not null) on commit drop;
insert into cleanup_target_counts
select * from (values
  ('school_business_entities', (select count(*) from target_business_entities)),
  ('school_accounts', (select count(*) from target_accounts)),
  ('school_subjects', (select count(*) from target_subjects)),
  ('school_teachers', (select count(*) from target_teachers)),
  ('school_students', (select count(*) from target_students)),
  ('school_import_batches', (select count(*) from target_import_batches)),
  ('school_import_errors', (select count(*) from school_import_errors e join target_import_batches b on b.id = e.import_batch_id)),
  ('school_lesson_schedules', (select count(*) from target_lesson_schedules)),
  ('school_schedule_students', (select count(*) from target_schedule_students)),
  ('school_student_months', (select count(*) from target_student_months)),
  ('school_student_payments', (select count(*) from target_student_payments)),
  ('school_student_monthly_settlements', (select count(*) from target_student_monthly_settlements)),
  ('school_student_settlement_adjustments', (select count(*) from target_student_settlement_adjustments)),
  ('school_student_settlement_adjustment_drafts', (select count(*) from target_student_settlement_adjustment_drafts)),
  ('school_student_settlement_carryovers', (select count(*) from target_student_settlement_carryovers)),
  ('school_planned_lessons', (select count(*) from target_planned_lessons)),
  ('school_actual_lessons', (select count(*) from target_actual_lessons)),
  ('school_lesson_records', (select count(*) from target_lesson_records)),
  ('school_teacher_work_logs', (select count(*) from target_teacher_work_logs)),
  ('school_salary_payments', (select count(*) from target_salary_payments)),
  ('school_teacher_wage_rules', (select count(*) from target_wage_rules)),
  ('school_teacher_wage_locks', (select count(*) from target_wage_locks)),
  ('school_teacher_wage_lock_details', (select count(*) from target_wage_lock_details)),
  ('school_teacher_wage_detail_adjustments', (select count(*) from target_wage_detail_adjustments)),
  ('school_payment_requests', (select count(*) from target_payment_requests)),
  ('school_expense_records', (select count(*) from target_expense_records)),
  ('school_expense_attachments', (select count(*) from target_expense_attachments)),
  ('school_reimbursements', (select count(*) from target_reimbursements)),
  ('school_reimbursement_items', (select count(*) from target_reimbursement_items)),
  ('school_reimbursement_expenses', (select count(*) from target_reimbursement_expenses)),
  ('school_income_records', (select count(*) from target_income_records)),
  ('school_account_adjustments', (select count(*) from target_account_adjustments)),
  ('school_account_transfers', (select count(*) from target_account_transfers)),
  ('school_monthly_reports', (select count(*) from target_monthly_reports)),
  ('school_account_transactions', (select count(*) from target_account_transactions))
) as v(table_name, target_count);

\echo target_counts
table cleanup_target_counts order by table_name;

\echo key_target_samples
select 'business_entity' as type, id::text, code as label, name as detail, null::text as amount_status
from school_business_entities where id in (select id from target_business_entities)
union all
select 'account', id::text, account_code, name, currency || ' current=' || current_balance::text || ' company=' || is_company_account::text
from school_accounts where id in (select id from target_accounts)
union all
select 'teacher', id::text, teacher_code, display_name, status
from school_teachers where id in (select id from target_teachers)
union all
select 'student', id::text, student_code, display_name, status
from school_students where id in (select id from target_students)
union all
select 'subject', id::text, name, category, is_active::text
from school_subjects where id in (select id from target_subjects)
union all
select 'wage_lock', id::text, settlement_month, teacher_name || ' / ' || business_name, status || ' total_jpy=' || total_jpy::text
from school_teacher_wage_locks where id in (select id from target_wage_locks)
union all
select 'payment_request', id::text, request_month, payee_name || ' / ' || business_name, status || ' amount=' || amount::text || ' ' || currency
from school_payment_requests where id in (select id from target_payment_requests)
union all
select 'expense', id::text, year_month, description, status || ' amount=' || amount::text || ' ' || currency
from school_expense_records where id in (select id from target_expense_records)
union all
select 'account_tx', id::text, year_month, description, amount::text || ' ' || currency || ' account=' || account_id::text
from school_account_transactions where id in (select id from target_account_transactions)
order by type, label, id
limit 80;

create temp table cleanup_unsafe(type text, id uuid, detail text) on commit drop;

insert into cleanup_unsafe
select 'target_account_transaction_on_non_target_account', tx.id,
       concat_ws(' | ', tx.year_month, tx.related_table, tx.related_id::text, tx.amount::text, tx.currency, tx.description, tx.account_id::text)
from school_account_transactions tx
join target_account_transactions ttx on ttx.id = tx.id
left join target_accounts ta on ta.id = tx.account_id
where ta.id is null;

insert into cleanup_unsafe
select 'target_expense_uses_non_target_account', e.id,
       concat_ws(' | ', e.year_month, e.status, e.amount::text, e.currency, e.description, e.account_id::text)
from school_expense_records e
join target_expense_records te on te.id = e.id
left join target_accounts ta on ta.id = e.account_id
where e.account_id is not null
  and ta.id is null;

insert into cleanup_unsafe
select 'target_income_uses_non_target_account', i.id,
       concat_ws(' | ', i.year_month, i.status, i.amount::text, i.currency, i.description, i.account_id::text)
from school_income_records i
join target_income_records ti on ti.id = i.id
left join target_accounts ta on ta.id = i.account_id
where i.account_id is not null
  and ta.id is null;

insert into cleanup_unsafe
select 'target_student_payment_uses_non_target_account', sp.id,
       concat_ws(' | ', sp.year_month, sp.status, sp.amount::text, sp.currency, sp.account_id::text)
from school_student_payments sp
join target_student_payments tsp on tsp.id = sp.id
left join target_accounts ta on ta.id = sp.account_id
where sp.account_id is not null
  and ta.id is null;

insert into cleanup_unsafe
select 'target_salary_payment_uses_non_target_account', sp.id,
       concat_ws(' | ', sp.year_month, sp.status, sp.salary_item, sp.account_id::text)
from school_salary_payments sp
join target_salary_payments tsp on tsp.id = sp.id
left join target_accounts ta on ta.id = sp.account_id
where sp.account_id is not null
  and ta.id is null;

insert into cleanup_unsafe
select 'target_reimbursement_uses_non_target_account', r.id,
       concat_ws(' | ', r.year_month, r.status, r.amount::text, r.currency, r.from_account_id::text, r.to_account_id::text)
from school_reimbursements r
join target_reimbursements tr on tr.id = r.id
left join target_accounts fa on fa.id = r.from_account_id
left join target_accounts ta on ta.id = r.to_account_id
where (r.from_account_id is not null and fa.id is null)
   or (r.to_account_id is not null and ta.id is null);

insert into cleanup_unsafe
select 'target_account_transfer_uses_non_target_account', at.id,
       concat_ws(' | ', at.year_month, at.status, at.amount::text, at.currency, at.from_account_id::text, at.to_account_id::text)
from school_account_transfers at
join target_account_transfers tat on tat.id = at.id
left join target_accounts fa on fa.id = at.from_account_id
left join target_accounts ta on ta.id = at.to_account_id
where (at.from_account_id is not null and fa.id is null)
   or (at.to_account_id is not null and ta.id is null);

insert into cleanup_unsafe
select 'target_account_adjustment_uses_non_target_account', aa.id,
       concat_ws(' | ', aa.year_month, aa.status, aa.amount::text, aa.currency, aa.account_id::text)
from school_account_adjustments aa
join target_account_adjustments taa on taa.id = aa.id
left join target_accounts ta on ta.id = aa.account_id
where aa.account_id is not null
  and ta.id is null;

insert into cleanup_unsafe
select 'non_target_lesson_child_would_be_modified', lr.id,
       concat_ws(' | ', lr.year_month, lr.lesson_type, lr.status, lr.planned_lesson_id::text)
from school_lesson_records lr
join target_lesson_records parent on parent.id = lr.planned_lesson_id
left join target_lesson_records child on child.id = lr.id
where child.id is null;

insert into cleanup_unsafe
select 'non_target_expense_references_target_salary_payment', e.id,
       concat_ws(' | ', e.year_month, e.status, e.description, e.salary_payment_id::text)
from school_expense_records e
join target_salary_payments tsp on tsp.id = e.salary_payment_id
left join target_expense_records te on te.id = e.id
where te.id is null;

insert into cleanup_unsafe
select 'non_target_income_references_target_student_payment', i.id,
       concat_ws(' | ', i.year_month, i.status, i.description, i.student_payment_id::text)
from school_income_records i
join target_student_payments tsp on tsp.id = i.student_payment_id
left join target_income_records ti on ti.id = i.id
where ti.id is null;

insert into cleanup_unsafe
select 'non_target_teacher_references_target_subject', t.id,
       concat_ws(' | ', t.teacher_code, t.display_name, t.default_subject_id::text)
from school_teachers t
join target_subjects ts on ts.id = t.default_subject_id
left join target_teachers tt on tt.id = t.id
where tt.id is null;

insert into cleanup_unsafe
select 'non_target_account_tx_fk_reference', tx.id,
       concat_ws(' | ', tx.year_month, tx.related_table, tx.related_id::text, tx.amount::text, tx.currency, tx.description)
from school_account_transactions tx
join target_account_transactions ttx on ttx.id = tx.id
where exists (
  select 1 from school_expense_records e
  left join target_expense_records te on te.id = e.id
  where te.id is null and e.reversal_account_transaction_id = tx.id
)
or exists (
  select 1 from school_income_records i
  left join target_income_records ti on ti.id = i.id
  where ti.id is null and i.reversal_account_transaction_id = tx.id
)
or exists (
  select 1 from school_reimbursements r
  left join target_reimbursements tr on tr.id = r.id
  where tr.id is null and (r.reversal_from_account_transaction_id = tx.id or r.reversal_to_account_transaction_id = tx.id)
)
or exists (
  select 1 from school_account_adjustments aa
  left join target_account_adjustments taa on taa.id = aa.id
  where taa.id is null and (aa.account_transaction_id = tx.id or aa.reversal_account_transaction_id = tx.id)
)
or exists (
  select 1 from school_account_transfers at
  left join target_account_transfers tat on tat.id = at.id
  where tat.id is null and (
    at.from_account_transaction_id = tx.id
    or at.to_account_transaction_id = tx.id
    or at.reversal_from_account_transaction_id = tx.id
    or at.reversal_to_account_transaction_id = tx.id
  )
);

\echo unsafe_findings
select type, count(*) as row_count
from cleanup_unsafe
group by type
order by type;

select *
from cleanup_unsafe
order by type, id
limit 80;

do $$
declare
  unsafe_count integer;
begin
  select count(*) into unsafe_count from cleanup_unsafe;
  if unsafe_count <> 0 then
    raise exception 'cleanup aborted: % unsafe target dependencies found', unsafe_count;
  end if;
end $$;

create temp table cleanup_delete_counts(table_name text primary key, deleted_count bigint not null default 0) on commit drop;

with deleted as (
  delete from school_import_errors e
  using target_import_batches t
  where e.import_batch_id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_import_errors', (select count(*) from deleted));

with deleted as (
  delete from school_schedule_students ss
  using target_schedule_students t
  where ss.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_schedule_students', (select count(*) from deleted));

with deleted as (
  delete from school_reimbursement_expenses re
  using target_reimbursement_expenses t
  where re.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_reimbursement_expenses', (select count(*) from deleted));

with deleted as (
  delete from school_reimbursement_items ri
  using target_reimbursement_items t
  where ri.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_reimbursement_items', (select count(*) from deleted));

with deleted as (
  delete from school_expense_attachments ea
  using target_expense_attachments t
  where ea.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_expense_attachments', (select count(*) from deleted));

with deleted as (
  delete from school_teacher_wage_detail_adjustments a
  using target_wage_detail_adjustments t
  where a.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_teacher_wage_detail_adjustments', (select count(*) from deleted));

with deleted as (
  delete from school_teacher_wage_lock_details d
  using target_wage_lock_details t
  where d.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_teacher_wage_lock_details', (select count(*) from deleted));

with deleted as (
  delete from school_student_settlement_adjustment_drafts d
  using target_student_settlement_adjustment_drafts t
  where d.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_student_settlement_adjustment_drafts', (select count(*) from deleted));

with deleted as (
  delete from school_student_settlement_adjustments a
  using target_student_settlement_adjustments t
  where a.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_student_settlement_adjustments', (select count(*) from deleted));

with deleted as (
  delete from school_student_settlement_carryovers c
  using target_student_settlement_carryovers t
  where c.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_student_settlement_carryovers', (select count(*) from deleted));

with deleted as (
  delete from school_account_adjustments aa
  using target_account_adjustments t
  where aa.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_account_adjustments', (select count(*) from deleted));

with deleted as (
  delete from school_account_transfers at
  using target_account_transfers t
  where at.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_account_transfers', (select count(*) from deleted));

with deleted as (
  delete from school_reimbursements r
  using target_reimbursements t
  where r.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_reimbursements', (select count(*) from deleted));

with deleted as (
  delete from school_payment_requests pr
  using target_payment_requests t
  where pr.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_payment_requests', (select count(*) from deleted));

with deleted as (
  delete from school_expense_records e
  using target_expense_records t
  where e.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_expense_records', (select count(*) from deleted));

with deleted as (
  delete from school_income_records i
  using target_income_records t
  where i.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_income_records', (select count(*) from deleted));

with deleted as (
  delete from school_student_payments sp
  using target_student_payments t
  where sp.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_student_payments', (select count(*) from deleted));

with deleted as (
  delete from school_salary_payments sp
  using target_salary_payments t
  where sp.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_salary_payments', (select count(*) from deleted));

with deleted as (
  delete from school_teacher_wage_locks wl
  using target_wage_locks t
  where wl.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_teacher_wage_locks', (select count(*) from deleted));

with deleted as (
  delete from school_teacher_wage_rules wr
  using target_wage_rules t
  where wr.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_teacher_wage_rules', (select count(*) from deleted));

with deleted as (
  delete from school_lesson_records lr
  using target_lesson_records t
  where lr.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_lesson_records', (select count(*) from deleted));

with deleted as (
  delete from school_actual_lessons al
  using target_actual_lessons t
  where al.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_actual_lessons', (select count(*) from deleted));

with deleted as (
  delete from school_planned_lessons pl
  using target_planned_lessons t
  where pl.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_planned_lessons', (select count(*) from deleted));

with deleted as (
  delete from school_lesson_schedules ls
  using target_lesson_schedules t
  where ls.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_lesson_schedules', (select count(*) from deleted));

with deleted as (
  delete from school_teacher_work_logs wl
  using target_teacher_work_logs t
  where wl.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_teacher_work_logs', (select count(*) from deleted));

with deleted as (
  delete from school_monthly_reports mr
  using target_monthly_reports t
  where mr.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_monthly_reports', (select count(*) from deleted));

with deleted as (
  delete from school_import_batches b
  using target_import_batches t
  where b.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_import_batches', (select count(*) from deleted));

with deleted as (
  delete from school_student_monthly_settlements sms
  using target_student_monthly_settlements t
  where sms.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_student_monthly_settlements', (select count(*) from deleted));

with deleted as (
  delete from school_student_months sm
  using target_student_months t
  where sm.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_student_months', (select count(*) from deleted));

with deleted as (
  delete from school_account_transactions tx
  using target_account_transactions t
  where tx.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_account_transactions', (select count(*) from deleted));

with deleted as (
  delete from school_accounts a
  using target_accounts t
  where a.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_accounts', (select count(*) from deleted));

with deleted as (
  delete from school_teachers t
  using target_teachers tt
  where t.id = tt.id
  returning 1
) insert into cleanup_delete_counts values ('school_teachers', (select count(*) from deleted));

with deleted as (
  delete from school_students s
  using target_students t
  where s.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_students', (select count(*) from deleted));

with deleted as (
  delete from school_subjects s
  using target_subjects t
  where s.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_subjects', (select count(*) from deleted));

with deleted as (
  delete from school_business_entities be
  using target_business_entities t
  where be.id = t.id
  returning 1
) insert into cleanup_delete_counts values ('school_business_entities', (select count(*) from deleted));

\echo delete_counts
table cleanup_delete_counts order by table_name;

\echo zero_orphan_checks_after_delete
select 'payment_requests_paid_expense_missing' as check_name, count(*) as count
from school_payment_requests pr
left join school_expense_records e on e.id = pr.paid_expense_id
where pr.paid_expense_id is not null and e.id is null
union all
select 'payment_requests_paid_tx_missing', count(*)
from school_payment_requests pr
left join school_account_transactions tx on tx.id = pr.paid_account_transaction_id
where pr.paid_account_transaction_id is not null and tx.id is null
union all
select 'expense_reversal_tx_missing', count(*)
from school_expense_records e
left join school_account_transactions tx on tx.id = e.reversal_account_transaction_id
where e.reversal_account_transaction_id is not null and tx.id is null
union all
select 'income_reversal_tx_missing', count(*)
from school_income_records i
left join school_account_transactions tx on tx.id = i.reversal_account_transaction_id
where i.reversal_account_transaction_id is not null and tx.id is null
union all
select 'wage_details_lock_missing', count(*)
from school_teacher_wage_lock_details d
left join school_teacher_wage_locks wl on wl.id = d.lock_id
where wl.id is null;

\if :cleanup_commit
commit;
\echo cleanup committed
\else
rollback;
\echo cleanup rolled back
\endif
