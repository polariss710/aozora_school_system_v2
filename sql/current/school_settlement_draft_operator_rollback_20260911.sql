-- =============================================================================
-- 回滚：撤除月结草稿的 operator 断言
--
-- 背景  月度结算两页要开放给教务老师（operator）。业务负责人 2026-09-11 定：
--         【保存草稿给她，锁定留给管理员。】
--       锁定会冻结当月结算并把结转带进下月账单，是不可逆的财务承诺。
--
-- ⚠️ 因此不能「换守卫」，只能「拆」。Codex 2026-09-11 取证确认两处都是共用的：
--       · Edge：_shared/student-settlement-online-contract.ts 只有一处
--         requireActiveAdmin，save 与 lock 都走它
--       · 数据库：save 与 lock 都 perform school_assert_student_settlement_online_admin(p_actor_user_id)
--       照前几批直接改，会把【锁定】也一起开放给她。
--
-- 本脚本只做【数据库侧】的拆分：
--   A. 新建 school_assert_student_settlement_online_operator(uuid)
--      —— 与 admin 版同形，仅把 role 判据放宽为 admin 或 operator。
--      owner-only ACL，与 admin 版一致；不给 authenticated / service_role。
--   B. save 改调新断言，两处 operator_authority 标签与 COMMENT 同步改准。
--   ⛔ lock 与 admin 断言【一个字节都不动】，脚本对此有正向断言。
--
-- ⚠️ 顺序：先库后 Edge。
--   库改完而 Edge 仍要求 admin ⇒【零行为变化】，operator 仍进不来；
--   反过来则会出现「Edge 放行、库拒绝」的半开状态。
--   Edge 侧另行准备，且必须先有经过验证的回退包。
--
-- ⛔ 不改：ACL、owner、签名、lock、admin 断言、业务数据、前端。
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

-- ⚠️ 回滚把草稿保存重新收回给管理员。
--    若 Edge 侧已部署 operator 版而库回滚了，她会拿到
--    SETTLEMENT_OPERATOR_REQUIRED —— 请连同 Edge 一起考虑。
--    回滚不撤销期间已产生的任何草稿行。

BEGIN;

CREATE TEMP TABLE settle_before ON COMMIT DROP AS
SELECT p.proname AS b_name,
       md5(pg_get_functiondef(p.oid)) AS b_md5,
       coalesce(p.proacl::text,'') AS b_acl,
       coalesce(obj_description(p.oid,'pg_proc'),'<NULL>') AS b_cmt,
       p.proisstrict AS b_strict, p.proparallel AS b_par, p.proleakproof AS b_leak,
       p.procost AS b_cost, p.prorows AS b_rows, p.prosecdef AS b_secdef,
       pg_get_userbyid(p.proowner) AS b_owner,
       coalesce(array_to_string(p.proconfig,', '),'<NULL>') AS b_cfg
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN ('school_lock_student_monthly_settlement_online_admin', 'school_assert_student_settlement_online_admin');

DO $cap$
BEGIN
  IF (SELECT count(*) FROM settle_before) <> 2 THEN
    RAISE EXCEPTION 'SETL_PRE_CAPTURE: 未能各取到 1 个 lock 与 admin 断言';
  END IF;
  RAISE NOTICE 'SETL_PRE: 已记下 lock 与 admin 断言的 md5/ACL/COMMENT/执行属性';
END
$cap$;

-- ⚠️ lock 与 admin 断言必须【本来就是对的】，不只是「我没动过」。
--    untouched 只能证明后者：若 admin 断言在本批之前就已被放宽到允许 operator，
--    untouched 依然通过，而脚本会输出「锁定仍是管理员专属」—— 那句话就成了假的。
--    本批的整个前提是「锁定只属于管理员」，所以这两个对象要按取证基线钉死。
DO $pinned$
DECLARE t record; v_md5 text; v_acl text; v_def text;
BEGIN
  FOR t IN SELECT * FROM (VALUES
      ('school_lock_student_monthly_settlement_online_admin',    'ae5a0cdf7f7c14de2785845cbd08687d', '{postgres=X/postgres,service_role=X/postgres}'),
      ('school_assert_student_settlement_online_admin', '1cbc270424a03e4b62906f0fafbdaab0',  '{postgres=X/postgres}')
    ) AS v(proname, md5, acl)
  LOOP
    SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,''), pg_get_functiondef(p.oid)
      INTO v_md5, v_acl, v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=t.proname;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'SETL_PRE_BASELINE_MISSING: 找不到 %', t.proname;
    END IF;
    IF v_md5 <> t.md5 THEN
      RAISE EXCEPTION 'SETL_PRE_BASELINE_MD5: % 的定义为 %，期望取证基线 %', t.proname, v_md5, t.md5;
    END IF;
    IF v_acl <> t.acl THEN
      RAISE EXCEPTION 'SETL_PRE_BASELINE_ACL: % 的 ACL 为 %，期望 %', t.proname, v_acl, t.acl;
    END IF;
  END LOOP;

  -- 再直接验一次语义：admin 断言的角色判据必须【仍然只认 admin】。
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_assert_student_settlement_online_admin';
  IF position('''operator''' in v_def) > 0 OR position('''admin''' in v_def) = 0 THEN
    RAISE EXCEPTION 'SETL_PRE_BASELINE_ADMIN_ROLE: admin 断言的角色判据已被改动';
  END IF;

  RAISE NOTICE 'SETL_PRE: lock 与 admin 断言与取证基线一致（锁定确为管理员专属）';
END
$pinned$;

DO $opr$
DECLARE v_n int; v_md5 text; v_acl text; v_cmt text;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_assert_student_settlement_online_operator';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'SETL_RB_OPER_ARITY: school_assert_student_settlement_online_operator 有 % 个（应为 1）', v_n;
  END IF;
  SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,''),
         coalesce(obj_description(p.oid,'pg_proc'),'<NULL>')
    INTO v_md5, v_acl, v_cmt
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_assert_student_settlement_online_operator';
  IF v_md5 <> 'a53eeb11dae4d7ec25ec30663cff2e9c' THEN
    RAISE EXCEPTION 'SETL_RB_OPER_MD5: 新断言定义为 %，期望 %', v_md5, 'a53eeb11dae4d7ec25ec30663cff2e9c';
  END IF;
  -- ⚠️ owner-only：绝不能给 authenticated 或 service_role。
  --    给了就等于前端能绕过 Edge 直接断言身份。
  IF v_acl <> '{postgres=X/postgres}' THEN
    RAISE EXCEPTION 'SETL_RB_OPER_ACL: 新断言 ACL 为 %，期望 %', v_acl, '{postgres=X/postgres}';
  END IF;
  IF v_cmt <> 'Owner-only Phase A assertion for the draft-save path. The caller-supplied UUID is accepted only after an auth.users-backed active admin-or-operator membership row is locked FOR SHARE. JWT-to-actor binding remains an Edge responsibility. Locking keeps the admin-only assertion.' THEN
    RAISE EXCEPTION 'SETL_RB_OPER_COMMENT: 新断言注释与预期不符';
  END IF;
  RAISE NOTICE 'SETL_RB: 新断言的 md5 / ACL（owner-only）/ 注释 全部符合预期';
END
$opr$;

DO $rbpre$
DECLARE v_n int; v_def text; v_md5 text; v_acl text; v_cmt text;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_save_student_monthly_settlement_draft_online_admin';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'SETL_RB_SAVE_ARITY: school_save_student_monthly_settlement_draft_online_admin 有 % 个（应为 1）', v_n;
  END IF;

  SELECT pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid)),
         coalesce(p.proacl::text,''), coalesce(obj_description(p.oid,'pg_proc'),'<NULL>')
    INTO v_def, v_md5, v_acl, v_cmt
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_save_student_monthly_settlement_draft_online_admin';

  IF v_md5 <> '8ea280dd155028abc48535ded8e6a7d1' THEN
    RAISE EXCEPTION 'SETL_RB_SAVE_MD5: 定义为 %，期望 %', v_md5, '8ea280dd155028abc48535ded8e6a7d1';
  END IF;
  IF v_acl <> '{postgres=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'SETL_RB_SAVE_ACL: ACL 为 %，期望 %', v_acl, '{postgres=X/postgres,service_role=X/postgres}';
  END IF;
  IF v_cmt <> 'Phase A service_role-only online save wrapper. Revalidates active admin-or-operator actor, effective state, scope, manifests, DB amounts, existing draft versions, and semantic idempotency; never locks a settlement.' THEN
    RAISE EXCEPTION 'SETL_RB_SAVE_COMMENT: 注释为 [%]', v_cmt;
  END IF;

  -- 断言「变成了什么」，不只是「变了」
  IF (length(v_def)-length(replace(v_def,'school_assert_student_settlement_online_admin','')))/length('school_assert_student_settlement_online_admin') <> 0 THEN
    RAISE EXCEPTION 'SETL_RB_SAVE_ADMIN_CALLS: admin 断言调用次数不是 0';
  END IF;
  IF (length(v_def)-length(replace(v_def,'school_assert_student_settlement_online_operator','')))/length('school_assert_student_settlement_online_operator') <> 1 THEN
    RAISE EXCEPTION 'SETL_RB_SAVE_OPER_CALLS: operator 断言调用次数不是 1';
  END IF;
  IF (length(v_def)-length(replace(v_def,'authenticated_active_admin_or_operator_edge_v1','')))/length('authenticated_active_admin_or_operator_edge_v1') <> 2 THEN
    RAISE EXCEPTION 'SETL_RB_SAVE_NEW_LABEL: 新 authority 标签出现次数不是 2';
  END IF;
  -- ⚠️ 新标签【包含】旧标签以外的字样，两者互不为子串，计数互不干扰。
  IF (length(v_def)-length(replace(v_def,'authenticated_active_admin_edge_v1','')))/length('authenticated_active_admin_edge_v1') <> 0 THEN
    RAISE EXCEPTION 'SETL_RB_SAVE_OLD_LABEL: 旧 authority 标签出现次数不是 0';
  END IF;

  RAISE NOTICE 'SETL_RB: save 的 md5 / ACL / 注释 / 断言调用 / authority 标签 全部符合预期';
END
$rbpre$;

-- ===== B. 还原 save 的生产 canonical 逐字节 =====
CREATE OR REPLACE FUNCTION public.school_save_student_monthly_settlement_draft_online_admin(p_actor_user_id uuid, p_student_id uuid, p_year_month text, p_source_treatment_mode text, p_settlement_exchange_rate numeric, p_settlement_exchange_rate_source text, p_settlement_exchange_rate_effective_date date, p_adjustment_mode text, p_explicit_user_amount_cny numeric, p_reason text, p_note text, p_expected_preview_manifest_sha256 text, p_expected_lesson_variance_manifest_sha256 text, p_expected_source_count integer, p_expected_unused_planned_credit_jpy numeric, p_expected_overage_charge_jpy numeric, p_expected_net_lesson_variance_jpy numeric, p_expected_net_lesson_variance_cny numeric, p_expected_system_difference_cny numeric, p_expected_final_carryover_cny numeric, p_expected_source_treatment_draft_id uuid, p_expected_source_treatment_draft_updated_at timestamp with time zone, p_expected_adjustment_draft_id uuid, p_expected_adjustment_draft_updated_at timestamp with time zone, p_request_correlation_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_business_entity_id uuid;
  v_preview jsonb;
  v_after jsonb;
  v_source public.school_student_settlement_source_treatment_drafts%rowtype;
  v_adjustment public.school_student_settlement_adjustment_drafts%rowtype;
  v_source_matches boolean;
  v_adjustment_matches boolean;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_resolved_adjustment numeric;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'SETTLEMENT_TRUSTED_EDGE_ROLE_REQUIRED';
  end if;
  perform public.school_assert_student_settlement_online_admin(p_actor_user_id);
  if p_student_id is null or p_year_month is null
     or p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
     or v_reason is null then
    raise exception using errcode = '22023', message = 'SETTLEMENT_INPUT_INVALID';
  end if;

  select s.business_entity_id into v_business_entity_id
  from public.school_students s
  where s.id = p_student_id and s.app_type = 'school'
  for share;
  if v_business_entity_id is null then
    raise exception using errcode = '22023', message = 'SETTLEMENT_SCOPE_NOT_UNIQUE';
  end if;

  begin
    perform public.school_tuition_p0a_lock_settlement_mutation_scope(
      p_student_id, v_business_entity_id, p_year_month
    );
  exception when lock_not_available or deadlock_detected then
    raise exception using errcode = '55P03', message = 'SETTLEMENT_SCOPE_BUSY';
  end;
  perform public.school_assert_student_monthly_settlement_online_writable(
    p_student_id, p_year_month, v_business_entity_id, 'save_draft'
  );

  select * into v_source
  from public.school_student_settlement_source_treatment_drafts d
  where d.student_id = p_student_id
    and d.business_entity_id = v_business_entity_id
    and d.year_month = p_year_month and d.status = 'active'
  for update;
  select * into v_adjustment
  from public.school_student_settlement_adjustment_drafts d
  where d.student_id = p_student_id
    and d.business_entity_id = v_business_entity_id
    and d.year_month = p_year_month and d.status = 'active'
  for update;

  v_preview := public.school_preview_student_settlement_adjustment_dialog(
    p_student_id, v_business_entity_id, p_year_month,
    p_source_treatment_mode, p_settlement_exchange_rate,
    p_settlement_exchange_rate_source,
    p_settlement_exchange_rate_effective_date,
    p_adjustment_mode, p_explicit_user_amount_cny
  );
  perform public.school_assert_student_settlement_online_expected_facts(
    v_preview, p_expected_preview_manifest_sha256,
    p_expected_lesson_variance_manifest_sha256, p_expected_source_count,
    p_expected_unused_planned_credit_jpy, p_expected_overage_charge_jpy,
    p_expected_net_lesson_variance_jpy, p_expected_net_lesson_variance_cny,
    p_expected_system_difference_cny, p_expected_final_carryover_cny
  );
  v_resolved_adjustment :=
    (v_preview->'preview'->>'projected_adjustment_amount_cny')::numeric;

  v_source_matches := v_source.id is not null
    and v_source.source_treatment_mode is not distinct from
      v_preview->'preview_expected_facts'->>'source_treatment_mode'
    and v_source.settlement_exchange_rate is not distinct from
      (v_preview->'preview_expected_facts'->>'settlement_exchange_rate')::numeric
    and v_source.settlement_exchange_rate_source is not distinct from
      nullif(v_preview->'preview_expected_facts'->>'settlement_exchange_rate_source', '')
    and v_source.settlement_exchange_rate_effective_date is not distinct from
      (v_preview->'preview_expected_facts'->>'settlement_exchange_rate_effective_date')::date
    and v_source.source_manifest_sha256 is not distinct from
      p_expected_lesson_variance_manifest_sha256
    and v_source.source_count is not distinct from p_expected_source_count
    and v_source.reason is not distinct from v_reason;

  v_adjustment_matches := v_adjustment.id is not null
    and v_adjustment.adjustment_source is not distinct from
      v_preview->'preview_expected_facts'->>'adjustment_mode'
    and v_adjustment.adjustment_amount_cny is not distinct from v_resolved_adjustment
    and v_adjustment.adjustment_reason is not distinct from v_reason
    and v_adjustment.note is not distinct from v_note;

  if v_source_matches and v_adjustment_matches then
    return jsonb_build_object(
      'ok', true, 'idempotent', true,
      'operation', 'save_student_settlement_draft_online_admin_v1',
      'operator_authority', 'authenticated_active_admin_edge_v1',
      'request_correlation_id', p_request_correlation_id,
      'actor_user_id', p_actor_user_id,
      'student_id', p_student_id, 'year_month', p_year_month,
      'business_entity_id', v_business_entity_id,
      'source_treatment_draft_id', v_source.id,
      'source_treatment_draft_updated_at', v_source.updated_at,
      'adjustment_draft_id', v_adjustment.id,
      'adjustment_draft_updated_at', v_adjustment.updated_at,
      'preview_manifest_sha256', p_expected_preview_manifest_sha256,
      'lesson_variance_manifest_sha256', p_expected_lesson_variance_manifest_sha256,
      'authoritative_preview', v_preview,
      'effective_status', 'incomplete'
    );
  end if;

  if not v_source_matches and (
    v_source.id is distinct from p_expected_source_treatment_draft_id
    or (v_source.id is not null and v_source.updated_at is distinct from
      p_expected_source_treatment_draft_updated_at)
  ) then
    raise exception 'SETTLEMENT_SOURCE_DRAFT_STALE';
  end if;
  if not v_adjustment_matches and (
    v_adjustment.id is distinct from p_expected_adjustment_draft_id
    or (v_adjustment.id is not null and v_adjustment.updated_at is distinct from
      p_expected_adjustment_draft_updated_at)
  ) then
    raise exception 'SETTLEMENT_ADJUSTMENT_DRAFT_STALE';
  end if;

  if not v_source_matches then
    perform *
    from public.school_set_student_settlement_source_treatment_draft(
      p_student_id, p_year_month, p_source_treatment_mode,
      p_settlement_exchange_rate, p_settlement_exchange_rate_source,
      p_settlement_exchange_rate_effective_date, v_reason
    );
  end if;
  if not v_adjustment_matches then
    perform *
    from public.school_set_student_monthly_settlement_draft_adjustment(
      p_student_id, p_year_month, p_explicit_user_amount_cny,
      p_adjustment_mode, v_reason, v_note
    );
  end if;

  select * into strict v_source
  from public.school_student_settlement_source_treatment_drafts d
  where d.student_id = p_student_id
    and d.business_entity_id = v_business_entity_id
    and d.year_month = p_year_month and d.status = 'active';
  select * into strict v_adjustment
  from public.school_student_settlement_adjustment_drafts d
  where d.student_id = p_student_id
    and d.business_entity_id = v_business_entity_id
    and d.year_month = p_year_month and d.status = 'active';

  v_after := public.school_preview_student_settlement_adjustment_dialog(
    p_student_id, v_business_entity_id, p_year_month,
    p_source_treatment_mode, p_settlement_exchange_rate,
    p_settlement_exchange_rate_source,
    p_settlement_exchange_rate_effective_date,
    p_adjustment_mode, p_explicit_user_amount_cny
  );
  perform public.school_assert_student_settlement_online_expected_facts(
    v_after, p_expected_preview_manifest_sha256,
    p_expected_lesson_variance_manifest_sha256, p_expected_source_count,
    p_expected_unused_planned_credit_jpy, p_expected_overage_charge_jpy,
    p_expected_net_lesson_variance_jpy, p_expected_net_lesson_variance_cny,
    p_expected_system_difference_cny, p_expected_final_carryover_cny
  );
  if v_source.source_manifest_sha256 is distinct from
       p_expected_lesson_variance_manifest_sha256
     or v_source.source_count is distinct from p_expected_source_count
     or v_adjustment.adjustment_amount_cny is distinct from
       (v_after->'preview'->>'projected_adjustment_amount_cny')::numeric then
    raise exception 'SETTLEMENT_EXPECTED_FACTS_MISMATCH';
  end if;

  return jsonb_build_object(
    'ok', true, 'idempotent', false,
    'operation', 'save_student_settlement_draft_online_admin_v1',
    'operator_authority', 'authenticated_active_admin_edge_v1',
    'request_correlation_id', p_request_correlation_id,
    'actor_user_id', p_actor_user_id,
    'student_id', p_student_id, 'year_month', p_year_month,
    'business_entity_id', v_business_entity_id,
    'source_treatment_draft_id', v_source.id,
    'source_treatment_draft_updated_at', v_source.updated_at,
    'adjustment_draft_id', v_adjustment.id,
    'adjustment_draft_updated_at', v_adjustment.updated_at,
    'preview_manifest_sha256', p_expected_preview_manifest_sha256,
    'lesson_variance_manifest_sha256', p_expected_lesson_variance_manifest_sha256,
    'authoritative_preview', v_after,
    'effective_status', 'incomplete'
  );
end
$function$;

COMMENT ON FUNCTION public.school_save_student_monthly_settlement_draft_online_admin(uuid, uuid, text, text, numeric, text, date, text, numeric, text, text, text, text, integer, numeric, numeric, numeric, numeric, numeric, numeric, uuid, timestamp with time zone, uuid, timestamp with time zone, uuid) IS 'Phase A service_role-only online save wrapper. Revalidates active-admin actor, effective state, scope, manifests, DB amounts, existing draft versions, and semantic idempotency; never locks a settlement.';

-- ===== A. 删除 operator 断言 =====

-- 删除前先确认【没有别的对象在引用它】。
-- 这与「守卫缺失只告警」不矛盾：那条针对的是回滚【不删】守卫的批次；
-- 本批的回滚要【删】这个断言，就必须先确认删的是自己那个、且无人依赖。
DO $refscan$
DECLARE r record; v_def text; v_hits int := 0;
BEGIN
  FOR r IN SELECT p.oid, n.nspname||'.'||p.proname AS fq
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname NOT IN ('pg_catalog','information_schema','pg_toast')
              AND n.nspname NOT LIKE 'pg_temp%' AND n.nspname NOT LIKE 'pg_toast_temp%'
              AND p.prokind IN ('f','p')
              AND p.proname <> 'school_assert_student_settlement_online_operator' LOOP
    BEGIN
      v_def := pg_get_functiondef(r.oid);
    EXCEPTION WHEN OTHERS THEN
      -- ⚠️ 读不到【不等于】没有引用。硬停止，不能当成「没引用」放过去。
      RAISE EXCEPTION 'SETL_RB_REFSCAN_FAILED: 无法读取 % 的定义：%', r.fq, SQLERRM;
    END;
    IF position('school_assert_student_settlement_online_operator' in v_def) > 0 THEN
      v_hits := v_hits + 1;
      RAISE WARNING 'SETL_RB_STILL_REFERENCED: % 仍引用新断言', r.fq;
    END IF;
  END LOOP;
  IF v_hits > 0 THEN
    RAISE EXCEPTION 'SETL_RB_OPER_IN_USE: 仍有 % 个对象引用 school_assert_student_settlement_online_operator，拒绝删除', v_hits;
  END IF;
END
$refscan$;

DROP FUNCTION public.school_assert_student_settlement_online_operator(uuid);

DO $opr$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_assert_student_settlement_online_operator';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'SETL_RB_POST_OPER_EXISTS: school_assert_student_settlement_online_operator 已存在（% 个）—— 可能已部署过', v_n;
  END IF;
  RAISE NOTICE 'SETL_RB_POST: 新断言尚不存在，符合部署前预期';
END
$opr$;

DO $rbpost$
DECLARE v_n int; v_def text; v_md5 text; v_acl text; v_cmt text;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_save_student_monthly_settlement_draft_online_admin';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'SETL_RB_POST_SAVE_ARITY: school_save_student_monthly_settlement_draft_online_admin 有 % 个（应为 1）', v_n;
  END IF;

  SELECT pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid)),
         coalesce(p.proacl::text,''), coalesce(obj_description(p.oid,'pg_proc'),'<NULL>')
    INTO v_def, v_md5, v_acl, v_cmt
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_save_student_monthly_settlement_draft_online_admin';

  IF v_md5 <> '883392cf7493dd05c3b5edc5ebc25de1' THEN
    RAISE EXCEPTION 'SETL_RB_POST_SAVE_MD5: 定义为 %，期望 %', v_md5, '883392cf7493dd05c3b5edc5ebc25de1';
  END IF;
  IF v_acl <> '{postgres=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'SETL_RB_POST_SAVE_ACL: ACL 为 %，期望 %', v_acl, '{postgres=X/postgres,service_role=X/postgres}';
  END IF;
  IF v_cmt <> 'Phase A service_role-only online save wrapper. Revalidates active-admin actor, effective state, scope, manifests, DB amounts, existing draft versions, and semantic idempotency; never locks a settlement.' THEN
    RAISE EXCEPTION 'SETL_RB_POST_SAVE_COMMENT: 注释为 [%]', v_cmt;
  END IF;

  -- 断言「变成了什么」，不只是「变了」
  IF (length(v_def)-length(replace(v_def,'school_assert_student_settlement_online_admin','')))/length('school_assert_student_settlement_online_admin') <> 1 THEN
    RAISE EXCEPTION 'SETL_RB_POST_SAVE_ADMIN_CALLS: admin 断言调用次数不是 1';
  END IF;
  IF (length(v_def)-length(replace(v_def,'school_assert_student_settlement_online_operator','')))/length('school_assert_student_settlement_online_operator') <> 0 THEN
    RAISE EXCEPTION 'SETL_RB_POST_SAVE_OPER_CALLS: operator 断言调用次数不是 0';
  END IF;
  IF (length(v_def)-length(replace(v_def,'authenticated_active_admin_or_operator_edge_v1','')))/length('authenticated_active_admin_or_operator_edge_v1') <> 0 THEN
    RAISE EXCEPTION 'SETL_RB_POST_SAVE_NEW_LABEL: 新 authority 标签出现次数不是 0';
  END IF;
  -- ⚠️ 新标签【包含】旧标签以外的字样，两者互不为子串，计数互不干扰。
  IF (length(v_def)-length(replace(v_def,'authenticated_active_admin_edge_v1','')))/length('authenticated_active_admin_edge_v1') <> 2 THEN
    RAISE EXCEPTION 'SETL_RB_POST_SAVE_OLD_LABEL: 旧 authority 标签出现次数不是 2';
  END IF;

  RAISE NOTICE 'SETL_RB_POST: save 的 md5 / ACL / 注释 / 断言调用 / authority 标签 全部符合预期';
END
$rbpost$;

DO $untouched$
DECLARE b record; v record;
BEGIN
  FOR b IN SELECT * FROM settle_before LOOP
    SELECT md5(pg_get_functiondef(p.oid)) AS md5, coalesce(p.proacl::text,'') AS acl,
           coalesce(obj_description(p.oid,'pg_proc'),'<NULL>') AS cmt,
           p.proisstrict AS strict_, p.proparallel AS par, p.proleakproof AS leak,
           p.procost AS cost_, p.prorows AS rows_, p.prosecdef AS secdef,
           pg_get_userbyid(p.proowner) AS owner_,
           coalesce(array_to_string(p.proconfig,', '),'<NULL>') AS cfg
      INTO v
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=b.b_name;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'SETL_RB_POST_UNTOUCHED_MISSING: % 不见了', b.b_name;
    END IF;
    IF v.md5 <> b.b_md5 OR v.acl <> b.b_acl OR v.cmt <> b.b_cmt
       OR v.strict_ <> b.b_strict OR v.par <> b.b_par OR v.leak <> b.b_leak
       OR v.cost_ <> b.b_cost OR v.rows_ <> b.b_rows OR v.secdef <> b.b_secdef
       OR v.owner_ <> b.b_owner OR v.cfg <> b.b_cfg THEN
      RAISE EXCEPTION 'SETL_RB_POST_UNTOUCHED_DRIFT: % 被改动了 —— 本批不应碰 lock 与 admin 断言', b.b_name;
    END IF;
  END LOOP;
  RAISE NOTICE 'SETL_RB_POST: lock 与 admin 断言逐项未变（锁定仍是管理员专属）';
END
$untouched$;

\if :is_commit
COMMIT;
\echo '>>> 已 COMMIT'
\else
ROLLBACK;
\echo '>>> 已 ROLLBACK（rehearsal）'
\endif
