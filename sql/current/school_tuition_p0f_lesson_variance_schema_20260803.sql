-- School V2 tuition P0-F schema: explicit source-treatment drafts and
-- immutable settlement lesson-variance claims.
-- Usage: psql -v p0f_schema_commit=0|1 -f this_file.sql
-- This migration adds nullable snapshot fields only and never updates business rows.
\set ON_ERROR_STOP on
\pset pager off
\if :{?p0f_schema_commit}
\else
  \set p0f_schema_commit 0
\endif

begin;
set local lock_timeout = '8s';
set local statement_timeout = '240s';

do $preflight$
begin
  if to_regclass('public.school_student_settlement_source_treatment_drafts') is not null
     or to_regclass('public.school_student_settlement_lesson_variance_claims') is not null then
    raise exception 'P0F_SCHEMA_ALREADY_INSTALLED';
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='school_student_monthly_settlements'
      and column_name in (
        'source_treatment_mode','settlement_exchange_rate',
        'settlement_exchange_rate_source','settlement_exchange_rate_effective_date',
        'lesson_variance_calculation_version','unused_planned_credit_jpy',
        'unused_planned_credit_cny','pending_makeup_hours',
        'lesson_variance_display_hours','net_lesson_variance_jpy',
        'net_lesson_variance_cny','lesson_variance_source_count',
        'lesson_variance_manifest_sha256'
      )
  ) then
    raise exception 'P0F_SETTLEMENT_COLUMN_ALREADY_EXISTS';
  end if;
  if not exists (
    select 1 from public.school_feature_gates
    where feature_key='student_tuition_preview' and state in ('enabled','validation_preview_only')
  ) or not exists (
    select 1 from public.school_feature_gates
    where feature_key='student_tuition_generate' and state='blocked'
  ) or not exists (
    select 1 from public.school_feature_gates
    where feature_key='student_tuition_cash_submit' and state='blocked'
  ) then
    raise exception 'P0F_GATE_BASELINE_MISMATCH';
  end if;
end
$preflight$;

alter table public.school_student_monthly_settlements
  add column source_treatment_mode text,
  add column settlement_exchange_rate numeric(12,6),
  add column settlement_exchange_rate_source text,
  add column settlement_exchange_rate_effective_date date,
  add column lesson_variance_calculation_version text,
  add column unused_planned_credit_jpy numeric,
  add column unused_planned_credit_cny numeric,
  add column pending_makeup_hours numeric,
  add column lesson_variance_display_hours numeric,
  add column net_lesson_variance_jpy numeric,
  add column net_lesson_variance_cny numeric,
  add column lesson_variance_source_count integer,
  add column lesson_variance_manifest_sha256 text,
  add constraint school_student_monthly_settlements_p0f_mode_chk check (
    source_treatment_mode is null or source_treatment_mode in (
      'separate_makeup_and_overage_v1',
      'net_lesson_variance_to_financial_credit_v1'
    )
  ),
  add constraint school_student_monthly_settlements_p0f_rate_chk check (
    settlement_exchange_rate is null or settlement_exchange_rate > 0
  ),
  add constraint school_student_monthly_settlements_p0f_manifest_chk check (
    lesson_variance_manifest_sha256 is null
    or lesson_variance_manifest_sha256 ~ '^[0-9a-f]{64}$'
  ),
  add constraint school_student_monthly_settlements_p0f_contract_chk check (
    source_treatment_mode is null
    or source_treatment_mode='separate_makeup_and_overage_v1'
    or (
      source_treatment_mode='net_lesson_variance_to_financial_credit_v1'
      and settlement_exchange_rate is not null
      and settlement_exchange_rate_source is not null
      and settlement_exchange_rate_effective_date is not null
      and lesson_variance_calculation_version='lesson_variance_financial_netting_v1'
      and unused_planned_credit_jpy is not null
      and unused_planned_credit_cny is not null
      and pending_makeup_hours is not null
      and lesson_variance_display_hours is not null
      and net_lesson_variance_jpy is not null
      and net_lesson_variance_cny is not null
      and lesson_variance_source_count is not null
      and lesson_variance_manifest_sha256 is not null
    )
  );

create table public.school_student_settlement_source_treatment_drafts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.school_students(id) on delete restrict,
  business_entity_id uuid not null references public.school_business_entities(id) on delete restrict,
  year_month text not null check (year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  source_treatment_mode text not null check (source_treatment_mode in (
    'separate_makeup_and_overage_v1',
    'net_lesson_variance_to_financial_credit_v1'
  )),
  settlement_exchange_rate numeric(12,6),
  settlement_exchange_rate_source text,
  settlement_exchange_rate_effective_date date,
  lesson_variance_calculation_version text not null
    default 'lesson_variance_financial_netting_v1',
  source_manifest_sha256 text not null check (source_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  source_count integer not null check (source_count >= 0),
  status text not null check (status in ('active','consumed','superseded')),
  settlement_id uuid references public.school_student_monthly_settlements(id) on delete restrict,
  superseded_at timestamptz,
  consumed_at timestamptz,
  reason text not null check (btrim(reason) <> ''),
  created_by text not null,
  updated_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint school_student_settlement_source_treatment_drafts_rate_chk check (
    (source_treatment_mode='separate_makeup_and_overage_v1'
      and settlement_exchange_rate is null
      and settlement_exchange_rate_source is null
      and settlement_exchange_rate_effective_date is null)
    or
    (source_treatment_mode='net_lesson_variance_to_financial_credit_v1'
      and settlement_exchange_rate > 0
      and btrim(settlement_exchange_rate_source) <> ''
      and settlement_exchange_rate_effective_date is not null)
  ),
  constraint school_student_settlement_source_treatment_drafts_lifecycle_chk check (
    (status='active' and settlement_id is null and consumed_at is null and superseded_at is null)
    or (status='consumed' and settlement_id is not null and consumed_at is not null)
    or (status='superseded' and settlement_id is null and superseded_at is not null)
  )
);

create unique index school_student_settlement_source_treatment_drafts_active_uidx
  on public.school_student_settlement_source_treatment_drafts(
    student_id,business_entity_id,year_month
  ) where status='active';
create index school_student_settlement_source_treatment_drafts_scope_idx
  on public.school_student_settlement_source_treatment_drafts(
    student_id,business_entity_id,year_month,created_at desc
  );

create table public.school_student_settlement_lesson_variance_claims (
  id uuid primary key default gen_random_uuid(),
  claim_batch_id uuid not null,
  claim_batch_version integer not null check (claim_batch_version > 0),
  settlement_id uuid not null references public.school_student_monthly_settlements(id) on delete restrict,
  student_id uuid not null references public.school_students(id) on delete restrict,
  business_entity_id uuid not null references public.school_business_entities(id) on delete restrict,
  year_month text not null check (year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  source_type text not null check (source_type in (
    'unused_planned_credit_v1','actual_duration_overage_charge_v1'
  )),
  source_planned_lesson_id uuid references public.school_lesson_records(id) on delete restrict,
  source_actual_lesson_id uuid references public.school_lesson_records(id) on delete restrict,
  source_hours numeric not null,
  source_amount_jpy numeric not null,
  source_amount_cny numeric not null,
  settlement_exchange_rate numeric(12,6) not null check (settlement_exchange_rate > 0),
  calculation_version text not null check (
    calculation_version='lesson_variance_financial_netting_v1'
  ),
  line_manifest_sha256 text not null check (line_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  claim_status text not null check (claim_status in ('active','released')),
  released_at timestamptz,
  release_reason text,
  released_by text,
  created_at timestamptz not null default now(),
  created_by text not null,
  constraint school_student_settlement_lesson_variance_claims_source_chk check (
    (source_type='unused_planned_credit_v1'
      and source_planned_lesson_id is not null
      and source_actual_lesson_id is null
      and source_hours <= 0 and source_amount_jpy <= 0 and source_amount_cny <= 0)
    or
    (source_type='actual_duration_overage_charge_v1'
      and source_actual_lesson_id is not null
      and source_hours >= 0 and source_amount_jpy >= 0 and source_amount_cny >= 0)
  ),
  constraint school_student_settlement_lesson_variance_claims_release_chk check (
    (claim_status='active' and released_at is null and release_reason is null and released_by is null)
    or
    (claim_status='released' and released_at is not null
      and btrim(release_reason) <> '' and btrim(released_by) <> '')
  )
);

create unique index school_p0f_claim_batch_line_uidx
  on public.school_student_settlement_lesson_variance_claims(
    claim_batch_id,source_type,
    coalesce(source_planned_lesson_id,'00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(source_actual_lesson_id,'00000000-0000-0000-0000-000000000000'::uuid)
  );
create unique index school_p0f_claim_active_planned_uidx
  on public.school_student_settlement_lesson_variance_claims(source_planned_lesson_id)
  where claim_status='active' and source_type='unused_planned_credit_v1';
create unique index school_p0f_claim_active_actual_uidx
  on public.school_student_settlement_lesson_variance_claims(source_actual_lesson_id)
  where claim_status='active' and source_type='actual_duration_overage_charge_v1';
create index school_p0f_claim_settlement_idx
  on public.school_student_settlement_lesson_variance_claims(
    settlement_id,claim_batch_version,claim_status
  );

alter table public.school_student_settlement_source_treatment_drafts enable row level security;
alter table public.school_student_settlement_lesson_variance_claims enable row level security;
revoke all on public.school_student_settlement_source_treatment_drafts
  from public,anon,authenticated,service_role;
revoke all on public.school_student_settlement_lesson_variance_claims
  from public,anon,authenticated,service_role;
grant select on public.school_student_settlement_source_treatment_drafts to service_role;
grant select on public.school_student_settlement_lesson_variance_claims to service_role;

comment on table public.school_student_settlement_source_treatment_drafts is
  'P0-F append-preserved source-treatment draft versions. One active row per student/entity/month is the sole pre-lock mode/rate authority.';
comment on table public.school_student_settlement_lesson_variance_claims is
  'P0-F immutable source claims. Batch/version is carried on every line; unlock releases lines without deletion and relock creates a new batch.';
comment on column public.school_student_monthly_settlements.settlement_exchange_rate is
  'P0-F explicit frozen transaction rate for net lesson variance. It never falls back to or reinterprets preset_exchange_rate.';

do $verify$
begin
  if (select count(*) from public.school_student_monthly_settlements
      where source_treatment_mode is not null
         or settlement_exchange_rate is not null
         or lesson_variance_manifest_sha256 is not null) <> 0 then
    raise exception 'P0F_HISTORICAL_SETTLEMENT_MUTATED';
  end if;
end
$verify$;

\if :p0f_schema_commit
  commit;
\else
  rollback;
\endif
