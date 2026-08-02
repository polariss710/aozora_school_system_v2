-- School V2 tuition finance P0-A gate alignment, 2026-08-03.
-- Required psql variable: p0a_gate_commit=0 for rehearsal, 1 for authorized commit.
-- This changes only the two tuition write gates. It never writes business rows.
\set ON_ERROR_STOP on
\pset pager off

\if :{?p0a_gate_commit}
\else
  \echo 'P0A_GATE_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';

do $preflight$
begin
  if (select count(*) from public.school_feature_gates
      where (feature_key = 'student_tuition_preview' and state = 'enabled')
         or (feature_key = 'student_tuition_generate' and state = 'enabled')
         or (feature_key = 'student_tuition_cash_submit' and state = 'enabled')) <> 3 then
    raise exception 'TUITION_P0A_GATE_BASELINE_DRIFT';
  end if;
end
$preflight$;

update public.school_feature_gates
set state = 'blocked',
    reason = 'P0-A安全收口期间停止学费正式生成；preview继续只读开放。',
    release_version = 'tuition-p0a-write-freeze-20260803',
    evidence_hash = 'tuition-p0a-consumed-settlement-rpc-only',
    updated_at = statement_timestamp(),
    updated_by = current_user
where feature_key = 'student_tuition_generate'
  and state = 'enabled';

update public.school_feature_gates
set state = 'blocked',
    reason = 'P0-A至后续全量复审完成前停止学费Cash提交；既有Cash事实不变。',
    release_version = 'tuition-p0a-write-freeze-20260803',
    evidence_hash = 'tuition-p0a-consumed-settlement-rpc-only',
    updated_at = statement_timestamp(),
    updated_by = current_user
where feature_key = 'student_tuition_cash_submit'
  and state = 'enabled';

do $verify$
begin
  if (select count(*) from public.school_feature_gates
      where (feature_key = 'student_tuition_preview' and state = 'enabled')
         or (feature_key = 'student_tuition_generate' and state = 'blocked')
         or (feature_key = 'student_tuition_cash_submit' and state = 'blocked')) <> 3 then
    raise exception 'TUITION_P0A_GATE_ALIGNMENT_FAILED';
  end if;
end
$verify$;

select feature_key, state, release_version
from public.school_feature_gates
where feature_key in (
  'student_tuition_preview',
  'student_tuition_generate',
  'student_tuition_cash_submit'
)
order by feature_key;

\if :p0a_gate_commit
  commit;
  \echo 'TUITION_P0A_GATE_ALIGNMENT_COMMITTED'
\else
  rollback;
  \echo 'TUITION_P0A_GATE_ALIGNMENT_REHEARSAL_ROLLED_BACK'
\endif
