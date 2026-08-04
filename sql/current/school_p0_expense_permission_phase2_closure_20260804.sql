-- School V2 ordinary expense permission P0 phase 2 closure.
-- Scope: writer ACL/RLS/storage closure only. No business data repair.
\set ON_ERROR_STOP on
\pset pager off

do $block$
declare
  v_signature text;
  v_definition text;
begin
  foreach v_signature in array array[
    'public.school_create_teacher_wage_expense_record(uuid,date,text)',
    'public.school_reissue_reversed_payment_request(uuid,text)',
    'public.school_void_unsubmitted_teacher_wage_expense_record(uuid,text)'
  ] loop
    if to_regprocedure(v_signature) is null then
      raise exception 'P0_PHASE2_REQUIRED_FUNCTION_MISSING: %', v_signature;
    end if;

    select pg_get_functiondef(to_regprocedure(v_signature))
      into v_definition;

    if v_definition not like '%school_require_current_app_admin()%' then
      v_definition := regexp_replace(
        v_definition,
        E'(?i)(\\nbegin\\n)',
        E'\\1  perform public.school_require_current_app_admin();' || chr(10) || chr(10)
      );
      if v_definition not like '%school_require_current_app_admin()%' then
        raise exception 'P0_PHASE2_ADMIN_GUARD_INJECTION_FAILED: %', v_signature;
      end if;
      execute v_definition;
    end if;
  end loop;
end;
$block$;

alter function public.school_create_teacher_wage_expense_record(uuid,date,text)
  security definer set search_path = pg_catalog, public;
alter function public.school_reissue_reversed_payment_request(uuid,text)
  security definer set search_path = pg_catalog, public;
alter function public.school_void_unsubmitted_teacher_wage_expense_record(uuid,text)
  security definer set search_path = pg_catalog, public;

revoke all on function public.school_create_teacher_wage_expense_record(uuid,date,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_create_teacher_wage_expense_record(uuid,date,text)
  to authenticated;
revoke all on function public.school_reissue_reversed_payment_request(uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_reissue_reversed_payment_request(uuid,text)
  to authenticated;
revoke all on function public.school_void_unsubmitted_teacher_wage_expense_record(uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_void_unsubmitted_teacher_wage_expense_record(uuid,text)
  to authenticated;

-- Preserve the latest production void business guards behind a private helper.
-- The public wrapper derives audit identity from auth.uid and fixes the source.
do $block$
begin
  if to_regprocedure('public.school_void_teacher_wage_lock_admin_impl_20260804(uuid,text,text,text)') is null then
    if to_regprocedure('public.school_void_teacher_wage_lock(uuid,text,text,text)') is null then
      raise exception 'P0_PHASE2_REQUIRED_FUNCTION_MISSING: school_void_teacher_wage_lock';
    end if;
    alter function public.school_void_teacher_wage_lock(uuid,text,text,text)
      rename to school_void_teacher_wage_lock_admin_impl_20260804;
  end if;
end;
$block$;

alter function public.school_void_teacher_wage_lock_admin_impl_20260804(uuid,text,text,text)
  security definer set search_path = pg_catalog, public;
revoke all on function public.school_void_teacher_wage_lock_admin_impl_20260804(uuid,text,text,text)
  from public,anon,authenticated,service_role;

create or replace function public.school_void_teacher_wage_lock(
  p_wage_lock_id uuid,
  p_reason text,
  p_operator text default null,
  p_source text default 'v2_wage_detail'
)
returns table (
  wage_lock_id uuid,
  settlement_month text,
  teacher_id uuid,
  teacher_name text,
  business_entity_id uuid,
  business_name text,
  status text,
  voided_at timestamptz,
  void_reason text,
  voided_by text,
  void_source text,
  detail_count integer
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid;
begin
  v_actor := public.school_require_current_app_admin();
  if coalesce(nullif(trim(p_source),''),'v2_wage_detail') <> 'v2_wage_detail' then
    raise exception using
      errcode='22023',
      message='P0_TEACHER_WAGE_VOID_SOURCE_INVALID';
  end if;

  return query
  select *
  from public.school_void_teacher_wage_lock_admin_impl_20260804(
    p_wage_lock_id,p_reason,v_actor::text,'v2_wage_detail'
  );
end;
$function$;

revoke all on function public.school_void_teacher_wage_lock(uuid,text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_void_teacher_wage_lock(uuid,text,text,text)
  to authenticated;

-- Old interactive overloads must not bypass the current API contracts.
revoke all on function public.school_update_expense_record(
  uuid,date,uuid,uuid,text,text,text,numeric,numeric,text,text,text,text,text
) from public,anon,authenticated,service_role;
alter function public.school_update_expense_record(
  uuid,date,uuid,uuid,text,text,text,numeric,numeric,text,text,text,text,text
) set search_path = pg_catalog, public;
revoke all on function public.school_update_teacher_wage_rule_config(
  uuid,text,numeric,numeric,numeric,numeric,numeric,boolean,text
) from public,anon,authenticated,service_role;
alter function public.school_update_teacher_wage_rule_config(
  uuid,text,numeric,numeric,numeric,numeric,numeric,boolean,text
) set search_path = pg_catalog, public;

-- Deprecated teacher-wage payment-request writers have no current caller.
alter function public.school_create_teacher_wage_payment_request(uuid,date,text)
  set search_path = pg_catalog, public;
alter function public.school_request_personal_cash_payment_confirmation(uuid,uuid,text)
  set search_path = pg_catalog, public;
alter function public.school_confirm_personal_cash_payment_request(uuid,uuid,date,numeric,text)
  set search_path = pg_catalog, public;
alter function public.school_create_personal_cash_account_mapping(uuid,uuid,uuid,text,text,text)
  set search_path = pg_catalog, public;
alter function public.school_update_personal_cash_account_mapping(uuid,text,text,boolean,text)
  set search_path = pg_catalog, public;
alter function public.school_create_personal_cash_linkage_event(uuid,uuid,text)
  set search_path = pg_catalog, public;
alter function public.school_update_personal_cash_linkage_event_status(uuid,text,uuid,text)
  set search_path = pg_catalog, public;
alter function public.school_mark_personal_cash_payment_request_submitted(uuid,uuid,text)
  set search_path = pg_catalog, public;
alter function public.school_mark_personal_cash_payment_request_confirmed(uuid,uuid,uuid,timestamptz)
  set search_path = pg_catalog, public;
alter function public.school_mark_personal_cash_payment_request_rejected(uuid,uuid,text,timestamptz)
  set search_path = pg_catalog, public;
alter function public.school_fix_202605_teacher_wage_duplicate_cong_qirun()
  set search_path = pg_catalog, public;

revoke all on function public.school_create_teacher_wage_payment_request(uuid,date,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_request_personal_cash_payment_confirmation(uuid,uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_confirm_personal_cash_payment_request(uuid,uuid,date,numeric,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_create_personal_cash_account_mapping(uuid,uuid,uuid,text,text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_update_personal_cash_account_mapping(uuid,text,text,boolean,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_create_personal_cash_linkage_event(uuid,uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_update_personal_cash_linkage_event_status(uuid,text,uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_mark_personal_cash_payment_request_submitted(uuid,uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_mark_personal_cash_payment_request_confirmed(uuid,uuid,uuid,timestamptz)
  from public,anon,authenticated,service_role;
revoke all on function public.school_mark_personal_cash_payment_request_rejected(uuid,uuid,text,timestamptz)
  from public,anon,authenticated,service_role;
revoke all on function public.school_fix_202605_teacher_wage_duplicate_cong_qirun()
  from public,anon,authenticated,service_role;

-- Deprecated rejection-only RPC is retained only for its service Edge caller.
alter function public.school_request_cash_payment_confirmation(
  uuid,uuid,uuid,text,text,text,numeric,numeric,text
) set search_path = pg_catalog, public;
revoke all on function public.school_request_cash_payment_confirmation(
  uuid,uuid,uuid,text,text,text,numeric,numeric,text
) from public,anon,authenticated,service_role;
grant execute on function public.school_request_cash_payment_confirmation(
  uuid,uuid,uuid,text,text,text,numeric,numeric,text
) to service_role;

-- Canonical ordinary-expense Cash helpers stay service-role-only.
revoke all on function public.school_request_cash_expense_payment_confirmation(
  uuid,uuid,uuid,text,text,numeric,text,text,numeric,text
) from public,anon,authenticated,service_role;
grant execute on function public.school_request_cash_expense_payment_confirmation(
  uuid,uuid,uuid,text,text,numeric,text,text,numeric,text
) to service_role;
revoke all on function public.school_mark_cash_expense_request_submitted(uuid,uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_mark_cash_expense_request_submitted(uuid,uuid,text)
  to service_role;
revoke all on function public.school_mark_cash_expense_confirmed(uuid,uuid,uuid,timestamptz)
  from public,anon,authenticated,service_role;
grant execute on function public.school_mark_cash_expense_confirmed(uuid,uuid,uuid,timestamptz)
  to service_role;
revoke all on function public.school_mark_cash_expense_rejected(uuid,uuid,text,timestamptz)
  from public,anon,authenticated,service_role;
grant execute on function public.school_mark_cash_expense_rejected(uuid,uuid,text,timestamptz)
  to service_role;

-- Direct business-table writes are closed; SECURITY DEFINER RPCs remain the writers.
revoke insert,update,delete,truncate,references,trigger on table
  public.school_expense_records,
  public.school_accounts,
  public.school_account_transactions,
  public.school_expense_attachments,
  public.school_reimbursements,
  public.school_reimbursement_items,
  public.school_reimbursement_expenses,
  public.school_salary_payments,
  public.school_teacher_wage_locks,
  public.school_teacher_wage_lock_details,
  public.school_teacher_wage_detail_adjustments,
  public.school_teacher_wage_rules,
  public.school_payment_requests,
  public.school_personal_cash_account_mappings,
  public.school_personal_cash_linkage_events
from public,anon,authenticated,service_role;

alter table public.school_personal_cash_account_mappings enable row level security;
alter table public.school_personal_cash_linkage_events enable row level security;

-- Existing permissive policies become inert for writes. Separate authenticated
-- SELECT policies preserve the signed-in page read surface.
alter policy school_allow_all_expense_attachments
  on public.school_expense_attachments to authenticated
  using (false) with check (false);
alter policy school_allow_all_reimbursements
  on public.school_reimbursements to authenticated
  using (false) with check (false);
alter policy school_allow_all_reimbursement_items
  on public.school_reimbursement_items to authenticated
  using (false) with check (false);
alter policy "school reimbursement expenses insert for app users"
  on public.school_reimbursement_expenses to authenticated with check (false);
alter policy "school reimbursement expenses update for app users"
  on public.school_reimbursement_expenses to authenticated
  using (false) with check (false);
alter policy "school reimbursement expenses delete for app users"
  on public.school_reimbursement_expenses to authenticated using (false);
alter policy "school reimbursement expenses select for app users"
  on public.school_reimbursement_expenses to authenticated using (true);
alter policy school_allow_all_salary_payments
  on public.school_salary_payments to authenticated
  using (false) with check (false);
alter policy school_teacher_wage_locks_all
  on public.school_teacher_wage_locks to authenticated
  using (false) with check (false);
alter policy school_teacher_wage_lock_details_all
  on public.school_teacher_wage_lock_details to authenticated
  using (false) with check (false);
alter policy school_teacher_wage_rules_insert_all
  on public.school_teacher_wage_rules to authenticated with check (false);
alter policy school_teacher_wage_rules_update_all
  on public.school_teacher_wage_rules to authenticated
  using (false) with check (false);
alter policy school_teacher_wage_rules_delete_all
  on public.school_teacher_wage_rules to authenticated using (false);
alter policy school_teacher_wage_rules_select_all
  on public.school_teacher_wage_rules to authenticated using (true);
alter policy school_payment_requests_all
  on public.school_payment_requests to authenticated
  using (false) with check (false);

do $block$
declare
  v_table text;
  v_policy text;
begin
  foreach v_table in array array[
    'school_expense_attachments','school_reimbursements','school_reimbursement_items',
    'school_salary_payments','school_teacher_wage_locks','school_teacher_wage_lock_details',
    'school_payment_requests','school_personal_cash_account_mappings',
    'school_personal_cash_linkage_events'
  ] loop
    -- Policy names are scoped per table, so keep one short deterministic name.
    -- The semantic lookup also recognizes the longer names created by the
    -- original production run after PostgreSQL identifier truncation.
    v_policy := 'p0_phase2_authenticated_select';
    if not exists (
      select 1 from pg_policies p
      where p.schemaname='public'
        and p.tablename=v_table
        and p.cmd='SELECT'
        and p.roles::text[] @> array['authenticated']::text[]
        and p.qual='true'
    ) then
      execute format(
        'create policy %I on public.%I for select to authenticated using (true)',
        v_policy,v_table
      );
    end if;
  end loop;
end;
$block$;

-- Storage is private. Active admins may create only new objects under the
-- established expenses/YYYY-MM/<expense UUID>/<filename> prefix. Overwrite and
-- delete remain denied because no current page workflow requires them.
update storage.buckets
set public=false
where id='school-expense-files' and public is distinct from false;

alter policy school_allow_all_storage_expense_files_select
  on storage.objects to authenticated
  using (
    bucket_id='school-expense-files'
    and exists (
      select 1 from public.school_get_current_app_membership() m
      where m.role='admin' and m.is_active
    )
  );

alter policy school_allow_all_storage_expense_files_insert
  on storage.objects to authenticated
  with check (
    bucket_id='school-expense-files'
    and name ~ '^expenses/[0-9]{4}-(0[1-9]|1[0-2])/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[^/]+$'
    and exists (
      select 1 from public.school_get_current_app_membership() m
      where m.role='admin' and m.is_active
    )
    and exists (
      select 1 from public.school_expense_records e
      where e.id::text=split_part(name,'/',3)
        and e.app_type='school'
        and e.year_month=split_part(name,'/',2)
        and e.expense_category is distinct from 'teacher_wage'
    )
  );

alter policy school_allow_all_storage_expense_files_update
  on storage.objects to authenticated
  using (false) with check (false);
alter policy school_allow_all_storage_expense_files_delete
  on storage.objects to authenticated using (false);

comment on function public.school_update_expense_record(
  uuid,timestamptz,date,uuid,uuid,text,text,text,numeric,numeric,text,text,text,text,text
) is 'Active-admin ordinary expense update. school_expense_records.updated_at is the sole DB-authoritative optimistic-lock token; the old overload has no client execute privilege.';
