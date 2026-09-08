-- =============================================================================
-- Cash 提交 revision 绑定：回滚（SQL 层）
--
-- ⚠️ 回滚顺序是【前端 → Edge → SQL】。本文件是最后一步。
--    先回退前端与 Edge，再执行本文件。
--
-- ⛔ 本文件只还原【函数定义】。它【不还原业务事实】：
--    若期间已产生真实 Cash request / School linkage / income 状态变化，
--    那些是真实业务事实，回滚函数定义【不会撤销它们】。
--    见 §1 的检查与停止条件。
--
-- 用法：
--   psql -v ON_ERROR_STOP=1 -f <本文件>
--   psql -v ON_ERROR_STOP=1 -v deployed_at='YYYY-MM-DD HH:MM:SS+09' -f <本文件>
-- =============================================================================
\set ON_ERROR_STOP on
\if :{?deployed_at}
\else
  \set deployed_at ''
\endif

BEGIN;
SET LOCAL statement_timeout = '300s';
SET LOCAL lock_timeout = '15s';

-- -----------------------------------------------------------------------------
-- §1 前置：当前必须是本次部署的结果；并检查期间是否已产生业务事实
-- -----------------------------------------------------------------------------
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

  RAISE NOTICE 'CBR: 当前确为本次部署的状态';
END $cb$;

\if :{?deployed_at}
\endif
-- ⚠️ 不能写 :'deployed_at'::timestamptz —— 空串的转型在【常量折叠】阶段就会抛错，
--    外层的 CASE 拦不住。用 nullif 先化为 NULL 再转型。
SELECT coalesce((
  SELECT count(*) FROM public.school_personal_cash_income_linkage_events
   WHERE nullif(:'deployed_at','') IS NOT NULL
     AND created_at >= nullif(:'deployed_at','')::timestamptz), 0) AS cbr_new_linkage \gset

\if :{?cbr_new_linkage}
\endif
SELECT (:cbr_new_linkage > 0) AS cbr_blocked \gset
\if :cbr_blocked
  \echo '⛔ 部署之后已产生' :cbr_new_linkage '条 School linkage 事件。'
  \echo '   回滚【只还原函数定义，不撤销这些业务事实】。'
  \echo '   请先逐笔列出已产生的 linkage / Cash request / transaction，'
  \echo '   交业务负责人判断后再决定是否继续。'
  \echo '   ⚠️ 继续回滚后，【不得】把整体状态描述为「恢复到部署前」。'
  ROLLBACK;
  \quit
\endif

-- -----------------------------------------------------------------------------
-- §2 还原定义（DROP + CREATE）与全部属性
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.school_get_cash_income_submission_preflight(uuid[]);

CREATE OR REPLACE FUNCTION public.school_get_cash_income_submission_preflight(p_income_record_ids uuid[])
 RETURNS TABLE(income_record_id uuid, classification text, eligible boolean, gate_state text, payment_currency text, payment_amount numeric, payment_exchange_rate numeric, previous_carryover_cny numeric, latest_linkage_status text, latest_cash_request_status text)
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
    cash_request_status
  from classified;
$function$
;

REVOKE ALL ON FUNCTION public.school_get_cash_income_submission_preflight(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.school_get_cash_income_submission_preflight(uuid[]) TO authenticated, service_role;
COMMENT ON FUNCTION public.school_get_cash_income_submission_preflight(uuid[]) IS 'Read-only server-authoritative Cash submission classification and frozen tuition payment display facts.';

-- -----------------------------------------------------------------------------
-- §3 后置断言：必须逐字节回到部署前
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

  RAISE NOTICE 'CBR: 已还原到部署前定义与属性';
END $cb$;

SELECT pg_notify('pgrst','reload schema');
COMMIT;
\echo '=== SQL 层回滚完成。'
\echo '⚠️ 本次只还原了函数定义与属性；业务事实不在回滚范围内。'
