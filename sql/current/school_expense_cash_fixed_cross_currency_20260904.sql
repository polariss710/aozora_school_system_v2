-- School 侧支持跨币种固定信用卡请求 —— 工行卡（JPY 消费 / CNY 结算）
--
-- 日期：2026-09-04
-- 配套：Cash 侧已于 2026-09-04 09:35 JST 部署
--       （home_account_book `supabase-update-20260903-fixed-request-cross-currency-atomic.sql`）
--
-- 基线（均取自生产只读导出，归档于 ~/aozora-security-20260827/cash-baseline/）：
--
--   school_request_cash_fixed_expense_payment_confirmation_v2
--     prosrc_md5      3a0fb26fe42a33ed4f6c4148a603d9a1
--     导出            2026-09-04 09:21:28 JST
--     文件            ...-production-20260904-0921.sql（SHA-256 6f30caef…）
--
--   school_expense_cash_attempts_route_contract_check
--     canonical md5   d3c9df090b4ed7ab7828c412f3205c7e
--     导出            2026-09-04 09:52:56 JST
--
-- ⚠️ **不要使用 ...-production-20260902.sql**。那份导出于 09-02 11:06，
--    而分类限制 d4e874f 提交于 11:21，里面没有 classroom 检查。
--    照它改一遍会把那条业务约束从生产里静默删掉。见 home_account_book
--    docs/lessons.md **E8**。
--
-- ===========================================================================
-- 为什么是一个事务
-- ===========================================================================
--
-- 约束与 writer 必须同轮改。放开约束而不改 RPC，跨币种仍写不进去；改 RPC 而不
-- 放开约束，RPC 一写 original ≠ payment 就 23514。**先改任一边都是缺陷**——
-- 这正是 Cash 侧首版被驳回的 P1-1（见 home_account_book docs/lessons.md E6）。
--
-- ===========================================================================
-- 为什么必须 DROP + CREATE 而不是 CREATE OR REPLACE
-- ===========================================================================
--
-- 本次给 prepare RPC 加两个参数。**加参数不是 replace，是新建重载**——
-- CREATE OR REPLACE 只在签名完全一致时替换，否则生产里会同时存在 15 参数与
-- 17 参数两个版本，PostgREST 按名解析可能歧义，且旧版会继续被调用。
--
-- 代价与必须做的补偿：
--
--   1. **DROP 会丢掉 ACL。** 目标 ACL 是 {postgres=X/postgres,service_role=X/postgres}，
--      而 Supabase 的 default privileges 会给新建函数自动授予
--      anon / authenticated / service_role 三个角色。因此建完必须**先全撤再单授**，
--      照抄 home_account_book docs/lessons.md **A3** 的「service_role 专用」模板。
--      本文件末尾的验证第二节要求逐字复核 proacl。
--   2. DROP 期间对该函数取锁，并发调用会阻塞。事务很短，且提交路线本就是
--      人工触发的低频操作，可接受。
--
-- ===========================================================================
-- 新参数的语义（业务模型扩展，需业务负责人批准后方可执行）
-- ===========================================================================
--
--   p_payment_amount   numeric  default null   结算币种下的金额
--   p_payment_currency text     default null   结算币种，JPY 或 CNY
--
-- 权威来源：用户手工输入（工行账单上印的人民币数字）。
-- **不引入汇率**：原币与结算额都是已知事实，从两者反推的汇率没有业务用途，
-- 多一个可写字段只会多一个权威冲突。
--
-- **不传时 settlement = original**，即与当前已部署行为逐字相同。
--
--   这是有意选择的「甲案」。业务负责人 2026-09-04 确认。
--   备选的「必填」会要求 Edge Function 与本 SQL 同刻切换，而两者是独立部署、
--   做不到原子，中间必然有一段提交全挂；备选的「建 v3」无窗口但要多维护一个
--   15 参数函数体。
--
--   这个默认**不是在推导新的业务事实**，而是原样保留今天的行为：现有 Edge 不传
--   金额，今天的函数就是把 v_expense.amount 同时写进 original 与 payment 两组列。
--   唯一危险场景——CNY 卡漏传金额——是**失败关闭**的：settlement 会落成 JPY，
--   而 Cash 侧创建器有 `v_card.settlement_currency is distinct from v_currency`
--   → HOME_FIXED_REQUEST_CARD_INVALID，写不进去。
--
-- 同币种时强制两个金额相等（见函数内 v_payment_* 校验段）：与 Cash 侧
-- home_external_requests_original_amount_contract_check 的同一条不变式对齐。
--
-- ===========================================================================
-- attempt 的四列是冻结的，所以新建与复用必须分开处理
-- ===========================================================================
--
-- 生产触发器 school_guard_expense_cash_attempt_v1（BEFORE INSERT/UPDATE/DELETE）
-- 的 UPDATE 可变字段白名单**不含** original_amount / payment_amount /
-- original_currency / payment_currency，改任一列报
-- 55000 / SCHOOL_EXPENSE_CASH_ATTEMPT_IDENTITY_IMMUTABLE。
--
-- 而现有 prepare 的复用分支**本来就不 UPDATE attempt**，只做一致性核对后返回。
-- 因此本次改动严格保持这个形状：
--
--   新建 attempt → 原币取支出记录，结算取入参（或默认等于原币）
--   复用 attempt → 只核对入参与已冻结的事实一致，不一致报
--                  SCHOOL_EXPENSE_CASH_FIXED_PREPARE_PAYLOAD_CONFLICT
--
-- 含义：**同一个 attempt 一旦建立，结算金额就改不了。** 用户填错人民币金额时
-- 的补救路径是走 Cash 侧「拒绝」再重新提交（会生成新的 attempt_no），
-- 而不是原地修改。这与 Phase D 之后确立的「跨库事实一经落库即冻结」一致。
--
-- ===========================================================================
-- 回滚
-- ===========================================================================
--
--   1. DROP 本文件建的 17 参数函数
--   2. 从 ~/aozora-security-20260827/cash-baseline/
--      school_request_cash_fixed_expense_payment_confirmation_v2-production-20260904-0921.sql
--      恢复 15 参数版本（该文件本身就是可执行的 CREATE OR REPLACE）
--   3. 恢复 ACL：revoke all from public, anon, authenticated, service_role;
--                grant execute to service_role;
--   4. 恢复约束：
--        alter table public.school_expense_cash_attempts
--          drop constraint school_expense_cash_attempts_route_contract_check;
--      再按 canonical md5 d3c9df090b4ed7ab7828c412f3205c7e 对应的定义重建
--      （源码形态见 sql/current/school_expense_cash_fixed_entry_phase3c3b_20260819.sql:169-210）
--
--   **顺序不能反**：先恢复函数再恢复约束，否则 17 参数版本写出的跨币种 attempt
--   会让约束重建失败。回滚前须确认表内没有 original ≠ payment 的行。
--
-- ===========================================================================

\set ON_ERROR_STOP on

begin;

-- ---------------------------------------------------------------------------
-- 0. 生产基线断言（失败关闭）
--
-- 全部基于 canonical 形式（pg_get_constraintdef 不传 pretty、md5(prosrc)）。
-- 见 home_account_book docs/lessons.md E7：指纹要连计算表达式一起记。
-- ---------------------------------------------------------------------------

do $$
declare
  v_actual text;
  v_count integer;
begin
  -- 0a. prepare RPC 有且仅有一个重载，且正文与基线一致
  select count(*) into v_count
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'school_request_cash_fixed_expense_payment_confirmation_v2';
  if v_count <> 1 then
    raise exception 'ABORT: prepare RPC 在生产中有 % 个重载，本文件假定唯一', v_count;
  end if;

  select md5(p.prosrc) into v_actual
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'school_request_cash_fixed_expense_payment_confirmation_v2';
  if v_actual is distinct from '3a0fb26fe42a33ed4f6c4148a603d9a1' then
    raise exception 'ABORT: prepare RPC 已漂移，期望 3a0fb26fe42a33ed4f6c4148a603d9a1，实际 %', v_actual;
  end if;

  -- 0b. 待改约束与基线一致
  select md5(pg_get_constraintdef(oid)) into v_actual
  from pg_constraint
  where conrelid = 'public.school_expense_cash_attempts'::regclass
    and conname = 'school_expense_cash_attempts_route_contract_check';
  if v_actual is distinct from 'd3c9df090b4ed7ab7828c412f3205c7e' then
    raise exception 'ABORT: route_contract_check 已漂移，实际 md5 %', coalesce(v_actual, '(不存在)');
  end if;

  -- 0c. 四列仍为 NOT NULL。放开 route 约束的两条等值条件之后，
  --     「非空」这层保护改由列定义单独承担，必须确认它还在。
  select count(*) into v_count
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'school_expense_cash_attempts'
    and column_name in ('original_amount', 'original_currency', 'payment_amount', 'payment_currency')
    and is_nullable = 'NO';
  if v_count <> 4 then
    raise exception 'ABORT: 四个金额/币种列中只有 % 个仍是 NOT NULL', v_count;
  end if;

  -- 0d. 冻结触发器仍在且启用。本文件的「新建/复用分开处理」完全建立在它之上。
  if not exists (
    select 1 from pg_trigger t
    where t.tgrelid = 'public.school_expense_cash_attempts'::regclass
      and t.tgname = 'school_guard_expense_cash_attempt_v1'
      and t.tgenabled <> 'D'
  ) then
    raise exception 'ABORT: school_guard_expense_cash_attempt_v1 不存在或已禁用';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. route contract 约束：去掉 fixed 分支的两条等值要求
--
-- 与基线的差异**仅两行**：
--     and original_amount = payment_amount        ← 删
--     and original_currency = payment_currency    ← 删
--
-- 其余逐字未改：immediate 分支全部十条、fixed 分支的字段互斥规则、
-- 四种 attempt_status 的状态契约。
--
-- 被删掉的这两条原本兼职做了「两列都非空」的保证，现在改由列的 NOT NULL 承担
-- （已由 0c 断言）；「金额为正、币种限 JPY/CNY」另有独立 CHECK，不受影响。
-- ---------------------------------------------------------------------------

alter table public.school_expense_cash_attempts
  drop constraint school_expense_cash_attempts_route_contract_check;

alter table public.school_expense_cash_attempts
  add constraint school_expense_cash_attempts_route_contract_check check (
    (
      payment_route = 'immediate_account'
      and cash_funding_account_id is not null
      and cash_fixed_projection_id is null
      and cash_fixed_item_id is null
      and cash_card_instrument_id is null
      and suggested_fixed_month is null
      and target_fixed_month is null
      and funding_date is null
      and funded_at is null
      and attempt_status not in ('approved_fixed', 'funded_fixed')
    )
    or
    (
      payment_route = 'fixed_credit_card'
      and cash_funding_account_id is null
      and cash_card_instrument_id is not null
      and suggested_fixed_month is not null
      and target_fixed_month is not null
      and funding_date is not null
      and (
        attempt_status in ('prepared', 'submitted', 'rejected')
        or (
          attempt_status = 'approved_fixed'
          and cash_fixed_projection_id is not null
          and cash_fixed_item_id is not null
          and cash_transaction_id is null
        )
        or (
          attempt_status = 'funded_fixed'
          and cash_fixed_projection_id is not null
          and cash_fixed_item_id is not null
          and cash_transaction_id is not null
          and funded_at is not null
        )
        or attempt_status = 'corrected'
      )
    )
  );

-- ---------------------------------------------------------------------------
-- 2. prepare RPC：DROP 旧的 15 参数版本，建 17 参数版本
--
-- 与基线的差异共 6 处：
--   ① 签名末尾追加 p_payment_amount / p_payment_currency，均 default null
--   ② 新增两个局部变量
--   ③ 载入支出记录后解析并校验结算金额（不传则等于原币）
--   ④ 复用分支的四处比对改为对照解析后的结算值
--   ⑤ 新建 attempt 的 insert：payment 两列取解析值
--   ⑥ 回写支出记录：cash_payment 两列取解析值
--
-- 其余逐字未改：两道 Gate、入参校验、外部身份校验、行锁读取、reversed 检查、
-- **classroom 分类检查**、source_type 分支、状态冲突检查、复用判定、
-- idempotency key 构造、cash_description 拼装、payload 构造、返回段。
--
-- ⚠️ 分类检查（下方标注「d4e874f」那段）**必须原样保留**。它 2026-09-02 11:21
--    才加进生产，而 09-02 11:06 那份归档里没有它——照那份改会静默删掉它。
-- ---------------------------------------------------------------------------

drop function public.school_request_cash_fixed_expense_payment_confirmation_v2(
  uuid, uuid, uuid, date, date, date, date, text, text, text, uuid, text, text, uuid, text
);

create function public.school_request_cash_fixed_expense_payment_confirmation_v2(
  p_expense_record_id uuid,
  p_cash_user_id uuid,
  p_card_instrument_id uuid,
  p_charge_date date,
  p_suggested_fixed_month date,
  p_target_fixed_month date,
  p_funding_date date,
  p_note text default null::text,
  p_external_source text default 'aozora_school'::text,
  p_external_reference_type text default 'school_expense_records'::text,
  p_external_reference_id uuid default null::uuid,
  p_request_type text default 'expense_paid'::text,
  p_transaction_type text default 'expense'::text,
  p_expected_request_event_id uuid default null::uuid,
  p_expected_idempotency_key text default null::text,
  -- ① 新增：结算币种下的金额。不传则等于原币，即与改动前行为逐字相同。
  p_payment_amount numeric default null::numeric,
  p_payment_currency text default null::text
)
returns table(
  expense_id uuid, request_event_id uuid, attempt_no integer, idempotency_key text,
  request_type text, payment_route text, expense_status text, expense_category text,
  source_type text, source_id uuid, payee_name_snapshot text, year_month text,
  expense_date date, description text, original_amount numeric, original_currency text,
  settlement_amount numeric, settlement_currency text, cash_user_id uuid,
  card_instrument_id uuid, charge_date date, suggested_fixed_month date,
  target_fixed_month date, funding_date date, cash_request_id uuid,
  cash_request_status text, attempt_id uuid, attempt_status text, attempt_version integer,
  request_payload_fingerprint text, cash_description text, cash_payload_snapshot jsonb,
  message text
)
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
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
  -- ② 结算币种下的金额与币种。解析在载入支出记录之后。
  v_payment_amount numeric;
  v_payment_currency text;
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

  -- ③ 解析结算金额。
  --
  -- 不传两个新参数时，结算等于原币——这是当前已部署版本的行为，不是新推导的
  -- 业务事实。见文件头「新参数的语义」。
  --
  -- 只传其中一个视为调用方出错，直接拒绝：跨币种必须两个都给，同币种两个都不给
  -- 即可。这样避免出现「金额给了 CNY 但币种仍是 JPY」这类半吊子状态。
  if (p_payment_amount is null) is distinct from (nullif(trim(coalesce(p_payment_currency, '')), '') is null) then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_FIXED_SETTLEMENT_PAIR_REQUIRED';
  end if;
  v_payment_amount := coalesce(p_payment_amount, v_expense.amount);
  v_payment_currency := upper(trim(coalesce(nullif(trim(coalesce(p_payment_currency, '')), ''), v_expense.currency)));
  if v_payment_currency not in ('JPY', 'CNY') or coalesce(v_payment_amount, 0) <= 0 then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_FIXED_SETTLEMENT_INVALID';
  end if;
  -- 同币种时两个金额必须相等。与 Cash 侧
  -- home_external_requests_original_amount_contract_check 的同一条不变式对齐——
  -- 同币种下 original ≠ settlement 在业务上没有含义，只会是 bug 的产物。
  if v_payment_currency = v_expense.currency and v_payment_amount is distinct from v_expense.amount then
    raise exception using errcode = '22023', message = 'SCHOOL_EXPENSE_CASH_FIXED_SETTLEMENT_SAME_CURRENCY_MISMATCH';
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
    -- ④ 复用分支只核对，不修改。attempt 的四个金额/币种列被
    --    school_guard_expense_cash_attempt_v1 冻结，原地改会报
    --    SCHOOL_EXPENSE_CASH_ATTEMPT_IDENTITY_IMMUTABLE。
    --    所以填错结算金额的补救路径是 Cash 侧「拒绝」后重新提交（新 attempt_no），
    --    不是重新调用本函数改金额。
    if v_attempt.payment_route <> 'fixed_credit_card'
       or v_attempt.attempt_no is distinct from v_expense.cash_request_attempt_no
       or v_attempt.original_amount is distinct from v_expense.amount
       or v_attempt.original_currency is distinct from v_expense.currency
       or v_attempt.payment_amount is distinct from v_payment_amount
       or v_attempt.payment_currency is distinct from v_payment_currency
       or v_attempt.cash_funding_account_id is not null
       or v_attempt.cash_card_instrument_id is distinct from p_card_instrument_id
       or v_attempt.charge_date is distinct from p_charge_date
       or v_attempt.suggested_fixed_month is distinct from p_suggested_fixed_month
       or v_attempt.target_fixed_month is distinct from p_target_fixed_month
       or v_attempt.funding_date is distinct from p_funding_date
       or v_expense.cash_payment_amount is distinct from v_payment_amount
       or v_expense.cash_payment_currency is distinct from v_payment_currency
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

    -- ⑤ 原币取支出记录，结算取解析值。同币种时两者相等，与改动前逐字相同。
    insert into public.school_expense_cash_attempts(
      expense_id, attempt_no, payment_route, request_type, request_event_id,
      idempotency_key, cash_funding_account_id, cash_card_instrument_id,
      original_amount, original_currency, payment_amount, payment_currency,
      charge_date, suggested_fixed_month, target_fixed_month, funding_date,
      attempt_status, version
    ) values (
      v_expense.id, v_attempt_no, 'fixed_credit_card', 'expense_paid', v_event_id,
      v_idempotency_key, null, p_card_instrument_id,
      v_expense.amount, v_expense.currency, v_payment_amount, v_payment_currency,
      p_charge_date, p_suggested_fixed_month, p_target_fixed_month, p_funding_date,
      'prepared', 1
    ) returning * into v_attempt;

    -- ⑥ 回写支出记录的 cash_payment 两列同样取结算值
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

-- ---------------------------------------------------------------------------
-- 3. ACL —— DROP 丢掉了原 ACL，必须显式重建
--
-- 目标与部署前逐字相同：{postgres=X/postgres,service_role=X/postgres}
--
-- 照抄 home_account_book docs/lessons.md A3 的「service_role 专用」模板：
-- **先全撤再单授**。Supabase 的 default privileges 会给 postgres 新建的函数
-- 自动授予 anon / authenticated / service_role，只 revoke 一部分会留下入口。
-- A3 记着这个错在 2026-08-31 到 09-01 之间犯过三次。
-- ---------------------------------------------------------------------------

revoke all on function public.school_request_cash_fixed_expense_payment_confirmation_v2(
  uuid, uuid, uuid, date, date, date, date, text, text, text, uuid, text, text, uuid, text, numeric, text
) from public, anon, authenticated, service_role;

grant execute on function public.school_request_cash_fixed_expense_payment_confirmation_v2(
  uuid, uuid, uuid, date, date, date, date, text, text, text, uuid, text, text, uuid, text, numeric, text
) to service_role;

commit;

-- ===========================================================================
-- 部署后必须立刻做的一件事
-- ===========================================================================
--
--   notify pgrst, 'reload schema';
--
-- 函数签名变了，PostgREST 的 schema 缓存不刷新会继续按 15 参数解析，
-- Edge 调用可能报 PGRST202 / 找不到函数。**这一步不做，提交路线会直接挂。**
--
-- ===========================================================================
-- 部署后验证
-- ===========================================================================
--
-- 零、基线断言能证伪（E3）
--   rollback-only 构造漂移，确认第 0 步四条断言会失败：
--     a. 改一下 prepare RPC 的正文 → ABORT: prepare RPC 已漂移
--     b. 改一下 route_contract_check → ABORT: route_contract_check 已漂移
--     c. 把某一列改成可空 → ABORT: 四个金额/币种列中只有 3 个仍是 NOT NULL
--     d. disable school_guard_expense_cash_attempt_v1 → ABORT: … 不存在或已禁用
--
-- 一、逐行 diff（E2）
--   函数与 ~/aozora-security-20260827/cash-baseline/
--   school_request_cash_fixed_expense_payment_confirmation_v2-production-20260904-0921.sql
--   比，期望恰好 6 处功能改动（注释与换行重排另计）。**出现第 7 处即为转录错误。**
--
--   ⚠️ **单独确认 classroom 分类检查仍在部署后的 prosrc 里。**
--      这是本文件最高风险的回归项：那段 09-02 11:21 才进生产，而我手上一度只有
--      11:06 的归档。见 home_account_book docs/lessons.md E8。
--
--   约束：部署后 canonical `pg_get_constraintdef(oid)` 与部署前相比，
--   **恰好少了 `(original_amount = payment_amount)` 与
--   `(original_currency = payment_currency)` 两个合取项，其余逐字相同**。
--   部署前 canonical md5 = d3c9df090b4ed7ab7828c412f3205c7e。
--
-- 二、结构与权限（A3）
--   1. 该函数名下**有且仅有一个重载**，17 个参数
--   2. **proacl 精确等于 {postgres=X/postgres,service_role=X/postgres}**
--      —— 不要只查「有没有 anon」，三个角色任一残留都是权限边界变化
--   3. owner = postgres、prosecdef = true、
--      proconfig = {search_path=pg_catalog, public}
--   4. 四列仍 NOT NULL；金额为正、币种限 JPY/CNY 的独立 CHECK 未变
--   5. school_guard_expense_cash_attempt_v1 的 tgname/tgtype/tgenabled 未变
--   6. 表上其余 12 条 CHECK、FK、索引、RLS/policy 未变
--
-- 三、向后兼容 —— 不传新参数时逐字不变（比跨币种跑通更重要）
--   rollback-only，用今天 Edge 的**原样 15 个具名参数**调用：
--     1. 新建 attempt：original 与 payment 四列全部等于支出记录的金额/币种
--     2. 支出记录 cash_payment_amount / cash_payment_currency 同上
--     3. request_payload_fingerprint（GENERATED ALWAYS）与改动前对同一输入相同
--     4. 返回的 33 列、cash_description、cash_payload_snapshot 逐字段相同
--   **任何一项不同都说明向后兼容被破坏。**
--
-- 四、该失败的仍然失败（E4，rollback-only，错误码精确匹配）
--   新增：
--     a. 只传 p_payment_amount 不传币种 → SCHOOL_EXPENSE_CASH_FIXED_SETTLEMENT_PAIR_REQUIRED
--     b. 只传 p_payment_currency 不传金额 → 同上
--     c. p_payment_currency = 'USD'        → SCHOOL_EXPENSE_CASH_FIXED_SETTLEMENT_INVALID
--     d. p_payment_amount = 0 或负         → 同上
--     e. 同币种但金额与支出记录不等        → SCHOOL_EXPENSE_CASH_FIXED_SETTLEMENT_SAME_CURRENCY_MISMATCH
--     f. **复用 attempt 时改结算金额**     → SCHOOL_EXPENSE_CASH_FIXED_PREPARE_PAYLOAD_CONFLICT
--        ← 这条最重要：它证明「一旦落库就改不了」，也证明本文件没有试图去写那四个
--          被 school_guard_expense_cash_attempt_v1 冻结的列
--   未改动的（必须全部照旧）：
--     g. 非 classroom 分类 → SCHOOL_EXPENSE_CASH_FIXED_CATEGORY_FORBIDDEN
--        ← **必验**，理由见第一节
--     h. 两道 Gate 任一关闭 → 各自的 DISABLED
--     i. reversed 支出 → SCHOOL_EXPENSE_CASH_REVERSED_FORBIDDEN
--     j. 已 paid / 已有 approved 请求 → SCHOOL_EXPENSE_CASH_ACTIVE_OR_COMPLETED_REQUEST_EXISTS
--     k. source_type 非 manual_cash / teacher_wage → P0_EXPENSE_CASH_REQUEST_SOURCE_NOT_ALLOWED
--     l. 月份非月首 / target ≠ suggested → SCHOOL_EXPENSE_CASH_FIXED_SCHEDULE_INVALID
--
-- 五、跨币种形态（rollback-only）
--   classroom 的 JPY 支出 166,100，传 p_payment_amount=8000 / p_payment_currency='CNY'：
--     1. attempt：original JPY 166100，payment CNY 8000
--     2. 支出记录：cash_payment_amount=8000、cash_payment_currency='CNY'
--     3. payload_snapshot：original_amount 166100 / original_currency JPY /
--        settlement_amount 8000 / settlement_currency CNY
--     4. **request_payload_fingerprint 与同一支出的同币种 attempt 不同**
--        —— 指纹链覆盖了这四个字段，这一条能证明它确实生效
--     5. cash_description 里的金额片段是「8000 CNY」
--
-- 六、跨库连通（可选，最后做）
--   把第五节的 payload 喂给 Cash 的 home_create_external_fixed_transaction_request
--   （rollback-only），确认它接受跨币种快照。Cash 侧已于 09-04 部署支持。
--
-- ===========================================================================
-- 我没能验证的假设（交审时的攻击点）
-- ===========================================================================
--
-- 1. **DROP + CREATE 期间的并发。** 事务内 DROP 会对该函数取锁，并发调用阻塞或
--    失败。提交路线是人工低频操作，且 Gate 开着但当前没有 pending 请求，
--    风险应该很低——但我没有实测锁的实际行为。
--
-- 2. **PostgREST schema 缓存。** 我知道要 notify，但不知道这个 Supabase 项目是否
--    有别的缓存层（比如 Edge Function 侧的连接池预处理语句）。
--    部署后应实际调一次 Edge 的 preview / list action 确认没坏。
--
-- 3. **谁还在读 cash_payment_amount。** 该列以前恒等于支出记录金额，现在跨币种时
--    不再相等。年度页、支出列表、撤销 RPC 是否有地方假定了相等，我没有全查。
--    **这一条最可能藏问题**，请用 catalog + 仓库 grep 双向查一遍。
--
-- 4. **request_payload_fingerprint 的生成列**在跨币种下是否正常重算。
--    审核上一轮确认过指纹函数覆盖 original/settlement 四字段，
--    但那是读代码，没有实际造过一条跨币种 attempt。第五节第 4 项就是验这个。
--
-- 5. **约束 drop + re-add 会重新校验全表。** 新约束比旧的弱，现有行必然通过，
--    但表有多少行、re-validate 要多久，我没查。若行数很大需要评估锁时间。
--
-- 6. Edge 与前端尚未改动，本文件部署后**跨币种仍然无法从界面发起**——
--    前端的 cashCardUnavailableReason() 仍把 CNY 卡置灰
--    （js/pages/expense-detail-page.js:1103-1128）。这是预期的，下一步处理。
--
-- ===========================================================================

