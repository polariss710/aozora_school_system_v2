-- School V2 open makeup-source origin display reader V2.
-- Adds read-only display evidence while preserving the V1 candidate identity,
-- eligibility, ordering, balance and authoritative student-month contract.
\set ON_ERROR_STOP on

begin;

do $preflight$
begin
  if md5(pg_get_functiondef(
      'public.school_list_open_lesson_credit_sources(text,text,text)'::regprocedure
    )) <> 'bbbc1eff71bc3f8f3ad468e8543537e8' then
    raise exception 'MAKEUP_SOURCE_V2_V1_DEFINITION_DRIFT';
  end if;
  perform 'public.school_assert_lesson_clearance_reader()'::regprocedure;
  if to_regprocedure(
      'public.school_list_open_lesson_credit_sources_v2(text,text,text)'
    ) is not null then
    raise exception 'MAKEUP_SOURCE_V2_ALREADY_EXISTS';
  end if;
  if md5(pg_get_functiondef(
      'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
    )) <> 'c0f9485be9783283db8c61c75473c43d' then
    raise exception 'MAKEUP_SOURCE_V2_CANONICAL_WRITER_DRIFT';
  end if;
end
$preflight$;

create function public.school_list_open_lesson_credit_sources_v2(
  p_from_month text,
  p_to_month text,
  p_target_month text
)
returns table(
  id uuid,
  lesson_date date,
  year_month text,
  student_id uuid,
  teacher_id uuid,
  subject_id uuid,
  business_entity_id uuid,
  start_time text,
  end_time text,
  duration_hours numeric,
  lesson_content text,
  note text,
  lesson_count integer,
  unit_price numeric,
  lesson_delivery_mode text,
  lesson_venue text,
  remaining_hours numeric,
  origin_display_kind text,
  origin_actual_lesson_id uuid,
  origin_display_date date,
  origin_display_start_time text,
  origin_display_end_time text,
  origin_display_selectable boolean
)
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $function$
#variable_conflict use_column
declare
  v_actor record;
begin
  select * into strict v_actor
  from public.school_assert_lesson_clearance_reader();

  return query
  with base as (
    select source.*
    from public.school_list_open_lesson_credit_sources(
      p_from_month,
      p_to_month,
      p_target_month
    ) source
  ), planned as (
    select base.*,
      planned_row.billing_week_start_date,
      coalesce(
        planned_row.billing_week_start_date,
        case when base.lesson_date is not null then
          (base.lesson_date
            -(extract(isodow from base.lesson_date)::integer-1))::date
        else null end
      ) source_week_start_date
    from base
    join public.school_lesson_records planned_row
      on planned_row.id=base.id
     and planned_row.app_type='school'
     and planned_row.lesson_type='planned'
  ), evidence as (
    select planned.id,
      count(actual_row.id) filter(
        where actual_row.status='cancelled'
           or (
             actual_row.status='completed'
             and coalesce(
               actual_row.actual_minutes,
               round(coalesce(actual_row.duration_hours,0)*60)::integer
             )>0
             and coalesce(
               actual_row.actual_minutes,
               round(coalesce(actual_row.duration_hours,0)*60)::integer
             )<round(coalesce(planned.duration_hours,0)*60)::integer
           )
      )::integer origin_candidate_count,
      count(actual_row.id) filter(
        where actual_row.status='cancelled'
      )::integer cancelled_candidate_count,
      count(actual_row.id) filter(
        where actual_row.status='completed'
          and coalesce(
            actual_row.actual_minutes,
            round(coalesce(actual_row.duration_hours,0)*60)::integer
          )>0
          and coalesce(
            actual_row.actual_minutes,
            round(coalesce(actual_row.duration_hours,0)*60)::integer
          )<round(coalesce(planned.duration_hours,0)*60)::integer
      )::integer partial_candidate_count,
      count(actual_row.id) filter(
        where (
            actual_row.status='cancelled'
            or (
              actual_row.status='completed'
              and coalesce(
                actual_row.actual_minutes,
                round(coalesce(actual_row.duration_hours,0)*60)::integer
              )>0
              and coalesce(
                actual_row.actual_minutes,
                round(coalesce(actual_row.duration_hours,0)*60)::integer
              )<round(coalesce(planned.duration_hours,0)*60)::integer
            )
          )
          and actual_row.student_id is not distinct from planned.student_id
          and actual_row.teacher_id is not distinct from planned.teacher_id
          and actual_row.subject_id is not distinct from planned.subject_id
          and actual_row.business_entity_id is not distinct from planned.business_entity_id
          and actual_row.lesson_date is not null
          and actual_row.start_time is not null
          and actual_row.end_time is not null
      )::integer valid_complete_candidate_count,
      array_agg(actual_row.id order by actual_row.created_at,actual_row.id) filter(
        where (
            actual_row.status='cancelled'
            or (
              actual_row.status='completed'
              and coalesce(
                actual_row.actual_minutes,
                round(coalesce(actual_row.duration_hours,0)*60)::integer
              )>0
              and coalesce(
                actual_row.actual_minutes,
                round(coalesce(actual_row.duration_hours,0)*60)::integer
              )<round(coalesce(planned.duration_hours,0)*60)::integer
            )
          )
          and actual_row.student_id is not distinct from planned.student_id
          and actual_row.teacher_id is not distinct from planned.teacher_id
          and actual_row.subject_id is not distinct from planned.subject_id
          and actual_row.business_entity_id is not distinct from planned.business_entity_id
          and actual_row.lesson_date is not null
          and actual_row.start_time is not null
          and actual_row.end_time is not null
      ) valid_origin_ids,
      array_agg(actual_row.lesson_date order by actual_row.created_at,actual_row.id) filter(
        where (
            actual_row.status='cancelled'
            or (
              actual_row.status='completed'
              and coalesce(
                actual_row.actual_minutes,
                round(coalesce(actual_row.duration_hours,0)*60)::integer
              )>0
              and coalesce(
                actual_row.actual_minutes,
                round(coalesce(actual_row.duration_hours,0)*60)::integer
              )<round(coalesce(planned.duration_hours,0)*60)::integer
            )
          )
          and actual_row.student_id is not distinct from planned.student_id
          and actual_row.teacher_id is not distinct from planned.teacher_id
          and actual_row.subject_id is not distinct from planned.subject_id
          and actual_row.business_entity_id is not distinct from planned.business_entity_id
          and actual_row.lesson_date is not null
          and actual_row.start_time is not null
          and actual_row.end_time is not null
      ) valid_origin_dates,
      array_agg(actual_row.start_time order by actual_row.created_at,actual_row.id) filter(
        where (
            actual_row.status='cancelled'
            or (
              actual_row.status='completed'
              and coalesce(
                actual_row.actual_minutes,
                round(coalesce(actual_row.duration_hours,0)*60)::integer
              )>0
              and coalesce(
                actual_row.actual_minutes,
                round(coalesce(actual_row.duration_hours,0)*60)::integer
              )<round(coalesce(planned.duration_hours,0)*60)::integer
            )
          )
          and actual_row.student_id is not distinct from planned.student_id
          and actual_row.teacher_id is not distinct from planned.teacher_id
          and actual_row.subject_id is not distinct from planned.subject_id
          and actual_row.business_entity_id is not distinct from planned.business_entity_id
          and actual_row.lesson_date is not null
          and actual_row.start_time is not null
          and actual_row.end_time is not null
      ) valid_origin_start_times,
      array_agg(actual_row.end_time order by actual_row.created_at,actual_row.id) filter(
        where (
            actual_row.status='cancelled'
            or (
              actual_row.status='completed'
              and coalesce(
                actual_row.actual_minutes,
                round(coalesce(actual_row.duration_hours,0)*60)::integer
              )>0
              and coalesce(
                actual_row.actual_minutes,
                round(coalesce(actual_row.duration_hours,0)*60)::integer
              )<round(coalesce(planned.duration_hours,0)*60)::integer
            )
          )
          and actual_row.student_id is not distinct from planned.student_id
          and actual_row.teacher_id is not distinct from planned.teacher_id
          and actual_row.subject_id is not distinct from planned.subject_id
          and actual_row.business_entity_id is not distinct from planned.business_entity_id
          and actual_row.lesson_date is not null
          and actual_row.start_time is not null
          and actual_row.end_time is not null
      ) valid_origin_end_times
    from planned
    left join public.school_lesson_records actual_row
      on actual_row.planned_lesson_id=planned.id
     and actual_row.app_type='school'
     and actual_row.lesson_type='actual'
     and actual_row.voided_at is null
    group by planned.id,planned.duration_hours,planned.student_id,
      planned.teacher_id,planned.subject_id,planned.business_entity_id
  ), classified as (
    select planned.*,
      evidence.origin_candidate_count,
      evidence.cancelled_candidate_count,
      evidence.partial_candidate_count,
      evidence.valid_complete_candidate_count,
      evidence.valid_origin_ids,
      evidence.valid_origin_dates,
      evidence.valid_origin_start_times,
      evidence.valid_origin_end_times,
      case
        when evidence.origin_candidate_count=0 then 'week_fallback'
        when evidence.origin_candidate_count<>1
          or evidence.valid_complete_candidate_count<>1 then 'ambiguous'
        when evidence.cancelled_candidate_count=1 then 'cancelled_original'
        when evidence.partial_candidate_count=1
          and planned.lesson_date is not null
          and planned.start_time is not null
          and planned.end_time is not null then 'partial_planned_original'
        when evidence.partial_candidate_count=1 then 'partial_actual'
        else 'ambiguous'
      end origin_kind
    from planned
    join evidence on evidence.id=planned.id
  )
  select classified.id,
    classified.lesson_date,
    classified.year_month,
    classified.student_id,
    classified.teacher_id,
    classified.subject_id,
    classified.business_entity_id,
    classified.start_time,
    classified.end_time,
    classified.duration_hours,
    classified.lesson_content,
    classified.note,
    classified.lesson_count,
    classified.unit_price,
    classified.lesson_delivery_mode,
    classified.lesson_venue,
    classified.remaining_hours,
    classified.origin_kind,
    case when classified.origin_kind in (
        'cancelled_original','partial_planned_original','partial_actual'
      ) then classified.valid_origin_ids[1] else null end,
    case classified.origin_kind
      when 'cancelled_original' then classified.valid_origin_dates[1]
      when 'partial_planned_original' then classified.lesson_date
      when 'partial_actual' then classified.valid_origin_dates[1]
      when 'week_fallback' then classified.source_week_start_date
      else null
    end,
    case classified.origin_kind
      when 'cancelled_original' then classified.valid_origin_start_times[1]
      when 'partial_planned_original' then classified.start_time
      when 'partial_actual' then classified.valid_origin_start_times[1]
      else null
    end,
    case classified.origin_kind
      when 'cancelled_original' then classified.valid_origin_end_times[1]
      when 'partial_planned_original' then classified.end_time
      when 'partial_actual' then classified.valid_origin_end_times[1]
      else null
    end,
    classified.origin_kind<>'ambiguous'
  from classified
  order by classified.year_month,
    classified.lesson_date,
    classified.lesson_count nulls last,
    classified.start_time nulls last,
    classified.id;
end
$function$;

alter function public.school_list_open_lesson_credit_sources_v2(text,text,text)
  owner to postgres;
revoke all on function public.school_list_open_lesson_credit_sources_v2(text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_open_lesson_credit_sources_v2(text,text,text)
  to authenticated;

comment on function public.school_list_open_lesson_credit_sources_v2(text,text,text) is
  'Authenticated active School member reader for the makeup-completion source dialog. Reuses V1 candidate identity, balance, month and ordering; adds deterministic original-session display evidence, explicit week fallback, and visible non-selectable ambiguity without changing any writer fact.';

do $verification$
declare
  v_v1_count integer;
  v_v2_count integer;
  v_diff_count integer;
  v_kind_counts jsonb;
  v_definition text;
begin
  if md5(pg_get_functiondef(
      'public.school_list_open_lesson_credit_sources(text,text,text)'::regprocedure
    )) <> 'bbbc1eff71bc3f8f3ad468e8543537e8' then
    raise exception 'MAKEUP_SOURCE_V2_V1_CHANGED';
  end if;
  if md5(pg_get_functiondef(
      'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
    )) <> 'c0f9485be9783283db8c61c75473c43d' then
    raise exception 'MAKEUP_SOURCE_V2_WRITER_CHANGED';
  end if;

  v_definition:=pg_get_functiondef(
    'public.school_list_open_lesson_credit_sources_v2(text,text,text)'::regprocedure
  );
  if position('school_assert_lesson_clearance_reader()' in v_definition)=0 then
    raise exception 'MAKEUP_SOURCE_V2_MEMBERSHIP_GUARD_MISSING';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    (
      select min(membership.user_id::text)
      from public.school_app_memberships membership
      where membership.is_active
        and membership.role in ('admin','operator','read_only')
    ),
    true
  );

  select count(*) into v_v1_count
  from public.school_list_open_lesson_credit_sources(
    '2024-01','2026-08','2026-08'
  );
  select count(*) into v_v2_count
  from public.school_list_open_lesson_credit_sources_v2(
    '2024-01','2026-08','2026-08'
  );
  if v_v1_count<>22 or v_v2_count<>v_v1_count then
    raise exception 'MAKEUP_SOURCE_V2_CANDIDATE_COUNT_MISMATCH:%/%',
      v_v1_count,v_v2_count;
  end if;

  with v1 as (
    select * from public.school_list_open_lesson_credit_sources(
      '2024-01','2026-08','2026-08'
    )
  ), v2 as (
    select * from public.school_list_open_lesson_credit_sources_v2(
      '2024-01','2026-08','2026-08'
    )
  )
  select count(*) into v_diff_count
  from v1 full join v2 using(id)
  where v1.id is null or v2.id is null
     or to_jsonb(v1)<>(to_jsonb(v2)-array[
       'origin_display_kind','origin_actual_lesson_id','origin_display_date',
       'origin_display_start_time','origin_display_end_time',
       'origin_display_selectable'
     ]);
  if v_diff_count<>0 then
    raise exception 'MAKEUP_SOURCE_V2_V1_FIELD_MISMATCH:%',v_diff_count;
  end if;

  select jsonb_object_agg(kind,row_count order by kind) into v_kind_counts
  from (
    select origin_display_kind kind,count(*) row_count
    from public.school_list_open_lesson_credit_sources_v2(
      '2024-01','2026-08','2026-08'
    )
    group by origin_display_kind
  ) counts;
  if v_kind_counts<>jsonb_build_object(
      'cancelled_original',8,
      'partial_actual',2,
      'partial_planned_original',1,
      'week_fallback',11
    ) then
    raise exception 'MAKEUP_SOURCE_V2_KIND_COUNTS_UNEXPECTED:%',v_kind_counts;
  end if;

  if not exists(
    select 1
    from public.school_list_open_lesson_credit_sources_v2(
      '2024-01','2026-08','2026-08'
    ) source
    where left(source.id::text,8)='c770d6fe'
      and source.origin_display_kind='partial_planned_original'
      and source.origin_display_date=date '2026-07-29'
      and source.origin_display_start_time='16:30'
      and source.origin_display_end_time='18:30'
      and source.remaining_hours=1
  ) then
    raise exception 'MAKEUP_SOURCE_V2_C770D6FE_REGRESSION';
  end if;

  if exists(
    select 1
    from public.school_list_open_lesson_credit_sources_v2(
      '2024-01','2026-08','2026-08'
    ) source
    where left(source.id::text,8)='37a2083e'
  ) then
    raise exception 'MAKEUP_SOURCE_V2_FULLY_CONSUMED_SOURCE_VISIBLE';
  end if;

  if exists(
    select 1
    from public.school_list_open_lesson_credit_sources_v2(
      '2024-01','2026-08','2026-08'
    ) source
    where source.origin_display_kind='ambiguous'
  ) then
    raise exception 'MAKEUP_SOURCE_V2_PRODUCTION_AMBIGUITY_PRESENT';
  end if;

  if exists(
      select 1
      from pg_proc procedure_row
      cross join lateral aclexplode(coalesce(
        procedure_row.proacl,
        acldefault('f',procedure_row.proowner)
      )) privilege_row
      where procedure_row.oid=
        'public.school_list_open_lesson_credit_sources_v2(text,text,text)'::regprocedure
        and privilege_row.grantee=0
        and privilege_row.privilege_type='EXECUTE'
    ) or has_function_privilege(
      'anon',
      'public.school_list_open_lesson_credit_sources_v2(text,text,text)',
      'EXECUTE'
    )
    or not has_function_privilege(
      'authenticated',
      'public.school_list_open_lesson_credit_sources_v2(text,text,text)',
      'EXECUTE'
    ) then
    raise exception 'MAKEUP_SOURCE_V2_ACL_INVALID';
  end if;

  raise notice 'MAKEUP_SOURCE_V2_VERIFIED v1_count=% v2_count=% kinds=%',
    v_v1_count,v_v2_count,v_kind_counts;
end
$verification$;

\if :makeup_source_v2_commit
  commit;
\else
  rollback;
\endif
