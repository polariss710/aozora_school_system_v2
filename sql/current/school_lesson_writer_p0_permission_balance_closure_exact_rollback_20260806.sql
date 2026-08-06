-- Exact rollback for lesson writer P0 function/trigger/comment/ACL changes.
-- No business-row DML. Do not execute unless an authorized rollback is required.
\set ON_ERROR_STOP on
\pset pager off

\if :{?lesson_writer_p0_rollback_rehearsal}
\else
begin;
\endif
set local lock_timeout='10s';
set local statement_timeout='300s';

\if false
create or replace function pg_temp.school_lesson_p0_remove_assertion(
  p_signature regprocedure,
  p_expected_post_md5 text,
  p_expected_pre_md5 text
) returns void
language plpgsql
set search_path=pg_catalog,public
as $function$
declare v_definition text; v_restored text;
begin
  select pg_get_functiondef(p_signature::oid) into strict v_definition;
  if md5(v_definition)<>p_expected_post_md5 then
    raise exception 'LESSON_WRITER_P0_ROLLBACK_POST_DRIFT:%:%',p_signature,md5(v_definition);
  end if;
  v_restored:=replace(v_definition,
    E'  PERFORM public.school_assert_active_lesson_writer();\n','');
  if v_restored=v_definition then
    raise exception 'LESSON_WRITER_P0_ROLLBACK_ASSERTION_MISSING:%',p_signature;
  end if;
  execute v_restored;
  if md5(pg_get_functiondef(p_signature::oid))<>p_expected_pre_md5 then
    raise exception 'LESSON_WRITER_P0_ROLLBACK_RESTORE_MISMATCH:%:%:%',
      p_signature,md5(pg_get_functiondef(p_signature::oid)),p_expected_pre_md5;
  end if;
end;
$function$;

select pg_temp.school_lesson_p0_remove_assertion('public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)','316c3b49bc1ab3950e9e61468c66d845','ff5181679cda96b26d2f27c17f6b9665');
select pg_temp.school_lesson_p0_remove_assertion('public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)','73ac1abeebb6ce82870f9e0f8240629b','e1d7414424dada7e1a77c0130c67d159');
select pg_temp.school_lesson_p0_remove_assertion('public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)','1475b36ade440630f7d1064cc24ff367','5727fa8abbb3037dfbcbff1ae06ddacd');
select pg_temp.school_lesson_p0_remove_assertion('public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer)','aa125b26f2dcb343d4234a2dd61a448a','38948f596feeb0511b7fe47fab83bf1c');
select pg_temp.school_lesson_p0_remove_assertion('public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text)','e76bdfe1bb8b914b4ec1777bb38aa60e','c39a922627781ebddd23a92b7ad3df99');
select pg_temp.school_lesson_p0_remove_assertion('public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)','f02b4bd86d0e9c4e65cc94264785e53f','b84dab8220d68fbbac03d164bf18f0f9');
select pg_temp.school_lesson_p0_remove_assertion('public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text,integer)','ebc17dcd785e724509fa43147ff8a718','1971e5640741560c4bd19b62c3ab9e7e');
select pg_temp.school_lesson_p0_remove_assertion('public.school_void_planned_lesson(uuid,timestamp with time zone,text)','4989ed14d7507ef346b9c1791cbc3a6b','dbe640d07fdb2c39a64c240af0f46396');
select pg_temp.school_lesson_p0_remove_assertion('public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean)','5e5f720bbc2bfcea67d0ff98699a79fb','9391d23a4933c7944a5013aca341a5c6');
\endif
\ir school_lesson_writer_p0_original_canonical_definitions_20260806.sql

do $verify_canonical_restore$
begin
  if md5(pg_get_functiondef('public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure))<>'ff5181679cda96b26d2f27c17f6b9665'
     or md5(pg_get_functiondef('public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure))<>'e1d7414424dada7e1a77c0130c67d159'
     or md5(pg_get_functiondef('public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure))<>'5727fa8abbb3037dfbcbff1ae06ddacd'
     or md5(pg_get_functiondef('public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer)'::regprocedure))<>'38948f596feeb0511b7fe47fab83bf1c'
     or md5(pg_get_functiondef('public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure))<>'c39a922627781ebddd23a92b7ad3df99'
     or md5(pg_get_functiondef('public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure))<>'b84dab8220d68fbbac03d164bf18f0f9'
     or md5(pg_get_functiondef('public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text,integer)'::regprocedure))<>'1971e5640741560c4bd19b62c3ab9e7e'
     or md5(pg_get_functiondef('public.school_void_planned_lesson(uuid,timestamp with time zone,text)'::regprocedure))<>'dbe640d07fdb2c39a64c240af0f46396'
     or md5(pg_get_functiondef('public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean)'::regprocedure))<>'9391d23a4933c7944a5013aca341a5c6' then
    raise exception 'LESSON_WRITER_P0_ROLLBACK_CANONICAL_MD5_MISMATCH';
  end if;
end;
$verify_canonical_restore$;

create or replace function public.school_create_lesson_credit_makeup_actual(
  p_planned_lesson_id uuid,p_lesson_date date,p_teacher_id uuid,p_subject_id uuid,
  p_start_time text,p_end_time text,p_duration_hours numeric,p_lesson_content text,
  p_note text default null,p_lesson_count integer default null,
  p_lesson_delivery_mode text default null,p_lesson_venue text default null
) returns setof public.school_lesson_records
language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare
  v_planned public.school_lesson_records%rowtype;
  v_student_settlement_month text;
  v_teacher_settlement_month text;
  v_remaining_hours numeric;
  v_actual_id uuid;
  v_teacher_id uuid;
  v_subject_id uuid;
  v_content text;
  v_note text;
  v_start_time text;
  v_end_time text;
  v_delivery_mode text;
  v_venue text;
begin
  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_planned_lesson_id);
  if p_planned_lesson_id is null then raise exception '请选择待补课来源。'; end if;
  select p.* into v_planned from public.school_lesson_records p
  where p.id=p_planned_lesson_id and p.app_type='school' and p.lesson_type='planned'
  for update;
  if not found then raise exception '待补课来源不存在。'; end if;
  if v_planned.voided_at is not null then raise exception '待补课来源已作废。'; end if;
  if v_planned.status<>'pending_makeup' then raise exception '只有待补课预定课时可以使用课时余额。'; end if;
  if v_planned.student_id is null or v_planned.business_entity_id is null then raise exception '待补课来源缺少学生或业务归属。'; end if;
  select public.school_get_lesson_credit_remaining_hours(v_planned.id) into v_remaining_hours;
  p_duration_hours:=coalesce(p_duration_hours,v_remaining_hours);
  if p_duration_hours is null or p_duration_hours<=0 then raise exception '补课完成时长必须大于 0。'; end if;
  if coalesce(v_remaining_hours,0)<=0 then raise exception '该待补课来源已无剩余课时。'; end if;
  if p_duration_hours>v_remaining_hours then raise exception '补课时长超过剩余课时：剩余 % 小时。',v_remaining_hours; end if;
  p_lesson_date:=coalesce(p_lesson_date,v_planned.lesson_date);
  v_teacher_id:=coalesce(p_teacher_id,v_planned.teacher_id);
  v_subject_id:=coalesce(p_subject_id,v_planned.subject_id);
  v_start_time:=coalesce(nullif(trim(coalesce(p_start_time,'')),''),v_planned.start_time);
  v_end_time:=coalesce(nullif(trim(coalesce(p_end_time,'')),''),v_planned.end_time);
  v_content:=coalesce(nullif(trim(coalesce(p_lesson_content,'')),''),v_planned.lesson_content);
  v_note:=nullif(trim(coalesce(p_note,'')),'');
  v_delivery_mode:=coalesce(nullif(trim(coalesce(p_lesson_delivery_mode,'')),''),v_planned.lesson_delivery_mode);
  v_venue:=coalesce(nullif(trim(coalesce(p_lesson_venue,'')),''),v_planned.lesson_venue);
  if v_teacher_id is null or not exists(select 1 from public.school_teachers t where t.id=v_teacher_id and t.app_type='school' and coalesce(t.status,'employed') not in ('inactive','retired')) then raise exception '请选择有效老师。'; end if;
  if v_subject_id is null or not exists(select 1 from public.school_subjects s where s.id=v_subject_id and coalesce(s.is_active,true)) then raise exception '请选择有效科目。'; end if;
  if not exists(select 1 from public.school_business_entities b where b.id=v_planned.business_entity_id and coalesce(b.is_active,true)) then raise exception '来源业务归属无效。'; end if;
  if not exists(select 1 from public.school_students s where s.id=v_planned.student_id and s.app_type='school' and (s.business_entity_id is null or s.business_entity_id=v_planned.business_entity_id)) then raise exception '来源学生无效或业务归属不一致。'; end if;
  if v_start_time is null or v_start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception '开始时间必填且必须为 HH:MM。'; end if;
  if v_end_time is null or v_end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception '结束时间必填且必须为 HH:MM。'; end if;
  if v_end_time::time<=v_start_time::time then raise exception '结束时间必须晚于开始时间。'; end if;
  if v_content is null then raise exception '补课内容必填。'; end if;
  if v_delivery_mode not in ('online','onsite') then raise exception '授课方式必须为 online 或 onsite。'; end if;
  if v_delivery_mode='onsite' and v_venue not in ('Regus公共区','Regus办公室') then raise exception '线下补课场地只能为 Regus公共区 或 Regus办公室。请先在来源课时补齐场地。'; end if;
  if p_lesson_count is not null and p_lesson_count<=0 then raise exception '课次数必须大于 0。'; end if;
  v_student_settlement_month:=public.school_resolve_r1d_e_b2_actual_student_month(v_planned.id);
  v_teacher_settlement_month:=to_char(p_lesson_date,'YYYY-MM');
  if exists(select 1 from public.school_student_monthly_settlements s where s.student_id=v_planned.student_id and s.year_month=v_student_settlement_month and s.business_entity_id is not distinct from v_planned.business_entity_id and s.settlement_status='locked') then raise exception '补课来源学生月度结算已锁定。'; end if;
  if exists(select 1 from public.school_teacher_wage_locks w where w.teacher_id=v_teacher_id and w.business_entity_id is not distinct from v_planned.business_entity_id and w.settlement_month=v_teacher_settlement_month and w.status='locked') then raise exception '补课老师的目标工资月份已锁定。'; end if;
  insert into public.school_lesson_records(
    lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
    is_billable,note,app_type,planned_lesson_id,unit_price,lesson_fee,lesson_count,
    actual_minutes,teacher_settlement_month,lesson_delivery_mode,lesson_venue,
    student_settlement_month
  ) values(
    'actual',p_lesson_date,v_student_settlement_month,v_planned.student_id,
    v_teacher_id,v_subject_id,v_planned.business_entity_id,v_start_time,v_end_time,
    p_duration_hours,v_content,'makeup_completed',false,v_note,'school',v_planned.id,
    coalesce(v_planned.unit_price,0),0,coalesce(p_lesson_count,v_planned.lesson_count),
    round(p_duration_hours*60)::integer,v_teacher_settlement_month,v_delivery_mode,
    v_venue,v_student_settlement_month
  ) returning id into v_actual_id;
  return query select a.* from public.school_lesson_records a where a.id=v_actual_id;
end;
$function$;
-- Overwrite the readable semantic copy above with the exact predeploy
-- pg_get_functiondef capture so definition MD5 is restored byte-for-byte.
\ir school_lesson_writer_p0_original_makeup_definition_20260806.sql
do $verify_makeup_restore$
begin
  if md5(pg_get_functiondef(
       'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
     ))<>'23ee5d41a11f8a7b6ebf46283f3b0f6a' then
    raise exception 'LESSON_WRITER_P0_ROLLBACK_MAKEUP_MD5_MISMATCH';
  end if;
end;
$verify_makeup_restore$;

comment on function public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text) is
  'Phase B3: makeup fulfilment of an existing planned/source fact is not student-status-gated; student month stays source-owned and teacher month stays actual-date-owned.';
comment on function public.school_create_makeup_completed_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text) is
  'Compatibility wrapper for school_create_lesson_credit_makeup_actual. Legacy fee and billable inputs are ignored; makeup is always non-billable student lesson-credit consumption.';
comment on function public.school_create_cross_month_makeup_completed_actual_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text) is
  'Compatibility wrapper for school_create_lesson_credit_makeup_actual. Legacy fee and billable inputs are ignored; makeup may be cross-month and is always non-billable student lesson-credit consumption.';

-- Restore every predeploy ACL exactly.
revoke all on function public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text) from public,anon,authenticated,service_role;
grant execute on function public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text) to anon,authenticated,service_role;
revoke all on function public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text) from public,anon,authenticated,service_role;
grant execute on function public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text) to authenticated;
revoke all on function public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text) from public,anon,authenticated,service_role;
grant execute on function public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text) to anon,authenticated,service_role;
revoke all on function public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text) from public,anon,authenticated,service_role;
grant execute on function public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text) to anon,authenticated,service_role;
revoke all on function public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer) from public,anon,authenticated,service_role;
grant execute on function public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer) to anon,authenticated,service_role;
revoke all on function public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text) to authenticated,service_role;
revoke all on function public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text) to authenticated,service_role;
revoke all on function public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text,integer) from public,anon,authenticated,service_role;
grant execute on function public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text,integer) to authenticated,service_role;
revoke all on function public.school_void_planned_lesson(uuid,timestamp with time zone,text) from public,anon,authenticated,service_role;
grant execute on function public.school_void_planned_lesson(uuid,timestamp with time zone,text) to anon,authenticated,service_role;
revoke all on function public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean) from public,anon,authenticated,service_role;
grant execute on function public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean) to authenticated,service_role;

do $restore_legacy_acl$
declare sig regprocedure;
begin
  for sig in select unnest(array[
    'public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure,
    'public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,integer)'::regprocedure,
    'public.school_create_makeup_completed_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure,
    'public.school_create_cross_month_makeup_completed_actual_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure,
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure
  ]::regprocedure[])
  loop execute format('grant execute on function %s to anon,authenticated,service_role',sig); end loop;
  for sig in select unnest(array[
    'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text)'::regprocedure,
    'public.school_generate_planned_lessons_batch(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,integer)'::regprocedure,
    'public.school_void_planned_lesson_after_tuition_void(uuid,timestamp with time zone,text,text)'::regprocedure
  ]::regprocedure[])
  loop execute format('grant execute on function %s to authenticated,service_role',sig); end loop;
  grant execute on function public.school_replace_unconsumed_makeup_actual_v1(uuid,timestamp with time zone,uuid,date,text,text) to service_role;
end;
$restore_legacy_acl$;

drop trigger trg_school_lesson_writer_p0_validate on public.school_lesson_records;
drop function public.school_lesson_writer_p0_validate_row();
drop function public.school_get_lesson_credit_raw_remaining_hours(uuid);
drop function public.school_assert_active_lesson_writer();
notify pgrst,'reload schema';
\if :{?lesson_writer_p0_rollback_rehearsal}
\else
commit;
\endif
