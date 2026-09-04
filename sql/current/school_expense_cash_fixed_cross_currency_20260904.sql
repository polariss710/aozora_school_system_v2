-- ###########################################################################
-- ##  2026-09-04 第二版：已补齐回写链，覆盖首轮驳回的 P1-1 / P1-2
-- ##
-- ##  首版只改了提交方向（约束 + prepare RPC），完全没碰回写方向，被审核以两条
-- ##  P1 驳回。教训已记为 home_account_book docs/lessons.md **E9**：
-- ##  跨库 saga 要双向 trace，回写链和提交链一样长。
-- ##
-- ##  本版把下面这条链一并改掉，六个对象放在同一个事务里：
-- ##
-- ##    school_mark_cash_fixed_expense_request_submitted_v2
-- ##    school_mark_cash_fixed_expense_rejected_v2
-- ##      → school_apply_expense_cash_fixed_attempt_transition_v2
-- ##        → school_apply_expense_cash_fixed_callback_v3
-- ##
-- ##  P1-1 attempt_transition_v2 把结算金额/币种**同时**传给 callback 的 original
-- ##       与 settlement 两组槽位，跨币种时回调收到 original=8000 CNY 而 attempt
-- ##       存的是 original=166100 JPY → SCHOOL_EXPENSE_CASH_FIXED_PAYLOAD_CONFLICT。
-- ##       submitted 标不了、rejected 也回写不了。
-- ##  P1-2 callback_v3 的 approved 分支锁死三条：固定项币种必须 JPY、原币必须等于
-- ##       结算币、原币金额必须等于结算金额。**后果是 Cash 已批准而 School 无法
-- ##       确认，而 Cash 批准不可逆**——正好推进到最不该到达的状态。
-- ##
-- ##  本版覆盖的六个对象（同一事务）：
-- ##    1. school_expense_cash_attempts_route_contract_check   删两条等值
-- ##    2. school_request_cash_fixed_expense_payment_confirmation_v2  +2 参数
-- ##    3. school_apply_expense_cash_fixed_callback_v3         approved 分支放三条锁
-- ##    4. school_apply_expense_cash_fixed_attempt_transition_v2      +2 参数
-- ##    5. school_mark_cash_fixed_expense_request_submitted_v2        +2 参数
-- ##    6. school_mark_cash_fixed_expense_rejected_v2                 +2 参数
-- ##
-- ##  **school_mark_cash_fixed_expense_approved_v2 有意不改**：它是回写链的第五个
-- ##  入口、直接调 callback 不经过 transition，而且**签名里第 12/13 位本来就是
-- ##  p_original_amount / p_original_currency**，正文原样转发。原设计预见了批准
-- ##  证据要带原币，只是没预见 submitted/rejected 也要。本文件第 0 步断言它未漂移。
-- ###########################################################################

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
--   唯一危险场景——CNY 卡漏传金额——**对 Cash 是失败关闭的**：settlement 会落成
--   JPY，而 Cash 侧创建器有 `v_card.settlement_currency is distinct from v_currency`
--   → HOME_FIXED_REQUEST_CARD_INVALID，写不进去。
--
--   ⚠️ **但这个论证只覆盖 Cash，不覆盖 School**（审核 P2，2026-09-04）。
--   实际序列是：
--
--     1. School 先落库一个 JPY 的 prepared attempt
--     2. Cash 返回 CARD_INVALID，没有创建请求
--     3. 当前 Edge 直接返回失败，**不撤销 prepare**
--     4. 补齐 CNY 参数重试 → 被复用分支以 PREPARE_PAYLOAD_CONFLICT 拒绝
--     5. 没有 Cash 请求可以「拒绝后重提」，而 attempt 的金额币种卡字段又被
--        school_guard_expense_cash_attempt_v1 冻结
--
--   → **不会写出错误的 Cash 请求，但会留下一个走不通正常流程的 School attempt。**
--
--   修法（待定，与回写链一并处理）：在 prepare 落库**之前**校验卡币种与结算输入
--   一致。可行位置是 Edge——它在调 prepare 之前已经调过
--   home_get_school_fixed_card_schedule，而那个函数的返回里就带 settlement_currency
--   （supabase/functions/request-cash-expense-confirmation/index.ts:599-604）。
--   prepare RPC 自己做不到：卡在 Cash 库，School 侧看不见它的币种。
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
-- **整套回滚必须在一个事务里**，理由与部署相同：中间态会出现「约束已恢复但
-- writer 还是新版」或反过来，任一都比部署前更糟。
--
-- 回滚前先确认 `school_expense_cash_attempts` 里**没有 original ≠ payment 的行**。
-- 若已经产生过跨币种 attempt，恢复旧约束会失败，必须先处理数据——那属于历史数据
-- 修补，需另行批准，不在本回滚脚本范围内。
--
-- ```
-- begin;
--
-- -- 1. 先恢复四个新签名的函数（DROP 新的，CREATE 旧的），顺序：叶子 → 根
-- --    submitted / rejected 调 transition，transition 调 callback，
-- --    所以恢复方向与调用方向相反才不会中途出现引用不存在签名的状态。
--
-- --  1a. mark_submitted_v2：DROP 25 参数版 → 恢复 23 参数版
-- --      基线 ...school_mark_cash_fixed_expense_request_submitted_v2-production-20260904-1346.sql
-- --      ACL: revoke all from public, anon, authenticated, service_role;
-- --           grant execute to service_role;
-- --  1b. mark_rejected_v2：DROP 27 参数版 → 恢复 25 参数版
-- --      基线 ...school_mark_cash_fixed_expense_rejected_v2-production-20260904-1346.sql
-- --      ACL 同 1a
-- --  1c. attempt_transition_v2：DROP 28 参数版 → 恢复 26 参数版
-- --      基线 ...school_apply_expense_cash_fixed_attempt_transition_v2-production-20260904-1346.sql
-- --      **ACL：只 revoke，不 grant** —— 基线是 {postgres=X/postgres}
-- --  1d. prepare_..._v2：DROP 17 参数版 → 恢复 15 参数版
-- --      基线 ...-production-20260904-0921.sql
-- --      ACL 同 1a
--
-- -- 2. callback_v3：签名未变，直接 create or replace 回基线
-- --    基线 ...school_apply_expense_cash_fixed_callback_v3-production-20260904-1346.sql
-- --    **不要 DROP** —— 它没被 DROP 过，ACL 一直是 {postgres=X/postgres}，
-- --    多此一举地 DROP 反而要重建 ACL，多一个出错点。
--
-- -- 3. 最后恢复约束
-- alter table public.school_expense_cash_attempts
--   drop constraint school_expense_cash_attempts_route_contract_check;
-- -- 再按 canonical md5 d3c9df090b4ed7ab7828c412f3205c7e 对应的定义重建
-- -- （源码形态见 sql/current/school_expense_cash_fixed_entry_phase3c3b_20260819.sql:169-210）
--
-- commit;
-- ```
--
-- **顺序不能反**：函数全部恢复完再恢复约束。反过来的话，约束已经禁止跨币种，
-- 而新版 writer 还在，任何跨币种提交会以一个更难诊断的错误失败。
--
-- **回滚后同样要 `notify pgrst, 'reload schema';`** —— 四个签名又变回去了。
--
-- 五份基线文件的 prosrc md5 见本文件第 0 步断言，回滚后应逐个比对复原。
-- mark_approved_v2 本文件未改，回滚也不碰。
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

  -- 0a2. 回写链五个函数的正文与基线一致。
  --      前四个本文件要改；approved 那个**有意不改**，断言它未漂移是因为本文件
  --      的正确性依赖「它已经在传原币」这个事实。
  for v_actual in
    select unnest(array[
      'school_apply_expense_cash_fixed_callback_v3|b340e9ab01ed2782338e291fed3493c6',
      'school_apply_expense_cash_fixed_attempt_transition_v2|52e2cd3118dd83a46e742f6aca88fc0d',
      'school_mark_cash_fixed_expense_request_submitted_v2|a68166c95e6e4393812dabb3ef539db8',
      'school_mark_cash_fixed_expense_rejected_v2|6956666215bd73de86d370cc623d6cae',
      'school_mark_cash_fixed_expense_approved_v2|2ef9bd847a521737bea7a8cf5100049a'
    ])
  loop
    declare
      v_name text := split_part(v_actual, '|', 1);
      v_expected text := split_part(v_actual, '|', 2);
      v_found text;
      v_overloads integer;
    begin
      select count(*) into v_overloads
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = v_name;
      if v_overloads <> 1 then
        raise exception 'ABORT: % 有 % 个重载，本文件假定唯一', v_name, v_overloads;
      end if;
      select md5(p.prosrc) into v_found
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = v_name;
      if v_found is distinct from v_expected then
        raise exception 'ABORT: % 已漂移，期望 %，实际 %', v_name, v_expected, v_found;
      end if;
    end;
  end loop;

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
-- 与基线的差异共 5 处：
--   ① 签名末尾追加 p_payment_amount / p_payment_currency，均 default null
--   ② 新增两个局部变量
--   ③ 载入支出记录后解析并校验结算金额（不传则等于原币）
--   ④ 复用分支的四处比对改为对照解析后的结算值
--   ⑤ 新建 attempt 的 insert：payment 两列取解析值
--
--   订正（审核 2026-09-04）：初稿写「6 处」，把「回写支出记录的 cash_payment 两列」
--   也算了进去。**那一处其实没有功能变化**——生产本来就取 v_attempt.payment_*，
--   我这版也是，逐字相同。多报一处改动会让审核去找一个不存在的差异。
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

-- ---------------------------------------------------------------------------
-- 4. 回写核心 callback_v3：approved 分支放开三条锁
--
-- **签名逐字未变**，所以用 create or replace，不需要 DROP，ACL 自动保留
-- （postgres-only）。
--
-- 与基线的差异恰好 3 处，全部在 approved 分支：
--   ① p_fixed_item_currency is distinct from 'JPY'
--        → is distinct from v_currency
--      Cash 侧的固定项现在按**结算币种**创建（工行卡 CNY、西武卡 JPY），
--      写死 JPY 会让所有 CNY 批准证据被拒。
--   ② 删 v_original_currency is distinct from v_currency      ← 跨币种禁令本身
--   ③ 删 p_original_amount is distinct from p_settlement_amount
--
-- **p_fixed_item_amount is distinct from p_settlement_amount 要留着**——
-- 固定项金额本来就该等于结算额，这条不是跨币种障碍。
--
-- 公共校验段（第 82-97 行那块）**一行不改**：它本来就分别核对 original 与
-- payment，不要求两组相等，天生支持跨币种。原币的合法性也由它保证——
-- v_attempt.original_amount 是 NOT NULL 列，传 NULL 或 0 都会在这里
-- PAYLOAD_CONFLICT，所以不需要在 EVIDENCE_REQUIRED 段额外加检查。
--
-- 其余逐字未改：Gate、action 校验、身份契约、状态契约、行锁、指纹重算、
-- submitted/rejected 两个分支的全部转移规则、幂等与 prepared 恢复、返回段。
-- ---------------------------------------------------------------------------

create or replace function public.school_apply_expense_cash_fixed_callback_v3(
  p_action text, p_expense_record_id uuid, p_cash_request_id uuid, p_cash_request_status text,
  p_payment_route text, p_external_source text, p_request_event_id uuid, p_idempotency_key text,
  p_external_reference_type text, p_external_reference_id uuid, p_request_type text,
  p_transaction_type text, p_original_amount numeric, p_original_currency text,
  p_settlement_amount numeric, p_settlement_currency text, p_card_instrument_id uuid,
  p_charge_date date, p_suggested_fixed_month date, p_target_fixed_month date,
  p_funding_date date, p_account_id uuid, p_funding_account_id uuid,
  p_request_payload_fingerprint text,
  p_cash_transaction_id uuid default null::uuid,
  p_fixed_projection_id uuid default null::uuid,
  p_projection_status text default null::text,
  p_projection_version integer default null::integer,
  p_projection_funding_status text default null::text,
  p_projection_funding_channel_id uuid default null::uuid,
  p_projection_funding_transaction_id uuid default null::uuid,
  p_fixed_item_id uuid default null::uuid,
  p_fixed_item_template_id uuid default null::uuid,
  p_fixed_item_scope text default null::text,
  p_fixed_item_currency text default null::text,
  p_fixed_item_direction text default null::text,
  p_fixed_item_amount numeric default null::numeric,
  p_fixed_item_month_key text default null::text,
  p_fixed_item_due_date date default null::date,
  p_fixed_item_payment_group text default null::text,
  p_fixed_item_status text default null::text,
  p_fixed_item_account_id uuid default null::uuid,
  p_fixed_item_linked_jpy_transaction_id uuid default null::uuid,
  p_fixed_item_linked_cny_transaction_id uuid default null::uuid,
  p_approved_actor uuid default null::uuid,
  p_result_at timestamp with time zone default null::timestamp with time zone,
  p_rejected_reason text default null::text
)
returns table(expense_id uuid, expense_status text, cash_request_id uuid, cash_request_status text, cash_transaction_id uuid, fixed_projection_id uuid, fixed_item_id uuid, attempt_id uuid, attempt_status text, attempt_version integer, callback_recovered_from_prepared boolean, idempotent boolean, message text)
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_action text := lower(nullif(trim(coalesce(p_action,'')),''));
  v_status text := lower(nullif(trim(coalesce(p_cash_request_status,'')),''));
  v_original_currency text := upper(nullif(trim(coalesce(p_original_currency,'')),''));
  v_currency text := upper(nullif(trim(coalesce(p_settlement_currency,'')),''));
  v_reason text := nullif(trim(coalesce(p_rejected_reason,'')),'');
  v_now timestamptz := coalesce(p_result_at,statement_timestamp());
  v_expense public.school_expense_records%rowtype;
  v_attempt public.school_expense_cash_attempts%rowtype;
  v_expected_fingerprint text;
  v_idempotent boolean := false;
  v_recovered boolean := false;
begin
  if not exists (
    select 1 from public.school_feature_gates g
    where g.feature_key='cash_expense_attempt_writer_v2_enabled' and g.state='enabled'
  ) then
    raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_ATTEMPT_V2_DISABLED';
  end if;
  -- The fixed Gate intentionally is not read here. It gates only new prepare.
  if v_action not in ('submitted','approved','rejected') then
    raise exception using errcode='22023', message='SCHOOL_EXPENSE_CASH_FIXED_ACTION_INVALID';
  end if;
  if p_expense_record_id is null or p_cash_request_id is null or p_request_event_id is null
     or p_external_reference_id is null or p_card_instrument_id is null
     or p_charge_date is null or p_suggested_fixed_month is null
     or p_target_fixed_month is null or p_funding_date is null
     or coalesce(p_settlement_amount,0)<=0 or nullif(trim(coalesce(p_idempotency_key,'')),'') is null
     or nullif(trim(coalesce(p_request_payload_fingerprint,'')),'') is null then
    raise exception using errcode='22023', message='SCHOOL_EXPENSE_CASH_FIXED_EVIDENCE_REQUIRED';
  end if;
  if p_payment_route is distinct from 'fixed_credit_card'
     or p_external_source is distinct from 'aozora_school'
     or p_external_reference_type is distinct from 'school_expense_records'
     or p_external_reference_id is distinct from p_expense_record_id
     or p_request_type is distinct from 'expense_paid'
     or p_transaction_type is distinct from 'expense'
     or p_account_id is not null or p_funding_account_id is not null
     or v_original_currency not in ('JPY','CNY') or v_currency not in ('JPY','CNY') then
    raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_EXTERNAL_IDENTITY_CONFLICT';
  end if;
  if (v_action='submitted' and v_status<>'pending')
     or (v_action='approved' and v_status<>'approved')
     or (v_action='rejected' and v_status<>'rejected') then
    raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_STATUS_CONFLICT';
  end if;

  select * into v_expense from public.school_expense_records e
  where e.id=p_expense_record_id and e.app_type='school' for update;
  if not found then raise exception using errcode='P0002', message='SCHOOL_EXPENSE_RECORD_NOT_FOUND'; end if;
  select * into v_attempt from public.school_expense_cash_attempts a
  where a.expense_id=p_expense_record_id and a.request_event_id=p_request_event_id for update;
  if not found then raise exception using errcode='P0002', message='SCHOOL_EXPENSE_CASH_ATTEMPT_NOT_FOUND'; end if;

  v_expected_fingerprint := public.school_expense_cash_attempt_payload_fingerprint_v3(
    v_attempt.expense_id,v_attempt.attempt_no,v_attempt.request_type,
    v_attempt.payment_route,v_attempt.request_event_id,v_attempt.idempotency_key,
    v_attempt.original_amount,v_attempt.original_currency,v_attempt.payment_amount,
    v_attempt.payment_currency,v_attempt.cash_funding_account_id,
    v_attempt.cash_card_instrument_id,v_attempt.charge_date,
    v_attempt.suggested_fixed_month,v_attempt.target_fixed_month,v_attempt.funding_date
  );
  if v_attempt.payment_route<>'fixed_credit_card'
     or v_attempt.idempotency_key is distinct from p_idempotency_key
     or v_attempt.original_amount is distinct from p_original_amount
     or v_attempt.original_currency is distinct from v_original_currency
     or v_attempt.payment_amount is distinct from p_settlement_amount
     or v_attempt.payment_currency is distinct from v_currency
     or v_attempt.cash_funding_account_id is not null
     or v_attempt.cash_card_instrument_id is distinct from p_card_instrument_id
     or v_attempt.charge_date is distinct from p_charge_date
     or v_attempt.suggested_fixed_month is distinct from p_suggested_fixed_month
     or v_attempt.target_fixed_month is distinct from p_target_fixed_month
     or v_attempt.funding_date is distinct from p_funding_date
     or v_attempt.request_payload_fingerprint is distinct from v_expected_fingerprint
     or v_attempt.request_payload_fingerprint is distinct from p_request_payload_fingerprint then
    raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_PAYLOAD_CONFLICT';
  end if;
  if v_attempt.cash_request_id is not null and v_attempt.cash_request_id is distinct from p_cash_request_id then
    raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_ATTEMPT_REQUEST_ID_CONFLICT';
  end if;
  if v_expense.cash_request_event_id is distinct from v_attempt.request_event_id
     or v_expense.cash_request_attempt_no is distinct from v_attempt.attempt_no
     or v_expense.cash_payment_amount is distinct from v_attempt.payment_amount
     or v_expense.cash_payment_currency is distinct from v_attempt.payment_currency then
    raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_ATTEMPT_LATEST_STATE_CONFLICT';
  end if;

  if v_action='submitted' then
    if p_cash_transaction_id is not null or p_fixed_projection_id is not null or p_fixed_item_id is not null then
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_DOWNSTREAM_FACT_FORBIDDEN';
    end if;
    if v_attempt.attempt_status='submitted' then
      if v_attempt.cash_request_id is distinct from p_cash_request_id
         or v_expense.cash_request_id is distinct from p_cash_request_id
         or v_expense.cash_request_status is distinct from 'pending' then
        raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_SUBMITTED_REPLAY_CONFLICT';
      end if;
      v_idempotent := true;
    elsif v_attempt.attempt_status<>'prepared' then
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_SUBMITTED_TRANSITION_FORBIDDEN';
    else
      if v_expense.cash_request_status is distinct from 'pending_cash_request'
         or v_expense.cash_request_id is not null or v_expense.cash_transaction_id is not null then
        raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_ATTEMPT_PREPARED_LATEST_STATE_CONFLICT';
      end if;
      update public.school_expense_cash_attempts a set
        cash_request_id=p_cash_request_id,submitted_at=v_now,attempt_status='submitted',
        latest_error_code=null,latest_error_message=null,version=a.version+1
      where a.id=v_attempt.id returning * into v_attempt;
      update public.school_expense_records e set
        cash_request_id=p_cash_request_id,cash_request_status='pending',
        cash_requested_at=coalesce(e.cash_requested_at,v_now),cash_error_message=null,updated_at=v_now
      where e.id=v_expense.id returning * into v_expense;
    end if;
  elsif v_action='approved' then
    -- ①②③ 三处改动全在这个 if 里，其余逐字未改
    if p_cash_transaction_id is not null or p_fixed_projection_id is null or p_fixed_item_id is null
       or p_projection_status is distinct from 'projected' or p_projection_version<>1
       or p_projection_funding_status is distinct from 'unfunded'
       or p_projection_funding_channel_id is null
       or p_projection_funding_transaction_id is not null
       or p_fixed_item_template_id is not null or p_fixed_item_scope is distinct from 'school'
       or p_fixed_item_currency is distinct from v_currency or p_fixed_item_direction is distinct from 'expense'
       or p_fixed_item_amount is distinct from p_settlement_amount
       or p_fixed_item_month_key is distinct from to_char(p_target_fixed_month,'YYYY-MM')
       or p_fixed_item_due_date is distinct from p_funding_date
       or nullif(trim(coalesce(p_fixed_item_payment_group,'')),'') is null
       or p_fixed_item_status is distinct from 'unpaid'
       or p_fixed_item_account_id is not null
       or p_fixed_item_linked_jpy_transaction_id is not null
       or p_fixed_item_linked_cny_transaction_id is not null
       or p_approved_actor is null or p_result_at is null
       or p_suggested_fixed_month is distinct from p_target_fixed_month
       or v_expense.expense_date is distinct from p_charge_date then
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_APPROVAL_EVIDENCE_CONFLICT';
    end if;
    if exists (
      select 1 from public.school_expense_cash_attempts a
      where a.id<>v_attempt.id and (
        a.cash_request_id=p_cash_request_id
        or a.cash_fixed_projection_id=p_fixed_projection_id
        or a.cash_fixed_item_id=p_fixed_item_id
      )
    ) then
      raise exception using errcode='23505', message='SCHOOL_EXPENSE_CASH_FIXED_APPROVAL_IDENTITY_ALREADY_USED';
    end if;
    if v_attempt.attempt_status='approved_fixed' then
      if v_attempt.cash_request_id is distinct from p_cash_request_id
         or v_attempt.cash_fixed_projection_id is distinct from p_fixed_projection_id
         or v_attempt.cash_fixed_item_id is distinct from p_fixed_item_id
         or v_attempt.approved_at is distinct from p_result_at
         or v_expense.status is distinct from 'paid'
         or v_expense.cash_request_status is distinct from 'approved'
         or v_expense.cash_request_id is distinct from p_cash_request_id
         or v_expense.cash_transaction_id is not null then
        raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_APPROVED_REPLAY_CONFLICT';
      end if;
      v_idempotent := true;
    elsif v_attempt.attempt_status='rejected' then
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_REJECTED_CANNOT_APPROVE';
    elsif v_attempt.attempt_status='prepared' then
      if v_expense.cash_request_status is distinct from 'pending_cash_request'
         or v_expense.cash_request_id is not null then
        raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_APPROVED_RECOVERY_EVIDENCE_REQUIRED';
      end if;
      v_recovered := true;
      update public.school_expense_cash_attempts a set
        cash_request_id=p_cash_request_id,submitted_at=v_now,
        cash_fixed_projection_id=p_fixed_projection_id,cash_fixed_item_id=p_fixed_item_id,
        approved_at=v_now,attempt_status='approved_fixed',
        callback_recovered_from_prepared=true,callback_recovered_at=v_now,
        callback_recovery_source='sync-cash-request-result-v2',
        latest_error_code=null,latest_error_message=null,version=a.version+2
      where a.id=v_attempt.id returning * into v_attempt;
    elsif v_attempt.attempt_status='submitted' then
      update public.school_expense_cash_attempts a set
        cash_fixed_projection_id=p_fixed_projection_id,cash_fixed_item_id=p_fixed_item_id,
        approved_at=v_now,attempt_status='approved_fixed',
        latest_error_code=null,latest_error_message=null,version=a.version+1
      where a.id=v_attempt.id returning * into v_attempt;
    else
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_APPROVED_TRANSITION_FORBIDDEN';
    end if;
    if not v_idempotent then
      update public.school_expense_records e set
        status='paid',cash_request_id=p_cash_request_id,cash_request_status='approved',
        cash_transaction_id=null,cash_synced_at=v_now,cash_error_message=null,updated_at=v_now
      where e.id=v_expense.id returning * into v_expense;
    end if;
  else
    if p_cash_transaction_id is not null or p_fixed_projection_id is not null or p_fixed_item_id is not null then
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_REJECTED_DOWNSTREAM_FACT_FORBIDDEN';
    end if;
    if v_attempt.attempt_status='rejected' then
      if v_attempt.cash_request_id is distinct from p_cash_request_id
         or v_attempt.rejected_at is distinct from p_result_at
         or v_expense.cash_request_status is distinct from 'rejected'
         or v_expense.cash_request_id is distinct from p_cash_request_id
         or v_expense.cash_transaction_id is not null then
        raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_REJECTED_REPLAY_CONFLICT';
      end if;
      v_idempotent := true;
    elsif v_attempt.attempt_status='approved_fixed' then
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_APPROVED_CANNOT_REJECT';
    elsif v_attempt.attempt_status='prepared' then
      if v_expense.cash_request_status is distinct from 'pending_cash_request'
         or v_expense.cash_request_id is not null then
        raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_REJECTED_RECOVERY_EVIDENCE_REQUIRED';
      end if;
      v_recovered := true;
      update public.school_expense_cash_attempts a set
        cash_request_id=p_cash_request_id,submitted_at=v_now,rejected_at=v_now,
        attempt_status='rejected',callback_recovered_from_prepared=true,
        callback_recovered_at=v_now,callback_recovery_source='sync-cash-request-result-v2',
        latest_error_code='CASH_REQUEST_REJECTED',
        latest_error_message=coalesce(v_reason,'Cash request rejected'),version=a.version+2
      where a.id=v_attempt.id returning * into v_attempt;
    elsif v_attempt.attempt_status='submitted' then
      update public.school_expense_cash_attempts a set
        rejected_at=v_now,attempt_status='rejected',latest_error_code='CASH_REQUEST_REJECTED',
        latest_error_message=coalesce(v_reason,'Cash request rejected'),version=a.version+1
      where a.id=v_attempt.id returning * into v_attempt;
    else
      raise exception using errcode='55000', message='SCHOOL_EXPENSE_CASH_FIXED_REJECTED_TRANSITION_FORBIDDEN';
    end if;
    if not v_idempotent then
      update public.school_expense_records e set
        cash_request_id=p_cash_request_id,cash_request_status='rejected',
        cash_synced_at=v_now,cash_error_message=coalesce(v_reason,'Cash request rejected'),updated_at=v_now
      where e.id=v_expense.id returning * into v_expense;
    end if;
  end if;

  return query select v_expense.id,v_expense.status,v_expense.cash_request_id,
    v_expense.cash_request_status,v_expense.cash_transaction_id,
    v_attempt.cash_fixed_projection_id,v_attempt.cash_fixed_item_id,v_attempt.id,
    v_attempt.attempt_status,v_attempt.version,v_attempt.callback_recovered_from_prepared,
    v_idempotent,case
      when v_idempotent then format('fixed Cash expense attempt %s callback already applied',v_action)
      when v_recovered then format('fixed Cash expense attempt recovered from prepared and marked %s',v_action)
      else format('fixed Cash expense attempt marked %s',v_action) end;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5. attempt_transition_v2 —— P1-1 的病灶所在
--
-- 基线正文里这一行把结算值塞进了 callback 的 original 与 settlement 两组槽位：
--
--     p_settlement_amount,p_settlement_currency,p_settlement_amount,p_settlement_currency,
--
-- 同币种时看不出问题（两组本来就相等），跨币种时 callback 收到的 original 与
-- attempt 存的对不上，直接 PAYLOAD_CONFLICT。
--
-- 加两个参数、按 default null 回落到结算值（与文件头「甲案」同一套理由：
-- 不传时行为与今天逐字相同，Edge 可以后跟）。
--
-- **ACL 是 postgres-only**，与另外两个 wrapper 不同，DROP 后不要照抄它们的模板。
-- ---------------------------------------------------------------------------

drop function public.school_apply_expense_cash_fixed_attempt_transition_v2(
  text, uuid, uuid, text, text, text, uuid, text, text, uuid, text, text, numeric, text,
  uuid, date, date, date, date, uuid, uuid, text, uuid, uuid, timestamptz, text
);

create function public.school_apply_expense_cash_fixed_attempt_transition_v2(
  p_action text, p_expense_record_id uuid, p_cash_request_id uuid, p_cash_request_status text,
  p_payment_route text, p_external_source text, p_request_event_id uuid, p_idempotency_key text,
  p_external_reference_type text, p_external_reference_id uuid, p_request_type text,
  p_transaction_type text, p_settlement_amount numeric, p_settlement_currency text,
  p_card_instrument_id uuid, p_charge_date date, p_suggested_fixed_month date,
  p_target_fixed_month date, p_funding_date date, p_account_id uuid, p_funding_account_id uuid,
  p_request_payload_fingerprint text,
  p_cash_transaction_id uuid default null::uuid,
  p_fixed_projection_id uuid default null::uuid,
  p_result_at timestamp with time zone default null::timestamp with time zone,
  p_rejected_reason text default null::text,
  p_original_amount numeric default null::numeric,
  p_original_currency text default null::text
)
returns table(expense_id uuid, expense_status text, cash_request_id uuid, cash_request_status text, attempt_id uuid, attempt_status text, attempt_version integer, idempotent boolean, message text)
language sql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select x.expense_id,x.expense_status,x.cash_request_id,x.cash_request_status,
    x.attempt_id,x.attempt_status,x.attempt_version,x.idempotent,x.message
  from public.school_apply_expense_cash_fixed_callback_v3(
    p_action,p_expense_record_id,p_cash_request_id,p_cash_request_status,
    p_payment_route,p_external_source,p_request_event_id,p_idempotency_key,
    p_external_reference_type,p_external_reference_id,p_request_type,p_transaction_type,
    coalesce(p_original_amount,p_settlement_amount),
    coalesce(p_original_currency,p_settlement_currency),
    p_settlement_amount,p_settlement_currency,
    p_card_instrument_id,p_charge_date,p_suggested_fixed_month,p_target_fixed_month,
    p_funding_date,p_account_id,p_funding_account_id,p_request_payload_fingerprint,
    p_cash_transaction_id,p_fixed_projection_id,
    null::text,null::integer,null::text,null::uuid,null::uuid,
    null::uuid,null::uuid,null::text,null::text,null::text,null::numeric,
    null::text,null::date,null::text,null::text,null::uuid,null::uuid,null::uuid,
    null::uuid,p_result_at,p_rejected_reason
  ) x;
$function$;

revoke all on function public.school_apply_expense_cash_fixed_attempt_transition_v2(
  text, uuid, uuid, text, text, text, uuid, text, text, uuid, text, text, numeric, text,
  uuid, date, date, date, date, uuid, uuid, text, uuid, uuid, timestamptz, text, numeric, text
) from public, anon, authenticated, service_role;

-- 不 grant 给任何角色：基线 ACL 就是 {postgres=X/postgres}，它只被两个
-- SECURITY DEFINER wrapper 以 postgres 身份调用（lessons A3「内部 helper」）。

-- ---------------------------------------------------------------------------
-- 6. mark_submitted_v2 / mark_rejected_v2
--
-- 两者都是薄转发层，各加两个参数并往下传。**ACL 带 service_role**（Edge 直接调）。
--
-- 注意：mark_approved_v2 不在这里——它签名里本来就有原币两参、直接调 callback，
-- 本文件不碰它。
-- ---------------------------------------------------------------------------

drop function public.school_mark_cash_fixed_expense_request_submitted_v2(
  uuid, uuid, text, text, text, uuid, text, text, uuid, text, text, numeric, text,
  uuid, date, date, date, date, uuid, uuid, text, uuid, uuid
);

create function public.school_mark_cash_fixed_expense_request_submitted_v2(
  p_expense_record_id uuid, p_cash_request_id uuid, p_cash_request_status text,
  p_payment_route text, p_external_source text, p_request_event_id uuid,
  p_idempotency_key text, p_external_reference_type text, p_external_reference_id uuid,
  p_request_type text, p_transaction_type text, p_settlement_amount numeric,
  p_settlement_currency text, p_card_instrument_id uuid, p_charge_date date,
  p_suggested_fixed_month date, p_target_fixed_month date, p_funding_date date,
  p_account_id uuid, p_funding_account_id uuid, p_request_payload_fingerprint text,
  p_cash_transaction_id uuid default null::uuid,
  p_fixed_projection_id uuid default null::uuid,
  p_original_amount numeric default null::numeric,
  p_original_currency text default null::text
)
returns table(expense_id uuid, expense_status text, cash_request_id uuid, cash_request_status text, attempt_id uuid, attempt_status text, attempt_version integer, idempotent boolean, message text)
language sql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select * from public.school_apply_expense_cash_fixed_attempt_transition_v2(
    'submitted', p_expense_record_id, p_cash_request_id, p_cash_request_status,
    p_payment_route, p_external_source, p_request_event_id, p_idempotency_key,
    p_external_reference_type, p_external_reference_id, p_request_type,
    p_transaction_type, p_settlement_amount, p_settlement_currency,
    p_card_instrument_id, p_charge_date, p_suggested_fixed_month,
    p_target_fixed_month, p_funding_date, p_account_id, p_funding_account_id,
    p_request_payload_fingerprint, p_cash_transaction_id,
    p_fixed_projection_id, null, null, p_original_amount, p_original_currency
  );
$function$;

revoke all on function public.school_mark_cash_fixed_expense_request_submitted_v2(
  uuid, uuid, text, text, text, uuid, text, text, uuid, text, text, numeric, text,
  uuid, date, date, date, date, uuid, uuid, text, uuid, uuid, numeric, text
) from public, anon, authenticated, service_role;

grant execute on function public.school_mark_cash_fixed_expense_request_submitted_v2(
  uuid, uuid, text, text, text, uuid, text, text, uuid, text, text, numeric, text,
  uuid, date, date, date, date, uuid, uuid, text, uuid, uuid, numeric, text
) to service_role;

drop function public.school_mark_cash_fixed_expense_rejected_v2(
  uuid, uuid, text, text, text, uuid, text, text, uuid, text, text, numeric, text,
  uuid, date, date, date, date, uuid, uuid, text, uuid, uuid, text, timestamptz
);

create function public.school_mark_cash_fixed_expense_rejected_v2(
  p_expense_record_id uuid, p_cash_request_id uuid, p_cash_request_status text,
  p_payment_route text, p_external_source text, p_request_event_id uuid,
  p_idempotency_key text, p_external_reference_type text, p_external_reference_id uuid,
  p_request_type text, p_transaction_type text, p_settlement_amount numeric,
  p_settlement_currency text, p_card_instrument_id uuid, p_charge_date date,
  p_suggested_fixed_month date, p_target_fixed_month date, p_funding_date date,
  p_account_id uuid, p_funding_account_id uuid, p_request_payload_fingerprint text,
  p_cash_transaction_id uuid default null::uuid,
  p_fixed_projection_id uuid default null::uuid,
  p_rejected_reason text default null::text,
  p_rejected_at timestamp with time zone default null::timestamp with time zone,
  p_original_amount numeric default null::numeric,
  p_original_currency text default null::text
)
returns table(expense_id uuid, expense_status text, cash_request_id uuid, cash_request_status text, attempt_id uuid, attempt_status text, attempt_version integer, idempotent boolean, message text)
language sql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
  select * from public.school_apply_expense_cash_fixed_attempt_transition_v2(
    'rejected', p_expense_record_id, p_cash_request_id, p_cash_request_status,
    p_payment_route, p_external_source, p_request_event_id, p_idempotency_key,
    p_external_reference_type, p_external_reference_id, p_request_type,
    p_transaction_type, p_settlement_amount, p_settlement_currency,
    p_card_instrument_id, p_charge_date, p_suggested_fixed_month,
    p_target_fixed_month, p_funding_date, p_account_id, p_funding_account_id,
    p_request_payload_fingerprint, p_cash_transaction_id,
    p_fixed_projection_id, p_rejected_at, p_rejected_reason,
    p_original_amount, p_original_currency
  );
$function$;

revoke all on function public.school_mark_cash_fixed_expense_rejected_v2(
  uuid, uuid, text, text, text, uuid, text, text, uuid, text, text, numeric, text,
  uuid, date, date, date, date, uuid, uuid, text, uuid, uuid, text, timestamptz, numeric, text
) from public, anon, authenticated, service_role;

grant execute on function public.school_mark_cash_fixed_expense_rejected_v2(
  uuid, uuid, text, text, text, uuid, text, text, uuid, text, text, numeric, text,
  uuid, date, date, date, date, uuid, uuid, text, uuid, uuid, text, timestamptz, numeric, text
) to service_role;

commit;

-- ===========================================================================
-- 部署后必须立刻做的一件事
-- ===========================================================================
--
--   notify pgrst, 'reload schema';
--
-- **本文件改了四个签名**（prepare 15→17、transition 26→28、submitted 23→25、
-- rejected 25→27；callback_v3 与 mark_approved_v2 的签名未变）。
-- 缓存不刷新，PostgREST 会继续按旧参数数解析，Edge 报 PGRST202 / 找不到函数。
-- **这一步不做，提交与回写两条路线都会挂。**
--
-- 刷新之后要**实际调一次改过签名的 RPC** 才算验证。跑 preview / list 证明不了
-- 什么——那两个 action 不经过本文件改动的任何一个函数。
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
-- 零之二、五个函数的基线断言也要能证伪
--   逐个改一下 callback_v3 / transition / submitted / rejected / **approved** 的正文，
--   确认各自报 ABORT: … 已漂移。
--   **approved 那条尤其要验**：本文件不改它，断言它未漂移是因为整个方案依赖
--   「它已经在传原币」这个事实——这条断言失效了，方案的前提就没人守。
--
-- 一、逐行 diff（E2）
--   五个函数分别与 ~/aozora-security-20260827/cash-baseline/ 下的导出比：
--
--   | 函数 | 基线文件 | 期望功能改动 |
--   |---|---|---|
--   | prepare_..._v2 | ...-production-20260904-0921.sql | **5 处** |
--   | callback_v3 | ...-production-20260904-1346.sql | **3 处**（全在 approved 分支） |
--   | attempt_transition_v2 | 同上 | **2 处**（签名 +2 参、original 两槽改 coalesce） |
--   | mark_submitted_v2 | 同上 | **2 处**（签名 +2 参、转发多传两个） |
--   | mark_rejected_v2 | 同上 | **2 处**（同上） |
--   | mark_approved_v2 | ...-production-20260904-1443.sql | **0 处，本文件不碰** |
--
--   **任一函数出现计划外差异即为我的转录错误，立即回滚。**
--   callback_v3 是 250 行 47 参数全文转录，最可能藏错；重点看 submitted 与
--   rejected 两个分支——那两段我一行没打算改。
--
--   ⚠️ **单独确认 classroom 分类检查仍在部署后的 prosrc 里。**
--      这是本文件最高风险的回归项：那段 09-02 11:21 才进生产，而我手上一度只有
--      11:06 的归档。见 home_account_book docs/lessons.md E8。
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
-- 二、结构与权限（A3）—— **本文件最容易出错的地方**
--
--   四次 DROP + CREATE，四个目标 ACL 不完全一样。A3 那个模板在本项目已经被写错
--   过三次，这一轮要连续用四次。**逐个精确比对，不要只查「有没有 anon」**——
--   anon / authenticated / service_role 三个角色任一残留都是权限边界变化。
--
--   | 函数 | 重载数 | 参数 | 目标 proacl |
--   |---|---|---|---|
--   | prepare_..._v2 | 1 | 17 | `{postgres=X/postgres,service_role=X/postgres}` |
--   | callback_v3 | 1 | 47 | `{postgres=X/postgres}`（未 DROP，应自动保留） |
--   | attempt_transition_v2 | 1 | 28 | **`{postgres=X/postgres}`** ← 只撤不授 |
--   | mark_submitted_v2 | 1 | 25 | `{postgres=X/postgres,service_role=X/postgres}` |
--   | mark_rejected_v2 | 1 | 27 | `{postgres=X/postgres,service_role=X/postgres}` |
--   | mark_approved_v2 | 1 | 45 | `{postgres=X/postgres,service_role=X/postgres}`（未动） |
--
--   五个函数的 owner 均为 postgres、prosecdef 均为 true、
--   proconfig 均为 {search_path=pg_catalog, public}。
--
--   **transition 那条最容易搞错**：它是内部 helper，基线就是 postgres-only，
--   只被两个 SECURITY DEFINER wrapper 以 postgres 身份调用。照抄另外两个的
--   「grant to service_role」会凭空开一个外部入口。
--
--   附带（原第 1、2 条，针对 prepare）：
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
-- 五之二、**回写链回归（本轮新增的全部行为，必验）**
--
--   首版的验收清单只验到 prepare 就停了，而首版被驳回的两条 P1 恰恰都在回写链上。
--   所以这一节不是补充，是这一版的主验收。全部 rollback-only，
--   **不需要批准任何真实 Cash 请求**——直接调三个 mark 函数即可。
--
--   A. **JPY 旧调用兼容**（比跨币种跑通更重要）
--      用今天 Edge 的原样参数（不传 p_original_*）依次调：
--        mark_submitted_v2 → attempt 转 submitted、支出转 pending
--        mark_rejected_v2  → attempt 转 rejected、支出转 rejected
--      两者的 attempt version 递增、返回结构、message 文案与部署前逐字相同。
--      **不传原币时 transition 回落到结算值，与基线行为等价——这条不过，
--      说明 coalesce 那两行写错了。**
--
--   B. **CNY 双金额正确写回**
--      用第五节造出的跨币种 attempt（original JPY 166100 / payment CNY 8000）：
--        1. mark_submitted_v2 传 p_original_amount=166100 / p_original_currency='JPY'
--           → 成功。**首版在这里必然 PAYLOAD_CONFLICT，这条就是 P1-1 的判据。**
--        2. 同一 attempt 走 mark_rejected_v2 → 成功，attempt 转 rejected
--        3. 用 Cash 的批准证据调 mark_approved_v2（该函数本轮未改，
--           原币来自 Cash projection）→ 成功，固定项币种 CNY 被接受。
--           **首版在这里必然 APPROVAL_EVIDENCE_CONFLICT，这条是 P1-2 的判据。**
--
--   C. **该失败的仍然失败**（错误码精确匹配）
--        a. 传错的原币金额（如 999）        → SCHOOL_EXPENSE_CASH_FIXED_PAYLOAD_CONFLICT
--        b. 传错的原币币种（如 'USD'）      → SCHOOL_EXPENSE_CASH_FIXED_EXTERNAL_IDENTITY_CONFLICT
--        c. approved 证据里固定项币种与结算币种不符
--                                           → SCHOOL_EXPENSE_CASH_FIXED_APPROVAL_EVIDENCE_CONFLICT
--           ← 这条证明改动 ① 是**换了判据**而不是**拆掉判据**
--        d. approved 证据里固定项金额 ≠ 结算金额 → 同上
--           ← 这条证明 p_fixed_item_amount 那条锁我确实留着了
--        e. 已 approved_fixed 再 rejected   → SCHOOL_EXPENSE_CASH_FIXED_APPROVED_CANNOT_REJECT
--        f. 已 rejected 再 approved         → SCHOOL_EXPENSE_CASH_FIXED_REJECTED_CANNOT_APPROVE
--           ← e/f 是我一行没改的分支，必须照旧
--
--   D. **幂等与 prepared 恢复**（同样是我没改的分支）
--        精确重放 submitted / rejected / approved 各一次 → idempotent=true，不重复写
--        从 prepared 直接 approved / rejected → callback_recovered_from_prepared=true，
--        version +2
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
-- 3. **谁还在读 cash_payment_amount。** 该列以前恒等于支出记录金额，跨币种后不再
--    相等。**仓库侧已查清（2026-09-04），只剩生产 DB 侧未查。**
--
--    仓库侧结论：
--      · 把 cash_payment_amount 与 v_expense.amount 直接比较的，全项目只有两处，
--        且都是 prepare RPC 自己复用分支的历史版本
--        （phase3c3b_20260819.sql:551、category_restriction_20260902.sql:180），
--        即本文件已经改掉的那两行。**没有第三处。**
--      · 前端只有四个引用点。渲染走 formatCashPaymentAmount()
--        （js/pages/expense-detail-page.js:1829-1835），它用
--        `cash_payment_currency || expense.currency`，跨币种会按结算币种渲染，
--        不会把 CNY 金额贴上 JPY 符号。列表页只 select 不渲染。
--
--    **仍需 Codex 用 catalog 查生产**：磁盘 SQL 不等于生产（lessons B1），
--    可能存在未进仓库的函数引用这两列。查法：
--      select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--      where n.nspname='public' and p.prosrc ~ 'cash_payment_amount';
--
-- 3b. **顺带发现：这个「原币 JPY / 结算 CNY」的形状，生产里早就有了。**
--
--    school_personal_cash_income_linkage_events（学生收入侧）上有两组金额列，且
--    school_get_student_monthly_settlement_historical_completion_candidate
--    明确要求 `v_cash_original_currency <> 'JPY'` /
--    `v_cash_payment_currency <> 'CNY'` 时报错
--    （school_historical_zero_carry_completion_rpcs_20260809.sql:256-259）。
--
--    **列名订正（审核 2026-09-04）**：收入侧那张表用的是
--    `amount` / `currency` + `payment_amount` / `payment_currency`，
--    **不是**两组同名的 `original_*`——我初稿写错了。语义仍然对得上：
--    前者被解释为原币 JPY，后者为结算 CNY。
--
--    所以本文件**不是引入新模型，是把收入侧已有的模式补到支出侧**。
--    审核时可以拿它做对照：若两侧对「第一组是消费币种、第二组是结算币种」的
--    理解出现分歧，说明我这边写反了。
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

