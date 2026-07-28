-- School V2 tuition P0 R1D-C-A evidence inventory.
-- Strictly SELECT/DO-only. No DDL, DML, temporary objects, write RPCs, or gates.
\set ON_ERROR_STOP on
\pset pager off

begin transaction isolation level repeatable read read only;

select clock_timestamp() as school_evidence_started_at,
       current_setting('transaction_isolation') as transaction_isolation,
       current_setting('transaction_read_only') as transaction_read_only;

-- Fail closed on the R1D-B/R1C authority baseline before producing manifests.
do $audit$
declare
  v_count bigint;
  v_hash text;
begin
  if (select count(*) from public.school_lesson_records) <> 626
     or (select count(*) from public.school_lesson_records where lesson_type = 'planned') <> 397
     or (select count(*) from public.school_lesson_records where lesson_type = 'actual') <> 229 then
    raise exception 'R1D_C_A_LESSON_COUNT_BASELINE_CHANGED';
  end if;

  if exists (
    select 1 from public.school_lesson_records lesson
    where lesson.billing_month is not null
       or lesson.billing_week_start_date is not null
       or lesson.scheduled_lesson_date is not null
       or lesson.student_settlement_month is not null
       or lesson.billing_month_source is not null
       or lesson.billing_month_decided_at is not null
  ) then
    raise exception 'R1D_C_A_NEW_FIELDS_NOT_EMPTY';
  end if;

  if (select count(*) from public.school_tuition_billing_attribution_override_audit) <> 0 then
    raise exception 'R1D_C_A_OVERRIDE_AUDIT_NOT_EMPTY';
  end if;

  select count(*), md5(coalesce(string_agg(md5((to_jsonb(lesson)
      - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
      - 'student_settlement_month' - 'billing_month_source'
      - 'billing_month_decided_at')::text), '' order by lesson.id::text), ''))
    into v_count, v_hash
  from public.school_lesson_records lesson;
  if v_count <> 626 or v_hash <> '4fb1901c888d56cb29c05e387490ca75' then
    raise exception 'R1D_C_A_OLD31_BASELINE_CHANGED: %/%', v_count, v_hash;
  end if;

  if (select count(*) from public.school_student_tuition_bills) <> 9
     or (select count(*) from public.school_income_records) <> 42
     or (select count(*) from public.school_student_tuition_billing_identities) <> 7
     or (select count(*) from public.school_student_tuition_bill_lessons) <> 121
     or (select count(*) from public.school_business_entity_migration_batches) <> 2
     or (select count(*) from public.school_business_entity_migration_items) <> 118 then
    raise exception 'R1D_C_A_TUITION_OR_MIGRATION_COUNT_BASELINE_CHANGED';
  end if;

  if (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), ''))
      from public.school_business_entity_migration_batches row_value)
       <> '18e74c21ebf95fdf80bed6767a4e28be'
     or (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), ''))
         from public.school_business_entity_migration_items row_value)
       <> '23a2f93d0db01d84ba6195573ec58790' then
    raise exception 'R1D_C_A_MIGRATION_AUDIT_HASH_CHANGED';
  end if;

  if (select count(*) from public.school_student_tuition_bills bill
      join public.school_income_records income
        on income.id = bill.income_record_id
       and income.tuition_bill_id = bill.id
       and income.source_type = 'student_tuition_bill'
       and income.source_id = bill.id) <> 9 then
    raise exception 'R1D_C_A_BILL_INCOME_PAIR_CHANGED';
  end if;

  if exists (
    select 1
    from public.school_business_entity_migration_items item
    left join public.school_lesson_records lesson on lesson.id = item.lesson_record_id
    where item.batch_id in (
      'c1000000-0000-4000-8000-202607279999',
      'c1000000-0000-4000-8000-202607289999'
    )
      and (lesson.id is null
        or (to_jsonb(lesson)
          - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
          - 'student_settlement_month' - 'billing_month_source'
          - 'billing_month_decided_at') is distinct from item.after_row_snapshot
        or lesson.updated_at is distinct from item.original_updated_at)
  ) then
    raise exception 'R1D_C_A_FIXED_118_DRIFTED';
  end if;

  if exists (
    select 1 from public.school_feature_gates
    where (feature_key = 'student_tuition_preview' and state <> 'validation_preview_only')
       or (feature_key in ('student_tuition_generate','student_tuition_cash_submit') and state <> 'blocked')
  ) or (select count(*) from public.school_feature_gates) <> 3 then
    raise exception 'R1D_C_A_R0_GATE_CHANGED';
  end if;
end;
$audit$;

-- R1D-B physical columns and all current DB functions that can write lesson rows.
select ordinal_position, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'school_lesson_records'
order by ordinal_position;

select procedure.oid::regprocedure as writer_signature,
       md5(pg_get_functiondef(procedure.oid)) as function_definition_md5
from pg_proc procedure
join pg_namespace namespace on namespace.oid=procedure.pronamespace
where namespace.nspname='public'
  and pg_get_functiondef(procedure.oid) ilike '%school_lesson_records%'
  and pg_get_functiondef(procedure.oid) ~* '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public\.)?school_lesson_records'
order by procedure.oid::regprocedure::text;

-- Raw physical hash and old-31-column business hashes. The raw hash contains six NULL keys.
select scope, row_count, business_hash
from (
  select 1 sort_key, 'lesson_raw_37_columns' scope, count(*) row_count,
         md5(coalesce(string_agg(md5(to_jsonb(lesson)::text), '' order by lesson.id::text), '')) business_hash
  from public.school_lesson_records lesson
  union all
  select 2, 'lesson_old31', count(*), md5(coalesce(string_agg(md5((to_jsonb(lesson)
    - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
    - 'student_settlement_month' - 'billing_month_source'
    - 'billing_month_decided_at')::text), '' order by lesson.id::text), ''))
  from public.school_lesson_records lesson
  union all
  select 3, 'planned_old31', count(*), md5(coalesce(string_agg(md5((to_jsonb(lesson)
    - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
    - 'student_settlement_month' - 'billing_month_source'
    - 'billing_month_decided_at')::text), '' order by lesson.id::text), ''))
  from public.school_lesson_records lesson where lesson_type = 'planned'
  union all
  select 4, 'actual_old31', count(*), md5(coalesce(string_agg(md5((to_jsonb(lesson)
    - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
    - 'student_settlement_month' - 'billing_month_source'
    - 'billing_month_decided_at')::text), '' order by lesson.id::text), ''))
  from public.school_lesson_records lesson where lesson_type = 'actual'
) baseline
order by sort_key;

-- School non-lesson business baseline. Run this same statement before and after the audit.
select object_name,row_count,business_hash
from (
  select 1 sort_key,'tuition_bill' object_name,count(*) row_count,
    md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),'')) business_hash
  from public.school_student_tuition_bills row_value
  union all select 2,'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_income_records row_value
  union all select 3,'billing_identity',count(*),md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_student_tuition_billing_identities row_value
  union all select 4,'bill_lesson_relation',count(*),md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_student_tuition_bill_lessons row_value
  union all select 5,'migration_batch',count(*),md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_business_entity_migration_batches row_value
  union all select 6,'migration_item',count(*),md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_business_entity_migration_items row_value
  union all select 7,'school_cash_linkage',count(*),md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_personal_cash_income_linkage_events row_value
  union all select 8,'account_transaction',count(*),md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_account_transactions row_value
  union all select 9,'student_settlement',count(*),md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_student_monthly_settlements row_value
  union all select 10,'teacher_wage_lock',count(*),md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_teacher_wage_locks row_value
  union all select 11,'teacher_wage_detail',count(*),md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_teacher_wage_lock_details row_value
  union all select 12,'feature_gate',count(*),md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.feature_key),''))
  from public.school_feature_gates row_value
) school_baseline
order by sort_key;

-- Four disjoint fixed top-level cohorts cover all 626 lessons.
with relation_ids as (
  select distinct planned_lesson_id from public.school_student_tuition_bill_lessons
), migration_ids as (
  select lesson_record_id from public.school_business_entity_migration_items
  where batch_id in ('c1000000-0000-4000-8000-202607279999','c1000000-0000-4000-8000-202607289999')
), classified as (
  select lesson.*,
         md5((to_jsonb(lesson) - 'billing_month' - 'billing_week_start_date'
           - 'scheduled_lesson_date' - 'student_settlement_month'
           - 'billing_month_source' - 'billing_month_decided_at')::text) old31_hash,
         case when lesson.lesson_type = 'actual' then 'actual_229'
              when migration_ids.lesson_record_id is not null then 'r1c_fixed_118'
              when relation_ids.planned_lesson_id is not null then 'historical_bill_85'
              else 'other_planned_194' end cohort
  from public.school_lesson_records lesson
  left join relation_ids on relation_ids.planned_lesson_id = lesson.id
  left join migration_ids on migration_ids.lesson_record_id = lesson.id
)
select cohort, count(*) rows, count(distinct student_id) students,
       count(*) filter (where lesson_type='planned') planned_rows,
       count(*) filter (where lesson_type='actual') actual_rows,
       sum(duration_hours) hours, sum(coalesce(lesson_fee,0)) jpy,
       md5(string_agg(old31_hash,'' order by id::text)) old31_hash_aggregate
from classified group by cohort order by cohort;

-- Complete historical 121-relation evidence. NULL snapshots remain visibly NULL.
select relation.planned_lesson_id, relation.relation_role, relation.tuition_bill_id,
       bill.billing_month as bill_billing_month,
       identity.billing_month as identity_billing_month,
       relation.billing_month_snapshot,
       bill.source_snapshot ->> 'year_month' as bill_json_billing_month,
       lesson.lesson_date as legacy_lesson_date, lesson.year_month as legacy_year_month,
       public.school_iso_week_start(lesson.lesson_date) as current_inferred_week,
       to_char(public.school_iso_week_start(lesson.lesson_date),'YYYY-MM') as current_inferred_week_month,
       relation.scheduled_lesson_date_snapshot, relation.week_start_date_snapshot,
       md5((to_jsonb(lesson) - 'billing_month' - 'billing_week_start_date'
         - 'scheduled_lesson_date' - 'student_settlement_month'
         - 'billing_month_source' - 'billing_month_decided_at')::text) as current_old31_hash,
       relation.source_snapshot -> 'current_planned_lesson'
         = (to_jsonb(lesson) - 'billing_month' - 'billing_week_start_date'
           - 'scheduled_lesson_date' - 'student_settlement_month'
           - 'billing_month_source' - 'billing_month_decided_at') as matches_r1b_snapshot
from public.school_student_tuition_bill_lessons relation
join public.school_student_tuition_bills bill on bill.id = relation.tuition_bill_id
join public.school_lesson_records lesson on lesson.id = relation.planned_lesson_id
left join public.school_student_tuition_billing_identities identity
  on identity.canonical_bill_id = bill.id
order by relation.planned_lesson_id, relation.relation_role, relation.tuition_bill_id;

-- Fixed 118 billing-pair and planned student-settlement proposals.
select item.batch_id, item.item_order, item.lesson_record_id, item.student_id,
       coalesce(student.display_name,student.name,item.student_id::text) student_name,
       item.target_year_month proposed_billing_month,
       lesson.lesson_date proposed_billing_week_start_date,
       item.source_generation_batch_id, lesson.year_month legacy_year_month,
       md5((to_jsonb(lesson) - 'billing_month' - 'billing_week_start_date'
         - 'scheduled_lesson_date' - 'student_settlement_month'
         - 'billing_month_source' - 'billing_month_decided_at')::text) current_old31_hash,
       item.before_hash migration_before_hash, item.after_hash migration_after_hash,
       item.original_updated_at, lesson.updated_at current_updated_at,
       case when item.batch_id='c1000000-0000-4000-8000-202607279999'
         then 'approved_r1c_a_manifest' else 'approved_r1c_c_b_manifest' end proposed_source,
       null::timestamptz proposed_decided_at,
       'R1D-C-B approval must capture an exact decision timestamp' decided_at_null_reason,
       public.school_is_valid_tuition_billing_period(item.target_year_month,lesson.lesson_date) pair_valid,
       (select count(*) from public.school_student_tuition_bill_lessons r where r.planned_lesson_id=lesson.id)
       + (select count(*) from public.school_lesson_records a where a.lesson_type='actual' and a.planned_lesson_id=lesson.id)
         downstream_conflicts,
       'reviewable_medium' evidence_class, true business_approval_required
from public.school_business_entity_migration_items item
join public.school_lesson_records lesson on lesson.id=item.lesson_record_id
left join public.school_students student on student.id=item.student_id
where item.batch_id in ('c1000000-0000-4000-8000-202607279999','c1000000-0000-4000-8000-202607289999')
order by item.batch_id,item.item_order;

-- Scheduled-date proposal group: explicit named imports, excluding generator and test files.
select lesson.id, lesson.student_id,
       coalesce(student.display_name,student.name,lesson.student_id::text) student_name,
       lesson.import_batch_id, lesson.import_source,
       lesson.lesson_date proposed_scheduled_lesson_date,
       lesson.year_month, lesson.updated_at,
       md5((to_jsonb(lesson) - 'billing_month' - 'billing_week_start_date'
         - 'scheduled_lesson_date' - 'student_settlement_month'
         - 'billing_month_source' - 'billing_month_decided_at')::text) current_old31_hash,
       'reviewable_medium' evidence_class,
       'named planned import preserved the supplied date; business file-level confirmation required' evidence
from public.school_lesson_records lesson
left join public.school_students student on student.id=lesson.student_id
where lesson.lesson_type='planned'
  and lesson.import_batch_id is not null
  and lesson.import_source not like 'lesson_planned_batch_generator%'
  and lesson.import_source not like '测试%'
order by lesson.import_source,lesson.import_batch_id,lesson.id;

-- Per-lesson, per-new-field classification. This is evidence only; it never writes proposals.
with relation_evidence as (
  select planned_lesson_id, min(billing_month_snapshot) relation_month,
         count(distinct billing_month_snapshot) month_count,
         bool_or(relation_role='canonical_charge') has_canonical
  from public.school_student_tuition_bill_lessons group by planned_lesson_id
), migration as (
  select lesson_record_id,batch_id,target_year_month
  from public.school_business_entity_migration_items
  where batch_id in ('c1000000-0000-4000-8000-202607279999','c1000000-0000-4000-8000-202607289999')
), actual_siblings as (
  select planned_lesson_id,count(*) siblings from public.school_lesson_records
  where lesson_type='actual' group by planned_lesson_id
), base as (
  select lesson.*, relation.relation_month, relation.month_count, relation.has_canonical,
         migration.batch_id,migration.target_year_month,
         coalesce(actual_siblings.siblings,0) actual_siblings,
         case when lesson.lesson_type='planned' and lesson.import_batch_id is not null
                   and lesson.import_source not like 'lesson_planned_batch_generator%'
                   and lesson.import_source not like '测试%' then true else false end named_import,
         case when lesson.lesson_type='planned' and lesson.import_source like '测试%' then true else false end test_import
  from public.school_lesson_records lesson
  left join relation_evidence relation on relation.planned_lesson_id=lesson.id
  left join migration on migration.lesson_record_id=lesson.id
  left join actual_siblings on actual_siblings.planned_lesson_id=lesson.id
)
select base.id lesson_id, base.lesson_type, field.field_name, field.evidence_class,
       field.proposed_value, field.reason
from base
cross join lateral (values
  ('billing_month',
    case when base.lesson_type='actual' then 'not_applicable'
         when base.batch_id is not null then 'reviewable_medium'
         when base.has_canonical then 'approved_high' else 'unavailable' end,
    case when base.batch_id is not null then base.target_year_month
         when base.has_canonical and base.month_count=1 then base.relation_month end,
    case when base.lesson_type='actual' then 'planned-only field'
         when base.batch_id is not null then 'approved fixed R1C manifest; new approval still required'
         when base.has_canonical then 'canonical evidence proves month but not billing week'
         else 'no frozen billing evidence' end),
  ('billing_week_start_date',
    case when base.lesson_type='actual' then 'not_applicable'
         when base.batch_id is not null then 'reviewable_medium' else 'unavailable' end,
    case when base.batch_id is not null then base.lesson_date::text end,
    case when base.lesson_type='actual' then 'planned-only field'
         when base.batch_id is not null then 'fixed R1C batch-plan Monday proxy'
         when base.has_canonical then 'historical relation snapshots contain no billing week'
         else 'no independent frozen week evidence' end),
  ('scheduled_lesson_date',
    case when base.lesson_type='actual' then 'not_applicable'
         when base.named_import then 'reviewable_medium'
         when base.test_import then 'conflict' else 'unavailable' end,
    case when base.named_import then base.lesson_date::text end,
    case when base.lesson_type='actual' then 'planned-only field'
         when base.named_import then 'named import supplied date; file-level approval required'
         when base.test_import then 'test import is not business evidence'
         when base.import_source like 'lesson_planned_batch_generator%' then 'old date is a Monday proxy'
         else 'single/unknown source lacks independent schedule evidence' end),
  ('student_settlement_month',
    case when base.lesson_type='planned' and base.batch_id is not null then 'reviewable_medium'
         when base.actual_siblings>1 or (base.lesson_type='actual' and exists (
           select 1 from public.school_lesson_records p where p.id=base.planned_lesson_id
             and (select count(*) from public.school_lesson_records a where a.lesson_type='actual' and a.planned_lesson_id=p.id)>1
         )) then 'conflict' else 'unavailable' end,
    case when base.lesson_type='planned' and base.batch_id is not null then base.target_year_month end,
    case when base.lesson_type='planned' and base.batch_id is not null then 'planned follows proposed approved billing pair'
         when base.actual_siblings>1 then 'one planned has multiple actual rows'
         when base.lesson_type='actual' then 'source planned billing/student settlement is not approved'
         else 'billing pair is not approved' end),
  ('billing_month_source',
    case when base.lesson_type='actual' then 'not_applicable'
         when base.batch_id is not null then 'reviewable_medium'
         when base.has_canonical then 'approved_high' else 'unavailable' end,
    case when base.batch_id='c1000000-0000-4000-8000-202607279999' then 'approved_r1c_a_manifest'
         when base.batch_id='c1000000-0000-4000-8000-202607289999' then 'approved_r1c_c_b_manifest'
         when base.has_canonical then 'canonical_billing_evidence' end,
    case when base.lesson_type='actual' then 'planned-only metadata'
         when base.batch_id is not null then 'stable machine-verifiable migration batch'
         when base.has_canonical then 'canonical relation/identity source'
         else 'no stable source code' end),
  ('billing_month_decided_at',
    case when base.lesson_type='actual' then 'not_applicable' else 'unavailable' end,
    null::text,
    case when base.lesson_type='actual' then 'planned-only metadata'
         else 'no exact original business-decision timestamp; audit/executed/created/updated times are not substitutes' end)
) field(field_name,evidence_class,proposed_value,reason)
order by base.id,field.field_name;

-- R1D-B check simulation for all 118 proposed pairs; source is intentionally not written
-- until R1D-C-B captures an exact decided_at, because source/decided_at are paired.
with proposed as (
  select lesson.id,item.target_year_month billing_month,lesson.lesson_date billing_week,
         item.target_year_month student_settlement_month
  from public.school_business_entity_migration_items item
  join public.school_lesson_records lesson on lesson.id=item.lesson_record_id
  where item.batch_id in ('c1000000-0000-4000-8000-202607279999','c1000000-0000-4000-8000-202607289999')
)
select count(*) rows,
       count(*) filter(where public.school_is_valid_tuition_billing_period(billing_month,billing_week)) valid_pairs,
       count(*) filter(where extract(isodow from billing_week)=1) monday_rows,
       count(*) filter(where billing_month=to_char(billing_week,'YYYY-MM')) month_week_matches,
       count(*) filter(where student_settlement_month=billing_month) settlement_matches,
       count(*) filter(where billing_month='2026-08' and billing_week='2026-07-27') invalid_august_july_week,
       count(*) filter(where billing_month='2026-09' and billing_week='2026-08-31') invalid_september_august_week
from proposed;

-- Current legacy candidate versus a future fail-closed candidate using only approved 118 proposals.
with current_candidates as (
  select distinct candidate.planned_lesson_id
  from public.school_students student
  join (select distinct student_id,year_month from public.school_lesson_records
        where app_type='school' and lesson_type='planned') scope on scope.student_id=student.id
  cross join lateral public.school_list_student_tuition_candidates(
    student.id,student.business_entity_id,scope.year_month,false) candidate
  where candidate.candidate_status='candidate'
), proposed_candidates as (
  select lesson_record_id planned_lesson_id
  from public.school_business_entity_migration_items
  where batch_id in ('c1000000-0000-4000-8000-202607279999','c1000000-0000-4000-8000-202607289999')
), current_only as (
  select * from current_candidates except select * from proposed_candidates
), proposed_only as (
  select * from proposed_candidates except select * from current_candidates
)
select (select count(*) from current_candidates) current_candidate_rows,
       (select count(*) from proposed_candidates) proposed_candidate_rows,
       (select count(*) from current_only) current_only_rows,
       (select count(*) from proposed_only) proposed_only_rows;

with current_candidates as (
  select distinct candidate.planned_lesson_id
  from public.school_students student
  join (select distinct student_id,year_month from public.school_lesson_records
        where app_type='school' and lesson_type='planned') scope on scope.student_id=student.id
  cross join lateral public.school_list_student_tuition_candidates(
    student.id,student.business_entity_id,scope.year_month,false) candidate
  where candidate.candidate_status='candidate'
), proposed_candidates as (
  select lesson_record_id planned_lesson_id
  from public.school_business_entity_migration_items
  where batch_id in ('c1000000-0000-4000-8000-202607279999','c1000000-0000-4000-8000-202607289999')
), differences as (
  select 'current_only' difference,planned_lesson_id from current_candidates
  except select 'current_only',planned_lesson_id from proposed_candidates
  union all
  select 'proposed_only',planned_lesson_id from proposed_candidates
  except select 'proposed_only',planned_lesson_id from current_candidates
)
select differences.difference,lesson.id,student.display_name student_name,
       lesson.year_month,lesson.lesson_date,lesson.status,lesson.import_batch_id,lesson.import_source,
       lesson.duration_hours,lesson.lesson_fee,
       (select count(*) from public.school_lesson_records actual
        where actual.lesson_type='actual' and actual.planned_lesson_id=lesson.id) actual_count,
       exists(select 1 from public.school_student_monthly_settlements settlement
         where settlement.student_id=lesson.student_id
           and settlement.business_entity_id is not distinct from lesson.business_entity_id
           and settlement.year_month=lesson.year_month and settlement.settlement_status='locked') locked_settlement,
       md5((to_jsonb(lesson)-'billing_month'-'billing_week_start_date'-'scheduled_lesson_date'
         -'student_settlement_month'-'billing_month_source'-'billing_month_decided_at')::text) old31_hash
from differences join public.school_lesson_records lesson on lesson.id=differences.planned_lesson_id
left join public.school_students student on student.id=lesson.student_id
order by differences.difference,lesson.year_month,student.display_name,lesson.id;

-- Historical roles must remain excluded by the current authoritative candidate function.
select relation.relation_role,count(*) relation_rows,
       count(*) filter(where candidate.candidate_status='candidate') candidate_rows,
       count(*) filter(where candidate.candidate_status='excluded') excluded_rows
from public.school_student_tuition_bill_lessons relation
join public.school_lesson_records lesson on lesson.id=relation.planned_lesson_id
cross join lateral public.school_list_student_tuition_candidates(
  lesson.student_id,lesson.business_entity_id,lesson.year_month,true) candidate
where candidate.planned_lesson_id=lesson.id
group by relation.relation_role order by relation.relation_role;

-- R1B normalized relation versus bill JSON/aggregate regression.
select count(*) relation_rows,
       count(*) filter(where
         relation.relation_role=bill.billing_role
         and relation.student_id_snapshot=bill.student_id
         and relation.business_entity_id_snapshot is not distinct from bill.business_entity_id
         and relation.billing_month_snapshot=bill.billing_month
         and relation.line_no <= jsonb_array_length(coalesce(bill.source_snapshot->'planned_lesson_ids','[]'::jsonb))
         and (bill.source_snapshot->'planned_lesson_ids'->>(relation.line_no-1))::uuid=relation.planned_lesson_id
       ) exact_json_rows,
       count(*) filter(where relation.week_start_date_snapshot is not null) week_snapshot_nonnull,
       count(*) filter(where relation.scheduled_lesson_date_snapshot is not null) scheduled_snapshot_nonnull
from public.school_student_tuition_bill_lessons relation
join public.school_student_tuition_bills bill on bill.id=relation.tuition_bill_id;

-- Two July-canonical cross-month lessons remain immutable historical evidence.
select lesson.id,lesson.lesson_date,lesson.year_month,lesson.business_entity_id,
       relation.relation_role,relation.billing_month_snapshot,relation.tuition_bill_id,
       lesson.duration_hours,lesson.unit_price,lesson.lesson_fee,
       md5((to_jsonb(lesson)-'billing_month'-'billing_week_start_date'-'scheduled_lesson_date'
         -'student_settlement_month'-'billing_month_source'-'billing_month_decided_at')::text) old31_hash
from public.school_lesson_records lesson
join public.school_student_tuition_bill_lessons relation on relation.planned_lesson_id=lesson.id
where lesson.id in ('8b737b58-cd14-42c5-afd2-34730dcef963'::uuid,
                    '685ad45e-b5da-42ca-8f43-7732e8d6e40d'::uuid)
  and relation.relation_role='canonical_charge'
order by lesson.lesson_date;

-- Li Tianlun fixed 11 and the independently added 229th actual stay evidence-only.
select lesson.id,lesson.lesson_type,lesson.status,lesson.year_month,lesson.lesson_date,
       lesson.planned_lesson_id,lesson.import_batch_id,lesson.import_source,
       md5((to_jsonb(lesson)-'billing_month'-'billing_week_start_date'-'scheduled_lesson_date'
         -'student_settlement_month'-'billing_month_source'-'billing_month_decided_at')::text) old31_hash
from public.school_lesson_records lesson
where lesson.id in (
  'f256bca9-fac5-4909-b113-8077efd27d65'::uuid,'a722a49e-dbe5-447d-8068-fd5fb743f6ab'::uuid,
  '265f4d3d-2372-42e3-aec3-b963bbdddf95'::uuid,'e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid,
  '552c54e3-2d0c-4607-962d-aad39dfff7f7'::uuid,'b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid,
  'ac16b068-a58b-4ca5-be95-7c57c3f1b82b'::uuid,'39aa30ab-d66c-43c0-bbde-3b3a35d71fb7'::uuid,
  'f759623b-ce28-4c5f-8556-95c4381b6b1b'::uuid,'c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid,
  'dc06b98c-360f-4661-a294-52ecb82830a7'::uuid,'50ec3900-63ff-4138-85f1-53a999c23daa'::uuid
)
order by lesson.id;

-- R0 state is read, not probed through write entry points in this strict read-only phase.
select feature_key,state from public.school_feature_gates order by feature_key;

select clock_timestamp() as school_evidence_finished_at;
commit;
