-- =============================================================================
-- 回滚：撤除打工隐私隔离
--
-- 目的  教务老师（operator）要开放收入记录页面。塾长在外部私塾打工的数据
--       ——课时、时薪、月结、收入、Cash 到账——她一律不该看见。
--       其中一家私塾正是当前商用出售的意向客户，那些记录是「客户付给塾长的
--       工资明细」。
--
-- ⚠️ 这件事【不是一层能解决的】。Codex 2026-09-11 三轮取证逐层推翻了前一版方案：
--
--   第 1 版：只给 school_income_records 加 RLS
--     ⇒ 被 school_get_profit_summary_schoolwide_v1 绕过。它是 postgres 的
--       SECURITY DEFINER，而 postgres 有 BYPASSRLS，【完全不看 RLS】；
--       它自己的角色检查还明确允许 operator / read_only。
--
--   第 2 版：再收紧利润 RPC
--     ⇒ 仍被 school_personal_cash_income_linkage_events 绕过。该表 RLS=false、
--       authenticated 有 SELECT，27 条事件带着打工收入的金额与 UUID。
--
--   第 3 版（本脚本）：整片数据面
--     ⇒ 还发现 4 个【无身份守卫】的 postgres DEFINER reader，
--       以及 4 个允许 operator 的打工 writer。
--
-- 本脚本做六件事
--   A. school_income_records 加一条 RESTRICTIVE SELECT 策略
--   B. 利润汇总 RPC 的角色收紧为仅 active admin
--   C. school_personal_cash_income_linkage_events 启用 RLS 并加一条策略
--   D. 4 个无守卫的打工 reader 加 PTW admin 守卫
--   E. 撤销 school_update_personal_cash_income_linkage_event_status 的 authenticated EXECUTE
--   F. 4 个打工 writer 的守卫由 PTW operator 换成 PTW admin
--
-- ⚠️ A 与 C 互相依赖：C 的策略判据是「父收入行是否可见」，
--    没有 A 就没有「不可见」这回事。两者必须同批，单发任何一个都不成立。
--
-- ⛔ 不改：owner、签名、函数体其余部分、现有 PERMISSIVE 策略、业务数据、
--         Cash Edge、前端。除 E 外不动任何 ACL。
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

-- ⚠️ 回滚会把打工课时、时薪、月结、收入与 Cash 到账【重新暴露】给
--    operator 与 read_only，并把 4 个打工 writer 重新开放给 operator。
--    它恢复的不是「更安全的状态」，是本次修复之前的状态。

BEGIN;

DO $dep$
DECLARE t record; v_n int; v_md5 text;
BEGIN
  FOR t IN SELECT * FROM (VALUES
      ('school_get_current_app_membership','2108cdeada67f8e357cda4df23d410b1'),
      ('school_require_current_part_time_work_admin','18bf1db587a9c0a8815d47522bf3395a')
    ) AS v(proname, md5)
  LOOP
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=t.proname;
    IF v_n <> 1 THEN
      RAISE WARNING 'PTWP_DEP_ARITY: public.% 有 % 个（应为 1）', t.proname, v_n;
      RETURN;
    ELSE
      SELECT md5(pg_get_functiondef(p.oid)) INTO v_md5
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname=t.proname;
      IF v_md5 <> t.md5 THEN
        RAISE WARNING 'PTWP_DEP_DRIFT: % 的定义为 %，期望 %', t.proname, v_md5, t.md5;
      RETURN;
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'PTWP_DEP: membership 与 PTW admin 守卫状态正常（回滚本身不依赖它们）';
END
$dep$;

DO $rbpre$
DECLARE t record; v_n int; v_md5 text; v_acl text;
BEGIN
  FOR t IN SELECT * FROM (VALUES
    ('school_get_profit_summary_schoolwide_v1','5eedbc896954ab48518edae8ceccae62','{postgres=X/postgres,authenticated=X/postgres}'),
    ('school_list_part_time_work_lessons','58aed1969c9b6a0afa307d288f984bd1','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'),
    ('school_list_part_time_work_monthly_settlements','80e265b21e5f194f5d4ed6954c09c26d','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'),
    ('school_get_part_time_work_settlement_export','363b77bc9689d675eb01f2be79627602','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'),
    ('school_get_part_time_work_cash_request_context','eea163219fce2648f7f0dc8f72c5ad63','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'),
    ('school_create_part_time_work_planned_lesson','be630ac030166b56a00939c10317656e','{postgres=X/postgres,authenticated=X/postgres}'),
    ('school_update_part_time_work_lesson','082c0b4d665ae7a4b50b0976cd89eedb','{postgres=X/postgres,authenticated=X/postgres}'),
    ('school_generate_part_time_work_actual_from_planned','f7a2ae7d0b56cd51303a4daf4b132bd5','{postgres=X/postgres,authenticated=X/postgres}'),
    ('school_delete_part_time_work_lesson','189909f8fa038364b682349d1dbb2ae7','{postgres=X/postgres,authenticated=X/postgres}')
    ) AS v(proname, md5, acl)
  LOOP
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=t.proname;
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'PTWP_RB_ARITY: public.% 有 % 个（应为 1）', t.proname, v_n;
    END IF;
    SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,'') INTO v_md5, v_acl
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=t.proname;
    IF v_md5 <> t.md5 THEN
      RAISE EXCEPTION 'PTWP_RB_MD5: % 的定义为 %，期望 %', t.proname, v_md5, t.md5;
    END IF;
    IF v_acl <> t.acl THEN
      RAISE EXCEPTION 'PTWP_RB_ACL: % 的 ACL 为 %，期望 %', t.proname, v_acl, t.acl;
    END IF;
  END LOOP;

  -- E 只撤授权，函数体必须原样
  SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,'') INTO v_md5, v_acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_update_personal_cash_income_linkage_event_status';
  IF v_md5 <> '48a6c54693e746c7426caec01e8056c1' THEN
    RAISE EXCEPTION 'PTWP_RB_E_MD5: school_update_personal_cash_income_linkage_event_status 的定义为 %，期望 %（本脚本不改它的函数体）', v_md5, '48a6c54693e746c7426caec01e8056c1';
  END IF;
  IF v_acl <> '{postgres=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'PTWP_RB_E_ACL: school_update_personal_cash_income_linkage_event_status 的 ACL 为 %，期望 %', v_acl, '{postgres=X/postgres,service_role=X/postgres}';
  END IF;

  RAISE NOTICE 'PTWP_RB: 9 个函数的 md5/ACL 与 school_update_personal_cash_income_linkage_event_status 的 md5/ACL 全部符合预期';
END
$rbpre$;

DO $rbpreg$
DECLARE t record; v_def text; v_a int; v_o int;
BEGIN
  FOR t IN SELECT * FROM (VALUES
    ('school_list_part_time_work_lessons',1,0),
    ('school_list_part_time_work_monthly_settlements',1,0),
    ('school_get_part_time_work_settlement_export',1,0),
    ('school_get_part_time_work_cash_request_context',1,0),
    ('school_create_part_time_work_planned_lesson',1,0),
    ('school_update_part_time_work_lesson',1,0),
    ('school_generate_part_time_work_actual_from_planned',1,0),
    ('school_delete_part_time_work_lesson',1,0)
    ) AS v(proname, n_admin, n_operator)
  LOOP
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=t.proname;
    v_a := (length(v_def)-length(replace(v_def,'school_require_current_part_time_work_admin','')))/length('school_require_current_part_time_work_admin');
    v_o := (length(v_def)-length(replace(v_def,'school_require_current_part_time_work_operator','')))/length('school_require_current_part_time_work_operator');
    -- ⚠️ 'school_require_current_part_time_work_admin' 不是 'school_require_current_part_time_work_operator' 的子串，两个计数互不干扰
    IF v_a <> t.n_admin OR v_o <> t.n_operator THEN
      RAISE EXCEPTION 'PTWP_RB_GUARD_SHAPE: % 的 PTW admin 守卫 % 次（期望 %）、operator 守卫 % 次（期望 %）',
        t.proname, v_a, t.n_admin, v_o, t.n_operator;
    END IF;
  END LOOP;
  RAISE NOTICE 'PTWP_RB: 8 个打工函数的守卫调用形状符合预期';
END
$rbpreg$;

DO $rbprep$
DECLARE p record; v_n int; v_rls boolean; v_force boolean; v_acl text;
BEGIN
  -- 收入表
  SELECT c.relrowsecurity, c.relforcerowsecurity INTO v_rls, v_force
    FROM pg_class c WHERE c.oid='public.school_income_records'::regclass;
  IF v_rls IS NOT TRUE OR v_force IS NOT FALSE THEN
    RAISE EXCEPTION 'PTWP_RB_INC_RLS: school_income_records rowsecurity=% force=%（期望 t / f）', v_rls, v_force;
  END IF;
  SELECT * INTO p FROM pg_policies
   WHERE schemaname='public' AND tablename='school_income_records' AND policyname='school_select_operational_income_records';
  IF NOT FOUND OR p.permissive <> 'PERMISSIVE' OR p.qual <> '((status <> ''incident_quarantined''::text) AND (operational_excluded IS NOT TRUE))' THEN
    RAISE EXCEPTION 'PTWP_RB_INC_OLD_POLICY: 原有 school_select_operational_income_records 缺失或已漂移（本脚本不碰它）';
  END IF;
  SELECT count(*) INTO v_n FROM pg_policies WHERE schemaname='public' AND tablename='school_income_records';
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'PTWP_RB_INC_POLICY_COUNT: school_income_records 上有 % 条策略（期望 2）', v_n;
  END IF;

  -- 关联表
  SELECT c.relrowsecurity, c.relforcerowsecurity, coalesce(c.relacl::text,'')
    INTO v_rls, v_force, v_acl
    FROM pg_class c WHERE c.oid='public.school_personal_cash_income_linkage_events'::regclass;
  IF v_rls IS NOT TRUE OR v_force IS NOT FALSE THEN
    RAISE EXCEPTION 'PTWP_RB_EV_RLS: school_personal_cash_income_linkage_events rowsecurity=% force=%（期望 t / f）', v_rls, v_force;
  END IF;
  IF v_acl <> '{postgres=arwdDxtm/postgres,authenticated=rm/postgres,service_role=arwdDxtm/postgres}' THEN
    RAISE EXCEPTION 'PTWP_RB_EV_ACL: school_personal_cash_income_linkage_events 的授权为 %，期望 %（本脚本不改它的授权）', v_acl, '{postgres=arwdDxtm/postgres,authenticated=rm/postgres,service_role=arwdDxtm/postgres}';
  END IF;
  SELECT count(*) INTO v_n FROM pg_policies WHERE schemaname='public' AND tablename='school_personal_cash_income_linkage_events';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'PTWP_RB_EV_POLICY_COUNT: school_personal_cash_income_linkage_events 上有 % 条策略（期望 1）', v_n;
  END IF;

  SELECT * INTO p FROM pg_policies
   WHERE schemaname='public' AND tablename='school_income_records' AND policyname='school_restrict_part_time_work_income';
  IF p.permissive <> 'RESTRICTIVE' OR p.cmd <> 'SELECT' OR p.roles::text <> '{public}'
     OR p.qual <> '(((source_type IS DISTINCT FROM ''part_time_work''::text) AND (income_category IS DISTINCT FROM ''part_time_work''::text)) OR (EXISTS ( SELECT 1
   FROM school_get_current_app_membership() membership(user_id, role, is_active)
  WHERE (membership.is_active AND (membership.role = ''admin''::text)))))' THEN
    RAISE EXCEPTION 'PTWP_RB_INC_POLICY: school_restrict_part_time_work_income 的形状或表达式与预期不符：% / % / % / %',
      p.permissive, p.cmd, p.roles::text, p.qual;
  END IF;

  SELECT * INTO p FROM pg_policies
   WHERE schemaname='public' AND tablename='school_personal_cash_income_linkage_events' AND policyname='school_select_income_linkage_events_by_visible_parent';
  IF p.permissive <> 'PERMISSIVE' OR p.cmd <> 'SELECT' OR p.roles::text <> '{public}'
     OR p.qual <> '((EXISTS ( SELECT 1
   FROM school_income_records i
  WHERE (i.id = school_personal_cash_income_linkage_events.income_record_id))) OR (EXISTS ( SELECT 1
   FROM school_get_current_app_membership() membership(user_id, role, is_active)
  WHERE (membership.is_active AND (membership.role = ''admin''::text)))))' THEN
    RAISE EXCEPTION 'PTWP_RB_EV_POLICY: school_select_income_linkage_events_by_visible_parent 的形状或表达式与预期不符：% / % / % / %',
      p.permissive, p.cmd, p.roles::text, p.qual;
  END IF;

  RAISE NOTICE 'PTWP_RB: 两张表的 RLS 开关、授权与策略集合符合预期';
END
$rbprep$;

-- ===== A / C 的撤除 =====
DROP POLICY school_restrict_part_time_work_income ON public.school_income_records;
DROP POLICY school_select_income_linkage_events_by_visible_parent ON public.school_personal_cash_income_linkage_events;
ALTER TABLE public.school_personal_cash_income_linkage_events DISABLE ROW LEVEL SECURITY;

-- ===== E 的还原 =====
--
-- ⚠️ 只补授 authenticated 会把它【追加到 service_role 之后】，
--    得到 {postgres,service_role,authenticated}，而生产是
--    {postgres,authenticated,service_role} —— 顺序不同，post 断言会拒绝。
--    必须全撤后按 authenticated → service_role 重授。
REVOKE ALL ON FUNCTION public.school_update_personal_cash_income_linkage_event_status(uuid,text,uuid,text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.school_update_personal_cash_income_linkage_event_status(uuid,text,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.school_update_personal_cash_income_linkage_event_status(uuid,text,uuid,text) TO service_role;

-- ===== 9 个函数逐字节还原 =====
-- ---- school_get_profit_summary_schoolwide_v1 ----
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

-- ---- school_list_part_time_work_lessons ----
CREATE OR REPLACE FUNCTION public.school_list_part_time_work_lessons(p_year_month text DEFAULT NULL::text, p_workplace_name text DEFAULT NULL::text, p_record_kind text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, record_kind text, planned_lesson_id uuid, generated_actual_id uuid, work_date date, start_time time without time zone, end_time time without time zone, year_month text, workplace_name text, teacher_name text, subject_name text, class_description text, planned_hours numeric, actual_hours numeric, lesson_count integer, cumulative_hours numeric, hourly_rate_jpy integer, lesson_wage_jpy integer, transportation_fee_jpy integer, memo text, settlement_id uuid, settlement_status text, income_request_id uuid, income_request_status text, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with active_lessons as (
    select
      l.*,
      row_number() over (
        partition by
          l.record_kind,
          l.workplace_name,
          l.subject_name,
          coalesce(l.class_description, '')
        order by l.work_date, l.start_time nulls last, l.created_at, l.id
      )::integer as calculated_lesson_count,
      sum(
        case
          when l.record_kind = 'actual' then l.actual_hours
          else l.planned_hours
        end
      ) over (
        partition by
          l.record_kind,
          l.workplace_name,
          l.subject_name,
          coalesce(l.class_description, '')
        order by l.work_date, l.start_time nulls last, l.created_at, l.id
        rows between unbounded preceding and current row
      )::numeric as calculated_cumulative_hours
    from public.school_part_time_work_lessons l
    where l.deleted_at is null
  )
  select
    l.id,
    l.record_kind,
    l.planned_lesson_id,
    ga.id as generated_actual_id,
    l.work_date,
    l.start_time,
    l.end_time,
    l.year_month,
    l.workplace_name,
    l.teacher_name,
    l.subject_name,
    l.class_description,
    l.planned_hours,
    l.actual_hours,
    l.calculated_lesson_count as lesson_count,
    l.calculated_cumulative_hours as cumulative_hours,
    l.hourly_rate_jpy,
    l.lesson_wage_jpy,
    l.transportation_fee_jpy,
    l.memo,
    s.id as settlement_id,
    s.status as settlement_status,
    s.income_request_id,
    ir.status as income_request_status,
    l.created_at,
    l.updated_at
  from active_lessons l
  left join public.school_part_time_work_lessons ga
    on ga.planned_lesson_id = l.id
    and ga.record_kind = 'actual'
    and ga.deleted_at is null
  left join public.school_part_time_work_monthly_settlement_details d
    on d.actual_lesson_id = l.id
    and l.record_kind = 'actual'
  left join public.school_part_time_work_monthly_settlements s
    on s.id = d.settlement_id
    and s.deleted_at is null
  left join public.school_part_time_work_income_requests ir
    on ir.id = s.income_request_id
    and ir.deleted_at is null
  where (nullif(trim(coalesce(p_year_month, '')), '') is null or l.year_month = trim(p_year_month))
    and (nullif(trim(coalesce(p_workplace_name, '')), '') is null or l.workplace_name = trim(p_workplace_name))
    and (nullif(trim(coalesce(p_record_kind, '')), '') is null or l.record_kind = lower(trim(p_record_kind)))
  order by l.work_date, l.start_time nulls last, l.created_at, l.id;
$function$;

-- ---- school_list_part_time_work_monthly_settlements ----
CREATE OR REPLACE FUNCTION public.school_list_part_time_work_monthly_settlements(p_year_month text)
 RETURNS TABLE(id uuid, year_month text, workplace_name text, teacher_name text, actual_lesson_count integer, actual_hours_total numeric, hourly_rate_jpy integer, lesson_wage_jpy integer, transportation_fee_jpy integer, adjustment_jpy integer, total_wage_jpy integer, status text, locked_at timestamp with time zone, income_request_id uuid, income_request_status text, income_record_id uuid, income_record_status text, income_record_cash_status text, income_record_is_blocking boolean, income_request_is_blocking boolean, memo text, updated_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with target_workplaces(workplace_name) as (
    values ('诺应教育'), ('致远教育'), ('新领域')
  ),
  actual_totals as (
    select
      l.workplace_name,
      count(*)::integer as actual_lesson_count,
      coalesce(sum(l.actual_hours), 0)::numeric as actual_hours_total,
      coalesce(sum(l.lesson_wage_jpy), 0)::integer as default_lesson_wage_jpy,
      coalesce(sum(l.transportation_fee_jpy), 0)::integer as transportation_fee_jpy
    from public.school_part_time_work_lessons l
    where l.deleted_at is null
      and l.record_kind = 'actual'
      and l.year_month = public.school_part_time_work_validate_year_month(p_year_month)
    group by l.workplace_name
  ),
  latest_income_linkage as (
    select distinct on (e.income_record_id)
      e.income_record_id,
      e.sync_status
    from public.school_personal_cash_income_linkage_events e
    where e.source_table = 'school_income_records'
      and e.source_event_type in ('tuition_income_received', 'income_received')
    order by e.income_record_id, e.created_at desc, e.id desc
  )
  select
    s.id,
    public.school_part_time_work_validate_year_month(p_year_month) as year_month,
    w.workplace_name,
    coalesce(s.teacher_name, '吴峰') as teacher_name,
    case when s.status in ('locked', 'income_request_created') then s.actual_lesson_count else coalesce(a.actual_lesson_count, 0) end as actual_lesson_count,
    case when s.status in ('locked', 'income_request_created') then s.actual_hours_total else coalesce(a.actual_hours_total, 0) end as actual_hours_total,
    coalesce(s.hourly_rate_jpy, 0) as hourly_rate_jpy,
    case
      when s.status in ('locked', 'income_request_created') then s.lesson_wage_jpy
      else coalesce(a.default_lesson_wage_jpy, 0)
    end as lesson_wage_jpy,
    case when s.status in ('locked', 'income_request_created') then s.transportation_fee_jpy else coalesce(a.transportation_fee_jpy, 0) end as transportation_fee_jpy,
    coalesce(s.adjustment_jpy, 0) as adjustment_jpy,
    case
      when s.status in ('locked', 'income_request_created') then s.total_wage_jpy
      else (
        coalesce(a.default_lesson_wage_jpy, 0)
        + coalesce(a.transportation_fee_jpy, 0)
        + coalesce(s.adjustment_jpy, 0)
      )
    end as total_wage_jpy,
    coalesce(s.status, 'draft') as status,
    s.locked_at,
    s.income_request_id,
    ir.status as income_request_status,
    s.income_record_id,
    i.status as income_record_status,
    l.sync_status as income_record_cash_status,
    case
      when i.id is null then false
      when exists (
        select 1
        from public.school_account_transactions t
        where t.related_table = 'school_income_records'
          and t.related_id = i.id
          and coalesce(t.app_type, '') = 'school'
      ) then true
      when exists (
        select 1
        from public.school_personal_cash_income_linkage_events e
        where e.source_table = 'school_income_records'
          and (
            e.income_record_id = i.id
            or e.source_id = i.id
          )
          and (
            e.cash_transaction_id is not null
            or coalesce(e.sync_status, '') in (
              'pending',
              'pending_cash_request',
              'cash_pending',
              'cash_submitted',
              'awaiting_cash_confirmation',
              'approved',
              'received',
              'settled',
              'synced'
            )
            or coalesce(e.cash_request_status, '') in (
              'pending',
              'approved',
              'synced',
              'cash_pending',
              'cash_submitted',
              'awaiting_cash_confirmation'
            )
            or (
              e.cash_request_id is not null
              and coalesce(e.cash_request_status, '') not in (
                'cancelled',
                'voided',
                'rejected',
                'cash_rejected',
                'reversed'
              )
            )
          )
      ) then true
      when coalesce(i.status, '') in (
        'cancelled',
        'voided',
        'rejected',
        'cash_rejected',
        'reversed'
      ) then false
      else true
    end as income_record_is_blocking,
    case
      when ir.id is null then false
      when ir.cash_transaction_id is not null then true
      when coalesce(ir.cash_request_status, '') in (
        'pending',
        'approved',
        'synced',
        'cash_pending',
        'cash_submitted',
        'awaiting_cash_confirmation'
      ) then true
      when ir.cash_request_id is not null
        and coalesce(ir.cash_request_status, '') not in (
          'cancelled',
          'voided',
          'rejected',
          'cash_rejected',
          'reversed'
        ) then true
      when coalesce(ir.status, '') in (
        'cancelled',
        'voided',
        'rejected',
        'cash_rejected',
        'reversed'
      ) then false
      else true
    end as income_request_is_blocking,
    s.memo,
    s.updated_at
  from target_workplaces w
  left join actual_totals a
    on a.workplace_name = w.workplace_name
  left join public.school_part_time_work_monthly_settlements s
    on s.year_month = public.school_part_time_work_validate_year_month(p_year_month)
    and s.workplace_name = w.workplace_name
    and s.deleted_at is null
  left join public.school_part_time_work_income_requests ir
    on ir.id = s.income_request_id
    and ir.deleted_at is null
  left join public.school_income_records i
    on i.id = s.income_record_id
    and coalesce(i.app_type, '') = 'school'
  left join latest_income_linkage l
    on l.income_record_id = i.id
  order by case w.workplace_name when '诺应教育' then 1 when '致远教育' then 2 else 3 end;
$function$;

-- ---- school_get_part_time_work_settlement_export ----
CREATE OR REPLACE FUNCTION public.school_get_part_time_work_settlement_export(p_settlement_id uuid)
 RETURNS TABLE(settlement_id uuid, year_month text, workplace_name text, teacher_name text, adjustment_jpy integer, total_wage_jpy integer, status text, locked_at timestamp with time zone, actual_lesson_id uuid, work_date date, start_time time without time zone, end_time time without time zone, subject_name text, class_description text, actual_hours numeric, lesson_count integer, cumulative_hours numeric, hourly_rate_jpy integer, lesson_wage_jpy integer, transportation_fee_jpy integer, memo text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_settlement public.school_part_time_work_monthly_settlements%rowtype;
begin
  select *
  into v_settlement
  from public.school_part_time_work_monthly_settlements s
  where s.id = p_settlement_id
    and s.deleted_at is null;

  if not found then
    raise exception '月度工资结算不存在。';
  end if;
  if v_settlement.status not in ('locked', 'income_request_created') then
    raise exception '月度工资结算锁定后才能导出。';
  end if;

  return query
  select
    v_settlement.id as settlement_id,
    v_settlement.year_month,
    v_settlement.workplace_name,
    v_settlement.teacher_name,
    v_settlement.adjustment_jpy,
    v_settlement.total_wage_jpy,
    v_settlement.status,
    v_settlement.locked_at,
    d.actual_lesson_id,
    d.work_date,
    d.start_time,
    d.end_time,
    d.subject_name,
    d.class_description,
    d.actual_hours,
    d.lesson_count,
    d.cumulative_hours,
    d.hourly_rate_jpy,
    d.lesson_wage_jpy,
    d.transportation_fee_jpy,
    d.memo
  from public.school_part_time_work_monthly_settlement_details d
  where d.settlement_id = v_settlement.id
  order by d.work_date, d.created_at;
end;
$function$;

-- ---- school_get_part_time_work_cash_request_context ----
CREATE OR REPLACE FUNCTION public.school_get_part_time_work_cash_request_context(p_income_request_id uuid)
 RETURNS TABLE(income_request_id uuid, settlement_id uuid, year_month text, workplace_name text, teacher_name text, original_amount_jpy integer, income_request_status text, cash_request_id uuid, cash_request_status text, cash_transaction_id uuid, actual_received_amount numeric, actual_received_currency text, actual_exchange_rate numeric, cash_attempt_no integer, request_type text, transaction_type text, idempotency_key text, memo text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_request public.school_part_time_work_income_requests%rowtype;
  v_settlement public.school_part_time_work_monthly_settlements%rowtype;
begin
  if p_income_request_id is null then
    raise exception 'income request id is required';
  end if;

  select *
    into v_request
    from public.school_part_time_work_income_requests ir
   where ir.id = p_income_request_id
     and ir.deleted_at is null;

  if not found then
    raise exception 'part-time work income request not found: %', p_income_request_id;
  end if;

  select *
    into v_settlement
    from public.school_part_time_work_monthly_settlements s
   where s.id = v_request.settlement_id
     and s.deleted_at is null;

  if not found then
    raise exception 'part-time work settlement not found: %', v_request.settlement_id;
  end if;

  if v_settlement.status <> 'income_request_created'
     or v_settlement.income_request_id is distinct from v_request.id then
    raise exception 'part-time work settlement is not ready for Cash request.';
  end if;

  if v_request.currency <> 'JPY' then
    raise exception 'part-time work income request original currency must be JPY.';
  end if;

  return query
  select
    v_request.id,
    v_request.settlement_id,
    v_request.year_month,
    v_request.workplace_name,
    v_request.teacher_name,
    v_request.amount_jpy,
    v_request.status,
    v_request.cash_request_id,
    v_request.cash_request_status,
    v_request.cash_transaction_id,
    v_request.actual_received_amount,
    v_request.actual_received_currency,
    v_request.actual_exchange_rate,
    v_request.cash_attempt_no,
    'part_time_work_income_received'::text,
    'income'::text,
    concat(
      'aozora_school:school_part_time_work_income_requests:',
      v_request.id::text,
      ':part_time_work_income_received:attempt:',
      (v_request.cash_attempt_no + 1)::text
    )::text,
    v_request.memo;
end;
$function$;

-- ---- school_create_part_time_work_planned_lesson ----
CREATE OR REPLACE FUNCTION public.school_create_part_time_work_planned_lesson(p_work_date date, p_start_time time without time zone, p_end_time time without time zone, p_workplace_name text, p_subject_name text, p_class_description text DEFAULT NULL::text, p_lesson_count integer DEFAULT 1, p_cumulative_hours numeric DEFAULT 0, p_hourly_rate_jpy integer DEFAULT 0, p_transportation_fee_jpy integer DEFAULT 0, p_memo text DEFAULT NULL::text, p_teacher_name text DEFAULT '吴峰'::text)
 RETURNS TABLE(id uuid, record_kind text, planned_lesson_id uuid, generated_actual_id uuid, work_date date, start_time time without time zone, end_time time without time zone, year_month text, workplace_name text, teacher_name text, subject_name text, class_description text, planned_hours numeric, actual_hours numeric, lesson_count integer, cumulative_hours numeric, hourly_rate_jpy integer, lesson_wage_jpy integer, transportation_fee_jpy integer, memo text, settlement_id uuid, settlement_status text, income_request_id uuid, income_request_status text, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_id uuid;
  v_workplace_name text := public.school_part_time_work_validate_workplace(p_workplace_name);
  v_subject_name text := public.school_part_time_work_validate_subject(p_subject_name);
  v_planned_hours numeric(8,2) := public.school_part_time_work_calculate_hours(p_start_time, p_end_time);
  v_lesson_count integer := coalesce(p_lesson_count, 1);
  v_cumulative_hours numeric(8,2) := coalesce(p_cumulative_hours, 0);
  v_hourly_rate_jpy integer := coalesce(p_hourly_rate_jpy, 0);
  v_transportation_fee_jpy integer := coalesce(p_transportation_fee_jpy, 0);
begin
  perform public.school_require_current_part_time_work_operator();
  if p_work_date is null then
    raise exception '请选择预定日期。';
  end if;
  if v_hourly_rate_jpy < 0 then
    raise exception '时给不能小于 0。';
  end if;
  if v_lesson_count < 1 then
    raise exception '回数必须大于等于 1。';
  end if;
  if v_cumulative_hours < 0 then
    raise exception '累计课时不能小于 0。';
  end if;
  if v_transportation_fee_jpy < 0 then
    raise exception '交通费不能小于 0。';
  end if;

  insert into public.school_part_time_work_lessons (
    record_kind,
    work_date,
    start_time,
    end_time,
    year_month,
    workplace_name,
    teacher_name,
    subject_name,
    class_description,
    planned_hours,
    actual_hours,
    lesson_count,
    cumulative_hours,
    hourly_rate_jpy,
    lesson_wage_jpy,
    transportation_fee_jpy,
    memo
  )
  values (
    'planned',
    p_work_date,
    p_start_time,
    p_end_time,
    to_char(p_work_date, 'YYYY-MM'),
    v_workplace_name,
    coalesce(nullif(trim(p_teacher_name), ''), '吴峰'),
    v_subject_name,
    nullif(trim(coalesce(p_class_description, '')), ''),
    v_planned_hours,
    0,
    v_lesson_count,
    v_cumulative_hours,
    v_hourly_rate_jpy,
    0,
    v_transportation_fee_jpy,
    nullif(trim(coalesce(p_memo, '')), '')
  )
  returning school_part_time_work_lessons.id into v_id;

  return query
  select *
  from public.school_list_part_time_work_lessons(null, null, null) r
  where r.id = v_id;
end;
$function$;

-- ---- school_update_part_time_work_lesson ----
CREATE OR REPLACE FUNCTION public.school_update_part_time_work_lesson(p_id uuid, p_work_date date, p_start_time time without time zone, p_end_time time without time zone, p_workplace_name text, p_subject_name text, p_class_description text DEFAULT NULL::text, p_lesson_count integer DEFAULT 1, p_cumulative_hours numeric DEFAULT 0, p_hourly_rate_jpy integer DEFAULT 0, p_transportation_fee_jpy integer DEFAULT 0, p_memo text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, record_kind text, planned_lesson_id uuid, generated_actual_id uuid, work_date date, start_time time without time zone, end_time time without time zone, year_month text, workplace_name text, teacher_name text, subject_name text, class_description text, planned_hours numeric, actual_hours numeric, lesson_count integer, cumulative_hours numeric, hourly_rate_jpy integer, lesson_wage_jpy integer, transportation_fee_jpy integer, memo text, settlement_id uuid, settlement_status text, income_request_id uuid, income_request_status text, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_lesson public.school_part_time_work_lessons%rowtype;
  v_workplace_name text := public.school_part_time_work_validate_workplace(p_workplace_name);
  v_subject_name text := public.school_part_time_work_validate_subject(p_subject_name);
  v_hours numeric(8,2) := public.school_part_time_work_calculate_hours(p_start_time, p_end_time);
  v_lesson_count integer := coalesce(p_lesson_count, 1);
  v_cumulative_hours numeric(8,2) := coalesce(p_cumulative_hours, 0);
  v_hourly_rate_jpy integer := coalesce(p_hourly_rate_jpy, 0);
  v_transportation_fee_jpy integer := coalesce(p_transportation_fee_jpy, 0);
begin
  perform public.school_require_current_part_time_work_operator();
  if p_id is null then
    raise exception '记录 ID 不能为空。';
  end if;
  if p_work_date is null then
    raise exception '请选择日期。';
  end if;
  if v_hourly_rate_jpy < 0 then
    raise exception '时给不能小于 0。';
  end if;
  if v_lesson_count < 1 then
    raise exception '回数必须大于等于 1。';
  end if;
  if v_cumulative_hours < 0 then
    raise exception '累计课时不能小于 0。';
  end if;
  if v_transportation_fee_jpy < 0 then
    raise exception '交通费不能小于 0。';
  end if;

  select *
  into v_lesson
  from public.school_part_time_work_lessons l
  where l.id = p_id
    and deleted_at is null
  for update;

  if not found then
    raise exception '私塾打工课时不存在或已删除。';
  end if;

  if v_lesson.record_kind = 'actual' and exists (
    select 1
    from public.school_part_time_work_monthly_settlement_details d
    join public.school_part_time_work_monthly_settlements s
      on s.id = d.settlement_id
    where d.actual_lesson_id = p_id
      and s.deleted_at is null
      and s.status in ('locked', 'income_request_created')
  ) then
    raise exception '该实际课时已进入锁定结算，不能编辑。';
  end if;

  update public.school_part_time_work_lessons l
  set
    work_date = p_work_date,
    start_time = p_start_time,
    end_time = p_end_time,
    year_month = to_char(p_work_date, 'YYYY-MM'),
    workplace_name = v_workplace_name,
    subject_name = v_subject_name,
    class_description = nullif(trim(coalesce(p_class_description, '')), ''),
    planned_hours = case when v_lesson.record_kind = 'planned' then v_hours else 0 end,
    actual_hours = case when v_lesson.record_kind = 'actual' then v_hours else 0 end,
    lesson_count = v_lesson_count,
    cumulative_hours = v_cumulative_hours,
    hourly_rate_jpy = v_hourly_rate_jpy,
    lesson_wage_jpy = case when v_lesson.record_kind = 'actual' then round(v_hours * v_hourly_rate_jpy) else 0 end,
    transportation_fee_jpy = v_transportation_fee_jpy,
    memo = nullif(trim(coalesce(p_memo, '')), ''),
    updated_at = now()
  where l.id = p_id;

  return query
  select *
  from public.school_list_part_time_work_lessons(null, null, null) r
  where r.id = p_id;
end;
$function$;

-- ---- school_generate_part_time_work_actual_from_planned ----
CREATE OR REPLACE FUNCTION public.school_generate_part_time_work_actual_from_planned(p_planned_lesson_id uuid, p_actual_work_date date DEFAULT NULL::date, p_start_time time without time zone DEFAULT NULL::time without time zone, p_end_time time without time zone DEFAULT NULL::time without time zone, p_lesson_count integer DEFAULT NULL::integer, p_cumulative_hours numeric DEFAULT NULL::numeric, p_hourly_rate_jpy integer DEFAULT NULL::integer, p_transportation_fee_jpy integer DEFAULT NULL::integer, p_memo text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, record_kind text, planned_lesson_id uuid, generated_actual_id uuid, work_date date, start_time time without time zone, end_time time without time zone, year_month text, workplace_name text, teacher_name text, subject_name text, class_description text, planned_hours numeric, actual_hours numeric, lesson_count integer, cumulative_hours numeric, hourly_rate_jpy integer, lesson_wage_jpy integer, transportation_fee_jpy integer, memo text, settlement_id uuid, settlement_status text, income_request_id uuid, income_request_status text, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_planned public.school_part_time_work_lessons%rowtype;
  v_actual_id uuid;
  v_work_date date;
  v_start_time time;
  v_end_time time;
  v_actual_hours numeric(8,2);
  v_lesson_count integer;
  v_cumulative_hours numeric(8,2);
  v_hourly_rate_jpy integer;
  v_transportation_fee_jpy integer;
begin
  perform public.school_require_current_part_time_work_operator();
  select *
  into v_planned
  from public.school_part_time_work_lessons l
  where l.id = p_planned_lesson_id
    and l.record_kind = 'planned'
    and l.deleted_at is null
  for update;

  if not found then
    raise exception '预定打工课时不存在或已删除。';
  end if;

  if exists (
    select 1
    from public.school_part_time_work_lessons a
    where a.planned_lesson_id = p_planned_lesson_id
      and a.record_kind = 'actual'
      and a.deleted_at is null
  ) then
    raise exception '该预定课时已经生成实际课时。';
  end if;

  v_work_date := coalesce(p_actual_work_date, v_planned.work_date);
  v_start_time := coalesce(p_start_time, v_planned.start_time);
  v_end_time := coalesce(p_end_time, v_planned.end_time);
  v_actual_hours := public.school_part_time_work_calculate_hours(v_start_time, v_end_time);
  v_lesson_count := coalesce(p_lesson_count, v_planned.lesson_count, 1);
  v_cumulative_hours := coalesce(p_cumulative_hours, v_planned.cumulative_hours, 0);
  v_hourly_rate_jpy := coalesce(p_hourly_rate_jpy, v_planned.hourly_rate_jpy);
  v_transportation_fee_jpy := coalesce(p_transportation_fee_jpy, v_planned.transportation_fee_jpy);

  if v_hourly_rate_jpy < 0 then
    raise exception '时给不能小于 0。';
  end if;
  if v_lesson_count < 1 then
    raise exception '回数必须大于等于 1。';
  end if;
  if v_cumulative_hours < 0 then
    raise exception '累计课时不能小于 0。';
  end if;
  if v_transportation_fee_jpy < 0 then
    raise exception '交通费不能小于 0。';
  end if;

  insert into public.school_part_time_work_lessons (
    record_kind,
    planned_lesson_id,
    work_date,
    start_time,
    end_time,
    year_month,
    workplace_name,
    teacher_name,
    subject_name,
    class_description,
    planned_hours,
    actual_hours,
    lesson_count,
    cumulative_hours,
    hourly_rate_jpy,
    lesson_wage_jpy,
    transportation_fee_jpy,
    memo
  )
  values (
    'actual',
    v_planned.id,
    v_work_date,
    v_start_time,
    v_end_time,
    to_char(v_work_date, 'YYYY-MM'),
    v_planned.workplace_name,
    v_planned.teacher_name,
    v_planned.subject_name,
    v_planned.class_description,
    0,
    v_actual_hours,
    v_lesson_count,
    v_cumulative_hours,
    v_hourly_rate_jpy,
    round(v_actual_hours * v_hourly_rate_jpy),
    v_transportation_fee_jpy,
    coalesce(nullif(trim(coalesce(p_memo, '')), ''), v_planned.memo)
  )
  returning school_part_time_work_lessons.id into v_actual_id;

  return query
  select *
  from public.school_list_part_time_work_lessons(null, null, null) r
  where r.id = v_actual_id;
end;
$function$;

-- ---- school_delete_part_time_work_lesson ----
CREATE OR REPLACE FUNCTION public.school_delete_part_time_work_lesson(p_id uuid, p_confirm_generated_actual boolean DEFAULT false)
 RETURNS TABLE(deleted_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_lesson public.school_part_time_work_lessons%rowtype;
  v_now timestamptz := now();
  v_count integer := 0;
begin
  perform public.school_require_current_part_time_work_operator();
  select *
  into v_lesson
  from public.school_part_time_work_lessons l
  where l.id = p_id
    and l.deleted_at is null
  for update;

  if not found then
    raise exception '私塾打工课时不存在或已删除。';
  end if;

  if v_lesson.record_kind = 'actual' and exists (
    select 1
    from public.school_part_time_work_monthly_settlement_details d
    join public.school_part_time_work_monthly_settlements s
      on s.id = d.settlement_id
    where d.actual_lesson_id = p_id
      and s.deleted_at is null
      and s.status in ('locked', 'income_request_created')
  ) then
    raise exception '该实际课时已进入锁定结算，不能删除。';
  end if;

  if v_lesson.record_kind = 'planned' and exists (
    select 1
    from public.school_part_time_work_lessons a
    where a.planned_lesson_id = p_id
      and a.record_kind = 'actual'
      and a.deleted_at is null
  ) and not p_confirm_generated_actual then
    raise exception '该预定课时已生成实际课时。请再次确认后删除。';
  end if;

  if v_lesson.record_kind = 'planned' and exists (
    select 1
    from public.school_part_time_work_lessons a
    join public.school_part_time_work_monthly_settlement_details d
      on d.actual_lesson_id = a.id
    join public.school_part_time_work_monthly_settlements s
      on s.id = d.settlement_id
    where a.planned_lesson_id = p_id
      and a.record_kind = 'actual'
      and a.deleted_at is null
      and s.deleted_at is null
      and s.status in ('locked', 'income_request_created')
  ) then
    raise exception '该预定课时的实际课时已进入锁定结算，不能删除。';
  end if;

  update public.school_part_time_work_lessons l
  set deleted_at = v_now, updated_at = v_now
  where l.id = p_id
    and l.deleted_at is null;
  get diagnostics v_count = row_count;

  if v_lesson.record_kind = 'planned' and p_confirm_generated_actual then
    update public.school_part_time_work_lessons a
    set deleted_at = v_now, updated_at = v_now
    where a.planned_lesson_id = p_id
      and a.record_kind = 'actual'
      and a.deleted_at is null
      and not exists (
        select 1
        from public.school_part_time_work_monthly_settlement_details d
        join public.school_part_time_work_monthly_settlements s
          on s.id = d.settlement_id
        where d.actual_lesson_id = a.id
          and s.deleted_at is null
          and s.status in ('locked', 'income_request_created')
      );
    get diagnostics v_count = row_count;
    v_count := v_count + 1;
  end if;

  return query select v_count;
end;
$function$;

DO $rbpost$
DECLARE t record; v_n int; v_md5 text; v_acl text;
BEGIN
  FOR t IN SELECT * FROM (VALUES
    ('school_get_profit_summary_schoolwide_v1','c140ce7a34a308eae4dfb017326ada0e','{postgres=X/postgres,authenticated=X/postgres}'),
    ('school_list_part_time_work_lessons','dfec8d798dd87e3a6542fb775f0c77c6','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'),
    ('school_list_part_time_work_monthly_settlements','3c331967f5fd017010a7d530a59fbcfe','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'),
    ('school_get_part_time_work_settlement_export','6b4c15e20b92d8f634d35e40302a470f','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'),
    ('school_get_part_time_work_cash_request_context','d4350bbe88d68f43394779e802407c18','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'),
    ('school_create_part_time_work_planned_lesson','7650ad340f790e2a491862013f988220','{postgres=X/postgres,authenticated=X/postgres}'),
    ('school_update_part_time_work_lesson','901e029935f229bcc9a01e0dddb75963','{postgres=X/postgres,authenticated=X/postgres}'),
    ('school_generate_part_time_work_actual_from_planned','84e9e32e7254fa7b76ff868d2d437107','{postgres=X/postgres,authenticated=X/postgres}'),
    ('school_delete_part_time_work_lesson','8891155ee046e57d272c23eb0fb5ec8f','{postgres=X/postgres,authenticated=X/postgres}')
    ) AS v(proname, md5, acl)
  LOOP
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=t.proname;
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'PTWP_RB_POST_ARITY: public.% 有 % 个（应为 1）', t.proname, v_n;
    END IF;
    SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,'') INTO v_md5, v_acl
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=t.proname;
    IF v_md5 <> t.md5 THEN
      RAISE EXCEPTION 'PTWP_RB_POST_MD5: % 的定义为 %，期望 %', t.proname, v_md5, t.md5;
    END IF;
    IF v_acl <> t.acl THEN
      RAISE EXCEPTION 'PTWP_RB_POST_ACL: % 的 ACL 为 %，期望 %', t.proname, v_acl, t.acl;
    END IF;
  END LOOP;

  -- E 只撤授权，函数体必须原样
  SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,'') INTO v_md5, v_acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_update_personal_cash_income_linkage_event_status';
  IF v_md5 <> '48a6c54693e746c7426caec01e8056c1' THEN
    RAISE EXCEPTION 'PTWP_RB_POST_E_MD5: school_update_personal_cash_income_linkage_event_status 的定义为 %，期望 %（本脚本不改它的函数体）', v_md5, '48a6c54693e746c7426caec01e8056c1';
  END IF;
  IF v_acl <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION 'PTWP_RB_POST_E_ACL: school_update_personal_cash_income_linkage_event_status 的 ACL 为 %，期望 %', v_acl, '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}';
  END IF;

  RAISE NOTICE 'PTWP_RB_POST: 9 个函数的 md5/ACL 与 school_update_personal_cash_income_linkage_event_status 的 md5/ACL 全部符合预期';
END
$rbpost$;

DO $rbpostg$
DECLARE t record; v_def text; v_a int; v_o int;
BEGIN
  FOR t IN SELECT * FROM (VALUES
    ('school_list_part_time_work_lessons',0,0),
    ('school_list_part_time_work_monthly_settlements',0,0),
    ('school_get_part_time_work_settlement_export',0,0),
    ('school_get_part_time_work_cash_request_context',0,0),
    ('school_create_part_time_work_planned_lesson',0,1),
    ('school_update_part_time_work_lesson',0,1),
    ('school_generate_part_time_work_actual_from_planned',0,1),
    ('school_delete_part_time_work_lesson',0,1)
    ) AS v(proname, n_admin, n_operator)
  LOOP
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=t.proname;
    v_a := (length(v_def)-length(replace(v_def,'school_require_current_part_time_work_admin','')))/length('school_require_current_part_time_work_admin');
    v_o := (length(v_def)-length(replace(v_def,'school_require_current_part_time_work_operator','')))/length('school_require_current_part_time_work_operator');
    -- ⚠️ 'school_require_current_part_time_work_admin' 不是 'school_require_current_part_time_work_operator' 的子串，两个计数互不干扰
    IF v_a <> t.n_admin OR v_o <> t.n_operator THEN
      RAISE EXCEPTION 'PTWP_RB_POST_GUARD_SHAPE: % 的 PTW admin 守卫 % 次（期望 %）、operator 守卫 % 次（期望 %）',
        t.proname, v_a, t.n_admin, v_o, t.n_operator;
    END IF;
  END LOOP;
  RAISE NOTICE 'PTWP_RB_POST: 8 个打工函数的守卫调用形状符合预期';
END
$rbpostg$;

DO $rbpostp$
DECLARE p record; v_n int; v_rls boolean; v_force boolean; v_acl text;
BEGIN
  -- 收入表
  SELECT c.relrowsecurity, c.relforcerowsecurity INTO v_rls, v_force
    FROM pg_class c WHERE c.oid='public.school_income_records'::regclass;
  IF v_rls IS NOT TRUE OR v_force IS NOT FALSE THEN
    RAISE EXCEPTION 'PTWP_RB_POST_INC_RLS: school_income_records rowsecurity=% force=%（期望 t / f）', v_rls, v_force;
  END IF;
  SELECT * INTO p FROM pg_policies
   WHERE schemaname='public' AND tablename='school_income_records' AND policyname='school_select_operational_income_records';
  IF NOT FOUND OR p.permissive <> 'PERMISSIVE' OR p.qual <> '((status <> ''incident_quarantined''::text) AND (operational_excluded IS NOT TRUE))' THEN
    RAISE EXCEPTION 'PTWP_RB_POST_INC_OLD_POLICY: 原有 school_select_operational_income_records 缺失或已漂移（本脚本不碰它）';
  END IF;
  SELECT count(*) INTO v_n FROM pg_policies WHERE schemaname='public' AND tablename='school_income_records';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'PTWP_RB_POST_INC_POLICY_COUNT: school_income_records 上有 % 条策略（期望 1）', v_n;
  END IF;

  -- 关联表
  SELECT c.relrowsecurity, c.relforcerowsecurity, coalesce(c.relacl::text,'')
    INTO v_rls, v_force, v_acl
    FROM pg_class c WHERE c.oid='public.school_personal_cash_income_linkage_events'::regclass;
  IF v_rls IS NOT FALSE OR v_force IS NOT FALSE THEN
    RAISE EXCEPTION 'PTWP_RB_POST_EV_RLS: school_personal_cash_income_linkage_events rowsecurity=% force=%（期望 f / f）', v_rls, v_force;
  END IF;
  IF v_acl <> '{postgres=arwdDxtm/postgres,authenticated=rm/postgres,service_role=arwdDxtm/postgres}' THEN
    RAISE EXCEPTION 'PTWP_RB_POST_EV_ACL: school_personal_cash_income_linkage_events 的授权为 %，期望 %（本脚本不改它的授权）', v_acl, '{postgres=arwdDxtm/postgres,authenticated=rm/postgres,service_role=arwdDxtm/postgres}';
  END IF;
  SELECT count(*) INTO v_n FROM pg_policies WHERE schemaname='public' AND tablename='school_personal_cash_income_linkage_events';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'PTWP_RB_POST_EV_POLICY_COUNT: school_personal_cash_income_linkage_events 上有 % 条策略（期望 0）', v_n;
  END IF;

  RAISE NOTICE 'PTWP_RB_POST: 两张表的 RLS 开关、授权与策略集合符合预期';
END
$rbpostp$;

\if :is_commit
COMMIT;
\echo '>>> 已 COMMIT'
\else
ROLLBACK;
\echo '>>> 已 ROLLBACK（rehearsal）'
\endif
