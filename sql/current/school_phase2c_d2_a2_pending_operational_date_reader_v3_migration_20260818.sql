-- School V2 Phase 2C-D2-A2 pending operational display-date reader V3.
-- Read-only RPC extension. V2 remains unchanged; no business rows are written.
\set ON_ERROR_STOP on

\if :{?PHASE2C_D2_A2_REHEARSAL}
\else
begin;
\endif

do $preflight$
begin
  perform 'public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean)'::regprocedure;
  perform 'public.school_assert_lesson_clearance_reader()'::regprocedure;
  if to_regprocedure(
      'public.school_list_lesson_clearance_pending_balances_v3(uuid,boolean)'
    ) is not null then
    raise exception 'PHASE2C_D2_A2_READER_V3_ALREADY_EXISTS';
  end if;
  if not exists(
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name='school_lesson_records'
      and column_name in ('planned_lesson_id','lesson_date','actual_minutes',
        'duration_hours','voided_at')
    group by table_schema,table_name
    having count(*)=5
  ) then
    raise exception 'PHASE2C_D2_A2_REQUIRED_LESSON_COLUMNS_MISSING';
  end if;
end
$preflight$;

\if :{?PHASE2C_D2_A2_SKIP_PRODUCTION_MD5}
\else
do $dependency_md5$
begin
  if md5(pg_get_functiondef(
      'public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean)'::regprocedure
    ))<>'94dcc95f7c64325e77ea5fa326dc5d05' then
    raise exception 'PHASE2C_D2_A2_READER_V2_DEFINITION_DRIFT';
  end if;
end
$dependency_md5$;
\endif

create function public.school_list_lesson_clearance_pending_balances_v3(
  p_student_id uuid default null,
  p_include_active_claimed boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_v2 jsonb;
  v_items jsonb;
  v_result jsonb;
  v_partial_count integer;
  v_week_count integer;
  v_ambiguous_count integer;
begin
  -- V2 remains the sole authority for balance, eligibility, FIFO, lock and claim facts.
  v_v2:=public.school_list_lesson_clearance_pending_balances_v2(
    p_student_id,
    p_include_active_claimed
  );

  with indexed_items as (
    select item.payload,item.ordinality
    from jsonb_array_elements(coalesce(v_v2->'items','[]'::jsonb))
      with ordinality as item(payload,ordinality)
  ), enriched as (
    select indexed.payload,indexed.ordinality,
      planned.lesson_date source_lesson_date,
      evidence.valid_partial_count,
      case when evidence.valid_partial_count=1
        then evidence.valid_partial_ids[1] else null end origin_partial_actual_id,
      case when evidence.valid_partial_count=1
        then evidence.valid_partial_dates[1] else null end origin_partial_actual_date,
      case
        when evidence.valid_partial_count=1 then evidence.valid_partial_dates[1]
        when planned.lesson_date is not null then
          (planned.lesson_date
            -(extract(isodow from planned.lesson_date)::integer-1))::date
        else null
      end operational_display_date,
      case
        when evidence.valid_partial_count=1 then 'partial_actual_date'
        when planned.lesson_date is not null then 'source_natural_week_start'
        else 'unavailable'
      end operational_display_date_basis,
      case
        when evidence.valid_partial_count=1 then 'unique_valid_partial_actual'
        when evidence.valid_partial_count=0 then 'no_valid_partial_actual'
        else 'ambiguous_valid_partial_actual'
      end origin_evidence_status,
      case
        when evidence.valid_partial_count=1
          then 'partial_actual_date_authoritative_v1'
        when evidence.valid_partial_count=0 and planned.lesson_date is not null
          then 'source_natural_week_start_fallback_v1'
        when evidence.valid_partial_count>1 and planned.lesson_date is not null
          then 'ambiguous_partial_actual_fallback_to_source_week_v1'
        else 'operational_display_date_unavailable_v1'
      end operational_display_explanation
    from indexed_items indexed
    join public.school_lesson_records planned
      on planned.id=(indexed.payload->>'pending_source_planned_id')::uuid
     and planned.app_type='school'
     and planned.lesson_type='planned'
    left join lateral (
      select count(*)::integer valid_partial_count,
        array_agg(actual_row.id order by actual_row.created_at,actual_row.id)
          valid_partial_ids,
        array_agg(actual_row.lesson_date order by actual_row.created_at,actual_row.id)
          valid_partial_dates
      from public.school_lesson_records actual_row
      where actual_row.app_type='school'
        and actual_row.lesson_type='actual'
        and actual_row.status='completed'
        and actual_row.voided_at is null
        and actual_row.planned_lesson_id=planned.id
        and actual_row.student_id is not distinct from planned.student_id
        and actual_row.teacher_id is not distinct from planned.teacher_id
        and actual_row.subject_id is not distinct from planned.subject_id
        and actual_row.business_entity_id is not distinct from planned.business_entity_id
        and actual_row.lesson_date is not null
        and coalesce(actual_row.actual_minutes,
          round(coalesce(actual_row.duration_hours,0)*60)::integer)>0
        and coalesce(actual_row.actual_minutes,
          round(coalesce(actual_row.duration_hours,0)*60)::integer)
          <coalesce((indexed.payload->>'initial_credit_minutes')::integer,
            round(coalesce(planned.duration_hours,0)*60)::integer)
    ) evidence on true
  ), payloads as (
    select enriched.ordinality,
      enriched.payload||jsonb_build_object(
        'operational_display_date',enriched.operational_display_date,
        'operational_display_date_basis',enriched.operational_display_date_basis,
        'origin_partial_actual_id',enriched.origin_partial_actual_id,
        'origin_partial_actual_date',enriched.origin_partial_actual_date,
        'origin_evidence_status',enriched.origin_evidence_status,
        'operational_display_explanation',enriched.operational_display_explanation
      ) payload
    from enriched
  )
  select coalesce(jsonb_agg(payloads.payload order by payloads.ordinality),'[]'::jsonb)
    into v_items
  from payloads;

  select count(*) filter(where item->>'operational_display_date_basis'
        ='partial_actual_date'),
    count(*) filter(where item->>'operational_display_date_basis'
        ='source_natural_week_start'),
    count(*) filter(where item->>'origin_evidence_status'
        ='ambiguous_valid_partial_actual')
    into v_partial_count,v_week_count,v_ambiguous_count
  from jsonb_array_elements(v_items) item;

  v_result:=jsonb_set(v_v2,'{contract_version}',
    to_jsonb('lesson_clearance_pending_balances_v3'::text),true);
  v_result:=jsonb_set(v_result,'{items}',v_items,true);
  v_result:=jsonb_set(v_result,'{summary}',
    coalesce(v_result->'summary','{}'::jsonb)||jsonb_build_object(
      'operational_partial_actual_date_count',coalesce(v_partial_count,0),
      'operational_week_monday_count',coalesce(v_week_count,0),
      'operational_ambiguous_evidence_count',coalesce(v_ambiguous_count,0),
      'operational_display_date_contract',
        'unique_valid_partial_actual_else_tokyo_natural_week_monday_v1'
    ),true);
  return v_result;
end
$function$;

alter function public.school_list_lesson_clearance_pending_balances_v3(uuid,boolean)
  owner to postgres;
revoke all on function public.school_list_lesson_clearance_pending_balances_v3(uuid,boolean)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_lesson_clearance_pending_balances_v3(uuid,boolean)
  to authenticated;
comment on function public.school_list_lesson_clearance_pending_balances_v3(uuid,boolean) is
  'Phase 2C-D2-A2 read-only pending candidate V3. V2 balance/FIFO facts are unchanged; operational display date is the unique valid partial actual date, otherwise the source date natural-week Monday.';

do $verify$
declare
  v_signature regprocedure:=
    'public.school_list_lesson_clearance_pending_balances_v3(uuid,boolean)'::regprocedure;
begin
  if exists(
    select 1
    from pg_proc function_row
    where function_row.oid=v_signature
      and (pg_get_userbyid(function_row.proowner)<>'postgres'
        or not function_row.prosecdef
        or function_row.provolatile<>'s'
        or function_row.proconfig is distinct from
          array['search_path=pg_catalog, public'])
  ) then
    raise exception 'PHASE2C_D2_A2_READER_V3_SECURITY_INVALID';
  end if;
  if not has_function_privilege('authenticated',v_signature,'EXECUTE')
     or has_function_privilege('anon',v_signature,'EXECUTE')
     or has_function_privilege('service_role',v_signature,'EXECUTE') then
    raise exception 'PHASE2C_D2_A2_READER_V3_ACL_INVALID';
  end if;
end
$verify$;

\if :{?PHASE2C_D2_A2_REHEARSAL}
\else
commit;
\endif
