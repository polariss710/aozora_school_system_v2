-- school_lesson_planned_count_backfill_20260906.sql 的回滚脚本
--
-- ⚠️ 一处不可逆，执行前必须知道：
-- 09-03 那条原值是 NULL。若 school_update_lesson_record_guarded_with_venue
-- 拒绝 p_lesson_count => NULL（它是候选判定要求非空的字段，RPC 很可能有校验），
-- 则**无法还原为 NULL**，只能停在某个正整数上。
-- 届时本脚本会在该步失败并整体回滚，09-04 也不会被改动。
--
-- 也请先想清楚是否真的需要回滚：NULL 是「数据不完整」的缺陷状态，
-- 回到它等于回到会漏计费的状态。lesson_count 不参与金额计算
-- （候选三节 lesson_count 为 1/1/2，course_total_jpy 均为 18000），
-- 所以正向改动对账单金额的影响仅限于「那节课能否进入候选」。
--
-- 期望值不硬编码 updated_at：正向脚本执行后时间戳会变，
-- 这里从表中实时读取，因此本脚本可在正向执行后的任意时刻运行。
--
-- 用法：先 lesson_count_rollback_commit=0 排练。
\set ON_ERROR_STOP on
\pset pager off

\if :{?lesson_count_rollback_commit}
\else
  \echo 'LESSON_COUNT_ROLLBACK_COMMIT_REQUIRED'
  \quit
\endif

begin;
set local lock_timeout='10s';
set local statement_timeout='120s';

do $rollback$
declare
  v_student  constant uuid:='be7effdf-b1eb-4c3d-a24e-0085cc032195';
  v_entity   constant uuid:='2cf7b72f-6e3c-4d09-80f7-7c58593cd466';
  v_teacher  constant uuid:='52babc53-d835-4d82-8481-5074f75d589a';
  v_subject  constant uuid:='14257e03-4d08-478e-b1dc-33c685c3d8f9';
  v_lesson_a constant uuid:='97d2cbd9-522c-4691-9e59-5c7786d65c68';  -- 09-03
  v_lesson_b constant uuid:='980f3039-365c-4676-9513-b8824bb3bccd';  -- 09-04
  v_row record; v_at_a timestamptz; v_at_b timestamptz;
begin
  -- 只有处在「已回填」状态才允许回滚
  select * into strict v_row from public.school_lesson_records where id=v_lesson_a;
  if v_row.lesson_count<>1 or v_row.lesson_type<>'planned' or v_row.status<>'planned' then
    raise exception 'LESSON_ROLLBACK_STATE_A_UNEXPECTED: lesson_count=%',v_row.lesson_count;
  end if;
  v_at_a:=v_row.updated_at;

  select * into strict v_row from public.school_lesson_records where id=v_lesson_b;
  if v_row.lesson_count<>2 or v_row.lesson_type<>'planned' or v_row.status<>'planned' then
    raise exception 'LESSON_ROLLBACK_STATE_B_UNEXPECTED: lesson_count=%',v_row.lesson_count;
  end if;
  v_at_b:=v_row.updated_at;

  -- 先做 09-04（可完全还原），再做 09-03（可能失败）。
  -- 任一失败都整体回滚，不会留下半改状态。
  perform public.school_update_lesson_record_guarded_with_venue(
    p_lesson_id            => v_lesson_b,
    p_expected_updated_at  => v_at_b,
    p_lesson_date          => date '2026-09-04',
    p_student_id           => v_student,
    p_teacher_id           => v_teacher,
    p_subject_id           => v_subject,
    p_business_entity_id   => v_entity,
    p_start_time           => '10:00',
    p_end_time             => '12:00',
    p_duration_hours       => 2,
    p_unit_price           => 9000,
    p_lesson_fee           => null,
    p_status               => 'planned',
    p_is_billable          => true,
    p_lesson_count         => 1,
    p_lesson_content       => 'EJU物理',
    p_note                 => '批量生成预定课时',
    p_lesson_delivery_mode => 'onsite',
    p_lesson_venue         => 'Regus办公室'
  );

  perform public.school_update_lesson_record_guarded_with_venue(
    p_lesson_id            => v_lesson_a,
    p_expected_updated_at  => v_at_a,
    p_lesson_date          => date '2026-09-03',
    p_student_id           => v_student,
    p_teacher_id           => v_teacher,
    p_subject_id           => v_subject,
    p_business_entity_id   => v_entity,
    p_start_time           => '10:00',
    p_end_time             => '12:00',
    p_duration_hours       => 2,
    p_unit_price           => 9000,
    p_lesson_fee           => null,
    p_status               => 'planned',
    p_is_billable          => true,
    p_lesson_count         => null,   -- ← 可能被 RPC 拒绝，见文件头
    p_lesson_content       => null,
    p_note                 => null,
    p_lesson_delivery_mode => 'onsite',
    p_lesson_venue         => 'Regus办公室'
  );

  -- 还原判定：回到 3 条候选 / JPY 54,000
  select * into strict v_row from public.school_lesson_records where id=v_lesson_a;
  if v_row.lesson_count is not null then
    raise exception 'LESSON_ROLLBACK_A_NOT_RESTORED: lesson_count=%',v_row.lesson_count;
  end if;
end;
$rollback$;

select id,lesson_date,lesson_count,lesson_fee,status,updated_at
from public.school_lesson_records
where id in ('97d2cbd9-522c-4691-9e59-5c7786d65c68',
             '980f3039-365c-4676-9513-b8824bb3bccd')
order by lesson_date;

select candidate_count,total_lesson_count,total_fee_jpy
from public.school_build_student_tuition_generation_snapshot(
  'be7effdf-b1eb-4c3d-a24e-0085cc032195','2026-08',0.042);

\if :lesson_count_rollback_commit
  commit;
  \echo 'LESSON_COUNT_ROLLBACK_COMMITTED'
\else
  rollback;
  \echo 'LESSON_COUNT_ROLLBACK_REHEARSAL_ROLLED_BACK'
\endif
