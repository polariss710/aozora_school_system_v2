-- School V2 tuition Cash submit technical hardening, 2026-08-02.
-- Status: deployed and rollback-tested on 2026-08-02; Gate remains blocked.
-- Scope: replace the canonical income Cash request RPC and contract bridge ACLs.
-- This file does not enable student_tuition_cash_submit and does not update business data.

create or replace function public.school_request_cash_income_confirmation_for_record(
  p_income_record_id uuid,
  p_cash_user_id uuid,
  p_cash_account_id uuid,
  p_cash_account_name_snapshot text,
  p_cash_account_type_snapshot text,
  p_payment_amount numeric,
  p_payment_currency text,
  p_exchange_rate numeric default null,
  p_note text default null,
  p_payment_rounding_mode text default null
)
returns table (
  income_id uuid,
  linkage_event_id uuid,
  sync_status text,
  attempt_no integer,
  idempotency_key text,
  request_type text,
  amount numeric,
  currency text,
  payment_currency text,
  payment_exchange_rate numeric,
  payment_amount numeric,
  cash_user_id uuid,
  cash_account_id uuid,
  cash_account_name_snapshot text,
  cash_account_type_snapshot text,
  cash_request_id uuid,
  cash_request_status text,
  message text
)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_income public.school_income_records%rowtype;
  v_existing public.school_personal_cash_income_linkage_events%rowtype;
  v_latest public.school_personal_cash_income_linkage_events%rowtype;
  v_bill public.school_student_tuition_bills%rowtype;
  v_identity public.school_student_tuition_billing_identities%rowtype;
  v_event_id uuid;
  v_attempt_no integer;
  v_request_type text;
  v_idempotency_key text;
  v_cash_transaction_table text;
  v_cash_account_name text := nullif(trim(coalesce(p_cash_account_name_snapshot, '')), '');
  v_cash_account_type text := nullif(trim(coalesce(p_cash_account_type_snapshot, '')), '');
  v_requested_payment_currency text := nullif(upper(trim(coalesce(p_payment_currency, ''))), '');
  v_payment_currency text;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_rounding_mode text := nullif(lower(trim(coalesce(p_payment_rounding_mode, ''))), '');
  v_payment_amount numeric;
  v_payment_exchange_rate numeric;
  v_computed_amount numeric;
  v_now timestamptz := now();
begin
  if p_income_record_id is null then
    raise exception 'income record id is required';
  end if;

  if p_cash_user_id is null or p_cash_account_id is null then
    raise exception '请选择 Cash System 账户。';
  end if;

  if v_cash_account_name is null then
    raise exception 'Cash account name snapshot is required';
  end if;

  select *
    into v_income
    from public.school_income_records
   where id = p_income_record_id
     and coalesce(app_type, '') = 'school'
   for update;

  if not found then
    raise exception 'income record not found: %', p_income_record_id;
  end if;

  if coalesce(v_income.status, '') <> 'pending' then
    raise exception 'Cash income request requires pending School income. current status: %', v_income.status;
  end if;

  if v_income.account_id is not null then
    raise exception 'Cash income must not have a School account id.';
  end if;

  if v_income.currency not in ('JPY', 'CNY') then
    raise exception 'School income original currency must be JPY or CNY.';
  end if;

  if v_income.source_type = 'student_tuition_bill' then
    if p_payment_amount is not null
       or v_requested_payment_currency is not null
       or p_exchange_rate is not null
       or v_rounding_mode is not null then
      raise exception '学费 Cash 金额、币种、汇率和取整规则只允许由冻结账单提供，客户端不得提交。';
    end if;

    if not exists (
      select 1
        from public.school_feature_gates gate_row
       where gate_row.feature_key = 'student_tuition_cash_submit'
         and gate_row.state = 'enabled'
    ) then
      raise exception 'TUITION_CASH_SUBMISSION_BLOCKED';
    end if;

    select *
      into v_bill
      from public.school_student_tuition_bills bill_row
     where bill_row.id = v_income.source_id
       and bill_row.id = v_income.tuition_bill_id
       and bill_row.income_record_id = v_income.id
       and bill_row.status = 'income_created'
       and bill_row.app_type = 'school'
     for update;

    if not found then
      raise exception '学生学费应收单与收入记录不匹配，不能提交 Cash。';
    end if;

    select *
      into v_identity
      from public.school_student_tuition_billing_identities identity_row
     where identity_row.canonical_bill_id = v_bill.id
       and identity_row.student_id = v_bill.student_id
       and identity_row.billing_month = v_bill.billing_month
     for update;

    if not found then
      raise exception '学生学费账单 identity 与 canonical bill 不匹配，不能提交 Cash。';
    end if;

    if v_income.income_category is distinct from 'tuition'
       or v_income.source_id is distinct from v_bill.id
       or v_income.tuition_bill_id is distinct from v_bill.id
       or v_bill.income_record_id is distinct from v_income.id
       or v_income.student_id is distinct from v_bill.student_id
       or v_income.business_entity_id is distinct from v_bill.business_entity_id
       or v_income.year_month is distinct from v_bill.billing_month
       or v_income.settlement_month is distinct from v_bill.billing_month
       or v_income.currency is distinct from 'JPY'
       or v_income.amount is distinct from v_bill.bill_amount_jpy
       or v_income.amount_jpy is distinct from v_bill.bill_amount_jpy
       or coalesce(v_income.cash_submission_blocked, false) is true
       or coalesce(v_income.operational_excluded, false) is true
       or coalesce(v_bill.cash_submission_blocked, false) is true then
      raise exception '学费收入、账单或 identity canonical 关系不满足 Cash 提交合同。';
    end if;

    if (v_income.source_snapshot ->> 'tuition_bill_id')::uuid is distinct from v_bill.id
       or (v_income.source_snapshot ->> 'billing_identity_id')::uuid is distinct from v_identity.id
       or v_income.source_snapshot ->> 'billing_month' is distinct from v_bill.billing_month
       or coalesce(
         (v_income.source_snapshot ->> 'bill_amount_jpy')::numeric,
         (v_income.source_snapshot ->> 'total_fee_jpy')::numeric,
         (v_income.source_snapshot ->> 'planned_lesson_fee_jpy')::numeric
       ) is distinct from v_bill.bill_amount_jpy
       or (v_income.source_snapshot ->> 'billing_exchange_rate')::numeric is distinct from v_bill.billing_exchange_rate
       or (v_income.source_snapshot ->> 'billing_amount_cny')::numeric is distinct from v_bill.billing_amount_cny
       or (v_income.source_snapshot ->> 'previous_carryover_cny')::numeric is distinct from v_bill.previous_carryover_cny
       or v_bill.source_snapshot ->> 'student_id' is distinct from v_bill.student_id::text
       or v_bill.source_snapshot ->> 'business_entity_id' is distinct from v_bill.business_entity_id::text
       or v_bill.source_snapshot ->> 'billing_month' is distinct from v_bill.billing_month
       or coalesce(
         (v_bill.source_snapshot ->> 'bill_amount_jpy')::numeric,
         (v_bill.source_snapshot ->> 'total_fee_jpy')::numeric,
         (v_bill.source_snapshot ->> 'planned_lesson_fee_jpy')::numeric
       ) is distinct from v_bill.bill_amount_jpy
       or (v_bill.source_snapshot ->> 'billing_exchange_rate')::numeric is distinct from v_bill.billing_exchange_rate
       or (v_bill.source_snapshot ->> 'billing_amount_cny')::numeric is distinct from v_bill.billing_amount_cny
       or (v_bill.source_snapshot ->> 'previous_carryover_cny')::numeric is distinct from v_bill.previous_carryover_cny then
      raise exception '学费收入或账单冻结快照与 canonical bill 不一致，不能提交 Cash。';
    end if;

    if v_bill.billing_exchange_rate is null or v_bill.billing_exchange_rate <= 0
       or v_bill.billing_amount_cny is null or v_bill.billing_amount_cny <= 0 then
      raise exception '学费账单冻结 CNY 金额或汇率无效，不能提交 Cash。';
    end if;

    v_payment_currency := 'CNY';
    v_payment_exchange_rate := v_bill.billing_exchange_rate;
    v_payment_amount := v_bill.billing_amount_cny;
  else
    v_payment_currency := v_requested_payment_currency;
    v_payment_amount := p_payment_amount;

    if v_payment_currency not in ('JPY', 'CNY') then
      raise exception '实际到账币种必须是 JPY 或 CNY。';
    end if;

    if p_exchange_rate is not null and p_exchange_rate <= 0 then
      raise exception '汇率必须大于 0。';
    end if;

    if v_income.currency = v_payment_currency then
      if p_exchange_rate is not null and p_exchange_rate <> 1 then
        raise exception '同币种实际到账汇率应为空或 1。';
      end if;

      v_payment_exchange_rate := coalesce(p_exchange_rate, 1);
      if v_payment_amount is null then
        v_payment_amount := v_income.amount;
      end if;
    else
      if v_payment_amount is null and (p_exchange_rate is null or p_exchange_rate <= 0) then
        raise exception '后端计算跨币种实际到账金额时必须填写本次汇率。';
      end if;

      if p_exchange_rate is not null then
        v_payment_exchange_rate := p_exchange_rate;
      elsif v_payment_amount is not null and v_payment_amount > 0 and v_income.amount > 0 then
        v_payment_exchange_rate := case
          when v_income.currency = 'JPY' and v_payment_currency = 'CNY'
            then round((v_payment_amount / v_income.amount) * 10000000) / 10000000
          when v_income.currency = 'CNY' and v_payment_currency = 'JPY'
            then round((v_income.amount / v_payment_amount) * 10000000) / 10000000
          else null
        end;
      end if;

      if v_payment_exchange_rate is null or v_payment_exchange_rate <= 0 then
        raise exception '跨币种实际到账汇率计算失败。';
      end if;
    end if;

    if v_income.currency <> v_payment_currency and v_payment_amount is null then
      if v_rounding_mode not in ('round', 'ceil', 'floor') then
        raise exception '后端计算实际到账金额时必须指定取整方式。';
      end if;

      v_computed_amount := case
        when v_income.currency = 'JPY' and v_payment_currency = 'CNY'
          then v_income.amount * v_payment_exchange_rate
        when v_income.currency = 'CNY' and v_payment_currency = 'JPY'
          then v_income.amount / v_payment_exchange_rate
        else null
      end;

      if v_computed_amount is null or v_computed_amount <= 0 then
        raise exception '实际到账金额计算失败。';
      end if;

      if v_rounding_mode = 'ceil' then
        v_payment_amount := ceil(v_computed_amount);
      elsif v_rounding_mode = 'floor' then
        v_payment_amount := floor(v_computed_amount);
      else
        v_payment_amount := round(v_computed_amount);
      end if;
    end if;
  end if;

  if v_payment_amount is null or v_payment_amount <= 0 then
    raise exception '实际到账金额必须大于 0。';
  end if;

  v_request_type := case
    when v_income.income_category = 'tuition' then 'tuition_income_received'
    else 'income_received'
  end;
  v_cash_transaction_table := case
    when v_payment_currency = 'JPY' then 'home_jpy_transactions'
    else 'home_cny_transactions'
  end;

  select *
    into v_existing
    from public.school_personal_cash_income_linkage_events event_row
   where event_row.source_table = 'school_income_records'
     and event_row.source_id = p_income_record_id
     and event_row.source_event_type = v_request_type
     and event_row.sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation')
   for update;

  if found then
    if v_existing.cash_user_id is distinct from p_cash_user_id
       or v_existing.cash_account_id is distinct from p_cash_account_id
       or v_existing.cash_account_name_snapshot is distinct from v_cash_account_name
       or v_existing.cash_account_type_snapshot is distinct from v_cash_account_type
       or v_existing.currency is distinct from v_income.currency
       or v_existing.amount is distinct from v_income.amount
       or v_existing.payment_currency is distinct from v_payment_currency
       or v_existing.payment_exchange_rate is distinct from v_payment_exchange_rate
       or v_existing.payment_amount is distinct from v_payment_amount then
      raise exception 'existing Cash income linkage event conflicts with requested snapshot: %', v_existing.id;
    end if;

    if v_existing.cash_transaction_id is not null then
      raise exception 'existing Cash income linkage event already has a Cash transaction: %', v_existing.id;
    end if;

    v_event_id := v_existing.id;
  else
    select *
      into v_latest
      from public.school_personal_cash_income_linkage_events event_row
     where event_row.source_table = 'school_income_records'
       and event_row.source_id = p_income_record_id
       and event_row.source_event_type = v_request_type
     order by event_row.attempt_no desc, event_row.created_at desc, event_row.id desc
     limit 1
     for update;

    if found and v_latest.sync_status <> 'cash_rejected' then
      raise exception 'latest Cash income linkage event is not rejected or requestable: %', v_latest.sync_status;
    end if;

    v_attempt_no := coalesce(v_latest.attempt_no, 0) + 1;
    v_idempotency_key := concat(
      'aozora_school:school_income_records:',
      p_income_record_id::text,
      ':',
      v_request_type,
      ':attempt:',
      v_attempt_no::text
    );

    begin
      insert into public.school_personal_cash_income_linkage_events (
        source_table, source_id, source_event_type, income_record_id,
        business_entity_id, cash_user_id, cash_account_id,
        cash_account_name_snapshot, cash_account_type_snapshot,
        cash_transaction_table, currency, amount, payment_currency,
        payment_exchange_rate, payment_amount, idempotency_key, sync_status,
        attempt_no, retry_count, note, created_at, updated_at
      ) values (
        'school_income_records', p_income_record_id, v_request_type, p_income_record_id,
        v_income.business_entity_id, p_cash_user_id, p_cash_account_id,
        v_cash_account_name, v_cash_account_type, v_cash_transaction_table,
        v_income.currency, v_income.amount, v_payment_currency,
        v_payment_exchange_rate, v_payment_amount, v_idempotency_key,
        'pending_cash_request', v_attempt_no,
        coalesce(v_latest.retry_count, 0) + case when found then 1 else 0 end,
        v_note, v_now, v_now
      )
      returning id into v_event_id;
    exception
      when unique_violation then
        select event_row.id
          into v_event_id
          from public.school_personal_cash_income_linkage_events event_row
         where event_row.source_table = 'school_income_records'
           and event_row.source_id = p_income_record_id
           and event_row.source_event_type = v_request_type
           and event_row.sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation')
           and event_row.cash_user_id is not distinct from p_cash_user_id
           and event_row.cash_account_id is not distinct from p_cash_account_id
           and event_row.cash_account_name_snapshot is not distinct from v_cash_account_name
           and event_row.cash_account_type_snapshot is not distinct from v_cash_account_type
           and event_row.currency is not distinct from v_income.currency
           and event_row.amount is not distinct from v_income.amount
           and event_row.payment_currency is not distinct from v_payment_currency
           and event_row.payment_exchange_rate is not distinct from v_payment_exchange_rate
           and event_row.payment_amount is not distinct from v_payment_amount
         for update;

        if not found then
          raise exception 'concurrent Cash income linkage event conflicts with requested snapshot';
        end if;
    end;
  end if;

  if v_income.source_type <> 'student_tuition_bill' then
    update public.school_income_records
       set receipt_status = 'Cash待确认', updated_at = v_now
     where id = p_income_record_id;
  end if;

  return query
  select
    income_row.id,
    event_row.id,
    event_row.sync_status,
    event_row.attempt_no,
    event_row.idempotency_key,
    event_row.source_event_type,
    event_row.amount,
    event_row.currency,
    event_row.payment_currency,
    event_row.payment_exchange_rate,
    event_row.payment_amount,
    event_row.cash_user_id,
    event_row.cash_account_id,
    event_row.cash_account_name_snapshot,
    event_row.cash_account_type_snapshot,
    event_row.cash_request_id,
    event_row.cash_request_status,
    case
      when event_row.sync_status = 'awaiting_cash_confirmation'
        then 'Cash income confirmation request already submitted'
      else 'School Cash income confirmation request event is ready to submit'
    end::text
  from public.school_income_records income_row
  join public.school_personal_cash_income_linkage_events event_row
    on event_row.id = v_event_id
  where income_row.id = p_income_record_id;
end;
$function$;

create or replace function public.school_get_cash_income_submission_preflight(
  p_income_record_ids uuid[]
)
returns table (
  income_record_id uuid,
  classification text,
  eligible boolean,
  gate_state text,
  payment_currency text,
  payment_amount numeric,
  payment_exchange_rate numeric,
  previous_carryover_cny numeric,
  latest_linkage_status text,
  latest_cash_request_status text
)
language sql
stable
security definer
set search_path = public
as $function$
  with requested as (
    select distinct requested_id
    from unnest(coalesce(p_income_record_ids, array[]::uuid[])) requested_id
    limit 500
  ), latest_linkage as (
    select distinct on (event_row.income_record_id) event_row.*
    from public.school_personal_cash_income_linkage_events event_row
    join requested on requested.requested_id = event_row.income_record_id
    order by event_row.income_record_id, event_row.attempt_no desc,
             event_row.created_at desc, event_row.id desc
  ), facts as (
    select
      income_row.id,
      income_row.status as income_status,
      income_row.account_id,
      income_row.source_type,
      income_row.income_category,
      income_row.source_id,
      income_row.tuition_bill_id,
      income_row.student_id,
      income_row.business_entity_id,
      income_row.year_month,
      income_row.settlement_month,
      income_row.currency,
      income_row.amount,
      income_row.amount_jpy,
      income_row.source_snapshot,
      income_row.cash_submission_blocked as income_blocked,
      income_row.operational_excluded,
      bill_row.id as bill_id,
      bill_row.status as bill_status,
      bill_row.income_record_id as bill_income_record_id,
      bill_row.student_id as bill_student_id,
      bill_row.business_entity_id as bill_business_entity_id,
      bill_row.billing_month,
      bill_row.bill_amount_jpy,
      bill_row.billing_exchange_rate,
      bill_row.billing_amount_cny,
      bill_row.previous_carryover_cny,
      bill_row.cash_submission_blocked as bill_blocked,
      identity_row.id as identity_id,
      latest.sync_status,
      latest.cash_request_status,
      latest.cash_transaction_id,
      coalesce((select state from public.school_feature_gates where feature_key = 'student_tuition_cash_submit'), 'unavailable') as current_gate_state
    from requested
    join public.school_income_records income_row on income_row.id = requested.requested_id
    left join public.school_student_tuition_bills bill_row
      on bill_row.id = income_row.source_id
     and bill_row.id = income_row.tuition_bill_id
    left join public.school_student_tuition_billing_identities identity_row
      on identity_row.canonical_bill_id = bill_row.id
     and identity_row.student_id = bill_row.student_id
     and identity_row.billing_month = bill_row.billing_month
    left join latest_linkage latest on latest.income_record_id = income_row.id
  ), classified as (
    select facts.*,
      case
        when source_type <> 'student_tuition_bill' then 'NON_TUITION'
        when income_status = 'received' and sync_status in ('synced', 'historical_confirmed') then 'ALREADY_SYNCED'
        when sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation')
          or cash_request_status = 'pending' then 'ALREADY_SUBMITTED'
        when income_status = 'pending' and sync_status = 'cash_rejected'
          and cash_request_status = 'rejected' and cash_transaction_id is null then 'REJECTED_RETRYABLE'
        when income_status = 'pending' and bill_status = 'income_created'
          and identity_id is not null
          and income_category = 'tuition'
          and source_id = bill_id and tuition_bill_id = bill_id
          and bill_income_record_id = id
          and account_id is null
          and income_blocked is false and operational_excluded is false
          and bill_blocked is false
          and student_id = bill_student_id
          and business_entity_id = bill_business_entity_id
          and year_month = billing_month and settlement_month = billing_month
          and currency = 'JPY' and amount = bill_amount_jpy and amount_jpy = bill_amount_jpy
          and (source_snapshot ->> 'tuition_bill_id')::uuid = bill_id
          and (source_snapshot ->> 'billing_identity_id')::uuid = identity_id
          and (source_snapshot ->> 'billing_exchange_rate')::numeric = billing_exchange_rate
          and (source_snapshot ->> 'billing_amount_cny')::numeric = billing_amount_cny
          and (source_snapshot ->> 'previous_carryover_cny')::numeric = previous_carryover_cny
          and sync_status is null then 'ELIGIBLE_FOR_CASH_SUBMIT'
        else 'BLOCKED_CONFLICT'
      end as result_classification
    from facts
  )
  select
    id,
    result_classification,
    result_classification in ('ELIGIBLE_FOR_CASH_SUBMIT', 'REJECTED_RETRYABLE')
      and current_gate_state = 'enabled',
    current_gate_state,
    case when source_type = 'student_tuition_bill' then 'CNY' else null end,
    case when source_type = 'student_tuition_bill' then billing_amount_cny else null end,
    case when source_type = 'student_tuition_bill' then billing_exchange_rate else null end,
    case when source_type = 'student_tuition_bill' then previous_carryover_cny else null end,
    sync_status,
    cash_request_status
  from classified;
$function$;

revoke all on function public.school_request_cash_income_confirmation_for_record(
  uuid, uuid, uuid, text, text, numeric, text, numeric, text, text
) from public, anon, authenticated;
grant execute on function public.school_request_cash_income_confirmation_for_record(
  uuid, uuid, uuid, text, text, numeric, text, numeric, text, text
) to service_role;

revoke all on function public.school_get_cash_income_submission_preflight(uuid[])
  from public, anon;
grant execute on function public.school_get_cash_income_submission_preflight(uuid[])
  to authenticated, service_role;

revoke all on function public.school_mark_cash_income_request_submitted(uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.school_mark_cash_income_confirmed(uuid, uuid, uuid, timestamptz)
  from public, anon, authenticated;
revoke all on function public.school_mark_cash_income_rejected(uuid, uuid, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.school_mark_cash_income_request_submitted(uuid, uuid, text)
  to service_role;
grant execute on function public.school_mark_cash_income_confirmed(uuid, uuid, uuid, timestamptz)
  to service_role;
grant execute on function public.school_mark_cash_income_rejected(uuid, uuid, text, timestamptz)
  to service_role;

revoke insert, update, delete, truncate, references, trigger
  on table public.school_personal_cash_income_linkage_events
  from anon, authenticated;
grant select on table public.school_personal_cash_income_linkage_events
  to anon, authenticated, service_role;

comment on function public.school_request_cash_income_confirmation_for_record(
  uuid, uuid, uuid, text, text, numeric, text, numeric, text, text
) is 'Creates/reuses the canonical School income Cash linkage attempt. Tuition payment currency/amount/rate come only from the locked canonical bill; client monetary inputs are forbidden. Gate protected; service_role bridge only.';
comment on function public.school_get_cash_income_submission_preflight(uuid[])
  is 'Read-only server-authoritative Cash submission classification and frozen tuition payment display facts.';
