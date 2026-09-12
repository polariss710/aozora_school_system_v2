-- =============================================================================
-- 账户调整 / 调拨：封堵直写 + 四个入口加 admin 守卫
--
-- 背景  演示线 2026-09-12 的生产 schema 分析发现，Codex 实时目录复核确认：
--
--   school_account_adjustments / school_account_transfers
--     · GRANT ALL TO authenticated（八项全给，含 TRUNCATE）
--     · RLS 未启用、策略 0 条、业务写保护触发器 0 个
--   ⇒ 持有效登录态者可用公开 anon key + 自己的 JWT【直接写这两张表】，
--      绕过全部 RPC 守卫。（anon 无授权，前提是有一个有效账号。）
--   ⚠️ 数据库权限 ≠ HTTP 入口：持有 TRUNCATE 权限，不等于 REST 接口
--      提供 TRUNCATE 动作。撤权是按【数据库权限面】收口，
--      不是在断言「REST 现在能 TRUNCATE」。（Codex 2026-09-12 更正）
--
-- ⚠️ 而且不止直写：这两张表的【四个正规读写函数】
--    create/reverse × adjustment/transfer
--    函数体内 school_require_* / auth.uid() / membership 检查【全部 0 次】。
--    ⇒ 只撤表权限的话，任何登录账号仍可经正规 RPC 调整账户余额、
--      在账户间调拨、以及撤销这两类操作。
--
-- 本脚本两件事，缺一不可
--   A. 撤销 authenticated 在两张表上的 INSERT/UPDATE/DELETE/TRUNCATE
--      ⚠️ 必须含 TRUNCATE：GRANT ALL 是含它的，只撤前三项仍能清空整表。
--      ⚠️ 且【RLS 不约束 TRUNCATE】，所以补 RLS 不能替代撤权。
--      保留 SELECT/REFERENCES/TRIGGER/MAINTAIN（对齐 school_income_records）：
--      账户流水详情页按 related_table 动态 .from() 读这两张表，撤了会断。
--   B. 四个函数各新增一行 admin 守卫。
--      业务负责人 2026-09-12 定：调整余额与账户间调拨都是资金实际变动，
--      按分工属出纳 ⇒ 仅 active admin。账户页本来也不在 operator 白名单里。
--
-- ⛔ 不改：service_role 的任何授权、owner、签名、RLS 开关、业务数据、前端。
--
-- 用法
--   psql -v ON_ERROR_STOP=1 -v mode=rehearsal -f <本文件>
--   psql -v ON_ERROR_STOP=1 -v mode=commit    -f <本文件>
-- =============================================================================
\set ON_ERROR_STOP on
SELECT (:'mode'='commit') AS is_commit, (:'mode'='rehearsal') AS is_rehearsal \gset
\if :is_commit
\echo '>>> mode=commit —— 通过全部断言后将 COMMIT'
\elif :is_rehearsal
\echo '>>> mode=rehearsal —— 通过全部断言后将 ROLLBACK'
\else
-- ⚠️ 不能用裸 \quit —— 它的退出码是 0，自动化会把「根本没执行」读成「成功」。
--    用 RAISE 让 psql 以非零码退出（ON_ERROR_STOP 已开）。
DO $mode$ BEGIN
  RAISE EXCEPTION 'ACCT_MODE_INVALID: 必须指定 -v mode=rehearsal 或 -v mode=commit';
END $mode$;
\endif

BEGIN;

-- 四个函数将依赖 admin 守卫；不核实就等于把准入建在没验过的对象上。

DO $g$
DECLARE v_n int; v_md5 text; v_acl text;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_require_current_app_admin';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'ACCT_PRE_GUARD_ARITY: public.school_require_current_app_admin 有 % 个（应为 1）', v_n;
  END IF;
  SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,'') INTO v_md5, v_acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_require_current_app_admin';
  IF v_md5 <> 'f9e6563d875bbb1bc61be31531da3d69' THEN
    RAISE EXCEPTION 'ACCT_PRE_GUARD_DRIFT: 守卫定义为 %，期望 %', v_md5, 'f9e6563d875bbb1bc61be31531da3d69';
  END IF;
  IF v_acl <> '{postgres=X/postgres,authenticated=X/postgres}' THEN
    RAISE EXCEPTION 'ACCT_PRE_GUARD_ACL: 守卫 ACL 为 %，期望 %', v_acl, '{postgres=X/postgres,authenticated=X/postgres}';
  END IF;
  RAISE NOTICE 'ACCT_PRE: admin 守卫在位且与取证一致';
END
$g$;

-- 四个函数的 COMMENT【钉死】取证原文；执行属性用 pre 段捕获 + post 段比对。
-- ⚠️ 只捕获检测不出【部署前就已存在】的注释漂移 —— 捕到的就是被改过的值，
--    post 自然对得上。这个缺口是本批的阴性对照自己暴露出来的。
-- 同样能证明「只改了定义」，且不必猜任何没逐字拿到的值。
CREATE TEMP TABLE acct_before ON COMMIT DROP AS
SELECT p.proname AS b_name,
       coalesce(obj_description(p.oid,'pg_proc'),'<NULL>') AS b_cmt,
       p.proisstrict AS b_strict, p.proparallel AS b_par, p.proleakproof AS b_leak,
       p.procost AS b_cost, p.prorows AS b_rows, pg_get_userbyid(p.proowner) AS b_owner,
       p.prosecdef AS b_secdef, coalesce(array_to_string(p.proconfig,', '),'<NULL>') AS b_cfg
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN ('school_create_account_adjustment','school_create_account_transfer','school_reverse_account_adjustment','school_reverse_account_transfer');

DO $cap$
BEGIN
  IF (SELECT count(*) FROM acct_before) <> 4 THEN
    RAISE EXCEPTION 'ACCT_PRE_ARITY: 四个函数不是恰好各 1 个（实得 %）',
      (SELECT count(*) FROM acct_before);
  END IF;
  RAISE NOTICE 'ACCT_PRE: 已记下 4 个函数的 COMMENT 与执行属性';
END
$cap$;

DO $pre$
DECLARE t record; v_n int; v_def text; v_md5 text; v_acl text; v_g int; b record;
BEGIN
  FOR t IN SELECT * FROM (VALUES
    ('school_create_account_adjustment','3298c544ad40df0d74393b259010d7ac','Draft RPC for v2 account adjustment creation: creates account adjustment, updates account balance, and inserts account_adjustment transaction.'),
    ('school_create_account_transfer','705b60a2f506000bf7b8fd25687b0b6d','Draft RPC for v2 account transfer creation: creates a posted transfer, updates two account balances, and inserts transfer_out / transfer_in transactions.'),
    ('school_reverse_account_adjustment','b38da4cb98eb98bcf6978892f229d2c4','Draft RPC for v2 account adjustment reversal: marks an account adjustment as reversed, restores account balance by the opposite amount, and inserts an account_adjustment_reversal transaction.'),
    ('school_reverse_account_transfer','3c2a594749d913a0ac3690d62bc63c75','Draft RPC for v2 account transfer reversal: marks an account transfer as reversed, restores the original from-account balance, reverses the original to-account balance, and inserts transfer_reverse_in / transfer_reverse_out transactions.')
  ) AS v(proname, md5, cmt) LOOP
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=t.proname;
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'ACCT_PRE_ARITY: %有 % 个（应为 1）', t.proname, v_n;
    END IF;

    SELECT pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,'')
      INTO v_def, v_md5, v_acl
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=t.proname;

    IF v_md5 <> t.md5 THEN
      RAISE EXCEPTION 'ACCT_PRE_MD5: % 定义为 %，期望 %', t.proname, v_md5, t.md5;
    END IF;
    IF v_acl <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
      RAISE EXCEPTION 'ACCT_PRE_ACL: % 的 ACL 为 %，期望 %', t.proname, v_acl, '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}';
    END IF;

    v_g := (length(v_def)-length(replace(v_def,'school_require_current_app_admin','')))/length('school_require_current_app_admin');
    IF v_g <> 0 THEN
      RAISE EXCEPTION 'ACCT_PRE_GUARD_CALLS: % 内 admin 守卫 % 次（期望 0）', t.proname, v_g;
    END IF;

    -- 钉死比对：这条才抓得住【部署前就已存在】的注释漂移。
    -- 下面与 pre 段捕获的比对只能证明「本脚本没改」，检测不出既有漂移。
    IF coalesce(obj_description(
         (SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='public' AND p.proname=t.proname),'pg_proc'),'<NULL>') <> t.cmt THEN
      RAISE EXCEPTION 'ACCT_PRE_COMMENT: % 的注释与取证基线不符', t.proname;
    END IF;

    SELECT * INTO b FROM acct_before WHERE b_name = t.proname;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'ACCT_PRE_CAPTURE_MISSING: pre 段没记下 %', t.proname;
    END IF;
    PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname=t.proname
        AND coalesce(obj_description(p.oid,'pg_proc'),'<NULL>')=b.b_cmt
        AND p.proisstrict=b.b_strict AND p.proparallel=b.b_par AND p.proleakproof=b.b_leak
        AND p.procost=b.b_cost AND p.prorows=b.b_rows AND p.prosecdef=b.b_secdef
        AND pg_get_userbyid(p.proowner)=b.b_owner
        AND coalesce(array_to_string(p.proconfig,', '),'<NULL>')=b.b_cfg;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'ACCT_PRE_ATTRS: % 的注释 / owner / secdef / proconfig / 执行属性与 pre 段不一致', t.proname;
    END IF;
  END LOOP;
  RAISE NOTICE 'ACCT_PRE: 4 个函数的 md5 / ACL / 守卫调用 / 注释 / 执行属性 全部符合预期';
END
$pre$;

DO $pretbl$
DECLARE t record; v_acl text; v_rls boolean; v_force boolean; v_pol int;
BEGIN
  FOR t IN SELECT unnest(ARRAY['school_account_adjustments','school_account_transfers']) AS tbl LOOP
    SELECT coalesce(c.relacl::text,''), c.relrowsecurity, c.relforcerowsecurity
      INTO v_acl, v_rls, v_force
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relname=t.tbl;
    IF v_acl <> '{postgres=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}' THEN
      RAISE EXCEPTION 'ACCT_PRE_TBL_ACL: % 的 ACL 为 %，期望 %', t.tbl, v_acl, '{postgres=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}';
    END IF;
    -- 本脚本【不动】RLS 开关，前后都应是 false/false
    IF v_rls IS NOT FALSE OR v_force IS NOT FALSE THEN
      RAISE EXCEPTION 'ACCT_PRE_TBL_RLS: % rowsecurity=% force=%（本批不改，期望 f/f）', t.tbl, v_rls, v_force;
    END IF;
    SELECT count(*) INTO v_pol FROM pg_policies
     WHERE schemaname='public' AND tablename=t.tbl;
    IF v_pol <> 0 THEN
      RAISE EXCEPTION 'ACCT_PRE_TBL_POLICY: % 上有 % 条策略（期望 0）', t.tbl, v_pol;
    END IF;
  END LOOP;
  RAISE NOTICE 'ACCT_PRE: 两张表的 ACL / RLS 开关 / 策略数 全部符合预期';
END
$pretbl$;

-- ===== A. 撤销 authenticated 的写权限（含 TRUNCATE）=====
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.school_account_adjustments FROM authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE public.school_account_transfers FROM authenticated;

-- ===== B. 四个函数各新增一行 admin 守卫 =====
-- ---- school_create_account_adjustment ----
CREATE OR REPLACE FUNCTION public.school_create_account_adjustment(p_adjustment_date date, p_business_entity_id uuid, p_account_id uuid, p_amount numeric, p_reason text, p_note text DEFAULT NULL::text)
 RETURNS TABLE(adjustment_id uuid, account_transaction_id uuid, account_id uuid, business_entity_id uuid, old_balance numeric, new_balance numeric, amount numeric, currency text, year_month text, status text, transaction_type text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_now timestamptz := now();
  v_business_entity public.school_business_entities%rowtype;
  v_account public.school_accounts%rowtype;
  v_adjustment_id uuid;
  v_account_transaction_id uuid;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_year_month text;
  v_old_balance numeric;
  v_new_balance numeric;
begin
  perform public.school_require_current_app_admin();
  if p_adjustment_date is null then
    raise exception '请选择调整日期。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  if p_account_id is null then
    raise exception '请选择调整账户。';
  end if;

  if p_amount is null or p_amount = 0 then
    raise exception '调整金额不能为 0。';
  end if;

  if v_reason is null then
    raise exception '调整原因不能为空。';
  end if;

  perform public.school_assert_new_business_entity_allowed(
    p_business_entity_id,
    '账户调整'
  );

  select *
  into v_business_entity
  from public.school_business_entities be
  where be.id = p_business_entity_id
    and be.is_active = true;

  if not found then
    raise exception '业务归属无效或已停用。';
  end if;

  select *
  into v_account
  from public.school_accounts a
  where a.id = p_account_id
    and coalesce(a.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '调整账户不存在或不可用。';
  end if;

  if v_account.is_active is not true then
    raise exception '调整账户已停用。';
  end if;

  if v_account.business_entity_id is distinct from p_business_entity_id then
    raise exception '调整账户与业务归属不一致。';
  end if;

  if v_account.currency not in ('JPY', 'CNY') then
    raise exception '暂不支持该账户币种：%。', v_account.currency;
  end if;

  v_year_month := to_char(p_adjustment_date, 'YYYY-MM');
  v_old_balance := coalesce(v_account.current_balance, 0);
  v_new_balance := v_old_balance + p_amount;

  insert into public.school_account_adjustments (
    business_entity_id,
    account_id,
    adjustment_date,
    year_month,
    currency,
    amount,
    balance_before,
    balance_after,
    reason,
    note,
    status,
    account_transaction_id,
    reversed_at,
    reversal_reason,
    reversal_account_transaction_id,
    app_type,
    created_at,
    updated_at
  )
  values (
    p_business_entity_id,
    v_account.id,
    p_adjustment_date,
    v_year_month,
    v_account.currency,
    p_amount,
    v_old_balance,
    v_new_balance,
    v_reason,
    v_note,
    'posted',
    null,
    null,
    null,
    null,
    'school',
    v_now,
    v_now
  )
  returning id into v_adjustment_id;

  update public.school_accounts a
  set
    current_balance = v_new_balance,
    updated_at = v_now
  where a.id = v_account.id;

  insert into public.school_account_transactions (
    account_id,
    business_entity_id,
    transaction_date,
    year_month,
    transaction_type,
    related_table,
    related_id,
    currency,
    amount,
    balance_after,
    description,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    v_account.id,
    p_business_entity_id,
    p_adjustment_date,
    v_year_month,
    'account_adjustment',
    'school_account_adjustments',
    v_adjustment_id,
    v_account.currency,
    p_amount,
    v_new_balance,
    '账户调整：' || v_reason,
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_account_transaction_id;

  update public.school_account_adjustments a
  set
    account_transaction_id = v_account_transaction_id,
    updated_at = v_now
  where a.id = v_adjustment_id;

  return query
  select
    v_adjustment_id,
    v_account_transaction_id,
    v_account.id,
    p_business_entity_id,
    v_old_balance,
    v_new_balance,
    p_amount,
    v_account.currency,
    v_year_month,
    'posted'::text,
    'account_adjustment'::text;
end;
$function$;

-- ---- school_create_account_transfer ----
CREATE OR REPLACE FUNCTION public.school_create_account_transfer(p_transfer_date date, p_business_entity_id uuid, p_from_account_id uuid, p_to_account_id uuid, p_amount numeric, p_reason text, p_note text DEFAULT NULL::text)
 RETURNS TABLE(transfer_id uuid, from_account_transaction_id uuid, to_account_transaction_id uuid, from_account_id uuid, to_account_id uuid, business_entity_id uuid, from_account_old_balance numeric, from_account_new_balance numeric, to_account_old_balance numeric, to_account_new_balance numeric, amount numeric, currency text, year_month text, status text, from_transaction_type text, to_transaction_type text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_now timestamptz := now();
  v_business_entity public.school_business_entities%rowtype;
  v_account public.school_accounts%rowtype;
  v_from_account public.school_accounts%rowtype;
  v_to_account public.school_accounts%rowtype;
  v_account_count integer := 0;
  v_transfer_id uuid;
  v_from_account_transaction_id uuid;
  v_to_account_transaction_id uuid;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_year_month text;
  v_from_account_old_balance numeric;
  v_from_account_new_balance numeric;
  v_to_account_old_balance numeric;
  v_to_account_new_balance numeric;
begin
  perform public.school_require_current_app_admin();
  if p_transfer_date is null then
    raise exception '请选择转账日期。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  if p_from_account_id is null then
    raise exception '请选择转出账户。';
  end if;

  if p_to_account_id is null then
    raise exception '请选择转入账户。';
  end if;

  if p_from_account_id = p_to_account_id then
    raise exception '转出账户和转入账户不能相同。';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception '转账金额必须大于 0。';
  end if;

  if v_reason is null then
    raise exception '转账原因不能为空。';
  end if;

  perform public.school_assert_new_business_entity_allowed(
    p_business_entity_id,
    '账户转账'
  );

  select *
  into v_business_entity
  from public.school_business_entities be
  where be.id = p_business_entity_id
    and be.is_active = true;

  if not found then
    raise exception '业务归属无效或已停用。';
  end if;

  for v_account in
    select *
    from public.school_accounts a
    where a.id = any (array[p_from_account_id, p_to_account_id])
    order by a.id
    for update
  loop
    v_account_count := v_account_count + 1;

    if v_account.id = p_from_account_id then
      v_from_account := v_account;
    elsif v_account.id = p_to_account_id then
      v_to_account := v_account;
    end if;
  end loop;

  if v_account_count <> 2 then
    raise exception '转账账户不存在或不可用。';
  end if;

  if coalesce(v_from_account.app_type, '') <> 'school'
    or coalesce(v_to_account.app_type, '') <> 'school' then
    raise exception '转账账户不存在或不可用。';
  end if;

  if v_from_account.is_active is not true
    or v_to_account.is_active is not true then
    raise exception '转账账户已停用。';
  end if;

  if v_from_account.business_entity_id is distinct from p_business_entity_id
    or v_to_account.business_entity_id is distinct from p_business_entity_id then
    raise exception '转账账户必须属于同一业务归属。';
  end if;

  if v_from_account.currency is distinct from v_to_account.currency then
    raise exception '转出账户和转入账户币种必须一致。';
  end if;

  if coalesce(v_from_account.currency, '') not in ('JPY', 'CNY') then
    raise exception '暂不支持该账户币种：%。', v_from_account.currency;
  end if;

  v_year_month := to_char(p_transfer_date, 'YYYY-MM');
  v_from_account_old_balance := coalesce(v_from_account.current_balance, 0);
  v_to_account_old_balance := coalesce(v_to_account.current_balance, 0);
  v_from_account_new_balance := v_from_account_old_balance - p_amount;
  v_to_account_new_balance := v_to_account_old_balance + p_amount;

  insert into public.school_account_transfers (
    business_entity_id,
    from_account_id,
    to_account_id,
    transfer_date,
    year_month,
    currency,
    amount,
    from_balance_before,
    from_balance_after,
    to_balance_before,
    to_balance_after,
    reason,
    note,
    status,
    from_account_transaction_id,
    to_account_transaction_id,
    reversed_at,
    reversal_reason,
    reversal_from_account_transaction_id,
    reversal_to_account_transaction_id,
    app_type,
    created_at,
    updated_at
  )
  values (
    p_business_entity_id,
    p_from_account_id,
    p_to_account_id,
    p_transfer_date,
    v_year_month,
    v_from_account.currency,
    p_amount,
    v_from_account_old_balance,
    v_from_account_new_balance,
    v_to_account_old_balance,
    v_to_account_new_balance,
    v_reason,
    v_note,
    'posted',
    null,
    null,
    null,
    null,
    null,
    null,
    'school',
    v_now,
    v_now
  )
  returning id into v_transfer_id;

  update public.school_accounts a
  set
    current_balance = v_from_account_new_balance,
    updated_at = v_now
  where a.id = p_from_account_id;

  insert into public.school_account_transactions (
    account_id,
    business_entity_id,
    transaction_date,
    year_month,
    transaction_type,
    related_table,
    related_id,
    currency,
    amount,
    balance_after,
    description,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    p_from_account_id,
    p_business_entity_id,
    p_transfer_date,
    v_year_month,
    'transfer_out',
    'school_account_transfers',
    v_transfer_id,
    v_from_account.currency,
    -p_amount,
    v_from_account_new_balance,
    '账户转账转出：' || v_reason,
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_from_account_transaction_id;

  update public.school_accounts a
  set
    current_balance = v_to_account_new_balance,
    updated_at = v_now
  where a.id = p_to_account_id;

  insert into public.school_account_transactions (
    account_id,
    business_entity_id,
    transaction_date,
    year_month,
    transaction_type,
    related_table,
    related_id,
    currency,
    amount,
    balance_after,
    description,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    p_to_account_id,
    p_business_entity_id,
    p_transfer_date,
    v_year_month,
    'transfer_in',
    'school_account_transfers',
    v_transfer_id,
    v_to_account.currency,
    p_amount,
    v_to_account_new_balance,
    '账户转账转入：' || v_reason,
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_to_account_transaction_id;

  update public.school_account_transfers t
  set
    from_account_transaction_id = v_from_account_transaction_id,
    to_account_transaction_id = v_to_account_transaction_id,
    updated_at = v_now
  where t.id = v_transfer_id;

  return query
  select
    v_transfer_id,
    v_from_account_transaction_id,
    v_to_account_transaction_id,
    p_from_account_id,
    p_to_account_id,
    p_business_entity_id,
    v_from_account_old_balance,
    v_from_account_new_balance,
    v_to_account_old_balance,
    v_to_account_new_balance,
    p_amount,
    v_from_account.currency,
    v_year_month,
    'posted'::text,
    'transfer_out'::text,
    'transfer_in'::text;
end;
$function$;

-- ---- school_reverse_account_adjustment ----
CREATE OR REPLACE FUNCTION public.school_reverse_account_adjustment(p_adjustment_id uuid, p_reversal_date date, p_reason text DEFAULT NULL::text)
 RETURNS TABLE(adjustment_id uuid, reversal_account_transaction_id uuid, account_id uuid, business_entity_id uuid, account_old_balance numeric, account_new_balance numeric, original_amount numeric, reversal_amount numeric, currency text, year_month text, status text, transaction_type text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_now timestamptz := now();
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_year_month text;
  v_adjustment public.school_account_adjustments%rowtype;
  v_original_transaction public.school_account_transactions%rowtype;
  v_account public.school_accounts%rowtype;
  v_original_transaction_count integer := 0;
  v_existing_reversal_count integer := 0;
  v_account_old_balance numeric;
  v_account_new_balance numeric;
  v_reversal_amount numeric;
  v_reversal_transaction_id uuid;
begin
  perform public.school_require_current_app_admin();
  if p_adjustment_id is null then
    raise exception '请选择要撤销的账户调整。';
  end if;

  if p_reversal_date is null then
    raise exception '请选择撤销日期。';
  end if;

  select *
  into v_adjustment
  from public.school_account_adjustments a
  where a.id = p_adjustment_id
    and coalesce(a.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '账户调整记录不存在。';
  end if;

  if v_adjustment.status = 'reversed'
    or v_adjustment.reversed_at is not null
    or v_adjustment.reversal_account_transaction_id is not null then
    raise exception '该账户调整已撤销，不能重复撤销。';
  end if;

  if v_adjustment.status is distinct from 'posted' then
    raise exception '只能撤销已过账的账户调整。';
  end if;

  if v_adjustment.account_transaction_id is null then
    raise exception '账户调整原始流水缺失，不能撤销。';
  end if;

  if coalesce(v_adjustment.amount, 0) = 0
    or nullif(trim(coalesce(v_adjustment.currency, '')), '') is null then
    raise exception '账户调整金额或币种无效，不能撤销。';
  end if;

  select count(*)::integer
  into v_existing_reversal_count
  from public.school_account_transactions t
  where t.related_table = 'school_account_adjustments'
    and t.related_id = v_adjustment.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'account_adjustment_reversal';

  if v_existing_reversal_count > 0 then
    raise exception '该账户调整已撤销，不能重复撤销。';
  end if;

  select count(*)::integer
  into v_original_transaction_count
  from public.school_account_transactions t
  where t.related_table = 'school_account_adjustments'
    and t.related_id = v_adjustment.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'account_adjustment';

  if v_original_transaction_count <> 1 then
    raise exception '账户调整原始流水不存在或不唯一。';
  end if;

  select *
  into v_original_transaction
  from public.school_account_transactions t
  where t.id = v_adjustment.account_transaction_id
    and t.related_table = 'school_account_adjustments'
    and t.related_id = v_adjustment.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'account_adjustment'
  for update;

  if not found then
    raise exception '账户调整原始流水不存在或不唯一。';
  end if;

  if v_original_transaction.amount is distinct from v_adjustment.amount then
    raise exception '账户调整原始流水金额不一致，不能撤销。';
  end if;

  if v_original_transaction.account_id is distinct from v_adjustment.account_id
    or v_original_transaction.business_entity_id is distinct from v_adjustment.business_entity_id
    or v_original_transaction.currency is distinct from v_adjustment.currency then
    raise exception '账户调整原始流水账户、业务归属或币种不一致，不能撤销。';
  end if;

  select *
  into v_account
  from public.school_accounts a
  where a.id = v_adjustment.account_id
    and coalesce(a.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '调整账户不存在或不可用。';
  end if;

  if v_account.is_active is not true then
    raise exception '调整账户已停用。';
  end if;

  if v_account.business_entity_id is distinct from v_adjustment.business_entity_id
    or v_account.currency is distinct from v_adjustment.currency then
    raise exception '调整账户业务归属或币种不一致。';
  end if;

  v_year_month := to_char(p_reversal_date, 'YYYY-MM');
  v_account_old_balance := coalesce(v_account.current_balance, 0);
  v_reversal_amount := -v_adjustment.amount;
  v_account_new_balance := v_account_old_balance + v_reversal_amount;

  update public.school_accounts a
  set
    current_balance = v_account_new_balance,
    updated_at = v_now
  where a.id = v_adjustment.account_id;

  insert into public.school_account_transactions (
    account_id,
    business_entity_id,
    transaction_date,
    year_month,
    transaction_type,
    related_table,
    related_id,
    currency,
    amount,
    balance_after,
    description,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    v_adjustment.account_id,
    v_adjustment.business_entity_id,
    p_reversal_date,
    v_year_month,
    'account_adjustment_reversal',
    'school_account_adjustments',
    v_adjustment.id,
    v_adjustment.currency,
    v_reversal_amount,
    v_account_new_balance,
    '账户调整撤销：' || coalesce(v_reason, v_adjustment.reason, ''),
    v_reason,
    'school',
    v_now,
    v_now
  )
  returning id into v_reversal_transaction_id;

  update public.school_account_adjustments a
  set
    status = 'reversed',
    reversed_at = v_now,
    reversal_reason = v_reason,
    reversal_account_transaction_id = v_reversal_transaction_id,
    updated_at = v_now
  where a.id = v_adjustment.id;

  return query
  select
    v_adjustment.id,
    v_reversal_transaction_id,
    v_adjustment.account_id,
    v_adjustment.business_entity_id,
    v_account_old_balance,
    v_account_new_balance,
    v_adjustment.amount,
    v_reversal_amount,
    v_adjustment.currency,
    v_year_month,
    'reversed'::text,
    'account_adjustment_reversal'::text;
end;
$function$;

-- ---- school_reverse_account_transfer ----
CREATE OR REPLACE FUNCTION public.school_reverse_account_transfer(p_transfer_id uuid, p_reversal_date date, p_reason text DEFAULT NULL::text)
 RETURNS TABLE(transfer_id uuid, reversal_from_account_transaction_id uuid, reversal_to_account_transaction_id uuid, from_account_id uuid, to_account_id uuid, business_entity_id uuid, from_account_old_balance numeric, from_account_new_balance numeric, to_account_old_balance numeric, to_account_new_balance numeric, amount numeric, currency text, year_month text, status text, from_transaction_type text, to_transaction_type text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_now timestamptz := now();
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_year_month text;
  v_transfer public.school_account_transfers%rowtype;
  v_original_out public.school_account_transactions%rowtype;
  v_original_in public.school_account_transactions%rowtype;
  v_account public.school_accounts%rowtype;
  v_from_account public.school_accounts%rowtype;
  v_to_account public.school_accounts%rowtype;
  v_account_count integer := 0;
  v_original_out_count integer := 0;
  v_original_in_count integer := 0;
  v_existing_reverse_count integer := 0;
  v_from_account_old_balance numeric;
  v_from_account_new_balance numeric;
  v_to_account_old_balance numeric;
  v_to_account_new_balance numeric;
  v_reversal_from_transaction_id uuid;
  v_reversal_to_transaction_id uuid;
begin
  perform public.school_require_current_app_admin();
  if p_transfer_id is null then
    raise exception '请选择要撤销的账户转账。';
  end if;

  if p_reversal_date is null then
    raise exception '请选择撤销日期。';
  end if;

  select *
  into v_transfer
  from public.school_account_transfers t
  where t.id = p_transfer_id
    and coalesce(t.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '账户转账记录不存在。';
  end if;

  if v_transfer.status = 'reversed'
    or v_transfer.reversed_at is not null
    or v_transfer.reversal_from_account_transaction_id is not null
    or v_transfer.reversal_to_account_transaction_id is not null then
    raise exception '该账户转账已撤销，不能重复撤销。';
  end if;

  if v_transfer.status is distinct from 'posted' then
    raise exception '只能撤销已过账的账户转账。';
  end if;

  if v_transfer.from_account_transaction_id is null
    or v_transfer.to_account_transaction_id is null then
    raise exception '账户转账原始流水缺失，不能撤销。';
  end if;

  if coalesce(v_transfer.amount, 0) <= 0
    or nullif(trim(coalesce(v_transfer.currency, '')), '') is null then
    raise exception '账户转账金额或币种无效，不能撤销。';
  end if;

  select count(*)::integer
  into v_existing_reverse_count
  from public.school_account_transactions t
  where t.related_table = 'school_account_transfers'
    and t.related_id = v_transfer.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type in ('transfer_reverse_in', 'transfer_reverse_out');

  if v_existing_reverse_count > 0 then
    raise exception '该账户转账已撤销，不能重复撤销。';
  end if;

  select count(*)::integer
  into v_original_out_count
  from public.school_account_transactions t
  where t.related_table = 'school_account_transfers'
    and t.related_id = v_transfer.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'transfer_out';

  if v_original_out_count <> 1 then
    raise exception '账户转账原始转出流水不存在或不唯一。';
  end if;

  select *
  into v_original_out
  from public.school_account_transactions t
  where t.id = v_transfer.from_account_transaction_id
    and t.related_table = 'school_account_transfers'
    and t.related_id = v_transfer.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'transfer_out'
  for update;

  if not found then
    raise exception '账户转账原始转出流水不存在或不唯一。';
  end if;

  select count(*)::integer
  into v_original_in_count
  from public.school_account_transactions t
  where t.related_table = 'school_account_transfers'
    and t.related_id = v_transfer.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'transfer_in';

  if v_original_in_count <> 1 then
    raise exception '账户转账原始转入流水不存在或不唯一。';
  end if;

  select *
  into v_original_in
  from public.school_account_transactions t
  where t.id = v_transfer.to_account_transaction_id
    and t.related_table = 'school_account_transfers'
    and t.related_id = v_transfer.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'transfer_in'
  for update;

  if not found then
    raise exception '账户转账原始转入流水不存在或不唯一。';
  end if;

  if v_original_out.account_id is distinct from v_transfer.from_account_id
    or v_original_out.business_entity_id is distinct from v_transfer.business_entity_id
    or v_original_out.currency is distinct from v_transfer.currency
    or v_original_out.amount is distinct from -v_transfer.amount
    or v_original_in.account_id is distinct from v_transfer.to_account_id
    or v_original_in.business_entity_id is distinct from v_transfer.business_entity_id
    or v_original_in.currency is distinct from v_transfer.currency
    or v_original_in.amount is distinct from v_transfer.amount then
    raise exception '账户转账原始流水金额、账户、业务归属或币种不一致，不能撤销。';
  end if;

  for v_account in
    select *
    from public.school_accounts a
    where a.id = any (array[v_transfer.from_account_id, v_transfer.to_account_id])
    order by a.id
    for update
  loop
    v_account_count := v_account_count + 1;

    if v_account.id = v_transfer.from_account_id then
      v_from_account := v_account;
    elsif v_account.id = v_transfer.to_account_id then
      v_to_account := v_account;
    end if;
  end loop;

  if v_account_count <> 2 then
    raise exception '账户转账账户不存在或不可用。';
  end if;

  if coalesce(v_from_account.app_type, '') <> 'school'
    or coalesce(v_to_account.app_type, '') <> 'school'
    or v_from_account.is_active is not true
    or v_to_account.is_active is not true then
    raise exception '账户转账账户不存在或不可用。';
  end if;

  if v_from_account.business_entity_id is distinct from v_transfer.business_entity_id
    or v_to_account.business_entity_id is distinct from v_transfer.business_entity_id
    or v_from_account.currency is distinct from v_transfer.currency
    or v_to_account.currency is distinct from v_transfer.currency then
    raise exception '账户转账账户业务归属或币种不一致。';
  end if;

  v_year_month := to_char(p_reversal_date, 'YYYY-MM');
  v_from_account_old_balance := coalesce(v_from_account.current_balance, 0);
  v_to_account_old_balance := coalesce(v_to_account.current_balance, 0);
  v_from_account_new_balance := v_from_account_old_balance + v_transfer.amount;
  v_to_account_new_balance := v_to_account_old_balance - v_transfer.amount;

  update public.school_accounts a
  set
    current_balance = v_from_account_new_balance,
    updated_at = v_now
  where a.id = v_transfer.from_account_id;

  insert into public.school_account_transactions (
    account_id,
    business_entity_id,
    transaction_date,
    year_month,
    transaction_type,
    related_table,
    related_id,
    currency,
    amount,
    balance_after,
    description,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    v_transfer.from_account_id,
    v_transfer.business_entity_id,
    p_reversal_date,
    v_year_month,
    'transfer_reverse_in',
    'school_account_transfers',
    v_transfer.id,
    v_transfer.currency,
    v_transfer.amount,
    v_from_account_new_balance,
    '账户转账撤销入金：' || coalesce(v_reason, v_transfer.reason, ''),
    v_reason,
    'school',
    v_now,
    v_now
  )
  returning id into v_reversal_from_transaction_id;

  update public.school_accounts a
  set
    current_balance = v_to_account_new_balance,
    updated_at = v_now
  where a.id = v_transfer.to_account_id;

  insert into public.school_account_transactions (
    account_id,
    business_entity_id,
    transaction_date,
    year_month,
    transaction_type,
    related_table,
    related_id,
    currency,
    amount,
    balance_after,
    description,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    v_transfer.to_account_id,
    v_transfer.business_entity_id,
    p_reversal_date,
    v_year_month,
    'transfer_reverse_out',
    'school_account_transfers',
    v_transfer.id,
    v_transfer.currency,
    -v_transfer.amount,
    v_to_account_new_balance,
    '账户转账撤销出金：' || coalesce(v_reason, v_transfer.reason, ''),
    v_reason,
    'school',
    v_now,
    v_now
  )
  returning id into v_reversal_to_transaction_id;

  update public.school_account_transfers t
  set
    status = 'reversed',
    reversed_at = v_now,
    reversal_reason = v_reason,
    reversal_from_account_transaction_id = v_reversal_from_transaction_id,
    reversal_to_account_transaction_id = v_reversal_to_transaction_id,
    updated_at = v_now
  where t.id = v_transfer.id;

  return query
  select
    v_transfer.id,
    v_reversal_from_transaction_id,
    v_reversal_to_transaction_id,
    v_transfer.from_account_id,
    v_transfer.to_account_id,
    v_transfer.business_entity_id,
    v_from_account_old_balance,
    v_from_account_new_balance,
    v_to_account_old_balance,
    v_to_account_new_balance,
    v_transfer.amount,
    v_transfer.currency,
    v_year_month,
    'reversed'::text,
    'transfer_reverse_in'::text,
    'transfer_reverse_out'::text;
end;
$function$;

DO $post$
DECLARE t record; v_n int; v_def text; v_md5 text; v_acl text; v_g int; b record;
BEGIN
  FOR t IN SELECT * FROM (VALUES
    ('school_create_account_adjustment','c1a6251c206524940cade9f6f0dcb755','Draft RPC for v2 account adjustment creation: creates account adjustment, updates account balance, and inserts account_adjustment transaction.'),
    ('school_create_account_transfer','948e357290b70c0efbf80f40025d949a','Draft RPC for v2 account transfer creation: creates a posted transfer, updates two account balances, and inserts transfer_out / transfer_in transactions.'),
    ('school_reverse_account_adjustment','5473844ba2b9f7945d910ccac9df8aa0','Draft RPC for v2 account adjustment reversal: marks an account adjustment as reversed, restores account balance by the opposite amount, and inserts an account_adjustment_reversal transaction.'),
    ('school_reverse_account_transfer','b192dab8fcb43491fe513b375eb67bd7','Draft RPC for v2 account transfer reversal: marks an account transfer as reversed, restores the original from-account balance, reverses the original to-account balance, and inserts transfer_reverse_in / transfer_reverse_out transactions.')
  ) AS v(proname, md5, cmt) LOOP
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=t.proname;
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'ACCT_POST_ARITY: %有 % 个（应为 1）', t.proname, v_n;
    END IF;

    SELECT pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,'')
      INTO v_def, v_md5, v_acl
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=t.proname;

    IF v_md5 <> t.md5 THEN
      RAISE EXCEPTION 'ACCT_POST_MD5: % 定义为 %，期望 %', t.proname, v_md5, t.md5;
    END IF;
    IF v_acl <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' THEN
      RAISE EXCEPTION 'ACCT_POST_ACL: % 的 ACL 为 %，期望 %', t.proname, v_acl, '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}';
    END IF;

    v_g := (length(v_def)-length(replace(v_def,'school_require_current_app_admin','')))/length('school_require_current_app_admin');
    IF v_g <> 1 THEN
      RAISE EXCEPTION 'ACCT_POST_GUARD_CALLS: % 内 admin 守卫 % 次（期望 1）', t.proname, v_g;
    END IF;

    -- 钉死比对：这条才抓得住【部署前就已存在】的注释漂移。
    -- 下面与 pre 段捕获的比对只能证明「本脚本没改」，检测不出既有漂移。
    IF coalesce(obj_description(
         (SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='public' AND p.proname=t.proname),'pg_proc'),'<NULL>') <> t.cmt THEN
      RAISE EXCEPTION 'ACCT_POST_COMMENT: % 的注释与取证基线不符', t.proname;
    END IF;

    SELECT * INTO b FROM acct_before WHERE b_name = t.proname;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'ACCT_POST_CAPTURE_MISSING: pre 段没记下 %', t.proname;
    END IF;
    PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname=t.proname
        AND coalesce(obj_description(p.oid,'pg_proc'),'<NULL>')=b.b_cmt
        AND p.proisstrict=b.b_strict AND p.proparallel=b.b_par AND p.proleakproof=b.b_leak
        AND p.procost=b.b_cost AND p.prorows=b.b_rows AND p.prosecdef=b.b_secdef
        AND pg_get_userbyid(p.proowner)=b.b_owner
        AND coalesce(array_to_string(p.proconfig,', '),'<NULL>')=b.b_cfg;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'ACCT_POST_ATTRS: % 的注释 / owner / secdef / proconfig / 执行属性与 pre 段不一致', t.proname;
    END IF;
  END LOOP;
  RAISE NOTICE 'ACCT_POST: 4 个函数的 md5 / ACL / 守卫调用 / 注释 / 执行属性 全部符合预期';
END
$post$;

DO $posttbl$
DECLARE t record; v_acl text; v_rls boolean; v_force boolean; v_pol int;
BEGIN
  FOR t IN SELECT unnest(ARRAY['school_account_adjustments','school_account_transfers']) AS tbl LOOP
    SELECT coalesce(c.relacl::text,''), c.relrowsecurity, c.relforcerowsecurity
      INTO v_acl, v_rls, v_force
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relname=t.tbl;
    IF v_acl <> '{postgres=arwdDxtm/postgres,authenticated=rxtm/postgres,service_role=arwdDxtm/postgres}' THEN
      RAISE EXCEPTION 'ACCT_POST_TBL_ACL: % 的 ACL 为 %，期望 %', t.tbl, v_acl, '{postgres=arwdDxtm/postgres,authenticated=rxtm/postgres,service_role=arwdDxtm/postgres}';
    END IF;
    -- 本脚本【不动】RLS 开关，前后都应是 false/false
    IF v_rls IS NOT FALSE OR v_force IS NOT FALSE THEN
      RAISE EXCEPTION 'ACCT_POST_TBL_RLS: % rowsecurity=% force=%（本批不改，期望 f/f）', t.tbl, v_rls, v_force;
    END IF;
    SELECT count(*) INTO v_pol FROM pg_policies
     WHERE schemaname='public' AND tablename=t.tbl;
    IF v_pol <> 0 THEN
      RAISE EXCEPTION 'ACCT_POST_TBL_POLICY: % 上有 % 条策略（期望 0）', t.tbl, v_pol;
    END IF;
  END LOOP;
  RAISE NOTICE 'ACCT_POST: 两张表的 ACL / RLS 开关 / 策略数 全部符合预期';
END
$posttbl$;

\if :is_commit
COMMIT;
\echo '>>> 已 COMMIT'
\else
ROLLBACK;
\echo '>>> 已 ROLLBACK（rehearsal）'
\endif
