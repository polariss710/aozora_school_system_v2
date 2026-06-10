-- school_student_settlement_adjustment_drafts_schema.sql
-- Purpose: Add pre-lock student monthly settlement difference adjustment drafts.
-- Status: EXECUTED ON SUPABASE. Read-verified after execution.
--
-- Scope:
-- - Add one draft table keyed by student + month for adjustments entered before locking.
-- - Drafts are consumed by lock/relock RPCs and preserved for audit linkage.
-- - No historical backfill, cleanup, destructive operation, or business data repair.

create table if not exists public.school_student_settlement_adjustment_drafts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.school_students(id),
  year_month text not null,
  business_entity_id uuid references public.school_business_entities(id),
  adjustment_amount_cny numeric not null default 0,
  adjustment_source text not null default 'manual',
  adjustment_reason text not null,
  note text,
  status text not null default 'active',
  settlement_id uuid references public.school_student_monthly_settlements(id),
  app_type text not null default 'school',
  created_by text not null default current_user,
  updated_by text not null default current_user,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint school_student_settlement_adjustment_drafts_month_format_chk
    check (year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  constraint school_student_settlement_adjustment_drafts_status_chk
    check (status in ('active', 'consumed')),
  constraint school_student_settlement_adjustment_drafts_app_type_chk
    check (app_type = 'school')
);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'school_student_settlement_adjustment_drafts_student_month_key'
      and conrelid = 'public.school_student_settlement_adjustment_drafts'::regclass
  ) then
    if exists (
      select 1
      from pg_indexes
      where schemaname = 'public'
        and tablename = 'school_student_settlement_adjustment_drafts'
        and indexname = 'school_student_settlement_adjustment_drafts_student_month_uidx'
    ) then
      alter table public.school_student_settlement_adjustment_drafts
        add constraint school_student_settlement_adjustment_drafts_student_month_key
        unique using index school_student_settlement_adjustment_drafts_student_month_uidx;
    else
      alter table public.school_student_settlement_adjustment_drafts
        add constraint school_student_settlement_adjustment_drafts_student_month_key
        unique (student_id, year_month, app_type);
    end if;
  end if;
end $$;

create index if not exists school_student_settlement_adjustment_drafts_status_idx
  on public.school_student_settlement_adjustment_drafts(status, year_month);

create index if not exists school_student_settlement_adjustment_drafts_settlement_idx
  on public.school_student_settlement_adjustment_drafts(settlement_id);

comment on table public.school_student_settlement_adjustment_drafts is
  'Pre-lock student monthly settlement difference adjustment drafts. Active drafts are included in preview and consumed into the locked settlement snapshot.';

comment on column public.school_student_settlement_adjustment_drafts.adjustment_amount_cny is
  'Signed CNY adjustment amount entered before settlement locking. It is added to the calculated system difference when locking.';

comment on column public.school_student_settlement_adjustment_drafts.status is
  'active means the draft is used by preview/lock; consumed means it has been frozen into a settlement snapshot.';
