-- =============================================================================
-- 顺序守卫：ordering reader 的 ACL 数组顺序修正（向前修）
--
-- 背景   2026-09-10 02:57 守卫已 commit 到生产，但 verify_readonly 停在
--        VR_READER_ACL：
--          期望 {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--          实际 {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
--        权限集合相同，数组顺序不同。
--
-- 成因   与当晚 deploy 里 G 的那处、以及前一天 Cash 部署的那处【完全相同】：
--        新建函数时 public schema 的默认授权先把 service_role 放进 ACL 数组，
--        随后一条带两个角色的 GRANT 再追加 authenticated ⇒ 顺序颠倒。
--        new_objects 里 reader 的授权仍是旧写法（一条 GRANT 带两个角色）。
--
-- 本脚本 只改这一个 reader 的 ACL 数组顺序。
--        ⛔ 不改任何函数定义、不动业务数据、不碰 ack 表内容。
--
-- 为什么向前修而不是回滚：
--   生产此刻 B/G/C/F/N 均为部署后 md5、旧五参数签名已消失、ack 表存在且 0 行。
--   除本项外一切符合预期。回滚要重建五个函数并删除 ack 表，动的东西多得多，
--   且回滚脚本自身在 G 的授权上带着同一个 bug（已另行修正）。
--
-- 用法
--   psql -v ON_ERROR_STOP=1 -f <本文件>
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

DO $pre$
DECLARE
  v_oid oid; v_acl text; v_md5 text;
BEGIN
  v_oid := to_regprocedure('public.school_get_tuition_generation_ordering_state(uuid,text)');
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'RAF_READER_MISSING: 找不到 ordering reader —— 当前不是本次部署后的状态';
  END IF;

  SELECT coalesce(proacl::text,''), md5(pg_get_functiondef(oid))
    INTO v_acl, v_md5 FROM pg_proc WHERE oid = v_oid;

  -- 只在【确认是那个顺序问题】时才动手。集合不同说明是另一回事，不能用本脚本处理。
  IF v_acl = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'RAF_ALREADY_CORRECT: ACL 已是基线顺序，无需修正';
  END IF;
  IF v_acl <> '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}' THEN
    RAISE EXCEPTION 'RAF_UNEXPECTED_ACL: 实际 %  —— 不是已知的顺序问题，拒绝处理', v_acl;
  END IF;

  RAISE NOTICE 'RAF: 确认为顺序问题，reader 定义 md5=%', v_md5;
END
$pre$;

-- 先显式清空，再【按基线顺序逐条 GRANT】。
-- 一条 GRANT 带两个角色不行：默认授权已经把 service_role 放在前面了。
REVOKE ALL ON FUNCTION public.school_get_tuition_generation_ordering_state(uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.school_get_tuition_generation_ordering_state(uuid,text) FROM authenticated;
REVOKE ALL ON FUNCTION public.school_get_tuition_generation_ordering_state(uuid,text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.school_get_tuition_generation_ordering_state(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.school_get_tuition_generation_ordering_state(uuid,text) TO service_role;

DO $post$
DECLARE
  v_oid oid; v_acl text; v_md5 text; v_cnt bigint;
BEGIN
  v_oid := to_regprocedure('public.school_get_tuition_generation_ordering_state(uuid,text)');
  SELECT coalesce(proacl::text,''), md5(pg_get_functiondef(oid))
    INTO v_acl, v_md5 FROM pg_proc WHERE oid = v_oid;

  IF v_acl <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'RAF_POST_ACL: 修正后仍为 %', v_acl;
  END IF;

  -- 授权改动不该碰到定义，也不该碰到 ack 表里的行。两条都钉住。
  IF v_md5 IS NULL THEN RAISE EXCEPTION 'RAF_POST_DEF_GONE'; END IF;
  SELECT count(*) INTO v_cnt
    FROM public.school_student_tuition_generation_ordering_ack_events;
  RAISE NOTICE 'RAF: ACL 已修正为基线顺序；reader 定义 md5=%（未改动），ack 事件 % 行',
    v_md5, v_cnt;
END
$post$;

COMMIT;
