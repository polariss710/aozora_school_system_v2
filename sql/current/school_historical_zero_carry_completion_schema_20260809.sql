-- School V2 historical zero-carry completion evidence schema.
-- Approved business model: one immutable completion fact per student/month/entity.
-- Schema only. Execute with psql -1 after static review.
\set ON_ERROR_STOP on

create table if not exists public.school_student_monthly_settlement_historical_completion_evidence (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.school_students(id) on delete restrict,
  settlement_month text not null,
  business_entity_id uuid not null references public.school_business_entities(id) on delete restrict,
  final_carry_cny numeric not null default 0,
  lesson_count integer not null,
  lesson_manifest jsonb not null,
  lesson_manifest_sha256 text not null,
  makeup_source_count integer not null,
  makeup_remaining_hours numeric not null,
  makeup_manifest jsonb not null,
  makeup_manifest_sha256 text not null,
  active_revision_id uuid not null references public.school_student_tuition_generation_revisions(id) on delete restrict,
  tuition_bill_id uuid not null references public.school_student_tuition_bills(id) on delete restrict,
  income_record_id uuid not null references public.school_income_records(id) on delete restrict,
  cash_linkage_event_id uuid not null references public.school_personal_cash_income_linkage_events(id) on delete restrict,
  cash_request_id uuid not null,
  cash_transaction_id uuid not null,
  cash_transaction_currency text not null,
  evidence_version text not null default 'historical_zero_carry_completion_v1',
  evidence_manifest jsonb not null,
  evidence_manifest_sha256 text not null,
  idempotency_key text not null,
  payload_sha256 text not null,
  created_by_actor_id uuid not null,
  reason text not null,
  confirmation_text text not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint school_historical_zero_carry_scope_month_check
    check (settlement_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  constraint school_historical_zero_carry_final_check
    check (final_carry_cny = 0),
  constraint school_historical_zero_carry_counts_check
    check (lesson_count >= 0 and makeup_source_count >= 0 and makeup_remaining_hours >= 0),
  constraint school_historical_zero_carry_lesson_hash_check
    check (lesson_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  constraint school_historical_zero_carry_makeup_hash_check
    check (makeup_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  constraint school_historical_zero_carry_evidence_hash_check
    check (evidence_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  constraint school_historical_zero_carry_payload_hash_check
    check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  constraint school_historical_zero_carry_version_check
    check (evidence_version = 'historical_zero_carry_completion_v1'),
  constraint school_historical_zero_carry_cash_currency_check
    check (cash_transaction_currency in ('JPY','CNY')),
  constraint school_historical_zero_carry_idempotency_check
    check (btrim(idempotency_key) <> ''),
  constraint school_historical_zero_carry_reason_check
    check (btrim(reason) <> ''),
  constraint school_historical_zero_carry_confirmation_check
    check (btrim(confirmation_text) <> ''),
  constraint school_historical_zero_carry_scope_uniq
    unique (student_id, settlement_month, business_entity_id),
  constraint school_historical_zero_carry_idempotency_uniq
    unique (idempotency_key)
);

create index if not exists school_historical_zero_carry_revision_idx
  on public.school_student_monthly_settlement_historical_completion_evidence(active_revision_id);
create index if not exists school_historical_zero_carry_bill_idx
  on public.school_student_monthly_settlement_historical_completion_evidence(tuition_bill_id);
create index if not exists school_historical_zero_carry_income_idx
  on public.school_student_monthly_settlement_historical_completion_evidence(income_record_id);
create index if not exists school_historical_zero_carry_cash_request_idx
  on public.school_student_monthly_settlement_historical_completion_evidence(cash_request_id);
create index if not exists school_historical_zero_carry_cash_transaction_idx
  on public.school_student_monthly_settlement_historical_completion_evidence(cash_transaction_id);

alter table public.school_student_monthly_settlement_historical_completion_evidence enable row level security;

revoke all privileges on table public.school_student_monthly_settlement_historical_completion_evidence
  from public, anon, authenticated, service_role;

comment on table public.school_student_monthly_settlement_historical_completion_evidence is
  'Append-only historical completion evidence. It is not an ordinary monthly settlement, always carries CNY 0, and freezes authoritative lesson, makeup, successor tuition and Cash references.';
comment on column public.school_student_monthly_settlement_historical_completion_evidence.evidence_manifest is
  'DB-built immutable manifest for historical_zero_carry_completion_v1; frontend and callers never calculate it.';
comment on column public.school_student_monthly_settlement_historical_completion_evidence.created_by_actor_id is
  'Explicit active School admin/operator membership user UUID supplied by the trusted local tool and validated by the DB wrapper.';
