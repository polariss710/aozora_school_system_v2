-- School V2 student monthly status Phase B4-Lesson.
-- Technical helpers only: authoritative planned-date candidates and a batch
-- preflight that shares the formal writer's occurrence expansion algorithm.

create or replace function public.school_expand_planned_lesson_batch_occurrences_v1(
  p_start_date date,
  p_end_date date,
  p_patterns jsonb,
  p_excluded_occurrences jsonb default '[]'::jsonb
)
returns table (
  row_index integer,
  pattern_index integer,
  occurrence_index integer,
  lesson_date date
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
begin
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception using errcode='22023',message='LESSON_BATCH_PREFLIGHT_DATE_RANGE_INVALID';
  end if;
  if p_end_date - p_start_date > 370 then
    raise exception using errcode='22023',message='LESSON_BATCH_PREFLIGHT_DATE_RANGE_TOO_LARGE';
  end if;
  if p_patterns is null or jsonb_typeof(p_patterns) <> 'array' then
    raise exception using errcode='22023',message='LESSON_BATCH_PREFLIGHT_PATTERNS_ARRAY_REQUIRED';
  end if;
  if p_excluded_occurrences is null or jsonb_typeof(p_excluded_occurrences) <> 'array' then
    raise exception using errcode='22023',message='LESSON_BATCH_PREFLIGHT_EXCLUSIONS_ARRAY_REQUIRED';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_patterns) as p(
      pattern_index integer,
      weekday integer,
      occurrence_count integer
    )
    where p.pattern_index is null
      or p.weekday is null or p.weekday < 0 or p.weekday > 6
      or p.occurrence_count is null or p.occurrence_count < 1 or p.occurrence_count > 10
  ) then
    raise exception using errcode='22023',message='LESSON_BATCH_PREFLIGHT_PATTERN_INVALID';
  end if;

  return query
  with patterns as (
    select p.pattern_index,p.weekday,p.occurrence_count
    from jsonb_to_recordset(p_patterns) as p(
      pattern_index integer,
      weekday integer,
      occurrence_count integer
    )
  ),
  exclusions as (
    select e.pattern_index,e.lesson_date,e.occurrence_index
    from jsonb_to_recordset(p_excluded_occurrences) as e(
      pattern_index integer,
      lesson_date date,
      occurrence_index integer
    )
    where e.pattern_index is not null and e.lesson_date is not null
  ),
  expanded as (
    select
      p.pattern_index,
      o.occurrence_index,
      (d.source_date - ((extract(dow from d.source_date)::integer + 6) % 7))::date as lesson_date
    from patterns p
    cross join lateral generate_series(p_start_date,p_end_date,interval '1 day') gs(source_date)
    cross join lateral (select gs.source_date::date as source_date) d
    cross join lateral generate_series(1,p.occurrence_count) o(occurrence_index)
    where extract(dow from d.source_date)::integer=p.weekday
  ),
  included as (
    select e.*
    from expanded e
    where not exists (
      select 1 from exclusions x
      where x.pattern_index=e.pattern_index
        and x.lesson_date=e.lesson_date
        and (x.occurrence_index is null or x.occurrence_index=e.occurrence_index)
    )
  )
  select
    row_number() over (order by i.lesson_date,i.pattern_index,i.occurrence_index)::integer,
    i.pattern_index,
    i.occurrence_index,
    i.lesson_date
  from included i
  order by i.lesson_date,i.pattern_index,i.occurrence_index;
end;
$function$;

create or replace function public.school_list_planned_lesson_student_candidates_v1(
  p_lesson_date date,
  p_business_entity_id uuid,
  p_selected_student_id uuid default null
)
returns table (
  billing_week_start_date date,
  billing_month text,
  student_settlement_month text,
  student_id uuid,
  student_code text,
  name text,
  display_name text,
  business_entity_id uuid,
  resolved_status text,
  source_event_id uuid,
  source_effective_month date,
  is_legacy_fallback boolean,
  is_active boolean,
  is_eligible boolean,
  is_selected_override boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_attribution record;
begin
  perform public.school_require_current_app_student_reader_v1();
  if p_lesson_date is null or p_business_entity_id is null then
    raise exception using errcode='22023',message='LESSON_PLANNED_DATE_AND_BUSINESS_ENTITY_REQUIRED';
  end if;
  if p_selected_student_id is not null and not exists (
    select 1 from public.school_students s
    where s.id=p_selected_student_id and s.app_type='school'
  ) then
    raise exception using errcode='P0002',message='STUDENT_STATUS_SELECTED_STUDENT_NOT_FOUND';
  end if;

  select * into strict v_attribution
  from public.school_resolve_planned_billing_attribution(p_lesson_date,null);

  return query
  select
    v_attribution.billing_week_start_date,
    v_attribution.billing_month,
    v_attribution.student_settlement_month,
    s.id,s.student_code,s.name,s.display_name,s.business_entity_id,
    r.resolved_status,r.source_event_id,r.source_effective_month,
    r.is_legacy_fallback,r.is_active,
    (r.is_active and s.business_entity_id is not distinct from p_business_entity_id),
    (s.id=p_selected_student_id)
  from public.school_students s
  cross join lateral public.school_resolve_student_status_at_month_core_v1(
    s.id,to_date(v_attribution.billing_month || '-01','YYYY-MM-DD')
  ) r
  where s.app_type='school'
    and (
      (r.is_active and s.business_entity_id is not distinct from p_business_entity_id)
      or s.id=p_selected_student_id
    )
  order by coalesce(nullif(s.display_name,''),s.name),s.name,s.id;
end;
$function$;

create or replace function public.school_preflight_planned_lesson_batch_student_candidates_v1(
  p_start_date date,
  p_end_date date,
  p_patterns jsonb,
  p_excluded_occurrences jsonb,
  p_business_entity_id uuid,
  p_selected_student_id uuid default null
)
returns table (
  student_id uuid,
  student_code text,
  name text,
  display_name text,
  business_entity_id uuid,
  target_billing_months text[],
  target_occurrences jsonb,
  invalid_occurrences jsonb,
  is_active_for_all boolean,
  is_eligible boolean,
  is_selected_override boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
begin
  perform public.school_require_current_app_student_reader_v1();
  if p_business_entity_id is null then
    raise exception using errcode='22023',message='LESSON_BATCH_PREFLIGHT_BUSINESS_ENTITY_REQUIRED';
  end if;
  if p_selected_student_id is not null and not exists (
    select 1 from public.school_students s
    where s.id=p_selected_student_id and s.app_type='school'
  ) then
    raise exception using errcode='P0002',message='STUDENT_STATUS_SELECTED_STUDENT_NOT_FOUND';
  end if;

  if not exists (
    select 1
    from public.school_expand_planned_lesson_batch_occurrences_v1(
      p_start_date,p_end_date,p_patterns,p_excluded_occurrences
    )
  ) then
    raise exception using errcode='22023',message='LESSON_BATCH_PREFLIGHT_NO_OCCURRENCES';
  end if;

  return query
  with occurrences as materialized (
    select o.*,
           a.billing_month,
           to_date(a.billing_month || '-01','YYYY-MM-DD') as target_month
    from public.school_expand_planned_lesson_batch_occurrences_v1(
      p_start_date,p_end_date,p_patterns,p_excluded_occurrences
    ) o
    cross join lateral public.school_resolve_planned_billing_attribution(null,o.lesson_date) a
  ),
  evaluated as (
    select
      s.id,s.student_code,s.name,s.display_name,s.business_entity_id,
      o.row_index,o.pattern_index,o.occurrence_index,o.lesson_date,o.billing_month,
      r.resolved_status,r.is_active
    from public.school_students s
    cross join occurrences o
    cross join lateral public.school_resolve_student_status_at_month_core_v1(s.id,o.target_month) r
    where s.app_type='school'
  ),
  grouped as (
    select
      e.id,e.student_code,e.name,e.display_name,e.business_entity_id,
      array_agg(distinct e.billing_month order by e.billing_month) as target_billing_months,
      jsonb_agg(
        jsonb_build_object(
          'row_index',e.row_index,
          'pattern_index',e.pattern_index,
          'occurrence_index',e.occurrence_index,
          'lesson_date',e.lesson_date,
          'billing_month',e.billing_month
        ) order by e.row_index
      ) as target_occurrences,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'row_index',e.row_index,
            'pattern_index',e.pattern_index,
            'occurrence_index',e.occurrence_index,
            'lesson_date',e.lesson_date,
            'billing_month',e.billing_month,
            'resolved_status',e.resolved_status
          ) order by e.row_index
        ) filter (where not e.is_active),
        '[]'::jsonb
      ) as invalid_occurrences,
      bool_and(e.is_active) as is_active_for_all
    from evaluated e
    group by e.id,e.student_code,e.name,e.display_name,e.business_entity_id
  )
  select
    g.id,g.student_code,g.name,g.display_name,g.business_entity_id,
    g.target_billing_months,g.target_occurrences,g.invalid_occurrences,g.is_active_for_all,
    (g.is_active_for_all and g.business_entity_id is not distinct from p_business_entity_id),
    (g.id=p_selected_student_id)
  from grouped g
  where (
    g.is_active_for_all and g.business_entity_id is not distinct from p_business_entity_id
  ) or g.id=p_selected_student_id
  order by coalesce(nullif(g.display_name,''),g.name),g.name,g.id;
end;
$function$;

do $b4_lesson_writer_refactor$
declare
  v_signature regprocedure := 'public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure;
  v_definition text;
  v_replaced text;
  v_old text := $old$
  select
    row_number() over (order by w.lesson_date, p.pattern_index, o.occurrence_index)::integer,
    p.pattern_index,
    o.occurrence_index,
    w.lesson_date,
    to_char(w.lesson_date, 'YYYY-MM'),
$old$;
  v_new text := $new$
  select
    row_number() over (order by o.lesson_date, p.pattern_index, o.occurrence_index)::integer,
    p.pattern_index,
    o.occurrence_index,
    o.lesson_date,
    to_char(o.lesson_date, 'YYYY-MM'),
$new$;
  v_old_from text := $old$
  from planned_lesson_generation_patterns p
  cross join lateral generate_series(p_start_date, p_end_date, interval '1 day') as gs(lesson_date)
  cross join lateral (select gs.lesson_date::date as lesson_date) d
  cross join lateral (
    select (d.lesson_date - ((extract(dow from d.lesson_date)::integer + 6) % 7))::date as lesson_date
  ) w
  cross join lateral generate_series(1, p.occurrence_count) as o(occurrence_index)
  where extract(dow from d.lesson_date)::integer = p.weekday
    and not exists (
      select 1
      from planned_lesson_generation_exclusions x
      where x.pattern_index = p.pattern_index
        and x.lesson_date = w.lesson_date
        and (
          x.occurrence_index is null
          or x.occurrence_index = o.occurrence_index
        )
    );
$old$;
  v_new_from text := $new$
  from planned_lesson_generation_patterns p
  cross join lateral public.school_expand_planned_lesson_batch_occurrences_v1(
    p_start_date,
    p_end_date,
    jsonb_build_array(jsonb_build_object(
      'pattern_index',p.pattern_index,
      'weekday',p.weekday,
      'occurrence_count',p.occurrence_count
    )),
    p_excluded_occurrences
  ) o;
$new$;
begin
  v_definition:=pg_get_functiondef(v_signature);
  if md5(v_definition)<>'bb9c71e08ad87e428297e64bcf0751d7' then
    raise exception 'B4_LESSON_BATCH_WRITER_BASELINE_MD5_MISMATCH actual=%',md5(v_definition);
  end if;
  if position(v_old in v_definition)=0 or position(v_old_from in v_definition)=0 then
    raise exception 'B4_LESSON_BATCH_WRITER_FRAGMENT_NOT_FOUND';
  end if;
  v_replaced:=replace(replace(v_definition,v_old,v_new),v_old_from,v_new_from);
  execute v_replaced;
end;
$b4_lesson_writer_refactor$;

comment on function public.school_expand_planned_lesson_batch_occurrences_v1(date,date,jsonb,jsonb) is
  'Owner-only technical helper shared by the formal batch planned writer and B4-Lesson read-only preflight. Preserves the existing occurrence and exclusion algorithm; introduces no second billing-month authority.';
comment on function public.school_list_planned_lesson_student_candidates_v1(date,uuid,uuid) is
  'B4-Lesson read-only candidate reader. DB resolves planned billing attribution, then returns active students for that authoritative month plus an optional selected override.';
comment on function public.school_preflight_planned_lesson_batch_student_candidates_v1(date,date,jsonb,jsonb,uuid,uuid) is
  'B4-Lesson read-only batch preflight. Uses the formal writer shared occurrence helper, resolves each occurrence billing month, and returns the all-month active intersection plus optional selected ineligibility evidence.';

revoke all on function public.school_expand_planned_lesson_batch_occurrences_v1(date,date,jsonb,jsonb)
  from public,anon,authenticated,service_role;
revoke all on function public.school_list_planned_lesson_student_candidates_v1(date,uuid,uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_planned_lesson_student_candidates_v1(date,uuid,uuid)
  to authenticated;
revoke all on function public.school_preflight_planned_lesson_batch_student_candidates_v1(date,date,jsonb,jsonb,uuid,uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.school_preflight_planned_lesson_batch_student_candidates_v1(date,date,jsonb,jsonb,uuid,uuid)
  to authenticated;
