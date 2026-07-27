-- school_tuition_r0_fail_closed_rpcs.sql
-- R0 backend fail-closed guards for formal tuition bill/income generation,
-- the superseded personal-Cash tuition income/outbox RPC, and
-- student_tuition_bill Cash submission. No business row is modified by this
-- deployment file; it installs functions, grants, and mutation guards only.

begin;

create or replace function public.school_require_feature_gate_state(
  p_feature_key text,
  p_expected_state text,
  p_error_code text,
  p_error_message text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_state text;
begin
  begin
    select g.state
      into strict v_state
      from public.school_feature_gates g
     where g.feature_key = p_feature_key;
  exception
    when no_data_found then
      raise exception '%: %', p_error_code, p_error_message
        using detail = format('feature gate %s is missing; request denied fail-closed', p_feature_key);
    when others then
      raise exception '%: %', p_error_code, p_error_message
        using detail = format('feature gate %s could not be read; request denied fail-closed', p_feature_key);
  end;

  if v_state is distinct from p_expected_state then
    raise exception '%: %', p_error_code, p_error_message
      using detail = format(
        'feature gate %s state is %s; expected %s',
        p_feature_key,
        coalesce(v_state, '<null>'),
        p_expected_state
      );
  end if;
end;
$$;

comment on function public.school_require_feature_gate_state(text, text, text, text) is
  'Internal fail-closed feature-gate assertion. Missing, unreadable, null, unknown, or unexpected state rejects the caller.';

revoke all on function public.school_require_feature_gate_state(text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.school_require_feature_gate_state(text, text, text, text)
  to service_role;

create or replace function public.school_generate_student_tuition_bill(
  p_student_id uuid,
  p_billing_month text,
  p_note text default null
)
returns table (
  tuition_bill_id uuid,
  student_id uuid,
  business_entity_id uuid,
  billing_month text,
  previous_settlement_month text,
  previous_settlement_id uuid,
  previous_carryover_cny numeric,
  planned_lesson_count integer,
  planned_lesson_hours numeric,
  planned_lesson_fee_jpy numeric,
  bill_amount_jpy numeric,
  currency text,
  status text,
  income_record_id uuid,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.school_require_feature_gate_state(
    'student_tuition_generate',
    'enabled',
    'TUITION_GENERATION_BLOCKED',
    '学费应收生成功能正在进行资金一致性整改，当前仅允许预览，禁止生成正式账单或收入。'
  );

  raise exception 'TUITION_GENERATION_BLOCKED: R0 does not provide an enabled generation path.';
end;
$$;

create or replace function public.school_generate_student_tuition_bill(
  p_student_id uuid,
  p_billing_month text,
  p_billing_exchange_rate numeric,
  p_note text default null
)
returns table (
  tuition_bill_id uuid,
  student_id uuid,
  business_entity_id uuid,
  billing_month text,
  previous_settlement_month text,
  previous_settlement_id uuid,
  previous_carryover_cny numeric,
  planned_lesson_count integer,
  planned_lesson_hours numeric,
  planned_lesson_fee_jpy numeric,
  bill_amount_jpy numeric,
  currency text,
  billing_exchange_rate numeric,
  billing_amount_cny numeric,
  billing_amount_currency text,
  status text,
  income_record_id uuid,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.school_require_feature_gate_state(
    'student_tuition_generate',
    'enabled',
    'TUITION_GENERATION_BLOCKED',
    '学费应收生成功能正在进行资金一致性整改，当前仅允许预览，禁止生成正式账单或收入。'
  );

  raise exception 'TUITION_GENERATION_BLOCKED: R0 does not provide an enabled generation path.';
end;
$$;

create or replace function public.school_create_student_tuition_bill_income_record(
  p_tuition_bill_id uuid,
  p_income_date date,
  p_note text default null
)
returns table (
  income_id uuid,
  tuition_bill_id uuid,
  income_status text,
  bill_status text,
  amount numeric,
  currency text,
  settlement_month text,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.school_require_feature_gate_state(
    'student_tuition_generate',
    'enabled',
    'TUITION_GENERATION_BLOCKED',
    '学费应收生成功能正在进行资金一致性整改，当前仅允许预览，禁止生成正式账单或收入。'
  );

  raise exception 'TUITION_GENERATION_BLOCKED: R0 does not provide an enabled income-generation path.';
end;
$$;

create or replace function public.school_create_personal_cash_tuition_income_record(
  p_income_date date,
  p_settlement_month text,
  p_business_entity_id uuid,
  p_student_id uuid,
  p_cash_account_mapping_id uuid,
  p_amount numeric,
  p_income_category text default 'tuition',
  p_description text default null,
  p_currency text default 'JPY',
  p_payment_currency text default 'JPY',
  p_payment_method text default null,
  p_is_taxable_income boolean default false,
  p_tax_category text default null,
  p_receipt_status text default null,
  p_note text default null
)
returns table (
  income_id uuid,
  linkage_event_id uuid,
  business_entity_id uuid,
  student_id uuid,
  cash_account_mapping_id uuid,
  cash_user_id uuid,
  cash_account_id uuid,
  cash_account_name_snapshot text,
  currency text,
  amount numeric,
  income_status text,
  source_event_type text,
  idempotency_key text,
  sync_status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.school_require_feature_gate_state(
    'student_tuition_generate',
    'enabled',
    'TUITION_GENERATION_BLOCKED',
    '学费应收生成功能正在进行资金一致性整改，当前仅允许预览，禁止生成正式账单或收入。'
  );

  raise exception 'TUITION_GENERATION_BLOCKED: R0 does not provide an enabled legacy personal-Cash tuition income path.';
end;
$$;

comment on function public.school_generate_student_tuition_bill(uuid, text, text) is
  'R0 fail-closed compatibility entry. Formal tuition generation is blocked before validation or writes.';
comment on function public.school_generate_student_tuition_bill(uuid, text, numeric, text) is
  'R0 fail-closed formal tuition generation entry. Blocked before calculation, locking, or writes.';
comment on function public.school_create_student_tuition_bill_income_record(uuid, date, text) is
  'R0 fail-closed tuition bill to income entry. Blocked before locking or writes.';
comment on function public.school_create_personal_cash_tuition_income_record(
  date, text, uuid, uuid, uuid, numeric, text, text, text, text, text, boolean, text, text, text
) is
  'R0 fail-closed historical personal-Cash tuition income entry. The superseded RPC is preserved by signature but blocked before validation, locking, income creation, or outbox creation.';

revoke all on function public.school_generate_student_tuition_bill(uuid, text, text)
  from public, anon, authenticated;
revoke all on function public.school_generate_student_tuition_bill(uuid, text, numeric, text)
  from public, anon, authenticated;
revoke all on function public.school_create_student_tuition_bill_income_record(uuid, date, text)
  from public, anon, authenticated;
revoke all on function public.school_create_personal_cash_tuition_income_record(
  date, text, uuid, uuid, uuid, numeric, text, text, text, text, text, boolean, text, text, text
) from public, anon, authenticated;

grant execute on function public.school_generate_student_tuition_bill(uuid, text, text)
  to authenticated, service_role;
grant execute on function public.school_generate_student_tuition_bill(uuid, text, numeric, text)
  to authenticated, service_role;
grant execute on function public.school_create_student_tuition_bill_income_record(uuid, date, text)
  to authenticated, service_role;
grant execute on function public.school_create_personal_cash_tuition_income_record(
  date, text, uuid, uuid, uuid, numeric, text, text, text, text, text, boolean, text, text, text
) to authenticated, service_role;

create or replace function public.school_guard_r0_tuition_business_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_income_record_id uuid;
  v_income_source_type text;
begin
  if tg_table_name = 'school_student_tuition_bills' then
    perform public.school_require_feature_gate_state(
      'student_tuition_generate',
      'enabled',
      'TUITION_GENERATION_BLOCKED',
      '学费应收生成功能正在进行资金一致性整改，当前仅允许预览，禁止生成正式账单或收入。'
    );
  elsif tg_table_name = 'school_income_records' then
    if coalesce(case when tg_op <> 'DELETE' then new.source_type end, '') = 'student_tuition_bill'
       or coalesce(case when tg_op <> 'INSERT' then old.source_type end, '') = 'student_tuition_bill' then
      perform public.school_require_feature_gate_state(
        'student_tuition_generate',
        'enabled',
        'TUITION_GENERATION_BLOCKED',
        '学费应收生成功能正在进行资金一致性整改，当前仅允许预览，禁止生成正式账单或收入。'
      );
    end if;
  elsif tg_table_name = 'school_personal_cash_income_linkage_events' then
    v_income_record_id := coalesce(
      case when tg_op <> 'DELETE' then new.income_record_id end,
      case when tg_op <> 'INSERT' then old.income_record_id end
    );

    begin
      select i.source_type
        into strict v_income_source_type
        from public.school_income_records i
       where i.id = v_income_record_id;
    exception
      when no_data_found then
        if coalesce(case when tg_op <> 'DELETE' then new.source_event_type end, '') = 'tuition_income_received'
           or coalesce(case when tg_op <> 'INSERT' then old.source_event_type end, '') = 'tuition_income_received' then
          raise exception 'TUITION_CASH_SUBMISSION_BLOCKED: 学费收入来源无法验证，禁止提交 Cash。';
        end if;
        v_income_source_type := null;
      when others then
        raise exception 'TUITION_CASH_SUBMISSION_BLOCKED: 学费 Cash gate 读取失败，禁止提交 Cash。';
    end;

    if v_income_source_type = 'student_tuition_bill' then
      perform public.school_require_feature_gate_state(
        'student_tuition_cash_submit',
        'enabled',
        'TUITION_CASH_SUBMISSION_BLOCKED',
        '学费收入 Cash 提交正在进行资金一致性整改，当前禁止提交。'
      );
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.school_guard_r0_tuition_business_mutation()
  from public, anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.school_student_tuition_bills'::regclass
       and tgname = 'school_r0_tuition_bill_mutation_guard'
       and not tgisinternal
  ) then
    create trigger school_r0_tuition_bill_mutation_guard
    before insert or update or delete on public.school_student_tuition_bills
    for each row execute function public.school_guard_r0_tuition_business_mutation();
  end if;

  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.school_income_records'::regclass
       and tgname = 'school_r0_tuition_income_mutation_guard'
       and not tgisinternal
  ) then
    create trigger school_r0_tuition_income_mutation_guard
    before insert or update or delete on public.school_income_records
    for each row execute function public.school_guard_r0_tuition_business_mutation();
  end if;

  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.school_personal_cash_income_linkage_events'::regclass
       and tgname = 'school_r0_tuition_cash_linkage_mutation_guard'
       and not tgisinternal
  ) then
    create trigger school_r0_tuition_cash_linkage_mutation_guard
    before insert or update or delete on public.school_personal_cash_income_linkage_events
    for each row execute function public.school_guard_r0_tuition_business_mutation();
  end if;
end;
$$;

commit;
