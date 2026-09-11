-- =============================================================================
-- 回滚：撤除收入可见性隔离
--
-- 背景  教务老师（operator）要开放收入记录两个页面。收入列表读
--       school_operational_income_records（security_invoker 视图，select i.*），
--       底表唯一的 SELECT 策略只过滤 incident / operational_excluded，
--       【没有】角色、个人归属或 part_time_work 条件。
--       ⇒ 塾长在外部私塾的打工收入会出现在她的收入列表里。
--       其中一家外部私塾正是当前商用出售的意向客户，
--       那些记录是「客户付给塾长的工资明细」。
--
-- ⚠️ 光加 RLS 不够。Codex 2026-09-11 取证发现 P1：
--       school_get_profit_summary_schoolwide_v1 是 postgres 的 SECURITY DEFINER，
--       而 postgres 有 BYPASSRLS ⇒ 它【完全不看 RLS】；
--       它自己的角色检查又明确允许 admin / operator / read_only，
--       并返回含金额、description、note 的完整 income_records。
--       当前 27 条已收款打工收入符合它的筛选条件。
--       ⇒ 只做 RLS 会得到「看起来隔离了，其实没有」。
--
-- 本脚本两件事
--   A. 给 school_income_records 加一条【RESTRICTIVE】SELECT 策略。
--      必须 RESTRICTIVE：现有那条是 PERMISSIVE，再加 PERMISSIVE 是取并集
--      （放宽），方向相反。
--   B. 把利润汇总 RPC 的角色收紧为【仅 active admin】。
--      全校损益本就是业主视角，利润页也不在 operator 的页面白名单里。
--
-- 判据取 source_type 与 income_category【两个字段】。
-- 取证显示当前 28/28 完全重合，但那只是数据等价，不是约束保证
-- ——往隐私保守的方向写。
--
-- ⛔ 不改：表/函数的 ACL、owner、签名、现有 PERMISSIVE 策略、
--         业务数据、Cash 相关对象、前端。
--
-- 用法
--   psql -v ON_ERROR_STOP=1 -v mode=commit -f <本文件>
-- =============================================================================
\set ON_ERROR_STOP on
SELECT (:'mode'='commit') AS is_commit, (:'mode'='rehearsal') AS is_rehearsal \gset
\if :is_commit
\echo '>>> mode=commit —— 通过全部断言后将 COMMIT'
\elif :is_rehearsal
\echo '>>> mode=rehearsal —— 通过全部断言后将 ROLLBACK'
\else
\echo '!!! 必须指定 -v mode=rehearsal 或 -v mode=commit'
\quit
\endif

-- ⚠️ 回滚会把打工收入【重新暴露】给 operator 与 read_only，
--    并把利润汇总 RPC 重新开放给这两个角色。
--    它恢复的不是「更安全的状态」，是本次修复之前的状态。

BEGIN;

-- 新策略依赖 school_get_current_app_membership()。它必须是生产那个版本——
-- 准入建在一个没验过的对象上，等于没建。
-- 【复用既有实现】：school_students 与 school_business_entities 的策略
-- 用的就是这个函数与这个写法，本轮不另造布尔判定函数。
DO $mem$
DECLARE v_n int; v_md5 text; v_acl text;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_get_current_app_membership';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'IVIS_MEM_ARITY: public.school_get_current_app_membership 有 % 个（应为 1）', v_n;
  END IF;
  SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,'') INTO v_md5, v_acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_get_current_app_membership';
  IF v_md5 <> '2108cdeada67f8e357cda4df23d410b1' THEN
    RAISE EXCEPTION 'IVIS_MEM_DRIFT: % 的定义为 %，期望 %', 'school_get_current_app_membership', v_md5, '2108cdeada67f8e357cda4df23d410b1';
  END IF;
  IF v_acl <> '{postgres=X/postgres,authenticated=X/postgres}' THEN
    RAISE EXCEPTION 'IVIS_MEM_ACL: % 的 ACL 为 %，期望 %', 'school_get_current_app_membership', v_acl, '{postgres=X/postgres,authenticated=X/postgres}';
  END IF;
  RAISE NOTICE 'IVIS_MEM: school_get_current_app_membership() 在位且与取证一致';
END
$mem$;

-- 注释与执行属性【不写死】：本轮取证没有导出 profit RPC 的 COMMENT，
-- 而「没见过」不等于「是 NULL」——上次正是这样害生产 rehearsal 白跑一轮。
-- 改为 pre 段当场记下、post 段与之比对：同样能证明「只改了定义」，
-- 且不必猜任何没拿到的值。
-- ON COMMIT DROP：同一个 psql 会话里先 rehearsal 再 commit 时，
-- 否则第二次会撞上「已存在」。
CREATE TEMP TABLE incvis_before ON COMMIT DROP AS
-- 列名一律加 b_ 前缀：strict / cost / rows / owner 都是关键字或易冲突名，
-- 直接拿来做记录字段会撞上 plpgsql 的 SELECT ... INTO STRICT（已踩过）。
SELECT coalesce(obj_description(p.oid,'pg_proc'), '<NULL>') AS b_cmt,
       p.proisstrict AS b_strict, p.proparallel AS b_par, p.proleakproof AS b_leak,
       p.procost AS b_cost, p.prorows AS b_rows, pg_get_userbyid(p.proowner) AS b_owner,
       p.prosecdef AS b_secdef, coalesce(array_to_string(p.proconfig,', '),'<NULL>') AS b_cfg,
       coalesce(p.proacl::text,'') AS b_acl
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='school_get_profit_summary_schoolwide_v1';

DO $cap$
BEGIN
  IF (SELECT count(*) FROM incvis_before) <> 1 THEN
    RAISE EXCEPTION 'IVIS_PRE_ARITY: public.school_get_profit_summary_schoolwide_v1 不是恰好 1 个';
  END IF;
  RAISE NOTICE 'IVIS_PRE: 已记下 profit RPC 的 COMMENT 与执行属性  comment=[%]',
    (SELECT b_cmt FROM incvis_before);
END
$cap$;

DO $rbpre$
DECLARE v_n int; v_def text; v_md5 text; v_acl text; b record;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_get_profit_summary_schoolwide_v1';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'IVIS_RB_ARITY: public.school_get_profit_summary_schoolwide_v1 有 % 个（应为 1）', v_n;
  END IF;

  SELECT pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,'')
    INTO v_def, v_md5, v_acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_get_profit_summary_schoolwide_v1';

  IF v_md5 <> '5eedbc896954ab48518edae8ceccae62' THEN
    RAISE EXCEPTION 'IVIS_RB_MD5: 定义为 %，期望 %', v_md5, '5eedbc896954ab48518edae8ceccae62';
  END IF;
  IF v_acl <> '{postgres=X/postgres,authenticated=X/postgres}' THEN
    RAISE EXCEPTION 'IVIS_RB_ACL: ACL 为 %，期望 %', v_acl, '{postgres=X/postgres,authenticated=X/postgres}';
  END IF;

  -- 角色清单的直接断言：md5 变了只说明「变了」，这里说明「变成了什么」
  IF NOT (v_def LIKE '%membership.role=''admin''%') THEN
    RAISE EXCEPTION 'IVIS_RB_ROLE_SHAPE: 函数体的角色判据不是预期形状';
  END IF;
  IF  (v_def LIKE '%operator%' OR v_def LIKE '%read_only%') THEN
    RAISE EXCEPTION 'IVIS_RB_ROLE_LIST: operator / read_only 的出现情况与预期不符';
  END IF;

  -- 与 pre 段记下的比对：证明只动了定义
  SELECT * INTO b FROM incvis_before;
  IF coalesce(obj_description(
       (SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname='school_get_profit_summary_schoolwide_v1'),'pg_proc'),'<NULL>') <> b.b_cmt THEN
    RAISE EXCEPTION 'IVIS_RB_COMMENT: 注释被改动了（本脚本不改注释）';
  END IF;
  PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='school_get_profit_summary_schoolwide_v1'
      AND p.proisstrict=b.b_strict AND p.proparallel=b.b_par AND p.proleakproof=b.b_leak
      AND p.procost=b.b_cost AND p.prorows=b.b_rows AND p.prosecdef=b.b_secdef
      AND pg_get_userbyid(p.proowner)=b.b_owner
      AND coalesce(array_to_string(p.proconfig,', '),'<NULL>')=b.b_cfg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'IVIS_RB_ATTRS: owner / secdef / proconfig / 执行属性与 pre 段不一致';
  END IF;

  RAISE NOTICE 'IVIS_RB: profit RPC 的 md5 / ACL / 角色判据 / 注释 / 执行属性 全部符合预期';
END
$rbpre$;

DO $rbprepol$
DECLARE v_rls boolean; v_force boolean; v_n int; p record;
BEGIN
  SELECT c.relrowsecurity, c.relforcerowsecurity INTO v_rls, v_force
    FROM pg_class c WHERE c.oid='public.school_income_records'::regclass;
  IF v_rls IS NOT TRUE OR v_force IS NOT FALSE THEN
    RAISE EXCEPTION 'IVIS_RB_RLS: school_income_records rowsecurity=% force=%（期望 t / f）', v_rls, v_force;
  END IF;

  -- 现有 PERMISSIVE 策略必须原样还在：本脚本不碰它
  SELECT * INTO p FROM pg_policies
   WHERE schemaname='public' AND tablename='school_income_records' AND policyname='school_select_operational_income_records';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'IVIS_RB_OLD_POLICY_MISSING: 找不到 school_select_operational_income_records';
  END IF;
  IF p.permissive <> 'PERMISSIVE' OR p.cmd <> 'SELECT'
     OR p.roles::text <> '{public}' OR p.qual <> '((status <> ''incident_quarantined''::text) AND (operational_excluded IS NOT TRUE))' THEN
    RAISE EXCEPTION 'IVIS_RB_OLD_POLICY_DRIFT: school_select_operational_income_records 与基线不符  permissive=% cmd=% roles=% qual=%',
      p.permissive, p.cmd, p.roles::text, p.qual;
  END IF;

  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='public' AND tablename='school_income_records' AND policyname='school_restrict_part_time_work_income';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'IVIS_RB_NEW_POLICY: school_restrict_part_time_work_income 有 % 条（期望 1）', v_n;
  END IF;

  SELECT * INTO p FROM pg_policies
   WHERE schemaname='public' AND tablename='school_income_records' AND policyname='school_restrict_part_time_work_income';
  IF p.permissive <> 'RESTRICTIVE' OR p.cmd <> 'SELECT' OR p.roles::text <> '{public}' THEN
    RAISE EXCEPTION 'IVIS_RB_NEW_POLICY_SHAPE: permissive=% cmd=% roles=%',
      p.permissive, p.cmd, p.roles::text;
  END IF;
  IF p.qual <> '(((source_type IS DISTINCT FROM ''part_time_work''::text) AND (income_category IS DISTINCT FROM ''part_time_work''::text)) OR (EXISTS ( SELECT 1
   FROM school_get_current_app_membership() membership(user_id, role, is_active)
  WHERE (membership.is_active AND (membership.role = ''admin''::text)))))' THEN
    RAISE EXCEPTION 'IVIS_RB_NEW_POLICY_QUAL: 表达式与预期不符：%', p.qual;
  END IF;
  IF coalesce(obj_description(
       (SELECT pol.oid FROM pg_policy pol WHERE pol.polname='school_restrict_part_time_work_income'
          AND pol.polrelid='public.school_income_records'::regclass),'pg_policy'),'<NULL>') <> 'Hides the owner’s external part-time income from every role except an active admin. RLS only covers invoker paths; postgres and service_role have BYPASSRLS, so SECURITY DEFINER readers are deliberately unaffected.' THEN
    RAISE EXCEPTION 'IVIS_RB_NEW_POLICY_COMMENT: 策略注释与预期不符';
  END IF;

  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='public' AND tablename='school_income_records';
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'IVIS_RB_POLICY_COUNT: school_income_records 上共有 % 条策略（期望 2）', v_n;
  END IF;

  RAISE NOTICE 'IVIS_RB: school_income_records 的 RLS 开关与策略集合符合预期';
END
$rbprepol$;

-- ===== A. 撤除 RESTRICTIVE 策略 =====
DROP POLICY school_restrict_part_time_work_income ON public.school_income_records;

-- ===== B. 还原生产 canonical 逐字节 =====
CREATE OR REPLACE FUNCTION public.school_get_profit_summary_schoolwide_v1(p_start_month text, p_end_month text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_result jsonb;
begin
  if v_actor is null then
    raise exception using errcode='42501',message='BE_UI_AUTH_REQUIRED';
  end if;

  if not exists (
    select 1
    from public.school_app_memberships membership
    where membership.user_id=v_actor
      and membership.is_active
      and membership.role in ('admin','operator','read_only')
  ) then
    raise exception using errcode='42501',message='BE_UI_ACTIVE_MEMBERSHIP_REQUIRED';
  end if;

  if p_start_month is null or p_start_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
     or p_end_month is null or p_end_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
     or p_start_month > p_end_month then
    raise exception using errcode='22023',message='BE_UI_MONTH_RANGE_INVALID';
  end if;

  with
  currencies(currency,sort_order) as (
    values ('JPY'::text,1),('CNY'::text,2)
  ),
  income_base as (
    select i.id,i.income_date,i.income_category,i.description,i.currency,
           i.amount,i.amount_jpy,i.amount_cny,i.status,i.note,i.created_at
    from public.school_operational_income_records i
    where i.app_type='school'
      and i.year_month between p_start_month and p_end_month
      and i.status='received'
      and i.currency in ('JPY','CNY')
  ),
  expense_base as (
    select e.id,e.expense_date,e.expense_category,e.description,e.currency,
           e.amount,e.amount_jpy,e.amount_cny,e.status,e.reimbursement_status,
           e.note,e.created_at
    from public.school_expense_records e
    where e.app_type='school'
      and e.year_month between p_start_month and p_end_month
      and e.status='paid'
      and e.currency in ('JPY','CNY')
  ),
  reimbursement_base as (
    select r.id,r.currency,r.amount,r.status
    from public.school_reimbursements r
    where r.app_type='school'
      and r.year_month between p_start_month and p_end_month
      and r.currency in ('JPY','CNY')
  ),
  payment_request_base as (
    select p.id,p.currency,p.amount,p.amount_jpy,p.amount_cny,p.status,p.source_type
    from public.school_payment_requests p
    where p.request_month between p_start_month and p_end_month
      and p.currency in ('JPY','CNY')
  ),
  transaction_base as (
    select t.id,t.currency,t.amount,t.transaction_type
    from public.school_account_transactions t
    where t.app_type='school'
      and t.year_month between p_start_month and p_end_month
      and t.currency in ('JPY','CNY')
  ),
  summary_rows as (
    select c.currency,c.sort_order,
           (select count(*) from income_base i where i.currency=c.currency) income_count,
           coalesce((select sum(case c.currency when 'JPY' then coalesce(i.amount_jpy,i.amount)
                                                else coalesce(i.amount_cny,i.amount) end)
                     from income_base i where i.currency=c.currency),0) income_amount,
           (select count(*) from expense_base e where e.currency=c.currency) expense_count,
           coalesce((select sum(case c.currency when 'JPY' then coalesce(e.amount_jpy,e.amount)
                                                else coalesce(e.amount_cny,e.amount) end)
                     from expense_base e where e.currency=c.currency),0) expense_amount,
           coalesce((select sum(case c.currency when 'JPY' then coalesce(e.amount_jpy,e.amount)
                                                else coalesce(e.amount_cny,e.amount) end)
                     from expense_base e
                     where e.currency=c.currency and e.expense_category='teacher_wage'),0) teacher_wage_amount
    from currencies c
  ),
  audit_source(sort_order,name,profit_policy,record_count,jpy_amount,cny_amount,note) as (
    select 1,'报销记录','不计入利润',count(*),
           coalesce(sum(case when currency='JPY' then amount else 0 end),0),
           coalesce(sum(case when currency='CNY' then amount else 0 end),0),
           '原始支出已计入支出；这里只观察资金报销流。'
    from reimbursement_base where status='paid'
    union all
    select 2,'报销撤销','不计入利润',count(*),
           coalesce(sum(case when currency='JPY' then amount else 0 end),0),
           coalesce(sum(case when currency='CNY' then amount else 0 end),0),
           '撤销改变账户资金流，不重算经营利润。'
    from reimbursement_base where status='reversed'
    union all
    select 3,'老师工资支付请求','不重复计入利润',count(*),
           coalesce(sum(case when currency='JPY' then coalesce(amount_jpy,amount) else 0 end),0),
           coalesce(sum(case when currency='CNY' then coalesce(amount_cny,amount) else 0 end),0),
           '工资通过 teacher_wage 支出计入；支付请求只做状态参考。'
    from payment_request_base where source_type='teacher_wage' and status='paid'
    union all
    select 4,'老师工资支付撤销','不计入利润',count(*),
           coalesce(sum(case when currency='JPY' then coalesce(amount_jpy,amount) else 0 end),0),
           coalesce(sum(case when currency='CNY' then coalesce(amount_cny,amount) else 0 end),0),
           '撤销支付是资金流和状态变化，不直接进入利润。'
    from payment_request_base where source_type='teacher_wage' and status='reversed'
    union all
    select 5,'账户调整流水','不计入经营利润',count(*),
           coalesce(sum(case when currency='JPY' then amount else 0 end),0),
           coalesce(sum(case when currency='CNY' then amount else 0 end),0),
           '余额校正单列展示，不混入经营利润。'
    from transaction_base where transaction_type in ('account_adjustment','account_adjustment_reversal')
    union all
    select 6,'账户转账/调拨流水','不计入经营利润',count(*),
           coalesce(sum(case when currency='JPY' then amount else 0 end),0),
           coalesce(sum(case when currency='CNY' then amount else 0 end),0),
           '账户间资金移动只做审计。'
    from transaction_base where transaction_type in ('transfer_out','transfer_in','transfer_reverse_in','transfer_reverse_out')
    union all
    select 7,'其他账户流水','仅参考',count(*),
           coalesce(sum(case when currency='JPY' then amount else 0 end),0),
           coalesce(sum(case when currency='CNY' then amount else 0 end),0),
           '用于观察业务流水；利润以收入和支出事实表为准。'
    from transaction_base
    where transaction_type not in (
      'account_adjustment','account_adjustment_reversal','transfer_out','transfer_in',
      'transfer_reverse_in','transfer_reverse_out'
    )
  )
  select jsonb_build_object(
    'start_month',p_start_month,
    'end_month',p_end_month,
    'summary_rows',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'currency',s.currency,
        'income_count',s.income_count,
        'income_amount',s.income_amount,
        'expense_count',s.expense_count,
        'expense_amount',s.expense_amount,
        'teacher_wage_amount',s.teacher_wage_amount,
        'profit_amount',s.income_amount-s.expense_amount
      ) order by s.sort_order),'[]'::jsonb) from summary_rows s
    ),
    'audit_rows',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'name',a.name,'profit_policy',a.profit_policy,'record_count',a.record_count,
        'jpy_amount',a.jpy_amount,'cny_amount',a.cny_amount,'note',a.note
      ) order by a.sort_order),'[]'::jsonb) from audit_source a
    ),
    'income_records',(
      select coalesce(jsonb_agg(to_jsonb(i) - 'created_at' order by i.income_date desc,i.created_at desc,i.id),'[]'::jsonb)
      from income_base i
    ),
    'expense_records',(
      select coalesce(jsonb_agg(to_jsonb(e) - 'created_at' order by e.expense_date desc,e.created_at desc,e.id),'[]'::jsonb)
      from expense_base e
    )
  ) into v_result;

  return v_result;
end;
$function$;

DO $rbpost$
DECLARE v_n int; v_def text; v_md5 text; v_acl text; b record;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_get_profit_summary_schoolwide_v1';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'IVIS_RB_POST_ARITY: public.school_get_profit_summary_schoolwide_v1 有 % 个（应为 1）', v_n;
  END IF;

  SELECT pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,'')
    INTO v_def, v_md5, v_acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_get_profit_summary_schoolwide_v1';

  IF v_md5 <> 'c140ce7a34a308eae4dfb017326ada0e' THEN
    RAISE EXCEPTION 'IVIS_RB_POST_MD5: 定义为 %，期望 %', v_md5, 'c140ce7a34a308eae4dfb017326ada0e';
  END IF;
  IF v_acl <> '{postgres=X/postgres,authenticated=X/postgres}' THEN
    RAISE EXCEPTION 'IVIS_RB_POST_ACL: ACL 为 %，期望 %', v_acl, '{postgres=X/postgres,authenticated=X/postgres}';
  END IF;

  -- 角色清单的直接断言：md5 变了只说明「变了」，这里说明「变成了什么」
  IF  (v_def LIKE '%membership.role=''admin''%') THEN
    RAISE EXCEPTION 'IVIS_RB_POST_ROLE_SHAPE: 函数体的角色判据不是预期形状';
  END IF;
  IF NOT (v_def LIKE '%operator%' OR v_def LIKE '%read_only%') THEN
    RAISE EXCEPTION 'IVIS_RB_POST_ROLE_LIST: operator / read_only 的出现情况与预期不符';
  END IF;

  -- 与 pre 段记下的比对：证明只动了定义
  SELECT * INTO b FROM incvis_before;
  IF coalesce(obj_description(
       (SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname='school_get_profit_summary_schoolwide_v1'),'pg_proc'),'<NULL>') <> b.b_cmt THEN
    RAISE EXCEPTION 'IVIS_RB_POST_COMMENT: 注释被改动了（本脚本不改注释）';
  END IF;
  PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='school_get_profit_summary_schoolwide_v1'
      AND p.proisstrict=b.b_strict AND p.proparallel=b.b_par AND p.proleakproof=b.b_leak
      AND p.procost=b.b_cost AND p.prorows=b.b_rows AND p.prosecdef=b.b_secdef
      AND pg_get_userbyid(p.proowner)=b.b_owner
      AND coalesce(array_to_string(p.proconfig,', '),'<NULL>')=b.b_cfg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'IVIS_RB_POST_ATTRS: owner / secdef / proconfig / 执行属性与 pre 段不一致';
  END IF;

  RAISE NOTICE 'IVIS_RB_POST: profit RPC 的 md5 / ACL / 角色判据 / 注释 / 执行属性 全部符合预期';
END
$rbpost$;

DO $rbpostpol$
DECLARE v_rls boolean; v_force boolean; v_n int; p record;
BEGIN
  SELECT c.relrowsecurity, c.relforcerowsecurity INTO v_rls, v_force
    FROM pg_class c WHERE c.oid='public.school_income_records'::regclass;
  IF v_rls IS NOT TRUE OR v_force IS NOT FALSE THEN
    RAISE EXCEPTION 'IVIS_RB_POST_RLS: school_income_records rowsecurity=% force=%（期望 t / f）', v_rls, v_force;
  END IF;

  -- 现有 PERMISSIVE 策略必须原样还在：本脚本不碰它
  SELECT * INTO p FROM pg_policies
   WHERE schemaname='public' AND tablename='school_income_records' AND policyname='school_select_operational_income_records';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'IVIS_RB_POST_OLD_POLICY_MISSING: 找不到 school_select_operational_income_records';
  END IF;
  IF p.permissive <> 'PERMISSIVE' OR p.cmd <> 'SELECT'
     OR p.roles::text <> '{public}' OR p.qual <> '((status <> ''incident_quarantined''::text) AND (operational_excluded IS NOT TRUE))' THEN
    RAISE EXCEPTION 'IVIS_RB_POST_OLD_POLICY_DRIFT: school_select_operational_income_records 与基线不符  permissive=% cmd=% roles=% qual=%',
      p.permissive, p.cmd, p.roles::text, p.qual;
  END IF;

  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='public' AND tablename='school_income_records' AND policyname='school_restrict_part_time_work_income';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'IVIS_RB_POST_NEW_POLICY: school_restrict_part_time_work_income 有 % 条（期望 0）', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='public' AND tablename='school_income_records';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'IVIS_RB_POST_POLICY_COUNT: school_income_records 上共有 % 条策略（期望 1）', v_n;
  END IF;

  RAISE NOTICE 'IVIS_RB_POST: school_income_records 的 RLS 开关与策略集合符合预期';
END
$rbpostpol$;

\if :is_commit
COMMIT;
\echo '>>> 已 COMMIT'
\else
ROLLBACK;
\echo '>>> 已 ROLLBACK（rehearsal）'
\endif
