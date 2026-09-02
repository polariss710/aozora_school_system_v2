-- 开启固定信用卡路线 Gate（第二步）
--
-- 日期：2026-09-02
-- 前序：Cash 侧西武卡 is_school_fixed_route_enabled 已于 2026-09-02 23:31 开启
--
-- ===========================================================================
-- 这一步做什么
-- ===========================================================================
--
-- 把 cash_fixed_credit_card_route_enabled 从 blocked 改为 enabled。
--
-- 这是两道 Gate 中的第二道。第一道（Cash 侧西武卡的路线 flag）已开启并验证：
-- 卡列表返回 cash_route_enabled=true，schedule 推导正确，且用户已在生产界面
-- 逐一验证刷卡日与目标月份的对应关系：
--
--   2026-09-02 → 2026-09 固定项，09-25 扣款
--   2026-09-10 → 2026-09 固定项，09-25 扣款   ← cutoff 当天，inclusive 生效
--   2026-09-11 → 2026-10 固定项，10-25 扣款
--
-- 本步执行后，教室费用分类的支出即可真实提交为 Cash 固定项。
--
-- ===========================================================================
-- 前置检查为什么包含分类限制
-- ===========================================================================
--
-- 「只有教室租金走信用卡」这条业务约定的权威判定在
-- school_request_cash_fixed_expense_payment_confirmation_v2 里（d4e874f 部署）。
-- 若该检查未部署而先开 Gate，老师工资等任何分类都能被提交成固定项，那笔钱会挂到
-- 信用卡账单上、与实际支付方式不符，且撤销要经过 Cash 侧整套固定项删除保护。
--
-- 因此前置检查直接读函数定义确认该错误码存在，而不是假定它已部署。
--
-- ===========================================================================
-- 回滚
-- ===========================================================================
--
--   update public.school_feature_gates
--   set state='blocked',
--       reason='Fixed credit card route not yet released; School expense fixed writer fails closed.',
--       release_version='phase-3c2r-20260819',
--       evidence_hash='phase3c2r-db-edge-cutover-verified',
--       updated_at=now(),
--       updated_by=current_user
--   where feature_key='cash_fixed_credit_card_route_enabled';
--
--   注意必须一并恢复 release_version 与 evidence_hash。本文件初稿的回滚语句只改了
--   state 与 reason，导致 2026-09-02 那次回滚后这两个元数据仍停留在本次部署的值。
--   它们不影响功能判定（权威状态是 state），但会让 Gate 的发布溯源失真。
--   上面填的是该 Gate 在本次部署前的实际值。
--
--   回滚后固定卡路线的提交立即失效（报 SCHOOL_CASH_FIXED_CREDIT_CARD_ROUTE_DISABLED），
--   但已生成的 Cash 固定项不会消失，需要另行处理。因此回滚前应先确认没有已提交
--   但未处理的固定请求。
--
-- ===========================================================================

\set ON_ERROR_STOP on

begin;

do $gate_precheck$
begin
  -- 依赖的上游 Gate 必须已开。
  --
  -- 用 not exists 而不是 (select state) <> 'enabled'：后者在 Gate 行不存在时
  -- 返回 NULL，而 NULL <> 'enabled' 既不是 true 也不是 false，异常不会触发，
  -- 前置检查形同虚设。
  if not exists (
    select 1 from public.school_feature_gates
    where feature_key = 'cash_expense_attempt_writer_v2_enabled'
      and state = 'enabled'
  ) then
    raise exception using errcode = '55000',
      message = 'FIXED_CARD_GATE_UPSTREAM_WRITER_V2_NOT_ENABLED';
  end if;

  -- 当前必须仍是 blocked，避免重复执行或状态漂移。同样用 not exists。
  if not exists (
    select 1 from public.school_feature_gates
    where feature_key = 'cash_fixed_credit_card_route_enabled'
      and state = 'blocked'
  ) then
    raise exception using errcode = '55000',
      message = 'FIXED_CARD_GATE_NOT_BLOCKED';
  end if;

  -- 分类限制必须已部署。直接读生产函数体，不假定 d4e874f 已上线。
  --
  -- 按 proname 匹配而不写死签名。该函数在生产上有 15 个参数——本文件初稿按 Edge
  -- 的调用推断为 13 个，是错的。写死签名会让这个本该通过的检查报「函数不存在」，
  -- 把前置保护变成部署阻塞。
  --
  -- 生产已确认该函数只有一个重载，因此 exists 不会放行未打补丁的旧版本。
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'school_request_cash_fixed_expense_payment_confirmation_v2'
      and position('SCHOOL_EXPENSE_CASH_FIXED_CATEGORY_FORBIDDEN' in p.prosrc) > 0
  ) then
    raise exception using errcode = '55000',
      message = 'FIXED_CARD_GATE_CATEGORY_RESTRICTION_MISSING';
  end if;
end;
$gate_precheck$;

update public.school_feature_gates
set state = 'enabled',
    reason = 'Fixed credit card route enabled for classroom expenses only; Cash-side card flag and School-side category restriction both verified in production.',
    release_version = 'fixed-card-route-20260902',
    evidence_hash = 'fixed-card-schedule-preview-verified-20260902',
    updated_at = now(),
    updated_by = current_user
where feature_key = 'cash_fixed_credit_card_route_enabled'
  and state = 'blocked';

do $gate_postcheck$
begin
  if (select state from public.school_feature_gates
      where feature_key = 'cash_fixed_credit_card_route_enabled') <> 'enabled' then
    raise exception using errcode = '55000',
      message = 'FIXED_CARD_GATE_ENABLE_FAILED';
  end if;
end;
$gate_postcheck$;

commit;

-- ===========================================================================
-- 部署后验证
-- ===========================================================================
--
-- 一、Gate 状态
--   cash_fixed_credit_card_route_enabled = 'enabled'
--   其余 Gate 状态一律未变（尤其 cash_expense_attempt_writer_v2_enabled 仍 enabled）
--
-- 二、教室费用可提交（rollback-only fixture）
--   构造 expense_category='classroom' 的待支付支出，以固定卡路线调用
--   school_request_cash_fixed_expense_payment_confirmation_v2
--   → 期望成功返回 prepared，payment_route='fixed_credit_card'
--
-- 三、其他分类仍被拒（rollback-only fixture）
--   用 software / advertising / other 三个分类构造，期望均报
--   SCHOOL_EXPENSE_CASH_FIXED_CATEGORY_FORBIDDEN
--
--   这一条是本次开 Gate 后最关键的保护：Gate 开了之后，分类限制成为唯一屏障。
--
--   **不要用 teacher_wage 构造 fixture。** 2026-09-02 的首次验证正是卡在这里：
--   老师工资支出不能经通用的待支付支出 RPC 创建（报「老师工资支出请通过老师工资
--   支付流程生成」），fixture 构造阶段就会失败，导致整组验证无法进行。
--
--   teacher_wage 不需要单独验证。分类检查是单条判断
--   `if v_expense.expense_category is distinct from 'classroom'`，对所有非
--   classroom 分类一视同仁，software 被拒即证明该判断生效。若将来改成白名单多值
--   匹配，这个论证不再成立，届时需要另找验证 teacher_wage 的途径。
--
--   该论证已于 2026-09-03 由审核方独立核实：生产只有一个 prepare 重载，
--   `IS DISTINCT FROM 'classroom'` 精确出现一次，且位于 source_type 的
--   manual_cash / teacher_wage 分支之前，teacher_wage 无绕过路径。
--
-- 三之附：fixture 的正确终态 —— 汇总断言按此写
--   classroom 固定卡请求      → cash_request_status = 'pending_cash_request'
--   immediate_account 请求    → cash_request_status = 'pending_cash_request'
--   software / advertising / other → cash_request_status 保持 NULL，整行不变
--
--   **不要断言「全部 fixture 进入 pending_cash_request」。** 被分类限制拒绝的三条
--   本就不该有任何状态变化，它们保持 NULL 才是正确结果。2026-09-03 的第二次尝试
--   正是卡在这条写反的汇总断言上——五组功能验证全部通过，却因汇总判据错误而回滚。
--
-- 四、即时账户路线不受影响
--   immediate_account 的提交行为与开 Gate 前完全一致
--
-- 五、不受影响
--   1. Cash 侧任何对象未改动
--   2. 西武卡配置未改动
--   3. 已有的支出记录与 attempt 未改动
--
-- ===========================================================================
