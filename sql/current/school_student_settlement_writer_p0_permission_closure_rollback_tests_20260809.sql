-- Exact deployment rehearsal plus role/active-revision/local-wrapper regression.
-- Every synthetic business row is rolled back by the included wrapper suite.
\set ON_ERROR_STOP on
\pset pager off

begin;
\ir school_student_settlement_writer_p0_permission_closure_20260809.sql

do $acl_matrix$
declare
  v_signature text;
  v_oid regprocedure;
  v_role text;
begin
  foreach v_signature in array array[
    'public.school_lock_student_monthly_settlement(uuid,text,text)',
    'public.school_relock_student_monthly_settlement(uuid,text)',
    'public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)',
    'public.school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text)',
    'public.school_unlock_student_monthly_settlement(uuid,text)'
  ] loop
    v_oid := v_signature::regprocedure;
    foreach v_role in array array['anon','authenticated','service_role'] loop
      if has_function_privilege(v_role,v_oid,'execute') then
        raise exception 'SETTLEMENT_WRITER_P0_ROLE_MATRIX_FAILED: % %',v_role,v_signature;
      end if;
    end loop;
    if not has_function_privilege('postgres',v_oid,'execute') then
      raise exception 'SETTLEMENT_WRITER_P0_OWNER_EXECUTE_MISSING: %',v_signature;
    end if;
  end loop;
  if has_function_privilege('anon',
      'public.school_save_student_settlement_draft_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,text)',
      'execute')
     or has_function_privilege('authenticated',
      'public.school_save_student_settlement_draft_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,text)',
      'execute')
     or not has_function_privilege('service_role',
      'public.school_save_student_settlement_draft_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,text)',
      'execute') then
    raise exception 'SETTLEMENT_WRITER_P0_SAVE_WRAPPER_ACL_FAILED';
  end if;
end
$acl_matrix$;

do $active_revision_owner_negative$
declare
  v_before integer;
begin
  select count(*) into v_before
  from public.school_student_monthly_settlements
  where student_id='eceb2c59-9689-4ec8-9d3f-799b90bfdb27'
    and year_month='2026-07';
  begin
    perform * from public.school_lock_student_monthly_settlement(
      'eceb2c59-9689-4ec8-9d3f-799b90bfdb27','2026-07','codex-test p0 owner negative'
    );
    raise exception 'SETTLEMENT_WRITER_P0_OWNER_ACTIVE_REVISION_REJECTION_MISSING';
  exception when others then
    if sqlstate<>'P0001'
       or position('TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE' in sqlerrm)=0 then
      raise;
    end if;
  end;
  if (select count(*) from public.school_student_monthly_settlements
      where student_id='eceb2c59-9689-4ec8-9d3f-799b90bfdb27'
        and year_month='2026-07')<>v_before then
    raise exception 'SETTLEMENT_WRITER_P0_OWNER_NEGATIVE_PARTIAL_WRITE';
  end if;
end
$active_revision_owner_negative$;

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $active_revision_wrapper_negative$
begin
  begin
    perform public.school_lock_student_monthly_settlement_local(
      'eceb2c59-9689-4ec8-9d3f-799b90bfdb27',
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
      '2026-07',null,null,null,null,null,null,
      'p0-active-revision-probe',null,null,null,null,null,null,null,0,
      null,null,null,null,'codex-test p0 wrapper negative',
      'local_trusted_business_owner_v1',
      'LOCK STUDENT SETTLEMENT eceb2c59-9689-4ec8-9d3f-799b90bfdb27 2026-07 MANIFEST p0-active-revision-probe CARRY 0'
    );
    raise exception 'SETTLEMENT_WRITER_P0_WRAPPER_ACTIVE_REVISION_REJECTION_MISSING';
  exception when others then
    if sqlstate<>'P0001'
       or position('TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE' in sqlerrm)=0 then
      raise;
    end if;
  end;
end
$active_revision_wrapper_negative$;
reset role;
select set_config('request.jwt.claims','',true);

-- This existing suite proves confirmation, expected facts/manifest/amount,
-- service-role save/lock, duplicate-lock idempotency, and leaves residue zero.
\ir school_tuition_p0f_local_settlement_management_rollback_20260803.sql
