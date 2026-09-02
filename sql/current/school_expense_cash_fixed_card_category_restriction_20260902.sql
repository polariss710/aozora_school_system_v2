-- 固定信用卡路线 —— 限制为教室费用分类
--
-- 日期：2026-09-02
-- 基线：2026-09-02 11:06:16 JST 从生产 pg_get_functiondef 导出
--       SHA-256 679c61a414b96504a3ba21b04845fac2b1fdfb95e700d96d2e0bad5a94df7061
--       归档于 ~/aozora-security-20260827/cash-baseline/
--
-- ===========================================================================
-- 这一步做什么
-- ===========================================================================
--
-- 给 prepare 函数增加一条分类检查：只有 expense_category = 'classroom' 的支出
-- 可以走固定信用卡路线。除此之外函数逐字节不变。
--
-- 业务约定（用户 2026-09-02 确认）：只有教室租金这类大额、需要「刷卡进账单、
-- 次月还款」的预扣支出才走信用卡；其余小额支出直接用公司卡走即时账户路线。
--
-- ===========================================================================
-- 为什么必须放在数据库层
-- ===========================================================================
--
-- 前端已在 0e4582b 做了界面镜像（非 classroom 时隐藏「支付路线」字段），但那
-- 挡不住直接调用 Edge 的调用方。一旦把老师工资之类提交成固定项，那笔钱会挂到
-- 信用卡账单上、与实际支付方式不符，而撤销要经过 Cash 侧整套固定项删除保护
-- （2026-09-01 删一笔 7,000 JPY 走了四个步骤）。
--
-- ===========================================================================
-- 检查位置为什么在这里
-- ===========================================================================
--
-- 放在 reversed 检查之后、source_type 分支之前。此时支出行已 for update 锁定并
-- 完成存在性与作废状态检查，分类判断拿到的是确定的行；同时不改变 Gate 检查的
-- 优先级——Gate 未开时仍然先报 SCHOOL_CASH_FIXED_CREDIT_CARD_ROUTE_DISABLED。
--
-- 错误码采用 SCHOOL_EXPENSE_CASH_FIXED_CATEGORY_FORBIDDEN，与本函数既有的
-- SCHOOL_EXPENSE_CASH_FIXED_* 系列一致。
--
-- ===========================================================================
-- 回滚
-- ===========================================================================
--
--   从 ~/aozora-security-20260827/cash-baseline/
--     school_request_cash_fixed_expense_payment_confirmation_v2-production-20260902.sql
--   原样 CREATE OR REPLACE 覆盖即可。不涉及数据变更、不涉及 ACL 变更。
--
--   回滚后该函数恢复到「任何分类都可走固定卡路线」的状态。由于前端仍有界面
--   镜像，正常操作不受影响，但权威层保护会消失。
--
-- ===========================================================================

\set ON_ERROR_STOP on

begin;

CREATE OR REPLACE FUNCTION public.school_request_cash_fixed_expense_payment_confirmation_v2(p_expense_record_id uuid, p_cash_user_id uuid, p_card_instrument_id uuid, p_charge_date date, p_suggested_fixed_month date, p_target_fixed_month date, p_funding_date date, p_note text DEFAULT NULL::text, p_external_source text DEFAULT 'aozora_school'::text, p_external_reference_type text DEFAULT 'school_expense_records'::text, p_external_reference_id uuid DEFAULT NULL::uuid, p_request_type text DEFAULT 'expense_paid'::text, p_transaction_type text DEFAULT 'expense'::text, p_expected_request_event_id uuid DEFAULT NULL::uuid, p_expected_idempotency_key text DEFAULT NULL::text)
 RETURNS TABLE(expense_id uuid, request_event_id uuid, attempt_no integer, idempotency_key text, request_type text, payment_route text, expense_status text, expense_category text, source_type text, source_id uuid, payee_name_snapshot text, year_month text, expense_date date, description text, original_amount numeric, original_currency text, settlement_amount numeric, settlement_currency text, cash_user_id uuid, card_instrument_id uuid, charge_date date, suggested_fixed_month date, target_fixed_month date, funding_date date, cash_request_id uuid, cash_request_status text, attempt_id uuid, attempt_status text, attempt_version integer, request_payload_fingerprint text, cash_description text, cash_payload_snapshot jsonb, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_expense public.school_expense_records%rowtype;
  v_attempt public.school_expense_cash_attempts%rowtype;
  v_now timestamptz := statement_timestamp();
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_attempt_no integer;
  v_event_id uuid;
  v_idempotency_key text;
  v_reuse_attempt boolean := false;
  v_cash_description text;
  v_cash_payload jsonb;
begin
  if not exists (
    select 1 from public.school_feature_gates g
    where g.feature_key = 'cash_expense_attempt_writer_v2_enabled' and g.state = 'enabled'
  ) then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_V2_DISABLED';
  end if;
  if not exists (
    select 1 from public.school_feature_gates g
    where g.feature_key = 'cash_fixed_credit_card_route_enabled' and g.state = 'enabled'
  ) then
    raise exception using errcode = '55000', message = 'SCHOOL_CASH_FIXED_CREDIT_CARD_ROUTE_DISABLED';
  end if;

  if p_expense_record_id is null or p_cash_user_id is null
     or p_card_instrument_id is null or p_charge_date is null
     or p_suggested_fixed_month is null or p_target_fixed_month is null
     or p_funding_date is null then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_FIXED_PREPARE_REQUIRED_INPUT';
  end if;
  if p_suggested_fixed_month <> date_trunc('month', p_suggested_fixed_month)::date
     or p_target_fixed_month <> date_trunc('month', p_target_fixed_month)::date
     or p_target_fixed_month <> p_suggested_fixed_month then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_FIXED_SCHEDULE_INVALID';
  end if;
  if p_external_source is distinct from 'aozora_school'
     or p_external_reference_type is distinct from 'school_expense_records'
     or coalesce(p_external_reference_id, p_expense_record_id) is distinct from p_expense_record_id
     or p_request_type is distinct from 'expense_paid'
     or p_transaction_type is distinct from 'expense' then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ATTEMPT_EXTERNAL_IDENTITY_CONFLICT';
  end if;

  select * into v_expense
  from public.school_expense_records e
  where e.id = p_expense_record_id and e.app_type = 'school'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'SCHOOL_EXPENSE_RECORD_NOT_FOUND';
  end if;
  if v_expense.reversed_at is not null or v_expense.status = 'reversed' then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_REVERSED_FORBIDDEN';
  end if;
  -- 2026-09-02：固定信用卡路线只对教室费用开放。
  --
  -- 业务约定是只有教室租金这类大额、需要「刷卡进账单、次月还款」的支出才走
  -- 信用卡。前端已按同一条件隐藏路线选择，但 UI 挡不住直接调用 Edge 的调用方，
  -- 因此判定必须落在这里。
  if v_expense.expense_category is distinct from 'classroom' then
    raise exception using errcode = '55000',
      message = 'SCHOOL_EXPENSE_CASH_FIXED_CATEGORY_FORBIDDEN';
  end if;
  if v_expense.source_type = 'manual_cash' then
    if v_expense.cash_creation_event_id is null
       or v_expense.created_by_user_id is null
       or v_expense.account_id is not null
       or v_expense.payment_method is not null then
      raise exception using errcode = '55000', message = 'P0_MANUAL_CASH_EXPENSE_AUDIT_INVARIANT_VIOLATION';
    end if;
  elsif v_expense.source_type = 'teacher_wage' then
    if v_expense.source_id is null then
      raise exception using errcode = '55000', message = 'P0_TEACHER_WAGE_EXPENSE_SOURCE_ID_REQUIRED';
    end if;
  else
    raise exception using errcode = '42501', message = 'P0_EXPENSE_CASH_REQUEST_SOURCE_NOT_ALLOWED';
  end if;
  if v_expense.currency not in ('JPY', 'CNY') or coalesce(v_expense.amount, 0) <= 0 then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_FIXED_AMOUNT_OR_CURRENCY_INVALID';
  end if;
  if v_expense.status = 'paid' or v_expense.cash_transaction_id is not null
     or v_expense.cash_request_status in ('approved', 'synced') then
    raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_ACTIVE_OR_COMPLETED_REQUEST_EXISTS';
  end if;

  v_reuse_attempt := v_expense.cash_request_status in ('pending_cash_request', 'pending')
    and v_expense.cash_request_event_id is not null;

  if v_reuse_attempt then
    select * into v_attempt
    from public.school_expense_cash_attempts a
    where a.expense_id = v_expense.id
      and a.request_event_id = v_expense.cash_request_event_id
    for update;
    if not found
       or (v_expense.cash_request_status = 'pending_cash_request' and (
         v_attempt.attempt_status <> 'prepared'
         or v_expense.cash_request_id is not null
         or v_attempt.cash_request_id is not null
       ))
       or (v_expense.cash_request_status = 'pending' and (
         v_attempt.attempt_status <> 'submitted'
         or v_expense.cash_request_id is null
         or v_attempt.cash_request_id is distinct from v_expense.cash_request_id
       )) then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_REUSABLE_ATTEMPT_MISSING';
    end if;
    if v_attempt.payment_route <> 'fixed_credit_card'
       or v_attempt.attempt_no is distinct from v_expense.cash_request_attempt_no
       or v_attempt.original_amount is distinct from v_expense.amount
       or v_attempt.original_currency is distinct from v_expense.currency
       or v_attempt.payment_amount is distinct from v_expense.amount
       or v_attempt.payment_currency is distinct from v_expense.currency
       or v_attempt.cash_funding_account_id is not null
       or v_attempt.cash_card_instrument_id is distinct from p_card_instrument_id
       or v_attempt.charge_date is distinct from p_charge_date
       or v_attempt.suggested_fixed_month is distinct from p_suggested_fixed_month
       or v_attempt.target_fixed_month is distinct from p_target_fixed_month
       or v_attempt.funding_date is distinct from p_funding_date
       or v_expense.cash_payment_amount is distinct from v_expense.amount
       or v_expense.cash_payment_currency is distinct from v_expense.currency
       or v_expense.cash_payment_note is distinct from v_note
       or (p_expected_request_event_id is not null and v_attempt.request_event_id is distinct from p_expected_request_event_id)
       or (p_expected_idempotency_key is not null and v_attempt.idempotency_key is distinct from p_expected_idempotency_key) then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_PREPARE_PAYLOAD_CONFLICT';
    end if;
  else
    v_attempt_no := coalesce(v_expense.cash_request_attempt_no, 0) + 1;
    v_event_id := gen_random_uuid();
    v_idempotency_key := format(
      'aozora_school:school_expense_records:%s:expense_paid:attempt:%s',
      v_expense.id,
      v_attempt_no
    );
    if p_expected_request_event_id is not null and p_expected_request_event_id is distinct from v_event_id then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_EXPECTED_EVENT_CONFLICT';
    end if;
    if p_expected_idempotency_key is not null and p_expected_idempotency_key is distinct from v_idempotency_key then
      raise exception using errcode = '55000', message = 'SCHOOL_EXPENSE_CASH_FIXED_EXPECTED_IDEMPOTENCY_CONFLICT';
    end if;

    insert into public.school_expense_cash_attempts(
      expense_id, attempt_no, payment_route, request_type, request_event_id,
      idempotency_key, cash_funding_account_id, cash_card_instrument_id,
      original_amount, original_currency, payment_amount, payment_currency,
      charge_date, suggested_fixed_month, target_fixed_month, funding_date,
      attempt_status, version
    ) values (
      v_expense.id, v_attempt_no, 'fixed_credit_card', 'expense_paid', v_event_id,
      v_idempotency_key, null, p_card_instrument_id,
      v_expense.amount, v_expense.currency, v_expense.amount, v_expense.currency,
      p_charge_date, p_suggested_fixed_month, p_target_fixed_month, p_funding_date,
      'prepared', 1
    ) returning * into v_attempt;

    update public.school_expense_records e
    set cash_request_event_id = v_attempt.request_event_id,
        cash_request_attempt_no = v_attempt.attempt_no,
        cash_request_status = 'pending_cash_request',
        cash_request_id = null,
        cash_transaction_id = null,
        cash_requested_at = v_now,
        cash_payment_amount = v_attempt.payment_amount,
        cash_payment_currency = v_attempt.payment_currency,
        cash_payment_note = v_note,
        cash_error_message = null,
        updated_at = v_now
    where e.id = v_expense.id
    returning * into v_expense;
  end if;

  v_cash_description := concat_ws(
    ' / ',
    case v_expense.expense_category
      when 'advertising' then '广告宣传'
      when 'classroom' then '教室费用'
      when 'other' then '其他'
      when 'software' then '软件服务'
      when 'tax_accounting' then '税务会计'
      when 'teacher_wage' then '老师工资'
      else v_expense.expense_category
    end,
    nullif(trim(coalesce(v_expense.payee_name_snapshot, '')), ''),
    v_expense.year_month,
    format('%s %s', v_attempt.payment_amount, v_attempt.payment_currency),
    '信用卡固定支出'
  );

  v_cash_payload := jsonb_build_object(
    'external_source', 'aozora_school',
    'external_event_id', v_attempt.request_event_id,
    'external_reference_type', 'school_expense_records',
    'external_reference_id', v_expense.id,
    'request_type', 'expense_paid',
    'transaction_type', 'expense',
    'payment_route', 'fixed_credit_card',
    'expense_record_id', v_expense.id,
    'expense_date', v_expense.expense_date,
    'year_month', v_expense.year_month,
    'expense_category', v_expense.expense_category,
    'source_type', v_expense.source_type,
    'source_id', v_expense.source_id,
    'payee_name_snapshot', v_expense.payee_name_snapshot,
    'description', v_expense.description,
    'original_currency', v_attempt.original_currency,
    'original_amount', v_attempt.original_amount,
    'settlement_amount', v_attempt.payment_amount,
    'settlement_currency', v_attempt.payment_currency,
    'card_instrument_id', v_attempt.cash_card_instrument_id,
    'charge_date', v_attempt.charge_date,
    'suggested_fixed_month', v_attempt.suggested_fixed_month,
    'target_fixed_month', v_attempt.target_fixed_month,
    'funding_date', v_attempt.funding_date,
    'account_id', null,
    'funding_account_id', null,
    'attempt_no', v_attempt.attempt_no,
    'school_expense_status', v_expense.status,
    'school_attempt_payload_fingerprint', v_attempt.request_payload_fingerprint,
    'note', v_note
  );

  return query select
    v_expense.id, v_attempt.request_event_id, v_attempt.attempt_no,
    v_attempt.idempotency_key, v_attempt.request_type, v_attempt.payment_route,
    v_expense.status, v_expense.expense_category, v_expense.source_type,
    v_expense.source_id, v_expense.payee_name_snapshot, v_expense.year_month,
    v_expense.expense_date, v_expense.description, v_attempt.original_amount,
    v_attempt.original_currency, v_attempt.payment_amount, v_attempt.payment_currency,
    p_cash_user_id, v_attempt.cash_card_instrument_id, v_attempt.charge_date,
    v_attempt.suggested_fixed_month, v_attempt.target_fixed_month,
    v_attempt.funding_date, v_expense.cash_request_id, v_expense.cash_request_status,
    v_attempt.id, v_attempt.attempt_status, v_attempt.version,
    v_attempt.request_payload_fingerprint, v_cash_description, v_cash_payload,
    case when v_reuse_attempt
      then format('existing %s fixed Cash expense attempt reused', v_attempt.attempt_status)
      else 'fixed Cash expense attempt prepared'
    end;
end;
$function$;

commit;

-- ===========================================================================
-- 部署后验证
-- ===========================================================================
--
-- 一、结构
--   1. 函数仍为 SECURITY DEFINER、owner postgres
--   2. proacl 精确等于 {postgres=X/postgres,service_role=X/postgres}
--      （本次不改 ACL，CREATE OR REPLACE 不改参数列表应自动保留，仍需核对）
--   3. 与基线定义的 diff 只有新增的这一段，无其他差异
--
-- 二、新增保护生效（rollback-only fixture）
--   构造 expense_category 分别为 teacher_wage / software / advertising 的支出，
--   以固定卡路线调用本函数
--   → 期望 SCHOOL_EXPENSE_CASH_FIXED_CATEGORY_FORBIDDEN
--
-- 三、既有行为不变（rollback-only fixture）
--   1. expense_category = 'classroom' 的支出，其余条件齐备
--      → 期望与部署前完全一致（当前 Gate 未开，仍应先报
--        SCHOOL_CASH_FIXED_CREDIT_CARD_ROUTE_DISABLED）
--   2. Gate 未开时，无论什么分类都应先报 ROUTE_DISABLED，
--      而不是 CATEGORY_FORBIDDEN —— 证明检查顺序未被打乱
--   3. 已作废支出仍报 SCHOOL_EXPENSE_CASH_REVERSED_FORBIDDEN，
--      而不是 CATEGORY_FORBIDDEN —— 证明新检查确实在 reversed 之后
--   4. 不存在的支出仍报 SCHOOL_EXPENSE_RECORD_NOT_FOUND
--   5. 即时账户路线（本函数不参与）完全不受影响
--
-- 四、不受影响
--   1. school_request_cash_expense_payment_confirmation_v2（即时路线）未改动
--   2. Cash 侧任何对象未改动
--   3. 两个 Gate 状态不变
--
-- ===========================================================================
