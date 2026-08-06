-- School V2 lesson writer P0 permission, credit and time authority closure.
-- Drafted 2026-08-06. Function/trigger/ACL only; no business-row DML.
--
-- Business-model expansion declaration
-- New tables: none.
-- New columns: none.
-- New enum/status values: none.
-- New date/month/attribution concepts: none.
-- New identity concepts: none; auth.uid + school_app_memberships remains authority.
-- New source/snapshot/version concepts: none.
-- New writable facts: none.
-- Changed existing-field semantics: duration_hours and actual_minutes for completed,
--   makeup_completed and cancelled actuals become DB-derived from start/end; expressly
--   approved by task sections IX and XXI.
-- Changed field mutability: user-reachable lesson writers are restricted to active
--   admin/operator and credit-consuming proposed states may not exceed entitlement;
--   expressly approved by task sections VI, VIII, X and XXI.
-- Changed writer authority: canonical interactive writers are authenticated-only;
--   internal/legacy writers are postgres-owner-only; expressly approved by sections VI/XII.
-- Changed locking rules: affected planned sources are locked in UUID order before raw
--   credit validation; expressly approved by sections VIII and X.
-- New authoritative sources: DB start/end difference is sole persisted duration/minute
--   authority for completed/makeup/cancelled actuals; expressly approved by section IX.
-- Legacy fallback/dual read/dual write/historical reinterpretation/destructive schema: none.

create or replace function public.school_assert_active_lesson_writer()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid := auth.uid();
  v_role text;
  v_active boolean;
  v_claims text := nullif(current_setting('request.jwt.claims',true),'');
begin
  -- A direct postgres maintenance session has no request JWT. PostgREST always has
  -- authenticator as session_user and therefore cannot enter this owner exception.
  if v_actor is null and session_user='postgres' and v_claims is null then
    return;
  end if;
  if v_actor is null then
    raise exception using errcode='42501',message='LESSON_WRITER_AUTH_REQUIRED';
  end if;

  select m.role,m.is_active into v_role,v_active
  from public.school_app_memberships m
  where m.user_id=v_actor;
  if not found then
    raise exception using errcode='42501',message='LESSON_WRITER_MEMBERSHIP_REQUIRED';
  end if;
  if v_active is distinct from true then
    raise exception using errcode='42501',message='LESSON_WRITER_ACTIVE_MEMBERSHIP_REQUIRED';
  end if;
  if v_role not in ('admin','operator') then
    raise exception using errcode='42501',message='LESSON_WRITER_ROLE_REQUIRED';
  end if;
end;
$function$;

revoke all on function public.school_assert_active_lesson_writer()
  from public,anon,authenticated,service_role;
comment on function public.school_assert_active_lesson_writer() is
  'Owner-only lesson writer assertion. PostgREST callers require auth.uid plus an active School admin/operator membership; only a direct postgres session without request JWT is an operational exception.';

create or replace function public.school_get_lesson_credit_raw_remaining_hours(
  p_planned_lesson_id uuid
)
returns numeric
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select p.duration_hours-coalesce(sum(a.duration_hours) filter (
    where a.lesson_type='actual'
      and a.status in ('completed','makeup_completed')
      and a.voided_at is null
  ),0)
  from public.school_lesson_records p
  left join public.school_lesson_records a on a.planned_lesson_id=p.id
  where p.id=p_planned_lesson_id
    and p.app_type='school'
    and p.lesson_type='planned'
  group by p.id,p.duration_hours
$function$;

revoke all on function public.school_get_lesson_credit_raw_remaining_hours(uuid)
  from public,anon,authenticated,service_role;
comment on function public.school_get_lesson_credit_raw_remaining_hours(uuid) is
  'Owner-only writer helper returning entitlement minus completed/makeup_completed consumption without clamping negative values. Not a public diagnostic reader.';

create or replace function public.school_lesson_writer_p0_validate_row()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_time_changed boolean:=false;
  v_credit_changed boolean:=false;
  v_start time;
  v_end time;
  v_minutes integer;
  v_hours numeric;
  v_old_source uuid;
  v_new_source uuid;
  v_current_actual uuid;
  v_source_id uuid;
  v_source public.school_lesson_records%rowtype;
  v_other_consumed numeric;
  v_proposed_consumed numeric;
  v_total_consumed numeric;
begin
  if new.app_type is distinct from 'school' then
    return new;
  end if;

  if tg_op='UPDATE' then
    v_old_source:=old.planned_lesson_id;
    v_current_actual:=old.id;
    v_time_changed:=(new.lesson_type,new.status,new.lesson_date,new.start_time,
      new.end_time,new.duration_hours,new.actual_minutes)
      is distinct from
      (old.lesson_type,old.status,old.lesson_date,old.start_time,
       old.end_time,old.duration_hours,old.actual_minutes);
    v_credit_changed:=(new.lesson_type,new.status,new.planned_lesson_id,new.duration_hours,
      new.is_billable,new.lesson_fee,new.voided_at)
      is distinct from
      (old.lesson_type,old.status,old.planned_lesson_id,old.duration_hours,
       old.is_billable,old.lesson_fee,old.voided_at);
  else
    v_time_changed:=true;
    v_credit_changed:=true;
  end if;
  v_new_source:=new.planned_lesson_id;

  if new.lesson_type='actual' then
    if new.status in ('completed','makeup_completed','cancelled') and v_time_changed then
      if new.lesson_date is null then
        raise exception using errcode='22023',message='LESSON_TIME_DATE_REQUIRED';
      end if;
      if new.start_time is null
         or new.start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
        raise exception using errcode='22023',message='LESSON_TIME_START_INVALID';
      end if;
      if new.end_time is null
         or new.end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
        raise exception using errcode='22023',message='LESSON_TIME_END_INVALID';
      end if;
      v_start:=new.start_time::time;
      v_end:=new.end_time::time;
      if extract(minute from v_start)::integer%15<>0
         or extract(minute from v_end)::integer%15<>0 then
        raise exception using errcode='22023',message='LESSON_TIME_GRID_INVALID';
      end if;
      if v_end<=v_start then
        raise exception using errcode='22023',message='LESSON_TIME_RANGE_INVALID';
      end if;
      v_minutes:=extract(epoch from (v_end-v_start))::integer/60;
      v_hours:=v_minutes::numeric/60;
      if new.duration_hours is null or new.duration_hours is distinct from v_hours then
        raise exception using errcode='22023',message='LESSON_DURATION_MISMATCH',
          detail=format('provided=%s db_hours=%s',new.duration_hours,v_hours);
      end if;
      new.start_time:=to_char(v_start,'HH24:MI');
      new.end_time:=to_char(v_end,'HH24:MI');
      new.duration_hours:=v_hours;
      if new.status='cancelled' then
        new.actual_minutes:=0;
      else
        new.actual_minutes:=v_minutes;
      end if;
    end if;

    if new.status='cancelled' then
      new.is_billable:=false;
      new.lesson_fee:=0;
      new.actual_minutes:=0;
    elsif new.status='makeup_completed' then
      new.is_billable:=false;
      new.lesson_fee:=0;
      if v_time_changed then new.actual_minutes:=v_minutes; end if;
    end if;

    if v_credit_changed then
      for v_source_id in
        select distinct source_id
        from unnest(array[v_old_source,v_new_source]::uuid[]) source_id
        where source_id is not null
        order by source_id
      loop
        select p.* into v_source
        from public.school_lesson_records p
        where p.id=v_source_id
        for update;
        if not found or v_source.app_type<>'school'
           or v_source.lesson_type<>'planned'
           or v_source.voided_at is not null then
          if new.planned_lesson_id=v_source_id
             and new.lesson_type='actual'
             and new.status='makeup_completed'
             and new.voided_at is null then
            raise exception using errcode='22023',
              message='LESSON_MAKEUP_SOURCE_INVALID';
          end if;
          continue;
        end if;
        if v_source.status<>'pending_makeup' then
          if new.planned_lesson_id=v_source_id
             and new.lesson_type='actual'
             and new.status='makeup_completed'
             and new.voided_at is null then
            raise exception using errcode='22023',
              message='LESSON_MAKEUP_SOURCE_STATUS_INVALID';
          end if;
          continue;
        end if;

        select coalesce(sum(a.duration_hours),0) into v_other_consumed
        from public.school_lesson_records a
        where a.app_type='school' and a.lesson_type='actual'
          and a.planned_lesson_id=v_source_id
          and a.status in ('completed','makeup_completed')
          and a.voided_at is null
          and (v_current_actual is null or a.id<>v_current_actual);

        v_proposed_consumed:=case
          when new.planned_lesson_id=v_source_id
           and new.lesson_type='actual'
           and new.status in ('completed','makeup_completed')
           and new.voided_at is null
          then new.duration_hours else 0 end;
        v_total_consumed:=v_other_consumed+coalesce(v_proposed_consumed,0);
        if v_other_consumed>v_source.duration_hours then
          raise exception using errcode='P0001',
            message='LESSON_MAKEUP_CREDIT_DATA_INCONSISTENT',
            detail=format('planned_id=%s entitlement=%s other_consumed=%s',
              v_source.id,v_source.duration_hours,v_other_consumed);
        end if;
        if v_total_consumed>v_source.duration_hours then
          raise exception using errcode='P0001',message='LESSON_MAKEUP_CREDIT_EXCEEDED',
            detail=format('planned_id=%s entitlement=%s proposed_consumed=%s',
              v_source.id,v_source.duration_hours,v_total_consumed);
        end if;
      end loop;
    end if;
  elsif new.lesson_type='planned' and tg_op='UPDATE'
        and (new.duration_hours,new.status,new.voided_at)
          is distinct from (old.duration_hours,old.status,old.voided_at)
        and (old.status='pending_makeup' or new.status='pending_makeup') then
    select coalesce(sum(a.duration_hours),0) into v_total_consumed
    from public.school_lesson_records a
    where a.app_type='school' and a.lesson_type='actual'
      and a.planned_lesson_id=new.id
      and a.status in ('completed','makeup_completed')
      and a.voided_at is null;
    if v_total_consumed>new.duration_hours then
      raise exception using errcode='P0001',message='LESSON_MAKEUP_CREDIT_EXCEEDED',
        detail=format('planned_id=%s entitlement=%s proposed_consumed=%s',
          new.id,new.duration_hours,v_total_consumed);
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function public.school_lesson_writer_p0_validate_row()
  from public,anon,authenticated,service_role;

create trigger trg_school_lesson_writer_p0_validate
before insert or update of lesson_type,status,lesson_date,start_time,end_time,
  duration_hours,actual_minutes,planned_lesson_id,is_billable,lesson_fee,voided_at
on public.school_lesson_records
for each row execute function public.school_lesson_writer_p0_validate_row();

comment on function public.school_lesson_writer_p0_validate_row() is
  'P0 row guard: relevant actual writes use DB time-derived duration/minutes; cancelled and makeup facts are zero-fee/non-billable; pending-makeup sources cannot enter a negative proposed raw balance. Content/note-only edits do not revalidate frozen legacy anomalies.';

-- Insert the common identity assertion at the first statement of every current
-- browser/API canonical writer. Each replacement is protected by the production
-- predefinition MD5 captured immediately before this phase.
create or replace function pg_temp.school_lesson_p0_prepend_assertion(
  p_signature regprocedure,
  p_expected_md5 text
)
returns text
language plpgsql
set search_path=pg_catalog,public
as $function$
declare
  v_definition text;
  v_replaced text;
begin
  select pg_get_functiondef(p_signature::oid) into strict v_definition;
  if md5(v_definition) is distinct from p_expected_md5 then
    raise exception 'LESSON_WRITER_P0_PREDEFINITION_DRIFT:%:%',
      p_signature,md5(v_definition);
  end if;
  if position('school_assert_active_lesson_writer()' in v_definition)>0 then
    raise exception 'LESSON_WRITER_P0_ASSERTION_ALREADY_PRESENT:%',p_signature;
  end if;
  v_replaced:=regexp_replace(
    v_definition,
    E'\nBEGIN\n',
    E'\nBEGIN\n  PERFORM public.school_assert_active_lesson_writer();\n',
    'i'
  );
  if v_replaced=v_definition
     or (length(v_replaced)-length(replace(v_replaced,
       'school_assert_active_lesson_writer()','')))
        /length('school_assert_active_lesson_writer()')<>1 then
    raise exception 'LESSON_WRITER_P0_ASSERTION_INSERT_FAILED:%',p_signature;
  end if;
  execute v_replaced;
  return md5(pg_get_functiondef(p_signature::oid));
end;
$function$;

select pg_temp.school_lesson_p0_prepend_assertion(
  'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure,
  'ff5181679cda96b26d2f27c17f6b9665');
select pg_temp.school_lesson_p0_prepend_assertion(
  'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure,
  'e1d7414424dada7e1a77c0130c67d159');
select pg_temp.school_lesson_p0_prepend_assertion(
  'public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure,
  '5727fa8abbb3037dfbcbff1ae06ddacd');
select pg_temp.school_lesson_p0_prepend_assertion(
  'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer)'::regprocedure,
  '38948f596feeb0511b7fe47fab83bf1c');
select pg_temp.school_lesson_p0_prepend_assertion(
  'public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,
  'c39a922627781ebddd23a92b7ad3df99');
select pg_temp.school_lesson_p0_prepend_assertion(
  'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure,
  'b84dab8220d68fbbac03d164bf18f0f9');
select pg_temp.school_lesson_p0_prepend_assertion(
  'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text,integer)'::regprocedure,
  '1971e5640741560c4bd19b62c3ab9e7e');
select pg_temp.school_lesson_p0_prepend_assertion(
  'public.school_void_planned_lesson(uuid,timestamp with time zone,text)'::regprocedure,
  'dbe640d07fdb2c39a64c240af0f46396');
select pg_temp.school_lesson_p0_prepend_assertion(
  'public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean)'::regprocedure,
  '9391d23a4933c7944a5013aca341a5c6');

-- Canonical makeup writer: common identity assertion, raw (unclamped) remaining,
-- DB-derived duration/minutes and stable credit errors.
do $pre_makeup$
begin
  if md5(pg_get_functiondef(
    'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
  ))<>'23ee5d41a11f8a7b6ebf46283f3b0f6a' then
    raise exception 'LESSON_WRITER_P0_MAKEUP_PREDEFINITION_DRIFT';
  end if;
end;
$pre_makeup$;

create or replace function public.school_create_lesson_credit_makeup_actual(
  p_planned_lesson_id uuid,
  p_lesson_date date,
  p_teacher_id uuid,
  p_subject_id uuid,
  p_start_time text,
  p_end_time text,
  p_duration_hours numeric,
  p_lesson_content text,
  p_note text default null,
  p_lesson_count integer default null,
  p_lesson_delivery_mode text default null,
  p_lesson_venue text default null
)
returns setof public.school_lesson_records
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_planned public.school_lesson_records%rowtype;
  v_student_settlement_month text;
  v_teacher_settlement_month text;
  v_raw_remaining numeric;
  v_actual_id uuid;
  v_teacher_id uuid;
  v_subject_id uuid;
  v_content text;
  v_note text;
  v_start_time text;
  v_end_time text;
  v_start_value time;
  v_end_value time;
  v_duration_hours numeric;
  v_actual_minutes integer;
  v_delivery_mode text;
  v_venue text;
begin
  perform public.school_assert_active_lesson_writer();
  if p_planned_lesson_id is null then
    raise exception using errcode='22023',message='LESSON_MAKEUP_SOURCE_REQUIRED';
  end if;
  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_planned_lesson_id);
  select p.* into v_planned
  from public.school_lesson_records p
  where p.id=p_planned_lesson_id and p.app_type='school' and p.lesson_type='planned'
  for update;
  if not found then
    raise exception using errcode='P0002',message='LESSON_MAKEUP_SOURCE_NOT_FOUND';
  end if;
  if v_planned.voided_at is not null then
    raise exception using errcode='22023',message='LESSON_MAKEUP_SOURCE_VOIDED';
  end if;
  if v_planned.status<>'pending_makeup' then
    raise exception using errcode='22023',message='LESSON_MAKEUP_SOURCE_STATUS_INVALID';
  end if;
  if v_planned.student_id is null or v_planned.business_entity_id is null then
    raise exception using errcode='22023',message='LESSON_MAKEUP_SOURCE_MASTER_REQUIRED';
  end if;

  select public.school_get_lesson_credit_raw_remaining_hours(v_planned.id)
    into v_raw_remaining;
  if v_raw_remaining<0 then
    raise exception using errcode='P0001',message='LESSON_MAKEUP_CREDIT_DATA_INCONSISTENT',
      detail=format('planned_id=%s raw_remaining=%s',v_planned.id,v_raw_remaining);
  end if;
  if v_raw_remaining=0 then
    raise exception using errcode='P0001',message='LESSON_MAKEUP_CREDIT_EXHAUSTED';
  end if;

  p_lesson_date:=coalesce(p_lesson_date,v_planned.lesson_date);
  if p_lesson_date is null then
    raise exception using errcode='22023',message='LESSON_TIME_DATE_REQUIRED';
  end if;
  v_teacher_id:=coalesce(p_teacher_id,v_planned.teacher_id);
  v_subject_id:=coalesce(p_subject_id,v_planned.subject_id);
  v_start_time:=coalesce(nullif(trim(coalesce(p_start_time,'')),''),v_planned.start_time);
  v_end_time:=coalesce(nullif(trim(coalesce(p_end_time,'')),''),v_planned.end_time);
  v_content:=coalesce(nullif(trim(coalesce(p_lesson_content,'')),''),v_planned.lesson_content);
  v_note:=nullif(trim(coalesce(p_note,'')),'');
  v_delivery_mode:=coalesce(nullif(trim(coalesce(p_lesson_delivery_mode,'')),''),v_planned.lesson_delivery_mode);
  v_venue:=coalesce(nullif(trim(coalesce(p_lesson_venue,'')),''),v_planned.lesson_venue);

  if v_start_time is null or v_start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception using errcode='22023',message='LESSON_TIME_START_INVALID';
  end if;
  if v_end_time is null or v_end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception using errcode='22023',message='LESSON_TIME_END_INVALID';
  end if;
  v_start_value:=v_start_time::time;
  v_end_value:=v_end_time::time;
  if extract(minute from v_start_value)::integer%15<>0
     or extract(minute from v_end_value)::integer%15<>0 then
    raise exception using errcode='22023',message='LESSON_TIME_GRID_INVALID';
  end if;
  if v_end_value<=v_start_value then
    raise exception using errcode='22023',message='LESSON_TIME_RANGE_INVALID';
  end if;
  v_actual_minutes:=extract(epoch from (v_end_value-v_start_value))::integer/60;
  v_duration_hours:=v_actual_minutes::numeric/60;
  if p_duration_hours is not null and p_duration_hours is distinct from v_duration_hours then
    raise exception using errcode='22023',message='LESSON_DURATION_MISMATCH',
      detail=format('provided=%s db_hours=%s',p_duration_hours,v_duration_hours);
  end if;
  v_start_time:=to_char(v_start_value,'HH24:MI');
  v_end_time:=to_char(v_end_value,'HH24:MI');

  if v_duration_hours>v_raw_remaining then
    raise exception using errcode='P0001',message='LESSON_MAKEUP_CREDIT_EXCEEDED',
      detail=format('planned_id=%s raw_remaining=%s requested=%s',
        v_planned.id,v_raw_remaining,v_duration_hours);
  end if;

  if v_teacher_id is null or not exists(
    select 1 from public.school_teachers t where t.id=v_teacher_id
      and t.app_type='school' and coalesce(t.status,'employed') not in ('inactive','retired')) then
    raise exception using errcode='22023',message='LESSON_MAKEUP_TEACHER_INVALID';
  end if;
  if v_subject_id is null or not exists(
    select 1 from public.school_subjects s where s.id=v_subject_id and coalesce(s.is_active,true)) then
    raise exception using errcode='22023',message='LESSON_MAKEUP_SUBJECT_INVALID';
  end if;
  if not exists(select 1 from public.school_business_entities b
    where b.id=v_planned.business_entity_id and coalesce(b.is_active,true)) then
    raise exception using errcode='22023',message='LESSON_MAKEUP_ENTITY_INVALID';
  end if;
  if not exists(select 1 from public.school_students s
    where s.id=v_planned.student_id and s.app_type='school'
      and (s.business_entity_id is null or s.business_entity_id=v_planned.business_entity_id)) then
    raise exception using errcode='22023',message='LESSON_MAKEUP_STUDENT_ENTITY_INVALID';
  end if;
  if v_content is null then
    raise exception using errcode='22023',message='LESSON_MAKEUP_CONTENT_REQUIRED';
  end if;
  if v_delivery_mode not in ('online','onsite') then
    raise exception using errcode='22023',message='LESSON_MAKEUP_DELIVERY_MODE_INVALID';
  end if;
  if v_delivery_mode='onsite' and v_venue not in ('Regus公共区','Regus办公室') then
    raise exception using errcode='22023',message='LESSON_MAKEUP_VENUE_INVALID';
  end if;
  if p_lesson_count is not null and p_lesson_count<=0 then
    raise exception using errcode='22023',message='LESSON_MAKEUP_COUNT_INVALID';
  end if;

  v_student_settlement_month:=public.school_resolve_r1d_e_b2_actual_student_month(v_planned.id);
  v_teacher_settlement_month:=to_char(p_lesson_date,'YYYY-MM');
  if exists(select 1 from public.school_student_monthly_settlements s
    where s.student_id=v_planned.student_id and s.year_month=v_student_settlement_month
      and s.business_entity_id is not distinct from v_planned.business_entity_id
      and s.settlement_status='locked') then
    raise exception using errcode='P0001',message='LESSON_MAKEUP_STUDENT_SETTLEMENT_LOCKED';
  end if;
  if exists(select 1 from public.school_teacher_wage_locks w
    where w.teacher_id=v_teacher_id
      and w.business_entity_id is not distinct from v_planned.business_entity_id
      and w.settlement_month=v_teacher_settlement_month and w.status='locked') then
    raise exception using errcode='P0001',message='LESSON_MAKEUP_TEACHER_WAGE_LOCKED';
  end if;

  insert into public.school_lesson_records(
    lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,
    status,is_billable,note,app_type,planned_lesson_id,unit_price,lesson_fee,
    lesson_count,actual_minutes,teacher_settlement_month,lesson_delivery_mode,
    lesson_venue,student_settlement_month
  ) values(
    'actual',p_lesson_date,v_student_settlement_month,v_planned.student_id,
    v_teacher_id,v_subject_id,v_planned.business_entity_id,v_start_time,v_end_time,
    v_duration_hours,v_content,'makeup_completed',false,v_note,'school',v_planned.id,
    coalesce(v_planned.unit_price,0),0,coalesce(p_lesson_count,v_planned.lesson_count),
    v_actual_minutes,v_teacher_settlement_month,v_delivery_mode,v_venue,
    v_student_settlement_month
  ) returning id into v_actual_id;

  -- The original charged planned row remains pending_makeup at zero balance.
  return query select a.* from public.school_lesson_records a where a.id=v_actual_id;
end;
$function$;

-- Canonical browser/API ABI: authenticated only; function entry assertion is mandatory.
revoke all on function public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer) from public,anon,authenticated,service_role;
grant execute on function public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer) to authenticated;
revoke all on function public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text) to authenticated;
revoke all on function public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text) to authenticated;
revoke all on function public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text,integer) from public,anon,authenticated,service_role;
grant execute on function public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text,integer) to authenticated;
revoke all on function public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text) from public,anon,authenticated,service_role;
grant execute on function public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text) to authenticated;
revoke all on function public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text) from public,anon,authenticated,service_role;
grant execute on function public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text) to authenticated;
revoke all on function public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text) from public,anon,authenticated,service_role;
grant execute on function public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text) to authenticated;
revoke all on function public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text) from public,anon,authenticated,service_role;
grant execute on function public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text) to authenticated;
revoke all on function public.school_void_planned_lesson(uuid,timestamp with time zone,text) from public,anon,authenticated,service_role;
grant execute on function public.school_void_planned_lesson(uuid,timestamp with time zone,text) to authenticated;
revoke all on function public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean) from public,anon,authenticated,service_role;
grant execute on function public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean) to authenticated;

-- Internal cores, superseded overloads, compatibility wrappers and operational tools.
-- They remain defined for dependency safety but are no longer PostgREST write ABI.
do $acl_closure$
declare
  v_signature regprocedure;
begin
  for v_signature in select unnest(array[
    'public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure,
    'public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,integer)'::regprocedure,
    'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text)'::regprocedure,
    'public.school_create_planned_lesson_record_r1d_f1_legacy_core(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure,
    'public.school_generate_planned_lessons_batch(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,
    'public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure,
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,integer)'::regprocedure,
    'public.school_p0c_baseline_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure,
    'public.school_create_makeup_completed_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure,
    'public.school_create_cross_month_makeup_completed_actual_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure,
    'public.school_import_lesson_records_batch(uuid,text,text,jsonb,text)'::regprocedure,
    'public.school_import_lesson_records_batch_with_venue(uuid,text,text,jsonb,text)'::regprocedure,
    'public.school_import_lesson_records_batch_r1d_f1_legacy_core(uuid,text,text,jsonb,text)'::regprocedure,
    'public.school_replace_unconsumed_makeup_actual_v1(uuid,timestamp with time zone,uuid,date,text,text)'::regprocedure,
    'public.school_void_planned_lesson_after_tuition_void(uuid,timestamp with time zone,text,text)'::regprocedure,
    'public.school_void_planned_lesson_p0f_legacy(uuid,timestamp with time zone,text)'::regprocedure,
    'public.school_backfill_actual_minutes_from_duration(text)'::regprocedure
  ]::regprocedure[])
  loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role',v_signature);
  end loop;
end;
$acl_closure$;

comment on function public.school_create_makeup_completed_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text) is
  'Deprecated owner-only legacy makeup ABI. Interactive callers must use school_create_lesson_credit_makeup_actual.';
comment on function public.school_create_cross_month_makeup_completed_actual_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text) is
  'Deprecated owner-only legacy cross-month makeup ABI. Interactive callers must use school_create_lesson_credit_makeup_actual.';
comment on function public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text) is
  'Canonical authenticated active-admin/operator makeup writer. Uses planned-scope locking, unclamped raw credit, DB-derived 15-minute time/duration/minutes, source-owned student month, actual-date teacher month, and fixed non-billable fee zero.';

notify pgrst,'reload schema';
