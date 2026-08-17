-- School V2 Phase 2C-C production clearance schema migration.
-- Creates only append-only clearance header/detail facts. Phase 2I-A package lot is reused.
\set ON_ERROR_STOP on

\if :{?PHASE2C_C_REHEARSAL}
\else
begin;
\endif

do $preflight$
begin
  if to_regclass('public.school_lesson_clearances') is not null
     or to_regclass('public.school_lesson_clearance_details') is not null then
    raise exception 'LESSON_CLEARANCE_SCHEMA_ALREADY_EXISTS';
  end if;
  if to_regclass('public.school_student_package_credit_lots') is null
     or to_regprocedure('public.school_is_active_package_credit_origin(uuid)') is null
     or to_regprocedure('public.school_list_student_package_credit_lots(uuid)') is null then
    raise exception 'LESSON_CLEARANCE_PHASE2I_A_PACKAGE_CONTRACT_MISSING';
  end if;
  perform 'public.school_students'::regclass;
  perform 'public.school_business_entities'::regclass;
  perform 'public.school_lesson_records'::regclass;
  perform 'public.school_student_monthly_settlements'::regclass;
  perform 'public.school_student_settlement_lesson_variance_claims'::regclass;
  perform 'public.school_student_tuition_bills'::regclass;
  perform 'public.school_student_tuition_generation_revisions'::regclass;
  perform 'public.school_income_records'::regclass;
  perform 'public.school_personal_cash_income_linkage_events'::regclass;
end
$preflight$;

create table public.school_lesson_clearances (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.school_students(id) on delete restrict,
  business_entity_id uuid not null
    references public.school_business_entities(id) on delete restrict,
  clearance_type text not null check (clearance_type in (
    'overtime_offset',
    'administrative_writeoff',
    'legacy_consolidated_fulfillment',
    'reversal'
  )),
  operation_date date not null,
  operational_year_month text not null
    check (operational_year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  financial_year_month text
    check (financial_year_month is null
      or financial_year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  requires_forward_adjustment boolean not null default false,
  selection_mode text not null default 'manual'
    check (selection_mode = 'manual'),
  recommended_pending_source_id uuid
    references public.school_lesson_records(id) on delete restrict,
  deviated_from_recommendation boolean not null default false,
  deviation_reason_code text,
  deviation_note text,
  business_note text not null check (btrim(business_note) <> ''),
  administrative_financial_treatment text check (
    administrative_financial_treatment is null
    or administrative_financial_treatment in (
      'no_refund_no_credit',
      'financial_adjustment_required'
    )
  ),
  actor_user_id uuid not null,
  actor_role text not null check (actor_role in ('admin','operator','owner')),
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  reverses_clearance_id uuid
    references public.school_lesson_clearances(id) on delete restrict,
  rule_version text not null default 'lesson_clearance_v2_same_price_v1'
    check (rule_version = 'lesson_clearance_v2_same_price_v1'),
  input_manifest_sha256 text not null
    check (input_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default transaction_timestamp(),
  constraint school_lesson_clearances_month_date_chk check (
    operational_year_month = to_char(operation_date,'YYYY-MM')
  ),
  constraint school_lesson_clearances_deviation_chk check (
    (deviated_from_recommendation is false
      and deviation_reason_code is null and deviation_note is null)
    or
    (deviated_from_recommendation is true
      and recommended_pending_source_id is not null
      and btrim(coalesce(deviation_reason_code,'')) <> '')
  ),
  constraint school_lesson_clearances_admin_treatment_chk check (
    (clearance_type='administrative_writeoff'
      and administrative_financial_treatment is not null)
    or
    (clearance_type<>'administrative_writeoff'
      and administrative_financial_treatment is null)
  ),
  constraint school_lesson_clearances_reversal_chk check (
    (clearance_type='reversal' and reverses_clearance_id is not null)
    or (clearance_type<>'reversal' and reverses_clearance_id is null)
  ),
  constraint school_lesson_clearances_forward_month_chk check (
    (requires_forward_adjustment is false and financial_year_month is null)
    or
    (requires_forward_adjustment is true and financial_year_month is not null)
  ),
  constraint school_lesson_clearances_idempotency_uniq unique (
    student_id,business_entity_id,idempotency_key
  )
);

create unique index school_lesson_clearances_reversal_once_uidx
  on public.school_lesson_clearances(reverses_clearance_id)
  where clearance_type='reversal';
create index school_lesson_clearances_student_month_idx
  on public.school_lesson_clearances(
    student_id,business_entity_id,operational_year_month,created_at,id
  );

create table public.school_lesson_clearance_details (
  id uuid primary key default gen_random_uuid(),
  clearance_id uuid not null
    references public.school_lesson_clearances(id) on delete restrict,
  line_no integer not null check (line_no > 0),
  pending_source_planned_id uuid not null
    references public.school_lesson_records(id) on delete restrict,
  overtime_source_actual_id uuid
    references public.school_lesson_records(id) on delete restrict,
  allocated_minutes integer not null
    check (allocated_minutes > 0 and allocated_minutes % 15 = 0),
  balance_effect text not null check (balance_effect in ('consume','restore')),
  pending_unit_price_jpy numeric not null check (pending_unit_price_jpy >= 0),
  overtime_unit_price_jpy numeric check (
    overtime_unit_price_jpy is null or overtime_unit_price_jpy >= 0
  ),
  pending_source_year_month text not null
    check (pending_source_year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  overtime_source_year_month text check (
    overtime_source_year_month is null
    or overtime_source_year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
  ),
  pending_before_minutes integer not null check (pending_before_minutes >= 0),
  pending_after_minutes integer not null check (pending_after_minutes >= 0),
  overtime_before_minutes integer check (
    overtime_before_minutes is null or overtime_before_minutes >= 0
  ),
  overtime_after_minutes integer check (
    overtime_after_minutes is null or overtime_after_minutes >= 0
  ),
  forward_adjustment_direction text not null default 'none'
    check (forward_adjustment_direction in (
      'none','increase_student_due','decrease_student_due'
    )),
  forward_adjustment_amount_jpy numeric not null default 0
    check (forward_adjustment_amount_jpy>=0),
  forward_adjustment_amount_source text not null
    default 'same_unit_price_zero_residual_v1'
    check (forward_adjustment_amount_source in (
      'same_unit_price_zero_residual_v1','pending_unit_price_minutes_v1'
    )),
  pending_source_updated_at timestamptz not null,
  pending_source_row_md5 text not null check (pending_source_row_md5 ~ '^[0-9a-f]{32}$'),
  overtime_source_updated_at timestamptz,
  overtime_source_row_md5 text check (
    overtime_source_row_md5 is null or overtime_source_row_md5 ~ '^[0-9a-f]{32}$'
  ),
  created_at timestamptz not null default transaction_timestamp(),
  constraint school_lesson_clearance_details_line_uniq unique(clearance_id,line_no),
  constraint school_lesson_clearance_details_forward_amount_chk check (
    (forward_adjustment_direction='none' and forward_adjustment_amount_jpy=0)
    or
    (forward_adjustment_direction in ('increase_student_due','decrease_student_due')
      and forward_adjustment_amount_jpy>0
      and forward_adjustment_amount_source='pending_unit_price_minutes_v1')
  ),
  constraint school_lesson_clearance_details_pending_balance_chk check (
    (balance_effect='consume'
      and pending_after_minutes = pending_before_minutes - allocated_minutes)
    or
    (balance_effect='restore'
      and pending_after_minutes = pending_before_minutes + allocated_minutes)
  ),
  constraint school_lesson_clearance_details_overtime_balance_chk check (
    (overtime_source_actual_id is null
      and overtime_unit_price_jpy is null
      and overtime_source_year_month is null
      and overtime_before_minutes is null
      and overtime_after_minutes is null
      and overtime_source_updated_at is null
      and overtime_source_row_md5 is null)
    or
    (overtime_source_actual_id is not null
      and overtime_unit_price_jpy is not null
      and overtime_source_year_month is not null
      and overtime_before_minutes is not null
      and (
        (balance_effect='consume'
          and overtime_after_minutes = overtime_before_minutes - allocated_minutes)
        or
        (balance_effect='restore'
          and overtime_after_minutes = overtime_before_minutes + allocated_minutes)
      )
      and overtime_source_updated_at is not null
      and overtime_source_row_md5 is not null)
  )
);

create index school_lesson_clearance_details_pending_idx
  on public.school_lesson_clearance_details(pending_source_planned_id,created_at,id);
create index school_lesson_clearance_details_overtime_idx
  on public.school_lesson_clearance_details(overtime_source_actual_id,created_at,id)
  where overtime_source_actual_id is not null;

alter table public.school_lesson_clearances enable row level security;
alter table public.school_lesson_clearance_details enable row level security;
alter table public.school_lesson_clearances owner to postgres;
alter table public.school_lesson_clearance_details owner to postgres;

revoke all on public.school_lesson_clearances from public,anon,authenticated,service_role;
revoke all on public.school_lesson_clearance_details from public,anon,authenticated,service_role;

comment on table public.school_lesson_clearances is
  'Phase 2C-C append-only manual lesson-clearance headers. No automatic target selection and no ordinary makeup duplication.';
comment on table public.school_lesson_clearance_details is
  'Phase 2C-C immutable integer-minute allocations. Effective balances include appended reversal facts and never update prior rows.';

\if :{?PHASE2C_C_REHEARSAL}
\else
commit;
\endif
