-- Cash read-only fingerprint for School expense permission phase 2.
\set ON_ERROR_STOP on
\pset pager off

begin read only;

do $block$
begin
  if (select count(*) from public.home_external_transaction_requests
      where external_source='aozora_school'
        and external_reference_type='school_expense_records'
        and request_type='expense_paid') <> 17
     or (select count(*) from public.home_external_transaction_requests
         where external_source='aozora_school'
           and external_reference_type='school_expense_records'
           and request_type='expense_paid' and status='approved') <> 15
     or (select count(*) from public.home_external_transaction_requests
         where external_source='aozora_school'
           and external_reference_type='school_expense_records'
           and request_type='expense_paid' and status='rejected') <> 2
     or exists (select 1 from public.home_external_transaction_requests where id::text like '98000000-%')
     or exists (select 1 from public.home_cny_transactions where id::text like '98000000-%')
     or exists (select 1 from public.home_jpy_transactions where id::text like '98000000-%') then
    raise exception 'P0_PHASE2_CASH_HISTORY_OR_RESIDUE_DRIFT';
  end if;
end;
$block$;

select 'cash_expense_requests' as object_name,count(*) as row_count,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) as row_hash
from public.home_external_transaction_requests x
where x.external_source='aozora_school'
  and x.external_reference_type='school_expense_records'
  and x.request_type='expense_paid'
union all
select 'cash_cny_expense_transactions',count(*),
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.home_cny_transactions x
where x.external_source='aozora_school'
  and x.external_reference_type='school_expense_records'
union all
select 'cash_jpy_expense_transactions',count(*),
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.home_jpy_transactions x
where x.external_source='aozora_school'
  and x.external_reference_type='school_expense_records';

select 'CASH_P0_PHASE2_POSTDEPLOY_PASS' as result;
rollback;
