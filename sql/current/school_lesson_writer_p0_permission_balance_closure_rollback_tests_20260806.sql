-- Rollback-only synthetic permission, balance, time and proposed-state matrix.
-- All persistent-looking rows use the fixed be10... whitelist and are rolled back.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='300s';

do $preflight$
begin
  if exists(select 1 from auth.users where id::text like 'be100000-%')
     or exists(select 1 from public.school_students where id::text like 'be100000-%')
     or exists(select 1 from public.school_teachers where id::text like 'be100000-%')
     or exists(select 1 from public.school_subjects where id::text like 'be100000-%')
     or exists(select 1 from public.school_lesson_records where id::text like 'be100000-%') then
    raise exception 'LESSON_WRITER_P0_FIXTURE_COLLISION';
  end if;
end;
$preflight$;

insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
 ('be100000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"lesson-p0-admin"}',now(),now()),
 ('be100000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"lesson-p0-operator"}',now(),now()),
 ('be100000-0000-4000-8000-000000000003','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"lesson-p0-read-only"}',now(),now()),
 ('be100000-0000-4000-8000-000000000004','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"lesson-p0-inactive-admin"}',now(),now()),
 ('be100000-0000-4000-8000-000000000005','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"lesson-p0-inactive-operator"}',now(),now()),
 ('be100000-0000-4000-8000-000000000006','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"lesson-p0-no-membership"}',now(),now());

insert into public.school_app_memberships(
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values
 ('be100000-0000-4000-8000-000000000001','admin',true,'be100000-0000-4000-8000-000000000001','be100000-0000-4000-8000-000000000001','codex-test lesson writer p0'),
 ('be100000-0000-4000-8000-000000000002','operator',true,'be100000-0000-4000-8000-000000000001','be100000-0000-4000-8000-000000000001','codex-test lesson writer p0'),
 ('be100000-0000-4000-8000-000000000003','read_only',true,'be100000-0000-4000-8000-000000000001','be100000-0000-4000-8000-000000000001','codex-test lesson writer p0'),
 ('be100000-0000-4000-8000-000000000004','admin',false,'be100000-0000-4000-8000-000000000001','be100000-0000-4000-8000-000000000001','codex-test lesson writer p0'),
 ('be100000-0000-4000-8000-000000000005','operator',false,'be100000-0000-4000-8000-000000000001','be100000-0000-4000-8000-000000000001','codex-test lesson writer p0');

insert into public.school_subjects(id,name,category,is_active,note,primary_category)
values('be100000-0000-4000-8000-00000000d001','codex-test lesson writer P0 subject','codex-test',true,'codex-test lesson writer p0','班课');
insert into public.school_teachers(
 id,teacher_code,name,display_name,default_subject_id,default_business_entity_id,status,note,app_type
) values(
 'be100000-0000-4000-8000-000000007001','codex-lesson-p0','codex-test lesson writer P0 teacher',
 'codex-test lesson writer P0 teacher','be100000-0000-4000-8000-00000000d001',
 public.school_primary_business_entity_id(),'active','codex-test lesson writer p0','school'
);
insert into public.school_students(
 id,student_code,name,display_name,business_entity_id,status,app_type,
 preset_exchange_rate,previous_balance_cny,note
) values(
 'be100000-0000-4000-8000-00000000a001','codex-lesson-p0','codex-test lesson writer P0 student',
 'codex-test lesson writer P0 student',public.school_primary_business_entity_id(),
 'active','school',0.05,0,'codex-test lesson writer p0'
);

insert into public.school_lesson_records(
 id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
 business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
 is_billable,app_type,unit_price,lesson_fee,lesson_count,
 lesson_delivery_mode,lesson_venue,note
)
select id,'planned',lesson_date,to_char(lesson_date,'YYYY-MM'),
 'be100000-0000-4000-8000-00000000a001'::uuid,
 'be100000-0000-4000-8000-000000007001'::uuid,
 'be100000-0000-4000-8000-00000000d001'::uuid,
 public.school_primary_business_entity_id(),'09:00','11:00',2,
 'codex-test lesson writer p0 '||label,status,true,'school',1000,2000,1,
 'online','Zoom','codex-test lesson writer p0'
from (values
 ('be100000-0000-4000-8000-000000001101'::uuid,date '2020-01-08','admin-full','pending_makeup'),
 ('be100000-0000-4000-8000-000000001102'::uuid,date '2020-01-15','operator-split','pending_makeup'),
 ('be100000-0000-4000-8000-000000001103'::uuid,date '2020-01-22','over-request','pending_makeup'),
 ('be100000-0000-4000-8000-000000001104'::uuid,date '2020-01-29','cancelled-does-not-consume','pending_makeup'),
 ('be100000-0000-4000-8000-000000001105'::uuid,date '2020-02-05','legacy-negative','pending_makeup'),
 ('be100000-0000-4000-8000-000000001106'::uuid,date '2020-02-12','update-enlarge','pending_makeup'),
 ('be100000-0000-4000-8000-000000001107'::uuid,date '2020-02-19','status-change','pending_makeup'),
 ('be100000-0000-4000-8000-000000001108'::uuid,date '2020-02-26','source-target','pending_makeup'),
 ('be100000-0000-4000-8000-000000001109'::uuid,date '2020-03-05','source-origin','pending_makeup'),
 ('be100000-0000-4000-8000-000000001110'::uuid,date '2020-03-12','non-makeup-source','planned'),
 ('be100000-0000-4000-8000-000000001111'::uuid,date '2020-03-19','ordinary-overage','planned'),
 ('be100000-0000-4000-8000-000000001112'::uuid,date '2020-03-26','partial','planned'),
 ('be100000-0000-4000-8000-000000001113'::uuid,date '2020-04-02','cancelled','planned'),
 ('be100000-0000-4000-8000-000000001114'::uuid,date '2020-04-09','ordinary','planned'),
 ('be100000-0000-4000-8000-000000001115'::uuid,date '2020-04-16','unvoid-credit','pending_makeup')
) fixture(id,lesson_date,label,status);

-- These rows intentionally model pre-existing states before the new trigger exists.
insert into public.school_lesson_records(
 id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
 business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
 is_billable,app_type,planned_lesson_id,unit_price,lesson_fee,lesson_count,
 actual_minutes,teacher_settlement_month,student_settlement_month,
 lesson_delivery_mode,lesson_venue,note,voided_at,void_reason
) values
 ('be100000-0000-4000-8000-000000002104','actual','2020-01-29','2020-01','be100000-0000-4000-8000-00000000a001','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','11:00',2,'cancelled','cancelled',false,'school','be100000-0000-4000-8000-000000001104',1000,0,1,0,'2020-01','2020-01','online','Zoom','codex-test lesson writer p0',null,null),
 ('be100000-0000-4000-8000-000000002105','actual','2020-02-05','2020-02','be100000-0000-4000-8000-00000000a001','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','13:00',4,'legacy negative','completed',true,'school','be100000-0000-4000-8000-000000001105',1000,4000,1,240,'2020-02','2020-02','online','Zoom','codex-test lesson writer p0',null,null),
 ('be100000-0000-4000-8000-000000002106','actual','2020-02-12','2020-02','be100000-0000-4000-8000-00000000a001','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','10:00',1,'update enlarge','makeup_completed',false,'school','be100000-0000-4000-8000-000000001106',1000,0,1,60,'2020-02','2020-02','online','Zoom','codex-test lesson writer p0',null,null),
 ('be100000-0000-4000-8000-000000002107','actual','2020-02-19','2020-02','be100000-0000-4000-8000-00000000a001','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','11:00',2,'status consumed','completed',true,'school','be100000-0000-4000-8000-000000001107',1000,2000,1,120,'2020-02','2020-02','online','Zoom','codex-test lesson writer p0',null,null),
 ('be100000-0000-4000-8000-000000002207','actual','2020-02-20','2020-02','be100000-0000-4000-8000-00000000a001','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','10:00',1,'status cancelled','cancelled',false,'school','be100000-0000-4000-8000-000000001107',1000,0,1,0,'2020-02','2020-02','online','Zoom','codex-test lesson writer p0',null,null),
 ('be100000-0000-4000-8000-000000002108','actual','2020-02-26','2020-02','be100000-0000-4000-8000-00000000a001','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','11:00',2,'source target consumed','completed',true,'school','be100000-0000-4000-8000-000000001108',1000,2000,1,120,'2020-02','2020-02','online','Zoom','codex-test lesson writer p0',null,null),
 ('be100000-0000-4000-8000-000000002109','actual','2020-03-05','2020-03','be100000-0000-4000-8000-00000000a001','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','10:00',1,'source origin','makeup_completed',false,'school','be100000-0000-4000-8000-000000001109',1000,0,1,60,'2020-03','2020-03','online','Zoom','codex-test lesson writer p0',null,null),
 ('be100000-0000-4000-8000-000000002115','actual','2020-04-16','2020-04','be100000-0000-4000-8000-00000000a001','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','13:00',4,'voided oversized','completed',true,'school','be100000-0000-4000-8000-000000001115',1000,4000,1,240,'2020-04','2020-04','online','Zoom','codex-test lesson writer p0',now(),'codex-test lesson writer p0');

\ir school_lesson_writer_p0_permission_balance_closure_core_20260806.sql
create temp table lesson_p0_results(test_name text primary key,detail text) on commit drop;

set local role anon;
do $anon$
declare denied boolean:=false;
begin
  begin perform * from public.school_create_lesson_credit_makeup_actual(null,null,null,null,null,null,null,null,null,null,null,null);
  exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'LESSON_WRITER_P0_ANON_ALLOWED'; end if;
end;
$anon$;
reset role;
insert into lesson_p0_results values('anon_acl','canonical writer execution denied');

set local role service_role;
do $service$
declare denied boolean:=false;
begin
  begin perform * from public.school_create_lesson_credit_makeup_actual(null,null,null,null,null,null,null,null,null,null,null,null);
  exception when insufficient_privilege then denied:=true; end;
  if not denied then raise exception 'LESSON_WRITER_P0_SERVICE_ALLOWED'; end if;
end;
$service$;
reset role;
insert into lesson_p0_results values('service_acl','canonical writer execution denied');

set local role authenticated;
do $membership_matrix$
declare actor uuid; expected text; denied boolean;
begin
  for actor,expected in select * from (values
    ('be100000-0000-4000-8000-000000000006'::uuid,'LESSON_WRITER_MEMBERSHIP_REQUIRED'),
    ('be100000-0000-4000-8000-000000000003'::uuid,'LESSON_WRITER_ROLE_REQUIRED'),
    ('be100000-0000-4000-8000-000000000004'::uuid,'LESSON_WRITER_ACTIVE_MEMBERSHIP_REQUIRED'),
    ('be100000-0000-4000-8000-000000000005'::uuid,'LESSON_WRITER_ACTIVE_MEMBERSHIP_REQUIRED')
  ) x(actor,expected)
  loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
    denied:=false;
    begin perform * from public.school_create_lesson_credit_makeup_actual(null,null,null,null,null,null,null,null,null,null,null,null);
    exception when insufficient_privilege then if sqlerrm=expected then denied:=true; else raise; end if; end;
    if not denied then raise exception 'LESSON_WRITER_P0_MEMBERSHIP_ALLOWED:%',actor; end if;
  end loop;
  perform set_config('request.jwt.claims','{"role":"authenticated"}',true);
  denied:=false;
  begin perform * from public.school_create_lesson_credit_makeup_actual(null,null,null,null,null,null,null,null,null,null,null,null);
  exception when insufficient_privilege then if sqlerrm='LESSON_WRITER_AUTH_REQUIRED' then denied:=true; else raise; end if; end;
  if not denied then raise exception 'LESSON_WRITER_P0_AUTHLESS_ALLOWED'; end if;
end;
$membership_matrix$;
reset role;
insert into lesson_p0_results values('membership_matrix','read_only, inactive admin/operator, no membership and authless rejected');

do $business_matrix$
declare a uuid; b1 uuid; b2 uuid; c uuid; ordinary uuid; partial uuid; cancelled uuid;
  denied boolean; updated timestamptz; before_note text;
begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','be100000-0000-4000-8000-000000000001','role','authenticated')::text,true);
  select id into strict a from public.school_create_lesson_credit_makeup_actual(
    'be100000-0000-4000-8000-000000001101','2020-05-01','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001','09:00','11:00',2,'admin full','codex-test lesson writer p0',1,'online','Zoom');
  if not exists(select 1 from public.school_lesson_records where id=a and duration_hours=2 and actual_minutes=120 and not is_billable and lesson_fee=0) then
    raise exception 'LESSON_WRITER_P0_ADMIN_RESULT';
  end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub','be100000-0000-4000-8000-000000000002','role','authenticated')::text,true);
  select id into strict b1 from public.school_create_lesson_credit_makeup_actual(
    'be100000-0000-4000-8000-000000001102','2020-05-02','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001','09:00','10:00',1,'operator split 1','codex-test lesson writer p0',1,'online','Zoom');
  select id into strict b2 from public.school_create_lesson_credit_makeup_actual(
    'be100000-0000-4000-8000-000000001102','2020-05-03','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001','10:00','11:00',1,'operator split 2','codex-test lesson writer p0',1,'online','Zoom');
  if public.school_get_lesson_credit_raw_remaining_hours('be100000-0000-4000-8000-000000001102')<>0 then raise exception 'LESSON_WRITER_P0_SPLIT_BALANCE'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub','be100000-0000-4000-8000-000000000001','role','authenticated')::text,true);
  denied:=false;
  begin perform * from public.school_create_lesson_credit_makeup_actual('be100000-0000-4000-8000-000000001103','2020-05-04','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001','09:00','11:15',2.25,'over','codex-test lesson writer p0',1,'online','Zoom');
  exception when others then if sqlerrm='LESSON_MAKEUP_CREDIT_EXCEEDED' then denied:=true; else raise; end if; end;
  if not denied then raise exception 'LESSON_WRITER_P0_OVER_ALLOWED'; end if;
  denied:=false;
  begin perform * from public.school_create_lesson_credit_makeup_actual('be100000-0000-4000-8000-000000001101','2020-05-05','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001','09:00','09:15',0.25,'zero','codex-test lesson writer p0',1,'online','Zoom');
  exception when others then if sqlerrm='LESSON_MAKEUP_CREDIT_EXHAUSTED' then denied:=true; else raise; end if; end;
  if not denied then raise exception 'LESSON_WRITER_P0_ZERO_ALLOWED'; end if;
  denied:=false;
  begin perform * from public.school_create_lesson_credit_makeup_actual('be100000-0000-4000-8000-000000001105','2020-05-06','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001','09:00','09:15',0.25,'negative','codex-test lesson writer p0',1,'online','Zoom');
  exception when others then if sqlerrm='LESSON_MAKEUP_CREDIT_DATA_INCONSISTENT' then denied:=true; else raise; end if; end;
  if not denied then raise exception 'LESSON_WRITER_P0_NEGATIVE_ALLOWED'; end if;
  select id into strict c from public.school_create_lesson_credit_makeup_actual(
    'be100000-0000-4000-8000-000000001104','2020-05-07','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001','09:00','11:00',2,'cancel ignored','codex-test lesson writer p0',1,'online','Zoom');
  if public.school_get_lesson_credit_raw_remaining_hours('be100000-0000-4000-8000-000000001104')<>0 then raise exception 'LESSON_WRITER_P0_CANCEL_CONSUMED'; end if;

  denied:=false;
  begin perform * from public.school_create_lesson_credit_makeup_actual('be100000-0000-4000-8000-000000001103','2020-05-08','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001','09:10','10:10',1,'grid','codex-test lesson writer p0',1,'online','Zoom');
  exception when others then if sqlerrm='LESSON_TIME_GRID_INVALID' then denied:=true; else raise; end if; end;
  if not denied then raise exception 'LESSON_WRITER_P0_GRID_ALLOWED'; end if;
  denied:=false;
  begin perform * from public.school_create_lesson_credit_makeup_actual('be100000-0000-4000-8000-000000001103','2020-05-08','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001','10:00','10:00',1,'range','codex-test lesson writer p0',1,'online','Zoom');
  exception when others then if sqlerrm='LESSON_TIME_RANGE_INVALID' then denied:=true; else raise; end if; end;
  if not denied then raise exception 'LESSON_WRITER_P0_RANGE_ALLOWED'; end if;
  denied:=false;
  begin perform * from public.school_create_lesson_credit_makeup_actual('be100000-0000-4000-8000-000000001103','2020-05-08','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001','09:00','10:15',1,'mismatch','codex-test lesson writer p0',1,'online','Zoom');
  exception when others then if sqlerrm='LESSON_DURATION_MISMATCH' then denied:=true; else raise; end if; end;
  if not denied then raise exception 'LESSON_WRITER_P0_MISMATCH_ALLOWED'; end if;

  select lesson_id into strict ordinary from public.school_create_actual_lesson_from_planned(
    'be100000-0000-4000-8000-000000001111','2020-03-19','09:00','11:30',2.5,1000,null,1,'ordinary overage','codex-test lesson writer p0');
  if not exists(select 1 from public.school_lesson_records where id=ordinary and duration_hours=2.5 and actual_minutes=150 and lesson_fee=2500 and student_duration_overage_minutes=30 and student_duration_overage_fee_jpy=500) then
    raise exception 'LESSON_WRITER_P0_ORDINARY_OVERAGE';
  end if;
  select id into strict partial from public.school_create_partial_completed_actual_from_planned(
    'be100000-0000-4000-8000-000000001112','2020-03-26','09:00','10:30',1.5,'partial','codex-test lesson writer p0');
  if not exists(select 1 from public.school_lesson_records where id=partial and duration_hours=1.5 and actual_minutes=90 and lesson_fee=1500 and is_billable) then raise exception 'LESSON_WRITER_P0_PARTIAL'; end if;
  select lesson_id into strict cancelled from public.school_create_cancelled_actual_lesson_from_planned(
    'be100000-0000-4000-8000-000000001113','2020-04-02','09:00','10:15',1.25,1000,1,'cancel','codex-test lesson writer p0');
  if not exists(select 1 from public.school_lesson_records where id=cancelled and duration_hours=1.25 and actual_minutes=0 and not is_billable and lesson_fee=0) then raise exception 'LESSON_WRITER_P0_CANCELLED'; end if;

  select updated_at into strict updated from public.school_lesson_records where id='be100000-0000-4000-8000-000000002106';
  denied:=false;
  begin perform * from public.school_update_lesson_record_guarded_with_venue(
    'be100000-0000-4000-8000-000000002106',updated,'2020-02-12','be100000-0000-4000-8000-00000000a001','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','11:30',2.5,1000,null,'makeup_completed',false,1,'update enlarge','codex-test lesson writer p0','online','Zoom');
  exception when others then if position('LESSON_MAKEUP_CREDIT_EXCEEDED' in sqlerrm)>0 or position('R1D_E_B2_ACTUAL_SOURCE_STUDENT_ENTITY_IMMUTABLE' in sqlerrm)>0 then denied:=true; else raise; end if; end;
  if not denied then raise exception 'LESSON_WRITER_P0_UPDATE_ENLARGE_ALLOWED'; end if;

  denied:=false;
  begin update public.school_lesson_records set status='completed',actual_minutes=60 where id='be100000-0000-4000-8000-000000002207';
  exception when others then if position('LESSON_MAKEUP_CREDIT_EXCEEDED' in sqlerrm)>0 then denied:=true; else raise; end if; end;
  if not denied then raise exception 'LESSON_WRITER_P0_STATUS_OVER_ALLOWED'; end if;
  denied:=false;
  begin update public.school_lesson_records set planned_lesson_id='be100000-0000-4000-8000-000000001108' where id='be100000-0000-4000-8000-000000002109';
  exception when others then if position('LESSON_MAKEUP_CREDIT_EXCEEDED' in sqlerrm)>0 or position('R1D_E_B2_ACTUAL_SOURCE_STUDENT_ENTITY_IMMUTABLE' in sqlerrm)>0 then denied:=true; else raise; end if; end;
  if not denied then raise exception 'LESSON_WRITER_P0_SOURCE_MOVE_ALLOWED'; end if;
  denied:=false;
  begin update public.school_lesson_records set duration_hours=0.5 where id='be100000-0000-4000-8000-000000001106';
  exception when others then if position('LESSON_MAKEUP_CREDIT_EXCEEDED' in sqlerrm)>0 or position('LESSON_FINANCIAL_FACT_IMMUTABLE' in sqlerrm)>0 then denied:=true; else raise; end if; end;
  if not denied then raise exception 'LESSON_WRITER_P0_SOURCE_SHRINK_ALLOWED'; end if;
  denied:=false;
  begin update public.school_lesson_records set voided_at=null,void_reason=null where id='be100000-0000-4000-8000-000000002115';
  exception when others then if position('LESSON_MAKEUP_CREDIT_EXCEEDED' in sqlerrm)>0 or position('IMMUTABLE' in sqlerrm)>0 then denied:=true; else raise; end if; end;
  if not denied then raise exception 'LESSON_WRITER_P0_UNVOID_OVER_ALLOWED'; end if;
  denied:=false;
  begin insert into public.school_lesson_records(
    lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,business_entity_id,
    start_time,end_time,duration_hours,lesson_content,status,is_billable,app_type,planned_lesson_id,
    unit_price,lesson_fee,lesson_count,actual_minutes,teacher_settlement_month,student_settlement_month,
    lesson_delivery_mode,lesson_venue,note
  ) values('actual','2020-03-12','2020-03','be100000-0000-4000-8000-00000000a001','be100000-0000-4000-8000-000000007001','be100000-0000-4000-8000-00000000d001',public.school_primary_business_entity_id(),'09:00','10:00',1,'bypass','makeup_completed',false,'school','be100000-0000-4000-8000-000000001110',1000,0,1,60,'2020-03','2020-03','online','Zoom','codex-test lesson writer p0');
  exception when others then if position('LESSON_MAKEUP_SOURCE_STATUS_INVALID' in sqlerrm)>0 then denied:=true; else raise; end if; end;
  if not denied then raise exception 'LESSON_WRITER_P0_MAKEUP_STATUS_BYPASS'; end if;

  select note into before_note from public.school_lesson_records where id='be100000-0000-4000-8000-000000002105';
  update public.school_lesson_records set note=note||' content-only' where id='be100000-0000-4000-8000-000000002105';
  if (select note from public.school_lesson_records where id='be100000-0000-4000-8000-000000002105')=before_note then raise exception 'LESSON_WRITER_P0_CONTENT_ONLY_BLOCKED'; end if;
  update public.school_lesson_records set is_billable=true,lesson_fee=999 where id=b1;
  if exists(select 1 from public.school_lesson_records where id=b1 and (is_billable or lesson_fee<>0)) then raise exception 'LESSON_WRITER_P0_MAKEUP_FEE_TAMPER'; end if;
end;
$business_matrix$;

insert into lesson_p0_results values('active_roles','active admin and operator successful on synthetic canonical makeup writes');
insert into lesson_p0_results values('credit_matrix','full/split/cancelled/exceeded/exhausted/raw-negative paths passed');
insert into lesson_p0_results values('time_matrix','grid/range/mismatch and DB minutes/duration authority passed');
insert into lesson_p0_results values('proposed_state','update enlargement/status/source/duration/unvoid and non-makeup-source bypass rejected');
insert into lesson_p0_results values('fee_and_legacy','makeup fee fixed; legacy negative content-only edit allowed');
insert into lesson_p0_results values('ordinary_regression','ordinary overage, partial and cancelled calculations preserved');

do $catalog$
declare sig regprocedure;
begin
  for sig in select unnest(array[
    'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer)'::regprocedure,
    'public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,
    'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure,
    'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text,integer)'::regprocedure,
    'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure,
    'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure,
    'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure,
    'public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure,
    'public.school_void_planned_lesson(uuid,timestamp with time zone,text)'::regprocedure,
    'public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean)'::regprocedure
  ]::regprocedure[])
  loop
    if not has_function_privilege('authenticated',sig,'execute')
       or has_function_privilege('anon',sig,'execute')
       or has_function_privilege('service_role',sig,'execute')
       or has_function_privilege('public',sig,'execute')
       or position('school_assert_active_lesson_writer()' in pg_get_functiondef(sig::oid))=0 then
      raise exception 'LESSON_WRITER_P0_CANONICAL_CATALOG:%',sig;
    end if;
  end loop;
  if has_function_privilege('authenticated','public.school_create_makeup_completed_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)','execute')
     or has_function_privilege('service_role','public.school_replace_unconsumed_makeup_actual_v1(uuid,timestamp with time zone,uuid,date,text,text)','execute') then
    raise exception 'LESSON_WRITER_P0_LEGACY_EXPOSED';
  end if;
end;
$catalog$;
insert into lesson_p0_results values('catalog_acl','all canonical/helper/legacy ACL assertions passed');

select * from lesson_p0_results order by test_name;
select count(*) fixture_rows_inside_transaction from public.school_lesson_records where id::text like 'be100000-%';
select 'LESSON_WRITER_P0_ROLLBACK_TESTS_PASS' result;
rollback;
