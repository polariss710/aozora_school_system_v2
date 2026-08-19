-- Phase 3C2-R School expense Cash attempt schema extension and deterministic backfill.
-- Prerequisite: school_expense_cash_attempt_v2_fingerprint_helper_20260819.sql.
-- Cash DB is never written. The 24 VALUES rows are a reviewed structural snapshot
-- of the unique home_external_transaction_requests mapping taken on 2026-08-19.

lock table public.school_expense_cash_attempts in access exclusive mode;

alter table public.school_expense_cash_attempts
  add column payment_amount numeric,
  add column payment_currency text,
  add column request_payload_fingerprint text generated always as (
    public.school_expense_cash_attempt_payload_fingerprint_v2(
      expense_id,
      attempt_no,
      request_type,
      payment_route,
      request_event_id,
      idempotency_key,
      original_amount,
      original_currency,
      payment_amount,
      payment_currency,
      cash_funding_account_id,
      charge_date
    )
  ) stored,
  add column callback_recovered_from_prepared boolean not null default false,
  add column callback_recovered_at timestamptz,
  add column callback_recovery_source text;

-- The existing immutable trigger predates these six columns. Disable it only for
-- this locked one-time backfill; it is re-enabled before constraints are added and
-- is replaced below with the Phase 3C2-R transition-aware definition.
alter table public.school_expense_cash_attempts
  disable trigger school_guard_expense_cash_attempt_v1;

do $backfill$
declare
  v_updated integer;
begin
  with cash_snapshot(
    cash_request_id,
    expense_id,
    request_event_id,
    idempotency_key,
    cash_funding_account_id,
    payment_amount,
    payment_currency,
    cash_transaction_id,
    charge_date
  ) as (
    values
      ('2b9ee52f-677a-4db9-9375-a8ae823f413b'::uuid,'99652545-8235-439d-9478-829691130e3c'::uuid,'145ec0da-8e7e-493b-bda1-568594dd18d2'::uuid,'aozora_school:school_expense_records:99652545-8235-439d-9478-829691130e3c:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,2739::numeric,'CNY'::text,'5de6d85c-c319-47cc-84cd-e2ec66edf189'::uuid,'2026-06-16'::date),
      ('2eb4cfc1-fa78-4a96-9a95-6e65c0662678'::uuid,'0b9540a3-7d1d-45c7-ae6e-3eda823c7e0c'::uuid,'80f965ab-8e83-445e-9464-f95822d42be0'::uuid,'aozora_school:school_expense_records:0b9540a3-7d1d-45c7-ae6e-3eda823c7e0c:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,3573::numeric,'CNY'::text,null::uuid,'2026-08-18'::date),
      ('382330f8-ba30-4d5d-8e4e-512a6d167756'::uuid,'4bb7176f-b4ca-4c31-8c3d-1ed3d1d66ca0'::uuid,'9d65e381-0a39-4a48-93cf-8bc19e6e5989'::uuid,'aozora_school:school_expense_records:4bb7176f-b4ca-4c31-8c3d-1ed3d1d66ca0:expense_paid:attempt:1'::text,'b06f29c4-67cd-4d55-b39c-7cff0eab99a1'::uuid,32000::numeric,'JPY'::text,'101bf957-72ba-4deb-8cc4-80a1bc117b02'::uuid,'2026-06-16'::date),
      ('3fbf6434-be9d-410f-9edd-ac98b1ef35c0'::uuid,'9f8a4ce3-7916-4e07-b57d-96b77d9e17e7'::uuid,'742f8bb7-45a0-4a9e-a6bd-d3ac95bb11e1'::uuid,'aozora_school:school_expense_records:9f8a4ce3-7916-4e07-b57d-96b77d9e17e7:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,3791::numeric,'CNY'::text,'e17e157a-2adf-41d1-8704-bc74fb942d8a'::uuid,'2026-07-10'::date),
      ('4bb43566-e871-4570-8e6e-9d162684ae71'::uuid,'9fead984-ba0e-4b3e-b3c9-eeb56cc2ff01'::uuid,'e8b4a1be-3e1f-4bb7-bdcb-240ab6873170'::uuid,'aozora_school:school_expense_records:9fead984-ba0e-4b3e-b3c9-eeb56cc2ff01:expense_paid:attempt:1'::text,'0cf1208d-2364-4dff-8bfe-8eccee9d386c'::uuid,36000::numeric,'JPY'::text,'96ed071d-3c67-4647-803c-bb9b09578ab8'::uuid,'2026-07-10'::date),
      ('4dc47f16-4d40-47d3-8396-f643f4ae8071'::uuid,'63d9e48f-2bff-4ede-9863-b69df03f11d2'::uuid,'7c0bd1d6-f53c-46a9-b8e7-9e574f7ed10f'::uuid,'aozora_school:school_expense_records:63d9e48f-2bff-4ede-9863-b69df03f11d2:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,4348::numeric,'CNY'::text,'6bffea75-96e5-444f-b5aa-de5ea96dc524'::uuid,'2026-07-10'::date),
      ('4eff8bb8-4773-41fc-9b34-cf271f515e18'::uuid,'c3094302-6790-4800-a1f7-21afb00c150e'::uuid,'de4261cd-92c3-45fc-8efa-1ccae4dee6c0'::uuid,'aozora_school:school_expense_records:c3094302-6790-4800-a1f7-21afb00c150e:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,4602::numeric,'CNY'::text,null::uuid,'2026-07-10'::date),
      ('69e3e928-4862-4d8c-8bbc-a667947a7305'::uuid,'a1771a90-9a1c-4d3b-a8ab-9483ba5a007d'::uuid,'6bc02989-478d-4ca6-88b8-ffc367186ae2'::uuid,'aozora_school:school_expense_records:a1771a90-9a1c-4d3b-a8ab-9483ba5a007d:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,1254::numeric,'CNY'::text,'c9dd4f33-b373-418c-bf86-73596655f935'::uuid,'2026-07-01'::date),
      ('70df07b0-4f8c-45e7-bff6-29fdfb0520fa'::uuid,'c723ec94-f42b-42be-a2e2-efa63fdff0fc'::uuid,'80930bb3-a482-4faa-ade5-07123589e61b'::uuid,'aozora_school:school_expense_records:c723ec94-f42b-42be-a2e2-efa63fdff0fc:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,2675::numeric,'CNY'::text,'d999b7a4-b244-4df9-9e0c-aa7fa9234e31'::uuid,'2026-07-01'::date),
      ('7e74e991-9f68-4747-9599-2f8d92cf2b4e'::uuid,'4e318c70-5bc7-41ed-ad7a-140d4c31cb13'::uuid,'bf7f3880-e1ec-40ae-a225-9085dbb87bb0'::uuid,'aozora_school:school_expense_records:4e318c70-5bc7-41ed-ad7a-140d4c31cb13:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,1382::numeric,'CNY'::text,null::uuid,'2026-08-18'::date),
      ('93d6cc84-94c7-4ad8-9359-45f4db62d1bb'::uuid,'3adfda54-74ce-4d01-bc99-c9c9c32ed021'::uuid,'4c9e4ae0-fea0-47c9-af9f-dc82f61c4136'::uuid,'aozora_school:school_expense_records:3adfda54-74ce-4d01-bc99-c9c9c32ed021:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,6641::numeric,'CNY'::text,'e30ce4a0-6498-41b2-a34d-65c6e49349a5'::uuid,'2026-07-13'::date),
      ('97eb7a83-3a08-43f4-879d-17428f5212ba'::uuid,'35811bca-e93d-47aa-a433-44c42456b020'::uuid,'b4aae69a-fe35-4d5d-8154-adffd6913f20'::uuid,'aozora_school:school_expense_records:35811bca-e93d-47aa-a433-44c42456b020:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,5893::numeric,'CNY'::text,null::uuid,'2026-08-18'::date),
      ('a7e069aa-4bfd-4838-9446-18718b10f1b7'::uuid,'9bf548e7-b74a-4b34-bca6-9254eb8057a8'::uuid,'60f19d99-f860-4bdf-bc6a-b09f3fdb858f'::uuid,'aozora_school:school_expense_records:9bf548e7-b74a-4b34-bca6-9254eb8057a8:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,2175::numeric,'CNY'::text,'6a9e77c2-f4cd-41f6-8116-1665814e458c'::uuid,'2026-07-09'::date),
      ('aec4eb6d-2794-4ea4-abef-2176d32c48c5'::uuid,'204278e1-5f89-4358-b4ea-1effa5be48af'::uuid,'018b3c99-6a43-4eec-b784-f11b0e0030be'::uuid,'aozora_school:school_expense_records:204278e1-5f89-4358-b4ea-1effa5be48af:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,1330::numeric,'CNY'::text,null::uuid,'2026-08-20'::date),
      ('b882ad95-36bb-41cd-b544-dc6b9756a4e2'::uuid,'7f347fbe-be1b-495b-b694-c7fd855b505a'::uuid,'b5071776-8c70-48b9-b1d7-6f34981fe634'::uuid,'aozora_school:school_expense_records:7f347fbe-be1b-495b-b694-c7fd855b505a:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,3506::numeric,'CNY'::text,'e26f8348-e002-4377-b245-86c40060d6a2'::uuid,'2026-06-16'::date),
      ('c1b517e1-4495-4538-b19e-d7fa4842b104'::uuid,'79cf7b82-a76b-4782-9b63-77dcd566dc7c'::uuid,'56427f23-152a-4d1f-a9b7-dd6f26897255'::uuid,'aozora_school:school_expense_records:79cf7b82-a76b-4782-9b63-77dcd566dc7c:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,2023::numeric,'CNY'::text,'4199274e-b4c2-4d71-a9ea-785339340a49'::uuid,'2026-06-16'::date),
      ('c2e1c4c6-624d-4415-a98d-1f5cda334779'::uuid,'ba93ed4b-9630-4cb3-82b3-ba1652f6e992'::uuid,'6e454eb3-850c-45d5-8447-8988aabc9a29'::uuid,'aozora_school:school_expense_records:ba93ed4b-9630-4cb3-82b3-ba1652f6e992:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,1729::numeric,'CNY'::text,null::uuid,'2026-08-18'::date),
      ('c46cf281-4c00-475a-b65b-7e47da5cb41b'::uuid,'a27a8f48-758e-4079-9a37-f1af1965eb5a'::uuid,'8e4042aa-e5d5-438b-99a3-df791b0f5c8f'::uuid,'aozora_school:school_expense_records:a27a8f48-758e-4079-9a37-f1af1965eb5a:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,3792::numeric,'CNY'::text,null::uuid,'2026-07-10'::date),
      ('e86acd8f-8b0f-4983-ae3a-55df051ac7c5'::uuid,'d1345550-18f4-4699-976b-6667ff9295b3'::uuid,'9c390938-77ec-42cc-846b-a85f0704d3c7'::uuid,'aozora_school:school_expense_records:d1345550-18f4-4699-976b-6667ff9295b3:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,5651::numeric,'CNY'::text,'d60d00d8-c344-4f7b-b731-95e7ae04f210'::uuid,'2026-06-16'::date),
      ('e8b9bd1e-a585-4c62-a77b-64936408cfbf'::uuid,'b50fb58a-b9da-4386-ac01-4fe7b968fbba'::uuid,'a3330f49-0584-4584-8c94-c542892ebfd9'::uuid,'aozora_school:school_expense_records:b50fb58a-b9da-4386-ac01-4fe7b968fbba:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,2704::numeric,'CNY'::text,null::uuid,'2026-08-18'::date),
      ('ea5a7ce2-1b7a-44f3-8db7-22bb73c963bc'::uuid,'ed23a346-2ba5-47fb-a496-4c4ba781ec86'::uuid,'fa3aad38-5886-4154-a7d4-8c8331fb71fe'::uuid,'aozora_school:school_expense_records:ed23a346-2ba5-47fb-a496-4c4ba781ec86:expense_paid:attempt:1'::text,'b06f29c4-67cd-4d55-b39c-7cff0eab99a1'::uuid,202991::numeric,'JPY'::text,'01e910b8-bf54-486c-a13a-597ca9dbf684'::uuid,'2026-08-13'::date),
      ('ef8da4c6-c628-440a-8a01-9a46e3ba1fd4'::uuid,'a68f2491-1fa3-4dcb-b870-28bd2d4fa29a'::uuid,'bc8f0d32-52fe-4272-819b-2c11c56b5271'::uuid,'aozora_school:school_expense_records:a68f2491-1fa3-4dcb-b870-28bd2d4fa29a:expense_paid:attempt:1'::text,'b06f29c4-67cd-4d55-b39c-7cff0eab99a1'::uuid,40000::numeric,'JPY'::text,'5289bbf7-f090-433c-99fa-9c222dbca696'::uuid,'2026-06-16'::date),
      ('f72c49c1-43e1-4d26-a375-6f9917b444fb'::uuid,'1d3ade97-b3ce-41b2-b661-3e14dd8f0440'::uuid,'ff17b87c-bf1d-4868-b4e0-1fcd7a2ade4c'::uuid,'aozora_school:school_expense_records:1d3ade97-b3ce-41b2-b661-3e14dd8f0440:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,1186::numeric,'CNY'::text,'ba75e811-1cb5-4bc6-95df-1b3cc144d02d'::uuid,'2026-07-09'::date),
      ('fcc1e75a-5e17-4246-b1ea-17243b593f70'::uuid,'e7211e3a-d504-4ad2-831e-526b959be6ce'::uuid,'f30266a7-4bd2-4926-86eb-9642509de630'::uuid,'aozora_school:school_expense_records:e7211e3a-d504-4ad2-831e-526b959be6ce:expense_paid:attempt:1'::text,'c61781cf-dd07-40d1-ab00-7f76eb581034'::uuid,3820::numeric,'CNY'::text,'6651a038-3381-47b9-a966-4f0f34c1b1ae'::uuid,'2026-06-16'::date)
  )
  update public.school_expense_cash_attempts a
     set payment_amount = s.payment_amount,
         payment_currency = s.payment_currency
    from cash_snapshot s
   where a.cash_request_id = s.cash_request_id
     and a.expense_id = s.expense_id
     and a.request_event_id = s.request_event_id
     and a.idempotency_key = s.idempotency_key
     and a.cash_funding_account_id = s.cash_funding_account_id
     and a.cash_transaction_id is not distinct from s.cash_transaction_id
     and a.charge_date = s.charge_date
     and a.payment_route = 'immediate_account'
     and a.request_type = 'expense_paid';

  get diagnostics v_updated = row_count;
  if v_updated <> 24 then
    raise exception using
      errcode = '55000',
      message = format('PHASE3C2R_HISTORY_MAPPING_COUNT_MISMATCH:%s', v_updated);
  end if;

  if (select count(*) from public.school_expense_cash_attempts) <> 24
     or exists (
       select 1
       from public.school_expense_cash_attempts a
       where a.payment_amount is null
          or a.payment_currency is null
          or a.request_payload_fingerprint is null
     ) then
    raise exception using
      errcode = '55000',
      message = 'PHASE3C2R_HISTORY_BACKFILL_INCOMPLETE';
  end if;
end;
$backfill$;

alter table public.school_expense_cash_attempts
  enable trigger school_guard_expense_cash_attempt_v1;

alter table public.school_expense_cash_attempts
  alter column payment_amount set not null,
  alter column payment_currency set not null,
  alter column request_payload_fingerprint set not null,
  add constraint school_expense_cash_attempts_payment_amount_check
    check (payment_amount > 0),
  add constraint school_expense_cash_attempts_payment_currency_check
    check (payment_currency in ('JPY', 'CNY')),
  add constraint school_expense_cash_attempts_payload_fingerprint_check
    check (request_payload_fingerprint ~ '^[0-9a-f]{64}$'),
  add constraint school_expense_cash_attempts_callback_recovery_check
    check (
      (
        not callback_recovered_from_prepared
        and callback_recovered_at is null
        and callback_recovery_source is null
      )
      or
      (
        callback_recovered_from_prepared
        and callback_recovered_at is not null
        and callback_recovery_source = 'sync-cash-request-result-v2'
        and attempt_status in ('approved_immediate', 'rejected')
      )
    );

create or replace function public.school_guard_expense_cash_attempt_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_allowed_columns text[] := array[
    'cash_request_id','cash_transaction_id','cash_fixed_projection_id','cash_fixed_item_id',
    'attempt_status','submitted_at','approved_at','funded_at','rejected_at','corrected_at',
    'latest_error_code','latest_error_message','request_payload_fingerprint','callback_recovered_from_prepared',
    'callback_recovered_at','callback_recovery_source','version','updated_at'
  ];
  v_unexpected_columns text;
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_DELETE_FORBIDDEN';
  end if;

  if tg_op = 'INSERT' then
    if new.payment_route = 'fixed_credit_card'
       and not exists (
         select 1 from public.school_feature_gates g
         where g.feature_key = 'cash_fixed_credit_card_route_enabled'
           and g.state = 'enabled'
       ) then
      raise exception using errcode = '55000', message = 'SCHOOL_CASH_FIXED_CREDIT_CARD_ROUTE_DISABLED';
    end if;
    return new;
  end if;

  if new is not distinct from old then
    return new;
  end if;

  if (to_jsonb(new) - v_allowed_columns) is distinct from (to_jsonb(old) - v_allowed_columns) then
    select string_agg(n.key, ',' order by n.key)
      into v_unexpected_columns
      from jsonb_each(to_jsonb(new)) n
      join jsonb_each(to_jsonb(old)) o on o.key=n.key
     where n.value is distinct from o.value
       and not (n.key = any(v_allowed_columns));
    raise exception using
      errcode = '55000',
      message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_IDENTITY_IMMUTABLE',
      detail = coalesce(v_unexpected_columns, 'unknown generated or structural column');
  end if;

  if old.payment_route = 'immediate_account' then
    if old.attempt_status = 'prepared' and new.attempt_status = 'submitted' then
      if new.version <> old.version + 1
         or old.cash_request_id is not null or new.cash_request_id is null
         or old.submitted_at is not null or new.submitted_at is null
         or new.cash_transaction_id is not null or new.approved_at is not null or new.rejected_at is not null
         or new.callback_recovered_from_prepared then
        raise exception using errcode = '40001', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_VERSION_CONFLICT';
      end if;
    elsif old.attempt_status = 'submitted' and new.attempt_status = 'approved_immediate' then
      if new.version <> old.version + 1
         or new.cash_request_id is distinct from old.cash_request_id
         or new.submitted_at is distinct from old.submitted_at
         or old.cash_transaction_id is not null or new.cash_transaction_id is null
         or old.approved_at is not null or new.approved_at is null
         or new.rejected_at is not null or new.callback_recovered_from_prepared then
        raise exception using errcode = '40001', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_VERSION_CONFLICT';
      end if;
    elsif old.attempt_status = 'submitted' and new.attempt_status = 'rejected' then
      if new.version <> old.version + 1
         or new.cash_request_id is distinct from old.cash_request_id
         or new.submitted_at is distinct from old.submitted_at
         or new.cash_transaction_id is not null
         or old.rejected_at is not null or new.rejected_at is null
         or new.approved_at is not null or new.callback_recovered_from_prepared then
        raise exception using errcode = '40001', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_VERSION_CONFLICT';
      end if;
    elsif old.attempt_status = 'prepared'
          and new.attempt_status in ('approved_immediate', 'rejected') then
      if new.version <> old.version + 2
         or new.cash_request_id is null or new.submitted_at is null
         or not new.callback_recovered_from_prepared
         or new.callback_recovered_at is null
         or new.callback_recovery_source <> 'sync-cash-request-result-v2'
         or (new.attempt_status = 'approved_immediate' and (new.cash_transaction_id is null or new.approved_at is null or new.rejected_at is not null))
         or (new.attempt_status = 'rejected' and (new.cash_transaction_id is not null or new.rejected_at is null or new.approved_at is not null)) then
        raise exception using errcode = '40001', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_RECOVERY_VERSION_CONFLICT';
      end if;
    else
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_TRANSITION_FORBIDDEN';
    end if;
  elsif new.version is distinct from old.version + 1 then
    -- Preserve the Phase 3C1 fixed-route version rule; the fixed gate remains blocked.
    raise exception using errcode = '40001', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_VERSION_CONFLICT';
  end if;

  new.updated_at := statement_timestamp();
  return new;
end;
$function$;

alter function public.school_guard_expense_cash_attempt_v1() owner to postgres;
revoke all on function public.school_guard_expense_cash_attempt_v1()
  from public, anon, authenticated, service_role;

alter table public.school_feature_gates
  drop constraint school_feature_gates_key_check,
  add constraint school_feature_gates_key_check check (
    feature_key in (
      'student_tuition_preview',
      'student_tuition_generate',
      'student_tuition_cash_submit',
      'cash_fixed_credit_card_route_enabled',
      'cash_expense_attempt_writer_v2_enabled'
    )
  );

insert into public.school_feature_gates(
  feature_key, state, reason, release_version, evidence_hash, updated_at, updated_by
) values (
  'cash_expense_attempt_writer_v2_enabled',
  'blocked',
  'Phase 3C2-R schema/RPC staging gate; enable only after both Edge functions are deployed and legacy-request drift is zero.',
  'phase-3c2r-20260819',
  'phase3c2r-schema-rpc-staged',
  now(),
  current_user
);

comment on column public.school_expense_cash_attempts.payment_amount is
  'Immutable actual Cash request amount for this attempt; distinct from the School original expense amount.';
comment on column public.school_expense_cash_attempts.payment_currency is
  'Immutable actual Cash request currency for this attempt; distinct from the School original expense currency.';
comment on column public.school_expense_cash_attempts.request_payload_fingerprint is
  'Database-generated SHA-256 of the immutable canonical request identity and payment snapshot.';
comment on column public.school_expense_cash_attempts.callback_recovered_from_prepared is
  'True only when a full-evidence sync callback atomically recovered prepared -> submitted -> terminal.';
comment on column public.school_expense_cash_attempts.callback_recovered_at is
  'Audit timestamp of a full-evidence prepared callback recovery.';
comment on column public.school_expense_cash_attempts.callback_recovery_source is
  'Fixed owner-writer source for a prepared callback recovery.';
