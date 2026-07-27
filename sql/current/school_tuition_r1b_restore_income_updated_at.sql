-- School V2 tuition P0 R1B: restore the nine original income.updated_at values
-- after the generic timestamp trigger fired during the authorized backfill.
-- Required psql variable: r1b_restore_commit=0 for rollback rehearsal or 1 for commit.

\set ON_ERROR_STOP on

begin;
lock table public.school_income_records in access exclusive mode;

create temp table r1b_original_income_timestamps (
  income_id uuid primary key,
  expected_status_before_r1b text not null,
  original_updated_at timestamptz not null,
  expected_original_hash text not null
) on commit drop;

insert into r1b_original_income_timestamps values
  ('09fa4398-9d20-494b-8ab5-8f7c3cafa414', 'received',  '2026-07-13 04:28:45.530825+00', 'e208d10927f40820ffd6bc08c57a3396'),
  ('3a5542c5-5397-4688-999e-a08bb678f40d', 'received',  '2026-07-08 08:29:05.316602+00', 'a7222d442cdac4563e165b6848fc1e7b'),
  ('468ab75b-312e-4ba0-8d8d-8ae2f6ace00e', 'received',  '2026-07-13 04:35:55.241111+00', '76e751b4c6f8855b502591b78286f66f'),
  ('474f0fd2-71ca-4cce-9ba5-e615bd390151', 'cancelled', '2026-07-01 16:33:28.994556+00', '501e1612d4332ef60ec4ffeb14efa471'),
  ('4a63f0ca-450f-4306-9e39-6d43172b3cf8', 'received',  '2026-07-04 14:36:59.682104+00', '02559bbf6d7958f4a43c6f4b778b304b'),
  ('91756564-c48d-4a1d-b6bc-88a041660e46', 'received',  '2026-07-17 00:10:14.268923+00', '1b17ab68571e0377f841670698cf8f06'),
  ('bbd7e7fd-fa04-404b-91fc-ab894cca28c8', 'pending',   '2026-07-26 16:11:01.234382+00', '883dccc58fd713a644ad7b5d9d200a91'),
  ('cdf3da68-e578-4f1b-b759-2fff394e1906', 'received',  '2026-07-04 14:36:56.813552+00', '18570150dc49316287523ea34d34b2a8'),
  ('f86ac9db-effd-402e-a320-1e4b6846a9c7', 'received',  '2026-07-13 04:36:00.953664+00', '99d438fc9f4bcf2d2080584d6e3a0e28');

do $$
begin
  if (select count(*) from r1b_original_income_timestamps) <> 9
     or (select count(*) from public.school_income_records i join r1b_original_income_timestamps m on m.income_id = i.id) <> 9
     or (select count(distinct updated_at) from public.school_income_records i join r1b_original_income_timestamps m on m.income_id = i.id) <> 1
     or not exists (
       select 1 from public.school_income_records i
       join r1b_original_income_timestamps m on m.income_id = i.id
       where i.updated_at = '2026-07-27 08:26:29.320017+00'::timestamptz
     ) then
    raise exception 'R1B_UPDATED_AT_RESTORE_PRECONDITION_FAILED';
  end if;

  if (select count(*) from public.school_income_records where status = 'incident_quarantined') <> 1
     or (select count(*) from public.school_student_tuition_billing_identities) <> 7
     or (select count(*) from public.school_student_tuition_bill_lessons) <> 121 then
    raise exception 'R1B_BACKFILL_STATE_MISSING_BEFORE_TIMESTAMP_RESTORE';
  end if;

  if (select count(*)
      from r1b_original_income_timestamps m
      join public.school_income_records i on i.id = m.income_id
      where md5((
        (to_jsonb(i) || jsonb_build_object(
          'status', m.expected_status_before_r1b,
          'updated_at', m.original_updated_at
        )) - array[
          'status_before_quarantine','incident_type','incident_canonical_income_id',
          'incident_canonical_bill_id','incident_duplicate_bill_id','incident_quarantined_at',
          'incident_quarantined_by','incident_reason','cash_submission_blocked',
          'operational_excluded','tuition_bill_id'
        ]::text[]
      )::text) = m.expected_original_hash) <> 9 then
    raise exception 'R1B_UPDATED_AT_RESTORE_HASH_PROOF_FAILED';
  end if;
end;
$$;

alter table public.school_income_records
  disable trigger school_r0_tuition_income_mutation_guard;
alter table public.school_income_records
  disable trigger school_incident_quarantined_income_immutable;
alter table public.school_income_records
  disable trigger trg_school_income_records_updated_at;

update public.school_income_records i
set updated_at = m.original_updated_at
from r1b_original_income_timestamps m
where i.id = m.income_id;

set constraints all immediate;

alter table public.school_income_records
  enable trigger trg_school_income_records_updated_at;
alter table public.school_income_records
  enable trigger school_incident_quarantined_income_immutable;
alter table public.school_income_records
  enable trigger school_r0_tuition_income_mutation_guard;

do $$
begin
  if (select count(*)
      from r1b_original_income_timestamps m
      join public.school_income_records i on i.id = m.income_id
      where i.updated_at = m.original_updated_at
        and md5((
          (to_jsonb(i) || jsonb_build_object('status', m.expected_status_before_r1b)) - array[
            'status_before_quarantine','incident_type','incident_canonical_income_id',
            'incident_canonical_bill_id','incident_duplicate_bill_id','incident_quarantined_at',
            'incident_quarantined_by','incident_reason','cash_submission_blocked',
            'operational_excluded','tuition_bill_id'
          ]::text[]
        )::text) = m.expected_original_hash) <> 9 then
    raise exception 'R1B_UPDATED_AT_RESTORE_ACCEPTANCE_FAILED';
  end if;

  if exists (
    select 1 from pg_trigger
    where tgname in (
      'school_r0_tuition_income_mutation_guard',
      'school_incident_quarantined_income_immutable',
      'trg_school_income_records_updated_at'
    ) and tgenabled <> 'O'
  ) then
    raise exception 'R1B_UPDATED_AT_RESTORE_TRIGGER_REENABLE_FAILED';
  end if;
end;
$$;

select count(*) as restored_original_income_hashes
from r1b_original_income_timestamps m
join public.school_income_records i on i.id = m.income_id
where i.updated_at = m.original_updated_at;

\if :r1b_restore_commit
  commit;
\else
  rollback;
\endif
