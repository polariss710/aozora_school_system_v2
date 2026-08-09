-- Full schema + RPC migration rehearsal. Entire file rolls back.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='8s';
set local statement_timeout='240s';
\ir school_historical_zero_carry_completion_schema_20260809.sql
\ir school_historical_zero_carry_completion_rpcs_20260809.sql
\ir school_historical_zero_carry_completion_postdeploy_20260809.sql

select to_regclass('public.school_student_monthly_settlement_historical_completion_evidence') is not null table_created,
  to_regprocedure('public.school_resolve_student_monthly_settlement_effective_state(uuid,text,uuid)') is not null resolver_created,
  to_regprocedure('public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)') is not null preflight_created;
rollback;
select to_regclass('public.school_student_monthly_settlement_historical_completion_evidence') is null rehearsal_rolled_back;
