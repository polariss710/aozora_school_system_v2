-- School V2 student monthly status Phase B5 core, 2026-08-07.
-- Function/ACL definitions only. No business DML.

create or replace function public.school_preview_student_status_transition_core_v1(
  p_student_id uuid,
  p_requested_status text,
  p_input_month date,
  p_expected_current_event_id uuid
)
returns table (
  student_id uuid,
  current_month date,
  current_status text,
  current_source_event_id uuid,
  current_source_effective_month date,
  is_fallback_active boolean,
  latest_event_id uuid,
  latest_event_effective_month date,
  input_month date,
  effective_month date,
  requested_status text,
  transition_kind text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_current_month date := date_trunc('month', statement_timestamp() at time zone 'Asia/Tokyo')::date;
  v_requested_status text := lower(trim(coalesce(p_requested_status, '')));
  v_current record;
  v_latest record;
  v_effective_month date;
  v_transition_kind text;
begin
  if p_student_id is null or p_input_month is null
     or p_input_month <> date_trunc('month', p_input_month)::date then
    raise exception using errcode = '22023', message = 'STUDENT_STATUS_TRANSITION_MONTH_FIRST_REQUIRED';
  end if;
  if v_requested_status not in ('active', 'paused', 'left') then
    raise exception using errcode = '22023', message = 'STUDENT_STATUS_VALUE_INVALID';
  end if;
  if not exists (
    select 1 from public.school_students s
    where s.id = p_student_id and s.app_type = 'school'
  ) then
    raise exception using errcode = 'P0002', message = 'STUDENT_STATUS_STUDENT_NOT_FOUND';
  end if;

  select * into strict v_current
  from public.school_resolve_student_status_at_month_core_v1(p_student_id, v_current_month);

  select e.id, e.effective_month, e.status
  into v_latest
  from public.school_student_status_events e
  where e.student_id = p_student_id and e.voided_at is null
  order by e.effective_month desc, e.created_at desc, e.id desc
  limit 1;

  if v_latest.id is distinct from p_expected_current_event_id then
    raise exception using errcode = '40001', message = 'STUDENT_STATUS_EXPECTED_CURRENT_EVENT_MISMATCH';
  end if;
  if v_latest.effective_month is not null and v_latest.effective_month > v_current_month then
    raise exception using errcode = '23514', message = 'STUDENT_STATUS_FUTURE_EVENT_REQUIRES_CORRECTION';
  end if;
  if v_current.resolved_status = v_requested_status then
    raise exception using errcode = '23514', message = 'STUDENT_STATUS_REDUNDANT_STATE_EVENT';
  end if;

  if v_current.resolved_status = 'active' and v_requested_status in ('paused', 'left') then
    v_effective_month := (p_input_month + interval '1 month')::date;
    v_transition_kind := 'active_to_' || v_requested_status;
  elsif v_current.resolved_status = 'paused' and v_requested_status = 'active' then
    v_effective_month := p_input_month;
    v_transition_kind := 'paused_to_active';
  elsif v_current.resolved_status = 'paused' and v_requested_status = 'left' then
    v_effective_month := p_input_month;
    v_transition_kind := 'paused_to_left';
    if v_current.source_effective_month is not null
       and v_effective_month < v_current.source_effective_month then
      raise exception using errcode = '23514', message = 'STUDENT_STATUS_LEFT_MONTH_BEFORE_PAUSE';
    end if;
  elsif v_current.resolved_status = 'left' and v_requested_status = 'active' then
    v_effective_month := p_input_month;
    v_transition_kind := 'left_to_active';
  else
    raise exception using errcode = '23514', message = 'STUDENT_STATUS_TRANSITION_FORBIDDEN';
  end if;

  if v_latest.effective_month is not null and v_effective_month <= v_latest.effective_month then
    raise exception using errcode = '23514', message = 'STUDENT_STATUS_TRANSITION_OUT_OF_ORDER';
  end if;
  if exists (
    select 1 from public.school_student_status_events e
    where e.student_id = p_student_id
      and e.voided_at is null
      and e.effective_month = v_effective_month
  ) then
    raise exception using errcode = '23505', message = 'STUDENT_STATUS_ACTIVE_EVENT_MONTH_EXISTS';
  end if;

  return query select p_student_id, v_current_month, v_current.resolved_status,
    v_current.source_event_id, v_current.source_effective_month,
    v_current.is_legacy_fallback, v_latest.id, v_latest.effective_month,
    p_input_month, v_effective_month, v_requested_status, v_transition_kind;
end;
$function$;

create or replace function public.school_preview_student_status_transition_v1(
  p_student_id uuid,
  p_requested_status text,
  p_input_month date,
  p_expected_current_event_id uuid
)
returns table (
  student_id uuid,
  current_month date,
  current_status text,
  current_source_event_id uuid,
  current_source_effective_month date,
  is_fallback_active boolean,
  latest_event_id uuid,
  latest_event_effective_month date,
  input_month date,
  effective_month date,
  requested_status text,
  transition_kind text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
begin
  perform public.school_require_current_app_student_reader_v1();
  return query select *
  from public.school_preview_student_status_transition_core_v1(
    p_student_id, p_requested_status, p_input_month, p_expected_current_event_id
  );
end;
$function$;

create or replace function public.school_transition_student_status_v1(
  p_student_id uuid,
  p_requested_status text,
  p_input_month date,
  p_reason text,
  p_expected_current_event_id uuid,
  p_confirmation text
)
returns table (
  event_id uuid,
  student_id uuid,
  input_month date,
  effective_month date,
  previous_status text,
  resolved_status text,
  transition_kind text,
  reason text,
  row_version uuid,
  created_at timestamptz,
  current_event_id uuid
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_preview record;
  v_event record;
begin
  perform public.school_require_current_app_admin();
  if p_confirmation is distinct from 'TRANSITION_STUDENT_STATUS_V1' then
    raise exception using errcode = '22023', message = 'STUDENT_STATUS_TRANSITION_CONFIRMATION_REQUIRED';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) not between 1 and 1000 then
    raise exception using errcode = '22023', message = 'STUDENT_STATUS_REASON_INVALID';
  end if;

  perform 1 from public.school_students s
  where s.id = p_student_id and s.app_type = 'school'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'STUDENT_STATUS_STUDENT_NOT_FOUND';
  end if;
  perform 1 from public.school_student_status_events e
  where e.student_id = p_student_id
  order by e.effective_month, e.created_at, e.id
  for update;

  select * into strict v_preview
  from public.school_preview_student_status_transition_core_v1(
    p_student_id, p_requested_status, p_input_month, p_expected_current_event_id
  );

  select * into strict v_event
  from public.school_record_student_status_event_v1(
    p_student_id,
    v_preview.effective_month,
    v_preview.requested_status,
    trim(p_reason),
    v_preview.latest_event_id,
    'RECORD_STUDENT_STATUS_EVENT_V1'
  );

  return query select v_event.event_id, v_event.student_id, v_preview.input_month,
    v_event.effective_month, v_preview.current_status, v_event.status,
    v_preview.transition_kind, v_event.reason, v_event.row_version,
    v_event.created_at, v_event.current_event_id;
end;
$function$;

create or replace function public.school_preview_student_status_correction_core_v1(
  p_event_id uuid,
  p_expected_row_version uuid,
  p_expected_current_event_id uuid,
  p_replacement_effective_month date,
  p_replacement_status text
)
returns table (
  event_id uuid,
  student_id uuid,
  original_effective_month date,
  original_status text,
  replacement_effective_month date,
  replacement_status text,
  expected_current_event_id uuid,
  affected_start_month date,
  affected_end_month date
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_target public.school_student_status_events%rowtype;
  v_latest_event_id uuid;
  v_replacement_status text := lower(trim(coalesce(p_replacement_status, '')));
  v_affected_start date;
  v_next_month date;
begin
  if p_event_id is null or p_expected_row_version is null
     or p_replacement_effective_month is null
     or p_replacement_effective_month <> date_trunc('month', p_replacement_effective_month)::date then
    raise exception using errcode = '22023', message = 'STUDENT_STATUS_CORRECTION_INPUT_INVALID';
  end if;
  if v_replacement_status not in ('active', 'paused', 'left') then
    raise exception using errcode = '22023', message = 'STUDENT_STATUS_VALUE_INVALID';
  end if;

  select * into v_target
  from public.school_student_status_events e
  where e.id = p_event_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'STUDENT_STATUS_EVENT_NOT_FOUND';
  end if;
  if v_target.voided_at is not null then
    raise exception using errcode = '23514', message = 'STUDENT_STATUS_EVENT_ALREADY_VOIDED';
  end if;
  if v_target.row_version is distinct from p_expected_row_version then
    raise exception using errcode = '40001', message = 'STUDENT_STATUS_EVENT_VERSION_MISMATCH';
  end if;

  select e.id into v_latest_event_id
  from public.school_student_status_events e
  where e.student_id = v_target.student_id and e.voided_at is null
  order by e.effective_month desc, e.created_at desc, e.id desc
  limit 1;
  if v_latest_event_id is distinct from p_expected_current_event_id then
    raise exception using errcode = '40001', message = 'STUDENT_STATUS_EXPECTED_CURRENT_EVENT_MISMATCH';
  end if;
  if exists (
    select 1 from public.school_student_status_events e
    where e.student_id = v_target.student_id
      and e.voided_at is null
      and e.id <> v_target.id
      and e.effective_month = p_replacement_effective_month
  ) then
    raise exception using errcode = '23505', message = 'STUDENT_STATUS_ACTIVE_EVENT_MONTH_EXISTS';
  end if;

  if exists (
    with timeline as (
      select e.effective_month, e.status, e.created_at, e.id
      from public.school_student_status_events e
      where e.student_id = v_target.student_id and e.voided_at is null and e.id <> v_target.id
      union all
      select p_replacement_effective_month, v_replacement_status,
        v_target.created_at, v_target.id
    ), ordered as (
      select t.*,
        lag(t.status, 1, 'active') over (order by t.effective_month, t.created_at, t.id) as previous_status
      from timeline t
    )
    select 1 from ordered o
    where o.status = o.previous_status
       or not (
         (o.previous_status = 'active' and o.status in ('paused', 'left'))
         or (o.previous_status = 'paused' and o.status in ('active', 'left'))
         or (o.previous_status = 'left' and o.status = 'active')
       )
  ) then
    raise exception using errcode = '23514', message = 'STUDENT_STATUS_CORRECTION_SEQUENCE_INVALID';
  end if;

  v_affected_start := least(v_target.effective_month, p_replacement_effective_month);
  select min(e.effective_month) into v_next_month
  from public.school_student_status_events e
  where e.student_id = v_target.student_id
    and e.voided_at is null
    and e.id <> v_target.id
    and e.effective_month > greatest(v_target.effective_month, p_replacement_effective_month);

  return query select v_target.id, v_target.student_id,
    v_target.effective_month, v_target.status,
    p_replacement_effective_month, v_replacement_status,
    v_latest_event_id, v_affected_start,
    case when v_next_month is null then null::date else (v_next_month - interval '1 month')::date end;
end;
$function$;

create or replace function public.school_preview_student_status_correction_v1(
  p_event_id uuid,
  p_expected_row_version uuid,
  p_expected_current_event_id uuid,
  p_replacement_effective_month date,
  p_replacement_status text
)
returns table (
  event_id uuid,
  student_id uuid,
  original_effective_month date,
  original_status text,
  replacement_effective_month date,
  replacement_status text,
  expected_current_event_id uuid,
  affected_start_month date,
  affected_end_month date
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
begin
  perform public.school_require_current_app_student_reader_v1();
  return query select *
  from public.school_preview_student_status_correction_core_v1(
    p_event_id, p_expected_row_version, p_expected_current_event_id,
    p_replacement_effective_month, p_replacement_status
  );
end;
$function$;

create or replace function public.school_correct_student_status_event_v1(
  p_event_id uuid,
  p_expected_row_version uuid,
  p_expected_current_event_id uuid,
  p_replacement_effective_month date,
  p_replacement_status text,
  p_replacement_reason text,
  p_correction_reason text,
  p_confirmation text
)
returns table (
  voided_event_id uuid,
  voided_event_new_row_version uuid,
  replacement_event_id uuid,
  replacement_row_version uuid,
  student_id uuid,
  replacement_effective_month date,
  replacement_status text,
  affected_start_month date,
  affected_end_month date,
  corrected_by_user_id uuid,
  corrected_by_membership_id uuid,
  corrected_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_target_student_id uuid;
  v_preview record;
  v_result record;
begin
  perform public.school_require_current_app_admin();
  if p_confirmation is distinct from 'CORRECT_STUDENT_STATUS_EVENT_B5_V1' then
    raise exception using errcode = '22023', message = 'STUDENT_STATUS_CORRECTION_CONFIRMATION_REQUIRED';
  end if;

  select e.student_id into v_target_student_id
  from public.school_student_status_events e where e.id = p_event_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'STUDENT_STATUS_EVENT_NOT_FOUND';
  end if;
  perform 1 from public.school_students s where s.id = v_target_student_id for update;
  perform 1 from public.school_student_status_events e
  where e.student_id = v_target_student_id
  order by e.effective_month, e.created_at, e.id
  for update;

  select * into strict v_preview
  from public.school_preview_student_status_correction_core_v1(
    p_event_id, p_expected_row_version, p_expected_current_event_id,
    p_replacement_effective_month, p_replacement_status
  );

  select * into strict v_result
  from public.school_correct_student_status_event_v1(
    p_event_id, p_expected_row_version, p_replacement_effective_month,
    p_replacement_status, trim(p_replacement_reason), trim(p_correction_reason),
    'CORRECT_STUDENT_STATUS_EVENT_V1'
  );

  return query select v_result.voided_event_id, v_result.voided_event_new_row_version,
    v_result.replacement_event_id, v_result.replacement_row_version,
    v_result.student_id, v_result.replacement_effective_month,
    v_result.replacement_status, v_result.affected_start_month,
    v_result.affected_end_month, v_result.corrected_by_user_id,
    v_result.corrected_by_membership_id, v_result.corrected_at;
end;
$function$;

create or replace function public.school_list_student_status_management_v1()
returns table (
  student_id uuid,
  current_month date,
  resolved_status text,
  source_event_id uuid,
  source_effective_month date,
  is_fallback_active boolean,
  current_reason text,
  current_actor text,
  latest_event_id uuid,
  latest_event_effective_month date,
  latest_event_status text,
  latest_event_row_version uuid,
  has_future_event boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_current_month date := date_trunc('month', statement_timestamp() at time zone 'Asia/Tokyo')::date;
begin
  perform public.school_require_current_app_student_reader_v1();
  return query
  select s.id, v_current_month, r.resolved_status, r.source_event_id,
    r.source_effective_month, r.is_legacy_fallback,
    se.reason, coalesce(su.email::text, se.created_by_user_id::text),
    le.id, le.effective_month, le.status, le.row_version,
    coalesce(le.effective_month > v_current_month, false)
  from public.school_students s
  cross join lateral public.school_resolve_student_status_at_month_core_v1(s.id, v_current_month) r
  left join public.school_student_status_events se on se.id = r.source_event_id
  left join auth.users su on su.id = se.created_by_user_id
  left join lateral (
    select e.id, e.effective_month, e.status, e.row_version
    from public.school_student_status_events e
    where e.student_id = s.id and e.voided_at is null
    order by e.effective_month desc, e.created_at desc, e.id desc
    limit 1
  ) le on true
  where s.app_type = 'school'
  order by coalesce(nullif(s.display_name, ''), s.name), s.name, s.id;
end;
$function$;

create or replace function public.school_list_student_status_history_v1(p_student_id uuid)
returns table (
  event_id uuid,
  student_id uuid,
  effective_month date,
  status text,
  reason text,
  row_version uuid,
  created_actor text,
  created_at timestamptz,
  is_voided boolean,
  voided_actor text,
  voided_at timestamptz,
  correction_reason text,
  replacement_event_id uuid
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
begin
  perform public.school_require_current_app_student_reader_v1();
  if p_student_id is null or not exists (
    select 1 from public.school_students s where s.id = p_student_id and s.app_type = 'school'
  ) then
    raise exception using errcode = 'P0002', message = 'STUDENT_STATUS_STUDENT_NOT_FOUND';
  end if;
  return query
  select e.id, e.student_id, e.effective_month, e.status, e.reason, e.row_version,
    coalesce(cu.email::text, e.created_by_user_id::text), e.created_at,
    e.voided_at is not null,
    case when e.voided_at is null then null::text
      else coalesce(vu.email::text, e.voided_by_user_id::text) end,
    e.voided_at, e.void_reason, e.replacement_event_id
  from public.school_student_status_events e
  left join auth.users cu on cu.id = e.created_by_user_id
  left join auth.users vu on vu.id = e.voided_by_user_id
  where e.student_id = p_student_id
  order by e.effective_month desc, e.created_at desc, e.id desc;
end;
$function$;

revoke all on function public.school_preview_student_status_transition_core_v1(uuid,text,date,uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.school_preview_student_status_correction_core_v1(uuid,uuid,uuid,date,text)
  from public, anon, authenticated, service_role;

revoke all on function public.school_preview_student_status_transition_v1(uuid,text,date,uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.school_preview_student_status_correction_v1(uuid,uuid,uuid,date,text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_list_student_status_management_v1()
  from public, anon, authenticated, service_role;
revoke all on function public.school_list_student_status_history_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.school_preview_student_status_transition_v1(uuid,text,date,uuid) to authenticated;
grant execute on function public.school_preview_student_status_correction_v1(uuid,uuid,uuid,date,text) to authenticated;
grant execute on function public.school_list_student_status_management_v1() to authenticated;
grant execute on function public.school_list_student_status_history_v1(uuid) to authenticated;

revoke all on function public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_transition_student_status_v1(uuid,text,date,text,uuid,text)
  from public, anon, authenticated, service_role;
revoke all on function public.school_correct_student_status_event_v1(uuid,uuid,uuid,date,text,text,text,text)
  from public, anon, authenticated, service_role;

comment on function public.school_transition_student_status_v1(uuid,text,date,text,uuid,text) is
  'B5 active-admin interactive transition. DB derives actor and effective month, locks the student timeline, then calls the owner-only Phase A append writer.';
comment on function public.school_correct_student_status_event_v1(uuid,uuid,uuid,date,text,text,text,text) is
  'B5 active-admin correction overload. Expected target row version and expected latest event are checked under the student timeline lock before atomic void plus replacement.';
comment on function public.school_list_student_status_management_v1() is
  'B5 active-membership current Tokyo-month status management reader. Events are sole authority and fallback active never reads legacy status.';
comment on function public.school_list_student_status_history_v1(uuid) is
  'B5 active-membership append/correction history reader including void and replacement audit.';
