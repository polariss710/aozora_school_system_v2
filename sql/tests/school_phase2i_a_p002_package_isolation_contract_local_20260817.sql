-- Disposable PostgreSQL contract for Phase 2I-A. All business writes roll back.
\set ON_ERROR_STOP on
begin;

create temporary table phase2i_assertions(label text primary key);
grant insert on phase2i_assertions to authenticated,service_role;
create function pg_temp.phase2i_assert(p_ok boolean,p_label text)
returns void language plpgsql security definer as $function$
begin
  if p_ok is distinct from true then raise exception 'ASSERTION_FAILED: %',p_label; end if;
  insert into phase2i_assertions values(p_label);
end
$function$;
create function pg_temp.phase2i_expect_error(p_sql text,p_pattern text,p_label text)
returns void language plpgsql as $function$
begin
  begin execute p_sql; raise exception 'EXPECTED_ERROR_MISSING: %',p_label;
  exception when others then
    if sqlerrm like 'EXPECTED_ERROR_MISSING:%'
       or position(p_pattern in sqlerrm)=0 then raise; end if;
  end;
  insert into phase2i_assertions values(p_label);
end
$function$;

select pg_temp.phase2i_assert(
  (select count(*)=1 and bool_and(
    origin_planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
    and initial_minutes=1200 and consumed_minutes=0 and remaining_minutes=1200
    and unit_price_jpy=13000 and total_price_jpy=260000
    and student_billing_month='2026-07' and status='active')
   from public.school_student_package_credit_lots),
  '01 exact P002 package lot is unique and has authoritative 1200 minutes');
select pg_temp.phase2i_assert(not exists(
  select 1 from public.school_student_package_credit_lots
  where origin_planned_lesson_id<>'8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'),
  '02 no other planned lesson is classified');

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
select pg_temp.phase2i_assert((select count(*)=1 and bool_and(remaining_minutes=1200)
  from public.school_list_student_package_credit_lots(
    'a7b163a0-201e-4867-9b94-372343356a80')),
  '03 active admin canonical reader returns P002');
select pg_temp.phase2i_assert(
  public.school_get_lesson_credit_remaining_hours(
    '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9')=0
  and not exists(select 1 from public.school_list_student_lesson_credit_balances(
    'a7b163a0-201e-4867-9b94-372343356a80')),
  '03b authenticated public readers can traverse owner-only helper');
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000002',true);
select pg_temp.phase2i_assert((select count(*)=1
  from public.school_list_student_package_credit_lots(null)),
  '04 active operator canonical reader is allowed');
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000003',true);
select pg_temp.phase2i_assert((select count(*)=1
  from public.school_list_student_package_credit_lots(null)),
  '05 active read_only canonical reader is allowed');
reset role;

select pg_temp.phase2i_expect_error($sql$
  set local role authenticated;
  select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000004',true);
  select * from public.school_list_student_package_credit_lots(null)$sql$,
  'PACKAGE_READER_ACTIVE_MEMBERSHIP_REQUIRED','06 inactive membership is rejected');
reset role;
select pg_temp.phase2i_expect_error($sql$
  set local role authenticated;
  select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000099',true);
  select * from public.school_list_student_package_credit_lots(null)$sql$,
  'PACKAGE_READER_MEMBERSHIP_REQUIRED','07 missing membership is rejected');
reset role;
select pg_temp.phase2i_expect_error($sql$
  set local role anon;
  select * from public.school_list_student_package_credit_lots(null)$sql$,
  'permission denied','08 anon cannot execute package reader');
reset role;

select pg_temp.phase2i_assert(
  public.school_get_lesson_credit_raw_remaining_hours(
    '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9')=0
  and public.school_get_lesson_credit_remaining_hours(
    '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9')=0,
  '09 raw and public ordinary balance readers exclude P002');
select pg_temp.phase2i_assert(not exists(
  select 1 from public.school_list_open_lesson_credit_sources(
    '2026-07','2026-07','2026-07') source
  where source.id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'),
  '10 makeup source reader excludes P002');
select pg_temp.phase2i_assert(not exists(
  select 1 from public.school_list_student_lesson_credit_balances(
    'a7b163a0-201e-4867-9b94-372343356a80')),
  '11 ordinary aggregate balance excludes P002');
select pg_temp.phase2i_assert(not exists(
  select 1 from public.school_tuition_p0f_source_lines(
    'a7b163a0-201e-4867-9b94-372343356a80',
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-07',0.045,false)
  where source_planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'),
  '12 registered variance and net source exclude P002');
select public.school_tuition_p0f_assert_sources_resolved(
  'a7b163a0-201e-4867-9b94-372343356a80',
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-07');
select pg_temp.phase2i_assert(true,'13 unresolved source guard is not blocked by P002');

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
do $reject_package$
begin
  begin
    perform * from public.school_create_lesson_credit_makeup_actual(
      '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9','2026-08-17',
      'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd',
      'ed258e2b-81e4-4268-9682-124f310fbdf9','13:00','15:00',2,
      'codex-test forbidden package actual',null,1,'onsite','fixture');
    raise exception 'EXPECTED_PACKAGE_REJECTION_MISSING';
  exception when others then
    if sqlerrm='EXPECTED_PACKAGE_REJECTION_MISSING'
       or position('LESSON_PACKAGE_SOURCE_NOT_MAKEUP_CREDIT' in sqlerrm)=0 then raise; end if;
  end;
end
$reject_package$;
reset role;
select pg_temp.phase2i_assert(not exists(select 1 from public.school_lesson_records
  where planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'),
  '14 makeup writer rejects P002 before actual creation');

select pg_temp.phase2i_expect_error($sql$
  insert into public.school_lesson_records(
    id,lesson_type,status,student_id,business_entity_id,planned_lesson_id,
    lesson_date,duration_hours,is_billable
  ) values('4a000000-0000-4000-8000-202608170001','actual','makeup_completed',
    'a7b163a0-201e-4867-9b94-372343356a80',
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
    '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9','2026-08-17',1,false)$sql$,
  'LESSON_PACKAGE_SOURCE_NOT_MAKEUP_CREDIT','15 table guard rejects package actual for owner too');

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000002',true);
select pg_temp.phase2i_assert(exists(
  select 1 from public.school_list_open_lesson_credit_sources('2026-01','2026-01','2026-01')
  where id='30000000-0000-4000-8000-000000000002'),
  '16 ordinary pending source remains readable');
select pg_temp.phase2i_assert((select count(*)=1 from
  public.school_create_lesson_credit_makeup_actual(
    '30000000-0000-4000-8000-000000000002','2026-01-10',
    '71000000-0000-4000-8000-000000000002',
    '72000000-0000-4000-8000-000000000002','13:00','15:00',2,
    'codex-test ordinary source still works',null,1,'onsite','fixture')),
  '17 ordinary pending source remains consumable by active operator');
reset role;

select pg_temp.phase2i_expect_error($sql$
  update public.school_student_package_credit_lots set consumed_minutes=1$sql$,
  'LESSON_PACKAGE_LOT_APPEND_ONLY','18 package lot is append-only');
select pg_temp.phase2i_expect_error($sql$
  insert into public.school_student_package_credit_lots(
    id,origin_planned_lesson_id,student_id,business_entity_id,initial_minutes,
    consumed_minutes,unit_price_jpy,total_price_jpy,student_billing_month,
    tuition_bill_id,tuition_revision_id,income_record_id,cash_linkage_event_id,
    cash_request_id_snapshot,cash_transaction_id_snapshot,status,
    classification_reason,origin_lesson_row_md5,evidence_manifest_sha256,
    classified_by,created_at)
  select id,origin_planned_lesson_id,student_id,business_entity_id,initial_minutes,
    consumed_minutes,unit_price_jpy,total_price_jpy,student_billing_month,
    tuition_bill_id,tuition_revision_id,income_record_id,cash_linkage_event_id,
    cash_request_id_snapshot,cash_transaction_id_snapshot,status,
    classification_reason,origin_lesson_row_md5,evidence_manifest_sha256,
    classified_by,created_at from public.school_student_package_credit_lots$sql$,
  'duplicate key','19 duplicate classification is rejected');

set local role authenticated;
select pg_temp.phase2i_expect_error($sql$
  insert into public.school_student_package_credit_lots(
    id,origin_planned_lesson_id,student_id,business_entity_id,initial_minutes,
    consumed_minutes,unit_price_jpy,total_price_jpy,student_billing_month,
    tuition_bill_id,tuition_revision_id,income_record_id,cash_linkage_event_id,
    cash_request_id_snapshot,cash_transaction_id_snapshot,status,
    classification_reason,origin_lesson_row_md5,evidence_manifest_sha256,classified_by)
  select gen_random_uuid(),origin_planned_lesson_id,student_id,business_entity_id,
    initial_minutes,consumed_minutes,unit_price_jpy,total_price_jpy,
    student_billing_month,tuition_bill_id,tuition_revision_id,income_record_id,
    cash_linkage_event_id,cash_request_id_snapshot,cash_transaction_id_snapshot,
    status,classification_reason,origin_lesson_row_md5,evidence_manifest_sha256,classified_by
  from public.school_student_package_credit_lots$sql$,
  'permission denied','20 authenticated has no direct classification DML');
reset role;
set local role service_role;
select pg_temp.phase2i_expect_error($sql$
  update public.school_student_package_credit_lots set consumed_minutes=1$sql$,
  'permission denied','21 service_role has no package DML');
reset role;

select pg_temp.phase2i_assert(
  not exists(select 1 from pg_proc procedure
    where procedure.pronamespace='public'::regnamespace
      and procedure.proname~'package.*(consume|reserve)|(consume|reserve).*package')
  and to_regclass('public.school_lesson_clearances') is null
  and to_regclass('public.school_lesson_clearance_details') is null,
  '22 no package consumption/reservation or clearance objects exist');
select pg_temp.phase2i_assert(
  (select count(*)=1 from public.school_student_tuition_bill_lessons
   where planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9')
  and (select count(*)=1 from public.school_student_tuition_generation_revisions
   where id='96000000-0000-4000-8000-202608031004')
  and (select count(*)=1 from public.school_income_records
   where id='91756564-c48d-4a1d-b6bc-88a041660e46')
  and (select count(*)=1 from public.school_personal_cash_income_linkage_events
   where id='9de972ff-8e66-470a-8b05-e430ef51562f'),
  '23 P002 immutable financial evidence remains present');

select count(*) as passed_assertions from phase2i_assertions;
rollback;
