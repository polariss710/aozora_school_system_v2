-- =============================================================================
-- 回滚：工资 preflight reader 还原为 admin 守卫
--
-- 背景  2026-09-11 02:0x 前端发布后，教务老师（operator）一进工资页就报
--         读取老师工资结算数据失败：P0G1_ACTIVE_ADMIN_REQUIRED
--       浏览器实测定位到 403 的是本函数（js/api/wage-api.js:118）。
--
--       前两批只把 writer 的守卫改成 admin-or-operator，【reader 一个没查】。
--       开放一个页面要过的是它整条数据通路，不是业务方点名的那几个写操作。
--
-- 范围  Codex 2026-09-11 02:45 生产取证：27 个名称 / 30 个签名 / 15 张表全查，
--       【唯一】对 active operator 构成加载阻断的就是本函数。
--       其余 reader 要么已兼容 operator，要么本就无角色守卫；
--       冲销、作废、支付确认等仍是 admin-only，本批不动。
--
-- 连带  工资生成链是 (2) → (3) → 本函数 → admin 守卫。
--       9-10 已换守卫的那两个 writer 仍被本函数挡在下游 ⇒
--       修这一个，页面加载与「生成老师工资」按钮一起通。
--
-- 改动  一行：admin 守卫 → operator 守卫。COMMENT 追加一句准入说明。
--       ⛔ 不改 ACL、owner、签名、函数体其余部分、业务数据。
--
-- 用法
--   psql -v ON_ERROR_STOP=1 -v mode=commit -f <本文件>
-- =============================================================================
\set ON_ERROR_STOP on
SELECT (:'mode'='commit') AS is_commit, (:'mode'='rehearsal') AS is_rehearsal \gset
\if :is_commit
\echo '>>> mode=commit —— 通过全部断言后将 COMMIT'
\elif :is_rehearsal
\echo '>>> mode=rehearsal —— 通过全部断言后将 ROLLBACK'
\else
\echo '!!! 必须指定 -v mode=rehearsal 或 -v mode=commit'
\quit
\endif

-- ⚠️ 回滚【不依赖】operator 守卫：还原后的定义不引用它。
--    守卫若消失，本函数会在运行时报「函数不存在」，工资页整页读不出来，
--    而回滚正是唯一的救援手段 ⇒ 这里只告警、不中断。

BEGIN;

DO $guard$
DECLARE v_n int; v_md5 text; v_acl text;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_require_current_app_operator';
  IF v_n <> 1 THEN
    RAISE WARNING 'OPWRP_RB_GUARD_MISSING: public.school_require_current_app_operator 有 % 个（应为 1）', v_n;
    RETURN;
  END IF;
  SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,'') INTO v_md5, v_acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_require_current_app_operator';
  IF v_md5 <> '526c615da0c5bf179894ccbcc325008c' THEN
    RAISE WARNING 'OPWRP_RB_GUARD_DRIFT: 守卫定义为 %，期望 %', v_md5, '526c615da0c5bf179894ccbcc325008c';
    RETURN;
  END IF;
  IF v_acl <> '{postgres=X/postgres,authenticated=X/postgres}' THEN
    RAISE WARNING 'OPWRP_RB_GUARD_ACL: 守卫 ACL 为 %，期望 %', v_acl, '{postgres=X/postgres,authenticated=X/postgres}';
    RETURN;
  END IF;
  RAISE NOTICE 'OPWRP_RB: operator 守卫状态正常（回滚本身不依赖它）';
END
$guard$;

DO $rbpre$
DECLARE
  v_n int; v_md5 text; v_acl text; v_cmt text; v_cfg text; v_owner text;
  v_sec boolean; v_strict boolean; v_par char; v_leak boolean; v_cost real; v_rows real;
  v_def text; v_a int; v_o int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_get_teacher_monthly_wage_generation_preflight' AND p.pronargs=3;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'OPWRP_RB_ARITY: public.school_get_teacher_monthly_wage_generation_preflight(3) 匹配到 % 个（应为 1）', v_n;
  END IF;

  SELECT pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,''),
         coalesce(obj_description(p.oid,'pg_proc'),'<NULL>'),
         coalesce(array_to_string(p.proconfig,', '),'<NULL>'),
         pg_get_userbyid(p.proowner), p.prosecdef, p.proisstrict,
         p.proparallel, p.proleakproof, p.procost, p.prorows
    INTO v_def, v_md5, v_acl, v_cmt, v_cfg, v_owner, v_sec, v_strict, v_par, v_leak, v_cost, v_rows
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_get_teacher_monthly_wage_generation_preflight' AND p.pronargs=3;

  IF v_md5 <> '25a1f8cf76f25c8b31aa47f4c6103399' THEN
    RAISE EXCEPTION 'OPWRP_RB_MD5: 定义为 %，期望 %', v_md5, '25a1f8cf76f25c8b31aa47f4c6103399';
  END IF;
  IF v_acl <> '{postgres=X/postgres,authenticated=X/postgres}' THEN
    RAISE EXCEPTION 'OPWRP_RB_ACL: ACL 为 %，期望 %', v_acl, '{postgres=X/postgres,authenticated=X/postgres}';
  END IF;
  IF v_cmt <> 'Read-only structured wage preflight shared with the writer. candidate_prerequisites exposes the same per-lesson effective/no_wage classification for UI display; no client-side qualification rule. Requires an active admin or operator membership.' THEN
    RAISE EXCEPTION 'OPWRP_RB_COMMENT: 注释为 [%]，期望 [%]', v_cmt, 'Read-only structured wage preflight shared with the writer. candidate_prerequisites exposes the same per-lesson effective/no_wage classification for UI display; no client-side qualification rule. Requires an active admin or operator membership.';
  END IF;
  IF v_cfg <> 'search_path=pg_catalog, public' THEN
    RAISE EXCEPTION 'OPWRP_RB_CONFIG: proconfig 为 %，期望 %', v_cfg, 'search_path=pg_catalog, public';
  END IF;
  IF v_owner <> 'postgres' OR v_sec IS NOT TRUE OR v_strict IS NOT FALSE
     OR v_par <> 'u' OR v_leak IS NOT FALSE OR v_cost <> 100 THEN
    RAISE EXCEPTION 'OPWRP_RB_ATTRS: owner=% secdef=% strict=% parallel=% leakproof=% cost=% rows=%',
      v_owner, v_sec, v_strict, v_par, v_leak, v_cost, v_rows;
  END IF;

  v_a := (length(v_def)-length(replace(v_def,'school_require_current_app_admin','')))/length('school_require_current_app_admin');
  v_o := (length(v_def)-length(replace(v_def,'school_require_current_app_operator','')))/length('school_require_current_app_operator');
  -- ⚠️ operator 守卫名【包含】admin 守卫名之外的字样，但两个名字互不为子串，
  --    所以这两个计数互不干扰。
  IF v_a <> 0 OR v_o <> 1 THEN
    RAISE EXCEPTION 'OPWRP_RB_CALLS: admin 守卫 % 次（期望 0）、operator 守卫 % 次（期望 1）',
      v_a, v_o;
  END IF;

  RAISE NOTICE 'OPWRP_RB: md5 / ACL / COMMENT / proconfig / 执行属性 / 守卫调用次数 全部符合预期';
END
$rbpre$;

-- ===== 还原：生产 canonical 逐字节 =====
CREATE OR REPLACE FUNCTION public.school_get_teacher_monthly_wage_generation_preflight(p_year_month text, p_teacher_id uuid, p_business_entity_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_result jsonb;
begin
  perform public.school_require_current_app_admin();
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
$function$;

-- ===== 注释还原 =====
COMMENT ON FUNCTION public.school_get_teacher_monthly_wage_generation_preflight(p_year_month text, p_teacher_id uuid, p_business_entity_id uuid) IS 'Read-only structured wage preflight shared with the writer. candidate_prerequisites exposes the same per-lesson effective/no_wage classification for UI display; no client-side qualification rule.';

DO $rbpost$
DECLARE
  v_n int; v_md5 text; v_acl text; v_cmt text; v_cfg text; v_owner text;
  v_sec boolean; v_strict boolean; v_par char; v_leak boolean; v_cost real; v_rows real;
  v_def text; v_a int; v_o int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_get_teacher_monthly_wage_generation_preflight' AND p.pronargs=3;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'OPWRP_RB_POST_ARITY: public.school_get_teacher_monthly_wage_generation_preflight(3) 匹配到 % 个（应为 1）', v_n;
  END IF;

  SELECT pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,''),
         coalesce(obj_description(p.oid,'pg_proc'),'<NULL>'),
         coalesce(array_to_string(p.proconfig,', '),'<NULL>'),
         pg_get_userbyid(p.proowner), p.prosecdef, p.proisstrict,
         p.proparallel, p.proleakproof, p.procost, p.prorows
    INTO v_def, v_md5, v_acl, v_cmt, v_cfg, v_owner, v_sec, v_strict, v_par, v_leak, v_cost, v_rows
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_get_teacher_monthly_wage_generation_preflight' AND p.pronargs=3;

  IF v_md5 <> 'b2df4d76ed9cc9533b198e247d459ac1' THEN
    RAISE EXCEPTION 'OPWRP_RB_POST_MD5: 定义为 %，期望 %', v_md5, 'b2df4d76ed9cc9533b198e247d459ac1';
  END IF;
  IF v_acl <> '{postgres=X/postgres,authenticated=X/postgres}' THEN
    RAISE EXCEPTION 'OPWRP_RB_POST_ACL: ACL 为 %，期望 %', v_acl, '{postgres=X/postgres,authenticated=X/postgres}';
  END IF;
  IF v_cmt <> 'Read-only structured wage preflight shared with the writer. candidate_prerequisites exposes the same per-lesson effective/no_wage classification for UI display; no client-side qualification rule.' THEN
    RAISE EXCEPTION 'OPWRP_RB_POST_COMMENT: 注释为 [%]，期望 [%]', v_cmt, 'Read-only structured wage preflight shared with the writer. candidate_prerequisites exposes the same per-lesson effective/no_wage classification for UI display; no client-side qualification rule.';
  END IF;
  IF v_cfg <> 'search_path=pg_catalog, public' THEN
    RAISE EXCEPTION 'OPWRP_RB_POST_CONFIG: proconfig 为 %，期望 %', v_cfg, 'search_path=pg_catalog, public';
  END IF;
  IF v_owner <> 'postgres' OR v_sec IS NOT TRUE OR v_strict IS NOT FALSE
     OR v_par <> 'u' OR v_leak IS NOT FALSE OR v_cost <> 100 THEN
    RAISE EXCEPTION 'OPWRP_RB_POST_ATTRS: owner=% secdef=% strict=% parallel=% leakproof=% cost=% rows=%',
      v_owner, v_sec, v_strict, v_par, v_leak, v_cost, v_rows;
  END IF;

  v_a := (length(v_def)-length(replace(v_def,'school_require_current_app_admin','')))/length('school_require_current_app_admin');
  v_o := (length(v_def)-length(replace(v_def,'school_require_current_app_operator','')))/length('school_require_current_app_operator');
  -- ⚠️ operator 守卫名【包含】admin 守卫名之外的字样，但两个名字互不为子串，
  --    所以这两个计数互不干扰。
  IF v_a <> 1 OR v_o <> 0 THEN
    RAISE EXCEPTION 'OPWRP_RB_POST_CALLS: admin 守卫 % 次（期望 1）、operator 守卫 % 次（期望 0）',
      v_a, v_o;
  END IF;

  RAISE NOTICE 'OPWRP_RB_POST: md5 / ACL / COMMENT / proconfig / 执行属性 / 守卫调用次数 全部符合预期';
END
$rbpost$;

-- ⚠️ 回滚只还原定义与注释。它把工资页对 operator 重新关上，
--    也不撤销期间已产生的任何业务记录（工资快照、支付请求、支出记录）。

\if :is_commit
COMMIT;
\echo '>>> 已 COMMIT'
\else
ROLLBACK;
\echo '>>> 已 ROLLBACK（rehearsal）'
\endif
