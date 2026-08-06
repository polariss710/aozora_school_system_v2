CREATE OR REPLACE FUNCTION public.school_create_lesson_credit_makeup_actual(p_planned_lesson_id uuid, p_lesson_date date, p_teacher_id uuid, p_subject_id uuid, p_start_time text, p_end_time text, p_duration_hours numeric, p_lesson_content text, p_note text DEFAULT NULL::text, p_lesson_count integer DEFAULT NULL::integer, p_lesson_delivery_mode text DEFAULT NULL::text, p_lesson_venue text DEFAULT NULL::text)
 RETURNS SETOF school_lesson_records
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_planned public.school_lesson_records%ROWTYPE;
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
BEGIN
  PERFORM public.school_tuition_p0b1_lock_existing_lesson_scope(p_planned_lesson_id);
  IF p_planned_lesson_id IS NULL THEN
    RAISE EXCEPTION '请选择待补课来源。';
  END IF;
  SELECT p.* INTO v_planned
  FROM public.school_lesson_records p
  WHERE p.id=p_planned_lesson_id
    AND p.app_type='school' AND p.lesson_type='planned'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '待补课来源不存在。';
  END IF;
  IF v_planned.voided_at IS NOT NULL THEN
    RAISE EXCEPTION '待补课来源已作废。';
  END IF;
  IF v_planned.status<>'pending_makeup' THEN
    RAISE EXCEPTION '只有待补课预定课时可以使用课时余额。';
  END IF;
  IF v_planned.student_id IS NULL OR v_planned.business_entity_id IS NULL THEN
    RAISE EXCEPTION '待补课来源缺少学生或业务归属。';
  END IF;

  SELECT public.school_get_lesson_credit_remaining_hours(v_planned.id)
  INTO v_remaining_hours;
  p_duration_hours:=coalesce(p_duration_hours,v_remaining_hours);
  IF p_duration_hours IS NULL OR p_duration_hours<=0 THEN
    RAISE EXCEPTION '补课完成时长必须大于 0。';
  END IF;
  IF coalesce(v_remaining_hours,0)<=0 THEN
    RAISE EXCEPTION '该待补课来源已无剩余课时。';
  END IF;
  IF p_duration_hours>v_remaining_hours THEN
    RAISE EXCEPTION '补课时长超过剩余课时：剩余 % 小时。',v_remaining_hours;
  END IF;

  p_lesson_date:=coalesce(p_lesson_date,v_planned.lesson_date);
  v_teacher_id:=coalesce(p_teacher_id,v_planned.teacher_id);
  v_subject_id:=coalesce(p_subject_id,v_planned.subject_id);
  v_start_time:=coalesce(nullif(trim(coalesce(p_start_time,'')),''),v_planned.start_time);
  v_end_time:=coalesce(nullif(trim(coalesce(p_end_time,'')),''),v_planned.end_time);
  v_content:=coalesce(nullif(trim(coalesce(p_lesson_content,'')),''),v_planned.lesson_content);
  v_note:=nullif(trim(coalesce(p_note,'')),'');
  v_delivery_mode:=coalesce(nullif(trim(coalesce(p_lesson_delivery_mode,'')),''),
    v_planned.lesson_delivery_mode);
  v_venue:=coalesce(nullif(trim(coalesce(p_lesson_venue,'')),''),v_planned.lesson_venue);

  IF v_teacher_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.school_teachers t
    WHERE t.id=v_teacher_id AND t.app_type='school'
      AND coalesce(t.status,'employed') NOT IN ('inactive','retired')) THEN
    RAISE EXCEPTION '请选择有效老师。';
  END IF;
  IF v_subject_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.school_subjects s
    WHERE s.id=v_subject_id AND coalesce(s.is_active,true)) THEN
    RAISE EXCEPTION '请选择有效科目。';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.school_business_entities b
    WHERE b.id=v_planned.business_entity_id AND coalesce(b.is_active,true)) THEN
    RAISE EXCEPTION '来源业务归属无效。';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.school_students s
    WHERE s.id=v_planned.student_id AND s.app_type='school'
      AND (s.business_entity_id IS NULL
        OR s.business_entity_id=v_planned.business_entity_id)) THEN
    RAISE EXCEPTION '来源学生无效或业务归属不一致。';
  END IF;
  IF v_start_time IS NULL
     OR v_start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
    RAISE EXCEPTION '开始时间必填且必须为 HH:MM。';
  END IF;
  IF v_end_time IS NULL
     OR v_end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
    RAISE EXCEPTION '结束时间必填且必须为 HH:MM。';
  END IF;
  IF v_end_time::time<=v_start_time::time THEN
    RAISE EXCEPTION '结束时间必须晚于开始时间。';
  END IF;
  IF v_content IS NULL THEN
    RAISE EXCEPTION '补课内容必填。';
  END IF;
  IF v_delivery_mode NOT IN ('online','onsite') THEN
    RAISE EXCEPTION '授课方式必须为 online 或 onsite。';
  END IF;
  IF v_delivery_mode='onsite' AND v_venue NOT IN ('Regus公共区','Regus办公室') THEN
    RAISE EXCEPTION '线下补课场地只能为 Regus公共区 或 Regus办公室。请先在来源课时补齐场地。';
  END IF;
  IF p_lesson_count IS NOT NULL AND p_lesson_count<=0 THEN
    RAISE EXCEPTION '课次数必须大于 0。';
  END IF;

  v_student_settlement_month:=
    public.school_resolve_r1d_e_b2_actual_student_month(v_planned.id);
  v_teacher_settlement_month:=to_char(p_lesson_date,'YYYY-MM');
  IF EXISTS (
    SELECT 1 FROM public.school_student_monthly_settlements s
    WHERE s.student_id=v_planned.student_id
      AND s.year_month=v_student_settlement_month
      AND s.business_entity_id IS NOT DISTINCT FROM v_planned.business_entity_id
      AND s.settlement_status='locked') THEN
    RAISE EXCEPTION '补课来源学生月度结算已锁定。';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.school_teacher_wage_locks w
    WHERE w.teacher_id=v_teacher_id
      AND w.business_entity_id IS NOT DISTINCT FROM v_planned.business_entity_id
      AND w.settlement_month=v_teacher_settlement_month
      AND w.status='locked') THEN
    RAISE EXCEPTION '补课老师的目标工资月份已锁定。';
  END IF;

  INSERT INTO public.school_lesson_records (
    lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,
    status,is_billable,note,app_type,planned_lesson_id,unit_price,
    lesson_fee,lesson_count,actual_minutes,teacher_settlement_month,
    lesson_delivery_mode,lesson_venue,student_settlement_month
  ) VALUES (
    'actual',p_lesson_date,v_student_settlement_month,v_planned.student_id,
    v_teacher_id,v_subject_id,v_planned.business_entity_id,v_start_time,
    v_end_time,p_duration_hours,v_content,'makeup_completed',false,
    v_note,'school',v_planned.id,coalesce(v_planned.unit_price,0),0,
    coalesce(p_lesson_count,v_planned.lesson_count),
    round(p_duration_hours*60)::integer,v_teacher_settlement_month,
    v_delivery_mode,v_venue,v_student_settlement_month
  ) RETURNING id INTO v_actual_id;

  -- R2-F-E1: the original charged planned row is the immutable credit source.
  -- Linked completed/makeup_completed actual duration consumes its balance;
  -- the source remains pending_makeup even when the remaining balance is zero.

  RETURN QUERY SELECT a.* FROM public.school_lesson_records a
  WHERE a.id=v_actual_id;
END
$function$;
