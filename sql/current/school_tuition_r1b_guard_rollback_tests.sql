-- School V2 tuition P0 R1B negative guard tests. Every probe is rolled back.

\set ON_ERROR_STOP on

begin;
set constraints all immediate;

alter table public.school_student_tuition_bills
  disable trigger school_r0_tuition_bill_mutation_guard;
alter table public.school_income_records
  disable trigger school_r0_tuition_income_mutation_guard;

do $$
begin
  begin
    update public.school_income_records
    set note = note
    where id = 'bbd7e7fd-fa04-404b-91fc-ab894cca28c8';
    raise exception 'EXPECTED_INCIDENT_INCOME_UPDATE_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_INCIDENT_IMMUTABLE:%' then raise; end if;
  end;

  begin
    delete from public.school_income_records
    where id = 'bbd7e7fd-fa04-404b-91fc-ab894cca28c8';
    raise exception 'EXPECTED_INCIDENT_INCOME_DELETE_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_INCIDENT_IMMUTABLE:%' then raise; end if;
  end;

  begin
    update public.school_student_tuition_bills
    set note = note
    where id = '047dac2b-9484-4637-8e5e-9887857d121b';
    raise exception 'EXPECTED_INCIDENT_BILL_UPDATE_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_INCIDENT_BILL_IMMUTABLE:%' then raise; end if;
  end;

  begin
    delete from public.school_student_tuition_bills
    where id = '047dac2b-9484-4637-8e5e-9887857d121b';
    raise exception 'EXPECTED_INCIDENT_BILL_DELETE_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_INCIDENT_BILL_IMMUTABLE:%' then raise; end if;
  end;

  begin
    insert into public.school_student_tuition_billing_identities (
      id, student_id, billing_month, canonical_bill_id,
      creation_idempotency_key, source, created_by, evidence
    ) values (
      'b1000000-0000-4000-8000-202607279901',
      '7aef8061-7037-4881-a847-a2cdb031c0f4',
      '2026-08',
      '4109a4ec-1169-4d0b-965b-3e806b7e4c55',
      'codex-test:r1b:identity-mismatch',
      'historical_backfill',
      'codex-test-r1b-rollback',
      '{"test":"identity mismatch rejection"}'::jsonb
    );
    raise exception 'EXPECTED_IDENTITY_MISMATCH_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_IDENTITY_MISMATCH:%' then raise; end if;
  end;

  begin
    insert into public.school_student_tuition_bill_lessons
    select
      'b1000000-0000-4000-8000-202607279902'::uuid,
      rel.tuition_bill_id,
      rel.planned_lesson_id,
      rel.relation_role,
      rel.line_no + 1000,
      rel.student_id_snapshot,
      rel.business_entity_id_snapshot,
      rel.billing_month_snapshot,
      rel.week_start_date_snapshot,
      rel.scheduled_lesson_date_snapshot,
      rel.teacher_id_snapshot,
      rel.subject_id_snapshot,
      rel.lesson_count_snapshot,
      rel.duration_hours_snapshot,
      rel.unit_price_jpy_snapshot,
      rel.lesson_fee_jpy_snapshot,
      rel.source_lesson_updated_at,
      rel.source_snapshot,
      rel.attribution_confidence,
      rel.snapshot_source,
      rel.backfill_batch_id,
      statement_timestamp(),
      'codex-test-r1b-rollback'
    from public.school_student_tuition_bill_lessons rel
    where rel.relation_role = 'canonical_charge'
    order by rel.tuition_bill_id, rel.line_no
    limit 1;
    raise exception 'EXPECTED_CANONICAL_DUPLICATE_REJECTION_MISSING';
  exception when unique_violation then
    null;
  end;

  begin
    insert into public.school_student_tuition_bill_lessons
    select (jsonb_populate_record(
      null::public.school_student_tuition_bill_lessons,
      to_jsonb(rel) || jsonb_build_object(
        'id', 'b1000000-0000-4000-8000-202607279905',
        'planned_lesson_id', candidate.id,
        'line_no', 1001,
        'created_by', 'codex-test-r1b-rollback'
      )
    )).*
    from public.school_student_tuition_bill_lessons rel
    cross join lateral (
      select l.id from public.school_lesson_records l
      where not exists (
        select 1 from public.school_student_tuition_bill_lessons canonical
        where canonical.planned_lesson_id = l.id
          and canonical.relation_role = 'canonical_charge'
      )
      order by l.id limit 1
    ) candidate
    where rel.relation_role = 'incident_duplicate'
    order by rel.line_no limit 1;
    raise exception 'EXPECTED_INCIDENT_WITHOUT_CANONICAL_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_NONCANONICAL_LESSON_WITHOUT_CANONICAL:%' then raise; end if;
  end;

  begin
    insert into public.school_student_tuition_bill_lessons
    select (jsonb_populate_record(
      null::public.school_student_tuition_bill_lessons,
      to_jsonb(rel) || jsonb_build_object(
        'id', 'b1000000-0000-4000-8000-202607279906',
        'planned_lesson_id', candidate.id,
        'line_no', 1002,
        'created_by', 'codex-test-r1b-rollback'
      )
    )).*
    from public.school_student_tuition_bill_lessons rel
    cross join lateral (
      select l.id from public.school_lesson_records l
      where not exists (
        select 1 from public.school_student_tuition_bill_lessons canonical
        where canonical.planned_lesson_id = l.id
          and canonical.relation_role = 'canonical_charge'
      )
      order by l.id limit 1
    ) candidate
    where rel.relation_role = 'legacy_cancelled'
    order by rel.line_no limit 1;
    raise exception 'EXPECTED_LEGACY_WITHOUT_CANONICAL_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_NONCANONICAL_LESSON_WITHOUT_CANONICAL:%' then raise; end if;
  end;

  begin
    update public.school_income_records
    set source_id = '07a02092-9503-47d1-9000-106f7e3de7e5'
    where id = '468ab75b-312e-4ba0-8d8d-8ae2f6ace00e';
    raise exception 'EXPECTED_BILL_INCOME_MISMATCH_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_BILL_INCOME_MISMATCH:%' then raise; end if;
  end;

  begin
    insert into public.school_personal_cash_income_linkage_events
    select (jsonb_populate_record(
      null::public.school_personal_cash_income_linkage_events,
      to_jsonb(e) || jsonb_build_object(
        'id', 'b1000000-0000-4000-8000-202607279903',
        'income_record_id', 'bbd7e7fd-fa04-404b-91fc-ab894cca28c8',
        'source_id', 'bbd7e7fd-fa04-404b-91fc-ab894cca28c8',
        'idempotency_key', 'codex-test:r1b:incident-cash-linkage'
      )
    )).* from public.school_personal_cash_income_linkage_events e limit 1;
    raise exception 'EXPECTED_INCIDENT_CASH_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_INCIDENT_DOWNSTREAM_BLOCKED:%' then raise; end if;
  end;

  begin
    insert into public.school_account_transactions
    select (jsonb_populate_record(
      null::public.school_account_transactions,
      to_jsonb(t) || jsonb_build_object(
        'id', 'b1000000-0000-4000-8000-202607279904',
        'related_table', 'school_income_records',
        'related_id', 'bbd7e7fd-fa04-404b-91fc-ab894cca28c8'
      )
    )).* from public.school_account_transactions t limit 1;
    raise exception 'EXPECTED_INCIDENT_ACCOUNT_TRANSACTION_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_INCIDENT_DOWNSTREAM_BLOCKED:%' then raise; end if;
  end;
end;
$$;

alter table public.school_personal_cash_income_linkage_events
  disable trigger school_incident_income_cash_linkage_guard;

do $$
begin
  begin
    insert into public.school_personal_cash_income_linkage_events
    select (jsonb_populate_record(
      null::public.school_personal_cash_income_linkage_events,
      to_jsonb(e) || jsonb_build_object(
        'id', 'b1000000-0000-4000-8000-202607279907',
        'income_record_id', 'bbd7e7fd-fa04-404b-91fc-ab894cca28c8',
        'source_id', 'bbd7e7fd-fa04-404b-91fc-ab894cca28c8',
        'idempotency_key', 'codex-test:r1b:r0-cash-linkage'
      )
    )).* from public.school_personal_cash_income_linkage_events e limit 1;
    raise exception 'EXPECTED_R0_TUITION_CASH_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_CASH_SUBMISSION_BLOCKED:%' then raise; end if;
  end;
end;
$$;

alter table public.school_personal_cash_income_linkage_events
  enable trigger school_incident_income_cash_linkage_guard;

alter table public.school_income_records
  enable trigger school_r0_tuition_income_mutation_guard;
alter table public.school_student_tuition_bills
  enable trigger school_r0_tuition_bill_mutation_guard;

select 'all_r1b_negative_guards_rejected_as_expected' as result;

rollback;
