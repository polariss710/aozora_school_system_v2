-- School V2 historical zero-carry evidence writers, resolver and wage contract.
-- Requires school_historical_zero_carry_completion_schema_20260809.sql.
-- Execute with psql -1 after static review and rollback rehearsal.
\set ON_ERROR_STOP on

create or replace function public.school_reject_historical_zero_carry_evidence_mutation()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  raise exception using
    errcode = 'P0001',
    message = 'HISTORICAL_ZERO_CARRY_EVIDENCE_IMMUTABLE';
end
$function$;

drop trigger if exists school_historical_zero_carry_evidence_immutable
  on public.school_student_monthly_settlement_historical_completion_evidence;
create trigger school_historical_zero_carry_evidence_immutable
before update or delete on public.school_student_monthly_settlement_historical_completion_evidence
for each row execute function public.school_reject_historical_zero_carry_evidence_mutation();

create or replace function public.school_guard_ordinary_settlement_against_historical_zero_carry_evidence()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if exists (
    select 1
    from public.school_student_monthly_settlement_historical_completion_evidence e
    where e.student_id = new.student_id
      and e.settlement_month = new.year_month
      and e.business_entity_id = new.business_entity_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'HISTORICAL_ZERO_CARRY_EVIDENCE_ALREADY_AUTHORITATIVE';
  end if;
  return new;
end
$function$;

drop trigger if exists school_guard_ordinary_settlement_historical_zero_carry
  on public.school_student_monthly_settlements;
create trigger school_guard_ordinary_settlement_historical_zero_carry
before insert or update of student_id, year_month, business_entity_id
on public.school_student_monthly_settlements
for each row execute function public.school_guard_ordinary_settlement_against_historical_zero_carry_evidence();

create or replace function public.school_get_student_monthly_settlement_historical_completion_candidate(
  p_student_id uuid,
  p_settlement_month text,
  p_business_entity_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_next_month text;
  v_lesson_manifest jsonb;
  v_lesson_count integer;
  v_lesson_hash text;
  v_makeup_manifest jsonb;
  v_makeup_source_count integer;
  v_makeup_remaining_hours numeric;
  v_makeup_hash text;
  v_revision_count integer;
  v_revision_id uuid;
  v_revision_manifest text;
  v_bill_id uuid;
  v_bill_status text;
  v_bill_currency text;
  v_bill_amount_jpy numeric;
  v_bill_amount_cny numeric;
  v_bill_previous_carry numeric;
  v_income_id uuid;
  v_income_status text;
  v_income_currency text;
  v_income_amount_jpy numeric;
  v_income_reversed_at timestamptz;
  v_cash_count integer;
  v_cash_linkage_id uuid;
  v_cash_request_id uuid;
  v_cash_transaction_id uuid;
  v_cash_transaction_table text;
  v_cash_original_currency text;
  v_cash_original_amount numeric;
  v_cash_payment_currency text;
  v_cash_payment_amount numeric;
  v_cash_sync_status text;
  v_cash_request_status text;
  v_manifest jsonb;
  v_manifest_hash text;
begin
  if p_student_id is null
     or p_business_entity_id is null
     or p_settlement_month is null
     or p_settlement_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'HISTORICAL_ZERO_CARRY_SCOPE_INVALID';
  end if;
  if not exists (
    select 1 from public.school_students s
    where s.id = p_student_id
      and s.app_type = 'school'
      and s.business_entity_id = p_business_entity_id
  ) then
    raise exception 'HISTORICAL_ZERO_CARRY_STUDENT_ENTITY_MISMATCH';
  end if;
  if exists (
    select 1 from public.school_student_monthly_settlements s
    where s.student_id = p_student_id
      and s.year_month = p_settlement_month
      and s.business_entity_id = p_business_entity_id
  ) then
    raise exception 'HISTORICAL_ZERO_CARRY_ORDINARY_SETTLEMENT_EXISTS';
  end if;

  v_next_month := to_char(
    to_date(p_settlement_month || '-01', 'YYYY-MM-DD') + interval '1 month',
    'YYYY-MM'
  );

  select
    count(*)::integer,
    coalesce(jsonb_agg(jsonb_build_object(
      'id', l.id,
      'lesson_type', l.lesson_type,
      'status', l.status,
      'lesson_date', l.lesson_date,
      'student_settlement_month', public.school_resolve_r1d_e_c_lesson_student_month(l.id),
      'teacher_settlement_month', coalesce(l.teacher_settlement_month, l.year_month),
      'student_id', l.student_id,
      'teacher_id', l.teacher_id,
      'subject_id', l.subject_id,
      'business_entity_id', l.business_entity_id,
      'duration_hours', l.duration_hours,
      'actual_minutes', l.actual_minutes,
      'unit_price', l.unit_price,
      'lesson_fee', l.lesson_fee,
      'is_billable', l.is_billable,
      'source_planned_lesson_id', l.planned_lesson_id,
      'created_at', l.created_at,
      'updated_at', l.updated_at
    ) order by l.id), '[]'::jsonb)
  into v_lesson_count, v_lesson_manifest
  from public.school_lesson_records l
  where l.app_type = 'school'
    and l.student_id = p_student_id
    and l.business_entity_id = p_business_entity_id
    and l.voided_at is null
    and public.school_resolve_r1d_e_c_lesson_student_month(l.id) = p_settlement_month;
  v_lesson_hash := encode(extensions.digest(v_lesson_manifest::text, 'sha256'), 'hex');

  select
    count(*)::integer,
    coalesce(sum(source.remaining_hours), 0)::numeric,
    coalesce(jsonb_agg(jsonb_build_object(
      'planned_lesson_id', source.id,
      'source_student_settlement_month', source.student_month,
      'lesson_date', source.lesson_date,
      'duration_hours', source.duration_hours,
      'remaining_hours', source.remaining_hours,
      'status', source.status,
      'business_entity_id', source.business_entity_id,
      'updated_at', source.updated_at
    ) order by source.lesson_date, source.id), '[]'::jsonb)
  into v_makeup_source_count, v_makeup_remaining_hours, v_makeup_manifest
  from (
    select p.id, p.lesson_date, p.duration_hours, p.status, p.business_entity_id,
           p.updated_at,
           public.school_resolve_r1d_e_c_lesson_student_month(p.id) student_month,
           public.school_get_lesson_credit_remaining_hours(p.id) remaining_hours
    from public.school_lesson_records p
    where p.app_type = 'school'
      and p.lesson_type = 'planned'
      and p.status = 'pending_makeup'
      and p.voided_at is null
      and p.student_id = p_student_id
      and p.business_entity_id = p_business_entity_id
      and public.school_get_lesson_credit_remaining_hours(p.id) > 0
  ) source;
  v_makeup_hash := encode(extensions.digest(v_makeup_manifest::text, 'sha256'), 'hex');

  select count(*)::integer
  into v_revision_count
  from public.school_student_tuition_bills b
  join public.school_student_tuition_generation_revisions r on r.tuition_bill_id = b.id
  where b.student_id = p_student_id
    and b.business_entity_id = p_business_entity_id
    and b.billing_month = v_next_month
    and b.cancelled_at is null
    and r.lifecycle_status = 'active';
  if v_revision_count <> 1 then
    raise exception 'HISTORICAL_ZERO_CARRY_ACTIVE_REVISION_NOT_UNIQUE: %', v_revision_count;
  end if;

  select r.id, r.generation_manifest_sha256, b.id, b.status, b.currency,
         b.bill_amount_jpy, b.billing_amount_cny, b.previous_carryover_cny,
         i.id, i.status, i.currency, i.amount_jpy, i.reversed_at
  into strict v_revision_id, v_revision_manifest, v_bill_id, v_bill_status,
       v_bill_currency, v_bill_amount_jpy, v_bill_amount_cny, v_bill_previous_carry,
       v_income_id, v_income_status, v_income_currency, v_income_amount_jpy,
       v_income_reversed_at
  from public.school_student_tuition_bills b
  join public.school_student_tuition_generation_revisions r
    on r.tuition_bill_id = b.id and r.lifecycle_status = 'active'
  join public.school_income_records i on i.id = b.income_record_id
  where b.student_id = p_student_id
    and b.business_entity_id = p_business_entity_id
    and b.billing_month = v_next_month
    and b.cancelled_at is null;

  if v_bill_status <> 'income_created'
     or v_bill_currency <> 'JPY'
     or v_bill_amount_cny is null
     or v_bill_previous_carry <> 0
     or v_income_status <> 'received'
     or v_income_reversed_at is not null
     or v_income_currency <> 'JPY'
     or v_income_amount_jpy is distinct from v_bill_amount_jpy then
    raise exception 'HISTORICAL_ZERO_CARRY_TUITION_CHAIN_INCONSISTENT';
  end if;

  select count(*)::integer
  into v_cash_count
  from public.school_personal_cash_income_linkage_events e
  where e.income_record_id = v_income_id
    and e.sync_status = 'synced'
    and e.cash_request_status = 'approved'
    and e.cash_request_id is not null
    and e.cash_transaction_id is not null;
  if v_cash_count <> 1 then
    raise exception 'HISTORICAL_ZERO_CARRY_APPROVED_CASH_NOT_UNIQUE: %', v_cash_count;
  end if;

  select e.id, e.cash_request_id, e.cash_transaction_id, e.cash_transaction_table,
         e.currency, e.amount, e.payment_currency, e.payment_amount,
         e.sync_status, e.cash_request_status
  into strict v_cash_linkage_id, v_cash_request_id, v_cash_transaction_id,
       v_cash_transaction_table, v_cash_original_currency, v_cash_original_amount,
       v_cash_payment_currency, v_cash_payment_amount, v_cash_sync_status,
       v_cash_request_status
  from public.school_personal_cash_income_linkage_events e
  where e.income_record_id = v_income_id
    and e.sync_status = 'synced'
    and e.cash_request_status = 'approved'
    and e.cash_request_id is not null
    and e.cash_transaction_id is not null;

  if v_cash_original_currency <> 'JPY'
     or v_cash_original_amount is distinct from v_bill_amount_jpy
     or v_cash_payment_currency <> 'CNY'
     or v_cash_payment_amount is distinct from v_bill_amount_cny
     or v_cash_transaction_table <> 'home_cny_transactions' then
    raise exception 'HISTORICAL_ZERO_CARRY_CASH_AMOUNT_OR_CURRENCY_MISMATCH';
  end if;

  v_manifest := jsonb_build_object(
    'evidence_version', 'historical_zero_carry_completion_v1',
    'student_id', p_student_id,
    'settlement_month', p_settlement_month,
    'business_entity_id', p_business_entity_id,
    'final_carry_cny', 0,
    'lesson_count', v_lesson_count,
    'lesson_manifest_sha256', v_lesson_hash,
    'makeup_source_count', v_makeup_source_count,
    'makeup_remaining_hours', v_makeup_remaining_hours,
    'makeup_manifest_sha256', v_makeup_hash,
    'successor_billing_month', v_next_month,
    'active_revision_id', v_revision_id,
    'active_revision_manifest_sha256', v_revision_manifest,
    'tuition_bill_id', v_bill_id,
    'bill_amount_jpy', v_bill_amount_jpy,
    'billing_amount_cny', v_bill_amount_cny,
    'income_record_id', v_income_id,
    'cash_linkage_event_id', v_cash_linkage_id,
    'cash_request_id', v_cash_request_id,
    'cash_transaction_id', v_cash_transaction_id,
    'cash_transaction_currency', v_cash_payment_currency,
    'cash_transaction_amount', v_cash_payment_amount
  );
  v_manifest_hash := encode(extensions.digest(v_manifest::text, 'sha256'), 'hex');

  return jsonb_build_object(
    'student_id', p_student_id,
    'settlement_month', p_settlement_month,
    'business_entity_id', p_business_entity_id,
    'final_carry_cny', 0,
    'lesson_count', v_lesson_count,
    'lesson_manifest', v_lesson_manifest,
    'lesson_manifest_sha256', v_lesson_hash,
    'makeup_source_count', v_makeup_source_count,
    'makeup_remaining_hours', v_makeup_remaining_hours,
    'makeup_manifest', v_makeup_manifest,
    'makeup_manifest_sha256', v_makeup_hash,
    'active_revision_id', v_revision_id,
    'tuition_bill_id', v_bill_id,
    'income_record_id', v_income_id,
    'cash_linkage_event_id', v_cash_linkage_id,
    'cash_request_id', v_cash_request_id,
    'cash_transaction_id', v_cash_transaction_id,
    'cash_transaction_currency', v_cash_payment_currency,
    'evidence_version', 'historical_zero_carry_completion_v1',
    'evidence_manifest', v_manifest,
    'evidence_manifest_sha256', v_manifest_hash,
    'expected_idempotency_key', format(
      'historical-zero-carry:%s:%s:%s:v1',
      p_student_id, p_settlement_month, p_business_entity_id
    ),
    'expected_confirmation', format(
      'CREATE HISTORICAL ZERO CARRY EVIDENCE %s %s %s MANIFEST %s',
      p_student_id, p_settlement_month, p_business_entity_id, v_manifest_hash
    )
  );
end
$function$;

create or replace function public.school_create_student_monthly_settlement_historical_completion_evidence_core(
  p_student_id uuid,
  p_settlement_month text,
  p_business_entity_id uuid,
  p_expected_lesson_manifest_sha256 text,
  p_expected_makeup_manifest_sha256 text,
  p_expected_active_revision_id uuid,
  p_expected_tuition_bill_id uuid,
  p_expected_income_record_id uuid,
  p_expected_cash_linkage_event_id uuid,
  p_expected_cash_request_id uuid,
  p_expected_cash_transaction_id uuid,
  p_created_by_actor_id uuid,
  p_reason text,
  p_confirmation_text text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_candidate jsonb;
  v_payload jsonb;
  v_payload_hash text;
  v_existing public.school_student_monthly_settlement_historical_completion_evidence%rowtype;
  v_inserted public.school_student_monthly_settlement_historical_completion_evidence%rowtype;
begin
  if p_created_by_actor_id is null or not exists (
    select 1 from public.school_app_memberships m
    where m.user_id = p_created_by_actor_id
      and m.is_active
      and m.role in ('admin','operator')
  ) then
    raise exception 'HISTORICAL_ZERO_CARRY_ACTOR_INVALID';
  end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'HISTORICAL_ZERO_CARRY_REASON_REQUIRED';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    concat_ws('|', 'historical_zero_carry_completion_v1', p_student_id::text,
      p_settlement_month, p_business_entity_id::text), 0
  ));
  v_candidate := public.school_get_student_monthly_settlement_historical_completion_candidate(
    p_student_id, p_settlement_month, p_business_entity_id
  );

  if v_candidate->>'lesson_manifest_sha256' is distinct from p_expected_lesson_manifest_sha256
     or v_candidate->>'makeup_manifest_sha256' is distinct from p_expected_makeup_manifest_sha256
     or (v_candidate->>'active_revision_id')::uuid is distinct from p_expected_active_revision_id
     or (v_candidate->>'tuition_bill_id')::uuid is distinct from p_expected_tuition_bill_id
     or (v_candidate->>'income_record_id')::uuid is distinct from p_expected_income_record_id
     or (v_candidate->>'cash_linkage_event_id')::uuid is distinct from p_expected_cash_linkage_event_id
     or (v_candidate->>'cash_request_id')::uuid is distinct from p_expected_cash_request_id
     or (v_candidate->>'cash_transaction_id')::uuid is distinct from p_expected_cash_transaction_id then
    raise exception 'HISTORICAL_ZERO_CARRY_EXPECTED_FACTS_MISMATCH';
  end if;
  if p_idempotency_key is distinct from v_candidate->>'expected_idempotency_key' then
    raise exception 'HISTORICAL_ZERO_CARRY_IDEMPOTENCY_KEY_MISMATCH';
  end if;
  if p_confirmation_text is distinct from v_candidate->>'expected_confirmation' then
    raise exception 'HISTORICAL_ZERO_CARRY_CONFIRMATION_MISMATCH';
  end if;

  v_payload := jsonb_build_object(
    'evidence_manifest_sha256', v_candidate->>'evidence_manifest_sha256',
    'created_by_actor_id', p_created_by_actor_id,
    'reason', btrim(p_reason),
    'confirmation_text', p_confirmation_text,
    'idempotency_key', p_idempotency_key
  );
  v_payload_hash := encode(extensions.digest(v_payload::text, 'sha256'), 'hex');

  select * into v_existing
  from public.school_student_monthly_settlement_historical_completion_evidence e
  where e.student_id = p_student_id
    and e.settlement_month = p_settlement_month
    and e.business_entity_id = p_business_entity_id
  for update;
  if found then
    if v_existing.payload_sha256 is distinct from v_payload_hash
       or v_existing.evidence_manifest_sha256 is distinct from v_candidate->>'evidence_manifest_sha256'
       or v_existing.idempotency_key is distinct from p_idempotency_key then
      raise exception 'HISTORICAL_ZERO_CARRY_IDEMPOTENCY_PAYLOAD_CONFLICT';
    end if;
    return jsonb_build_object(
      'ok', true, 'idempotent', true, 'evidence_id', v_existing.id,
      'evidence_manifest_sha256', v_existing.evidence_manifest_sha256,
      'payload_sha256', v_existing.payload_sha256
    );
  end if;

  insert into public.school_student_monthly_settlement_historical_completion_evidence(
    student_id, settlement_month, business_entity_id, final_carry_cny,
    lesson_count, lesson_manifest, lesson_manifest_sha256,
    makeup_source_count, makeup_remaining_hours, makeup_manifest, makeup_manifest_sha256,
    active_revision_id, tuition_bill_id, income_record_id, cash_linkage_event_id,
    cash_request_id, cash_transaction_id, cash_transaction_currency,
    evidence_version, evidence_manifest, evidence_manifest_sha256,
    idempotency_key, payload_sha256, created_by_actor_id, reason, confirmation_text
  ) values (
    p_student_id, p_settlement_month, p_business_entity_id, 0,
    (v_candidate->>'lesson_count')::integer,
    v_candidate->'lesson_manifest', v_candidate->>'lesson_manifest_sha256',
    (v_candidate->>'makeup_source_count')::integer,
    (v_candidate->>'makeup_remaining_hours')::numeric,
    v_candidate->'makeup_manifest', v_candidate->>'makeup_manifest_sha256',
    (v_candidate->>'active_revision_id')::uuid,
    (v_candidate->>'tuition_bill_id')::uuid,
    (v_candidate->>'income_record_id')::uuid,
    (v_candidate->>'cash_linkage_event_id')::uuid,
    (v_candidate->>'cash_request_id')::uuid,
    (v_candidate->>'cash_transaction_id')::uuid,
    v_candidate->>'cash_transaction_currency',
    v_candidate->>'evidence_version', v_candidate->'evidence_manifest',
    v_candidate->>'evidence_manifest_sha256', p_idempotency_key, v_payload_hash,
    p_created_by_actor_id, btrim(p_reason), p_confirmation_text
  ) returning * into strict v_inserted;

  return jsonb_build_object(
    'ok', true, 'idempotent', false, 'evidence_id', v_inserted.id,
    'evidence_manifest_sha256', v_inserted.evidence_manifest_sha256,
    'payload_sha256', v_inserted.payload_sha256
  );
end
$function$;

create or replace function public.school_local_create_student_monthly_settlement_historical_completion_evidence(
  p_student_id uuid,
  p_settlement_month text,
  p_business_entity_id uuid,
  p_expected_lesson_manifest_sha256 text,
  p_expected_makeup_manifest_sha256 text,
  p_expected_active_revision_id uuid,
  p_expected_tuition_bill_id uuid,
  p_expected_income_record_id uuid,
  p_expected_cash_linkage_event_id uuid,
  p_expected_cash_request_id uuid,
  p_expected_cash_transaction_id uuid,
  p_created_by_actor_id uuid,
  p_reason text,
  p_confirmation_text text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'HISTORICAL_ZERO_CARRY_LOCAL_TRUSTED_ROLE_REQUIRED';
  end if;
  if not (
    p_settlement_month = '2026-07'
    and p_business_entity_id = '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
    and p_student_id in (
      'eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,
      '881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,
      'a7b163a0-201e-4867-9b94-372343356a80'::uuid,
      '4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid
    )
  ) and not exists (
    select 1 from public.school_students s
    where s.id = p_student_id
      and s.business_entity_id = p_business_entity_id
      and (s.name ilike '%codex-test%' or coalesce(s.note, '') ilike '%codex-test%')
  ) then
    raise exception 'HISTORICAL_ZERO_CARRY_LOCAL_SCOPE_NOT_APPROVED';
  end if;

  return public.school_create_student_monthly_settlement_historical_completion_evidence_core(
    p_student_id, p_settlement_month, p_business_entity_id,
    p_expected_lesson_manifest_sha256, p_expected_makeup_manifest_sha256,
    p_expected_active_revision_id, p_expected_tuition_bill_id,
    p_expected_income_record_id, p_expected_cash_linkage_event_id,
    p_expected_cash_request_id, p_expected_cash_transaction_id,
    p_created_by_actor_id, p_reason, p_confirmation_text, p_idempotency_key
  );
end
$function$;

create or replace function public.school_resolve_student_monthly_settlement_effective_state(
  p_student_id uuid,
  p_settlement_month text,
  p_business_entity_id uuid
) returns table(
  student_id uuid,
  settlement_month text,
  business_entity_id uuid,
  effective_complete boolean,
  effective_status text,
  source_type text,
  source_id uuid,
  carry_cny numeric,
  blocker_code text,
  blocker_detail text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_settlement public.school_student_monthly_settlements%rowtype;
  v_historical_settlement_id uuid;
  v_historical_carry numeric;
  v_evidence public.school_student_monthly_settlement_historical_completion_evidence%rowtype;
  v_other_entity_completion boolean;
begin
  if p_student_id is null or p_business_entity_id is null
     or p_settlement_month is null
     or p_settlement_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'SETTLEMENT_EFFECTIVE_SCOPE_INVALID';
  end if;

  select * into v_settlement
  from public.school_student_monthly_settlements s
  where s.student_id = p_student_id
    and s.year_month = p_settlement_month
    and s.business_entity_id = p_business_entity_id
    and s.settlement_status = 'locked'
  order by s.updated_at desc, s.id
  limit 1;
  if found then
    return query select p_student_id, p_settlement_month, p_business_entity_id,
      true, 'ordinary_locked', 'ordinary_settlement', v_settlement.id,
      v_settlement.carryover_amount_cny, null::text, null::text;
    return;
  end if;

  select s.id, b.previous_carryover_cny
  into v_historical_settlement_id, v_historical_carry
  from public.school_student_monthly_settlements s
  join public.school_student_tuition_bills b on b.previous_settlement_id = s.id
  join public.school_student_tuition_generation_revisions r on r.tuition_bill_id = b.id
  where s.student_id = p_student_id
    and s.year_month = p_settlement_month
    and s.business_entity_id = p_business_entity_id
  order by r.created_at desc, r.id desc
  limit 1;
  if found then
    return query select p_student_id, p_settlement_month, p_business_entity_id,
      true, 'historically_consumed_immutable', 'historical_consumed_settlement',
      v_historical_settlement_id, v_historical_carry,
      null::text, null::text;
    return;
  end if;

  select * into v_evidence
  from public.school_student_monthly_settlement_historical_completion_evidence e
  where e.student_id = p_student_id
    and e.settlement_month = p_settlement_month
    and e.business_entity_id = p_business_entity_id;
  if found then
    return query select p_student_id, p_settlement_month, p_business_entity_id,
      true, 'historical_zero_carry_complete', 'historical_zero_carry_evidence',
      v_evidence.id, 0::numeric, null::text, null::text;
    return;
  end if;

  select exists(
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = p_student_id
      and s.year_month = p_settlement_month
      and s.business_entity_id is distinct from p_business_entity_id
      and (
        s.settlement_status = 'locked'
        or exists (
          select 1 from public.school_student_tuition_bills b
          join public.school_student_tuition_generation_revisions r on r.tuition_bill_id = b.id
          where b.previous_settlement_id = s.id
        )
      )
    union all
    select 1
    from public.school_student_monthly_settlement_historical_completion_evidence e
    where e.student_id = p_student_id
      and e.settlement_month = p_settlement_month
      and e.business_entity_id is distinct from p_business_entity_id
  ) into v_other_entity_completion;

  return query select p_student_id, p_settlement_month, p_business_entity_id,
    false, 'incomplete', null::text, null::uuid, null::numeric,
    case when v_other_entity_completion
      then 'WAGE_SETTLEMENT_BUSINESS_ENTITY_MISMATCH'
      else 'WAGE_EFFECTIVE_SETTLEMENT_MISSING' end,
    case when v_other_entity_completion
      then 'A completed settlement fact exists only under another business entity.'
      else 'No ordinary locked settlement, historically consumed immutable settlement, or approved historical zero-carry evidence exists.' end;
end
$function$;

create or replace function public.school_get_student_monthly_settlement_effective_states(p_settlement_ids uuid[])
returns table(
  settlement_id uuid, physical_status text, effective_status text,
  immutable_error_code text, consumed_generation_identity_id uuid,
  consumed_revision_id uuid, consumed_bill_id uuid, frozen_carryover_cny numeric,
  editable boolean, unlockable boolean, relockable boolean,
  display_label text, immutable_reason text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  with requested as (
    select s.*
    from public.school_student_monthly_settlements s
    where s.id = any(coalesce(p_settlement_ids, '{}'::uuid[]))
  ), resolved as (
    select s.*, e.*
    from requested s
    cross join lateral public.school_resolve_student_monthly_settlement_effective_state(
      s.student_id, s.year_month, s.business_entity_id
    ) e
  ), consumed as (
    select r.id settlement_id,
      claim.generation_identity_id, claim.revision_id, claim.bill_id, claim.carry
    from requested r
    left join lateral (
      select gr.generation_identity_id, gr.id revision_id, b.id bill_id,
             b.previous_carryover_cny carry
      from public.school_student_tuition_bills b
      join public.school_student_tuition_generation_revisions gr on gr.tuition_bill_id = b.id
      where b.previous_settlement_id = r.id
      order by gr.created_at desc, gr.id desc
      limit 1
    ) claim on true
  )
  select r.id, r.settlement_status, r.effective_status,
    case when r.effective_status = 'historically_consumed_immutable'
      then 'TUITION_CONSUMED_SETTLEMENT_IMMUTABLE' end,
    c.generation_identity_id, c.revision_id, c.bill_id,
    coalesce(c.carry, r.carryover_amount_cny),
    (c.bill_id is null),
    (c.bill_id is null and r.settlement_status = 'locked'),
    (c.bill_id is null and r.settlement_status = 'unlocked'),
    case r.effective_status
      when 'historically_consumed_immutable' then '已被历史学费账单消费（不可重开）'
      when 'ordinary_locked' then '已锁定'
      else '锁定已撤销' end,
    case when r.effective_status = 'historically_consumed_immutable'
      then '该结算已被历史学费账单消费，作为冻结历史事实保留，不能重新打开或覆盖。' end
  from resolved r
  left join consumed c on c.settlement_id = r.id
$function$;

create or replace function public.school_get_teacher_monthly_wage_generation_candidate_facts(
  p_year_month text,
  p_teacher_id uuid,
  p_business_entity_id uuid
) returns table(
  lesson_record_id uuid, lesson_date date, start_time text, end_time text,
  student_id uuid, teacher_id uuid, subject_id uuid, business_entity_id uuid,
  lesson_status text, lesson_content text, actual_minutes integer,
  teacher_name text, student_name text, subject_name text, business_name text,
  student_settlement_month text, fact_complete boolean,
  active_rule_count integer, wage_rule_id uuid, settlement_type text,
  hourly_rate_jpy numeric, pay_hours numeric, lesson_wage_jpy numeric,
  is_no_wage boolean, effective_complete boolean, effective_status text,
  effective_source_type text, effective_source_id uuid, effective_carry_cny numeric,
  settlement_blocker_code text, settlement_blocker_detail text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  with raw as (
    select lr.id lesson_record_id, lr.lesson_date, lr.start_time, lr.end_time,
      lr.student_id, lr.teacher_id, lr.subject_id, lr.business_entity_id,
      lr.status lesson_status, lr.lesson_content, lr.actual_minutes,
      coalesce(t.display_name, t.name) teacher_name,
      coalesce(s.display_name, s.name) student_name,
      sub.name subject_name, be.name business_name,
      case when lr.student_id is not null then
        public.school_resolve_r1d_e_c_lesson_student_month(lr.id) end student_settlement_month,
      (lr.teacher_id is not null and lr.student_id is not null and lr.subject_id is not null
       and lr.business_entity_id is not null and lr.actual_minutes is not null
       and lr.actual_minutes >= 0) fact_complete
    from public.school_lesson_records lr
    left join public.school_teachers t on t.id = lr.teacher_id
    left join public.school_students s on s.id = lr.student_id
    left join public.school_subjects sub on sub.id = lr.subject_id
    left join public.school_business_entities be on be.id = lr.business_entity_id
    where lr.app_type = 'school'
      and lr.lesson_type = 'actual'
      and lr.status in ('completed','makeup_completed')
      and lr.voided_at is null
      and coalesce(lr.teacher_settlement_month, lr.year_month) = p_year_month
      and (p_teacher_id is null or lr.teacher_id = p_teacher_id)
      and (p_business_entity_id is null or lr.business_entity_id = p_business_entity_id)
  ), matched as (
    select raw.*, rules.active_rule_count, rules.wage_rule_id,
      rules.settlement_type, rules.hourly_rate_jpy
    from raw
    cross join lateral (
      select count(r.id)::integer active_rule_count,
        case when count(r.id) = 1 then min(r.id::text)::uuid end wage_rule_id,
        case when count(r.id) = 1 then min(r.settlement_type) end settlement_type,
        case when count(r.id) = 1 then min(r.hourly_rate_jpy) end hourly_rate_jpy
      from public.school_teacher_wage_rules r
      where r.teacher_id = raw.teacher_id
        and r.student_id = raw.student_id
        and r.subject_id = raw.subject_id
        and r.business_entity_id = raw.business_entity_id
        and coalesce(r.is_active, true)
    ) rules
  ), effective as (
    select matched.*, state.effective_complete resolved_complete,
      state.effective_status resolved_status, state.source_type resolved_source_type,
      state.source_id resolved_source_id, state.carry_cny resolved_carry,
      state.blocker_code resolved_blocker_code, state.blocker_detail resolved_blocker_detail
    from matched
    left join lateral public.school_resolve_student_monthly_settlement_effective_state(
      matched.student_id, matched.student_settlement_month, matched.business_entity_id
    ) state on matched.fact_complete and matched.active_rule_count = 1
      and matched.settlement_type <> 'no_wage'
  )
  select lesson_record_id, lesson_date, start_time, end_time,
    student_id, teacher_id, subject_id, business_entity_id,
    lesson_status, lesson_content, actual_minutes,
    teacher_name, student_name, subject_name, business_name,
    student_settlement_month, fact_complete, active_rule_count, wage_rule_id,
    settlement_type, hourly_rate_jpy,
    case when active_rule_count <> 1 then null
         when settlement_type = 'no_wage' then 0
         else actual_minutes::numeric / 60 end,
    case when active_rule_count <> 1 then null
         when settlement_type = 'no_wage' then 0
         else round((actual_minutes::numeric / 60) * hourly_rate_jpy) end,
    (active_rule_count = 1 and settlement_type = 'no_wage'),
    case when active_rule_count = 1 and settlement_type = 'no_wage' then true
         else resolved_complete end,
    case when active_rule_count = 1 and settlement_type = 'no_wage'
         then 'no_wage_not_required' else resolved_status end,
    resolved_source_type, resolved_source_id, resolved_carry,
    resolved_blocker_code, resolved_blocker_detail
  from effective
$function$;

create or replace function public.school_get_teacher_monthly_wage_generation_preflight(
  p_year_month text,
  p_teacher_id uuid,
  p_business_entity_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_result jsonb;
begin
  perform public.school_require_current_app_admin();
  if p_year_month is null or p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'WAGE_MONTH_INVALID';
  end if;
  if p_teacher_id is not null and not exists(
    select 1 from public.school_teachers t where t.id = p_teacher_id and t.app_type = 'school'
  ) then raise exception 'WAGE_TEACHER_INVALID'; end if;
  if p_business_entity_id is not null and not exists(
    select 1 from public.school_business_entities b where b.id = p_business_entity_id
  ) then raise exception 'WAGE_BUSINESS_ENTITY_INVALID'; end if;

  with candidates as materialized (
    select * from public.school_get_teacher_monthly_wage_generation_candidate_facts(
      p_year_month, p_teacher_id, p_business_entity_id
    )
  ), classified as (
    select c.*,
      case
        when not c.fact_complete then 'WAGE_LESSON_FACT_INCOMPLETE'
        when c.active_rule_count = 0 then 'WAGE_RULE_MISSING'
        when c.active_rule_count > 1 then 'WAGE_RULE_DUPLICATE'
        when not coalesce(c.effective_complete, false) then
          coalesce(c.settlement_blocker_code, 'WAGE_EFFECTIVE_SETTLEMENT_MISSING')
      end blocker_code,
      case
        when not c.fact_complete then 'Required teacher/student/subject/business entity/actual minutes are incomplete.'
        when c.active_rule_count = 0 then 'No unique active wage rule exists.'
        when c.active_rule_count > 1 then 'Multiple active wage rules match this lesson.'
        when not coalesce(c.effective_complete, false) then c.settlement_blocker_detail
      end blocker_detail
    from candidates c
  ), teacher_preview as (
    select teacher_id, max(teacher_name) teacher_name, business_entity_id,
      max(business_name) business_name, count(*)::integer lesson_count,
      sum(actual_minutes)::numeric total_minutes,
      count(*) filter(where is_no_wage)::integer no_wage_lesson_count,
      coalesce(sum(actual_minutes) filter(where is_no_wage),0)::numeric no_wage_minutes,
      coalesce(sum(pay_hours),0)::numeric pay_hours,
      coalesce(sum(lesson_wage_jpy),0)::numeric amount_jpy
    from classified
    where blocker_code is null
    group by teacher_id,business_entity_id
  ), blockers as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'blocker_code', blocker_code,
      'blocker_detail', blocker_detail,
      'lesson_record_id', lesson_record_id,
      'teacher_id', teacher_id,
      'student_id', student_id,
      'subject_id', subject_id,
      'business_entity_id', business_entity_id,
      'student_settlement_month', student_settlement_month,
      'active_rule_count', active_rule_count,
      'wage_rule_id', wage_rule_id,
      'settlement_type', settlement_type,
      'effective_status', effective_status,
      'effective_source_type', effective_source_type,
      'effective_source_id', effective_source_id
    ) order by blocker_code,student_name,lesson_record_id) filter(where blocker_code is not null), '[]'::jsonb) rows
    from classified
  )
  select jsonb_build_object(
    'year_month', p_year_month,
    'summary', jsonb_build_object(
      'candidate_actual_count', (select count(*) from classified),
      'candidate_teacher_count', (select count(distinct teacher_id) from classified),
      'total_minutes', coalesce((select sum(actual_minutes) from classified),0),
      'missing_rule_count', (select count(*) from classified where blocker_code='WAGE_RULE_MISSING'),
      'duplicate_rule_count', (select count(*) from classified where blocker_code='WAGE_RULE_DUPLICATE'),
      'incomplete_lesson_count', (select count(*) from classified where blocker_code='WAGE_LESSON_FACT_INCOMPLETE'),
      'no_wage_lesson_count', (select count(*) from classified where active_rule_count=1 and is_no_wage),
      'no_wage_minutes', coalesce((select sum(actual_minutes) from classified where active_rule_count=1 and is_no_wage),0),
      'student_settlement_blocker_count', (select count(*) from classified where blocker_code in ('WAGE_EFFECTIVE_SETTLEMENT_MISSING','WAGE_SETTLEMENT_BUSINESS_ENTITY_MISMATCH')),
      'student_settlement_blocker_group_count', (select count(*) from (select distinct student_id,student_settlement_month,business_entity_id from classified where blocker_code in ('WAGE_EFFECTIVE_SETTLEMENT_MISSING','WAGE_SETTLEMENT_BUSINESS_ENTITY_MISMATCH')) g),
      'blocker_count', (select count(*) from classified where blocker_code is not null),
      'active_wage_lock_count', (select count(*) from public.school_teacher_wage_locks w where w.settlement_month=p_year_month and w.status='locked' and w.voided_at is null and (p_teacher_id is null or w.teacher_id=p_teacher_id) and (p_business_entity_id is null or w.business_entity_id=p_business_entity_id)),
      'existing_wage_detail_count', (select count(*) from classified c where exists(select 1 from public.school_teacher_wage_lock_details d join public.school_teacher_wage_locks w on w.id=d.lock_id where d.lesson_record_id=c.lesson_record_id and w.status='locked' and w.voided_at is null)),
      'conditional_pay_hours', coalesce((select sum(pay_hours) from classified where blocker_code is null),0),
      'conditional_amount_jpy', coalesce((select sum(lesson_wage_jpy) from classified where blocker_code is null),0)
    ),
    'teacher_previews', coalesce((select jsonb_agg(to_jsonb(t) order by teacher_name,teacher_id) from teacher_preview t), '[]'::jsonb),
    'blockers', (select rows from blockers)
  ) into v_result;
  return v_result;
end
$function$;

create or replace function public.school_generate_teacher_monthly_wage(
  p_year_month text,
  p_teacher_id uuid,
  p_business_entity_id uuid
) returns table (
  wage_lock_id uuid, teacher_id uuid, teacher_name text, settlement_month text,
  business_entity_id uuid, business_name text, lesson_count integer,
  total_minutes numeric, pay_hours numeric, lesson_wage_jpy numeric,
  total_jpy numeric, status text, locked_at timestamptz, detail_count integer
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_preflight jsonb;
  v_summary jsonb;
  v_first_blocker text;
begin
  perform public.school_require_current_app_admin();
  v_preflight := public.school_get_teacher_monthly_wage_generation_preflight(
    p_year_month,p_teacher_id,p_business_entity_id
  );
  v_summary := v_preflight->'summary';
  if (v_summary->>'candidate_actual_count')::integer = 0 then
    raise exception 'WAGE_NO_CANDIDATES';
  end if;
  if (v_summary->>'active_wage_lock_count')::integer > 0 then
    raise exception 'WAGE_ACTIVE_LOCK_EXISTS';
  end if;
  if (v_summary->>'existing_wage_detail_count')::integer > 0 then
    raise exception 'WAGE_DETAIL_ALREADY_CONSUMED';
  end if;
  if (v_summary->>'blocker_count')::integer > 0 then
    select value->>'blocker_code' into v_first_blocker
    from jsonb_array_elements(v_preflight->'blockers')
    order by case value->>'blocker_code'
      when 'WAGE_LESSON_FACT_INCOMPLETE' then 1
      when 'WAGE_RULE_MISSING' then 2
      when 'WAGE_RULE_DUPLICATE' then 3
      when 'WAGE_SETTLEMENT_BUSINESS_ENTITY_MISMATCH' then 4
      else 5 end
    limit 1;
    raise exception using errcode='P0001', message=coalesce(v_first_blocker,'WAGE_PREFLIGHT_BLOCKED');
  end if;

  return query
  with candidates as materialized (
    select * from public.school_get_teacher_monthly_wage_generation_candidate_facts(
      p_year_month,p_teacher_id,p_business_entity_id
    )
  ), lock_groups as (
    select c.teacher_id,max(c.teacher_name) teacher_name,c.business_entity_id,
      max(c.business_name) business_name,
      case when bool_and(c.is_no_wage) then 'no_wage' else 'jpy_hourly' end settlement_type,
      count(*)::integer lesson_count,sum(c.actual_minutes)::numeric total_minutes,
      sum(c.pay_hours)::numeric pay_hours,sum(c.lesson_wage_jpy)::numeric lesson_wage_jpy,
      sum(c.lesson_wage_jpy)::numeric total_jpy
    from candidates c
    group by c.teacher_id,c.business_entity_id
  ), inserted_locks as (
    insert into public.school_teacher_wage_locks as w(
      settlement_month,teacher_id,teacher_name,business_entity_id,business_name,
      settlement_type,exchange_rate,total_minutes,pay_hours,lesson_wage_jpy,
      lesson_wage_cny,fee_jpy,total_jpy,total_cny,lesson_count,status,locked_at,updated_at
    ) select p_year_month,g.teacher_id,g.teacher_name,g.business_entity_id,g.business_name,
      g.settlement_type,0,g.total_minutes,g.pay_hours,g.lesson_wage_jpy,0,0,g.total_jpy,0,
      g.lesson_count,'locked',now(),now() from lock_groups g
    returning w.id,w.teacher_id,w.teacher_name,w.settlement_month,w.business_entity_id,
      w.business_name,w.lesson_count,w.total_minutes,w.pay_hours,w.lesson_wage_jpy,
      w.total_jpy,w.status,w.locked_at
  ), inserted_details as (
    insert into public.school_teacher_wage_lock_details as d(
      lock_id,lesson_record_id,lesson_date,start_time,end_time,student_id,student_name,
      subject_id,subject_name,business_entity_id,business_name,pay_hours,lesson_wage_jpy,
      lesson_wage_cny,transport_fee_jpy,classroom_fee_jpy,total_jpy,total_cny,
      settlement_type,exchange_rate,is_no_wage,status,lesson_content
    ) select il.id,c.lesson_record_id,c.lesson_date,c.start_time,c.end_time,c.student_id,
      c.student_name,c.subject_id,c.subject_name,c.business_entity_id,c.business_name,
      c.pay_hours,c.lesson_wage_jpy,0,0,0,c.lesson_wage_jpy,0,c.settlement_type,0,
      c.is_no_wage,c.lesson_status,c.lesson_content
    from candidates c join inserted_locks il on il.teacher_id=c.teacher_id
      and il.business_entity_id is not distinct from c.business_entity_id
    returning d.lock_id
  ), detail_counts as (
    select lock_id,count(*)::integer detail_count from inserted_details group by lock_id
  )
  select il.id,il.teacher_id,il.teacher_name,il.settlement_month,il.business_entity_id,
    il.business_name,il.lesson_count,il.total_minutes,il.pay_hours,il.lesson_wage_jpy,
    il.total_jpy,il.status,il.locked_at,dc.detail_count
  from inserted_locks il join detail_counts dc on dc.lock_id=il.id
  order by il.teacher_name nulls last,il.teacher_id;
end
$function$;

create or replace function public.school_generate_teacher_monthly_wage(
  p_year_month text,
  p_teacher_id uuid default null
) returns table (
  wage_lock_id uuid, teacher_id uuid, teacher_name text, settlement_month text,
  business_entity_id uuid, business_name text, lesson_count integer,
  total_minutes numeric, pay_hours numeric, lesson_wage_jpy numeric,
  total_jpy numeric, status text, locked_at timestamptz, detail_count integer
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  perform public.school_require_current_app_admin();
  return query select * from public.school_generate_teacher_monthly_wage(
    p_year_month,p_teacher_id,null::uuid
  );
end
$function$;

revoke all on function public.school_reject_historical_zero_carry_evidence_mutation()
  from public, anon, authenticated, service_role;
revoke all on function public.school_guard_ordinary_settlement_against_historical_zero_carry_evidence()
  from public, anon, authenticated, service_role;
revoke all on function public.school_get_student_monthly_settlement_historical_completion_candidate(uuid,text,uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.school_get_student_monthly_settlement_historical_completion_candidate(uuid,text,uuid)
  to service_role;
revoke all on function public.school_create_student_monthly_settlement_historical_completion_evidence_core(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_local_create_student_monthly_settlement_historical_completion_evidence(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.school_local_create_student_monthly_settlement_historical_completion_evidence(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)
  to service_role;
revoke all on function public.school_resolve_student_monthly_settlement_effective_state(uuid,text,uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.school_resolve_student_monthly_settlement_effective_state(uuid,text,uuid)
  to authenticated, service_role;
revoke all on function public.school_get_student_monthly_settlement_effective_states(uuid[])
  from public, anon, authenticated, service_role;
grant execute on function public.school_get_student_monthly_settlement_effective_states(uuid[])
  to authenticated, service_role;
revoke all on function public.school_get_teacher_monthly_wage_generation_candidate_facts(text,uuid,uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)
  to authenticated;
revoke all on function public.school_generate_teacher_monthly_wage(text,uuid,uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.school_generate_teacher_monthly_wage(text,uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.school_generate_teacher_monthly_wage(text,uuid,uuid)
  to authenticated;
grant execute on function public.school_generate_teacher_monthly_wage(text,uuid)
  to authenticated;

comment on function public.school_get_student_monthly_settlement_historical_completion_candidate(uuid,text,uuid) is
  'Service-role-only read preview that DB-builds all exact immutable evidence facts; callers may compare but never calculate persisted manifests.';
comment on function public.school_create_student_monthly_settlement_historical_completion_evidence_core(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text) is
  'Owner-only append-only historical zero-carry evidence writer with DB recomputation, exact expected facts, scope lock and payload idempotency.';
comment on function public.school_local_create_student_monthly_settlement_historical_completion_evidence(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text) is
  'Service-role-only local trusted wrapper for the four approved 2026-07 scopes; no browser entry point.';
comment on function public.school_resolve_student_monthly_settlement_effective_state(uuid,text,uuid) is
  'Sole scope resolver: ordinary locked, historically consumed immutable, approved historical zero-carry evidence, then incomplete; never crosses business entities.';
comment on function public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid) is
  'Read-only structured wage preflight using the same candidate/rule/effective resolver contract as the writer. no_wage remains auditable and skips student settlement completion.';
comment on function public.school_generate_teacher_monthly_wage(text,uuid,uuid) is
  'Generates wage locks/details only after the shared structured preflight passes. Unique no_wage lessons remain zero-value details and skip effective settlement; payable lessons require completion.';
