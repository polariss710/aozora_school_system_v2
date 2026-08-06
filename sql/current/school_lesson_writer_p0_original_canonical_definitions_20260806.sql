CREATE OR REPLACE FUNCTION public.school_create_actual_lesson_from_planned(p_planned_lesson_id uuid, p_lesson_date date DEFAULT NULL::date, p_start_time text DEFAULT NULL::text, p_end_time text DEFAULT NULL::text, p_duration_hours numeric DEFAULT NULL::numeric, p_unit_price numeric DEFAULT NULL::numeric, p_lesson_fee numeric DEFAULT NULL::numeric, p_lesson_count integer DEFAULT NULL::integer, p_lesson_content text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS TABLE(lesson_id uuid, lesson_type text, lesson_date date, year_month text, student_id uuid, teacher_id uuid, subject_id uuid, business_entity_id uuid, start_time text, end_time text, duration_hours numeric, unit_price numeric, lesson_fee numeric, status text, is_billable boolean, lesson_count integer, actual_minutes integer, planned_lesson_id uuid, teacher_settlement_month text, lesson_content text, note text, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_planned public.school_lesson_records%rowtype;
  v_lesson_date date;
  v_start_time text;
  v_end_time text;
  v_duration_hours numeric;
  v_unit_price numeric;
  v_lesson_fee numeric;
  v_lesson_count integer;
  v_lesson_content text;
  v_note text;
  v_actual_minutes integer;
  v_teacher_settlement_month text;
  v_actual_id uuid;
  v_student_business_entity_id uuid;
  v_overage_duration numeric;
  v_overage_minutes integer;
  v_overage_fee_jpy numeric;
  v_overage_source_student_month text;
  v_overage_target_student_month text;
  v_overage_policy_version text;
  v_overage_source text;
  v_overage_decided_at timestamptz;
begin
  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_planned_lesson_id);
  if p_planned_lesson_id is null then
    raise exception '请选择预定课时。';
  end if;

  select p.*
  into v_planned
  from public.school_lesson_records p
  where p.id = p_planned_lesson_id
    and p.app_type = 'school'
  for update;

  if not found then
    raise exception '预定课时不存在。';
  end if;

  if v_planned.lesson_type <> 'planned' then
    raise exception '只能从 planned 课时生成 actual。';
  end if;

  if v_planned.voided_at is not null then
    raise exception '该预定课时已作废，不能生成 completed actual。';
  end if;

  if v_planned.status not in ('planned', 'pending_makeup') then
    raise exception '当前 planned 状态不能生成 completed actual：%。', coalesce(v_planned.status, '');
  end if;

  if v_planned.student_id is null then
    raise exception '预定课时缺少学生，不能生成 actual。';
  end if;

  if v_planned.teacher_id is null then
    raise exception '预定课时缺少老师，不能生成 actual。';
  end if;

  if v_planned.subject_id is null then
    raise exception '预定课时缺少科目，不能生成 actual。';
  end if;

  if v_planned.business_entity_id is null then
    raise exception '预定课时缺少业务归属，不能生成 actual。';
  end if;

  if exists (
    select 1
    from public.school_lesson_records a
    where a.app_type = 'school'
      and a.lesson_type = 'actual'
      and a.planned_lesson_id = v_planned.id
  ) then
    raise exception '该预定课时已有关联 actual，不能重复生成。';
  end if;

  v_lesson_date := coalesce(p_lesson_date, v_planned.lesson_date);
  if v_lesson_date is null then
    raise exception '请选择实际课时日期。';
  end if;

  v_start_time := coalesce(nullif(trim(coalesce(p_start_time, '')), ''), nullif(trim(coalesce(v_planned.start_time, '')), ''));
  v_end_time := coalesce(nullif(trim(coalesce(p_end_time, '')), ''), nullif(trim(coalesce(v_planned.end_time, '')), ''));
  v_duration_hours := coalesce(p_duration_hours, v_planned.duration_hours, 0);
  v_unit_price := coalesce(p_unit_price, v_planned.unit_price, 0);
  v_lesson_count := coalesce(p_lesson_count, v_planned.lesson_count);
  v_lesson_content := coalesce(nullif(trim(coalesce(p_lesson_content, '')), ''), v_planned.lesson_content);
  v_note := coalesce(nullif(trim(coalesce(p_note, '')), ''), v_planned.note);

  if v_start_time is null then
    raise exception '开始时间必填。';
  end if;

  if v_end_time is null then
    raise exception '结束时间必填。';
  end if;

  if nullif(trim(coalesce(v_lesson_content, '')), '') is null then
    raise exception '内容必填。';
  end if;

  if v_duration_hours <= 0 then
    raise exception '实际课时时长必须大于 0。';
  end if;

  if v_planned.duration_hours is null or v_planned.duration_hours <= 0 then
    raise exception '来源预定课时时长无效，不能生成 actual。';
  elsif v_duration_hours < v_planned.duration_hours then
    raise exception '实际完成时长小于预定时长；部分完成请使用“部分完成，剩余转待补”流程。';
  elsif v_duration_hours > v_planned.duration_hours then
    if v_planned.business_entity_id is distinct from public.school_primary_business_entity_id() then
      raise exception 'S1_B_OVERAGE_PRIMARY_BUSINESS_ENTITY_REQUIRED';
    end if;

    if v_planned.is_billable is distinct from true then
      raise exception 'S1_B_OVERAGE_BILLABLE_SOURCE_REQUIRED';
    end if;

    if num_nonnulls(
         v_planned.billing_month,
         v_planned.billing_week_start_date,
         v_planned.student_settlement_month,
         v_planned.billing_month_source,
         v_planned.billing_month_decided_at
       ) = 5 then
      v_overage_source_student_month :=
        public.school_resolve_r1d_e_b2_actual_student_month(v_planned.id);
      if v_overage_source_student_month is distinct from v_planned.student_settlement_month then
        raise exception 'S1_B_OVERAGE_SOURCE_STUDENT_MONTH_INVALID';
      end if;
    elsif num_nonnulls(
         v_planned.billing_month,
         v_planned.billing_week_start_date,
         v_planned.student_settlement_month,
         v_planned.billing_month_source,
         v_planned.billing_month_decided_at
       ) = 0 then
      if (select count(*)
          from public.school_legacy_planned_settlement_evidence e
          where e.planned_lesson_id = v_planned.id
            and e.approved_manifest is true
            and e.evidence_source = 'r1d_e_b1_fixed_legacy_279'
            and e.evidence_version = 'legacy_settlement_evidence_v1') <> 1 then
        raise exception 'S1_B_OVERAGE_APPROVED_LEGACY_SOURCE_REQUIRED';
      end if;

      v_overage_source_student_month :=
        public.school_resolve_r1d_e_b2_actual_student_month(v_planned.id);
      if v_overage_source_student_month is distinct from (
           select e.legacy_student_settlement_month
           from public.school_legacy_planned_settlement_evidence e
           where e.planned_lesson_id = v_planned.id
         ) then
        raise exception 'S1_B_OVERAGE_LEGACY_SOURCE_MONTH_INVALID';
      end if;
    else
      raise exception 'S1_B_OVERAGE_PARTIAL_SOURCE_ATTRIBUTION_REJECTED';
    end if;

    if v_overage_source_student_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
      raise exception 'S1_B_OVERAGE_SOURCE_STUDENT_MONTH_INVALID';
    end if;

    v_overage_target_student_month := to_char(
      (to_date(v_overage_source_student_month || '-01', 'YYYY-MM-DD')
        + interval '1 month')::date,
      'YYYY-MM'
    );
    if v_overage_target_student_month = v_overage_source_student_month then
      raise exception 'S1_B_OVERAGE_TARGET_STUDENT_MONTH_INVALID';
    end if;

    if v_planned.unit_price is null or v_planned.unit_price <= 0 then
      raise exception 'S1_B_OVERAGE_SOURCE_UNIT_PRICE_REQUIRED';
    end if;

    v_overage_duration := v_duration_hours - v_planned.duration_hours;
    v_overage_minutes := round(v_overage_duration * 60)::integer;
    v_overage_fee_jpy := round(v_overage_duration * v_planned.unit_price);
    if v_overage_minutes <= 0 or v_overage_fee_jpy <= 0 then
      raise exception 'S1_B_OVERAGE_POSITIVE_AMOUNT_REQUIRED';
    end if;

    v_overage_policy_version := 'student_duration_overage_v1';
    v_overage_source := 'ordinary_actual_rpc';
    v_overage_decided_at := statement_timestamp();
  end if;

  if v_unit_price < 0 then
    raise exception '课程单价不能小于 0。';
  end if;

  if p_lesson_fee is null then
    v_lesson_fee := round(v_duration_hours * v_unit_price);
  else
    v_lesson_fee := p_lesson_fee;
  end if;

  if v_lesson_fee < 0 then
    raise exception '课时金额不能小于 0。';
  end if;

  if v_lesson_count is not null and v_lesson_count <= 0 then
    raise exception '课次数必须大于 0。';
  end if;

  if v_start_time is not null and v_start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception '开始时间格式无效，请使用 HH:MM。';
  end if;

  if v_end_time is not null and v_end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception '结束时间格式无效，请使用 HH:MM。';
  end if;

  select s.business_entity_id
  into v_student_business_entity_id
  from public.school_students s
  where s.id = v_planned.student_id
    and s.app_type = 'school';

  if not found then
    raise exception '学生无效或不可用。';
  end if;

  if v_student_business_entity_id is not null
    and v_student_business_entity_id is distinct from v_planned.business_entity_id then
    raise exception '学生默认业务归属与课时业务归属不一致。';
  end if;

  if not exists (
    select 1
    from public.school_teachers t
    where t.id = v_planned.teacher_id
      and t.app_type = 'school'
      and coalesce(t.status, 'employed') not in ('inactive', 'retired')
  ) then
    raise exception '老师无效或不可用。';
  end if;

  if not exists (
    select 1
    from public.school_subjects s
    where s.id = v_planned.subject_id
      and coalesce(s.is_active, true) = true
  ) then
    raise exception '科目无效或已停用。';
  end if;

  if not exists (
    select 1
    from public.school_business_entities b
    where b.id = v_planned.business_entity_id
      and coalesce(b.is_active, true) = true
  ) then
    raise exception '业务归属无效或已停用。';
  end if;

  if exists (
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = v_planned.student_id
      and s.year_month = coalesce(
        v_overage_source_student_month,
        public.school_resolve_r1d_e_c_lesson_student_month(v_planned.id)
      )
      and s.business_entity_id is not distinct from v_planned.business_entity_id
      and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能生成 actual。';
  end if;

  v_teacher_settlement_month := to_char(v_lesson_date, 'YYYY-MM');

  if exists (
    select 1
    from public.school_teacher_wage_locks w
    where w.teacher_id = v_planned.teacher_id
      and w.business_entity_id is not distinct from v_planned.business_entity_id
      and w.settlement_month = v_teacher_settlement_month
      and w.status = 'locked'
  ) then
    raise exception '目标老师工资月份已锁定，不能生成 actual。';
  end if;

  v_actual_minutes := round(v_duration_hours * 60)::integer;

  insert into public.school_lesson_records (
    lesson_type,
    lesson_date,
    year_month,
    student_id,
    teacher_id,
    subject_id,
    business_entity_id,
    start_time,
    end_time,
    duration_hours,
    lesson_content,
    status,
    is_billable,
    note,
    app_type,
    planned_lesson_id,
    unit_price,
    lesson_fee,
    import_batch_id,
    import_source,
    imported_at,
    lesson_count,
    actual_minutes,
    teacher_settlement_month,
    student_duration_overage_minutes,
    student_duration_overage_fee_jpy,
    student_duration_overage_policy_version,
    student_duration_overage_source,
    student_duration_overage_decided_at
  )
  values (
    'actual',
    v_lesson_date,
    v_planned.year_month,
    v_planned.student_id,
    v_planned.teacher_id,
    v_planned.subject_id,
    v_planned.business_entity_id,
    v_start_time,
    v_end_time,
    v_duration_hours,
    v_lesson_content,
    'completed',
    coalesce(v_planned.is_billable, true),
    v_note,
    'school',
    v_planned.id,
    v_unit_price,
    v_lesson_fee,
    null,
    null,
    null,
    v_lesson_count,
    v_actual_minutes,
    v_teacher_settlement_month,
    v_overage_minutes,
    v_overage_fee_jpy,
    v_overage_policy_version,
    v_overage_source,
    v_overage_decided_at
  )
  returning id into v_actual_id;

  return query
  select
    a.id,
    a.lesson_type,
    a.lesson_date,
    a.year_month,
    a.student_id,
    a.teacher_id,
    a.subject_id,
    a.business_entity_id,
    a.start_time,
    a.end_time,
    a.duration_hours,
    a.unit_price,
    a.lesson_fee,
    a.status,
    a.is_billable,
    a.lesson_count,
    a.actual_minutes,
    a.planned_lesson_id,
    a.teacher_settlement_month,
    a.lesson_content,
    a.note,
    a.created_at,
    a.updated_at
  from public.school_lesson_records a
  where a.id = v_actual_id;
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
begin
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

CREATE OR REPLACE FUNCTION public.school_create_partial_completed_actual_from_planned(p_planned_lesson_id uuid, p_lesson_date date, p_start_time text, p_end_time text, p_duration_hours numeric, p_lesson_content text, p_note text DEFAULT NULL::text)
 RETURNS SETOF school_lesson_records
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_planned public.school_lesson_records%rowtype;
  v_target_year_month text;
  v_actual_id uuid;
  v_content text;
  v_note text;
begin
  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_planned_lesson_id);
  if p_planned_lesson_id is null then
    raise exception '请选择预定课时。';
  end if;
  if p_lesson_date is null then
    raise exception '请选择实际完成日期。';
  end if;
  if p_duration_hours is null or p_duration_hours <= 0 then
    raise exception '实际完成时长必须大于 0。';
  end if;
  if p_start_time is null or p_start_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception '开始时间必填且必须为 HH:MM。';
  end if;
  if p_end_time is null or p_end_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception '结束时间必填且必须为 HH:MM。';
  end if;
  if p_end_time::time <= p_start_time::time then
    raise exception '结束时间必须晚于开始时间。';
  end if;

  select p.*
    into v_planned
  from public.school_lesson_records p
  where p.id = p_planned_lesson_id
    and p.app_type = 'school'
    and p.lesson_type = 'planned'
  for update;

  if not found then
    raise exception '预定课时不存在。';
  end if;
  if v_planned.voided_at is not null or v_planned.status <> 'planned' then
    raise exception '只有未处理的待上课预定课时可以登记部分完成。';
  end if;
  if p_duration_hours >= coalesce(v_planned.duration_hours, 0) then
    raise exception '部分完成时长必须小于原预定时长；完整上课请使用普通生成实际课时。';
  end if;
  if exists (
    select 1 from public.school_lesson_records a
    where a.app_type = 'school'
      and a.lesson_type = 'actual'
      and a.planned_lesson_id = v_planned.id
  ) then
    raise exception '该预定课时已有实际记录，不能再登记首次部分完成。';
  end if;
  if v_planned.student_id is null or v_planned.teacher_id is null
     or v_planned.subject_id is null or v_planned.business_entity_id is null then
    raise exception '预定课时缺少学生、老师、科目或业务归属。';
  end if;

  v_content := nullif(trim(coalesce(p_lesson_content, '')), '');
  v_note := nullif(trim(coalesce(p_note, '')), '');
  if v_content is null then
    raise exception '实际课时内容必填。';
  end if;
  if not exists (
    select 1 from public.school_students s
    where s.id = v_planned.student_id
      and s.app_type = 'school'
      and (s.business_entity_id is null or s.business_entity_id = v_planned.business_entity_id)
  ) then
    raise exception '学生无效或业务归属不一致。';
  end if;
  if not exists (
    select 1 from public.school_teachers t
    where t.id = v_planned.teacher_id
      and t.app_type = 'school'
      and coalesce(t.status, 'employed') not in ('inactive', 'retired')
  ) then
    raise exception '老师无效或不可用。';
  end if;
  if not exists (
    select 1 from public.school_subjects s
    where s.id = v_planned.subject_id and coalesce(s.is_active, true)
  ) then
    raise exception '科目无效或已停用。';
  end if;
  if not exists (
    select 1 from public.school_business_entities b
    where b.id = v_planned.business_entity_id and coalesce(b.is_active, true)
  ) then
    raise exception '业务归属无效。';
  end if;

  v_target_year_month := to_char(p_lesson_date, 'YYYY-MM');
  if exists (
    select 1 from public.school_student_monthly_settlements s
    where s.student_id = v_planned.student_id
      and s.year_month = public.school_resolve_r1d_e_c_lesson_student_month(
        v_planned.id
      )
      and s.business_entity_id is not distinct from v_planned.business_entity_id
      and s.settlement_status = 'locked'
  ) then
    raise exception '来源学生月度结算已锁定，不能登记部分完成。';
  end if;
  if exists (
    select 1 from public.school_teacher_wage_locks w
    where w.teacher_id = v_planned.teacher_id
      and w.business_entity_id is not distinct from v_planned.business_entity_id
      and w.settlement_month = v_target_year_month
      and w.status = 'locked'
  ) then
    raise exception '实际完成老师的目标工资月份已锁定。';
  end if;

  insert into public.school_lesson_records (
    lesson_type, lesson_date, year_month, student_id, teacher_id, subject_id,
    business_entity_id, start_time, end_time, duration_hours, lesson_content,
    status, is_billable, note, app_type, planned_lesson_id, unit_price,
    lesson_fee, lesson_count, actual_minutes, teacher_settlement_month,
    lesson_delivery_mode, lesson_venue
  ) values (
    'actual', p_lesson_date, v_planned.year_month, v_planned.student_id,
    v_planned.teacher_id, v_planned.subject_id, v_planned.business_entity_id,
    p_start_time, p_end_time, p_duration_hours, v_content, 'completed',
    coalesce(v_planned.is_billable, true), v_note, 'school', v_planned.id,
    coalesce(v_planned.unit_price, 0), round(p_duration_hours * coalesce(v_planned.unit_price, 0)),
    v_planned.lesson_count, round(p_duration_hours * 60)::integer,
    v_target_year_month, v_planned.lesson_delivery_mode, v_planned.lesson_venue
  ) returning id into v_actual_id;

  update public.school_lesson_records
     set status = 'pending_makeup'
   where id = v_planned.id;

  return query
  select a.* from public.school_lesson_records a where a.id = v_actual_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.school_create_planned_lesson_record_with_venue(p_lesson_date date, p_student_id uuid, p_teacher_id uuid, p_subject_id uuid, p_business_entity_id uuid, p_start_time text, p_end_time text, p_duration_hours numeric, p_unit_price numeric, p_lesson_fee numeric, p_status text, p_lesson_count integer, p_lesson_content text, p_note text, p_lesson_delivery_mode text, p_lesson_venue text, p_aircon_rate_jpy_per_hour integer)
 RETURNS SETOF school_lesson_records
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_row public.school_lesson_records%ROWTYPE;
BEGIN
  SELECT * INTO STRICT v_row
  FROM public.school_create_planned_lesson_record_with_venue(
    p_lesson_date,p_student_id,p_teacher_id,p_subject_id,p_business_entity_id,
    p_start_time,p_end_time,p_duration_hours,p_unit_price,p_lesson_fee,p_status,
    p_lesson_count,p_lesson_content,p_note,p_lesson_delivery_mode,p_lesson_venue
  );
  UPDATE public.school_lesson_records
  SET aircon_unit_price_jpy_snapshot = p_aircon_rate_jpy_per_hour
  WHERE id = v_row.id;
  RETURN QUERY SELECT * FROM public.school_lesson_records WHERE id = v_row.id;
END
$function$
;

CREATE OR REPLACE FUNCTION public.school_generate_planned_lessons_batch_with_venue(p_generation_id uuid, p_student_id uuid, p_business_entity_id uuid, p_start_date date, p_end_date date, p_patterns jsonb, p_excluded_occurrences jsonb DEFAULT '[]'::jsonb, p_note text DEFAULT NULL::text)
 RETURNS TABLE(row_index integer, pattern_index integer, lesson_date date, row_valid boolean, batch_committed boolean, created_lesson_id uuid, status text, warnings text[], errors text[], generation_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_result record;
  v_pattern jsonb;
  v_mode text;
  v_venue text;
begin
  if p_patterns is null or jsonb_typeof(p_patterns) <> 'array' then
    raise exception '课程规则必须是 JSON array。';
  end if;

  for v_pattern in
    select value
    from jsonb_array_elements(p_patterns)
  loop
    perform 1
    from public.school_normalize_lesson_schedule_venue(
      v_pattern ->> 'lesson_delivery_mode',
      v_pattern ->> 'lesson_venue'
    );
  end loop;

  for v_result in
    select *
    from public.school_generate_planned_lessons_batch(
      p_generation_id,
      p_student_id,
      p_business_entity_id,
      p_start_date,
      p_end_date,
      p_patterns,
      p_excluded_occurrences,
      p_note
    )
  loop
    if v_result.batch_committed and v_result.created_lesson_id is not null then
      select value
      into v_pattern
      from jsonb_array_elements(p_patterns)
      where (value ->> 'pattern_index')::integer = v_result.pattern_index
      limit 1;

      if not found then
        raise exception '无法匹配批量生成结果的课程规则：pattern_index=%。',
          v_result.pattern_index;
      end if;

      select n.lesson_delivery_mode, n.lesson_venue
      into v_mode, v_venue
      from public.school_normalize_lesson_schedule_venue(
        v_pattern ->> 'lesson_delivery_mode',
        v_pattern ->> 'lesson_venue'
      ) n;

      update public.school_lesson_records l
      set
        lesson_delivery_mode = v_mode,
        lesson_venue = v_venue,
        updated_at = now()
      where l.id = v_result.created_lesson_id;
    end if;

    row_index := v_result.row_index;
    pattern_index := v_result.pattern_index;
    lesson_date := v_result.lesson_date;
    row_valid := v_result.row_valid;
    batch_committed := v_result.batch_committed;
    created_lesson_id := v_result.created_lesson_id;
    status := v_result.status;
    warnings := v_result.warnings;
    errors := v_result.errors;
    generation_id := v_result.generation_id;
    return next;
  end loop;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.school_update_lesson_record_guarded_with_venue(p_lesson_id uuid, p_expected_updated_at timestamp with time zone, p_lesson_date date, p_student_id uuid, p_teacher_id uuid, p_subject_id uuid, p_business_entity_id uuid, p_start_time text DEFAULT NULL::text, p_end_time text DEFAULT NULL::text, p_duration_hours numeric DEFAULT 0, p_unit_price numeric DEFAULT 0, p_lesson_fee numeric DEFAULT NULL::numeric, p_status text DEFAULT NULL::text, p_is_billable boolean DEFAULT true, p_lesson_count integer DEFAULT NULL::integer, p_lesson_content text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_lesson_delivery_mode text DEFAULT NULL::text, p_lesson_venue text DEFAULT NULL::text)
 RETURNS SETOF school_lesson_records
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_lesson_id uuid;
  v_mode text;
  v_venue text;
  v_current_updated_at timestamptz;
  v_prepared_updated_at timestamptz;
begin
  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_lesson_id,p_student_id,p_business_entity_id,p_lesson_date);
  if p_lesson_id is null then
    raise exception '请选择要编辑的课时。';
  end if;

  if p_expected_updated_at is null then
    raise exception '缺少课时版本，请刷新页面后重试。';
  end if;

  select n.lesson_delivery_mode, n.lesson_venue
  into v_mode, v_venue
  from public.school_normalize_lesson_schedule_venue(
    p_lesson_delivery_mode,
    p_lesson_venue
  ) n;

  select l.updated_at
  into v_current_updated_at
  from public.school_lesson_records l
  where l.id = p_lesson_id
    and l.app_type = 'school'
  for update;

  if not found then
    raise exception '课时记录不存在。';
  end if;

  if v_current_updated_at is distinct from p_expected_updated_at then
    raise exception '课时记录已被其他操作更新，请刷新页面后重试。';
  end if;

  -- Prepare the normalized venue before calling the verified core updater.
  -- The table updated_at trigger advances the version, so capture that new
  -- value and pass it to the core optimistic-lock check. If the core rejects
  -- any business guard, this entire function call (including this update)
  -- rolls back atomically.
  update public.school_lesson_records l
  set
    lesson_delivery_mode = v_mode,
    lesson_venue = v_venue
  where l.id = p_lesson_id
  returning l.updated_at into v_prepared_updated_at;

  select u.lesson_id
  into v_lesson_id
  from public.school_update_lesson_record_guarded(
    p_lesson_id,
    v_prepared_updated_at,
    p_lesson_date,
    p_student_id,
    p_teacher_id,
    p_subject_id,
    p_business_entity_id,
    p_start_time,
    p_end_time,
    p_duration_hours,
    p_unit_price,
    p_lesson_fee,
    p_status,
    p_is_billable,
    p_lesson_count,
    p_lesson_content,
    p_note
  ) u;

  return query
  select l.*
  from public.school_lesson_records l
  where l.id = v_lesson_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.school_update_lesson_record_guarded_with_venue(p_lesson_id uuid, p_expected_updated_at timestamp with time zone, p_lesson_date date, p_student_id uuid, p_teacher_id uuid, p_subject_id uuid, p_business_entity_id uuid, p_start_time text, p_end_time text, p_duration_hours numeric, p_unit_price numeric, p_lesson_fee numeric, p_status text, p_is_billable boolean, p_lesson_count integer, p_lesson_content text, p_note text, p_lesson_delivery_mode text, p_lesson_venue text, p_aircon_rate_jpy_per_hour integer)
 RETURNS SETOF school_lesson_records
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_row public.school_lesson_records%ROWTYPE;
BEGIN
  SELECT * INTO STRICT v_row
  FROM public.school_update_lesson_record_guarded_with_venue(
    p_lesson_id,p_expected_updated_at,p_lesson_date,p_student_id,p_teacher_id,
    p_subject_id,p_business_entity_id,p_start_time,p_end_time,p_duration_hours,
    p_unit_price,p_lesson_fee,p_status,p_is_billable,p_lesson_count,
    p_lesson_content,p_note,p_lesson_delivery_mode,p_lesson_venue
  );
  UPDATE public.school_lesson_records
  SET aircon_unit_price_jpy_snapshot = p_aircon_rate_jpy_per_hour
  WHERE id = v_row.id;
  RETURN QUERY SELECT * FROM public.school_lesson_records WHERE id = v_row.id;
END
$function$
;

CREATE OR REPLACE FUNCTION public.school_void_planned_lesson(p_lesson_id uuid, p_expected_updated_at timestamp with time zone, p_void_reason text)
 RETURNS TABLE(lesson_id uuid, lesson_type text, status text, voided_at timestamp with time zone, void_reason text, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if exists(
    select 1
    from public.school_student_tuition_bill_lessons bl
    join public.school_student_tuition_generation_revisions r
      on r.tuition_bill_id=bl.tuition_bill_id
    where bl.planned_lesson_id=p_lesson_id and r.lifecycle_status='voided'
  ) then
    return query select *
    from public.school_void_planned_lesson_after_tuition_void(
      p_lesson_id,p_expected_updated_at,p_void_reason,
      'CONFIRM VOID PLANNED LESSON AFTER TUITION VOID'
    );
  else
    return query select *
    from public.school_void_planned_lesson_p0f_legacy(
      p_lesson_id,p_expected_updated_at,p_void_reason
    );
  end if;
end
$function$
;

CREATE OR REPLACE FUNCTION public.school_delete_fresh_planned_lesson(p_lesson_id uuid, p_expected_updated_at timestamp with time zone, p_confirm_delete boolean DEFAULT false)
 RETURNS TABLE(lesson_id uuid, lesson_date date, year_month text, student_id uuid, teacher_id uuid, subject_id uuid, business_entity_id uuid, deleted_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_lesson public.school_lesson_records%rowtype;
  v_deleted_at timestamptz := now();
begin
  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_lesson_id);
  if p_lesson_id is null then
    raise exception '请选择要删除的预定课时。';
  end if;

  if p_expected_updated_at is null then
    raise exception '缺少课时版本信息，请刷新后重试。';
  end if;

  if p_confirm_delete is distinct from true then
    raise exception '请确认删除预定课时。';
  end if;

  select l.*
  into v_lesson
  from public.school_lesson_records l
  where l.id = p_lesson_id
    and l.app_type = 'school'
  for update;

  if not found then
    raise exception '预定课时不存在。';
  end if;

  if v_lesson.updated_at is distinct from p_expected_updated_at then
    raise exception '课时已被其他操作更新，请刷新后重试。';
  end if;

  if v_lesson.lesson_type <> 'planned' then
    raise exception '只能删除 planned 预定课时。';
  end if;

  if v_lesson.status <> 'planned' then
    raise exception '只有全新的待上课预定课时可以删除；当前状态为：%。', coalesce(v_lesson.status, '');
  end if;

  if v_lesson.voided_at is not null then
    raise exception '该预定课时已作废，不能删除。';
  end if;

  if v_lesson.planned_lesson_id is not null then
    raise exception '该预定课时存在来源关联，不能删除。';
  end if;

  if exists (
    select 1
    from public.school_lesson_records a
    where a.app_type = 'school'
      and a.lesson_type = 'actual'
      and a.planned_lesson_id = v_lesson.id
  ) then
    raise exception '该预定课时已有实际课时、取消课或补课完成记录，不能删除。';
  end if;

  if exists (
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = v_lesson.student_id
      and s.year_month = public.school_resolve_r1d_e_c_lesson_student_month(v_lesson.id)
      and s.business_entity_id is not distinct from v_lesson.business_entity_id
  ) then
    raise exception '该学生月份已存在月度结算记录，不能删除预定课时。';
  end if;

  if exists (
    select 1
    from public.school_student_settlement_adjustment_drafts d
    where d.app_type = 'school'
      and d.student_id = v_lesson.student_id
      and d.year_month = public.school_resolve_r1d_e_c_lesson_student_month(v_lesson.id)
      and d.business_entity_id is not distinct from v_lesson.business_entity_id
  ) then
    raise exception '该学生月份已存在月度结算调整草稿，不能删除预定课时。';
  end if;

  if exists (
    select 1
    from public.school_student_settlement_adjustments a
    where a.app_type = 'school'
      and a.student_id = v_lesson.student_id
      and a.year_month = public.school_resolve_r1d_e_c_lesson_student_month(v_lesson.id)
      and a.business_entity_id is not distinct from v_lesson.business_entity_id
  ) then
    raise exception '该学生月份已存在月度结算调整记录，不能删除预定课时。';
  end if;

  if exists (
    select 1
    from public.school_teacher_wage_lock_details d
    where d.lesson_record_id = v_lesson.id
  ) then
    raise exception '该课时已进入老师工资快照明细，不能删除。';
  end if;

  if exists (
    select 1
    from public.school_student_tuition_bills b
    where exists (
      select 1
      from jsonb_array_elements_text(coalesce(b.source_snapshot->'planned_lesson_ids', '[]'::jsonb)) ids(lesson_id)
      where ids.lesson_id = v_lesson.id::text
    )
  ) then
    raise exception '该预定课时已进入学生学费应收快照，不能删除。';
  end if;

  if exists (
    select 1
    from public.school_income_records i
    where i.app_type = 'school'
      and exists (
        select 1
        from jsonb_array_elements_text(coalesce(i.source_snapshot->'planned_lesson_ids', '[]'::jsonb)) ids(lesson_id)
        where ids.lesson_id = v_lesson.id::text
      )
  ) then
    raise exception '该预定课时已进入收入记录快照，不能删除。';
  end if;

  delete from public.school_lesson_records l
  where l.id = v_lesson.id;

  return query
  select
    v_lesson.id,
    v_lesson.lesson_date,
    v_lesson.year_month,
    v_lesson.student_id,
    v_lesson.teacher_id,
    v_lesson.subject_id,
    v_lesson.business_entity_id,
    v_deleted_at;
end;
$function$
;
