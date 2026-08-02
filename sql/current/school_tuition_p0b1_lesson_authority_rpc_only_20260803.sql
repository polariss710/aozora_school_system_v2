-- School V2 tuition P0-B1: DB-authoritative lesson fee, RPC-only lesson DML,
-- consumed-source immutability, and shared P0-A operation locking.
-- Business-model expansion declaration:
--   new business tables/columns/statuses/facts: none;
--   changed authority/mutability/writer/locking: exactly the P0-B1 prompt
--   sections IV, VI, VII and VIII. No historical data DML is performed.

begin;

create or replace function public.school_tuition_p0b1_lock_lesson_scopes(
  p_scopes jsonb
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_scope record;
  v_count integer;
  v_previous_lock_timeout text := current_setting('lock_timeout');
begin
  if p_scopes is null or jsonb_typeof(p_scopes) <> 'array' then
    raise exception 'LESSON_OPERATION_SCOPE_INVALID';
  end if;

  select count(*) into v_count
  from (
    select distinct
      (item ->> 'student_id')::uuid student_id,
      (item ->> 'business_entity_id')::uuid business_entity_id,
      item ->> 'year_month' year_month
    from jsonb_array_elements(p_scopes) item
    where nullif(item ->> 'student_id','') is not null
      and nullif(item ->> 'business_entity_id','') is not null
      and (item ->> 'year_month') ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
  ) s;
  if v_count = 0 then
    raise exception 'LESSON_OPERATION_SCOPE_INVALID';
  end if;

  perform set_config('lock_timeout','8s',true);
  begin
    for v_scope in
      select distinct
        (item ->> 'student_id')::uuid student_id,
        (item ->> 'business_entity_id')::uuid business_entity_id,
        item ->> 'year_month' year_month
      from jsonb_array_elements(p_scopes) item
      where nullif(item ->> 'student_id','') is not null
        and nullif(item ->> 'business_entity_id','') is not null
        and (item ->> 'year_month') ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
      order by 1,2,3
    loop
      perform pg_advisory_xact_lock(hashtextextended(concat_ws('|',
        'student_tuition_operation_v1',v_scope.student_id::text,
        v_scope.business_entity_id::text,v_scope.year_month),0));
    end loop;

    -- The P0-A table order is normative. Lesson mutation is exclusive against
    -- Generate/settlement source reads; the four downstream tables are read only.
    lock table public.school_lesson_records in share row exclusive mode;
    lock table public.school_student_monthly_settlements in share mode;
    lock table public.school_student_settlement_carryovers in share mode;
    lock table public.school_student_settlement_adjustment_drafts in share mode;
    lock table public.school_student_settlement_adjustments in share mode;
  exception when lock_not_available or deadlock_detected then
    perform set_config('lock_timeout',v_previous_lock_timeout,true);
    raise exception using errcode='55P03',
      message='LESSON_SOURCE_BUSY: 学费来源正在更新，请重新读取后重试。';
  end;
  perform set_config('lock_timeout',v_previous_lock_timeout,true);
end
$function$;

create or replace function public.school_tuition_p0b1_lock_new_planned_scope(
  p_student_id uuid,
  p_business_entity_id uuid,
  p_lesson_date date
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if p_student_id is null or p_business_entity_id is null or p_lesson_date is null then
    return;
  end if;
  perform public.school_tuition_p0b1_lock_lesson_scopes(jsonb_build_array(
    jsonb_build_object(
      'student_id',p_student_id,
      'business_entity_id',p_business_entity_id,
      'year_month',to_char(date_trunc('week',p_lesson_date::timestamp),'YYYY-MM')
    )
  ));
end
$function$;

create or replace function public.school_tuition_p0b1_lock_new_planned_range(
  p_student_id uuid,
  p_business_entity_id uuid,
  p_start_date date,
  p_end_date date
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_scopes jsonb;
begin
  if p_student_id is null or p_business_entity_id is null
     or p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    return;
  end if;
  select jsonb_agg(jsonb_build_object(
    'student_id',p_student_id,
    'business_entity_id',p_business_entity_id,
    'year_month',m.year_month
  ) order by m.year_month)
  into v_scopes
  from (
    select distinct to_char(date_trunc('week',d::timestamp),'YYYY-MM') year_month
    from generate_series(p_start_date,p_end_date,interval '1 day') d
  ) m;
  perform public.school_tuition_p0b1_lock_lesson_scopes(v_scopes);
end
$function$;

create or replace function public.school_tuition_p0b1_lock_existing_lesson_scope(
  p_lesson_id uuid,
  p_new_student_id uuid default null,
  p_new_business_entity_id uuid default null,
  p_new_lesson_date date default null
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_lesson public.school_lesson_records%rowtype;
  v_old_month text;
  v_new_month text;
begin
  if p_lesson_id is null then return; end if;
  select l.* into v_lesson
  from public.school_lesson_records l
  where l.id=p_lesson_id and l.app_type='school';
  if not found then return; end if;

  v_old_month:=public.school_resolve_r1d_e_c_lesson_student_month(v_lesson.id);
  if v_old_month is null then
    raise exception 'LESSON_OPERATION_SCOPE_UNCLASSIFIED';
  end if;
  v_new_month:=case
    when v_lesson.lesson_type='planned' and p_new_lesson_date is not null
      then to_char(date_trunc('week',p_new_lesson_date::timestamp),'YYYY-MM')
    else v_old_month
  end;

  perform public.school_tuition_p0b1_lock_lesson_scopes(jsonb_build_array(
    jsonb_build_object('student_id',v_lesson.student_id,
      'business_entity_id',v_lesson.business_entity_id,'year_month',v_old_month),
    jsonb_build_object('student_id',coalesce(p_new_student_id,v_lesson.student_id),
      'business_entity_id',coalesce(p_new_business_entity_id,v_lesson.business_entity_id),
      'year_month',v_new_month)
  ));
end
$function$;

create or replace function public.school_tuition_p0b1_lesson_financial_authority()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_financial_changed boolean:=false;
  v_old_month text;
  v_consumed boolean:=false;
  v_relation_frozen boolean:=false;
begin
  if tg_op='DELETE' then
    v_old_month:=public.school_resolve_r1d_e_c_lesson_student_month(old.id);
    select exists(
      select 1 from public.school_student_monthly_settlements s
      where s.student_id=old.student_id
        and s.business_entity_id is not distinct from old.business_entity_id
        and s.year_month=v_old_month
        and public.school_tuition_p0a_consumed_bill_id(s.id) is not null
    ) or exists(
      select 1 from public.school_student_tuition_bill_lessons r
      where r.planned_lesson_id=old.id
    ) or exists(
      select 1 from public.school_lesson_records a
      where a.planned_lesson_id=old.id and a.lesson_type='actual'
    ) or exists(
      select 1 from public.school_teacher_wage_lock_details w
      where w.lesson_record_id=old.id
    ) into v_relation_frozen;
    if v_relation_frozen then
      raise exception 'LESSON_FINANCIAL_FACT_IMMUTABLE';
    end if;
    return old;
  end if;

  if new.app_type is distinct from 'school'
     or new.lesson_type not in ('planned','actual') then
    return new;
  end if;

  if tg_op='UPDATE' then
    v_financial_changed:=
      new.student_id is distinct from old.student_id
      or new.business_entity_id is distinct from old.business_entity_id
      or new.subject_id is distinct from old.subject_id
      or new.duration_hours is distinct from old.duration_hours
      or new.unit_price is distinct from old.unit_price
      or new.lesson_fee is distinct from old.lesson_fee
      or new.is_billable is distinct from old.is_billable
      or new.lesson_count is distinct from old.lesson_count
      or new.billing_month is distinct from old.billing_month
      or new.billing_week_start_date is distinct from old.billing_week_start_date
      or new.student_settlement_month is distinct from old.student_settlement_month
      or new.lesson_delivery_mode is distinct from old.lesson_delivery_mode
      or new.lesson_venue is distinct from old.lesson_venue
      or new.lesson_venue_id is distinct from old.lesson_venue_id
      or new.base_lesson_fee_jpy is distinct from old.base_lesson_fee_jpy
      or new.aircon_charge_status is distinct from old.aircon_charge_status
      or new.aircon_rate_id is distinct from old.aircon_rate_id
      or new.aircon_unit_price_jpy_snapshot is distinct from old.aircon_unit_price_jpy_snapshot
      or new.aircon_billable_hours_snapshot is distinct from old.aircon_billable_hours_snapshot
      or new.aircon_fee_jpy is distinct from old.aircon_fee_jpy
      or new.fee_calculation_version is distinct from old.fee_calculation_version
      or new.lesson_total_fee_jpy is distinct from old.lesson_total_fee_jpy
      or new.student_duration_overage_minutes is distinct from old.student_duration_overage_minutes
      or new.student_duration_overage_fee_jpy is distinct from old.student_duration_overage_fee_jpy
      or new.student_duration_overage_policy_version is distinct from old.student_duration_overage_policy_version
      or new.student_duration_overage_source is distinct from old.student_duration_overage_source
      or new.student_duration_overage_decided_at is distinct from old.student_duration_overage_decided_at;

    if v_financial_changed then
      v_old_month:=public.school_resolve_r1d_e_c_lesson_student_month(old.id);
      select exists(
        select 1 from public.school_student_monthly_settlements s
        where s.student_id=old.student_id
          and s.business_entity_id is not distinct from old.business_entity_id
          and s.year_month=v_old_month
          and public.school_tuition_p0a_consumed_bill_id(s.id) is not null
      ) into v_consumed;
      select exists(select 1 from public.school_student_tuition_bill_lessons r
                    where r.planned_lesson_id=old.id)
          or exists(select 1 from public.school_lesson_records a
                    where a.planned_lesson_id=old.id and a.lesson_type='actual')
          or exists(select 1 from public.school_teacher_wage_lock_details w
                    where w.lesson_record_id=old.id)
      into v_relation_frozen;
      if v_consumed or v_relation_frozen then
        raise exception 'LESSON_FINANCIAL_FACT_IMMUTABLE';
      end if;
    end if;
  end if;

  -- Client lesson_fee is never authoritative. Preserve frozen/no-op historical
  -- facts; calculate only inserts or changes to the approved fee inputs.
  if tg_op='INSERT'
     or new.duration_hours is distinct from old.duration_hours
     or new.unit_price is distinct from old.unit_price
     or new.is_billable is distinct from old.is_billable
     or new.lesson_type is distinct from old.lesson_type then
    if new.duration_hours is null or new.duration_hours <= 0 then
      raise exception 'LESSON_FEE_INPUT_INVALID';
    end if;
    if new.unit_price is null or new.unit_price < 0 then
      raise exception 'LESSON_FEE_INPUT_INVALID';
    end if;
    new.lesson_fee:=case
      when new.lesson_type='actual' and new.is_billable is distinct from true then 0
      else round(new.duration_hours * new.unit_price)
    end;
  elsif new.lesson_fee is distinct from old.lesson_fee then
    new.lesson_fee:=old.lesson_fee;
  end if;
  return new;
end
$function$;

drop trigger if exists trg_school_lesson_p0b1_financial_authority
on public.school_lesson_records;
create trigger trg_school_lesson_p0b1_financial_authority
before insert or update or delete on public.school_lesson_records
for each row execute function public.school_tuition_p0b1_lesson_financial_authority();

-- Patch only hash-pinned production entry definitions. The compatibility amount
-- parameter remains but the trigger owns the saved result.
do $do$
declare
  v record;
  v_def text;
  v_new text;
begin
  for v in select * from (values
    ('public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure,'7409ba5fc9284b5aa81feadfe26b1123','begin' || chr(10),'begin' || chr(10) || '  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_planned_lesson_id);' || chr(10)),
    ('public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure,'e54ce485005b3f2e41e4c0c31813cd68','begin' || chr(10),'begin' || chr(10) || '  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_planned_lesson_id);' || chr(10)),
    ('public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure,'4b3af5a89c0409d934513a259dc29d94','BEGIN' || chr(10),'BEGIN' || chr(10) || '  PERFORM public.school_tuition_p0b1_lock_existing_lesson_scope(p_planned_lesson_id);' || chr(10)),
    ('public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure,'b80a6607c01d8c10ebef8ceb082192a2','begin' || chr(10),'begin' || chr(10) || '  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_planned_lesson_id);' || chr(10)),
    ('public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure,'607a6030f28fecdcefbeb94f23306d2e','BEGIN' || chr(10),'BEGIN' || chr(10) || '  PERFORM public.school_tuition_p0b1_lock_new_planned_scope(p_student_id,p_business_entity_id,p_lesson_date);' || chr(10)),
    ('public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean)'::regprocedure,'0de03bd89e606dfcdd3ab577ce6848e2','begin' || chr(10),'begin' || chr(10) || '  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_lesson_id);' || chr(10)),
    ('public.school_generate_planned_lessons_batch(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,'741a31ff98c9adf7720aab65afdb1cf5','BEGIN' || chr(10),'BEGIN' || chr(10) || '  PERFORM public.school_tuition_p0b1_lock_new_planned_range(p_student_id,p_business_entity_id,p_start_date,p_end_date);' || chr(10)),
    ('public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure,'9edf041a5cfa92a9262fcf5f2ecfb0ba','begin' || chr(10),'begin' || chr(10) || '  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_lesson_id,p_student_id,p_business_entity_id,p_lesson_date);' || chr(10)),
    ('public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure,'dca22a58c3efad550d87597385a143df','begin' || chr(10),'begin' || chr(10) || '  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_lesson_id,p_student_id,p_business_entity_id,p_lesson_date);' || chr(10)),
    ('public.school_void_planned_lesson(uuid,timestamp with time zone,text)'::regprocedure,'e499ec9b6a73a9c5bcfaabffcd399075','begin' || chr(10),'begin' || chr(10) || '  perform public.school_tuition_p0b1_lock_existing_lesson_scope(p_lesson_id);' || chr(10))
  ) x(proc,expected_hash,needle,replacement)
  loop
    v_def:=pg_get_functiondef(v.proc);
    if md5(v_def)<>v.expected_hash then
      raise exception 'P0B1_WRITER_HASH_MISMATCH: %',v.proc;
    end if;
    v_new:=replace(v_def,v.needle,v.replacement);
    if v_new=v_def or length(v_new)-length(v_def)<>length(v.replacement)-length(v.needle) then
      raise exception 'P0B1_WRITER_PATCH_MISMATCH: %',v.proc;
    end if;
    execute v_new;
  end loop;
end
$do$;

-- Fix every daily writer's execution context. Historical import/backfill and
-- R1D legacy cores stay owner-only.
do $do$
declare v_proc regprocedure;
begin
  foreach v_proc in array array[
    'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure,
    'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure,
    'public.school_create_cross_month_makeup_completed_actual_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure,
    'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure,
    'public.school_create_makeup_completed_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text)'::regprocedure,
    'public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure,
    'public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure,
    'public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,integer)'::regprocedure,
    'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text)'::regprocedure,
    'public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer)'::regprocedure,
    'public.school_delete_fresh_planned_lesson(uuid,timestamp with time zone,boolean)'::regprocedure,
    'public.school_generate_planned_lessons_batch(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,
    'public.school_generate_planned_lessons_batch_with_venue(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure,
    'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,integer)'::regprocedure,
    'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text)'::regprocedure,
    'public.school_update_lesson_record_guarded_with_venue(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text,text,text,integer)'::regprocedure,
    'public.school_void_planned_lesson(uuid,timestamp with time zone,text)'::regprocedure
  ] loop
    execute format('alter function %s security definer set search_path=pg_catalog,public',v_proc);
    execute format('revoke all on function %s from public,anon,authenticated,service_role',v_proc);
    execute format('grant execute on function %s to authenticated,service_role',v_proc);
  end loop;
end
$do$;

-- Preserve the previously public/anon daily subset explicitly without PUBLIC.
grant execute on function public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text) to anon;
grant execute on function public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text) to anon;
grant execute on function public.school_create_cross_month_makeup_completed_actual_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text) to anon;
grant execute on function public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text) to anon;
grant execute on function public.school_create_makeup_completed_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,boolean,integer,text,text) to anon;
grant execute on function public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text) to anon;
grant execute on function public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text) to anon;
grant execute on function public.school_create_planned_lesson_record(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,integer) to anon;
grant execute on function public.school_create_planned_lesson_record_with_venue(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text,text,text,integer) to anon;
grant execute on function public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text) to anon;
grant execute on function public.school_void_planned_lesson(uuid,timestamp with time zone,text) to anon;

-- Historical utilities are not reopened by this cutover.
revoke all on function public.school_import_lesson_records_batch(uuid,text,text,jsonb,text) from public,anon,authenticated,service_role;
revoke all on function public.school_import_lesson_records_batch_with_venue(uuid,text,text,jsonb,text) from public,anon,authenticated,service_role;
revoke all on function public.school_backfill_actual_minutes_from_duration(text) from public,anon,authenticated,service_role;

revoke all on function public.school_tuition_p0b1_lock_lesson_scopes(jsonb) from public,anon,authenticated,service_role;
revoke all on function public.school_tuition_p0b1_lock_new_planned_scope(uuid,uuid,date) from public,anon,authenticated,service_role;
revoke all on function public.school_tuition_p0b1_lock_new_planned_range(uuid,uuid,date,date) from public,anon,authenticated,service_role;
revoke all on function public.school_tuition_p0b1_lock_existing_lesson_scope(uuid,uuid,uuid,date) from public,anon,authenticated,service_role;
revoke all on function public.school_tuition_p0b1_lesson_financial_authority() from public,anon,authenticated,service_role;

revoke all on public.school_lesson_records from public,anon,authenticated,service_role;
grant select on public.school_lesson_records to anon,authenticated,service_role;

alter table public.school_lesson_records enable row level security;
drop policy if exists school_allow_all_lesson_records on public.school_lesson_records;
drop policy if exists school_lesson_records_select on public.school_lesson_records;
create policy school_lesson_records_select on public.school_lesson_records
for select to anon,authenticated,service_role using (true);

comment on function public.school_tuition_p0b1_lesson_financial_authority() is
  'P0-B1 sole persisted base lesson-fee authority and consumed financial-fact guard; historical no-op edits preserve old facts.';
comment on function public.school_tuition_p0b1_lock_lesson_scopes(jsonb) is
  'P0-B1 lesson writer lock helper: student_tuition_operation_v1 then lesson, settlement, carryover, draft, adjustment.';

commit;
