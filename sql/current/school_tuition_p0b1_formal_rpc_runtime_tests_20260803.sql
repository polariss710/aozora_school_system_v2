\set ON_ERROR_STOP on
\pset pager off
begin;
insert into public.school_subjects(id,name,note)
values('b1b10000-0000-4000-8000-000000000012','codex-test P0-B1 role subject','codex-test tuition-p0b1-role-runtime');
insert into public.school_teachers(id,teacher_code,name,default_subject_id,default_business_entity_id,note)
values('b1b10000-0000-4000-8000-000000000013','codex-p0b1-role','codex-test P0-B1 role teacher',
  'b1b10000-0000-4000-8000-000000000012',public.school_primary_business_entity_id(),'codex-test tuition-p0b1-role-runtime');
insert into public.school_students(id,student_code,name,business_entity_id,note)
values('b1b10000-0000-4000-8000-000000000014','codex-p0b1-role','codex-test P0-B1 role student',
  public.school_primary_business_entity_id(),'codex-test tuition-p0b1-role-runtime');

set local role anon;
select lesson_id,lesson_fee from public.school_create_planned_lesson_record(
  '2036-01-07','b1b10000-0000-4000-8000-000000000014','b1b10000-0000-4000-8000-000000000013',
  'b1b10000-0000-4000-8000-000000000012',public.school_primary_business_entity_id(),
  '09:00','11:00',2,2100,1,'planned',1,'anon role','codex-test tuition-p0b1-role-runtime');
reset role;

set local role authenticated;
select lesson_id,lesson_fee from public.school_create_planned_lesson_record(
  '2036-01-14','b1b10000-0000-4000-8000-000000000014','b1b10000-0000-4000-8000-000000000013',
  'b1b10000-0000-4000-8000-000000000012',public.school_primary_business_entity_id(),
  '09:00','11:00',2,2100,1,'planned',1,'authenticated role','codex-test tuition-p0b1-role-runtime');
reset role;

set local role service_role;
select lesson_id,lesson_fee from public.school_create_planned_lesson_record(
  '2036-01-21','b1b10000-0000-4000-8000-000000000014','b1b10000-0000-4000-8000-000000000013',
  'b1b10000-0000-4000-8000-000000000012',public.school_primary_business_entity_id(),
  '09:00','11:00',2,2100,1,'planned',1,'service role','codex-test tuition-p0b1-role-runtime');
reset role;

do $verify$
begin
  if (select count(*) from public.school_lesson_records where note='codex-test tuition-p0b1-role-runtime')<>3
     or exists(select 1 from public.school_lesson_records where note='codex-test tuition-p0b1-role-runtime'
               and lesson_fee<>4200) then
    raise exception 'P0B1_FORMAL_RPC_ROLE_RUNTIME_FAILED';
  end if;
end
$verify$;
select 'anon/authenticated/service formal RPC 3/3; DB fee 4200' result;
rollback;
