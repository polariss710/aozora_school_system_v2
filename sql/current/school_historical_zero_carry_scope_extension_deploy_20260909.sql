-- =============================================================================
-- 历史零结转：范围闸门扩围（C′）
--
-- 目的   让 b17abc58 的 2026-08 可以走既有的历史零结转完成机制。
--        该月无法走常规「草稿调整＋锁定」——2026-09 的 active 账单声明上月为
--        2026-08，草稿 writer 与 lock writer 都会撞
--        TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE。
--        而候选检查【通过】：它的零值判据是「次月账单冻结的 previous_carryover_cny
--        必须为 0」，不是「当月差额为零」；候选还要求恰好存在一条次月 active
--        revision —— 正是这个缺陷产生的形状。
--
-- 改动   闸门由「月份 = 2026-07 【且】学生 ∈ 四人」改为 (月份, 学生) 【逐对】列举，
--        并追加一对 ('2026-08', b17abc58)。
--        ⚠️ 直接把 '2026-08' 加进原写法会把【那四个人的八月】也一并放开，
--           那是没人批准过的范围。配对形式就是为挡住这个交叉积。
--
-- 不改   角色闸门、core、candidate、evidence 表与触发器，一律不动。
--        本脚本【不建立任何 evidence】——建立是之后单独授权的执行步骤。
--
-- 签名不变 ⇒ CREATE OR REPLACE，不 DROP：不掉 ACL、不产生重载、无默认授权回流。
--
-- ⚠️ 函数真名被 PostgreSQL 的 63 字节上限截断为
--      school_local_create_student_monthly_settlement_historical_compl
--    调用与 PostgREST 路径都必须用截断后的真名。
--
-- 用法
--   排练  psql -v ON_ERROR_STOP=1 -v mode=rehearsal -f <本文件>
--   正式  psql -v ON_ERROR_STOP=1 -v mode=commit    -f <本文件>
-- =============================================================================
\set ON_ERROR_STOP on

\if :{?mode}
\else
  \set mode 'unset'
\endif

BEGIN;

SELECT set_config('hzc.mode', :'mode', false);

DO $gate$
BEGIN
  IF current_setting('hzc.mode') NOT IN ('rehearsal','commit') THEN
    RAISE EXCEPTION 'HZC_MODE_REQUIRED: 需要 -v mode=rehearsal 或 -v mode=commit，得到 %',
      current_setting('hzc.mode');
  END IF;
END
$gate$;

-- -----------------------------------------------------------------------------
-- §1 部署前基线
-- -----------------------------------------------------------------------------
DO $pre$
DECLARE
  v_oid oid; v_md5 text; v_acl text; v_cfg text; v_cmt text; v_n int;
  v_own text; v_sec boolean; v_strict boolean; v_par char; v_leak boolean;
  v_cost real; v_rows real;
BEGIN
  -- 同名重载必须恰好一个。基线校验走精确签名，多出来的重载它看不见，
  -- 而调用时才会报 function ... is not unique。
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_local_create_student_monthly_settlement_historical_compl';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'HZC_PRE_OVERLOAD: public.% 有 % 个重载（应为 1）', 'school_local_create_student_monthly_settlement_historical_compl', v_n;
  END IF;

  v_oid := to_regprocedure('public.school_local_create_student_monthly_settlement_historical_compl(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)');
  IF v_oid IS NULL THEN RAISE EXCEPTION 'HZC_PRE_MISSING: 找不到目标签名'; END IF;

  SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,''),
         coalesce(array_to_string(p.proconfig,','),''), obj_description(p.oid,'pg_proc'),
         pg_get_userbyid(p.proowner), p.prosecdef, p.proisstrict, p.proparallel,
         p.proleakproof, p.procost, p.prorows
    INTO v_md5, v_acl, v_cfg, v_cmt, v_own, v_sec, v_strict, v_par, v_leak, v_cost, v_rows
    FROM pg_proc p WHERE p.oid=v_oid;

  IF v_md5 <> '3036165ab9352e7701b43f40c19018fc' THEN
    RAISE EXCEPTION 'HZC_PRE_MD5: 得 %  期望 %', v_md5, '3036165ab9352e7701b43f40c19018fc'; END IF;
  IF v_acl <> '{postgres=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'HZC_PRE_ACL: 得 %', v_acl; END IF;
  IF v_cfg <> 'search_path=pg_catalog, public' THEN
    RAISE EXCEPTION 'HZC_PRE_PROCONFIG: 得 %', v_cfg; END IF;
  IF v_cmt IS DISTINCT FROM 'Service-role-only local trusted wrapper for the four approved 2026-07 scopes; no browser entry point.' THEN
    RAISE EXCEPTION 'HZC_PRE_COMMENT: 得 %', coalesce(v_cmt,'<null>'); END IF;
  IF v_own <> 'postgres' OR v_sec IS NOT TRUE OR v_strict IS NOT FALSE
     OR v_par <> 'u' OR v_leak IS NOT FALSE OR v_cost <> 100 OR v_rows <> 0 THEN
    RAISE EXCEPTION 'HZC_PRE_ATTRS: owner=% secdef=% strict=% parallel=% leak=% cost=% rows=%',
      v_own, v_sec, v_strict, v_par, v_leak, v_cost, v_rows;
  END IF;

  -- 本次要新增的那一对，此刻【必须还没有】evidence。
  SELECT count(*) INTO v_n
    FROM public.school_student_monthly_settlement_historical_completion_evidence
   WHERE student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid
     AND settlement_month='2026-08';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'HZC_PRE_EVIDENCE_EXISTS: 已有 % 行，本次改动的前提不成立', v_n;
  END IF;

  RAISE NOTICE 'HZC: 部署前基线全部通过';
END
$pre$;

-- -----------------------------------------------------------------------------
-- §2 替换定义（签名不变 ⇒ CREATE OR REPLACE）
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.school_local_create_student_monthly_settlement_historical_compl(p_student_id uuid, p_settlement_month text, p_business_entity_id uuid, p_expected_lesson_manifest_sha256 text, p_expected_makeup_manifest_sha256 text, p_expected_active_revision_id uuid, p_expected_tuition_bill_id uuid, p_expected_income_record_id uuid, p_expected_cash_linkage_event_id uuid, p_expected_cash_request_id uuid, p_expected_cash_transaction_id uuid, p_created_by_actor_id uuid, p_reason text, p_confirmation_text text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'HISTORICAL_ZERO_CARRY_LOCAL_TRUSTED_ROLE_REQUIRED';
  end if;
  if not (
    p_business_entity_id = '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
    and (p_settlement_month, p_student_id) in (
      ('2026-07', 'eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid),
      ('2026-07', '881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid),
      ('2026-07', 'a7b163a0-201e-4867-9b94-372343356a80'::uuid),
      ('2026-07', '4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::uuid),
      ('2026-08', 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid)
    )
  ) and not exists (
    select 1 from public.school_students s
    where s.id = p_student_id
      and s.business_entity_id = p_business_entity_id
      and (s.name ilike '%codex-test%' or coalesce(s.note, '') ilike '%codex-test%')
  ) then
    raise exception 'HISTORICAL_ZERO_CARRY_LOCAL_SCOPE_NOT_APPROVED';
  end if;

  return public.school_create_student_monthly_settlement_historical_completion_evidence_core(
    p_student_id, p_settlement_month, p_business_entity_id,
    p_expected_lesson_manifest_sha256, p_expected_makeup_manifest_sha256,
    p_expected_active_revision_id, p_expected_tuition_bill_id,
    p_expected_income_record_id, p_expected_cash_linkage_event_id,
    p_expected_cash_request_id, p_expected_cash_transaction_id,
    p_created_by_actor_id, p_reason, p_confirmation_text, p_idempotency_key
  );
end
$function$;

COMMENT ON FUNCTION public.school_local_create_student_monthly_settlement_historical_compl(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text) IS 'Service-role-only local trusted wrapper for the five approved (month, student) scopes; no browser entry point.';

-- -----------------------------------------------------------------------------
-- §3 部署后断言
-- -----------------------------------------------------------------------------
DO $post$
DECLARE
  v_oid oid; v_md5 text; v_acl text; v_cfg text; v_cmt text; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_local_create_student_monthly_settlement_historical_compl';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'HZC_POST_OVERLOAD: public.% 有 % 个重载（应为 1）', 'school_local_create_student_monthly_settlement_historical_compl', v_n; END IF;

  v_oid := to_regprocedure('public.school_local_create_student_monthly_settlement_historical_compl(uuid,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)');
  IF v_oid IS NULL THEN RAISE EXCEPTION 'HZC_POST_MISSING'; END IF;
  SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,''),
         coalesce(array_to_string(p.proconfig,','),''), obj_description(p.oid,'pg_proc')
    INTO v_md5, v_acl, v_cfg, v_cmt FROM pg_proc p WHERE p.oid=v_oid;

  IF v_md5 <> '1e071b2b9caa465e10f8879a2e11926a' THEN
    RAISE EXCEPTION 'HZC_POST_MD5: 得 %  期望 %', v_md5, '1e071b2b9caa465e10f8879a2e11926a'; END IF;
  -- 签名未变，CREATE OR REPLACE 不该动 ACL。若这里报错，说明发生了预期外的重建。
  IF v_acl <> '{postgres=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'HZC_POST_ACL: 得 %  ← 权限被改动', v_acl; END IF;
  IF v_cfg <> 'search_path=pg_catalog, public' THEN
    RAISE EXCEPTION 'HZC_POST_PROCONFIG: 得 %', v_cfg; END IF;
  IF v_cmt IS DISTINCT FROM 'Service-role-only local trusted wrapper for the five approved (month, student) scopes; no browser entry point.' THEN
    RAISE EXCEPTION 'HZC_POST_COMMENT: 得 %', coalesce(v_cmt,'<null>'); END IF;
END
$post$;

-- -----------------------------------------------------------------------------
-- §4 闸门行为矩阵
--
--   十组，五放行五拒绝。放行组用【无效 actor】去撞 core —— core 先校验 actor
--   才插入，所以「打到了 core」这件事可观测，而且【不产生任何写入】。
--   拒绝组必须报 SCOPE_NOT_APPROVED。
--
--   ⚠️ 交叉积那几组是这次改动的要害：原写法是「月份=2026-07 且 学生∈四人」，
--      若直接把 2026-08 加进去，那四个人的八月会被一并放开。
-- -----------------------------------------------------------------------------
DO $gatecheck$
DECLARE
  r record; v_err text; v_got text; v_bad int := 0; v_before bigint; v_after bigint;
BEGIN
  SELECT count(*) INTO v_before
    FROM public.school_student_monthly_settlement_historical_completion_evidence;

  FOR r IN SELECT * FROM (VALUES
    ('service_role','2026-07','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::text,'pass','原四人之一 / 2026-07'),
    ('service_role','2026-07','881dd60c-b92b-44ae-98e1-98448567a8d2'::text,'pass','原四人之一 / 2026-07'),
    ('service_role','2026-07','a7b163a0-201e-4867-9b94-372343356a80'::text,'pass','原四人之一 / 2026-07'),
    ('service_role','2026-07','4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::text,'pass','原四人之一 / 2026-07'),
    ('service_role','2026-08','b17abc58-2f64-4bad-bf20-c9643ead60bc'::text,'pass','本次新增'),
    ('service_role','2026-08','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::text,'deny','交叉积：原四人的八月'),
    ('service_role','2026-08','4c6f1473-7d44-467d-a70b-30f02e7cf8cd'::text,'deny','交叉积：原四人的八月'),
    ('service_role','2026-07','b17abc58-2f64-4bad-bf20-c9643ead60bc'::text,'deny','交叉积：孙陈锋的七月'),
    ('service_role','2026-09','b17abc58-2f64-4bad-bf20-c9643ead60bc'::text,'deny','孙陈锋的九月'),
    ('service_role','2026-08','00000000-0000-4000-8000-000000000001'::text,'deny','无关学生')
  ) AS t(role, month, student, expect, note) LOOP
    PERFORM set_config('request.jwt.claim.role', r.role, true);
    PERFORM set_config('request.jwt.claims', json_build_object('role', r.role)::text, true);
    BEGIN
      PERFORM public.school_local_create_student_monthly_settlement_historical_compl(
        r.student::uuid, r.month, '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
        'deliberately-wrong-lesson-manifest', 'deliberately-wrong-makeup-manifest',
        NULL, NULL, NULL, NULL, NULL, NULL,
        '00000000-0000-4000-8000-000000000009'::uuid, 'gate probe', 'gate probe', 'gate probe');
      v_err := '<无异常 —— 不应发生>';
    EXCEPTION WHEN OTHERS THEN
      v_err := SQLERRM;
    END;

    v_got := CASE
      WHEN position('HISTORICAL_ZERO_CARRY_LOCAL_SCOPE_NOT_APPROVED' in v_err) > 0 THEN 'deny'
      WHEN position('HISTORICAL_ZERO_CARRY_LOCAL_TRUSTED_ROLE_REQUIRED' in v_err) > 0 THEN 'role'
      ELSE 'pass' END;

    IF v_got <> r.expect THEN
      v_bad := v_bad + 1;
      RAISE WARNING 'HZC_GATE_MISMATCH: % / % (%) 期望 % 实得 % —— %',
        r.month, r.student, r.note, r.expect, v_got, v_err;
    END IF;
  END LOOP;

  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '', true);

  SELECT count(*) INTO v_after
    FROM public.school_student_monthly_settlement_historical_completion_evidence;
  IF v_after <> v_before THEN
    RAISE EXCEPTION 'HZC_GATE_WROTE_ROWS: 探测期间 evidence 由 % 变为 % —— 必须零写入',
      v_before, v_after;
  END IF;

  IF v_bad > 0 THEN
    RAISE EXCEPTION 'HZC_GATE_MATRIX: % 组与预期不符，见上方 WARNING', v_bad;
  END IF;
  RAISE NOTICE 'HZC: 闸门矩阵 10 组全部符合预期，evidence 行数未变（% 行）', v_after;
END
$gatecheck$;

-- -----------------------------------------------------------------------------
-- §5 收尾
-- -----------------------------------------------------------------------------
DO $fin$
BEGIN
  IF current_setting('hzc.mode') = 'rehearsal' THEN
    RAISE NOTICE 'HZC: 排练通过，即将 ROLLBACK —— 生产未被修改';
  ELSE
    RAISE NOTICE 'HZC: 断言全部通过，即将 COMMIT';
  END IF;
END
$fin$;

-- psql 的 \if 只认简单布尔值，故先把判定落成变量再分支。
SELECT (:'mode' = 'rehearsal') AS hzc_is_rehearsal \gset
\if :hzc_is_rehearsal
ROLLBACK;
\else
COMMIT;
\endif
