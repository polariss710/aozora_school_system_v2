-- School V2 Phase 2C-C production preflight. SELECT/DO assertions only.
\set ON_ERROR_STOP on
\pset pager off
begin transaction read only;

do $contract$
begin
  if to_regclass('public.school_lesson_clearances') is not null
     or to_regclass('public.school_lesson_clearance_details') is not null
     or to_regprocedure('public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)') is not null then
    raise exception 'PHASE2C_C_CLEARANCE_OBJECT_ALREADY_PRESENT';
  end if;
  if to_regclass('public.school_student_package_credit_lots') is null
     or to_regprocedure('public.school_is_active_package_credit_origin(uuid)') is null
     or to_regprocedure('public.school_list_student_package_credit_lots(uuid)') is null then
    raise exception 'PHASE2C_C_PHASE2I_A_PACKAGE_CONTRACT_MISSING';
  end if;
  if not exists(select 1 from public.school_student_package_credit_lots
    where id='2a000000-0000-4000-8000-202608170002'
      and origin_planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
      and initial_minutes=1200 and consumed_minutes=0 and remaining_minutes=1200
      and unit_price_jpy=13000 and total_price_jpy=260000
      and student_billing_month='2026-07' and status='active') then
    raise exception 'PHASE2C_C_P002_BASELINE_MISMATCH';
  end if;
  if md5(pg_get_functiondef('public.school_get_lesson_credit_raw_remaining_hours(uuid)'::regprocedure))<>'63dc342b8eeefd4f65732bbda95e91bc'
     or md5(pg_get_functiondef('public.school_get_lesson_credit_remaining_hours(uuid)'::regprocedure))<>'fc179172c6d1eda1bcf1662604aad3d7'
     or md5(pg_get_functiondef('public.school_list_student_lesson_credit_balances(uuid)'::regprocedure))<>'5290639714c0aba6967d41d014711d0a'
     or md5(pg_get_functiondef('public.school_list_open_lesson_credit_sources(text,text,text)'::regprocedure))<>'564a2ac0532af748f52be2945e76aae5'
     or md5(pg_get_functiondef('public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)'::regprocedure))<>'ab1db690c2736dfadab474e3951e2118' then
    raise exception 'PHASE2C_C_PHASE2I_A_FUNCTION_BASELINE_CHANGED';
  end if;
end
$contract$;

select object_name,row_count,row_hash from (
  select 1 sort_order,'lessons' object_name,count(*) row_count,
    md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
  from public.school_lesson_records x
  union all select 2,'settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_monthly_settlements x
  union all select 3,'claims',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_settlement_lesson_variance_claims x
  union all select 4,'bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bills x
  union all select 5,'bill_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bill_lessons x
  union all select 6,'revisions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_generation_revisions x
  union all select 7,'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_income_records x
  union all select 8,'cash_linkages',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_personal_cash_income_linkage_events x
  union all select 9,'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_locks x
  union all select 10,'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_lock_details x
  union all select 11,'package_lots',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_package_credit_lots x
  union all select 12,'storage',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from storage.objects x
  union all select 13,'feature_gates',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.feature_key),'')) from public.school_feature_gates x
) fingerprint order by sort_order;

with pending as (
  select lesson.id,public.school_get_lesson_credit_raw_remaining_hours(lesson.id) remaining_hours
  from public.school_lesson_records lesson
  where lesson.app_type='school' and lesson.lesson_type='planned'
    and lesson.status='pending_makeup' and lesson.voided_at is null
    and not public.school_is_active_package_credit_origin(lesson.id)
    and not exists(select 1 from public.school_student_settlement_lesson_variance_claims claim
      where claim.claim_status='active' and claim.source_type='unused_planned_credit_v1'
        and claim.source_planned_lesson_id=lesson.id)
), overage as (
  select lesson.id,lesson.student_duration_overage_minutes remaining_minutes
  from public.school_lesson_records lesson
  where lesson.app_type='school' and lesson.lesson_type='actual'
    and lesson.status='completed' and lesson.is_billable is true and lesson.voided_at is null
    and lesson.student_duration_overage_policy_version='student_duration_overage_v1'
    and lesson.student_duration_overage_source='ordinary_actual_rpc'
    and lesson.student_duration_overage_minutes>0 and lesson.student_duration_overage_fee_jpy>0
    and not exists(select 1 from public.school_student_settlement_lesson_variance_claims claim
      where claim.claim_status='active' and claim.source_type='actual_duration_overage_charge_v1'
        and claim.source_actual_lesson_id=lesson.id)
)
select 'pending_available' object_name,count(*) filter(where remaining_hours>0) row_count,
  coalesce(sum(remaining_hours) filter(where remaining_hours>0),0) balance,
  md5(coalesce(string_agg(id::text||':'||remaining_hours::text,'|' order by id),'')) manifest
from pending
union all
select 'overage_available',count(*) filter(where remaining_minutes>0),
  coalesce(sum(remaining_minutes) filter(where remaining_minutes>0),0),
  md5(coalesce(string_agg(id::text||':'||remaining_minutes::text,'|' order by id),''))
from overage;

select pid,state,backend_xid,backend_xmin,query_start,left(query,160) query
from pg_stat_activity
where datname=current_database() and pid<>pg_backend_pid()
  and (state<>'idle' or backend_xid is not null)
order by query_start;

select p.oid::regprocedure signature,md5(pg_get_functiondef(p.oid)) definition_md5,
  pg_get_userbyid(p.proowner) owner,p.prosecdef,p.proconfig,p.proacl
from pg_proc p
where p.oid in (
  'public.school_get_lesson_credit_raw_remaining_hours(uuid)'::regprocedure,
  'public.school_get_lesson_credit_remaining_hours(uuid)'::regprocedure,
  'public.school_list_student_lesson_credit_balances(uuid)'::regprocedure,
  'public.school_list_open_lesson_credit_sources(text,text,text)'::regprocedure,
  'public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)'::regprocedure
) order by 1;

rollback;
