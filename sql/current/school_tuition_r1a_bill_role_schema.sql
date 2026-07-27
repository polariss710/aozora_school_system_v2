-- School V2 tuition P0 R1A: additive, nullable tuition-bill role fields.
-- R1A does not classify or update any existing bill row.

begin;

alter table public.school_student_tuition_bills
  add column if not exists billing_role text,
  add column if not exists incident_locked_at timestamptz,
  add column if not exists incident_reason text,
  add column if not exists cash_submission_blocked boolean not null default false;

alter table public.school_student_tuition_bills
  drop constraint if exists school_student_tuition_bills_billing_role_check,
  drop constraint if exists school_student_tuition_bills_incident_reason_not_blank_check;

alter table public.school_student_tuition_bills
  add constraint school_student_tuition_bills_billing_role_check
    check (
      billing_role is null
      or billing_role in (
        'canonical_charge',
        'incident_duplicate',
        'legacy_cancelled'
      )
    ),
  add constraint school_student_tuition_bills_incident_reason_not_blank_check
    check (
      incident_reason is null
      or length(btrim(incident_reason)) > 0
    );

create index if not exists school_student_tuition_bills_billing_role_idx
  on public.school_student_tuition_bills (billing_role, billing_month, student_id)
  where billing_role is not null;

comment on column public.school_student_tuition_bills.billing_role is
  'Permanent billing role. Nullable during R1A; later reviewed backfill may set canonical_charge, incident_duplicate, or legacy_cancelled.';
comment on column public.school_student_tuition_bills.incident_locked_at is
  'Timestamp when a later reviewed workflow permanently locks an incident bill.';
comment on column public.school_student_tuition_bills.incident_reason is
  'Immutable incident/legacy classification evidence recorded by a later reviewed workflow.';
comment on column public.school_student_tuition_bills.cash_submission_blocked is
  'Backend-authoritative bill-level Cash-submission exclusion flag. Existing rows receive false in R1A.';

commit;
