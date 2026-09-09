-- =============================================================================
-- 学费生成顺序守卫：回滚
--
-- 逐字节还原五个函数到部署前的生产 canonical 定义，
-- 并还原 ACL（含【显式 REVOKE】）、proconfig、COMMENT，
-- 然后删除本次新增的 reader / 触发器 / 守卫函数 / ack 事件表。
--
-- ⛔ 硬停止：若 ack 事件表【已有行】，本脚本拒绝执行。
--    DROP 会销毁审计事实，那不是无损回滚。
--    须先把事件导出到 ~/aozora-security-20260827/ 并经业务负责人确认，
--    再以 -v allow_ack_loss=yes 重跑。
--
-- 用法：
--   psql -v ON_ERROR_STOP=1 -f <本文件>
--   psql -v ON_ERROR_STOP=1 -v allow_ack_loss=yes -f <本文件>   （已导出后）
-- =============================================================================
\set ON_ERROR_STOP on
\if :{?allow_ack_loss}
\else
  \set allow_ack_loss 'no'
\endif

-- 显式 READ COMMITTED：§2 取锁后的 COUNT 必须能看到等锁期间提交的 ack。
-- 若沿用会话默认而它是 REPEATABLE READ，§1 建立的旧快照会看不到，
-- 审计事实保护就失效了。不能把结论建立在会话默认值上。
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET LOCAL statement_timeout = '600s';
SET LOCAL lock_timeout = '15s';

-- -----------------------------------------------------------------------------
-- §1 前置断言：当前必须是本次部署的结果，否则不是「回滚本次改动」
-- -----------------------------------------------------------------------------
DO $lc$
DECLARE r record; v_oid oid; v_md5 text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('B','public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)','c456d247f804058e8ae29ef4ba419599','{postgres=X/postgres,service_role=X/postgres}','Phase B3: existing tuition facts are governed by lesson, settlement, bill, income, immutable and Gate contracts; frozen legacy student status is not an eligibility authority.'),
    ('G','public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text,text)','40ef9ec344623bb7c02bf8aea670ad52','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','R2-F-B authoritative atomic tuition writer. The public wrapper is R0-gated; clients submit no amounts or candidate details.'),
    ('C','public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text,text)','dad1d0512d44114aed0d9c2a3b61480e','{postgres=X/postgres}','R2-F-C owner-only atomic tuition core. New generation holds fixed-order SHARE table locks on lesson and settlement evidence tables until transaction end; public wrapper remains R0 blocked.'),
    ('F','public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text,text)','8b9b4fd5079a2794aa15c223bbbf9ffc','{postgres=X/postgres}',NULL),
    ('N','public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text,text)','06262763ce6c223e1b271e2be005fdbb','{postgres=X/postgres}',NULL)
  ) AS t(code,sig,md5,acl,cmt) LOOP
    v_oid := to_regprocedure(r.sig);
    IF v_oid IS NULL THEN
      RAISE EXCEPTION 'OGR_NOT_DEPLOYED: % 的新签名不存在，当前不是本次部署的状态', r.code;
    END IF;
    SELECT md5(pg_get_functiondef(v_oid)) INTO v_md5 FROM pg_proc WHERE oid=v_oid;
    IF v_md5 <> r.md5 THEN
      RAISE EXCEPTION 'OGR_UNEXPECTED_STATE: % md5=%  ← 生产已被本次部署之外的改动修改', r.code, v_md5;
    END IF;
  END LOOP;

  -- ack 表必须存在：§2 的 \gset 会直接引用它，缺表则本脚本不适用
  IF to_regclass('public.school_student_tuition_generation_ordering_ack_events') IS NULL THEN
    RAISE EXCEPTION 'OGR_ACK_TABLE_MISSING: 部署不完整，本回滚脚本不适用';
  END IF;
  IF to_regprocedure('public.school_get_tuition_generation_ordering_state(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'OGR_READER_MISSING: 部署不完整，本回滚脚本不适用';
  END IF;
END $lc$;

-- -----------------------------------------------------------------------------
-- §2 审计事实保护
--     已有 ack 事件时 DROP 表会销毁审计事实 —— 那不是无损回滚。
--
--     ⚠️ COUNT 与 DROP 之间若无排他保护，存在并发窗口：
--        ① 本事务 COUNT 得 0 → ② 另一事务提交账单与 ack → ③ 本事务 DROP。
--        即使 allow_ack_loss=no，也会删掉检查之后新增的审计事实。
--        DROP 最终取得的锁【不会追溯保护先前的 COUNT】。
--     故先取 ACCESS EXCLUSIVE 锁并持有到事务结束，再 COUNT。
-- -----------------------------------------------------------------------------
LOCK TABLE public.school_student_tuition_generation_ordering_ack_events IN ACCESS EXCLUSIVE MODE;

SELECT count(*) AS og_ack_rows FROM public.school_student_tuition_generation_ordering_ack_events \gset
SELECT (:og_ack_rows > 0 AND :'allow_ack_loss' <> 'yes') AS og_blocked \gset
\if :og_blocked
  \echo '⛔ ack 事件表有' :og_ack_rows '条记录。DROP 会销毁审计事实。'
  \echo '   请先导出并经业务负责人确认，再以 -v allow_ack_loss=yes 重跑。'
  \echo '   导出： \copy (select * from public.school_student_tuition_generation_ordering_ack_events) to ~/aozora-security-20260827/ack-events-backup.csv csv header'
  ROLLBACK;
  \quit
\endif

-- -----------------------------------------------------------------------------
-- §3 还原五个函数到部署前的 canonical 定义
-- -----------------------------------------------------------------------------
-- ── B：签名未变，直接 REPLACE 回基线 ──
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
$function$
;

-- ── G ──
DROP FUNCTION IF EXISTS public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text,text);
CREATE OR REPLACE FUNCTION public.school_generate_student_tuition_bill_atomic(p_student_id uuid, p_billing_month text, p_billing_exchange_rate numeric, p_expected_generation_manifest_sha256 text, p_note text DEFAULT NULL::text)
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
    p_expected_generation_manifest_sha256,p_note,NULL
  );
END
$function$
;
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text) TO authenticated, service_role;
COMMENT ON FUNCTION public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text) IS 'R2-F-B authoritative atomic tuition writer. The public wrapper is R0-gated; clients submit no amounts or candidate details.';

-- ── C ──
DROP FUNCTION IF EXISTS public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text,text);
CREATE OR REPLACE FUNCTION public.school_generate_student_tuition_bill_atomic_core(p_student_id uuid, p_billing_month text, p_billing_exchange_rate numeric, p_expected_generation_manifest_sha256 text, p_note text DEFAULT NULL::text, p_test_fail_after_step text DEFAULT NULL::text)
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
      p_student_id,p_billing_month,p_billing_exchange_rate,p_expected_generation_manifest_sha256,p_note,p_test_fail_after_step);
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
      'service_role_v2_operations_v1',now(),null,null);
    perform public.school_validate_tuition_identity_for_bill(v_result.tuition_bill_id);
    perform public.school_validate_tuition_bill_income_for_bill(v_result.tuition_bill_id);
    perform public.school_validate_tuition_bill_lessons_for_bill(v_result.tuition_bill_id);
    
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
  return query select * from public.school_generate_student_tuition_next_revision_core(
    v_generation.id,v_previous.id,p_student_id,p_billing_month,p_billing_exchange_rate,
    p_expected_generation_manifest_sha256,p_note,p_test_fail_after_step);
end;
$function$
;
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text) FROM service_role;   -- 阻断默认授权回流
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text) FROM authenticated;
COMMENT ON FUNCTION public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text) IS 'R2-F-C owner-only atomic tuition core. New generation holds fixed-order SHARE table locks on lesson and settlement evidence tables until transaction end; public wrapper remains R0 blocked.';

-- ── F ──
DROP FUNCTION IF EXISTS public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text,text);
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
$function$
;
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text) FROM service_role;   -- 阻断默认授权回流
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text) FROM authenticated;
-- F 基线 COMMENT 为 SQL NULL ⇒ 不得添加注释

-- ── N ──
DROP FUNCTION IF EXISTS public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text,text);
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
$function$
;
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text) FROM service_role;   -- 阻断默认授权回流
REVOKE ALL ON FUNCTION public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text) FROM authenticated;
-- N 基线 COMMENT 为 SQL NULL ⇒ 不得添加注释

-- -----------------------------------------------------------------------------
-- §4 删除本次新增的对象
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.school_get_tuition_generation_ordering_state(uuid,text);
DROP TABLE IF EXISTS public.school_student_tuition_generation_ordering_ack_events;
DROP FUNCTION IF EXISTS public.school_guard_tuition_ordering_ack_event_immutable();
DROP FUNCTION IF EXISTS public.school_guard_tuition_ordering_ack_event_delete();

-- -----------------------------------------------------------------------------
-- §5 后置断言：必须逐字节回到部署前
-- -----------------------------------------------------------------------------
DO $lc$
DECLARE r record; v_oid oid; v_md5 text; v_acl text; v_cfg text; v_cmt text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('B','public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)','efa51498e77b515b6f67fc4be599a1b8','{postgres=X/postgres,service_role=X/postgres}','Phase B3: existing tuition facts are governed by lesson, settlement, bill, income, immutable and Gate contracts; frozen legacy student status is not an eligibility authority.'),
    ('G','public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text)','36bdadc9af59637c9d336ce68d9afb4c','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','R2-F-B authoritative atomic tuition writer. The public wrapper is R0-gated; clients submit no amounts or candidate details.'),
    ('C','public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)','95a68598215b61f55e5b63c74eeaa3f1','{postgres=X/postgres}','R2-F-C owner-only atomic tuition core. New generation holds fixed-order SHARE table locks on lesson and settlement evidence tables until transaction end; public wrapper remains R0 blocked.'),
    ('F','public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text)','a8ea31ced7f054d0b7ca4306dda1d3d8','{postgres=X/postgres}',NULL),
    ('N','public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text)','54ba2360eae9abfa740f539cb2ffb4ab','{postgres=X/postgres}',NULL)
  ) AS t(code,sig,md5,acl,cmt) LOOP
    v_oid := to_regprocedure(r.sig);
    IF v_oid IS NULL THEN RAISE EXCEPTION 'OGR_RESTORE_MISSING: %', r.code; END IF;
    SELECT md5(pg_get_functiondef(v_oid)), coalesce(proacl::text,''),
           coalesce(array_to_string(proconfig,','),''), obj_description(v_oid,'pg_proc')
      INTO v_md5, v_acl, v_cfg, v_cmt FROM pg_proc WHERE oid=v_oid;
    IF v_md5 <> r.md5 THEN RAISE EXCEPTION 'OGR_RESTORE_MD5: % 得 %', r.code, v_md5; END IF;
    IF v_acl <> r.acl THEN RAISE EXCEPTION 'OGR_RESTORE_ACL: % 得 %', r.code, v_acl; END IF;
    IF v_cfg <> 'search_path=pg_catalog, public' THEN
      RAISE EXCEPTION 'OGR_RESTORE_PROCONFIG: % 得 %', r.code, v_cfg; END IF;
    IF v_cmt IS DISTINCT FROM r.cmt THEN
      RAISE EXCEPTION 'OGR_RESTORE_COMMENT: %', r.code; END IF;
  END LOOP;

  -- 新签名必须消失
  FOR r IN SELECT * FROM (VALUES
    ('public.school_generate_student_tuition_bill_atomic(uuid,text,numeric,text,text,text)'),('public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text,text)'),
    ('public.school_generate_student_tuition_bill_atomic_base_core_v1(uuid,text,numeric,text,text,text,text)'),('public.school_generate_student_tuition_next_revision_core(uuid,uuid,uuid,text,numeric,text,text,text,text)')
  ) AS t(sig) LOOP
    IF to_regprocedure(r.sig) IS NOT NULL THEN
      RAISE EXCEPTION 'OGR_NEW_SIGNATURE_ALIVE: %', r.sig;
    END IF;
  END LOOP;

  IF to_regclass('public.school_student_tuition_generation_ordering_ack_events') IS NOT NULL THEN
    RAISE EXCEPTION 'OGR_ACK_TABLE_ALIVE';
  END IF;
  IF to_regprocedure('public.school_get_tuition_generation_ordering_state(uuid,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'OGR_READER_ALIVE';
  END IF;

  RAISE NOTICE 'OGR: 已逐字节还原到部署前状态';
END $lc$;

SELECT pg_notify('pgrst','reload schema');
COMMIT;
\echo '=== 回滚完成 ==='
