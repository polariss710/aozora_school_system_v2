-- =============================================================================
-- 教务老师写入权限（工资 + 支出）：回滚
--
-- 把 8 个 writer 逐字节还原为部署前的生产 canonical、还原 3 条 COMMENT，
-- 并删除本次新建的 school_require_current_app_operator()。
--
-- ⚠️ 回滚只还原【函数定义与注释】。它【不撤销】教务老师在此期间已经做出的
--    业务动作 —— 工资快照、支付请求、支出记录一旦建立就还在。
--    事后不得把整体状态描述为「恢复到部署前」。
--
-- ⛔ 硬停止：若新守卫【已被别的函数引用】，删除会失败或留下断链。
--    脚本对此有断言：除本次 8 个之外，不得有别的函数体提到它。
--
-- 用法
--   psql -v ON_ERROR_STOP=1 -f <本文件>
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TEMP TABLE opwr_target(
  proname text, nargs int, pre_md5 text, post_md5 text,
  acl text, pre_cmt text, post_cmt text) ON COMMIT DROP;
INSERT INTO opwr_target VALUES
    ('school_generate_teacher_monthly_wage',2,'6c320b41271c744714b1b84d8ca6e6f1','71a380a99b408f8d16fbca1acc845f0a','{postgres=X/postgres,authenticated=X/postgres}','Backward-compatible wrapper for school_generate_teacher_monthly_wage(text, uuid, uuid) with no business-entity scope.','Backward-compatible wrapper for school_generate_teacher_monthly_wage(text, uuid, uuid) with no business-entity scope.'),
    ('school_generate_teacher_monthly_wage',3,'093da7c5bee268541efdcbedb0ee1177','19bb575c75751fde1e9ea4e61f1e2e12','{postgres=X/postgres,authenticated=X/postgres}','Generates wage locks/details only after the shared structured preflight passes. Unique no_wage lessons remain zero-value details and skip effective settlement; payable lessons require completion.','Generates wage locks/details only after the shared structured preflight passes. Unique no_wage lessons remain zero-value details and skip effective settlement; payable lessons require completion.'),
    ('school_adjust_teacher_wage_detail',5,'971c1d3816e9273f94bf54e8f55b636a','3b334aedf00991d52fc8407da5a6d54b','{postgres=X/postgres,authenticated=X/postgres}','Adjusts one teacher wage snapshot detail with a required reason, recalculates the parent wage snapshot totals from saved details, and writes an append-only audit row. Rejects voided/non-locked snapshots and snapshots with any teacher_wage payment request.','Adjusts one teacher wage snapshot detail with a required reason, recalculates the parent wage snapshot totals from saved details, and writes an append-only audit row. Rejects voided/non-locked snapshots and snapshots with any teacher_wage payment request.'),
    ('school_create_teacher_wage_expense_record',3,'765356535f968e3fb7771a7e9557fc97','0f837b669dd0e5e4a9dbf52fa41b4ac5','{postgres=X/postgres,authenticated=X/postgres}','Creates or returns one active pending teacher_wage school_expense_records row from one locked teacher wage snapshot. Cancelled historical rows do not block regeneration. Does not create Cash requests, Cash transactions, payment requests, account transactions, or account balance changes.','Creates or returns one active pending teacher_wage school_expense_records row from one locked teacher wage snapshot. Cancelled historical rows do not block regeneration. Does not create Cash requests, Cash transactions, payment requests, account transactions, or account balance changes.'),
    ('school_void_unsubmitted_teacher_wage_expense_record',2,'087f5092f24f6f7a522b01d2db8f6dc1','ba12e41decaceacddc6ae760afef4f3e','{postgres=X/postgres,authenticated=X/postgres}','Logically cancels one pending teacher_wage school_expense_records row before Cash transaction creation. Allows rejected Cash requests with no Cash transaction, preserves rejected request metadata, and rejects non-teacher_wage, paid, active Cash-pending/approved/synced, and already-cancelled records.','Logically cancels one pending teacher_wage school_expense_records row before Cash transaction creation. Allows rejected Cash requests with no Cash transaction, preserves rejected request metadata, and rejects non-teacher_wage, paid, active Cash-pending/approved/synced, and already-cancelled records.'),
    ('school_create_expense_record',16,'9663b3a65a1433381cac23a6d6af10b1','4f6e363bd7f0bd68c7b3e5c59e6c644e','{postgres=X/postgres,authenticated=X/postgres}','Active-admin-only RPC for ordinary paid School expense creation. Creates one paid manual_school expense with DB-authoritative creator audit, deducts one School account balance once, and inserts one negative expense_adjust transaction.','Active admin or operator RPC for ordinary paid School expense creation. Creates one paid manual_school expense with DB-authoritative creator audit, deducts one School account balance once, and inserts one negative expense_adjust transaction.'),
    ('school_update_expense_record',15,'f282ec2a7e73693dadb8adba82058c9f','a63f21efb1e396185915114f6f5ff956','{postgres=X/postgres,authenticated=X/postgres}','Active-admin ordinary expense update. school_expense_records.updated_at is the sole DB-authoritative optimistic-lock token; the old overload has no client execute privilege.','Active admin or operator ordinary expense update. school_expense_records.updated_at is the sole DB-authoritative optimistic-lock token; the old overload has no client execute privilege.'),
    ('school_create_pending_cash_expense_record_v1',15,'48c2d74d3fa6fc8899b4685b25d32203','f6485f7a714f3a764f58c3d0ddf30d94','{postgres=X/postgres,authenticated=X/postgres}','Active-admin-only idempotent writer for one manual Cash pending expense. It writes no School account balance, School account transaction, Cash request, or Cash transaction.','Active admin or operator idempotent writer for one manual Cash pending expense. It writes no School account balance, School account transaction, Cash request, or Cash transaction.');

DO $pre$
DECLARE r record; v_n int; v_md5 text; v_acl text; v_cmt text; v_def text;
BEGIN
  -- 当前必须【正是本次部署的结果】，否则不是「回滚本次改动」。
  FOR r IN SELECT * FROM opwr_target ORDER BY proname, nargs LOOP
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=r.proname AND p.pronargs=r.nargs;
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'OPWR_NOT_UNIQUE: %(%) 匹配 % 个', r.proname, r.nargs, v_n; END IF;
    SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,''), obj_description(p.oid,'pg_proc')
      INTO v_md5, v_acl, v_cmt FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=r.proname AND p.pronargs=r.nargs;
    IF v_md5 = r.pre_md5 THEN
      RAISE EXCEPTION 'OPWR_ALREADY_BASELINE: %(%) 已是部署前定义，无需回滚', r.proname, r.nargs; END IF;
    IF v_md5 <> r.post_md5 THEN
      RAISE EXCEPTION 'OPWR_UNEXPECTED: %(%) md5=%  —— 不是本次部署的结果，拒绝覆盖',
        r.proname, r.nargs, v_md5; END IF;
    IF v_acl <> r.acl THEN
      RAISE EXCEPTION 'OPWR_ACL_DRIFT: %(%) 得 %', r.proname, r.nargs, v_acl; END IF;
    IF v_cmt IS DISTINCT FROM r.post_cmt THEN
      RAISE EXCEPTION 'OPWR_COMMENT_DRIFT: %(%) 注释与部署后不符', r.proname, r.nargs; END IF;
  END LOOP;

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_require_current_app_operator';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'OPWR_GUARD_COUNT: 新守卫有 % 个（应为 1）', v_n; END IF;

  RAISE NOTICE 'OPWR: 回滚前基线通过（当前正是本次部署的结果）';
END
$pre$;

-- ── 还原 8 个函数的生产 canonical ──
-- school_generate_teacher_monthly_wage（2 参数）
CREATE OR REPLACE FUNCTION public.school_generate_teacher_monthly_wage(p_year_month text, p_teacher_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(wage_lock_id uuid, teacher_id uuid, teacher_name text, settlement_month text, business_entity_id uuid, business_name text, lesson_count integer, total_minutes numeric, pay_hours numeric, lesson_wage_jpy numeric, total_jpy numeric, status text, locked_at timestamp with time zone, detail_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  perform public.school_require_current_app_admin();
  return query select * from public.school_generate_teacher_monthly_wage(
    p_year_month,p_teacher_id,null::uuid
  );
end
$function$;

-- school_generate_teacher_monthly_wage（3 参数）
CREATE OR REPLACE FUNCTION public.school_generate_teacher_monthly_wage(p_year_month text, p_teacher_id uuid, p_business_entity_id uuid)
 RETURNS TABLE(wage_lock_id uuid, teacher_id uuid, teacher_name text, settlement_month text, business_entity_id uuid, business_name text, lesson_count integer, total_minutes numeric, pay_hours numeric, lesson_wage_jpy numeric, total_jpy numeric, status text, locked_at timestamp with time zone, detail_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_preflight jsonb;
  v_summary jsonb;
  v_first_blocker text;
begin
  perform public.school_require_current_app_admin();
  v_preflight := public.school_get_teacher_monthly_wage_generation_preflight(
    p_year_month,p_teacher_id,p_business_entity_id
  );
  v_summary := v_preflight->'summary';
  if (v_summary->>'candidate_actual_count')::integer = 0 then
    raise exception 'WAGE_NO_CANDIDATES';
  end if;
  if (v_summary->>'active_wage_lock_count')::integer > 0 then
    raise exception 'WAGE_ACTIVE_LOCK_EXISTS';
  end if;
  if (v_summary->>'existing_wage_detail_count')::integer > 0 then
    raise exception 'WAGE_DETAIL_ALREADY_CONSUMED';
  end if;
  if (v_summary->>'blocker_count')::integer > 0 then
    select value->>'blocker_code' into v_first_blocker
    from jsonb_array_elements(v_preflight->'blockers')
    order by case value->>'blocker_code'
      when 'WAGE_LESSON_FACT_INCOMPLETE' then 1
      when 'WAGE_RULE_MISSING' then 2
      when 'WAGE_RULE_DUPLICATE' then 3
      when 'WAGE_SETTLEMENT_BUSINESS_ENTITY_MISMATCH' then 4
      else 5 end
    limit 1;
    raise exception using errcode='P0001', message=coalesce(v_first_blocker,'WAGE_PREFLIGHT_BLOCKED');
  end if;

  return query
  with candidates as materialized (
    select * from public.school_get_teacher_monthly_wage_generation_candidate_facts(
      p_year_month,p_teacher_id,p_business_entity_id
    )
  ), lock_groups as (
    select c.teacher_id,max(c.teacher_name) teacher_name,c.business_entity_id,
      max(c.business_name) business_name,
      case when bool_and(c.is_no_wage) then 'no_wage' else 'jpy_hourly' end settlement_type,
      count(*)::integer lesson_count,sum(c.actual_minutes)::numeric total_minutes,
      sum(c.pay_hours)::numeric pay_hours,sum(c.lesson_wage_jpy)::numeric lesson_wage_jpy,
      sum(c.lesson_wage_jpy)::numeric total_jpy
    from candidates c
    group by c.teacher_id,c.business_entity_id
  ), inserted_locks as (
    insert into public.school_teacher_wage_locks as w(
      settlement_month,teacher_id,teacher_name,business_entity_id,business_name,
      settlement_type,exchange_rate,total_minutes,pay_hours,lesson_wage_jpy,
      lesson_wage_cny,fee_jpy,total_jpy,total_cny,lesson_count,status,locked_at,updated_at
    ) select p_year_month,g.teacher_id,g.teacher_name,g.business_entity_id,g.business_name,
      g.settlement_type,0,g.total_minutes,g.pay_hours,g.lesson_wage_jpy,0,0,g.total_jpy,0,
      g.lesson_count,'locked',now(),now() from lock_groups g
    returning w.id,w.teacher_id,w.teacher_name,w.settlement_month,w.business_entity_id,
      w.business_name,w.lesson_count,w.total_minutes,w.pay_hours,w.lesson_wage_jpy,
      w.total_jpy,w.status,w.locked_at
  ), inserted_details as (
    insert into public.school_teacher_wage_lock_details as d(
      lock_id,lesson_record_id,lesson_date,start_time,end_time,student_id,student_name,
      subject_id,subject_name,business_entity_id,business_name,pay_hours,lesson_wage_jpy,
      lesson_wage_cny,transport_fee_jpy,classroom_fee_jpy,total_jpy,total_cny,
      settlement_type,exchange_rate,is_no_wage,status,lesson_content
    ) select il.id,c.lesson_record_id,c.lesson_date,c.start_time,c.end_time,c.student_id,
      c.student_name,c.subject_id,c.subject_name,c.business_entity_id,c.business_name,
      c.pay_hours,c.lesson_wage_jpy,0,0,0,c.lesson_wage_jpy,0,c.settlement_type,0,
      c.is_no_wage,c.lesson_status,c.lesson_content
    from candidates c join inserted_locks il on il.teacher_id=c.teacher_id
      and il.business_entity_id is not distinct from c.business_entity_id
    returning d.lock_id
  ), detail_counts as (
    select lock_id,count(*)::integer detail_count from inserted_details group by lock_id
  )
  select il.id,il.teacher_id,il.teacher_name,il.settlement_month,il.business_entity_id,
    il.business_name,il.lesson_count,il.total_minutes,il.pay_hours,il.lesson_wage_jpy,
    il.total_jpy,il.status,il.locked_at,dc.detail_count
  from inserted_locks il join detail_counts dc on dc.lock_id=il.id
  order by il.teacher_name nulls last,il.teacher_id;
end
$function$;

-- school_adjust_teacher_wage_detail（5 参数）
CREATE OR REPLACE FUNCTION public.school_adjust_teacher_wage_detail(p_wage_detail_id uuid, p_pay_hours numeric, p_transport_fee_jpy numeric, p_classroom_fee_jpy numeric, p_reason text)
 RETURNS TABLE(adjustment_id uuid, wage_lock_id uuid, wage_detail_id uuid, pay_hours numeric, lesson_wage_jpy numeric, lesson_wage_cny numeric, transport_fee_jpy numeric, classroom_fee_jpy numeric, total_jpy numeric, total_cny numeric, lock_pay_hours numeric, lock_lesson_wage_jpy numeric, lock_lesson_wage_cny numeric, lock_fee_jpy numeric, lock_total_jpy numeric, lock_total_cny numeric, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_detail public.school_teacher_wage_lock_details%rowtype;
  v_lock public.school_teacher_wage_locks%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_pay_hours numeric := p_pay_hours;
  v_transport_fee_jpy numeric := round(coalesce(p_transport_fee_jpy, 0));
  v_classroom_fee_jpy numeric := round(coalesce(p_classroom_fee_jpy, 0));
  v_hourly_rate_jpy numeric := 0;
  v_exchange_rate numeric := 0;
  v_new_lesson_wage_jpy numeric := 0;
  v_new_lesson_wage_cny numeric := 0;
  v_new_total_jpy numeric := 0;
  v_new_total_cny numeric := 0;
  v_new_lock_pay_hours numeric := 0;
  v_new_lock_lesson_wage_jpy numeric := 0;
  v_new_lock_lesson_wage_cny numeric := 0;
  v_new_lock_fee_jpy numeric := 0;
  v_new_lock_total_jpy numeric := 0;
  v_new_lock_total_cny numeric := 0;
  v_adjustment_id uuid;
  v_created_at timestamptz;
begin
  perform public.school_require_current_app_admin();

  if p_wage_detail_id is null then
    raise exception '请选择要调整的工资明细。';
  end if;

  if v_reason is null then
    raise exception '请输入调整备注。';
  end if;

  if v_pay_hours is null then
    raise exception '请输入结算课时。';
  end if;

  if v_pay_hours < 0 or v_pay_hours > 24 then
    raise exception '结算课时必须在 0 到 24 之间。当前值：%', v_pay_hours;
  end if;

  if v_transport_fee_jpy < 0 or v_transport_fee_jpy > 1000000 then
    raise exception '交通费必须在 0 到 1,000,000 JPY 之间。当前值：%', v_transport_fee_jpy;
  end if;

  if v_classroom_fee_jpy < 0 or v_classroom_fee_jpy > 1000000 then
    raise exception '教室费必须在 0 到 1,000,000 JPY 之间。当前值：%', v_classroom_fee_jpy;
  end if;

  select *
    into v_detail
    from public.school_teacher_wage_lock_details d
   where d.id = p_wage_detail_id
   for update;

  if not found then
    raise exception '工资明细不存在：%。', p_wage_detail_id;
  end if;

  select *
    into v_lock
    from public.school_teacher_wage_locks w
   where w.id = v_detail.lock_id
   for update;

  if not found then
    raise exception '工资快照不存在：%。', v_detail.lock_id;
  end if;

  if coalesce(v_lock.status, '') <> 'locked' then
    raise exception '只有已生成且未作废的工资快照可以调整。当前状态：%。', v_lock.status;
  end if;

  if v_lock.voided_at is not null then
    raise exception '已作废的工资快照不能调整：%。', v_lock.id;
  end if;

  if exists (
    select 1
    from public.school_payment_requests p
    where p.source_type = 'teacher_wage'
      and p.source_id = v_lock.id
  ) then
    raise exception '该工资快照已生成支付请求，不能直接调整。请先按支付流程处理或另行走受控修正流程。';
  end if;

  if coalesce(v_detail.is_no_wage, false) = true
     or coalesce(v_detail.settlement_type, '') = 'no_wage' then
    v_new_lesson_wage_jpy := 0;
  else
    if coalesce(v_detail.pay_hours, 0) <= 0 then
      if v_pay_hours = 0 then
        v_new_lesson_wage_jpy := 0;
      else
        raise exception '当前明细结算课时为 0，无法从工资快照推导时给，不能自动调整为正课时。';
      end if;
    else
      v_hourly_rate_jpy := coalesce(v_detail.lesson_wage_jpy, 0) / v_detail.pay_hours;
      v_new_lesson_wage_jpy := round(v_pay_hours * v_hourly_rate_jpy);
    end if;
  end if;

  v_exchange_rate := coalesce(nullif(v_detail.exchange_rate, 0), nullif(v_lock.exchange_rate, 0), 0);
  v_new_total_jpy := v_new_lesson_wage_jpy + v_transport_fee_jpy + v_classroom_fee_jpy;
  v_new_lesson_wage_cny := round(v_new_lesson_wage_jpy * v_exchange_rate * 100) / 100;
  v_new_total_cny := round(v_new_total_jpy * v_exchange_rate * 100) / 100;

  if v_pay_hours is not distinct from coalesce(v_detail.pay_hours, 0)
     and v_transport_fee_jpy is not distinct from coalesce(v_detail.transport_fee_jpy, 0)
     and v_classroom_fee_jpy is not distinct from coalesce(v_detail.classroom_fee_jpy, 0) then
    raise exception '调整前后数值没有变化。';
  end if;

  update public.school_teacher_wage_lock_details d
     set pay_hours = v_pay_hours,
         lesson_wage_jpy = v_new_lesson_wage_jpy,
         lesson_wage_cny = v_new_lesson_wage_cny,
         transport_fee_jpy = v_transport_fee_jpy,
         classroom_fee_jpy = v_classroom_fee_jpy,
         total_jpy = v_new_total_jpy,
         total_cny = v_new_total_cny
   where d.id = v_detail.id;

  select
    coalesce(sum(d.pay_hours), 0),
    coalesce(sum(d.lesson_wage_jpy), 0),
    coalesce(sum(d.lesson_wage_cny), 0),
    coalesce(sum(coalesce(d.transport_fee_jpy, 0) + coalesce(d.classroom_fee_jpy, 0)), 0),
    coalesce(sum(d.total_jpy), 0),
    coalesce(sum(d.total_cny), 0)
  into
    v_new_lock_pay_hours,
    v_new_lock_lesson_wage_jpy,
    v_new_lock_lesson_wage_cny,
    v_new_lock_fee_jpy,
    v_new_lock_total_jpy,
    v_new_lock_total_cny
  from public.school_teacher_wage_lock_details d
  where d.lock_id = v_lock.id;

  update public.school_teacher_wage_locks w
     set pay_hours = v_new_lock_pay_hours,
         lesson_wage_jpy = v_new_lock_lesson_wage_jpy,
         lesson_wage_cny = v_new_lock_lesson_wage_cny,
         fee_jpy = v_new_lock_fee_jpy,
         total_jpy = v_new_lock_total_jpy,
         total_cny = v_new_lock_total_cny,
         updated_at = now()
   where w.id = v_lock.id;

  insert into public.school_teacher_wage_detail_adjustments (
    wage_lock_id,
    wage_detail_id,
    reason,
    old_pay_hours,
    new_pay_hours,
    old_lesson_wage_jpy,
    new_lesson_wage_jpy,
    old_lesson_wage_cny,
    new_lesson_wage_cny,
    old_transport_fee_jpy,
    new_transport_fee_jpy,
    old_classroom_fee_jpy,
    new_classroom_fee_jpy,
    old_total_jpy,
    new_total_jpy,
    old_total_cny,
    new_total_cny,
    old_lock_pay_hours,
    new_lock_pay_hours,
    old_lock_lesson_wage_jpy,
    new_lock_lesson_wage_jpy,
    old_lock_lesson_wage_cny,
    new_lock_lesson_wage_cny,
    old_lock_fee_jpy,
    new_lock_fee_jpy,
    old_lock_total_jpy,
    new_lock_total_jpy,
    old_lock_total_cny,
    new_lock_total_cny
  )
  values (
    v_lock.id,
    v_detail.id,
    v_reason,
    coalesce(v_detail.pay_hours, 0),
    v_pay_hours,
    coalesce(v_detail.lesson_wage_jpy, 0),
    v_new_lesson_wage_jpy,
    coalesce(v_detail.lesson_wage_cny, 0),
    v_new_lesson_wage_cny,
    coalesce(v_detail.transport_fee_jpy, 0),
    v_transport_fee_jpy,
    coalesce(v_detail.classroom_fee_jpy, 0),
    v_classroom_fee_jpy,
    coalesce(v_detail.total_jpy, 0),
    v_new_total_jpy,
    coalesce(v_detail.total_cny, 0),
    v_new_total_cny,
    coalesce(v_lock.pay_hours, 0),
    v_new_lock_pay_hours,
    coalesce(v_lock.lesson_wage_jpy, 0),
    v_new_lock_lesson_wage_jpy,
    coalesce(v_lock.lesson_wage_cny, 0),
    v_new_lock_lesson_wage_cny,
    coalesce(v_lock.fee_jpy, 0),
    v_new_lock_fee_jpy,
    coalesce(v_lock.total_jpy, 0),
    v_new_lock_total_jpy,
    coalesce(v_lock.total_cny, 0),
    v_new_lock_total_cny
  )
  returning
    school_teacher_wage_detail_adjustments.id,
    school_teacher_wage_detail_adjustments.created_at
  into v_adjustment_id, v_created_at;

  return query
  select
    v_adjustment_id,
    v_lock.id,
    v_detail.id,
    v_pay_hours,
    v_new_lesson_wage_jpy,
    v_new_lesson_wage_cny,
    v_transport_fee_jpy,
    v_classroom_fee_jpy,
    v_new_total_jpy,
    v_new_total_cny,
    v_new_lock_pay_hours,
    v_new_lock_lesson_wage_jpy,
    v_new_lock_lesson_wage_cny,
    v_new_lock_fee_jpy,
    v_new_lock_total_jpy,
    v_new_lock_total_cny,
    v_created_at;
end;
$function$;

-- school_create_teacher_wage_expense_record（3 参数）
CREATE OR REPLACE FUNCTION public.school_create_teacher_wage_expense_record(p_wage_lock_id uuid, p_expense_date date DEFAULT NULL::date, p_note text DEFAULT NULL::text)
 RETURNS TABLE(expense_id uuid, wage_lock_id uuid, expense_status text, expense_category text, source_type text, source_id uuid, teacher_id uuid, payee_name_snapshot text, business_entity_id uuid, year_month text, currency text, amount numeric, amount_jpy numeric, amount_cny numeric, cash_request_status text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_wage public.school_teacher_wage_locks%rowtype;
  v_existing_expense public.school_expense_records%rowtype;
  v_expense_id uuid;
  v_expense_date date;
  v_now timestamptz := now();
  v_description text;
  v_note text;
begin
  perform public.school_require_current_app_admin();

  if p_wage_lock_id is null then
    raise exception 'wage lock id is required';
  end if;

  select *
    into v_wage
    from public.school_teacher_wage_locks
   where id = p_wage_lock_id
   for update;

  if not found then
    raise exception 'teacher wage lock not found: %', p_wage_lock_id;
  end if;

  if coalesce(v_wage.status, '') <> 'locked' then
    raise exception 'only locked teacher wage records can generate expense records. current status: %', v_wage.status;
  end if;

  if v_wage.voided_at is not null then
    raise exception 'voided teacher wage records cannot generate expense records: %', p_wage_lock_id;
  end if;

  if v_wage.teacher_id is null then
    raise exception 'teacher wage record has no teacher_id: %', p_wage_lock_id;
  end if;

  if nullif(trim(coalesce(v_wage.teacher_name, '')), '') is null then
    raise exception 'teacher wage record has no teacher_name: %', p_wage_lock_id;
  end if;

  if v_wage.business_entity_id is null then
    raise exception 'teacher wage record has no business_entity_id: %', p_wage_lock_id;
  end if;

  if nullif(trim(coalesce(v_wage.business_name, '')), '') is null then
    raise exception 'teacher wage record has no business_name: %', p_wage_lock_id;
  end if;

  if v_wage.settlement_month !~ '^[0-9]{4}-[0-9]{2}$' then
    raise exception 'invalid teacher wage settlement month: %', v_wage.settlement_month;
  end if;

  if coalesce(v_wage.total_jpy, 0) <= 0 then
    raise exception 'teacher wage total_jpy must be greater than 0 to generate an expense record. current total_jpy: %', v_wage.total_jpy;
  end if;

  select *
    into v_existing_expense
    from public.school_expense_records e
   where e.source_type = 'teacher_wage'
     and e.source_id = p_wage_lock_id
     and e.app_type = 'school'
     and e.cancelled_at is null
     and coalesce(e.status, '') not in ('cancelled', 'void', 'voided')
   order by e.created_at asc
   limit 1;

  if v_existing_expense.id is not null then
    return query
    select
      e.id,
      p_wage_lock_id,
      e.status,
      e.expense_category,
      e.source_type,
      e.source_id,
      e.teacher_id,
      e.payee_name_snapshot,
      e.business_entity_id,
      e.year_month,
      e.currency,
      e.amount,
      e.amount_jpy,
      e.amount_cny,
      e.cash_request_status,
      e.created_at
    from public.school_expense_records e
    where e.id = v_existing_expense.id;

    return;
  end if;

  v_expense_date := coalesce(
    p_expense_date,
    (to_date(v_wage.settlement_month || '-01', 'YYYY-MM-DD') + interval '1 month - 1 day')::date
  );
  v_description := trim(both from concat(v_wage.settlement_month, ' ', v_wage.teacher_name, ' 老师工资'));
  v_note := nullif(trim(coalesce(p_note, '')), '');

  insert into public.school_expense_records (
    business_entity_id,
    teacher_id,
    student_id,
    salary_payment_id,
    account_id,
    expense_date,
    year_month,
    expense_category,
    description,
    currency,
    amount,
    amount_jpy,
    amount_cny,
    exchange_rate,
    payment_method,
    status,
    is_business_expense,
    tax_category,
    receipt_status,
    reimbursement_status,
    reimbursement_note,
    note,
    app_type,
    source_type,
    source_id,
    payee_name_snapshot,
    cash_request_id,
    cash_request_status,
    cash_transaction_id,
    cash_requested_at,
    cash_synced_at,
    cash_error_message,
    created_at,
    updated_at
  )
  values (
    v_wage.business_entity_id,
    v_wage.teacher_id,
    null,
    null,
    null,
    v_expense_date,
    v_wage.settlement_month,
    'teacher_wage',
    v_description,
    'JPY',
    round(coalesce(v_wage.total_jpy, 0)),
    round(coalesce(v_wage.total_jpy, 0)),
    round(coalesce(v_wage.total_cny, 0) * 100) / 100,
    nullif(v_wage.exchange_rate, 0),
    null,
    'pending',
    true,
    '給与',
    '无需收据',
    null,
    null,
    v_note,
    'school',
    'teacher_wage',
    v_wage.id,
    v_wage.teacher_name,
    null,
    null,
    null,
    null,
    null,
    null,
    v_now,
    v_now
  )
  returning id into v_expense_id;

  return query
  select
    e.id,
    v_wage.id,
    e.status,
    e.expense_category,
    e.source_type,
    e.source_id,
    e.teacher_id,
    e.payee_name_snapshot,
    e.business_entity_id,
    e.year_month,
    e.currency,
    e.amount,
    e.amount_jpy,
    e.amount_cny,
    e.cash_request_status,
    e.created_at
  from public.school_expense_records e
  where e.id = v_expense_id;
end;
$function$;

-- school_void_unsubmitted_teacher_wage_expense_record（2 参数）
CREATE OR REPLACE FUNCTION public.school_void_unsubmitted_teacher_wage_expense_record(p_expense_record_id uuid, p_void_reason text DEFAULT NULL::text)
 RETURNS TABLE(expense_id uuid, wage_lock_id uuid, status text, cancelled_at timestamp with time zone, cancelled_reason text, cash_request_status text, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_expense public.school_expense_records%rowtype;
  v_reason text := nullif(trim(coalesce(p_void_reason, '')), '');
  v_now timestamptz := now();
begin
  perform public.school_require_current_app_admin();

  if p_expense_record_id is null then
    raise exception '请选择要作废的老师工资支出记录。';
  end if;

  select *
    into v_expense
    from public.school_expense_records e
   where e.id = p_expense_record_id
   for update;

  if not found then
    raise exception '支出记录不存在：%。', p_expense_record_id;
  end if;

  if coalesce(v_expense.app_type, '') <> 'school' then
    raise exception '只能作废 School 支出记录。';
  end if;

  if coalesce(v_expense.source_type, '') <> 'teacher_wage' then
    raise exception '本流程只允许作废老师工资支出记录。';
  end if;

  if coalesce(v_expense.status, '') = 'cancelled'
     or v_expense.cancelled_at is not null then
    raise exception '该老师工资支出记录已经作废，不能重复作废。';
  end if;

  if coalesce(v_expense.status, '') <> 'pending' then
    raise exception '只有待支付且未生成 Cash 流水的老师工资支出记录可以作废。当前状态：%。', v_expense.status;
  end if;

  if v_expense.cash_transaction_id is not null then
    raise exception '该支出记录已关联 Cash transaction，不能作废。';
  end if;

  if v_expense.cash_request_status is not null
     and v_expense.cash_request_status <> 'rejected' then
    raise exception '该支出记录已有未终止 Cash 状态，不能在 School 侧直接作废：%。', v_expense.cash_request_status;
  end if;

  if v_expense.cash_request_id is not null
     and coalesce(v_expense.cash_request_status, '') <> 'rejected' then
    raise exception '该支出记录已关联未拒绝的 Cash request，不能在 School 侧直接作废。';
  end if;

  if v_expense.source_id is null then
    raise exception '老师工资支出记录缺少来源工资快照，不能作废。';
  end if;

  update public.school_expense_records e
     set status = 'cancelled',
         cancelled_at = v_now,
         cancelled_reason = v_reason,
         cancelled_by = coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), current_user),
         updated_at = v_now
   where e.id = v_expense.id
   returning * into v_expense;

  return query
  select
    v_expense.id,
    v_expense.source_id,
    v_expense.status,
    v_expense.cancelled_at,
    v_expense.cancelled_reason,
    v_expense.cash_request_status,
    case
      when v_expense.cash_request_status = 'rejected'
        then 'Rejected teacher wage expense record cancelled. Cash request metadata was preserved for audit.'
      else 'Unsubmitted teacher wage expense record cancelled. A new active expense can be generated from the same wage lock.'
    end::text;
end;
$function$;

-- school_create_expense_record（16 参数）
CREATE OR REPLACE FUNCTION public.school_create_expense_record(p_expense_date date, p_business_entity_id uuid, p_account_id uuid, p_expense_category text, p_description text, p_currency text, p_amount numeric, p_exchange_rate numeric DEFAULT NULL::numeric, p_payment_method text DEFAULT NULL::text, p_is_business_expense boolean DEFAULT true, p_tax_category text DEFAULT NULL::text, p_receipt_status text DEFAULT NULL::text, p_reimbursement_status text DEFAULT NULL::text, p_teacher_id uuid DEFAULT NULL::uuid, p_student_id uuid DEFAULT NULL::uuid, p_note text DEFAULT NULL::text)
 RETURNS TABLE(expense_id uuid, account_transaction_id uuid, account_id uuid, new_balance numeric, expense_status text, transaction_type text, year_month text, reimbursement_status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_now timestamptz := now();
  v_actor uuid;
  v_business_entity public.school_business_entities%rowtype;
  v_account public.school_accounts%rowtype;
  v_currency text := upper(trim(coalesce(p_currency, '')));
  v_category text := lower(trim(coalesce(p_expense_category, '')));
  v_description text := nullif(trim(coalesce(p_description, '')), '');
  v_payment_method text := nullif(trim(coalesce(p_payment_method, '')), '');
  v_tax_category text := nullif(trim(coalesce(p_tax_category, '')), '');
  v_receipt_status text := coalesce(nullif(trim(coalesce(p_receipt_status, '')), ''), '待确认');
  v_reimbursement_status text := nullif(trim(coalesce(p_reimbursement_status, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_year_month text;
  v_amount_jpy numeric;
  v_amount_cny numeric;
  v_old_balance numeric;
  v_new_balance numeric;
  v_expense_id uuid;
  v_account_transaction_id uuid;
begin
  v_actor := public.school_require_current_app_admin();

  if not pg_catalog.pg_try_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'school_create_expense_record:actor:' || v_actor::text,
      0
    )
  ) then
    raise exception using
      errcode = '55P03',
      message = 'SCHOOL_CREATE_EXPENSE_ALREADY_IN_PROGRESS';
  end if;

  if p_expense_date is null then
    raise exception '请选择支出日期。';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception '支出金额必须大于 0。';
  end if;

  if v_description is null then
    raise exception '支出内容不能为空。';
  end if;

  if v_category = '' then
    raise exception '支出分类不能为空。';
  end if;

  if v_category = 'teacher_wage' then
    raise exception '老师工资支出请通过老师工资支付流程生成。';
  end if;

  if v_category not in ('classroom', 'other', 'tax_accounting', 'advertising', 'software') then
    raise exception '暂不支持该支出分类。';
  end if;

  if v_currency not in ('JPY', 'CNY') then
    raise exception '暂不支持该支出币种：%。', v_currency;
  end if;

  if p_exchange_rate is not null and p_exchange_rate <= 0 then
    raise exception '汇率必须大于 0。';
  end if;

  if v_receipt_status not in ('有', '无需收据', '待确认') then
    raise exception '收据状态无效。';
  end if;

  perform public.school_assert_new_business_entity_allowed(
    p_business_entity_id,
    '新增支出'
  );

  select *
  into v_business_entity
  from public.school_business_entities
  where id = p_business_entity_id
    and is_active = true;

  if not found then
    raise exception '业务归属无效或已停用。';
  end if;

  if p_teacher_id is not null and not exists (
    select 1
    from public.school_teachers
    where id = p_teacher_id
      and app_type = 'school'
  ) then
    raise exception '老师无效或不可用。';
  end if;

  if p_student_id is not null and not exists (
    select 1
    from public.school_students
    where id = p_student_id
      and app_type = 'school'
  ) then
    raise exception '学生无效或不可用。';
  end if;

  select *
  into v_account
  from public.school_accounts
  where id = p_account_id
    and app_type = 'school'
  for update;

  if not found then
    raise exception '付款账户无效。';
  end if;

  if v_account.is_active is not true then
    raise exception '付款账户已停用。';
  end if;

  if v_account.business_entity_id is distinct from p_business_entity_id then
    raise exception '付款账户与业务归属不一致。';
  end if;

  if v_account.currency is distinct from v_currency then
    raise exception '付款账户币种必须与支出币种一致。';
  end if;

  if v_reimbursement_status is null then
    v_reimbursement_status := case
      when coalesce(v_account.is_company_account, false) then 'not_required'
      else 'pending'
    end;
  end if;

  if v_reimbursement_status not in ('not_required', 'pending') then
    raise exception '报销状态无效。';
  end if;

  if v_currency = 'JPY' then
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

  v_year_month := to_char(p_expense_date, 'YYYY-MM');
  v_old_balance := coalesce(v_account.current_balance, 0);
  v_new_balance := v_old_balance - p_amount;

  insert into public.school_expense_records (
    business_entity_id,
    teacher_id,
    student_id,
    salary_payment_id,
    account_id,
    expense_date,
    year_month,
    expense_category,
    description,
    currency,
    amount,
    amount_jpy,
    amount_cny,
    exchange_rate,
    payment_method,
    status,
    is_business_expense,
    tax_category,
    receipt_status,
    reimbursement_status,
    reimbursement_note,
    note,
    app_type,
    source_type,
    source_id,
    cash_creation_event_id,
    created_by_user_id,
    created_at,
    updated_at
  )
  values (
    p_business_entity_id,
    p_teacher_id,
    p_student_id,
    null,
    v_account.id,
    p_expense_date,
    v_year_month,
    v_category,
    v_description,
    v_currency,
    p_amount,
    v_amount_jpy,
    v_amount_cny,
    p_exchange_rate,
    v_payment_method,
    'paid',
    coalesce(p_is_business_expense, true),
    v_tax_category,
    v_receipt_status,
    v_reimbursement_status,
    null,
    v_note,
    'school',
    'manual_school',
    null,
    null,
    v_actor,
    v_now,
    v_now
  )
  returning id into v_expense_id;

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
    p_expense_date,
    v_year_month,
    'expense_adjust',
    'school_expense_records',
    v_expense_id,
    v_account.currency,
    -p_amount,
    v_new_balance,
    '支出出账：' || v_description,
    v_note,
    'school',
    v_now,
    v_now
  )
  returning id into v_account_transaction_id;

  return query
  select
    v_expense_id,
    v_account_transaction_id,
    v_account.id,
    v_new_balance,
    'paid'::text,
    'expense_adjust'::text,
    v_year_month,
    v_reimbursement_status;
end;
$function$;

-- school_update_expense_record（15 参数）
CREATE OR REPLACE FUNCTION public.school_update_expense_record(p_expense_id uuid, p_expected_updated_at timestamp with time zone, p_expense_date date, p_business_entity_id uuid, p_account_id uuid, p_expense_category text, p_description text, p_currency text, p_amount numeric, p_exchange_rate numeric DEFAULT NULL::numeric, p_payment_method text DEFAULT NULL::text, p_tax_category text DEFAULT NULL::text, p_receipt_status text DEFAULT NULL::text, p_reimbursement_status text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS TABLE(expense_id uuid, account_transaction_id uuid, account_id uuid, new_balance numeric, expense_status text, transaction_type text, year_month text, reimbursement_status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_now timestamptz := now();
  v_expense public.school_expense_records%rowtype;
  v_business_entity public.school_business_entities%rowtype;
  v_account public.school_accounts%rowtype;
  v_original_transaction public.school_account_transactions%rowtype;
  v_currency text := upper(trim(coalesce(p_currency, '')));
  v_category text := lower(trim(coalesce(p_expense_category, '')));
  v_description text := nullif(trim(coalesce(p_description, '')), '');
  v_payment_method text := nullif(trim(coalesce(p_payment_method, '')), '');
  v_tax_category text := nullif(trim(coalesce(p_tax_category, '')), '');
  v_receipt_status text := coalesce(nullif(trim(coalesce(p_receipt_status, '')), ''), '待确认');
  v_reimbursement_status text := nullif(trim(coalesce(p_reimbursement_status, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_year_month text;
  v_amount_jpy numeric;
  v_amount_cny numeric;
  v_amount_delta numeric;
  v_new_balance numeric;
  v_original_transaction_count integer := 0;
  v_existing_reversal_count integer := 0;
  v_payment_request_count integer := 0;
  v_reimbursement_item_count integer := 0;
begin
  perform public.school_require_current_app_admin();

  if p_expense_id is null then
    raise exception '请选择要编辑的支出记录。';
  end if;

  if p_expense_date is null then
    raise exception '请选择支出日期。';
  end if;

  if p_business_entity_id is null then
    raise exception '请选择业务归属。';
  end if;

  if p_account_id is null then
    raise exception '请选择付款账户。';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception '支出金额必须大于 0。';
  end if;

  if v_description is null then
    raise exception '支出内容不能为空。';
  end if;

  if v_category = '' then
    raise exception '支出分类不能为空。';
  end if;

  if v_category = 'teacher_wage' then
    raise exception '老师工资支出请通过老师工资支付流程维护。';
  end if;

  if v_category not in ('classroom', 'other', 'tax_accounting', 'advertising', 'software') then
    raise exception '暂不支持该支出分类。';
  end if;

  if v_currency not in ('JPY', 'CNY') then
    raise exception '暂不支持该支出币种：%。', v_currency;
  end if;

  if p_exchange_rate is not null and p_exchange_rate <= 0 then
    raise exception '汇率必须大于 0。';
  end if;

  if v_payment_method is null then
    raise exception '请选择支付方式。';
  end if;

  if v_payment_method not in ('cash', 'bank_transfer', 'card', 'alipay') then
    raise exception '支付方式无效。';
  end if;

  if v_receipt_status not in ('有', '无需收据', '待确认') then
    raise exception '收据状态无效。';
  end if;

  if v_reimbursement_status is null then
    raise exception '请选择报销状态。';
  end if;

  if v_reimbursement_status not in ('not_required', 'pending') then
    raise exception '报销状态无效。';
  end if;

  select *
  into v_expense
  from public.school_expense_records e
  where e.id = p_expense_id
    and coalesce(e.app_type, '') = 'school'
  for update;

  if not found then
    raise exception '支出记录不存在。';
  end if;

  if p_expected_updated_at is null then
    raise exception using
      errcode = '22023',
      message = 'P0_EXPENSE_UPDATE_EXPECTED_UPDATED_AT_REQUIRED';
  end if;

  if v_expense.updated_at is distinct from p_expected_updated_at then
    raise exception using
      errcode = '40001',
      message = 'P0_EXPENSE_UPDATE_STALE_VERSION';
  end if;

  if p_business_entity_id is distinct from v_expense.business_entity_id then
    perform public.school_assert_new_business_entity_allowed(
      p_business_entity_id,
      '更新支出业务归属'
    );
  end if;

  if v_expense.status = 'reversed'
    or v_expense.reversed_at is not null
    or v_expense.reversal_account_transaction_id is not null then
    raise exception '已撤销支出不能编辑。';
  end if;

  if v_expense.cash_transaction_id is not null
    or v_expense.cash_request_status in ('approved', 'synced') then
    raise exception 'expense record has been synced to Cash and cannot be edited or deleted directly';
  end if;

  if v_expense.cash_request_status in ('pending', 'pending_cash_request') then
    raise exception 'expense record has a pending Cash request and core fields cannot be edited directly';
  end if;

  if v_expense.status is distinct from 'paid' then
    raise exception '只能编辑已支付支出。';
  end if;

  if v_expense.expense_category = 'teacher_wage'
    or v_expense.salary_payment_id is not null then
    raise exception '老师工资或工资支付来源支出不能通过普通支出编辑。';
  end if;

  if v_expense.reimbursement_status = 'paid' then
    raise exception '已报销支出不能编辑。';
  end if;

  if p_account_id is distinct from v_expense.account_id then
    raise exception '已出账支出暂不支持更换付款账户。请撤销后重新新增。';
  end if;

  select count(*)::integer
  into v_payment_request_count
  from public.school_payment_requests pr
  where pr.paid_expense_id = v_expense.id;

  if v_payment_request_count > 0 then
    raise exception '来源支付请求生成的支出不能通过普通支出编辑。';
  end if;

  select count(*)::integer
  into v_reimbursement_item_count
  from public.school_reimbursement_items items
  where items.expense_id = v_expense.id
    and coalesce(items.app_type, '') = 'school';

  if v_reimbursement_item_count > 0 then
    raise exception '已进入报销链路的支出不能编辑。';
  end if;

  select count(*)::integer
  into v_existing_reversal_count
  from public.school_account_transactions t
  where t.related_table = 'school_expense_records'
    and t.related_id = v_expense.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'expense_reversal';

  if v_existing_reversal_count > 0 then
    raise exception '已存在支出撤销流水，不能编辑。';
  end if;

  select count(*)::integer
  into v_original_transaction_count
  from public.school_account_transactions t
  where t.related_table = 'school_expense_records'
    and t.related_id = v_expense.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'expense_adjust';

  if v_original_transaction_count <> 1 then
    raise exception '支出原始账户流水不存在或不唯一，不能编辑。';
  end if;

  select *
  into v_original_transaction
  from public.school_account_transactions t
  where t.related_table = 'school_expense_records'
    and t.related_id = v_expense.id
    and coalesce(t.app_type, '') = 'school'
    and t.transaction_type = 'expense_adjust'
  for update;

  if v_original_transaction.amount is distinct from -v_expense.amount
    or v_original_transaction.account_id is distinct from v_expense.account_id
    or v_original_transaction.currency is distinct from v_expense.currency then
    raise exception '支出原始账户流水与支出记录不一致，不能编辑。';
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
    raise exception '该支出之后已有账户流水，不能直接编辑会影响余额的字段。请使用撤销后重新新增。';
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
  into v_account
  from public.school_accounts
  where id = p_account_id
    and app_type = 'school'
  for update;

  if not found then
    raise exception '付款账户无效。';
  end if;

  if v_account.is_active is not true then
    raise exception '付款账户已停用。';
  end if;

  if v_account.business_entity_id is distinct from p_business_entity_id then
    raise exception '付款账户与业务归属不一致。';
  end if;

  if v_account.currency is distinct from v_currency then
    raise exception '付款账户币种必须与支出币种一致。';
  end if;

  if v_currency = 'JPY' then
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

  v_year_month := to_char(p_expense_date, 'YYYY-MM');
  v_amount_delta := p_amount - v_expense.amount;
  v_new_balance := coalesce(v_account.current_balance, 0) - v_amount_delta;

  update public.school_accounts a
  set
    current_balance = v_new_balance,
    updated_at = v_now
  where a.id = v_account.id;

  update public.school_account_transactions t
  set
    business_entity_id = p_business_entity_id,
    transaction_date = p_expense_date,
    year_month = v_year_month,
    currency = v_account.currency,
    amount = -p_amount,
    balance_after = v_new_balance,
    description = '支出出账：' || v_description,
    note = v_note,
    updated_at = v_now
  where t.id = v_original_transaction.id;

  update public.school_expense_records e
  set
    business_entity_id = p_business_entity_id,
    account_id = p_account_id,
    expense_date = p_expense_date,
    year_month = v_year_month,
    expense_category = v_category,
    description = v_description,
    currency = v_account.currency,
    amount = p_amount,
    amount_jpy = v_amount_jpy,
    amount_cny = v_amount_cny,
    exchange_rate = p_exchange_rate,
    payment_method = v_payment_method,
    tax_category = v_tax_category,
    receipt_status = v_receipt_status,
    reimbursement_status = v_reimbursement_status,
    note = v_note,
    updated_at = v_now
  where e.id = v_expense.id;

  return query
  select
    v_expense.id,
    v_original_transaction.id,
    v_account.id,
    v_new_balance,
    'paid'::text,
    'expense_adjust'::text,
    v_year_month,
    v_reimbursement_status;
end;
$function$;

-- school_create_pending_cash_expense_record_v1（15 参数）
CREATE OR REPLACE FUNCTION public.school_create_pending_cash_expense_record_v1(p_client_request_id uuid, p_expense_date date, p_business_entity_id uuid, p_expense_category text, p_description text, p_currency text, p_amount numeric, p_reimbursement_status text, p_exchange_rate numeric DEFAULT NULL::numeric, p_is_business_expense boolean DEFAULT true, p_tax_category text DEFAULT NULL::text, p_receipt_status text DEFAULT NULL::text, p_teacher_id uuid DEFAULT NULL::uuid, p_student_id uuid DEFAULT NULL::uuid, p_note text DEFAULT NULL::text)
 RETURNS TABLE(expense_record jsonb, expense_id uuid, expense_status text, cash_request_status text, client_request_id uuid, created_by_user_id uuid, creation_channel text, idempotent boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_now timestamptz := now();
  v_actor uuid;
  v_expense public.school_expense_records%rowtype;
  v_currency text := upper(trim(coalesce(p_currency,'')));
  v_category text := lower(trim(coalesce(p_expense_category,'')));
  v_description text := nullif(trim(coalesce(p_description,'')),'');
  v_tax_category text := nullif(trim(coalesce(p_tax_category,'')),'');
  v_receipt_status text := coalesce(nullif(trim(coalesce(p_receipt_status,'')),''),'待确认');
  v_reimbursement_status text := nullif(trim(coalesce(p_reimbursement_status,'')),'');
  v_note text := nullif(trim(coalesce(p_note,'')),'');
  v_is_business_expense boolean := coalesce(p_is_business_expense,true);
  v_year_month text;
  v_amount_jpy numeric;
  v_amount_cny numeric;
begin
  v_actor := public.school_require_current_app_admin();

  if p_client_request_id is null then
    raise exception using
      errcode='22023',
      message='P0_PENDING_CASH_EXPENSE_CLIENT_REQUEST_ID_REQUIRED';
  end if;
  if p_expense_date is null then
    raise exception '请选择支出日期。';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception '支出金额必须大于 0。';
  end if;
  if v_description is null then
    raise exception '支出内容不能为空。';
  end if;
  if v_category='teacher_wage' then
    raise exception '老师工资支出请通过老师工资支付流程生成。';
  end if;
  if v_category not in ('classroom','other','tax_accounting','advertising','software') then
    raise exception '暂不支持该支出分类。';
  end if;
  if v_currency not in ('JPY','CNY') then
    raise exception '暂不支持该支出币种：%。',v_currency;
  end if;
  if p_exchange_rate is not null and p_exchange_rate <= 0 then
    raise exception '汇率必须大于 0。';
  end if;
  if v_receipt_status not in ('有','无需收据','待确认') then
    raise exception '收据状态无效。';
  end if;
  if v_reimbursement_status not in ('not_required','pending') then
    raise exception '报销状态无效。';
  end if;

  if v_currency='JPY' then
    v_amount_jpy := p_amount;
    v_amount_cny := case when p_exchange_rate is null then null else p_amount/p_exchange_rate end;
  else
    v_amount_cny := p_amount;
    v_amount_jpy := case when p_exchange_rate is null then null else p_amount*p_exchange_rate end;
  end if;
  v_year_month := to_char(p_expense_date,'YYYY-MM');

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'school_create_pending_cash_expense_record_v1:'||p_client_request_id::text,
      0
    )
  );

  select e.*
    into v_expense
    from public.school_expense_records e
   where e.cash_creation_event_id=p_client_request_id
   for update;

  if found then
    if v_expense.app_type is distinct from 'school'
       or v_expense.source_type is distinct from 'manual_cash'
       or v_expense.source_id is not null
       or v_expense.created_by_user_id is null
       or v_expense.expense_date is distinct from p_expense_date
       or v_expense.year_month is distinct from v_year_month
       or v_expense.business_entity_id is distinct from p_business_entity_id
       or v_expense.expense_category is distinct from v_category
       or v_expense.description is distinct from v_description
       or v_expense.currency is distinct from v_currency
       or v_expense.amount is distinct from p_amount
       or v_expense.amount_jpy is distinct from v_amount_jpy
       or v_expense.amount_cny is distinct from v_amount_cny
       or v_expense.exchange_rate is distinct from p_exchange_rate
       or v_expense.account_id is not null
       or v_expense.payment_method is not null
       or v_expense.is_business_expense is distinct from v_is_business_expense
       or v_expense.tax_category is distinct from v_tax_category
       or v_expense.receipt_status is distinct from v_receipt_status
       or v_expense.reimbursement_status is distinct from v_reimbursement_status
       or v_expense.teacher_id is distinct from p_teacher_id
       or v_expense.student_id is distinct from p_student_id
       or v_expense.note is distinct from v_note then
      raise exception using
        errcode='23505',
        message='P0_PENDING_CASH_EXPENSE_IDENTITY_PAYLOAD_CONFLICT';
    end if;

    return query select
      to_jsonb(v_expense),v_expense.id,v_expense.status,
      v_expense.cash_request_status,v_expense.cash_creation_event_id,
      v_expense.created_by_user_id,v_expense.source_type,true;
    return;
  end if;

  perform public.school_assert_new_business_entity_allowed(
    p_business_entity_id,
    '新增Cash待审批支出'
  );

  if not exists (
    select 1
    from public.school_business_entities b
    where b.id=p_business_entity_id and b.is_active=true
  ) then
    raise exception '业务归属无效或已停用。';
  end if;
  if p_teacher_id is not null and not exists (
    select 1 from public.school_teachers t
    where t.id=p_teacher_id and t.app_type='school'
  ) then
    raise exception '老师无效或不可用。';
  end if;
  if p_student_id is not null and not exists (
    select 1 from public.school_students s
    where s.id=p_student_id and s.app_type='school'
  ) then
    raise exception '学生无效或不可用。';
  end if;

  insert into public.school_expense_records (
    business_entity_id,teacher_id,student_id,salary_payment_id,account_id,
    expense_date,year_month,expense_category,description,currency,amount,
    amount_jpy,amount_cny,exchange_rate,payment_method,status,
    is_business_expense,tax_category,receipt_status,reimbursement_status,
    reimbursement_note,note,app_type,source_type,source_id,
    cash_creation_event_id,created_by_user_id,
    cash_request_id,cash_request_status,cash_transaction_id,cash_requested_at,
    cash_synced_at,cash_error_message,cash_request_event_id,
    cash_request_attempt_no,cash_payment_amount,cash_payment_currency,
    cash_payment_note,created_at,updated_at
  ) values (
    p_business_entity_id,p_teacher_id,p_student_id,null,null,
    p_expense_date,v_year_month,v_category,v_description,v_currency,p_amount,
    v_amount_jpy,v_amount_cny,p_exchange_rate,null,'pending',
    v_is_business_expense,v_tax_category,v_receipt_status,v_reimbursement_status,
    null,v_note,'school','manual_cash',null,
    p_client_request_id,v_actor,
    null,null,null,null,
    null,null,null,
    0,null,null,
    null,v_now,v_now
  )
  returning * into v_expense;

  return query select
    to_jsonb(v_expense),v_expense.id,v_expense.status,
    v_expense.cash_request_status,v_expense.cash_creation_event_id,
    v_expense.created_by_user_id,v_expense.source_type,false;
end;
$function$;

-- ── 还原 3 条 COMMENT（签名动态解析）──
DO $cmt$
DECLARE r record; v_sig text; v_n int := 0;
BEGIN
  FOR r IN SELECT * FROM opwr_target WHERE post_cmt IS DISTINCT FROM pre_cmt LOOP
    SELECT 'public.'||quote_ident(p.proname)||'('||pg_get_function_identity_arguments(p.oid)||')'
      INTO v_sig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=r.proname AND p.pronargs=r.nargs;
    EXECUTE format('COMMENT ON FUNCTION %s IS %L', v_sig, r.pre_cmt);
    v_n := v_n + 1;
  END LOOP;
  IF v_n <> 3 THEN RAISE EXCEPTION 'OPWR_COMMENT_COUNT: 还原了 % 条，应为 3', v_n; END IF;
END
$cmt$;

-- ── 删除新守卫。删之前确认没有别的函数还在引用它 ──
DO $drop$
DECLARE r record; v_def text; v_left int := 0;
BEGIN
  -- ⚠️ 逐个查，不写成带 pg_get_functiondef 的聚合查询：规划器会把它提前到
  --    pg_proc 全表扫描上求值，碰到聚合函数就报错。deploy 脚本里已实测过。
  FOR r IN SELECT p.oid, p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='public' AND p.prokind='f' AND p.proname <> 'school_require_current_app_operator' LOOP
    BEGIN
      v_def := pg_get_functiondef(r.oid);
    EXCEPTION WHEN OTHERS THEN CONTINUE;  -- 取不到定义的跳过，不影响判断
    END;
    IF position('school_require_current_app_operator' in v_def) > 0 THEN
      v_left := v_left + 1;
      RAISE WARNING 'OPWR_STILL_REFERENCED: % 仍引用新守卫', r.proname;
    END IF;
  END LOOP;
  IF v_left > 0 THEN
    RAISE EXCEPTION 'OPWR_GUARD_IN_USE: 还有 % 个函数引用 school_require_current_app_operator，'
      '删除会留下断链。请先处理它们', v_left;
  END IF;
END
$drop$;

DROP FUNCTION public.school_require_current_app_operator();

DO $post$
DECLARE r record; v_md5 text; v_acl text; v_cmt text; v_n int;
BEGIN
  FOR r IN SELECT * FROM opwr_target ORDER BY proname, nargs LOOP
    SELECT md5(pg_get_functiondef(p.oid)), coalesce(p.proacl::text,''), obj_description(p.oid,'pg_proc')
      INTO v_md5, v_acl, v_cmt FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname=r.proname AND p.pronargs=r.nargs;
    IF v_md5 <> r.pre_md5 THEN
      RAISE EXCEPTION 'OPWR_POST_MD5: %(%) 得 %  期望 %', r.proname, r.nargs, v_md5, r.pre_md5; END IF;
    IF v_acl <> r.acl THEN
      RAISE EXCEPTION 'OPWR_POST_ACL: %(%) 得 %', r.proname, r.nargs, v_acl; END IF;
    IF v_cmt IS DISTINCT FROM r.pre_cmt THEN
      RAISE EXCEPTION 'OPWR_POST_COMMENT: %(%) 注释未还原', r.proname, r.nargs; END IF;
  END LOOP;
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='school_require_current_app_operator';
  IF v_n <> 0 THEN RAISE EXCEPTION 'OPWR_POST_GUARD_REMAINS: 新守卫仍存在'; END IF;
  RAISE NOTICE 'OPWR: 已逐字节还原 8 个函数与 3 条注释，新守卫已删除';
END
$post$;

COMMIT;
