\set ON_ERROR_STOP on

-- School V2 student settlement lesson-week close guard.
--
-- Purpose
-- -------
-- Student lesson attribution month is derived from the Monday of the lesson's
-- natural week:
--     to_char(date_trunc('week', lesson_date), 'YYYY-MM')
-- (see school_tuition_p0b1_lesson_authority_rpc_only_20260803.sql).
-- Therefore a month M is not complete when the calendar month M ends; it is
-- complete only after the last natural week whose Monday falls in M has ended.
--
-- Example: 2026-08-31 is a Monday, so lessons on 2026-08-31..2026-09-06 belong
-- to 2026-08. The previous calendar-month guard classified 2026-08 as `closed`
-- on 2026-09-01 and allowed save/lock while six days of August lessons had not
-- yet occurred. This file replaces the calendar-month rule with a lesson-week
-- rule so the close rule is symmetric with the attribution rule.
--
-- Business-model expansion declaration:
-- - new business tables/columns: none;
-- - new enum/status value: classification `lesson_week_open` and blocker code
--   `SETTLEMENT_LESSON_WEEK_NOT_CLOSED` (approved for this phase);
-- - changed semantics: save/lock mutability for student monthly settlement is
--   restricted to months whose last natural lesson week has ended, instead of
--   months strictly before the current Asia/Tokyo calendar month (approved);
-- - authoritative month remains the existing settlement YYYY-MM;
-- - sole authority for month write eligibility remains
--   school_get_student_settlement_month_write_eligibility_at_core;
-- - teacher wage settlement keeps its calendar-month rule and is untouched:
--   this guard is referenced only by student settlement writers;
-- - Preview and every amount/manifest/source-treatment formula are unchanged;
-- - no historical data is reinterpreted: `lesson_week_open` can only apply to
--   the immediately preceding month during the first days of a month, and
--   already-locked settlements fail earlier on their existing blockers.

begin;
set local lock_timeout = '8s';
set local statement_timeout = '120s';

-- Preflight: the five writers must still carry the month-write assert that the
-- 2026-08-10 guard injected. Those injections were applied by string-patching
-- live function definitions, so re-running any base file silently drops them.
-- If an injection is missing, replacing the eligibility core below would not
-- actually protect that path, so fail closed instead.
do $preflight$
declare
  v_name text;
  v_definition text;
begin
  foreach v_name in array array[
    'school_save_student_settlement_draft_local',
    'school_lock_student_monthly_settlement_local',
    'school_lock_student_monthly_settlement',
    'school_set_student_monthly_settlement_draft_adjustment',
    'school_set_student_settlement_source_treatment_draft'
  ] loop
    select pg_get_functiondef(p.oid) into strict v_definition
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = v_name;

    if position('school_assert_student_settlement_month_write_allowed'
                in v_definition) = 0 then
      raise exception
        'LESSON_WEEK_CLOSE_PREFLIGHT_WRITER_GUARD_MISSING: %', v_name;
    end if;
  end loop;

  -- The online eligibility core must still consult the eligibility core, and
  -- the online status core must still surface a distinct lock blocker message.
  select pg_get_functiondef(
           to_regprocedure(
             'public.school_get_student_settlement_online_save_eligibility_core(uuid,text)'
           )
         )
    into strict v_definition;
  if position('school_get_student_settlement_month_write_eligibility_core'
              in v_definition) = 0 then
    raise exception 'LESSON_WEEK_CLOSE_PREFLIGHT_ELIGIBILITY_GUARD_MISSING';
  end if;

  select pg_get_functiondef(
           to_regprocedure(
             'public.school_get_student_monthly_settlement_online_status_core(uuid,text)'
           )
         )
    into strict v_definition;
  if position('lock_blocker_message' in v_definition) = 0 then
    raise exception 'LESSON_WEEK_CLOSE_PREFLIGHT_STATUS_LOCK_MESSAGE_MISSING';
  end if;
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
  v_current_lesson_month date;
  v_classification text;
  v_code text;
  v_save_message text;
  v_lock_message text;
begin
  if p_reference_time is null
     or p_year_month is null
     or p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    return jsonb_build_object(
      'contract_version', 'student_settlement_lesson_week_close_v2',
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
      'contract_version', 'student_settlement_lesson_week_close_v2',
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
      'contract_version', 'student_settlement_lesson_week_close_v2',
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

  -- The lesson month currently being accumulated. date_trunc('week', ...) is
  -- ISO and returns the Monday, matching how lesson year_month is generated.
  -- v_current_lesson_month <= v_current_business_month always holds, so the
  -- new `lesson_week_open` branch can only fire during the first days of a
  -- calendar month and never reclassifies older months.
  v_current_lesson_month := date_trunc(
    'month',
    date_trunc('week', v_business_today::timestamp)
  )::date;

  if v_target_month > v_current_business_month then
    v_classification := 'future';
    v_code := 'SETTLEMENT_FUTURE_MONTH_NOT_ALLOWED';
    v_save_message := '不能保存未来月份的月结草稿。';
    v_lock_message := '不能锁定未来月份的月结。';
  elsif v_target_month = v_current_business_month then
    v_classification := 'current';
    v_code := 'SETTLEMENT_MONTH_NOT_CLOSED';
    v_save_message := '当前月份尚未结束，只能预览；进入下个月后才可保存月结草稿。';
    v_lock_message := '当前月份尚未结束，不能正式锁定月结。';
  elsif v_target_month >= v_current_lesson_month then
    v_classification := 'lesson_week_open';
    v_code := 'SETTLEMENT_LESSON_WEEK_NOT_CLOSED';
    v_save_message := '该月最后一个自然周尚未结束，只能预览；本周结束后才可保存月结草稿。';
    v_lock_message := '该月最后一个自然周尚未结束，不能正式锁定月结。';
  else
    v_classification := 'closed';
  end if;

  return jsonb_build_object(
    'contract_version', 'student_settlement_lesson_week_close_v2',
    'year_month', p_year_month,
    'target_month', v_target_month,
    'business_timezone', 'Asia/Tokyo',
    'business_today', v_business_today,
    'current_business_month', v_current_business_month,
    'current_lesson_month', v_current_lesson_month,
    'classification', v_classification,
    'write_allowed', v_classification = 'closed',
    'save_blocker_code', v_code,
    'save_blocker_message', v_save_message,
    'lock_blocker_code', v_code,
    'lock_blocker_message', v_lock_message
  );
end
$function$;

comment on function public.school_get_student_settlement_month_write_eligibility_at_core(
  text, timestamptz
) is
  'Sole authority for student monthly settlement month write eligibility. A '
  'month is writable only after the last natural lesson week whose Monday '
  'falls in that month has ended, mirroring lesson attribution '
  '(date_trunc(week)). Teacher wage settlement is not governed by this '
  'function and keeps its calendar-month rule.';

-- school_get_student_settlement_month_write_eligibility_core is unchanged: it
-- delegates to the _at_core above with transaction_timestamp(), so all five
-- patched writers and the online eligibility chain inherit the new rule
-- without any further definition patching.

alter function public.school_get_student_settlement_month_write_eligibility_at_core(
  text, timestamptz
) owner to postgres;

revoke all on function public.school_get_student_settlement_month_write_eligibility_at_core(
  text, timestamptz
) from public, anon, authenticated, service_role;

commit;
