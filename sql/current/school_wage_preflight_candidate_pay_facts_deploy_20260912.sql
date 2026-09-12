-- =============================================================================
-- 工资 preflight：candidate_prerequisites 增吐 pay_hours / lesson_wage_jpy
--
-- 背景  勤务申报表（讲师填写用）现在只能在【工资快照生成后】导出，
--       因为 handleBatchDutyReportExport 按 lock.id 取明细。
--       业务负责人 2026-09-12 定：勤务表确认的是【课时】，金额仅供参考，
--       且生成时交通费尚未填写 —— 它本来就不承载最终金额。
--       ⇒ 应当在快照之前也能导出，让老师先核对课时，再锁结算、生成快照。
--
-- 卡点  前端拿不到每节课的「结算课时」。
--       · js/api/wage-api.js 的 fetchWageCandidateLessons【不调】
--         school_get_teacher_monthly_wage_generation_candidate_facts，
--         而是直查 school_lesson_records + 调本 preflight 合并。
--         直查取的列里没有 pay_hours / lesson_wage_jpy。
--       · candidate_facts 函数本身 REVOKE ALL FROM PUBLIC、无 GRANT，
--         前端不可调用。（这正是 wage-api 绕开它的原因。）
--       ⇒ 若在 JS 里用 actual_minutes/60 兜底，就要连 no_wage 归零、
--         规则缺失置 null 一起抄进前端 —— 违反 P0：前端不得计算业务事实。
--
-- 本脚本  只做一件事：把 classified 里【已经算好】的两个值，
--         往 candidate_prerequisites 的每条记录上多吐一份。
--           'pay_hours'       ← classified.pay_hours
--           'lesson_wage_jpy' ← classified.lesson_wage_jpy
--
--   这两个值本函数【早已在用】：summary.conditional_pay_hours 与
--   summary.conditional_amount_jpy 就是它们的聚合，teacher_previews 亦然。
--   本次不新增业务事实、不改权威来源、不改任何字段语义，
--   只是把同一权威值从「仅聚合可见」变成「逐条可见」，供 UI 渲染与导出。
--   函数现有 COMMENT 声明的契约正是这个用途：
--     "exposes the same per-lesson ... for UI display; no client-side rule"
--
--   ⚠️ null 是正确输出，不要在任何一侧兜底：
--      candidate_facts 里 pay_hours / lesson_wage_jpy 的 case 为
--        active_rule_count <> 1 → null（规则缺失或重复，需人工处理）
--        settlement_type='no_wage' → 0
--      学生结算未完成【不影响】这两个值，它们照常算出。
--      ⇒ 未结算月份导出勤务表时课时金额齐全；
--        留空的只有真正缺/重工资规则的异常课，那本就该在发给老师前修掉。
--
-- 向后兼容  jsonb_build_object 增键。wage-api.js 的
--           wagePrerequisiteFactsByLessonId 按键名取值，增键不影响既有读者。
--
-- ⛔ 不改：函数签名、返回类型、volatility、SECURITY DEFINER、search_path、
--         owner、ACL、operator 守卫、candidate_facts 函数本身、
--         summary / teacher_previews / blockers 三段的任何内容、业务数据、前端。
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
--    用 RAISE 让 psql 以非零码退出（ON_ERROR_STOP 已开）。
DO $mode$ BEGIN
  RAISE EXCEPTION 'WAGE_PREFLIGHT_MODE_INVALID: 必须指定 -v mode=rehearsal 或 -v mode=commit';
END $mode$;
\endif

BEGIN;

-- -----------------------------------------------------------------------------
-- pre 段：钉住「我们要替换的就是我们读过的那一版」
--
-- ⚠️ 生产是当前部署状态的唯一权威。本项目已知存在运行时补丁，
--    源文件/dump 不足以证明生产定义。这里逐条验特征串：
--    若生产已被改过而特征不符，宁可这里停住，也不要用 CREATE OR REPLACE
--    把未知补丁静默覆盖掉。
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE _wage_preflight_pre ON COMMIT DROP AS
SELECT
  p.oid,
  pg_catalog.pg_get_functiondef(p.oid)              AS def,
  COALESCE(p.proacl::text, '<null>')                AS acl,
  p.provolatile::text                               AS volatility,
  p.prosecdef                                       AS secdef,
  COALESCE(p.proconfig::text, '<null>')             AS cfg,
  p.proowner::regrole::text                         AS owner,
  COALESCE(pg_catalog.obj_description(p.oid, 'pg_proc'), '<null>') AS cmt
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

  -- 已经加过 → 不要重复部署（也可能是别人加的，语义未必相同）
  IF v_def LIKE '%''pay_hours'', pay_hours%' OR v_def LIKE '%''lesson_wage_jpy'', lesson_wage_jpy%' THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_ALREADY_PATCHED: candidate_prerequisites 已含 pay_hours/lesson_wage_jpy，停止';
  END IF;

  -- 守卫必须在，且必须是 operator 那一支（不是 admin-only）
  IF v_def NOT LIKE '%school_require_current_app_operator()%' THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_GUARD_DRIFT: 未找到 school_require_current_app_operator 守卫';
  END IF;

  -- 我们要改的 CTE 与其现有 9 个键（改后 11 个）
  IF v_def NOT LIKE '%candidate_prerequisites as (%'
     OR v_def NOT LIKE '%''prerequisite_satisfied'', blocker_code is null%'
     OR v_def NOT LIKE '%''effective_source_id'', effective_source_id%' THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_CTE_DRIFT: candidate_prerequisites 结构与取证版本不符';
  END IF;

  -- 我们不打算碰、但必须原样保留的三段
  IF v_def NOT LIKE '%''conditional_pay_hours'', coalesce((select sum(pay_hours) from classified where blocker_code is null),0)%'
     OR v_def NOT LIKE '%''conditional_amount_jpy'', coalesce((select sum(lesson_wage_jpy) from classified where blocker_code is null),0)%' THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_SUMMARY_DRIFT: summary 段与取证版本不符';
  END IF;

  IF v_def NOT LIKE '%''teacher_previews''%' OR v_def NOT LIKE '%''blockers''%' THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_SECTION_DRIFT: teacher_previews / blockers 段缺失';
  END IF;

  -- 四段式 blocker 分类的优先级顺序（改动不得影响它）
  IF v_def NOT LIKE '%when not c.fact_complete then ''WAGE_LESSON_FACT_INCOMPLETE''%'
     OR v_def NOT LIKE '%when c.active_rule_count = 0 then ''WAGE_RULE_MISSING''%'
     OR v_def NOT LIKE '%when c.active_rule_count > 1 then ''WAGE_RULE_DUPLICATE''%'
     OR v_def NOT LIKE '%''WAGE_EFFECTIVE_SETTLEMENT_MISSING''%' THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_CLASSIFY_DRIFT: blocker 分类分支与取证版本不符';
  END IF;

  RAISE NOTICE 'pre 检查通过：目标函数唯一，定义与 2026-09-12 取证版本一致。';

  -- 取证记录：Codex 2026-09-12 执行前只读检查录得生产定义 md5
  --   25a1f8cf76f25c8b31aa47f4c6103399
  -- 这里打印出来留痕。不做硬断言 —— 上面的特征串断言，加上 post 段
  -- 「去掉新增两行后必须逐字等于 pre」的比对，已经能挡住「生产定义与取证
  -- 版本不同」这件事本身；而 md5 一旦取值表达式不同就会无谓地打断部署。
  RAISE NOTICE 'pre 定义 md5(pg_get_functiondef) = %', md5(v_def);
  IF md5(v_def) <> '25a1f8cf76f25c8b31aa47f4c6103399' THEN
    RAISE NOTICE '⚠️ 与 Codex 执行前记录的 md5 不同。若上面各项特征断言均已通过，'
                 '最可能是取值表达式不同（本行按 md5(pg_get_functiondef(oid)) 计算）。'
                 '若有理由认为生产定义确实被改动过，请在此停止，不要继续 commit。';
  END IF;
END
$pre$;

-- -----------------------------------------------------------------------------
-- 替换：只在 candidate_prerequisites 的 jsonb_build_object 里加两个键。
--       其余部分与生产现定义逐字一致。
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
      'effective_source_id', effective_source_id,
      'pay_hours', pay_hours,
      'lesson_wage_jpy', lesson_wage_jpy
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

-- COMMENT 同步：原文保留，仅补上新增的两个逐条字段及其 null 语义。
COMMENT ON FUNCTION public.school_get_teacher_monthly_wage_generation_preflight(p_year_month text, p_teacher_id uuid, p_business_entity_id uuid) IS
  'Read-only structured wage preflight shared with the writer. candidate_prerequisites exposes the same per-lesson effective/no_wage classification for UI display, plus per-lesson pay_hours and lesson_wage_jpy so the UI and the duty-report export can render authoritative settled hours without a client-side rule; both are null when active_rule_count <> 1 and 0 for no_wage, and neither is affected by student settlement completeness. No client-side qualification rule. Requires an active admin or operator membership.';

-- -----------------------------------------------------------------------------
-- post 段：新键已就位，且除此之外什么都没变。
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

  -- CREATE OR REPLACE 不应换 oid；换了说明是 DROP+CREATE，ACL 会丢
  IF v_oid <> v_pre.oid THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_OID_CHANGED: 函数被重建而非替换，ACL 可能已丢失（pre=% post=%）', v_pre.oid, v_oid;
  END IF;

  -- 新键到位
  IF v_def NOT LIKE '%''pay_hours'', pay_hours%' THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_PATCH_MISSING: pay_hours 未写入 candidate_prerequisites';
  END IF;
  IF v_def NOT LIKE '%''lesson_wage_jpy'', lesson_wage_jpy%' THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_PATCH_MISSING: lesson_wage_jpy 未写入 candidate_prerequisites';
  END IF;

  -- 执行属性与权限面：一律不得变
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

  -- 守卫与其余三段原样还在
  IF v_def NOT LIKE '%school_require_current_app_operator()%' THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_GUARD_LOST: operator 守卫丢失';
  END IF;
  IF v_def NOT LIKE '%''conditional_pay_hours''%'
     OR v_def NOT LIKE '%''conditional_amount_jpy''%'
     OR v_def NOT LIKE '%''teacher_previews''%'
     OR v_def NOT LIKE '%''blockers''%' THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_SECTION_LOST: summary/teacher_previews/blockers 段受损';
  END IF;

  -- 除 candidate_prerequisites 的两行外，定义应与 pre 完全一致：
  -- 把新定义里这两行去掉后，应当逐字等于 pre 的定义。
  IF replace(
       replace(v_def, E',\n      ''pay_hours'', pay_hours', ''),
       E',\n      ''lesson_wage_jpy'', lesson_wage_jpy', ''
     ) IS DISTINCT FROM v_pre.def THEN
    RAISE EXCEPTION 'WAGE_PREFLIGHT_UNEXPECTED_DIFF: 除新增两键外定义发生了其他变化，请人工比对后再决定';
  END IF;

  RAISE NOTICE 'post 检查通过：仅新增 pay_hours / lesson_wage_jpy 两键，其余逐字未变。';
END
$post$;

-- -----------------------------------------------------------------------------
-- 冒烟 1：新键引用的两列确实存在于 candidate_facts 的输出上。
--
-- ⚠️ 这一步不能省，也不能用「调一次 preflight」替代：
--    · CREATE OR REPLACE 对 plpgsql 只做语法检查，不解析函数体内的表/列引用，
--      列名拼错不会在部署时报错，要等真实调用才炸。
--    · 而 preflight 首行就是 operator 守卫，psql 直连无 JWT 必然在那里 raise，
--      函数体后段根本执行不到 —— 调它证明不了列名写对了。
--    ⇒ 只能直接向 candidate_facts 探这两列。用 1900-01，返回 0 行，
--      不读任何真实业务数据，但列引用照样被解析。
-- -----------------------------------------------------------------------------
DO $cols$
DECLARE
  v_n int;
BEGIN
  SELECT count(*) INTO v_n
  FROM (
    SELECT jsonb_build_object('pay_hours', pay_hours, 'lesson_wage_jpy', lesson_wage_jpy) AS probe
    FROM public.school_get_teacher_monthly_wage_generation_candidate_facts('1900-01', null, null)
  ) s;
  RAISE NOTICE '冒烟 1 通过：pay_hours / lesson_wage_jpy 两列可解析（1900-01 返回 % 行）。', v_n;
END
$cols$;

-- -----------------------------------------------------------------------------
-- 冒烟 2：preflight 仍可调用，且 operator 守卫仍是第一道。
--   psql 直连无 JWT ⇒ auth.uid() 为 null ⇒ 预期 P0G1_AUTH_REQUIRED(42501)。
--   若连接恰好带有效 operator 身份，则应正常返回 jsonb。两者都算通过；
--   其它任何异常都说明函数坏了。
-- -----------------------------------------------------------------------------
DO $smoke$
DECLARE
  v_json jsonb;
BEGIN
  BEGIN
    v_json := public.school_get_teacher_monthly_wage_generation_preflight('1900-01', null, null);
    IF v_json->'candidate_prerequisites' IS NULL THEN
      RAISE EXCEPTION 'WAGE_PREFLIGHT_SMOKE_FAILED: candidate_prerequisites 缺失';
    END IF;
    RAISE NOTICE '冒烟 2 通过：带身份调用成功，候选 % 条。', jsonb_array_length(v_json->'candidate_prerequisites');
  EXCEPTION WHEN sqlstate '42501' THEN
    RAISE NOTICE '冒烟 2 通过：无 JWT 直连被 operator 守卫拦下（%），符合预期。', SQLERRM;
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
