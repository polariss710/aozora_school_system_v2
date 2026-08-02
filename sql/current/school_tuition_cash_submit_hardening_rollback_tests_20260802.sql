-- School tuition Cash hardening authoritative-writer rollback tests, 2026-08-02.
-- Canonical tuition objects are generated only by the owner-only Atomic Core.
-- Every fixture write is inside this transaction and must roll back.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout = '10s';
set local statement_timeout = '240s';

create temporary table tuition_cash_fixture (
  fixture_name text primary key,
  student_id uuid not null,
  planned_lesson_id uuid not null,
  billing_identity_id uuid not null,
  tuition_bill_id uuid not null,
  income_record_id uuid not null,
  billing_amount_cny numeric not null,
  billing_exchange_rate numeric not null,
  linkage_event_id uuid,
  cash_request_id uuid,
  cash_transaction_id uuid
) on commit drop;

do $fixture$
declare
  v_source public.school_lesson_records%rowtype;
  v_student_a constant uuid := 'f2fc0000-0000-4000-8000-00000000a001';
  v_student_b constant uuid := 'f2fc0000-0000-4000-8000-00000000a002';
  v_planned_a uuid;
  v_planned_b uuid;
  v_preview record;
  v_result record;
begin
  select lesson.* into strict v_source
  from public.school_lesson_records lesson
  join public.school_students student on student.id = lesson.student_id
  where lesson.app_type = 'school'
    and lesson.lesson_type = 'planned'
    and lesson.status = 'planned'
    and lesson.voided_at is null
    and lesson.teacher_id is not null
    and lesson.subject_id is not null
    and lesson.business_entity_id is not null
    and student.business_entity_id is not distinct from lesson.business_entity_id
  order by lesson.id
  limit 1;

  insert into public.school_students (
    id, student_code, name, display_name, business_entity_id, status, app_type,
    preset_exchange_rate, previous_balance_cny, note
  ) values
    (v_student_a, 'codex-tuition-cash-a', 'codex-test tuition Cash A',
      'codex-test tuition Cash A', v_source.business_entity_id, 'active', 'school',
      0.05, 0, 'codex-test tuition-cash-hardening authoritative rollback'),
    (v_student_b, 'codex-tuition-cash-b', 'codex-test tuition Cash B',
      'codex-test tuition Cash B', v_source.business_entity_id, 'active', 'school',
      0.05, 0, 'codex-test tuition-cash-hardening authoritative rollback');

  select created.lesson_id into strict v_planned_a
  from public.school_create_planned_lesson_record(
    date '2099-08-09', v_student_a, v_source.teacher_id, v_source.subject_id,
    v_source.business_entity_id, '15:00', '17:00', 0, 10000, null,
    'planned', 2, 'codex-test tuition Cash A planned',
    'codex-test tuition-cash-hardening authoritative rollback'
  ) created;
  select * into strict v_preview
  from public.school_get_student_tuition_validation_preview_details(
    v_student_a, '2099-08', 0.05
  );
  select * into strict v_result
  from public.school_generate_student_tuition_bill_atomic_core(
    v_student_a, '2099-08', 0.05, v_preview.generation_manifest_sha256,
    'codex-test tuition-cash-hardening authoritative rollback', null
  );
  insert into tuition_cash_fixture
  values ('approve', v_student_a, v_planned_a, v_result.billing_identity_id,
    v_result.tuition_bill_id, v_result.income_record_id,
    v_result.billing_amount_cny, 0.05, null, null, null);

  select created.lesson_id into strict v_planned_b
  from public.school_create_planned_lesson_record(
    date '2099-09-13', v_student_b, v_source.teacher_id, v_source.subject_id,
    v_source.business_entity_id, '15:00', '17:00', 0, 8000, null,
    'planned', 1, 'codex-test tuition Cash B planned',
    'codex-test tuition-cash-hardening authoritative rollback'
  ) created;
  select * into strict v_preview
  from public.school_get_student_tuition_validation_preview_details(
    v_student_b, '2099-09', 0.04
  );
  select * into strict v_result
  from public.school_generate_student_tuition_bill_atomic_core(
    v_student_b, '2099-09', 0.04, v_preview.generation_manifest_sha256,
    'codex-test tuition-cash-hardening authoritative rollback', null
  );
  insert into tuition_cash_fixture
  values ('reject_retry', v_student_b, v_planned_b, v_result.billing_identity_id,
    v_result.tuition_bill_id, v_result.income_record_id,
    v_result.billing_amount_cny, 0.04, null, null, null);

  if exists (select 1 from public.school_tuition_atomic_writer_context) then
    raise exception 'TUITION_CASH_WRITER_CONTEXT_RESIDUE_AFTER_ATOMIC_CORE';
  end if;
end
$fixture$;

-- Gate blocked must reject the canonical fixture without creating linkage.
do $gate$
declare v_income uuid;
begin
  select income_record_id into v_income from tuition_cash_fixture where fixture_name = 'approve';
  begin
    perform * from public.school_request_cash_income_confirmation_for_record(
      v_income, '8596a708-d99f-4264-8f8c-5b89af9254b6',
      'f2fc0000-0000-4000-8000-00000000c001', 'codex-test CNY account', 'bank',
      null, null, null, null, null
    );
    raise exception 'EXPECTED_TUITION_GATE_BLOCK_MISSING';
  exception when others then
    if sqlerrm = 'EXPECTED_TUITION_GATE_BLOCK_MISSING'
       or position('TUITION_CASH_SUBMISSION_BLOCKED' in sqlerrm) = 0 then
      raise;
    end if;
  end;
end
$gate$;

update public.school_feature_gates
set state = 'enabled'
where feature_key = 'student_tuition_cash_submit';

-- Create and sequentially reuse the same active School linkage event.
do $submit$
declare
  v_fixture tuition_cash_fixture%rowtype;
  v_first record;
  v_second record;
begin
  select * into strict v_fixture from tuition_cash_fixture where fixture_name = 'approve';
  select * into strict v_first
  from public.school_request_cash_income_confirmation_for_record(
    v_fixture.income_record_id, '8596a708-d99f-4264-8f8c-5b89af9254b6',
    'f2fc0000-0000-4000-8000-00000000c001', 'codex-test CNY account', 'bank',
    null, null, null, 'codex-test submit rollback', null
  );
  select * into strict v_second
  from public.school_request_cash_income_confirmation_for_record(
    v_fixture.income_record_id, '8596a708-d99f-4264-8f8c-5b89af9254b6',
    'f2fc0000-0000-4000-8000-00000000c001', 'codex-test CNY account', 'bank',
    null, null, null, 'codex-test submit rollback', null
  );
  if v_first.linkage_event_id is distinct from v_second.linkage_event_id
     or v_first.attempt_no <> 1
     or v_first.payment_currency <> 'CNY'
     or v_first.payment_amount is distinct from v_fixture.billing_amount_cny
     or v_first.payment_exchange_rate is distinct from v_fixture.billing_exchange_rate then
    raise exception 'TUITION_CASH_SCHOOL_DUPLICATE_OR_AUTHORITY_FAILED';
  end if;
  update tuition_cash_fixture set linkage_event_id = v_first.linkage_event_id
  where fixture_name = 'approve';
end
$submit$;

-- Every non-empty tuition monetary input fails closed.
do $tamper$
declare v_fixture tuition_cash_fixture%rowtype; v_case record;
begin
  select * into strict v_fixture from tuition_cash_fixture where fixture_name = 'approve';
  for v_case in select * from (values
    (v_fixture.billing_amount_cny, null::text, null::numeric, null::text),
    (null::numeric, 'CNY'::text, null::numeric, null::text),
    (null::numeric, null::text, v_fixture.billing_exchange_rate, null::text),
    (null::numeric, null::text, null::numeric, 'round'::text)
  ) cases(amount_value, currency_value, rate_value, rounding_value)
  loop
    begin
      perform * from public.school_request_cash_income_confirmation_for_record(
        v_fixture.income_record_id, '8596a708-d99f-4264-8f8c-5b89af9254b6',
        'f2fc0000-0000-4000-8000-00000000c001', 'codex-test CNY account', 'bank',
        v_case.amount_value, v_case.currency_value, v_case.rate_value, null,
        v_case.rounding_value
      );
      raise exception 'EXPECTED_TUITION_TAMPER_REJECTION_MISSING';
    exception when others then
      if sqlerrm = 'EXPECTED_TUITION_TAMPER_REJECTION_MISSING'
         or position('客户端不得提交' in sqlerrm) = 0 then raise; end if;
    end;
  end loop;
end
$tamper$;

-- Cash request creation followed by School submitted writeback is retry-safe.
do $callback$
declare v_fixture tuition_cash_fixture%rowtype; v_first record; v_second record;
begin
  select * into strict v_fixture from tuition_cash_fixture where fixture_name = 'approve';
  select * into strict v_first
  from public.school_mark_cash_income_request_submitted(
    v_fixture.linkage_event_id,
    'f2fc0000-0000-4000-8000-00000000d001', 'pending'
  );
  select * into strict v_second
  from public.school_mark_cash_income_request_submitted(
    v_fixture.linkage_event_id,
    'f2fc0000-0000-4000-8000-00000000d001', 'pending'
  );
  if v_first.cash_request_id is distinct from v_second.cash_request_id
     or v_second.sync_status <> 'awaiting_cash_confirmation' then
    raise exception 'TUITION_CASH_SUBMITTED_CALLBACK_NOT_IDEMPOTENT';
  end if;
  update tuition_cash_fixture
  set cash_request_id = v_first.cash_request_id
  where fixture_name = 'approve';
end
$callback$;

-- Confirm callback is idempotent, then received income cannot be resubmitted.
do $confirm$
declare v_fixture tuition_cash_fixture%rowtype; v_first record; v_second record;
begin
  select * into strict v_fixture from tuition_cash_fixture where fixture_name = 'approve';
  select * into strict v_first
  from public.school_mark_cash_income_confirmed(
    v_fixture.linkage_event_id, v_fixture.cash_request_id,
    'f2fc0000-0000-4000-8000-00000000e001', now()
  );
  select * into strict v_second
  from public.school_mark_cash_income_confirmed(
    v_fixture.linkage_event_id, v_fixture.cash_request_id,
    'f2fc0000-0000-4000-8000-00000000e001', now()
  );
  if v_first.cash_transaction_id is distinct from v_second.cash_transaction_id
     or (select status from public.school_income_records where id = v_fixture.income_record_id) <> 'received' then
    raise exception 'TUITION_CASH_CONFIRM_CALLBACK_NOT_IDEMPOTENT';
  end if;
  begin
    perform * from public.school_request_cash_income_confirmation_for_record(
      v_fixture.income_record_id, '8596a708-d99f-4264-8f8c-5b89af9254b6',
      'f2fc0000-0000-4000-8000-00000000c001', 'codex-test CNY account', 'bank',
      null, null, null, null, null
    );
    raise exception 'EXPECTED_RECEIVED_RESUBMIT_REJECTION_MISSING';
  exception when others then
    if sqlerrm = 'EXPECTED_RECEIVED_RESUBMIT_REJECTION_MISSING'
       or position('requires pending School income' in sqlerrm) = 0 then raise; end if;
  end;
  update tuition_cash_fixture
  set cash_transaction_id = v_first.cash_transaction_id
  where fixture_name = 'approve';
end
$confirm$;

-- Rejected attempt remains terminal; retry creates attempt 2 and a new key.
do $retry$
declare v_fixture tuition_cash_fixture%rowtype; v_attempt1 record; v_attempt2 record;
begin
  select * into strict v_fixture from tuition_cash_fixture where fixture_name = 'reject_retry';
  select * into strict v_attempt1
  from public.school_request_cash_income_confirmation_for_record(
    v_fixture.income_record_id, '8596a708-d99f-4264-8f8c-5b89af9254b6',
    'f2fc0000-0000-4000-8000-00000000c001', 'codex-test CNY account', 'bank',
    null, null, null, 'codex-test reject rollback', null
  );
  perform * from public.school_mark_cash_income_request_submitted(
    v_attempt1.linkage_event_id,
    'f2fc0000-0000-4000-8000-00000000d002', 'pending'
  );
  perform * from public.school_mark_cash_income_rejected(
    v_attempt1.linkage_event_id,
    'f2fc0000-0000-4000-8000-00000000d002',
    'codex-test rejected', now()
  );
  select * into strict v_attempt2
  from public.school_request_cash_income_confirmation_for_record(
    v_fixture.income_record_id, '8596a708-d99f-4264-8f8c-5b89af9254b6',
    'f2fc0000-0000-4000-8000-00000000c001', 'codex-test CNY account', 'bank',
    null, null, null, 'codex-test retry rollback', null
  );
  if v_attempt2.attempt_no <> 2
     or v_attempt2.linkage_event_id = v_attempt1.linkage_event_id
     or v_attempt2.idempotency_key = v_attempt1.idempotency_key
     or (select count(*) from public.school_personal_cash_income_linkage_events
         where income_record_id = v_fixture.income_record_id) <> 2 then
    raise exception 'TUITION_CASH_REJECTED_RETRY_CONTRACT_FAILED';
  end if;
  update tuition_cash_fixture set linkage_event_id = v_attempt2.linkage_event_id
  where fixture_name = 'reject_retry';
end
$retry$;

-- Ordinary non-tuition explicit received amount remains unchanged.
do $non_tuition$
declare v_entity uuid; v_result record;
begin
  select business_entity_id into strict v_entity
  from public.school_students where id = 'f2fc0000-0000-4000-8000-00000000a001';
  insert into public.school_income_records (
    id, business_entity_id, income_date, year_month, settlement_month,
    income_category, description, currency, amount, amount_jpy, status,
    app_type, source_type, note
  ) values (
    'f2fc0000-0000-4000-8000-00000000f001', v_entity, date '2099-08-31',
    '2099-08', '2099-08', 'other', 'codex-test non-tuition', 'JPY', 5000,
    5000, 'pending', 'school', 'codex-test-non-tuition',
    'codex-test tuition-cash-hardening authoritative rollback'
  );
  select * into strict v_result
  from public.school_request_cash_income_confirmation_for_record(
    'f2fc0000-0000-4000-8000-00000000f001',
    '8596a708-d99f-4264-8f8c-5b89af9254b6',
    'f2fc0000-0000-4000-8000-00000000c001', 'codex-test CNY account', 'bank',
    211, 'CNY', null, 'codex-test non-tuition explicit amount', null
  );
  if v_result.payment_amount <> 211 or v_result.payment_currency <> 'CNY' then
    raise exception 'NON_TUITION_EXPLICIT_AMOUNT_REGRESSION';
  end if;
end
$non_tuition$;

-- ACL and active-attempt uniqueness are the concurrency backstops.
do $acl$
begin
  if has_function_privilege('anon',
      'public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)', 'EXECUTE')
     or has_function_privilege('authenticated',
      'public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)', 'EXECUTE')
     or not has_function_privilege('service_role',
      'public.school_request_cash_income_confirmation_for_record(uuid,uuid,uuid,text,text,numeric,text,numeric,text,text)', 'EXECUTE')
     or has_table_privilege('anon', 'public.school_personal_cash_income_linkage_events', 'INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('authenticated', 'public.school_personal_cash_income_linkage_events', 'INSERT,UPDATE,DELETE,TRUNCATE') then
    raise exception 'TUITION_CASH_SCHOOL_ACL_FAILED';
  end if;
  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and tablename = 'school_personal_cash_income_linkage_events'
      and indexname = 'school_pc_income_events_active_attempt_uniq'
      and indexdef like '%UNIQUE INDEX%'
  ) then raise exception 'TUITION_CASH_ACTIVE_ATTEMPT_UNIQUE_BACKSTOP_MISSING'; end if;
  if exists (select 1 from public.school_tuition_atomic_writer_context) then
    raise exception 'TUITION_CASH_WRITER_CONTEXT_RESIDUE_BEFORE_ROLLBACK';
  end if;
end
$acl$;

select fixture_name, student_id, planned_lesson_id, billing_identity_id,
       tuition_bill_id, income_record_id, billing_amount_cny,
       billing_exchange_rate, linkage_event_id, cash_request_id,
       cash_transaction_id
from tuition_cash_fixture
order by fixture_name;
select count(*) as in_transaction_linkage_count
from public.school_personal_cash_income_linkage_events
where income_record_id in (select income_record_id from tuition_cash_fixture);

rollback;

begin transaction read only;
select
  (select count(*) from public.school_students where id::text like 'f2fc0000-0000-4000-8000-00000000a00%') +
  (select count(*) from public.school_lesson_records where note = 'codex-test tuition-cash-hardening authoritative rollback') +
  (select count(*) from public.school_student_tuition_billing_identities where student_id::text like 'f2fc0000-0000-4000-8000-00000000a00%') +
  (select count(*) from public.school_student_tuition_bills where student_id::text like 'f2fc0000-0000-4000-8000-00000000a00%') +
  (select count(*) from public.school_income_records where student_id::text like 'f2fc0000-0000-4000-8000-00000000a00%' or id = 'f2fc0000-0000-4000-8000-00000000f001') +
  (select count(*) from public.school_personal_cash_income_linkage_events where income_record_id = 'f2fc0000-0000-4000-8000-00000000f001')
  as school_fixture_residue;
select count(*) as writer_context_residue
from public.school_tuition_atomic_writer_context;
select feature_key, state
from public.school_feature_gates
where feature_key = 'student_tuition_cash_submit';
rollback;
