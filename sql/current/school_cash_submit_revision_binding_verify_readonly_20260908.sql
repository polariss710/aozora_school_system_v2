-- =============================================================================
-- Cash 提交 revision 绑定：部署后只读验收
--
-- 【纯只读】。跑在服务端强制的 READ ONLY 事务里。
-- 用法：psql -v ON_ERROR_STOP=1 -f <本文件>
-- =============================================================================
\set ON_ERROR_STOP on
\echo '=== Cash revision 绑定：部署后只读验收 ==='

-- READ ONLY 禁 CREATE TABLE 但允许写临时表 ⇒ 建表放在事务外
DROP TABLE IF EXISTS pg_temp.cv_base;
CREATE TEMP TABLE cv_base(income_id uuid, bill_id uuid, active_revision_id uuid);

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

DO $cb$
DECLARE
  v_md5 text; v_owner text; v_secdef boolean; v_cfg text; v_strict boolean;
  v_par text; v_leak boolean; v_cost real; v_rows real; v_acl text; v_cmt text; v_res text;
BEGIN
  IF to_regprocedure('public.school_get_cash_income_submission_preflight(uuid[])') IS NULL THEN
    RAISE EXCEPTION 'CB_POST_MISSING: preflight 不存在';
  END IF;
  SELECT md5(pg_get_functiondef(to_regprocedure('public.school_get_cash_income_submission_preflight(uuid[])'))) INTO v_md5;
  IF v_md5 <> '621ae46e9bbc2a17a8e65c7d4521eb2f' THEN RAISE EXCEPTION 'CB_POST_MD5: 得 % 期望 %', v_md5, '621ae46e9bbc2a17a8e65c7d4521eb2f'; END IF;
    SELECT p.proowner::regrole::text, p.prosecdef, coalesce(array_to_string(p.proconfig,','),''),
           p.proisstrict, p.proparallel::text, p.proleakproof, p.procost, p.prorows,
           coalesce(p.proacl::text,''), obj_description(p.oid,'pg_proc'),
           pg_get_function_result(p.oid)
      INTO v_owner, v_secdef, v_cfg, v_strict, v_par, v_leak, v_cost, v_rows, v_acl, v_cmt, v_res
      FROM pg_proc p WHERE p.oid = to_regprocedure('public.school_get_cash_income_submission_preflight(uuid[])');
  -- DROP 会清掉 ACL / COMMENT，且 postgres 在 public 建函数的默认 ACL 恰好也含
  -- service_role —— 但【不能依赖默认权限碰巧等于目标值】，必须显式设置并逐项断言。
  IF v_owner  <> 'postgres'          THEN RAISE EXCEPTION 'CB_POST_OWNER: %', v_owner; END IF;
  IF v_secdef IS NOT TRUE            THEN RAISE EXCEPTION 'CB_POST_SECDEF: %', v_secdef; END IF;
  IF v_cfg    <> 'search_path=public' THEN RAISE EXCEPTION 'CB_POST_PROCONFIG: %', v_cfg; END IF;
  IF v_strict IS NOT FALSE           THEN RAISE EXCEPTION 'CB_POST_ISSTRICT: %', v_strict; END IF;
  IF v_par    <> 'u'                 THEN RAISE EXCEPTION 'CB_POST_PARALLEL: %', v_par; END IF;
  IF v_leak   IS NOT FALSE           THEN RAISE EXCEPTION 'CB_POST_LEAKPROOF: %', v_leak; END IF;
  IF v_cost   <> 100                 THEN RAISE EXCEPTION 'CB_POST_COST: %', v_cost; END IF;
  IF v_rows   <> 1000                THEN RAISE EXCEPTION 'CB_POST_ROWS: %', v_rows; END IF;
  IF v_acl    <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'            THEN RAISE EXCEPTION 'CB_POST_ACL: %', v_acl; END IF;
  IF v_cmt IS DISTINCT FROM 'Read-only server-authoritative Cash submission classification and frozen tuition payment display facts.' THEN RAISE EXCEPTION 'CB_POST_COMMENT: %', coalesce(v_cmt,'<NULL>'); END IF;
  IF v_res    <> 'TABLE(income_record_id uuid, classification text, eligible boolean, gate_state text, payment_currency text, payment_amount numeric, payment_exchange_rate numeric, previous_carryover_cny numeric, latest_linkage_status text, latest_cash_request_status text, active_generation_revision_id uuid)'            THEN RAISE EXCEPTION 'CB_POST_RESULT: %', v_res; END IF;

  RAISE NOTICE 'CV §1: 定义 / 属性 / ACL / COMMENT / 返回契约 —— 通过';
END $cb$;

-- 基线仍【直接查 revision 表】建立，不取自被测的 preflight
INSERT INTO cv_base
SELECT i.id, b.id, r.id
FROM public.school_income_records i
JOIN public.school_student_tuition_bills b
  ON b.id = i.source_id AND b.id = i.tuition_bill_id
JOIN public.school_student_tuition_generation_revisions r
  ON r.tuition_bill_id = b.id AND r.lifecycle_status = 'active'
WHERE i.source_type = 'student_tuition_bill' AND i.status = 'pending';

DO $cb$
DECLARE v_n bigint; v_bad bigint;
BEGIN
  -- 每笔 income 必须【恰好一个】 active revision。
  -- 缺了这条，两个 active revision 时 cv_base 会出两行，
  -- 配对比较照样「相等」—— 那是真空通过。
  SELECT count(*) INTO v_bad FROM (
    SELECT i.id
    FROM public.school_income_records i
    JOIN public.school_student_tuition_bills b
      ON b.id = i.source_id AND b.id = i.tuition_bill_id
    LEFT JOIN public.school_student_tuition_generation_revisions r
      ON r.tuition_bill_id = b.id AND r.lifecycle_status = 'active'
    WHERE i.source_type = 'student_tuition_bill' AND i.status = 'pending'
    GROUP BY i.id HAVING count(r.id) <> 1
  ) x;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'CV_REVISION_CARDINALITY: % 笔 pending income 的 active revision 不是恰好一个', v_bad;
  END IF;

  SELECT count(*) INTO v_n FROM cv_base;
  RAISE NOTICE 'CV §2: 当前 pending 学费 income % 笔', v_n;
  IF v_n = 0 THEN
    RAISE WARNING 'CV_COVERAGE_ABSENT: 无 pending 样本，【值正确性未验证】（不是通过）';
    RETURN;
  END IF;

  SELECT count(*) INTO v_bad
  FROM public.school_get_cash_income_submission_preflight(
         (SELECT array_agg(income_id) FROM cv_base)) pf
  JOIN cv_base b ON b.income_id = pf.income_record_id
  WHERE pf.active_generation_revision_id IS DISTINCT FROM b.active_revision_id;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'CV_VALUE_MISMATCH: % 笔的新列与 revision 表不符', v_bad;
  END IF;

  SELECT count(*) INTO v_bad
  FROM public.school_get_cash_income_submission_preflight(
         (SELECT array_agg(income_id) FROM cv_base)) pf
  WHERE pf.active_generation_revision_id IS NOT NULL;
  IF v_bad = 0 THEN
    RAISE EXCEPTION 'CV_ALL_NULL: 无非空样本，值正确性未验证';
  END IF;
  RAISE NOTICE 'CV §2: 新列与 revision 表逐笔一致（非空 % 笔）—— 通过', v_bad;
END $cb$;

\echo ''
\echo '--- 当前 pending 学费 income 的 revision 对照 ---'
SELECT b.income_id, b.active_revision_id AS via_revision_table,
       pf.active_generation_revision_id  AS via_preflight
FROM cv_base b
LEFT JOIN public.school_get_cash_income_submission_preflight(
       (SELECT array_agg(income_id) FROM cv_base)) pf
  ON pf.income_record_id = b.income_id
ORDER BY b.income_id;

ROLLBACK;
DROP TABLE IF EXISTS pg_temp.cv_base;
\echo ''
\echo '=== 只读验收结束（未写入任何业务数据）==='
\echo '⚠️ 仍未由本脚本覆盖：HTTP 层可见性、Edge 负例的两库零写入证明。'
