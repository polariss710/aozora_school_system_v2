-- Phase 3C2-R final cutover. Execute only after both Edge deployments and zero legacy drift.
\set ON_ERROR_STOP on
\pset pager off

begin;
lock table public.school_feature_gates in row exclusive mode;

do $gate_precheck$
begin
  if (select state from public.school_feature_gates where feature_key='cash_fixed_credit_card_route_enabled') <> 'blocked' then
    raise exception using errcode='55000', message='PHASE3C2R_FIXED_GATE_NOT_BLOCKED';
  end if;
  if (select state from public.school_feature_gates where feature_key='cash_expense_attempt_writer_v2_enabled') <> 'blocked' then
    raise exception using errcode='55000', message='PHASE3C2R_V2_GATE_NOT_BLOCKED';
  end if;
  if (select count(*) from public.school_expense_cash_attempts where payment_route='fixed_credit_card') <> 0 then
    raise exception using errcode='55000', message='PHASE3C2R_FIXED_ATTEMPT_EXISTS';
  end if;
  if (select count(*) from public.school_expense_cash_attempts) <> 24 then
    raise exception using errcode='55000', message='PHASE3C2R_ATTEMPT_COUNT_DRIFT';
  end if;
end;
$gate_precheck$;

update public.school_feature_gates
set state='enabled',
    reason='Phase 3C2-R School immediate-account attempt V2 writer active; legacy expense Cash RPC signatures fail closed.',
    release_version='phase-3c2r-20260819',
    evidence_hash='phase3c2r-db-edge-cutover-verified',
    updated_at=now(),
    updated_by=current_user
where feature_key='cash_expense_attempt_writer_v2_enabled'
  and state='blocked';

do $gate_postcheck$
begin
  if (select state from public.school_feature_gates where feature_key='cash_expense_attempt_writer_v2_enabled') <> 'enabled'
     or (select state from public.school_feature_gates where feature_key='cash_fixed_credit_card_route_enabled') <> 'blocked' then
    raise exception using errcode='55000', message='PHASE3C2R_GATE_ENABLE_FAILED';
  end if;
end;
$gate_postcheck$;
commit;
