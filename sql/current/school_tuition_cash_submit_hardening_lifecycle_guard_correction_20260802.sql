-- School tuition Cash lifecycle guard correction, 2026-08-02.
-- Status: deployed and rollback-tested on 2026-08-02; Gate remains blocked.
-- Allows only the approved pending -> received lifecycle projection after the
-- service-role linkage event is already synced. Frozen tuition facts remain
-- writable only by the Atomic Writer.

create or replace function public.school_guard_r0_tuition_business_mutation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_income_record_id uuid;
  v_income_source_type text;
  v_authoritative_writer boolean := false;
  v_approved_cash_lifecycle_projection boolean := false;
begin
  if tg_table_name in ('school_student_tuition_bills', 'school_income_records') then
    select exists (
      select 1
      from public.school_tuition_atomic_writer_context context_row
      where context_row.backend_pid = pg_catalog.pg_backend_pid()
        and context_row.transaction_id = pg_catalog.txid_current()
        and context_row.writer_source in (
          'student_tuition_atomic_generate_v1', 'legacy_tuition_cancel'
        )
    ) into v_authoritative_writer;
  end if;

  if tg_table_name = 'school_student_tuition_bills' then
    if not v_authoritative_writer then
      perform public.school_require_feature_gate_state(
        'student_tuition_generate', 'enabled', 'TUITION_GENERATION_BLOCKED',
        '学费应收生成功能正在进行资金一致性整改，当前仅允许预览，禁止生成正式账单或收入。'
      );
      raise exception 'TUITION_DIRECT_DML_FORBIDDEN: tuition bills are writable only by the authoritative atomic writer.';
    end if;
  elsif tg_table_name = 'school_income_records' then
    if coalesce(case when tg_op <> 'DELETE' then new.source_type end, '') = 'student_tuition_bill'
       or coalesce(case when tg_op <> 'INSERT' then old.source_type end, '') = 'student_tuition_bill' then
      if tg_op = 'UPDATE' and not v_authoritative_writer
         and old.status = 'pending' and new.status = 'received'
         and new.receipt_status = 'Cash已确认'
         and (to_jsonb(new) - array['status', 'receipt_status', 'updated_at'])
           = (to_jsonb(old) - array['status', 'receipt_status', 'updated_at']) then
        select exists (
          select 1
          from public.school_personal_cash_income_linkage_events event_row
          where event_row.income_record_id = new.id
            and event_row.source_table = 'school_income_records'
            and event_row.source_event_type = 'tuition_income_received'
            and event_row.sync_status = 'synced'
            and event_row.cash_request_status = 'approved'
            and event_row.cash_request_id is not null
            and event_row.cash_transaction_id is not null
        ) into v_approved_cash_lifecycle_projection;
      end if;

      if not v_authoritative_writer and not v_approved_cash_lifecycle_projection then
        perform public.school_require_feature_gate_state(
          'student_tuition_generate', 'enabled', 'TUITION_GENERATION_BLOCKED',
          '学费应收生成功能正在进行资金一致性整改，当前仅允许预览，禁止生成正式账单或收入。'
        );
        raise exception 'TUITION_DIRECT_DML_FORBIDDEN: tuition income is writable only by an authoritative tuition workflow.';
      end if;
    end if;
  elsif tg_table_name = 'school_personal_cash_income_linkage_events' then
    v_income_record_id := coalesce(
      case when tg_op <> 'DELETE' then new.income_record_id end,
      case when tg_op <> 'INSERT' then old.income_record_id end
    );
    begin
      select income_row.source_type into strict v_income_source_type
      from public.school_income_records income_row
      where income_row.id = v_income_record_id;
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
        'student_tuition_cash_submit', 'enabled', 'TUITION_CASH_SUBMISSION_BLOCKED',
        '学费收入 Cash 提交正在进行资金一致性整改，当前禁止提交。'
      );
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$function$;

revoke all on function public.school_guard_r0_tuition_business_mutation()
  from public, anon, authenticated, service_role;

create or replace function public.school_mark_cash_income_confirmed(
  p_event_id uuid,
  p_cash_request_id uuid,
  p_cash_transaction_id uuid,
  p_confirmed_at timestamptz default null
)
returns table (
  income_id uuid, linkage_event_id uuid, income_status text, sync_status text,
  cash_request_id uuid, cash_request_status text, cash_transaction_id uuid,
  confirmed_at timestamptz, message text
)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_event public.school_personal_cash_income_linkage_events%rowtype;
  v_income public.school_income_records%rowtype;
  v_confirmed_at timestamptz := coalesce(p_confirmed_at, now());
  v_now timestamptz := now();
begin
  if p_event_id is null or p_cash_request_id is null or p_cash_transaction_id is null then
    raise exception 'event id, Cash request id, and Cash transaction id are required';
  end if;

  select * into v_event
  from public.school_personal_cash_income_linkage_events
  where id = p_event_id for update;
  if not found then raise exception 'Cash income linkage event not found: %', p_event_id; end if;
  if v_event.cash_request_id is not null and v_event.cash_request_id is distinct from p_cash_request_id then
    raise exception 'Cash income linkage event references a different Cash request: %', v_event.cash_request_id;
  end if;
  if v_event.cash_transaction_id is not null and v_event.cash_transaction_id is distinct from p_cash_transaction_id then
    raise exception 'Cash income linkage event already references a different Cash transaction: %', v_event.cash_transaction_id;
  end if;

  select * into v_income from public.school_income_records
  where id = v_event.income_record_id for update;
  if not found then raise exception 'income record not found for Cash income linkage event: %', v_event.income_record_id; end if;

  if v_event.sync_status = 'synced' then
    if coalesce(v_income.status, '') <> 'received'
       or v_event.cash_request_id is distinct from p_cash_request_id
       or v_event.cash_transaction_id is distinct from p_cash_transaction_id
       or v_event.cash_request_status is distinct from 'approved' then
      raise exception 'existing synced Cash income linkage event conflicts with approved callback: %', p_event_id;
    end if;
    return query select v_income.id, v_event.id, v_income.status,
      v_event.sync_status, v_event.cash_request_id, v_event.cash_request_status,
      v_event.cash_transaction_id, v_event.confirmed_at,
      'Cash income approval already reflected in School'::text;
    return;
  end if;

  if v_event.sync_status <> 'awaiting_cash_confirmation' then
    raise exception 'Cash income linkage event must be awaiting Cash confirmation before approval callback. current status: %', v_event.sync_status;
  end if;
  if coalesce(v_income.status, '') <> 'pending' then
    raise exception 'income record must remain pending before Cash approval. current status: %', v_income.status;
  end if;

  update public.school_personal_cash_income_linkage_events event_row
  set cash_request_id = p_cash_request_id,
      cash_request_status = 'approved', sync_status = 'synced',
      cash_transaction_id = p_cash_transaction_id,
      confirmed_at = v_confirmed_at, synced_at = v_confirmed_at,
      cash_request_last_checked_at = v_now, last_error = null, updated_at = v_now
  where event_row.id = p_event_id;

  update public.school_income_records income_row
  set status = 'received', receipt_status = 'Cash已确认', updated_at = v_now
  where income_row.id = v_income.id;

  return query
  select income_row.id, event_row.id, income_row.status, event_row.sync_status,
    event_row.cash_request_id, event_row.cash_request_status,
    event_row.cash_transaction_id, event_row.confirmed_at,
    'Cash income approval reflected in School; income marked received without School account ledger side effects'::text
  from public.school_income_records income_row
  join public.school_personal_cash_income_linkage_events event_row on event_row.id = p_event_id
  where income_row.id = v_income.id;
end
$function$;

create or replace function public.school_mark_cash_income_rejected(
  p_event_id uuid,
  p_cash_request_id uuid,
  p_rejected_reason text default null,
  p_rejected_at timestamptz default null
)
returns table (
  income_id uuid, linkage_event_id uuid, income_status text, sync_status text,
  cash_request_id uuid, cash_request_status text, rejected_at timestamptz,
  rejected_reason text, message text
)
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_event public.school_personal_cash_income_linkage_events%rowtype;
  v_income public.school_income_records%rowtype;
  v_rejected_at timestamptz := coalesce(p_rejected_at, now());
  v_reason text := nullif(trim(coalesce(p_rejected_reason, '')), '');
  v_now timestamptz := now();
begin
  if p_event_id is null or p_cash_request_id is null then
    raise exception 'event id and Cash request id are required';
  end if;
  select * into v_event from public.school_personal_cash_income_linkage_events
  where id = p_event_id for update;
  if not found then raise exception 'Cash income linkage event not found: %', p_event_id; end if;
  if v_event.cash_request_id is not null and v_event.cash_request_id is distinct from p_cash_request_id then
    raise exception 'Cash income linkage event references a different Cash request: %', v_event.cash_request_id;
  end if;
  if v_event.cash_transaction_id is not null then
    raise exception 'Cash income linkage event already has a Cash transaction and cannot be rejected: %', p_event_id;
  end if;
  select * into v_income from public.school_income_records
  where id = v_event.income_record_id for update;
  if not found then raise exception 'income record not found for Cash income linkage event: %', v_event.income_record_id; end if;

  if v_event.sync_status = 'cash_rejected' then
    if coalesce(v_income.status, '') <> 'pending'
       or v_event.cash_request_id is distinct from p_cash_request_id
       or v_event.cash_request_status is distinct from 'rejected' then
      raise exception 'existing rejected Cash income linkage event conflicts with rejection callback: %', p_event_id;
    end if;
    return query select v_income.id, v_event.id, v_income.status,
      v_event.sync_status, v_event.cash_request_id, v_event.cash_request_status,
      v_event.rejected_at, v_event.rejected_reason,
      'Cash income rejection already reflected in School'::text;
    return;
  end if;
  if v_event.sync_status <> 'awaiting_cash_confirmation' then
    raise exception 'Cash income linkage event must be awaiting Cash confirmation before rejection callback. current status: %', v_event.sync_status;
  end if;
  if coalesce(v_income.status, '') <> 'pending' then
    raise exception 'income record must remain pending for Cash rejection. current status: %', v_income.status;
  end if;

  update public.school_personal_cash_income_linkage_events event_row
  set cash_request_id = p_cash_request_id, cash_request_status = 'rejected',
      sync_status = 'cash_rejected', rejected_at = v_rejected_at,
      rejected_reason = v_reason, cash_request_last_checked_at = v_now,
      last_error = null, updated_at = v_now
  where event_row.id = p_event_id;

  return query
  select v_income.id, event_row.id, v_income.status, event_row.sync_status,
    event_row.cash_request_id, event_row.cash_request_status,
    event_row.rejected_at, event_row.rejected_reason,
    'Cash income rejection reflected in School; income remains pending and can be retried'::text
  from public.school_personal_cash_income_linkage_events event_row
  where event_row.id = p_event_id;
end
$function$;

revoke all on function public.school_mark_cash_income_confirmed(uuid, uuid, uuid, timestamptz)
  from public, anon, authenticated;
revoke all on function public.school_mark_cash_income_rejected(uuid, uuid, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.school_mark_cash_income_confirmed(uuid, uuid, uuid, timestamptz)
  to service_role;
grant execute on function public.school_mark_cash_income_rejected(uuid, uuid, text, timestamptz)
  to service_role;

comment on function public.school_guard_r0_tuition_business_mutation()
  is 'Protects frozen tuition business facts. Allows only a pending-to-received projection after an approved, synced canonical Cash linkage event already exists.';
