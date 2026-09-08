-- =============================================================================
-- Cash 提交 revision 绑定：回滚（SQL 层）
--
-- ⚠️ 回滚顺序是【前端 → Edge → SQL】。本文件是最后一步。
--
-- ⛔ 本文件只还原【函数定义与属性】。它【不还原业务事实】。
--
-- ⛔ 两个必填参数，缺一不可（缺失 / 空 / 非法一律非零退出）：
--
--   -v deployed_at='YYYY-MM-DD HH:MM:SS+09'
--       部署时刻。用于盘点其后是否产生了 School linkage。
--
--   -v cash_inventory='<两库盘点结论的说明>'
--       ⚠️ 本脚本【只连 School 库】，School linkage 为零【只能证明 School 侧】。
--          Cash 库的 request / transaction 盘点【必须在本脚本之外独立完成】，
--          并把结论写进本参数。没有这份两库证据，不得执行定义回滚。
--       写 'skip' 视为未完成盘点，脚本拒绝执行。
--
-- 用法：
--   psql -v ON_ERROR_STOP=1 \
--        -v deployed_at='2026-09-08 20:00:00+09' \
--        -v cash_inventory='Cash 库 request=0 transaction=0，20:31 只读核对，业务负责人确认' \
--        -f <本文件>
-- =============================================================================
\set ON_ERROR_STOP on
\if :{?deployed_at}
\else
  \set deployed_at ''
\endif
\if :{?cash_inventory}
\else
  \set cash_inventory ''
\endif

BEGIN;
SET LOCAL statement_timeout = '300s';
SET LOCAL lock_timeout = '15s';

-- psql 不在美元引号内做变量插值 ⇒ 先经 set_config 交给会话
SELECT set_config('cbr.deployed_at',    :'deployed_at',    true),
       set_config('cbr.cash_inventory', :'cash_inventory', true);

-- -----------------------------------------------------------------------------
-- §1 必填参数（缺失一律【抛异常】，不用 \quit —— 那个退出码是 0，
--     会把「拒绝回滚」记成「回滚成功」）
-- -----------------------------------------------------------------------------
DO $cb$
DECLARE v_at text := nullif(btrim(current_setting('cbr.deployed_at')),'');
        v_inv text := nullif(btrim(current_setting('cbr.cash_inventory')),'');
        v_ts timestamptz;
BEGIN
  IF v_at IS NULL THEN
    RAISE EXCEPTION 'CBR_DEPLOYED_AT_REQUIRED: 必须 -v deployed_at=...；'
      '缺省会让 linkage 计数恒为 0，等于绕过业务事实盘点';
  END IF;
  BEGIN
    v_ts := v_at::timestamptz;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'CBR_DEPLOYED_AT_INVALID: 无法解析为时间戳: %', v_at;
  END;
  IF v_inv IS NULL OR lower(v_inv) IN ('skip','no','none','n/a') THEN
    RAISE EXCEPTION 'CBR_CASH_INVENTORY_REQUIRED: 必须 -v cash_inventory=<两库盘点结论>。'
      '本脚本只连 School 库，School linkage 为零【只能证明 School 侧】；'
      'Cash 库的 request / transaction 盘点须在本脚本之外独立完成。';
  END IF;
  RAISE NOTICE 'CBR: 部署时刻 %；Cash 侧盘点结论已提供（外部证据，本脚本不复核其真伪）', v_ts;
END $cb$;

-- -----------------------------------------------------------------------------
-- §2 当前必须是本次部署的结果
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
  IF v_acl <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    -- 区分两种失败：权限【集合】变了（真问题），还是只是数组【顺序】不同
    -- （DROP 后默认授权回流所致）。上一轮就是后者，而报错只说「实际/期望」，
    -- 盯了几秒才看出来 —— 同一个断言下次再响时要能一眼分辨。
    IF EXISTS (SELECT unnest(string_to_array(btrim(v_acl,'{}'), ','))
               EXCEPT SELECT unnest(string_to_array(btrim('{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','{}'), ',')))
       OR EXISTS (SELECT unnest(string_to_array(btrim('{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','{}'), ','))
                  EXCEPT SELECT unnest(string_to_array(btrim(v_acl,'{}'), ','))) THEN
      RAISE EXCEPTION 'CB_POST_ACL_SET: 权限集合与基线不同  实际 %  期望 %', v_acl, '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}';
    ELSE
      RAISE EXCEPTION 'CB_POST_ACL_ORDER: 集合相同但数组顺序不同  实际 %  期望 %', v_acl, '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}';
    END IF;
  END IF;
  IF v_cmt IS DISTINCT FROM 'Read-only server-authoritative Cash submission classification and frozen tuition payment display facts.' THEN RAISE EXCEPTION 'CB_POST_COMMENT: %', coalesce(v_cmt,'<NULL>'); END IF;
  IF v_res    <> 'TABLE(income_record_id uuid, classification text, eligible boolean, gate_state text, payment_currency text, payment_amount numeric, payment_exchange_rate numeric, previous_carryover_cny numeric, latest_linkage_status text, latest_cash_request_status text, active_generation_revision_id uuid)'            THEN RAISE EXCEPTION 'CB_POST_RESULT: %', v_res; END IF;

  RAISE NOTICE 'CBR: 当前确为本次部署的状态';
END $cb$;

-- -----------------------------------------------------------------------------
-- §3 School 侧业务事实盘点（发现即【抛异常】停止）
-- -----------------------------------------------------------------------------
DO $cb$
DECLARE v_n bigint;
BEGIN
  SELECT count(*) INTO v_n FROM public.school_personal_cash_income_linkage_events
   WHERE created_at >= current_setting('cbr.deployed_at')::timestamptz;
  RAISE NOTICE 'CBR: 部署后新增 School linkage 事件 % 条', v_n;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'CBR_BUSINESS_FACTS_EXIST: 部署后已产生 % 条 School linkage 事件。'
      '回滚【只还原函数定义，不撤销这些业务事实】。'
      '请逐笔列出 linkage / Cash request / transaction 交业务负责人判断；'
      '若仍决定继续，事后【不得】把整体状态描述为「恢复到部署前」。', v_n;
  END IF;
END $cb$;

-- -----------------------------------------------------------------------------
-- §4 还原定义与全部属性
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

-- ⚠️ DROP 之后 public schema 的默认授权会把 service_role 【先】放回 ACL 数组，
--    随后的 GRANT 再追加 authenticated ⇒ 顺序成为
--    {postgres,service_role,authenticated}，与基线的
--    {postgres,authenticated,service_role} 不符 —— 权限集合相同，数组顺序不同。
--    故先【显式清空】，再【按基线顺序逐条 GRANT】，保住逐字节还原。
REVOKE ALL ON FUNCTION public.school_get_cash_income_submission_preflight(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.school_get_cash_income_submission_preflight(uuid[]) FROM authenticated;
REVOKE ALL ON FUNCTION public.school_get_cash_income_submission_preflight(uuid[]) FROM service_role;
GRANT EXECUTE ON FUNCTION public.school_get_cash_income_submission_preflight(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.school_get_cash_income_submission_preflight(uuid[]) TO service_role;
COMMENT ON FUNCTION public.school_get_cash_income_submission_preflight(uuid[]) IS 'Read-only server-authoritative Cash submission classification and frozen tuition payment display facts.';

-- -----------------------------------------------------------------------------
-- §5 后置断言：必须逐字节回到部署前
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
  IF v_acl <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    -- 区分两种失败：权限【集合】变了（真问题），还是只是数组【顺序】不同
    -- （DROP 后默认授权回流所致）。上一轮就是后者，而报错只说「实际/期望」，
    -- 盯了几秒才看出来 —— 同一个断言下次再响时要能一眼分辨。
    IF EXISTS (SELECT unnest(string_to_array(btrim(v_acl,'{}'), ','))
               EXCEPT SELECT unnest(string_to_array(btrim('{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','{}'), ',')))
       OR EXISTS (SELECT unnest(string_to_array(btrim('{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','{}'), ','))
                  EXCEPT SELECT unnest(string_to_array(btrim(v_acl,'{}'), ','))) THEN
      RAISE EXCEPTION 'CB_PRE_ACL_SET: 权限集合与基线不同  实际 %  期望 %', v_acl, '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}';
    ELSE
      RAISE EXCEPTION 'CB_PRE_ACL_ORDER: 集合相同但数组顺序不同  实际 %  期望 %', v_acl, '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}';
    END IF;
  END IF;
  IF v_cmt IS DISTINCT FROM 'Read-only server-authoritative Cash submission classification and frozen tuition payment display facts.' THEN RAISE EXCEPTION 'CB_PRE_COMMENT: %', coalesce(v_cmt,'<NULL>'); END IF;
  IF v_res    <> 'TABLE(income_record_id uuid, classification text, eligible boolean, gate_state text, payment_currency text, payment_amount numeric, payment_exchange_rate numeric, previous_carryover_cny numeric, latest_linkage_status text, latest_cash_request_status text)'            THEN RAISE EXCEPTION 'CB_PRE_RESULT: %', v_res; END IF;

  RAISE NOTICE 'CBR: 已还原到部署前定义与属性';
END $cb$;

SELECT pg_notify('pgrst','reload schema');
COMMIT;
\echo '=== SQL 层回滚完成。'
\echo '⚠️ 只还原了函数定义与属性。业务事实不在回滚范围内，'
\echo '   且 Cash 侧的盘点由外部提供，本脚本未复核。'
