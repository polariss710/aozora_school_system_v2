-- School V2 tuition P0 R1B: OLD/NEW deferred-consistency negative tests.
-- All business DML is rollback-only. No historical backfill or timestamp repair is executed.

\set ON_ERROR_STOP on

begin;
set constraints all immediate;

create temporary table r1b_consistency_test_results (
  test_name text primary key,
  rejected_by text not null
) on commit drop;

create temporary table r1b_consistency_baseline (
  object_name text primary key,
  row_count bigint not null,
  content_hash text not null
) on commit drop;

insert into r1b_consistency_baseline
select
  'identities',
  count(*),
  md5(coalesce(jsonb_agg(to_jsonb(identity_row) order by identity_row.id)::text, '[]'))
from public.school_student_tuition_billing_identities identity_row
union all
select
  'bill_lessons',
  count(*),
  md5(coalesce(jsonb_agg(to_jsonb(rel) order by rel.id)::text, '[]'))
from public.school_student_tuition_bill_lessons rel
union all
select
  'bills',
  count(*),
  md5(coalesce(jsonb_agg(to_jsonb(b) order by b.id)::text, '[]'))
from public.school_student_tuition_bills b
union all
select
  'incomes',
  count(*),
  md5(coalesce(jsonb_agg(to_jsonb(i) order by i.id)::text, '[]'))
from public.school_income_records i;

create temporary table r1b_identity_targets on commit drop as
select identity_row.*, row_number() over (order by identity_row.canonical_bill_id) as target_no
from public.school_student_tuition_billing_identities identity_row
join public.school_student_tuition_bills b
  on b.id = identity_row.canonical_bill_id
where b.billing_role = 'canonical_charge'
order by identity_row.canonical_bill_id
limit 2;

create temporary table r1b_identity_b_snapshot on commit drop as
select identity_row.*
from public.school_student_tuition_billing_identities identity_row
join r1b_identity_targets target on target.id = identity_row.id
where target.target_no = 2;

alter table public.school_student_tuition_bills
  disable trigger school_r0_tuition_bill_mutation_guard;
alter table public.school_income_records
  disable trigger school_r0_tuition_income_mutation_guard;
alter table public.school_student_tuition_billing_identities
  disable trigger school_tuition_billing_identities_immutable;
alter table public.school_student_tuition_bill_lessons
  disable trigger school_tuition_bill_lessons_immutable;

-- Free canonical bill B's unique identity inside this rollback transaction so
-- test 1 reaches the deferred trigger instead of the immediate unique index.
alter table public.school_student_tuition_billing_identities
  disable trigger school_tuition_identity_consistency;

delete from public.school_student_tuition_billing_identities identity_row
using r1b_identity_targets target
where target.target_no = 2
  and identity_row.id = target.id;

alter table public.school_student_tuition_billing_identities
  enable trigger school_tuition_identity_consistency;

do $$
declare
  v_identity_a_id uuid;
  v_bill_b_id uuid;
  v_student_b_id uuid;
  v_month_b text;
begin
  select id into strict v_identity_a_id
  from r1b_identity_targets where target_no = 1;
  select canonical_bill_id, student_id, billing_month
  into strict v_bill_b_id, v_student_b_id, v_month_b
  from r1b_identity_targets where target_no = 2;

  begin
    update public.school_student_tuition_billing_identities
    set canonical_bill_id = v_bill_b_id,
        student_id = v_student_b_id,
        billing_month = v_month_b
    where id = v_identity_a_id;
    raise exception 'EXPECTED_IDENTITY_A_TO_B_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_IDENTITY_MISMATCH:%' then raise; end if;
    insert into r1b_consistency_test_results values (
      '1_identity_canonical_bill_a_to_b',
      'TUITION_IDENTITY_MISMATCH'
    );
  end;
end;
$$;

alter table public.school_student_tuition_billing_identities
  disable trigger school_tuition_identity_consistency;

insert into public.school_student_tuition_billing_identities
select snapshot.* from r1b_identity_b_snapshot snapshot;

alter table public.school_student_tuition_billing_identities
  enable trigger school_tuition_identity_consistency;

do $$
declare
  v_lesson_id uuid;
  v_lesson_bill_b_id uuid;
  v_bill_a_id uuid;
  v_bill_b_id uuid;
  v_income_a_id uuid;
  v_other_income_id uuid;
  v_identity_id uuid;
begin
  select rel.id, candidate_bill.id
  into strict v_lesson_id, v_lesson_bill_b_id
  from public.school_student_tuition_bill_lessons rel
  join public.school_student_tuition_bills source_bill
    on source_bill.id = rel.tuition_bill_id
   and source_bill.billing_role = 'canonical_charge'
  join lateral (
    select target_bill.id
    from public.school_student_tuition_bills target_bill
    where target_bill.billing_role = 'canonical_charge'
      and target_bill.id <> rel.tuition_bill_id
      and not exists (
        select 1
        from public.school_student_tuition_bill_lessons target_rel
        where target_rel.tuition_bill_id = target_bill.id
          and target_rel.line_no = rel.line_no
      )
    order by target_bill.id
    limit 1
  ) candidate_bill on true
  where rel.relation_role = 'canonical_charge'
  order by rel.tuition_bill_id, rel.line_no
  limit 1;

  select b.id, b.income_record_id
  into strict v_bill_a_id, v_income_a_id
  from public.school_student_tuition_bills b
  where b.billing_role = 'canonical_charge'
  order by b.id
  limit 1;

  select b.id into strict v_bill_b_id
  from public.school_student_tuition_bills b
  where b.billing_role = 'canonical_charge'
    and b.id <> v_bill_a_id
  order by b.id
  limit 1;

  select i.id into strict v_other_income_id
  from public.school_income_records i
  where i.status <> 'incident_quarantined'
    and i.operational_excluded is not true
    and not exists (
      select 1
      from public.school_student_tuition_bills b
      where b.income_record_id = i.id
    )
  order by i.id
  limit 1;

  select identity_row.id into strict v_identity_id
  from public.school_student_tuition_billing_identities identity_row
  join public.school_student_tuition_bills b
    on b.id = identity_row.canonical_bill_id
   and b.billing_role = 'canonical_charge'
  order by identity_row.id
  limit 1;

  begin
    update public.school_student_tuition_bill_lessons
    set tuition_bill_id = v_lesson_bill_b_id
    where id = v_lesson_id;
    raise exception 'EXPECTED_BILL_LESSON_A_TO_B_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_BILL_LESSON_MISMATCH:%' then raise; end if;
    insert into r1b_consistency_test_results values (
      '2_bill_lesson_a_to_b',
      'TUITION_BILL_LESSON_MISMATCH'
    );
  end;

  begin
    update public.school_income_records
    set tuition_bill_id = null
    where id = v_income_a_id;
    raise exception 'EXPECTED_INCOME_TUITION_BILL_CLEAR_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_BILL_INCOME_MISMATCH:%' then raise; end if;
    insert into r1b_consistency_test_results values (
      '3_income_clear_tuition_bill_id',
      'TUITION_BILL_INCOME_MISMATCH'
    );
  end;

  begin
    update public.school_income_records
    set source_id = v_bill_b_id
    where id = v_income_a_id;
    raise exception 'EXPECTED_INCOME_SOURCE_TO_OTHER_BILL_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_BILL_INCOME_MISMATCH:%' then raise; end if;
    insert into r1b_consistency_test_results values (
      '4_income_source_to_other_bill',
      'TUITION_BILL_INCOME_MISMATCH'
    );
  end;

  begin
    update public.school_student_tuition_bills
    set income_record_id = v_other_income_id
    where id = v_bill_a_id;
    raise exception 'EXPECTED_BILL_INCOME_TO_OTHER_INCOME_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_BILL_INCOME_MISMATCH:%' then raise; end if;
    insert into r1b_consistency_test_results values (
      '5_bill_income_record_to_other_income',
      'TUITION_BILL_INCOME_MISMATCH'
    );
  end;

  begin
    delete from public.school_student_tuition_billing_identities
    where id = v_identity_id;
    raise exception 'EXPECTED_CANONICAL_IDENTITY_DELETE_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_IDENTITY_MISMATCH:%' then raise; end if;
    insert into r1b_consistency_test_results values (
      '6_delete_canonical_identity',
      'TUITION_IDENTITY_MISMATCH'
    );
  end;

  begin
    delete from public.school_student_tuition_bill_lessons
    where id = v_lesson_id;
    raise exception 'EXPECTED_CANONICAL_BILL_LESSON_DELETE_REJECTION_MISSING';
  exception when others then
    if sqlerrm not like 'TUITION_BILL_LESSON_MISMATCH:%' then raise; end if;
    insert into r1b_consistency_test_results values (
      '7_delete_canonical_bill_lesson',
      'TUITION_BILL_LESSON_MISMATCH'
    );
  end;
end;
$$;

alter table public.school_student_tuition_bill_lessons
  enable trigger school_tuition_bill_lessons_immutable;
alter table public.school_student_tuition_billing_identities
  enable trigger school_tuition_billing_identities_immutable;
alter table public.school_income_records
  enable trigger school_r0_tuition_income_mutation_guard;
alter table public.school_student_tuition_bills
  enable trigger school_r0_tuition_bill_mutation_guard;

do $$
declare
  v_rejected_count integer;
  v_residue_count integer;
begin
  select count(*)::integer into v_rejected_count
  from r1b_consistency_test_results;

  if v_rejected_count <> 7 then
    raise exception 'R1B_OLD_NEW_TEST_COUNT_MISMATCH: expected 7 rejections, got %.', v_rejected_count;
  end if;

  select count(*)::integer into v_residue_count
  from (
    select
      'identities' as object_name,
      count(*) as row_count,
      md5(coalesce(jsonb_agg(to_jsonb(identity_row) order by identity_row.id)::text, '[]')) as content_hash
    from public.school_student_tuition_billing_identities identity_row
    union all
    select
      'bill_lessons',
      count(*),
      md5(coalesce(jsonb_agg(to_jsonb(rel) order by rel.id)::text, '[]'))
    from public.school_student_tuition_bill_lessons rel
    union all
    select
      'bills',
      count(*),
      md5(coalesce(jsonb_agg(to_jsonb(b) order by b.id)::text, '[]'))
    from public.school_student_tuition_bills b
    union all
    select
      'incomes',
      count(*),
      md5(coalesce(jsonb_agg(to_jsonb(i) order by i.id)::text, '[]'))
    from public.school_income_records i
  ) current_state
  join r1b_consistency_baseline baseline using (object_name)
  where current_state.row_count is distinct from baseline.row_count
     or current_state.content_hash is distinct from baseline.content_hash;

  if v_residue_count <> 0 then
    raise exception 'R1B_OLD_NEW_TEST_RESIDUE: % business object groups changed before rollback.', v_residue_count;
  end if;
end;
$$;

select
  count(*) as rejected_test_count,
  array_agg(test_name order by test_name) as rejected_tests,
  0 as business_residue_count
from r1b_consistency_test_results;

rollback;
