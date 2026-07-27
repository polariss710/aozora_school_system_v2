-- School V2 tuition P0 R1A: normalized tuition-bill lesson snapshot empty table.
-- No historical relationship is inserted by this file.

begin;

create table if not exists public.school_student_tuition_bill_lessons (
  id uuid primary key default gen_random_uuid(),
  tuition_bill_id uuid not null,
  planned_lesson_id uuid not null,
  relation_role text not null,
  line_no integer not null,
  student_id_snapshot uuid not null,
  business_entity_id_snapshot uuid not null,
  billing_month_snapshot text not null,
  week_start_date_snapshot date,
  scheduled_lesson_date_snapshot date,
  teacher_id_snapshot uuid,
  subject_id_snapshot uuid,
  lesson_count_snapshot integer not null,
  duration_hours_snapshot numeric not null,
  unit_price_jpy_snapshot numeric not null,
  lesson_fee_jpy_snapshot numeric not null,
  source_lesson_updated_at timestamptz,
  source_snapshot jsonb not null default '{}'::jsonb,
  attribution_confidence text not null,
  snapshot_source text not null,
  backfill_batch_id uuid,
  created_at timestamptz not null default now(),
  created_by text not null default current_user,
  constraint school_tuition_bill_lessons_bill_fkey
    foreign key (tuition_bill_id)
    references public.school_student_tuition_bills(id)
    on delete restrict,
  constraint school_tuition_bill_lessons_planned_lesson_fkey
    foreign key (planned_lesson_id)
    references public.school_lesson_records(id)
    on delete restrict,
  constraint school_tuition_bill_lessons_bill_planned_key
    unique (tuition_bill_id, planned_lesson_id),
  constraint school_tuition_bill_lessons_bill_line_key
    unique (tuition_bill_id, line_no),
  constraint school_tuition_bill_lessons_relation_role_check
    check (
      relation_role in (
        'canonical_charge',
        'incident_duplicate',
        'legacy_cancelled'
      )
    ),
  constraint school_tuition_bill_lessons_line_no_check
    check (line_no > 0),
  constraint school_tuition_bill_lessons_billing_month_check
    check (billing_month_snapshot ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  constraint school_tuition_bill_lessons_lesson_count_check
    check (lesson_count_snapshot > 0),
  constraint school_tuition_bill_lessons_duration_check
    check (duration_hours_snapshot > 0),
  constraint school_tuition_bill_lessons_unit_price_check
    check (unit_price_jpy_snapshot >= 0),
  constraint school_tuition_bill_lessons_fee_check
    check (lesson_fee_jpy_snapshot >= 0),
  constraint school_tuition_bill_lessons_attribution_check
    check (attribution_confidence in ('high', 'medium', 'low')),
  constraint school_tuition_bill_lessons_snapshot_source_not_blank_check
    check (length(btrim(snapshot_source)) > 0),
  constraint school_tuition_bill_lessons_created_by_not_blank_check
    check (length(btrim(created_by)) > 0)
);

create unique index if not exists school_tuition_bill_lessons_canonical_planned_key
  on public.school_student_tuition_bill_lessons (planned_lesson_id)
  where relation_role = 'canonical_charge';

create index if not exists school_tuition_bill_lessons_bill_role_idx
  on public.school_student_tuition_bill_lessons (tuition_bill_id, relation_role, line_no);

comment on table public.school_student_tuition_bill_lessons is
  'Immutable normalized tuition-bill lesson relationships and charge snapshots. Canonical relationships uniquely consume a planned lesson.';
comment on column public.school_student_tuition_bill_lessons.week_start_date_snapshot is
  'Historical scheduled-week evidence. Nullable when the bill snapshot cannot reliably reconstruct it.';
comment on column public.school_student_tuition_bill_lessons.scheduled_lesson_date_snapshot is
  'Historical planned schedule date only. Actual lesson dates must never be stored here; nullable when unavailable.';
comment on column public.school_student_tuition_bill_lessons.source_snapshot is
  'Immutable source evidence used for the relationship and numeric lesson snapshots.';
comment on column public.school_student_tuition_bill_lessons.snapshot_source is
  'Evidence provenance, including whether values came from bill JSON or the current planned lesson row.';

revoke all on table public.school_student_tuition_bill_lessons
  from public, anon, authenticated, service_role;
grant select, insert on table public.school_student_tuition_bill_lessons
  to service_role;

commit;
