-- P0-B2 authoritative-mode rollback tests against the fixed synthetic fixture.
-- All mutations are rolled back. No real business row is addressed.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='10s';
set local statement_timeout='240s';

do $tests$
declare
  v_student constant uuid:='b1b10000-0000-4000-8000-00000000a100';
  v_settlement constant uuid:='b1b10000-0000-4000-8000-00000000b100';
  v_lesson constant uuid:='b1b10000-0000-4000-8000-000000001101';
  v_marker constant text:='codex-test tuition-p0b2-adjustment-mode-20260803';
  v_row record;
  v_updated timestamptz;
  v_locked uuid;
begin
  if (select count(*) from public.school_students
      where id=v_student and note='codex-test tuition-p0b1-lesson-authority-20260803')<>1 then
    raise exception 'P0B2_TEST_FIXTURE_OWNERSHIP_FAILED';
  end if;

  -- Atomic Generate consumes the previous settlement inside this savepoint;
  -- a draft write against that consumed settlement month must fail closed.
  begin
    select * into strict v_row
    from public.school_get_student_tuition_validation_preview_details(
      v_student,'2020-06',0.05);
    perform * from public.school_generate_student_tuition_bill_atomic_core(
      v_student,'2020-06',0.05,v_row.generation_manifest_sha256,
      v_marker,null);
    perform * from public.school_set_student_monthly_settlement_draft_adjustment(
      v_student,'2020-05',1,'manual_adjustment',v_marker,v_marker);
    raise exception 'EXPECTED_CONSUMED_SETTLEMENT_DRAFT_REJECTION_MISSING';
  exception when others then
    if position('CONSUMED' in upper(sqlerrm))=0
       and position('已消费' in sqlerrm)=0 then raise; end if;
  end;

  -- Pure resolver truth table: positive, negative, zero, and DB CNY rounding.
  select * into strict v_row from public.school_tuition_p0b2_resolve_adjustment(
    'carry_final_balance',null,10.125);
  if v_row.resolved_adjustment_amount_cny<>0
     or v_row.resolved_carryover_cny<>10.13 then
    raise exception 'P0B2_CARRY_POSITIVE_FAILED';
  end if;
  select * into strict v_row from public.school_tuition_p0b2_resolve_adjustment(
    'carry_final_balance',null,-10.125);
  if v_row.resolved_adjustment_amount_cny<>0
     or v_row.resolved_carryover_cny<>-10.13 then
    raise exception 'P0B2_CARRY_NEGATIVE_FAILED';
  end if;
  select * into strict v_row from public.school_tuition_p0b2_resolve_adjustment(
    'clear_balance',null,10.125);
  if v_row.resolved_adjustment_amount_cny<>-10.13
     or v_row.resolved_carryover_cny<>0 then
    raise exception 'P0B2_CLEAR_POSITIVE_FAILED';
  end if;
  select * into strict v_row from public.school_tuition_p0b2_resolve_adjustment(
    'clear_balance',null,-10.125);
  if v_row.resolved_adjustment_amount_cny<>10.13
     or v_row.resolved_carryover_cny<>0 then
    raise exception 'P0B2_CLEAR_NEGATIVE_FAILED';
  end if;
  select * into strict v_row from public.school_tuition_p0b2_resolve_adjustment(
    'clear_balance',null,0);
  if v_row.resolved_adjustment_amount_cny<>0
     or v_row.resolved_carryover_cny<>0 then
    raise exception 'P0B2_CLEAR_ZERO_FAILED';
  end if;
  select * into strict v_row from public.school_tuition_p0b2_resolve_adjustment(
    'manual_adjustment',12.345,-10.125);
  if v_row.authoritative_system_difference_cny<>-10.13
     or v_row.resolved_adjustment_amount_cny<>12.35
     or v_row.resolved_carryover_cny<>2.22 then
    raise exception 'P0B2_MANUAL_ROUNDING_FAILED';
  end if;

  begin
    perform * from public.school_tuition_p0b2_resolve_adjustment(
      'carry_final_balance',0,1);
    raise exception 'EXPECTED_CARRY_AMOUNT_REJECTION_MISSING';
  exception when others then
    if position('SETTLEMENT_ADJUSTMENT_AMOUNT_FORBIDDEN_FOR_MODE' in sqlerrm)=0 then raise; end if;
  end;
  begin
    perform * from public.school_tuition_p0b2_resolve_adjustment(
      'clear_balance',0,1);
    raise exception 'EXPECTED_CLEAR_AMOUNT_REJECTION_MISSING';
  exception when others then
    if position('SETTLEMENT_ADJUSTMENT_AMOUNT_FORBIDDEN_FOR_MODE' in sqlerrm)=0 then raise; end if;
  end;
  begin
    perform * from public.school_tuition_p0b2_resolve_adjustment(
      'manual_adjustment',null,1);
    raise exception 'EXPECTED_MANUAL_AMOUNT_REJECTION_MISSING';
  exception when others then
    if position('SETTLEMENT_MANUAL_ADJUSTMENT_AMOUNT_REQUIRED' in sqlerrm)=0 then raise; end if;
  end;
  begin
    perform * from public.school_tuition_p0b2_resolve_adjustment('manual',1,1);
    raise exception 'EXPECTED_MODE_REJECTION_MISSING';
  exception when others then
    if position('SETTLEMENT_ADJUSTMENT_MODE_INVALID' in sqlerrm)=0 then raise; end if;
  end;

  -- The formal writer accepts NULL only for system-resolved modes.
  select * into strict v_row
  from public.school_set_student_monthly_settlement_draft_adjustment(
    v_student,'2020-06',null,'carry_final_balance',v_marker,v_marker);
  if v_row.final_due_cny<>3000 or v_row.adjustment_amount_cny<>0
     or v_row.locked_carryover_cny<>3000 then
    raise exception 'P0B2_DRAFT_CARRY_FAILED';
  end if;
  select * into strict v_row
  from public.school_set_student_monthly_settlement_draft_adjustment(
    v_student,'2020-06',null,'clear_balance',v_marker,v_marker);
  if v_row.adjustment_amount_cny<>-3000 or v_row.locked_carryover_cny<>0 then
    raise exception 'P0B2_DRAFT_CLEAR_FAILED';
  end if;
  select * into strict v_row
  from public.school_set_student_monthly_settlement_draft_adjustment(
    v_student,'2020-06',12.345,'manual_adjustment',v_marker,v_marker);
  if v_row.adjustment_amount_cny<>12.35 or v_row.locked_carryover_cny<>3012.35 then
    raise exception 'P0B2_DRAFT_MANUAL_FAILED';
  end if;

  begin
    perform * from public.school_set_student_monthly_settlement_draft_adjustment(
      v_student,'2020-06',0,'carry_final_balance',v_marker,v_marker);
    raise exception 'EXPECTED_WRITER_FORBIDDEN_AMOUNT_MISSING';
  exception when others then
    if position('SETTLEMENT_ADJUSTMENT_AMOUNT_FORBIDDEN_FOR_MODE' in sqlerrm)=0 then raise; end if;
  end;
  begin
    perform * from public.school_set_student_monthly_settlement_draft_adjustment(
      v_student,'2020-06',null,'manual_adjustment',v_marker,v_marker);
    raise exception 'EXPECTED_WRITER_MANUAL_REQUIRED_MISSING';
  exception when others then
    if position('SETTLEMENT_MANUAL_ADJUSTMENT_AMOUNT_REQUIRED' in sqlerrm)=0 then raise; end if;
  end;

  -- Production data path also covers negative and zero differences.
  update public.school_student_monthly_settlements set
    system_difference_cny=-4000,adjustment_amount_cny=0,
    carryover_amount_cny=-4000,updated_at=statement_timestamp()
  where id=v_settlement;
  set constraints school_tuition_p0b2_settlement_resolution immediate;
  select * into strict v_row
  from public.school_set_student_monthly_settlement_draft_adjustment(
    v_student,'2020-06',null,'clear_balance',v_marker,v_marker);
  if v_row.final_due_cny<>-1000 or v_row.adjustment_amount_cny<>1000
     or v_row.locked_carryover_cny<>0 then
    raise exception 'P0B2_DATA_PATH_NEGATIVE_FAILED';
  end if;
  update public.school_student_monthly_settlements set
    system_difference_cny=-3000,adjustment_amount_cny=0,
    carryover_amount_cny=-3000,updated_at=statement_timestamp()
  where id=v_settlement;
  set constraints school_tuition_p0b2_settlement_resolution immediate;
  select * into strict v_row
  from public.school_set_student_monthly_settlement_draft_adjustment(
    v_student,'2020-06',null,'clear_balance',v_marker,v_marker);
  if v_row.final_due_cny<>0 or v_row.adjustment_amount_cny<>0
     or v_row.locked_carryover_cny<>0 then
    raise exception 'P0B2_DATA_PATH_ZERO_FAILED';
  end if;
  update public.school_student_monthly_settlements set
    system_difference_cny=0,adjustment_amount_cny=0,
    carryover_amount_cny=0,updated_at=statement_timestamp()
  where id=v_settlement;
  set constraints school_tuition_p0b2_settlement_resolution immediate;

  -- Save clear, mutate an authoritative lesson through the formal Lesson RPC,
  -- then prove preview and lock re-resolve instead of freezing the stale draft.
  perform * from public.school_set_student_monthly_settlement_draft_adjustment(
    v_student,'2020-06',null,'clear_balance',v_marker,v_marker);
  select updated_at into strict v_updated
  from public.school_lesson_records where id=v_lesson;
  perform * from public.school_update_lesson_record_guarded(
    v_lesson,v_updated,'2020-06-10',v_student,
    'b1b10000-0000-4000-8000-000000007100'::uuid,
    'b1b10000-0000-4000-8000-00000000d100'::uuid,
    'b1b10000-0000-4000-8000-00000000e100'::uuid,
    '15:00','17:00',2,12000,1,'planned',true,2,v_marker,v_marker);
  select * into strict v_row
  from public.school_get_student_monthly_settlement_preview(v_student,'2020-06');
  if v_row.final_due_cny<>3200 or v_row.adjustment_amount_cny<>-3200
     or v_row.locked_carryover_cny<>0 then
    raise exception 'P0B2_PREVIEW_RERESOLUTION_FAILED';
  end if;
  select settlement_id into strict v_locked
  from public.school_lock_student_monthly_settlement(v_student,'2020-06',v_marker);
  if not exists (
    select 1 from public.school_student_monthly_settlements m
    join public.school_student_settlement_adjustments a
      on a.settlement_id=m.id
    join public.school_student_settlement_adjustment_drafts d
      on d.settlement_id=m.id
    where m.id=v_locked and m.system_difference_cny=3200
      and m.adjustment_amount_cny=-3200 and m.carryover_amount_cny=0
      and a.adjustment_source='clear_balance'
      and a.adjustment_amount_cny=-3200 and a.status='posted'
      and d.status='consumed' and d.adjustment_amount_cny=-3200
  ) then raise exception 'P0B2_LOCK_FREEZE_FAILED'; end if;

  begin
    update public.school_student_settlement_adjustments
    set adjustment_amount_cny=-1 where settlement_id=v_locked;
    raise exception 'EXPECTED_POSTED_IMMUTABILITY_MISSING';
  exception when others then
    if position('SETTLEMENT_POSTED_ADJUSTMENT_IMMUTABLE' in sqlerrm)=0
       and position('TUITION_CONSUMED_SETTLEMENT' in sqlerrm)=0 then raise; end if;
  end;
  begin
    update public.school_student_monthly_settlements
    set carryover_amount_cny=1 where id=v_locked;
    set constraints school_tuition_p0b2_settlement_resolution immediate;
    raise exception 'EXPECTED_SETTLEMENT_MISMATCH_REJECTION_MISSING';
  exception when others then
    if position('SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH' in sqlerrm)=0
       and position('TUITION_CONSUMED_SETTLEMENT' in sqlerrm)=0 then raise; end if;
  end;
  begin
    perform * from public.school_apply_student_monthly_settlement_adjustment(
      v_locked,1,'manual_adjustment',v_marker,v_marker);
    raise exception 'EXPECTED_LEGACY_APPLY_FAILCLOSED_MISSING';
  exception when others then
    if position('禁用' in sqlerrm)=0 and position('已停用' in sqlerrm)=0
       and position('只读快照' in sqlerrm)=0 then raise; end if;
  end;
end
$tests$;

rollback;
select 'P0B2_ADJUSTMENT_MODE_ROLLBACK_TESTS_PASSED' result;
