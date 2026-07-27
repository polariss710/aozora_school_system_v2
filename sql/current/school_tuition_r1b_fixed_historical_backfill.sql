-- School V2 tuition P0 R1B: fixed historical backfill and Zhang Zhuowen incident quarantine.
-- Required psql variable: r1b_commit=0 for the mandatory rollback rehearsal,
-- or r1b_commit=1 for the reviewed formal execution. Both paths run this exact file.

\set ON_ERROR_STOP on

begin;

lock table public.school_feature_gates in access exclusive mode;
lock table public.school_student_tuition_bills in access exclusive mode;
lock table public.school_income_records in access exclusive mode;
lock table public.school_student_tuition_billing_identities in access exclusive mode;
lock table public.school_student_tuition_bill_lessons in access exclusive mode;
lock table public.school_personal_cash_income_linkage_events in access exclusive mode;
lock table public.school_account_transactions in access exclusive mode;
lock table public.school_lesson_records in access exclusive mode;

create temp table r1b_bill_manifest (
  bill_id uuid primary key,
  income_id uuid not null unique,
  expected_role text not null,
  expected_student_id uuid not null,
  expected_billing_month text not null,
  expected_bill_status text not null,
  expected_income_status text not null,
  expected_lesson_count integer not null,
  expected_source_snapshot_hash text not null,
  expected_bill_business_hash text not null,
  expected_income_business_hash text not null
) on commit drop;

insert into r1b_bill_manifest values
  ('2a9f1c25-a060-461e-ae10-b02295dec381', '468ab75b-312e-4ba0-8d8d-8ae2f6ace00e', 'canonical_charge',  'b17abc58-2f64-4bad-bf20-c9643ead60bc', '2026-07', 'income_created', 'received',  18, 'c17b651ad94f58c4f452658946ed4016', '530b606649ef912a9e098be6f7f8b807', '76e751b4c6f8855b502591b78286f66f'),
  ('fdf3cdfe-f715-4814-b500-9ff2bfe77a63', 'f86ac9db-effd-402e-a320-1e4b6846a9c7', 'canonical_charge',  '7aef8061-7037-4881-a847-a2cdb031c0f4', '2026-07', 'income_created', 'received',  24, '849987f1ac5927a3f8e6ee1ed19c7526', '65b7604c2c40a8a67e1ba3ce70e9fb97', '99d438fc9f4bcf2d2080584d6e3a0e28'),
  ('047dac2b-9484-4637-8e5e-9887857d121b', 'bbd7e7fd-fa04-404b-91fc-ab894cca28c8', 'incident_duplicate','7aef8061-7037-4881-a847-a2cdb031c0f4', '2026-07', 'income_created', 'pending',   24, 'c05f5a224ecb140a0603a7ecbb15707a', 'f513a994221f5958232c90d6e3c289f2', '883dccc58fd713a644ad7b5d9d200a91'),
  ('2a0948e0-9015-4b18-848c-8c397e0bc2a0', '09fa4398-9d20-494b-8ab5-8f7c3cafa414', 'canonical_charge',  'eb705aad-de4d-45e6-a391-42dcdd89aeda', '2026-07', 'income_created', 'received',   6, 'ac9b5e8049d85d3df4789636355cc079', '0bca9f6b2e3bfa44c9b78941a12c1b1a', 'e208d10927f40820ffd6bc08c57a3396'),
  ('07a02092-9503-47d1-9000-106f7e3de7e5', '91756564-c48d-4a1d-b6bc-88a041660e46', 'canonical_charge',  'a7b163a0-201e-4867-9b94-372343356a80', '2026-07', 'income_created', 'received',   1, '5e07406047473046ec7c9414a3595867', 'd487869ac28d36b47db05ad995f0e4f0', '1b17ab68571e0377f841670698cf8f06'),
  ('4109a4ec-1169-4d0b-965b-3e806b7e4c55', '474f0fd2-71ca-4cce-9ba5-e615bd390151', 'legacy_cancelled',  '881dd60c-b92b-44ae-98e1-98448567a8d2', '2026-07', 'cancelled',      'cancelled', 12, 'b9019f774239bc0bbbe55ebd6d24a29d', 'd6cfc3544a180f6ef653e913e06b39b8', '501e1612d4332ef60ec4ffeb14efa471'),
  ('2608806a-283a-4919-a851-b25962f2c0b2', '4a63f0ca-450f-4306-9e39-6d43172b3cf8', 'canonical_charge',  '881dd60c-b92b-44ae-98e1-98448567a8d2', '2026-07', 'income_created', 'received',  12, '2b46c73271af35c95bb6511b6e7013fa', 'a501e52e011fd50eba8b4e80b3518e46', '02559bbf6d7958f4a43c6f4b778b304b'),
  ('1b546782-1b39-4c73-a85d-27ab1e5086ad', 'cdf3da68-e578-4f1b-b759-2fff394e1906', 'canonical_charge',  '881dd60c-b92b-44ae-98e1-98448567a8d2', '2026-08', 'income_created', 'received',  12, 'b40348fe7d51f58fe3d84cbfc0c35d39', '27c3462d0c20e6290097e63518ed95f8', '18570150dc49316287523ea34d34b2a8'),
  ('7472f73f-fa19-4565-9180-a517c7151835', '3a5542c5-5397-4688-999e-a08bb678f40d', 'canonical_charge',  'eceb2c59-9689-4ec8-9d3f-799b90bfdb27', '2026-07', 'income_created', 'received',  12, '08edeee5a42b51714bb99e853c5b6f3a', '929fa6c029e89708fe03cffa0105e87c', 'a7222d442cdac4563e165b6848fc1e7b');

create temp table r1b_identity_manifest (
  identity_id uuid primary key,
  student_id uuid not null,
  billing_month text not null,
  canonical_bill_id uuid not null unique,
  creation_idempotency_key text not null unique
) on commit drop;

insert into r1b_identity_manifest values
  ('b1000000-0000-4000-8000-202607270001', 'b17abc58-2f64-4bad-bf20-c9643ead60bc', '2026-07', '2a9f1c25-a060-461e-ae10-b02295dec381', 'historical_backfill:student_tuition:b17abc58-2f64-4bad-bf20-c9643ead60bc:2026-07'),
  ('b1000000-0000-4000-8000-202607270002', '7aef8061-7037-4881-a847-a2cdb031c0f4', '2026-07', 'fdf3cdfe-f715-4814-b500-9ff2bfe77a63', 'historical_backfill:student_tuition:7aef8061-7037-4881-a847-a2cdb031c0f4:2026-07'),
  ('b1000000-0000-4000-8000-202607270003', 'eb705aad-de4d-45e6-a391-42dcdd89aeda', '2026-07', '2a0948e0-9015-4b18-848c-8c397e0bc2a0', 'historical_backfill:student_tuition:eb705aad-de4d-45e6-a391-42dcdd89aeda:2026-07'),
  ('b1000000-0000-4000-8000-202607270004', 'a7b163a0-201e-4867-9b94-372343356a80', '2026-07', '07a02092-9503-47d1-9000-106f7e3de7e5', 'historical_backfill:student_tuition:a7b163a0-201e-4867-9b94-372343356a80:2026-07'),
  ('b1000000-0000-4000-8000-202607270005', '881dd60c-b92b-44ae-98e1-98448567a8d2', '2026-07', '2608806a-283a-4919-a851-b25962f2c0b2', 'historical_backfill:student_tuition:881dd60c-b92b-44ae-98e1-98448567a8d2:2026-07'),
  ('b1000000-0000-4000-8000-202607270006', '881dd60c-b92b-44ae-98e1-98448567a8d2', '2026-08', '1b546782-1b39-4c73-a85d-27ab1e5086ad', 'historical_backfill:student_tuition:881dd60c-b92b-44ae-98e1-98448567a8d2:2026-08'),
  ('b1000000-0000-4000-8000-202607270007', 'eceb2c59-9689-4ec8-9d3f-799b90bfdb27', '2026-07', '7472f73f-fa19-4565-9180-a517c7151835', 'historical_backfill:student_tuition:eceb2c59-9689-4ec8-9d3f-799b90bfdb27:2026-07');

create temp table r1b_bill_income_manifest (
  bill_id uuid primary key,
  income_id uuid not null unique
) on commit drop;

insert into r1b_bill_income_manifest values
  ('2a9f1c25-a060-461e-ae10-b02295dec381', '468ab75b-312e-4ba0-8d8d-8ae2f6ace00e'),
  ('fdf3cdfe-f715-4814-b500-9ff2bfe77a63', 'f86ac9db-effd-402e-a320-1e4b6846a9c7'),
  ('047dac2b-9484-4637-8e5e-9887857d121b', 'bbd7e7fd-fa04-404b-91fc-ab894cca28c8'),
  ('2a0948e0-9015-4b18-848c-8c397e0bc2a0', '09fa4398-9d20-494b-8ab5-8f7c3cafa414'),
  ('07a02092-9503-47d1-9000-106f7e3de7e5', '91756564-c48d-4a1d-b6bc-88a041660e46'),
  ('4109a4ec-1169-4d0b-965b-3e806b7e4c55', '474f0fd2-71ca-4cce-9ba5-e615bd390151'),
  ('2608806a-283a-4919-a851-b25962f2c0b2', '4a63f0ca-450f-4306-9e39-6d43172b3cf8'),
  ('1b546782-1b39-4c73-a85d-27ab1e5086ad', 'cdf3da68-e578-4f1b-b759-2fff394e1906'),
  ('7472f73f-fa19-4565-9180-a517c7151835', '3a5542c5-5397-4688-999e-a08bb678f40d');

create temp table r1b_incident_manifest (
  incident_income_id uuid primary key,
  canonical_income_id uuid not null,
  canonical_bill_id uuid not null,
  duplicate_bill_id uuid not null unique,
  status_before_quarantine text not null,
  incident_type text not null,
  quarantined_by text not null,
  incident_reason text not null
) on commit drop;

insert into r1b_incident_manifest values (
  'bbd7e7fd-fa04-404b-91fc-ab894cca28c8',
  'f86ac9db-effd-402e-a320-1e4b6846a9c7',
  'fdf3cdfe-f715-4814-b500-9ff2bfe77a63',
  '047dac2b-9484-4637-8e5e-9887857d121b',
  'pending',
  'duplicate_tuition_charge',
  'codex-r1b-authorized-backfill-20260727',
  'R1B fixed-ID quarantine: duplicate pending tuition income for the same 24 planned lessons already owned by canonical bill fdf3cdfe-f715-4814-b500-9ff2bfe77a63.'
);

create temp table r1b_lesson_manifest on commit drop as
select
  (
    substr(md5(m.bill_id::text || ':' || lesson.planned_lesson_id || ':r1b'), 1, 8) || '-' ||
    substr(md5(m.bill_id::text || ':' || lesson.planned_lesson_id || ':r1b'), 9, 4) || '-' ||
    substr(md5(m.bill_id::text || ':' || lesson.planned_lesson_id || ':r1b'), 13, 4) || '-' ||
    substr(md5(m.bill_id::text || ':' || lesson.planned_lesson_id || ':r1b'), 17, 4) || '-' ||
    substr(md5(m.bill_id::text || ':' || lesson.planned_lesson_id || ':r1b'), 21, 12)
  )::uuid as relationship_id,
  m.bill_id as tuition_bill_id,
  lesson.planned_lesson_id::uuid as planned_lesson_id,
  m.expected_role as relation_role,
  lesson.line_no::integer as line_no,
  b.student_id as student_id_snapshot,
  b.business_entity_id as business_entity_id_snapshot,
  b.billing_month as billing_month_snapshot,
  null::date as week_start_date_snapshot,
  null::date as scheduled_lesson_date_snapshot,
  l.teacher_id as teacher_id_snapshot,
  l.subject_id as subject_id_snapshot,
  coalesce(l.lesson_count, 1) as lesson_count_snapshot,
  l.duration_hours as duration_hours_snapshot,
  coalesce(l.unit_price, 0) as unit_price_jpy_snapshot,
  coalesce(l.lesson_fee, 0) as lesson_fee_jpy_snapshot,
  l.updated_at as source_lesson_updated_at,
  jsonb_build_object(
    'bill_json_planned_lesson_id', lesson.planned_lesson_id::uuid,
    'bill_json_line_no', lesson.line_no::integer,
    'current_planned_lesson', to_jsonb(l),
    'relationship_identity_confidence', 'high',
    'current_source_field_confidence', 'medium',
    'bill_aggregate_verified', true,
    'historical_schedule_dates_available', false,
    'scheduled_date_policy', 'leave_null_do_not_use_actual_date'
  ) as source_snapshot,
  'medium'::text as attribution_confidence,
  'bill_json_exact_id_plus_current_source_fields_aggregate_verified'::text as snapshot_source,
  'b1000000-0000-4000-8000-202607279999'::uuid as backfill_batch_id
from r1b_bill_manifest m
join public.school_student_tuition_bills b on b.id = m.bill_id
cross join lateral jsonb_array_elements_text(
  coalesce(b.source_snapshot -> 'planned_lesson_ids', '[]'::jsonb)
) with ordinality lesson(planned_lesson_id, line_no)
left join public.school_lesson_records l on l.id = lesson.planned_lesson_id::uuid;

do $$
declare
  v_hash text;
  v_count integer;
begin
  if (select count(*) from r1b_bill_manifest) <> 9
     or (select count(*) from r1b_identity_manifest) <> 7
     or (select count(*) from r1b_bill_income_manifest) <> 9
     or (select count(*) from r1b_incident_manifest) <> 1
     or (select count(*) from r1b_lesson_manifest) <> 121 then
    raise exception 'R1B_MANIFEST_COUNT_MISMATCH';
  end if;

  if (select count(*) from r1b_bill_manifest where expected_role = 'canonical_charge') <> 7
     or (select count(*) from r1b_bill_manifest where expected_role = 'incident_duplicate') <> 1
     or (select count(*) from r1b_bill_manifest where expected_role = 'legacy_cancelled') <> 1
     or (select count(*) from r1b_lesson_manifest where relation_role = 'canonical_charge') <> 85
     or (select count(*) from r1b_lesson_manifest where relation_role = 'incident_duplicate') <> 24
     or (select count(*) from r1b_lesson_manifest where relation_role = 'legacy_cancelled') <> 12 then
    raise exception 'R1B_MANIFEST_ROLE_COUNT_MISMATCH';
  end if;

  if exists (
    select 1
    from public.school_feature_gates
    where (feature_key = 'student_tuition_preview' and state <> 'validation_preview_only')
       or (feature_key in ('student_tuition_generate', 'student_tuition_cash_submit') and state <> 'blocked')
       or release_version <> 'r0-20260727'
  ) or (select count(*) from public.school_feature_gates) <> 3 then
    raise exception 'R1B_R0_GATE_PRECONDITION_FAILED';
  end if;

  if (select count(*) from public.school_student_tuition_billing_identities) <> 0
     or (select count(*) from public.school_student_tuition_bill_lessons) <> 0
     or (select count(*) from public.school_student_tuition_bills where billing_role is not null) <> 0
     or (select count(*) from public.school_income_records where tuition_bill_id is not null) <> 0
     or (select count(*) from public.school_income_records where status = 'incident_quarantined') <> 0 then
    raise exception 'R1B_EMPTY_BACKFILL_PRECONDITION_FAILED';
  end if;

  if (select count(*) from public.school_income_records) <> 42
     or (select count(*) from public.school_student_tuition_bills) <> 9
     or (select count(*) from public.school_lesson_records) <> 625
     or (select count(*) from public.school_account_transactions) <> 185
     or (select count(*) from public.school_personal_cash_income_linkage_events) <> 35 then
    raise exception 'R1B_BUSINESS_ROW_COUNT_PRECONDITION_FAILED';
  end if;

  select md5(coalesce(string_agg(md5((to_jsonb(t) - array[
    'status_before_quarantine','incident_type','incident_canonical_income_id',
    'incident_canonical_bill_id','incident_duplicate_bill_id','incident_quarantined_at',
    'incident_quarantined_by','incident_reason','cash_submission_blocked',
    'operational_excluded','tuition_bill_id'
  ]::text[])::text), '' order by id::text), '')) into v_hash
  from public.school_income_records t;
  if v_hash <> 'b00238c330e8ab5ef7a51eb2fd281d4f' then
    raise exception 'R1B_INCOME_BASELINE_HASH_MISMATCH: %', v_hash;
  end if;

  select md5(coalesce(string_agg(md5((to_jsonb(t) - array[
    'billing_role','incident_locked_at','incident_reason','cash_submission_blocked'
  ]::text[])::text), '' order by id::text), '')) into v_hash
  from public.school_student_tuition_bills t;
  if v_hash <> '9ee93472fdac490897b8b837b174bbaa' then
    raise exception 'R1B_BILL_BASELINE_HASH_MISMATCH: %', v_hash;
  end if;

  select count(*)::integer into v_count
  from r1b_bill_manifest m
  join public.school_student_tuition_bills b on b.id = m.bill_id
  join public.school_income_records i on i.id = m.income_id
  where b.student_id = m.expected_student_id
    and b.billing_month = m.expected_billing_month
    and b.status = m.expected_bill_status
    and i.status = m.expected_income_status
    and b.income_record_id = i.id
    and i.source_type = 'student_tuition_bill'
    and i.source_id = b.id
    and jsonb_array_length(coalesce(b.source_snapshot -> 'planned_lesson_ids', '[]'::jsonb)) = m.expected_lesson_count
    and md5(b.source_snapshot::text) = m.expected_source_snapshot_hash
    and md5((to_jsonb(b) - array['billing_role','incident_locked_at','incident_reason','cash_submission_blocked'])::text) = m.expected_bill_business_hash
    and md5((to_jsonb(i) - array[
      'status_before_quarantine','incident_type','incident_canonical_income_id',
      'incident_canonical_bill_id','incident_duplicate_bill_id','incident_quarantined_at',
      'incident_quarantined_by','incident_reason','cash_submission_blocked',
      'operational_excluded','tuition_bill_id'
    ])::text) = m.expected_income_business_hash;
  if v_count <> 9 then
    raise exception 'R1B_FIXED_TARGET_HASH_OR_MAPPING_MISMATCH: matched % of 9.', v_count;
  end if;

  if exists (select 1 from r1b_lesson_manifest where duration_hours_snapshot is null)
     or exists (
       select planned_lesson_id from r1b_lesson_manifest
       where relation_role = 'canonical_charge'
       group by planned_lesson_id having count(*) > 1
     )
     or exists (
       select 1 from r1b_lesson_manifest rel
       where rel.relation_role in ('incident_duplicate', 'legacy_cancelled')
         and not exists (
           select 1 from r1b_lesson_manifest canonical
           where canonical.planned_lesson_id = rel.planned_lesson_id
             and canonical.relation_role = 'canonical_charge'
         )
     )
     or exists (
       select 1
       from (
         select tuition_bill_id, count(*) count_rows,
                sum(duration_hours_snapshot) hours,
                sum(lesson_fee_jpy_snapshot) fee
         from r1b_lesson_manifest group by tuition_bill_id
       ) aggregate_row
       join public.school_student_tuition_bills b on b.id = aggregate_row.tuition_bill_id
       where aggregate_row.count_rows <> b.planned_lesson_count
          or aggregate_row.hours <> b.planned_lesson_hours
          or aggregate_row.fee <> b.planned_lesson_fee_jpy
          or aggregate_row.fee <> b.bill_amount_jpy
     ) then
    raise exception 'R1B_LESSON_MANIFEST_VALIDATION_FAILED';
  end if;

  if (select count(*) from r1b_bill_manifest m where m.expected_role = 'canonical_charge' and exists (
    select 1 from public.school_personal_cash_income_linkage_events e
    where e.income_record_id = m.income_id
      and e.source_table = 'school_income_records'
      and e.sync_status = 'synced'
      and e.cash_request_status = 'approved'
      and e.cash_transaction_id is not null
  )) <> 7 then
    raise exception 'R1B_CANONICAL_CASH_EVIDENCE_MISMATCH';
  end if;

  if exists (
    select 1 from public.school_personal_cash_income_linkage_events e
    where e.income_record_id = 'bbd7e7fd-fa04-404b-91fc-ab894cca28c8'
  ) or exists (
    select 1 from public.school_account_transactions t
    where t.related_table = 'school_income_records'
      and t.related_id = 'bbd7e7fd-fa04-404b-91fc-ab894cca28c8'
  ) then
    raise exception 'R1B_INCIDENT_ALREADY_HAS_DOWNSTREAM_ACTIVITY';
  end if;

  select md5(coalesce(string_agg(md5(to_jsonb(rel)::text), '' order by tuition_bill_id::text, line_no), ''))
  into v_hash from r1b_lesson_manifest rel;
  if v_hash <> '9b05ec18c7d6e4b2574591edae6b5709' then
    raise exception 'R1B_LESSON_MANIFEST_HASH_MISMATCH: %', v_hash;
  end if;
  raise notice 'R1B_LESSON_MANIFEST_HASH=%', v_hash;

  select md5(coalesce(string_agg(md5(to_jsonb(identity_row)::text), '' order by identity_id::text), ''))
  into v_hash from r1b_identity_manifest identity_row;
  if v_hash <> 'a5a4d8665f7c0d2d794756f37934175e' then
    raise exception 'R1B_IDENTITY_MANIFEST_HASH_MISMATCH: %', v_hash;
  end if;
  raise notice 'R1B_IDENTITY_MANIFEST_HASH=%', v_hash;
end;
$$;

alter table public.school_student_tuition_bills
  disable trigger school_r0_tuition_bill_mutation_guard;
alter table public.school_income_records
  disable trigger school_r0_tuition_income_mutation_guard;
alter table public.school_income_records
  disable trigger trg_school_income_records_updated_at;

update public.school_student_tuition_bills b
set
  billing_role = m.expected_role,
  incident_locked_at = case
    when m.expected_role in ('incident_duplicate', 'legacy_cancelled') then statement_timestamp()
    else null
  end,
  incident_reason = case m.expected_role
    when 'incident_duplicate' then 'R1B fixed-ID incident isolation: duplicate pending tuition bill; canonical bill fdf3cdfe-f715-4814-b500-9ff2bfe77a63 owns the same 24 planned lessons.'
    when 'legacy_cancelled' then 'R1B fixed-ID legacy classification: cancelled historical tuition bill retained unchanged; canonical bill 2608806a-283a-4919-a851-b25962f2c0b2 owns the same 12 planned lessons.'
    else null
  end,
  cash_submission_blocked = m.expected_role in ('incident_duplicate', 'legacy_cancelled')
from r1b_bill_manifest m
where b.id = m.bill_id;

insert into public.school_student_tuition_billing_identities (
  id, student_id, billing_month, canonical_bill_id,
  creation_idempotency_key, source, created_at, created_by, evidence
)
select
  identity_row.identity_id,
  identity_row.student_id,
  identity_row.billing_month,
  identity_row.canonical_bill_id,
  identity_row.creation_idempotency_key,
  'historical_backfill',
  statement_timestamp(),
  'codex-r1b-authorized-backfill-20260727',
  jsonb_build_object(
    'phase', 'R1B',
    'manifest', 'fixed-reviewed-9-bill-r1a-baseline',
    'bill_id', identity_row.canonical_bill_id,
    'income_id', bill_manifest.income_id,
    'classification_basis', 'received income + synced School linkage + approved Cash request + Cash transaction',
    'cash_linkage_id', linkage.id,
    'cash_request_id', linkage.cash_request_id,
    'cash_transaction_id', linkage.cash_transaction_id
  )
from r1b_identity_manifest identity_row
join r1b_bill_manifest bill_manifest on bill_manifest.bill_id = identity_row.canonical_bill_id
left join lateral (
  select e.id, e.cash_request_id, e.cash_transaction_id
  from public.school_personal_cash_income_linkage_events e
  where e.income_record_id = bill_manifest.income_id
    and e.source_table = 'school_income_records'
    and e.sync_status = 'synced'
    and e.cash_request_status = 'approved'
    and e.cash_transaction_id is not null
  order by e.attempt_no desc, e.created_at desc, e.id desc
  limit 1
) linkage on true;

insert into public.school_student_tuition_bill_lessons (
  id, tuition_bill_id, planned_lesson_id, relation_role, line_no,
  student_id_snapshot, business_entity_id_snapshot, billing_month_snapshot,
  week_start_date_snapshot, scheduled_lesson_date_snapshot,
  teacher_id_snapshot, subject_id_snapshot, lesson_count_snapshot,
  duration_hours_snapshot, unit_price_jpy_snapshot, lesson_fee_jpy_snapshot,
  source_lesson_updated_at, source_snapshot, attribution_confidence,
  snapshot_source, backfill_batch_id, created_at, created_by
)
select
  rel.relationship_id, rel.tuition_bill_id, rel.planned_lesson_id,
  rel.relation_role, rel.line_no, rel.student_id_snapshot,
  rel.business_entity_id_snapshot, rel.billing_month_snapshot,
  rel.week_start_date_snapshot, rel.scheduled_lesson_date_snapshot,
  rel.teacher_id_snapshot, rel.subject_id_snapshot, rel.lesson_count_snapshot,
  rel.duration_hours_snapshot, rel.unit_price_jpy_snapshot,
  rel.lesson_fee_jpy_snapshot, rel.source_lesson_updated_at,
  rel.source_snapshot, rel.attribution_confidence, rel.snapshot_source,
  rel.backfill_batch_id, statement_timestamp(),
  'codex-r1b-authorized-backfill-20260727'
from r1b_lesson_manifest rel
order by rel.tuition_bill_id, rel.line_no;

update public.school_income_records i
set
  tuition_bill_id = pair.bill_id,
  status_before_quarantine = incident.status_before_quarantine,
  status = case when incident.incident_income_id is not null then 'incident_quarantined' else i.status end,
  incident_type = incident.incident_type,
  incident_canonical_income_id = incident.canonical_income_id,
  incident_canonical_bill_id = incident.canonical_bill_id,
  incident_duplicate_bill_id = incident.duplicate_bill_id,
  incident_quarantined_at = case when incident.incident_income_id is not null then statement_timestamp() else null end,
  incident_quarantined_by = incident.quarantined_by,
  incident_reason = incident.incident_reason,
  cash_submission_blocked = incident.incident_income_id is not null,
  operational_excluded = incident.incident_income_id is not null
from r1b_bill_income_manifest pair
left join r1b_incident_manifest incident on incident.incident_income_id = pair.income_id
where i.id = pair.income_id;

set constraints all immediate;

alter table public.school_income_records
  enable trigger trg_school_income_records_updated_at;
alter table public.school_income_records
  enable trigger school_r0_tuition_income_mutation_guard;
alter table public.school_student_tuition_bills
  enable trigger school_r0_tuition_bill_mutation_guard;

do $$
begin
  if (select count(*) from public.school_student_tuition_bills where billing_role = 'canonical_charge') <> 7
     or (select count(*) from public.school_student_tuition_bills where billing_role = 'incident_duplicate') <> 1
     or (select count(*) from public.school_student_tuition_bills where billing_role = 'legacy_cancelled') <> 1
     or (select count(*) from public.school_student_tuition_bills where billing_role is null) <> 0
     or (select count(*) from public.school_student_tuition_billing_identities) <> 7
     or (select count(*) from public.school_student_tuition_bill_lessons where relation_role = 'canonical_charge') <> 85
     or (select count(*) from public.school_student_tuition_bill_lessons where relation_role = 'incident_duplicate') <> 24
     or (select count(*) from public.school_student_tuition_bill_lessons where relation_role = 'legacy_cancelled') <> 12
     or (select count(*) from public.school_student_tuition_bill_lessons) <> 121
     or (select count(*) from public.school_income_records where tuition_bill_id is not null) <> 9
     or (select count(*) from public.school_income_records where status = 'incident_quarantined') <> 1 then
    raise exception 'R1B_TRANSACTION_ACCEPTANCE_COUNT_FAILED';
  end if;

  if exists (
    select 1
    from r1b_bill_income_manifest pair
    join public.school_student_tuition_bills b on b.id = pair.bill_id
    join public.school_income_records i on i.id = pair.income_id
    where b.income_record_id is distinct from i.id
       or i.source_type is distinct from 'student_tuition_bill'
       or i.source_id is distinct from b.id
       or i.tuition_bill_id is distinct from b.id
  ) then
    raise exception 'R1B_TRANSACTION_ACCEPTANCE_1TO1_FAILED';
  end if;

  if exists (
    select 1 from pg_trigger
    where tgname in (
      'school_r0_tuition_bill_mutation_guard',
      'school_r0_tuition_income_mutation_guard',
      'school_r0_tuition_cash_linkage_mutation_guard'
    ) and tgenabled <> 'O'
  ) or (select count(*) from pg_trigger where tgname in (
    'school_r0_tuition_bill_mutation_guard',
    'school_r0_tuition_income_mutation_guard',
    'school_r0_tuition_cash_linkage_mutation_guard'
  ) and tgenabled = 'O') <> 3 then
    raise exception 'R1B_R0_TRIGGER_REENABLE_FAILED';
  end if;

  if exists (
    select 1 from public.school_operational_income_records
    where id = 'bbd7e7fd-fa04-404b-91fc-ab894cca28c8'
  ) or not exists (
    select 1 from public.school_incident_income_records
    where id = 'bbd7e7fd-fa04-404b-91fc-ab894cca28c8'
  ) then
    raise exception 'R1B_INCIDENT_VIEW_ISOLATION_FAILED';
  end if;
end;
$$;

select
  (select count(*) from public.school_student_tuition_billing_identities) as identity_count,
  (select count(*) from public.school_student_tuition_bill_lessons) as relationship_count,
  (select count(*) from public.school_income_records where tuition_bill_id is not null) as reverse_pair_count,
  (select count(*) from public.school_income_records where status = 'incident_quarantined') as incident_count;

\if :r1b_commit
  commit;
\else
  rollback;
  select
    (select count(*) from public.school_student_tuition_billing_identities) as identity_count_after_rollback,
    (select count(*) from public.school_student_tuition_bill_lessons) as relationship_count_after_rollback,
    (select count(*) from public.school_student_tuition_bills where billing_role is not null) as classified_bill_count_after_rollback,
    (select count(*) from public.school_income_records where tuition_bill_id is not null) as reverse_pair_count_after_rollback,
    (select count(*) from public.school_income_records where status = 'incident_quarantined') as incident_count_after_rollback;
\endif
