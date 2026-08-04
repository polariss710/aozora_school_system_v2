-- School V2 ordinary expense permission P0 phase 2 postdeploy verification.
-- SELECT/metadata assertions only.
\set ON_ERROR_STOP on
\pset pager off

begin read only;

do $block$
declare
  v_signature text;
  v_oid oid;
begin
  foreach v_signature in array array[
    'public.school_update_expense_record(uuid,timestamptz,date,uuid,uuid,text,text,text,numeric,numeric,text,text,text,text,text)',
    'public.school_reverse_expense_record(uuid,date,text)',
    'public.school_create_reimbursement_record(date,uuid,uuid,uuid,uuid[],text)',
    'public.school_reverse_reimbursement_record(uuid,date,text)',
    'public.school_create_expense_attachment_metadata(uuid,text,text,bigint,text,text)',
    'public.school_generate_teacher_monthly_wage(text,uuid,uuid)',
    'public.school_generate_teacher_monthly_wage(text,uuid)',
    'public.school_adjust_teacher_wage_detail(uuid,numeric,numeric,numeric,text)',
    'public.school_create_teacher_wage_expense_record(uuid,date,text)',
    'public.school_void_unsubmitted_teacher_wage_expense_record(uuid,text)',
    'public.school_void_teacher_wage_lock(uuid,text,text,text)',
    'public.school_create_teacher_wage_rule_config(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,boolean,text)',
    'public.school_update_teacher_wage_rule_config(uuid,uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,boolean,text)',
    'public.school_set_teacher_wage_rule_active_state(uuid,boolean,text)',
    'public.school_confirm_payment_request(uuid,uuid,date,numeric,text,text)',
    'public.school_reverse_paid_payment_request(uuid,text,date)',
    'public.school_cancel_payment_request(uuid,text)',
    'public.school_restore_cancelled_payment_request(uuid)',
    'public.school_reissue_reversed_payment_request(uuid,text)'
  ] loop
    v_oid := to_regprocedure(v_signature);
    if v_oid is null
       or has_function_privilege('anon',v_oid,'EXECUTE')
       or not has_function_privilege('authenticated',v_oid,'EXECUTE')
       or has_function_privilege('service_role',v_oid,'EXECUTE')
       or not (select p.prosecdef from pg_proc p where p.oid=v_oid)
       or (select p.proconfig from pg_proc p where p.oid=v_oid) is distinct from array['search_path=pg_catalog, public']::text[]
       or pg_get_functiondef(v_oid) not like '%school_require_current_app_admin()%' then
      raise exception 'P0_PHASE2_INTERACTIVE_POSTDEPLOY_FAILED: %',v_signature;
    end if;
  end loop;

  foreach v_signature in array array[
    'public.school_update_expense_record(uuid,date,uuid,uuid,text,text,text,numeric,numeric,text,text,text,text,text)',
    'public.school_update_teacher_wage_rule_config(uuid,text,numeric,numeric,numeric,numeric,numeric,boolean,text)',
    'public.school_void_teacher_wage_lock_admin_impl_20260804(uuid,text,text,text)',
    'public.school_create_teacher_wage_payment_request(uuid,date,text)',
    'public.school_request_personal_cash_payment_confirmation(uuid,uuid,text)',
    'public.school_confirm_personal_cash_payment_request(uuid,uuid,date,numeric,text)',
    'public.school_create_personal_cash_account_mapping(uuid,uuid,uuid,text,text,text)',
    'public.school_update_personal_cash_account_mapping(uuid,text,text,boolean,text)',
    'public.school_create_personal_cash_linkage_event(uuid,uuid,text)',
    'public.school_update_personal_cash_linkage_event_status(uuid,text,uuid,text)',
    'public.school_mark_personal_cash_payment_request_submitted(uuid,uuid,text)',
    'public.school_mark_personal_cash_payment_request_confirmed(uuid,uuid,uuid,timestamptz)',
    'public.school_mark_personal_cash_payment_request_rejected(uuid,uuid,text,timestamptz)',
    'public.school_fix_202605_teacher_wage_duplicate_cong_qirun()'
  ] loop
    v_oid := to_regprocedure(v_signature);
    if v_oid is null
       or has_function_privilege('anon',v_oid,'EXECUTE')
       or has_function_privilege('authenticated',v_oid,'EXECUTE')
       or has_function_privilege('service_role',v_oid,'EXECUTE')
       or (select p.proconfig from pg_proc p where p.oid=v_oid) is distinct from array['search_path=pg_catalog, public']::text[] then
      raise exception 'P0_PHASE2_OWNER_ONLY_POSTDEPLOY_FAILED: %',v_signature;
    end if;
  end loop;

  foreach v_signature in array array[
    'public.school_request_cash_expense_payment_confirmation(uuid,uuid,uuid,text,text,numeric,text,text,numeric,text)',
    'public.school_mark_cash_expense_request_submitted(uuid,uuid,text)',
    'public.school_mark_cash_expense_confirmed(uuid,uuid,uuid,timestamptz)',
    'public.school_mark_cash_expense_rejected(uuid,uuid,text,timestamptz)'
  ] loop
    v_oid := to_regprocedure(v_signature);
    if v_oid is null
       or has_function_privilege('anon',v_oid,'EXECUTE')
       or has_function_privilege('authenticated',v_oid,'EXECUTE')
       or not has_function_privilege('service_role',v_oid,'EXECUTE')
       or (select p.proconfig from pg_proc p where p.oid=v_oid) is distinct from array['search_path=pg_catalog, public']::text[] then
      raise exception 'P0_PHASE2_SERVICE_HELPER_POSTDEPLOY_FAILED: %',v_signature;
    end if;
  end loop;

  if exists (
    with f as (
      select p.oid,p.proname,p.proowner,p.proacl,p.proconfig,pg_get_functiondef(p.oid) definition
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public'
    )
    select 1 from f
    where definition ~* '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public\.)?school_(expense|reimbursement|teacher_wage|salary|payment_request|personal_cash)'
      and proname !~ '(income|tuition|part_time)'
      and (
        has_function_privilege('anon',oid,'EXECUTE')
        or (has_function_privilege('authenticated',oid,'EXECUTE') and definition not like '%school_require_current_app_admin()%')
        or ((has_function_privilege('authenticated',oid,'EXECUTE') or has_function_privilege('service_role',oid,'EXECUTE'))
            and proconfig is distinct from array['search_path=pg_catalog, public']::text[])
      )
  ) then
    raise exception 'P0_PHASE2_EQUIVALENT_WRITER_BYPASS_FOUND';
  end if;

  if exists (
    select 1
    from pg_default_acl d
    join pg_namespace n on n.oid=d.defaclnamespace
    cross join lateral aclexplode(d.defaclacl) a
    where d.defaclrole='postgres'::regrole and n.nspname='public'
      and a.grantee=0
  ) then
    raise exception 'P0_PHASE2_PUBLIC_DEFAULT_ACL_FOUND';
  end if;
end;
$block$;

do $block$
declare v_table text; v_role text;
begin
  foreach v_table in array array[
    'school_expense_records','school_accounts','school_account_transactions',
    'school_expense_attachments','school_reimbursements','school_reimbursement_items',
    'school_reimbursement_expenses','school_salary_payments','school_teacher_wage_locks',
    'school_teacher_wage_lock_details','school_teacher_wage_detail_adjustments',
    'school_teacher_wage_rules','school_payment_requests',
    'school_personal_cash_account_mappings','school_personal_cash_linkage_events'
  ] loop
    foreach v_role in array array['anon','authenticated','service_role'] loop
      if has_table_privilege(v_role,'public.'||v_table,'INSERT')
         or has_table_privilege(v_role,'public.'||v_table,'UPDATE')
         or has_table_privilege(v_role,'public.'||v_table,'DELETE') then
        raise exception 'P0_PHASE2_DIRECT_DML_FOUND: %.%',v_role,v_table;
      end if;
    end loop;
  end loop;
end;
$block$;

do $block$
begin
  if (select public from storage.buckets where id='school-expense-files')
     or exists (
       select 1 from pg_policies p
       where p.schemaname='storage' and p.tablename='objects'
         and p.policyname like 'school_allow_all_storage_expense_files_%'
         and ('anon'=any(p.roles) or 'public'=any(p.roles))
     )
     or not exists (
       select 1 from pg_policies p
       where p.schemaname='storage' and p.tablename='objects'
         and p.policyname='school_allow_all_storage_expense_files_insert'
         and p.roles=array['authenticated']::name[]
         and p.with_check like '%school_get_current_app_membership%'
         and p.with_check like '%school_expense_records%'
     )
     or not exists (
       select 1 from pg_policies p
       where p.schemaname='storage' and p.tablename='objects'
         and p.policyname='school_allow_all_storage_expense_files_update'
         and p.qual='false' and p.with_check='false'
     )
     or not exists (
       select 1 from pg_policies p
       where p.schemaname='storage' and p.tablename='objects'
         and p.policyname='school_allow_all_storage_expense_files_delete'
         and p.qual='false'
     ) then
    raise exception 'P0_PHASE2_STORAGE_POLICY_FAILED';
  end if;
end;
$block$;

do $block$
begin
  if (select state from public.school_feature_gates where feature_key='student_tuition_preview') <> 'enabled'
     or (select state from public.school_feature_gates where feature_key='student_tuition_generate') <> 'blocked'
     or (select state from public.school_feature_gates where feature_key='student_tuition_cash_submit') <> 'enabled' then
    raise exception 'P0_PHASE2_TUITION_GATE_DRIFT';
  end if;
  if (select count(*) from public.school_expense_records) <> 46
     or (select count(*) from public.school_expense_records where expense_category='teacher_wage' and cash_request_id is not null) <> 17
     or exists (select 1 from public.school_expense_records where id::text like '98000000-%')
     or exists (select 1 from public.school_accounts where id::text like '98000000-%')
     or exists (select 1 from public.school_account_transactions where id::text like '98000000-%')
     or exists (select 1 from public.school_teacher_wage_locks where id::text like '98000000-%')
     or exists (select 1 from auth.users where id::text like 'e4100000-%')
     or exists (select 1 from public.school_app_memberships where user_id::text like 'e4100000-%')
     or exists (select 1 from public.school_expense_records where id::text like 'e4100000-%')
     or exists (select 1 from public.school_accounts where id::text like 'e4100000-%')
     or exists (select 1 from public.school_account_transactions where id::text like 'e4100000-%') then
    raise exception 'P0_PHASE2_HISTORY_OR_RESIDUE_DRIFT';
  end if;
end;
$block$;

select 'school_expense_records' as object_name,count(*) as row_count,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) as row_hash
from public.school_expense_records x
union all
select 'teacher_wage_cash_expenses',count(*),
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_expense_records x
where x.expense_category='teacher_wage' and x.cash_request_id is not null
union all
select 'school_accounts',count(*),
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_accounts x
union all
select 'school_account_transactions',count(*),
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_account_transactions x;

select count(*) as storage_object_count,
       count(*) filter (where e.id is null) as preexisting_orphan_object_count
from storage.objects o
left join public.school_expense_records e
  on e.id::text=split_part(o.name,'/',3) and e.app_type='school'
where o.bucket_id='school-expense-files';

select feature_key,state
from public.school_feature_gates
where feature_key in ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit')
order by feature_key;

select 'P0_PHASE2_POSTDEPLOY_PASS' as result;
rollback;
