\set ON_ERROR_STOP on

-- School V2 student settlement Tokyo natural-month close guard.
-- Business-model expansion declaration:
-- - new business tables/columns/enums/manual gates: none;
-- - authoritative month remains the existing settlement YYYY-MM;
-- - save/lock mutability is restricted to months strictly before the current
--   Asia/Tokyo natural month, as explicitly approved for this phase;
-- - Preview and every amount/manifest/source-treatment formula are unchanged.

begin;
set local lock_timeout = '8s';
set local statement_timeout = '120s';

do $preflight$
declare
  v_expected record;
  v_actual text;
begin
  for v_expected in
    select * from (values
      ('public.school_get_student_settlement_online_save_eligibility_core(uuid,text)', 'c19f796538866f5acdc88193548ebb38'),
      ('public.school_get_student_monthly_settlement_online_status_core(uuid,text)', '68f10d78bef77da0b260196aaf64274c'),
      ('public.school_save_student_settlement_draft_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,text)', '5296dbdc64dbe2f36ccae242c5740a1c'),
      ('public.school_lock_student_monthly_settlement_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,text,text,text)', 'd9e07d2f330f34637fafb570743a5a59'),
      ('public.school_lock_student_monthly_settlement(uuid,text,text)', 'f9d85d62be938c5c92b2feb047616c3c'),
      ('public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)', '9b68480b55736c0602b28f637dcdc7a1'),
      ('public.school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text)', '5982596c31fa6cbf6c99df0cc5bee732')
    ) expected(signature, definition_md5)
  loop
    if to_regprocedure(v_expected.signature) is null then
      raise exception 'SETTLEMENT_MONTH_CLOSE_DEPENDENCY_MISSING: %', v_expected.signature;
    end if;
    select md5(pg_get_functiondef(to_regprocedure(v_expected.signature))) into v_actual;
    if v_actual is distinct from v_expected.definition_md5 then
      raise exception 'SETTLEMENT_MONTH_CLOSE_DEFINITION_DRIFT: % expected %, actual %',
        v_expected.signature, v_expected.definition_md5, v_actual;
    end if;
  end loop;
end
$preflight$;

create or replace function public.school_get_student_settlement_month_write_eligibility_at_core(
  p_year_month text,
  p_reference_time timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_target_month date;
  v_business_today date;
  v_current_business_month date;
  v_classification text;
  v_code text;
  v_save_message text;
  v_lock_message text;
begin
  if p_reference_time is null
     or p_year_month is null
     or p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    return jsonb_build_object(
      'contract_version', 'student_settlement_tokyo_month_close_v1',
      'year_month', p_year_month,
      'business_timezone', 'Asia/Tokyo',
      'classification', 'invalid',
      'write_allowed', false,
      'save_blocker_code', 'SETTLEMENT_MONTH_INVALID',
      'save_blocker_message', '结算月份格式无效，不能保存月结草稿。',
      'lock_blocker_code', 'SETTLEMENT_MONTH_INVALID',
      'lock_blocker_message', '结算月份格式无效，不能正式锁定月结。'
    );
  end if;

  begin
    v_target_month := make_date(
      substring(p_year_month from 1 for 4)::integer,
      substring(p_year_month from 6 for 2)::integer,
      1
    );
  exception when others then
    return jsonb_build_object(
      'contract_version', 'student_settlement_tokyo_month_close_v1',
      'year_month', p_year_month,
      'business_timezone', 'Asia/Tokyo',
      'classification', 'invalid',
      'write_allowed', false,
      'save_blocker_code', 'SETTLEMENT_MONTH_INVALID',
      'save_blocker_message', '结算月份格式无效，不能保存月结草稿。',
      'lock_blocker_code', 'SETTLEMENT_MONTH_INVALID',
      'lock_blocker_message', '结算月份格式无效，不能正式锁定月结。'
    );
  end;

  if to_char(v_target_month, 'YYYY-MM') is distinct from p_year_month then
    return jsonb_build_object(
      'contract_version', 'student_settlement_tokyo_month_close_v1',
      'year_month', p_year_month,
      'business_timezone', 'Asia/Tokyo',
      'classification', 'invalid',
      'write_allowed', false,
      'save_blocker_code', 'SETTLEMENT_MONTH_INVALID',
      'save_blocker_message', '结算月份格式无效，不能保存月结草稿。',
      'lock_blocker_code', 'SETTLEMENT_MONTH_INVALID',
      'lock_blocker_message', '结算月份格式无效，不能正式锁定月结。'
    );
  end if;

  v_business_today := (p_reference_time at time zone 'Asia/Tokyo')::date;
  v_current_business_month := date_trunc('month', v_business_today)::date;

  if v_target_month < v_current_business_month then
    v_classification := 'closed';
  elsif v_target_month = v_current_business_month then
    v_classification := 'current';
    v_code := 'SETTLEMENT_MONTH_NOT_CLOSED';
    v_save_message := '当前月份尚未结束，只能预览；进入下个月后才可保存月结草稿。';
    v_lock_message := '当前月份尚未结束，不能正式锁定月结。';
  else
    v_classification := 'future';
    v_code := 'SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED';
    v_save_message := '不能保存未来月份的月结草稿。';
    v_lock_message := '不能锁定未来月份的月结。';
  end if;

  return jsonb_build_object(
    'contract_version', 'student_settlement_tokyo_month_close_v1',
    'year_month', p_year_month,
    'target_month', v_target_month,
    'business_timezone', 'Asia/Tokyo',
    'business_today', v_business_today,
    'current_business_month', v_current_business_month,
    'classification', v_classification,
    'write_allowed', v_classification = 'closed',
    'save_blocker_code', v_code,
    'save_blocker_message', v_save_message,
    'lock_blocker_code', v_code,
    'lock_blocker_message', v_lock_message
  );
end
$function$;

create or replace function public.school_get_student_settlement_month_write_eligibility_core(
  p_year_month text
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select public.school_get_student_settlement_month_write_eligibility_at_core(
    p_year_month,
    transaction_timestamp()
  );
$function$;

create or replace function public.school_assert_student_settlement_month_write_allowed(
  p_year_month text,
  p_action text
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_eligibility jsonb;
  v_code text;
begin
  v_eligibility := public.school_get_student_settlement_month_write_eligibility_core(
    p_year_month
  );
  if coalesce((v_eligibility->>'write_allowed')::boolean, false) then
    return;
  end if;
  v_code := case when p_action = 'lock'
    then v_eligibility->>'lock_blocker_code'
    else v_eligibility->>'save_blocker_code'
  end;
  raise exception using errcode = 'P0001',
    message = coalesce(nullif(v_code, ''), 'SETTLEMENT_MONTH_INVALID');
end
$function$;

revoke all on function public.school_get_student_settlement_month_write_eligibility_at_core(
  text, timestamptz
) from public, anon, authenticated, service_role;
revoke all on function public.school_get_student_settlement_month_write_eligibility_core(
  text
) from public, anon, authenticated, service_role;
revoke all on function public.school_assert_student_settlement_month_write_allowed(
  text, text
) from public, anon, authenticated, service_role;

do $patch_eligibility$
declare
  v_oid regprocedure :=
    'public.school_get_student_settlement_online_save_eligibility_core(uuid,text)'::regprocedure;
  v_definition text := pg_get_functiondef(v_oid);
  v_old_declare text := $old$  v_cross_entity_canonical_bill boolean := false;
begin$old$;
  v_new_declare text := $new$  v_cross_entity_canonical_bill boolean := false;
  v_month_eligibility jsonb;
begin$new$;
  v_old_block text := $old$  if v_blocker_code is null and not v_source_facts_available then
    v_blocker_code := 'SETTLEMENT_SOURCE_FACTS_EMPTY';
    v_blocker_message := '该月份没有可用于月结的课时或收款来源，不能保存草稿。';
  end if;$old$;
  v_new_block text := $new$  if v_blocker_code is null then
    v_month_eligibility := public.school_get_student_settlement_month_write_eligibility_core(
      p_year_month
    );
    if not coalesce((v_month_eligibility->>'write_allowed')::boolean, false) then
      v_blocker_code := coalesce(
        nullif(v_month_eligibility->>'save_blocker_code', ''),
        'SETTLEMENT_MONTH_INVALID'
      );
      v_blocker_message := v_month_eligibility->>'save_blocker_message';
    end if;
  end if;

  if v_blocker_code is null and not v_source_facts_available then
    v_blocker_code := 'SETTLEMENT_SOURCE_FACTS_EMPTY';
    v_blocker_message := '该月份没有可用于月结的课时或收款来源，不能保存草稿。';
  end if;$new$;
  v_old_return text := $old$    'source_facts_available', v_source_facts_available,
    'can_save', v_blocker_code is null,$old$;
  v_new_return text := $new$    'source_facts_available', v_source_facts_available,
    'month_write_eligibility', v_month_eligibility,
    'lock_blocker_message', case when v_month_eligibility is null then null
      else v_month_eligibility->>'lock_blocker_message' end,
    'can_save', v_blocker_code is null,$new$;
begin
  if position(v_old_declare in v_definition) = 0
     or position(v_old_block in v_definition) = 0
     or position(v_old_return in v_definition) = 0 then
    raise exception 'SETTLEMENT_MONTH_CLOSE_ELIGIBILITY_PATCH_SHAPE_MISMATCH';
  end if;
  v_definition := replace(v_definition, v_old_declare, v_new_declare);
  v_definition := replace(v_definition, v_old_block, v_new_block);
  v_definition := replace(v_definition, v_old_return, v_new_return);
  execute v_definition;
end
$patch_eligibility$;

do $patch_status_lock_message$
declare
  v_oid regprocedure :=
    'public.school_get_student_monthly_settlement_online_status_core(uuid,text)'::regprocedure;
  v_definition text := pg_get_functiondef(v_oid);
  v_old text := $old$    v_lock_blocker_code := v_blocker_code;
    v_lock_blocker_message := v_blocker_message;$old$;
  v_new text := $new$    v_lock_blocker_code := v_blocker_code;
    v_lock_blocker_message := coalesce(
      nullif(v_eligibility->>'lock_blocker_message', ''),
      v_blocker_message
    );$new$;
begin
  if position(v_old in v_definition) = 0 then
    raise exception 'SETTLEMENT_MONTH_CLOSE_STATUS_PATCH_SHAPE_MISMATCH';
  end if;
  execute replace(v_definition, v_old, v_new);
end
$patch_status_lock_message$;

do $patch_core_writers$
declare
  v_oid regprocedure;
  v_definition text;
  v_old text;
  v_new text;
begin
  v_oid := 'public.school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text)'::regprocedure;
  v_definition := pg_get_functiondef(v_oid);
  v_old := '  perform public.school_assert_tuition_settlement_month_mutable(p_student_id,p_year_month);';
  v_new := v_old || E'\n  perform public.school_assert_student_settlement_month_write_allowed(\n    p_year_month, ''save_draft''\n  );';
  if position(v_old in v_definition) = 0 then
    raise exception 'SETTLEMENT_MONTH_CLOSE_SOURCE_CORE_PATCH_SHAPE_MISMATCH';
  end if;
  execute replace(v_definition, v_old, v_new);

  v_oid := 'public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)'::regprocedure;
  v_definition := pg_get_functiondef(v_oid);
  v_old := E'  perform public.school_assert_tuition_settlement_month_mutable(\n    p_student_id, v_year_month\n  );';
  v_new := v_old || E'\n  perform public.school_assert_student_settlement_month_write_allowed(\n    v_year_month, ''save_draft''\n  );';
  if position(v_old in v_definition) = 0 then
    raise exception 'SETTLEMENT_MONTH_CLOSE_ADJUSTMENT_CORE_PATCH_SHAPE_MISMATCH';
  end if;
  execute replace(v_definition, v_old, v_new);

  v_oid := 'public.school_lock_student_monthly_settlement(uuid,text,text)'::regprocedure;
  v_definition := pg_get_functiondef(v_oid);
  v_old := E'  perform public.school_assert_tuition_settlement_month_mutable(\n    p_student_id, v_year_month\n  );';
  v_new := v_old || E'\n  perform public.school_assert_student_settlement_month_write_allowed(\n    v_year_month, ''lock''\n  );';
  if position(v_old in v_definition) = 0 then
    raise exception 'SETTLEMENT_MONTH_CLOSE_LOCK_CORE_PATCH_SHAPE_MISMATCH';
  end if;
  execute replace(v_definition, v_old, v_new);
end
$patch_core_writers$;

do $patch_local_wrappers$
declare
  v_oid regprocedure;
  v_definition text;
  v_old text;
  v_new text;
begin
  v_oid := 'public.school_save_student_settlement_draft_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,text)'::regprocedure;
  v_definition := pg_get_functiondef(v_oid);
  v_old := E'  perform public.school_tuition_p0a_lock_settlement_mutation_scope(\n    p_student_id, p_business_entity_id, p_year_month\n  );\n\n  v_preview :=';
  v_new := E'  perform public.school_tuition_p0a_lock_settlement_mutation_scope(\n    p_student_id, p_business_entity_id, p_year_month\n  );\n  perform public.school_assert_tuition_settlement_month_mutable(\n    p_student_id, p_year_month\n  );\n  perform public.school_assert_student_settlement_month_write_allowed(\n    p_year_month, ''save_draft''\n  );\n\n  v_preview :=';
  if position(v_old in v_definition) = 0 then
    raise exception 'SETTLEMENT_MONTH_CLOSE_LOCAL_SAVE_PATCH_SHAPE_MISMATCH';
  end if;
  execute replace(v_definition, v_old, v_new);

  v_oid := 'public.school_lock_student_monthly_settlement_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,text,text,text)'::regprocedure;
  v_definition := pg_get_functiondef(v_oid);
  v_old := E'  end if;\n\n  select * into v_settlement\n  from public.school_student_monthly_settlements s';
  v_new := E'  end if;\n  perform public.school_assert_tuition_settlement_month_mutable(\n    p_student_id, p_year_month\n  );\n  perform public.school_assert_student_settlement_month_write_allowed(\n    p_year_month, ''lock''\n  );\n\n  select * into v_settlement\n  from public.school_student_monthly_settlements s';
  if position(v_old in v_definition) = 0 then
    raise exception 'SETTLEMENT_MONTH_CLOSE_LOCAL_LOCK_PATCH_SHAPE_MISMATCH';
  end if;
  execute replace(v_definition, v_old, v_new);
end
$patch_local_wrappers$;

alter function public.school_get_student_settlement_month_write_eligibility_at_core(text,timestamptz) owner to postgres;
alter function public.school_get_student_settlement_month_write_eligibility_core(text) owner to postgres;
alter function public.school_assert_student_settlement_month_write_allowed(text,text) owner to postgres;
alter function public.school_get_student_settlement_online_save_eligibility_core(uuid,text) owner to postgres;
alter function public.school_get_student_monthly_settlement_online_status_core(uuid,text) owner to postgres;
alter function public.school_save_student_settlement_draft_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,text,text,text,text) owner to postgres;
alter function public.school_lock_student_monthly_settlement_local(uuid,uuid,text,text,numeric,text,date,text,numeric,text,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,uuid,timestamptz,uuid,timestamptz,text,text,text) owner to postgres;
alter function public.school_lock_student_monthly_settlement(uuid,text,text) owner to postgres;
alter function public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text) owner to postgres;
alter function public.school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text) owner to postgres;

revoke all on function public.school_get_student_settlement_online_save_eligibility_core(uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.school_get_student_monthly_settlement_online_status_core(uuid,text) from public,anon,authenticated,service_role;
revoke all on function public.school_lock_student_monthly_settlement(uuid,text,text) from public,anon,authenticated,service_role;
revoke all on function public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text) from public,anon,authenticated,service_role;
revoke all on function public.school_set_student_settlement_source_treatment_draft(uuid,text,text,numeric,text,date,text) from public,anon,authenticated,service_role;

comment on function public.school_get_student_settlement_month_write_eligibility_at_core(text,timestamptz) is
  'Owner-only deterministic classifier used for Tokyo boundary tests. Production writers never accept a caller clock and use the transaction-time wrapper instead.';
comment on function public.school_get_student_settlement_month_write_eligibility_core(text) is
  'Owner-only single authority for student-settlement month write eligibility. Uses transaction_timestamp converted explicitly to Asia/Tokyo; only months strictly before the current Tokyo natural month may save or lock.';
comment on function public.school_assert_student_settlement_month_write_allowed(text,text) is
  'Owner-only shared assertion for online/local/core student-settlement save and normal lock paths. Raises stable current/future month blocker codes before business-row writes; Preview remains read-only and available.';

\if :{?MONTH_CLOSE_REHEARSAL}
rollback;
\elif :{?MONTH_CLOSE_HOLD}
\echo 'SETTLEMENT_TOKYO_MONTH_CLOSE_MIGRATION_HELD_FOR_ROLLBACK_TESTS'
\else
commit;
\endif
