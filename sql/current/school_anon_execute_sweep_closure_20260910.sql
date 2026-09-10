-- =============================================================================
-- 撤销匿名面：17 个函数的 PUBLIC / anon EXECUTE
--
-- 背景   2026-09-10 全库扫描（Codex 只读取证）在 public schema 找到
--        26 个对 PUBLIC 或 anon 开着 EXECUTE 的函数，分档：
--          甲 1  SECURITY DEFINER + writer + 无身份守卫
--          乙 16 SECURITY DEFINER + reader + 无身份守卫
--          丙 9  非 DEFINER / 有守卫 / 触发器函数（本脚本不动）
--        表与视图的直接授权命中 0 项。
--
-- 甲档   school_update_personal_cash_income_linkage_event_status
--        能改 School↔Cash 联动的同步状态（pending/synced/failed）、
--        Cash transaction ID、重试次数、错误信息，且【不校验调用者身份，
--        也不校验所给的 Cash transaction ID 是否真实存在】。
--        目标表 RLS 未启用。
--        ⇒ 未认证调用者只要拿到有效 event ID，就能篡改对账状态。
--        它篡改的正是「你以为已经对上了」的那个字段，比前两个更难察觉。
--
-- 乙档   两类值得单说：
--        · school_list_personal_cash_account_mappings /
--          school_get_personal_cash_linkage_events
--          返回 Cash 用户与账户标识、账户名称快照、金额与备注 —— 信息泄露面。
--        · 四个月结 summary/preview/adjustment 入口的调用链可到达
--          school_tuition_p0a_lock_settlement_mutation_scope，
--          它取 advisory lock 及四张月结相关表的 SHARE ROW EXCLUSIVE。
--          ⇒ 「无 DML」不等于「无副作用」，匿名者据此可制造锁竞争。
--
-- 本脚本 只撤销 PUBLIC 与 anon 的 EXECUTE。
--        ⛔ 【保留】authenticated 与 service_role ——
--           已知的合法调用方全是登录后的前端，收 authenticated 是另一个
--           需要逐功能评估的问题，不在本次范围。
--        ⛔ 不改函数体、不改 owner、不动业务数据。
--
-- ⚠️ 定义 md5 【不写死】：本轮取证只给了甲档一个 md5。
--    改为在 pre 段【当场记下】、post 段与之比对 —— 同样能证明「只改了权限」，
--    而不必把 16 个没拿到的值猜出来。
--
-- ⚠️ 签名按【名字】解析并断言重载唯一：取证给的是 identity arguments 文本，
--    抄进脚本再解析一次只会多一处出错的机会。
--
-- 用法
--   psql -v ON_ERROR_STOP=1 -f <本文件>
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE anonsweep_target(grade text, proname text) ON COMMIT DROP;
INSERT INTO anonsweep_target(grade, proname) VALUES
  -- 甲：SECURITY DEFINER + writer + 无身份守卫
  ('甲','school_update_personal_cash_income_linkage_event_status'),
  -- 乙：SECURITY DEFINER + reader + 无身份守卫
  ('乙','school_assert_new_business_entity_allowed'),
  ('乙','school_primary_business_entity_id'),
  ('乙','school_get_lesson_credit_remaining_hours'),
  ('乙','school_get_lesson_management_stats'),
  ('乙','school_get_personal_cash_linkage_events'),
  ('乙','school_get_planned_lesson_tuition_history_state'),
  ('乙','school_get_student_monthly_settlement_preview'),
  ('乙','school_get_student_monthly_settlement_summary'),
  ('乙','school_get_student_monthly_settlement_wage_blockers'),
  ('乙','school_list_lesson_management_records_authoritative'),
  ('乙','school_list_open_lesson_credit_sources'),
  ('乙','school_list_personal_cash_account_mappings'),
  ('乙','school_list_student_lesson_credit_balances'),
  ('乙','school_preview_student_settlement_adjustment_dialog'),
  ('乙','school_preview_student_settlement_source_treatment'),
  ('乙','school_resolve_lesson_student_month_authoritative');

-- pre 段记下的事实，post 段拿它比对。定义 md5 不写死，就靠这张表。
CREATE TEMP TABLE anonsweep_before(
  proname text PRIMARY KEY, oid oid, md5 text, acl text) ON COMMIT DROP;

DO $pre$
DECLARE r record; v_oid oid; v_n int; v_acl text; v_md5 text; v_sec boolean; v_own text;
BEGIN
  FOR r IN SELECT * FROM anonsweep_target ORDER BY grade, proname LOOP
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=r.proname;
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'SWEEP_OVERLOAD: public.% 有 % 个重载（应为 1）—— '
        '按名字撤销会打到不该打的那个，拒绝执行', r.proname, v_n;
    END IF;

    SELECT p.oid, md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,''),
           p.prosecdef, pg_get_userbyid(p.proowner)
      INTO v_oid, v_md5, v_acl, v_sec, v_own
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=r.proname;

    IF v_own <> 'postgres' OR v_sec IS NOT TRUE THEN
      RAISE EXCEPTION 'SWEEP_PRE_ATTRS: % owner=% secdef=%  —— 与取证不符',
        r.proname, v_own, v_sec;
    END IF;

    -- 必须【确实】对 PUBLIC 或 anon 开着，否则不是本脚本要处理的对象。
    IF NOT EXISTS (SELECT 1 FROM aclexplode(
                     coalesce((SELECT p2.proacl FROM pg_proc p2 WHERE p2.oid=v_oid),
                              acldefault('f',(SELECT p2.proowner FROM pg_proc p2 WHERE p2.oid=v_oid)))) a
                    WHERE a.grantee IN (0, 'anon'::regrole::oid)
                      AND a.privilege_type='EXECUTE') THEN
      RAISE EXCEPTION 'SWEEP_PRE_NOT_EXPOSED: % 对 PUBLIC 与 anon 都没有 EXECUTE  ACL=%  '
        '—— 可能已被处理过，拒绝继续', r.proname, v_acl;
    END IF;

    -- ⚠️ authenticated / service_role 必须各有【直接】授权条目。
    --    若它们的权限其实靠 PUBLIC 继承，撤掉 PUBLIC 就会静默切断前端或 Edge。
    --    has_function_privilege 会把 PUBLIC 算进去，所以这里只能查 ACL 条目。
    IF NOT EXISTS (SELECT 1 FROM aclexplode(
                     coalesce((SELECT p2.proacl FROM pg_proc p2 WHERE p2.oid=v_oid),
                              acldefault('f',(SELECT p2.proowner FROM pg_proc p2 WHERE p2.oid=v_oid)))) a
                    WHERE a.grantee='authenticated'::regrole::oid AND a.privilege_type='EXECUTE') THEN
      RAISE EXCEPTION 'SWEEP_PRE_NO_DIRECT_AUTHENTICATED: % 的 authenticated 没有直接授权，'
        '当前只靠 PUBLIC 继承 —— 撤销 PUBLIC 会切断前端  ACL=%', r.proname, v_acl;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM aclexplode(
                     coalesce((SELECT p2.proacl FROM pg_proc p2 WHERE p2.oid=v_oid),
                              acldefault('f',(SELECT p2.proowner FROM pg_proc p2 WHERE p2.oid=v_oid)))) a
                    WHERE a.grantee='service_role'::regrole::oid AND a.privilege_type='EXECUTE') THEN
      RAISE EXCEPTION 'SWEEP_PRE_NO_DIRECT_SERVICE_ROLE: % 的 service_role 没有直接授权，'
        '当前只靠 PUBLIC 继承 —— 撤销 PUBLIC 会切断 Edge  ACL=%', r.proname, v_acl;
    END IF;

    INSERT INTO anonsweep_before(proname, oid, md5, acl) VALUES (r.proname, v_oid, v_md5, v_acl);
  END LOOP;
  RAISE NOTICE 'SWEEP: 部署前基线通过（% 个函数：重载唯一、owner、secdef、'
    'PUBLIC/anon 确有 EXECUTE、authenticated 与 service_role 均有直接授权）',
    (SELECT count(*) FROM anonsweep_before);
END
$pre$;

DO $revoke$
DECLARE r record; v_sig text;
BEGIN
  FOR r IN SELECT * FROM anonsweep_before ORDER BY proname LOOP
    SELECT 'public.'||quote_ident(p.proname)||'('||pg_get_function_identity_arguments(p.oid)||')'
      INTO v_sig FROM pg_proc p WHERE p.oid = r.oid;
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', v_sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', v_sig);
  END LOOP;
  RAISE NOTICE 'SWEEP: 已对 % 个函数撤销 PUBLIC 与 anon', (SELECT count(*) FROM anonsweep_before);
END
$revoke$;

DO $post$
DECLARE r record; v_md5 text; v_acl text; v_bad int := 0;
BEGIN
  FOR r IN SELECT * FROM anonsweep_before ORDER BY proname LOOP
    SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,'')
      INTO v_md5, v_acl FROM pg_proc p WHERE p.oid = r.oid;

    -- 只改权限的证明：定义与 pre 段当场记下的完全一致。
    IF v_md5 IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION 'SWEEP_POST_MD5: % 的定义被改动了', r.proname;
    END IF;
    -- PUBLIC 只能用 aclexplode 查；has_function_privilege 查不出它本身。
    IF EXISTS (SELECT 1 FROM aclexplode(
                 coalesce((SELECT p2.proacl FROM pg_proc p2 WHERE p2.oid=r.oid),
                          acldefault('f',(SELECT p2.proowner FROM pg_proc p2 WHERE p2.oid=r.oid)))) a
                WHERE a.grantee = 0 AND a.privilege_type='EXECUTE') THEN
      RAISE EXCEPTION 'SWEEP_POST_PUBLIC_REMAINS: % PUBLIC 仍持有 EXECUTE  ACL=%', r.proname, v_acl;
    END IF;
    -- PUBLIC 撤掉之后，has_function_privilege 对具体角色才是可信的。
    IF has_function_privilege('anon', r.oid, 'EXECUTE') THEN
      RAISE EXCEPTION 'SWEEP_POST_ANON_REMAINS: % anon 仍可执行  ACL=%', r.proname, v_acl;
    END IF;
    IF NOT has_function_privilege('authenticated', r.oid, 'EXECUTE') THEN
      RAISE EXCEPTION 'SWEEP_POST_AUTHENTICATED_LOST: % —— 前端会因此中断', r.proname;
    END IF;
    IF NOT has_function_privilege('service_role', r.oid, 'EXECUTE') THEN
      RAISE EXCEPTION 'SWEEP_POST_SERVICE_ROLE_LOST: % —— Edge 会因此中断', r.proname;
    END IF;
  END LOOP;
  RAISE NOTICE 'SWEEP: % 个函数已关闭匿名面；authenticated 与 service_role 均保留；定义全部未变',
    (SELECT count(*) FROM anonsweep_before);
END
$post$;

COMMIT;
