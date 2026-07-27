-- School V2 tuition P0 R1D-B: minimal additive date and billing attribution schema.
--
-- Scope:
-- - add nullable attribution columns only;
-- - add deterministic read-only helpers and a read-only semantic view;
-- - add an empty append-only override audit table;
-- - add checks and partial indexes that do not infer or backfill old facts.
--
-- This file intentionally contains no lesson UPDATE/backfill, no candidate/writer
-- switch, no bill/income/Cash write, and no feature-gate mutation.

do $preflight$
declare
  v_lesson_count bigint;
  v_lesson_hash text;
begin
  if to_regprocedure('public.school_iso_week_start(date)') is not null
     or to_regprocedure('public.school_is_valid_tuition_billing_period(text,date)') is not null
     or to_regprocedure('public.school_guard_tuition_billing_override_audit_immutable()') is not null
     or to_regclass('public.school_lesson_date_semantics') is not null
     or to_regclass('public.school_tuition_billing_attribution_override_audit') is not null then
    raise exception 'R1D_B_PREFLIGHT_OBJECT_ALREADY_EXISTS';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'school_lesson_records'
      and column_name in (
        'billing_month',
        'billing_week_start_date',
        'scheduled_lesson_date',
        'student_settlement_month',
        'billing_month_source',
        'billing_month_decided_at'
      )
  ) then
    raise exception 'R1D_B_PREFLIGHT_COLUMN_ALREADY_EXISTS';
  end if;

  select
    count(*),
    md5(coalesce(string_agg(md5(to_jsonb(lesson)::text), '' order by lesson.id::text), ''))
  into v_lesson_count, v_lesson_hash
  from public.school_lesson_records lesson;

  if v_lesson_count <> 626
     or v_lesson_hash <> '4fb1901c888d56cb29c05e387490ca75' then
    raise exception 'R1D_B_PREFLIGHT_LESSON_BASELINE_CHANGED: count %, hash %',
      v_lesson_count,
      v_lesson_hash;
  end if;

  if not exists (
    select 1
    from public.school_feature_gates
    where feature_key = 'student_tuition_preview'
      and state = 'validation_preview_only'
  )
  or not exists (
    select 1
    from public.school_feature_gates
    where feature_key = 'student_tuition_generate'
      and state = 'blocked'
  )
  or not exists (
    select 1
    from public.school_feature_gates
    where feature_key = 'student_tuition_cash_submit'
      and state = 'blocked'
  ) then
    raise exception 'R1D_B_PREFLIGHT_R0_GATE_CHANGED';
  end if;
end;
$preflight$;

create function public.school_iso_week_start(p_input_date date)
returns date
language sql
immutable
strict
parallel safe
set search_path = pg_catalog
as $function$
  select (p_input_date - (extract(isodow from p_input_date)::integer - 1))::date;
$function$;

comment on function public.school_iso_week_start(date) is
  'R1D-B DB-authoritative ISO week Monday helper. NULL input returns NULL through STRICT; no business tables are read.';

revoke all on function public.school_iso_week_start(date) from public;
revoke all on function public.school_iso_week_start(date) from anon;
revoke all on function public.school_iso_week_start(date) from authenticated;
grant execute on function public.school_iso_week_start(date) to service_role;

create function public.school_is_valid_tuition_billing_period(
  p_billing_month text,
  p_billing_week_start_date date
)
returns boolean
language sql
immutable
parallel safe
set search_path = pg_catalog
as $function$
  select
    p_billing_month is not null
    and p_billing_week_start_date is not null
    and p_billing_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
    and extract(isodow from p_billing_week_start_date)::integer = 1
    and p_billing_month = to_char(p_billing_week_start_date, 'YYYY-MM');
$function$;

comment on function public.school_is_valid_tuition_billing_period(text, date) is
  'R1D-B read-only validator for an explicit billing_month plus ISO-Monday billing_week_start_date pair.';

revoke all on function public.school_is_valid_tuition_billing_period(text, date) from public;
revoke all on function public.school_is_valid_tuition_billing_period(text, date) from anon;
revoke all on function public.school_is_valid_tuition_billing_period(text, date) from authenticated;
grant execute on function public.school_is_valid_tuition_billing_period(text, date) to service_role;

alter table public.school_lesson_records
  add column billing_month text null,
  add column billing_week_start_date date null,
  add column scheduled_lesson_date date null,
  add column student_settlement_month text null,
  add column billing_month_source text null,
  add column billing_month_decided_at timestamptz null;

alter table public.school_lesson_records
  add constraint school_lesson_records_billing_month_format_chk
    check (
      billing_month is null
      or billing_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
    ),
  add constraint school_lesson_records_student_settlement_month_format_chk
    check (
      student_settlement_month is null
      or student_settlement_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
    ),
  add constraint school_lesson_records_billing_pair_complete_chk
    check (
      (billing_month is null and billing_week_start_date is null)
      or (billing_month is not null and billing_week_start_date is not null)
    ),
  add constraint school_lesson_records_billing_week_monday_chk
    check (
      billing_week_start_date is null
      or extract(isodow from billing_week_start_date)::integer = 1
    ),
  add constraint school_lesson_records_billing_month_week_match_chk
    check (
      billing_week_start_date is null
      or billing_month = to_char(billing_week_start_date, 'YYYY-MM')
    ),
  add constraint school_lesson_records_planned_attribution_fields_chk
    check (
      lesson_type = 'planned'
      or (
        billing_month is null
        and billing_week_start_date is null
        and scheduled_lesson_date is null
        and billing_month_source is null
        and billing_month_decided_at is null
      )
    ),
  add constraint school_lesson_records_billing_source_metadata_chk
    check (
      (billing_month_source is null and billing_month_decided_at is null)
      or (
        billing_month_source is not null
        and nullif(btrim(billing_month_source), '') is not null
        and char_length(btrim(billing_month_source)) <= 100
        and billing_month_decided_at is not null
        and billing_month is not null
        and billing_week_start_date is not null
      )
    );

comment on column public.school_lesson_records.billing_month is
  'R1D-B nullable authoritative tuition billing month (YYYY-MM). Planned-only; frozen with billing_week_start_date by a future controlled writer.';
comment on column public.school_lesson_records.billing_week_start_date is
  'R1D-B nullable authoritative tuition billing ISO Monday. Independent from scheduled_lesson_date.';
comment on column public.school_lesson_records.scheduled_lesson_date is
  'R1D-B nullable planned-only expected lesson date for scheduling/display. It must not derive or mutate billing attribution.';
comment on column public.school_lesson_records.student_settlement_month is
  'R1D-B nullable student settlement attribution month (YYYY-MM). Future planned writers default from billing; actual writers inherit source planned.';
comment on column public.school_lesson_records.billing_month_source is
  'R1D-B nullable nonblank evidence/source label for a future controlled billing attribution decision.';
comment on column public.school_lesson_records.billing_month_decided_at is
  'R1D-B nullable timestamp when a future controlled billing attribution decision is frozen; not a transaction commit timestamp.';

create index idx_school_lesson_records_planned_billing_month
  on public.school_lesson_records (student_id, business_entity_id, billing_month)
  where lesson_type = 'planned'
    and billing_month is not null
    and voided_at is null;

create index idx_school_lesson_records_planned_billing_week
  on public.school_lesson_records (billing_week_start_date, student_id, business_entity_id)
  where lesson_type = 'planned'
    and billing_week_start_date is not null
    and voided_at is null;

create index idx_school_lesson_records_student_settlement_month
  on public.school_lesson_records (student_id, business_entity_id, student_settlement_month)
  where student_settlement_month is not null;

create index idx_school_lesson_records_planned_scheduled_date
  on public.school_lesson_records (scheduled_lesson_date, start_time, end_time)
  where lesson_type = 'planned'
    and scheduled_lesson_date is not null
    and voided_at is null;

create view public.school_lesson_date_semantics
with (security_invoker = true)
as
select distinct
  lesson.id,
  lesson.app_type,
  lesson.lesson_type,
  lesson.student_id,
  lesson.teacher_id,
  lesson.subject_id,
  lesson.business_entity_id,
  lesson.status,
  lesson.lesson_date as legacy_lesson_date,
  lesson.year_month as legacy_year_month,
  lesson.start_time as legacy_start_time,
  lesson.end_time as legacy_end_time,
  lesson.scheduled_lesson_date,
  case
    when lesson.lesson_type = 'planned' then lesson.lesson_date
    else null::date
  end as legacy_planned_scheduled_date_inferred,
  case
    when lesson.lesson_type = 'actual' then lesson.lesson_date
    else null::date
  end as actual_occurred_date,
  lesson.billing_week_start_date,
  lesson.billing_month,
  lesson.student_settlement_month,
  lesson.teacher_settlement_month,
  lesson.billing_month_source,
  lesson.billing_month_decided_at,
  lesson.planned_lesson_id,
  lesson.created_at,
  lesson.updated_at
from public.school_lesson_records lesson;

comment on view public.school_lesson_date_semantics is
  'R1D-B non-updatable service-role semantic projection. Authoritative nullable fields remain NULL; explicitly named legacy inference never masquerades as frozen billing/schedule evidence.';

revoke all on table public.school_lesson_date_semantics from public;
revoke all on table public.school_lesson_date_semantics from anon;
revoke all on table public.school_lesson_date_semantics from authenticated;
revoke all on table public.school_lesson_date_semantics from service_role;
grant select on table public.school_lesson_date_semantics to service_role;

create table public.school_tuition_billing_attribution_override_audit (
  id uuid primary key default gen_random_uuid(),
  planned_lesson_id uuid not null
    references public.school_lesson_records(id) on delete restrict,
  before_billing_month text null,
  before_billing_week_start_date date null,
  requested_billing_month text not null,
  requested_billing_week_start_date date not null,
  reason text not null,
  evidence_source text not null,
  business_approval text not null,
  expected_lesson_updated_at timestamptz null,
  before_row_hash text not null,
  requested_by text not null,
  requested_at timestamptz not null default now(),
  executed_by text null,
  executed_at timestamptz null,
  execution_status text not null,
  failure_reason text null,
  created_at timestamptz not null default now(),
  constraint school_tuition_billing_override_before_pair_chk check (
    (before_billing_month is null and before_billing_week_start_date is null)
    or public.school_is_valid_tuition_billing_period(
      before_billing_month,
      before_billing_week_start_date
    )
  ),
  constraint school_tuition_billing_override_requested_pair_chk check (
    public.school_is_valid_tuition_billing_period(
      requested_billing_month,
      requested_billing_week_start_date
    )
  ),
  constraint school_tuition_billing_override_text_chk check (
    nullif(btrim(reason), '') is not null
    and nullif(btrim(evidence_source), '') is not null
    and nullif(btrim(business_approval), '') is not null
    and nullif(btrim(before_row_hash), '') is not null
    and nullif(btrim(requested_by), '') is not null
  ),
  constraint school_tuition_billing_override_status_chk check (
    execution_status in ('executed', 'rejected', 'failed')
  ),
  constraint school_tuition_billing_override_outcome_chk check (
    (
      execution_status = 'executed'
      and executed_by is not null
      and nullif(btrim(executed_by), '') is not null
      and executed_at is not null
      and failure_reason is null
    )
    or (
      execution_status in ('rejected', 'failed')
      and executed_by is not null
      and nullif(btrim(executed_by), '') is not null
      and executed_at is not null
      and nullif(btrim(failure_reason), '') is not null
    )
  )
);

comment on table public.school_tuition_billing_attribution_override_audit is
  'R1D-B empty append-only evidence table for a future separately authorized controlled billing attribution override. This phase installs no override entry point.';
comment on column public.school_tuition_billing_attribution_override_audit.requested_at is
  'Audit request/evidence timestamp; not a database transaction commit timestamp.';
comment on column public.school_tuition_billing_attribution_override_audit.executed_at is
  'Audit execution timestamp supplied by the future controlled workflow; not a database transaction commit timestamp.';

create index idx_school_tuition_billing_override_audit_lesson_created
  on public.school_tuition_billing_attribution_override_audit
    (planned_lesson_id, created_at desc);

create function public.school_guard_tuition_billing_override_audit_immutable()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  raise exception 'TUITION_BILLING_OVERRIDE_AUDIT_IMMUTABLE';
end;
$function$;

comment on function public.school_guard_tuition_billing_override_audit_immutable() is
  'R1D-B append-only guard: override audit evidence cannot be updated or deleted.';

revoke all on function public.school_guard_tuition_billing_override_audit_immutable() from public;
revoke all on function public.school_guard_tuition_billing_override_audit_immutable() from anon;
revoke all on function public.school_guard_tuition_billing_override_audit_immutable() from authenticated;
revoke all on function public.school_guard_tuition_billing_override_audit_immutable() from service_role;

create trigger school_tuition_billing_override_audit_immutable
before update or delete on public.school_tuition_billing_attribution_override_audit
for each row
execute function public.school_guard_tuition_billing_override_audit_immutable();

revoke all on table public.school_tuition_billing_attribution_override_audit from public;
revoke all on table public.school_tuition_billing_attribution_override_audit from anon;
revoke all on table public.school_tuition_billing_attribution_override_audit from authenticated;
revoke all on table public.school_tuition_billing_attribution_override_audit from service_role;
grant select on table public.school_tuition_billing_attribution_override_audit to service_role;
