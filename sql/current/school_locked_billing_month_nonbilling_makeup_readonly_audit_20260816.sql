-- Repeatable read-only baseline/postdeploy/post-correction audit.
\set ON_ERROR_STOP on
\pset pager off
begin transaction isolation level repeatable read read only;

select p.oid::regprocedure signature,md5(pg_get_functiondef(p.oid)) definition_md5,
       pg_get_userbyid(p.proowner) owner,p.prosecdef,
       coalesce(array_to_string(p.proconfig,','),'') settings,
       coalesce(array_to_string(p.proacl,','),'') acl
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'school_create_lesson_credit_makeup_actual',
  'school_create_cancelled_actual_lesson_from_planned',
  'school_enforce_r1d_e_b2_actual_attribution',
  'school_correct_sun_chenfeng_20260811_makeup_v1'
) order by p.oid::regprocedure::text;

select l.id,l.lesson_type,l.lesson_date,l.start_time,l.end_time,l.duration_hours,
       l.status,l.is_billable,l.lesson_fee,l.actual_minutes,l.student_settlement_month,
       l.teacher_settlement_month,l.planned_lesson_id,l.voided_at,l.void_reason,
       l.updated_at,md5(to_jsonb(l)::text) row_md5
from public.school_lesson_records l
where l.id in (
  '8b737b58-cd14-42c5-afd2-34730dcef963'::uuid,
  'c8e6cf21-850c-4700-af9e-7ebf3c2a577d'::uuid,
  '6722e5a8-d7a1-453a-93a8-9cbaab227378'::uuid
) or l.planned_lesson_id='8b737b58-cd14-42c5-afd2-34730dcef963'::uuid
order by l.lesson_date,l.lesson_type,l.id;

select 'target_remaining' object_name,
       public.school_get_lesson_credit_remaining_hours('8b737b58-cd14-42c5-afd2-34730dcef963'::uuid)::text value
union all select 'excluded_20260706_remaining',
       public.school_get_lesson_credit_remaining_hours('6722e5a8-d7a1-453a-93a8-9cbaab227378'::uuid)::text;

select c.lesson_record_id,c.lesson_date,c.actual_minutes,c.lesson_wage_jpy,
       c.wage_rule_id,c.student_settlement_month
from public.school_get_teacher_monthly_wage_generation_candidate_facts(
  '2026-08','edaf30da-1315-4455-99d1-ead1b7147662'::uuid,
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
) c order by c.lesson_record_id;

select 'target_settlement' object_name,count(*) row_count,
       max(md5(to_jsonb(x)::text)) row_hash
from public.school_student_monthly_settlements x
where x.id='5e0a23ff-0e1e-48c6-9866-5fc335b3e42d'::uuid
union all select 'target_bill',count(*),max(md5(to_jsonb(x)::text))
from public.school_student_tuition_bills x where x.id='2a9f1c25-a060-461e-ae10-b02295dec381'::uuid
union all select 'target_bill_lesson',count(*),max(md5(to_jsonb(x)::text))
from public.school_student_tuition_bill_lessons x where x.id='ac2caa48-aaeb-c039-19ac-3b3779beb3bf'::uuid
union all select 'target_revision',count(*),max(md5(to_jsonb(x)::text))
from public.school_student_tuition_generation_revisions x where x.id='96000000-0000-4000-8000-202608031005'::uuid
union all select 'target_income',count(*),max(md5(to_jsonb(x)::text))
from public.school_income_records x where x.id='468ab75b-312e-4ba0-8d8d-8ae2f6ace00e'::uuid
union all select 'target_cash_linkage',count(*),max(md5(to_jsonb(x)::text))
from public.school_personal_cash_income_linkage_events x where x.id='43256fb6-3f6e-41f7-9802-1d1c42a3f2c5'::uuid;

select object_name,row_count,row_hash from (
  select 1 sort_order,'lessons_all' object_name,count(*) row_count,
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
  from public.school_lesson_records x
  union all select 2,'lessons_outside_target_chain',count(*),
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.school_lesson_records x
  where x.id<>'8b737b58-cd14-42c5-afd2-34730dcef963'::uuid
    and x.planned_lesson_id is distinct from '8b737b58-cd14-42c5-afd2-34730dcef963'::uuid
  union all select 3,'settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_monthly_settlements x
  union all select 4,'bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bills x
  union all select 5,'bill_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bill_lessons x
  union all select 6,'revisions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_generation_revisions x
  union all select 7,'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_income_records x
  union all select 8,'cash_linkages',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_personal_cash_income_linkage_events x
  union all select 9,'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_locks x
  union all select 10,'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_lock_details x
  union all select 11,'correction_events',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_lesson_exact_correction_events x
  union all select 12,'feature_gates',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.feature_key),'')) from public.school_feature_gates x
  union all select 13,'storage_objects',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from storage.objects x
) f order by sort_order;

select count(*) open_related_transactions
from pg_stat_activity a where a.datname=current_database() and a.pid<>pg_backend_pid()
  and a.xact_start is not null and a.state<>'idle'
  and (a.query ilike '%school_lesson_records%' or a.query ilike '%school_student_monthly_settlements%');

select 'SCHOOL_LOCKED_BILLING_MONTH_NONBILLING_MAKEUP_READONLY_AUDIT_PASS' result;
rollback;
