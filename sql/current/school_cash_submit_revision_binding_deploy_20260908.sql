-- =============================================================================
-- Cash 提交 revision 绑定：部署
--
-- 设计   ~/aozora-security-20260827/cash-submit-revision-binding-design-20260908-v3.md
-- 缺陷   Edge 把客户端回传值与 income snapshot 的同名字段比对，不比对当前 active
--        revision；而首次生成的账单 snapshot 里根本没有该键 ⇒ 永远提交不了。
--
-- 本文件【只改 preflight 的返回列】：facts 与最终 SELECT 各加一列。
--   前 10 列的名称、类型、顺序与【取值】一律不变。
--
-- ⚠️ 必须 DROP + CREATE：CREATE OR REPLACE 不能改返回类型
--    （PostgreSQL 原话：cannot change return type of existing function）。
--    DROP 会清掉 ACL 与 COMMENT，本文件逐项还原并断言。
--
-- ⚠️ 本文件【不含】HTTP 可见性门槛 —— 那一步必须在本文件 commit 之后、
--    Edge 部署之前，用【真实 HTTP RPC】单独执行（设计 §1.2）。
--
-- 用法：
--   排练  psql -v ON_ERROR_STOP=1 -v mode=rehearsal -f <本文件>
--   正式  psql -v ON_ERROR_STOP=1 -v mode=commit    -f <本文件>
-- =============================================================================
\set ON_ERROR_STOP on
\if :{?mode}
\else
  \set mode 'rehearsal'
\endif
\echo '=== Cash revision 绑定部署，mode =' :mode '==='

BEGIN;
SET LOCAL statement_timeout = '300s';
SET LOCAL lock_timeout = '15s';

-- -----------------------------------------------------------------------------
-- §1 部署前基线断言
-- -----------------------------------------------------------------------------
DO $cb$
DECLARE
  v_md5 text; v_owner text; v_secdef boolean; v_cfg text; v_strict boolean;
  v_par text; v_leak boolean; v_cost real; v_rows real; v_acl text; v_cmt text; v_res text;
BEGIN
  IF to_regprocedure('public.school_get_cash_income_submission_preflight(uuid[])') IS NULL THEN
    RAISE EXCEPTION 'CB_PRE_MISSING: preflight 不存在';
  END IF;
  SELECT md5(pg_get_functiondef(to_regprocedure('public.school_get_cash_income_submission_preflight(uuid[])'))) INTO v_md5;
  IF v_md5 <> '7a3c47a75988c86a003a999ab5b7a9e5' THEN RAISE EXCEPTION 'CB_PRE_MD5: 得 % 期望 %', v_md5, '7a3c47a75988c86a003a999ab5b7a9e5'; END IF;
    SELECT p.proowner::regrole::text, p.prosecdef, coalesce(array_to_string(p.proconfig,','),''),
           p.proisstrict, p.proparallel::text, p.proleakproof, p.procost, p.prorows,
           coalesce(p.proacl::text,''), obj_description(p.oid,'pg_proc'),
           pg_get_function_result(p.oid)
      INTO v_owner, v_secdef, v_cfg, v_strict, v_par, v_leak, v_cost, v_rows, v_acl, v_cmt, v_res
      FROM pg_proc p WHERE p.oid = to_regprocedure('public.school_get_cash_income_submission_preflight(uuid[])');
  -- DROP 会清掉 ACL / COMMENT，且 postgres 在 public 建函数的默认 ACL 恰好也含
  -- service_role —— 但【不能依赖默认权限碰巧等于目标值】，必须显式设置并逐项断言。
  IF v_owner  <> 'postgres'          THEN RAISE EXCEPTION 'CB_PRE_OWNER: %', v_owner; END IF;
  IF v_secdef IS NOT TRUE            THEN RAISE EXCEPTION 'CB_PRE_SECDEF: %', v_secdef; END IF;
  IF v_cfg    <> 'search_path=public' THEN RAISE EXCEPTION 'CB_PRE_PROCONFIG: %', v_cfg; END IF;
  IF v_strict IS NOT FALSE           THEN RAISE EXCEPTION 'CB_PRE_ISSTRICT: %', v_strict; END IF;
  IF v_par    <> 'u'                 THEN RAISE EXCEPTION 'CB_PRE_PARALLEL: %', v_par; END IF;
  IF v_leak   IS NOT FALSE           THEN RAISE EXCEPTION 'CB_PRE_LEAKPROOF: %', v_leak; END IF;
  IF v_cost   <> 100                 THEN RAISE EXCEPTION 'CB_PRE_COST: %', v_cost; END IF;
  IF v_rows   <> 1000                THEN RAISE EXCEPTION 'CB_PRE_ROWS: %', v_rows; END IF;
  IF v_acl    <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'            THEN RAISE EXCEPTION 'CB_PRE_ACL: %', v_acl; END IF;
  IF v_cmt IS DISTINCT FROM 'Read-only server-authoritative Cash submission classification and frozen tuition payment display facts.' THEN RAISE EXCEPTION 'CB_PRE_COMMENT: %', coalesce(v_cmt,'<NULL>'); END IF;
  IF v_res    <> 'TABLE(income_record_id uuid, classification text, eligible boolean, gate_state text, payment_currency text, payment_amount numeric, payment_exchange_rate numeric, previous_carryover_cny numeric, latest_linkage_status text, latest_cash_request_status text)'            THEN RAISE EXCEPTION 'CB_PRE_RESULT: %', v_res; END IF;

  RAISE NOTICE 'CB: 部署前基线全部通过';
END $cb$;

-- -----------------------------------------------------------------------------
-- §2 当次部署基线（【当场建立】，不引用任何写死的 revision UUID）
--
--   revision ID 是【业务状态】：会随作废、重发、提交而变化。
--   2026-09-08 取证到的 556a5ce1… / 928ec3e0… 只是当时的观察，
--   不得作为部署判据 —— 观察会过期，断言不会。
--
--   ⚠️ 基线【直接查 revision 表】建立，不得取自 preflight 的返回值 ——
--      那样就成了「拿被测函数的输出验证它自己」。
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE cb_baseline ON COMMIT DROP AS
SELECT i.id                AS income_id,
       b.id                AS bill_id,
       r.id                AS active_revision_id
FROM public.school_income_records i
JOIN public.school_student_tuition_bills b
  ON b.id = i.source_id AND b.id = i.tuition_bill_id
JOIN public.school_student_tuition_generation_revisions r
  ON r.tuition_bill_id = b.id AND r.lifecycle_status = 'active'
WHERE i.source_type = 'student_tuition_bill'
  AND i.status = 'pending';

DO $cb$
DECLARE v_n bigint; v_bad bigint;
BEGIN
  -- 每笔 income 必须【恰好一个】 active revision：零行或多行都停。
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
    RAISE EXCEPTION 'CB_BASELINE_REVISION_CARDINALITY: % 笔 pending income 的 active revision 不是恰好一个', v_bad;
  END IF;

  SELECT count(*) INTO v_n FROM cb_baseline;
  RAISE NOTICE 'CB: 当次基线 % 笔', v_n;
  -- 零样本时后续的值正确性比对将是真空的 —— 必须停止，不得当作通过。
  IF v_n = 0 THEN
    RAISE EXCEPTION 'CB_BASELINE_EMPTY: 无 pending 学费 income，值正确性无从验证，停止部署';
  END IF;
  IF EXISTS (SELECT 1 FROM cb_baseline WHERE active_revision_id IS NULL) THEN
    RAISE EXCEPTION 'CB_BASELINE_NULL_REVISION';
  END IF;
END $cb$;

\echo ''
\echo '--- 当次部署基线（供漂移比对，非永久常量）---'
SELECT income_id, bill_id, active_revision_id FROM cb_baseline ORDER BY income_id;

CREATE TEMP TABLE cb_sweep(phase text, income_id uuid, payload jsonb) ON COMMIT DROP;

CREATE OR REPLACE FUNCTION pg_temp.cb_scan(p_phase text) RETURNS void
LANGUAGE plpgsql AS $cb$
BEGIN
  INSERT INTO cb_sweep
  SELECT p_phase, pf.income_record_id, to_jsonb(pf)
  FROM public.school_get_cash_income_submission_preflight(
         (SELECT array_agg(income_id) FROM cb_baseline)) pf;
END $cb$;

SELECT pg_temp.cb_scan('before');

-- -----------------------------------------------------------------------------
-- §3 替换（DROP + CREATE）
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.school_get_cash_income_submission_preflight(uuid[]);

CREATE OR REPLACE FUNCTION public.school_get_cash_income_submission_preflight(p_income_record_ids uuid[])
 RETURNS TABLE(income_record_id uuid, classification text, eligible boolean, gate_state text, payment_currency text, payment_amount numeric, payment_exchange_rate numeric, previous_carryover_cny numeric, latest_linkage_status text, latest_cash_request_status text, active_generation_revision_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with requested as (
    select distinct requested_id
    from unnest(coalesce(p_income_record_ids, array[]::uuid[])) requested_id
    limit 500
  ), latest_linkage as (
    select distinct on (event_row.income_record_id) event_row.*
    from public.school_personal_cash_income_linkage_events event_row
    join requested on requested.requested_id = event_row.income_record_id
    order by event_row.income_record_id, event_row.attempt_no desc,
             event_row.created_at desc, event_row.id desc
  ), facts as (
    select
      income_row.id,
      income_row.status as income_status,
      income_row.account_id,
      income_row.source_type,
      income_row.income_category,
      income_row.source_id,
      income_row.tuition_bill_id,
      income_row.student_id,
      income_row.business_entity_id,
      income_row.year_month,
      income_row.settlement_month,
      income_row.currency,
      income_row.amount,
      income_row.amount_jpy,
      income_row.source_snapshot,
      income_row.cash_submission_blocked as income_blocked,
      income_row.operational_excluded,
      bill_row.id as bill_id,
      bill_row.status as bill_status,
      bill_row.income_record_id as bill_income_record_id,
      bill_row.student_id as bill_student_id,
      bill_row.business_entity_id as bill_business_entity_id,
      bill_row.billing_month,
      bill_row.bill_amount_jpy,
      bill_row.billing_exchange_rate,
      bill_row.billing_amount_cny,
      bill_row.previous_carryover_cny,
      bill_row.cash_submission_blocked as bill_blocked,
      identity_row.id as identity_id,
      latest.sync_status,
      latest.cash_request_status,
      latest.cash_transaction_id,
      revision_row.id as active_generation_revision_id,
      coalesce((select state from public.school_feature_gates where feature_key = 'student_tuition_cash_submit'), 'unavailable') as current_gate_state
    from requested
    join public.school_income_records income_row on income_row.id = requested.requested_id
    left join public.school_student_tuition_bills bill_row
      on bill_row.id = income_row.source_id
     and bill_row.id = income_row.tuition_bill_id
    left join public.school_student_tuition_generation_revisions revision_row
      on revision_row.tuition_bill_id = bill_row.id
     and revision_row.lifecycle_status = 'active'
    left join public.school_student_tuition_generation_identities generation_row
      on generation_row.id = revision_row.generation_identity_id
     and generation_row.student_id = bill_row.student_id
     and (revision_row.manifest_kind = 'historical_registration_v1'
       or generation_row.business_entity_id = bill_row.business_entity_id)
     and to_char(generation_row.billing_month,'YYYY-MM') = bill_row.billing_month
    left join public.school_student_tuition_billing_identities identity_row
      on identity_row.id = generation_row.legacy_billing_identity_id
    left join latest_linkage latest on latest.income_record_id = income_row.id
  ), classified as (
    select facts.*,
      case
        when source_type <> 'student_tuition_bill' then 'NON_TUITION'
        when income_status = 'received' and sync_status in ('synced', 'historical_confirmed') then 'ALREADY_SYNCED'
        when sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation')
          or cash_request_status = 'pending' then 'ALREADY_SUBMITTED'
        when income_status = 'pending' and sync_status = 'cash_rejected'
          and cash_request_status = 'rejected' and cash_transaction_id is null then 'REJECTED_RETRYABLE'
        when income_status = 'pending' and bill_status = 'income_created'
          and identity_id is not null
          and income_category = 'tuition'
          and source_id = bill_id and tuition_bill_id = bill_id
          and bill_income_record_id = id
          and account_id is null
          and income_blocked is false and operational_excluded is false
          and bill_blocked is false
          and student_id = bill_student_id
          and business_entity_id = bill_business_entity_id
          and year_month = billing_month and settlement_month = billing_month
          and currency = 'JPY' and amount = bill_amount_jpy and amount_jpy = bill_amount_jpy
          and (source_snapshot ->> 'tuition_bill_id')::uuid = bill_id
          and (source_snapshot ->> 'billing_identity_id')::uuid = identity_id
          and (source_snapshot ->> 'billing_exchange_rate')::numeric = billing_exchange_rate
          and (source_snapshot ->> 'billing_amount_cny')::numeric = billing_amount_cny
          and (source_snapshot ->> 'previous_carryover_cny')::numeric = previous_carryover_cny
          and sync_status is null then 'ELIGIBLE_FOR_CASH_SUBMIT'
        else 'BLOCKED_CONFLICT'
      end as result_classification
    from facts
  )
  select
    id,
    result_classification,
    result_classification in ('ELIGIBLE_FOR_CASH_SUBMIT', 'REJECTED_RETRYABLE')
      and current_gate_state = 'enabled',
    current_gate_state,
    case when source_type = 'student_tuition_bill' then 'CNY' else null end,
    case when source_type = 'student_tuition_bill' then billing_amount_cny else null end,
    case when source_type = 'student_tuition_bill' then billing_exchange_rate else null end,
    case when source_type = 'student_tuition_bill' then previous_carryover_cny else null end,
    sync_status,
    cash_request_status,
    active_generation_revision_id
  from classified;
$function$
;

REVOKE ALL ON FUNCTION public.school_get_cash_income_submission_preflight(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.school_get_cash_income_submission_preflight(uuid[]) TO authenticated, service_role;
COMMENT ON FUNCTION public.school_get_cash_income_submission_preflight(uuid[]) IS 'Read-only server-authoritative Cash submission classification and frozen tuition payment display facts.';

-- -----------------------------------------------------------------------------
-- §4 部署后断言
-- -----------------------------------------------------------------------------
SELECT pg_temp.cb_scan('after');

DO $cb$
DECLARE
  v_md5 text; v_owner text; v_secdef boolean; v_cfg text; v_strict boolean;
  v_par text; v_leak boolean; v_cost real; v_rows real; v_acl text; v_cmt text; v_res text;
  v_bad bigint; v_ok bigint;
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


  -- 4.1 前 10 列的【取值】必须逐笔完全相同
  SELECT count(*) INTO v_bad
  FROM cb_sweep a JOIN cb_sweep b
    ON b.phase='after' AND a.phase='before' AND a.income_id=b.income_id
  WHERE (a.payload - 'active_generation_revision_id')
     <> (b.payload - 'active_generation_revision_id');
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'CB_EXISTING_COLUMNS_CHANGED: % 笔的原有 10 列取值发生变化', v_bad;
  END IF;

  -- 4.2 前后笔数必须一致（漏笔也是变化）
  IF (SELECT count(*) FROM cb_sweep WHERE phase='before')
     <> (SELECT count(*) FROM cb_sweep WHERE phase='after') THEN
    RAISE EXCEPTION 'CB_SWEEP_COUNT_CHANGED';
  END IF;

  -- 4.3 新列必须【逐笔等于当次基线】（基线来自 revision 表，非本函数输出）
  SELECT count(*) INTO v_bad
  FROM cb_sweep s JOIN cb_baseline base ON base.income_id = s.income_id
  WHERE s.phase='after'
    AND (s.payload->>'active_generation_revision_id')::uuid
        IS DISTINCT FROM base.active_revision_id;
  IF v_bad > 0 THEN
    RAISE EXCEPTION 'CB_NEW_COLUMN_MISMATCH: % 笔的新列与当次基线不符', v_bad;
  END IF;

  -- 4.4 至少一笔【非空】—— 全为 NULL 时上面的比对是真空的
  SELECT count(*) INTO v_ok FROM cb_sweep
   WHERE phase='after' AND payload->>'active_generation_revision_id' IS NOT NULL;
  IF v_ok = 0 THEN
    RAISE EXCEPTION 'CB_NEW_COLUMN_ALL_NULL: 无非空样本，值正确性未验证';
  END IF;
  RAISE NOTICE 'CB: 部署后断言全部通过（非空样本 % 笔）', v_ok;
END $cb$;

\echo ''
\echo '--- 部署后 preflight 的新列 ---'
SELECT s.income_id,
       (s.payload->>'active_generation_revision_id')::uuid AS via_preflight,
       b.active_revision_id                                 AS via_revision_table
FROM cb_sweep s JOIN cb_baseline b ON b.income_id = s.income_id
WHERE s.phase='after' ORDER BY s.income_id;

-- -----------------------------------------------------------------------------
-- §5 收尾
-- -----------------------------------------------------------------------------
SELECT (:'mode' = 'commit') AS cb_is_commit \gset
\if :cb_is_commit
  SELECT pg_notify('pgrst','reload schema');
  COMMIT;
  \echo '=== 已 COMMIT。'
  \echo '⛔ 下一步【不是】部署 Edge，而是 HTTP 可见性门槛：'
  \echo '   用真实 HTTP RPC 调 preflight，确认新列已出现且逐笔等于上表 via_revision_table。'
  \echo '   门槛不过 ⇒ 不得部署 Edge（新 Edge 会读到 undefined 并拒绝全部学费提交）。'
\else
  ROLLBACK;
  \echo '=== 排练完成，已 ROLLBACK，生产未改变 ==='
\endif
