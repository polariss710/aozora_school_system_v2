-- R2 isolated diagnostic: production-origin schema/functions/triggers/RLS,
-- synthetic rows only, and one outer transaction that always rolls back.
\set ON_ERROR_STOP on
\pset pager off
begin;

grant usage on schema public,auth to anon,authenticated,service_role;
grant select on public.school_lesson_records to anon,authenticated,service_role;
revoke all on function public.school_create_lesson_credit_makeup_actual(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) from public,anon,authenticated,service_role;
grant execute on function public.school_create_lesson_credit_makeup_actual(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) to authenticated;
revoke all on function public.school_list_lesson_management_records_authoritative(text,date)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_lesson_management_records_authoritative(text,date)
  to authenticated;

insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('c8160000-0000-4000-8000-000000000001','authenticated','authenticated',
  '{"provider":"email","providers":["email"]}','{"codex_test":"r2-visibility-admin"}',now(),now());
insert into public.school_app_memberships(
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values(
  'c8160000-0000-4000-8000-000000000001','admin',true,
  'c8160000-0000-4000-8000-000000000001','c8160000-0000-4000-8000-000000000001',
  'codex-test r2 visibility');
insert into public.school_business_entities(id,code,name,entity_type,is_active,note)
values('c8160000-0000-4000-8000-00000000e001','aosora','codex-test entity','company',true,'codex-test r2 visibility');
insert into public.school_subjects(id,name,category,is_active,note,primary_category)
values('c8160000-0000-4000-8000-00000000d001','codex-test subject','codex-test',true,'codex-test r2 visibility','班课');
insert into public.school_teachers(
  id,teacher_code,name,display_name,default_subject_id,default_business_entity_id,status,note,app_type
) values(
  'c8160000-0000-4000-8000-000000007001','codex-r2-visibility','codex-test teacher','codex-test teacher',
  'c8160000-0000-4000-8000-00000000d001','c8160000-0000-4000-8000-00000000e001',
  'active','codex-test r2 visibility','school');
insert into public.school_students(
  id,student_code,name,display_name,business_entity_id,status,app_type,
  preset_exchange_rate,previous_balance_cny,note
) values(
  'c8160000-0000-4000-8000-00000000a001','codex-r2-visibility','codex-test student','codex-test student',
  'c8160000-0000-4000-8000-00000000e001','active','school',0.05,0,'codex-test r2 visibility');

insert into public.school_lesson_records(
  id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
  business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
  is_billable,app_type,unit_price,lesson_fee,lesson_count,
  lesson_delivery_mode,lesson_venue,note
) values(
  'c8160000-0000-4000-8000-000000001101','planned','2020-01-06','2020-01',
  'c8160000-0000-4000-8000-00000000a001','c8160000-0000-4000-8000-000000007001',
  'c8160000-0000-4000-8000-00000000d001','c8160000-0000-4000-8000-00000000e001',
  '09:00','11:00',2,'allowed makeup','pending_makeup',true,'school',1000,2000,1,
  'online','Zoom','codex-test r2 visibility');

create temp table r2_writer_return on commit drop as
select * from public.school_lesson_records with no data;
alter table r2_writer_return owner to authenticated;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"c8160000-0000-4000-8000-000000000001","role":"authenticated"}',true);
insert into r2_writer_return
select * from public.school_create_lesson_credit_makeup_actual(
  'c8160000-0000-4000-8000-000000001101','2020-01-07',
  'c8160000-0000-4000-8000-000000007001','c8160000-0000-4000-8000-00000000d001',
  '09:00','11:00',2,'allowed locked fee-zero makeup','codex-test r2 visibility',1,'online','Zoom');

select 'A_writer_return' assertion,jsonb_build_object(
  'row_count',(select count(*) from r2_writer_return),
  'id',(select id from r2_writer_return),
  'returned',(select to_jsonb(r) from r2_writer_return r)
) evidence;
reset role;

-- Owner storage contract and field-by-field semantic diff.
with returned as (
  select id from r2_writer_return
), actual as (
  select jsonb_build_object(
    'id',l.id,'planned_lesson_id',l.planned_lesson_id,
    'student_id',l.student_id,'teacher_id',l.teacher_id,'subject_id',l.subject_id,
    'business_entity_id',l.business_entity_id,'lesson_date',l.lesson_date,
    'start_time',l.start_time,'end_time',l.end_time,'actual_minutes',l.actual_minutes,
    'duration_hours',l.duration_hours,'status',l.status,'is_billable',l.is_billable,
    'lesson_fee',l.lesson_fee,'student_settlement_month',l.student_settlement_month,
    'teacher_settlement_month',l.teacher_settlement_month,'lesson_content',l.lesson_content,
    'voided_at',l.voided_at,'void_reason',l.void_reason,
    'import_batch_id',l.import_batch_id,'import_source',l.import_source,
    'imported_at',l.imported_at,'created_at_present',l.created_at is not null,
    'updated_at_present',l.updated_at is not null
  ) facts
  from public.school_lesson_records l join returned r on r.id=l.id
), expected as (
  select jsonb_build_object(
    'id',(select id from returned),
    'planned_lesson_id','c8160000-0000-4000-8000-000000001101'::uuid,
    'student_id','c8160000-0000-4000-8000-00000000a001'::uuid,
    'teacher_id','c8160000-0000-4000-8000-000000007001'::uuid,
    'subject_id','c8160000-0000-4000-8000-00000000d001'::uuid,
    'business_entity_id','c8160000-0000-4000-8000-00000000e001'::uuid,
    'lesson_date','2020-01-07'::date,'start_time','09:00','end_time','11:00',
    'actual_minutes',120,'duration_hours',2::numeric,'status','makeup_completed',
    'is_billable',false,'lesson_fee',0::numeric,'student_settlement_month','2020-01',
    'teacher_settlement_month','2020-01','lesson_content','allowed locked fee-zero makeup',
    'voided_at',null,'void_reason',null,'import_batch_id',null,'import_source',null,
    'imported_at',null,'created_at_present',true,'updated_at_present',true
  ) facts
), diff as (
  select coalesce(jsonb_object_agg(e.key,jsonb_build_object(
    'expected',e.value,'actual',a.value)) filter(where a.value is distinct from e.value),'{}'::jsonb) fields
  from expected x cross join actual y
  cross join lateral jsonb_each(x.facts) e
  left join lateral jsonb_each(y.facts) a on a.key=e.key
)
select 'B_owner_storage' assertion,(select facts from actual) actual,
       (select facts from expected) expected,(select fields from diff) field_diff,
       public.school_get_lesson_credit_remaining_hours(
         'c8160000-0000-4000-8000-000000001101'::uuid) remaining_hours;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"c8160000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select 'C_authenticated_direct_select' assertion,count(*) visible_rows,
       coalesce(jsonb_agg(to_jsonb(l)),'[]'::jsonb) rows
from public.school_lesson_records l
where l.id=(select id from r2_writer_return);
select 'C_authenticated_reader' assertion,count(*) visible_rows,
       coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) rows
from public.school_list_lesson_management_records_authoritative('2020-01',null) r
where r.id=(select id from r2_writer_return);
reset role;

select 'R2_LOCAL_VISIBILITY_DIAGNOSTIC_PASS' result;
rollback;
