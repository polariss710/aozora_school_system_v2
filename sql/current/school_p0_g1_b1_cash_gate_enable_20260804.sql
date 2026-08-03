-- P0-G1-B1 controlled Cash Gate enable. The only persistent write is one Gate row.
\set ON_ERROR_STOP on
\pset pager off

\if :{?p0_g1_b1_gate_commit}
\else
  \echo 'P0_G1_B1_GATE_COMMIT_REQUIRED'
  \quit
\endif

begin;
set local lock_timeout='10s';
set local statement_timeout='120s';

do $enable$
declare
  v_target public.school_feature_gates%rowtype;
  v_case record;
  v_rows integer;
begin
  select * into strict v_target
  from public.school_feature_gates
  where feature_key='student_tuition_cash_submit'
  for update;

  if v_target.state<>'blocked'
     or v_target.reason<>'P0-A至后续全量复审完成前停止学费Cash提交；既有Cash事实不变。'
     or v_target.release_version<>'tuition-p0a-write-freeze-20260803'
     or v_target.evidence_hash<>'tuition-p0a-consumed-settlement-rpc-only'
     or (select state from public.school_feature_gates where feature_key='student_tuition_preview')<>'enabled'
     or (select state from public.school_feature_gates where feature_key='student_tuition_generate')<>'blocked' then
    raise exception 'P0G1B1_GATE_BASELINE_DRIFT';
  end if;

  if md5(pg_get_functiondef(
       'public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure
     ))<>'95a68598215b61f55e5b63c74eeaa3f1'
     or has_function_privilege('anon','public.school_require_current_app_admin()','EXECUTE')
     or not has_function_privilege('authenticated','public.school_require_current_app_admin()','EXECUTE')
     or has_function_privilege('service_role','public.school_require_current_app_admin()','EXECUTE')
     or has_function_privilege('anon','public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)','EXECUTE')
     or has_function_privilege('authenticated','public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)','EXECUTE')
     or not has_function_privilege('service_role','public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)','EXECUTE') then
    raise exception 'P0G1B1_GATE_FUNCTION_OR_ACL_DRIFT';
  end if;

  for v_case in select * from (values
    ('7d319b0d-8f62-41e9-95bf-c1a0c6ed7090'::uuid,'013a7766-101b-4b5b-bcae-c008825b14fa'::uuid,'d980cedd-ebba-4be1-afcb-b25dfa26798a'::uuid,27950.00::numeric),
    ('f7bbd000-9753-4f00-9d3a-d8705ee8d5e9'::uuid,'a5cac133-36ee-4324-9c67-f95eadf62200'::uuid,'648e264d-3435-43f1-a797-cf1394011f65'::uuid,8147.25::numeric),
    ('f7150ce5-fb77-4b7f-99f8-207bfbbced91'::uuid,'66a1f276-2756-466f-b709-b8ca29063fd9'::uuid,'efd670bc-8dba-4926-82c4-2d194281a609'::uuid,9240.00::numeric)
  ) expected(revision_id,bill_id,income_id,amount_cny)
  loop
    if not exists(
      select 1
      from public.school_student_tuition_generation_revisions revision
      join public.school_student_tuition_bills bill on bill.id=revision.tuition_bill_id
      join public.school_income_records income on income.id=bill.income_record_id
      where revision.id=v_case.revision_id and revision.lifecycle_status='active'
        and bill.id=v_case.bill_id and bill.status='income_created'
        and bill.billing_amount_cny=v_case.amount_cny
        and income.id=v_case.income_id and income.status='pending'
        and (income.source_snapshot->>'billing_amount_cny')::numeric=v_case.amount_cny
    ) or exists(
      select 1 from public.school_personal_cash_income_linkage_events
      where income_record_id=v_case.income_id
    ) then
      raise exception 'P0G1B1_GATE_PRODUCTION_FACT_DRIFT: %',v_case.income_id;
    end if;
  end loop;

  update public.school_feature_gates
  set state='enabled',
      reason='P0-G1-B1 active admin授权链、Edge、Pages、权限负向矩阵及双库指纹验收完成；仅开放学费Cash待确认请求。',
      release_version='p0-g1-b1-admin-cash-20260804',
      evidence_hash='e48d55b7727ab32496dc42299de18789140e6ed1',
      updated_at=statement_timestamp(),
      updated_by=current_user
  where feature_key='student_tuition_cash_submit' and state='blocked';
  get diagnostics v_rows=row_count;
  if v_rows<>1
     or (select state from public.school_feature_gates where feature_key='student_tuition_cash_submit')<>'enabled'
     or (select state from public.school_feature_gates where feature_key='student_tuition_generate')<>'blocked' then
    raise exception 'P0G1B1_GATE_ENABLE_ROW_COUNT_OR_STATE_INVALID';
  end if;
end;
$enable$;

select feature_key,state,release_version,evidence_hash
from public.school_feature_gates
where feature_key in ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit')
order by feature_key;

\if :p0_g1_b1_gate_commit
  commit;
  \echo 'P0_G1_B1_CASH_GATE_ENABLED'
\else
  rollback;
  \echo 'P0_G1_B1_CASH_GATE_ENABLE_REHEARSAL_ROLLED_BACK'
\endif
