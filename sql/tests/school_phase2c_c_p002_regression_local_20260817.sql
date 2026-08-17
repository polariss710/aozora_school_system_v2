-- Phase 2C-C regression: deployed P002 lot remains isolated and immutable.
-- The production UUIDs below exist only as synthetic rows in the disposable DB.
\set ON_ERROR_STOP on

begin;
create temporary table phase2ca_assertions(label text primary key);
create temporary table phase2ca_before(object_name text primary key,row_md5 text);
create function pg_temp.phase2ca_assert(p_ok boolean,p_label text)
returns void language plpgsql as $function$
begin
  if p_ok is distinct from true then raise exception 'ASSERTION_FAILED: %',p_label; end if;
  insert into phase2ca_assertions values(p_label);
end
$function$;
create function pg_temp.phase2ca_expect_error(p_sql text,p_pattern text,p_label text)
returns void language plpgsql as $function$
begin
  begin execute p_sql; raise exception 'EXPECTED_ERROR_MISSING: %',p_label;
  exception when others then
    if sqlerrm like 'EXPECTED_ERROR_MISSING:%'
       or position(p_pattern in sqlerrm)=0 then raise; end if;
  end;
  insert into phase2ca_assertions values(p_label);
end
$function$;

insert into phase2ca_before values
  ('lesson',(select md5(to_jsonb(row_value)::text) from public.school_lesson_records row_value
    where id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9')),
  ('bill',(select md5(to_jsonb(row_value)::text) from public.school_student_tuition_bills row_value
    where id='07a02092-9503-47d1-9000-106f7e3de7e5')),
  ('revision',(select md5(to_jsonb(row_value)::text) from public.school_student_tuition_generation_revisions row_value
    where id='96000000-0000-4000-8000-202608031004')),
  ('income',(select md5(to_jsonb(row_value)::text) from public.school_income_records row_value
    where id='91756564-c48d-4a1d-b6bc-88a041660e46')),
  ('cash',(select md5(to_jsonb(row_value)::text) from public.school_personal_cash_income_linkage_events row_value
    where id='9de972ff-8e66-470a-8b05-e430ef51562f'));

select lot.id package_lot_id,lot.origin_planned_lesson_id,
  lot.initial_minutes,lot.consumed_minutes,lot.remaining_minutes
from public.school_student_package_credit_lots lot
where lot.id='2a000000-0000-4000-8000-202608170002' \gset package_
select pg_temp.phase2ca_assert(
  :'package_origin_planned_lesson_id'::uuid='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
  and :'package_initial_minutes'::integer=1200
  and :'package_consumed_minutes'::integer=0
  and :'package_remaining_minutes'::integer=1200,
  '26 P002 deployed lot is still the exact 1200/0/1200-minute authority');
select pg_temp.phase2ca_assert(
  (select initial_minutes=1200 and consumed_minutes=0 and remaining_minutes=1200
   from public.school_student_package_credit_lots
   where id=:'package_package_lot_id'::uuid),
  '28/29 package reader authority starts at 1200 and consumed remains zero');

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
select * from public.school_list_student_package_credit_lots(
  'a7b163a0-201e-4867-9b94-372343356a80'
) \gset package_reader_
reset role;
select pg_temp.phase2ca_assert(:'package_reader_remaining_minutes'::integer=1200,
  '28 authenticated read-only package reader returns 1200 minutes');

select pg_temp.phase2ca_expect_error($sql$
  insert into public.school_student_package_credit_lots(
    id,origin_planned_lesson_id,student_id,business_entity_id,initial_minutes,
    consumed_minutes,unit_price_jpy,total_price_jpy,student_billing_month,
    tuition_bill_id,tuition_revision_id,income_record_id,cash_linkage_event_id,
    cash_request_id_snapshot,cash_transaction_id_snapshot,status,
    classification_reason,origin_lesson_row_md5,evidence_manifest_sha256,classified_by
  ) select '2b000000-0000-4000-8000-202608170002'::uuid,
    origin_planned_lesson_id,student_id,business_entity_id,initial_minutes,
    0,unit_price_jpy,total_price_jpy,student_billing_month,tuition_bill_id,
    tuition_revision_id,income_record_id,cash_linkage_event_id,
    cash_request_id_snapshot,cash_transaction_id_snapshot,status,
    'duplicate must reject',origin_lesson_row_md5,repeat('a',64),classified_by
  from public.school_student_package_credit_lots limit 1$sql$,
  'school_package_credit_lots_active_origin_uidx',
  '27 one active package lot per origin is unique');

select pg_temp.phase2ca_assert(
  public.school_get_lesson_credit_raw_remaining_hours(
    '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9')=0
  and public.school_get_lesson_credit_remaining_hours(
    '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9')=0,
  '30 raw/public ordinary pending readers return zero for P002');
select pg_temp.phase2ca_assert(not exists(
  select 1 from public.school_list_open_lesson_credit_sources(
    '2026-07','2026-07','2026-07') source
  where source.id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'),
  '31 makeup source dropdown reader excludes P002');

set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
do $makeup_reject$
begin
  begin
    perform * from public.school_create_lesson_credit_makeup_actual(
      '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9','2026-08-17',
      'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd',
      'ed258e2b-81e4-4268-9682-124f310fbdf9','13:00','15:00',2,
      'package forbidden fixture','codex-test Phase2C-A',1,'onsite','fixture');
    raise exception 'EXPECTED_PACKAGE_MAKEUP_DENIAL_MISSING';
  exception when others then
    if sqlerrm='EXPECTED_PACKAGE_MAKEUP_DENIAL_MISSING'
       or position('LESSON_PACKAGE_CREDIT_MAKEUP_FORBIDDEN' in sqlerrm)=0 then raise; end if;
  end;
end
$makeup_reject$;
reset role;
select pg_temp.phase2ca_assert(
  (select count(*)=0 from public.school_lesson_records
   where planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'),
  '32 package origin makeup writer rejects before creating actual');

select pg_temp.phase2ca_assert(not exists(
  select 1 from public.school_tuition_p0f_source_lines(
    'a7b163a0-201e-4867-9b94-372343356a80',
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-07',0.045,false)
  where source_planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'),
  '33/34 registered variance and net source helper exclude P002 -20h/-JPY260000');
select public.school_tuition_p0f_assert_sources_resolved(
  'a7b163a0-201e-4867-9b94-372343356a80',
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-07');
select pg_temp.phase2ca_assert(true,
  '35 unresolved planned guard is not blocked by P002 pending_makeup status');

select pg_temp.phase2ca_assert(
  (select row_md5=(select md5(to_jsonb(row_value)::text)
      from public.school_lesson_records row_value
      where id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9')
   from phase2ca_before where object_name='lesson')
  and (select row_md5=(select md5(to_jsonb(row_value)::text)
      from public.school_student_tuition_bills row_value
      where id='07a02092-9503-47d1-9000-106f7e3de7e5')
   from phase2ca_before where object_name='bill')
  and (select row_md5=(select md5(to_jsonb(row_value)::text)
      from public.school_student_tuition_generation_revisions row_value
      where id='96000000-0000-4000-8000-202608031004')
   from phase2ca_before where object_name='revision')
  and (select row_md5=(select md5(to_jsonb(row_value)::text)
      from public.school_income_records row_value
      where id='91756564-c48d-4a1d-b6bc-88a041660e46')
   from phase2ca_before where object_name='income')
  and (select row_md5=(select md5(to_jsonb(row_value)::text)
      from public.school_personal_cash_income_linkage_events row_value
      where id='9de972ff-8e66-470a-8b05-e430ef51562f')
   from phase2ca_before where object_name='cash'),
  '36 original planned, bill, revision, income, and Cash evidence are byte-stable');

select pg_temp.phase2ca_assert(
  not exists(
    select 1 from pg_proc procedure
    where procedure.pronamespace='public'::regnamespace
      and procedure.proname ~ 'package.*(consume|reserve)|(consume|reserve).*package'
      and (has_function_privilege('authenticated',procedure.oid,'EXECUTE')
        or has_function_privilege('service_role',procedure.oid,'EXECUTE'))
  )
  and not has_table_privilege('authenticated',
    'public.school_student_package_credit_lots','UPDATE'),
  '37 no authenticated/service-role package consumption or reservation writer exists');
select pg_temp.phase2ca_assert(
  (select count(*)=0 from public.school_lesson_records
   where planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'),
  '37 no package actual means no wage candidate is introduced');

select count(*) as passed_package_assertions from phase2ca_assertions;
rollback;
