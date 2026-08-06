-- Phase BE-UI School production baseline/reconciliation. SELECT only.
\set ON_ERROR_STOP on
\pset pager off

begin transaction isolation level repeatable read read only;

select object_name,row_count,row_hash
from (
  select 1 sort_order,'school_business_entities' object_name,count(*) row_count,
         md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
  from public.school_business_entities x
  union all select 2,'school_lesson_records',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_lesson_records x
  union all select 3,'school_student_monthly_settlements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_monthly_settlements x
  union all select 4,'school_student_tuition_bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bills x
  union all select 5,'school_student_tuition_bill_lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bill_lessons x
  union all select 6,'school_teacher_wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_locks x
  union all select 7,'school_teacher_wage_lock_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_lock_details x
  union all select 8,'school_income_records',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_income_records x
  union all select 9,'school_expense_records',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_expense_records x
  union all select 10,'school_payment_requests',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_payment_requests x
  union all select 11,'school_reimbursements',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_reimbursements x
  union all select 12,'school_accounts',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_accounts x
  union all select 13,'school_account_transactions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_account_transactions x
  union all select 14,'school_personal_cash_income_linkage_events',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_personal_cash_income_linkage_events x
) fingerprints
order by sort_order;

select entity.code,source_name,reference_count
from public.school_business_entities entity
cross join lateral (
  values
    ('lessons',(select count(*) from public.school_lesson_records x where x.business_entity_id=entity.id)),
    ('settlements',(select count(*) from public.school_student_monthly_settlements x where x.business_entity_id=entity.id)),
    ('tuition_bills',(select count(*) from public.school_student_tuition_bills x where x.business_entity_id=entity.id)),
    ('tuition_bill_lessons',(select count(*) from public.school_student_tuition_bill_lessons x where x.business_entity_id_snapshot=entity.id)),
    ('wage_locks',(select count(*) from public.school_teacher_wage_locks x where x.business_entity_id=entity.id)),
    ('wage_details',(select count(*) from public.school_teacher_wage_lock_details x where x.business_entity_id=entity.id)),
    ('income',(select count(*) from public.school_income_records x where x.business_entity_id=entity.id)),
    ('expense',(select count(*) from public.school_expense_records x where x.business_entity_id=entity.id)),
    ('payment_requests',(select count(*) from public.school_payment_requests x where x.business_entity_id=entity.id)),
    ('cash_linkage',(select count(*) from public.school_personal_cash_income_linkage_events x where x.business_entity_id=entity.id))
) refs(source_name,reference_count)
order by entity.code,source_name;

select year_month,currency,
       count(*) income_count,
       sum(case currency when 'JPY' then coalesce(amount_jpy,amount) else coalesce(amount_cny,amount) end) income_amount
from public.school_operational_income_records
where app_type='school' and status='received' and currency in ('JPY','CNY')
group by year_month,currency
order by year_month,currency;

select year_month,currency,
       count(*) expense_count,
       sum(case currency when 'JPY' then coalesce(amount_jpy,amount) else coalesce(amount_cny,amount) end) expense_amount,
       sum(case when expense_category='teacher_wage'
                then case currency when 'JPY' then coalesce(amount_jpy,amount) else coalesce(amount_cny,amount) end
                else 0 end) teacher_wage_amount
from public.school_expense_records
where app_type='school' and status='paid' and currency in ('JPY','CNY')
group by year_month,currency
order by year_month,currency;

select count(*) duplicate_wage_scope_groups
from (
  select teacher_id,business_entity_id,settlement_month
  from public.school_teacher_wage_locks
  where status='locked'
  group by teacher_id,business_entity_id,settlement_month
  having count(*)>1
) duplicate_scope;

select p.oid::regprocedure::text signature,coalesce(s.calls,0) tracked_calls,
       has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') service_role_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
left join pg_stat_user_functions s on s.funcid=p.oid
where n.nspname='public'
  and p.proname in ('school_create_business_entity_profile','school_update_business_entity_profile')
order by signature;

select feature_key,state,updated_at
from public.school_feature_gates
where feature_key in ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit')
order by feature_key;

select md5(coalesce(string_agg(to_jsonb(x)::text,'|' order by x.bill_id,x.linkage_event_id),'')) anomaly_fingerprint
from (
  select b.id bill_id,b.business_entity_id bill_business_entity_id,b.status bill_status,b.updated_at bill_updated_at,
         i.id income_id,i.business_entity_id income_business_entity_id,i.status income_status,i.updated_at income_updated_at,
         g.id generation_identity_id,g.business_entity_id identity_business_entity_id,
         r.id revision_id,r.lifecycle_status revision_status,r.activated_at revision_activated_at,
         e.id linkage_event_id,e.business_entity_id linkage_business_entity_id,e.sync_status linkage_status,e.updated_at linkage_updated_at
  from public.school_student_tuition_bills b
  left join public.school_income_records i on i.id=b.income_record_id
  left join public.school_student_tuition_generation_revisions r on r.tuition_bill_id=b.id and r.lifecycle_status='active'
  left join public.school_student_tuition_generation_identities g on g.id=r.generation_identity_id
  left join public.school_personal_cash_income_linkage_events e on e.income_record_id=i.id
  where b.id in ('2a9f1c25-a060-461e-ae10-b02295dec381','fdf3cdfe-f715-4814-b500-9ff2bfe77a63')
) x;

select 'BE_UI_SCHOOL_BASELINE_READONLY_PASS' result;
rollback;
