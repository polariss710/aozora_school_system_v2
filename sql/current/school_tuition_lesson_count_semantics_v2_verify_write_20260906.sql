-- ===========================================================================
-- lesson_count 语义修复：写入验证（rollback-only）/ 2026-09-06
-- ===========================================================================
--
-- 覆盖设计 §11.2 的场景 1（三个写入点标 v2、total=条数、JSON 与明细一致）
-- 与场景 2（count 4 / sum 6 的样本），以及场景 4 的全部负例。
--
-- 【授权边界】业务负责人 2026-09-06 批准，第二版文本见
--   ~/aozora-security-20260827/AUTHORIZATION-DRAFT-lesson-count-write-verify-20260906.md
--   允许：单事务内 CREATE OR REPLACE 六函数；对**逐个写死**的三个 (学生×月份)
--         各调一次 school_generate_student_tuition_bill_atomic_core；
--         由此产生的一切事务性写入；**仅对本事务内刚生成、尚未提交的行**
--         做直接 UPDATE 以构造负例；建临时表；取锁；SET CONSTRAINTS ALL IMMEDIATE。
--   禁止：COMMIT；目标清单以外的任何生成；对任何历史行的直接 DML；
--         void/reissue；改 ACL/gate/约束/触发器/表结构；调 baseline 系列。
--
-- 【没有 commit 模式】结尾无条件 ROLLBACK，脚本里不存在能提交的分支。
--
-- 【为什么调 atomic_core 而不是 base_core_v1】
--   base 只写 bill/income/明细；**外层 atomic_core 才注册 generation
--   identity 与 revision（L33-43）并调三个 validator（L44-46）**。
--   只调 base 会停在 revision 未注册的中间态，身份校验必抛
--   TUITION_IDENTITY_MISMATCH —— 那是假失败，不是缺陷。
--
-- 【负例不造假数据】每个负例都是对**刚由 writer 生成的真实行**做最小篡改，
--   放在带 EXCEPTION 的子事务里：validator 抛错时子事务自动回滚，
--   篡改被精确撤销，下一个负例从同一份原始数据重新开始。
--   全程不 INSERT 任何合成行，不碰任何历史行。
--
-- 【隔离级别用默认 READ COMMITTED】与另两份脚本不同：那两份要在事务内
--   前后两次快照比对，需要 REPEATABLE READ 锁定快照；本脚本只做一次生成，
--   READ COMMITTED 更接近真实生成路径。
--
-- 【本脚本不覆盖】
--   · next_revision / P0-E 路径 —— 生产无合格样本（8 张 atomic 账单
--     income 全部已收款、void preflight 全不通过；而 next 要求 previous
--     revision 为 voided）
--   · 设计 §11.2 场景 11「已持久化 v2 后的回退」—— 单一强制回滚的事务
--     证明不了它，自然位置是部署后用回滚脚本的 generation_only rehearsal
--   · **gate**：本脚本直接调 atomic_core，位于 student_tuition_generate
--     gate 之下，**不经过也不验证 gate**
-- ===========================================================================

\set ON_ERROR_STOP on
\timing on

\if :{?rate}
\else
\set rate 0.05
\endif

\echo ''
\echo '================================================================'
\echo 'lesson_count v2 写入验证（rollback-only）  汇率占位' :rate
\echo '================================================================'

BEGIN;
SET LOCAL statement_timeout = '600s';
SET LOCAL lock_timeout = '15s';
SET LOCAL idle_in_transaction_session_timeout = '1800s';

CREATE TEMP TABLE lc2w_run(rate numeric NOT NULL) ON COMMIT DROP;
INSERT INTO lc2w_run VALUES (:'rate');
DO $do$
BEGIN
  IF (SELECT rate FROM lc2w_run) IS NULL OR (SELECT rate FROM lc2w_run) <= 0 THEN
    RAISE EXCEPTION 'LC2W_RATE_INVALID: 汇率占位值须 > 0';
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
-- §1b 前置断言 A：六个函数必须逐字节等于审查基线
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
-- §2 目标清单：**写死三个**，来自 09-06 17:14 只读侦察 + 17:53 前置盘点
--   改这张表等于改授权范围，必须重新过审。
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE lc2w_target(
  label text PRIMARY KEY, student_id uuid NOT NULL, billing_month text NOT NULL,
  expect_count integer NOT NULL, expect_ordinal_sum integer NOT NULL,
  bill_id uuid, income_id uuid
) ON COMMIT DROP;

INSERT INTO lc2w_target(label,student_id,billing_month,expect_count,expect_ordinal_sum) VALUES
  -- 场景 2 的样本：条数 4、序号和 6，是唯一能区分新旧算法的组合
  ('count4_sum6','be7effdf-b1eb-4c3d-a24e-0085cc032195','2026-08', 4, 6),
  -- 较大样本：18 条，序号和 23
  ('large',      '7aef8061-7037-4881-a847-a2cdb031c0f4','2026-11',18,23),
  -- 单条边界：序号恒为 1
  ('single',     'a7b163a0-201e-4867-9b94-372343356a80','2026-06', 1, 1);

-- 事务内自查：三个目标现在必须是干净的。
-- 不依赖 17:53 那张表——那是几小时前的事实。
DO $do$
DECLARE t record; v_bad text := '';
  v_bills integer; v_ident integer; v_gen integer; v_rev integer; v_rel integer;
BEGIN
  FOR t IN SELECT * FROM lc2w_target ORDER BY label LOOP
    SELECT count(*) INTO v_bills FROM public.school_student_tuition_bills b
     WHERE b.student_id=t.student_id AND b.billing_month=t.billing_month;
    SELECT count(*) INTO v_ident FROM public.school_student_tuition_billing_identities i
     WHERE i.student_id=t.student_id AND i.billing_month=t.billing_month;
    SELECT count(*) INTO v_gen FROM public.school_student_tuition_generation_identities g
     WHERE g.student_id=t.student_id
       AND to_char(g.billing_month,'YYYY-MM')=t.billing_month;
    SELECT count(*) INTO v_rev FROM public.school_student_tuition_generation_revisions r
     JOIN public.school_student_tuition_bills b ON b.id=r.tuition_bill_id
     WHERE b.student_id=t.student_id AND b.billing_month=t.billing_month;
    SELECT count(*) INTO v_rel FROM public.school_student_tuition_bill_lessons rel
     WHERE rel.student_id_snapshot=t.student_id
       AND rel.billing_month_snapshot=t.billing_month;
    IF (v_bills,v_ident,v_gen,v_rev,v_rel) IS DISTINCT FROM (0,0,0,0,0) THEN
      v_bad := v_bad || format(E'\n  %s %s %s: bill=%s identity=%s gen=%s rev=%s rel=%s',
        t.label,t.student_id,t.billing_month,v_bills,v_ident,v_gen,v_rev,v_rel);
    END IF;
  END LOOP;
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'LC2W_TARGET_NOT_CLEAN: 目标组合已不是空白状态，'
      '说明 17:53 之后有人动过。停止，样本清单需重选。%', v_bad;
  END IF;
END
$do$;

\echo '--- 目标清单（事务内已确认全部空白）---'
SELECT label AS "标签", billing_month AS "月份",
       expect_count AS "预期条数", expect_ordinal_sum AS "预期序号和"
FROM lc2w_target ORDER BY label;

-- ---------------------------------------------------------------------------
-- §3 部署六个函数为 v2（同一事务，结尾整体 ROLLBACK）
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
-- §4 生成：对三个目标各调一次完整入口
--   先调 builder 拿 generation_manifest_sha256 当作 expected 传进去——
--   这正是真实的 preview → generate 协议，顺带验证 manifest 对得上。
-- ---------------------------------------------------------------------------
DO $do$
DECLARE t record; s record; v_res record; v_rate numeric;
BEGIN
  SELECT rate INTO v_rate FROM lc2w_run;
  FOR t IN SELECT * FROM lc2w_target ORDER BY label LOOP
    SELECT * INTO STRICT s
    FROM public.school_build_student_tuition_generation_snapshot(
      t.student_id, t.billing_month, v_rate);

    SELECT * INTO STRICT v_res
    FROM public.school_generate_student_tuition_bill_atomic_core(
      t.student_id, t.billing_month, v_rate,
      s.generation_manifest_sha256,
      'lesson_count v2 write verification (rollback-only)',
      NULL);

    IF v_res.idempotent IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'LC2W_UNEXPECTED_IDEMPOTENT: % 返回幂等分支，'
        '说明该组合已经有账单了，与 §2 的空白断言矛盾。', t.label;
    END IF;

    UPDATE lc2w_target
       SET bill_id = v_res.tuition_bill_id, income_id = v_res.income_record_id
     WHERE label = t.label;
  END LOOP;
END
$do$;

\echo '--- 生成结果 ---'
SELECT t.label AS "标签", t.billing_month AS "月份",
       b.status AS "账单状态", b.bill_amount_jpy AS "金额 JPY",
       (b.source_snapshot->>'total_lesson_count')::integer AS "总次数",
       jsonb_array_length(b.source_snapshot->'candidate_lines') AS "冻结条数",
       b.source_snapshot->>'lesson_count_semantics' AS "bill 版本键",
       i.source_snapshot->>'lesson_count_semantics' AS "income 版本键"
FROM lc2w_target t
JOIN public.school_student_tuition_bills b ON b.id=t.bill_id
JOIN public.school_income_records i ON i.id=t.income_id
ORDER BY t.label;

-- ---------------------------------------------------------------------------
-- §5 SET CONSTRAINTS ALL IMMEDIATE
--   **必须在三次生成全部完成之后**。提前切会把「bill 已插入但 revision
--   尚未注册」这个允许存在的中间态当成违规，抛 TUITION_IDENTITY_MISMATCH，
--   那是假失败（09-06 17:53 盘点 §4.3）。
--   六张目标表共 9 个 INITIALLY DEFERRED 约束触发器，这一句会追溯刷新
--   已排队事件：身份 / bill-income / bill-lesson / lesson claim / carryover claim。
-- ---------------------------------------------------------------------------
SET CONSTRAINTS ALL IMMEDIATE;
\echo '>>> 延迟约束已刷新，9 个约束触发器全部通过'

-- ---------------------------------------------------------------------------
-- §6 正例断言（设计 §11.2 场景 1 与 2）
-- ---------------------------------------------------------------------------

-- (P1) bill 与 income 两份快照都必须带 v2
DO $do$
DECLARE v_bad text := '';
BEGIN
  SELECT string_agg(format(E'\n  %s: bill=%s income=%s', t.label,
           coalesce(b.source_snapshot->'lesson_count_semantics'::text,'<缺键>'),
           coalesce(i.source_snapshot->'lesson_count_semantics'::text,'<缺键>')), '')
  INTO v_bad
  FROM lc2w_target t
  JOIN public.school_student_tuition_bills b ON b.id=t.bill_id
  JOIN public.school_income_records i ON i.id=t.income_id
  WHERE b.source_snapshot->>'lesson_count_semantics' IS DISTINCT FROM 'v2'
     OR i.source_snapshot->>'lesson_count_semantics' IS DISTINCT FROM 'v2';
  IF coalesce(v_bad,'') <> '' THEN
    RAISE EXCEPTION 'LC2W_P1_VERSION_KEY_MISSING: bill/income 版本键不是 v2。%', v_bad;
  END IF;
END
$do$;

-- (P2) total_lesson_count = 冻结条数 = normalized 明细条数
DO $do$
DECLARE v_bad text := '';
BEGIN
  SELECT string_agg(format(E'\n  %s: total=%s 冻结=%s 明细=%s', t.label,
           (b.source_snapshot->>'total_lesson_count')::integer,
           jsonb_array_length(b.source_snapshot->'candidate_lines'),
           (SELECT count(*) FROM public.school_student_tuition_bill_lessons r
             WHERE r.tuition_bill_id=b.id)), '')
  INTO v_bad
  FROM lc2w_target t JOIN public.school_student_tuition_bills b ON b.id=t.bill_id
  WHERE (b.source_snapshot->>'total_lesson_count')::integer
          IS DISTINCT FROM jsonb_array_length(b.source_snapshot->'candidate_lines')
     OR (b.source_snapshot->>'total_lesson_count')::integer IS DISTINCT FROM
        (SELECT count(*)::integer FROM public.school_student_tuition_bill_lessons r
          WHERE r.tuition_bill_id=b.id);
  IF coalesce(v_bad,'') <> '' THEN
    RAISE EXCEPTION 'LC2W_P2_TOTAL_NOT_COUNT: 总次数与条数不一致。%', v_bad;
  END IF;
END
$do$;

-- (P3) 【场景 2 的核心】条数与序号和必须等于预期
--   序号和 <> 条数 正是本次修复的证据：旧算法会要求 total = 序号和，
--   新算法要求 total = 条数。样本若 sum=count 则测了等于没测。
DO $do$
DECLARE v_bad text := '';
BEGIN
  SELECT string_agg(format(E'\n  %s: 条数 %s(预期 %s) 序号和 %s(预期 %s)', t.label,
           x.cnt, t.expect_count, x.ord_sum, t.expect_ordinal_sum), '')
  INTO v_bad
  FROM lc2w_target t
  CROSS JOIN LATERAL (
    SELECT count(*)::integer AS cnt,
           sum(r.lesson_count_snapshot)::integer AS ord_sum
    FROM public.school_student_tuition_bill_lessons r WHERE r.tuition_bill_id=t.bill_id
  ) x
  WHERE (x.cnt,x.ord_sum) IS DISTINCT FROM (t.expect_count,t.expect_ordinal_sum);
  IF coalesce(v_bad,'') <> '' THEN
    RAISE EXCEPTION 'LC2W_P3_SHAPE_MISMATCH: 条数或序号和与预期不符。%', v_bad;
  END IF;
END
$do$;

-- (P4) 冻结 JSON 与 normalized 明细逐行一致
DO $do$
DECLARE v_bad text := '';
BEGIN
  SELECT string_agg(format(E'\n  %s 第 %s 行: json(%s,%s) rel(%s,%s)',
           t.label, r.line_no,
           line.value->>'planned_lesson_id', line.value->>'lesson_count',
           r.planned_lesson_id, r.lesson_count_snapshot), '')
  INTO v_bad
  FROM lc2w_target t
  JOIN public.school_student_tuition_bills b ON b.id=t.bill_id
  JOIN public.school_student_tuition_bill_lessons r ON r.tuition_bill_id=b.id
  CROSS JOIN LATERAL (
    SELECT (b.source_snapshot->'candidate_lines'->(r.line_no-1)) AS value
  ) line
  WHERE (line.value->>'planned_lesson_id')::uuid IS DISTINCT FROM r.planned_lesson_id
     OR (line.value->>'lesson_count')::integer IS DISTINCT FROM r.lesson_count_snapshot
     OR (line.value->>'course_total_jpy')::numeric IS DISTINCT FROM r.lesson_fee_jpy_snapshot;
  IF coalesce(v_bad,'') <> '' THEN
    RAISE EXCEPTION 'LC2W_P4_JSON_REL_MISMATCH: 冻结 JSON 与明细行不一致。%', v_bad;
  END IF;
END
$do$;

-- (P5) 账单内序号在每个「周 × 科目」内是 1..n 连续正整数
DO $do$
DECLARE v_bad text := '';
BEGIN
  WITH grp AS (
    SELECT t.label, r.week_start_date_snapshot AS wk, r.subject_id_snapshot AS subj,
           count(*)::integer AS n,
           count(DISTINCT r.lesson_count_snapshot)::integer AS distinct_ord,
           min(r.lesson_count_snapshot) AS min_ord, max(r.lesson_count_snapshot) AS max_ord
    FROM lc2w_target t
    JOIN public.school_student_tuition_bill_lessons r ON r.tuition_bill_id=t.bill_id
    GROUP BY 1,2,3
  )
  SELECT string_agg(format(E'\n  %s 周%s 科目%s: n=%s 不同=%s 范围 %s..%s',
           label,wk,subj,n,distinct_ord,min_ord,max_ord), '')
  INTO v_bad FROM grp
  WHERE distinct_ord <> n OR min_ord <> 1 OR max_ord <> n;
  IF coalesce(v_bad,'') <> '' THEN
    RAISE EXCEPTION 'LC2W_P5_ORDINAL_NOT_DENSE: 序号不是 1..n 连续。%', v_bad;
  END IF;
END
$do$;

-- (P6) 三个 validator 对三张新账单都必须通过
DO $do$
DECLARE t record;
BEGIN
  FOR t IN SELECT * FROM lc2w_target ORDER BY label LOOP
    PERFORM public.school_validate_tuition_identity_for_bill(t.bill_id);
    PERFORM public.school_validate_tuition_bill_income_for_bill(t.bill_id);
    PERFORM public.school_validate_tuition_bill_lessons_for_bill(t.bill_id);
  END LOOP;
END
$do$;

\echo '>>> §6 正例断言全部通过'

-- ---------------------------------------------------------------------------
-- §7 负例（设计 §11.2 场景 4）：该失败的必须失败
--
--   每个用例都对**刚由 writer 生成的真实行**做最小篡改，放在带 EXCEPTION 的
--   子事务里。validator 抛错时子事务自动回滚，篡改被精确撤销，
--   下一个用例从同一份原始数据重新开始。**不 INSERT 任何合成行。**
--
--   如果 validator **没有**抛错，就由哨兵 RAISE 强制回滚该子事务并记为失败——
--   这样无论通过与否，篡改都不会留下。
--
--   ⚠️ 判据不是「抛了错」，是「抛了**预期的那个**错」。
--      只判「有异常」的话，我自己写错一句 UPDATE 也会算通过。
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE lc2w_neg(
  case_name text PRIMARY KEY, description text, expect_needle text,
  rejected boolean, sqlstate text, err text
) ON COMMIT DROP;

DO $do$
DECLARE v_bill uuid; v_income uuid;
BEGIN
  -- 全部负例都打在 count4_sum6 这张账单上：它是唯一 序号和(6) <> 条数(4) 的样本，
  -- 版本分支选错时会立刻暴露，而 sum=count 的样本测不出区别。
  SELECT bill_id, income_id INTO STRICT v_bill, v_income
  FROM lc2w_target WHERE label='count4_sum6';

  -- 把冻结的 total_lesson_count 改成 99
  BEGIN
    UPDATE public.school_student_tuition_bills SET source_snapshot=jsonb_set(source_snapshot,'{total_lesson_count}','99') WHERE id=v_bill;
    PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill);
    RAISE EXCEPTION 'LC2W_SENTINEL_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO lc2w_neg(case_name,description,expect_needle,rejected,sqlstate,err)
    VALUES ('total_tampered','把冻结的 total_lesson_count 改成 99','TUITION_ATOMIC_BILL_LESSON_MISMATCH',
            SQLERRM NOT LIKE 'LC2W_SENTINEL_NOT_REJECTED%',
            SQLSTATE, SQLERRM);
  END;
  -- 把第 1 行明细的账单内序号 +1
  BEGIN
    UPDATE public.school_student_tuition_bill_lessons SET lesson_count_snapshot=lesson_count_snapshot+1 WHERE tuition_bill_id=v_bill AND line_no=1;
    PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill);
    RAISE EXCEPTION 'LC2W_SENTINEL_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO lc2w_neg(case_name,description,expect_needle,rejected,sqlstate,err)
    VALUES ('line_ordinal_tampered','把第 1 行明细的账单内序号 +1','TUITION_ATOMIC_BILL_LESSON_MISMATCH',
            SQLERRM NOT LIKE 'LC2W_SENTINEL_NOT_REJECTED%',
            SQLSTATE, SQLERRM);
  END;
  -- 把第 1 行的 candidate_line_hash 改成全 0
  BEGIN
    UPDATE public.school_student_tuition_bills SET source_snapshot=jsonb_set(source_snapshot,'{candidate_lines,0,candidate_line_hash}',to_jsonb(repeat('0',64))) WHERE id=v_bill;
    PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill);
    RAISE EXCEPTION 'LC2W_SENTINEL_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO lc2w_neg(case_name,description,expect_needle,rejected,sqlstate,err)
    VALUES ('line_hash_tampered','把第 1 行的 candidate_line_hash 改成全 0','TUITION_ATOMIC_BILL_LESSON_MISMATCH',
            SQLERRM NOT LIKE 'LC2W_SENTINEL_NOT_REJECTED%',
            SQLSTATE, SQLERRM);
  END;
  -- 把 candidate_manifest_sha256 改成全 0
  BEGIN
    UPDATE public.school_student_tuition_bills SET source_snapshot=jsonb_set(source_snapshot,'{candidate_manifest_sha256}',to_jsonb(repeat('0',64))) WHERE id=v_bill;
    PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill);
    RAISE EXCEPTION 'LC2W_SENTINEL_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO lc2w_neg(case_name,description,expect_needle,rejected,sqlstate,err)
    VALUES ('candidate_manifest_tampered','把 candidate_manifest_sha256 改成全 0','TUITION_ATOMIC_BILL_LESSON_MISMATCH',
            SQLERRM NOT LIKE 'LC2W_SENTINEL_NOT_REJECTED%',
            SQLSTATE, SQLERRM);
  END;
  -- 改 relation.source_snapshot 里的 lesson_count
  BEGIN
    UPDATE public.school_student_tuition_bill_lessons SET source_snapshot=jsonb_set(source_snapshot,'{lesson_count}','99') WHERE tuition_bill_id=v_bill AND line_no=1;
    PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill);
    RAISE EXCEPTION 'LC2W_SENTINEL_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO lc2w_neg(case_name,description,expect_needle,rejected,sqlstate,err)
    VALUES ('relation_snapshot_tampered','改 relation.source_snapshot 里的 lesson_count','TUITION_ATOMIC_BILL_LESSON_MISMATCH',
            SQLERRM NOT LIKE 'LC2W_SENTINEL_NOT_REJECTED%',
            SQLSTATE, SQLERRM);
  END;
  -- bill 仍标 v2，把 income 的版本键删掉
  BEGIN
    UPDATE public.school_income_records SET source_snapshot=source_snapshot-'lesson_count_semantics' WHERE id=v_income;
    PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill);
    RAISE EXCEPTION 'LC2W_SENTINEL_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO lc2w_neg(case_name,description,expect_needle,rejected,sqlstate,err)
    VALUES ('income_key_removed','bill 仍标 v2，把 income 的版本键删掉','TUITION_LESSON_COUNT_SEMANTICS_DIVERGED',
            SQLERRM NOT LIKE 'LC2W_SENTINEL_NOT_REJECTED%',
            SQLSTATE, SQLERRM);
  END;
  -- 把 bill 的版本键改成未知字符串 v3
  BEGIN
    UPDATE public.school_student_tuition_bills SET source_snapshot=jsonb_set(source_snapshot,'{lesson_count_semantics}','"v3"') WHERE id=v_bill;
    PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill);
    RAISE EXCEPTION 'LC2W_SENTINEL_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO lc2w_neg(case_name,description,expect_needle,rejected,sqlstate,err)
    VALUES ('bill_key_unknown','把 bill 的版本键改成未知字符串 v3','TUITION_LESSON_COUNT_SEMANTICS_INVALID',
            SQLERRM NOT LIKE 'LC2W_SENTINEL_NOT_REJECTED%',
            SQLSTATE, SQLERRM);
  END;
  -- 把 bill 的版本键改成 JSON null
  BEGIN
    UPDATE public.school_student_tuition_bills SET source_snapshot=jsonb_set(source_snapshot,'{lesson_count_semantics}','null') WHERE id=v_bill;
    PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill);
    RAISE EXCEPTION 'LC2W_SENTINEL_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO lc2w_neg(case_name,description,expect_needle,rejected,sqlstate,err)
    VALUES ('bill_key_json_null','把 bill 的版本键改成 JSON null','TUITION_LESSON_COUNT_SEMANTICS_INVALID',
            SQLERRM NOT LIKE 'LC2W_SENTINEL_NOT_REJECTED%',
            SQLSTATE, SQLERRM);
  END;
  -- 把 bill 的版本键改成数字 2
  BEGIN
    UPDATE public.school_student_tuition_bills SET source_snapshot=jsonb_set(source_snapshot,'{lesson_count_semantics}','2') WHERE id=v_bill;
    PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill);
    RAISE EXCEPTION 'LC2W_SENTINEL_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO lc2w_neg(case_name,description,expect_needle,rejected,sqlstate,err)
    VALUES ('bill_key_number','把 bill 的版本键改成数字 2','TUITION_LESSON_COUNT_SEMANTICS_INVALID',
            SQLERRM NOT LIKE 'LC2W_SENTINEL_NOT_REJECTED%',
            SQLSTATE, SQLERRM);
  END;
  -- bill 与 income 一致地降级为 v1（版本键合法但算法错）
  BEGIN
    UPDATE public.school_student_tuition_bills SET source_snapshot=jsonb_set(source_snapshot,'{lesson_count_semantics}','"v1"') WHERE id=v_bill; UPDATE public.school_income_records SET source_snapshot=jsonb_set(source_snapshot,'{lesson_count_semantics}','"v1"') WHERE id=v_income;
    PERFORM public.school_validate_tuition_bill_lessons_for_bill(v_bill);
    RAISE EXCEPTION 'LC2W_SENTINEL_NOT_REJECTED';
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO lc2w_neg(case_name,description,expect_needle,rejected,sqlstate,err)
    VALUES ('both_downgraded_to_v1','bill 与 income 一致地降级为 v1（版本键合法但算法错）','TUITION_ATOMIC_BILL_LESSON_MISMATCH',
            SQLERRM NOT LIKE 'LC2W_SENTINEL_NOT_REJECTED%',
            SQLSTATE, SQLERRM);
  END;
END
$do$;

\echo '--- 负例结果 ---'
SELECT case_name AS "用例", description AS "篡改内容",
       rejected AS "被拒绝", expect_needle AS "期望错误",
       sqlstate AS "SQLSTATE", left(err,60) AS "实际错误"
FROM lc2w_neg ORDER BY case_name;

-- (N1) 每个负例都必须被拒绝
DO $do$
DECLARE v_bad text := '';
BEGIN
  SELECT string_agg(format(E'\n  %s（%s）', case_name, description), '')
  INTO v_bad FROM lc2w_neg WHERE NOT rejected;
  IF coalesce(v_bad,'') <> '' THEN
    RAISE EXCEPTION 'LC2W_N1_NOT_REJECTED: 以下篡改**没有**被 validator 拒绝，'
      '说明防护有洞。%', v_bad;
  END IF;
END
$do$;

-- (N2) 而且必须是**预期的那个**错误
DO $do$
DECLARE v_bad text := '';
BEGIN
  SELECT string_agg(format(E'\n  %s: 期望含 %s，实际 %s',
           case_name, expect_needle, left(err,80)), '')
  INTO v_bad FROM lc2w_neg
  WHERE rejected AND strpos(coalesce(err,''), expect_needle) = 0;
  IF coalesce(v_bad,'') <> '' THEN
    RAISE EXCEPTION 'LC2W_N2_WRONG_ERROR: 抛的不是预期的错误，'
      '不能算这条防护生效。%', v_bad;
  END IF;
END
$do$;

-- (N3) 篡改必须已被子事务回滚干净：三张账单重新全量校验一遍
DO $do$
DECLARE t record;
BEGIN
  FOR t IN SELECT * FROM lc2w_target ORDER BY label LOOP
    PERFORM public.school_validate_tuition_identity_for_bill(t.bill_id);
    PERFORM public.school_validate_tuition_bill_income_for_bill(t.bill_id);
    PERFORM public.school_validate_tuition_bill_lessons_for_bill(t.bill_id);
  END LOOP;
END
$do$;

\echo '>>> §7 负例全部按预期被拒绝，且篡改已回滚干净'

-- ---------------------------------------------------------------------------
-- §8 收尾：无条件 ROLLBACK
-- ---------------------------------------------------------------------------
\echo '--- writer 上下文表（应为 0，回滚前后都是）---'
SELECT count(*) AS "context 行数" FROM public.school_tuition_atomic_writer_context;

ROLLBACK;

\echo ''
\echo '>>> ROLLBACK 已执行：三张账单、三条收入、全部明细与 revision 均已撤销。'
