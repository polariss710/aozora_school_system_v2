-- =============================================================================
-- 回滚：工资 preflight 的 candidate_prerequisites 撤回 pay_hours / lesson_wage_jpy
--
-- 对应  school_wage_preflight_candidate_pay_facts_deploy_20260912.sql
--
-- 把 candidate_prerequisites 的 jsonb_build_object 恢复成 9 个键，
-- 并把 COMMENT 恢复为部署前原文。其余逐字不动。
--
-- ⚠️ 回滚前先确认前端已经不依赖这两个键：
--    勤务申报表的「无快照导出」分支读 pay_hours 渲染「结算课时」列。
--    先回滚本函数、后回滚前端的话，那一列会变空白而不是报错。
--    正确顺序：先撤前端（或先把缓存链键回退），再跑本脚本。
--
-- ⛔ 不改：函数签名、返回类型、volatility、SECURITY DEFINER、search_path、
--         owner、ACL、operator 守卫、candidate_facts 函数本身、
--         summary / teacher_previews / blockers 三段、业务数据。
--
-- 用法
--   psql -v ON_ERROR_STOP=1 -v mode=rehearsal -f <本文件>
--   psql -v ON_ERROR_STOP=1 -v mode=commit    -f <本文件>
-- =============================================================================
\set ON_ERROR_STOP on
SELECT (:'mode'='commit') AS is_commit, (:'mode'='rehearsal') AS is_rehearsal \gset
\if :is_commit
\echo '>>> mode=commit —— 通过全部断言后将 COMMIT'
\elif :is_rehearsal
\echo '>>> mode=rehearsal —— 通过全部断言后将 ROLLBACK'
\else
-- ⚠️ 不能用裸 \quit —— 它的退出码是 0，自动化会把「根本没执行」读成「成功」。
DO $mode$ BEGIN
  RAISE EXCEPTION 'WAGE_PREFLIGHT_MODE_INVALID: 必须指定 -v mode=rehearsal 或 -v mode=commit';
END $mode$;
\endif

BEGIN;

CREATE TEMP TABLE _wage_preflight_pre ON COMMIT DROP AS
SELECT
  p.oid,
  pg_catalog.pg_get_functiondef(p.oid)              AS def,
  COALESCE(p.proacl::text, '<null>')                AS acl,
  p.provolatile::text                               AS volatility,
  p.prosecdef                                       AS secdef,
  COALESCE(p.proconfig::text, '<null>')             AS cfg,
  p.proowner::regrole::text                         AS owner
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'school_get_teacher_monthly_wage_generation_preflight'
  AND p.oid = pg_catalog.to_regprocedure('public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)');

DO $pre$
DECLARE
  v_count int;
  v_def   text;
BEGIN
  SELECT count(*) INTO v_count FROM _wage_preflight_pre;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_TARGET_NOT_UNIQUE: 期望恰好 1 个 (text,uuid,uuid) 重载，实际 %', v_count;
  END IF;

  SELECT def INTO v_def FROM _wage_preflight_pre;

  -- 没打过补丁就没什么可回滚的；继续跑会把生产覆盖成本文件里的版本，危险
  IF v_def NOT LIKE '%''pay_hours'', pay_hours%' OR v_def NOT LIKE '%''lesson_wage_jpy'', lesson_wage_jpy%' THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_NOT_PATCHED: 当前定义不含待回滚的两个键，停止（不要用本脚本去覆盖未知版本）';
  END IF;

  IF v_def NOT LIKE '%school_require_current_app_operator()%' THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_GUARD_DRIFT: 未找到 operator 守卫，当前定义非预期版本';
  END IF;

  RAISE NOTICE 'pre 检查通过：目标函数唯一且确为已打补丁版本。';
END
$pre$;

-- -----------------------------------------------------------------------------
-- 恢复：candidate_prerequisites 回到 9 个键。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.school_get_teacher_monthly_wage_generation_preflight(p_year_month text, p_teacher_id uuid, p_business_entity_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $_$
declare
  v_result jsonb;
begin
  perform public.school_require_current_app_operator();
  if p_year_month is null or p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'WAGE_MONTH_INVALID';
  end if;
  if p_teacher_id is not null and not exists(
    select 1 from public.school_teachers t where t.id = p_teacher_id and t.app_type = 'school'
  ) then raise exception 'WAGE_TEACHER_INVALID'; end if;
  if p_business_entity_id is not null and not exists(
    select 1 from public.school_business_entities b where b.id = p_business_entity_id
  ) then raise exception 'WAGE_BUSINESS_ENTITY_INVALID'; end if;

  with candidates as materialized (
    select * from public.school_get_teacher_monthly_wage_generation_candidate_facts(
      p_year_month, p_teacher_id, p_business_entity_id
    )
  ), classified as (
    select c.*,
      case
        when not c.fact_complete then 'WAGE_LESSON_FACT_INCOMPLETE'
        when c.active_rule_count = 0 then 'WAGE_RULE_MISSING'
        when c.active_rule_count > 1 then 'WAGE_RULE_DUPLICATE'
        when not coalesce(c.effective_complete, false) then
          coalesce(c.settlement_blocker_code, 'WAGE_EFFECTIVE_SETTLEMENT_MISSING')
      end blocker_code,
      case
        when not c.fact_complete then 'Required teacher/student/subject/business entity/actual minutes are incomplete.'
        when c.active_rule_count = 0 then 'No unique active wage rule exists.'
        when c.active_rule_count > 1 then 'Multiple active wage rules match this lesson.'
        when not coalesce(c.effective_complete, false) then c.settlement_blocker_detail
      end blocker_detail
    from candidates c
  ), teacher_preview as (
    select teacher_id, max(teacher_name) teacher_name, business_entity_id,
      max(business_name) business_name, count(*)::integer lesson_count,
      sum(actual_minutes)::numeric total_minutes,
      count(*) filter(where is_no_wage)::integer no_wage_lesson_count,
      coalesce(sum(actual_minutes) filter(where is_no_wage),0)::numeric no_wage_minutes,
      coalesce(sum(pay_hours),0)::numeric pay_hours,
      coalesce(sum(lesson_wage_jpy),0)::numeric amount_jpy
    from classified
    where blocker_code is null
    group by teacher_id,business_entity_id
  ), candidate_prerequisites as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'lesson_record_id', lesson_record_id,
      'prerequisite_satisfied', blocker_code is null,
      'prerequisite_status', case
        when blocker_code is null then effective_status
        else coalesce(effective_status, blocker_code)
      end,
      'blocker_code', blocker_code,
      'blocker_detail', blocker_detail,
      'settlement_type', settlement_type,
      'is_no_wage', is_no_wage,
      'effective_source_type', effective_source_type,
      'effective_source_id', effective_source_id
    ) order by lesson_date,start_time,lesson_record_id), '[]'::jsonb) rows
    from classified
  ), blockers as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'blocker_code', blocker_code,
      'blocker_detail', blocker_detail,
      'lesson_record_id', lesson_record_id,
      'teacher_id', teacher_id,
      'student_id', student_id,
      'subject_id', subject_id,
      'business_entity_id', business_entity_id,
      'student_settlement_month', student_settlement_month,
      'active_rule_count', active_rule_count,
      'wage_rule_id', wage_rule_id,
      'settlement_type', settlement_type,
      'effective_status', effective_status,
      'effective_source_type', effective_source_type,
      'effective_source_id', effective_source_id
    ) order by blocker_code,student_name,lesson_record_id) filter(where blocker_code is not null), '[]'::jsonb) rows
    from classified
  )
  select jsonb_build_object(
    'year_month', p_year_month,
    'summary', jsonb_build_object(
      'candidate_actual_count', (select count(*) from classified),
      'candidate_teacher_count', (select count(distinct teacher_id) from classified),
      'total_minutes', coalesce((select sum(actual_minutes) from classified),0),
      'missing_rule_count', (select count(*) from classified where blocker_code='WAGE_RULE_MISSING'),
      'duplicate_rule_count', (select count(*) from classified where blocker_code='WAGE_RULE_DUPLICATE'),
      'incomplete_lesson_count', (select count(*) from classified where blocker_code='WAGE_LESSON_FACT_INCOMPLETE'),
      'no_wage_lesson_count', (select count(*) from classified where active_rule_count=1 and is_no_wage),
      'no_wage_minutes', coalesce((select sum(actual_minutes) from classified where active_rule_count=1 and is_no_wage),0),
      'student_settlement_blocker_count', (select count(*) from classified where blocker_code in ('WAGE_EFFECTIVE_SETTLEMENT_MISSING','WAGE_SETTLEMENT_BUSINESS_ENTITY_MISMATCH')),
      'student_settlement_blocker_group_count', (select count(*) from (select distinct student_id,student_settlement_month,business_entity_id from classified where blocker_code in ('WAGE_EFFECTIVE_SETTLEMENT_MISSING','WAGE_SETTLEMENT_BUSINESS_ENTITY_MISMATCH')) g),
      'blocker_count', (select count(*) from classified where blocker_code is not null),
      'active_wage_lock_count', (select count(*) from public.school_teacher_wage_locks w where w.settlement_month=p_year_month and w.status='locked' and w.voided_at is null and (p_teacher_id is null or w.teacher_id=p_teacher_id) and (p_business_entity_id is null or w.business_entity_id=p_business_entity_id)),
      'existing_wage_detail_count', (select count(*) from classified c where exists(select 1 from public.school_teacher_wage_lock_details d join public.school_teacher_wage_locks w on w.id=d.lock_id where d.lesson_record_id=c.lesson_record_id and w.status='locked' and w.voided_at is null)),
      'conditional_pay_hours', coalesce((select sum(pay_hours) from classified where blocker_code is null),0),
      'conditional_amount_jpy', coalesce((select sum(lesson_wage_jpy) from classified where blocker_code is null),0)
    ),
    'teacher_previews', coalesce((select jsonb_agg(to_jsonb(t) order by teacher_name,teacher_id) from teacher_preview t), '[]'::jsonb),
    'candidate_prerequisites', (select rows from candidate_prerequisites),
    'blockers', (select rows from blockers)
  ) into v_result;
  return v_result;
end
$_$;

-- COMMENT 恢复为部署前原文。
COMMENT ON FUNCTION public.school_get_teacher_monthly_wage_generation_preflight(p_year_month text, p_teacher_id uuid, p_business_entity_id uuid) IS
  'Read-only structured wage preflight shared with the writer. candidate_prerequisites exposes the same per-lesson effective/no_wage classification for UI display; no client-side qualification rule. Requires an active admin or operator membership.';

-- -----------------------------------------------------------------------------
-- post 段：两键已撤，且除此之外什么都没变。
-- -----------------------------------------------------------------------------
DO $post$
DECLARE
  v_pre  _wage_preflight_pre%rowtype;
  v_def  text;
  v_acl  text;
  v_vol  text;
  v_sec  boolean;
  v_cfg  text;
  v_own  text;
  v_oid  oid;
BEGIN
  SELECT * INTO v_pre FROM _wage_preflight_pre;

  SELECT p.oid,
         pg_catalog.pg_get_functiondef(p.oid),
         COALESCE(p.proacl::text, '<null>'),
         p.provolatile::text,
         p.prosecdef,
         COALESCE(p.proconfig::text, '<null>'),
         p.proowner::regrole::text
    INTO v_oid, v_def, v_acl, v_vol, v_sec, v_cfg, v_own
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'school_get_teacher_monthly_wage_generation_preflight'
    AND p.oid = pg_catalog.to_regprocedure('public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)');

  IF v_oid <> v_pre.oid THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_OID_CHANGED: 函数被重建而非替换，ACL 可能已丢失（pre=% post=%）', v_pre.oid, v_oid;
  END IF;

  IF v_def LIKE '%''pay_hours'', pay_hours%' OR v_def LIKE '%''lesson_wage_jpy'', lesson_wage_jpy%' THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_ROLLBACK_INCOMPLETE: 两键仍在 candidate_prerequisites 上';
  END IF;

  IF v_acl IS DISTINCT FROM v_pre.acl THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_ACL_CHANGED: pre=% post=%', v_pre.acl, v_acl;
  END IF;
  IF v_vol IS DISTINCT FROM v_pre.volatility THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_VOLATILITY_CHANGED: pre=% post=%', v_pre.volatility, v_vol;
  END IF;
  IF v_sec IS DISTINCT FROM v_pre.secdef THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_SECDEF_CHANGED: pre=% post=%', v_pre.secdef, v_sec;
  END IF;
  IF v_cfg IS DISTINCT FROM v_pre.cfg THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_SEARCHPATH_CHANGED: pre=% post=%', v_pre.cfg, v_cfg;
  END IF;
  IF v_own IS DISTINCT FROM v_pre.owner THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_OWNER_CHANGED: pre=% post=%', v_pre.owner, v_own;
  END IF;

  IF v_def NOT LIKE '%school_require_current_app_operator()%' THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_GUARD_LOST: operator 守卫丢失';
  END IF;

  -- 把 pre（已打补丁版）去掉两行后，应逐字等于回滚后的定义
  IF replace(
       replace(v_pre.def, E',\n      ''pay_hours'', pay_hours', ''),
       E',\n      ''lesson_wage_jpy'', lesson_wage_jpy', ''
     ) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_UNEXPECTED_DIFF: 回滚结果与「部署前定义」不逐字一致，请人工比对';
  END IF;

  RAISE NOTICE 'post 检查通过：两键已撤，其余逐字未变。';
END
$post$;

-- 冒烟：preflight 仍可调用，operator 守卫仍是第一道。
DO $smoke$
DECLARE
  v_json jsonb;
BEGIN
  BEGIN
    v_json := public.school_get_teacher_monthly_wage_generation_preflight('1900-01', null, null);
    IF v_json->'candidate_prerequisites' IS NULL THEN
      RAISE EXCEPTION 'WAGE_PREFLIGHT_SMOKE_FAILED: candidate_prerequisites 缺失';
    END IF;
    RAISE NOTICE '冒烟通过：带身份调用成功，候选 % 条。', jsonb_array_length(v_json->'candidate_prerequisites');
  EXCEPTION WHEN sqlstate '42501' THEN
    RAISE NOTICE '冒烟通过：无 JWT 直连被 operator 守卫拦下（%），符合预期。', SQLERRM;
  END;
END
$smoke$;

\if :is_commit
COMMIT;
\echo '>>> 已 COMMIT。'
\else
ROLLBACK;
\echo '>>> 已 ROLLBACK（rehearsal）。'
\endif
