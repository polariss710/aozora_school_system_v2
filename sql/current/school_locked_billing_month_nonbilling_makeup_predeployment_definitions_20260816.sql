-- Exact predeployment definitions captured read-only from School production on 2026-08-16.
-- Source MD5: makeup e6de3be6719e88c7da9b451e40f3b7c7; cancellation
-- 73ac1abeebb6ce82870f9e0f8240629b; actual attribution
-- 60e380b560b0682dd78aa97139382d65.
CREATE OR REPLACE FUNCTION public.school_create_lesson_credit_makeup_actual(p_planned_lesson_id uuid, p_lesson_date date, p_teacher_id uuid, p_subject_id uuid, p_start_time text, p_end_time text, p_duration_hours numeric, p_lesson_content text, p_note text DEFAULT NULL::text, p_lesson_count integer DEFAULT NULL::integer, p_lesson_delivery_mode text DEFAULT NULL::text, p_lesson_venue text DEFAULT NULL::text)
 RETURNS SETOF school_lesson_records
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.school_create_cancelled_actual_lesson_from_planned(p_planned_lesson_id uuid, p_lesson_date date DEFAULT NULL::date, p_start_time text DEFAULT NULL::text, p_end_time text DEFAULT NULL::text, p_duration_hours numeric DEFAULT NULL::numeric, p_unit_price numeric DEFAULT NULL::numeric, p_lesson_count integer DEFAULT NULL::integer, p_lesson_content text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS TABLE(lesson_id uuid, lesson_type text, lesson_date date, year_month text, student_id uuid, teacher_id uuid, subject_id uuid, business_entity_id uuid, start_time text, end_time text, duration_hours numeric, unit_price numeric, lesson_fee numeric, status text, is_billable boolean, lesson_count integer, actual_minutes integer, planned_lesson_id uuid, teacher_settlement_month text, lesson_content text, note text, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_membership_role text;
  v_membership_active boolean;
  v_planned public.school_lesson_records%rowtype;
  v_lesson_date date;
  v_start_time text;
  v_end_time text;
  v_start_value time;
  v_end_value time;
  v_duration_hours numeric;
  v_unit_price numeric;
  v_lesson_count integer;
  v_lesson_content text;
  v_note text;
  v_student_settlement_month text;
  v_teacher_settlement_month text;
  v_actual_id uuid;
  v_student_business_entity_id uuid;
BEGIN
  PERFORM public.school_assert_active_lesson_writer();
  if v_actor is null then
    raise exception using errcode='42501', message='LESSON_CANCELLATION_AUTH_REQUIRED';
  end if;

  select membership.role, membership.is_active
  into v_membership_role, v_membership_active
  from public.school_app_memberships membership
  where membership.user_id = v_actor;

  if not found then
    raise exception using errcode='42501', message='LESSON_CANCELLATION_MEMBERSHIP_REQUIRED';
  end if;
  if v_membership_active is distinct from true then
    raise exception using errcode='42501', message='LESSON_CANCELLATION_ACTIVE_MEMBERSHIP_REQUIRED';
  end if;
  if v_membership_role not in ('admin','operator') then
    raise exception using errcode='42501', message='LESSON_CANCELLATION_ROLE_REQUIRED';
  end if;

  if p_planned_lesson_id is null then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_SOURCE_REQUIRED';
  end if;

  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_planned_lesson_id);

  select planned.*
  into v_planned
  from public.school_lesson_records planned
  where planned.id = p_planned_lesson_id
    and planned.app_type = 'school'
  for update;

  if not found then
    raise exception using errcode='P0002', message='LESSON_CANCELLATION_SOURCE_NOT_FOUND';
  end if;
  if v_planned.lesson_type <> 'planned' then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_SOURCE_TYPE_INVALID';
  end if;
  if v_planned.voided_at is not null then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_SOURCE_VOIDED';
  end if;

  if exists (
    select 1
    from public.school_lesson_records actual
    where actual.app_type = 'school'
      and actual.lesson_type = 'actual'
      and actual.planned_lesson_id = v_planned.id
  ) then
    raise exception using errcode='P0001', message='LESSON_CANCELLATION_LINKED_ACTUAL_EXISTS';
  end if;

  if v_planned.status <> 'planned' then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_SOURCE_STATUS_INVALID';
  end if;
  if v_planned.student_id is null
     or v_planned.teacher_id is null
     or v_planned.subject_id is null
     or v_planned.business_entity_id is null then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_SOURCE_MASTER_REQUIRED';
  end if;

  v_lesson_date := coalesce(p_lesson_date, v_planned.lesson_date);
  if v_lesson_date is null then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_DATE_REQUIRED';
  end if;

  v_start_time := coalesce(
    nullif(trim(coalesce(p_start_time, '')), ''),
    nullif(trim(coalesce(v_planned.start_time, '')), '')
  );
  v_end_time := coalesce(
    nullif(trim(coalesce(p_end_time, '')), ''),
    nullif(trim(coalesce(v_planned.end_time, '')), '')
  );
  if v_start_time is null or v_end_time is null then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_TIME_REQUIRED';
  end if;
  if v_start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_START_TIME_INVALID';
  end if;
  if v_end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_END_TIME_INVALID';
  end if;

  v_start_value := v_start_time::time;
  v_end_value := v_end_time::time;
  if extract(minute from v_start_value)::integer % 15 <> 0
     or extract(minute from v_end_value)::integer % 15 <> 0 then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_TIME_GRID_INVALID';
  end if;
  if v_end_value <= v_start_value then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_TIME_RANGE_INVALID';
  end if;

  v_start_time := to_char(v_start_value, 'HH24:MI');
  v_end_time := to_char(v_end_value, 'HH24:MI');
  v_duration_hours := extract(epoch from (v_end_value - v_start_value))::numeric / 3600;
  if p_duration_hours is not null
     and p_duration_hours is distinct from v_duration_hours then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_DURATION_MISMATCH';
  end if;

  v_unit_price := coalesce(p_unit_price, v_planned.unit_price, 0);
  v_lesson_count := coalesce(p_lesson_count, v_planned.lesson_count);
  v_lesson_content := coalesce(
    nullif(trim(coalesce(p_lesson_content, '')), ''),
    v_planned.lesson_content
  );
  v_note := coalesce(nullif(trim(coalesce(p_note, '')), ''), v_planned.note);

  if v_unit_price < 0 then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_UNIT_PRICE_INVALID';
  end if;
  if v_lesson_count is not null and v_lesson_count <= 0 then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_COUNT_INVALID';
  end if;

  select student.business_entity_id
  into v_student_business_entity_id
  from public.school_students student
  where student.id = v_planned.student_id
    and student.app_type = 'school';

  if not found then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_STUDENT_INACTIVE';
  end if;
  if v_student_business_entity_id is not null
     and v_student_business_entity_id is distinct from v_planned.business_entity_id then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_STUDENT_ENTITY_MISMATCH';
  end if;
  if not exists (
    select 1
    from public.school_teachers teacher
    where teacher.id = v_planned.teacher_id
      and teacher.app_type = 'school'
      and coalesce(teacher.status, 'employed') not in ('inactive', 'retired')
  ) then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_TEACHER_INACTIVE';
  end if;
  if not exists (
    select 1
    from public.school_subjects subject
    where subject.id = v_planned.subject_id
      and coalesce(subject.is_active, true)
  ) then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_SUBJECT_INACTIVE';
  end if;
  if not exists (
    select 1
    from public.school_business_entities entity
    where entity.id = v_planned.business_entity_id
      and coalesce(entity.is_active, true)
  ) then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_ENTITY_INACTIVE';
  end if;

  v_student_settlement_month :=
    public.school_resolve_r1d_e_c_lesson_student_month(v_planned.id);
  if v_student_settlement_month is null then
    raise exception using errcode='22023', message='LESSON_OPERATION_SCOPE_UNCLASSIFIED';
  end if;

  if exists (
    select 1
    from public.school_student_monthly_settlements settlement
    where settlement.student_id = v_planned.student_id
      and settlement.year_month = v_student_settlement_month
      and settlement.business_entity_id is not distinct from v_planned.business_entity_id
      and public.school_tuition_p0a_consumed_bill_id(settlement.id) is not null
  ) then
    raise exception using errcode='P0001', message='LESSON_FINANCIAL_FACT_IMMUTABLE';
  end if;

  if exists (
    select 1
    from public.school_student_monthly_settlements settlement
    where settlement.student_id = v_planned.student_id
      and settlement.year_month = v_student_settlement_month
      and settlement.business_entity_id is not distinct from v_planned.business_entity_id
      and settlement.settlement_status = 'locked'
  ) then
    raise exception using errcode='P0001', message='LESSON_CANCELLATION_STUDENT_SETTLEMENT_LOCKED';
  end if;

  v_teacher_settlement_month := to_char(v_lesson_date, 'YYYY-MM');
  if exists (
    select 1
    from public.school_teacher_wage_locks wage_lock
    where wage_lock.teacher_id = v_planned.teacher_id
      and wage_lock.business_entity_id is not distinct from v_planned.business_entity_id
      and wage_lock.settlement_month = v_teacher_settlement_month
      and wage_lock.status = 'locked'
  ) then
    raise exception using errcode='P0001', message='LESSON_CANCELLATION_TEACHER_WAGE_LOCKED';
  end if;

  insert into public.school_lesson_records (
    lesson_type, lesson_date, year_month, student_id, teacher_id, subject_id,
    business_entity_id, start_time, end_time, duration_hours, lesson_content,
    status, is_billable, note, app_type, planned_lesson_id, unit_price,
    lesson_fee, import_batch_id, import_source, imported_at, lesson_count,
    actual_minutes, teacher_settlement_month
  ) values (
    'actual', v_lesson_date, v_planned.year_month, v_planned.student_id,
    v_planned.teacher_id, v_planned.subject_id, v_planned.business_entity_id,
    v_start_time, v_end_time, v_duration_hours, v_lesson_content, 'cancelled',
    false, v_note, 'school', v_planned.id, v_unit_price, 0, null, null, null,
    v_lesson_count, 0, v_teacher_settlement_month
  ) returning id into v_actual_id;

  update public.school_lesson_records
  set status = 'pending_makeup'
  where id = v_planned.id;

  return query
  select
    actual.id, actual.lesson_type, actual.lesson_date, actual.year_month,
    actual.student_id, actual.teacher_id, actual.subject_id,
    actual.business_entity_id, actual.start_time, actual.end_time,
    actual.duration_hours, actual.unit_price, actual.lesson_fee, actual.status,
    actual.is_billable, actual.lesson_count, actual.actual_minutes,
    actual.planned_lesson_id, actual.teacher_settlement_month,
    actual.lesson_content, actual.note, actual.created_at, actual.updated_at
  from public.school_lesson_records actual
  where actual.id = v_actual_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.school_enforce_r1d_e_b2_actual_attribution()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_source public.school_lesson_records%ROWTYPE;
  v_evidence public.school_legacy_actual_settlement_evidence%ROWTYPE;
  v_student_month text;
  v_old_teacher_month text;
  v_new_teacher_month text;
  v_has_legacy_evidence boolean;
  v_is_exact_correction boolean:=false;
BEGIN
  IF TG_OP='INSERT' THEN
    IF NEW.lesson_type<>'actual' THEN
      RETURN NEW;
    END IF;
    IF NEW.app_type<>'school' THEN
      RAISE EXCEPTION 'R1D_E_B2_NON_SCHOOL_ACTUAL_REJECTED';
    END IF;
    SELECT p.* INTO v_source FROM public.school_lesson_records p
    WHERE p.id=NEW.planned_lesson_id;
    IF NOT FOUND OR v_source.status NOT IN ('planned','pending_makeup') THEN
      RAISE EXCEPTION 'R1D_E_B2_ACTUAL_SOURCE_STATUS_INVALID';
    END IF;
    v_student_month:=public.school_resolve_r1d_e_b2_actual_student_month(
      NEW.planned_lesson_id);
    IF NEW.student_id IS DISTINCT FROM v_source.student_id
       OR NEW.business_entity_id IS DISTINCT FROM v_source.business_entity_id THEN
      RAISE EXCEPTION 'R1D_E_B2_ACTUAL_SOURCE_STUDENT_ENTITY_MISMATCH';
    END IF;
    IF num_nonnulls(NEW.billing_month,NEW.billing_week_start_date,
         NEW.billing_month_source,NEW.billing_month_decided_at)<>0 THEN
      RAISE EXCEPTION 'R1D_E_B2_ACTUAL_BILLING_BUNDLE_FORBIDDEN';
    END IF;

    NEW.student_settlement_month:=v_student_month;
    NEW.year_month:=v_student_month;
    NEW.teacher_settlement_month:=to_char(NEW.lesson_date,'YYYY-MM');

    IF EXISTS (SELECT 1 FROM public.school_student_monthly_settlements s
               WHERE s.student_id=NEW.student_id
                 AND s.business_entity_id IS NOT DISTINCT FROM NEW.business_entity_id
                 AND s.year_month=v_student_month AND s.settlement_status='locked') THEN
      RAISE EXCEPTION 'R1D_E_B2_STUDENT_SETTLEMENT_LOCKED';
    END IF;
    IF EXISTS (SELECT 1 FROM public.school_teacher_wage_locks w
               WHERE w.teacher_id=NEW.teacher_id
                 AND w.business_entity_id IS NOT DISTINCT FROM NEW.business_entity_id
                 AND w.settlement_month=NEW.teacher_settlement_month
                 AND w.status='locked') THEN
      RAISE EXCEPTION 'R1D_E_B2_TEACHER_WAGE_MONTH_LOCKED';
    END IF;
    RETURN NEW;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.school_legacy_actual_settlement_evidence e
    WHERE e.actual_lesson_id=OLD.id
  ) INTO v_has_legacy_evidence;

  IF OLD.lesson_type='actual' OR v_has_legacy_evidence THEN
    IF OLD.lesson_type IS DISTINCT FROM 'actual'
       OR OLD.app_type IS DISTINCT FROM 'school'
       OR NEW.lesson_type IS DISTINCT FROM 'actual'
       OR NEW.app_type IS DISTINCT FROM 'school' THEN
      RAISE EXCEPTION 'R1D_E_B2_ACTUAL_TYPE_OR_APP_IMMUTABLE';
    END IF;
  ELSE
    IF NEW.lesson_type<>'actual' THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'R1D_E_B2_PLANNED_TO_ACTUAL_UPDATE_REJECTED';
  END IF;

  IF OLD.lesson_type<>'actual' OR OLD.app_type<>'school'
     OR NEW.planned_lesson_id IS DISTINCT FROM OLD.planned_lesson_id
     OR NEW.student_id IS DISTINCT FROM OLD.student_id
     OR NEW.business_entity_id IS DISTINCT FROM OLD.business_entity_id THEN
    RAISE EXCEPTION 'R1D_E_B2_ACTUAL_SOURCE_STUDENT_ENTITY_IMMUTABLE';
  END IF;

  SELECT e.* INTO v_evidence
  FROM public.school_legacy_actual_settlement_evidence e
  WHERE e.actual_lesson_id=OLD.id;

  v_is_exact_correction:=
    current_setting('app.school_lesson_exact_correction_context',true)
      ='li_wu_2026_09_11_test_lessons_void_v1_20260806'
    AND current_setting('app.school_lesson_exact_correction_manifest',true)
      ='e2bc9f4380f5bf5a95ff0341ae47183b'
    AND current_setting('app.school_lesson_exact_correction_action',true)
      ='exact_void_correction'
    AND current_setting('app.school_lesson_exact_correction_actor',true)=auth.uid()::text
    AND EXISTS(SELECT 1 FROM public.school_app_memberships m
      WHERE m.user_id=auth.uid() AND m.role='admin' AND m.is_active)
    AND OLD.id=ANY(ARRAY[
      'e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid,
      'b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid,
      'dc06b98c-360f-4661-a294-52ecb82830a7'::uuid,
      'c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid
    ])
    AND md5(to_jsonb(OLD)::text)=CASE OLD.id
      WHEN 'e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid THEN '68a2e384c0da181bbc514899899e1bf1'
      WHEN 'b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid THEN '97667b2d7b8bd485e7571c7ca12306d8'
      WHEN 'dc06b98c-360f-4661-a294-52ecb82830a7'::uuid THEN 'b111085217eff6410f34895722068117'
      WHEN 'c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid THEN '34ecb1210e1c65d2e35f0b8165b97d06'
    END
    AND OLD.voided_at IS NULL AND OLD.void_reason IS NULL
    AND NEW.voided_at IS NOT NULL
    AND NEW.void_reason=
      '业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。'
    AND (to_jsonb(NEW)-ARRAY['voided_at','void_reason','updated_at'])
        IS NOT DISTINCT FROM
        (to_jsonb(OLD)-ARRAY['voided_at','void_reason','updated_at']);

  IF FOUND THEN
    IF NOT v_is_exact_correction AND (
       OLD.student_settlement_month IS NOT NULL OR NEW.student_settlement_month IS NOT NULL
       OR NEW.planned_lesson_id IS DISTINCT FROM v_evidence.source_planned_lesson_id
       OR NEW.student_id IS DISTINCT FROM v_evidence.student_id_snapshot
       OR NEW.business_entity_id IS DISTINCT FROM v_evidence.business_entity_id_snapshot
       OR NEW.teacher_id IS DISTINCT FROM v_evidence.teacher_id_snapshot
       OR NEW.subject_id IS DISTINCT FROM v_evidence.subject_id_snapshot
       OR NEW.year_month IS DISTINCT FROM v_evidence.legacy_year_month
       OR NEW.teacher_settlement_month IS DISTINCT FROM v_evidence.teacher_settlement_month_snapshot
       OR NEW.lesson_date IS DISTINCT FROM v_evidence.lesson_date_snapshot
       OR md5(concat_ws('|',NEW.id::text,NEW.planned_lesson_id::text,
          NEW.student_id::text,NEW.business_entity_id::text,
          coalesce(NEW.teacher_id::text,'<NULL>'),coalesce(NEW.subject_id::text,'<NULL>'),
          NEW.year_month,NEW.teacher_settlement_month,NEW.lesson_date::text,
          NEW.lesson_type,NEW.app_type)) IS DISTINCT FROM v_evidence.actual_identity_md5
    ) THEN
      RAISE EXCEPTION 'R1D_E_B2_LEGACY_ACTUAL_ATTRIBUTION_IMMUTABLE';
    END IF;
    IF NOT v_is_exact_correction AND
       (to_jsonb(NEW)-ARRAY['note','lesson_content','lesson_delivery_mode',
          'lesson_venue','updated_at']) IS DISTINCT FROM
       (to_jsonb(OLD)-ARRAY['note','lesson_content','lesson_delivery_mode',
          'lesson_venue','updated_at']) THEN
      RAISE EXCEPTION 'R1D_E_B2_LEGACY_ACTUAL_ONLY_NONATTRIBUTION_CONTENT_EDIT_ALLOWED';
    END IF;
    v_student_month:=v_evidence.legacy_year_month;
    v_old_teacher_month:=v_evidence.teacher_settlement_month_snapshot;
    v_new_teacher_month:=v_old_teacher_month;
  ELSE
    IF OLD.student_settlement_month IS NULL
       OR NEW.student_settlement_month IS DISTINCT FROM OLD.student_settlement_month
       OR num_nonnulls(NEW.billing_month,NEW.billing_week_start_date,
            NEW.billing_month_source,NEW.billing_month_decided_at)<>0 THEN
      RAISE EXCEPTION 'R1D_E_B2_CANONICAL_ACTUAL_STUDENT_MONTH_IMMUTABLE';
    END IF;
    v_student_month:=public.school_resolve_r1d_e_b2_actual_student_month(
      OLD.planned_lesson_id);
    IF v_student_month IS DISTINCT FROM OLD.student_settlement_month THEN
      RAISE EXCEPTION 'R1D_E_B2_CANONICAL_ACTUAL_SOURCE_MONTH_DRIFT';
    END IF;
    NEW.year_month:=OLD.student_settlement_month;
    NEW.teacher_settlement_month:=to_char(NEW.lesson_date,'YYYY-MM');
    v_old_teacher_month:=OLD.teacher_settlement_month;
    v_new_teacher_month:=NEW.teacher_settlement_month;
  END IF;

  IF EXISTS (SELECT 1 FROM public.school_student_monthly_settlements s
             WHERE s.student_id=OLD.student_id
               AND s.business_entity_id IS NOT DISTINCT FROM OLD.business_entity_id
               AND s.year_month=v_student_month AND s.settlement_status='locked') THEN
    RAISE EXCEPTION 'R1D_E_B2_STUDENT_SETTLEMENT_LOCKED';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_teacher_wage_lock_details d
             JOIN public.school_teacher_wage_locks w ON w.id=d.lock_id
             WHERE d.lesson_record_id=OLD.id AND w.status='locked'
               AND w.voided_at IS NULL) THEN
    RAISE EXCEPTION 'R1D_E_B2_ACTIVE_WAGE_DETAIL_LOCKED';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_teacher_wage_locks w
             WHERE w.teacher_id=OLD.teacher_id
               AND w.business_entity_id IS NOT DISTINCT FROM OLD.business_entity_id
               AND w.settlement_month=v_old_teacher_month AND w.status='locked')
     OR EXISTS (SELECT 1 FROM public.school_teacher_wage_locks w
                WHERE w.teacher_id=NEW.teacher_id
                  AND w.business_entity_id IS NOT DISTINCT FROM NEW.business_entity_id
                  AND w.settlement_month=v_new_teacher_month AND w.status='locked') THEN
    RAISE EXCEPTION 'R1D_E_B2_TEACHER_WAGE_MONTH_LOCKED';
  END IF;
  RETURN NEW;
END
$function$
;

revoke all on function public.school_enforce_r1d_e_b2_actual_attribution()
  from public,anon,authenticated,service_role;
revoke all on function public.school_create_lesson_credit_makeup_actual(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) from public,anon,authenticated,service_role;
grant execute on function public.school_create_lesson_credit_makeup_actual(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) to authenticated;
revoke all on function public.school_create_cancelled_actual_lesson_from_planned(
  uuid,date,text,text,numeric,numeric,integer,text,text
) from public,anon,authenticated,service_role;
grant execute on function public.school_create_cancelled_actual_lesson_from_planned(
  uuid,date,text,text,numeric,numeric,integer,text,text
) to authenticated;
