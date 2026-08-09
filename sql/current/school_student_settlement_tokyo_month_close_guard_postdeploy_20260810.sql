\set ON_ERROR_STOP on

begin transaction read only;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

do $assert_contract$
declare
  v_name text;
  v_definition text;
  v_current date := date_trunc('month', transaction_timestamp() at time zone 'Asia/Tokyo')::date;
begin
  if v_current <> '2026-08-01'::date then
    raise exception 'MONTH_CLOSE_POSTDEPLOY_UNEXPECTED_BUSINESS_MONTH: %',v_current;
  end if;

  foreach v_name in array array[
    'school_get_student_settlement_online_save_eligibility_core',
    'school_get_student_monthly_settlement_online_status_core',
    'school_save_student_settlement_draft_local',
    'school_lock_student_monthly_settlement_local',
    'school_lock_student_monthly_settlement',
    'school_set_student_monthly_settlement_draft_adjustment',
    'school_set_student_settlement_source_treatment_draft'
  ] loop
    select pg_get_functiondef(p.oid) into strict v_definition
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=v_name;
    if position('school_assert_student_settlement_month_write_allowed' in v_definition)=0
       and v_name not in (
         'school_get_student_settlement_online_save_eligibility_core',
         'school_get_student_monthly_settlement_online_status_core'
       ) then
      raise exception 'MONTH_CLOSE_POSTDEPLOY_WRITER_GUARD_MISSING: %',v_name;
    end if;
    if v_name='school_get_student_settlement_online_save_eligibility_core'
       and position('school_get_student_settlement_month_write_eligibility_core' in v_definition)=0 then
      raise exception 'MONTH_CLOSE_POSTDEPLOY_ELIGIBILITY_GUARD_MISSING';
    end if;
    if v_name='school_get_student_monthly_settlement_online_status_core'
       and position('lock_blocker_message' in v_definition)=0 then
      raise exception 'MONTH_CLOSE_POSTDEPLOY_STATUS_LOCK_MESSAGE_MISSING';
    end if;
  end loop;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in (
        'school_get_student_settlement_month_write_eligibility_at_core',
        'school_get_student_settlement_month_write_eligibility_core',
        'school_assert_student_settlement_month_write_allowed'
      ) and (
        p.proowner <> 'postgres'::regrole
        or not p.prosecdef
        or p.proconfig is distinct from array['search_path=pg_catalog, public']::text[]
        or has_function_privilege('public',p.oid,'EXECUTE')
        or has_function_privilege('anon',p.oid,'EXECUTE')
        or has_function_privilege('authenticated',p.oid,'EXECUTE')
        or has_function_privilege('service_role',p.oid,'EXECUTE')
      )
  ) then
    raise exception 'MONTH_CLOSE_POSTDEPLOY_HELPER_SECURITY_DRIFT';
  end if;
end
$assert_contract$;

do $assert_status$
declare
  v jsonb;
begin
  v := public.school_get_student_monthly_settlement_online_status_core(
    'eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'2026-08'
  );
  if (v->>'can_save')::boolean or (v->>'can_lock')::boolean
     or v->>'save_blocker_code'<>'SETTLEMENT_MONTH_NOT_CLOSED'
     or v->'authoritative_preview' is null then
    raise exception 'MONTH_CLOSE_POSTDEPLOY_CURRENT_STATUS_FAILED: %',v;
  end if;

  v := public.school_get_student_monthly_settlement_online_status_core(
    '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'2026-09'
  );
  if (v->>'can_save')::boolean or (v->>'can_lock')::boolean
     or v->>'save_blocker_code'<>'SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED'
     or v->'authoritative_preview' is null then
    raise exception 'MONTH_CLOSE_POSTDEPLOY_FUTURE_STATUS_FAILED: %',v;
  end if;

  v := public.school_get_student_monthly_settlement_online_status_core(
    'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2026-08'
  );
  if v->>'save_blocker_code'<>'SETTLEMENT_SUCCESSOR_REVISION_BLOCKED' then
    raise exception 'MONTH_CLOSE_POSTDEPLOY_PRIORITY_FAILED: %',v;
  end if;
end
$assert_status$;

do $assert_data$
begin
  if exists (
    select 1 from public.school_student_settlement_source_treatment_drafts
    where status='active' and to_date(year_month||'-01','YYYY-MM-DD') >= '2026-08-01'::date
  ) or exists (
    select 1 from public.school_student_settlement_adjustment_drafts
    where status='active' and to_date(year_month||'-01','YYYY-MM-DD') >= '2026-08-01'::date
  ) or exists (
    select 1 from public.school_student_monthly_settlements
    where settlement_status='locked' and to_date(year_month||'-01','YYYY-MM-DD') >= '2026-08-01'::date
  ) or exists (
    select 1 from public.school_student_monthly_settlement_historical_completion_evidenc
    where to_date(settlement_month||'-01','YYYY-MM-DD') >= '2026-08-01'::date
  ) then
    raise exception 'MONTH_CLOSE_POSTDEPLOY_CURRENT_OR_FUTURE_BUSINESS_FACT_FOUND';
  end if;

  if (select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))) from public.school_student_monthly_settlements x)
       <> jsonb_build_array(18,'481ffa7ed5173da852f0f28ce66c2e9b')
     or (select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))) from public.school_student_settlement_adjustment_drafts x)
       <> jsonb_build_array(7,'0b162413935ed3a35920d144faffbc52')
     or (select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))) from public.school_student_settlement_source_treatment_drafts x)
       <> jsonb_build_array(1,'c2a01866c1bfe9edd5eb559d6faf4a67')
     or (select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))) from public.school_student_monthly_settlement_historical_completion_evidenc x)
       <> jsonb_build_array(4,'9cb22ef4ddd83f7a77c8fcd2e3ab3966')
     or (select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))) from public.school_lesson_records x)
       <> jsonb_build_array(744,'3cd0c2ce1b7baa60c779c257c38e9f50')
     or (select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))) from public.school_income_records x)
       <> jsonb_build_array(55,'c55f82c7d62dbe92d0b49714a911a234') then
    raise exception 'MONTH_CLOSE_POSTDEPLOY_BUSINESS_FINGERPRINT_DRIFT';
  end if;

  if (select jsonb_object_agg(feature_key,state order by feature_key)
      from public.school_feature_gates where feature_key like 'student_tuition_%')
     <> '{"student_tuition_cash_submit":"enabled","student_tuition_generate":"blocked","student_tuition_preview":"enabled"}'::jsonb then
    raise exception 'MONTH_CLOSE_POSTDEPLOY_GATE_DRIFT';
  end if;
end
$assert_data$;

select p.oid::regprocedure signature,r.rolname owner,p.prosecdef,p.proconfig,
  has_function_privilege('public',p.oid,'EXECUTE') public_exec,
  has_function_privilege('anon',p.oid,'EXECUTE') anon_exec,
  has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_exec,
  has_function_privilege('service_role',p.oid,'EXECUTE') service_role_exec,
  md5(pg_get_functiondef(p.oid)) definition_md5
from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_roles r on r.oid=p.proowner
where n.nspname='public' and p.proname in (
  'school_get_student_settlement_month_write_eligibility_at_core',
  'school_get_student_settlement_month_write_eligibility_core',
  'school_assert_student_settlement_month_write_allowed',
  'school_get_student_settlement_online_save_eligibility_core',
  'school_get_student_monthly_settlement_online_status_core',
  'school_save_student_settlement_draft_local',
  'school_lock_student_monthly_settlement_local',
  'school_lock_student_monthly_settlement',
  'school_set_student_monthly_settlement_draft_adjustment',
  'school_set_student_settlement_source_treatment_draft'
) order by p.proname,pg_get_function_identity_arguments(p.oid);

select feature_key,state from public.school_feature_gates
where feature_key like 'student_tuition_%' order by feature_key;

commit;
select 'SETTLEMENT_TOKYO_MONTH_CLOSE_POSTDEPLOY_PASS' result;
