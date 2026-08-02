-- School V2 tuition Cash submit emergency disable, 2026-08-02.
-- Idempotently blocks only new tuition Cash submissions. It never deletes or
-- rewrites existing linkage, request, transaction, income or bill records.
\set ON_ERROR_STOP on
\pset pager off
\if :{?tuition_cash_disable_commit}
\else
  \echo 'TUITION_CASH_DISABLE_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';

update public.school_feature_gates
set state = 'blocked',
    reason = '学费Cash紧急停用：仅阻断新提交，既有Cash请求由运营人员明确处理。',
    release_version = 'tuition-cash-emergency-disabled-20260802',
    updated_at = statement_timestamp(),
    updated_by = current_user
where feature_key = 'student_tuition_cash_submit'
  and state is distinct from 'blocked';

do $verify$
begin
  if (select count(*) from public.school_feature_gates
      where (feature_key = 'student_tuition_preview' and state = 'enabled')
         or (feature_key = 'student_tuition_generate' and state = 'enabled')
         or (feature_key = 'student_tuition_cash_submit' and state = 'blocked')) <> 3 then
    raise exception 'TUITION_CASH_EMERGENCY_DISABLE_FAILED';
  end if;
end
$verify$;

\if :tuition_cash_disable_commit
  commit;
\else
  rollback;
\endif
