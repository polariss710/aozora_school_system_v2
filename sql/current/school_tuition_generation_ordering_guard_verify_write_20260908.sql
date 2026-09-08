-- =============================================================================
-- 学费生成顺序守卫：写路径验收
--
-- 设计   ~/aozora-security-20260827/school-generation-ordering-guard-design-20260908-v14.md
-- 前置   deploy 已 commit，且 verify_readonly 已通过
--
-- 【全程包在一个事务里，末尾无条件 ROLLBACK】。
--   本脚本确实会调用真实 writer 生成账单——那是唯一能证明守卫生效的方式——
--   但没有任何一次写入会被提交。
--
-- ⚠️ 它会对 school_lesson_records / school_student_monthly_settlements 等表
--    取 SHARE 锁（writer 自身的行为），会阻塞并发的生成与结算。
--    **请在无人操作时运行。**
--
-- 【不篡改、不绕 guard】：所有负例都经由合法入口
--   school_generate_student_tuition_bill_atomic 触发，
--   不直接 UPDATE 业务表、不伪造 writer context。
--
-- 用法：
--   psql -v ON_ERROR_STOP=1 -f <本文件>
-- =============================================================================
\set ON_ERROR_STOP on
\echo '=== 顺序守卫：写路径验收（末尾无条件 ROLLBACK）==='

DROP TABLE IF EXISTS vw_result;
CREATE TEMP TABLE vw_result(seq int, item text, verdict text, detail text);

BEGIN;
SET LOCAL statement_timeout = '600s';
SET LOCAL lock_timeout = '15s';

DO $vw$
DECLARE
  v_manifest text;
  v_bill uuid; v_rev uuid; v_income uuid;
  v_evt public.school_student_tuition_generation_ordering_ack_events%rowtype;
  v_snap jsonb;
  v_msg text; v_state text;
  v_n int; v_seq int := 0;
  v_inc_sid uuid; v_inc_m text; v_cmp_sid uuid; v_cmp_m text;
  v_has_inc boolean := false; v_has_cmp boolean := false;
  v_fired boolean;
BEGIN
  -- ---------------------------------------------------------------------------
  -- 选样：从真实数据里挑一个「上月未完成」和一个「上月已完成」的组合。
  --       挑不到就【声明该分支未验证】，不静默跳过。
  --
  --       用 reader 而不是 builder 来选：builder 会对无候选课时的组合抛
  --       R2_F_B_CANDIDATES_EMPTY，在 WHERE 子句里会让整条选样查询失败。
  --       reader 只回答「上月是否完成」，正是为此而生。
  -- ---------------------------------------------------------------------------
  SELECT c.sid, c.m INTO v_inc_sid, v_inc_m FROM (
    SELECT DISTINCT l.student_id AS sid, to_char(l.lesson_date,'YYYY-MM') AS m
    FROM public.school_lesson_records l WHERE l.student_id IS NOT NULL
  ) c
  WHERE NOT EXISTS (SELECT 1 FROM public.school_student_tuition_bills b
                     WHERE b.student_id=c.sid AND b.billing_month=c.m
                       AND b.status <> 'cancelled')
    AND (SELECT r.settlement_effective_complete
         FROM public.school_get_tuition_generation_ordering_state(c.sid,c.m) r
        ) IS FALSE
  LIMIT 1;
  v_has_inc := FOUND;

  SELECT c.sid, c.m INTO v_cmp_sid, v_cmp_m FROM (
    SELECT DISTINCT l.student_id AS sid, to_char(l.lesson_date,'YYYY-MM') AS m
    FROM public.school_lesson_records l WHERE l.student_id IS NOT NULL
  ) c
  WHERE NOT EXISTS (SELECT 1 FROM public.school_student_tuition_bills b
                     WHERE b.student_id=c.sid AND b.billing_month=c.m
                       AND b.status <> 'cancelled')
    AND (SELECT r.settlement_effective_complete
         FROM public.school_get_tuition_generation_ordering_state(c.sid,c.m) r
        ) IS TRUE
  LIMIT 1;
  v_has_cmp := FOUND;

  -- ---------------------------------------------------------------------------
  -- ① 上月未完成 + 不传理由 ⇒ 必须抛 TUITION_PREVIOUS_SETTLEMENT_INCOMPLETE
  -- ---------------------------------------------------------------------------
  v_seq := v_seq + 1;
  IF NOT v_has_inc THEN
    INSERT INTO vw_result VALUES(v_seq,'① 未完成+无理由 ⇒ 拦截','未验证',
      '找不到「上月未完成且本月尚无账单」的组合');
  ELSE
    SELECT s.generation_manifest_sha256 INTO v_manifest
    FROM public.school_build_student_tuition_generation_snapshot(
      v_inc_sid, v_inc_m, 0.042) s;
    -- 【注意】判定用标志位，不在 BEGIN 块内 RAISE：
    -- 那样会被本块自己的 EXCEPTION 处理器捕获，得到误导性的错误信息。
    v_fired := false; v_msg := NULL;
    BEGIN
      PERFORM public.school_generate_student_tuition_bill_atomic(
        v_inc_sid, v_inc_m, 0.042, v_manifest, NULL);
    EXCEPTION WHEN OTHERS THEN
      v_fired := true;
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    END;
    IF NOT v_fired THEN
      INSERT INTO vw_result VALUES(v_seq,'① 未完成+无理由 ⇒ 拦截','失败',
        '未抛异常，账单被生成 —— 守卫未生效');
      RAISE EXCEPTION 'VW_GUARD_DID_NOT_FIRE';
    ELSIF v_msg LIKE 'TUITION_PREVIOUS_SETTLEMENT_INCOMPLETE%' THEN
      INSERT INTO vw_result VALUES(v_seq,'① 未完成+无理由 ⇒ 拦截','通过',left(v_msg,90));
    ELSE
      INSERT INTO vw_result VALUES(v_seq,'① 未完成+无理由 ⇒ 拦截','失败',
        '抛出的不是守卫异常: '||left(v_msg,80));
      RAISE EXCEPTION 'VW_WRONG_EXCEPTION: %', v_msg;
    END IF;
  END IF;

  -- ---------------------------------------------------------------------------
  -- ② 上月未完成 + 传理由 ⇒ 放行，并写下一条内容正确的 ack 事件
  -- ---------------------------------------------------------------------------
  v_seq := v_seq + 1;
  IF NOT v_has_inc THEN
    INSERT INTO vw_result VALUES(v_seq,'② 未完成+有理由 ⇒ 放行并留痕','未验证','同上');
  ELSE
    SELECT s.generation_manifest_sha256 INTO v_manifest
    FROM public.school_build_student_tuition_generation_snapshot(
      v_inc_sid, v_inc_m, 0.042) s;
    SELECT g.tuition_bill_id, g.income_record_id INTO v_bill, v_income
    FROM public.school_generate_student_tuition_bill_atomic(
      v_inc_sid, v_inc_m, 0.042, v_manifest, NULL,
      'verify_write 验收样本：上月确无需结算') g;

    SELECT * INTO v_evt FROM public.school_student_tuition_generation_ordering_ack_events
     WHERE tuition_bill_id = v_bill;
    IF NOT FOUND THEN
      INSERT INTO vw_result VALUES(v_seq,'② 未完成+有理由 ⇒ 放行并留痕','失败','放行了但没有 ack 事件');
      RAISE EXCEPTION 'VW_ACK_NOT_WRITTEN';
    END IF;

    IF v_evt.income_record_id IS DISTINCT FROM v_income THEN
      RAISE EXCEPTION 'VW_ACK_INCOME_MISMATCH';
    END IF;
    IF (v_evt.precondition_evidence->>'settlement_effective_complete')::boolean IS NOT FALSE THEN
      RAISE EXCEPTION 'VW_ACK_PRECONDITION_WRONG';
    END IF;
    -- 源键名是 settlement_month；若按同名键读会得 NULL，这条就是那个错的探针
    IF nullif(btrim(coalesce(v_evt.precondition_evidence->>'previous_settlement_month','')),'') IS NULL THEN
      RAISE EXCEPTION 'VW_ACK_MONTH_NULL: 键名映射错误';
    END IF;
    IF v_evt.operator_authority_source NOT IN
       ('request_jwt_claim_sub','tuition_operator_authority','fallback_current_user','fallback_literal') THEN
      RAISE EXCEPTION 'VW_ACK_SOURCE_INVALID: %', v_evt.operator_authority_source;
    END IF;
    IF v_evt.reason <> 'verify_write 验收样本：上月确无需结算' THEN
      RAISE EXCEPTION 'VW_ACK_REASON_ALTERED';
    END IF;

    INSERT INTO vw_result VALUES(v_seq,'② 未完成+有理由 ⇒ 放行并留痕','通过',
      'bill='||left(v_bill::text,8)||' 身份='||v_evt.operator_authority
      ||'('||v_evt.operator_authority_source||')');
    v_rev := v_evt.generation_revision_id;
  END IF;

  -- ---------------------------------------------------------------------------
  -- ③ 上月【已完成】+ 不传理由 ⇒ 必须【不被拦】，且不产生 ack 事件
  --    这一条针对 2026-09-07 上午那次误判：只查 locked 行会把
  --    historical_zero_carry_complete 的学生当成「从未结算」。
  -- ---------------------------------------------------------------------------
  v_seq := v_seq + 1;
  IF NOT v_has_cmp THEN
    INSERT INTO vw_result VALUES(v_seq,'③ 已完成+无理由 ⇒ 不误拦','未验证',
      '找不到「上月已完成且本月尚无账单」的组合 —— 【误报分支未被验收】');
  ELSE
    SELECT count(*) INTO v_n FROM public.school_student_tuition_generation_ordering_ack_events;
    SELECT s.generation_manifest_sha256 INTO v_manifest
    FROM public.school_build_student_tuition_generation_snapshot(
      v_cmp_sid, v_cmp_m, 0.042) s;
    BEGIN
      SELECT g.tuition_bill_id INTO v_bill
      FROM public.school_generate_student_tuition_bill_atomic(
        v_cmp_sid, v_cmp_m, 0.042, v_manifest, NULL) g;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      IF v_msg LIKE 'TUITION_PREVIOUS_SETTLEMENT_INCOMPLETE%' THEN
        INSERT INTO vw_result VALUES(v_seq,'③ 已完成+无理由 ⇒ 不误拦','失败',
          '上月已完成却被拦 —— 误报');
        RAISE EXCEPTION 'VW_FALSE_ALARM: %', v_msg;
      END IF;
      INSERT INTO vw_result VALUES(v_seq,'③ 已完成+无理由 ⇒ 不误拦','未验证',
        '因其它业务原因失败（非守卫）: '||left(v_msg,60));
      v_bill := NULL;
    END;
    IF v_bill IS NOT NULL THEN
      IF (SELECT count(*) FROM public.school_student_tuition_generation_ordering_ack_events) <> v_n THEN
        RAISE EXCEPTION 'VW_SPURIOUS_ACK: 上月已完成却写了 ack 事件';
      END IF;
      INSERT INTO vw_result VALUES(v_seq,'③ 已完成+无理由 ⇒ 不误拦','通过',
        'bill='||left(v_bill::text,8)||'，未产生 ack 事件');
    END IF;
  END IF;

  -- ---------------------------------------------------------------------------
  -- ④ ack 事件不可变：UPDATE / DELETE / TRUNCATE 必须全部被拒
  -- ---------------------------------------------------------------------------
  v_seq := v_seq + 1;
  IF v_rev IS NULL THEN
    INSERT INTO vw_result VALUES(v_seq,'④ ack 不可变','未验证','本轮未产生 ack 事件');
  ELSE
    v_fired := false; v_msg := NULL;
    BEGIN
      UPDATE public.school_student_tuition_generation_ordering_ack_events
         SET reason='篡改' WHERE generation_revision_id=v_rev;
    EXCEPTION WHEN OTHERS THEN
      v_fired := true; GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    END;
    IF NOT v_fired THEN RAISE EXCEPTION 'VW_ACK_UPDATE_ALLOWED'; END IF;
    IF v_msg <> 'TUITION_ORDERING_ACK_EVENT_IMMUTABLE' THEN
      RAISE EXCEPTION 'VW_ACK_UPDATE_WRONG_ERROR: %', v_msg; END IF;

    v_fired := false; v_msg := NULL;
    BEGIN
      DELETE FROM public.school_student_tuition_generation_ordering_ack_events
       WHERE generation_revision_id=v_rev;
    EXCEPTION WHEN OTHERS THEN
      v_fired := true; GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    END;
    IF NOT v_fired THEN RAISE EXCEPTION 'VW_ACK_DELETE_ALLOWED'; END IF;
    IF v_msg NOT IN ('TUITION_ORDERING_ACK_EVENT_IMMUTABLE',
                     'TUITION_ORDERING_ACK_EVENT_DELETE_FORBIDDEN') THEN
      RAISE EXCEPTION 'VW_ACK_DELETE_WRONG_ERROR: %', v_msg; END IF;
    INSERT INTO vw_result VALUES(v_seq,'④ ack 不可变','通过','UPDATE / DELETE 均被拒');
  END IF;

  -- ---------------------------------------------------------------------------
  -- ⑤ 同一 revision 第二条 ack ⇒ UNIQUE 兜底
  -- ---------------------------------------------------------------------------
  v_seq := v_seq + 1;
  IF v_rev IS NULL THEN
    INSERT INTO vw_result VALUES(v_seq,'⑤ 一 revision 一 ack','未验证','本轮未产生 ack 事件');
  ELSE
    v_fired := false;
    BEGIN
      INSERT INTO public.school_student_tuition_generation_ordering_ack_events
      SELECT gen_random_uuid(), generation_identity_id, generation_revision_id,
             tuition_bill_id, income_record_id, expected_generation_manifest_sha256,
             reason, operator_authority, operator_authority_source,
             precondition_evidence, result_evidence, created_at
      FROM public.school_student_tuition_generation_ordering_ack_events
      WHERE generation_revision_id = v_rev;
    EXCEPTION WHEN unique_violation THEN v_fired := true;
    END;
    IF NOT v_fired THEN RAISE EXCEPTION 'VW_DUPLICATE_ACK_ALLOWED'; END IF;
    INSERT INTO vw_result VALUES(v_seq,'⑤ 一 revision 一 ack','通过','UNIQUE 拒绝重复');
  END IF;
END $vw$;

\echo ''
\echo '--- 写路径验收结论 ---'
SELECT seq, item, verdict, detail FROM vw_result ORDER BY seq;

\echo ''
\echo '--- 「未验证」计数（>0 表示验收不完整）---'
SELECT count(*) AS 未验证项 FROM vw_result WHERE verdict = '未验证';

DO $vw$
DECLARE v_fail int; v_skip int;
BEGIN
  SELECT count(*) FILTER (WHERE verdict='失败'), count(*) FILTER (WHERE verdict='未验证')
    INTO v_fail, v_skip FROM vw_result;
  IF v_fail > 0 THEN RAISE EXCEPTION 'VW_FAILED: % 项失败', v_fail; END IF;
  IF v_skip > 0 THEN
    RAISE WARNING 'VW_INCOMPLETE: % 项未验证 —— 本次写路径验收【不完整】，'
      '缺的分支须另行取证或在 harness 补造样本', v_skip;
  END IF;
END $vw$;

ROLLBACK;
DROP TABLE IF EXISTS vw_result;
\echo ''
\echo '=== 写路径验收结束。事务已 ROLLBACK —— 本次生成的账单、收入、ack 事件全部未提交。 ==='
