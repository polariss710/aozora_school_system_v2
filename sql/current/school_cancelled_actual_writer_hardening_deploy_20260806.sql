-- School V2 cancellation writer hardening formal deployment/rehearsal.
-- Use -v cancellation_writer_commit=0 for rollback rehearsal and 1 for deploy.
\set ON_ERROR_STOP on
\pset pager off
\if :{?cancellation_writer_commit}
\else
  \set cancellation_writer_commit 0
\endif

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';

do $preflight$
declare
  v_writer regprocedure :=
    'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure;
begin
  if md5(pg_get_functiondef(v_writer)) <> 'fcbb8a4c48cf62c285de45238b219e43' then
    raise exception 'CANCELLATION_WRITER_BASELINE_DRIFT';
  end if;
  if md5(pg_get_functiondef(
       'public.school_tuition_p0a_consumed_bill_id(uuid)'::regprocedure
     )) <> 'a843f2b80421543511a70e6d671da560' then
    raise exception 'CANCELLATION_WRITER_RULE_B_HELPER_DRIFT';
  end if;
  if md5(pg_get_functiondef(
       'public.school_tuition_p0b1_lock_existing_lesson_scope(uuid,uuid,uuid,date)'::regprocedure
     )) <> '86a8cd7e2a69eac97a65929bf29dec91' then
    raise exception 'CANCELLATION_WRITER_SCOPE_LOCK_DRIFT';
  end if;
  if to_regclass('public.school_app_memberships') is null
     or to_regprocedure('public.school_tuition_p0f_guard_claimed_lesson_source()') is null
     or pg_get_userbyid((select proowner from pg_proc where oid=v_writer)) <> 'postgres'
     or not (select prosecdef from pg_proc where oid=v_writer)
     or (select proconfig from pg_proc where oid=v_writer)
        <> '{"search_path=pg_catalog, public"}'::text[] then
    raise exception 'CANCELLATION_WRITER_SECURITY_BASELINE_INVALID';
  end if;
end;
$preflight$;

create temporary table cancellation_writer_business_baseline(
  object_name text primary key,
  row_count bigint not null,
  full_hash text not null
) on commit drop;

insert into cancellation_writer_business_baseline
select 'lesson',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_lesson_records t
union all select 'settlement',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_student_monthly_settlements t
union all select 'bill',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_student_tuition_bills t
union all select 'bill_lesson',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_student_tuition_bill_lessons t
union all select 'generation_identity',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_student_tuition_generation_identities t
union all select 'generation_revision',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_student_tuition_generation_revisions t
union all select 'wage_lock',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_teacher_wage_locks t
union all select 'wage_detail',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_teacher_wage_lock_details t
union all select 'variance_claim',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_student_settlement_lesson_variance_claims t;

\ir school_create_cancelled_actual_lesson_from_planned_rpc.sql

do $verify$
declare
  v_writer regprocedure :=
    'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure;
  v_definition text := pg_get_functiondef(
    'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure
  );
begin
  if pg_get_userbyid((select proowner from pg_proc where oid=v_writer)) <> 'postgres'
     or not (select prosecdef from pg_proc where oid=v_writer)
     or (select proconfig from pg_proc where oid=v_writer)
        <> '{"search_path=pg_catalog, public"}'::text[]
     or not has_function_privilege('authenticated',v_writer,'EXECUTE')
     or has_function_privilege('public',v_writer,'EXECUTE')
     or has_function_privilege('anon',v_writer,'EXECUTE')
     or has_function_privilege('service_role',v_writer,'EXECUTE') then
    raise exception 'CANCELLATION_WRITER_DEPLOY_ACL_INVALID';
  end if;
  if position('v_actor uuid := auth.uid()' in v_definition)=0
     or position($needle$v_membership_role not in ('admin','operator')$needle$ in v_definition)=0
     or position('school_tuition_p0a_consumed_bill_id(settlement.id)' in v_definition)=0
     or position($needle$message='LESSON_FINANCIAL_FACT_IMMUTABLE'$needle$ in v_definition)=0
     or position('extract(epoch from (v_end_value - v_start_value))' in v_definition)=0
     or position($needle$v_planned.status <> 'planned'$needle$ in v_definition)=0 then
    raise exception 'CANCELLATION_WRITER_DEPLOY_DEFINITION_INVALID';
  end if;

  if exists (
    select 1
    from cancellation_writer_business_baseline before_rows
    full join (
      select 'lesson' object_name,count(*) row_count,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) full_hash from public.school_lesson_records t
      union all select 'settlement',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_monthly_settlements t
      union all select 'bill',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bills t
      union all select 'bill_lesson',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bill_lessons t
      union all select 'generation_identity',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_generation_identities t
      union all select 'generation_revision',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_generation_revisions t
      union all select 'wage_lock',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_teacher_wage_locks t
      union all select 'wage_detail',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_teacher_wage_lock_details t
      union all select 'variance_claim',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_lesson_variance_claims t
    ) after_rows using(object_name)
    where before_rows.row_count is distinct from after_rows.row_count
       or before_rows.full_hash is distinct from after_rows.full_hash
  ) then
    raise exception 'CANCELLATION_WRITER_DEPLOY_CHANGED_BUSINESS_DATA';
  end if;
end;
$verify$;

select md5(pg_get_functiondef(
  'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure
)) deployed_definition_md5;

\if :cancellation_writer_commit
  commit;
  \echo 'CANCELLATION_WRITER_HARDENING_COMMIT'
\else
  rollback;
  \echo 'CANCELLATION_WRITER_HARDENING_REHEARSAL_ROLLBACK'
\endif
