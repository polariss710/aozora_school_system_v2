-- School V2 tuition P0 R1B R0 entry probes. Expected errors only; no write succeeds.

\set ON_ERROR_STOP on

do $$
declare
  v_generation_rejections integer := 0;
begin
  begin
    perform public.school_generate_student_tuition_bill(
      '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,
      '2026-07',
      null::text
    );
  exception when others then
    if sqlerrm not like 'TUITION_GENERATION_BLOCKED:%' then raise; end if;
    v_generation_rejections := v_generation_rejections + 1;
  end;

  begin
    perform public.school_generate_student_tuition_bill(
      '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,
      '2026-07',
      0.043::numeric,
      null::text
    );
  exception when others then
    if sqlerrm not like 'TUITION_GENERATION_BLOCKED:%' then raise; end if;
    v_generation_rejections := v_generation_rejections + 1;
  end;

  begin
    perform public.school_create_student_tuition_bill_income_record(
      '047dac2b-9484-4637-8e5e-9887857d121b'::uuid,
      '2026-07-27'::date,
      null::text
    );
  exception when others then
    if sqlerrm not like 'TUITION_GENERATION_BLOCKED:%' then raise; end if;
    v_generation_rejections := v_generation_rejections + 1;
  end;

  begin
    perform public.school_create_personal_cash_tuition_income_record(
      '2026-07-27'::date,
      '2026-07',
      '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid,
      '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,
      null::uuid,
      1::numeric,
      'tuition'::text,
      null::text,
      'JPY'::text,
      'JPY'::text,
      null::text,
      false,
      null::text,
      null::text,
      null::text
    );
  exception when others then
    if sqlerrm not like 'TUITION_GENERATION_BLOCKED:%' then raise; end if;
    v_generation_rejections := v_generation_rejections + 1;
  end;

  if v_generation_rejections <> 4 then
    raise exception 'R1B_R0_GENERATION_PROBE_COUNT_MISMATCH: %', v_generation_rejections;
  end if;

  begin
    perform public.school_require_feature_gate_state(
      'student_tuition_cash_submit',
      'enabled',
      'TUITION_CASH_SUBMISSION_BLOCKED',
      'R1B Cash gate probe'
    );
    raise exception 'EXPECTED_R0_CASH_GATE_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_CASH_SUBMISSION_BLOCKED:%' then raise; end if;
  end;

  begin
    perform public.school_request_cash_income_confirmation_for_record(
      'bbd7e7fd-fa04-404b-91fc-ab894cca28c8'::uuid,
      'b1000000-0000-4000-8000-202607279911'::uuid,
      'b1000000-0000-4000-8000-202607279912'::uuid,
      'codex-test-r1b'::text,
      'wallet'::text,
      1::numeric,
      'JPY'::text,
      null::numeric,
      null::text,
      null::text
    );
    raise exception 'EXPECTED_INCIDENT_CASH_RPC_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'Cash income request requires pending School income.%' then raise; end if;
  end;

  raise notice 'R1B_R0_ENTRY_PROBES_OK: four generation entries blocked, Cash gate blocked, incident Cash RPC rejected.';
end;
$$;
