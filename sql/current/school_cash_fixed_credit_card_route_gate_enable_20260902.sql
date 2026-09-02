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
--       reason='Rolled back: fixed credit card route disabled.',
--       updated_at=now(),
--       updated_by=current_user
--   where feature_key='cash_fixed_credit_card_route_enabled';
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
  -- 依赖的上游 Gate 必须已开
  if (select state from public.school_feature_gates
      where feature_key = 'cash_expense_attempt_writer_v2_enabled') <> 'enabled' then
    raise exception using errcode = '55000',
      message = 'FIXED_CARD_GATE_UPSTREAM_WRITER_V2_NOT_ENABLED';
  end if;

  -- 当前必须仍是 blocked，避免重复执行或状态漂移
  if (select state from public.school_feature_gates
      where feature_key = 'cash_fixed_credit_card_route_enabled') <> 'blocked' then
    raise exception using errcode = '55000',
      message = 'FIXED_CARD_GATE_NOT_BLOCKED';
  end if;

  -- 分类限制必须已部署。直接读生产函数体，不假定 d4e874f 已上线。
  --
  -- 按 proname 匹配而不写死签名：该函数有 13 个参数，写死签名一旦顺序有出入就会
  -- 报「函数不存在」，把一个本该通过的前置检查变成部署阻塞。
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
--   teacher_wage / software / advertising
--   → 期望仍报 SCHOOL_EXPENSE_CASH_FIXED_CATEGORY_FORBIDDEN
--
--   这一条是本次开 Gate 后最关键的保护：Gate 开了之后，分类限制成为唯一屏障。
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
