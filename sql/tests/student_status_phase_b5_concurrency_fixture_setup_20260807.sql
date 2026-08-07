\set ON_ERROR_STOP on
\pset pager off

begin;

do $preflight$
begin
  if exists (select 1 from auth.users where id = 'b5010000-0000-4000-8000-000000000001')
     or exists (select 1 from public.school_app_memberships where user_id = 'b5010000-0000-4000-8000-000000000001')
     or exists (select 1 from public.school_students where id = 'b5010000-0000-4000-8000-000000000100')
     or exists (select 1 from public.school_student_status_events where student_id = 'b5010000-0000-4000-8000-000000000100') then
    raise exception 'B5_CONCURRENCY_FIXTURE_ALREADY_EXISTS';
  end if;
end;
$preflight$;

insert into auth.users (id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('b5010000-0000-4000-8000-000000000001','authenticated','authenticated','b5-concurrency@codex.test',
  '{"provider":"email","providers":["email"]}'::jsonb,'{"codex_test":"b5-concurrency"}'::jsonb,now(),now());

insert into public.school_app_memberships (
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values (
  'b5010000-0000-4000-8000-000000000001','admin',true,
  'b5010000-0000-4000-8000-000000000001','b5010000-0000-4000-8000-000000000001',
  'codex-test b5 concurrency'
);

insert into public.school_students (
  id,student_code,name,display_name,status,business_entity_id,default_currency,
  preset_exchange_rate,note,app_type,created_at,updated_at
) values (
  'b5010000-0000-4000-8000-000000000100','CODEX-B5-CONCURRENCY',
  'codex-test B5 concurrency','codex-test B5 concurrency','active',
  public.school_primary_business_entity_id(),'CNY',0,
  'codex-test b5 concurrency exact cleanup','school',now(),now()
);

commit;

select 'STUDENT_STATUS_PHASE_B5_CONCURRENCY_FIXTURE_READY' result;
