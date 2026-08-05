-- School V2 cancellation writer hardening read-only postdeploy.
\set ON_ERROR_STOP on
\pset pager off

do $postdeploy$
declare
  v_writer regprocedure :=
    'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure;
  v_definition text := pg_get_functiondef(
    'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure
  );
begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public'
        and p.proname='school_create_cancelled_actual_lesson_from_planned') <> 1 then
    raise exception 'CANCELLATION_WRITER_POSTDEPLOY_OVERLOAD_DRIFT';
  end if;
  if md5(v_definition) <> 'e1d7414424dada7e1a77c0130c67d159'
     or pg_get_userbyid((select proowner from pg_proc where oid=v_writer)) <> 'postgres'
     or not (select prosecdef from pg_proc where oid=v_writer)
     or (select proconfig from pg_proc where oid=v_writer)
        <> '{"search_path=pg_catalog, public"}'::text[] then
    raise exception 'CANCELLATION_WRITER_POSTDEPLOY_DEFINITION_INVALID';
  end if;
  if not has_function_privilege('authenticated',v_writer,'EXECUTE')
     or has_function_privilege('public',v_writer,'EXECUTE')
     or has_function_privilege('anon',v_writer,'EXECUTE')
     or has_function_privilege('service_role',v_writer,'EXECUTE') then
    raise exception 'CANCELLATION_WRITER_POSTDEPLOY_ACL_INVALID';
  end if;
  if position('v_actor uuid := auth.uid()' in v_definition)=0
     or position($needle$v_membership_role not in ('admin','operator')$needle$ in v_definition)=0
     or position('school_tuition_p0b1_lock_existing_lesson_scope' in v_definition)=0
     or position('for update' in lower(v_definition))=0
     or position('school_tuition_p0a_consumed_bill_id(settlement.id)' in v_definition)=0
     or position($needle$message='LESSON_FINANCIAL_FACT_IMMUTABLE'$needle$ in v_definition)=0
     or position($needle$v_planned.status <> 'planned'$needle$ in v_definition)=0
     or position('extract(epoch from (v_end_value - v_start_value))' in v_definition)=0
     or position('actual_minutes, teacher_settlement_month' in v_definition)=0 then
    raise exception 'CANCELLATION_WRITER_POSTDEPLOY_CONTRACT_MISSING';
  end if;
  if position($needle$coalesce(student.status, 'active') not in ('inactive', 'graduated')$needle$
       in lower(v_definition))>0 then
    raise exception 'CANCELLATION_WRITER_POSTDEPLOY_LEGACY_STATUS_PREDICATE';
  end if;
  if md5(pg_get_functiondef(
       'public.school_tuition_p0a_consumed_bill_id(uuid)'::regprocedure
     )) <> 'a843f2b80421543511a70e6d671da560'
     or position('school_student_tuition_generation_revisions' in pg_get_functiondef(
       'public.school_tuition_p0a_consumed_bill_id(uuid)'::regprocedure
     ))=0 then
    raise exception 'CANCELLATION_WRITER_POSTDEPLOY_RULE_B_INVALID';
  end if;
  if not exists (
    select 1 from pg_trigger
    where tgrelid='public.school_lesson_records'::regclass
      and tgname='school_tuition_p0f_claimed_lesson_source_guard'
      and tgenabled='O'
  ) or not exists (
    select 1 from pg_trigger
    where tgrelid='public.school_lesson_records'::regclass
      and tgname='trg_school_lesson_p0b1_financial_authority'
      and tgenabled='O'
  ) or not exists (
    select 1 from pg_trigger
    where tgrelid='public.school_lesson_records'::regclass
      and tgname='trg_school_lesson_actual_minutes_sync'
      and tgenabled='O'
  ) then
    raise exception 'CANCELLATION_WRITER_POSTDEPLOY_TRIGGER_INVALID';
  end if;
  if position($needle$status in ('completed', 'makeup_completed')$needle$ in lower(pg_get_functiondef(
       'public.school_generate_teacher_monthly_wage(text,uuid,uuid)'::regprocedure
     )))=0 then
    raise exception 'CANCELLATION_WRITER_POSTDEPLOY_WAGE_FILTER_INVALID';
  end if;
  if exists (select 1 from auth.users where id::text like 'c6080000-%')
     or exists (select 1 from public.school_lesson_records where id::text like 'c6080000-%')
     or exists (select 1 from public.school_students where id::text like 'c6080000-%') then
    raise exception 'CANCELLATION_WRITER_POSTDEPLOY_FIXTURE_RESIDUE';
  end if;
end;
$postdeploy$;

select p.oid::regprocedure signature,
       md5(pg_get_functiondef(p.oid)) definition_md5,
       pg_get_userbyid(p.proowner) owner,
       p.prosecdef security_definer,
       p.proconfig,
       has_function_privilege('public',p.oid,'EXECUTE') public_execute,
       has_function_privilege('anon',p.oid,'EXECUTE') anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') service_execute
from pg_proc p
where p.oid=
  'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure;

select 'CANCELLATION_WRITER_HARDENING_POSTDEPLOY_PASS' result;
