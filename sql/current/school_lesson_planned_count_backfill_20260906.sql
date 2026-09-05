-- ⚠️⚠️ 本脚本已作废，不可执行。2026-09-06 交叉审核在排练前拦下。
--
-- 不可行的原因（两道，缺一都能挡住）：
--   1. school_update_lesson_record_guarded_with_venue 显式拒绝已有 actual 关联的
--      planned 课时：'该预定课时已有 actual 关联，不能编辑。'
--      见 sql/current/school_update_lesson_record_guarded_rpc.sql:291-299
--   2. 表级触发器 school_tuition_p0b1_lesson_financial_authority 的 v_relation_frozen
--      命中同一条件抛 LESSON_FINANCIAL_FACT_IMMUTABLE，**绕过 RPC 直接 UPDATE 同样不行**
--      见 sql/current/school_tuition_p0b1_lesson_authority_rpc_only_20260803.sql:251-253
--   本脚本的两条目标课时都已有 completed actual 关联，因此排练都进不去。
--   且 actual 侧全部 writer 均为 create_*，无 delete / unlink 入口，
--   「解绑 actual 再改 planned」这条路同样不存在。
--
-- 同轮审核发现的第二处缺陷（即使上面两道不存在，本脚本也是错的）：
--   后置断言**未覆盖 year_month**。core 的更新分支会赋自然月 2026-09，
--   而 980f3039 当前是计费月 2026-08。脚本若执行，会把一条正确的数据改成
--   与出问题那条相同的错误状态，而断言不会发现。
--   —— 全字段回填时，未被断言覆盖的字段会被静默改掉（lessons E8 同族）。
--
-- 保留本文件作为「该路径不可行」的记录。实际采用的方案是放宽候选判定中的
-- lesson_count 必填要求（该字段不参与金额计算）。
--
-- ================== 以下为作废前的原始内容 ==================
--
-- 预定课时 lesson_count 回填，2026-09-06
--
-- 背景：某学生 2026-08 计费周期有 4 节预定课，但只有 3 节进入计费候选。
-- 被排除的那节（2026-09-03）lesson_count 为 NULL，命中候选判定中的
--   AND evidence.lesson_count IS NOT NULL
--   AND evidence.lesson_count > 0
-- 判定表达式见 sql/current/school_tuition_r2_b_candidate_f1_source_compatibility.sql:259-285，
-- 分类函数见 sql/current/school_student_tuition_bill_preview_rpc.sql:66-68
-- （reason_code = 'invalid_or_incomplete_data'）。
--
-- 成因：该节课是单独创建的，另外三节由批量生成器创建（import_source =
-- lesson_planned_batch_generator）。单独创建的入口没有写 lesson_count。
-- 这是入口层的缺陷，本脚本只修数据，不修入口。
--
-- 影响：按修复前的状态生成账单，金额为 JPY 54,000，比应收少 18,000。
--
-- 改动范围：两条预定课时的 lesson_count，与已经改好的实际课时侧对齐。
--   97d2cbd9(09-03)  NULL -> 1
--   980f3039(09-04)  1    -> 2
-- 除 lesson_count 外所有字段原样回填；lesson_fee 传 NULL 交由 DB 计算
-- （P0-B1：lesson_fee 由 DB 权威计算，前端同样传 null）。
--
-- 用法：先 lesson_count_backfill_commit=0 排练，确认输出后再用 1 提交。
\set ON_ERROR_STOP on
\pset pager off

\if :{?lesson_count_backfill_commit}
\else
  \echo 'LESSON_COUNT_BACKFILL_COMMIT_REQUIRED'
  \quit
\endif

begin;
set local lock_timeout='10s';
set local statement_timeout='120s';

do $backfill$
declare
  v_student   constant uuid:='be7effdf-b1eb-4c3d-a24e-0085cc032195';
  v_entity    constant uuid:='2cf7b72f-6e3c-4d09-80f7-7c58593cd466';
  v_teacher   constant uuid:='52babc53-d835-4d82-8481-5074f75d589a';
  v_subject   constant uuid:='14257e03-4d08-478e-b1dc-33c685c3d8f9';
  v_lesson_a  constant uuid:='97d2cbd9-522c-4691-9e59-5c7786d65c68';  -- 09-03
  v_lesson_b  constant uuid:='980f3039-365c-4676-9513-b8824bb3bccd';  -- 09-04
  v_at_a      constant timestamptz:='2026-09-05 15:55:16.569612+00';
  v_at_b      constant timestamptz:='2026-08-31 06:46:46.255961+00';
  v_row record;
  v_snapshot record;
begin
  -- ===== 前置断言：确认取样时的快照现在仍然成立 =====
  -- 任何一处不符都说明期间有人改过，必须停下重新取样，不能盲改。
  select * into strict v_row from public.school_lesson_records where id=v_lesson_a;
  if v_row.updated_at<>v_at_a
     or v_row.lesson_type<>'planned' or v_row.status<>'planned'
     or v_row.lesson_count is not null
     or v_row.student_id<>v_student or v_row.business_entity_id<>v_entity
     or v_row.teacher_id<>v_teacher or v_row.subject_id<>v_subject
     or v_row.lesson_date<>date '2026-09-03'
     or v_row.billing_month<>'2026-08' or v_row.student_settlement_month<>'2026-08'
     or v_row.billing_week_start_date<>date '2026-08-31'
     or v_row.duration_hours<>2 or v_row.unit_price<>9000 or v_row.lesson_fee<>18000
     or v_row.is_billable is not true
     or v_row.lesson_content is not null or v_row.note is not null
     or v_row.lesson_delivery_mode<>'onsite' or v_row.lesson_venue<>'Regus办公室'
     or v_row.aircon_fee_jpy<>0 or v_row.voided_at is not null then
    raise exception 'LESSON_BACKFILL_BASELINE_DRIFT_A';
  end if;

  select * into strict v_row from public.school_lesson_records where id=v_lesson_b;
  if v_row.updated_at<>v_at_b
     or v_row.lesson_type<>'planned' or v_row.status<>'planned'
     or v_row.lesson_count<>1
     or v_row.student_id<>v_student or v_row.business_entity_id<>v_entity
     or v_row.teacher_id<>v_teacher or v_row.subject_id<>v_subject
     or v_row.lesson_date<>date '2026-09-04'
     or v_row.billing_month<>'2026-08' or v_row.student_settlement_month<>'2026-08'
     or v_row.billing_week_start_date<>date '2026-08-31'
     or v_row.duration_hours<>2 or v_row.unit_price<>9000 or v_row.lesson_fee<>18000
     or v_row.is_billable is not true
     or v_row.lesson_content<>'EJU物理' or v_row.note<>'批量生成预定课时'
     or v_row.lesson_delivery_mode<>'onsite' or v_row.lesson_venue<>'Regus办公室'
     or v_row.aircon_fee_jpy<>0 or v_row.voided_at is not null then
    raise exception 'LESSON_BACKFILL_BASELINE_DRIFT_B';
  end if;

  -- 修复前应为 3 条候选 / JPY 54,000
  select * into strict v_snapshot
  from public.school_build_student_tuition_generation_snapshot(v_student,'2026-08',0.042);
  if v_snapshot.candidate_count<>3 or v_snapshot.total_fee_jpy<>54000 then
    raise exception 'LESSON_BACKFILL_PRECONDITION_SNAPSHOT_UNEXPECTED: count=% fee=%',
      v_snapshot.candidate_count,v_snapshot.total_fee_jpy;
  end if;

  -- ===== 写入：走前端同一个授权 RPC，具名参数 =====
  perform public.school_update_lesson_record_guarded_with_venue(
    p_lesson_id               => v_lesson_a,
    p_expected_updated_at     => v_at_a,
    p_lesson_date             => date '2026-09-03',
    p_student_id              => v_student,
    p_teacher_id              => v_teacher,
    p_subject_id              => v_subject,
    p_business_entity_id      => v_entity,
    p_start_time              => '10:00',
    p_end_time                => '12:00',
    p_duration_hours          => 2,
    p_unit_price              => 9000,
    p_lesson_fee              => null,
    p_status                  => 'planned',
    p_is_billable             => true,
    p_lesson_count            => 1,
    p_lesson_content          => null,
    p_note                    => null,
    p_lesson_delivery_mode    => 'onsite',
    p_lesson_venue            => 'Regus办公室'
  );

  perform public.school_update_lesson_record_guarded_with_venue(
    p_lesson_id               => v_lesson_b,
    p_expected_updated_at     => v_at_b,
    p_lesson_date             => date '2026-09-04',
    p_student_id              => v_student,
    p_teacher_id              => v_teacher,
    p_subject_id              => v_subject,
    p_business_entity_id      => v_entity,
    p_start_time              => '10:00',
    p_end_time                => '12:00',
    p_duration_hours          => 2,
    p_unit_price              => 9000,
    p_lesson_fee              => null,
    p_status                  => 'planned',
    p_is_billable             => true,
    p_lesson_count            => 2,
    p_lesson_content          => 'EJU物理',
    p_note                    => '批量生成预定课时',
    p_lesson_delivery_mode    => 'onsite',
    p_lesson_venue            => 'Regus办公室'
  );

  -- ===== 后置断言：只有 lesson_count 变了 =====
  select * into strict v_row from public.school_lesson_records where id=v_lesson_a;
  if v_row.lesson_count<>1
     or v_row.lesson_fee<>18000 or v_row.base_lesson_fee_jpy<>18000
     or v_row.lesson_total_fee_jpy<>18000 or v_row.aircon_fee_jpy<>0
     or v_row.lesson_date<>date '2026-09-03' or v_row.status<>'planned'
     or v_row.billing_month<>'2026-08' or v_row.student_settlement_month<>'2026-08'
     or v_row.billing_week_start_date<>date '2026-08-31'
     or v_row.is_billable is not true
     or v_row.lesson_content is not null or v_row.note is not null
     or v_row.lesson_venue<>'Regus办公室' or v_row.lesson_delivery_mode<>'onsite'
     or v_row.duration_hours<>2 or v_row.unit_price<>9000 then
    raise exception 'LESSON_BACKFILL_POSTCONDITION_A_INVALID';
  end if;

  select * into strict v_row from public.school_lesson_records where id=v_lesson_b;
  if v_row.lesson_count<>2
     or v_row.lesson_fee<>18000 or v_row.base_lesson_fee_jpy<>18000
     or v_row.lesson_total_fee_jpy<>18000 or v_row.aircon_fee_jpy<>0
     or v_row.lesson_date<>date '2026-09-04' or v_row.status<>'planned'
     or v_row.billing_month<>'2026-08' or v_row.student_settlement_month<>'2026-08'
     or v_row.billing_week_start_date<>date '2026-08-31'
     or v_row.is_billable is not true
     or v_row.lesson_content<>'EJU物理' or v_row.note<>'批量生成预定课时'
     or v_row.lesson_venue<>'Regus办公室' or v_row.lesson_delivery_mode<>'onsite'
     or v_row.duration_hours<>2 or v_row.unit_price<>9000 then
    raise exception 'LESSON_BACKFILL_POSTCONDITION_B_INVALID';
  end if;

  -- 目的达成判定：候选 4 条 / JPY 72,000
  select * into strict v_snapshot
  from public.school_build_student_tuition_generation_snapshot(v_student,'2026-08',0.042);
  if v_snapshot.candidate_count<>4 or v_snapshot.total_fee_jpy<>72000 then
    raise exception 'LESSON_BACKFILL_SNAPSHOT_NOT_REPAIRED: count=% fee=%',
      v_snapshot.candidate_count,v_snapshot.total_fee_jpy;
  end if;
end;
$backfill$;

-- 改后状态（回滚脚本需要新的 updated_at，请保存本输出）
select id,lesson_date,lesson_count,lesson_fee,lesson_total_fee_jpy,
       billing_month,year_month,status,updated_at
from public.school_lesson_records
where id in ('97d2cbd9-522c-4691-9e59-5c7786d65c68',
             '980f3039-365c-4676-9513-b8824bb3bccd')
order by lesson_date;

select candidate_count,total_lesson_count,total_fee_jpy,
       generation_manifest_sha256
from public.school_build_student_tuition_generation_snapshot(
  'be7effdf-b1eb-4c3d-a24e-0085cc032195','2026-08',0.042);

\if :lesson_count_backfill_commit
  commit;
  \echo 'LESSON_COUNT_BACKFILL_COMMITTED'
\else
  rollback;
  \echo 'LESSON_COUNT_BACKFILL_REHEARSAL_ROLLED_BACK'
\endif
