-- school_tuition_r0_feature_gate_schema.sql
-- R0 schema only. Creates the authoritative fail-closed feature-gate store.
-- This file does not create functions and does not modify business records.

begin;

create table if not exists public.school_feature_gates (
  feature_key text primary key,
  state text not null,
  reason text not null,
  release_version text not null,
  evidence_hash text,
  updated_at timestamptz not null default now(),
  updated_by text not null default current_user,
  constraint school_feature_gates_key_check check (
    feature_key in (
      'student_tuition_preview',
      'student_tuition_generate',
      'student_tuition_cash_submit'
    )
  ),
  constraint school_feature_gates_state_check check (
    state in ('validation_preview_only', 'blocked')
  )
);

comment on table public.school_feature_gates is
  'Backend-authoritative School feature gates. R0 supports validation_preview_only and blocked only; enabling requires a later reviewed migration.';

comment on column public.school_feature_gates.evidence_hash is
  'Optional deployment/review evidence hash. R0 reserves the field without requiring a value.';

revoke all on table public.school_feature_gates from public, anon, authenticated;
grant select on table public.school_feature_gates to service_role;

alter table public.school_feature_gates enable row level security;

commit;
