-- School V2 tuition P0 R1A: additive incident-isolation fields for income.
-- This file changes schema only. It does not update any existing income row.

begin;

alter table public.school_income_records
  add column if not exists status_before_quarantine text,
  add column if not exists incident_type text,
  add column if not exists incident_canonical_income_id uuid,
  add column if not exists incident_canonical_bill_id uuid,
  add column if not exists incident_duplicate_bill_id uuid,
  add column if not exists incident_quarantined_at timestamptz,
  add column if not exists incident_quarantined_by text,
  add column if not exists incident_reason text,
  add column if not exists cash_submission_blocked boolean not null default false,
  add column if not exists operational_excluded boolean not null default false;

alter table public.school_income_records
  drop constraint if exists school_income_records_status_check;

alter table public.school_income_records
  drop constraint if exists school_income_records_status_before_quarantine_check,
  drop constraint if exists school_income_records_incident_type_not_blank_check,
  drop constraint if exists school_income_records_incident_actor_not_blank_check,
  drop constraint if exists school_income_records_incident_reason_not_blank_check,
  drop constraint if exists school_income_records_incident_quarantine_state_check,
  drop constraint if exists school_income_records_incident_canonical_income_fkey,
  drop constraint if exists school_income_records_incident_canonical_bill_fkey,
  drop constraint if exists school_income_records_incident_duplicate_bill_fkey;

alter table public.school_income_records
  add constraint school_income_records_status_check
    check (
      status in (
        'pending',
        'received',
        'reversed',
        'cancelled',
        'incident_quarantined'
      )
    ),
  add constraint school_income_records_status_before_quarantine_check
    check (
      status_before_quarantine is null
      or status_before_quarantine in ('pending', 'received', 'reversed', 'cancelled')
    ),
  add constraint school_income_records_incident_type_not_blank_check
    check (
      incident_type is null
      or length(btrim(incident_type)) > 0
    ),
  add constraint school_income_records_incident_actor_not_blank_check
    check (
      incident_quarantined_by is null
      or length(btrim(incident_quarantined_by)) > 0
    ),
  add constraint school_income_records_incident_reason_not_blank_check
    check (
      incident_reason is null
      or length(btrim(incident_reason)) > 0
    ),
  add constraint school_income_records_incident_quarantine_state_check
    check (
      (
        status = 'incident_quarantined'
        and status_before_quarantine is not null
        and incident_type is not null
        and incident_canonical_income_id is not null
        and incident_canonical_bill_id is not null
        and incident_duplicate_bill_id is not null
        and incident_quarantined_at is not null
        and incident_quarantined_by is not null
        and incident_reason is not null
        and cash_submission_blocked
        and operational_excluded
      )
      or (
        status <> 'incident_quarantined'
        and status_before_quarantine is null
        and incident_type is null
        and incident_canonical_income_id is null
        and incident_canonical_bill_id is null
        and incident_duplicate_bill_id is null
        and incident_quarantined_at is null
        and incident_quarantined_by is null
        and incident_reason is null
        and not cash_submission_blocked
        and not operational_excluded
      )
    ),
  add constraint school_income_records_incident_canonical_income_fkey
    foreign key (incident_canonical_income_id)
    references public.school_income_records(id)
    on delete restrict,
  add constraint school_income_records_incident_canonical_bill_fkey
    foreign key (incident_canonical_bill_id)
    references public.school_student_tuition_bills(id)
    on delete restrict,
  add constraint school_income_records_incident_duplicate_bill_fkey
    foreign key (incident_duplicate_bill_id)
    references public.school_student_tuition_bills(id)
    on delete restrict;

create index if not exists school_income_records_incident_status_idx
  on public.school_income_records (status, incident_type, incident_quarantined_at)
  where status = 'incident_quarantined';

create index if not exists school_income_records_incident_canonical_income_idx
  on public.school_income_records (incident_canonical_income_id)
  where incident_canonical_income_id is not null;

comment on column public.school_income_records.status_before_quarantine is
  'R1A incident evidence: the authoritative income status immediately before incident quarantine.';
comment on column public.school_income_records.incident_type is
  'R1A incident classification. Null for all normal and pre-R1A income rows.';
comment on column public.school_income_records.incident_canonical_income_id is
  'Canonical income retained for an isolated duplicate incident; protected by ON DELETE RESTRICT.';
comment on column public.school_income_records.incident_canonical_bill_id is
  'Canonical tuition bill retained for an isolated tuition incident; protected by ON DELETE RESTRICT.';
comment on column public.school_income_records.incident_duplicate_bill_id is
  'Duplicate tuition bill associated with the isolated income; protected by ON DELETE RESTRICT.';
comment on column public.school_income_records.incident_quarantined_at is
  'Timestamp of a later reviewed incident-quarantine operation. R1A performs no such operation.';
comment on column public.school_income_records.incident_quarantined_by is
  'Operator recorded by a later reviewed incident-quarantine operation.';
comment on column public.school_income_records.incident_reason is
  'Immutable incident evidence recorded by a later reviewed quarantine operation.';
comment on column public.school_income_records.cash_submission_blocked is
  'Backend-authoritative Cash-submission exclusion flag. Existing rows receive the safe false default.';
comment on column public.school_income_records.operational_excluded is
  'Backend-authoritative operational-read exclusion flag. Existing reads are not switched to this flag in R1A.';

commit;
