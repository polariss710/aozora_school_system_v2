-- Exact rollback for Phase 2C-D2-A2. V2 and all business rows remain unchanged.
\set ON_ERROR_STOP on

\if :{?PHASE2C_D2_A2_ROLLBACK_IN_EXISTING_TRANSACTION}
\else
begin;
\endif

drop function if exists
  public.school_list_lesson_clearance_pending_balances_v3(uuid,boolean);

do $verify$
begin
  if to_regprocedure(
      'public.school_list_lesson_clearance_pending_balances_v3(uuid,boolean)'
    ) is not null then
    raise exception 'PHASE2C_D2_A2_EXACT_ROLLBACK_OBJECT_REMAINS';
  end if;
end
$verify$;

\if :{?PHASE2C_D2_A2_SKIP_PRODUCTION_MD5}
\else
do $dependency_md5$
begin
  if md5(pg_get_functiondef(
      'public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean)'::regprocedure
    ))<>'94dcc95f7c64325e77ea5fa326dc5d05' then
    raise exception 'PHASE2C_D2_A2_EXACT_ROLLBACK_V2_DRIFT';
  end if;
end
$dependency_md5$;
\endif

\if :{?PHASE2C_D2_A2_ROLLBACK_IN_EXISTING_TRANSACTION}
\else
commit;
\endif
