-- School V2 tuition P0 R1A: permanent billing identity empty table.
-- The table is intentionally empty after R1A.

begin;

create table if not exists public.school_student_tuition_billing_identities (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null,
  billing_month text not null,
  canonical_bill_id uuid not null,
  creation_idempotency_key text not null,
  source text not null,
  created_at timestamptz not null default now(),
  created_by text not null default current_user,
  evidence jsonb not null default '{}'::jsonb,
  constraint school_tuition_billing_identities_student_fkey
    foreign key (student_id)
    references public.school_students(id)
    on delete restrict,
  constraint school_tuition_billing_identities_canonical_bill_fkey
    foreign key (canonical_bill_id)
    references public.school_student_tuition_bills(id)
    on delete restrict,
  constraint school_tuition_billing_identities_student_month_key
    unique (student_id, billing_month),
  constraint school_tuition_billing_identities_canonical_bill_key
    unique (canonical_bill_id),
  constraint school_tuition_billing_identities_idempotency_key
    unique (creation_idempotency_key),
  constraint school_tuition_billing_identities_month_check
    check (billing_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  constraint school_tuition_billing_identities_idempotency_not_blank_check
    check (length(btrim(creation_idempotency_key)) > 0),
  constraint school_tuition_billing_identities_source_check
    check (source in ('historical_backfill', 'atomic_charge')),
  constraint school_tuition_billing_identities_created_by_not_blank_check
    check (length(btrim(created_by)) > 0)
);

alter table public.school_student_tuition_billing_identities
  drop constraint if exists school_tuition_billing_identities_source_not_blank_check,
  drop constraint if exists school_tuition_billing_identities_source_check;

alter table public.school_student_tuition_billing_identities
  add constraint school_tuition_billing_identities_source_check
    check (source in ('historical_backfill', 'atomic_charge'));

comment on table public.school_student_tuition_billing_identities is
  'Permanent one-per-student-month tuition charging identity. Rows are append-only and may point only to the canonical bill.';
comment on column public.school_student_tuition_billing_identities.creation_idempotency_key is
  'Permanent backend-generated idempotency key for identity creation.';
comment on column public.school_student_tuition_billing_identities.evidence is
  'Immutable evidence supporting the canonical bill selection.';

revoke all on table public.school_student_tuition_billing_identities
  from public, anon, authenticated, service_role;
grant select, insert on table public.school_student_tuition_billing_identities
  to service_role;

commit;
