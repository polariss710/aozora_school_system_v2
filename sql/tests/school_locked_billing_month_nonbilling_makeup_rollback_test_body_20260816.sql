-- Caller owns the transaction. All c816... fixtures must be rolled back.
do $fixture_preflight$
begin
  if exists(select 1 from auth.users where id::text like 'c8160000-%')
     or exists(select 1 from public.school_lesson_records where id::text like 'c8160000-%')
     or exists(select 1 from public.school_students where id::text like 'c8160000-%') then
    raise exception 'LOCKED_MAKEUP_FIXTURE_COLLISION';
  end if;
end;
$fixture_preflight$;

insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
 ('c8160000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"locked-makeup-admin"}',now(),now()),
 ('c8160000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"locked-makeup-operator"}',now(),now()),
 ('c8160000-0000-4000-8000-000000000003','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"locked-makeup-read-only"}',now(),now()),
 ('c8160000-0000-4000-8000-000000000004','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"locked-makeup-inactive"}',now(),now()),
 ('c8160000-0000-4000-8000-000000000006','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"locked-makeup-no-membership"}',now(),now());

insert into public.school_app_memberships(
 user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values
 ('c8160000-0000-4000-8000-000000000001','admin',true,'c8160000-0000-4000-8000-000000000001','c8160000-0000-4000-8000-000000000001','codex-test locked makeup'),
 ('c8160000-0000-4000-8000-000000000002','operator',true,'c8160000-0000-4000-8000-000000000001','c8160000-0000-4000-8000-000000000001','codex-test locked makeup'),
 ('c8160000-0000-4000-8000-000000000003','read_only',true,'c8160000-0000-4000-8000-000000000001','c8160000-0000-4000-8000-000000000001','codex-test locked makeup'),
 ('c8160000-0000-4000-8000-000000000004','admin',false,'c8160000-0000-4000-8000-000000000001','c8160000-0000-4000-8000-000000000001','codex-test locked makeup');

insert into public.school_subjects(id,name,category,is_active,note,primary_category)
values('c8160000-0000-4000-8000-00000000d001','codex-test locked makeup subject','codex-test',true,'codex-test locked makeup','班课');
insert into public.school_teachers(
 id,teacher_code,name,display_name,default_subject_id,default_business_entity_id,status,note,app_type
) values(
 'c8160000-0000-4000-8000-000000007001','codex-locked-makeup','codex-test locked makeup teacher',
 'codex-test locked makeup teacher','c8160000-0000-4000-8000-00000000d001',
 public.school_primary_business_entity_id(),'active','codex-test locked makeup','school');
insert into public.school_students(
 id,student_code,name,display_name,business_entity_id,status,app_type,
 preset_exchange_rate,previous_balance_cny,note
) values(
 'c8160000-0000-4000-8000-00000000a001','codex-locked-makeup','codex-test locked makeup student',
 'codex-test locked makeup student',public.school_primary_business_entity_id(),
 'active','school',0.05,0,'codex-test locked makeup');

insert into public.school_lesson_records(
 id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
 business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
 is_billable,app_type,unit_price,lesson_fee,lesson_count,
 lesson_delivery_mode,lesson_venue,note
) values
 ('c8160000-0000-4000-8000-000000001101','planned','2020-01-06','2020-01','c8160000-0000-4000-8000-00000000a001','c8160000-0000-4000-8000-000000007001','c8160000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','11:00',2,'allowed locked makeup','pending_makeup',true,'school',1000,2000,1,'online','Zoom','codex-test locked makeup'),
 ('c8160000-0000-4000-8000-000000001102','planned','2020-01-07','2020-01','c8160000-0000-4000-8000-00000000a001','c8160000-0000-4000-8000-000000007001','c8160000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','11:00',2,'ordinary locked reject','planned',true,'school',1000,2000,1,'online','Zoom','codex-test locked makeup'),
 ('c8160000-0000-4000-8000-000000001103','planned','2020-01-10','2020-01','c8160000-0000-4000-8000-00000000a001','c8160000-0000-4000-8000-000000007001','c8160000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','11:00',2,'early date reject','pending_makeup',true,'school',1000,2000,1,'online','Zoom','codex-test locked makeup'),
 ('c8160000-0000-4000-8000-000000001104','planned','2020-01-12','2020-01','c8160000-0000-4000-8000-00000000a001','c8160000-0000-4000-8000-000000007001','c8160000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','11:00',2,'insufficient balance','pending_makeup',true,'school',1000,2000,1,'online','Zoom','codex-test locked makeup'),
 ('c8160000-0000-4000-8000-000000001105','planned','2020-01-31','2020-01','c8160000-0000-4000-8000-00000000a001','c8160000-0000-4000-8000-000000007001','c8160000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','11:00',2,'wage locked reject','pending_makeup',true,'school',1000,2000,1,'online','Zoom','codex-test locked makeup'),
 ('c8160000-0000-4000-8000-000000001106','planned','2020-01-15','2020-01','c8160000-0000-4000-8000-00000000a001','c8160000-0000-4000-8000-000000007001','c8160000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','11:00',2,'billable flag reject','pending_makeup',true,'school',1000,2000,1,'online','Zoom','codex-test locked makeup'),
 ('c8160000-0000-4000-8000-000000001107','planned','2020-01-16','2020-01','c8160000-0000-4000-8000-00000000a001','c8160000-0000-4000-8000-000000007001','c8160000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','11:00',2,'nonzero fee reject','pending_makeup',true,'school',1000,2000,1,'online','Zoom','codex-test locked makeup');

set local session_replication_role='replica';
insert into public.school_student_monthly_settlements(
 id,student_id,year_month,business_entity_id,carryover_amount_cny,
 settlement_status,locked_at,note
) values(
 'c8160000-0000-4000-8000-00000000b001','c8160000-0000-4000-8000-00000000a001','2020-01',
 public.school_primary_business_entity_id(),0,'locked',now(),'codex-test locked makeup');
set local session_replication_role='origin';

insert into public.school_teacher_wage_locks(
 id,settlement_month,teacher_id,teacher_name,business_entity_id,business_name,
 settlement_type,exchange_rate,total_minutes,pay_hours,lesson_wage_jpy,
 lesson_wage_cny,fee_jpy,total_jpy,total_cny,lesson_count,status,locked_at
) values(
 'c8160000-0000-4000-8000-000000007101','2020-02','c8160000-0000-4000-8000-000000007001',
 'codex-test locked makeup teacher',public.school_primary_business_entity_id(),
 'codex-test entity','jpy_hourly',0,60,1,1000,0,0,1000,0,1,'locked',now());

create temp table r2_makeup_writer_return on commit drop as
select * from public.school_lesson_records with no data;
alter table r2_makeup_writer_return owner to authenticated;

-- ACL and membership matrix; no call is allowed to reach row creation.
set local role anon;
do $anon$
begin
  begin
    perform * from public.school_create_lesson_credit_makeup_actual(
      'c8160000-0000-4000-8000-000000001101','2020-01-07',null,null,'09:00','11:00',2,'x',null,1,'online','Zoom');
    raise exception 'LOCKED_MAKEUP_ANON_ALLOWED';
  exception when insufficient_privilege then null; end;
end;
$anon$;
reset role;

set local role service_role;
do $service$
begin
  begin
    perform * from public.school_create_lesson_credit_makeup_actual(
      'c8160000-0000-4000-8000-000000001101','2020-01-07',null,null,'09:00','11:00',2,'x',null,1,'online','Zoom');
    raise exception 'LOCKED_MAKEUP_SERVICE_ALLOWED';
  exception when insufficient_privilege then null; end;
end;
$service$;
reset role;

set local role authenticated;
do $membership$
declare v_actor uuid; v_expected text; v_message text;
begin
  for v_actor,v_expected in select * from (values
    ('c8160000-0000-4000-8000-000000000003'::uuid,'LESSON_WRITER_ROLE_REQUIRED'),
    ('c8160000-0000-4000-8000-000000000004'::uuid,'LESSON_WRITER_ACTIVE_MEMBERSHIP_REQUIRED'),
    ('c8160000-0000-4000-8000-000000000006'::uuid,'LESSON_WRITER_MEMBERSHIP_REQUIRED'),
    (null::uuid,'LESSON_WRITER_AUTH_REQUIRED')) x(actor,expected)
  loop
    perform set_config('request.jwt.claims',case when v_actor is null
      then '{"role":"authenticated"}'
      else jsonb_build_object('sub',v_actor,'role','authenticated')::text end,true);
    v_message:=null;
    begin
      perform * from public.school_create_lesson_credit_makeup_actual(
        'c8160000-0000-4000-8000-000000001101','2020-01-07',null,null,'09:00','11:00',2,'x',null,1,'online','Zoom');
    exception when others then v_message:=sqlerrm; end;
    if position(v_expected in coalesce(v_message,''))=0 then
      raise exception 'LOCKED_MAKEUP_MEMBERSHIP_MATRIX:%:%',v_expected,v_message;
    end if;
  end loop;
  foreach v_actor in array array[
    'c8160000-0000-4000-8000-000000000001'::uuid,
    'c8160000-0000-4000-8000-000000000002'::uuid]
  loop
    perform set_config('request.jwt.claims',
      jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    begin
      perform * from public.school_create_lesson_credit_makeup_actual(
        '00000000-0000-4000-8000-000000000000','2020-01-02',null,null,'09:00','11:00',2,'x',null,1,'online','Zoom');
    exception when others then
      if position('LESSON_MAKEUP_SOURCE_NOT_FOUND' in sqlerrm)=0 then raise; end if;
    end;
  end loop;
end;
$membership$;

select set_config('request.jwt.claims',
  '{"sub":"c8160000-0000-4000-8000-000000000001","role":"authenticated"}',true);

do $negative_matrix$
declare v_message text;
begin
  begin
    perform * from public.school_create_actual_lesson_from_planned(
      'c8160000-0000-4000-8000-000000001102','2020-01-07','09:00','11:00',2,1000,null,1,'ordinary','codex-test');
  exception when others then
    get stacked diagnostics v_message=message_text;
  end;
  if v_message is distinct from '目标学生月度结算已锁定，不能生成 actual。' then
    raise exception 'ORDINARY_LOCK_ASSERTION_FAILED:%',coalesce(v_message,'NO_EXCEPTION');
  end if;

  begin
    perform * from public.school_create_lesson_credit_makeup_actual(
      'c8160000-0000-4000-8000-000000001103','2020-01-09',null,null,'09:00','11:00',2,'early',null,1,'online','Zoom');
    raise exception 'EARLY_MAKEUP_ALLOWED';
  exception when sqlstate '22023' then
    get stacked diagnostics v_message=message_text;
    if v_message<>'LESSON_MAKEUP_DATE_BEFORE_SOURCE' then raise; end if;
  end;

  begin
    perform * from public.school_create_lesson_credit_makeup_actual(
      'c8160000-0000-4000-8000-000000001104','2020-01-13',null,null,'09:00','12:00',3,'too long',null,1,'online','Zoom');
    raise exception 'MAKEUP_OVER_BALANCE_ALLOWED';
  exception when others then
    get stacked diagnostics v_message=message_text;
    if v_message<>'LESSON_MAKEUP_CREDIT_EXCEEDED' then raise; end if;
  end;

  begin
    perform * from public.school_create_lesson_credit_makeup_actual(
      'c8160000-0000-4000-8000-000000001105','2020-02-01',null,null,'09:00','11:00',2,'wage locked',null,1,'online','Zoom');
    raise exception 'WAGE_LOCKED_MAKEUP_ALLOWED';
  exception when others then
    get stacked diagnostics v_message=message_text;
    if v_message<>'LESSON_MAKEUP_TEACHER_WAGE_LOCKED' then raise; end if;
  end;

end;
$negative_matrix$;

-- A. Writer return contract under authenticated admin.
insert into r2_makeup_writer_return
select * from public.school_create_lesson_credit_makeup_actual(
    'c8160000-0000-4000-8000-000000001101','2020-01-07',
    'c8160000-0000-4000-8000-000000007001','c8160000-0000-4000-8000-00000000d001',
    '09:00','11:00',2,'allowed locked fee-zero makeup','codex-test locked makeup',1,'online','Zoom');
select 'A_writer_return' assertion,count(*) row_count,min(id::text)::uuid returned_uuid,
       jsonb_agg(to_jsonb(r)) returned_rows from r2_makeup_writer_return r;

do $repeat_rejected$
declare v_message text;
begin
  begin
    perform * from public.school_create_lesson_credit_makeup_actual(
      'c8160000-0000-4000-8000-000000001101','2020-01-08',null,null,'09:00','11:00',2,'repeat',null,1,'online','Zoom');
  exception when others then
    get stacked diagnostics v_message=message_text;
  end;
  if v_message is distinct from 'LESSON_MAKEUP_CREDIT_EXHAUSTED' then
    raise exception 'EXHAUSTED_MAKEUP_ASSERTION_FAILED:%',coalesce(v_message,'NO_EXCEPTION');
  end if;
end;
$repeat_rejected$;
reset role;

-- B. Owner storage contract: precise UUID read plus field-diff evidence.
with actual as (
  select jsonb_build_object(
    'id',a.id,'planned_lesson_id',a.planned_lesson_id,'student_id',a.student_id,
    'teacher_id',a.teacher_id,'subject_id',a.subject_id,
    'business_entity_id',a.business_entity_id,'lesson_date',a.lesson_date,
    'start_time',a.start_time,'end_time',a.end_time,'actual_minutes',a.actual_minutes,
    'duration_hours',a.duration_hours,'status',a.status,'is_billable',a.is_billable,
    'lesson_fee',a.lesson_fee,'student_settlement_month',a.student_settlement_month,
    'teacher_settlement_month',a.teacher_settlement_month,'lesson_content',a.lesson_content,
    'voided_at',a.voided_at,'void_reason',a.void_reason,
    'created_at_present',a.created_at is not null,'updated_at_present',a.updated_at is not null
  ) facts from public.school_lesson_records a
  where a.id=(select id from r2_makeup_writer_return)
), expected as (
  select jsonb_build_object(
    'id',(select id from r2_makeup_writer_return),
    'planned_lesson_id','c8160000-0000-4000-8000-000000001101'::uuid,
    'student_id','c8160000-0000-4000-8000-00000000a001'::uuid,
    'teacher_id','c8160000-0000-4000-8000-000000007001'::uuid,
    'subject_id','c8160000-0000-4000-8000-00000000d001'::uuid,
    'business_entity_id',public.school_primary_business_entity_id(),
    'lesson_date','2020-01-07'::date,'start_time','09:00','end_time','11:00',
    'actual_minutes',120,'duration_hours',2::numeric,'status','makeup_completed',
    'is_billable',false,'lesson_fee',0::numeric,'student_settlement_month','2020-01',
    'teacher_settlement_month','2020-01','lesson_content','allowed locked fee-zero makeup',
    'voided_at',null,'void_reason',null,'created_at_present',true,'updated_at_present',true
  ) facts
), diff as (
  select coalesce(jsonb_object_agg(e.key,jsonb_build_object('expected',e.value,'actual',a.value))
    filter(where a.value is distinct from e.value),'{}'::jsonb) fields
  from expected x cross join actual y cross join lateral jsonb_each(x.facts) e
  left join lateral jsonb_each(y.facts) a on a.key=e.key
)
select 'B_owner_storage' assertion,(select facts from actual) actual,
       (select facts from expected) expected,(select fields from diff) field_diff,
       public.school_get_lesson_credit_remaining_hours(
         'c8160000-0000-4000-8000-000000001101'::uuid) remaining_hours;

do $owner_storage_assert$
begin
  if (select count(*) from r2_makeup_writer_return)<>1
     or not exists(select 1 from public.school_lesson_records a
       where a.id=(select id from r2_makeup_writer_return)
         and a.planned_lesson_id='c8160000-0000-4000-8000-000000001101'::uuid
         and a.student_id='c8160000-0000-4000-8000-00000000a001'::uuid
         and a.teacher_id='c8160000-0000-4000-8000-000000007001'::uuid
         and a.subject_id='c8160000-0000-4000-8000-00000000d001'::uuid
         and a.lesson_date='2020-01-07' and a.start_time='09:00' and a.end_time='11:00'
         and a.actual_minutes=120 and a.duration_hours=2
         and a.status='makeup_completed' and not a.is_billable and a.lesson_fee=0
         and a.student_settlement_month='2020-01' and a.teacher_settlement_month='2020-01'
         and a.lesson_content='allowed locked fee-zero makeup'
         and a.voided_at is null and a.void_reason is null
         and a.created_at is not null and a.updated_at is not null)
     or public.school_get_lesson_credit_remaining_hours(
       'c8160000-0000-4000-8000-000000001101'::uuid)<>0 then
    raise exception 'LOCKED_NONBILLING_MAKEUP_OWNER_STORAGE_INVALID';
  end if;
end;
$owner_storage_assert$;

-- C. Existing client visibility: table SELECT/RLS and the page list reader.
set local role authenticated;
select 'C_authenticated_direct_select' assertion,count(*) visible_rows
from public.school_lesson_records a where a.id=(select id from r2_makeup_writer_return);
select 'C_authenticated_reader' assertion,count(*) visible_rows
from public.school_list_lesson_management_records_authoritative('2020-01',null) r
where r.id=(select id from r2_makeup_writer_return);
do $client_visibility_assert$
begin
  if (select count(*) from public.school_lesson_records a
      where a.id=(select id from r2_makeup_writer_return))<>1
     or (select count(*) from public.school_list_lesson_management_records_authoritative(
       '2020-01',null) r where r.id=(select id from r2_makeup_writer_return))<>1 then
    raise exception 'LOCKED_NONBILLING_MAKEUP_CLIENT_VISIBILITY_INVALID';
  end if;
end;
$client_visibility_assert$;
reset role;

-- Owner-only trigger probe: browser roles intentionally lack table INSERT.
-- The contradictory fee=1 case is judged by the final stored fact and all
-- downstream objects, because the DB may authoritatively normalize it to zero.
create temp table r3_fee_normalization_result(
  input_is_billable boolean,input_lesson_fee numeric,returned_id uuid,
  returned_is_billable boolean,returned_lesson_fee numeric,
  owner_is_billable boolean,owner_lesson_fee numeric,owner_status text,
  remaining_hours numeric
) on commit drop;

create temp table r3_fee_downstream_before on commit drop as
select * from (
  select 'settlements' object_name,count(*) row_count,
    md5(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)::text) row_hash
    from public.school_student_monthly_settlements x
  union all select 'bills',count(*),md5(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)::text)
    from public.school_student_tuition_bills x
  union all select 'bill_lessons',count(*),md5(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)::text)
    from public.school_student_tuition_bill_lessons x
  union all select 'revisions',count(*),md5(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)::text)
    from public.school_student_tuition_generation_revisions x
  union all select 'income',count(*),md5(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)::text)
    from public.school_income_records x
  union all select 'cash_links',count(*),md5(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)::text)
    from public.school_personal_cash_income_linkage_events x
  union all select 'wage_locks',count(*),md5(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)::text)
    from public.school_teacher_wage_locks x
  union all select 'wage_details',count(*),md5(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)::text)
    from public.school_teacher_wage_lock_details x
) snapshot;

select 'R3_RELATED_TRIGGER_ORDER' evidence,
  row_number() over (
    partition by case when (t.tgtype & 2)=2 then 'BEFORE'
                      when (t.tgtype & 64)=64 then 'INSTEAD OF' else 'AFTER' end
    order by t.tgname
  ) execution_order,
  case when (t.tgtype & 2)=2 then 'BEFORE'
       when (t.tgtype & 64)=64 then 'INSTEAD OF' else 'AFTER' end timing,
  t.tgname,pg_get_triggerdef(t.oid,true) definition
from pg_trigger t
where t.tgrelid='public.school_lesson_records'::regclass
  and not t.tgisinternal and (t.tgtype & 4)=4
order by timing,execution_order;

do $billing_trigger_guards$
declare
  v_message text;
  v_actual_id uuid;
  v_returned_is_billable boolean;
  v_returned_lesson_fee numeric;
  v_owner_is_billable boolean;
  v_owner_lesson_fee numeric;
  v_owner_status text;
  v_remaining_hours numeric;
begin
  v_message:=null;
  begin
    insert into public.school_lesson_records(
      lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
      business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
      is_billable,app_type,planned_lesson_id,unit_price,lesson_fee,lesson_count,
      actual_minutes,teacher_settlement_month,lesson_delivery_mode,lesson_venue
    ) values('actual','2020-01-16','2020-01','c8160000-0000-4000-8000-00000000a001',
      'c8160000-0000-4000-8000-000000007001','c8160000-0000-4000-8000-00000000d001',
      public.school_primary_business_entity_id(),'09:00','11:00',2,'billable flag forged makeup',
      'makeup_completed',true,'school','c8160000-0000-4000-8000-000000001106',1000,0,1,120,'2020-01','online','Zoom');
  exception when others then
    get stacked diagnostics v_message=message_text;
  end;
  if v_message is null then raise exception 'BILLABLE_FLAG_MAKEUP_DIRECT_INSERT_ALLOWED'; end if;

  insert into public.school_lesson_records(
    lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
    is_billable,app_type,planned_lesson_id,unit_price,lesson_fee,lesson_count,
    actual_minutes,teacher_settlement_month,lesson_delivery_mode,lesson_venue
  ) values('actual','2020-01-17','2020-01','c8160000-0000-4000-8000-00000000a001',
    'c8160000-0000-4000-8000-000000007001','c8160000-0000-4000-8000-00000000d001',
    public.school_primary_business_entity_id(),'09:00','11:00',2,'codex-test R3 fee=1 normalization probe',
    'makeup_completed',false,'school','c8160000-0000-4000-8000-000000001107',1000,1,1,120,'2020-01','online','Zoom')
  returning id,is_billable,lesson_fee
  into v_actual_id,v_returned_is_billable,v_returned_lesson_fee;

  select a.is_billable,a.lesson_fee,a.status
  into strict v_owner_is_billable,v_owner_lesson_fee,v_owner_status
  from public.school_lesson_records a where a.id=v_actual_id;
  v_remaining_hours:=public.school_get_lesson_credit_remaining_hours(
    'c8160000-0000-4000-8000-000000001107'::uuid);

  insert into r3_fee_normalization_result values(
    false,1,v_actual_id,v_returned_is_billable,v_returned_lesson_fee,
    v_owner_is_billable,v_owner_lesson_fee,v_owner_status,v_remaining_hours);

  if v_returned_is_billable is not false or v_returned_lesson_fee<>0
     or v_owner_is_billable is not false or v_owner_lesson_fee<>0
     or v_owner_status<>'makeup_completed' or v_remaining_hours<>0 then
    raise exception 'R3_NONZERO_FEE_PERSISTED_OR_FINAL_FACT_INVALID';
  end if;
end;
$billing_trigger_guards$;

create temp table r3_fee_downstream_after on commit drop as
select * from (
  select 'settlements' object_name,count(*) row_count,
    md5(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)::text) row_hash
    from public.school_student_monthly_settlements x
  union all select 'bills',count(*),md5(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)::text)
    from public.school_student_tuition_bills x
  union all select 'bill_lessons',count(*),md5(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)::text)
    from public.school_student_tuition_bill_lessons x
  union all select 'revisions',count(*),md5(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)::text)
    from public.school_student_tuition_generation_revisions x
  union all select 'income',count(*),md5(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)::text)
    from public.school_income_records x
  union all select 'cash_links',count(*),md5(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)::text)
    from public.school_personal_cash_income_linkage_events x
  union all select 'wage_locks',count(*),md5(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)::text)
    from public.school_teacher_wage_locks x
  union all select 'wage_details',count(*),md5(coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb)::text)
    from public.school_teacher_wage_lock_details x
) snapshot;

do $r3_fee_side_effect_assert$
begin
  if exists(
    (select * from r3_fee_downstream_before except select * from r3_fee_downstream_after)
    union all
    (select * from r3_fee_downstream_after except select * from r3_fee_downstream_before)
  ) then
    raise exception 'R3_FEE_NORMALIZATION_DOWNSTREAM_SIDE_EFFECT';
  end if;
end;
$r3_fee_side_effect_assert$;

select 'R3_FEE_INPUT_RETURNING_OWNER_FINAL' evidence,*
from r3_fee_normalization_result;
select 'R3_FEE_DOWNSTREAM_ZERO_DIFF' evidence,b.*
from r3_fee_downstream_before b
join r3_fee_downstream_after a using(object_name,row_count,row_hash)
order by b.object_name;

do $target_unchanged$
begin
  if (select md5(to_jsonb(l)::text) from public.school_lesson_records l
      where l.id='6722e5a8-d7a1-453a-93a8-9cbaab227378'::uuid)
       is distinct from '94050771268fa97cda680affb81e9364'
     or (select md5(to_jsonb(s)::text) from public.school_student_monthly_settlements s
      where s.id='5e0a23ff-0e1e-48c6-9866-5fc335b3e42d'::uuid)
       is distinct from 'c96670560d491a82b552b32492cd1a55' then
    raise exception 'LOCKED_MAKEUP_REAL_TARGET_CHANGED_BY_FIXTURE_TEST';
  end if;
end;
$target_unchanged$;

select 'LOCKED_BILLING_MONTH_NONBILLING_MAKEUP_ROLLBACK_BODY_PASS' result;
