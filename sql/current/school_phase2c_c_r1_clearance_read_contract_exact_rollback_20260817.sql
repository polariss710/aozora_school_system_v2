-- Exact rollback for Phase 2C-C-R1. New versioned read-only RPCs only.
\set ON_ERROR_STOP on
\if :{?PHASE2C_C_R1_REHEARSAL}
\else
begin;
\endif

drop function if exists public.school_list_lesson_clearance_history_v2(uuid);
drop function if exists public.school_preview_lesson_clearance_reversal_v1(uuid,uuid,date);
drop function if exists public.school_preview_lesson_clearance_v2(
  uuid,text,uuid,uuid,integer,date,text,text,text,text
);

do $verify$
begin
  if to_regprocedure('public.school_preview_lesson_clearance_v2(uuid,text,uuid,uuid,integer,date,text,text,text,text)') is not null
     or to_regprocedure('public.school_preview_lesson_clearance_reversal_v1(uuid,uuid,date)') is not null
     or to_regprocedure('public.school_list_lesson_clearance_history_v2(uuid)') is not null then
    raise exception 'PHASE2C_C_R1_EXACT_ROLLBACK_INCOMPLETE';
  end if;
end
$verify$;

\if :{?PHASE2C_C_R1_REHEARSAL}
\else
commit;
\endif
