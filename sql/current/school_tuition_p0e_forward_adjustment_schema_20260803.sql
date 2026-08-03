-- P0-E schema: one append-only generation-revision forward-adjustment evidence table.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';

create table public.school_student_tuition_generation_revision_adjustments (
  id uuid primary key default gen_random_uuid(),
  generation_identity_id uuid not null references public.school_student_tuition_generation_identities(id),
  target_revision_id uuid not null references public.school_student_tuition_generation_revisions(id),
  target_billing_month date not null,
  source_previous_revision_id uuid not null references public.school_student_tuition_generation_revisions(id),
  source_settlement_id uuid not null references public.school_student_monthly_settlements(id),
  adjustment_type text not null check (adjustment_type='neutralize_historical_carryover_v1'),
  amount_cny numeric(14,2) not null,
  source_historical_carryover_cny numeric(14,2) not null,
  reason text not null check (btrim(reason)<>''),
  operator_authority text not null,
  created_at timestamptz not null default clock_timestamp(),
  line_manifest_sha256 text not null check (line_manifest_sha256~'^[0-9a-f]{64}$'),
  unique(target_revision_id),
  unique(generation_identity_id,target_revision_id,adjustment_type)
);
create index school_tuition_revision_adjustments_source_settlement_idx
  on public.school_student_tuition_generation_revision_adjustments(source_settlement_id);
create index school_tuition_revision_adjustments_source_revision_idx
  on public.school_student_tuition_generation_revision_adjustments(source_previous_revision_id);
alter table public.school_student_tuition_generation_revision_adjustments enable row level security;
revoke all on table public.school_student_tuition_generation_revision_adjustments from public,anon,authenticated;
revoke insert,update,delete,truncate,references,trigger
  on table public.school_student_tuition_generation_revision_adjustments from service_role;
grant select on table public.school_student_tuition_generation_revision_adjustments to service_role;
create policy school_tuition_revision_adjustments_service_read
  on public.school_student_tuition_generation_revision_adjustments for select to service_role using (true);

comment on table public.school_student_tuition_generation_revision_adjustments is
  'P0-E append-only generation revision evidence. Sole writer: dedicated P0-E Reissue core; never settlement authority.';
comment on column public.school_student_tuition_generation_revision_adjustments.amount_cny is
  'DB authority: negative source_historical_carryover_cny for neutralize_historical_carryover_v1.';

commit;
