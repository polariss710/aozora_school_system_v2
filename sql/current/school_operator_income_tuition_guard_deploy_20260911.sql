-- =============================================================================
-- 新增 operator 准入守卫：5 个收入 writer + 学费生成入口 G
--
-- 背景  2026-09-10 22:56 生产只读取证（Codex）发现 P1：
--       学费正常生成链 G→C→F/N 没有【任何】调用者身份/角色准入断言，
--       五个常规收入 writer 同样零守卫。
--       ⇒ 当时任何 authenticated 账号都能生成学费账单、增删改收入记录。
--
--       因此本批的性质是【新增守卫】，不是把 admin 守卫换成 operator。
--       对教务老师（operator）而言这不是「开放」——她本来就能调；
--       真正的变化是把 read_only、停用成员、无成员、未登录挡在门外。
--
-- 位置  守卫放在 G 一处即可：C/F/N 对 authenticated 与 service_role
--       的 EXECUTE 均为 false，只能由 SECURITY DEFINER 内部进入。
--       作废/重发等内部路径从 C/F/N 进入，因此【不会】被本守卫误伤。
--
-- 范围  6 个函数各【新增一行】守卫调用 + 6 条 COMMENT 各追加一句。
--       ⛔ 不改 ACL、不改 owner、不改函数签名、不动业务数据。
--       签名不变 ⇒ CREATE OR REPLACE ⇒ ACL 与 COMMENT 不受默认授权影响。
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
--    回滚脚本尤其致命：在最需要它工作的时刻静默什么都不做。
DO $mode$ BEGIN
  RAISE EXCEPTION 'OPWRI_MODE_INVALID: 必须指定 -v mode=rehearsal 或 -v mode=commit';
END $mode$;
\endif

BEGIN;

-- operator 守卫必须【已在生产】且正是 2026-09-10 部署的那一个。
-- 它是本批 6 个函数的唯一依赖；不核实就等于把准入建在一个没验过的对象上。

DO $guard$
DECLARE v_n int; v_md5 text; v_acl text;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_require_current_app_operator';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'OPWRI_PRE_GUARD_MISSING: public.school_require_current_app_operator 有 % 个（应为 1）', v_n;
  END IF;
  SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,'')
    INTO v_md5, v_acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_require_current_app_operator';
  IF v_md5 <> '526c615da0c5bf179894ccbcc325008c' THEN
    RAISE EXCEPTION 'OPWRI_PRE_GUARD_DRIFT: 守卫定义为 %，期望 %', v_md5, '526c615da0c5bf179894ccbcc325008c';
  END IF;
  IF v_acl <> '{postgres=X/postgres,authenticated=X/postgres}' THEN
    RAISE EXCEPTION 'OPWRI_PRE_GUARD_ACL: 守卫 ACL 为 %，期望 %', v_acl, '{postgres=X/postgres,authenticated=X/postgres}';
  END IF;
  RAISE NOTICE 'OPWRI_PRE: operator 守卫在位且与 2026-09-10 部署结果一致';
END
$guard$;

DO $pre$
DECLARE
  t record; v_n int; v_md5 text; v_acl text; v_cmt text; v_cfg text;
  v_owner text; v_sec boolean; v_strict boolean; v_par char; v_leak boolean;
  v_cost real; v_rows real;
BEGIN
  FOR t IN
    SELECT * FROM (VALUES
    ('school_create_income_record',17,'1cf8561f02abd4bdfbff66cf8a90e79b','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','Verified RPC for v2 income creation: creates received income, updates account balance, and inserts account transaction. Only tuition income participates in student settlement.','search_path=public'),
    ('school_update_income_record',18,'1296e1efaefb13646aee8e649225381f','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','Guarded v2 income edit: updates one received income and its original account transaction only when settlement/account guards pass; rejects personal Cash-linked tuition income.','search_path=public'),
    ('school_reverse_income_record',3,'d5043b75cee6e3f59f59419287fee499','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','Guarded RPC for v2 income reversal: marks a received income as reversed, restores account balance, inserts a negative income_reversal transaction, and rejects personal Cash-linked tuition income.','search_path=public'),
    ('school_cancel_pending_income_record',3,'816cdadf85b9604aca56c8767326f22a','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','Guardedly cancels ordinary pending School income and preserves the legacy tuition cancellation path behind the generate gate. R2-F-B atomic tuition income is permanently rejected.','search_path=pg_catalog, public'),
    ('school_create_pending_cash_income_record',14,'4f13632b3d7ca41299c9c2e61ea60bf9','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','Creates one pending School income record for later Cash submission. Amount JPY/CNY conversion is calculated in DB/RPC and no School account ledger or Cash request is created.','search_path=public'),
    ('school_generate_student_tuition_bill_atomic',6,'40ef9ec344623bb7c02bf8aea670ad52','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','R2-F-B authoritative atomic tuition writer. The public wrapper is R0-gated; clients submit no amounts or candidate details.','search_path=pg_catalog, public')
    ) AS v(proname, nargs, md5, acl, cmt, cfg)
  LOOP
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=t.proname AND p.pronargs=t.nargs;
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'OPWRI_PRE_ARITY: public.%(%) 匹配到 % 个（应为 1）', t.proname, t.nargs, v_n;
    END IF;

    SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,''),
           coalesce(obj_description(p.oid,'pg_proc'),'<NULL>'),
           coalesce(array_to_string(p.proconfig,', '),'<NULL>'),
           pg_get_userbyid(p.proowner), p.prosecdef, p.proisstrict,
           p.proparallel, p.proleakproof, p.procost, p.prorows
      INTO v_md5, v_acl, v_cmt, v_cfg, v_owner, v_sec, v_strict, v_par, v_leak, v_cost, v_rows
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=t.proname AND p.pronargs=t.nargs;

    IF v_md5 <> t.md5 THEN
      RAISE EXCEPTION 'OPWRI_PRE_MD5: %(%) 定义为 %，期望 %', t.proname, t.nargs, v_md5, t.md5;
    END IF;
    IF v_acl <> t.acl THEN
      RAISE EXCEPTION 'OPWRI_PRE_ACL: %(%) ACL 为 %，期望 %', t.proname, t.nargs, v_acl, t.acl;
    END IF;
    IF v_cmt <> t.cmt THEN
      RAISE EXCEPTION 'OPWRI_PRE_COMMENT: %(%) 注释为 [%]，期望 [%]', t.proname, t.nargs, v_cmt, t.cmt;
    END IF;
    IF v_cfg <> t.cfg THEN
      RAISE EXCEPTION 'OPWRI_PRE_CONFIG: %(%) proconfig 为 %，期望 %', t.proname, t.nargs, v_cfg, t.cfg;
    END IF;
    IF v_owner <> 'postgres' OR v_sec IS NOT TRUE OR v_strict IS NOT FALSE
       OR v_par <> 'u' OR v_leak IS NOT FALSE OR v_cost <> 100 OR v_rows <> 1000 THEN
      RAISE EXCEPTION 'OPWRI_PRE_ATTRS: %(%) owner=% secdef=% strict=% parallel=% leakproof=% cost=% rows=%',
        t.proname, t.nargs, v_owner, v_sec, v_strict, v_par, v_leak, v_cost, v_rows;
    END IF;
  END LOOP;
  RAISE NOTICE 'OPWRI_PRE: 6 个函数的 md5 / ACL / COMMENT / proconfig / 执行属性全部符合预期';
END
$pre$;

DO $calls$
DECLARE r record; v_def text; v_op int; v_ad int;
BEGIN
  FOR r IN SELECT p.oid, p.proname, p.pronargs FROM pg_proc p
             JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='public' AND p.proname IN ('school_create_income_record','school_update_income_record','school_reverse_income_record','school_cancel_pending_income_record','school_create_pending_cash_income_record','school_generate_student_tuition_bill_atomic') LOOP
    v_def := pg_get_functiondef(r.oid);
    v_op := (length(v_def)-length(replace(v_def,'school_require_current_app_operator','')))/length('school_require_current_app_operator');
    v_ad := (length(v_def)-length(replace(v_def,'school_require_current_app_admin','')))
            /length('school_require_current_app_admin');
    IF v_op <> 0 THEN
      RAISE EXCEPTION 'OPWRI_PRE_CALLS: %(%) 内 operator 守卫调用 % 次，期望 0',
        r.proname, r.pronargs, v_op;
    END IF;
    IF v_ad <> 0 THEN
      RAISE EXCEPTION 'OPWRI_PRE_ADMIN_CALLS: %(%) 内出现 admin 守卫调用 % 次，本批不应引入',
        r.proname, r.pronargs, v_ad;
    END IF;
  END LOOP;
  RAISE NOTICE 'OPWRI_PRE: 6 个函数体内 operator 守卫调用次数均为 0，admin 守卫 0 次';
END
$calls$;

-- ===== 应用：6 个函数各新增一行守卫调用（其余逐字节不变）=====
-- ---- school_create_income_record(17) ----
CREATE OR REPLACE FUNCTION public.school_create_income_record(p_income_date date, p_settlement_month text, p_business_entity_id uuid, p_student_id uuid, p_account_id uuid, p_amount numeric, p_income_category text DEFAULT 'tuition'::text, p_description text DEFAULT NULL::text, p_currency text DEFAULT 'JPY'::text, p_payment_currency text DEFAULT 'JPY'::text, p_exchange_rate numeric DEFAULT NULL::numeric, p_payment_method text DEFAULT NULL::text, p_is_taxable_income boolean DEFAULT false, p_tax_category text DEFAULT NULL::text, p_receipt_status text DEFAULT NULL::text, p_include_in_student_settlement boolean DEFAULT true, p_note text DEFAULT NULL::text)
 RETURNS TABLE(income_id uuid, account_transaction_id uuid, account_id uuid, new_balance numeric, income_status text, transaction_type text, settlement_month text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_now timestamptz := now();
  v_business_entity public.school_business_entities%rowtype;
  v_student public.school_students%rowtype;
  v_account public.school_accounts%rowtype;
  v_income_id uuid;
  v_account_transaction_id uuid;
  v_currency text := upper(trim(coalesce(p_currency, '')));
  v_payment_currency text := upper(trim(coalesce(p_payment_currency, '')));
  v_income_category text := lower(trim(coalesce(p_income_category, '')));
  v_include_in_student_settlement boolean;
  v_year_month text := trim(coalesce(p_settlement_month, ''));
  v_transaction_month text;
  v_amount_jpy numeric;
  v_amount_cny numeric;
  v_old_balance numeric;
  v_new_balance numeric;
  v_description text;
  v_note text;
begin
  perform public.school_require_current_app_operator();
  if p_income_date is null then
    raise exception '请选择实际收款日期。';
  end if;

  if v_year_month = '' or v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '结算月份格式无效。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  perform public.school_assert_new_business_entity_allowed(
    p_business_entity_id,
    '新增收入'
  );

  if p_account_id is null then
    raise exception '请选择入账账户。';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception '收入金额必须大于 0。';
  end if;

  if v_income_category = '' then
    raise exception '收入分类不能为空。';
  end if;

  if v_income_category not in ('tuition', 'material_fee', 'registration_fee', 'other_fee') then
    raise exception '收入分类无效。';
  end if;

  v_include_in_student_settlement := v_income_category = 'tuition'
    and coalesce(p_include_in_student_settlement, true);

  if v_currency not in ('JPY', 'CNY') then
    raise exception '暂不支持该收入币种：%。', v_currency;
  end if;

  if v_payment_currency not in ('JPY', 'CNY') then
    raise exception '暂不支持该收款币种：%。', v_payment_currency;
  end if;

  if v_currency <> v_payment_currency then
    raise exception '第一版要求收入币种与收款币种一致。';
  end if;

  if p_exchange_rate is not null and p_exchange_rate <= 0 then
    raise exception '汇率必须大于 0。';
  end if;

  select *
  into v_business_entity
  from public.school_business_entities
  where id = p_business_entity_id
    and is_active = true;

  if not found then
    raise exception '业务归属无效或已停用。';
  end if;

  if v_include_in_student_settlement and p_student_id is null then
    raise exception '进入学生结算的收入必须选择学生。';
  end if;

  if p_student_id is not null then
    select *
    into v_student
    from public.school_students
    where id = p_student_id
      and app_type = 'school';

    if not found then
      raise exception '学生无效或不可用。';
    end if;

    if v_student.business_entity_id is not null
      and v_student.business_entity_id is distinct from p_business_entity_id then
      raise exception '学生业务归属与收入业务归属不一致。';
    end if;
  end if;

  if v_include_in_student_settlement and exists (
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = p_student_id
      and s.business_entity_id = p_business_entity_id
      and s.year_month = v_year_month
      and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能直接新增收入。';
  end if;

  select *
  into v_account
  from public.school_accounts
  where id = p_account_id
    and app_type = 'school'
  for update;

  if not found then
    raise exception '入账账户无效。';
  end if;

  if v_account.is_active is not true then
    raise exception '入账账户已停用。';
  end if;

  if v_account.business_entity_id is distinct from p_business_entity_id then
    raise exception '入账账户与业务归属不一致。';
  end if;

  if v_account.currency is distinct from v_payment_currency then
    raise exception '入账账户币种必须与收款币种一致。';
  end if;

  if v_payment_currency = 'JPY' then
    v_amount_jpy := p_amount;
    v_amount_cny := case
      when p_exchange_rate is not null then p_amount / p_exchange_rate
      else null
    end;
  else
    v_amount_cny := p_amount;
    v_amount_jpy := case
      when p_exchange_rate is not null then p_amount * p_exchange_rate
      else null
    end;
  end if;

  v_transaction_month := to_char(p_income_date, 'YYYY-MM');
  v_old_balance := coalesce(v_account.current_balance, 0);
  v_new_balance := v_old_balance + p_amount;
  v_description := coalesce(
    nullif(trim(p_description), ''),
    case v_income_category
      when 'tuition' then '学费收入'
      when 'material_fee' then '教材费收入'
      when 'registration_fee' then '报名费收入'
      else '其他费用收入'
    end
  );
  v_note := nullif(trim(coalesce(p_note, '')), '');

  insert into public.school_income_records (
    business_entity_id,
    student_id,
    student_payment_id,
    account_id,
    income_date,
    year_month,
    settlement_month,
    income_category,
    description,
    currency,
    amount,
    amount_jpy,
    amount_cny,
    exchange_rate,
    payment_currency,
    payment_method,
    status,
    is_taxable_income,
    tax_category,
    receipt_status,
    include_in_student_settlement,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    p_business_entity_id,
    p_student_id,
    null,
    p_account_id,
    p_income_date,
    v_year_month,
    v_year_month,
    v_income_category,
    v_description,
    v_currency,
    p_amount,
    v_amount_jpy,
    v_amount_cny,
    p_exchange_rate,
    v_payment_currency,
    nullif(trim(coalesce(p_payment_method, '')), ''),
    'received',
    coalesce(p_is_taxable_income, false),
    nullif(trim(coalesce(p_tax_category, '')), ''),
    coalesce(nullif(trim(coalesce(p_receipt_status, '')), ''), '待确认'),
    v_include_in_student_settlement,
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_income_id;

  update public.school_accounts
  set
    current_balance = v_new_balance,
    updated_at = v_now
  where id = v_account.id;

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
    p_income_date,
    v_transaction_month,
    'income_adjust',
    'school_income_records',
    v_income_id,
    v_account.currency,
    p_amount,
    v_new_balance,
    '收入入账：' || v_description,
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_account_transaction_id;

  return query
  select
    v_income_id,
    v_account_transaction_id,
    v_account.id,
    v_new_balance,
    'received'::text,
    'income_adjust'::text,
    v_year_month;
end;
$function$;

-- ---- school_update_income_record(18) ----
CREATE OR REPLACE FUNCTION public.school_update_income_record(p_income_id uuid, p_income_date date, p_settlement_month text, p_business_entity_id uuid, p_student_id uuid, p_account_id uuid, p_amount numeric, p_income_category text DEFAULT 'tuition'::text, p_description text DEFAULT NULL::text, p_currency text DEFAULT 'JPY'::text, p_payment_currency text DEFAULT 'JPY'::text, p_exchange_rate numeric DEFAULT NULL::numeric, p_payment_method text DEFAULT NULL::text, p_is_taxable_income boolean DEFAULT false, p_tax_category text DEFAULT NULL::text, p_receipt_status text DEFAULT NULL::text, p_include_in_student_settlement boolean DEFAULT true, p_note text DEFAULT NULL::text)
 RETURNS TABLE(income_id uuid, account_transaction_id uuid, account_id uuid, new_balance numeric, income_status text, transaction_type text, settlement_month text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_now timestamptz := now();
  v_income public.school_income_records%rowtype;
  v_business_entity public.school_business_entities%rowtype;
  v_student public.school_students%rowtype;
  v_account public.school_accounts%rowtype;
  v_original_transaction public.school_account_transactions%rowtype;
  v_currency text := upper(trim(coalesce(p_currency, '')));
  v_payment_currency text := upper(trim(coalesce(p_payment_currency, '')));
  v_income_category text := lower(trim(coalesce(p_income_category, '')));
  v_year_month text := trim(coalesce(p_settlement_month, ''));
  v_transaction_month text;
  v_amount_jpy numeric;
  v_amount_cny numeric;
  v_new_balance numeric;
  v_amount_delta numeric;
  v_description text;
  v_note text;
  v_include_in_student_settlement boolean;
  v_original_transaction_count integer := 0;
  v_existing_reversal_count integer := 0;
begin
  perform public.school_require_current_app_operator();
  if p_income_id is null then
    raise exception '请选择要编辑的收入记录。';
  end if;

  if p_income_date is null then
    raise exception '请选择实际收款日期。';
  end if;

  if v_year_month = '' or v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '结算月份格式无效。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  if p_account_id is null then
    raise exception '请选择入账账户。';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception '收入金额必须大于 0。';
  end if;

  if v_income_category = '' then
    raise exception '收入分类不能为空。';
  end if;

  if v_income_category not in ('tuition', 'material_fee', 'registration_fee', 'other_fee') then
    raise exception '收入分类无效。';
  end if;

  v_include_in_student_settlement := v_income_category = 'tuition'
    and coalesce(p_include_in_student_settlement, true);

  if v_currency not in ('JPY', 'CNY') then
    raise exception '暂不支持该收入币种：%。', v_currency;
  end if;

  if v_payment_currency not in ('JPY', 'CNY') then
    raise exception '暂不支持该收款币种：%。', v_payment_currency;
  end if;

  if v_currency <> v_payment_currency then
    raise exception '收入币种必须与收款币种一致。';
  end if;

  if p_exchange_rate is not null and p_exchange_rate <= 0 then
    raise exception '汇率必须大于 0。';
  end if;

  select *
  into v_income
  from public.school_income_records i
  where i.id = p_income_id
    and coalesce(i.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '收入记录不存在。';
  end if;

  if p_business_entity_id is distinct from v_income.business_entity_id then
    perform public.school_assert_new_business_entity_allowed(
      p_business_entity_id,
      '更新收入业务归属'
    );
  end if;

  if v_income.status = 'reversed'
    or v_income.reversed_at is not null
    or v_income.reversal_account_transaction_id is not null then
    raise exception '已撤销收入不能编辑。';
  end if;

  if v_income.status is distinct from 'received' then
    raise exception '只能编辑已收款收入。';
  end if;

  if v_income.student_payment_id is not null then
    raise exception '关联学生收款链路的收入暂不支持普通编辑。';
  end if;

  if exists (
    select 1
    from public.school_personal_cash_income_linkage_events e
    where e.income_record_id = v_income.id
      and e.source_table = 'school_income_records'
      and e.source_event_type in ('tuition_income_received', 'income_received')
      and (
        e.cash_transaction_id is not null
        or e.sync_status = 'synced'
        or e.cash_request_status in ('approved', 'synced')
      )
  ) then
    raise exception 'income record has been synced to Cash and cannot be edited or deleted directly';
  end if;

  if exists (
    select 1
    from public.school_personal_cash_income_linkage_events e
    where e.income_record_id = v_income.id
      and e.source_table = 'school_income_records'
      and e.source_event_type in ('tuition_income_received', 'income_received')
      and (
        e.sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation')
        or e.cash_request_status = 'pending'
      )
  ) then
    raise exception 'income record has a pending Cash request and core fields cannot be edited directly';
  end if;

  if exists (
    select 1
    from public.school_personal_cash_income_linkage_events e
    where e.income_record_id = v_income.id
      and e.source_table = 'school_income_records'
      and e.source_event_type in ('tuition_income_received', 'income_received')
  ) then
    raise exception '该收入已进入 Cash System 联动流程，不能通过普通收入编辑。';
  end if;

  select count(*)::integer
  into v_existing_reversal_count
  from public.school_account_transactions t
  where t.related_table = 'school_income_records'
    and t.related_id = v_income.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'income_reversal';

  if v_existing_reversal_count > 0 then
    raise exception '已存在收入撤销流水，不能编辑。';
  end if;

  select count(*)::integer
  into v_original_transaction_count
  from public.school_account_transactions t
  where t.related_table = 'school_income_records'
    and t.related_id = v_income.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'income_adjust';

  if v_original_transaction_count <> 1 then
    raise exception '收入原始账户流水不存在或不唯一，不能编辑。';
  end if;

  select *
  into v_original_transaction
  from public.school_account_transactions t
  where t.related_table = 'school_income_records'
    and t.related_id = v_income.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'income_adjust'
  for update;

  if v_original_transaction.amount is distinct from v_income.amount
    or v_original_transaction.account_id is distinct from v_income.account_id
    or v_original_transaction.currency is distinct from v_income.currency then
    raise exception '收入原始账户流水与收入记录不一致，不能编辑。';
  end if;

  if exists (
    select 1
    from public.school_account_transactions t
    where t.account_id = v_original_transaction.account_id
      and coalesce(t.app_type, '') = 'school'
      and (
        t.created_at > v_original_transaction.created_at
        or (t.created_at = v_original_transaction.created_at and t.id::text > v_original_transaction.id::text)
      )
  ) then
    raise exception '该收入之后已有账户流水，不能直接编辑会影响余额的字段。请使用撤销后重新新增。';
  end if;

  if p_account_id is distinct from v_income.account_id then
    raise exception '已入账收入暂不支持更换入账账户。请撤销后重新新增。';
  end if;

  select *
  into v_business_entity
  from public.school_business_entities
  where id = p_business_entity_id
    and is_active = true;

  if not found then
    raise exception '业务归属无效或已停用。';
  end if;

  if v_include_in_student_settlement and p_student_id is null then
    raise exception '进入学生结算的收入必须选择学生。';
  end if;

  if p_student_id is not null then
    select *
    into v_student
    from public.school_students
    where id = p_student_id
      and app_type = 'school';

    if not found then
      raise exception '学生无效或不可用。';
    end if;

    if v_student.business_entity_id is not null
      and v_student.business_entity_id is distinct from p_business_entity_id then
      raise exception '学生业务归属与收入业务归属不一致。';
    end if;
  end if;

  if coalesce(v_income.include_in_student_settlement, false)
    and v_income.student_id is not null
    and nullif(trim(coalesce(v_income.settlement_month, '')), '') is not null
    and v_income.business_entity_id is not null
    and exists (
      select 1
      from public.school_student_monthly_settlements s
      where s.student_id = v_income.student_id
        and s.business_entity_id = v_income.business_entity_id
        and s.year_month = v_income.settlement_month
        and s.settlement_status = 'locked'
    ) then
    raise exception '原学生月度结算已锁定，不能编辑收入。';
  end if;

  if v_include_in_student_settlement and exists (
    select 1
    from public.school_student_monthly_settlements s
    where s.student_id = p_student_id
      and s.business_entity_id = p_business_entity_id
      and s.year_month = v_year_month
      and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能编辑收入。';
  end if;

  select *
  into v_account
  from public.school_accounts
  where id = p_account_id
    and app_type = 'school'
  for update;

  if not found then
    raise exception '入账账户无效。';
  end if;

  if v_account.is_active is not true then
    raise exception '入账账户已停用。';
  end if;

  if v_account.business_entity_id is distinct from p_business_entity_id then
    raise exception '入账账户与业务归属不一致。';
  end if;

  if v_account.currency is distinct from v_payment_currency
    or v_account.currency is distinct from v_currency then
    raise exception '入账账户币种必须与收入币种一致。';
  end if;

  if v_payment_currency = 'JPY' then
    v_amount_jpy := p_amount;
    v_amount_cny := case
      when p_exchange_rate is not null then p_amount / p_exchange_rate
      else null
    end;
  else
    v_amount_cny := p_amount;
    v_amount_jpy := case
      when p_exchange_rate is not null then p_amount * p_exchange_rate
      else null
    end;
  end if;

  v_transaction_month := to_char(p_income_date, 'YYYY-MM');
  v_amount_delta := p_amount - v_income.amount;
  v_new_balance := coalesce(v_account.current_balance, 0) + v_amount_delta;
  v_description := coalesce(
    nullif(trim(p_description), ''),
    case v_income_category
      when 'tuition' then '学费收入'
      when 'material_fee' then '教材费收入'
      when 'registration_fee' then '报名费收入'
      else '其他费用收入'
    end
  );
  v_note := nullif(trim(coalesce(p_note, '')), '');

  update public.school_accounts a
  set
    current_balance = v_new_balance,
    updated_at = v_now
  where a.id = v_account.id;

  update public.school_account_transactions t
  set
    business_entity_id = p_business_entity_id,
    transaction_date = p_income_date,
    year_month = v_transaction_month,
    currency = v_account.currency,
    amount = p_amount,
    balance_after = v_new_balance,
    description = '收入入账：' || v_description,
    note = v_note,
    updated_at = v_now
  where t.id = v_original_transaction.id;

  update public.school_income_records i
  set
    business_entity_id = p_business_entity_id,
    student_id = p_student_id,
    account_id = p_account_id,
    income_date = p_income_date,
    year_month = v_year_month,
    settlement_month = v_year_month,
    income_category = v_income_category,
    description = v_description,
    currency = v_account.currency,
    amount = p_amount,
    amount_jpy = v_amount_jpy,
    amount_cny = v_amount_cny,
    exchange_rate = p_exchange_rate,
    payment_currency = v_account.currency,
    payment_method = nullif(trim(coalesce(p_payment_method, '')), ''),
    is_taxable_income = coalesce(p_is_taxable_income, false),
    tax_category = nullif(trim(coalesce(p_tax_category, '')), ''),
    receipt_status = coalesce(nullif(trim(coalesce(p_receipt_status, '')), ''), '待确认'),
    include_in_student_settlement = v_include_in_student_settlement,
    note = v_note,
    updated_at = v_now
  where i.id = v_income.id;

  return query
  select
    v_income.id,
    v_original_transaction.id,
    v_account.id,
    v_new_balance,
    'received'::text,
    'income_adjust'::text,
    v_year_month;
end;
$function$;

-- ---- school_reverse_income_record(3) ----
CREATE OR REPLACE FUNCTION public.school_reverse_income_record(p_income_id uuid, p_reversal_date date, p_reason text DEFAULT NULL::text)
 RETURNS TABLE(income_id uuid, reversal_account_transaction_id uuid, account_id uuid, account_new_balance numeric, amount numeric, currency text, year_month text, status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_now timestamptz := now();
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_year_month text;
  v_income public.school_income_records%rowtype;
  v_original_transaction public.school_account_transactions%rowtype;
  v_account public.school_accounts%rowtype;
  v_original_transaction_count integer := 0;
  v_existing_reversal_count integer := 0;
  v_locked_settlement_count integer := 0;
  v_new_balance numeric;
  v_reversal_transaction_id uuid;
begin
  perform public.school_require_current_app_operator();
  if p_income_id is null then
    raise exception '请选择要撤销的收入记录。';
  end if;

  if p_reversal_date is null then
    raise exception '请选择撤销日期。';
  end if;

  select *
  into v_income
  from public.school_income_records i
  where i.id = p_income_id
    and coalesce(i.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '收入记录不存在。';
  end if;

  if v_income.status = 'reversed'
    or v_income.reversed_at is not null
    or v_income.reversal_account_transaction_id is not null then
    raise exception '该收入已撤销，不能重复撤销。';
  end if;

  if v_income.status is distinct from 'received' then
    raise exception '只能撤销已收款收入。';
  end if;

  if v_income.student_payment_id is not null then
    raise exception '关联学生收款链路的收入暂不支持通过普通收入撤销处理。';
  end if;

  if exists (
    select 1
    from public.school_personal_cash_income_linkage_events e
    where e.income_record_id = v_income.id
      and e.source_table = 'school_income_records'
      and e.source_event_type in ('tuition_income_received', 'income_received')
      and (
        e.cash_transaction_id is not null
        or e.sync_status = 'synced'
        or e.cash_request_status in ('approved', 'synced')
      )
  ) then
    raise exception 'income record has been synced to Cash and cannot be edited or deleted directly';
  end if;

  if exists (
    select 1
    from public.school_personal_cash_income_linkage_events e
    where e.income_record_id = v_income.id
      and e.source_table = 'school_income_records'
      and e.source_event_type in ('tuition_income_received', 'income_received')
      and (
        e.sync_status in ('pending', 'pending_cash_request', 'awaiting_cash_confirmation')
        or e.cash_request_status = 'pending'
      )
  ) then
    raise exception 'income record has a pending Cash request and cannot be reversed directly';
  end if;

  if exists (
    select 1
    from public.school_personal_cash_income_linkage_events e
    where e.income_record_id = v_income.id
      and e.source_table = 'school_income_records'
      and e.source_event_type in ('tuition_income_received', 'income_received')
  ) then
    raise exception '该收入已进入 Cash System 联动流程，当前版本暂不支持普通收入撤销。';
  end if;

  if coalesce(v_income.amount, 0) <= 0
    or nullif(trim(coalesce(v_income.currency, '')), '') is null then
    raise exception '收入记录金额或币种无效，不能撤销。';
  end if;

  select count(*)::integer
  into v_existing_reversal_count
  from public.school_account_transactions t
  where t.related_table = 'school_income_records'
    and t.related_id = v_income.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'income_reversal';

  if v_existing_reversal_count > 0 then
    raise exception '该收入已撤销，不能重复撤销。';
  end if;

  select count(*)::integer
  into v_original_transaction_count
  from public.school_account_transactions t
  where t.related_table = 'school_income_records'
    and t.related_id = v_income.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'income_adjust';

  if v_original_transaction_count <> 1 then
    raise exception '收入原始账户流水不存在或不唯一。';
  end if;

  select *
  into v_original_transaction
  from public.school_account_transactions t
  where t.related_table = 'school_income_records'
    and t.related_id = v_income.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'income_adjust'
  for update;

  if v_original_transaction.amount is distinct from v_income.amount then
    raise exception '收入原始账户流水金额不一致，不能撤销。';
  end if;

  if v_original_transaction.account_id is distinct from v_income.account_id
    or v_original_transaction.currency is distinct from v_income.currency then
    raise exception '收入原始账户流水账户或币种不一致，不能撤销。';
  end if;

  select *
  into v_account
  from public.school_accounts a
  where a.id = v_income.account_id
    and coalesce(a.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '入账账户不存在或不可用。';
  end if;

  if v_account.is_active is not true
    or v_account.business_entity_id is distinct from v_income.business_entity_id
    or v_account.currency is distinct from v_income.currency then
    raise exception '入账账户不存在或不可用。';
  end if;

  if coalesce(v_income.include_in_student_settlement, false)
    and v_income.student_id is not null
    and nullif(trim(coalesce(v_income.settlement_month, '')), '') is not null
    and v_income.business_entity_id is not null then
    select count(*)::integer
    into v_locked_settlement_count
    from public.school_student_monthly_settlements s
    where s.student_id = v_income.student_id
      and s.business_entity_id = v_income.business_entity_id
      and s.year_month = v_income.settlement_month
      and s.settlement_status = 'locked';

    if v_locked_settlement_count > 0 then
      raise exception '目标学生月度结算已锁定，不能撤销收入。';
    end if;
  end if;

  v_year_month := to_char(p_reversal_date, 'YYYY-MM');
  v_new_balance := coalesce(v_account.current_balance, 0) - v_income.amount;

  update public.school_accounts a
  set
    current_balance = v_new_balance,
    updated_at = v_now
  where a.id = v_income.account_id;

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
    v_income.account_id,
    v_income.business_entity_id,
    p_reversal_date,
    v_year_month,
    'income_reversal',
    'school_income_records',
    v_income.id,
    v_income.currency,
    -v_income.amount,
    v_new_balance,
    '收入撤销：' || coalesce(v_income.description, ''),
    v_reason,
    'school',
    v_now,
    v_now
  )
  returning id into v_reversal_transaction_id;

  update public.school_income_records i
  set
    status = 'reversed',
    reversed_at = v_now,
    reversal_reason = v_reason,
    reversal_account_transaction_id = v_reversal_transaction_id,
    updated_at = v_now
  where i.id = v_income.id;

  return query
  select
    v_income.id,
    v_reversal_transaction_id,
    v_income.account_id,
    v_new_balance,
    v_income.amount,
    v_income.currency,
    v_year_month,
    'reversed'::text;
end;
$function$;

-- ---- school_cancel_pending_income_record(3) ----
CREATE OR REPLACE FUNCTION public.school_cancel_pending_income_record(p_income_id uuid, p_cancel_reason text, p_operator text DEFAULT NULL::text)
 RETURNS TABLE(income_id uuid, status text, cancelled_at timestamp with time zone, cancelled_reason text, cancelled_by text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_now timestamptz:=now();
  v_reason text:=nullif(btrim(coalesce(p_cancel_reason,'')),'');
  v_operator text:=nullif(btrim(coalesce(p_operator,'')),'');
  v_income public.school_income_records%ROWTYPE;
  v_latest_event public.school_personal_cash_income_linkage_events%ROWTYPE;
  v_account_transaction_count integer:=0;
  v_legacy_tuition boolean:=false;
BEGIN
  PERFORM public.school_require_current_app_operator();
  IF p_income_id IS NULL THEN RAISE EXCEPTION '请选择要作废的收入记录。'; END IF;
  IF v_reason IS NULL THEN RAISE EXCEPTION '请填写作废理由。'; END IF;
  SELECT income.* INTO v_income FROM public.school_income_records income
  WHERE income.id=p_income_id AND coalesce(income.app_type,'')='school' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '收入记录不存在。'; END IF;
  IF v_income.source_type='student_tuition_bill'
     AND v_income.source_snapshot->>'generation_source'='student_tuition_atomic_generate_v1' THEN
    RAISE EXCEPTION 'TUITION_ATOMIC_CANCEL_FORBIDDEN: atomic tuition bill/income cannot use the generic cancellation workflow.';
  END IF;
  v_legacy_tuition:=v_income.source_type='student_tuition_bill';
  IF v_legacy_tuition THEN
    PERFORM public.school_require_feature_gate_state(
      'student_tuition_generate','enabled','TUITION_GENERATION_BLOCKED',
      '历史学费作废在正式生成 gate 开放前保持阻断。'
    );
    INSERT INTO public.school_tuition_atomic_writer_context(
      backend_pid,transaction_id,writer_source
    ) VALUES (pg_backend_pid(),txid_current(),'legacy_tuition_cancel');
  END IF;
  IF v_income.status='cancelled' OR v_income.cancelled_at IS NOT NULL THEN
    RAISE EXCEPTION '该收入已作废，不能重复作废。';
  END IF;
  IF v_income.status IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION '只能作废待确认收入。当前状态：%。',v_income.status;
  END IF;
  IF v_income.account_id IS NOT NULL THEN RAISE EXCEPTION '已有入账账户的收入不能走 pending 作废。'; END IF;
  IF v_income.student_payment_id IS NOT NULL THEN RAISE EXCEPTION '关联学生收款链路的收入不能通过普通 pending 作废处理。'; END IF;
  IF v_income.reversed_at IS NOT NULL OR v_income.reversal_account_transaction_id IS NOT NULL THEN
    RAISE EXCEPTION '已撤销收入不能作废。';
  END IF;
  SELECT count(*)::integer INTO v_account_transaction_count
  FROM public.school_account_transactions transaction_row
  WHERE transaction_row.related_table='school_income_records'
    AND transaction_row.related_id=v_income.id
    AND coalesce(transaction_row.app_type,'')='school';
  IF v_account_transaction_count>0 THEN RAISE EXCEPTION '已有账户流水的收入不能走 pending 作废。'; END IF;
  SELECT event_row.* INTO v_latest_event
  FROM public.school_personal_cash_income_linkage_events event_row
  WHERE event_row.income_record_id=v_income.id
    AND event_row.source_table='school_income_records'
    AND event_row.source_event_type IN ('tuition_income_received','income_received')
  ORDER BY event_row.attempt_no DESC,event_row.created_at DESC,event_row.id DESC
  LIMIT 1 FOR UPDATE;
  IF FOUND THEN
    IF v_latest_event.cash_transaction_id IS NOT NULL THEN RAISE EXCEPTION '已有 Cash transaction 的收入不能作废。'; END IF;
    IF v_latest_event.sync_status IN ('pending','pending_cash_request','awaiting_cash_confirmation','synced')
       OR v_latest_event.cash_request_status IN ('pending','approved','synced') THEN
      RAISE EXCEPTION '该收入存在待确认或已确认 Cash 请求，不能作废。';
    END IF;
    IF v_latest_event.sync_status IN ('failed','blocked') THEN RAISE EXCEPTION 'Cash failed / blocked 的收入暂不允许作废。'; END IF;
    IF NOT (v_latest_event.sync_status='cash_rejected' OR v_latest_event.cash_request_status='rejected') THEN
      RAISE EXCEPTION '只有 Cash 已拒绝或没有 Cash linkage 的 pending 收入可以作废。';
    END IF;
  END IF;
  UPDATE public.school_income_records income SET status='cancelled',cancelled_at=v_now,
    cancelled_reason=v_reason,
    cancelled_by=coalesce(v_operator,nullif(current_setting('request.jwt.claim.sub',true),''),current_user),
    updated_at=v_now WHERE income.id=v_income.id
  RETURNING income.id,income.status,income.cancelled_at,income.cancelled_reason,income.cancelled_by
  INTO income_id,status,cancelled_at,cancelled_reason,cancelled_by;
  IF v_legacy_tuition AND v_income.source_id IS NOT NULL THEN
    UPDATE public.school_student_tuition_bills bill SET status='cancelled',
      cancelled_at=coalesce(bill.cancelled_at,v_now),
      cancelled_reason=coalesce(bill.cancelled_reason,'associated income record cancelled: '||v_reason),
      updated_by=coalesce(v_operator,nullif(current_setting('request.jwt.claim.sub',true),''),current_user),
      updated_at=v_now
    WHERE bill.id=v_income.source_id AND bill.income_record_id=v_income.id
      AND bill.status='income_created' AND bill.app_type='school';
  END IF;
  IF v_legacy_tuition THEN
    DELETE FROM public.school_tuition_atomic_writer_context context_row
    WHERE context_row.backend_pid=pg_backend_pid()
      AND context_row.transaction_id=txid_current();
  END IF;
  RETURN NEXT;
END
$function$;

-- ---- school_create_pending_cash_income_record(14) ----
CREATE OR REPLACE FUNCTION public.school_create_pending_cash_income_record(p_income_date date, p_settlement_month text, p_business_entity_id uuid, p_student_id uuid, p_amount numeric, p_income_category text DEFAULT 'tuition'::text, p_description text DEFAULT NULL::text, p_currency text DEFAULT 'JPY'::text, p_payment_currency text DEFAULT 'JPY'::text, p_exchange_rate numeric DEFAULT NULL::numeric, p_is_taxable_income boolean DEFAULT false, p_tax_category text DEFAULT NULL::text, p_receipt_status text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS TABLE(income_id uuid, account_transaction_id uuid, account_id uuid, income_status text, cash_request_id uuid, cash_request_status text, cash_transaction_id uuid, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_now timestamptz := now();
  v_business_entity public.school_business_entities%rowtype;
  v_student public.school_students%rowtype;
  v_income_id uuid;
  v_currency text := upper(trim(coalesce(p_currency, '')));
  v_payment_currency text := upper(trim(coalesce(p_payment_currency, p_currency, '')));
  v_income_category text := lower(trim(coalesce(p_income_category, '')));
  v_year_month text := trim(coalesce(p_settlement_month, ''));
  v_amount_jpy numeric;
  v_amount_cny numeric;
  v_description text;
  v_note text;
begin
  perform public.school_require_current_app_operator();
  if p_income_date is null then
    raise exception '请选择实际收款日期。';
  end if;

  if v_year_month = '' or v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '结算月份格式无效。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  perform public.school_assert_new_business_entity_allowed(
    p_business_entity_id,
    '新增 Cash 待提交收入'
  );

  if p_student_id is null then
    raise exception '请选择学生。';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception '收入金额必须大于 0。';
  end if;

  if v_income_category not in ('tuition', 'material_fee', 'registration_fee', 'other_fee') then
    raise exception '收入分类无效。';
  end if;

  if v_currency not in ('JPY', 'CNY') or v_payment_currency not in ('JPY', 'CNY') then
    raise exception 'Cash 收入币种仅支持 JPY / CNY。';
  end if;

  if v_currency <> v_payment_currency then
    raise exception 'Cash 收入要求收入币种与收款币种一致。';
  end if;

  if p_exchange_rate is not null and p_exchange_rate <= 0 then
    raise exception '汇率必须大于 0。';
  end if;

  select *
    into v_business_entity
    from public.school_business_entities
   where id = p_business_entity_id
     and is_active = true;

  if not found then
    raise exception '业务归属无效或已停用。';
  end if;

  select *
    into v_student
    from public.school_students
   where id = p_student_id
     and app_type = 'school';

  if not found then
    raise exception '学生无效或不可用。';
  end if;

  if v_student.business_entity_id is not null
     and v_student.business_entity_id is distinct from p_business_entity_id then
    raise exception '学生业务归属与收入业务归属不一致。';
  end if;

  if v_income_category = 'tuition' and exists (
    select 1
      from public.school_student_monthly_settlements s
     where s.student_id = p_student_id
       and s.business_entity_id = p_business_entity_id
       and s.year_month = v_year_month
       and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能直接新增收入。';
  end if;

  if v_currency = 'JPY' then
    v_amount_jpy := p_amount;
    v_amount_cny := case when p_exchange_rate is not null then p_amount / p_exchange_rate else null end;
  else
    v_amount_cny := p_amount;
    v_amount_jpy := case when p_exchange_rate is not null then p_amount * p_exchange_rate else null end;
  end if;

  v_description := coalesce(
    nullif(trim(p_description), ''),
    case v_income_category
      when 'tuition' then '学费收入'
      when 'material_fee' then '教材费收入'
      when 'registration_fee' then '报名费收入'
      else '其他费用收入'
    end
  );
  v_note := nullif(trim(coalesce(p_note, '')), '');

  insert into public.school_income_records (
    business_entity_id,
    student_id,
    student_payment_id,
    account_id,
    income_date,
    year_month,
    settlement_month,
    income_category,
    description,
    currency,
    amount,
    amount_jpy,
    amount_cny,
    exchange_rate,
    payment_currency,
    payment_method,
    status,
    is_taxable_income,
    tax_category,
    receipt_status,
    include_in_student_settlement,
    note,
    app_type,
    created_at,
    updated_at
  )
  values (
    p_business_entity_id,
    p_student_id,
    null,
    null,
    p_income_date,
    v_year_month,
    v_year_month,
    v_income_category,
    v_description,
    v_currency,
    p_amount,
    v_amount_jpy,
    v_amount_cny,
    p_exchange_rate,
    v_payment_currency,
    null,
    'pending',
    coalesce(p_is_taxable_income, false),
    nullif(trim(coalesce(p_tax_category, '')), ''),
    coalesce(nullif(trim(coalesce(p_receipt_status, '')), ''), 'Cash待提交'),
    v_income_category = 'tuition',
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_income_id;

  return query
  select
    v_income_id,
    null::uuid,
    null::uuid,
    'pending'::text,
    null::uuid,
    null::text,
    null::uuid,
    'Cash 收入记录已保存，尚未提交 Cash。'::text;
end;
$function$;

-- ---- school_generate_student_tuition_bill_atomic(6) ----
CREATE OR REPLACE FUNCTION public.school_generate_student_tuition_bill_atomic(p_student_id uuid, p_billing_month text, p_billing_exchange_rate numeric, p_expected_generation_manifest_sha256 text, p_note text DEFAULT NULL::text, p_previous_settlement_absence_ack_reason text DEFAULT NULL::text)
 RETURNS TABLE(tuition_bill_id uuid, billing_identity_id uuid, income_record_id uuid, student_id uuid, business_entity_id uuid, billing_month text, generation_manifest_sha256 text, candidate_count integer, total_lesson_count integer, total_duration_hours numeric, total_base_lesson_fee_jpy numeric, total_aircon_fee_jpy numeric, total_fee_jpy numeric, billing_exchange_rate numeric, previous_carryover_cny numeric, billing_amount_cny numeric, bill_status text, income_status text, idempotent boolean, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  PERFORM public.school_require_current_app_operator();
  PERFORM public.school_require_feature_gate_state(
    'student_tuition_generate','enabled','TUITION_GENERATION_BLOCKED',
    '学费应收生成功能尚未开放，当前禁止生成正式账单或收入。'
  );
  RETURN QUERY SELECT *
  FROM public.school_generate_student_tuition_bill_atomic_core(
    p_student_id,p_billing_month,p_billing_exchange_rate,
    p_expected_generation_manifest_sha256,p_note,NULL,
    p_previous_settlement_absence_ack_reason
  );
END
$function$;

-- ===== 注释：各追加一句准入说明 =====
COMMENT ON FUNCTION public.school_create_income_record(p_income_date date, p_settlement_month text, p_business_entity_id uuid, p_student_id uuid, p_account_id uuid, p_amount numeric, p_income_category text, p_description text, p_currency text, p_payment_currency text, p_exchange_rate numeric, p_payment_method text, p_is_taxable_income boolean, p_tax_category text, p_receipt_status text, p_include_in_student_settlement boolean, p_note text) IS 'Verified RPC for v2 income creation: creates received income, updates account balance, and inserts account transaction. Only tuition income participates in student settlement. Requires an active admin or operator membership.';
COMMENT ON FUNCTION public.school_update_income_record(p_income_id uuid, p_income_date date, p_settlement_month text, p_business_entity_id uuid, p_student_id uuid, p_account_id uuid, p_amount numeric, p_income_category text, p_description text, p_currency text, p_payment_currency text, p_exchange_rate numeric, p_payment_method text, p_is_taxable_income boolean, p_tax_category text, p_receipt_status text, p_include_in_student_settlement boolean, p_note text) IS 'Guarded v2 income edit: updates one received income and its original account transaction only when settlement/account guards pass; rejects personal Cash-linked tuition income. Requires an active admin or operator membership.';
COMMENT ON FUNCTION public.school_reverse_income_record(p_income_id uuid, p_reversal_date date, p_reason text) IS 'Guarded RPC for v2 income reversal: marks a received income as reversed, restores account balance, inserts a negative income_reversal transaction, and rejects personal Cash-linked tuition income. Requires an active admin or operator membership.';
COMMENT ON FUNCTION public.school_cancel_pending_income_record(p_income_id uuid, p_cancel_reason text, p_operator text) IS 'Guardedly cancels ordinary pending School income and preserves the legacy tuition cancellation path behind the generate gate. R2-F-B atomic tuition income is permanently rejected. Requires an active admin or operator membership.';
COMMENT ON FUNCTION public.school_create_pending_cash_income_record(p_income_date date, p_settlement_month text, p_business_entity_id uuid, p_student_id uuid, p_amount numeric, p_income_category text, p_description text, p_currency text, p_payment_currency text, p_exchange_rate numeric, p_is_taxable_income boolean, p_tax_category text, p_receipt_status text, p_note text) IS 'Creates one pending School income record for later Cash submission. Amount JPY/CNY conversion is calculated in DB/RPC and no School account ledger or Cash request is created. Requires an active admin or operator membership.';
COMMENT ON FUNCTION public.school_generate_student_tuition_bill_atomic(p_student_id uuid, p_billing_month text, p_billing_exchange_rate numeric, p_expected_generation_manifest_sha256 text, p_note text, p_previous_settlement_absence_ack_reason text) IS 'R2-F-B authoritative atomic tuition writer. The public wrapper is R0-gated; clients submit no amounts or candidate details. Requires an active admin or operator membership.';

DO $post$
DECLARE
  t record; v_n int; v_md5 text; v_acl text; v_cmt text; v_cfg text;
  v_owner text; v_sec boolean; v_strict boolean; v_par char; v_leak boolean;
  v_cost real; v_rows real;
BEGIN
  FOR t IN
    SELECT * FROM (VALUES
    ('school_create_income_record',17,'9d141f81ed1aba0c4c4e440ff4cc3c14','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','Verified RPC for v2 income creation: creates received income, updates account balance, and inserts account transaction. Only tuition income participates in student settlement. Requires an active admin or operator membership.','search_path=public'),
    ('school_update_income_record',18,'a5189e72f4ce4e692afb746c107d2241','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','Guarded v2 income edit: updates one received income and its original account transaction only when settlement/account guards pass; rejects personal Cash-linked tuition income. Requires an active admin or operator membership.','search_path=public'),
    ('school_reverse_income_record',3,'60005d5436e74165ae3d23749fed823b','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','Guarded RPC for v2 income reversal: marks a received income as reversed, restores account balance, inserts a negative income_reversal transaction, and rejects personal Cash-linked tuition income. Requires an active admin or operator membership.','search_path=public'),
    ('school_cancel_pending_income_record',3,'078349ebbe8c3be3d93aa505eac3b1ef','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','Guardedly cancels ordinary pending School income and preserves the legacy tuition cancellation path behind the generate gate. R2-F-B atomic tuition income is permanently rejected. Requires an active admin or operator membership.','search_path=pg_catalog, public'),
    ('school_create_pending_cash_income_record',14,'191350ab8a1bbb93254b8c1142d4b64b','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','Creates one pending School income record for later Cash submission. Amount JPY/CNY conversion is calculated in DB/RPC and no School account ledger or Cash request is created. Requires an active admin or operator membership.','search_path=public'),
    ('school_generate_student_tuition_bill_atomic',6,'88b6d181d6b5eb83c7eceb37c056a031','{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}','R2-F-B authoritative atomic tuition writer. The public wrapper is R0-gated; clients submit no amounts or candidate details. Requires an active admin or operator membership.','search_path=pg_catalog, public')
    ) AS v(proname, nargs, md5, acl, cmt, cfg)
  LOOP
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=t.proname AND p.pronargs=t.nargs;
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'OPWRI_POST_ARITY: public.%(%) 匹配到 % 个（应为 1）', t.proname, t.nargs, v_n;
    END IF;

    SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,''),
           coalesce(obj_description(p.oid,'pg_proc'),'<NULL>'),
           coalesce(array_to_string(p.proconfig,', '),'<NULL>'),
           pg_get_userbyid(p.proowner), p.prosecdef, p.proisstrict,
           p.proparallel, p.proleakproof, p.procost, p.prorows
      INTO v_md5, v_acl, v_cmt, v_cfg, v_owner, v_sec, v_strict, v_par, v_leak, v_cost, v_rows
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=t.proname AND p.pronargs=t.nargs;

    IF v_md5 <> t.md5 THEN
      RAISE EXCEPTION 'OPWRI_POST_MD5: %(%) 定义为 %，期望 %', t.proname, t.nargs, v_md5, t.md5;
    END IF;
    IF v_acl <> t.acl THEN
      RAISE EXCEPTION 'OPWRI_POST_ACL: %(%) ACL 为 %，期望 %', t.proname, t.nargs, v_acl, t.acl;
    END IF;
    IF v_cmt <> t.cmt THEN
      RAISE EXCEPTION 'OPWRI_POST_COMMENT: %(%) 注释为 [%]，期望 [%]', t.proname, t.nargs, v_cmt, t.cmt;
    END IF;
    IF v_cfg <> t.cfg THEN
      RAISE EXCEPTION 'OPWRI_POST_CONFIG: %(%) proconfig 为 %，期望 %', t.proname, t.nargs, v_cfg, t.cfg;
    END IF;
    IF v_owner <> 'postgres' OR v_sec IS NOT TRUE OR v_strict IS NOT FALSE
       OR v_par <> 'u' OR v_leak IS NOT FALSE OR v_cost <> 100 OR v_rows <> 1000 THEN
      RAISE EXCEPTION 'OPWRI_POST_ATTRS: %(%) owner=% secdef=% strict=% parallel=% leakproof=% cost=% rows=%',
        t.proname, t.nargs, v_owner, v_sec, v_strict, v_par, v_leak, v_cost, v_rows;
    END IF;
  END LOOP;
  RAISE NOTICE 'OPWRI_POST: 6 个函数的 md5 / ACL / COMMENT / proconfig / 执行属性全部符合预期';
END
$post$;

DO $calls$
DECLARE r record; v_def text; v_op int; v_ad int;
BEGIN
  FOR r IN SELECT p.oid, p.proname, p.pronargs FROM pg_proc p
             JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='public' AND p.proname IN ('school_create_income_record','school_update_income_record','school_reverse_income_record','school_cancel_pending_income_record','school_create_pending_cash_income_record','school_generate_student_tuition_bill_atomic') LOOP
    v_def := pg_get_functiondef(r.oid);
    v_op := (length(v_def)-length(replace(v_def,'school_require_current_app_operator','')))/length('school_require_current_app_operator');
    v_ad := (length(v_def)-length(replace(v_def,'school_require_current_app_admin','')))
            /length('school_require_current_app_admin');
    IF v_op <> 1 THEN
      RAISE EXCEPTION 'OPWRI_POST_CALLS: %(%) 内 operator 守卫调用 % 次，期望 1',
        r.proname, r.pronargs, v_op;
    END IF;
    IF v_ad <> 0 THEN
      RAISE EXCEPTION 'OPWRI_POST_ADMIN_CALLS: %(%) 内出现 admin 守卫调用 % 次，本批不应引入',
        r.proname, r.pronargs, v_ad;
    END IF;
  END LOOP;
  RAISE NOTICE 'OPWRI_POST: 6 个函数体内 operator 守卫调用次数均为 1，admin 守卫 0 次';
END
$calls$;

\if :is_commit
COMMIT;
\echo '>>> 已 COMMIT'
\else
ROLLBACK;
\echo '>>> 已 ROLLBACK（rehearsal）'
\endif
