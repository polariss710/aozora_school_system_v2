-- =============================================================================
-- 学费生成顺序守卫：部署
--
-- 设计   ~/aozora-security-20260827/school-generation-ordering-guard-design-20260908-v14.md
-- 实测   ~/aozora-security-20260827/ordering-guard-local-harness-test-20260908.md
-- 取证   Codex R6–R16（2026-09-07 23:52 ～ 2026-09-08 10:08 JST）
--
-- 缺陷：builder 查不到上月 locked 结算时，把结转记 0 并盖章 zero_carryover_verified_v1
--       （「已核实为零」），不报错、不提示、继续生成——而该账单会通过
--       TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE 永久冻结那个结算月。
--
-- 本次【不改变任何金额】。IF FOUND / ELSE 结转分支一字未动。
--   deploy 前后 previous_carryover_cny 出现任何差异 ⇒ 判部署失败。
--
-- ⚠️ 在 harness 上排练之前，harness 必须先具备与生产相同的默认授权：
--      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO service_role;
--    否则 DROP + CREATE 之后 service_role 【不会】回流，
--    「ACL 集合相同而数组顺序不同」这一类问题在本地【复现不出来】。
--    2026-09-09 的 Cash 部署与 2026-09-10 的本次部署都因此拖到生产 rehearsal 才暴露。
--    注意顺序：重建库的脚本会清掉默认授权，须在重建【之后】设置。
--
-- 用法：
--   排练  psql -v ON_ERROR_STOP=1 -v mode=rehearsal -f <本文件>
--   正式  psql -v ON_ERROR_STOP=1 -v mode=commit    -f <本文件>
--   排练模式在末尾 ROLLBACK，不留任何痕迹。
--
-- 前置：本文件不创建 ack 表与 reader。请【先】执行
--   sql/current/school_tuition_generation_ordering_guard_new_objects_20260908.sql
-- （同一事务内，见 §3）。
-- =============================================================================
\set ON_ERROR_STOP on
\if :{?mode}
\else
  \set mode 'rehearsal'
\endif
\if :{?p0e_adjustment_type}
\else
  \set p0e_adjustment_type 'neutralize_historical_carryover_v1'
\endif
\if :{?allow_incomplete_coverage}
\else
  \set allow_incomplete_coverage 'no'
\endif
\echo '=== 顺序守卫部署，mode =' :mode '  P0-E 调整类型 =' :p0e_adjustment_type '==='

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout = '600s';
SET LOCAL lock_timeout = '15s';

-- -----------------------------------------------------------------------------
-- §1 基线断言：生产现状必须与取证一致，否则中止
--     md5 常量与 §4 要装的定义来自【同一批文件】，不可能对不上。
-- -----------------------------------------------------------------------------
DO $lc$
DECLARE
  r record; v_oid oid; v_md5 text; v_acl text; v_cfg text; v_cmt text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('B','public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)','efa51498e77b515b6f67fc4be599a1b8','{postgres=X/postgres,service_role=X/postgres}','Phase B3: existing tuition facts are governed by lesson, settlement, bill, income, immutable and Gate contracts; frozen legacy student status is not an eligibility authority.'),
    ('G','public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)','36bdadc9af59637c9d336ce68d9afb4c','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','R2-F-B authoritative atomic tuition writer. The public wrapper is R0-gated; clients submit no amounts or candidate details.'),
    ('C','public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)','95a68598215b61f55e5b63c74eeaa3f1','{postgres=X/postgres}','R2-F-C owner-only atomic tuition core. New generation holds fixed-order SHARE table locks on lesson and settlement evidence tables until transaction end; public wrapper remains R0 blocked.'),
    ('F','public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text)','a8ea31ced7f054d0b7ca4306dda1d3d8','{postgres=X/postgres}',NULL),
    ('N','public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text)','54ba2360eae9abfa740f539cb2ffb4ab','{postgres=X/postgres}',NULL)
  ) AS t(code,sig,md5,acl,cmt) LOOP
    v_oid := to_regprocedure(r.sig);
    IF v_oid IS NULL THEN
      RAISE EXCEPTION 'OG_BASELINE_MISSING: % (%) 不存在', r.code, r.sig;
    END IF;
    SELECT md5(pg_get_functiondef(v_oid)),
           coalesce(proacl::text,''), coalesce(array_to_string(proconfig,','),''),
           obj_description(v_oid,'pg_proc')
      INTO v_md5, v_acl, v_cfg, v_cmt
      FROM pg_proc WHERE oid = v_oid;
    IF v_md5 <> r.md5 THEN
      RAISE EXCEPTION 'OG_BASELINE_DRIFT: % md5=% 期望 %', r.code, v_md5, r.md5;
    END IF;
    IF v_acl <> r.acl THEN
      RAISE EXCEPTION 'OG_ACL_DRIFT: % acl=% 期望 %', r.code, v_acl, r.acl;
    END IF;
    IF v_cfg <> 'search_path=pg_catalog, public' THEN
      RAISE EXCEPTION 'OG_PROCONFIG_DRIFT: % proconfig=%', r.code, v_cfg;
    END IF;
    IF v_cmt IS DISTINCT FROM r.cmt THEN
      RAISE EXCEPTION 'OG_COMMENT_DRIFT: % 注释与取证不符', r.code;
    END IF;
  END LOOP;

  -- BG：直接调 builder 并写账单，但仅 postgres 可执行、无生产调用方。
  -- 「它现在不可达」若只写进文档就会过期；写成断言才不会。
  v_oid := to_regprocedure('public.school_p0c_baseline_generate_atomic_core(uuid,text,numeric,text,text,text)');
  IF v_oid IS NULL THEN RAISE EXCEPTION 'OG_BG_MISSING'; END IF;
  SELECT md5(pg_get_functiondef(v_oid)), coalesce(proacl::text,'')
    INTO v_md5, v_acl FROM pg_proc WHERE oid = v_oid;
  IF v_md5 <> '5adc2283993493e1a6095b5fabe460b0' THEN RAISE EXCEPTION 'OG_BG_DRIFT: md5=%', v_md5; END IF;
  IF v_acl <> '{postgres=X/postgres}' THEN
    RAISE EXCEPTION 'OG_BG_ACL_WIDENED: %  ← baseline core 已被授权，重新评估可达性', v_acl;
  END IF;

  RAISE NOTICE 'OG: 基线断言全部通过（5 个目标函数 + BG 不可达）';
END $lc$;

-- -----------------------------------------------------------------------------
-- §2 前置扫描：记录 B / V 在每个 (student, month) 上的完整输出【或 SQLSTATE】
--
--     验收判据是「同输入 → 同输出」，不是「存量行没变」——
--     存量账单本来就不会被 UPDATE，只比对它们是【真空通过】。
-- -----------------------------------------------------------------------------
-- in_key 是【完整输入向量】的文本表示：
--   B / V  -> student|month
--   EP     -> generation_identity|previous_revision|student|month
-- 前后比对按 in_key 配对。EP 的输入含 generation 与 previous revision，
-- 只用 学生+月份 会在同月存在多个 voided revision 时产生交叉配对，
-- 那就不是「同输入对同输入」了。
CREATE TEMP TABLE og_sweep(
  phase text, fn text, in_key text, student_id uuid, billing_month text,
  ok boolean, sqlstate text, errcode text, payload jsonb
) ON COMMIT DROP;

CREATE TEMP TABLE og_combo(student_id uuid, billing_month text, rate numeric)
  ON COMMIT DROP;
INSERT INTO og_combo
SELECT DISTINCT l.student_id, to_char(l.lesson_date,'YYYY-MM'), 0.042::numeric
FROM public.school_lesson_records l
WHERE l.student_id IS NOT NULL
UNION
SELECT DISTINCT b.student_id, b.billing_month, 0.042::numeric
FROM public.school_student_tuition_bills b;

CREATE TEMP TABLE og_p0e ON COMMIT DROP AS
SELECT r.generation_identity_id, r.id AS previous_revision_id,
       g.student_id, g.business_entity_id,
       to_char(g.billing_month,'YYYY-MM') AS billing_month
FROM public.school_student_tuition_generation_revisions r
JOIN public.school_student_tuition_generation_identities g ON g.id = r.generation_identity_id
WHERE r.lifecycle_status = 'voided' AND r.manifest_kind = 'atomic_generation_v1';

-- 无条件设置：coalesce 既有会话值会让 -v 传入的新值被旧值遮蔽，
-- 且日志打印的参数就不是实际调用值。
SELECT set_config('og.p0e_adjustment_type', :'p0e_adjustment_type', false);

CREATE OR REPLACE FUNCTION pg_temp.og_scan(p_phase text) RETURNS void
LANGUAGE plpgsql AS $lc$
DECLARE c record; v jsonb; k text;
BEGIN
  FOR c IN SELECT * FROM og_combo LOOP
    k := c.student_id::text || '|' || c.billing_month;
    -- INTO STRICT：零行不得被记成 ok=true / payload=NULL，那会削弱覆盖率门槛
    BEGIN
      SELECT to_jsonb(s) INTO STRICT v
      FROM public.school_build_student_tuition_generation_snapshot(
        c.student_id,c.billing_month,c.rate) s;
      INSERT INTO og_sweep VALUES(p_phase,'B',k,c.student_id,c.billing_month,true,NULL,NULL,v);
    EXCEPTION WHEN OTHERS THEN
      -- 同为 P0001 的不同业务错误必须区分，故一并记录错误码前缀
      INSERT INTO og_sweep VALUES(p_phase,'B',k,c.student_id,c.billing_month,false,
        SQLSTATE,split_part(SQLERRM,':',1),NULL);
    END;
    BEGIN
      SELECT to_jsonb(s) INTO STRICT v
      FROM public.school_get_student_tuition_validation_preview_details(
        c.student_id,c.billing_month,c.rate) s;
      INSERT INTO og_sweep VALUES(p_phase,'V',k,c.student_id,c.billing_month,true,NULL,NULL,v);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO og_sweep VALUES(p_phase,'V',k,c.student_id,c.billing_month,false,
        SQLSTATE,split_part(SQLERRM,':',1),NULL);
    END;
  END LOOP;

  -- EP（P0-E 重发预览）：金额最不该变的一条路径。
  -- adjustment_type 由 -v p0e_adjustment_type=... 指定，默认
  -- neutralize_historical_carryover_v1；取值不适用时 EP 会前后一致地失败，
  -- 覆盖率门槛会把它标为未验证。
  -- ⚠️ EP 还要求该 generation 没有 active revision，故并非每个 voided
  --    revision 都能产出成功样本。
  FOR c IN SELECT * FROM og_p0e LOOP
    k := c.generation_identity_id::text || '|' || c.previous_revision_id::text
         || '|' || c.student_id::text || '|' || c.billing_month;
    BEGIN
      SELECT to_jsonb(s) INTO STRICT v
      FROM public.school_get_atomic_tuition_reissue_preview_p0e(
        c.generation_identity_id,c.previous_revision_id,c.student_id,
        c.business_entity_id,c.billing_month,0.042,
        current_setting('og.p0e_adjustment_type',true),'og sweep probe') s;
      INSERT INTO og_sweep VALUES(p_phase,'EP',k,c.student_id,c.billing_month,true,NULL,NULL,v);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO og_sweep VALUES(p_phase,'EP',k,c.student_id,c.billing_month,false,
        SQLSTATE,split_part(SQLERRM,':',1),NULL);
    END;
  END LOOP;
END $lc$;

SELECT pg_temp.og_scan('before');

-- -----------------------------------------------------------------------------
-- §3 新对象（ack 事件表 / 守卫函数 / 触发器 / 只读 reader）
--     由独立文件提供，必须在【本事务内、本行位置】执行：
-- -----------------------------------------------------------------------------
\ir school_tuition_generation_ordering_guard_new_objects_20260908.sql

-- -----------------------------------------------------------------------------
-- §4 函数替换
--
--   B  签名不变 ⇒ CREATE OR REPLACE
--   G/C/F/N 增加参数 ⇒ 【必须 DROP + CREATE】。
--     CREATE OR REPLACE 不能增删参数，会产生【新重载而旧签名仍在】。
--     本地 harness 已实证该场景直接报
--       function ... is not unique
--     ——SQL 层就会歧义，不必等到 PostgREST。
--
--   DROP 会清除 ACL / COMMENT，且【默认授权含 service_role】，
--   故 C/F/N 重建后必须【显式 REVOKE service_role】，否则权限扩大。
-- -----------------------------------------------------------------------------
-- ── B：加 resolver 调用与六个只读 evidence 键（金额逻辑一字未动）──
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
  v_eff_complete boolean;
  v_eff_status text;
  v_eff_source_type text;
  v_eff_source_id uuid;
  v_eff_carry numeric;
  v_eff_blocker text;
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

  -- 上月结算的「完成状态」与「来源金额」——只作事实记录，不参与任何金额计算。
  -- 上面的 IF FOUND / ELSE 结转逻辑一字未动：carry_cny 是 provenance，不是应计结转。
  SELECT resolved.effective_complete,resolved.effective_status,resolved.source_type,
         resolved.source_id,resolved.carry_cny,resolved.blocker_code
    INTO v_eff_complete,v_eff_status,v_eff_source_type,
         v_eff_source_id,v_eff_carry,v_eff_blocker
  FROM public.school_resolve_student_monthly_settlement_effective_state(
    p_student_id,v_previous_month,v_student.business_entity_id
  ) resolved;

  v_carryover_evidence := v_carryover_evidence || jsonb_build_object(
    'settlement_effective_complete',v_eff_complete,
    'settlement_effective_status',v_eff_status,
    'settlement_source_type',v_eff_source_type,
    'settlement_source_id',v_eff_source_id,
    'settlement_provenance_carry_cny',v_eff_carry,
    'settlement_blocker_code',v_eff_blocker
  );

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
$function$
;

-- ── G ──
DROP FUNCTION IF EXISTS public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text);
CREATE OR REPLACE FUNCTION public.school_generate_student_tuition_bill_atomic(p_student_id uuid, p_billing_month text, p_billing_exchange_rate numeric, p_expected_generation_manifest_sha256 text, p_note text DEFAULT NULL::text, p_previous_settlement_absence_ack_reason text DEFAULT NULL::text)
 RETURNS TABLE(tuition_bill_id uuid, billing_identity_id uuid, income_record_id uuid, student_id uuid, business_entity_id uuid, billing_month text, generation_manifest_sha256 text, candidate_count integer, total_lesson_count integer, total_duration_hours numeric, total_base_lesson_fee_jpy numeric, total_aircon_fee_jpy numeric, total_fee_jpy numeric, billing_exchange_rate numeric, previous_carryover_cny numeric, billing_amount_cny numeric, bill_status text, income_status text, idempotent boolean, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  PERFORM public.school_require_feature_gate_state(
    'student_tuition_generate','enabled','TUITION_GENERATION_BLOCKED',
    '学费应收生成功能尚未开放，当前禁止生成正式账单或收入。'
  );
  RETURN QUERY SELECT *
  FROM public.school_generate_student_tuition_bill_atomic_core(
    p_student_id,p_billing_month,p_billing_exchange_rate,
    p_expected_generation_manifest_sha256,p_note,NULL,
    p_previous_settlement_absence_ack_reason
  );
END
$function$
;
-- ⚠️ DROP 之后 public schema 的默认授权会把 service_role 【先】放回 ACL 数组，
--    随后的 GRANT 再追加 authenticated ⇒ 顺序成为
--    {postgres,service_role,authenticated}，与基线的
--    {postgres,authenticated,service_role} 不符 —— 权限集合相同，数组顺序不同。
--    故先【显式清空】，再【按基线顺序逐条 GRANT】。
--    2026-09-09 的 Cash 部署栽在同一处；那次修了 Cash，没回头查这个脚本。
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text,text) FROM authenticated;
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text,text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text,text) TO service_role;
COMMENT ON FUNCTION public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text,text) IS 'R2-F-B authoritative atomic tuition writer. The public wrapper is R0-gated; clients submit no amounts or candidate details.';

-- ── C ──
DROP FUNCTION IF EXISTS public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text);
CREATE OR REPLACE FUNCTION public.school_generate_student_tuition_bill_atomic_core(p_student_id uuid, p_billing_month text, p_billing_exchange_rate numeric, p_expected_generation_manifest_sha256 text, p_note text DEFAULT NULL::text, p_test_fail_after_step text DEFAULT NULL::text, p_previous_settlement_absence_ack_reason text DEFAULT NULL::text)
 RETURNS TABLE(tuition_bill_id uuid, billing_identity_id uuid, income_record_id uuid, student_id uuid, business_entity_id uuid, billing_month text, generation_manifest_sha256 text, candidate_count integer, total_lesson_count integer, total_duration_hours numeric, total_base_lesson_fee_jpy numeric, total_aircon_fee_jpy numeric, total_fee_jpy numeric, billing_exchange_rate numeric, previous_carryover_cny numeric, billing_amount_cny numeric, bill_status text, income_status text, idempotent boolean, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_student public.school_students%rowtype; v_generation public.school_student_tuition_generation_identities%rowtype;
  v_revision public.school_student_tuition_generation_revisions%rowtype;
  v_previous public.school_student_tuition_generation_revisions%rowtype;
  v_bill public.school_student_tuition_bills%rowtype; v_income public.school_income_records%rowtype;
  v_legacy public.school_student_tuition_billing_identities%rowtype; v_result record;
  v_month date;
  -- 照抄 void 先例：插入事件的函数在【开始时】取一次 clock_timestamp()，
  -- 不是 now()、也不是 INSERT 当场调用。
  v_now timestamptz:=clock_timestamp();
  v_new_revision_id uuid;
begin
  if p_billing_month is null or btrim(p_billing_month)!~'^[0-9]{4}-(0[1-9]|1[0-2])$'
     or p_billing_exchange_rate is null or p_billing_exchange_rate<=0
     or p_expected_generation_manifest_sha256!~'^[0-9a-f]{64}$' then
    raise exception 'R2_F_B_GENERATION_INPUT_INVALID';
  end if;
  v_month:=to_date(btrim(p_billing_month)||'-01','YYYY-MM-DD');
  select s.* into strict v_student from public.school_students s
  where s.id=p_student_id and s.app_type='school';
  perform public.school_lock_student_tuition_operation(p_student_id,v_student.business_entity_id,(v_month-interval '1 month')::date);
  perform public.school_lock_student_tuition_operation(p_student_id,v_student.business_entity_id,v_month);
  select g.* into v_generation from public.school_student_tuition_generation_identities g
  where g.student_id=p_student_id and g.business_entity_id=v_student.business_entity_id
    and g.billing_month=v_month for update;
  if not found then
    select * into strict v_result from public.school_generate_student_tuition_bill_atomic_base_core_v1(
      p_student_id,p_billing_month,p_billing_exchange_rate,p_expected_generation_manifest_sha256,p_note,p_test_fail_after_step,
      p_previous_settlement_absence_ack_reason);
    select i.* into strict v_legacy from public.school_student_tuition_billing_identities i
    where i.id=v_result.billing_identity_id;
    insert into public.school_student_tuition_generation_identities(
      id,student_id,business_entity_id,billing_month,legacy_billing_identity_id,created_at,created_by_authority
    ) values(gen_random_uuid(),p_student_id,v_student.business_entity_id,v_month,v_legacy.id,now(),'service_role_v2_operations_v1')
    returning * into v_generation;
    insert into public.school_student_tuition_generation_revisions(
      id,generation_identity_id,tuition_bill_id,revision_no,previous_revision_id,
      generation_manifest_sha256,manifest_kind,lifecycle_status,created_at,created_by_authority,
      activated_at,voided_at,voided_by_authority
    ) values(gen_random_uuid(),v_generation.id,v_result.tuition_bill_id,1,null,
      p_expected_generation_manifest_sha256,'atomic_generation_v1','active',now(),
      'service_role_v2_operations_v1',now(),null,null)
    returning id into v_new_revision_id;
    perform public.school_validate_tuition_identity_for_bill(v_result.tuition_bill_id);
    perform public.school_validate_tuition_bill_income_for_bill(v_result.tuition_bill_id);
    perform public.school_validate_tuition_bill_lessons_for_bill(v_result.tuition_bill_id);
    if v_result.ack_consumed then
      insert into public.school_student_tuition_generation_ordering_ack_events(
        id,generation_identity_id,generation_revision_id,tuition_bill_id,income_record_id,
        expected_generation_manifest_sha256,reason,operator_authority,
        operator_authority_source,precondition_evidence,result_evidence,created_at
      ) values(
        gen_random_uuid(),v_generation.id,v_new_revision_id,v_result.tuition_bill_id,
        v_result.income_record_id,p_expected_generation_manifest_sha256,
        p_previous_settlement_absence_ack_reason,v_result.ack_operator_authority,
        v_result.ack_operator_authority_source,v_result.ack_precondition_evidence,
        jsonb_build_object(
          'billing_month',v_result.billing_month,
          'previous_carryover_cny',v_result.previous_carryover_cny,
          'billing_amount_cny',v_result.billing_amount_cny,
          'candidate_count',v_result.candidate_count,
          'total_lesson_count',v_result.total_lesson_count,
          'generation_manifest_sha256',v_result.generation_manifest_sha256
        ),v_now);
    end if;
    
return query select
      v_result.tuition_bill_id::uuid,
      v_result.billing_identity_id::uuid,
      v_result.income_record_id::uuid,
      v_result.student_id::uuid,
      v_result.business_entity_id::uuid,
      v_result.billing_month::text,
      v_result.generation_manifest_sha256::text,
      v_result.candidate_count::integer,
      v_result.total_lesson_count::integer,
      v_result.total_duration_hours::numeric,
      v_result.total_base_lesson_fee_jpy::numeric,
      v_result.total_aircon_fee_jpy::numeric,
      v_result.total_fee_jpy::numeric,
      v_result.billing_exchange_rate::numeric,
      v_result.previous_carryover_cny::numeric,
      v_result.billing_amount_cny::numeric,
      v_result.bill_status::text,
      v_result.income_status::text,
      v_result.idempotent::boolean,
      v_result.message::text;
    return;
  end if;
  select r.* into v_revision from public.school_student_tuition_generation_revisions r
  where r.generation_identity_id=v_generation.id and r.lifecycle_status='active' for update;
  if found then
    if v_revision.manifest_kind<>'atomic_generation_v1'
       or v_revision.generation_manifest_sha256<>p_expected_generation_manifest_sha256 then
      raise exception 'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE';
    end if;
    select b.* into strict v_bill from public.school_student_tuition_bills b where b.id=v_revision.tuition_bill_id for update;
    select i.* into strict v_income from public.school_income_records i where i.id=v_bill.income_record_id for update;
    select l.* into strict v_legacy from public.school_student_tuition_billing_identities l
      where l.id=v_generation.legacy_billing_identity_id;
    if v_bill.billing_exchange_rate<>p_billing_exchange_rate or v_bill.status<>'income_created'
       or v_income.status<>'pending' then raise exception 'R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'; end if;
    perform public.school_validate_tuition_identity_for_bill(v_bill.id);
    perform public.school_validate_tuition_bill_income_for_bill(v_bill.id);
    perform public.school_validate_tuition_bill_lessons_for_bill(v_bill.id);
    return query select v_bill.id,v_legacy.id,v_income.id,v_bill.student_id,v_bill.business_entity_id,
      v_bill.billing_month,v_revision.generation_manifest_sha256,v_bill.planned_lesson_count,
      (v_bill.source_snapshot->>'total_lesson_count')::integer,v_bill.planned_lesson_hours,
      (v_bill.source_snapshot->>'total_base_lesson_fee_jpy')::numeric,
      (v_bill.source_snapshot->>'total_aircon_fee_jpy')::numeric,v_bill.bill_amount_jpy,
      v_bill.billing_exchange_rate,v_bill.previous_carryover_cny,v_bill.billing_amount_cny,
      v_bill.status,v_income.status,true,'existing active tuition revision returned idempotently'::text;
    return;
  end if;
  select r.* into strict v_previous from public.school_student_tuition_generation_revisions r
  where r.generation_identity_id=v_generation.id order by r.revision_no desc limit 1 for update;
  if v_previous.manifest_kind='historical_registration_v1' then
    raise exception 'TUITION_HISTORICAL_REVISION_REISSUE_FORBIDDEN';
  end if;
  select * into strict v_result
  from public.school_generate_student_tuition_next_revision_core(
    v_generation.id,v_previous.id,p_student_id,p_billing_month,p_billing_exchange_rate,
    p_expected_generation_manifest_sha256,p_note,p_test_fail_after_step,
    p_previous_settlement_absence_ack_reason);
  if v_result.ack_consumed then
    insert into public.school_student_tuition_generation_ordering_ack_events(
      id,generation_identity_id,generation_revision_id,tuition_bill_id,income_record_id,
      expected_generation_manifest_sha256,reason,operator_authority,
      operator_authority_source,precondition_evidence,result_evidence,created_at
    ) values(
      gen_random_uuid(),v_generation.id,v_result.generation_revision_id,v_result.tuition_bill_id,
      v_result.income_record_id,p_expected_generation_manifest_sha256,
      p_previous_settlement_absence_ack_reason,v_result.ack_operator_authority,
      v_result.ack_operator_authority_source,v_result.ack_precondition_evidence,
      jsonb_build_object(
        'billing_month',v_result.billing_month,
        'previous_carryover_cny',v_result.previous_carryover_cny,
        'billing_amount_cny',v_result.billing_amount_cny,
        'candidate_count',v_result.candidate_count,
        'total_lesson_count',v_result.total_lesson_count,
        'generation_manifest_sha256',v_result.generation_manifest_sha256
      ),v_now);
  end if;

  -- 显式投影【原 20 列】。N 已扩展为 25 列，若继续 select * 转发，
  -- 新增的内部事实会改变 G/C 的对外结果结构。
  return query select
    v_result.tuition_bill_id::uuid,
    v_result.billing_identity_id::uuid,
    v_result.income_record_id::uuid,
    v_result.student_id::uuid,
    v_result.business_entity_id::uuid,
    v_result.billing_month::text,
    v_result.generation_manifest_sha256::text,
    v_result.candidate_count::integer,
    v_result.total_lesson_count::integer,
    v_result.total_duration_hours::numeric,
    v_result.total_base_lesson_fee_jpy::numeric,
    v_result.total_aircon_fee_jpy::numeric,
    v_result.total_fee_jpy::numeric,
    v_result.billing_exchange_rate::numeric,
    v_result.previous_carryover_cny::numeric,
    v_result.billing_amount_cny::numeric,
    v_result.bill_status::text,
    v_result.income_status::text,
    v_result.idempotent::boolean,
    v_result.message::text;
  return;
end;
$function$
;
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text,text) FROM service_role;   -- 阻断默认授权回流
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text,text) FROM authenticated;
COMMENT ON FUNCTION public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text,text) IS 'R2-F-C owner-only atomic tuition core. New generation holds fixed-order SHARE table locks on lesson and settlement evidence tables until transaction end; public wrapper remains R0 blocked.';

-- ── F ──
DROP FUNCTION IF EXISTS public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text);
CREATE OR REPLACE FUNCTION public.school_generate_student_tuition_bill_atomic_base_core_v1(p_student_id uuid, p_billing_month text, p_billing_exchange_rate numeric, p_expected_generation_manifest_sha256 text, p_note text DEFAULT NULL::text, p_test_fail_after_step text DEFAULT NULL::text, p_previous_settlement_absence_ack_reason text DEFAULT NULL::text)
 RETURNS TABLE(tuition_bill_id uuid, billing_identity_id uuid, income_record_id uuid, student_id uuid, business_entity_id uuid, billing_month text, generation_manifest_sha256 text, candidate_count integer, total_lesson_count integer, total_duration_hours numeric, total_base_lesson_fee_jpy numeric, total_aircon_fee_jpy numeric, total_fee_jpy numeric, billing_exchange_rate numeric, previous_carryover_cny numeric, billing_amount_cny numeric, bill_status text, income_status text, idempotent boolean, message text, generation_revision_id uuid, ack_consumed boolean, ack_operator_authority text, ack_operator_authority_source text, ack_precondition_evidence jsonb)
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
  -- 来源标签由身份取值【实际走的分支】决定；条件与 v_operator 逐字相同（不 trim）。
  v_operator_source text:=CASE
    WHEN nullif(current_setting('request.jwt.claim.sub',true),'') IS NOT NULL
    THEN 'request_jwt_claim_sub' ELSE 'fallback_current_user' END;
  v_ack_consumed boolean:=false;
  v_ack_precondition jsonb;
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
      v_bill.status,v_income.status,true,'existing atomic tuition generation returned idempotently'::text,
      NULL::uuid,false,NULL::text,NULL::text,NULL::jsonb;
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

  -- 顺序守卫：只回答「上月结算是否完成」。不判断重发是否合法——重发身份、
  -- 生命周期、来源消费、调整契约各有其检查，本布尔值不得替代任何一项。
  -- 位置刻意在既有一致性检查【之后】、writer context 建立【之前】：
  -- 请求本身无效（manifest 陈旧、候选集变化）应先于「不该现在生成」报出，
  -- 且此处 RAISE 时尚无任何写入需要回退。
  -- 亦必须在 builder 调用【之后】——上方旧 billing identity 的幂等分支在
  -- builder 之前就 RETURN，它不建账单、不消费 ack，勿将本检查上移。
  IF (v_snapshot.carryover_evidence->>'settlement_effective_complete')::boolean IS NOT TRUE THEN
    IF nullif(btrim(coalesce(p_previous_settlement_absence_ack_reason,'')),'') IS NULL THEN
      RAISE EXCEPTION 'TUITION_PREVIOUS_SETTLEMENT_INCOMPLETE: student % period % not settled (%)',
        p_student_id,v_snapshot.previous_settlement_month,
        coalesce(v_snapshot.carryover_evidence->>'settlement_blocker_code','no_settlement');
    END IF;
    v_ack_consumed:=true;
    -- 事实在哪产生就在哪取：不重算，直接取 snapshot 的对应键。
    -- previous_settlement_month 对应的键名是 settlement_month，须显式映射。
    v_ack_precondition:=jsonb_build_object(
      'previous_settlement_month',v_snapshot.carryover_evidence->>'settlement_month',
      'settlement_effective_complete',v_snapshot.carryover_evidence->'settlement_effective_complete',
      'settlement_effective_status',v_snapshot.carryover_evidence->>'settlement_effective_status',
      'settlement_blocker_code',v_snapshot.carryover_evidence->>'settlement_blocker_code',
      'settlement_source_type',v_snapshot.carryover_evidence->>'settlement_source_type',
      'settlement_source_id',v_snapshot.carryover_evidence->>'settlement_source_id',
      'settlement_provenance_carry_cny',v_snapshot.carryover_evidence->'settlement_provenance_carry_cny'
    );
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
    v_bill.status,v_income.status,false,'atomic tuition bill, identity, relations and pending income created'::text,
    NULL::uuid,v_ack_consumed,
    CASE WHEN v_ack_consumed THEN v_operator END,
    CASE WHEN v_ack_consumed THEN v_operator_source END,
    v_ack_precondition;
END
$function$
;
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text,text) FROM service_role;   -- 阻断默认授权回流
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text,text) FROM authenticated;
-- F 生产 COMMENT 为 SQL NULL ⇒ 不得添加注释

-- ── N ──
DROP FUNCTION IF EXISTS public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text);
CREATE OR REPLACE FUNCTION public.school_generate_student_tuition_next_revision_core(p_generation_identity_id uuid, p_previous_revision_id uuid, p_student_id uuid, p_billing_month text, p_billing_exchange_rate numeric, p_expected_generation_manifest_sha256 text, p_note text, p_test_fail_after_step text, p_previous_settlement_absence_ack_reason text DEFAULT NULL::text)
 RETURNS TABLE(tuition_bill_id uuid, billing_identity_id uuid, income_record_id uuid, student_id uuid, business_entity_id uuid, billing_month text, generation_manifest_sha256 text, candidate_count integer, total_lesson_count integer, total_duration_hours numeric, total_base_lesson_fee_jpy numeric, total_aircon_fee_jpy numeric, total_fee_jpy numeric, billing_exchange_rate numeric, previous_carryover_cny numeric, billing_amount_cny numeric, bill_status text, income_status text, idempotent boolean, message text, generation_revision_id uuid, ack_consumed boolean, ack_operator_authority text, ack_operator_authority_source text, ack_precondition_evidence jsonb)
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
  v_operator_source text:=CASE
    WHEN nullif(current_setting('school.tuition_operator_authority',true),'') IS NOT NULL
    THEN 'tuition_operator_authority' ELSE 'fallback_literal' END;
  v_ack_consumed boolean:=false;
  v_ack_precondition jsonb;
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

  -- 顺序守卫：只回答「上月结算是否完成」。不判断重发是否合法。
  -- 位置在既有一致性检查之后、writer context 建立之前。
  if (v_snapshot.carryover_evidence->>'settlement_effective_complete')::boolean is not true then
    if nullif(btrim(coalesce(p_previous_settlement_absence_ack_reason,'')),'') is null then
      raise exception 'TUITION_PREVIOUS_SETTLEMENT_INCOMPLETE: student % period % not settled (%)',
        p_student_id,v_snapshot.previous_settlement_month,
        coalesce(v_snapshot.carryover_evidence->>'settlement_blocker_code','no_settlement');
    end if;
    v_ack_consumed:=true;
    v_ack_precondition:=jsonb_build_object(
      'previous_settlement_month',v_snapshot.carryover_evidence->>'settlement_month',
      'settlement_effective_complete',v_snapshot.carryover_evidence->'settlement_effective_complete',
      'settlement_effective_status',v_snapshot.carryover_evidence->>'settlement_effective_status',
      'settlement_blocker_code',v_snapshot.carryover_evidence->>'settlement_blocker_code',
      'settlement_source_type',v_snapshot.carryover_evidence->>'settlement_source_type',
      'settlement_source_id',v_snapshot.carryover_evidence->>'settlement_source_id',
      'settlement_provenance_carry_cny',v_snapshot.carryover_evidence->'settlement_provenance_carry_cny'
    );
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
    v_bill.status,v_income.status,false,'atomic tuition revision created'::text,
    v_revision_id,v_ack_consumed,
    case when v_ack_consumed then v_operator end,
    case when v_ack_consumed then v_operator_source end,
    v_ack_precondition;
end;
$function$
;
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text,text) FROM service_role;   -- 阻断默认授权回流
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text,text) FROM authenticated;
-- N 生产 COMMENT 为 SQL NULL ⇒ 不得添加注释

-- -----------------------------------------------------------------------------
-- §5 后置断言
-- -----------------------------------------------------------------------------
SELECT set_config('og.mode', :'mode', false);
SELECT set_config('og.allow_incomplete_coverage', :'allow_incomplete_coverage', false);
SELECT pg_temp.og_scan('after');

DO $lc$
DECLARE
  r record; v_oid oid; v_md5 text; v_acl text; v_cfg text; v_cmt text; v_own text;
  v_ok int; v_fail int; v_bad int; v_incomplete int := 0;
BEGIN
  -- 5.1 新定义、ACL、proconfig、COMMENT
  FOR r IN SELECT * FROM (VALUES
    ('B','public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)','c456d247f804058e8ae29ef4ba419599','{postgres=X/postgres,service_role=X/postgres}','Phase B3: existing tuition facts are governed by lesson, settlement, bill, income, immutable and Gate contracts; frozen legacy student status is not an eligibility authority.'),
    ('G','public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text,text)','40ef9ec344623bb7c02bf8aea670ad52','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','R2-F-B authoritative atomic tuition writer. The public wrapper is R0-gated; clients submit no amounts or candidate details.'),
    ('C','public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text,text)','dad1d0512d44114aed0d9c2a3b61480e','{postgres=X/postgres}','R2-F-C owner-only atomic tuition core. New generation holds fixed-order SHARE table locks on lesson and settlement evidence tables until transaction end; public wrapper remains R0 blocked.'),
    ('F','public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text,text)','8b9b4fd5079a2794aa15c223bbbf9ffc','{postgres=X/postgres}',NULL),
    ('N','public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text,text)','06262763ce6c223e1b271e2be005fdbb','{postgres=X/postgres}',NULL)
  ) AS t(code,sig,md5,acl,cmt) LOOP
    v_oid := to_regprocedure(r.sig);
    IF v_oid IS NULL THEN RAISE EXCEPTION 'OG_POST_MISSING: %', r.code; END IF;
    SELECT md5(pg_get_functiondef(v_oid)), coalesce(proacl::text,''),
           coalesce(array_to_string(proconfig,','),''), obj_description(v_oid,'pg_proc'),
           pg_get_userbyid(proowner)
      INTO v_md5, v_acl, v_cfg, v_cmt, v_own FROM pg_proc WHERE oid = v_oid;
    IF v_md5 <> r.md5 THEN RAISE EXCEPTION 'OG_POST_MD5: % 得 %', r.code, v_md5; END IF;
    -- owner 不在函数定义的 md5 里。它【也不是】上面 ACL 断言漏掉的东西 ——
    -- 改 owner 会把 ACL 里的授予者一并改掉（X/someone_else），实测由 ACL 断言先响。
    -- 这条的价值是【诊断】：直接说出 owner 是谁，而不是让人去解码那串 ACL。
    IF v_own <> 'postgres' THEN
      RAISE EXCEPTION 'OG_POST_OWNER: % 的 owner 为 %（应为 postgres）'
        '  ← 本脚本被非 postgres 角色执行过', r.code, v_own; END IF;
    IF v_acl <> r.acl THEN
      -- 集合相同而仅顺序不同，与真的多/少了一个角色，是两回事。
      -- 报文不分开，收到的人得自己逐字符比对才知道是哪一种。
      IF EXISTS (SELECT unnest(string_to_array(btrim(v_acl,'{}'),','))
                 EXCEPT SELECT unnest(string_to_array(btrim(r.acl,'{}'),',')))
         OR EXISTS (SELECT unnest(string_to_array(btrim(r.acl,'{}'),','))
                    EXCEPT SELECT unnest(string_to_array(btrim(v_acl,'{}'),','))) THEN
        RAISE EXCEPTION 'OG_POST_ACL_SET: % 权限集合与基线不同  实际 %  期望 %',
          r.code, v_acl, r.acl;
      ELSE
        RAISE EXCEPTION 'OG_POST_ACL_ORDER: % 集合相同但数组顺序不同  实际 %  期望 %',
          r.code, v_acl, r.acl;
      END IF;
    END IF;
    IF v_cfg <> 'search_path=pg_catalog, public' THEN
      RAISE EXCEPTION 'OG_POST_PROCONFIG: % 得 %', r.code, v_cfg; END IF;
    IF v_cmt IS DISTINCT FROM r.cmt THEN
      RAISE EXCEPTION 'OG_POST_COMMENT: % 注释未按原文恢复', r.code; END IF;
  END LOOP;

  -- 5.2 旧签名必须消失（必要断言之一，非唯一防线）
  FOR r IN SELECT * FROM (VALUES
    ('public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)'),('public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'),
    ('public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text)'),('public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text)')
  ) AS t(sig) LOOP
    IF to_regprocedure(r.sig) IS NOT NULL THEN
      RAISE EXCEPTION 'OG_OLD_SIGNATURE_ALIVE: %  ← 重载歧义风险', r.sig;
    END IF;
  END LOOP;

  -- 5.2b 五个函数名各自【只能有一个重载】。
  --   上一条只查【已知的】四个旧签名，来历不明的第三个重载它看不见；
  --   5.1 走 to_regprocedure(精确签名)，多出来的重载同样看不见。
  --   ⇒ 五个 md5 断言可以全绿，而 PostgREST 在调用时才报
  --     function ... is not unique。按【名字】数，才关得住这一类。
  FOR r IN SELECT * FROM (VALUES
    ('school_build_student_tuition_generation_snapshot'),
    ('school_generate_student_tuition_bill_atomic'),
    ('school_generate_student_tuition_bill_atomic_core'),
    ('school_generate_student_tuition_bill_atomic_base_core_v1'),
    ('school_generate_student_tuition_next_revision_core')
  ) AS t(nm) LOOP
    SELECT count(*) INTO v_bad FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = r.nm;
    IF v_bad <> 1 THEN
      RAISE EXCEPTION 'OG_OVERLOAD_NOT_UNIQUE: public.% 有 % 个重载（应为 1）%实际: %',
        r.nm, v_bad, chr(10),
        (SELECT string_agg(pg_get_function_identity_arguments(p2.oid), '  |  ' ORDER BY p2.oid)
           FROM pg_proc p2 JOIN pg_namespace n2 ON n2.oid = p2.pronamespace
          WHERE n2.nspname = 'public' AND p2.proname = r.nm);
    END IF;
  END LOOP;

  -- 5.3 对外返回契约：G 与 C 的返回签名必须【逐字节】等于基线。
  --     只数逗号是不够的——同列数、不同名称或类型也能通过。
  FOR r IN SELECT * FROM (VALUES
    ('public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text,text)','TABLE(tuition_bill_id uuid, billing_identity_id uuid, income_record_id uuid, student_id uuid, business_entity_id uuid, billing_month text, generation_manifest_sha256 text, candidate_count integer, total_lesson_count integer, total_duration_hours numeric, total_base_lesson_fee_jpy numeric, total_aircon_fee_jpy numeric, total_fee_jpy numeric, billing_exchange_rate numeric, previous_carryover_cny numeric, billing_amount_cny numeric, bill_status text, income_status text, idempotent boolean, message text)'),
    ('public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text,text)','TABLE(tuition_bill_id uuid, billing_identity_id uuid, income_record_id uuid, student_id uuid, business_entity_id uuid, billing_month text, generation_manifest_sha256 text, candidate_count integer, total_lesson_count integer, total_duration_hours numeric, total_base_lesson_fee_jpy numeric, total_aircon_fee_jpy numeric, total_fee_jpy numeric, billing_exchange_rate numeric, previous_carryover_cny numeric, billing_amount_cny numeric, bill_status text, income_status text, idempotent boolean, message text)')
  ) AS t(sig,expected) LOOP
    IF pg_get_function_result(to_regprocedure(r.sig)) IS DISTINCT FROM r.expected THEN
      RAISE EXCEPTION 'OG_RESULT_SHAPE_CHANGED: %  ← 前端契约被改变%  实际: %',
        r.sig, chr(10), pg_get_function_result(to_regprocedure(r.sig));
    END IF;
  END LOOP;

  -- 5.4 同输入同输出（B / V）。允许差异【仅限】carryover_evidence 的六个新键
  --     与由其派生的 generation_manifest_sha256；其余字段与错误码必须完全一致。
  --     不能把整个 carryover_evidence 剔除——那样原有键被改也查不出来。
  SELECT count(*) INTO v_bad FROM og_sweep a JOIN og_sweep b
    ON b.phase='after' AND a.phase='before' AND a.fn=b.fn AND a.in_key=b.in_key
  WHERE a.fn IN ('B','V')
    AND (a.ok <> b.ok
     OR a.sqlstate IS DISTINCT FROM b.sqlstate
     OR a.errcode  IS DISTINCT FROM b.errcode
     OR (a.ok AND (
              (a.payload - 'carryover_evidence' - 'generation_manifest_sha256')
           <> (b.payload - 'carryover_evidence' - 'generation_manifest_sha256')))
     OR (a.ok AND a.payload ? 'carryover_evidence' AND (
              (a.payload->'carryover_evidence')
           IS DISTINCT FROM ((b.payload->'carryover_evidence')
                - 'settlement_effective_complete' - 'settlement_effective_status'
                - 'settlement_source_type' - 'settlement_source_id'
                - 'settlement_provenance_carry_cny' - 'settlement_blocker_code'))));
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'OG_SWEEP_DIVERGED: % 个 B/V 组合的非豁免字段或错误码发生变化', v_bad;
  END IF;

  -- 5.4b EP 用【它自己的】矩阵——B/V 那套用在 EP 上正好是反的：
  --      base_generation_manifest_sha256  应【改变】（源自 B）
  --      generation_manifest_sha256       应【不变】（P0-E 专用最终 manifest，
  --                                        其计算不使用 B 的 carryover evidence）
  --      line_manifest_sha256、四个金额、三个身份引用  应【不变】
  --      EP 也不返回 carryover_evidence，剔除它毫无意义。
  SELECT count(*) INTO v_bad FROM og_sweep a JOIN og_sweep b
    ON b.phase='after' AND a.phase='before' AND a.fn=b.fn AND a.in_key=b.in_key
  WHERE a.fn='EP'
    AND (a.ok <> b.ok
     OR a.sqlstate IS DISTINCT FROM b.sqlstate
     OR a.errcode  IS DISTINCT FROM b.errcode
     OR (a.ok AND ((a.payload - 'base_generation_manifest_sha256')
                <> (b.payload - 'base_generation_manifest_sha256'))));
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'OG_EP_DIVERGED: % 个 EP 组合的应不变字段发生变化', v_bad;
  END IF;

  -- 5.4c EP 的 base manifest 【必须】改变——它源自 B，B 变了它不变才是异常
  SELECT count(*) INTO v_bad FROM og_sweep a JOIN og_sweep b
    ON b.phase='after' AND a.phase='before' AND a.fn='EP' AND b.fn='EP' AND a.in_key=b.in_key
  WHERE a.ok AND b.ok
    AND a.payload->>'base_generation_manifest_sha256'
      = b.payload->>'base_generation_manifest_sha256';
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'OG_EP_BASE_MANIFEST_UNCHANGED: % 个 EP 组合的 base manifest 未变  ← B 的改动未传导', v_bad;
  END IF;

  -- 5.5 【本次不改变任何金额】——出现差异即判失败
  SELECT count(*) INTO v_bad FROM og_sweep a JOIN og_sweep b
    ON b.phase='after' AND a.phase='before' AND a.fn=b.fn AND a.in_key=b.in_key
  WHERE a.ok AND b.ok
    AND (a.payload->>'previous_carryover_cny'  IS DISTINCT FROM b.payload->>'previous_carryover_cny'
      OR a.payload->>'billing_amount_cny'      IS DISTINCT FROM b.payload->>'billing_amount_cny'
      OR a.payload->>'previous_settlement_id'  IS DISTINCT FROM b.payload->>'previous_settlement_id'
      OR a.payload->>'exchange_amount_cny'          IS DISTINCT FROM b.payload->>'exchange_amount_cny'
      OR a.payload->>'source_historical_carryover_cny' IS DISTINCT FROM b.payload->>'source_historical_carryover_cny'
      OR a.payload->>'adjustment_amount_cny'        IS DISTINCT FROM b.payload->>'adjustment_amount_cny'
      OR a.payload->>'final_billing_amount_cny'     IS DISTINCT FROM b.payload->>'final_billing_amount_cny');
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'OG_AMOUNT_CHANGED: % 个组合金额或来源 ID 变化  ← 本次不应改变任何金额', v_bad;
  END IF;

  -- 5.6 六个新键必须真的出现在【每一个成功的 B 输出】里
  SELECT count(*) INTO v_bad FROM og_sweep
  WHERE phase='after' AND fn='B' AND ok
    AND NOT (payload->'carryover_evidence' ?& ARRAY[
      'settlement_effective_complete','settlement_effective_status','settlement_source_type',
      'settlement_source_id','settlement_provenance_carry_cny','settlement_blocker_code']);
  IF v_bad > 0 THEN RAISE EXCEPTION 'OG_EVIDENCE_KEYS_MISSING: % 个组合缺新键', v_bad; END IF;

  -- 5.7 同源断言：reader 与 B 的结论必须一致（只比双方都产出值的组合）
  SELECT count(*) INTO v_bad
  FROM og_sweep s
  CROSS JOIN LATERAL (
    SELECT (SELECT settlement_effective_complete
              FROM public.school_get_tuition_generation_ordering_state(s.student_id,s.billing_month)) AS rd
  ) x
  WHERE s.phase='after' AND s.fn='B' AND s.ok
    AND x.rd IS DISTINCT FROM (s.payload->'carryover_evidence'->>'settlement_effective_complete')::boolean;
  -- 不排除 rd IS NULL：B 成功而 reader 给不出结论，本身就是分叉，不能静默跳过。
  IF v_bad > 0 THEN RAISE EXCEPTION 'OG_READER_DIVERGED: % 个组合 reader 与 B 结论不一致或 reader 无结论', v_bad; END IF;

  -- 5.8 覆盖率门槛，【逐函数】施加，并显式枚举三个被验收函数：
  --     「一行都没扫到」与「扫了全失败」必须能区分，否则又是缺席被当成没问题。
  --
  --     排练：WARNING，继续收集其余结果，但整体标为【验收不完整】。
  --     正式提交：零成功【硬失败】。R2_F_B_ALREADY_BILLED 是正常业务结果，
  --       允许单个样本失败；但它证明不了 V 的成功输出契约。
  --       「全失败说明样本不适合验证」不等于「要求成功样本会误伤业务」——
  --       这里拦的是部署验收，不是学生生成业务。
  FOR r IN
    SELECT e.fn,
           count(s.*) FILTER (WHERE s.ok)     AS n_ok,
           count(s.*) FILTER (WHERE NOT s.ok) AS n_fail,
           count(s.*)                          AS n_total
    FROM (VALUES ('B'),('V'),('EP')) AS e(fn)
    LEFT JOIN og_sweep s ON s.fn = e.fn AND s.phase='after'
    GROUP BY e.fn ORDER BY e.fn
  LOOP
    RAISE NOTICE 'OG: % 扫描 组合=% 成功=% 失败=%', r.fn, r.n_total, r.n_ok, r.n_fail;
    IF r.n_ok = 0 THEN
      v_incomplete := v_incomplete + 1;
      IF r.n_total = 0 THEN
        RAISE WARNING 'OG_COVERAGE_ABSENT: % 一个组合都没扫到，该函数【完全未被验收】', r.fn;
      ELSE
        RAISE WARNING 'OG_COVERAGE_VACUOUS: % 成功样本为 0，前后比对不构成验收', r.fn;
      END IF;
    END IF;
  END LOOP;

  IF v_incomplete > 0 THEN
    IF current_setting('og.mode',true) = 'commit'
       AND coalesce(current_setting('og.allow_incomplete_coverage',true),'no') <> 'yes' THEN
      RAISE EXCEPTION 'OG_COVERAGE_INSUFFICIENT: % 个被验收函数零成功样本，'
        '正式提交不放行。若已有独立的有效验收证据，请由业务负责人书面确认后'
        '以 -v allow_incomplete_coverage=yes 重跑。', v_incomplete;
    ELSIF current_setting('og.mode',true) = 'commit' THEN
      RAISE WARNING 'OG: 已由 allow_incomplete_coverage=yes 放行，'
        '% 个函数【未经本脚本验收】，须有独立证据支撑', v_incomplete;
    ELSE
      RAISE WARNING 'OG: 排练完成但【验收不完整】——% 个函数零成功样本', v_incomplete;
    END IF;
  END IF;

  -- 非预期数据库错误不得混入「一致失败」而被当成正常。
  -- 允许的业务失败集之外的错误码 ⇒ commit 模式【硬失败】。
  -- allow_incomplete_coverage 只豁免【样本覆盖不足】，【不豁免非预期异常】。
  SELECT count(*) INTO v_bad FROM og_sweep
  WHERE phase='after' AND NOT ok
    AND errcode NOT IN (
      'R2_F_B_CANDIDATES_EMPTY','R2_F_B_ALREADY_BILLED','R2_F_B_TARGET_SETTLEMENT_LOCKED',
      'R2_F_B_STUDENT_NOT_FOUND','R2_F_B_BUSINESS_ENTITY_REQUIRED',
      'R2_F_B_MULTIPLE_PREVIOUS_LOCKED_SETTLEMENTS','R2_F_B_BILLING_AMOUNT_INVALID',
      'R2_F_B_DUPLICATE_CANDIDATE_UUID','R2_F_B_CANDIDATE_CONTRACT_MISMATCH',
      'TUITION_P0E_PREVIEW_INPUT_INVALID','TUITION_P0E_HISTORICAL_CARRY_REQUIRED',
      -- 重发路径上「已存在 active revision」的正当拒绝，与首次生成路径的
      -- R2_F_B_ALREADY_BILLED 完全对应。原先漏了它 —— 这份集合是照 harness
      -- 上见过的错误码列的，而 harness 从未产生过这一条。
      'TUITION_REISSUE_ACTIVE_REVISION_EXISTS');
  IF v_bad > 0 THEN
    IF current_setting('og.mode',true) = 'commit' THEN
      RAISE EXCEPTION 'OG_UNEXPECTED_ERRORS: % 个样本的错误码不在允许的业务失败集内，'
        '正式提交不放行。allow_incomplete_coverage 不豁免本项 —— '
        '它只豁免样本覆盖不足。明细见下方按函数与错误码的分类。', v_bad;
    ELSE
      RAISE WARNING 'OG_UNEXPECTED_ERRORS: % 个样本的错误码不在允许的业务失败集内 —— '
        '排练继续收集，但本次验收【不通过】，见下方明细', v_bad;
    END IF;
  END IF;
END $lc$;

-- 各 effective_status 的实际覆盖数——任一为 0 即该分支未被验证，须在 harness 补造
SELECT payload->'carryover_evidence'->>'settlement_effective_status' AS effective_status,
       count(*) AS combos
FROM og_sweep WHERE phase='after' AND fn='B' AND ok
GROUP BY 1 ORDER BY 2 DESC;

-- 失败样本按函数与错误码分类（不得被笼统吞掉）
SELECT fn, sqlstate, errcode, count(*)
FROM og_sweep WHERE phase='after' AND NOT ok GROUP BY 1,2,3 ORDER BY 4 DESC;

-- -----------------------------------------------------------------------------
-- §6 收尾
-- -----------------------------------------------------------------------------
SELECT (:'mode' = 'commit') AS og_is_commit \gset

\if :og_is_commit
  -- schema cache：pgrst_ddl_watch / pgrst_drop_watch 会自动 NOTIFY，
  -- 此处再显式发一次（有先例、无害）。⚠️ 通知 ≠ 所有实例已刷新，
  -- 重载解析仍须在 HTTP 层单独验证（设计 §5.10(b)）。
  SELECT pg_notify('pgrst','reload schema');
  COMMIT;
  \echo '=== 已 COMMIT。请立即执行 verify_readonly 与 verify_write ==='
\else
  ROLLBACK;
  \echo '=== 排练完成，已 ROLLBACK，生产未改变 ==='
\endif
