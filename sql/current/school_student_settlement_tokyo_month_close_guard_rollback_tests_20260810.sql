\set ON_ERROR_STOP on

begin;
set local lock_timeout = '8s';
set local statement_timeout = '120s';
select set_config('request.jwt.claims', json_build_object('role','service_role')::text, true);

do $time_contract$
declare
  v jsonb;
  v_utc jsonb;
  v_tokyo jsonb;
  v_other jsonb;
begin
  v := public.school_get_student_settlement_month_write_eligibility_at_core(
    '2026-07', '2026-08-09 15:00:00+00'::timestamptz
  );
  if v->>'classification' <> 'closed' or (v->>'write_allowed')::boolean is not true then
    raise exception 'MONTH_CLOSE_PREVIOUS_MONTH_FAILED: %', v;
  end if;

  v := public.school_get_student_settlement_month_write_eligibility_at_core(
    '2026-08', '2026-08-09 15:00:00+00'::timestamptz
  );
  if v->>'classification' <> 'current'
     or v->>'save_blocker_code' <> 'SETTLEMENT_MONTH_NOT_CLOSED' then
    raise exception 'MONTH_CLOSE_CURRENT_MONTH_FAILED: %', v;
  end if;

  v := public.school_get_student_settlement_month_write_eligibility_at_core(
    '2026-09', '2026-08-09 15:00:00+00'::timestamptz
  );
  if v->>'classification' <> 'future'
     or v->>'save_blocker_code' <> 'SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED' then
    raise exception 'MONTH_CLOSE_NEXT_MONTH_FAILED: %', v;
  end if;

  v := public.school_get_student_settlement_month_write_eligibility_at_core(
    '2027-02', '2026-08-09 15:00:00+00'::timestamptz
  );
  if v->>'classification' <> 'future' then
    raise exception 'MONTH_CLOSE_FAR_FUTURE_FAILED: %', v;
  end if;

  foreach v in array array[
    public.school_get_student_settlement_month_write_eligibility_at_core('2026-8', now()),
    public.school_get_student_settlement_month_write_eligibility_at_core('2026-13', now()),
    public.school_get_student_settlement_month_write_eligibility_at_core('2026-08-01', now()),
    public.school_get_student_settlement_month_write_eligibility_at_core('0000-08', now())
  ] loop
    if v->>'classification' <> 'invalid'
       or v->>'save_blocker_code' <> 'SETTLEMENT_MONTH_INVALID' then
      raise exception 'MONTH_CLOSE_INVALID_MONTH_FAILED: %', v;
    end if;
  end loop;

  if (public.school_get_student_settlement_month_write_eligibility_at_core(
        '2026-08', '2026-08-31 14:59:59+00'::timestamptz
      )->>'classification') <> 'current'
     or (public.school_get_student_settlement_month_write_eligibility_at_core(
        '2026-08', '2026-08-31 15:00:00+00'::timestamptz
      )->>'classification') <> 'closed' then
    raise exception 'MONTH_CLOSE_TOKYO_BOUNDARY_FAILED';
  end if;

  if (public.school_get_student_settlement_month_write_eligibility_at_core(
        '2026-12', '2026-12-31 14:59:59+00'::timestamptz
      )->>'classification') <> 'current'
     or (public.school_get_student_settlement_month_write_eligibility_at_core(
        '2026-12', '2026-12-31 15:00:00+00'::timestamptz
      )->>'classification') <> 'closed'
     or (public.school_get_student_settlement_month_write_eligibility_at_core(
        '2027-01', '2026-12-31 15:00:00+00'::timestamptz
      )->>'classification') <> 'current' then
    raise exception 'MONTH_CLOSE_YEAR_BOUNDARY_FAILED';
  end if;

  if (public.school_get_student_settlement_month_write_eligibility_at_core(
        '2028-02', '2028-02-29 14:59:59+00'::timestamptz
      )->>'classification') <> 'current'
     or (public.school_get_student_settlement_month_write_eligibility_at_core(
        '2028-02', '2028-02-29 15:00:00+00'::timestamptz
      )->>'classification') <> 'closed' then
    raise exception 'MONTH_CLOSE_LEAP_YEAR_BOUNDARY_FAILED';
  end if;

  set local timezone to 'UTC';
  v_utc := public.school_get_student_settlement_month_write_eligibility_at_core(
    '2026-08', '2026-08-31 15:00:00+00'::timestamptz
  );
  set local timezone to 'Asia/Tokyo';
  v_tokyo := public.school_get_student_settlement_month_write_eligibility_at_core(
    '2026-08', '2026-08-31 15:00:00+00'::timestamptz
  );
  set local timezone to 'America/Los_Angeles';
  v_other := public.school_get_student_settlement_month_write_eligibility_at_core(
    '2026-08', '2026-08-31 15:00:00+00'::timestamptz
  );
  if v_utc is distinct from v_tokyo or v_utc is distinct from v_other then
    raise exception 'MONTH_CLOSE_SESSION_TIMEZONE_DRIFT';
  end if;
end
$time_contract$;

create temporary table month_close_before on commit drop as
select * from (
  select 'settlements' object_name,count(*) row_count,md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash from public.school_student_monthly_settlements x
  union all select 'adjustment_drafts',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_settlement_adjustment_drafts x
  union all select 'source_drafts',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_settlement_source_treatment_drafts x
  union all select 'historical_evidence',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_monthly_settlement_historical_completion_evidenc x
  union all select 'lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_lesson_records x
  union all select 'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_income_records x
  union all select 'bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bills x
  union all select 'revisions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_generation_revisions x
  union all select 'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_locks x
  union all select 'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_lock_details x
) fingerprint;

do $status_contract$
declare
  v jsonb;
begin
  v := public.school_get_student_monthly_settlement_online_status_core(
    'eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid, '2026-08'
  );
  if (v->>'can_save')::boolean is not false
     or (v->>'can_lock')::boolean is not false
     or v->>'save_blocker_code' <> 'SETTLEMENT_MONTH_NOT_CLOSED'
     or v->>'lock_blocker_code' <> 'SETTLEMENT_MONTH_NOT_CLOSED'
     or v->>'lock_blocker_message' <> '当前月份尚未结束，不能正式锁定月结。'
     or v->'authoritative_preview' is null then
    raise exception 'MONTH_CLOSE_CURRENT_STATUS_FAILED: %', v;
  end if;

  v := public.school_get_student_monthly_settlement_online_status_core(
    '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '2026-09'
  );
  if (v->>'can_save')::boolean is not false
     or (v->>'can_lock')::boolean is not false
     or v->>'save_blocker_code' <> 'SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED'
     or v->>'lock_blocker_code' <> 'SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED'
     or v->'authoritative_preview' is null then
    raise exception 'MONTH_CLOSE_FUTURE_STATUS_FAILED: %', v;
  end if;

  v := public.school_get_student_monthly_settlement_online_status_core(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2026-08'
  );
  if v->>'save_blocker_code' <> 'SETTLEMENT_SUCCESSOR_REVISION_BLOCKED' then
    raise exception 'MONTH_CLOSE_IMMUTABLE_PRIORITY_FAILED: %', v;
  end if;

  v := public.school_get_student_monthly_settlement_online_status_core(
    'a7b163a0-201e-4867-9b94-372343356a80'::uuid, '2026-06'
  );
  if v->>'save_blocker_code' <> 'SETTLEMENT_SCOPE_NOT_UNIQUE' then
    raise exception 'MONTH_CLOSE_SCOPE_PRIORITY_FAILED: %', v;
  end if;
end
$status_contract$;

do $writer_rejections$
declare
  v_actor uuid;
  v_student uuid;
  v_entity constant uuid := '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid;
  v_month text;
  v_code text;
  v_hash constant text := repeat('a',64);
  v_expected_confirmation text;
begin
  select m.user_id into strict v_actor
  from public.school_app_memberships m
  where m.is_active=true and m.role='admin'
  order by m.user_id limit 1;

  foreach v_month in array array['2026-08','2026-09'] loop
    v_student := case when v_month='2026-08'
      then 'eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid
      else '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid end;
    v_code := case when v_month='2026-08'
      then 'SETTLEMENT_MONTH_NOT_CLOSED'
      else 'SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED' end;

    begin
      perform public.school_save_student_monthly_settlement_draft_online_admin(
        v_actor,v_student,v_month,'separate_makeup_and_overage_v1',null,null,null,
        'carry_final_balance',null,'rollback month close test',null,
        v_hash,v_hash,0,0,0,0,0,0,0,null,null,null,null,gen_random_uuid()
      );
      raise exception 'ONLINE_SAVE_REJECTION_MISSING';
    exception when others then
      if position(v_code in sqlerrm)=0 then raise; end if;
    end;

    begin
      perform public.school_lock_student_monthly_settlement_online_admin(
        v_actor,v_student,v_month,
        '11111111-1111-4111-8111-111111111111'::uuid,'2026-08-10 00:00:00+09'::timestamptz,
        '22222222-2222-4222-8222-222222222222'::uuid,'2026-08-10 00:00:00+09'::timestamptz,
        v_hash,v_hash,0,0,0,0,0,0,0,
        'rollback month close test',gen_random_uuid()
      );
      raise exception 'ONLINE_LOCK_REJECTION_MISSING';
    exception when others then
      if position(v_code in sqlerrm)=0 then raise; end if;
    end;

    v_expected_confirmation := format(
      'SAVE STUDENT SETTLEMENT DRAFT %s %s MANIFEST %s',v_student,v_month,v_hash
    );
    begin
      perform public.school_save_student_settlement_draft_local(
        v_student,v_entity,v_month,'separate_makeup_and_overage_v1',null,null,null,
        'carry_final_balance',null,v_hash,v_hash,0,0,0,0,0,0,0,
        'rollback month close test',null,'local_trusted_business_owner_v1',
        v_expected_confirmation
      );
      raise exception 'LOCAL_SAVE_REJECTION_MISSING';
    exception when others then
      if position(v_code in sqlerrm)=0 then raise; end if;
    end;

    v_expected_confirmation := format(
      'LOCK STUDENT SETTLEMENT %s %s MANIFEST %s CARRY %s',
      v_student,v_month,v_hash,0
    );
    begin
      perform public.school_lock_student_monthly_settlement_local(
        v_student,v_entity,v_month,'separate_makeup_and_overage_v1',null,null,null,
        'carry_final_balance',null,v_hash,v_hash,0,0,0,0,0,0,0,
        null,null,null,null,'rollback month close test',
        'local_trusted_business_owner_v1',v_expected_confirmation
      );
      raise exception 'LOCAL_LOCK_REJECTION_MISSING';
    exception when others then
      if position(v_code in sqlerrm)=0 then raise; end if;
    end;

    begin
      perform public.school_set_student_settlement_source_treatment_draft(
        v_student,v_month,'separate_makeup_and_overage_v1',null,null,null,
        'rollback month close test'
      );
      raise exception 'SOURCE_CORE_REJECTION_MISSING';
    exception when others then
      if position(v_code in sqlerrm)=0 then raise; end if;
    end;

    begin
      perform public.school_set_student_monthly_settlement_draft_adjustment(
        v_student,v_month,null,'carry_final_balance','rollback month close test',null
      );
      raise exception 'ADJUSTMENT_CORE_REJECTION_MISSING';
    exception when others then
      if position(v_code in sqlerrm)=0 then raise; end if;
    end;

    begin
      perform public.school_lock_student_monthly_settlement(
        v_student,v_month,'rollback month close test'
      );
      raise exception 'LOCK_CORE_REJECTION_MISSING';
    exception when others then
      if position(v_code in sqlerrm)=0 then raise; end if;
    end;
  end loop;
end
$writer_rejections$;

do $no_business_drift$
declare
  v record;
begin
  for v in
    select before.object_name,before.row_count,before.row_hash,
      after.row_count after_count,after.row_hash after_hash
    from month_close_before before
    join (
      select 'settlements' object_name,count(*) row_count,md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash from public.school_student_monthly_settlements x
      union all select 'adjustment_drafts',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_settlement_adjustment_drafts x
      union all select 'source_drafts',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_settlement_source_treatment_drafts x
      union all select 'historical_evidence',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_monthly_settlement_historical_completion_evidenc x
      union all select 'lessons',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_lesson_records x
      union all select 'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_income_records x
      union all select 'bills',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_bills x
      union all select 'revisions',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_student_tuition_generation_revisions x
      union all select 'wage_locks',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_locks x
      union all select 'wage_details',count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) from public.school_teacher_wage_lock_details x
    ) after using(object_name)
  loop
    if v.row_count is distinct from v.after_count or v.row_hash is distinct from v.after_hash then
      raise exception 'MONTH_CLOSE_ROLLBACK_BUSINESS_DRIFT: %',v.object_name;
    end if;
  end loop;
end
$no_business_drift$;

select 'SETTLEMENT_TOKYO_MONTH_CLOSE_ROLLBACK_PASS' result;
rollback;
