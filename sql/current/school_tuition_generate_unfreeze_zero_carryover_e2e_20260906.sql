-- 学费生成 Gate 解冻前的定向 E2E：零结转行为实证
-- 2026-09-06。ROLLBACK-ONLY，脚本末尾无条件 rollback，不提供 commit 分支。
--
-- 要回答的头号问题：9-07 之后若在「8 月月度结算尚未锁定」时生成 9 月账单，
-- 究竟是 (a) 静默按 carryover=0 生成，还是 (b) 被 Rule A 之类的 guard 拦住。
-- 生产实测 2026-09-06：2026-08 settlement 为 0 行，而 6 名学生的账单停在 8 月，
-- 所以这个场景在 9-07 当天是真实可达的。
--
-- 设计要点：
--  * 只调 core（school_generate_student_tuition_bill_atomic_core）。core 层不含
--    gate 检查与 admin 检查（两者都在五参数 wrapper 上），因此本脚本
--    **完全不需要改动 student_tuition_generate gate**。
--  * fixture 用 2020 年份 + 独立 UUID 前缀 c0d00000，与 P0-C 的 c0c00000 隔离。
--  * 每个用例用 exception 捕获，一次运行拿到全部结果，不让首个失败中断后续。
--
-- 用法：psql ... -v e2e_confirm=1 -f 本文件
\set ON_ERROR_STOP on
\pset pager off

\if :{?e2e_confirm}
\else
  \echo 'TUITION_UNFREEZE_E2E_CONFIRM_REQUIRED'
  \quit
\endif

begin;
set local lock_timeout='10s';
set local statement_timeout='300s';

create temporary table tuition_unfreeze_e2e_result(
  seq integer generated always as identity,
  case_name text not null,
  outcome text not null,
  detail text
) on commit drop;

do $e2e$
declare
  v_marker    constant text:='claude-test tuition-generate-unfreeze-e2e-20260906';
  v_entity    constant uuid:='c0d00000-0000-4000-8000-00000000e001';
  v_subject   constant uuid:='c0d00000-0000-4000-8000-00000000d001';
  v_teacher   constant uuid:='c0d00000-0000-4000-8000-000000007001';
  -- 学生 A：有上月 locked settlement，carryover 非 0（对照组）
  v_student_a constant uuid:='c0d00000-0000-4000-8000-00000000a001';
  v_settle_a  constant uuid:='c0d00000-0000-4000-8000-00000000b001';
  -- 学生 B：无上月 settlement（零结转测试组）
  v_student_b constant uuid:='c0d00000-0000-4000-8000-00000000a002';
  v_lessons_a constant uuid[]:=array['c0d00000-0000-4000-8000-000000001101'::uuid,
                                     'c0d00000-0000-4000-8000-000000001102'::uuid];
  v_lessons_b constant uuid[]:=array['c0d00000-0000-4000-8000-000000001201'::uuid,
                                     'c0d00000-0000-4000-8000-000000001202'::uuid];
  v_rate      constant numeric:=0.05;
  v_carry_a   constant numeric:=500.00;   -- 学生 A 的上月结转，必须非 0 才能区分两种情形
  v_now       timestamptz:=clock_timestamp();
  v_snap_a record; v_snap_b record; v_gen record;
  v_carry numeric; v_prev_settlement uuid; v_errcode text; v_errmsg text;
begin
  -- ---------- 残留预检：本脚本 rollback-only，但仍拒绝在有同名残留时运行 ----------
  if exists(select 1 from public.school_business_entities where id=v_entity or code='claude-test-unfreeze-e2e')
     or exists(select 1 from public.school_students where id in (v_student_a,v_student_b)) then
    raise exception 'TUITION_UNFREEZE_E2E_FIXTURE_RESIDUE';
  end if;

  -- ---------- fixture ----------
  insert into public.school_business_entities(id,code,name,entity_type,default_currency,is_active,note)
  values(v_entity,'claude-test-unfreeze-e2e','claude-test unfreeze E2E entity','company','JPY',true,v_marker);

  insert into public.school_subjects(id,name,category,is_active,note,primary_category)
  values(v_subject,'claude-test unfreeze E2E subject','claude-test',true,v_marker,'班课');

  insert into public.school_teachers(id,teacher_code,name,display_name,default_subject_id,
    default_business_entity_id,status,note,app_type)
  values(v_teacher,'claude-test-unfreeze-teacher','claude-test unfreeze teacher',
    'claude-test unfreeze teacher',v_subject,v_entity,'active',v_marker,'school');

  insert into public.school_students(id,student_code,name,display_name,business_entity_id,status,
    app_type,preset_exchange_rate,previous_balance_cny,note)
  values
    (v_student_a,'claude-test-unfreeze-a','claude-test unfreeze A','claude-test unfreeze A',
     v_entity,'active','school',v_rate,0,v_marker),
    (v_student_b,'claude-test-unfreeze-b','claude-test unfreeze B','claude-test unfreeze B',
     v_entity,'active','school',v_rate,0,v_marker);

  -- 两名学生各 2 节 2020-08 计费课
  insert into public.school_lesson_records(
    id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,
    business_entity_id,start_time,end_time,duration_hours,lesson_content,status,
    is_billable,note,app_type,unit_price,lesson_fee,lesson_count,
    lesson_delivery_mode,lesson_venue,billing_month,billing_week_start_date,
    scheduled_lesson_date,student_settlement_month,billing_month_source,billing_month_decided_at
  ) select lesson_id,'planned',lesson_date,'2020-08',stud,v_teacher,v_subject,
    v_entity,'15:00','17:00',2,v_marker,'planned',true,v_marker,'school',
    10000,1,2,'online',v_marker,'2020-08',date_trunc('week',lesson_date::timestamp)::date,
    lesson_date,'2020-08','explicit_billing_week_at_create',statement_timestamp()
  from (values
    (v_lessons_a[1],date '2020-08-12',v_student_a),(v_lessons_a[2],date '2020-08-19',v_student_a),
    (v_lessons_b[1],date '2020-08-12',v_student_b),(v_lessons_b[2],date '2020-08-19',v_student_b)
  ) x(lesson_id,lesson_date,stud);

  -- 只有学生 A 有 2020-07 locked settlement，且 carryover 非 0
  insert into public.school_student_monthly_settlements(
    id,student_id,year_month,business_entity_id,preset_exchange_rate,
    planned_lesson_fee_jpy,planned_lesson_fee_cny,actual_lesson_fee_jpy,
    actual_lesson_fee_cny,previous_balance_cny,received_jpy,received_cny,
    received_equivalent_cny,system_difference_cny,adjustment_amount_cny,
    carryover_amount_cny,settlement_status,locked_at,note,
    duration_overage_minutes,duration_overage_fee_jpy,duration_overage_fee_cny,
    duration_overage_actual_count,duration_overage_policy_version,duration_overage_source
  ) values(v_settle_a,v_student_a,'2020-07',v_entity,v_rate,0,0,0,0,0,0,0,0,0,0,
    v_carry_a,'locked',v_now,v_marker,0,0,0,0,
    'student_duration_overage_v1','monthly_settlement_lock');

  -- ---------- 用例 0：snapshot 层面确认两名学生的 previous_settlement_id ----------
  select * into strict v_snap_a
  from public.school_build_student_tuition_generation_snapshot(v_student_a,'2020-08',v_rate);
  select * into strict v_snap_b
  from public.school_build_student_tuition_generation_snapshot(v_student_b,'2020-08',v_rate);

  insert into tuition_unfreeze_e2e_result(case_name,outcome,detail) values(
    '0a. snapshot A（有 locked settlement）',
    case when v_snap_a.previous_settlement_id=v_settle_a then 'AS_EXPECTED' else 'UNEXPECTED' end,
    format('previous_settlement_id=%s candidate_count=%s',
           v_snap_a.previous_settlement_id,v_snap_a.candidate_count));

  insert into tuition_unfreeze_e2e_result(case_name,outcome,detail) values(
    '0b. snapshot B（无 settlement）',
    case when v_snap_b.previous_settlement_id is null then 'AS_EXPECTED' else 'UNEXPECTED' end,
    format('previous_settlement_id=%s candidate_count=%s',
           v_snap_b.previous_settlement_id,v_snap_b.candidate_count));

  -- ---------- 用例 1【头号问题】无上月 locked settlement 时生成 ----------
  begin
    select * into strict v_gen from public.school_generate_student_tuition_bill_atomic_core(
      v_student_b,'2020-08',v_rate,v_snap_b.generation_manifest_sha256,v_marker);
    select b.previous_carryover_cny,b.previous_settlement_id into v_carry,v_prev_settlement
    from public.school_student_tuition_bills b where b.id=v_gen.tuition_bill_id;
    insert into tuition_unfreeze_e2e_result(case_name,outcome,detail) values(
      '1. 无上月结算时生成 → 是否静默零结转',
      'GENERATED_SILENTLY',
      format('返回 %s 列已具名；previous_carryover_cny=%s；previous_settlement_id=%s；'
             ||'billing_amount_cny=%s；idempotent=%s。'
             ||'【若 carryover=0 且 settlement 为 NULL，则误操作窗口真实存在】',
             20,v_carry,coalesce(v_prev_settlement::text,'NULL'),
             v_gen.billing_amount_cny,v_gen.idempotent));
  exception when others then
    get stacked diagnostics v_errcode=returned_sqlstate,v_errmsg=message_text;
    insert into tuition_unfreeze_e2e_result(case_name,outcome,detail) values(
      '1. 无上月结算时生成 → 是否静默零结转',
      'BLOCKED',
      format('SQLSTATE=%s message=%s。【被拦住＝不存在误操作窗口】',v_errcode,v_errmsg));
  end;

  -- ---------- 用例 2：对照组，有 locked settlement 时 carryover 应等于 500 ----------
  begin
    select * into strict v_gen from public.school_generate_student_tuition_bill_atomic_core(
      v_student_a,'2020-08',v_rate,v_snap_a.generation_manifest_sha256,v_marker);
    select b.previous_carryover_cny,b.previous_settlement_id into v_carry,v_prev_settlement
    from public.school_student_tuition_bills b where b.id=v_gen.tuition_bill_id;
    insert into tuition_unfreeze_e2e_result(case_name,outcome,detail) values(
      '2. 有上月结算时生成（对照）',
      case when v_carry=v_carry_a and v_prev_settlement=v_settle_a
           then 'AS_EXPECTED' else 'UNEXPECTED' end,
      format('previous_carryover_cny=%s（期望 %s）；previous_settlement_id=%s（期望 %s）',
             v_carry,v_carry_a,v_prev_settlement,v_settle_a));
  exception when others then
    get stacked diagnostics v_errcode=returned_sqlstate,v_errmsg=message_text;
    insert into tuition_unfreeze_e2e_result(case_name,outcome,detail) values(
      '2. 有上月结算时生成（对照）','ERROR',
      format('SQLSTATE=%s message=%s',v_errcode,v_errmsg));
  end;

  -- ---------- 用例 3：42809 回归 + duplicate 幂等分支 ----------
  begin
    select * into strict v_gen from public.school_generate_student_tuition_bill_atomic_core(
      v_student_a,'2020-08',v_rate,v_snap_a.generation_manifest_sha256,v_marker);
    insert into tuition_unfreeze_e2e_result(case_name,outcome,detail) values(
      '3. 重复调用 → duplicate 幂等分支',
      case when v_gen.idempotent then 'AS_EXPECTED' else 'UNEXPECTED' end,
      format('idempotent=%s message=%s',v_gen.idempotent,v_gen.message));
  exception when others then
    get stacked diagnostics v_errcode=returned_sqlstate,v_errmsg=message_text;
    insert into tuition_unfreeze_e2e_result(case_name,outcome,detail) values(
      '3. 重复调用 → duplicate 幂等分支','ERROR',
      format('SQLSTATE=%s message=%s。【若为 42809 则首次生成修复已回退】',v_errcode,v_errmsg));
  end;

  -- ---------- 用例 4：被消费的 settlement 不可 unlock（反向 guard） ----------
  begin
    perform public.school_unlock_student_monthly_settlement(v_settle_a,v_marker);
    insert into tuition_unfreeze_e2e_result(case_name,outcome,detail) values(
      '4. 已被账单消费的 settlement → unlock',
      'NOT_BLOCKED',
      '【严重：反向 guard 失效，unlock 竟然成功】');
  exception when others then
    get stacked diagnostics v_errcode=returned_sqlstate,v_errmsg=message_text;
    insert into tuition_unfreeze_e2e_result(case_name,outcome,detail) values(
      '4. 已被账单消费的 settlement → unlock',
      'BLOCKED_AS_EXPECTED',
      format('SQLSTATE=%s message=%s',v_errcode,v_errmsg));
  end;

  -- ---------- 用例 5【第二关键】零结转生成之后，还能不能补做上月结算 ----------
  -- 学生 B 已在用例 1 中以零结转生成（若用例 1 为 BLOCKED，本用例结果仅供参考）
  begin
    insert into public.school_student_monthly_settlements(
      id,student_id,year_month,business_entity_id,preset_exchange_rate,
      planned_lesson_fee_jpy,planned_lesson_fee_cny,actual_lesson_fee_jpy,
      actual_lesson_fee_cny,previous_balance_cny,received_jpy,received_cny,
      received_equivalent_cny,system_difference_cny,adjustment_amount_cny,
      carryover_amount_cny,settlement_status,locked_at,note,
      duration_overage_minutes,duration_overage_fee_jpy,duration_overage_fee_cny,
      duration_overage_actual_count,duration_overage_policy_version,duration_overage_source
    ) values('c0d00000-0000-4000-8000-00000000b002',v_student_b,'2020-07',v_entity,v_rate,
      0,0,0,0,0,0,0,0,0,0,777.00,'locked',v_now,v_marker,0,0,0,0,
      'student_duration_overage_v1','monthly_settlement_lock');
    insert into tuition_unfreeze_e2e_result(case_name,outcome,detail) values(
      '5. 零结转生成后补做上月结算',
      'INSERT_ALLOWED',
      '结算行可写入，但已生成的账单 carryover 仍为 0——结转不会自动回填，需 void/reissue');
  exception when others then
    get stacked diagnostics v_errcode=returned_sqlstate,v_errmsg=message_text;
    insert into tuition_unfreeze_e2e_result(case_name,outcome,detail) values(
      '5. 零结转生成后补做上月结算',
      'BLOCKED',
      format('SQLSTATE=%s message=%s',v_errcode,v_errmsg));
  end;
end;
$e2e$;

select seq,case_name,outcome,detail from tuition_unfreeze_e2e_result order by seq;

-- 无条件回滚。本脚本不提供 commit 分支，fixture 与全部写入均不落盘。
rollback;
\echo 'TUITION_UNFREEZE_E2E_ROLLED_BACK'
