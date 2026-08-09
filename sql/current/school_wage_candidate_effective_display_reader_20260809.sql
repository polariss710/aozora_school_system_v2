-- School V2 wage candidate effective-prerequisite display reader.
-- Read-only contract extension only: no schema, business row, writer or authority change.
\set ON_ERROR_STOP on

create or replace function public.school_get_teacher_monthly_wage_generation_preflight(
  p_year_month text,
  p_teacher_id uuid,
  p_business_entity_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_result jsonb;
begin
  perform public.school_require_current_app_admin();
  if p_year_month is null or p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'WAGE_MONTH_INVALID';
  end if;
  if p_teacher_id is not null and not exists(
    select 1 from public.school_teachers t where t.id = p_teacher_id and t.app_type = 'school'
  ) then raise exception 'WAGE_TEACHER_INVALID'; end if;
  if p_business_entity_id is not null and not exists(
    select 1 from public.school_business_entities b where b.id = p_business_entity_id
  ) then raise exception 'WAGE_BUSINESS_ENTITY_INVALID'; end if;

  with candidates as materialized (
    select * from public.school_get_teacher_monthly_wage_generation_candidate_facts(
      p_year_month, p_teacher_id, p_business_entity_id
    )
  ), classified as (
    select c.*,
      case
        when not c.fact_complete then 'WAGE_LESSON_FACT_INCOMPLETE'
        when c.active_rule_count = 0 then 'WAGE_RULE_MISSING'
        when c.active_rule_count > 1 then 'WAGE_RULE_DUPLICATE'
        when not coalesce(c.effective_complete, false) then
          coalesce(c.settlement_blocker_code, 'WAGE_EFFECTIVE_SETTLEMENT_MISSING')
      end blocker_code,
      case
        when not c.fact_complete then 'Required teacher/student/subject/business entity/actual minutes are incomplete.'
        when c.active_rule_count = 0 then 'No unique active wage rule exists.'
        when c.active_rule_count > 1 then 'Multiple active wage rules match this lesson.'
        when not coalesce(c.effective_complete, false) then c.settlement_blocker_detail
      end blocker_detail
    from candidates c
  ), teacher_preview as (
    select teacher_id, max(teacher_name) teacher_name, business_entity_id,
      max(business_name) business_name, count(*)::integer lesson_count,
      sum(actual_minutes)::numeric total_minutes,
      count(*) filter(where is_no_wage)::integer no_wage_lesson_count,
      coalesce(sum(actual_minutes) filter(where is_no_wage),0)::numeric no_wage_minutes,
      coalesce(sum(pay_hours),0)::numeric pay_hours,
      coalesce(sum(lesson_wage_jpy),0)::numeric amount_jpy
    from classified
    where blocker_code is null
    group by teacher_id,business_entity_id
  ), candidate_prerequisites as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'lesson_record_id', lesson_record_id,
      'prerequisite_satisfied', blocker_code is null,
      'prerequisite_status', case
        when blocker_code is null then effective_status
        else coalesce(effective_status, blocker_code)
      end,
      'blocker_code', blocker_code,
      'blocker_detail', blocker_detail,
      'settlement_type', settlement_type,
      'is_no_wage', is_no_wage,
      'effective_source_type', effective_source_type,
      'effective_source_id', effective_source_id
    ) order by lesson_date,start_time,lesson_record_id), '[]'::jsonb) rows
    from classified
  ), blockers as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'blocker_code', blocker_code,
      'blocker_detail', blocker_detail,
      'lesson_record_id', lesson_record_id,
      'teacher_id', teacher_id,
      'student_id', student_id,
      'subject_id', subject_id,
      'business_entity_id', business_entity_id,
      'student_settlement_month', student_settlement_month,
      'active_rule_count', active_rule_count,
      'wage_rule_id', wage_rule_id,
      'settlement_type', settlement_type,
      'effective_status', effective_status,
      'effective_source_type', effective_source_type,
      'effective_source_id', effective_source_id
    ) order by blocker_code,student_name,lesson_record_id) filter(where blocker_code is not null), '[]'::jsonb) rows
    from classified
  )
  select jsonb_build_object(
    'year_month', p_year_month,
    'summary', jsonb_build_object(
      'candidate_actual_count', (select count(*) from classified),
      'candidate_teacher_count', (select count(distinct teacher_id) from classified),
      'total_minutes', coalesce((select sum(actual_minutes) from classified),0),
      'missing_rule_count', (select count(*) from classified where blocker_code='WAGE_RULE_MISSING'),
      'duplicate_rule_count', (select count(*) from classified where blocker_code='WAGE_RULE_DUPLICATE'),
      'incomplete_lesson_count', (select count(*) from classified where blocker_code='WAGE_LESSON_FACT_INCOMPLETE'),
      'no_wage_lesson_count', (select count(*) from classified where active_rule_count=1 and is_no_wage),
      'no_wage_minutes', coalesce((select sum(actual_minutes) from classified where active_rule_count=1 and is_no_wage),0),
      'student_settlement_blocker_count', (select count(*) from classified where blocker_code in ('WAGE_EFFECTIVE_SETTLEMENT_MISSING','WAGE_SETTLEMENT_BUSINESS_ENTITY_MISMATCH')),
      'student_settlement_blocker_group_count', (select count(*) from (select distinct student_id,student_settlement_month,business_entity_id from classified where blocker_code in ('WAGE_EFFECTIVE_SETTLEMENT_MISSING','WAGE_SETTLEMENT_BUSINESS_ENTITY_MISMATCH')) g),
      'blocker_count', (select count(*) from classified where blocker_code is not null),
      'active_wage_lock_count', (select count(*) from public.school_teacher_wage_locks w where w.settlement_month=p_year_month and w.status='locked' and w.voided_at is null and (p_teacher_id is null or w.teacher_id=p_teacher_id) and (p_business_entity_id is null or w.business_entity_id=p_business_entity_id)),
      'existing_wage_detail_count', (select count(*) from classified c where exists(select 1 from public.school_teacher_wage_lock_details d join public.school_teacher_wage_locks w on w.id=d.lock_id where d.lesson_record_id=c.lesson_record_id and w.status='locked' and w.voided_at is null)),
      'conditional_pay_hours', coalesce((select sum(pay_hours) from classified where blocker_code is null),0),
      'conditional_amount_jpy', coalesce((select sum(lesson_wage_jpy) from classified where blocker_code is null),0)
    ),
    'teacher_previews', coalesce((select jsonb_agg(to_jsonb(t) order by teacher_name,teacher_id) from teacher_preview t), '[]'::jsonb),
    'candidate_prerequisites', (select rows from candidate_prerequisites),
    'blockers', (select rows from blockers)
  ) into v_result;
  return v_result;
end
$function$;

revoke all on function public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)
  to authenticated;

comment on function public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid) is
  'Read-only structured wage preflight shared with the writer. candidate_prerequisites exposes the same per-lesson effective/no_wage classification for UI display; no client-side qualification rule.';
