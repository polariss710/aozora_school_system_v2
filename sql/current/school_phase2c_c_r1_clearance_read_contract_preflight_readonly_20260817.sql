-- Phase 2C-C-R1 production preflight. Catalog and business facts are read only.
\set ON_ERROR_STOP on
\pset pager off
begin transaction read only;

do $contract$
begin
  if to_regclass('public.school_lesson_clearances') is null
     or to_regclass('public.school_lesson_clearance_details') is null then
    raise exception 'PHASE2C_C_R1_CLEARANCE_TABLES_MISSING';
  end if;
  if exists(select 1 from public.school_lesson_clearances)
     or exists(select 1 from public.school_lesson_clearance_details) then
    raise exception 'PHASE2C_C_R1_PRODUCTION_CLEARANCE_NOT_EMPTY';
  end if;
  if to_regprocedure('public.school_preview_lesson_clearance_v2(uuid,text,uuid,uuid,integer,date,text,text,text,text)') is not null
     or to_regprocedure('public.school_preview_lesson_clearance_reversal_v1(uuid,uuid,date)') is not null
     or to_regprocedure('public.school_list_lesson_clearance_history_v2(uuid)') is not null then
    raise exception 'PHASE2C_C_R1_VERSIONED_RPC_ALREADY_PRESENT';
  end if;
  if md5(pg_get_functiondef('public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)'::regprocedure))
       <> 'f3706ef036a48de97a187c5e0d4e8e40'
     or md5(pg_get_functiondef('public.school_create_lesson_clearance_core(text,uuid,uuid,integer,date,text,text,text,text,text,uuid,text)'::regprocedure))
       <> 'b378854a8756c36574e06f6cd8031397'
     or md5(pg_get_functiondef('public.school_reverse_lesson_clearance(uuid,date,text,text)'::regprocedure))
       <> '07aefc153a1b2f9f2faacbf28f29447f'
     or md5(pg_get_functiondef('public.school_reverse_lesson_clearance_core(uuid,date,text,text,uuid,text)'::regprocedure))
       <> 'b996fc53e38793ec116fde9713eea75d'
     or md5(pg_get_functiondef('public.school_preview_lesson_clearance(text,uuid,uuid,integer,date,text)'::regprocedure))
       <> '0e12c975a29f9fa70a00140f71163299'
     or md5(pg_get_functiondef('public.school_list_lesson_clearance_history(uuid)'::regprocedure))
       <> '4a48873a37a8e4ddc461eca042caa359' then
    raise exception 'PHASE2C_C_R1_EXISTING_FUNCTION_BASELINE_CHANGED';
  end if;
  if not exists(select 1 from public.school_student_package_credit_lots lot
    where lot.id='2a000000-0000-4000-8000-202608170002'
      and lot.origin_planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
      and lot.initial_minutes=1200 and lot.consumed_minutes=0 and lot.remaining_minutes=1200
      and lot.status='active'
      and md5(to_jsonb(lot)::text)='21e6453eddc240c626c0ba50eafbe72f') then
    raise exception 'PHASE2C_C_R1_P002_BASELINE_CHANGED';
  end if;
end
$contract$;

select p.oid::regprocedure signature,md5(pg_get_functiondef(p.oid)) definition_md5,
  pg_get_userbyid(p.proowner) owner,p.prosecdef security_definer,
  p.proconfig function_config,p.proacl acl
from pg_proc p
where p.oid in (
  'public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)'::regprocedure,
  'public.school_create_lesson_clearance_core(text,uuid,uuid,integer,date,text,text,text,text,text,uuid,text)'::regprocedure,
  'public.school_reverse_lesson_clearance(uuid,date,text,text)'::regprocedure,
  'public.school_reverse_lesson_clearance_core(uuid,date,text,text,uuid,text)'::regprocedure,
  'public.school_preview_lesson_clearance(text,uuid,uuid,integer,date,text)'::regprocedure,
  'public.school_list_lesson_clearance_history(uuid)'::regprocedure
)
order by p.oid::regprocedure::text;

select count(*) clearance_count from public.school_lesson_clearances;
select count(*) clearance_detail_count from public.school_lesson_clearance_details;
select lot.id,lot.origin_planned_lesson_id,lot.initial_minutes,lot.consumed_minutes,
  lot.remaining_minutes,lot.status,md5(to_jsonb(lot)::text) row_md5
from public.school_student_package_credit_lots lot
where lot.id='2a000000-0000-4000-8000-202608170002';

select pid,state,backend_xid,backend_xmin,query_start,left(query,160) query
from pg_stat_activity
where datname=current_database() and pid<>pg_backend_pid()
  and (state<>'idle' or backend_xid is not null)
order by query_start;

rollback;
