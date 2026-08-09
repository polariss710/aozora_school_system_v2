\set ON_ERROR_STOP on

begin;
set local lock_timeout = '8s';
set local statement_timeout = '120s';

do $test$
declare
  v_sun constant uuid := 'b17abc58-2f64-4bad-bf20-c9643ead60bc';
  v_zhang constant uuid := '7aef8061-7037-4881-a847-a2cdb031c0f4';
  v_actor uuid;
  v_status jsonb;
  v_eligibility jsonb;
  v_before_settlements integer;
  v_before_source integer;
  v_before_adjustment integer;
begin
  select count(*) into v_before_settlements
  from public.school_student_monthly_settlements;
  select count(*) into v_before_source
  from public.school_student_settlement_source_treatment_drafts;
  select count(*) into v_before_adjustment
  from public.school_student_settlement_adjustment_drafts;

  foreach v_actor in array array[v_sun, v_zhang]
  loop
    v_eligibility := public.school_get_student_settlement_online_save_eligibility_core(
      v_actor, '2026-06'
    );
    if (v_eligibility->>'can_save')::boolean
       or v_eligibility->>'save_blocker_code'
            is distinct from 'SETTLEMENT_SUCCESSOR_REVISION_BLOCKED'
       or (v_eligibility->>'source_facts_available')::boolean then
      raise exception 'C_R1_KNOWN_SCOPE_ELIGIBILITY_FAILED: % %',
        v_actor, v_eligibility;
    end if;
    v_status := public.school_get_student_monthly_settlement_online_status_core(
      v_actor, '2026-06'
    );
    if (v_status->>'can_save')::boolean
       or (v_status->>'can_lock')::boolean
       or v_status->>'save_blocker_code'
            is distinct from 'SETTLEMENT_SUCCESSOR_REVISION_BLOCKED'
       or v_status->'immutable_blocker'->>'code'
            is distinct from 'SETTLEMENT_SUCCESSOR_REVISION_BLOCKED' then
      raise exception 'C_R1_KNOWN_SCOPE_STATUS_FAILED: % %', v_actor, v_status;
    end if;
  end loop;

  v_status := public.school_get_student_monthly_settlement_online_status_core(
    'eceb2c59-9689-4ec8-9d3f-799b90bfdb27', '2026-08'
  );
  if not (v_status->>'can_save')::boolean
     or not (v_status->>'source_facts_available')::boolean
     or v_status->>'save_blocker_code' is not null then
    raise exception 'C_R1_CURRENT_MONTH_RULE_CHANGED: %', v_status;
  end if;

  v_status := public.school_get_student_monthly_settlement_online_status_core(
    '7aef8061-7037-4881-a847-a2cdb031c0f4', '2026-09'
  );
  if not (v_status->>'can_save')::boolean
     or not (v_status->>'source_facts_available')::boolean
     or v_status->>'save_blocker_code' is not null then
    raise exception 'C_R1_FUTURE_MONTH_RULE_CHANGED: %', v_status;
  end if;

  if public.school_get_student_monthly_settlement_online_status_core(
       'eceb2c59-9689-4ec8-9d3f-799b90bfdb27', '2026-05'
     )->>'save_blocker_code' is distinct from 'SETTLEMENT_ORDINARY_ALREADY_LOCKED'
     or public.school_get_student_monthly_settlement_online_status_core(
       '7aef8061-7037-4881-a847-a2cdb031c0f4', '2026-07'
     )->>'save_blocker_code' is distinct from 'SETTLEMENT_HISTORICALLY_CONSUMED'
     or public.school_get_student_monthly_settlement_online_status_core(
       'eceb2c59-9689-4ec8-9d3f-799b90bfdb27', '2026-07'
     )->>'save_blocker_code' is distinct from 'SETTLEMENT_HISTORICAL_ZERO_CARRY_COMPLETE'
     or public.school_get_student_monthly_settlement_online_status_core(
       '4c6f1473-7d44-467d-a70b-30f02e7cf8cd', '2026-06'
     )->>'save_blocker_code' is distinct from 'SETTLEMENT_SUCCESSOR_REVISION_BLOCKED'
     or public.school_get_student_monthly_settlement_online_status_core(
       'a7b163a0-201e-4867-9b94-372343356a80', '2026-05'
     )->>'save_blocker_code' is distinct from 'SETTLEMENT_SCOPE_NOT_UNIQUE' then
    raise exception 'C_R1_HISTORICAL_STATUS_REGRESSION';
  end if;

  v_status := public.school_get_student_monthly_settlement_online_status_core(
    v_zhang, '2026-07'
  );
  if v_status->'adjustment_draft'->>'draft_id'
       is distinct from '99221804-52f0-4733-b6cd-7d7838248ae4' then
    raise exception 'C_R1_ACTIVE_DRAFT_VISIBILITY_REGRESSION: %', v_status;
  end if;

  if (select count(*) from public.school_student_monthly_settlements)
       is distinct from v_before_settlements
     or (select count(*) from public.school_student_settlement_source_treatment_drafts)
       is distinct from v_before_source
     or (select count(*) from public.school_student_settlement_adjustment_drafts)
       is distinct from v_before_adjustment then
    raise exception 'C_R1_NEGATIVE_GUARD_CHANGED_BUSINESS_ROWS';
  end if;
end
$test$;

do $writer_negative$
declare
  v_actor uuid;
  v_student uuid;
  v_error text;
begin
  select m.user_id into strict v_actor
  from public.school_app_memberships m
  join auth.users u on u.id = m.user_id
  where m.is_active and m.role = 'admin'
  order by m.user_id
  limit 1;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_actor, 'role', 'service_role')::text,
    true
  );

  foreach v_student in array array[
    'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,
    '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid
  ]
  loop
    begin
      perform public.school_save_student_monthly_settlement_draft_online_admin(
        v_actor, v_student, '2026-06',
        'separate_makeup_and_overage_v1', null, null, null,
        'carry_final_balance', null,
        'codex-test Phase C-R1 negative guard only', null,
        repeat('0', 64), repeat('0', 64), 0,
        0, 0, 0, 0, 0, 0,
        null, null, null, null,
        'c1000000-0000-4000-8000-000000000001'::uuid
      );
      raise exception 'C_R1_WRITER_NEGATIVE_UNEXPECTED_SUCCESS: %', v_student;
    exception when others then
      v_error := sqlerrm;
      if position('SETTLEMENT_SUCCESSOR_REVISION_BLOCKED' in v_error) = 0 then
        raise exception 'C_R1_WRITER_NEGATIVE_WRONG_ERROR: % %', v_student, v_error;
      end if;
    end;
  end loop;
end
$writer_negative$;

do $acl$
declare
  v_helper oid := 'public.school_get_student_settlement_online_save_eligibility_core(uuid,text)'::regprocedure;
begin
  if has_function_privilege('public', v_helper, 'EXECUTE')
     or has_function_privilege('anon', v_helper, 'EXECUTE')
     or has_function_privilege('authenticated', v_helper, 'EXECUTE')
     or has_function_privilege('service_role', v_helper, 'EXECUTE') then
    raise exception 'C_R1_HELPER_ACL_REGRESSION';
  end if;
end
$acl$;

rollback;

select 'SETTLEMENT_ONLINE_CAN_SAVE_R1_ROLLBACK_PASS' result;
