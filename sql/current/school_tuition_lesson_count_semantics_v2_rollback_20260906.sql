-- ===========================================================================
-- 学费 lesson_count 语义修复：回滚脚本 / 2026-09-06
-- ===========================================================================
--
-- 与部署脚本配套：sql/current/school_tuition_lesson_count_semantics_v2_deploy_20260906.sql
--
-- 【两种回滚范围 —— 不是随便选的，取决于生产里有没有 v2 账单（设计 §9.2）】
--
--   scope=full             还原全部六个函数到 2026-09-06 12:05 JST 生产基线。
--                          **仅当生产不存在任何 v2 账单/收入时允许。**
--                          v2 账单的明细序号被重编为周内 1/2（例如 4 行 1,2,1,2：
--                          条数 4、序号和 6），还原旧 sum validator 后它会要求 4=6，
--                          且失败不限于 Reissue——普通 generate 的幂等返回校验、
--                          Void preflight 等任何触发 validator 的路径都会失败。
--                          脚本会自己数，数到 v2 数据就硬停止，不靠人记得。
--
--   scope=generation_only  只还原候选 reader / builder / 三个 writer 五个函数，
--                          **保留 v1/v2 兼容 validator**。
--                          回滚后：老 v2 账单带 v2 键走 count 分支照常通过；
--                          新账单不带键走 v1 分支、builder 也回到 sum，二者自洽。
--
--   个别 v2 账单恰好 sum=count，不能据此证明整体回退安全。
--   不接受用「人工处理」替代兼容契约。
--
-- 【用法】
--   psql "$DB_URL" -v mode=rehearsal -v scope=generation_only -f <本文件>
--   psql "$DB_URL" -v mode=commit    -v scope=full            -f <本文件>
--   默认 mode=rehearsal、scope=generation_only（两个默认值都取更保守的一侧）。
--
-- 【还原保真度】被还原的函数正文是生产 2026-09-06 12:05:12 JST 的原文逐字节副本，
--   脚本末尾断言 md5(pg_get_functiondef(oid)) 精确等于审查报告 Appendix C 的值。
-- ===========================================================================

\set ON_ERROR_STOP on
\timing on

\if :{?mode}
\else
\set mode rehearsal
\endif
\if :{?scope}
\else
\set scope generation_only
\endif

\echo ''
\echo '================================================================'
\echo 'lesson_count 语义修复  回滚'
\echo 'mode =' :mode '/ scope =' :scope
\echo '================================================================'

BEGIN;
SET LOCAL statement_timeout = '300s';
SET LOCAL lock_timeout = '15s';
SET LOCAL idle_in_transaction_session_timeout = '600s';

-- ---------------------------------------------------------------------------
-- §0 运行参数校验
--   psql 不会在美元引用内做变量插值，所以 mode 先落临时表再判断。
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE lc2_run(mode text NOT NULL, scope text NOT NULL) ON COMMIT DROP;
INSERT INTO lc2_run(mode,scope) VALUES (:'mode',:'scope');

DO $do$
BEGIN
  IF (SELECT mode FROM lc2_run) NOT IN ('rehearsal','commit') THEN
    RAISE EXCEPTION 'LC2_MODE_INVALID: mode 只接受 rehearsal 或 commit，收到 %',
      (SELECT mode FROM lc2_run);
  END IF;
END
$do$;

DO $do$
BEGIN
  IF (SELECT scope FROM lc2_run) NOT IN ('full','generation_only') THEN
    RAISE EXCEPTION 'LC2_SCOPE_INVALID: scope 只接受 full 或 generation_only，收到 %',
      (SELECT scope FROM lc2_run);
  END IF;
END
$do$;

-- ---------------------------------------------------------------------------
-- §1 目标函数清单与审查基线 md5
--   基线来源：lesson-count-design-review-20260906-12:05-report.md Appendix C
--   （SQL md5(pg_get_functiondef(oid))，取证时刻 2026-09-06 12:05:12 JST）
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE lc2_target(
  fn_key       text PRIMARY KEY,
  signature    text NOT NULL,
  baseline_md5 text NOT NULL,
  purpose      text NOT NULL,
  before_md5   text,
  after_md5    text,
  in_scope     boolean
) ON COMMIT DROP;

INSERT INTO lc2_target(fn_key,signature,baseline_md5,purpose) VALUES
 ('candidates','public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)','438b4619ad46b4501199ad3bae45ff87','候选判定：删除 lesson_count 必填两行'),
 ('build','public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)','4e7ddd85b884bf3607f14bb905bd9ed6','builder：新增 ranked_candidates，序号重编 + total 改 count(*)'),
 ('validator','public.school_validate_tuition_bill_lessons_for_bill(uuid)','bb9ff1e1d6e259fafdd64b392a740c3a','validator：v1/v2 版本契约 + bill/income 版本一致性'),
 ('base_core_v1','public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text)','8c7a55f4c9c855598c2df7cc931df943','writer 首次生成：bill/income 快照标 v2'),
 ('next_revision_core','public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text)','28842924bd509321ef21cae10080d238','writer 次轮生成：bill/income 快照标 v2'),
 ('next_revision_p0e_core','public.school_generate_student_tuition_next_revision_p0e_core(uuid,uuid,uuid,text,numeric,text,text,text)','359cd91dff91769d4ad4beaadb172e90','writer P0-E：bill/income 快照标 v2');

-- generation_only 时保留兼容 validator，其余五个函数还原
UPDATE lc2_target SET in_scope = CASE
  WHEN (SELECT scope FROM lc2_run) = 'full' THEN true
  ELSE fn_key <> 'validator' END;

\echo '--- 本次回滚范围 ---'
SELECT fn_key AS "函数", in_scope AS "还原", signature AS "签名"
FROM lc2_target ORDER BY in_scope DESC, fn_key;

-- ---------------------------------------------------------------------------
-- §2 期望标记表
--   variant='v2' 用作**回滚前**的状态确认（确认我们确实在从 v2 往回退）
--   variant='v1' 用作**回滚后**的状态确认（仅对 in_scope 的函数）
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE lc2_marker(
  fn_key text NOT NULL, variant text NOT NULL,
  needle text NOT NULL, must_exist boolean NOT NULL
) ON COMMIT DROP;

INSERT INTO lc2_marker(fn_key,variant,needle,must_exist) VALUES
  ('candidates','v2','evidence.lesson_count IS NOT NULL',false),
  ('candidates','v2','evidence.lesson_count > 0',false),
  ('build','v2','ranked_candidates',true),
  ('build','v2','bill_lesson_ordinal',true),
  ('build','v2','source_start_time',true),
  ('build','v2','count(*)::integer AS lesson_count',true),
  ('build','v2','sum(detail.lesson_count)',false),
  ('validator','v2','lesson_count_semantics',true),
  ('validator','v2','v_expected_lesson_total',true),
  ('validator','v2','TUITION_LESSON_COUNT_SEMANTICS_DIVERGED',true),
  ('validator','v2','DISTINCT FROM v_lesson_count',false),
  ('base_core_v1','v2','lesson_count_semantics',true),
  ('next_revision_core','v2','lesson_count_semantics',true),
  ('next_revision_p0e_core','v2','lesson_count_semantics',true),
  ('candidates','v1','evidence.lesson_count IS NOT NULL',true),
  ('candidates','v1','evidence.lesson_count > 0',true),
  ('build','v1','sum(detail.lesson_count)',true),
  ('build','v1','ranked_candidates',false),
  ('build','v1','bill_lesson_ordinal',false),
  ('validator','v1','DISTINCT FROM v_lesson_count',true),
  ('validator','v1','lesson_count_semantics',false),
  ('base_core_v1','v1','lesson_count_semantics',false),
  ('next_revision_core','v1','lesson_count_semantics',false),
  ('next_revision_p0e_core','v1','lesson_count_semantics',false);

-- ---------------------------------------------------------------------------
-- §3 前置断言 A：当前必须处于已部署 v2 的状态
--   这里不核 md5——部署后的 md5 我在离线状态下算不出来，
--   写死一个猜的值就是把未知量当断言（lessons E10 第三次发作）。
--   改为核对 v2 的正/负标记，判据落在「被保护的性质」上。
-- ---------------------------------------------------------------------------
DO $do$
DECLARE r record; v_def text; v_hit boolean; v_bad text := '';
BEGIN
  FOR r IN
    SELECT m.fn_key, m.needle, m.must_exist, t.signature
    FROM lc2_marker m JOIN lc2_target t USING (fn_key)
    WHERE m.variant = 'v2'
    ORDER BY m.fn_key, m.needle
  LOOP
    IF to_regprocedure(r.signature) IS NULL THEN
      RAISE EXCEPTION 'LC2_FUNCTION_MISSING: % 在生产不存在', r.signature;
    END IF;
    v_def := pg_get_functiondef(to_regprocedure(r.signature)::oid);
    v_hit := strpos(v_def, r.needle) > 0;
    IF v_hit IS DISTINCT FROM r.must_exist THEN
      v_bad := v_bad || format(E'\n  %s: 子串 %L 期望%s，实际%s',
        r.fn_key, r.needle,
        CASE WHEN r.must_exist THEN '出现' ELSE '消失' END,
        CASE WHEN v_hit THEN '出现' ELSE '消失' END);
    END IF;
  END LOOP;
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'LC2_NOT_IN_V2_STATE: 生产当前不是完整的 v2 状态，'
      '继续回滚会造成半新半旧的组合。请先人工确认实际状态。%', v_bad;
  END IF;
END
$do$;

-- 记录回滚前 md5
DO $do$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM lc2_target LOOP
    UPDATE lc2_target
       SET before_md5 = md5(pg_get_functiondef(to_regprocedure(r.signature)::oid))
     WHERE fn_key = r.fn_key;
  END LOOP;
END
$do$;

-- ---------------------------------------------------------------------------
-- §4 前置断言 B：scope=full 时，生产不得存在任何 v2 持久化数据
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE lc2_v2_data ON COMMIT DROP AS
SELECT
  (SELECT count(*) FROM public.school_student_tuition_bills
    WHERE source_snapshot->>'lesson_count_semantics' = 'v2') AS v2_bills,
  (SELECT count(*) FROM public.school_income_records
    WHERE source_snapshot->>'lesson_count_semantics' = 'v2') AS v2_incomes;

\echo '--- 生产中的 v2 持久化数据 ---'
SELECT v2_bills AS "v2 账单", v2_incomes AS "v2 收入" FROM lc2_v2_data;

DO $do$
DECLARE v_bills bigint; v_inc bigint;
BEGIN
  SELECT v2_bills, v2_incomes INTO v_bills, v_inc FROM lc2_v2_data;
  IF (SELECT scope FROM lc2_run) = 'full' AND (v_bills > 0 OR v_inc > 0) THEN
    RAISE EXCEPTION 'LC2_FULL_ROLLBACK_UNSAFE: 生产已有 % 张 v2 账单 / % 条 v2 收入。'
      '完整还原旧 sum validator 会让它们在 generate 幂等返回、Void preflight 等'
      '任何触发校验的路径上失败（设计 §9.2），不限于 Reissue。'
      '请改用 -v scope=generation_only。', v_bills, v_inc;
  END IF;
END
$do$;

-- ---------------------------------------------------------------------------
-- §5 前置：ACL / owner 快照
--   CREATE OR REPLACE 不会重置 ACL，这里断言的是「没有变」这个性质本身
--   （lessons A3 / E10：判据落在被保护的性质上，不套模板期望值）。
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE lc2_acl_before ON COMMIT DROP AS
SELECT t.fn_key,
       coalesce(p.proacl::text,'<default>') AS acl,
       pg_get_userbyid(p.proowner)          AS owner,
       p.prosecdef, p.provolatile, p.proconfig::text AS proconfig
FROM lc2_target t
JOIN pg_proc p ON p.oid = to_regprocedure(t.signature)::oid;

\echo '--- ACL / owner 回滚前快照 ---'
SELECT fn_key, owner, prosecdef, provolatile, acl FROM lc2_acl_before ORDER BY fn_key;

-- ---------------------------------------------------------------------------
-- §6 回滚前：全量账单校验扫描
--   只读。记录每张账单当前是否通过 validator。
--   判据是「不新增失败」而不是「全部通过」——生产可能本来就有失败项，
--   拿绝对值当断言会制造假阳性硬停止（lessons E10 第三次发作）。
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE lc2_validation_before(bill_id uuid PRIMARY KEY, ok boolean NOT NULL, err text)
  ON COMMIT DROP;

DO $do$
DECLARE r record;
BEGIN
  FOR r IN SELECT b.id FROM public.school_student_tuition_bills b ORDER BY b.id LOOP
    BEGIN
      PERFORM public.school_validate_tuition_bill_lessons_for_bill(r.id);
      INSERT INTO lc2_validation_before(bill_id,ok,err) VALUES (r.id,true,NULL);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO lc2_validation_before(bill_id,ok,err) VALUES (r.id,false,SQLERRM);
    END;
  END LOOP;
END
$do$;

\echo '--- 回滚前 账单校验汇总 ---'
SELECT count(*) FILTER (WHERE ok)     AS "通过",
       count(*) FILTER (WHERE NOT ok) AS "失败",
       count(*)                       AS "总数"
FROM lc2_validation_before;
SELECT bill_id, err FROM lc2_validation_before WHERE NOT ok ORDER BY bill_id;

-- ---------------------------------------------------------------------------
-- §7 还原（正文为 2026-09-06 12:05:12 JST 生产原文的逐字节副本）
-- ---------------------------------------------------------------------------
SELECT CASE WHEN :'scope' = 'full' THEN 'true' ELSE 'false' END AS lc2_restore_validator \gset

-- ---- 还原 public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)
CREATE OR REPLACE FUNCTION public.school_list_student_tuition_candidates(p_student_id uuid, p_business_entity_id uuid, p_billing_month text, p_include_excluded boolean DEFAULT false)
 RETURNS TABLE(planned_lesson_id uuid, student_id uuid, business_entity_id uuid, candidate_billing_month text, lesson_date date, year_month text, teacher_id uuid, subject_id uuid, lesson_count integer, duration_hours numeric, unit_price numeric, lesson_fee numeric, candidate_status text, exclusion_reason text, has_normalized_bill_relation boolean, relation_roles text[], associated_bill_ids uuid[], associated_billing_identity_ids uuid[], has_bill_snapshot_evidence boolean, snapshot_bill_ids uuid[], bill_evidence_conflict boolean, complete_row_hash text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_billing_month text := nullif(trim(coalesce(p_billing_month, '')), '');
BEGIN
  IF p_student_id IS NULL THEN
    RAISE EXCEPTION 'R1C_B_STUDENT_REQUIRED';
  END IF;

  IF p_business_entity_id IS NULL THEN
    RAISE EXCEPTION 'R1C_B_BUSINESS_ENTITY_REQUIRED';
  END IF;

  IF v_billing_month IS NULL
     OR v_billing_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'R1C_B_BILLING_MONTH_INVALID';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_student_tuition_bills bill
     JOIN public.school_student_tuition_generation_revisions active_revision
       ON active_revision.tuition_bill_id=bill.id
      AND active_revision.lifecycle_status='active'
    WHERE bill.source_snapshot IS NULL
       OR NOT (bill.source_snapshot ? 'planned_lesson_ids')
       OR jsonb_typeof(bill.source_snapshot -> 'planned_lesson_ids') <> 'array'
  ) THEN
    RAISE EXCEPTION 'R1C_B_BILL_SNAPSHOT_FORMAT_UNSAFE';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_student_tuition_bills bill
     JOIN public.school_student_tuition_generation_revisions active_revision
       ON active_revision.tuition_bill_id=bill.id
      AND active_revision.lifecycle_status='active'
    CROSS JOIN LATERAL jsonb_array_elements_text(
      bill.source_snapshot -> 'planned_lesson_ids'
    ) snapshot_lesson(lesson_id_text)
    WHERE snapshot_lesson.lesson_id_text
      !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ) THEN
    RAISE EXCEPTION 'R1C_B_BILL_SNAPSHOT_LESSON_ID_UNSAFE';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.school_student_tuition_bills bill
     JOIN public.school_student_tuition_generation_revisions active_revision
       ON active_revision.tuition_bill_id=bill.id
      AND active_revision.lifecycle_status='active'
    CROSS JOIN LATERAL jsonb_array_elements_text(
      bill.source_snapshot -> 'planned_lesson_ids'
    ) snapshot_lesson(lesson_id_text)
    GROUP BY bill.id, snapshot_lesson.lesson_id_text
    HAVING count(*) <> 1
  ) THEN
    RAISE EXCEPTION 'R1C_B_BILL_SNAPSHOT_DUPLICATE_LESSON_ID';
  END IF;

  RETURN QUERY
  WITH snapshot_rows AS (
    SELECT
      bill.id AS bill_id,
      snapshot_lesson.lesson_id_text::uuid AS planned_lesson_id,
      snapshot_lesson.line_no::integer AS line_no
    FROM public.school_student_tuition_bills bill
     JOIN public.school_student_tuition_generation_revisions active_revision
       ON active_revision.tuition_bill_id=bill.id
      AND active_revision.lifecycle_status='active'
    CROSS JOIN LATERAL jsonb_array_elements_text(
      bill.source_snapshot -> 'planned_lesson_ids'
    ) WITH ORDINALITY snapshot_lesson(lesson_id_text, line_no)
  ),
  relation_evidence AS (
    SELECT
      relation.planned_lesson_id,
      array_agg(DISTINCT relation.relation_role ORDER BY relation.relation_role) AS relation_roles,
      array_agg(DISTINCT relation.tuition_bill_id ORDER BY relation.tuition_bill_id) AS bill_ids,
      coalesce(
        array_agg(DISTINCT identity.id ORDER BY identity.id)
          FILTER (WHERE identity.id IS NOT NULL),
        '{}'::uuid[]
      ) AS identity_ids,
      bool_or(
        snapshot.bill_id IS NULL
        OR snapshot.line_no IS DISTINCT FROM relation.line_no
      ) AS relation_snapshot_mismatch
    FROM public.school_active_student_tuition_bill_lessons relation
    LEFT JOIN snapshot_rows snapshot
      ON snapshot.bill_id = relation.tuition_bill_id
     AND snapshot.planned_lesson_id = relation.planned_lesson_id
    LEFT JOIN public.school_student_tuition_billing_identities identity
      ON identity.canonical_bill_id = relation.tuition_bill_id
    GROUP BY relation.planned_lesson_id
  ),
  snapshot_evidence AS (
    SELECT
      snapshot.planned_lesson_id,
      array_agg(DISTINCT snapshot.bill_id ORDER BY snapshot.bill_id) AS bill_ids
    FROM snapshot_rows snapshot
    GROUP BY snapshot.planned_lesson_id
  ),
  evidence_rows AS (
    SELECT
      lesson.*,
      relation.planned_lesson_id IS NOT NULL AS has_relation,
      coalesce(relation.relation_roles, '{}'::text[]) AS normalized_relation_roles,
      coalesce(relation.bill_ids, '{}'::uuid[]) AS normalized_bill_ids,
      coalesce(relation.identity_ids, '{}'::uuid[]) AS billing_identity_ids,
      snapshot.planned_lesson_id IS NOT NULL AS has_snapshot,
      coalesce(snapshot.bill_ids, '{}'::uuid[]) AS historical_snapshot_bill_ids,
      (
        coalesce(relation.relation_snapshot_mismatch, false)
        OR coalesce(relation.bill_ids, '{}'::uuid[])
           IS DISTINCT FROM coalesce(snapshot.bill_ids, '{}'::uuid[])
      ) AS evidence_conflict,
      exclusion.planned_lesson_id IS NOT NULL AS has_historical_paid_exclusion
    FROM public.school_lesson_records lesson
    LEFT JOIN relation_evidence relation
      ON relation.planned_lesson_id = lesson.id
    LEFT JOIN snapshot_evidence snapshot
      ON snapshot.planned_lesson_id = lesson.id
    LEFT JOIN public.school_student_tuition_historical_lesson_exclusions exclusion
      ON exclusion.planned_lesson_id = lesson.id
    WHERE lesson.student_id = p_student_id
      AND lesson.billing_month = v_billing_month
  ),
  classified AS (
    SELECT
      evidence.*,
      CASE
        WHEN evidence.app_type IS DISTINCT FROM 'school'
          OR evidence.business_entity_id IS DISTINCT FROM p_business_entity_id
          THEN 'scope_mismatch'
        WHEN evidence.has_historical_paid_exclusion
          THEN 'historical_paid_exclusion'
        ELSE public.school_classify_student_tuition_candidate(
          true,
          evidence.has_relation,
          evidence.normalized_relation_roles,
          evidence.has_snapshot,
          evidence.evidence_conflict,
          evidence.lesson_type,
          evidence.status,
          evidence.voided_at,
          evidence.is_billable,
          evidence.student_id IS NOT NULL
            AND evidence.business_entity_id IS NOT NULL
            AND evidence.billing_month = v_billing_month
            AND evidence.billing_week_start_date IS NOT NULL
            AND public.school_is_valid_tuition_billing_period(
              evidence.billing_month,evidence.billing_week_start_date
            )
            AND evidence.student_settlement_month = evidence.billing_month
            AND evidence.billing_month_source IN (
              'approved_r1c_a_manifest',
              'approved_r1c_c_b_manifest',
              'scheduled_date_at_create',
              'explicit_billing_week_at_create',
              'approved_legacy_planned_canonicalization_20260801'
            )
            AND evidence.billing_month_decided_at IS NOT NULL
            AND evidence.lesson_date IS NOT NULL
            AND evidence.teacher_id IS NOT NULL
            AND evidence.subject_id IS NOT NULL
            AND evidence.lesson_count IS NOT NULL
            AND evidence.lesson_count > 0
            AND evidence.duration_hours > 0
            AND evidence.unit_price IS NOT NULL
            AND evidence.unit_price > 0
            AND evidence.lesson_fee IS NOT NULL
            AND evidence.lesson_fee > 0
            AND evidence.created_at IS NOT NULL
            AND evidence.updated_at IS NOT NULL
        )
      END AS reason_code
    FROM evidence_rows evidence
  )
  SELECT
    classified.id,
    classified.student_id,
    classified.business_entity_id,
    classified.billing_month,
    classified.lesson_date,
    classified.year_month,
    classified.teacher_id,
    classified.subject_id,
    classified.lesson_count,
    classified.duration_hours,
    classified.unit_price,
    classified.lesson_fee,
    CASE WHEN classified.reason_code = 'candidate' THEN 'candidate' ELSE 'excluded' END,
    CASE WHEN classified.reason_code = 'candidate' THEN NULL ELSE classified.reason_code END,
    classified.has_relation,
    classified.normalized_relation_roles,
    classified.normalized_bill_ids,
    classified.billing_identity_ids,
    classified.has_snapshot,
    classified.historical_snapshot_bill_ids,
    classified.evidence_conflict,
    md5((to_jsonb(classified) - ARRAY[
      'has_relation',
      'normalized_relation_roles',
      'normalized_bill_ids',
      'billing_identity_ids',
      'has_snapshot',
      'historical_snapshot_bill_ids',
      'evidence_conflict',
      'has_historical_paid_exclusion',
      'reason_code'
    ]::text[])::text)
  FROM classified
  WHERE coalesce(p_include_excluded, false)
     OR classified.reason_code = 'candidate'
  ORDER BY classified.billing_week_start_date,classified.lesson_date,classified.id;
END
$function$

-- ---- 还原 public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)
CREATE OR REPLACE FUNCTION public.school_build_student_tuition_generation_snapshot(p_student_id uuid, p_billing_month text, p_billing_exchange_rate numeric)
 RETURNS TABLE(student_id uuid, business_entity_id uuid, billing_month text, previous_settlement_month text, previous_settlement_id uuid, previous_carryover_cny numeric, carryover_evidence jsonb, candidate_count integer, total_lesson_count integer, total_duration_hours numeric, total_base_lesson_fee_jpy numeric, total_aircon_fee_jpy numeric, total_fee_jpy numeric, billing_exchange_rate numeric, billing_amount_cny numeric, candidate_uuid_md5 text, candidate_manifest_sha256 text, generation_manifest_sha256 text, candidates jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_student public.school_students%ROWTYPE;
  v_month text := nullif(pg_catalog.btrim(coalesce(p_billing_month,'')),'');
  v_previous_month text;
  v_previous_settlement public.school_student_monthly_settlements%ROWTYPE;
  v_locked_count integer;
  v_carryover numeric;
  v_carryover_evidence jsonb;
  v_carryover_evidence_sha text;
  v_count integer;
  v_distinct_count integer;
  v_lesson_count integer;
  v_hours numeric;
  v_base numeric;
  v_aircon numeric;
  v_total numeric;
  v_uuid_md5 text;
  v_candidate_manifest text;
  v_generation_manifest text;
  v_candidates jsonb;
  v_contract_valid boolean;
  v_amount_cny numeric;
BEGIN
  IF p_student_id IS NULL THEN RAISE EXCEPTION 'R2_F_B_STUDENT_REQUIRED'; END IF;
  IF v_month IS NULL OR v_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'R2_F_B_BILLING_MONTH_INVALID';
  END IF;
  IF p_billing_exchange_rate IS NULL OR p_billing_exchange_rate <= 0 THEN
    RAISE EXCEPTION 'R2_F_B_EXCHANGE_RATE_INVALID';
  END IF;

  SELECT student.* INTO v_student
  FROM public.school_students student
  WHERE student.id=p_student_id AND student.app_type='school';
  IF NOT FOUND THEN RAISE EXCEPTION 'R2_F_B_STUDENT_NOT_FOUND'; END IF;
  IF v_student.business_entity_id IS NULL THEN
    RAISE EXCEPTION 'R2_F_B_BUSINESS_ENTITY_REQUIRED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.school_student_monthly_settlements settlement
    WHERE settlement.student_id=p_student_id
      AND settlement.business_entity_id=v_student.business_entity_id
      AND settlement.year_month=v_month
      AND settlement.settlement_status='locked'
  ) THEN
    RAISE EXCEPTION 'R2_F_B_TARGET_SETTLEMENT_LOCKED';
  END IF;

  v_previous_month := pg_catalog.to_char(
    (pg_catalog.to_date(v_month||'-01','YYYY-MM-DD')-interval '1 month')::date,
    'YYYY-MM'
  );

  SELECT count(*)::integer INTO v_locked_count
  FROM public.school_student_monthly_settlements settlement
  WHERE settlement.student_id=p_student_id
    AND settlement.business_entity_id=v_student.business_entity_id
    AND settlement.year_month=v_previous_month
    AND settlement.settlement_status='locked';
  IF v_locked_count > 1 THEN
    RAISE EXCEPTION 'R2_F_B_MULTIPLE_PREVIOUS_LOCKED_SETTLEMENTS';
  END IF;

  SELECT settlement.* INTO v_previous_settlement
  FROM public.school_student_monthly_settlements settlement
  WHERE settlement.student_id=p_student_id
    AND settlement.business_entity_id=v_student.business_entity_id
    AND settlement.year_month=v_previous_month
    AND settlement.settlement_status='locked'
  ORDER BY settlement.locked_at DESC NULLS LAST,
    settlement.updated_at DESC NULLS LAST,settlement.created_at DESC NULLS LAST
  LIMIT 1;

  IF FOUND THEN
    v_carryover := pg_catalog.round(coalesce(v_previous_settlement.carryover_amount_cny,0),2);
    v_carryover_evidence := jsonb_build_object(
      'mode','locked_settlement_v1',
      'authority','locked_previous_settlement_only',
      'settlement_month',v_previous_month,
      'settlement_id',v_previous_settlement.id,
      'settlement_status',v_previous_settlement.settlement_status,
      'locked_at',v_previous_settlement.locked_at,
      'updated_at',v_previous_settlement.updated_at,
      'carryover_amount_cny',v_carryover
    );
  ELSE
    v_carryover := 0;
    v_carryover_evidence := jsonb_build_object(
      'mode','zero_carryover_verified_v1',
      'authority','locked_previous_settlement_only',
      'settlement_month',v_previous_month,
      'locked_settlement_count',v_locked_count,
      'carryover_amount_cny',v_carryover
    );
  END IF;

  v_carryover_evidence_sha := encode(sha256(convert_to(v_carryover_evidence::text,'UTF8')),'hex');

  WITH candidate_rows AS MATERIALIZED (
    SELECT candidate.*,
      lesson.teacher_id,lesson.subject_id,lesson.updated_at AS source_updated_at,
      coalesce(lesson.aircon_billable_hours_snapshot,0)::numeric AS aircon_billable_hours,
      lesson.lesson_venue_id,lesson.lesson_venue AS lesson_venue_code
    FROM public.school_list_student_tuition_charge_candidates(
      p_student_id,v_student.business_entity_id,v_month,false
    ) candidate
    JOIN public.school_lesson_records lesson ON lesson.id=candidate.planned_lesson_id
  ), canonical_lines AS (
    SELECT detail.*,
      jsonb_build_object(
        'planned_lesson_id',detail.planned_lesson_id,
        'student_id',detail.student_id,
        'business_entity_id',detail.business_entity_id,
        'billing_month',detail.candidate_billing_month,
        'billing_week_start_date',detail.billing_week_start_date,
        'lesson_date',detail.lesson_date,
        'teacher_id',detail.teacher_id,
        'subject_id',detail.subject_id,
        'lesson_count',detail.lesson_count,
        'duration_hours',detail.duration_hours,
        'unit_price_jpy',detail.unit_price,
        'base_lesson_fee_jpy',detail.base_lesson_fee_jpy,
        'aircon_rate_jpy_per_hour',detail.aircon_rate_jpy_per_hour,
        'aircon_billable_hours',detail.aircon_billable_hours,
        'aircon_fee_jpy',detail.aircon_fee_jpy,
        'course_total_jpy',detail.lesson_total_fee_jpy,
        'fee_policy_version',coalesce(detail.aircon_policy_version,'legacy_base_only'),
        'aircon_charge_status',detail.aircon_charge_status,
        'lesson_venue_id',detail.lesson_venue_id,
        'lesson_venue_code',detail.lesson_venue_code,
        'source_lesson_updated_at',detail.source_updated_at,
        'complete_row_hash',detail.complete_row_hash
      ) AS canonical_line
    FROM candidate_rows detail
  ), hashed_lines AS (
    SELECT line.*,
      encode(sha256(convert_to(line.canonical_line::text,'UTF8')),'hex')
        AS candidate_line_hash
    FROM canonical_lines line
  ), aggregated AS (
    SELECT count(*)::integer AS candidate_count,
      count(DISTINCT detail.planned_lesson_id)::integer AS distinct_count,
      coalesce(sum(detail.lesson_count),0)::integer AS lesson_count,
      coalesce(sum(detail.duration_hours),0)::numeric AS hours,
      coalesce(sum(detail.base_lesson_fee_jpy),0)::numeric AS base_fee,
      coalesce(sum(detail.aircon_fee_jpy),0)::numeric AS aircon_fee,
      coalesce(sum(detail.lesson_total_fee_jpy),0)::numeric AS total_fee,
      md5(string_agg(detail.planned_lesson_id::text,',' ORDER BY detail.planned_lesson_id::text)) AS uuid_md5,
      encode(sha256(convert_to(
        string_agg(detail.candidate_line_hash,E'\n'
          ORDER BY detail.billing_week_start_date,detail.lesson_date,
          detail.planned_lesson_id)||E'\n','UTF8')),'hex') AS candidate_manifest,
      jsonb_agg(detail.canonical_line||jsonb_build_object(
        'candidate_line_hash',detail.candidate_line_hash
      ) ORDER BY detail.billing_week_start_date,detail.lesson_date,
        detail.planned_lesson_id) AS candidates,
      bool_and(detail.student_id=p_student_id
        AND detail.business_entity_id=v_student.business_entity_id
        AND detail.candidate_billing_month=v_month
        AND detail.billing_week_start_date IS NOT NULL
        AND extract(isodow FROM detail.billing_week_start_date)=1
        AND to_char(detail.billing_week_start_date,'YYYY-MM')=v_month
        AND detail.lesson_total_fee_jpy=detail.base_lesson_fee_jpy+detail.aircon_fee_jpy
        AND detail.aircon_rate_jpy_per_hour>=0
        AND detail.aircon_billable_hours>=0
        AND detail.aircon_fee_jpy>=0
        AND (coalesce(detail.aircon_policy_version,'legacy_base_only')<>'planned_weekend_aircon_v1'
             OR detail.aircon_fee_jpy=detail.aircon_rate_jpy_per_hour*detail.aircon_billable_hours)
      ) AS contract_valid
    FROM hashed_lines detail
  )
  SELECT aggregated.candidate_count,aggregated.distinct_count,
    aggregated.lesson_count,aggregated.hours,aggregated.base_fee,
    aggregated.aircon_fee,aggregated.total_fee,aggregated.uuid_md5,
    aggregated.candidate_manifest,aggregated.candidates,
    aggregated.contract_valid
  INTO v_count,v_distinct_count,v_lesson_count,v_hours,v_base,v_aircon,
    v_total,v_uuid_md5,v_candidate_manifest,v_candidates,v_contract_valid
  FROM aggregated;

  IF v_count IS NULL OR v_count<=0 THEN RAISE EXCEPTION 'R2_F_B_CANDIDATES_EMPTY'; END IF;
  IF v_count IS DISTINCT FROM v_distinct_count THEN RAISE EXCEPTION 'R2_F_B_DUPLICATE_CANDIDATE_UUID'; END IF;
  IF v_contract_valid IS DISTINCT FROM true OR v_total IS DISTINCT FROM v_base+v_aircon THEN
    RAISE EXCEPTION 'R2_F_B_CANDIDATE_CONTRACT_MISMATCH';
  END IF;

  v_amount_cny := round(v_total*p_billing_exchange_rate+v_carryover,2);
  IF v_amount_cny<=0 THEN RAISE EXCEPTION 'R2_F_B_BILLING_AMOUNT_INVALID'; END IF;

  v_generation_manifest := encode(sha256(convert_to(concat_ws('|',
    'student_tuition_atomic_generate_v1',p_student_id::text,
    v_student.business_entity_id::text,v_month,v_candidate_manifest,
    v_uuid_md5,v_count::text,v_lesson_count::text,v_hours::text,
    v_base::text,v_aircon::text,v_total::text,p_billing_exchange_rate::text,
    v_previous_month,coalesce(v_previous_settlement.id::text,'zero'),
    v_carryover::text,v_carryover_evidence_sha,v_amount_cny::text
  ),'UTF8')),'hex');

  RETURN QUERY SELECT p_student_id,v_student.business_entity_id,v_month,
    v_previous_month,v_previous_settlement.id,v_carryover,v_carryover_evidence,
    v_count,v_lesson_count,v_hours,v_base,v_aircon,v_total,
    p_billing_exchange_rate,v_amount_cny,v_uuid_md5,v_candidate_manifest,
    v_generation_manifest,v_candidates;
END
$function$

-- validator 只在 scope=full 时还原；generation_only 保留兼容版本
\if :lc2_restore_validator
-- ---- 还原 public.school_validate_tuition_bill_lessons_for_bill(uuid)
CREATE OR REPLACE FUNCTION public.school_validate_tuition_bill_lessons_for_bill(p_bill_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_bill public.school_student_tuition_bills%ROWTYPE;
  v_identity public.school_student_tuition_billing_identities%ROWTYPE;
  v_revision public.school_student_tuition_generation_revisions%ROWTYPE;
  v_count integer; v_lesson_count integer; v_hours numeric;
  v_base numeric; v_aircon numeric; v_fee numeric; v_bad_rows integer;
  v_recomputed_candidate_manifest text;
BEGIN
  PERFORM public.school_validate_tuition_generation_revision_for_bill(p_bill_id);
  IF p_bill_id IS NULL THEN RETURN; END IF;
  SELECT bill.* INTO v_bill FROM public.school_student_tuition_bills bill
  WHERE bill.id=p_bill_id;
  IF NOT FOUND OR v_bill.billing_role IS NULL THEN RETURN; END IF;
  SELECT revision_row.* INTO v_revision
  FROM public.school_student_tuition_generation_revisions revision_row
  WHERE revision_row.tuition_bill_id=v_bill.id;
  SELECT identity_row.* INTO v_identity
  FROM public.school_student_tuition_generation_identities generation_row
  JOIN public.school_student_tuition_billing_identities identity_row
    ON identity_row.id=generation_row.legacy_billing_identity_id
  WHERE generation_row.id=v_revision.generation_identity_id;

  IF v_revision.manifest_kind='atomic_generation_v1' THEN
    SELECT count(*)::integer,coalesce(sum(rel.lesson_count_snapshot),0)::integer,
      coalesce(sum(rel.duration_hours_snapshot),0),
      coalesce(sum(rel.base_lesson_fee_jpy_snapshot),0),
      coalesce(sum(rel.aircon_fee_jpy_snapshot),0),
      coalesce(sum(rel.lesson_fee_jpy_snapshot),0),
      count(*) FILTER (WHERE
        rel.relation_role IS DISTINCT FROM 'canonical_charge'
        OR rel.student_id_snapshot IS DISTINCT FROM v_bill.student_id
        OR rel.business_entity_id_snapshot IS DISTINCT FROM v_bill.business_entity_id
        OR rel.billing_month_snapshot IS DISTINCT FROM v_bill.billing_month
        OR rel.attribution_confidence IS DISTINCT FROM 'high'
        OR rel.snapshot_source IS DISTINCT FROM 'student_tuition_atomic_generate_v1'
        OR rel.backfill_batch_id IS NOT NULL
        OR rel.line_no>jsonb_array_length(v_bill.source_snapshot->'candidate_lines')
        OR (v_bill.source_snapshot->'planned_lesson_ids'->>(rel.line_no-1))::uuid
             IS DISTINCT FROM rel.planned_lesson_id
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'planned_lesson_id')::uuid
             IS DISTINCT FROM rel.planned_lesson_id
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'billing_month')
             IS DISTINCT FROM rel.billing_month_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'billing_week_start_date')::date
             IS DISTINCT FROM rel.week_start_date_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'lesson_date')::date
             IS DISTINCT FROM rel.scheduled_lesson_date_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'lesson_count')::integer
             IS DISTINCT FROM rel.lesson_count_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'duration_hours')::numeric
             IS DISTINCT FROM rel.duration_hours_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'unit_price_jpy')::numeric
             IS DISTINCT FROM rel.unit_price_jpy_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'base_lesson_fee_jpy')::numeric
             IS DISTINCT FROM rel.base_lesson_fee_jpy_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'aircon_rate_jpy_per_hour')::integer
             IS DISTINCT FROM rel.aircon_unit_price_jpy_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'aircon_billable_hours')::numeric
             IS DISTINCT FROM rel.aircon_billable_hours_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'aircon_fee_jpy')::numeric
             IS DISTINCT FROM rel.aircon_fee_jpy_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'course_total_jpy')::numeric
             IS DISTINCT FROM rel.lesson_fee_jpy_snapshot
        OR (v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'fee_policy_version')
             IS DISTINCT FROM rel.fee_calculation_version_snapshot
        OR (rel.fee_calculation_version_snapshot IN (
              'planned_weekend_aircon_v1',
              'planned_weekend_venue_whole_hour_aircon_v2'
            )
            AND rel.aircon_fee_jpy_snapshot IS DISTINCT FROM
              rel.aircon_unit_price_jpy_snapshot*rel.aircon_billable_hours_snapshot)
        OR coalesce(v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'complete_row_hash','')=''
        OR coalesce(v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'candidate_line_hash','')
             !~ '^[0-9a-f]{64}$'
        OR encode(sha256(convert_to(
             ((v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1))-'candidate_line_hash')::text,
             'UTF8'
           )),'hex') IS DISTINCT FROM
             v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'candidate_line_hash'
        OR rel.source_snapshot->>'complete_row_hash' IS DISTINCT FROM
             v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'complete_row_hash'
        OR rel.source_snapshot->>'candidate_line_hash' IS DISTINCT FROM
             v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)->>'candidate_line_hash'
        OR (rel.source_snapshot-ARRAY[
             'generation_manifest_sha256','candidate_manifest_sha256'
           ]::text[]) IS DISTINCT FROM
             v_bill.source_snapshot->'candidate_lines'->(rel.line_no-1)
        OR rel.source_snapshot->>'candidate_manifest_sha256'
             IS DISTINCT FROM v_bill.source_snapshot->>'candidate_manifest_sha256'
        OR rel.source_snapshot->>'generation_manifest_sha256'
             IS DISTINCT FROM v_bill.source_snapshot->>'generation_manifest_sha256'
      )::integer
    INTO v_count,v_lesson_count,v_hours,v_base,v_aircon,v_fee,v_bad_rows
    FROM public.school_student_tuition_bill_lessons rel
    WHERE rel.tuition_bill_id=v_bill.id;

    SELECT encode(sha256(convert_to(
      string_agg(line.value->>'candidate_line_hash',E'\n' ORDER BY line.ordinality)
        ||E'\n','UTF8')),'hex')
    INTO v_recomputed_candidate_manifest
    FROM jsonb_array_elements(v_bill.source_snapshot->'candidate_lines')
      WITH ORDINALITY line(value,ordinality);

    IF v_bill.source_snapshot->>'generation_source' IS DISTINCT FROM 'student_tuition_atomic_generate_v1'
       OR v_revision.generation_manifest_sha256
            IS DISTINCT FROM v_bill.source_snapshot->>'generation_manifest_sha256'
       OR v_recomputed_candidate_manifest
            IS DISTINCT FROM v_bill.source_snapshot->>'candidate_manifest_sha256'
       
       OR jsonb_array_length(v_bill.source_snapshot->'candidate_lines') IS DISTINCT FROM v_count
       OR jsonb_array_length(v_bill.source_snapshot->'planned_lesson_ids') IS DISTINCT FROM v_count
       OR (v_bill.source_snapshot->>'candidate_count')::integer IS DISTINCT FROM v_count
       OR (v_bill.source_snapshot->>'total_lesson_count')::integer IS DISTINCT FROM v_lesson_count
       OR (v_bill.source_snapshot->>'total_duration_hours')::numeric IS DISTINCT FROM v_hours
       OR (v_bill.source_snapshot->>'total_base_lesson_fee_jpy')::numeric IS DISTINCT FROM v_base
       OR (v_bill.source_snapshot->>'total_aircon_fee_jpy')::numeric IS DISTINCT FROM v_aircon
       OR (v_bill.source_snapshot->>'total_fee_jpy')::numeric IS DISTINCT FROM v_fee
       OR v_count IS DISTINCT FROM v_bill.planned_lesson_count
       OR v_hours IS DISTINCT FROM v_bill.planned_lesson_hours
       OR v_fee IS DISTINCT FROM v_bill.planned_lesson_fee_jpy
       OR v_fee IS DISTINCT FROM v_bill.bill_amount_jpy
       OR v_fee IS DISTINCT FROM v_base+v_aircon OR v_bad_rows<>0 THEN
      RAISE EXCEPTION 'TUITION_ATOMIC_BILL_LESSON_MISMATCH: bill % frozen JSON and normalized relations differ.',v_bill.id;
    END IF;
  ELSE
    SELECT count(*)::integer,coalesce(sum(rel.duration_hours_snapshot),0),
      coalesce(sum(rel.lesson_fee_jpy_snapshot),0),
      count(*) FILTER (WHERE rel.relation_role IS DISTINCT FROM v_bill.billing_role
        OR rel.student_id_snapshot IS DISTINCT FROM v_bill.student_id
        OR rel.business_entity_id_snapshot IS DISTINCT FROM v_bill.business_entity_id
        OR rel.billing_month_snapshot IS DISTINCT FROM v_bill.billing_month
        OR rel.week_start_date_snapshot IS NOT NULL
        OR rel.scheduled_lesson_date_snapshot IS NOT NULL
        OR rel.attribution_confidence IS DISTINCT FROM 'medium'
        OR rel.snapshot_source IS DISTINCT FROM 'bill_json_exact_id_plus_current_source_fields_aggregate_verified'
        OR rel.line_no>jsonb_array_length(coalesce(v_bill.source_snapshot->'planned_lesson_ids','[]'::jsonb))
        OR (v_bill.source_snapshot->'planned_lesson_ids'->>(rel.line_no-1))::uuid
             IS DISTINCT FROM rel.planned_lesson_id)::integer
    INTO v_count,v_hours,v_fee,v_bad_rows
    FROM public.school_student_tuition_bill_lessons rel
    WHERE rel.tuition_bill_id=v_bill.id;
    IF v_bill.billing_role IN ('incident_duplicate','legacy_cancelled') AND EXISTS (
      SELECT 1 FROM public.school_student_tuition_bill_lessons rel
      WHERE rel.tuition_bill_id=v_bill.id AND NOT EXISTS (
        SELECT 1 FROM public.school_student_tuition_bill_lessons canonical
        WHERE canonical.planned_lesson_id=rel.planned_lesson_id
          AND canonical.relation_role='canonical_charge')) THEN
      RAISE EXCEPTION 'TUITION_NONCANONICAL_LESSON_WITHOUT_CANONICAL: bill % contains an unconsumed lesson.',v_bill.id;
    END IF;
    IF v_count IS DISTINCT FROM v_bill.planned_lesson_count
       OR v_hours IS DISTINCT FROM v_bill.planned_lesson_hours
       OR v_fee IS DISTINCT FROM v_bill.planned_lesson_fee_jpy
       OR v_fee IS DISTINCT FROM v_bill.bill_amount_jpy OR v_bad_rows<>0 THEN
      RAISE EXCEPTION 'TUITION_BILL_LESSON_MISMATCH: normalized lessons do not match frozen bill %.',v_bill.id;
    END IF;
  END IF;
END
$function$
\endif

-- ---- 还原 public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text)
CREATE OR REPLACE FUNCTION public.school_generate_student_tuition_bill_atomic_base_core_v1(p_student_id uuid, p_billing_month text, p_billing_exchange_rate numeric, p_expected_generation_manifest_sha256 text, p_note text DEFAULT NULL::text, p_test_fail_after_step text DEFAULT NULL::text)
 RETURNS TABLE(tuition_bill_id uuid, billing_identity_id uuid, income_record_id uuid, student_id uuid, business_entity_id uuid, billing_month text, generation_manifest_sha256 text, candidate_count integer, total_lesson_count integer, total_duration_hours numeric, total_base_lesson_fee_jpy numeric, total_aircon_fee_jpy numeric, total_fee_jpy numeric, billing_exchange_rate numeric, previous_carryover_cny numeric, billing_amount_cny numeric, bill_status text, income_status text, idempotent boolean, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_student_initial public.school_students%ROWTYPE;
  v_student public.school_students%ROWTYPE;
  v_identity public.school_student_tuition_billing_identities%ROWTYPE;
  v_bill public.school_student_tuition_bills%ROWTYPE;
  v_income public.school_income_records%ROWTYPE;
  v_snapshot record;
  v_initial_ids uuid[];
  v_locked_ids uuid[];
  v_previous_month text;
  v_lock_month text;
  v_note text:=nullif(btrim(coalesce(p_note,'')),'');
  v_now timestamptz:=clock_timestamp();
  v_operator text:=coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),current_user);
  v_line jsonb;
  v_line_no integer:=0;
  v_previous_lock_timeout text;
BEGIN
  IF p_billing_exchange_rate IS NULL OR p_billing_exchange_rate<=0 THEN
    RAISE EXCEPTION 'R2_F_B_EXCHANGE_RATE_INVALID';
  END IF;
  IF p_expected_generation_manifest_sha256 IS NULL
     OR p_expected_generation_manifest_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'R2_F_B_GENERATION_MANIFEST_INVALID';
  END IF;
  SELECT student.* INTO v_student_initial FROM public.school_students student
  WHERE student.id=p_student_id AND student.app_type='school';
  IF NOT FOUND OR v_student_initial.business_entity_id IS NULL THEN
    RAISE EXCEPTION 'R2_F_B_STUDENT_OR_ENTITY_INVALID';
  END IF;
  IF p_billing_month IS NULL OR btrim(p_billing_month)!~'^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'R2_F_B_BILLING_MONTH_INVALID';
  END IF;
  v_previous_month:=to_char((to_date(btrim(p_billing_month)||'-01','YYYY-MM-DD')-interval '1 month')::date,'YYYY-MM');
  PERFORM public.school_tuition_p0a_lock_generate_scope(
    p_student_id,v_student_initial.business_entity_id,
    ARRAY[v_previous_month,btrim(p_billing_month)]
  );

  SELECT identity_row.* INTO v_identity
  FROM public.school_student_tuition_billing_identities identity_row
  WHERE identity_row.student_id=p_student_id
    AND identity_row.billing_month=btrim(p_billing_month)
  FOR UPDATE;
  IF FOUND THEN
    SELECT bill.* INTO v_bill FROM public.school_student_tuition_bills bill
    WHERE bill.id=v_identity.canonical_bill_id FOR UPDATE;
    SELECT income.* INTO v_income FROM public.school_income_records income
    WHERE income.id=v_bill.income_record_id FOR UPDATE;
    SELECT student.* INTO STRICT v_student FROM public.school_students student
    WHERE student.id=p_student_id AND student.app_type='school' FOR SHARE;
    BEGIN
      IF v_identity.student_id IS DISTINCT FROM p_student_id
       OR v_identity.billing_month IS DISTINCT FROM btrim(p_billing_month)
       OR v_identity.source IS DISTINCT FROM 'atomic_charge'
       OR v_identity.evidence->>'generation_source' IS DISTINCT FROM 'student_tuition_atomic_generate_v1'
       OR v_identity.evidence->>'generation_manifest_sha256' IS DISTINCT FROM p_expected_generation_manifest_sha256
       OR v_identity.evidence->>'candidate_manifest_sha256'
            IS DISTINCT FROM v_bill.source_snapshot->>'candidate_manifest_sha256'
       OR v_identity.evidence->>'carryover_evidence_sha256'
            IS DISTINCT FROM v_bill.source_snapshot->>'carryover_evidence_sha256'
       OR v_identity.evidence->>'business_entity_id'
            IS DISTINCT FROM v_student.business_entity_id::text
       OR v_bill.id IS NULL
       OR v_bill.student_id IS DISTINCT FROM p_student_id
       OR v_bill.student_id IS DISTINCT FROM v_identity.student_id
       OR v_bill.business_entity_id IS DISTINCT FROM v_student.business_entity_id
       OR v_bill.billing_month IS DISTINCT FROM btrim(p_billing_month)
       OR v_bill.billing_exchange_rate IS DISTINCT FROM p_billing_exchange_rate
       OR v_bill.source_snapshot->>'generation_manifest_sha256' IS DISTINCT FROM p_expected_generation_manifest_sha256
       OR (v_bill.source_snapshot->>'billing_exchange_rate')::numeric
            IS DISTINCT FROM p_billing_exchange_rate
       OR (v_bill.source_snapshot->>'total_fee_jpy')::numeric
            IS DISTINCT FROM v_bill.bill_amount_jpy
       OR v_bill.planned_lesson_fee_jpy IS DISTINCT FROM v_bill.bill_amount_jpy
       OR (v_bill.source_snapshot->>'previous_carryover_cny')::numeric
            IS DISTINCT FROM v_bill.previous_carryover_cny
       OR (v_bill.source_snapshot->>'previous_settlement_month')
            IS DISTINCT FROM v_bill.previous_settlement_month
       OR nullif(v_bill.source_snapshot->>'previous_settlement_id','')::uuid
            IS DISTINCT FROM v_bill.previous_settlement_id
       OR jsonb_typeof(v_bill.source_snapshot->'carryover_evidence') IS DISTINCT FROM 'object'
       OR coalesce(v_bill.source_snapshot->>'carryover_evidence_sha256','') !~ '^[0-9a-f]{64}$'
       OR encode(sha256(convert_to(
            (v_bill.source_snapshot->'carryover_evidence')::text,'UTF8'
          )),'hex') IS DISTINCT FROM v_bill.source_snapshot->>'carryover_evidence_sha256'
       OR v_bill.source_snapshot->'carryover_evidence'->>'settlement_month'
            IS DISTINCT FROM v_bill.previous_settlement_month
       OR v_bill.source_snapshot->'carryover_evidence'->>'authority'
            IS DISTINCT FROM 'locked_previous_settlement_only'
       OR (
            v_bill.source_snapshot->'carryover_evidence'->>'mode'='locked_settlement_v1'
            AND (
              v_bill.previous_settlement_id IS NULL
              OR nullif(v_bill.source_snapshot->'carryover_evidence'->>'settlement_id','')::uuid
                   IS DISTINCT FROM v_bill.previous_settlement_id
              OR v_bill.source_snapshot->'carryover_evidence'->>'settlement_status'
                   IS DISTINCT FROM 'locked'
              OR (v_bill.source_snapshot->'carryover_evidence'->>'carryover_amount_cny')::numeric
                   IS DISTINCT FROM v_bill.previous_carryover_cny
            )
          )
       OR (
            v_bill.source_snapshot->'carryover_evidence'->>'mode'='zero_carryover_verified_v1'
            AND (
              v_bill.previous_settlement_id IS NOT NULL
              OR v_bill.previous_carryover_cny<>0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'locked_settlement_count')::integer
                   IS DISTINCT FROM 0
              OR (v_bill.source_snapshot->'carryover_evidence'->>'carryover_amount_cny')::numeric
                   IS DISTINCT FROM 0
            )
          )
       OR coalesce(v_bill.source_snapshot->'carryover_evidence'->>'mode','')
            NOT IN ('locked_settlement_v1','zero_carryover_verified_v1')
       OR v_bill.billing_amount_cny IS DISTINCT FROM round(
            v_bill.bill_amount_jpy*p_billing_exchange_rate
              +v_bill.previous_carryover_cny,2
          )
       OR (v_bill.source_snapshot->>'billing_amount_cny')::numeric
            IS DISTINCT FROM v_bill.billing_amount_cny
       OR v_bill.status IS DISTINCT FROM 'income_created'
       OR v_income.id IS NULL OR v_income.status IS DISTINCT FROM 'pending'
       OR v_income.cancelled_at IS NOT NULL
       OR v_income.student_id IS DISTINCT FROM p_student_id
       OR v_income.business_entity_id IS DISTINCT FROM v_bill.business_entity_id
       OR v_income.source_type IS DISTINCT FROM 'student_tuition_bill'
       OR v_income.source_id IS DISTINCT FROM v_bill.id
       OR v_income.tuition_bill_id IS DISTINCT FROM v_bill.id
       OR v_income.amount IS DISTINCT FROM v_bill.bill_amount_jpy
       OR v_income.amount_jpy IS DISTINCT FROM v_bill.bill_amount_jpy
       OR v_income.source_snapshot->>'generation_manifest_sha256' IS DISTINCT FROM p_expected_generation_manifest_sha256
       OR v_income.source_snapshot->>'candidate_manifest_sha256'
            IS DISTINCT FROM v_bill.source_snapshot->>'candidate_manifest_sha256'
       OR v_income.source_snapshot->>'carryover_evidence_sha256'
            IS DISTINCT FROM v_bill.source_snapshot->>'carryover_evidence_sha256'
       OR (v_income.source_snapshot->>'billing_exchange_rate')::numeric
            IS DISTINCT FROM p_billing_exchange_rate
       OR (v_income.source_snapshot->>'billing_amount_cny')::numeric
            IS DISTINCT FROM v_bill.billing_amount_cny
       OR (v_income.source_snapshot->>'previous_carryover_cny')::numeric
            IS DISTINCT FROM v_bill.previous_carryover_cny
       OR v_income.source_snapshot->>'previous_settlement_month'
            IS DISTINCT FROM v_bill.previous_settlement_month
       OR nullif(v_income.source_snapshot->>'previous_settlement_id','')::uuid
            IS DISTINCT FROM v_bill.previous_settlement_id THEN
        RAISE EXCEPTION 'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE';
      END IF;
      NULL; -- revision wrapper validates after registering revision authority
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE';
    END;
    RETURN QUERY SELECT v_bill.id,v_identity.id,v_income.id,v_bill.student_id,
      v_bill.business_entity_id,v_bill.billing_month,
      p_expected_generation_manifest_sha256,v_bill.planned_lesson_count,
      (v_bill.source_snapshot->>'total_lesson_count')::integer,
      v_bill.planned_lesson_hours,
      (v_bill.source_snapshot->>'total_base_lesson_fee_jpy')::numeric,
      (v_bill.source_snapshot->>'total_aircon_fee_jpy')::numeric,
      v_bill.bill_amount_jpy,v_bill.billing_exchange_rate,
      v_bill.previous_carryover_cny,v_bill.billing_amount_cny,
      v_bill.status,v_income.status,true,'existing atomic tuition generation returned idempotently'::text;
    RETURN;
  END IF;

  v_previous_lock_timeout:=current_setting('lock_timeout');
  PERFORM set_config('lock_timeout','8s',true);
  BEGIN
    LOCK TABLE public.school_lesson_records IN SHARE MODE;
    LOCK TABLE public.school_student_monthly_settlements IN SHARE MODE;
    LOCK TABLE public.school_student_settlement_carryovers IN SHARE MODE;
    LOCK TABLE public.school_student_settlement_adjustment_drafts IN SHARE MODE;
    LOCK TABLE public.school_student_settlement_adjustments IN SHARE MODE;
  EXCEPTION
    WHEN lock_not_available OR deadlock_detected THEN
      PERFORM set_config('lock_timeout',v_previous_lock_timeout,true);
      RAISE EXCEPTION USING
        ERRCODE='55P03',
        MESSAGE='R2_F_C_TUITION_SOURCE_BUSY: 课时或月结数据正在更新，请稍后重新预览并生成。';
  END;
  PERFORM set_config('lock_timeout',v_previous_lock_timeout,true);

  SELECT coalesce(array_agg(candidate.planned_lesson_id ORDER BY candidate.planned_lesson_id),'{}'::uuid[])
  INTO v_initial_ids
  FROM public.school_list_student_tuition_charge_candidates(
    p_student_id,v_student_initial.business_entity_id,btrim(p_billing_month),false
  ) candidate;
  IF cardinality(v_initial_ids)=0 THEN RAISE EXCEPTION 'R2_F_B_CANDIDATES_EMPTY'; END IF;
  PERFORM 1 FROM public.school_lesson_records lesson
  WHERE lesson.id=ANY(v_initial_ids) ORDER BY lesson.id FOR UPDATE;
  SELECT student.* INTO STRICT v_student FROM public.school_students student
  WHERE student.id=p_student_id AND student.app_type='school' FOR UPDATE;
  IF v_student.business_entity_id IS DISTINCT FROM v_student_initial.business_entity_id THEN
    RAISE EXCEPTION 'R2_F_B_BUSINESS_ENTITY_CHANGED_DURING_LOCK';
  END IF;
  PERFORM 1 FROM public.school_student_monthly_settlements settlement
  WHERE settlement.student_id=p_student_id
    AND settlement.business_entity_id=v_student.business_entity_id
    AND settlement.year_month IN (v_previous_month,btrim(p_billing_month))
  ORDER BY settlement.year_month,settlement.id FOR SHARE;

  SELECT * INTO STRICT v_snapshot
  FROM public.school_build_student_tuition_generation_snapshot(
    p_student_id,btrim(p_billing_month),p_billing_exchange_rate
  );
  SELECT coalesce(array_agg(candidate.planned_lesson_id ORDER BY candidate.planned_lesson_id),'{}'::uuid[])
  INTO v_locked_ids FROM public.school_list_student_tuition_charge_candidates(
    p_student_id,v_student.business_entity_id,btrim(p_billing_month),false
  ) candidate;
  IF v_locked_ids IS DISTINCT FROM v_initial_ids THEN
    RAISE EXCEPTION 'R2_F_B_CANDIDATE_SET_CHANGED_DURING_LOCK';
  END IF;
  IF v_snapshot.generation_manifest_sha256 IS DISTINCT FROM p_expected_generation_manifest_sha256 THEN
    RAISE EXCEPTION 'R2_F_B_STALE_GENERATION_MANIFEST';
  END IF;
  IF EXISTS (SELECT 1 FROM public.school_student_tuition_bill_lessons relation
    WHERE relation.planned_lesson_id=ANY(v_locked_ids)
      AND relation.relation_role='canonical_charge') THEN
    RAISE EXCEPTION 'R2_F_B_PLANNED_UUID_ALREADY_FROZEN';
  END IF;

  INSERT INTO public.school_tuition_atomic_writer_context(
    backend_pid,transaction_id,writer_source
  ) VALUES (pg_backend_pid(),txid_current(),'student_tuition_atomic_generate_v1');

  INSERT INTO public.school_student_tuition_bills(
    student_id,business_entity_id,billing_month,previous_settlement_month,
    previous_settlement_id,previous_carryover_cny,planned_lesson_count,
    planned_lesson_hours,planned_lesson_fee_jpy,bill_amount_jpy,currency,status,
    source_snapshot,note,app_type,created_by,updated_by,created_at,updated_at,
    billing_exchange_rate,billing_amount_cny,billing_amount_calculated_at,
    billing_role,cash_submission_blocked
  ) VALUES (
    v_snapshot.student_id,v_snapshot.business_entity_id,v_snapshot.billing_month,
    v_snapshot.previous_settlement_month,v_snapshot.previous_settlement_id,
    v_snapshot.previous_carryover_cny,v_snapshot.candidate_count,
    v_snapshot.total_duration_hours,v_snapshot.total_fee_jpy,
    v_snapshot.total_fee_jpy,'JPY','draft',jsonb_build_object(
      'generation_source','student_tuition_atomic_generate_v1',
      'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
      'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256,
      'candidate_uuid_md5',v_snapshot.candidate_uuid_md5,
      'student_id',v_snapshot.student_id,
      'business_entity_id',v_snapshot.business_entity_id,
      'billing_month',v_snapshot.billing_month,
      'previous_settlement_month',v_snapshot.previous_settlement_month,
      'previous_settlement_id',v_snapshot.previous_settlement_id,
      'previous_carryover_cny',v_snapshot.previous_carryover_cny,
      'carryover_evidence',v_snapshot.carryover_evidence,
      'carryover_evidence_sha256',encode(sha256(convert_to(v_snapshot.carryover_evidence::text,'UTF8')),'hex'),
      'candidate_count',v_snapshot.candidate_count,
      'total_lesson_count',v_snapshot.total_lesson_count,
      'total_duration_hours',v_snapshot.total_duration_hours,
      'total_base_lesson_fee_jpy',v_snapshot.total_base_lesson_fee_jpy,
      'total_aircon_fee_jpy',v_snapshot.total_aircon_fee_jpy,
      'total_fee_jpy',v_snapshot.total_fee_jpy,
      'planned_lesson_ids',(SELECT jsonb_agg(line->'planned_lesson_id') FROM jsonb_array_elements(v_snapshot.candidates) line),
      'candidate_lines',v_snapshot.candidates,
      'billing_exchange_rate',v_snapshot.billing_exchange_rate,
      'billing_amount_cny',v_snapshot.billing_amount_cny,
      'billing_amount_currency','CNY'
    ),v_note,'school',v_operator,v_operator,v_now,v_now,
    v_snapshot.billing_exchange_rate,v_snapshot.billing_amount_cny,v_now,
    'canonical_charge',false
  ) RETURNING * INTO v_bill;

  INSERT INTO public.school_student_tuition_billing_identities(
    student_id,billing_month,canonical_bill_id,creation_idempotency_key,
    source,created_by,evidence
  ) VALUES (
    v_snapshot.student_id,v_snapshot.billing_month,v_bill.id,
    'student_tuition_atomic_generate_v1:'||v_snapshot.generation_manifest_sha256,
    'atomic_charge',v_operator,jsonb_build_object(
      'generation_source','student_tuition_atomic_generate_v1',
      'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
      'business_entity_id',v_snapshot.business_entity_id,
      'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256,
      'carryover_evidence_sha256',encode(sha256(convert_to(v_snapshot.carryover_evidence::text,'UTF8')),'hex')
    )
  ) RETURNING * INTO v_identity;

  FOR v_line IN SELECT value FROM jsonb_array_elements(v_snapshot.candidates) LOOP
    v_line_no:=v_line_no+1;
    INSERT INTO public.school_student_tuition_bill_lessons(
      tuition_bill_id,planned_lesson_id,relation_role,line_no,
      student_id_snapshot,business_entity_id_snapshot,billing_month_snapshot,
      week_start_date_snapshot,scheduled_lesson_date_snapshot,
      teacher_id_snapshot,subject_id_snapshot,lesson_count_snapshot,
      duration_hours_snapshot,unit_price_jpy_snapshot,lesson_fee_jpy_snapshot,
      source_lesson_updated_at,source_snapshot,attribution_confidence,
      snapshot_source,created_by,base_lesson_fee_jpy_snapshot,
      aircon_rate_id_snapshot,aircon_unit_price_jpy_snapshot,
      aircon_billable_hours_snapshot,aircon_fee_jpy_snapshot,
      fee_calculation_version_snapshot,lesson_venue_id_snapshot,
      lesson_venue_code_snapshot
    ) VALUES (
      v_bill.id,(v_line->>'planned_lesson_id')::uuid,'canonical_charge',v_line_no,
      (v_line->>'student_id')::uuid,(v_line->>'business_entity_id')::uuid,
      v_line->>'billing_month',(v_line->>'billing_week_start_date')::date,
      (v_line->>'lesson_date')::date,(v_line->>'teacher_id')::uuid,
      (v_line->>'subject_id')::uuid,(v_line->>'lesson_count')::integer,
      (v_line->>'duration_hours')::numeric,(v_line->>'unit_price_jpy')::numeric,
      (v_line->>'course_total_jpy')::numeric,
      (v_line->>'source_lesson_updated_at')::timestamptz,
      v_line||jsonb_build_object(
        'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
        'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256
      ),'high','student_tuition_atomic_generate_v1',v_operator,
      (v_line->>'base_lesson_fee_jpy')::numeric,NULL,
      (v_line->>'aircon_rate_jpy_per_hour')::integer,
      (v_line->>'aircon_billable_hours')::numeric,
      (v_line->>'aircon_fee_jpy')::numeric,v_line->>'fee_policy_version',
      nullif(v_line->>'lesson_venue_id','')::uuid,v_line->>'lesson_venue_code'
    );
  END LOOP;

  IF p_test_fail_after_step='after_relations' THEN
    RAISE EXCEPTION 'R2_F_B_INJECTED_FAILURE_AFTER_RELATIONS';
  END IF;

  INSERT INTO public.school_income_records(
    business_entity_id,student_id,student_payment_id,account_id,income_date,
    year_month,settlement_month,income_category,description,currency,amount,
    amount_jpy,amount_cny,exchange_rate,payment_currency,payment_method,status,
    is_taxable_income,tax_category,receipt_status,include_in_student_settlement,
    note,source_type,source_id,source_label,source_snapshot,app_type,
    created_at,updated_at,tuition_bill_id,cash_submission_blocked,operational_excluded
  ) VALUES (
    v_snapshot.business_entity_id,v_snapshot.student_id,NULL,NULL,current_date,
    v_snapshot.billing_month,v_snapshot.billing_month,'tuition',
    v_snapshot.billing_month||' 学费应收','JPY',v_snapshot.total_fee_jpy,
    v_snapshot.total_fee_jpy,NULL,NULL,'JPY',NULL,'pending',false,NULL,
    'Cash待提交',true,v_note,'student_tuition_bill',v_bill.id,
    v_snapshot.billing_month||' 学费应收',jsonb_build_object(
      'generation_source','student_tuition_atomic_generate_v1',
      'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
      'tuition_bill_id',v_bill.id,'billing_identity_id',v_identity.id,
      'billing_month',v_snapshot.billing_month,
      'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256,
      'candidate_count',v_snapshot.candidate_count,
      'total_lesson_count',v_snapshot.total_lesson_count,
      'total_base_lesson_fee_jpy',v_snapshot.total_base_lesson_fee_jpy,
      'total_aircon_fee_jpy',v_snapshot.total_aircon_fee_jpy,
      'total_fee_jpy',v_snapshot.total_fee_jpy,
      'previous_settlement_month',v_snapshot.previous_settlement_month,
      'previous_settlement_id',v_snapshot.previous_settlement_id,
      'previous_carryover_cny',v_snapshot.previous_carryover_cny,
      'carryover_evidence_sha256',encode(sha256(convert_to(v_snapshot.carryover_evidence::text,'UTF8')),'hex'),
      'billing_exchange_rate',v_snapshot.billing_exchange_rate,
      'billing_amount_cny',v_snapshot.billing_amount_cny,
      'billing_amount_currency','CNY'
    ),'school',v_now,v_now,v_bill.id,false,false
  ) RETURNING * INTO v_income;

  UPDATE public.school_student_tuition_bills bill SET
    status='income_created',income_record_id=v_income.id,income_created_at=v_now,
    updated_by=v_operator,updated_at=v_now
  WHERE bill.id=v_bill.id RETURNING * INTO v_bill;

  DELETE FROM public.school_tuition_atomic_writer_context context_row
  WHERE context_row.backend_pid=pg_backend_pid()
    AND context_row.transaction_id=txid_current();

  NULL; -- revision wrapper validates after registering revision authority

  RETURN QUERY SELECT v_bill.id,v_identity.id,v_income.id,v_snapshot.student_id,
    v_snapshot.business_entity_id,v_snapshot.billing_month,
    v_snapshot.generation_manifest_sha256,v_snapshot.candidate_count,
    v_snapshot.total_lesson_count,v_snapshot.total_duration_hours,
    v_snapshot.total_base_lesson_fee_jpy,v_snapshot.total_aircon_fee_jpy,
    v_snapshot.total_fee_jpy,v_snapshot.billing_exchange_rate,
    v_snapshot.previous_carryover_cny,v_snapshot.billing_amount_cny,
    v_bill.status,v_income.status,false,'atomic tuition bill, identity, relations and pending income created'::text;
END
$function$

-- ---- 还原 public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text)
CREATE OR REPLACE FUNCTION public.school_generate_student_tuition_next_revision_core(p_generation_identity_id uuid, p_previous_revision_id uuid, p_student_id uuid, p_billing_month text, p_billing_exchange_rate numeric, p_expected_generation_manifest_sha256 text, p_note text, p_test_fail_after_step text)
 RETURNS TABLE(tuition_bill_id uuid, billing_identity_id uuid, income_record_id uuid, student_id uuid, business_entity_id uuid, billing_month text, generation_manifest_sha256 text, candidate_count integer, total_lesson_count integer, total_duration_hours numeric, total_base_lesson_fee_jpy numeric, total_aircon_fee_jpy numeric, total_fee_jpy numeric, billing_exchange_rate numeric, previous_carryover_cny numeric, billing_amount_cny numeric, bill_status text, income_status text, idempotent boolean, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_generation public.school_student_tuition_generation_identities%rowtype;
  v_previous public.school_student_tuition_generation_revisions%rowtype;
  v_legacy public.school_student_tuition_billing_identities%rowtype;
  v_bill public.school_student_tuition_bills%rowtype;
  v_income public.school_income_records%rowtype;
  v_snapshot record; v_ids uuid[]; v_locked_ids uuid[]; v_line jsonb; v_line_no integer:=0;
  v_revision_no integer; v_revision_id uuid:=gen_random_uuid();
  v_now timestamptz:=clock_timestamp(); v_note text:=nullif(btrim(coalesce(p_note,'')),'');
  v_operator text:=coalesce(nullif(current_setting('school.tuition_operator_authority',true),''),'service_role_v2_operations_v1');
begin
  select g.* into strict v_generation from public.school_student_tuition_generation_identities g
  where g.id=p_generation_identity_id for update;
  select r.* into strict v_previous from public.school_student_tuition_generation_revisions r
  where r.id=p_previous_revision_id and r.generation_identity_id=v_generation.id for update;
  if v_previous.lifecycle_status<>'voided' or v_previous.manifest_kind<>'atomic_generation_v1' then
    raise exception 'TUITION_REISSUE_PREVIOUS_REVISION_INVALID';
  end if;
  v_revision_no:=v_previous.revision_no+1;
  select i.* into strict v_legacy from public.school_student_tuition_billing_identities i
  where i.id=v_generation.legacy_billing_identity_id;
  lock table public.school_lesson_records in share mode;
  lock table public.school_student_monthly_settlements in share mode;
  lock table public.school_student_settlement_carryovers in share mode;
  lock table public.school_student_settlement_adjustment_drafts in share mode;
  select coalesce(array_agg(c.planned_lesson_id order by c.planned_lesson_id),'{}'::uuid[])
    into v_ids from public.school_list_student_tuition_charge_candidates(
      p_student_id,v_generation.business_entity_id,p_billing_month,false) c;
  if cardinality(v_ids)=0 then raise exception 'R2_F_B_CANDIDATES_EMPTY'; end if;
  perform public.school_assert_active_tuition_lesson_claim(x) from unnest(v_ids) x order by x;
  perform 1 from public.school_lesson_records l where l.id=any(v_ids) order by l.id for update;
  select * into strict v_snapshot from public.school_build_student_tuition_generation_snapshot(
    p_student_id,p_billing_month,p_billing_exchange_rate);
  select coalesce(array_agg(c.planned_lesson_id order by c.planned_lesson_id),'{}'::uuid[])
    into v_locked_ids from public.school_list_student_tuition_charge_candidates(
      p_student_id,v_generation.business_entity_id,p_billing_month,false) c;
  if v_locked_ids is distinct from v_ids then raise exception 'R2_F_B_CANDIDATE_SET_CHANGED_DURING_LOCK'; end if;
  if v_snapshot.generation_manifest_sha256 is distinct from p_expected_generation_manifest_sha256 then
    raise exception 'R2_F_B_STALE_GENERATION_MANIFEST';
  end if;
  insert into public.school_tuition_atomic_writer_context(backend_pid,transaction_id,writer_source)
  values(pg_backend_pid(),txid_current(),'student_tuition_atomic_generate_v1');
  insert into public.school_student_tuition_bills(
    student_id,business_entity_id,billing_month,previous_settlement_month,
    previous_settlement_id,previous_carryover_cny,planned_lesson_count,
    planned_lesson_hours,planned_lesson_fee_jpy,bill_amount_jpy,currency,status,
    source_snapshot,note,app_type,created_by,updated_by,created_at,updated_at,
    billing_exchange_rate,billing_amount_cny,billing_amount_calculated_at,
    billing_role,cash_submission_blocked
  ) values(
    v_snapshot.student_id,v_snapshot.business_entity_id,v_snapshot.billing_month,
    v_snapshot.previous_settlement_month,v_snapshot.previous_settlement_id,
    v_snapshot.previous_carryover_cny,v_snapshot.candidate_count,v_snapshot.total_duration_hours,
    v_snapshot.total_fee_jpy,v_snapshot.total_fee_jpy,'JPY','draft',jsonb_build_object(
      'generation_source','student_tuition_atomic_generate_v1',
      'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
      'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256,
      'candidate_uuid_md5',v_snapshot.candidate_uuid_md5,
      'generation_identity_id',v_generation.id,'generation_revision_id',v_revision_id,
      'revision_no',v_revision_no,'previous_revision_id',v_previous.id,
      'student_id',v_snapshot.student_id,'business_entity_id',v_snapshot.business_entity_id,
      'billing_month',v_snapshot.billing_month,'previous_settlement_month',v_snapshot.previous_settlement_month,
      'previous_settlement_id',v_snapshot.previous_settlement_id,
      'previous_carryover_cny',v_snapshot.previous_carryover_cny,
      'carryover_evidence',v_snapshot.carryover_evidence,
      'carryover_evidence_sha256',encode(sha256(convert_to(v_snapshot.carryover_evidence::text,'UTF8')),'hex'),
      'candidate_count',v_snapshot.candidate_count,'total_lesson_count',v_snapshot.total_lesson_count,
      'total_duration_hours',v_snapshot.total_duration_hours,
      'total_base_lesson_fee_jpy',v_snapshot.total_base_lesson_fee_jpy,
      'total_aircon_fee_jpy',v_snapshot.total_aircon_fee_jpy,'total_fee_jpy',v_snapshot.total_fee_jpy,
      'planned_lesson_ids',(select jsonb_agg(line->'planned_lesson_id') from jsonb_array_elements(v_snapshot.candidates) line),
      'candidate_lines',v_snapshot.candidates,'billing_exchange_rate',v_snapshot.billing_exchange_rate,
      'billing_amount_cny',v_snapshot.billing_amount_cny,'billing_amount_currency','CNY'
    ),v_note,'school',v_operator,v_operator,v_now,v_now,v_snapshot.billing_exchange_rate,
    v_snapshot.billing_amount_cny,v_now,'canonical_charge',false
  ) returning * into v_bill;
  for v_line in select value from jsonb_array_elements(v_snapshot.candidates) loop
    v_line_no:=v_line_no+1;
    insert into public.school_student_tuition_bill_lessons(
      tuition_bill_id,planned_lesson_id,relation_role,line_no,student_id_snapshot,
      business_entity_id_snapshot,billing_month_snapshot,week_start_date_snapshot,
      scheduled_lesson_date_snapshot,teacher_id_snapshot,subject_id_snapshot,
      lesson_count_snapshot,duration_hours_snapshot,unit_price_jpy_snapshot,
      lesson_fee_jpy_snapshot,source_lesson_updated_at,source_snapshot,attribution_confidence,
      snapshot_source,created_by,base_lesson_fee_jpy_snapshot,aircon_rate_id_snapshot,
      aircon_unit_price_jpy_snapshot,aircon_billable_hours_snapshot,aircon_fee_jpy_snapshot,
      fee_calculation_version_snapshot,lesson_venue_id_snapshot,lesson_venue_code_snapshot
    ) values(
      v_bill.id,(v_line->>'planned_lesson_id')::uuid,'canonical_charge',v_line_no,
      (v_line->>'student_id')::uuid,(v_line->>'business_entity_id')::uuid,v_line->>'billing_month',
      (v_line->>'billing_week_start_date')::date,(v_line->>'lesson_date')::date,
      (v_line->>'teacher_id')::uuid,(v_line->>'subject_id')::uuid,
      (v_line->>'lesson_count')::integer,(v_line->>'duration_hours')::numeric,
      (v_line->>'unit_price_jpy')::numeric,(v_line->>'course_total_jpy')::numeric,
      (v_line->>'source_lesson_updated_at')::timestamptz,
      v_line||jsonb_build_object('generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
        'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256),
      'high','student_tuition_atomic_generate_v1',v_operator,
      (v_line->>'base_lesson_fee_jpy')::numeric,null,
      (v_line->>'aircon_rate_jpy_per_hour')::integer,(v_line->>'aircon_billable_hours')::numeric,
      (v_line->>'aircon_fee_jpy')::numeric,v_line->>'fee_policy_version',
      nullif(v_line->>'lesson_venue_id','')::uuid,v_line->>'lesson_venue_code');
  end loop;
  if p_test_fail_after_step='after_relations' then raise exception 'R2_F_B_INJECTED_FAILURE_AFTER_RELATIONS'; end if;
  insert into public.school_income_records(
    business_entity_id,student_id,student_payment_id,account_id,income_date,year_month,
    settlement_month,income_category,description,currency,amount,amount_jpy,amount_cny,
    exchange_rate,payment_currency,payment_method,status,is_taxable_income,tax_category,
    receipt_status,include_in_student_settlement,note,source_type,source_id,source_label,
    source_snapshot,app_type,created_at,updated_at,tuition_bill_id,cash_submission_blocked,
    operational_excluded
  ) values(
    v_snapshot.business_entity_id,v_snapshot.student_id,null,null,current_date,v_snapshot.billing_month,
    v_snapshot.billing_month,'tuition',v_snapshot.billing_month||' 学费应收','JPY',
    v_snapshot.total_fee_jpy,v_snapshot.total_fee_jpy,null,null,'JPY',null,'pending',false,null,
    'Cash待提交',true,v_note,'student_tuition_bill',v_bill.id,v_snapshot.billing_month||' 学费应收',
    jsonb_build_object('generation_source','student_tuition_atomic_generate_v1',
      'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,'tuition_bill_id',v_bill.id,
      'billing_identity_id',v_legacy.id,'generation_identity_id',v_generation.id,
      'generation_revision_id',v_revision_id,'revision_no',v_revision_no,
      'billing_month',v_snapshot.billing_month,'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256,
      'candidate_count',v_snapshot.candidate_count,'total_lesson_count',v_snapshot.total_lesson_count,
      'total_base_lesson_fee_jpy',v_snapshot.total_base_lesson_fee_jpy,
      'total_aircon_fee_jpy',v_snapshot.total_aircon_fee_jpy,'total_fee_jpy',v_snapshot.total_fee_jpy,
      'previous_settlement_month',v_snapshot.previous_settlement_month,
      'previous_settlement_id',v_snapshot.previous_settlement_id,
      'previous_carryover_cny',v_snapshot.previous_carryover_cny,
      'carryover_evidence_sha256',encode(sha256(convert_to(v_snapshot.carryover_evidence::text,'UTF8')),'hex'),
      'billing_exchange_rate',v_snapshot.billing_exchange_rate,'billing_amount_cny',v_snapshot.billing_amount_cny,
      'billing_amount_currency','CNY'),'school',v_now,v_now,v_bill.id,false,false
  ) returning * into v_income;
  update public.school_student_tuition_bills set status='income_created',income_record_id=v_income.id,
    income_created_at=v_now,updated_by=v_operator,updated_at=v_now where id=v_bill.id returning * into v_bill;
  insert into public.school_student_tuition_generation_revisions(
    id,generation_identity_id,tuition_bill_id,revision_no,previous_revision_id,
    generation_manifest_sha256,manifest_kind,lifecycle_status,created_at,created_by_authority,
    activated_at,voided_at,voided_by_authority
  ) values(v_revision_id,v_generation.id,v_bill.id,v_revision_no,v_previous.id,
    v_snapshot.generation_manifest_sha256,'atomic_generation_v1','active',v_now,v_operator,
    v_now,null,null);
  delete from public.school_tuition_atomic_writer_context where backend_pid=pg_backend_pid()
    and transaction_id=txid_current();
  perform public.school_validate_tuition_identity_for_bill(v_bill.id);
  perform public.school_validate_tuition_bill_income_for_bill(v_bill.id);
  perform public.school_validate_tuition_bill_lessons_for_bill(v_bill.id);
  return query select v_bill.id,v_legacy.id,v_income.id,v_snapshot.student_id,
    v_snapshot.business_entity_id,v_snapshot.billing_month,v_snapshot.generation_manifest_sha256,
    v_snapshot.candidate_count,v_snapshot.total_lesson_count,v_snapshot.total_duration_hours,
    v_snapshot.total_base_lesson_fee_jpy,v_snapshot.total_aircon_fee_jpy,v_snapshot.total_fee_jpy,
    v_snapshot.billing_exchange_rate,v_snapshot.previous_carryover_cny,v_snapshot.billing_amount_cny,
    v_bill.status,v_income.status,false,'atomic tuition revision created'::text;
end;
$function$

-- ---- 还原 public.school_generate_student_tuition_next_revision_p0e_core(uuid,uuid,uuid,text,numeric,text,text,text)
CREATE OR REPLACE FUNCTION public.school_generate_student_tuition_next_revision_p0e_core(p_generation_identity_id uuid, p_previous_revision_id uuid, p_student_id uuid, p_billing_month text, p_billing_exchange_rate numeric, p_expected_generation_manifest_sha256 text, p_note text, p_test_fail_after_step text)
 RETURNS TABLE(tuition_bill_id uuid, billing_identity_id uuid, income_record_id uuid, student_id uuid, business_entity_id uuid, billing_month text, generation_manifest_sha256 text, candidate_count integer, total_lesson_count integer, total_duration_hours numeric, total_base_lesson_fee_jpy numeric, total_aircon_fee_jpy numeric, total_fee_jpy numeric, billing_exchange_rate numeric, previous_carryover_cny numeric, billing_amount_cny numeric, bill_status text, income_status text, idempotent boolean, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_generation public.school_student_tuition_generation_identities%rowtype;
  v_previous public.school_student_tuition_generation_revisions%rowtype;
  v_legacy public.school_student_tuition_billing_identities%rowtype;
  v_bill public.school_student_tuition_bills%rowtype;
  v_income public.school_income_records%rowtype;
  v_snapshot record; v_ids uuid[]; v_locked_ids uuid[]; v_line jsonb; v_line_no integer:=0;
  v_revision_no integer; v_revision_id uuid:=gen_random_uuid();
  v_now timestamptz:=clock_timestamp(); v_note text:=nullif(btrim(coalesce(p_note,'')),'');
  v_operator text:=coalesce(nullif(current_setting('school.tuition_operator_authority',true),''),'service_role_v2_operations_v1');
begin
  select g.* into strict v_generation from public.school_student_tuition_generation_identities g
  where g.id=p_generation_identity_id for update;
  select r.* into strict v_previous from public.school_student_tuition_generation_revisions r
  where r.id=p_previous_revision_id and r.generation_identity_id=v_generation.id for update;
  if v_previous.lifecycle_status<>'voided' or v_previous.manifest_kind<>'atomic_generation_v1' then
    raise exception 'TUITION_REISSUE_PREVIOUS_REVISION_INVALID';
  end if;
  v_revision_no:=v_previous.revision_no+1;
  select i.* into strict v_legacy from public.school_student_tuition_billing_identities i
  where i.id=v_generation.legacy_billing_identity_id;
  lock table public.school_lesson_records in share mode;
  lock table public.school_student_monthly_settlements in share mode;
  lock table public.school_student_settlement_carryovers in share mode;
  lock table public.school_student_settlement_adjustment_drafts in share mode;
  select coalesce(array_agg(c.planned_lesson_id order by c.planned_lesson_id),'{}'::uuid[])
    into v_ids from public.school_list_student_tuition_charge_candidates(
      p_student_id,v_generation.business_entity_id,p_billing_month,false) c;
  if cardinality(v_ids)=0 then raise exception 'R2_F_B_CANDIDATES_EMPTY'; end if;
  perform public.school_assert_active_tuition_lesson_claim(x) from unnest(v_ids) x order by x;
  perform 1 from public.school_lesson_records l where l.id=any(v_ids) order by l.id for update;
  select * into strict v_snapshot from public.school_build_student_tuition_generation_snapshot(
    p_student_id,p_billing_month,p_billing_exchange_rate);
  if v_snapshot.candidate_manifest_sha256 is distinct from current_setting('tuition.p0e_candidate_manifest',true)
     or v_snapshot.total_fee_jpy is distinct from current_setting('tuition.p0e_total_fee_jpy',true)::numeric then
    raise exception 'TUITION_P0E_EXPECTED_FACT_MISMATCH';
  end if;
  select b.* into strict v_bill from public.school_student_tuition_bills b where b.id=v_previous.tuition_bill_id;
  if v_bill.previous_settlement_id is distinct from current_setting('tuition.p0e_source_settlement_id',true)::uuid
     or round(v_bill.previous_carryover_cny,2) is distinct from current_setting('tuition.p0e_historical_carry',true)::numeric
     or public.school_tuition_p0a_consumed_bill_id(v_bill.previous_settlement_id) is distinct from v_bill.id then
    raise exception 'TUITION_P0E_SOURCE_EVIDENCE_CHANGED';
  end if;
  v_snapshot.previous_settlement_month:=v_bill.previous_settlement_month;
  v_snapshot.previous_settlement_id:=v_bill.previous_settlement_id;
  v_snapshot.previous_carryover_cny:=v_bill.previous_carryover_cny;
  v_snapshot.carryover_evidence:=v_bill.source_snapshot->'carryover_evidence';
  v_snapshot.billing_amount_cny:=current_setting('tuition.p0e_final_amount',true)::numeric;
  v_snapshot.generation_manifest_sha256:=p_expected_generation_manifest_sha256;
  select coalesce(array_agg(c.planned_lesson_id order by c.planned_lesson_id),'{}'::uuid[])
    into v_locked_ids from public.school_list_student_tuition_charge_candidates(
      p_student_id,v_generation.business_entity_id,p_billing_month,false) c;
  if v_locked_ids is distinct from v_ids then raise exception 'R2_F_B_CANDIDATE_SET_CHANGED_DURING_LOCK'; end if;
  if v_snapshot.generation_manifest_sha256 is distinct from p_expected_generation_manifest_sha256 then
    raise exception 'R2_F_B_STALE_GENERATION_MANIFEST';
  end if;
  insert into public.school_tuition_atomic_writer_context(backend_pid,transaction_id,writer_source)
  values(pg_backend_pid(),txid_current(),'student_tuition_atomic_generate_v1');
  insert into public.school_student_tuition_bills(
    student_id,business_entity_id,billing_month,previous_settlement_month,
    previous_settlement_id,previous_carryover_cny,planned_lesson_count,
    planned_lesson_hours,planned_lesson_fee_jpy,bill_amount_jpy,currency,status,
    source_snapshot,note,app_type,created_by,updated_by,created_at,updated_at,
    billing_exchange_rate,billing_amount_cny,billing_amount_calculated_at,
    billing_role,cash_submission_blocked
  ) values(
    v_snapshot.student_id,v_snapshot.business_entity_id,v_snapshot.billing_month,
    v_snapshot.previous_settlement_month,v_snapshot.previous_settlement_id,
    v_snapshot.previous_carryover_cny,v_snapshot.candidate_count,v_snapshot.total_duration_hours,
    v_snapshot.total_fee_jpy,v_snapshot.total_fee_jpy,'JPY','draft',jsonb_build_object(
      'generation_source','student_tuition_atomic_generate_v1',
      'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
      'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256,
      'candidate_uuid_md5',v_snapshot.candidate_uuid_md5,
      'generation_identity_id',v_generation.id,'generation_revision_id',v_revision_id,
      'revision_no',v_revision_no,'previous_revision_id',v_previous.id,
      'student_id',v_snapshot.student_id,'business_entity_id',v_snapshot.business_entity_id,
      'billing_month',v_snapshot.billing_month,'previous_settlement_month',v_snapshot.previous_settlement_month,
      'previous_settlement_id',v_snapshot.previous_settlement_id,
      'previous_carryover_cny',v_snapshot.previous_carryover_cny,
      'carryover_evidence',v_snapshot.carryover_evidence,
      'carryover_evidence_sha256',encode(sha256(convert_to(v_snapshot.carryover_evidence::text,'UTF8')),'hex'),
      'candidate_count',v_snapshot.candidate_count,'total_lesson_count',v_snapshot.total_lesson_count,
      'total_duration_hours',v_snapshot.total_duration_hours,
      'total_base_lesson_fee_jpy',v_snapshot.total_base_lesson_fee_jpy,
      'total_aircon_fee_jpy',v_snapshot.total_aircon_fee_jpy,'total_fee_jpy',v_snapshot.total_fee_jpy,
      'planned_lesson_ids',(select jsonb_agg(line->'planned_lesson_id') from jsonb_array_elements(v_snapshot.candidates) line),
      'candidate_lines',v_snapshot.candidates,'billing_exchange_rate',v_snapshot.billing_exchange_rate,
      'billing_amount_cny',v_snapshot.billing_amount_cny,'billing_amount_currency','CNY','forward_adjustment',current_setting('tuition.p0e_snapshot',true)::jsonb
    ),v_note,'school',v_operator,v_operator,v_now,v_now,v_snapshot.billing_exchange_rate,
    v_snapshot.billing_amount_cny,v_now,'canonical_charge',false
  ) returning * into v_bill;
  for v_line in select value from jsonb_array_elements(v_snapshot.candidates) loop
    v_line_no:=v_line_no+1;
    insert into public.school_student_tuition_bill_lessons(
      tuition_bill_id,planned_lesson_id,relation_role,line_no,student_id_snapshot,
      business_entity_id_snapshot,billing_month_snapshot,week_start_date_snapshot,
      scheduled_lesson_date_snapshot,teacher_id_snapshot,subject_id_snapshot,
      lesson_count_snapshot,duration_hours_snapshot,unit_price_jpy_snapshot,
      lesson_fee_jpy_snapshot,source_lesson_updated_at,source_snapshot,attribution_confidence,
      snapshot_source,created_by,base_lesson_fee_jpy_snapshot,aircon_rate_id_snapshot,
      aircon_unit_price_jpy_snapshot,aircon_billable_hours_snapshot,aircon_fee_jpy_snapshot,
      fee_calculation_version_snapshot,lesson_venue_id_snapshot,lesson_venue_code_snapshot
    ) values(
      v_bill.id,(v_line->>'planned_lesson_id')::uuid,'canonical_charge',v_line_no,
      (v_line->>'student_id')::uuid,(v_line->>'business_entity_id')::uuid,v_line->>'billing_month',
      (v_line->>'billing_week_start_date')::date,(v_line->>'lesson_date')::date,
      (v_line->>'teacher_id')::uuid,(v_line->>'subject_id')::uuid,
      (v_line->>'lesson_count')::integer,(v_line->>'duration_hours')::numeric,
      (v_line->>'unit_price_jpy')::numeric,(v_line->>'course_total_jpy')::numeric,
      (v_line->>'source_lesson_updated_at')::timestamptz,
      v_line||jsonb_build_object('generation_manifest_sha256',v_snapshot.generation_manifest_sha256,
        'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256),
      'high','student_tuition_atomic_generate_v1',v_operator,
      (v_line->>'base_lesson_fee_jpy')::numeric,null,
      (v_line->>'aircon_rate_jpy_per_hour')::integer,(v_line->>'aircon_billable_hours')::numeric,
      (v_line->>'aircon_fee_jpy')::numeric,v_line->>'fee_policy_version',
      nullif(v_line->>'lesson_venue_id','')::uuid,v_line->>'lesson_venue_code');
  end loop;
  if p_test_fail_after_step='after_relations' then raise exception 'R2_F_B_INJECTED_FAILURE_AFTER_RELATIONS'; end if;
  insert into public.school_income_records(
    business_entity_id,student_id,student_payment_id,account_id,income_date,year_month,
    settlement_month,income_category,description,currency,amount,amount_jpy,amount_cny,
    exchange_rate,payment_currency,payment_method,status,is_taxable_income,tax_category,
    receipt_status,include_in_student_settlement,note,source_type,source_id,source_label,
    source_snapshot,app_type,created_at,updated_at,tuition_bill_id,cash_submission_blocked,
    operational_excluded
  ) values(
    v_snapshot.business_entity_id,v_snapshot.student_id,null,null,current_date,v_snapshot.billing_month,
    v_snapshot.billing_month,'tuition',v_snapshot.billing_month||' 学费应收','JPY',
    v_snapshot.total_fee_jpy,v_snapshot.total_fee_jpy,null,null,'JPY',null,'pending',false,null,
    'Cash待提交',true,v_note,'student_tuition_bill',v_bill.id,v_snapshot.billing_month||' 学费应收',
    jsonb_build_object('generation_source','student_tuition_atomic_generate_v1',
      'generation_manifest_sha256',v_snapshot.generation_manifest_sha256,'tuition_bill_id',v_bill.id,
      'billing_identity_id',v_legacy.id,'generation_identity_id',v_generation.id,
      'generation_revision_id',v_revision_id,'revision_no',v_revision_no,
      'billing_month',v_snapshot.billing_month,'candidate_manifest_sha256',v_snapshot.candidate_manifest_sha256,
      'candidate_count',v_snapshot.candidate_count,'total_lesson_count',v_snapshot.total_lesson_count,
      'total_base_lesson_fee_jpy',v_snapshot.total_base_lesson_fee_jpy,
      'total_aircon_fee_jpy',v_snapshot.total_aircon_fee_jpy,'total_fee_jpy',v_snapshot.total_fee_jpy,
      'previous_settlement_month',v_snapshot.previous_settlement_month,
      'previous_settlement_id',v_snapshot.previous_settlement_id,
      'previous_carryover_cny',v_snapshot.previous_carryover_cny,
      'carryover_evidence_sha256',encode(sha256(convert_to(v_snapshot.carryover_evidence::text,'UTF8')),'hex'),
      'billing_exchange_rate',v_snapshot.billing_exchange_rate,'billing_amount_cny',v_snapshot.billing_amount_cny,
      'billing_amount_currency','CNY','forward_adjustment',current_setting('tuition.p0e_snapshot',true)::jsonb),'school',v_now,v_now,v_bill.id,false,false
  ) returning * into v_income;
  update public.school_student_tuition_bills set status='income_created',income_record_id=v_income.id,
    income_created_at=v_now,updated_by=v_operator,updated_at=v_now where id=v_bill.id returning * into v_bill;
  insert into public.school_student_tuition_generation_revisions(
    id,generation_identity_id,tuition_bill_id,revision_no,previous_revision_id,
    generation_manifest_sha256,manifest_kind,lifecycle_status,created_at,created_by_authority,
    activated_at,voided_at,voided_by_authority
  ) values(v_revision_id,v_generation.id,v_bill.id,v_revision_no,v_previous.id,
    v_snapshot.generation_manifest_sha256,'atomic_generation_v1','active',v_now,v_operator,
    v_now,null,null);
  insert into public.school_student_tuition_generation_revision_adjustments(
    generation_identity_id,target_revision_id,target_billing_month,source_previous_revision_id,
    source_settlement_id,adjustment_type,amount_cny,source_historical_carryover_cny,
    reason,operator_authority,line_manifest_sha256
  ) values(v_generation.id,v_revision_id,v_generation.billing_month,v_previous.id,
    current_setting('tuition.p0e_source_settlement_id',true)::uuid,
    'neutralize_historical_carryover_v1',current_setting('tuition.p0e_adjustment',true)::numeric,
    current_setting('tuition.p0e_historical_carry',true)::numeric,
    current_setting('tuition.p0e_reason',true),'local_trusted_business_owner_v1',
    current_setting('tuition.p0e_line_manifest',true));
  delete from public.school_tuition_atomic_writer_context where backend_pid=pg_backend_pid()
    and transaction_id=txid_current();
  perform public.school_validate_tuition_identity_for_bill(v_bill.id);
  perform public.school_validate_tuition_bill_income_for_bill(v_bill.id);
  perform public.school_validate_tuition_bill_lessons_for_bill(v_bill.id);
  return query select v_bill.id,v_legacy.id,v_income.id,v_snapshot.student_id,
    v_snapshot.business_entity_id,v_snapshot.billing_month,v_snapshot.generation_manifest_sha256,
    v_snapshot.candidate_count,v_snapshot.total_lesson_count,v_snapshot.total_duration_hours,
    v_snapshot.total_base_lesson_fee_jpy,v_snapshot.total_aircon_fee_jpy,v_snapshot.total_fee_jpy,
    v_snapshot.billing_exchange_rate,v_snapshot.previous_carryover_cny,v_snapshot.billing_amount_cny,
    v_bill.status,v_income.status,false,'atomic tuition revision created'::text;
end;
$function$

-- ---------------------------------------------------------------------------
-- §8 回滚后：全量账单校验扫描
--   只读。记录每张账单当前是否通过 validator。
--   判据是「不新增失败」而不是「全部通过」——生产可能本来就有失败项，
--   拿绝对值当断言会制造假阳性硬停止（lessons E10 第三次发作）。
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE lc2_validation_after(bill_id uuid PRIMARY KEY, ok boolean NOT NULL, err text)
  ON COMMIT DROP;

DO $do$
DECLARE r record;
BEGIN
  FOR r IN SELECT b.id FROM public.school_student_tuition_bills b ORDER BY b.id LOOP
    BEGIN
      PERFORM public.school_validate_tuition_bill_lessons_for_bill(r.id);
      INSERT INTO lc2_validation_after(bill_id,ok,err) VALUES (r.id,true,NULL);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO lc2_validation_after(bill_id,ok,err) VALUES (r.id,false,SQLERRM);
    END;
  END LOOP;
END
$do$;

\echo '--- 回滚后 账单校验汇总 ---'
SELECT count(*) FILTER (WHERE ok)     AS "通过",
       count(*) FILTER (WHERE NOT ok) AS "失败",
       count(*)                       AS "总数"
FROM lc2_validation_after;
SELECT bill_id, err FROM lc2_validation_after WHERE NOT ok ORDER BY bill_id;

-- ---------------------------------------------------------------------------
-- §9 后置断言
-- ---------------------------------------------------------------------------

-- (a) in_scope 的函数必须逐字节回到审查基线；范围外的必须原封不动
DO $do$
DECLARE r record; v_md5 text; v_bad text := '';
BEGIN
  FOR r IN SELECT * FROM lc2_target ORDER BY fn_key LOOP
    v_md5 := md5(pg_get_functiondef(to_regprocedure(r.signature)::oid));
    UPDATE lc2_target SET after_md5 = v_md5 WHERE fn_key = r.fn_key;
    IF r.in_scope THEN
      IF v_md5 IS DISTINCT FROM r.baseline_md5 THEN
        v_bad := v_bad || format(E'\n  %s 未回到基线\n    期望 %s\n    实际 %s',
                                 r.signature, r.baseline_md5, v_md5);
      END IF;
    ELSE
      IF v_md5 IS DISTINCT FROM r.before_md5 THEN
        v_bad := v_bad || format(E'\n  %s 本不该被动却变了\n    前 %s\n    后 %s',
                                 r.signature, r.before_md5, v_md5);
      END IF;
    END IF;
  END LOOP;
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'LC2_ROLLBACK_FIDELITY_FAILED: 还原结果与预期不符。%', v_bad;
  END IF;
END
$do$;

-- (b) 标记核对：in_scope 走 v1，范围外仍应为 v2
DO $do$
DECLARE r record; v_def text; v_hit boolean; v_bad text := '';
BEGIN
  FOR r IN
    SELECT m.fn_key, m.needle, m.must_exist, t.signature
    FROM lc2_marker m JOIN lc2_target t USING (fn_key)
    WHERE m.variant = CASE WHEN t.in_scope THEN 'v1' ELSE 'v2' END
    ORDER BY m.fn_key, m.needle
  LOOP
    v_def := pg_get_functiondef(to_regprocedure(r.signature)::oid);
    v_hit := strpos(v_def, r.needle) > 0;
    IF v_hit IS DISTINCT FROM r.must_exist THEN
      v_bad := v_bad || format(E'\n  %s: 子串 %L 期望%s，实际%s',
        r.fn_key, r.needle,
        CASE WHEN r.must_exist THEN '出现' ELSE '消失' END,
        CASE WHEN v_hit THEN '出现' ELSE '消失' END);
    END IF;
  END LOOP;
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'LC2_MARKER_MISMATCH: 回滚结果与预期不符。%', v_bad;
  END IF;
END
$do$;

-- (c) ACL / owner / 安全属性必须与回滚前完全一致
DO $do$
DECLARE v_bad text := '';
BEGIN
  SELECT string_agg(format(E'\n  %s\n    前 acl=%s owner=%s secdef=%s vol=%s cfg=%s'
                           || E'\n    后 acl=%s owner=%s secdef=%s vol=%s cfg=%s',
                    b.fn_key, b.acl, b.owner, b.prosecdef, b.provolatile, b.proconfig,
                    a.acl, a.owner, a.prosecdef, a.provolatile, a.proconfig), '')
  INTO v_bad
  FROM lc2_acl_before b
  JOIN (
    SELECT t.fn_key,
           coalesce(p.proacl::text,'<default>') AS acl,
           pg_get_userbyid(p.proowner)          AS owner,
           p.prosecdef, p.provolatile, p.proconfig::text AS proconfig
    FROM lc2_target t JOIN pg_proc p ON p.oid = to_regprocedure(t.signature)::oid
  ) a USING (fn_key)
  WHERE (b.acl,b.owner,b.prosecdef,b.provolatile,b.proconfig)
     IS DISTINCT FROM (a.acl,a.owner,a.prosecdef,a.provolatile,a.proconfig);
  IF coalesce(v_bad,'') <> '' THEN
    RAISE EXCEPTION 'LC2_ACL_DRIFT: 函数权限或安全属性被改变，停止。%', v_bad;
  END IF;
END
$do$;

-- (d) 账单校验不得回归：原本通过的一张都不能变成失败
DO $do$
DECLARE v_regressed integer; v_detail text;
BEGIN
  SELECT count(*), string_agg(format(E'\n  %s → %s', b.bill_id, a.err), '')
  INTO v_regressed, v_detail
  FROM lc2_validation_before b JOIN lc2_validation_after a USING (bill_id)
  WHERE b.ok AND NOT a.ok;
  IF v_regressed > 0 THEN
    RAISE EXCEPTION 'LC2_VALIDATION_REGRESSION: % 张原本通过的账单变为失败，停止。%',
      v_regressed, v_detail;
  END IF;
END
$do$;

\echo '--- 由失败转为通过的账单（观测项，不参与判定）---'
SELECT b.bill_id, b.err AS "原失败原因"
FROM lc2_validation_before b JOIN lc2_validation_after a USING (bill_id)
WHERE NOT b.ok AND a.ok
ORDER BY b.bill_id;

-- (e) md5 对照
\echo '--- 六函数 md5：回滚前 → 回滚后 ---'
SELECT fn_key, in_scope AS "本次还原", before_md5 AS "前", after_md5 AS "后",
       baseline_md5 AS "基线"
FROM lc2_target ORDER BY fn_key;

-- ---------------------------------------------------------------------------
-- §10 收尾
--   rehearsal → ROLLBACK（生产零变更，但已经真解析、真还原、真跑完全部断言）
--   commit    → COMMIT
-- ---------------------------------------------------------------------------
SELECT CASE WHEN :'mode' = 'commit' THEN 'true' ELSE 'false' END AS lc2_do_commit \gset

\if :lc2_do_commit
COMMIT;
\echo ''
\echo '>>> COMMIT 已执行：本次 scope 范围内的函数已在同一事务内还原到 2026-09-06 12:05 JST 基线。'
\else
ROLLBACK;
\echo ''
\echo '>>> ROLLBACK 已执行：rehearsal 模式，生产未发生任何变更。'
\endif
