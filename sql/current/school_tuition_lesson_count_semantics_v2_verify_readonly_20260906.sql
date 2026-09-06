-- ===========================================================================
-- lesson_count 语义修复：只读验证 + 写入场景侦察 / 2026-09-06
-- ===========================================================================
--
-- 覆盖设计 §11.1 与 §11.2 中**不需要写入**的场景：3、5、6、7、8、9、10。
-- 需要写入的 1、2、4、11 由后续的 rollback-only 写入脚本承担——
-- 而那份脚本要用哪些样本，正是本脚本 §9 侦察出来的。
-- **先盘点，后断言；没盘点过的东西不配有期望值。**
--
-- 【运行方式】本脚本自成一个事务，**结尾无条件 ROLLBACK，没有 commit 模式**。
--   psql "$DB_URL" -f <本文件>
--   可选参数（都有保守默认值）：
--     -v months_from=2025-01   起始计费月
--     -v months_to=2026-12     结束计费月
--     -v rate=0.05             比对用的汇率占位值
--
-- 【汇率是占位值，不是业务事实】v1/v2 两侧用的是同一个值，所以候选、序号、
--   总次数、日元金额的比对不受影响。但 billing_amount_cny 与
--   generation_manifest_sha256 会因此与任何真实 preview 不同，**不要拿去对账**。
--
-- 【授权边界】与部署脚本 rehearsal 相同：单事务内 CREATE OR REPLACE 六个函数、
--   建临时表、取目录锁，最后强制 ROLLBACK。
--   **无业务表 DML、无 writer RPC、无 COMMIT。**
--   builder 与候选 reader 都是只读的，本脚本只调用它们，不调用任何 writer。
--
-- 【排空】两次快照都读同一个 REPEATABLE READ 事务快照，所以 v1/v2 的差异
--   可归因到本事务替换的六个函数。但**这不构成排空**：晚于快照建立的业务提交
--   本脚本看不到。要让结论对「当下的生产」成立，仍须先排空再开事务。
-- ===========================================================================

\set ON_ERROR_STOP on
\timing on

\if :{?months_from}
\else
\set months_from 2025-01
\endif
\if :{?months_to}
\else
\set months_to 2026-12
\endif
\if :{?rate}
\else
\set rate 0.05
\endif

\echo ''
\echo '================================================================'
\echo 'lesson_count v1/v2 只读验证 + 写入场景侦察'
\echo '月份区间' :months_from '..' :months_to '  汇率占位' :rate
\echo '================================================================'

BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout = '900s';
SET LOCAL lock_timeout = '15s';
SET LOCAL idle_in_transaction_session_timeout = '1800s';

-- ---------------------------------------------------------------------------
-- §0 参数落表并校验（psql 不在美元引用内插值）
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE lc2v_run(months_from text, months_to text, rate numeric) ON COMMIT DROP;
INSERT INTO lc2v_run VALUES (:'months_from', :'months_to', :'rate');

DO $do$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM lc2v_run;
  IF r.months_from !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
     OR r.months_to !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'LC2V_MONTH_INVALID: 月份格式须为 YYYY-MM，收到 % / %',
      r.months_from, r.months_to;
  END IF;
  IF r.months_from > r.months_to THEN
    RAISE EXCEPTION 'LC2V_MONTH_RANGE_INVALID: 起始月晚于结束月';
  END IF;
  IF r.rate IS NULL OR r.rate <= 0 THEN
    RAISE EXCEPTION 'LC2V_RATE_INVALID: 汇率占位值须 > 0，收到 %', r.rate;
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
  after_md5    text
) ON COMMIT DROP;

INSERT INTO lc2_target(fn_key,signature,baseline_md5,purpose) VALUES
 ('candidates','public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)','438b4619ad46b4501199ad3bae45ff87','候选判定：删除 lesson_count 必填两行'),
 ('build','public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)','4e7ddd85b884bf3607f14bb905bd9ed6','builder：新增 ranked_candidates，序号重编 + total 改 count(*)'),
 ('validator','public.school_validate_tuition_bill_lessons_for_bill(uuid)','bb9ff1e1d6e259fafdd64b392a740c3a','validator：v1/v2 版本契约 + bill/income 版本一致性'),
 ('base_core_v1','public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text)','8c7a55f4c9c855598c2df7cc931df943','writer 首次生成：bill/income 快照标 v2'),
 ('next_revision_core','public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text)','28842924bd509321ef21cae10080d238','writer 次轮生成：bill/income 快照标 v2'),
 ('next_revision_p0e_core','public.school_generate_student_tuition_next_revision_p0e_core(uuid,uuid,uuid,text,numeric,text,text,text)','359cd91dff91769d4ad4beaadb172e90','writer P0-E：bill/income 快照标 v2');

-- ---------------------------------------------------------------------------
-- §2 前置断言 A：六个函数必须逐字节等于审查基线
--   任一漂移即停止——lessons B3：生产可能被热修复过而仓库看不到。
-- ---------------------------------------------------------------------------
DO $do$
DECLARE
  r record;
  v_oid oid;
  v_md5 text;
  v_bad text := '';
BEGIN
  FOR r IN SELECT * FROM lc2_target ORDER BY fn_key LOOP
    v_oid := to_regprocedure(r.signature)::oid;
    IF v_oid IS NULL THEN
      RAISE EXCEPTION 'LC2_FUNCTION_MISSING: % 在生产不存在', r.signature;
    END IF;
    v_md5 := md5(pg_get_functiondef(v_oid));
    UPDATE lc2_target SET before_md5 = v_md5 WHERE fn_key = r.fn_key;
    IF v_md5 IS DISTINCT FROM r.baseline_md5 THEN
      v_bad := v_bad || format(E'\n  %s\n    期望 %s\n    实际 %s',
                               r.signature, r.baseline_md5, v_md5);
    END IF;
  END LOOP;
  IF v_bad <> '' THEN
    RAISE EXCEPTION
      'LC2_BASELINE_DRIFT: 生产定义已偏离 2026-09-06 12:05 JST 审查基线，停止。%', v_bad;
  END IF;
END
$do$;

-- ---------------------------------------------------------------------------
-- §3 目标 (学生 × 月份) 对
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE lc2v_pair(
  student_id uuid, business_entity_id uuid, billing_month text,
  PRIMARY KEY (student_id, billing_month)
) ON COMMIT DROP;

INSERT INTO lc2v_pair(student_id, business_entity_id, billing_month)
SELECT s.id, s.business_entity_id, to_char(m.d, 'YYYY-MM')
FROM public.school_students s
CROSS JOIN LATERAL (
  SELECT generate_series(
    to_date((SELECT months_from FROM lc2v_run)||'-01','YYYY-MM-DD'),
    to_date((SELECT months_to   FROM lc2v_run)||'-01','YYYY-MM-DD'),
    interval '1 month')::date AS d
) m
WHERE s.app_type = 'school' AND s.business_entity_id IS NOT NULL;

\echo '--- 覆盖范围 ---'
SELECT count(DISTINCT student_id) AS "学生数",
       count(DISTINCT billing_month) AS "月份数",
       count(*) AS "组合数"
FROM lc2v_pair;

-- ---------------------------------------------------------------------------
-- §4 快照容器
--   builder 与候选 reader 的输出各存一份 v1 相、一份 v2 相。
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE lc2v_snap(
  phase text, student_id uuid, billing_month text,
  ok boolean NOT NULL, sqlstate text, err text,
  candidate_count integer, total_lesson_count integer,
  total_duration_hours numeric, total_base numeric, total_aircon numeric,
  total_fee numeric, billing_amount_cny numeric,
  uuid_md5 text, candidate_manifest text,
  generation_manifest text, candidates jsonb,
  PRIMARY KEY (phase, student_id, billing_month)
) ON COMMIT DROP;

-- 候选 reader 的采集结果**独立记录**。
-- 上一轮我用「reader 失败时 builder 必然也失败」把它的异常吞掉了，那条推理是错的：
-- builder 走 charge reader（include_excluded=false），这里直接调底层 reader
-- （include_excluded=true），是两条不同语句；而且 builder 遇到目标月已锁会在
-- 到达 reader 之前就退出。builder 的错误解释不了 reader 有没有跑成功。
CREATE TEMP TABLE lc2v_collect(
  phase text, student_id uuid, billing_month text,
  ok boolean NOT NULL, sqlstate text, err text,
  returned_rows integer, inserted_rows integer,
  PRIMARY KEY (phase, student_id, billing_month)
) ON COMMIT DROP;

CREATE TEMP TABLE lc2v_cand(
  phase text, student_id uuid, billing_month text, planned_lesson_id uuid,
  lesson_count integer, candidate_status text, exclusion_reason text,
  PRIMARY KEY (phase, student_id, billing_month, planned_lesson_id)
) ON COMMIT DROP;

-- ---------------------------------------------------------------------------
-- §5 采集 v1 相
-- ---------------------------------------------------------------------------
DO $do$
DECLARE p record; s record; v_rate numeric;
  v_returned integer; v_inserted integer;
BEGIN
  SELECT rate INTO v_rate FROM lc2v_run;
  FOR p IN SELECT * FROM lc2v_pair ORDER BY student_id, billing_month LOOP
    BEGIN
      SELECT * INTO STRICT s
      FROM public.school_build_student_tuition_generation_snapshot(
        p.student_id, p.billing_month, v_rate);
      INSERT INTO lc2v_snap VALUES ('v1',p.student_id,p.billing_month,true,NULL,NULL,
        s.candidate_count,s.total_lesson_count,s.total_duration_hours,
        s.total_base_lesson_fee_jpy,s.total_aircon_fee_jpy,s.total_fee_jpy,
        s.billing_amount_cny,s.candidate_uuid_md5,s.candidate_manifest_sha256,
        s.generation_manifest_sha256,s.candidates);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO lc2v_snap VALUES ('v1',p.student_id,p.billing_month,false,
        SQLSTATE,SQLERRM,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL);
    END;
    BEGIN
      CREATE TEMP TABLE lc2v_raw ON COMMIT DROP AS
      SELECT c.planned_lesson_id, c.lesson_count, c.candidate_status, c.exclusion_reason
      FROM public.school_list_student_tuition_candidates(
        p.student_id,p.business_entity_id,p.billing_month,true) c;
      SELECT count(*) INTO v_returned FROM lc2v_raw;
      INSERT INTO lc2v_cand
      SELECT 'v1',p.student_id,p.billing_month,r.planned_lesson_id,
             r.lesson_count,r.candidate_status,r.exclusion_reason
      FROM lc2v_raw r
      ON CONFLICT DO NOTHING;
      GET DIAGNOSTICS v_inserted = ROW_COUNT;
      DROP TABLE lc2v_raw;
      INSERT INTO lc2v_collect VALUES ('v1',p.student_id,p.billing_month,
        true,NULL,NULL,v_returned,v_inserted);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO lc2v_collect VALUES ('v1',p.student_id,p.billing_month,
        false,SQLSTATE,SQLERRM,NULL,NULL);
    END;
  END LOOP;
END
$do$;

\echo '--- v1 相 builder 结果 ---'
SELECT count(*) FILTER (WHERE ok) AS "成功", count(*) FILTER (WHERE NOT ok) AS "失败"
FROM lc2v_snap WHERE phase='v1';
\echo '--- v1 相失败原因分布（多数应为 R2_F_B_CANDIDATES_EMPTY，属正常）---'
SELECT err AS "原因", count(*) AS "次数"
FROM lc2v_snap WHERE phase='v1' AND NOT ok GROUP BY err ORDER BY 2 DESC, 1;

-- ---------------------------------------------------------------------------
-- §6 部署六个函数（同一事务，结尾整体 ROLLBACK）
-- ---------------------------------------------------------------------------

-- ---- public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)
--      候选判定：删除 lesson_count 必填两行
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
$function$;

-- ---- public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)
--      builder：新增 ranked_candidates，序号重编 + total 改 count(*)
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
      lesson.lesson_venue_id,lesson.lesson_venue AS lesson_venue_code,
      lesson.start_time AS source_start_time
    FROM public.school_list_student_tuition_charge_candidates(
      p_student_id,v_student.business_entity_id,v_month,false
    ) candidate
    JOIN public.school_lesson_records lesson ON lesson.id=candidate.planned_lesson_id
  ), ranked_candidates AS (
    SELECT detail.*,
      row_number() OVER (
        PARTITION BY detail.student_id,detail.subject_id,
          detail.billing_week_start_date
        ORDER BY detail.lesson_date,
          nullif(btrim(detail.source_start_time),'')::time NULLS LAST,
          detail.planned_lesson_id
      )::integer AS bill_lesson_ordinal
    FROM candidate_rows detail
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
        'lesson_count',detail.bill_lesson_ordinal,
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
    FROM ranked_candidates detail
  ), hashed_lines AS (
    SELECT line.*,
      encode(sha256(convert_to(line.canonical_line::text,'UTF8')),'hex')
        AS candidate_line_hash
    FROM canonical_lines line
  ), aggregated AS (
    SELECT count(*)::integer AS candidate_count,
      count(DISTINCT detail.planned_lesson_id)::integer AS distinct_count,
      count(*)::integer AS lesson_count,
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
$function$;

-- ---- public.school_validate_tuition_bill_lessons_for_bill(uuid)
--      validator：v1/v2 版本契约 + bill/income 版本一致性
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
  v_income public.school_income_records%ROWTYPE;
  v_bill_semantics text; v_income_semantics text;
  v_expected_lesson_total integer;
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

    -- lesson_count 语义版本契约：缺键=v1（历史账单）；显式 v1/v2 按值；
    -- 未知字符串 / JSON null / 非字符串一律拒绝，绝不静默回落旧算法。
    v_bill_semantics := CASE
      WHEN v_bill.source_snapshot->'lesson_count_semantics' IS NULL THEN 'v1'
      WHEN jsonb_typeof(v_bill.source_snapshot->'lesson_count_semantics')='string'
        AND v_bill.source_snapshot->>'lesson_count_semantics' IN ('v1','v2')
        THEN v_bill.source_snapshot->>'lesson_count_semantics'
      ELSE NULL
    END;

    SELECT income_row.* INTO v_income
    FROM public.school_income_records income_row
    WHERE income_row.id=v_bill.income_record_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'TUITION_LESSON_COUNT_SEMANTICS_INCOME_MISSING: bill % has no income record.',v_bill.id;
    END IF;

    v_income_semantics := CASE
      WHEN v_income.source_snapshot->'lesson_count_semantics' IS NULL THEN 'v1'
      WHEN jsonb_typeof(v_income.source_snapshot->'lesson_count_semantics')='string'
        AND v_income.source_snapshot->>'lesson_count_semantics' IN ('v1','v2')
        THEN v_income.source_snapshot->>'lesson_count_semantics'
      ELSE NULL
    END;

    IF v_bill_semantics IS NULL OR v_income_semantics IS NULL THEN
      RAISE EXCEPTION 'TUITION_LESSON_COUNT_SEMANTICS_INVALID: bill % / income % carry an unsupported lesson_count_semantics value.',v_bill.id,v_income.id;
    END IF;
    IF v_bill_semantics IS DISTINCT FROM v_income_semantics THEN
      RAISE EXCEPTION 'TUITION_LESSON_COUNT_SEMANTICS_DIVERGED: bill % declares %, income % declares %.',v_bill.id,v_bill_semantics,v_income.id,v_income_semantics;
    END IF;

    v_expected_lesson_total := CASE WHEN v_bill_semantics='v2'
      THEN v_count ELSE v_lesson_count END;

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
       OR (v_bill.source_snapshot->>'total_lesson_count')::integer IS DISTINCT FROM v_expected_lesson_total
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
$function$;

-- ---- public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text)
--      writer 首次生成：bill/income 快照标 v2
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
      'lesson_count_semantics','v2',
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
      'lesson_count_semantics','v2',
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
$function$;

-- ---- public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text)
--      writer 次轮生成：bill/income 快照标 v2
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
      'lesson_count_semantics','v2',
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
      'lesson_count_semantics','v2',
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
$function$;

-- ---- public.school_generate_student_tuition_next_revision_p0e_core(uuid,uuid,uuid,text,numeric,text,text,text)
--      writer P0-E：bill/income 快照标 v2
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
      'lesson_count_semantics','v2',
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
      'lesson_count_semantics','v2',
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
$function$;

-- ---------------------------------------------------------------------------
-- §7 采集 v2 相（与 §5 完全相同的循环，只是函数已被替换）
-- ---------------------------------------------------------------------------
DO $do$
DECLARE p record; s record; v_rate numeric;
  v_returned integer; v_inserted integer;
BEGIN
  SELECT rate INTO v_rate FROM lc2v_run;
  FOR p IN SELECT * FROM lc2v_pair ORDER BY student_id, billing_month LOOP
    BEGIN
      SELECT * INTO STRICT s
      FROM public.school_build_student_tuition_generation_snapshot(
        p.student_id, p.billing_month, v_rate);
      INSERT INTO lc2v_snap VALUES ('v2',p.student_id,p.billing_month,true,NULL,NULL,
        s.candidate_count,s.total_lesson_count,s.total_duration_hours,
        s.total_base_lesson_fee_jpy,s.total_aircon_fee_jpy,s.total_fee_jpy,
        s.billing_amount_cny,s.candidate_uuid_md5,s.candidate_manifest_sha256,
        s.generation_manifest_sha256,s.candidates);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO lc2v_snap VALUES ('v2',p.student_id,p.billing_month,false,
        SQLSTATE,SQLERRM,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL);
    END;
    BEGIN
      CREATE TEMP TABLE lc2v_raw ON COMMIT DROP AS
      SELECT c.planned_lesson_id, c.lesson_count, c.candidate_status, c.exclusion_reason
      FROM public.school_list_student_tuition_candidates(
        p.student_id,p.business_entity_id,p.billing_month,true) c;
      SELECT count(*) INTO v_returned FROM lc2v_raw;
      INSERT INTO lc2v_cand
      SELECT 'v2',p.student_id,p.billing_month,r.planned_lesson_id,
             r.lesson_count,r.candidate_status,r.exclusion_reason
      FROM lc2v_raw r
      ON CONFLICT DO NOTHING;
      GET DIAGNOSTICS v_inserted = ROW_COUNT;
      DROP TABLE lc2v_raw;
      INSERT INTO lc2v_collect VALUES ('v2',p.student_id,p.billing_month,
        true,NULL,NULL,v_returned,v_inserted);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO lc2v_collect VALUES ('v2',p.student_id,p.billing_month,
        false,SQLSTATE,SQLERRM,NULL,NULL);
    END;
  END LOOP;
END
$do$;

\echo '--- v2 相 builder 结果 ---'
SELECT count(*) FILTER (WHERE ok) AS "成功", count(*) FILTER (WHERE NOT ok) AS "失败"
FROM lc2v_snap WHERE phase='v2';
\echo '--- v2 相失败原因分布（与 v1 逐类对照；上一轮漏了这张表）---'
SELECT coalesce(a.err, b.err) AS "原因",
       count(a.*) AS "v1", count(b.*) AS "v2"
FROM (SELECT * FROM lc2v_snap WHERE phase='v1' AND NOT ok) a
FULL OUTER JOIN (SELECT * FROM lc2v_snap WHERE phase='v2' AND NOT ok) b
  ON b.student_id=a.student_id AND b.billing_month=a.billing_month
GROUP BY 1 ORDER BY 1;

-- ---------------------------------------------------------------------------
-- §8 断言
-- ---------------------------------------------------------------------------

-- (A) 【场景 9 / 核心性质】v2 下 total_lesson_count 必须等于候选条数
DO $do$
DECLARE v_bad integer; v_detail text;
BEGIN
  SELECT count(*), string_agg(format(E'\n  %s %s: total=%s count=%s',
           student_id, billing_month, total_lesson_count, candidate_count), '')
  INTO v_bad, v_detail
  FROM lc2v_snap WHERE phase='v2' AND ok
    AND total_lesson_count IS DISTINCT FROM candidate_count;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'LC2V_A_TOTAL_NOT_COUNT: v2 下有 % 个组合的总次数不等于条数。%',
      v_bad, v_detail;
  END IF;
END
$do$;

-- (A2) 自洽校验：v1 下 total 必须等于源序号之和（确认我对旧语义的理解没错）
DO $do$
DECLARE v_bad integer; v_detail text;
BEGIN
  WITH src AS (
    SELECT s.student_id, s.billing_month, s.total_lesson_count,
           coalesce(sum((line->>'lesson_count')::integer),0) AS sum_ord
    FROM lc2v_snap s
    CROSS JOIN LATERAL jsonb_array_elements(s.candidates) line
    WHERE s.phase='v1' AND s.ok
    GROUP BY s.student_id, s.billing_month, s.total_lesson_count
  )
  SELECT count(*), string_agg(format(E'\n  %s %s: total=%s sum=%s',
           student_id, billing_month, total_lesson_count, sum_ord), '')
  INTO v_bad, v_detail
  FROM src WHERE total_lesson_count IS DISTINCT FROM sum_ord;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'LC2V_A2_V1_NOT_SUM: v1 下 total 不等于源序号之和，'
      '说明我对旧语义的理解有误，后续所有推论都要重来。%', v_bad || v_detail;
  END IF;
END
$do$;

-- (B) 放宽候选不得让原本成功的组合失败
DO $do$
DECLARE v_bad integer; v_detail text;
BEGIN
  SELECT count(*), string_agg(format(E'\n  %s %s: %s %s',
           a.student_id, a.billing_month, b.sqlstate, b.err), '')
  INTO v_bad, v_detail
  FROM lc2v_snap a JOIN lc2v_snap b
    ON b.phase='v2' AND b.student_id=a.student_id AND b.billing_month=a.billing_month
  WHERE a.phase='v1' AND a.ok AND NOT b.ok;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'LC2V_B_REGRESSION: % 个组合在 v1 成功却在 v2 失败。%',
      v_bad, v_detail;
  END IF;
END
$do$;

-- (C) 候选集只增不减
DO $do$
DECLARE v_bad integer; v_detail text;
BEGIN
  SELECT count(*), string_agg(format(E'\n  %s %s 丢失 %s',
           student_id, billing_month, planned_lesson_id), '')
  INTO v_bad, v_detail
  FROM (
    SELECT v1.student_id, v1.billing_month, v1.planned_lesson_id
    FROM lc2v_cand v1
    WHERE v1.phase='v1' AND v1.candidate_status='candidate'
      AND NOT EXISTS (
        SELECT 1 FROM lc2v_cand v2
        WHERE v2.phase='v2' AND v2.candidate_status='candidate'
          AND v2.student_id=v1.student_id AND v2.billing_month=v1.billing_month
          AND v2.planned_lesson_id=v1.planned_lesson_id)
  ) lost;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'LC2V_C_CANDIDATE_LOST: 放宽判定后反而丢了 % 条候选。%',
      v_bad, v_detail;
  END IF;
END
$do$;

-- (D) 【场景 6】新进候选的**必要条件**：其 v1 源序号必须是 NULL 或 <= 0
--   ⚠️ 这是单向必要条件，**不是「恰好等于」**。
--   它证明「没有不该进来的进来了」，不证明「所有该进来的都进来了」——
--   其余排除原因、历史关联、历史已付排除仍可能合法挡住 NULL/<=0 的行。
--   要做双向差集，得先把预期集合完整定义出来，那超出本脚本范围。
DO $do$
DECLARE v_bad integer; v_detail text;
BEGIN
  SELECT count(*), string_agg(format(E'\n  %s %s %s 源序号=%s',
           student_id, billing_month, planned_lesson_id,
           coalesce(src_lesson_count::text,'NULL')), '')
  INTO v_bad, v_detail
  FROM (
    SELECT v2.student_id, v2.billing_month, v2.planned_lesson_id,
           v1.lesson_count AS src_lesson_count
    FROM lc2v_cand v2
    LEFT JOIN lc2v_cand v1
      ON v1.phase='v1' AND v1.student_id=v2.student_id
     AND v1.billing_month=v2.billing_month AND v1.planned_lesson_id=v2.planned_lesson_id
    WHERE v2.phase='v2' AND v2.candidate_status='candidate'
      AND coalesce(v1.candidate_status,'') <> 'candidate'
      AND v1.planned_lesson_id IS NOT NULL          -- 缺行的情况由 (I) 单独处理
      AND (v1.lesson_count IS NOT NULL AND v1.lesson_count > 0)
  ) unexpected;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'LC2V_D_UNEXPECTED_ADMISSION: % 条课时新进候选，'
      '但它们的源序号既不是 NULL 也不 <= 0，说明放宽的影响面超出预期。%',
      v_bad, v_detail;
  END IF;
END
$do$;

-- (E) 候选集完全相同的组合：金额与时长必须逐分不变
--     注意 candidate_manifest **允许**变：它 hash 了 candidate_line，
--     而 line 里的 lesson_count 已由源序号换成账单内序号。这是有意的。
--     billing_amount_cny 也纳入比较：两相用同一个占位汇率，它不该变。
DO $do$
DECLARE v_bad integer; v_detail text;
BEGIN
  WITH same_set AS (
    SELECT a.student_id, a.billing_month, a.total_fee AS f1, b.total_fee AS f2,
           a.total_duration_hours AS h1, b.total_duration_hours AS h2,
           a.total_base AS b1, b.total_base AS b2,
           a.total_aircon AS c1, b.total_aircon AS c2,
           a.billing_amount_cny AS y1, b.billing_amount_cny AS y2,
           a.uuid_md5 AS u1, b.uuid_md5 AS u2
    FROM lc2v_snap a JOIN lc2v_snap b
      ON b.phase='v2' AND b.student_id=a.student_id AND b.billing_month=a.billing_month
    WHERE a.phase='v1' AND a.ok AND b.ok AND a.uuid_md5 = b.uuid_md5
  )
  SELECT count(*), string_agg(format(E'\n  %s %s fee %s->%s hours %s->%s',
           student_id, billing_month, f1, f2, h1, h2), '')
  INTO v_bad, v_detail
  FROM same_set
  WHERE (f1,h1,b1,c1,y1) IS DISTINCT FROM (f2,h2,b2,c2,y2);
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'LC2V_E_AMOUNT_DRIFT: 候选集未变却有 % 个组合金额或时长变了。%',
      v_bad, v_detail;
  END IF;
END
$do$;

-- (F) 【前端契约】builder 返回数组顺序仍为 周 → 日期 → UUID
DO $do$
DECLARE v_bad integer; v_detail text;
BEGIN
  WITH ord AS (
    SELECT s.phase, s.student_id, s.billing_month, line.ordinality AS pos,
           (line.value->>'billing_week_start_date')::date AS wk,
           (line.value->>'lesson_date')::date AS dt,
           (line.value->>'planned_lesson_id')::uuid AS pid
    FROM lc2v_snap s
    CROSS JOIN LATERAL jsonb_array_elements(s.candidates)
      WITH ORDINALITY line(value, ordinality)
    WHERE s.ok
  ), bad AS (
    SELECT phase, student_id, billing_month, pos
    FROM (SELECT o.*, lag(wk) OVER w AS pwk, lag(dt) OVER w AS pdt, lag(pid) OVER w AS ppid
          FROM ord o WINDOW w AS (PARTITION BY phase,student_id,billing_month ORDER BY pos)) t
    WHERE pwk IS NOT NULL AND (wk,dt,pid) < (pwk,pdt,ppid)
  )
  SELECT count(*), string_agg(format(E'\n  %s %s %s 第 %s 项', phase,student_id,billing_month,pos), '')
  INTO v_bad, v_detail FROM bad;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'LC2V_F_ARRAY_ORDER_BROKEN: 返回数组不再是「周→日期→UUID」次序，'
      '前端 js/utils/tuition-validation-preview.js:71-77 会拒绝显示。%', v_detail;
  END IF;
END
$do$;


-- (G) 候选采集必须全部成功
--   上一轮这些异常被 WHEN OTHERS THEN NULL 吞掉了，于是「0 条候选」既可能是
--   真的没课时，也可能是采集炸了——两者无法区分。现在独立记录并硬停止。
DO $do$
DECLARE v_bad integer; v_detail text;
BEGIN
  SELECT count(*), string_agg(format(E'
  %s %s %s: %s %s',
           phase, student_id, billing_month, sqlstate, err), '')
  INTO v_bad, v_detail FROM lc2v_collect WHERE NOT ok;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'LC2V_G_COLLECT_FAILED: % 次候选采集失败，'
      '本轮的候选相关结论全部不可信。%', v_bad, v_detail;
  END IF;
END
$do$;

-- (H) 候选 reader 不得返回重复的 planned_lesson_id
--   ON CONFLICT DO NOTHING 会把重复静默折叠掉，看起来一切正常。
--   这里比对「返回行数」与「实际插入行数」，让折叠现形。
DO $do$
DECLARE v_bad integer; v_detail text;
BEGIN
  SELECT count(*), string_agg(format(E'
  %s %s %s: 返回 %s 行，插入 %s 行',
           phase, student_id, billing_month, returned_rows, inserted_rows), '')
  INTO v_bad, v_detail FROM lc2v_collect
  WHERE ok AND returned_rows IS DISTINCT FROM inserted_rows;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'LC2V_H_DUPLICATE_CANDIDATE_ROW: % 个组合的候选 reader '
      '返回了重复的 planned_lesson_id。%', v_bad, v_detail;
  END IF;
END
$do$;

-- (I) v2 有候选、而该行在 v1 相**整行缺失**
--   与 (D) 的「字段为 NULL」是两回事：整行缺失说明两相看到的行集合本身不同，
--   那已经不是「放宽判定」能解释的，必须人来看。
DO $do$
DECLARE v_bad integer; v_detail text;
BEGIN
  SELECT count(*), string_agg(format(E'
  %s %s %s',
           v2.student_id, v2.billing_month, v2.planned_lesson_id), '')
  INTO v_bad, v_detail
  FROM lc2v_cand v2
  LEFT JOIN lc2v_cand v1
    ON v1.phase='v1' AND v1.student_id=v2.student_id
   AND v1.billing_month=v2.billing_month AND v1.planned_lesson_id=v2.planned_lesson_id
  WHERE v2.phase='v2' AND v1.planned_lesson_id IS NULL;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'LC2V_I_ROW_ONLY_IN_V2: % 条课时只在 v2 相出现、v1 相整行没有。'
      '两相读的是同一个事务快照，行集合本不该不同。%', v_bad, v_detail;
  END IF;
END
$do$;

-- (J) builder 成功却返回空 candidates 数组
--   (A2) 用 CROSS JOIN 展开数组，空数组样本会直接从比较里消失——
--   于是一个「成功但没有明细」的坏结果可以静悄悄通过。这里单独堵上。
DO $do$
DECLARE v_bad integer; v_detail text;
BEGIN
  SELECT count(*), string_agg(format(E'
  %s %s %s: candidates=%s',
           phase, student_id, billing_month,
           coalesce(jsonb_typeof(candidates),'<NULL>')), '')
  INTO v_bad, v_detail FROM lc2v_snap
  WHERE ok AND coalesce(jsonb_array_length(candidates), 0) = 0;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'LC2V_J_EMPTY_CANDIDATES: % 个组合 builder 报成功却没有明细。%',
      v_bad, v_detail;
  END IF;
END
$do$;

-- (K) 【重编号的核心性质】v2 每个「学生 × 周 × 科目」分组内，
--   账单内序号必须恰好是 1..n 的连续正整数，不重不漏。
--   (F) 只验数组次序，验不到编号本身对不对。
DO $do$
DECLARE v_bad integer; v_detail text;
BEGIN
  WITH grp AS (
    SELECT s.student_id, s.billing_month,
           line->>'billing_week_start_date' AS wk,
           line->>'subject_id' AS subj,
           count(*)::integer AS n,
           count(DISTINCT (line->>'lesson_count')::integer)::integer AS distinct_ord,
           min((line->>'lesson_count')::integer) AS min_ord,
           max((line->>'lesson_count')::integer) AS max_ord
    FROM lc2v_snap s CROSS JOIN LATERAL jsonb_array_elements(s.candidates) line
    WHERE s.phase='v2' AND s.ok
    GROUP BY 1,2,3,4
  )
  SELECT count(*), string_agg(format(E'
  %s %s 周%s 科目%s: n=%s 不同序号=%s 范围=%s..%s',
           student_id, billing_month, wk, subj, n, distinct_ord, min_ord, max_ord), '')
  INTO v_bad, v_detail FROM grp
  WHERE distinct_ord <> n OR min_ord <> 1 OR max_ord <> n;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'LC2V_K_ORDINAL_NOT_DENSE: % 个「学生×周×科目」分组的账单内序号'
      '不是 1..n 的连续正整数。%', v_bad, v_detail;
  END IF;
END
$do$;

\echo ''
\echo '>>> §8 全部断言通过'

-- ---------------------------------------------------------------------------
-- §9 观测项与写入场景侦察（全部只报告，不参与判定）
-- ---------------------------------------------------------------------------

\echo '--- O1 总次数发生变化的组合（v1 序号和 → v2 条数）---'
SELECT a.student_id AS "学生", a.billing_month AS "月份",
       a.candidate_count AS "v1 条数", b.candidate_count AS "v2 条数",
       a.total_lesson_count AS "v1 总次数", b.total_lesson_count AS "v2 总次数",
       a.total_fee AS "v1 金额", b.total_fee AS "v2 金额"
FROM lc2v_snap a JOIN lc2v_snap b
  ON b.phase='v2' AND b.student_id=a.student_id AND b.billing_month=a.billing_month
WHERE a.phase='v1' AND a.ok AND b.ok
  AND (a.total_lesson_count,a.candidate_count,a.total_fee)
      IS DISTINCT FROM (b.total_lesson_count,b.candidate_count,b.total_fee)
ORDER BY 1,2;

\echo '--- O2 新进候选的课时明细（场景 6：源序号为 NULL / 0 / 负数）---'
SELECT v2.student_id AS "学生", v2.billing_month AS "月份",
       v2.planned_lesson_id AS "课时",
       CASE WHEN v1.planned_lesson_id IS NULL THEN '<v1 相整行缺失>'
            WHEN v1.lesson_count IS NULL THEN '<NULL>'
            ELSE v1.lesson_count::text END AS "v1 源序号",
       CASE WHEN v1.planned_lesson_id IS NULL THEN '<v1 相整行缺失>'
            ELSE coalesce(v1.exclusion_reason,'<候选>') END AS "v1 排除原因",
       CASE WHEN v2.lesson_count IS NULL THEN '<NULL>'
            ELSE v2.lesson_count::text END AS "v2 源序号"
FROM lc2v_cand v2
LEFT JOIN lc2v_cand v1
  ON v1.phase='v1' AND v1.student_id=v2.student_id
 AND v1.billing_month=v2.billing_month AND v1.planned_lesson_id=v2.planned_lesson_id
WHERE v2.phase='v2' AND v2.candidate_status='candidate'
  AND coalesce(v1.candidate_status,'') <> 'candidate'
ORDER BY 1,2,3;

\echo '--- O3 排除原因分布 v1 vs v2（场景 5 / 7）---'
SELECT coalesce(exclusion_reason,'<候选>') AS "原因",
       count(*) FILTER (WHERE phase='v1') AS "v1",
       count(*) FILTER (WHERE phase='v2') AS "v2"
FROM lc2v_cand GROUP BY 1 ORDER BY 1;

\echo '--- O4 【场景 8】preview manifest 是否变化：candidate_manifest / generation_manifest ---'
SELECT count(*) FILTER (WHERE a.candidate_manifest = b.candidate_manifest) AS "candidate 未变",
       count(*) FILTER (WHERE a.candidate_manifest <> b.candidate_manifest) AS "candidate 已变",
       count(*) FILTER (WHERE a.generation_manifest = b.generation_manifest) AS "generation 未变",
       count(*) FILTER (WHERE a.generation_manifest <> b.generation_manifest) AS "generation 已变"
FROM lc2v_snap a JOIN lc2v_snap b
  ON b.phase='v2' AND b.student_id=a.student_id AND b.billing_month=a.billing_month
WHERE a.phase='v1' AND a.ok AND b.ok;

\echo '--- R1 侦察：v2 下能产生「周内序号 ≥ 2」的组合 ---'
\echo '     sum(序号) ≠ 条数 的才能区分新旧算法（设计 §11.2 场景 2 要 count 4 / sum 6）'
WITH ord AS (
  SELECT s.student_id, s.billing_month,
         count(*)::integer AS cnt,
         sum((line->>'lesson_count')::integer)::integer AS sum_ord,
         max((line->>'lesson_count')::integer)::integer AS max_ord
  FROM lc2v_snap s CROSS JOIN LATERAL jsonb_array_elements(s.candidates) line
  WHERE s.phase='v2' AND s.ok
  GROUP BY 1,2
)
SELECT o.student_id AS "学生", o.billing_month AS "月份",
       o.cnt AS "条数", o.sum_ord AS "序号和", o.max_ord AS "最大序号",
       (o.sum_ord <> o.cnt) AS "可区分新旧",
       EXISTS (
         SELECT 1 FROM public.school_student_tuition_bills bill
         JOIN public.school_student_tuition_generation_revisions rev
           ON rev.tuition_bill_id=bill.id AND rev.lifecycle_status='active'
         WHERE bill.student_id=o.student_id AND bill.billing_month=o.billing_month
       ) AS "已有账单"
FROM ord o
WHERE o.max_ord >= 2
ORDER BY (o.sum_ord <> o.cnt) DESC, o.cnt DESC, 1, 2;

\echo '--- R2 侦察：v2 成功、且未查到与 active revision 相连的账单 ---'
\echo '     ⚠️ 仅此而已。**不证明**从无任何 bill / identity / voided revision，'
\echo '     也没查 writer gate、幂等状态、收款、权限。是待进一步核对的候选，'
\echo '     不是「可用于首次生成」的结论，更不是写入授权。'
SELECT s.student_id AS "学生", s.billing_month AS "月份",
       s.candidate_count AS "条数", s.total_lesson_count AS "总次数",
       s.total_fee AS "金额 JPY"
FROM lc2v_snap s
WHERE s.phase='v2' AND s.ok
  AND NOT EXISTS (
    SELECT 1 FROM public.school_student_tuition_bills bill
    JOIN public.school_student_tuition_generation_revisions rev
      ON rev.tuition_bill_id=bill.id AND rev.lifecycle_status='active'
    WHERE bill.student_id=s.student_id AND bill.billing_month=s.billing_month)
ORDER BY 2 DESC, 1;

\echo '--- R3 侦察：存在 active revision 的账单 ---'
\echo '     ⚠️ 未查收款状态、void/reissue preflight、下游消耗、可用调整事实、'
\echo '     writer 入参。active 本身不是 next revision 可立即执行的前提。'
SELECT bill.student_id AS "学生", bill.billing_month AS "月份",
       rev.manifest_kind AS "manifest 种类", rev.revision_no AS "修订号",
       (bill.source_snapshot->>'total_lesson_count')::integer AS "冻结总次数",
       jsonb_array_length(bill.source_snapshot->'candidate_lines') AS "冻结条数",
       (bill.source_snapshot ? 'lesson_count_semantics') AS "带版本键"
FROM public.school_student_tuition_bills bill
JOIN public.school_student_tuition_generation_revisions rev
  ON rev.tuition_bill_id=bill.id AND rev.lifecycle_status='active'
ORDER BY 2 DESC, 1;

\echo '--- R4 侦察：历史兼容样本（设计 §11.1 要 total = sum ≠ count）---'
\echo '     「序号和」由冻结 candidate_lines 现算，用来实证 total 确实等于 sum；'
\echo '     「版本键」列出实际值而不只是有无。**本脚本不调用 validator**，'
\echo '     所以这里只完成取样，不构成 §11.1 的完整证据。'
WITH b AS (
  SELECT bill.id, bill.billing_month, bill.billing_role, rev.manifest_kind,
         (bill.source_snapshot->>'total_lesson_count')::integer AS frozen_total,
         jsonb_array_length(bill.source_snapshot->'candidate_lines') AS frozen_count,
         (SELECT coalesce(sum((line->>'lesson_count')::integer),0)
            FROM jsonb_array_elements(bill.source_snapshot->'candidate_lines') line)
           AS frozen_sum,
         bill.source_snapshot->'lesson_count_semantics' AS semantics
  FROM public.school_student_tuition_bills bill
  JOIN public.school_student_tuition_generation_revisions rev
    ON rev.tuition_bill_id=bill.id
  WHERE rev.manifest_kind='atomic_generation_v1'
)
SELECT b.id AS "账单", b.billing_month AS "月份",
       b.frozen_total AS "冻结总次数", b.frozen_sum AS "冻结序号和",
       b.frozen_count AS "冻结条数",
       (b.frozen_total = b.frozen_sum) AS "total=sum",
       (b.frozen_total <> b.frozen_count) AS "sum<>count",
       coalesce(b.semantics::text,'<缺键>') AS "版本键",
       b.billing_role AS "billing_role"
FROM b ORDER BY (b.frozen_total = b.frozen_sum AND b.frozen_total <> b.frozen_count) DESC,
                b.billing_month DESC, b.id;

-- ---------------------------------------------------------------------------
-- §10 收尾：无条件 ROLLBACK
--   本脚本没有 commit 模式。要正式部署请用 deploy 脚本。
-- ---------------------------------------------------------------------------
ROLLBACK;

\echo ''
\echo '>>> ROLLBACK 已执行：生产未发生任何变更。'
