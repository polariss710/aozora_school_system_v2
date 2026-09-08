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
-- 【白名单】：样本【不自动挑选】。必须由业务负责人逐个指定学生与月份，
--   脚本会先核对该组合确实处于预期状态，不符即拒绝执行。
--   回滚测试也须使用白名单数据——「末尾回滚」不等于「没有写过真实业务数据」。
--
-- 【不篡改、不绕 guard】：生成一律经合法入口
--   school_generate_student_tuition_bill_atomic 触发，
--   不直接 UPDATE 业务表、不伪造 writer context、不禁用任何触发器。
--   ④⑤ 对【本次新增的 ack 表】做直接 DML，仅用于测它自己的不可变触发器与
--   UNIQUE 约束——经合法路径无法为同一 revision 产生第二条 ack，那正是被测的性质。
--
-- ⚠️ writer 会对 school_lesson_records / school_student_monthly_settlements 等
--    取 SHARE 锁，与写入常用的 ROW EXCLUSIVE 冲突。**请在无人操作时运行。**
--
-- 用法：
--   psql -v ON_ERROR_STOP=1 \
--        -v og_student=<uuid> \
--        -v og_month_incomplete=<YYYY-MM> \
--        [-v og_month_complete=<YYYY-MM>] \
--        -f <本文件>
--
--   og_month_complete 省略时，③（误报分支）报「未验证」并使整轮标为不完整。
-- =============================================================================
\set ON_ERROR_STOP on

\if :{?og_student}
\else
  \echo '⛔ 缺少 -v og_student=<uuid>。样本必须白名单指定，不自动挑选。'
  \quit
\endif
\if :{?og_month_incomplete}
\else
  \echo '⛔ 缺少 -v og_month_incomplete=<YYYY-MM>。'
  \quit
\endif
\if :{?og_month_complete}
\else
  \set og_month_complete ''
\endif

\echo '=== 顺序守卫：写路径验收（末尾无条件 ROLLBACK）==='
\echo '    学生 =' :og_student
\echo '    未完成月 =' :og_month_incomplete '  已完成月 =' :og_month_complete

-- 【必须限定 pg_temp】：未限定的 DROP 会命中搜索路径上的同名【永久】表，
-- 而它在 BEGIN 之前执行、自动提交，末尾 ROLLBACK 保护不了。
DROP TABLE IF EXISTS pg_temp.vw_result;
CREATE TEMP TABLE vw_result(seq int, item text, verdict text, detail text);

BEGIN;
SET LOCAL statement_timeout = '600s';
SET LOCAL lock_timeout = '15s';

SELECT set_config('og.student', :'og_student', true),
       set_config('og.month_incomplete', :'og_month_incomplete', true),
       set_config('og.month_complete', :'og_month_complete', true);

DO $vw$
DECLARE
  v_sid uuid := current_setting('og.student')::uuid;
  v_m_inc text := nullif(btrim(current_setting('og.month_incomplete')),'');
  v_m_cmp text := nullif(btrim(current_setting('og.month_complete')),'');
  v_entity uuid;
  v_manifest text;
  v_bill uuid; v_rev uuid; v_income uuid;
  v_evt public.school_student_tuition_generation_ordering_ack_events%rowtype;
  v_msg text; v_constraint text; v_path text;
  v_n int; v_seq int := 0;
  v_fired boolean;
  -- 生成链上【允许】的业务失败集。此集之外的异常一律判失败，
  -- 不得降级为「未验证」——那会把程序缺陷放行。
  c_allowed text[] := ARRAY[
    'R2_F_B_CANDIDATES_EMPTY','R2_F_B_TARGET_SETTLEMENT_LOCKED',
    'R2_F_B_PLANNED_UUID_ALREADY_FROZEN','R2_F_B_STALE_GENERATION_MANIFEST',
    'R2_F_B_ALREADY_BILLED','R2_F_B_IDEMPOTENCY_CONFLICT_OR_INCOMPLETE'];
BEGIN
  SELECT business_entity_id INTO STRICT v_entity
    FROM public.school_students WHERE id = v_sid AND app_type = 'school';

  -- ---------------------------------------------------------------------------
  -- 白名单核对：指定的组合必须确实处于预期状态，否则测的就不是那件事
  -- ---------------------------------------------------------------------------
  IF (SELECT settlement_effective_complete
        FROM public.school_get_tuition_generation_ordering_state(v_sid, v_m_inc)) IS NOT FALSE THEN
    RAISE EXCEPTION 'VW_SAMPLE_NOT_INCOMPLETE: % 的 % 上月并非「未完成」，白名单样本不符',
      v_sid, v_m_inc;
  END IF;
  IF v_m_cmp IS NOT NULL
     AND (SELECT settlement_effective_complete
            FROM public.school_get_tuition_generation_ordering_state(v_sid, v_m_cmp)) IS NOT TRUE THEN
    RAISE EXCEPTION 'VW_SAMPLE_NOT_COMPLETE: % 的 % 上月并非「已完成」，白名单样本不符',
      v_sid, v_m_cmp;
  END IF;

  -- 本次将走哪条路径：无 generation identity ⇒ F（首次生成）；否则 ⇒ N（重发）。
  -- 只排除「未取消账单」不足以断定路径——已取消账单的组合仍有 identity，会走 N。
  SELECT CASE WHEN EXISTS (
           SELECT 1 FROM public.school_student_tuition_generation_identities g
            WHERE g.student_id=v_sid AND g.business_entity_id=v_entity
              AND g.billing_month = to_date(v_m_inc||'-01','YYYY-MM-DD'))
         THEN 'N' ELSE 'F' END INTO v_path;

  -- ---------------------------------------------------------------------------
  -- ① 上月未完成 + 不传理由 ⇒ 必须抛 TUITION_PREVIOUS_SETTLEMENT_INCOMPLETE
  -- ---------------------------------------------------------------------------
  v_seq := v_seq + 1;
  SELECT s.generation_manifest_sha256 INTO v_manifest
  FROM public.school_build_student_tuition_generation_snapshot(v_sid, v_m_inc, 0.042) s;

  -- 判定用标志位：在 BEGIN 块内 RAISE 会被本块自己的 EXCEPTION 处理器捕获
  v_fired := false; v_msg := NULL;
  BEGIN
    PERFORM public.school_generate_student_tuition_bill_atomic(
      v_sid, v_m_inc, 0.042, v_manifest, NULL);
  EXCEPTION WHEN OTHERS THEN
    v_fired := true; GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  END;
  IF NOT v_fired THEN
    INSERT INTO vw_result VALUES(v_seq,'① 未完成+无理由 ⇒ 拦截','失败','未抛异常 —— 守卫未生效');
    RAISE EXCEPTION 'VW_GUARD_DID_NOT_FIRE';
  ELSIF v_msg NOT LIKE 'TUITION_PREVIOUS_SETTLEMENT_INCOMPLETE%' THEN
    INSERT INTO vw_result VALUES(v_seq,'① 未完成+无理由 ⇒ 拦截','失败','抛出的不是守卫异常: '||left(v_msg,70));
    RAISE EXCEPTION 'VW_WRONG_EXCEPTION: %', v_msg;
  END IF;
  INSERT INTO vw_result VALUES(v_seq,'① 未完成+无理由 ⇒ 拦截','通过',
    '路径='||v_path||'  '||left(v_msg,70));

  -- ---------------------------------------------------------------------------
  -- ② 上月未完成 + 传理由 ⇒ 放行，并写下一条内容正确的 ack 事件
  -- ---------------------------------------------------------------------------
  v_seq := v_seq + 1;
  SELECT s.generation_manifest_sha256 INTO v_manifest
  FROM public.school_build_student_tuition_generation_snapshot(v_sid, v_m_inc, 0.042) s;
  SELECT g.tuition_bill_id, g.income_record_id INTO v_bill, v_income
  FROM public.school_generate_student_tuition_bill_atomic(
    v_sid, v_m_inc, 0.042, v_manifest, NULL,
    'verify_write 验收样本：上月确无需结算') g;

  SELECT * INTO v_evt FROM public.school_student_tuition_generation_ordering_ack_events
   WHERE tuition_bill_id = v_bill;
  IF NOT FOUND THEN
    INSERT INTO vw_result VALUES(v_seq,'② 未完成+有理由 ⇒ 放行并留痕','失败','放行了但没有 ack 事件');
    RAISE EXCEPTION 'VW_ACK_NOT_WRITTEN';
  END IF;
  IF v_evt.income_record_id IS DISTINCT FROM v_income THEN
    RAISE EXCEPTION 'VW_ACK_INCOME_MISMATCH'; END IF;
  IF (v_evt.precondition_evidence->>'settlement_effective_complete')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'VW_ACK_PRECONDITION_WRONG'; END IF;
  -- 月份【非空还不够】，必须等于账单冻结的上月：记错月份同样通不过
  IF v_evt.precondition_evidence->>'previous_settlement_month' IS DISTINCT FROM
     (SELECT b.previous_settlement_month FROM public.school_student_tuition_bills b WHERE b.id=v_bill) THEN
    RAISE EXCEPTION 'VW_ACK_MONTH_MISMATCH'; END IF;
  IF v_evt.expected_generation_manifest_sha256 IS DISTINCT FROM v_manifest THEN
    RAISE EXCEPTION 'VW_ACK_MANIFEST_MISMATCH'; END IF;
  IF v_evt.operator_authority_source NOT IN
     ('request_jwt_claim_sub','tuition_operator_authority','fallback_current_user','fallback_literal') THEN
    RAISE EXCEPTION 'VW_ACK_SOURCE_INVALID: %', v_evt.operator_authority_source; END IF;
  IF v_evt.reason <> 'verify_write 验收样本：上月确无需结算' THEN
    RAISE EXCEPTION 'VW_ACK_REASON_ALTERED'; END IF;
  v_rev := v_evt.generation_revision_id;

  INSERT INTO vw_result VALUES(v_seq,'② 未完成+有理由 ⇒ 放行并留痕','通过',
    '路径='||v_path||'  bill='||left(v_bill::text,8)||'  身份='||v_evt.operator_authority
    ||'('||v_evt.operator_authority_source||')');

  -- ---------------------------------------------------------------------------
  -- ③ 上月【已完成】+ 不传理由 ⇒ 必须【不被拦】，且不产生 ack 事件
  --    针对 2026-09-07 上午那次误判：只查 locked 行会把
  --    historical_zero_carry_complete 的学生当成「从未结算」。
  -- ---------------------------------------------------------------------------
  v_seq := v_seq + 1;
  IF v_m_cmp IS NULL THEN
    INSERT INTO vw_result VALUES(v_seq,'③ 已完成+无理由 ⇒ 不误拦','未验证',
      '未指定 og_month_complete —— 【误报分支未被验收】');
  ELSE
    SELECT count(*) INTO v_n FROM public.school_student_tuition_generation_ordering_ack_events;
    SELECT s.generation_manifest_sha256 INTO v_manifest
    FROM public.school_build_student_tuition_generation_snapshot(v_sid, v_m_cmp, 0.042) s;
    v_fired := false; v_msg := NULL; v_bill := NULL;
    BEGIN
      SELECT g.tuition_bill_id INTO v_bill
      FROM public.school_generate_student_tuition_bill_atomic(
        v_sid, v_m_cmp, 0.042, v_manifest, NULL) g;
    EXCEPTION WHEN OTHERS THEN
      v_fired := true; GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    END;
    IF v_fired AND v_msg LIKE 'TUITION_PREVIOUS_SETTLEMENT_INCOMPLETE%' THEN
      INSERT INTO vw_result VALUES(v_seq,'③ 已完成+无理由 ⇒ 不误拦','失败','上月已完成却被拦 —— 误报');
      RAISE EXCEPTION 'VW_FALSE_ALARM: %', v_msg;
    ELSIF v_fired AND split_part(v_msg,':',1) <> ALL(c_allowed) THEN
      -- 【非预期异常判失败】，不降级为「未验证」
      INSERT INTO vw_result VALUES(v_seq,'③ 已完成+无理由 ⇒ 不误拦','失败','非预期异常: '||left(v_msg,60));
      RAISE EXCEPTION 'VW_UNEXPECTED_EXCEPTION: %', v_msg;
    ELSIF v_fired THEN
      INSERT INTO vw_result VALUES(v_seq,'③ 已完成+无理由 ⇒ 不误拦','未验证',
        '样本因允许的业务原因失败（非守卫）: '||split_part(v_msg,':',1));
    ELSE
      IF (SELECT count(*) FROM public.school_student_tuition_generation_ordering_ack_events) <> v_n THEN
        RAISE EXCEPTION 'VW_SPURIOUS_ACK: 上月已完成却写了 ack 事件'; END IF;
      INSERT INTO vw_result VALUES(v_seq,'③ 已完成+无理由 ⇒ 不误拦','通过',
        'bill='||left(v_bill::text,8)||'，未产生 ack 事件');
    END IF;
  END IF;

  -- ---------------------------------------------------------------------------
  -- ④ ack 不可变：UPDATE / DELETE / TRUNCATE 三个触发器逐个验
  -- ---------------------------------------------------------------------------
  v_seq := v_seq + 1;
  v_fired := false; v_msg := NULL;
  BEGIN
    UPDATE public.school_student_tuition_generation_ordering_ack_events
       SET reason='篡改' WHERE generation_revision_id=v_rev;
  EXCEPTION WHEN OTHERS THEN v_fired := true; GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  END;
  IF NOT v_fired THEN RAISE EXCEPTION 'VW_ACK_UPDATE_ALLOWED'; END IF;
  IF v_msg <> 'TUITION_ORDERING_ACK_EVENT_IMMUTABLE' THEN
    RAISE EXCEPTION 'VW_ACK_UPDATE_WRONG_ERROR: %', v_msg; END IF;

  v_fired := false; v_msg := NULL;
  BEGIN
    DELETE FROM public.school_student_tuition_generation_ordering_ack_events
     WHERE generation_revision_id=v_rev;
  EXCEPTION WHEN OTHERS THEN v_fired := true; GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  END;
  IF NOT v_fired THEN RAISE EXCEPTION 'VW_ACK_DELETE_ALLOWED'; END IF;
  IF v_msg NOT IN ('TUITION_ORDERING_ACK_EVENT_IMMUTABLE',
                   'TUITION_ORDERING_ACK_EVENT_DELETE_FORBIDDEN') THEN
    RAISE EXCEPTION 'VW_ACK_DELETE_WRONG_ERROR: %', v_msg; END IF;

  v_fired := false; v_msg := NULL;
  BEGIN
    EXECUTE 'TRUNCATE public.school_student_tuition_generation_ordering_ack_events';
  EXCEPTION WHEN OTHERS THEN v_fired := true; GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  END;
  IF NOT v_fired THEN RAISE EXCEPTION 'VW_ACK_TRUNCATE_ALLOWED'; END IF;
  IF v_msg <> 'TUITION_ORDERING_ACK_EVENT_DELETE_FORBIDDEN' THEN
    RAISE EXCEPTION 'VW_ACK_TRUNCATE_WRONG_ERROR: %', v_msg; END IF;

  INSERT INTO vw_result VALUES(v_seq,'④ ack 不可变（UPDATE/DELETE/TRUNCATE）','通过','三者均被拒');

  -- ---------------------------------------------------------------------------
  -- ⑤ 同一 revision 第二条 ack ⇒ 必须由【revision 的 UNIQUE】拒绝
  --    复制行会同时撞上 revision / bill / income 三个 UNIQUE，
  --    只捕获任意 unique_violation 证明不了 revision 那条还在 ——
  --    故断言实际触发的约束名。
  -- ---------------------------------------------------------------------------
  v_seq := v_seq + 1;
  v_fired := false; v_constraint := NULL;
  BEGIN
    INSERT INTO public.school_student_tuition_generation_ordering_ack_events
    SELECT gen_random_uuid(), generation_identity_id, generation_revision_id,
           tuition_bill_id, income_record_id, expected_generation_manifest_sha256,
           reason, operator_authority, operator_authority_source,
           precondition_evidence, result_evidence, created_at
    FROM public.school_student_tuition_generation_ordering_ack_events
    WHERE generation_revision_id = v_rev;
  EXCEPTION WHEN unique_violation THEN
    v_fired := true; GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
  END;
  IF NOT v_fired THEN RAISE EXCEPTION 'VW_DUPLICATE_ACK_ALLOWED'; END IF;
  IF v_constraint IS DISTINCT FROM 'tuition_ordering_ack_revision_key' THEN
    RAISE EXCEPTION 'VW_WRONG_CONSTRAINT: 触发的是 %，不是 revision 的 UNIQUE  '
      '← 无法证明「一 revision 一 ack」仍然成立', v_constraint;
  END IF;
  INSERT INTO vw_result VALUES(v_seq,'⑤ 一 revision 一 ack','通过',
    '由 '||v_constraint||' 拒绝');
END $vw$;

\echo ''
\echo '--- 写路径验收结论 ---'
SELECT seq, item, verdict, detail FROM vw_result ORDER BY seq;

DO $vw$
DECLARE v_fail int; v_skip int;
BEGIN
  SELECT count(*) FILTER (WHERE verdict='失败'), count(*) FILTER (WHERE verdict='未验证')
    INTO v_fail, v_skip FROM vw_result;
  IF v_fail > 0 THEN RAISE EXCEPTION 'VW_FAILED: % 项失败', v_fail; END IF;
  IF v_skip > 0 THEN
    RAISE WARNING 'VW_INCOMPLETE: % 项未验证 —— 本次写路径验收【不完整】。'
      '退出码为 0 不代表必测项已覆盖，缺的分支须另行取证。', v_skip;
  END IF;
END $vw$;

ROLLBACK;
DROP TABLE IF EXISTS pg_temp.vw_result;
\echo ''
\echo '=== 写路径验收结束。事务已 ROLLBACK —— 本次生成的账单、收入、ack 事件全部未提交。 ==='
\echo '⚠️ 本脚本只覆盖它实际走到的那条生成路径（结论中的「路径=」）。'
\echo '   F 与 N 两条路径须分别取得样本各跑一次。'
