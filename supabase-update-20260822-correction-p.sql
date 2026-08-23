-- School V2 x Cash Correction-P
--
-- 部署状态：已部署。2026-08-22 在 School 生产执行，同日 Home 侧 prepare、
-- School finalize，2026-08-23 02:26 UTC Home complete，saga status=completed。
-- 目标业务事实（202,991 JPY 教室租金由 immediate_account 更正至
-- fixed_credit_card 路线）已完成更正。
--
-- 注意：本文件头此前写的是「Phase B local draft only. NOT DEPLOYED.」，
-- 那是起草时的状态，部署后未更新，先后误导了两次判断。部署状态一律不再以
-- SQL 文件头为准，请查 docs/ 下对应的部署报告。
--
-- 2026-08-24 修订（本次唯一改动）：
-- school_correction_p_evidence_fingerprint_v1 的 'amount' 字段由
--   'amount', p_amount::text
-- 改为
--   'amount', trim_scale(p_amount)::text
-- 原因：本文件按原样重跑会把生产的 fingerprint helper 覆盖回旧定义，
-- 使 202991 与 202991.00 产生不同的 evidence fingerprint。生产已于
-- 2026-08-23 由 supabase-update-20260823-correction-p-evidence-fingerprint-
-- canonicalization.sql 修正为 trim_scale；此处同步，使本文件与生产一致、
-- 重跑幂等。除该行外，本文件与 2026-08-22 实际执行的内容相同。

create table if not exists public.school_expense_cash_corrections (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  correction_type text not null,
  reason_code text not null,
  school_expense_id uuid not null unique,
  school_attempt_id uuid not null unique,
  home_correction_id uuid not null unique,
  original_home_request_id uuid not null unique,
  original_home_transaction_id uuid not null unique,
  home_balance_effect_id uuid not null unique,
  replacement_request_id uuid not null unique,
  replacement_fixed_item_id uuid not null unique,
  replacement_projection_id uuid not null unique,
  amount numeric(14,2) not null,
  currency text not null,
  charge_date date not null,
  accounting_scope text not null,
  external_event_id uuid not null,
  original_idempotency_key text not null,
  school_fingerprint text not null,
  home_payload_hash text not null,
  replacement_fingerprint text not null,
  expense_snapshot jsonb not null,
  attempt_snapshot jsonb not null,
  home_prepared_snapshot jsonb not null,
  actor_source text not null,
  actor_id uuid not null,
  finalized_at timestamptz not null,
  evidence_fingerprint text not null unique,
  created_at timestamptz not null default statement_timestamp(),
  constraint school_expense_cash_corrections_type_check
    check (correction_type='school_expense_immediate_to_fixed'),
  constraint school_expense_cash_corrections_reason_check
    check (reason_code='wrong_immediate_account_route'),
  constraint school_expense_cash_corrections_amount_check check (amount>0),
  constraint school_expense_cash_corrections_currency_check check (currency='JPY'),
  constraint school_expense_cash_corrections_scope_check check (accounting_scope='school'),
  constraint school_expense_cash_corrections_hash_check check (
    school_fingerprint~'^[0-9a-f]{64}$'
    and home_payload_hash~'^[0-9a-f]{32}$'
    and replacement_fingerprint~'^[0-9a-f]{64}$'
    and evidence_fingerprint~'^[0-9a-f]{64}$'
  ),
  constraint school_expense_cash_corrections_expense_fkey
    foreign key (school_expense_id) references public.school_expense_records(id) on delete restrict,
  constraint school_expense_cash_corrections_attempt_fkey
    foreign key (school_attempt_id) references public.school_expense_cash_attempts(id) on delete restrict
);

comment on table public.school_expense_cash_corrections is
  'Immutable School finalize evidence for Correction-P. It never changes the canonical expense or original immediate attempt.';

alter table public.school_expense_cash_corrections enable row level security;
revoke all on table public.school_expense_cash_corrections from public,anon,authenticated,service_role;

create or replace function public.school_guard_expense_cash_correction()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  raise exception using errcode='42501',message='SCHOOL_EXPENSE_CASH_CORRECTION_APPEND_ONLY';
end;
$$;

drop trigger if exists school_expense_cash_corrections_append_only
  on public.school_expense_cash_corrections;
create trigger school_expense_cash_corrections_append_only
before update or delete on public.school_expense_cash_corrections
for each row execute function public.school_guard_expense_cash_correction();

create or replace function public.school_correction_p_require_active_admin(p_actor_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
begin
  if p_actor_id is null or not exists (
    select 1 from public.school_app_memberships m
    where m.user_id=p_actor_id and m.is_active and m.role='admin'
  ) then
    raise exception using errcode='42501',message='SCHOOL_CORRECTION_P_ACTIVE_ADMIN_REQUIRED';
  end if;
  return p_actor_id;
end;
$$;

create or replace function public.school_get_expense_cash_correction_source_v1(
  p_school_expense_id uuid,p_school_attempt_id uuid,p_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_expense public.school_expense_records%rowtype;
  v_attempt public.school_expense_cash_attempts%rowtype;
begin
  if coalesce(auth.role(),'')<>'service_role' then
    return jsonb_build_object('ok',false,'code','SCHOOL_CORRECTION_P_SERVICE_ROLE_REQUIRED','message','service_role is required');
  end if;
  perform public.school_correction_p_require_active_admin(p_actor_id);
  select * into v_expense from public.school_expense_records e
  where e.id=p_school_expense_id;
  select * into v_attempt from public.school_expense_cash_attempts a
  where a.id=p_school_attempt_id;
  if not found or v_expense.id is null then
    return jsonb_build_object('ok',false,'code','SCHOOL_CORRECTION_P_SOURCE_NOT_FOUND','message','expense or attempt was not found');
  end if;
  if v_attempt.expense_id is distinct from v_expense.id
     or v_expense.status<>'paid' or v_expense.reversed_at is not null
     or v_expense.cancelled_at is not null or v_expense.source_type<>'manual_cash'
     or v_expense.cash_request_status<>'approved'
     or v_expense.cash_request_id is distinct from v_attempt.cash_request_id
     or v_expense.cash_transaction_id is distinct from v_attempt.cash_transaction_id
     or v_expense.cash_request_event_id is distinct from v_attempt.request_event_id
     or v_expense.cash_request_attempt_no is distinct from v_attempt.attempt_no
     or v_attempt.attempt_status<>'approved_immediate'
     or v_attempt.payment_route<>'immediate_account'
     or v_attempt.request_type<>'expense_paid'
     or v_attempt.cash_request_id is null or v_attempt.cash_transaction_id is null
     or v_attempt.cash_funding_account_id is null
     or v_attempt.cash_card_instrument_id is not null
     or v_attempt.cash_fixed_projection_id is not null or v_attempt.cash_fixed_item_id is not null
     or v_attempt.original_amount is distinct from v_expense.amount
     or v_attempt.original_currency is distinct from v_expense.currency
     or v_attempt.payment_amount is distinct from v_expense.cash_payment_amount
     or v_attempt.payment_currency is distinct from v_expense.cash_payment_currency
     or v_attempt.charge_date is distinct from v_expense.expense_date
     or v_attempt.request_payload_fingerprint !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok',false,'code','SCHOOL_CORRECTION_P_SOURCE_MISMATCH','message','expense and approved immediate attempt do not match the Correction-P source contract');
  end if;
  return jsonb_build_object(
    'ok',true,'school_expense_id',v_expense.id,'school_attempt_id',v_attempt.id,
    'original_home_request_id',v_attempt.cash_request_id,
    'original_home_transaction_id',v_attempt.cash_transaction_id,
    'school_event_id',v_attempt.request_event_id,
    'school_idempotency_key',v_attempt.idempotency_key,
    'school_fingerprint',v_attempt.request_payload_fingerprint,
    'amount',v_attempt.payment_amount,'currency',v_attempt.payment_currency,
    'charge_date',v_attempt.charge_date,'actor_id',p_actor_id,
    'expense_snapshot',to_jsonb(v_expense),'attempt_snapshot',to_jsonb(v_attempt)
  );
end;
$$;

create or replace function public.school_correction_p_evidence_fingerprint_v1(
  p_evidence_id uuid,p_home_correction_id uuid,p_operation_id uuid,
  p_correction_type text,p_original_home_request_id uuid,
  p_original_home_transaction_id uuid,p_home_balance_effect_id uuid,
  p_replacement_request_id uuid,p_replacement_fixed_item_id uuid,
  p_replacement_projection_id uuid,p_school_expense_id uuid,
  p_school_attempt_id uuid,p_amount numeric,p_currency text,
  p_charge_date date,p_accounting_scope text,p_external_event_id uuid,
  p_original_idempotency_key text,p_school_fingerprint text,
  p_home_payload_hash text,p_replacement_fingerprint text,
  p_actor_id uuid,p_finalized_at timestamptz
)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog, public
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'evidence_id',p_evidence_id,'home_correction_id',p_home_correction_id,
    'operation_id',p_operation_id,'correction_type',p_correction_type,
    'original_home_request_id',p_original_home_request_id,
    'original_home_transaction_id',p_original_home_transaction_id,
    'home_balance_effect_id',p_home_balance_effect_id,
    'replacement_request_id',p_replacement_request_id,
    'replacement_fixed_item_id',p_replacement_fixed_item_id,
    'replacement_projection_id',p_replacement_projection_id,
    'school_expense_id',p_school_expense_id,'school_attempt_id',p_school_attempt_id,
    'amount',trim_scale(p_amount)::text,'currency',p_currency,'charge_date',p_charge_date::text,
    'accounting_scope',p_accounting_scope,'external_event_id',p_external_event_id,
    'original_idempotency_key',p_original_idempotency_key,
    'school_fingerprint',p_school_fingerprint,'home_payload_hash',p_home_payload_hash,
    'replacement_fingerprint',p_replacement_fingerprint,'actor_id',p_actor_id,
    'finalized_at_utc',to_char(p_finalized_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  )::text,'UTF8'),'sha256'),'hex');
$$;

create or replace function public.school_build_expense_cash_correction_result(p_evidence_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'ok',true,'school_evidence_id',c.id,'operation_id',c.operation_id,
    'correction_type',c.correction_type,'reason_code',c.reason_code,
    'school_expense_id',c.school_expense_id,'school_attempt_id',c.school_attempt_id,
    'home_correction_id',c.home_correction_id,
    'original_home_request_id',c.original_home_request_id,
    'original_home_transaction_id',c.original_home_transaction_id,
    'home_balance_effect_id',c.home_balance_effect_id,
    'replacement_request_id',c.replacement_request_id,
    'replacement_fixed_item_id',c.replacement_fixed_item_id,
    'replacement_projection_id',c.replacement_projection_id,
    'amount',c.amount,'currency',c.currency,'charge_date',c.charge_date,
    'accounting_scope',c.accounting_scope,'external_event_id',c.external_event_id,
    'original_idempotency_key',c.original_idempotency_key,
    'school_fingerprint',c.school_fingerprint,'home_payload_hash',c.home_payload_hash,
    'replacement_fingerprint',c.replacement_fingerprint,'actor_id',c.actor_id,
    'school_finalized_at',c.finalized_at,
    'school_evidence_fingerprint',c.evidence_fingerprint
  ) from public.school_expense_cash_corrections c where c.id=p_evidence_id;
$$;

create or replace function public.school_finalize_expense_cash_correction_p_core(
  p_operation_id uuid,p_home_correction_id uuid,
  p_original_home_request_id uuid,p_original_home_transaction_id uuid,
  p_home_balance_effect_id uuid,p_replacement_request_id uuid,
  p_replacement_fixed_item_id uuid,p_replacement_projection_id uuid,
  p_school_expense_id uuid,p_school_attempt_id uuid,p_amount numeric,
  p_currency text,p_charge_date date,p_accounting_scope text,
  p_external_event_id uuid,p_original_idempotency_key text,
  p_school_fingerprint text,p_home_payload_hash text,
  p_replacement_fingerprint text,p_actor_id uuid,p_home_prepared_snapshot jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_expense public.school_expense_records%rowtype;
  v_attempt public.school_expense_cash_attempts%rowtype;
  v_existing public.school_expense_cash_corrections%rowtype;
  v_id uuid:=gen_random_uuid();
  v_now timestamptz:=statement_timestamp();
  v_fingerprint text;
begin
  perform public.school_correction_p_require_active_admin(p_actor_id);
  if p_operation_id is null or p_home_correction_id is null
     or p_original_home_request_id is null or p_original_home_transaction_id is null
     or p_home_balance_effect_id is null or p_replacement_request_id is null
     or p_replacement_fixed_item_id is null or p_replacement_projection_id is null
     or p_school_expense_id is null or p_school_attempt_id is null
     or coalesce(p_amount,0)<=0 or p_currency<>'JPY' or p_charge_date is null
     or p_accounting_scope<>'school' or p_external_event_id is null
     or nullif(btrim(coalesce(p_original_idempotency_key,'')),'') is null
     or coalesce(p_school_fingerprint,'')!~'^[0-9a-f]{64}$'
     or coalesce(p_home_payload_hash,'')!~'^[0-9a-f]{32}$'
     or coalesce(p_replacement_fingerprint,'')!~'^[0-9a-f]{64}$'
     or p_home_prepared_snapshot is null
     or p_home_prepared_snapshot->>'status'<>'prepared'
     or (p_home_prepared_snapshot->>'correction_id')::uuid is distinct from p_home_correction_id
     or (p_home_prepared_snapshot->>'operation_id')::uuid is distinct from p_operation_id
     or (p_home_prepared_snapshot->>'original_home_request_id')::uuid is distinct from p_original_home_request_id
     or (p_home_prepared_snapshot->>'original_home_transaction_id')::uuid is distinct from p_original_home_transaction_id
     or (p_home_prepared_snapshot->>'balance_effect_id')::uuid is distinct from p_home_balance_effect_id
     or (p_home_prepared_snapshot->>'replacement_request_id')::uuid is distinct from p_replacement_request_id
     or (p_home_prepared_snapshot->>'replacement_fixed_item_id')::uuid is distinct from p_replacement_fixed_item_id
     or (p_home_prepared_snapshot->>'replacement_projection_id')::uuid is distinct from p_replacement_projection_id
     or (p_home_prepared_snapshot->>'school_expense_id')::uuid is distinct from p_school_expense_id
     or (p_home_prepared_snapshot->>'school_attempt_id')::uuid is distinct from p_school_attempt_id
     or (p_home_prepared_snapshot->>'amount')::numeric is distinct from p_amount
     or p_home_prepared_snapshot->>'currency' is distinct from p_currency
     or (p_home_prepared_snapshot->>'original_effective_date')::date is distinct from p_charge_date
     or p_home_prepared_snapshot->>'accounting_scope' is distinct from p_accounting_scope
     or (p_home_prepared_snapshot->>'external_event_id')::uuid is distinct from p_external_event_id
     or p_home_prepared_snapshot->>'original_idempotency_key' is distinct from p_original_idempotency_key
     or p_home_prepared_snapshot->>'school_fingerprint' is distinct from p_school_fingerprint
     or p_home_prepared_snapshot->>'home_payload_hash' is distinct from p_home_payload_hash
     or p_home_prepared_snapshot->>'replacement_fingerprint' is distinct from p_replacement_fingerprint
     or (p_home_prepared_snapshot->>'actor_id')::uuid is distinct from p_actor_id then
    return jsonb_build_object('ok',false,'code','SCHOOL_CORRECTION_P_FINALIZE_INPUT_INVALID','message','Home prepared evidence is incomplete');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    concat_ws(':','correction-p',p_school_expense_id,p_school_attempt_id),22082602));
  select * into v_existing from public.school_expense_cash_corrections c
  where c.operation_id=p_operation_id or c.home_correction_id=p_home_correction_id
     or c.school_expense_id=p_school_expense_id or c.school_attempt_id=p_school_attempt_id
  order by (c.operation_id=p_operation_id) desc limit 1 for update;
  if found then
    if row(v_existing.operation_id,v_existing.home_correction_id,
      v_existing.original_home_request_id,v_existing.original_home_transaction_id,
      v_existing.home_balance_effect_id,v_existing.replacement_request_id,
      v_existing.replacement_fixed_item_id,v_existing.replacement_projection_id,
      v_existing.school_expense_id,v_existing.school_attempt_id,v_existing.amount,
      v_existing.currency,v_existing.charge_date,v_existing.accounting_scope,
      v_existing.external_event_id,v_existing.original_idempotency_key,
      v_existing.school_fingerprint,v_existing.home_payload_hash,
      v_existing.replacement_fingerprint,v_existing.actor_id,v_existing.home_prepared_snapshot)
      is distinct from row(p_operation_id,p_home_correction_id,
      p_original_home_request_id,p_original_home_transaction_id,
      p_home_balance_effect_id,p_replacement_request_id,
      p_replacement_fixed_item_id,p_replacement_projection_id,
      p_school_expense_id,p_school_attempt_id,p_amount,p_currency,p_charge_date,
      p_accounting_scope,p_external_event_id,p_original_idempotency_key,
      p_school_fingerprint,p_home_payload_hash,p_replacement_fingerprint,p_actor_id,
      p_home_prepared_snapshot) then
      return jsonb_build_object('ok',false,'code','SCHOOL_CORRECTION_P_TERMINAL_CONFLICT','message','Correction-P evidence already exists with different facts');
    end if;
    return public.school_build_expense_cash_correction_result(v_existing.id)
      ||jsonb_build_object('idempotent',true,'message','School Correction-P evidence already finalized');
  end if;

  select * into v_expense from public.school_expense_records e
  where e.id=p_school_expense_id for update;
  select * into v_attempt from public.school_expense_cash_attempts a
  where a.id=p_school_attempt_id for update;
  if v_expense.id is null or v_attempt.id is null
     or v_attempt.expense_id is distinct from v_expense.id
     or v_expense.status<>'paid' or v_expense.reversed_at is not null
     or v_expense.cancelled_at is not null or v_expense.source_type<>'manual_cash'
     or v_expense.cash_request_status<>'approved'
     or v_attempt.attempt_status<>'approved_immediate'
     or v_attempt.payment_route<>'immediate_account'
     or v_attempt.request_type<>'expense_paid'
     or v_attempt.cash_request_id is distinct from p_original_home_request_id
     or v_attempt.cash_transaction_id is distinct from p_original_home_transaction_id
     or v_attempt.request_event_id is distinct from p_external_event_id
     or v_attempt.idempotency_key is distinct from p_original_idempotency_key
     or v_attempt.request_payload_fingerprint is distinct from p_school_fingerprint
     or v_attempt.payment_amount is distinct from p_amount
     or v_attempt.payment_currency is distinct from p_currency
     or v_attempt.charge_date is distinct from p_charge_date
     or v_expense.cash_request_id is distinct from v_attempt.cash_request_id
     or v_expense.cash_transaction_id is distinct from v_attempt.cash_transaction_id
     or v_expense.cash_request_event_id is distinct from v_attempt.request_event_id
     or v_expense.cash_request_attempt_no is distinct from v_attempt.attempt_no then
    return jsonb_build_object('ok',false,'code','SCHOOL_CORRECTION_P_SOURCE_DRIFT','message','original School facts drifted before finalize');
  end if;
  v_fingerprint:=public.school_correction_p_evidence_fingerprint_v1(
    v_id,p_home_correction_id,p_operation_id,'school_expense_immediate_to_fixed',
    p_original_home_request_id,p_original_home_transaction_id,p_home_balance_effect_id,
    p_replacement_request_id,p_replacement_fixed_item_id,p_replacement_projection_id,
    p_school_expense_id,p_school_attempt_id,p_amount,p_currency,p_charge_date,
    p_accounting_scope,p_external_event_id,p_original_idempotency_key,
    p_school_fingerprint,p_home_payload_hash,p_replacement_fingerprint,p_actor_id,v_now);
  insert into public.school_expense_cash_corrections(
    id,operation_id,correction_type,reason_code,school_expense_id,school_attempt_id,
    home_correction_id,original_home_request_id,original_home_transaction_id,
    home_balance_effect_id,replacement_request_id,replacement_fixed_item_id,
    replacement_projection_id,amount,currency,charge_date,accounting_scope,
    external_event_id,original_idempotency_key,school_fingerprint,home_payload_hash,
    replacement_fingerprint,expense_snapshot,attempt_snapshot,home_prepared_snapshot,
    actor_source,actor_id,finalized_at,evidence_fingerprint,created_at
  ) values (
    v_id,p_operation_id,'school_expense_immediate_to_fixed','wrong_immediate_account_route',
    p_school_expense_id,p_school_attempt_id,p_home_correction_id,
    p_original_home_request_id,p_original_home_transaction_id,p_home_balance_effect_id,
    p_replacement_request_id,p_replacement_fixed_item_id,p_replacement_projection_id,
    p_amount,p_currency,p_charge_date,p_accounting_scope,p_external_event_id,
    p_original_idempotency_key,p_school_fingerprint,p_home_payload_hash,
    p_replacement_fingerprint,to_jsonb(v_expense),to_jsonb(v_attempt),
    p_home_prepared_snapshot,'school_active_admin',p_actor_id,v_now,v_fingerprint,v_now
  );
  return public.school_build_expense_cash_correction_result(v_id)
    ||jsonb_build_object('idempotent',false,'message','School Correction-P evidence finalized');
exception when invalid_text_representation or invalid_datetime_format then
  return jsonb_build_object('ok',false,'code','SCHOOL_CORRECTION_P_FINALIZE_INPUT_INVALID','message','Home prepared evidence contains an invalid identity');
end;
$$;

create or replace function public.school_finalize_expense_cash_correction_p(
  p_operation_id uuid,p_home_correction_id uuid,
  p_original_home_request_id uuid,p_original_home_transaction_id uuid,
  p_home_balance_effect_id uuid,p_replacement_request_id uuid,
  p_replacement_fixed_item_id uuid,p_replacement_projection_id uuid,
  p_school_expense_id uuid,p_school_attempt_id uuid,p_amount numeric,
  p_currency text,p_charge_date date,p_accounting_scope text,
  p_external_event_id uuid,p_original_idempotency_key text,
  p_school_fingerprint text,p_home_payload_hash text,
  p_replacement_fingerprint text,p_actor_id uuid,p_home_prepared_snapshot jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if coalesce(auth.role(),'')<>'service_role' then
    return jsonb_build_object('ok',false,'code','SCHOOL_CORRECTION_P_SERVICE_ROLE_REQUIRED','message','service_role is required');
  end if;
  return public.school_finalize_expense_cash_correction_p_core(
    p_operation_id,p_home_correction_id,p_original_home_request_id,
    p_original_home_transaction_id,p_home_balance_effect_id,p_replacement_request_id,
    p_replacement_fixed_item_id,p_replacement_projection_id,p_school_expense_id,
    p_school_attempt_id,p_amount,p_currency,p_charge_date,p_accounting_scope,
    p_external_event_id,p_original_idempotency_key,p_school_fingerprint,
    p_home_payload_hash,p_replacement_fingerprint,p_actor_id,p_home_prepared_snapshot);
end;
$$;

create or replace function public.school_get_expense_cash_correction_p(p_operation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare v_id uuid;
begin
  if coalesce(auth.role(),'')<>'service_role' then
    return jsonb_build_object('ok',false,'code','SCHOOL_CORRECTION_P_SERVICE_ROLE_REQUIRED','message','service_role is required');
  end if;
  select id into v_id from public.school_expense_cash_corrections
  where operation_id=p_operation_id;
  if v_id is null then
    return jsonb_build_object('ok',false,'code','SCHOOL_CORRECTION_P_NOT_FOUND','message','School Correction-P operation was not found');
  end if;
  return public.school_build_expense_cash_correction_result(v_id);
end;
$$;

revoke all on function public.school_guard_expense_cash_correction() from public,anon,authenticated,service_role;
revoke all on function public.school_correction_p_require_active_admin(uuid) from public,anon,authenticated,service_role;
revoke all on function public.school_correction_p_evidence_fingerprint_v1(uuid,uuid,uuid,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,numeric,text,date,text,uuid,text,text,text,text,uuid,timestamptz) from public,anon,authenticated,service_role;
revoke all on function public.school_build_expense_cash_correction_result(uuid) from public,anon,authenticated,service_role;
revoke all on function public.school_finalize_expense_cash_correction_p_core(uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,numeric,text,date,text,uuid,text,text,text,text,uuid,jsonb) from public,anon,authenticated,service_role;

revoke all on function public.school_get_expense_cash_correction_source_v1(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.school_get_expense_cash_correction_source_v1(uuid,uuid,uuid) to service_role;
revoke all on function public.school_finalize_expense_cash_correction_p(uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,numeric,text,date,text,uuid,text,text,text,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.school_finalize_expense_cash_correction_p(uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,numeric,text,date,text,uuid,text,text,text,text,uuid,jsonb) to service_role;
revoke all on function public.school_get_expense_cash_correction_p(uuid) from public,anon,authenticated;
grant execute on function public.school_get_expense_cash_correction_p(uuid) to service_role;
