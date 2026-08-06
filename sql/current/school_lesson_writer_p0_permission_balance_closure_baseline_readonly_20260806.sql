-- School V2 lesson writer P0 production baseline/reconciliation. SELECT only.
\set ON_ERROR_STOP on
\pset pager off

begin transaction isolation level repeatable read read only;

select object_name,row_count,row_hash
from (
  select 1 sort_order,'lessons' object_name,count(*) row_count,
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
  from public.school_lesson_records x
  union all select 2,'settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.school_student_monthly_settlements x
  union all select 3,'tuition_bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.school_student_tuition_bills x
  union all select 4,'tuition_bill_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.school_student_tuition_bill_lessons x
  union all select 5,'tuition_revisions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.school_student_tuition_generation_revisions x
  union all select 6,'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.school_income_records x
  union all select 7,'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.school_teacher_wage_locks x
  union all select 8,'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.school_teacher_wage_lock_details x
  union all select 9,'claims',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.school_student_settlement_lesson_variance_claims x
  union all select 10,'school_cash_linkage',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
  from public.school_personal_cash_linkage_events x
) fingerprints
order by sort_order;

select 'li_tianlun_four' object_name,count(*) row_count,
  md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
from public.school_lesson_records x
where x.id in (
  'f759623b-ce28-4c5f-8556-95c4381b6b1b',
  'dc06b98c-360f-4661-a294-52ecb82830a7',
  'c582a187-32f6-4a24-bb7b-d590b25c1854',
  '39aa30ab-d66c-43c0-bbde-3b3a35d71fb7'
)
union all
select 'peng_yuhan_cancellation_chain',count(*),
  md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_lesson_records x
where x.id='1a370095-dd14-444f-8ffb-778e92e03c88'
   or x.planned_lesson_id='1a370095-dd14-444f-8ffb-778e92e03c88'
union all
select 'chen_hongzhuo_cross_month_chain',count(*),
  md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_lesson_records x
where x.id in (
  'd4e3e060-1951-4fdd-9340-e6feb6687b7f',
  'e28d255d-4f6b-45e4-9766-d8d16f97d37b',
  'd1c60932-0f8a-43e3-98b8-bb362921ccf8',
  '9d26220e-813a-43da-b48d-1e34cfa9324e'
)
order by object_name;

select 'legacy_fee_anomalies' object_name,count(*) row_count,
  md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
from public.school_lesson_records x
where x.app_type='school' and x.lesson_type='actual'
  and (
    (x.status in ('cancelled','makeup_completed')
      and (x.is_billable is distinct from false or coalesce(x.lesson_fee,0)<>0))
    or (x.status='completed' and x.is_billable is false and coalesce(x.lesson_fee,0)<>0)
  );

with credit as (
  select p.id,p.status,p.duration_hours entitlement,
    coalesce(sum(a.duration_hours) filter(
      where a.app_type='school' and a.lesson_type='actual'
        and a.status in ('completed','makeup_completed') and a.voided_at is null
    ),0) consumed
  from public.school_lesson_records p
  left join public.school_lesson_records a on a.planned_lesson_id=p.id
  where p.app_type='school' and p.lesson_type='planned'
  group by p.id,p.status,p.duration_hours
)
select 'raw_negative_sources' object_name,
  count(*) filter(where entitlement-consumed<0) row_count,
  md5(coalesce(string_agg(md5(to_jsonb(credit)::text),'' order by id)
    filter(where entitlement-consumed<0),'')) row_hash
from credit
union all
select 'zero_balance_pending_makeup',
  count(*) filter(where status='pending_makeup' and entitlement-consumed=0),
  md5(coalesce(string_agg(md5(to_jsonb(credit)::text),'' order by id)
    filter(where status='pending_makeup' and entitlement-consumed=0),''))
from credit
order by object_name;

select p.oid::regprocedure::text signature,pg_get_userbyid(p.proowner) owner,
  p.prosecdef security_definer,p.proconfig,p.proacl,
  md5(pg_get_functiondef(p.oid)) definition_md5
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.oid in (
  'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure,
  'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure,
  'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure,
  'public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure,
  'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer)'::regprocedure,
  'public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,
  'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure,
  'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text,integer)'::regprocedure,
  'public.school_void_planned_lesson(uuid,timestamp with time zone,text)'::regprocedure,
  'public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean)'::regprocedure
)
order by signature;

select c.relname,c.relrowsecurity,c.relforcerowsecurity,c.relacl
from pg_class c where c.oid='public.school_lesson_records'::regclass;
select policyname,roles,cmd,qual,with_check
from pg_policies where schemaname='public' and tablename='school_lesson_records'
order by policyname;
select t.tgname,t.tgenabled,pg_get_triggerdef(t.oid),
  md5(pg_get_functiondef(t.tgfoid)) trigger_function_md5
from pg_trigger t
where t.tgrelid='public.school_lesson_records'::regclass and not t.tgisinternal
order by t.tgname;
select feature_key,state,updated_at from public.school_feature_gates
where feature_key in ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit')
order by feature_key;
select count(*) fixture_residue from (
  select id from auth.users where left(id::text,9) in ('be100000-','be110000-','be120000-')
  union all select user_id from public.school_app_memberships
    where left(user_id::text,9) in ('be100000-','be110000-','be120000-')
  union all select id from public.school_lesson_records
    where left(id::text,9) in ('be100000-','be110000-','be120000-')
       or left(coalesce(planned_lesson_id::text,''),9) in ('be100000-','be110000-','be120000-')
  union all select id from public.school_students
    where left(id::text,9) in ('be100000-','be110000-','be120000-')
  union all select id from public.school_teachers
    where left(id::text,9) in ('be100000-','be110000-','be120000-')
  union all select id from public.school_subjects
    where left(id::text,9) in ('be100000-','be110000-','be120000-')
) residue;
select 'LESSON_WRITER_P0_BASELINE_READONLY_PASS' result;
rollback;
