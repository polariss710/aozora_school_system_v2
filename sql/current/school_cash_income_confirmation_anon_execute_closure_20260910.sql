-- =============================================================================
-- 收紧两个 Cash income writer 的 EXECUTE：撤销 PUBLIC / anon / authenticated
--
-- 背景   2026-09-10 只读取证发现：
--          school_create_cash_income_confirmation   （18 参数）
--          school_request_cash_income_confirmation  （6 参数）
--        两者 ACL 均为
--          {=X/postgres,postgres=X/postgres,anon=X/postgres,
--           authenticated=X/postgres,service_role=X/postgres}
--        即 PUBLIC 与 anon 都持有 EXECUTE。两者均 SECURITY DEFINER、
--        以 postgres 执行，而生产 postgres 具有 BYPASSRLS；
--        函数体内【没有任何身份、membership 或角色检查】。
--
--        收入表虽启用 RLS 但未 FORCE，linkage 表未启用 RLS，
--        既有触发器只做业务隔离、不要求已认证用户。
--        ⇒ 满足业务约束的【未认证】请求存在成功写入
--          school_income_records 与 school_personal_cash_income_linkage_events
--          的路径。
--
--        ⚠️ 它们【不连 Cash、不创建 Cash 流水、不转移资金】。
--           风险是未认证的 School 写入与返回值中的信息，不是资金损失。
--
-- 调用方 create：线上 request-cash-income-confirmation v14 仍在调用，
--                但用的是 service_role 客户端，且在 admin 校验【之后】。
--        request(6 参数)：未发现任何现存调用方；Edge 用的是
--                另一个 _for_record 入口。仓库 js/ 对两者命中数为 0。
--        ⇒ 保留 postgres 与 service_role 即可，不影响现有链路。
--
-- 本脚本 只改 EXECUTE 授权。⛔ 不改函数体、不改 owner、不动业务数据。
--        两个函数的定义 md5 前后必须【完全一致】——脚本对此有断言。
--
-- ⚠️ 签名【按名字解析】，不写死参数类型：取证只给了参数个数，
--    把类型表猜出来再写进脚本，就是把没验证的东西当基线。
--    改用 proname + 重载唯一断言，猜错的可能性从源头消掉。
--
-- 用法
--   psql -v ON_ERROR_STOP=1 -f <本文件>
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE anonfix_target ON COMMIT DROP AS
SELECT * FROM (VALUES
  ('create', 'school_create_cash_income_confirmation',  18, '4b5f0f6c0ab8b3be5f73b6f684e2fa07'),
  ('request','school_request_cash_income_confirmation',  6, 'b13f6a2d33627c8afd893eaba5e33ff1')
) AS t(code, proname, nargs, md5);

DO $pre$
DECLARE
  r record; v_oid oid; v_n int; v_acl text; v_md5 text;
  v_own text; v_sec boolean; v_args int;
BEGIN
  FOR r IN SELECT * FROM anonfix_target LOOP
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=r.proname;
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'ANONFIX_OVERLOAD: public.% 有 % 个重载（应为 1）—— '
        '按名字撤销会打到不该打的那个，拒绝执行', r.proname, v_n;
    END IF;

    SELECT p.oid, coalesce(p.proacl::text,''), md5(pg_get_functiondef(p.oid)),
           pg_get_userbyid(p.proowner), p.prosecdef, p.pronargs
      INTO v_oid, v_acl, v_md5, v_own, v_sec, v_args
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=r.proname;

    IF v_args <> r.nargs THEN
      RAISE EXCEPTION 'ANONFIX_PRE_NARGS: % 有 % 个参数  期望 %', r.code, v_args, r.nargs;
    END IF;
    IF v_md5 <> r.md5 THEN
      RAISE EXCEPTION 'ANONFIX_PRE_MD5: % 得 %  期望 %', r.code, v_md5, r.md5;
    END IF;
    IF v_own <> 'postgres' OR v_sec IS NOT TRUE THEN
      RAISE EXCEPTION 'ANONFIX_PRE_ATTRS: % owner=% secdef=%', r.code, v_own, v_sec;
    END IF;
    -- 前置条件是【谁持有 EXECUTE】，不是 ACL 数组长什么样。
    -- 按字符串比对会因数组顺序不同而误拒 —— 授权顺序不同就会换序，
    -- 而顺序不改变任何人的权限。这里问权限系统本身。
    IF NOT EXISTS (SELECT 1 FROM aclexplode(
                     coalesce((SELECT p2.proacl FROM pg_proc p2 WHERE p2.oid=v_oid),
                              acldefault('f',(SELECT p2.proowner FROM pg_proc p2 WHERE p2.oid=v_oid)))) a
                    WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN
      RAISE EXCEPTION 'ANONFIX_PRE_NO_PUBLIC: % PUBLIC 并不持有 EXECUTE，'
        '当前 ACL=%  —— 不是取证到的那个敞口，拒绝处理', r.code, v_acl;
    END IF;
    -- ⚠️ has_function_privilege 把 PUBLIC 的授权算进去：PUBLIC 持有 EXECUTE 时，
    --    任何角色查出来都是「有」。所以这里不能用它判 service_role ——
    --    必须确认 service_role 有【直接】授权条目，否则撤掉 PUBLIC 之后
    --    Edge 会因为失去继承而中断。
    IF NOT EXISTS (SELECT 1 FROM aclexplode(
                     coalesce((SELECT p2.proacl FROM pg_proc p2 WHERE p2.oid=v_oid),
                              acldefault('f',(SELECT p2.proowner FROM pg_proc p2 WHERE p2.oid=v_oid)))) a
                    WHERE a.grantee = 'service_role'::regrole::oid
                      AND a.privilege_type = 'EXECUTE') THEN
      RAISE EXCEPTION 'ANONFIX_PRE_NO_DIRECT_SERVICE_ROLE: % service_role 没有【直接】的 '
        'EXECUTE 授权，当前只靠 PUBLIC 继承。撤销 PUBLIC 会中断 Edge  ACL=%', r.code, v_acl;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM aclexplode(
                     coalesce((SELECT p2.proacl FROM pg_proc p2 WHERE p2.oid=v_oid),
                              acldefault('f',(SELECT p2.proowner FROM pg_proc p2 WHERE p2.oid=v_oid)))) a
                    WHERE a.grantee IN ('anon'::regrole::oid, 'authenticated'::regrole::oid)
                      AND a.privilege_type = 'EXECUTE') THEN
      RAISE EXCEPTION 'ANONFIX_PRE_GRANTS: % anon 与 authenticated 都没有直接授权，'
        '当前 ACL=%  —— 不是取证到的形状', r.code, v_acl;
    END IF;
  END LOOP;
  RAISE NOTICE 'ANONFIX: 部署前基线通过（重载唯一、参数个数、定义、owner、secdef、ACL 均与取证一致）';
END
$pre$;

-- 撤销。逐个角色分开执行，与 ACL 数组顺序无关（这里是【撤销】，不重建授权，
-- 所以不存在前两天那个「默认授权把 service_role 放回数组前面」的问题）。
DO $revoke$
DECLARE r record; v_sig text;
BEGIN
  FOR r IN SELECT * FROM anonfix_target LOOP
    SELECT 'public.'||quote_ident(p.proname)||'('||pg_get_function_identity_arguments(p.oid)||')'
      INTO v_sig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=r.proname;
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', v_sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', v_sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', v_sig);
    RAISE NOTICE 'ANONFIX: 已撤销 %', v_sig;
  END LOOP;
END
$revoke$;

DO $post$
DECLARE r record; v_oid oid; v_acl text; v_md5 text;
BEGIN
  FOR r IN SELECT * FROM anonfix_target LOOP
    SELECT p.oid, coalesce(p.proacl::text,''), md5(pg_get_functiondef(p.oid))
      INTO v_oid, v_acl, v_md5
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=r.proname;

    -- 授权改动不该碰定义。这条是本脚本「只改权限」的证明。
    IF v_md5 <> r.md5 THEN
      RAISE EXCEPTION 'ANONFIX_POST_MD5: % 定义被改动了  得 %', r.code, v_md5;
    END IF;
    -- 同样按语义判，不按数组顺序。PUBLIC 也要单独查：has_function_privilege
    -- 对具体角色返回的是【含 PUBLIC 继承】的结果，单看角色查不出 PUBLIC 本身。
    IF EXISTS (SELECT 1 FROM aclexplode(
                 coalesce((SELECT p2.proacl FROM pg_proc p2 WHERE p2.oid=v_oid),
                          acldefault('f',(SELECT p2.proowner FROM pg_proc p2 WHERE p2.oid=v_oid)))) a
                WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN
      RAISE EXCEPTION 'ANONFIX_POST_PUBLIC_REMAINS: % PUBLIC 仍持有 EXECUTE  ACL=%', r.code, v_acl;
    END IF;
    IF has_function_privilege('anon', v_oid, 'EXECUTE')
       OR has_function_privilege('authenticated', v_oid, 'EXECUTE') THEN
      RAISE EXCEPTION 'ANONFIX_POST_STILL_GRANTED: % 仍对 anon 或 authenticated 开放', r.code;
    END IF;
    IF NOT has_function_privilege('service_role', v_oid, 'EXECUTE') THEN
      RAISE EXCEPTION 'ANONFIX_POST_SERVICE_ROLE_LOST: % —— Edge 会因此中断', r.code;
    END IF;
  END LOOP;
  RAISE NOTICE 'ANONFIX: anon 与 authenticated 的 EXECUTE 已撤销；service_role 保留；两个定义未变';
END
$post$;

COMMIT;
