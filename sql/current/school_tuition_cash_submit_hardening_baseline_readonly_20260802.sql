-- School V2 tuition Cash hardening current 17-row baseline, 2026-08-02.
-- Read-only SELECT plus client-side TSV export. No RPC call and no DB write.
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset fieldsep '\t'
\pset footer off
\o docs/school-v2-tuition-cash-submit-hardening-baseline-17rows-20260802.tsv
with latest_linkage as (
  select distinct on (event_row.income_record_id) event_row.*
  from public.school_personal_cash_income_linkage_events event_row
  order by event_row.income_record_id, event_row.attempt_no desc,
           event_row.created_at desc, event_row.id desc
), relation_counts as (
  select tuition_bill_id, count(*)::integer as relation_count
  from public.school_student_tuition_bill_lessons
  group by tuition_bill_id
)
select
  coalesce(student.display_name, student.name) as student_name,
  student.id as student_id,
  bill.billing_month,
  entity.name as business_entity,
  identity.id as billing_identity_id,
  bill.id as bill_id,
  bill.status as bill_status,
  income.id as income_id,
  income.status as income_status,
  income.amount_jpy,
  bill.billing_exchange_rate,
  bill.billing_amount_cny,
  bill.previous_carryover_cny,
  latest.cash_request_status,
  latest.cash_request_id,
  latest.cash_transaction_id,
  latest.id as latest_linkage_event_id,
  latest.sync_status as latest_linkage_status,
  case
    when income.source_type is distinct from 'student_tuition_bill'
      or income.income_category is distinct from 'tuition'
      then 'NOT_TUITION_INCOME'
    when income.status = 'received'
      and latest.sync_status in ('synced', 'historical_confirmed')
      and (
        latest.sync_status = 'historical_confirmed'
        or (
          latest.cash_request_status = 'approved'
          and latest.cash_request_id is not null
          and latest.cash_transaction_id is not null
        )
      ) then 'ALREADY_SYNCED'
    when latest.sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation')
      or latest.cash_request_status = 'pending' then 'ALREADY_SUBMITTED'
    when income.status = 'pending'
      and latest.sync_status = 'cash_rejected'
      and latest.cash_request_status = 'rejected'
      and latest.cash_transaction_id is null then 'REJECTED_RETRYABLE'
    when income.status = 'pending'
      and bill.status = 'income_created'
      and identity.id is not null
      and income.source_type = 'student_tuition_bill'
      and income.income_category = 'tuition'
      and income.source_id = bill.id
      and income.tuition_bill_id = bill.id
      and bill.income_record_id = income.id
      and income.account_id is null
      and income.cash_submission_blocked is false
      and income.operational_excluded is false
      and bill.cash_submission_blocked is false
      and latest.id is null then 'ELIGIBLE_FOR_CASH_SUBMIT'
    else 'BLOCKED_CONFLICT'
  end as classification,
  coalesce(rel.relation_count, 0) as relation_count,
  bill.planned_lesson_count,
  coalesce((
    bill.student_id = income.student_id
    and bill.business_entity_id = income.business_entity_id
    and bill.billing_month = income.year_month
    and bill.billing_month = income.settlement_month
    and bill.id = income.source_id
    and bill.id = income.tuition_bill_id
    and bill.income_record_id = income.id
    and income.currency = 'JPY'
    and income.amount = bill.bill_amount_jpy
    and income.amount_jpy = bill.bill_amount_jpy
    and (income.source_snapshot ->> 'tuition_bill_id')::uuid = bill.id
    and (income.source_snapshot ->> 'billing_identity_id')::uuid = identity.id
    and (income.source_snapshot ->> 'billing_exchange_rate')::numeric = bill.billing_exchange_rate
    and (income.source_snapshot ->> 'billing_amount_cny')::numeric = bill.billing_amount_cny
    and (income.source_snapshot ->> 'previous_carryover_cny')::numeric = bill.previous_carryover_cny
    and coalesce(rel.relation_count, 0) = bill.planned_lesson_count
  ), false) as frozen_snapshot_consistent,
  income.created_at as income_created_at,
  bill.created_at as bill_created_at
from public.school_student_tuition_bills bill
left join public.school_income_records income on income.id = bill.income_record_id
left join public.school_students student on student.id = bill.student_id
left join public.school_business_entities entity on entity.id = bill.business_entity_id
left join public.school_student_tuition_billing_identities identity on identity.canonical_bill_id = bill.id
left join latest_linkage latest on latest.income_record_id = income.id
left join relation_counts rel on rel.tuition_bill_id = bill.id
order by bill.billing_month, student_name, bill.id;
\o
\pset format aligned
\pset footer on

select feature_key, state, release_version
from public.school_feature_gates
where feature_key in (
  'student_tuition_preview', 'student_tuition_generate', 'student_tuition_cash_submit'
)
order by feature_key;

with latest_linkage as (
  select distinct on (event_row.income_record_id) event_row.*
  from public.school_personal_cash_income_linkage_events event_row
  order by event_row.income_record_id, event_row.attempt_no desc,
           event_row.created_at desc, event_row.id desc
), classified as (
  select bill.billing_amount_cny, bill.bill_amount_jpy, bill.previous_carryover_cny,
    case
      when income.status = 'received'
        and latest.sync_status in ('synced', 'historical_confirmed') then 'ALREADY_SYNCED'
      when income.status = 'pending' and bill.status = 'income_created'
        and identity.id is not null
        and income.source_id = bill.id and income.tuition_bill_id = bill.id
        and bill.income_record_id = income.id
        and income.account_id is null
        and income.cash_submission_blocked is false
        and income.operational_excluded is false
        and bill.cash_submission_blocked is false
        and latest.id is null then 'ELIGIBLE_FOR_CASH_SUBMIT'
      else 'BLOCKED_CONFLICT'
    end as classification
  from public.school_student_tuition_bills bill
  left join public.school_income_records income on income.id = bill.income_record_id
  left join public.school_student_tuition_billing_identities identity on identity.canonical_bill_id = bill.id
  left join latest_linkage latest on latest.income_record_id = income.id
)
select classification, count(*) as row_count,
       sum(bill_amount_jpy) as total_jpy,
       sum(billing_amount_cny) as total_cny,
       sum(previous_carryover_cny) as total_carryover_cny
from classified
group by classification
order by classification;

select
  (select count(*) from public.school_student_tuition_bills) as bill_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), ''))
     from public.school_student_tuition_bills row_value) as bill_md5,
  (select count(*) from public.school_income_records) as income_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), ''))
     from public.school_income_records row_value) as income_md5,
  (select count(*) from public.school_personal_cash_income_linkage_events) as linkage_count,
  (select md5(coalesce(string_agg(md5(to_jsonb(row_value)::text), '' order by row_value.id::text), ''))
     from public.school_personal_cash_income_linkage_events row_value) as linkage_md5;
