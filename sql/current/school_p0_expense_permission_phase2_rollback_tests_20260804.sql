-- School V2 ordinary expense permission P0 phase 2 production rollback matrix.
\set ON_ERROR_STOP on
\pset pager off

begin;

create function pg_temp.p0_phase2_interactive_calls()
returns text[]
language sql
immutable
as $function$
  select array[
    'select * from public.school_update_expense_record(null::uuid,null::timestamptz,null::date,null::uuid,null::uuid,null::text,null::text,null::text,null::numeric,null::numeric,null::text,null::text,null::text,null::text,null::text)',
    'select * from public.school_reverse_expense_record(null::uuid,null::date,null::text)',
    'select * from public.school_create_reimbursement_record(null::date,null::uuid,null::uuid,null::uuid,null::uuid[],null::text)',
    'select * from public.school_reverse_reimbursement_record(null::uuid,null::date,null::text)',
    'select * from public.school_create_expense_attachment_metadata(null::uuid,null::text,null::text,null::bigint,null::text,null::text)',
    'select * from public.school_generate_teacher_monthly_wage(null::text,null::uuid,null::uuid)',
    'select * from public.school_generate_teacher_monthly_wage(null::text,null::uuid)',
    'select * from public.school_adjust_teacher_wage_detail(null::uuid,null::numeric,null::numeric,null::numeric,null::text)',
    'select * from public.school_create_teacher_wage_expense_record(null::uuid,null::date,null::text)',
    'select * from public.school_void_unsubmitted_teacher_wage_expense_record(null::uuid,null::text)',
    'select * from public.school_void_teacher_wage_lock(null::uuid,null::text,null::text,null::text)',
    'select * from public.school_create_teacher_wage_rule_config(null::uuid,null::uuid,null::uuid,null::uuid,null::text,null::numeric,null::numeric,null::numeric,null::numeric,null::numeric,null::boolean,null::text)',
    'select * from public.school_update_teacher_wage_rule_config(null::uuid,null::uuid,null::uuid,null::uuid,null::uuid,null::text,null::numeric,null::numeric,null::numeric,null::numeric,null::numeric,null::boolean,null::text)',
    'select * from public.school_set_teacher_wage_rule_active_state(null::uuid,null::boolean,null::text)',
    'select * from public.school_confirm_payment_request(null::uuid,null::uuid,null::date,null::numeric,null::text,null::text)',
    'select * from public.school_reverse_paid_payment_request(null::uuid,null::text,null::date)',
    'select * from public.school_cancel_payment_request(null::uuid,null::text)',
    'select * from public.school_restore_cancelled_payment_request(null::uuid)',
    'select * from public.school_reissue_reversed_payment_request(null::uuid,null::text)'
  ];
$function$;

create function pg_temp.p0_phase2_assert_denied(p_sql text,p_message_pattern text)
returns void
language plpgsql
as $function$
begin
  begin
    execute p_sql;
    raise exception 'P0_PHASE2_EXPECTED_DENIAL_MISSING';
  exception when others then
    if sqlerrm='P0_PHASE2_EXPECTED_DENIAL_MISSING' then
      raise;
    end if;
    if sqlstate <> '42501' or sqlerrm not like p_message_pattern then
      raise exception 'P0_PHASE2_UNEXPECTED_DENIAL [%] % for %',sqlstate,sqlerrm,p_sql;
    end if;
  end;
end;
$function$;

create function pg_temp.p0_phase2_assert_reaches_business(p_sql text)
returns void
language plpgsql
as $function$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate='42501' then
      raise exception 'P0_PHASE2_ACTIVE_ADMIN_BLOCKED [%] % for %',sqlstate,sqlerrm,p_sql;
    end if;
  end;
end;
$function$;

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
      raise exception 'P0_PHASE2_INTERACTIVE_CONTRACT_FAILED: %',v_signature;
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
       or has_function_privilege('service_role',v_oid,'EXECUTE') then
      raise exception 'P0_PHASE2_OWNER_ONLY_CONTRACT_FAILED: %',v_signature;
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
       or not has_function_privilege('service_role',v_oid,'EXECUTE') then
      raise exception 'P0_PHASE2_SERVICE_HELPER_CONTRACT_FAILED: %',v_signature;
    end if;
  end loop;
end;
$block$;

select user_id as p0_admin_id
from public.school_app_memberships
where role='admin' and is_active
order by created_at
limit 1
\gset
select set_config('p0_phase2.admin_id',:'p0_admin_id',true);

-- anon: every interactive writer is denied at ACL before business work.
set local role anon;
do $block$
declare v_sql text;
begin
  foreach v_sql in array pg_temp.p0_phase2_interactive_calls() loop
    perform pg_temp.p0_phase2_assert_denied(v_sql,'%permission denied for function%');
  end loop;
end;
$block$;
reset role;

-- service_role cannot borrow interactive writers.
set local role service_role;
do $block$
declare v_sql text;
begin
  foreach v_sql in array pg_temp.p0_phase2_interactive_calls() loop
    perform pg_temp.p0_phase2_assert_denied(v_sql,'%permission denied for function%');
  end loop;
end;
$block$;
reset role;

-- no membership authenticated.
select set_config('request.jwt.claims','{"sub":"98000000-0000-4000-8000-000000000099","role":"authenticated"}',true);
set local role authenticated;
do $block$
declare v_sql text;
begin
  foreach v_sql in array pg_temp.p0_phase2_interactive_calls() loop
    perform pg_temp.p0_phase2_assert_denied(v_sql,'P0G1_ACTIVE_ADMIN_REQUIRED');
  end loop;
end;
$block$;
reset role;

-- inactive admin, operator, and read_only.
update public.school_app_memberships set role='admin',is_active=false where user_id=:'p0_admin_id'::uuid;
select set_config('request.jwt.claims',format('{"sub":"%s","role":"authenticated"}',:'p0_admin_id'),true);
set local role authenticated;
do $block$
declare v_sql text;
begin
  foreach v_sql in array pg_temp.p0_phase2_interactive_calls() loop
    perform pg_temp.p0_phase2_assert_denied(v_sql,'P0G1_ACTIVE_ADMIN_REQUIRED');
  end loop;
end;
$block$;
reset role;

update public.school_app_memberships set role='operator',is_active=true where user_id=:'p0_admin_id'::uuid;
set local role authenticated;
do $block$
declare v_sql text;
begin
  foreach v_sql in array pg_temp.p0_phase2_interactive_calls() loop
    perform pg_temp.p0_phase2_assert_denied(v_sql,'P0G1_ACTIVE_ADMIN_REQUIRED');
  end loop;
end;
$block$;
reset role;

update public.school_app_memberships set role='read_only',is_active=true where user_id=:'p0_admin_id'::uuid;
set local role authenticated;
do $block$
declare v_sql text;
begin
  foreach v_sql in array pg_temp.p0_phase2_interactive_calls() loop
    perform pg_temp.p0_phase2_assert_denied(v_sql,'P0G1_ACTIVE_ADMIN_REQUIRED');
  end loop;
end;
$block$;
reset role;

-- Restore active admin inside the transaction; every function reaches its own
-- business validation instead of an auth/ACL denial.
update public.school_app_memberships set role='admin',is_active=true where user_id=:'p0_admin_id'::uuid;
set local role authenticated;
do $block$
declare v_sql text;
begin
  foreach v_sql in array pg_temp.p0_phase2_interactive_calls() loop
    perform pg_temp.p0_phase2_assert_reaches_business(v_sql);
  end loop;
end;
$block$;
reset role;

-- Minimal rollback-only business fixtures.
select id as p0_business_id,name as p0_business_name
from public.school_business_entities
where is_active
order by created_at
limit 1
\gset
select set_config('p0_phase2.business_id',:'p0_business_id',true);
select id as p0_teacher_id,name as p0_teacher_name
from public.school_teachers
where coalesce(app_type,'')='school'
order by created_at
limit 1
\gset
select set_config('p0_phase2.teacher_id',:'p0_teacher_id',true);

insert into public.school_accounts(
 id,business_entity_id,name,account_type,currency,opening_balance,current_balance,
 is_company_account,is_active,app_type
) values
 ('98000000-0000-4000-8000-000000000101',:'p0_business_id','codex-test p0p2 update','cash','JPY',1000,900,true,true,'school'),
 ('98000000-0000-4000-8000-000000000102',:'p0_business_id','codex-test p0p2 reverse','cash','JPY',1000,900,true,true,'school'),
 ('98000000-0000-4000-8000-000000000103',:'p0_business_id','codex-test p0p2 reimb out','cash','JPY',1000,1000,true,true,'school'),
 ('98000000-0000-4000-8000-000000000104',:'p0_business_id','codex-test p0p2 reimb in','cash','JPY',0,0,false,true,'school');

insert into public.school_expense_records(
 id,business_entity_id,account_id,expense_date,year_month,expense_category,
 description,currency,amount,amount_jpy,payment_method,status,receipt_status,
 reimbursement_status,app_type,updated_at
) values
 ('98000000-0000-4000-8000-000000000201',:'p0_business_id','98000000-0000-4000-8000-000000000101','2026-08-01','2026-08','other','codex-test p0p2 update','JPY',100,100,'bank_transfer','paid','待确认','pending','school',clock_timestamp()-interval '1 minute'),
 ('98000000-0000-4000-8000-000000000202',:'p0_business_id','98000000-0000-4000-8000-000000000102','2026-08-01','2026-08','other','codex-test p0p2 reverse','JPY',100,100,'bank_transfer','paid','待确认','pending','school',clock_timestamp()-interval '1 minute'),
 ('98000000-0000-4000-8000-000000000203',:'p0_business_id',null,'2026-08-01','2026-08','other','codex-test p0p2 reimbursement','JPY',100,100,'bank_transfer','paid','待确认','pending','school',clock_timestamp()-interval '1 minute');

insert into public.school_account_transactions(
 id,account_id,business_entity_id,transaction_date,year_month,transaction_type,
 related_table,related_id,currency,amount,balance_after,description,app_type
) values
 ('98000000-0000-4000-8000-000000000301','98000000-0000-4000-8000-000000000101',:'p0_business_id','2026-08-01','2026-08','expense_adjust','school_expense_records','98000000-0000-4000-8000-000000000201','JPY',-100,900,'codex-test p0p2 update','school'),
 ('98000000-0000-4000-8000-000000000302','98000000-0000-4000-8000-000000000102',:'p0_business_id','2026-08-01','2026-08','expense_adjust','school_expense_records','98000000-0000-4000-8000-000000000202','JPY',-100,900,'codex-test p0p2 reverse','school');

insert into public.school_teacher_wage_locks(
 id,settlement_month,teacher_id,teacher_name,business_entity_id,business_name,
 settlement_type,exchange_rate,total_minutes,pay_hours,lesson_wage_jpy,
 lesson_wage_cny,fee_jpy,total_jpy,total_cny,lesson_count,status,locked_at
) values (
 '98000000-0000-4000-8000-000000000401','2026-08',:'p0_teacher_id',:'p0_teacher_name',
 :'p0_business_id',:'p0_business_name','jpy_hourly',0,60,1,100,0,0,100,0,1,'locked',clock_timestamp()
);
insert into public.school_teacher_wage_lock_details(
 id,lock_id,business_entity_id,business_name,pay_hours,lesson_wage_jpy,
 lesson_wage_cny,transport_fee_jpy,classroom_fee_jpy,total_jpy,total_cny,
 settlement_type,exchange_rate,is_no_wage,status
) values (
 '98000000-0000-4000-8000-000000000402','98000000-0000-4000-8000-000000000401',
 :'p0_business_id',:'p0_business_name',1,100,0,0,0,100,0,'jpy_hourly',0,false,'completed'
);

select set_config('request.jwt.claims',format('{"sub":"%s","role":"authenticated"}',:'p0_admin_id'),true);
set local role authenticated;
do $block$
declare
  v_expected timestamptz;
  v_reimbursement_id uuid;
  v_wage_expense_id uuid;
begin
  select updated_at into v_expected
  from public.school_expense_records
  where id='98000000-0000-4000-8000-000000000201';

  perform public.school_update_expense_record(
    '98000000-0000-4000-8000-000000000201',v_expected,'2026-08-01',
    current_setting('p0_phase2.business_id')::uuid,'98000000-0000-4000-8000-000000000101','other',
    'codex-test p0p2 updated','JPY',110,null,'bank_transfer',null,'待确认','pending','codex-test'
  );
  begin
    perform public.school_update_expense_record(
      '98000000-0000-4000-8000-000000000201',v_expected,'2026-08-01',
      current_setting('p0_phase2.business_id')::uuid,'98000000-0000-4000-8000-000000000101','other',
      'codex-test stale','JPY',120,null,'bank_transfer',null,'待确认','pending','codex-test'
    );
    raise exception 'P0_PHASE2_STALE_UPDATE_WAS_NOT_REJECTED';
  exception when serialization_failure then
    if sqlerrm <> 'P0_EXPENSE_UPDATE_STALE_VERSION' then raise; end if;
  end;

  perform public.school_reverse_expense_record(
    '98000000-0000-4000-8000-000000000202','2026-08-04','codex-test p0p2 reverse'
  );
  begin
    perform public.school_reverse_expense_record(
      '98000000-0000-4000-8000-000000000202','2026-08-04','codex-test duplicate'
    );
    raise exception 'P0_PHASE2_DUPLICATE_REVERSE_WAS_NOT_REJECTED';
  exception when others then
    if sqlerrm='P0_PHASE2_DUPLICATE_REVERSE_WAS_NOT_REJECTED' then raise; end if;
  end;

  select reimbursement_id into v_reimbursement_id
  from public.school_create_reimbursement_record(
    '2026-08-04',current_setting('p0_phase2.business_id')::uuid,'98000000-0000-4000-8000-000000000103',
    '98000000-0000-4000-8000-000000000104',
    array['98000000-0000-4000-8000-000000000203'::uuid],
    'codex-test p0p2 reimbursement'
  );
  perform public.school_reverse_reimbursement_record(
    v_reimbursement_id,'2026-08-04','codex-test p0p2 reimbursement reverse'
  );
  begin
    perform public.school_reverse_reimbursement_record(
      v_reimbursement_id,'2026-08-04','codex-test duplicate'
    );
    raise exception 'P0_PHASE2_DUPLICATE_REIMBURSEMENT_REVERSE_NOT_REJECTED';
  exception when others then
    if sqlerrm='P0_PHASE2_DUPLICATE_REIMBURSEMENT_REVERSE_NOT_REJECTED' then raise; end if;
  end;

  perform public.school_create_expense_attachment_metadata(
    '98000000-0000-4000-8000-000000000201','codex-test-p0p2.txt','text/plain',8,
    'manual_metadata','codex-test p0p2'
  );
  begin
    perform public.school_create_expense_attachment_metadata(
      '98000000-0000-4000-8000-000000000201','codex-test-p0p2.txt','text/plain',8,
      'manual_metadata','codex-test p0p2'
    );
    raise exception 'P0_PHASE2_DUPLICATE_ATTACHMENT_NOT_REJECTED';
  exception when unique_violation then
    if sqlerrm <> 'P0_EXPENSE_ATTACHMENT_METADATA_DUPLICATE' then raise; end if;
  end;

  select expense_id into v_wage_expense_id
  from public.school_create_teacher_wage_expense_record(
    '98000000-0000-4000-8000-000000000401','2026-08-31','codex-test p0p2 wage'
  );
  perform public.school_void_unsubmitted_teacher_wage_expense_record(
    v_wage_expense_id,'codex-test p0p2 wage expense void'
  );
  perform public.school_void_teacher_wage_lock(
    '98000000-0000-4000-8000-000000000401','codex-test p0p2 wage void',
    'spoofed-client-operator','v2_wage_detail'
  );

  if not exists (
    select 1 from public.school_teacher_wage_locks w
    where w.id='98000000-0000-4000-8000-000000000401'
      and w.status='void'
      and w.voided_by=current_setting('p0_phase2.admin_id')
      and w.void_source='v2_wage_detail'
  ) then
    raise exception 'P0_PHASE2_WAGE_VOID_AUDIT_AUTHORITY_FAILED';
  end if;
end;
$block$;
reset role;

select 'P0_PHASE2_ROLLBACK_MATRIX_PASS' as result;
rollback;

select count(*) as residue_count
from (
  select id from public.school_accounts where id::text like '98000000-0000-4000-8000-0000000001%'
  union all select id from public.school_expense_records where id::text like '98000000-0000-4000-8000-0000000002%'
  union all select id from public.school_account_transactions where id::text like '98000000-0000-4000-8000-0000000003%'
  union all select id from public.school_teacher_wage_locks where id::text like '98000000-0000-4000-8000-0000000004%'
) residue;
