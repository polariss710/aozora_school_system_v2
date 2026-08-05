-- School V2 student monthly status Phase A RPCs, 2026-08-05.
-- RPC only: membership guards, authoritative resolvers, append writer and correction writer.

create function public.school_require_current_app_student_reader_v1()
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid:=auth.uid();
begin
  if v_actor is null then
    raise exception using errcode='42501',message='STUDENT_STATUS_AUTH_REQUIRED';
  end if;
  if not exists (
    select 1 from public.school_app_memberships m
    where m.user_id=v_actor and m.is_active
      and m.role in ('admin','operator','read_only')
  ) then
    raise exception using errcode='42501',message='STUDENT_STATUS_ACTIVE_MEMBERSHIP_REQUIRED';
  end if;
  return v_actor;
end;
$function$;

create function public.school_resolve_student_status_at_month_core_v1(
  p_student_id uuid,
  p_target_month date
)
returns table (
  student_id uuid,
  resolved_status text,
  source_event_id uuid,
  source_effective_month date,
  is_legacy_fallback boolean,
  is_active boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_event record;
begin
  if p_student_id is null or p_target_month is null then
    raise exception using errcode='22023',message='STUDENT_STATUS_STUDENT_AND_MONTH_REQUIRED';
  end if;
  if p_target_month<>date_trunc('month',p_target_month)::date then
    raise exception using errcode='22023',message='STUDENT_STATUS_MONTH_FIRST_REQUIRED';
  end if;
  if not exists (
    select 1 from public.school_students s
    where s.id=p_student_id and s.app_type='school'
  ) then
    raise exception using errcode='P0002',message='STUDENT_STATUS_STUDENT_NOT_FOUND';
  end if;

  select e.id,e.effective_month,e.status
  into v_event
  from public.school_student_status_events e
  where e.student_id=p_student_id
    and e.voided_at is null
    and e.effective_month<=p_target_month
  order by e.effective_month desc,e.created_at desc,e.id desc
  limit 1;

  if found then
    return query select p_student_id,v_event.status,v_event.id,v_event.effective_month,false,v_event.status='active';
  else
    return query select p_student_id,'active'::text,null::uuid,null::date,true,true;
  end if;
end;
$function$;

create function public.school_resolve_student_status_at_month_v1(
  p_student_id uuid,
  p_target_month date
)
returns table (
  student_id uuid,
  resolved_status text,
  source_event_id uuid,
  source_effective_month date,
  is_legacy_fallback boolean,
  is_active boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
begin
  perform public.school_require_current_app_student_reader_v1();
  return query select * from public.school_resolve_student_status_at_month_core_v1(p_student_id,p_target_month);
end;
$function$;

create function public.school_list_student_month_candidates_v1(
  p_target_month date,
  p_include_inactive boolean default false,
  p_selected_student_id uuid default null
)
returns table (
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
  is_selected_override boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
begin
  perform public.school_require_current_app_student_reader_v1();
  if p_target_month is null or p_target_month<>date_trunc('month',p_target_month)::date then
    raise exception using errcode='22023',message='STUDENT_STATUS_MONTH_FIRST_REQUIRED';
  end if;
  if p_selected_student_id is not null and not exists (
    select 1 from public.school_students s
    where s.id=p_selected_student_id and s.app_type='school'
  ) then
    raise exception using errcode='P0002',message='STUDENT_STATUS_SELECTED_STUDENT_NOT_FOUND';
  end if;

  return query
  select s.id,s.student_code,s.name,s.display_name,s.business_entity_id,
         r.resolved_status,r.source_event_id,r.source_effective_month,
         r.is_legacy_fallback,r.is_active,(s.id=p_selected_student_id)
  from public.school_students s
  cross join lateral public.school_resolve_student_status_at_month_core_v1(s.id,p_target_month) r
  where s.app_type='school'
    and (coalesce(p_include_inactive,false) or r.is_active or s.id=p_selected_student_id)
  order by coalesce(nullif(s.display_name,''),s.name),s.name,s.id;
end;
$function$;

create function public.school_list_student_range_candidates_v1(
  p_start_date date,
  p_end_date date,
  p_include_inactive boolean default false,
  p_selected_student_id uuid default null
)
returns table (
  student_id uuid,
  student_code text,
  name text,
  display_name text,
  business_entity_id uuid,
  start_month date,
  end_month date,
  status_at_start text,
  status_at_end text,
  end_source_event_id uuid,
  end_source_effective_month date,
  end_is_legacy_fallback boolean,
  is_active_in_range boolean,
  is_selected_override boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_start_month date;
  v_end_month date;
begin
  perform public.school_require_current_app_student_reader_v1();
  if p_start_date is null or p_end_date is null or p_start_date>p_end_date then
    raise exception using errcode='22023',message='STUDENT_STATUS_DATE_RANGE_INVALID';
  end if;
  v_start_month:=date_trunc('month',p_start_date)::date;
  v_end_month:=date_trunc('month',p_end_date)::date;
  if p_selected_student_id is not null and not exists (
    select 1 from public.school_students s
    where s.id=p_selected_student_id and s.app_type='school'
  ) then
    raise exception using errcode='P0002',message='STUDENT_STATUS_SELECTED_STUDENT_NOT_FOUND';
  end if;

  return query
  with resolved as (
    select s.id,s.student_code,s.name,s.display_name,s.business_entity_id,
           rs.resolved_status status_at_start,
           re.resolved_status status_at_end,
           re.source_event_id end_source_event_id,
           re.source_effective_month end_source_effective_month,
           re.is_legacy_fallback end_is_legacy_fallback,
           exists (
             select 1
             from generate_series(v_start_month,v_end_month,interval '1 month') m(month_value)
             cross join lateral public.school_resolve_student_status_at_month_core_v1(s.id,m.month_value::date) rm
             where rm.is_active
           ) is_active_in_range
    from public.school_students s
    cross join lateral public.school_resolve_student_status_at_month_core_v1(s.id,v_start_month) rs
    cross join lateral public.school_resolve_student_status_at_month_core_v1(s.id,v_end_month) re
    where s.app_type='school'
  )
  select r.id,r.student_code,r.name,r.display_name,r.business_entity_id,
         v_start_month,v_end_month,r.status_at_start,r.status_at_end,
         r.end_source_event_id,r.end_source_effective_month,r.end_is_legacy_fallback,
         r.is_active_in_range,(r.id=p_selected_student_id)
  from resolved r
  where coalesce(p_include_inactive,false) or r.is_active_in_range or r.id=p_selected_student_id
  order by coalesce(nullif(r.display_name,''),r.name),r.name,r.id;
end;
$function$;

create function public.school_assert_student_status_sequence_v1(p_student_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_previous text:='active';
  v_event record;
begin
  for v_event in
    select e.id,e.effective_month,e.status
    from public.school_student_status_events e
    where e.student_id=p_student_id and e.voided_at is null
    order by e.effective_month,e.created_at,e.id
  loop
    if v_event.status=v_previous then
      raise exception using errcode='23514',message='STUDENT_STATUS_REDUNDANT_STATE_EVENT';
    end if;
    if not (
      (v_previous='active' and v_event.status in ('paused','left'))
      or (v_previous='paused' and v_event.status in ('active','left'))
      or (v_previous='left' and v_event.status='active')
    ) then
      raise exception using errcode='23514',message='STUDENT_STATUS_TRANSITION_FORBIDDEN';
    end if;
    v_previous:=v_event.status;
  end loop;
end;
$function$;

create function public.school_record_student_status_event_v1(
  p_student_id uuid,
  p_effective_month date,
  p_status text,
  p_reason text,
  p_expected_current_event_id uuid,
  p_confirmation text
)
returns table (
  event_id uuid,
  student_id uuid,
  effective_month date,
  status text,
  reason text,
  row_version uuid,
  created_by_user_id uuid,
  created_by_membership_id uuid,
  created_at timestamptz,
  current_event_id uuid,
  canonical_status_after_event text
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_actor uuid;
  v_status text;
  v_reason text;
  v_current_event_id uuid;
  v_inserted public.school_student_status_events%rowtype;
begin
  v_actor:=public.school_require_current_app_admin();
  if p_confirmation is distinct from 'RECORD_STUDENT_STATUS_EVENT_V1' then
    raise exception using errcode='22023',message='STUDENT_STATUS_CONFIRMATION_REQUIRED';
  end if;
  if p_student_id is null or p_effective_month is null
     or p_effective_month<>date_trunc('month',p_effective_month)::date then
    raise exception using errcode='22023',message='STUDENT_STATUS_STUDENT_AND_MONTH_FIRST_REQUIRED';
  end if;
  v_status:=lower(trim(coalesce(p_status,'')));
  v_reason:=trim(coalesce(p_reason,''));
  if v_status not in ('active','paused','left') then
    raise exception using errcode='22023',message='STUDENT_STATUS_VALUE_INVALID';
  end if;
  if char_length(v_reason) not between 1 and 1000 then
    raise exception using errcode='22023',message='STUDENT_STATUS_REASON_INVALID';
  end if;

  perform 1 from public.school_students s
  where s.id=p_student_id and s.app_type='school'
  for update;
  if not found then
    raise exception using errcode='P0002',message='STUDENT_STATUS_STUDENT_NOT_FOUND';
  end if;
  perform 1 from public.school_student_status_events e
  where e.student_id=p_student_id for update;

  select e.id into v_current_event_id
  from public.school_student_status_events e
  where e.student_id=p_student_id and e.voided_at is null
  order by e.effective_month desc,e.created_at desc,e.id desc
  limit 1;
  if v_current_event_id is distinct from p_expected_current_event_id then
    raise exception using errcode='40001',message='STUDENT_STATUS_EXPECTED_CURRENT_EVENT_MISMATCH';
  end if;
  if exists (
    select 1 from public.school_student_status_events e
    where e.student_id=p_student_id and e.effective_month=p_effective_month and e.voided_at is null
  ) then
    raise exception using errcode='23505',message='STUDENT_STATUS_ACTIVE_EVENT_MONTH_EXISTS';
  end if;

  insert into public.school_student_status_events (
    student_id,effective_month,status,reason,created_by_user_id,created_by_membership_id
  ) values (
    p_student_id,p_effective_month,v_status,v_reason,v_actor,v_actor
  ) returning * into v_inserted;

  perform public.school_assert_student_status_sequence_v1(p_student_id);

  select e.id into strict v_current_event_id
  from public.school_student_status_events e
  where e.student_id=p_student_id and e.voided_at is null
  order by e.effective_month desc,e.created_at desc,e.id desc limit 1;

  return query select v_inserted.id,v_inserted.student_id,v_inserted.effective_month,
    v_inserted.status,v_inserted.reason,v_inserted.row_version,
    v_inserted.created_by_user_id,v_inserted.created_by_membership_id,v_inserted.created_at,
    v_current_event_id,v_inserted.status;
end;
$function$;

create function public.school_correct_student_status_event_v1(
  p_event_id uuid,
  p_expected_row_version uuid,
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
  v_actor uuid;
  v_target public.school_student_status_events%rowtype;
  v_replacement public.school_student_status_events%rowtype;
  v_status text;
  v_replacement_reason text;
  v_correction_reason text;
  v_replacement_id uuid:=gen_random_uuid();
  v_voided_version uuid:=gen_random_uuid();
  v_corrected_at timestamptz:=clock_timestamp();
  v_affected_start date;
  v_next_month date;
begin
  v_actor:=public.school_require_current_app_admin();
  if p_confirmation is distinct from 'CORRECT_STUDENT_STATUS_EVENT_V1' then
    raise exception using errcode='22023',message='STUDENT_STATUS_CORRECTION_CONFIRMATION_REQUIRED';
  end if;
  if p_event_id is null or p_expected_row_version is null
     or p_replacement_effective_month is null
     or p_replacement_effective_month<>date_trunc('month',p_replacement_effective_month)::date then
    raise exception using errcode='22023',message='STUDENT_STATUS_CORRECTION_INPUT_INVALID';
  end if;
  v_status:=lower(trim(coalesce(p_replacement_status,'')));
  v_replacement_reason:=trim(coalesce(p_replacement_reason,''));
  v_correction_reason:=trim(coalesce(p_correction_reason,''));
  if v_status not in ('active','paused','left') then
    raise exception using errcode='22023',message='STUDENT_STATUS_VALUE_INVALID';
  end if;
  if char_length(v_replacement_reason) not between 1 and 1000
     or char_length(v_correction_reason) not between 1 and 1000 then
    raise exception using errcode='22023',message='STUDENT_STATUS_CORRECTION_REASON_INVALID';
  end if;

  select * into v_target from public.school_student_status_events e where e.id=p_event_id;
  if not found then
    raise exception using errcode='P0002',message='STUDENT_STATUS_EVENT_NOT_FOUND';
  end if;
  perform 1 from public.school_students s where s.id=v_target.student_id for update;
  select * into strict v_target
  from public.school_student_status_events e where e.id=p_event_id for update;
  perform 1 from public.school_student_status_events e
  where e.student_id=v_target.student_id for update;

  if v_target.voided_at is not null then
    raise exception using errcode='23514',message='STUDENT_STATUS_EVENT_ALREADY_VOIDED';
  end if;
  if v_target.row_version is distinct from p_expected_row_version then
    raise exception using errcode='40001',message='STUDENT_STATUS_EVENT_VERSION_MISMATCH';
  end if;
  if exists (
    select 1 from public.school_student_status_events e
    where e.student_id=v_target.student_id
      and e.voided_at is null
      and e.id<>v_target.id
      and e.effective_month=p_replacement_effective_month
  ) then
    raise exception using errcode='23505',message='STUDENT_STATUS_ACTIVE_EVENT_MONTH_EXISTS';
  end if;

  perform set_config('school.student_status_correction_context_v1',v_target.id::text||':'||v_replacement_id::text,true);
  update public.school_student_status_events e
  set voided_at=v_corrected_at,
      voided_by_user_id=v_actor,
      voided_by_membership_id=v_actor,
      void_reason=v_correction_reason,
      replacement_event_id=v_replacement_id,
      row_version=v_voided_version
  where e.id=v_target.id;

  insert into public.school_student_status_events (
    id,student_id,effective_month,status,reason,created_by_user_id,created_by_membership_id
  ) values (
    v_replacement_id,v_target.student_id,p_replacement_effective_month,v_status,
    v_replacement_reason,v_actor,v_actor
  ) returning * into v_replacement;

  perform public.school_assert_student_status_sequence_v1(v_target.student_id);

  v_affected_start:=least(v_target.effective_month,p_replacement_effective_month);
  select min(e.effective_month) into v_next_month
  from public.school_student_status_events e
  where e.student_id=v_target.student_id and e.voided_at is null
    and e.effective_month>greatest(v_target.effective_month,p_replacement_effective_month);

  return query select v_target.id,v_voided_version,v_replacement.id,v_replacement.row_version,
    v_target.student_id,v_replacement.effective_month,v_replacement.status,
    v_affected_start,
    case when v_next_month is null then null::date else (v_next_month-interval '1 month')::date end,
    v_actor,v_actor,v_corrected_at;
end;
$function$;

create function public.school_list_student_status_shadow_v1(p_target_month date)
returns table (
  student_id uuid,
  student_code text,
  name text,
  legacy_status text,
  legacy_normalized_status text,
  resolved_status text,
  source_event_id uuid,
  source_effective_month date,
  is_legacy_fallback boolean,
  is_diff boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
begin
  perform public.school_require_current_app_student_reader_v1();
  if p_target_month is null or p_target_month<>date_trunc('month',p_target_month)::date then
    raise exception using errcode='22023',message='STUDENT_STATUS_MONTH_FIRST_REQUIRED';
  end if;
  return query
  select s.id,s.student_code,s.name,s.status,
         case when s.status in ('graduated','withdrawn') then 'left' else s.status end,
         r.resolved_status,r.source_event_id,r.source_effective_month,r.is_legacy_fallback,
         case when s.status in ('graduated','withdrawn') then 'left' else s.status end<>r.resolved_status
  from public.school_students s
  cross join lateral public.school_resolve_student_status_at_month_core_v1(s.id,p_target_month) r
  where s.app_type='school'
  order by coalesce(nullif(s.display_name,''),s.name),s.name,s.id;
end;
$function$;

revoke all on function public.school_require_current_app_student_reader_v1() from public,anon,authenticated,service_role;
revoke all on function public.school_resolve_student_status_at_month_core_v1(uuid,date) from public,anon,authenticated,service_role;
revoke all on function public.school_assert_student_status_sequence_v1(uuid) from public,anon,authenticated,service_role;

revoke all on function public.school_resolve_student_status_at_month_v1(uuid,date) from public,anon,authenticated,service_role;
revoke all on function public.school_list_student_month_candidates_v1(date,boolean,uuid) from public,anon,authenticated,service_role;
revoke all on function public.school_list_student_range_candidates_v1(date,date,boolean,uuid) from public,anon,authenticated,service_role;
revoke all on function public.school_list_student_status_shadow_v1(date) from public,anon,authenticated,service_role;
grant execute on function public.school_resolve_student_status_at_month_v1(uuid,date) to authenticated;
grant execute on function public.school_list_student_month_candidates_v1(date,boolean,uuid) to authenticated;
grant execute on function public.school_list_student_range_candidates_v1(date,date,boolean,uuid) to authenticated;
grant execute on function public.school_list_student_status_shadow_v1(date) to authenticated;

revoke all on function public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text) to authenticated;
grant execute on function public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text) to authenticated;

comment on function public.school_resolve_student_status_at_month_v1(uuid,date) is
  'Active-membership reader. Events are sole authority; before the first event and with no event the result is active fallback and school_students.status is ignored.';
comment on function public.school_list_student_range_candidates_v1(date,date,boolean,uuid) is
  'Treats input dates as Tokyo business dates and evaluates every covered natural month. Page modules are not migrated in Phase A.';
comment on function public.school_record_student_status_event_v1(uuid,date,text,text,uuid,text) is
  'Active-admin append writer with student/sequence locks, expected latest active event UUID and full transition validation.';
comment on function public.school_correct_student_status_event_v1(uuid,uuid,date,text,text,text,text) is
  'Active-admin atomic correction: one-way voids an active event and creates its replacement after expected row-version validation.';
comment on function public.school_list_student_status_shadow_v1(date) is
  'Diagnostic-only active-membership comparison between legacy snapshot and the event resolver; it does not influence production authority.';
