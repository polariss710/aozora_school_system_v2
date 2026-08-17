-- Phase 2C-C isolated role matrix. Requires local bootstrap + formal migrations.
-- All fixture writes are confined to the disposable PostgreSQL cluster.
\set ON_ERROR_STOP on

begin;
create temporary table phase2ca_assertions(label text primary key);
create function pg_temp.phase2ca_assert(p_ok boolean,p_label text)
returns void language plpgsql as $function$
begin
  if p_ok is distinct from true then raise exception 'ASSERTION_FAILED: %',p_label; end if;
  insert into phase2ca_assertions values(p_label);
end
$function$;

-- Owner-only core prepares two independent reversal candidates.
select * from public.school_create_lesson_clearance_core(
  'overtime_offset','30000000-0000-4000-8000-000000000002',
  '40000000-0000-4000-8000-000000000104',30,'2026-02-10',
  'manual_business_choice','role fixture','owner role fixture',null,
  'role-owner-reversal-1','90000000-0000-4000-8000-000000000001','owner'
) \gset owner_one_
select * from public.school_create_lesson_clearance_core(
  'overtime_offset','30000000-0000-4000-8000-000000000003',
  '40000000-0000-4000-8000-000000000103',30,'2026-02-10',
  'manual_business_choice','role fixture','owner role fixture',null,
  'role-owner-reversal-2','90000000-0000-4000-8000-000000000001','owner'
) \gset owner_two_
select set_config('school.phase2ca_owner_one_clearance_id',:'owner_one_clearance_id',true);

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000002',true);
select * from public.school_create_lesson_clearance(
  'overtime_offset','30000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000101',30,'2026-02-11',
  'manual_business_choice','operator chose non-FIFO','operator normal offset',null,
  'role-operator-normal-1'
);

do $operator_denials$
begin
  begin
    perform * from public.school_create_lesson_clearance(
      'overtime_offset','30000000-0000-4000-8000-000000000006',
      '40000000-0000-4000-8000-000000000102',30,'2026-02-11',
      null,null,'operator locked offset',null,'role-operator-locked-1');
    raise exception 'EXPECTED_OPERATOR_LOCKED_DENIAL_MISSING';
  exception when others then
    if sqlerrm='EXPECTED_OPERATOR_LOCKED_DENIAL_MISSING'
       or position('LESSON_CLEARANCE_FORWARD_ADMIN_REQUIRED' in sqlerrm)=0 then raise; end if;
  end;
  begin
    perform * from public.school_create_lesson_clearance(
      'administrative_writeoff','30000000-0000-4000-8000-000000000001',
      null,15,'2026-02-11',null,null,'operator writeoff forbidden',
      'no_refund_no_credit','role-operator-writeoff-1');
    raise exception 'EXPECTED_OPERATOR_WRITEOFF_DENIAL_MISSING';
  exception when others then
    if sqlerrm='EXPECTED_OPERATOR_WRITEOFF_DENIAL_MISSING'
       or position('LESSON_CLEARANCE_ADMIN_REQUIRED' in sqlerrm)=0 then raise; end if;
  end;
  begin
    perform * from public.school_reverse_lesson_clearance(
      current_setting('school.phase2ca_owner_one_clearance_id')::uuid,
      '2026-02-11','operator reversal forbidden',
      'role-operator-reversal-1');
    raise exception 'EXPECTED_OPERATOR_REVERSAL_DENIAL_MISSING';
  exception when others then
    if sqlerrm='EXPECTED_OPERATOR_REVERSAL_DENIAL_MISSING'
       or position('LESSON_CLEARANCE_REVERSAL_ADMIN_REQUIRED' in sqlerrm)=0 then raise; end if;
  end;
end
$operator_denials$;

select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
select * from public.school_create_lesson_clearance(
  'overtime_offset','30000000-0000-4000-8000-000000000006',
  '40000000-0000-4000-8000-000000000102',30,'2026-02-12',
  null,null,'admin locked forward offset',null,'role-admin-locked-1'
) \gset admin_locked_
select * from public.school_create_lesson_clearance(
  'administrative_writeoff','30000000-0000-4000-8000-000000000007',
  null,30,'2026-02-12',null,null,'M016 semantic fixture',
  'no_refund_no_credit','role-admin-writeoff-1'
);
select * from public.school_reverse_lesson_clearance(
  :'owner_one_clearance_id','2026-02-12','admin reversal permitted',
  'role-admin-reversal-1'
);

do $restricted_memberships$
declare v_expected text;
begin
  foreach v_expected in array array[
    'LESSON_CLEARANCE_ROLE_REQUIRED',
    'LESSON_CLEARANCE_ACTIVE_MEMBERSHIP_REQUIRED',
    'LESSON_CLEARANCE_MEMBERSHIP_REQUIRED',
    'LESSON_CLEARANCE_AUTH_REQUIRED'
  ] loop
    perform set_config('request.jwt.claim.sub',case v_expected
      when 'LESSON_CLEARANCE_ROLE_REQUIRED' then '90000000-0000-4000-8000-000000000003'
      when 'LESSON_CLEARANCE_ACTIVE_MEMBERSHIP_REQUIRED' then '90000000-0000-4000-8000-000000000004'
      when 'LESSON_CLEARANCE_MEMBERSHIP_REQUIRED' then '90000000-0000-4000-8000-000000000005'
      else '' end,true);
    begin
      perform * from public.school_create_lesson_clearance(
        'overtime_offset','30000000-0000-4000-8000-000000000001',
        '40000000-0000-4000-8000-000000000101',15,'2026-02-13',
        'manual_business_choice','restricted fixture','must reject',null,
        'role-denied-'||v_expected);
      raise exception 'EXPECTED_MEMBERSHIP_DENIAL_MISSING';
    exception when others then
      if sqlerrm='EXPECTED_MEMBERSHIP_DENIAL_MISSING'
         or position(v_expected in sqlerrm)=0 then raise; end if;
    end;
  end loop;
end
$restricted_memberships$;
reset role;

select pg_temp.phase2ca_assert(:'admin_locked_requires_forward_adjustment'::boolean,
  'active admin may create locked forward adjustment');
select pg_temp.phase2ca_assert(
  has_function_privilege('authenticated',
    'public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)',
    'EXECUTE'),
  'authenticated wrapper execute granted');
select pg_temp.phase2ca_assert(not has_function_privilege('anon',
    'public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)',
    'EXECUTE'),
  'anon writer execute revoked');
select pg_temp.phase2ca_assert(not has_function_privilege('service_role',
    'public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)',
    'EXECUTE'),
  'service_role writer execute revoked');
select pg_temp.phase2ca_assert(
  not has_table_privilege('authenticated','public.school_lesson_clearances','INSERT')
  and not has_table_privilege('authenticated','public.school_lesson_clearance_details','UPDATE')
  and not has_table_privilege('service_role','public.school_student_package_credit_lots','DELETE'),
  'application roles have zero table DML');
select pg_temp.phase2ca_assert(
  has_function_privilege('authenticated',
    'public.school_suggest_lesson_clearance_targets(uuid)','EXECUTE')
  and has_function_privilege('authenticated',
    'public.school_list_student_package_credit_lots(uuid)','EXECUTE'),
  'authenticated read-only readers granted');
set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000003',true);
select set_config('school.phase2cc_read_only_reader_ok',(
  (select count(*)>=0 from public.school_list_lesson_clearance_pending_balances(null,false))
  and (select count(*)>=0 from public.school_list_lesson_clearance_available_overages(null,false))
)::text,true);
reset role;
select pg_temp.phase2ca_assert(
  current_setting('school.phase2cc_read_only_reader_ok')::boolean,
  'active read_only membership may execute clearance readers');

select count(*) as passed_role_assertions from phase2ca_assertions;
rollback;
