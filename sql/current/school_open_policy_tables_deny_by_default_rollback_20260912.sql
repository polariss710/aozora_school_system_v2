-- =============================================================================
-- 回滚：恢复 10 张表的全放行 RLS 策略
--
-- 背景  这 10 张表【启用了 RLS】，但各带一条
--         CREATE POLICY ... FOR ALL TO public USING (true) WITH CHECK (true)
--       ⇒ RLS 开着，等于没开。
--
-- ⚠️ 这【不是】现实缺口，是护栏方向反了。
--    Codex 2026-09-12 实时目录取证：
--      · 10 张表全部 0 行，created_at/updated_at 最大值均为 NULL
--      · ACL 仅 {postgres,service_role} —— 没有其他 grantee
--      · anon / authenticated / dashboard_user / supabase_auth_admin
--        的有效读写权限均为 false
--    所以今天够不着。问题在于 public schema 有
--      ALTER DEFAULT PRIVILEGES ... GRANT ALL ON TABLES
--    哪天有人补个授权、或按同样方式新建表，USING(true) 就直接敞开，
--    而「RLS 已启用」看起来还是绿的。
--
-- 本脚本  DROP 这 10 条策略。RLS 保持启用 ⇒ 变成【默认拒绝】。
--
-- 影响面（逐条来自取证，不是推断）
--   · postgres / service_role      BYPASSRLS，不受影响
--   · authenticated / anon         表上零授权，本来就够不着
--   · pg_read_all_data 的 3 个成员  本身都带 BYPASSRLS，不受影响
--     （pg_write_all_data 当前无成员）
--   · 两个 security_invoker 视图
--       school_v_student_month_summary      → student_months
--       school_v_teacher_salary_month_summary → teacher_work_logs
--     authenticated 缺底表 SELECT，**本来就读不通**，删策略不改变这一点。
--     ⚠️ 若将来给底表补 SELECT 授权，届时会拿到 0 行而不是全部
--        —— 那是安全的方向，但需要那时显式加一条合适的策略。
--   · import_batches / import_errors 被
--     school_correct_li_wu_test_lessons_v1 读取，postgres DEFINER，不受影响
--
-- ⛔ 不改  RLS 开关、表授权、owner、列、触发器、注释、业务数据
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
-- ⚠️ 不能用裸 \quit —— 退出码 0 会让自动化把「根本没执行」读成「成功」。
DO $mode$ BEGIN
  RAISE EXCEPTION 'OPOL_MODE_INVALID: 必须指定 -v mode=rehearsal 或 -v mode=commit';
END $mode$;
\endif

-- ⚠️ 回滚把 USING(true) 全放行策略【装回去】。
--    它恢复的不是「更安全的状态」，是本次收紧之前的状态。

BEGIN;

DO $rbpre$
DECLARE
  t record; p record; v_n int; v_rls boolean; v_force boolean; v_acl text; v_rows bigint;
BEGIN
  FOR t IN SELECT * FROM (VALUES
    ('school_actual_lessons','school_allow_all_actual_lessons'),
    ('school_import_batches','school_allow_all_import_batches'),
    ('school_import_errors','school_allow_all_import_errors'),
    ('school_lesson_schedules','school_allow_all_lesson_schedules'),
    ('school_monthly_reports','school_allow_all_monthly_reports'),
    ('school_planned_lessons','school_allow_all_planned_lessons'),
    ('school_schedule_students','school_allow_all_schedule_students'),
    ('school_student_months','school_allow_all_student_months'),
    ('school_student_payments','school_allow_all_student_payments'),
    ('school_teacher_work_logs','school_allow_all_teacher_work_logs')
    ) AS v(tbl, pol)
  LOOP
    SELECT c.relrowsecurity, c.relforcerowsecurity, coalesce(c.relacl::text,'')
      INTO v_rls, v_force, v_acl
      FROM pg_class c WHERE c.oid = ('public.'||t.tbl)::regclass;

    IF v_rls IS NOT TRUE OR v_force IS NOT FALSE THEN
      RAISE EXCEPTION 'OPOL_RB_RLS: % rowsecurity=% force=%（期望 t / f）', t.tbl, v_rls, v_force;
    END IF;
    IF v_acl <> '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}' THEN
      RAISE EXCEPTION 'OPOL_RB_ACL: % 的 ACL 为 %，期望 %', t.tbl, v_acl, '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}';
    END IF;

    -- 取证时 10 张表全部 0 行。
    EXECUTE format('SELECT count(*) FROM public.%I', t.tbl) INTO v_rows;
    IF v_rows <> 0 THEN
      RAISE WARNING 'OPOL_RB_ROWS: % 有 % 行（取证时为 0）—— 仍继续回滚', t.tbl, v_rows;
    END IF;

    SELECT count(*) INTO v_n FROM pg_policies
     WHERE schemaname='public' AND tablename=t.tbl;
    IF v_n <> 0 THEN
      RAISE EXCEPTION 'OPOL_RB_POLICY_COUNT: % 上有 % 条策略（期望 0）', t.tbl, v_n;
    END IF;
  END LOOP;
  RAISE NOTICE 'OPOL_RB: 10 张表的 RLS 开关 / ACL / 行数 / 策略集合 全部符合预期';
END
$rbpre$;

-- ===== 还原 10 条策略（逐字节同生产形状）=====
CREATE POLICY school_allow_all_actual_lessons ON public.school_actual_lessons
  AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY school_allow_all_import_batches ON public.school_import_batches
  AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY school_allow_all_import_errors ON public.school_import_errors
  AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY school_allow_all_lesson_schedules ON public.school_lesson_schedules
  AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY school_allow_all_monthly_reports ON public.school_monthly_reports
  AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY school_allow_all_planned_lessons ON public.school_planned_lessons
  AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY school_allow_all_schedule_students ON public.school_schedule_students
  AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY school_allow_all_student_months ON public.school_student_months
  AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY school_allow_all_student_payments ON public.school_student_payments
  AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);
CREATE POLICY school_allow_all_teacher_work_logs ON public.school_teacher_work_logs
  AS PERMISSIVE FOR ALL TO public USING (true) WITH CHECK (true);

DO $rbpost$
DECLARE
  t record; p record; v_n int; v_rls boolean; v_force boolean; v_acl text; v_rows bigint;
BEGIN
  FOR t IN SELECT * FROM (VALUES
    ('school_actual_lessons','school_allow_all_actual_lessons'),
    ('school_import_batches','school_allow_all_import_batches'),
    ('school_import_errors','school_allow_all_import_errors'),
    ('school_lesson_schedules','school_allow_all_lesson_schedules'),
    ('school_monthly_reports','school_allow_all_monthly_reports'),
    ('school_planned_lessons','school_allow_all_planned_lessons'),
    ('school_schedule_students','school_allow_all_schedule_students'),
    ('school_student_months','school_allow_all_student_months'),
    ('school_student_payments','school_allow_all_student_payments'),
    ('school_teacher_work_logs','school_allow_all_teacher_work_logs')
    ) AS v(tbl, pol)
  LOOP
    SELECT c.relrowsecurity, c.relforcerowsecurity, coalesce(c.relacl::text,'')
      INTO v_rls, v_force, v_acl
      FROM pg_class c WHERE c.oid = ('public.'||t.tbl)::regclass;

    IF v_rls IS NOT TRUE OR v_force IS NOT FALSE THEN
      RAISE EXCEPTION 'OPOL_RB_POST_RLS: % rowsecurity=% force=%（期望 t / f）', t.tbl, v_rls, v_force;
    END IF;
    IF v_acl <> '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}' THEN
      RAISE EXCEPTION 'OPOL_RB_POST_ACL: % 的 ACL 为 %，期望 %', t.tbl, v_acl, '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}';
    END IF;

    -- 取证时 10 张表全部 0 行。
    EXECUTE format('SELECT count(*) FROM public.%I', t.tbl) INTO v_rows;
    IF v_rows <> 0 THEN
      RAISE WARNING 'OPOL_RB_POST_ROWS: % 有 % 行（取证时为 0）—— 仍继续回滚', t.tbl, v_rows;
    END IF;

    SELECT count(*) INTO v_n FROM pg_policies
     WHERE schemaname='public' AND tablename=t.tbl;
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'OPOL_RB_POST_POLICY_COUNT: % 上有 % 条策略（期望 1）', t.tbl, v_n;
    END IF;

    SELECT * INTO p FROM pg_policies
     WHERE schemaname='public' AND tablename=t.tbl AND policyname=t.pol;
    -- ⚠️ 先查 FOUND：策略总数对得上、但被同名以外的策略顶替时，
    --    p 各列全为 NULL，`NULL <> '...'` 求值为 NULL，IF 不进异常分支。
    IF NOT FOUND THEN
      RAISE EXCEPTION 'OPOL_RB_POST_POLICY_MISSING: % 上找不到策略 %', t.tbl, t.pol;
    END IF;
    IF p.permissive <> 'PERMISSIVE' OR p.cmd <> 'ALL'
       OR p.roles::text <> '{public}'
       OR p.qual IS DISTINCT FROM 'true' OR p.with_check IS DISTINCT FROM 'true' THEN
      RAISE EXCEPTION 'OPOL_RB_POST_POLICY_SHAPE: % 的策略形状不符  permissive=% cmd=% roles=% qual=% check=%',
        t.tbl, p.permissive, p.cmd, p.roles::text, p.qual, p.with_check;
    END IF;
  END LOOP;
  RAISE NOTICE 'OPOL_RB_POST: 10 张表的 RLS 开关 / ACL / 行数 / 策略集合 全部符合预期';
END
$rbpost$;

\if :is_commit
COMMIT;
\echo '>>> 已 COMMIT'
\else
ROLLBACK;
\echo '>>> 已 ROLLBACK（rehearsal）'
\endif
