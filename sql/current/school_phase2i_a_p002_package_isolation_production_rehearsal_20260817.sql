-- Production ROLLBACK rehearsal. Applies the exact migration in one transaction.
\set ON_ERROR_STOP on
\set phase2i_a_commit 0
\ir school_phase2i_a_p002_package_isolation_migration_20260817.sql

do $assert_rehearsal$
declare
  v_preview jsonb;
begin
  if (select count(*) from public.school_student_package_credit_lots)<>1
     or not exists(select 1 from public.school_student_package_credit_lots lot
       where lot.origin_planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
         and lot.initial_minutes=1200 and lot.consumed_minutes=0
         and lot.remaining_minutes=1200 and lot.status='active') then
    raise exception 'PHASE2I_A_REHEARSAL_PACKAGE_FACT_MISMATCH';
  end if;
  if public.school_get_lesson_credit_raw_remaining_hours(
       '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9')<>0
     or public.school_get_lesson_credit_remaining_hours(
       '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9')<>0
     or exists(select 1 from public.school_list_open_lesson_credit_sources(
       '2026-07','2026-07','2026-07') source
       where source.id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9')
     or exists(select 1 from public.school_tuition_p0f_source_lines(
       'a7b163a0-201e-4867-9b94-372343356a80',
       '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-07',0.045,false) source
       where source.source_planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9') then
    raise exception 'PHASE2I_A_REHEARSAL_ORDINARY_CHAIN_NOT_ISOLATED';
  end if;
  if exists(
    (select source.id from public.school_list_open_lesson_credit_sources(
      '2026-01','2026-08','2026-08') source)
    except
    (select p.id from public.school_lesson_records p
      where p.app_type='school' and p.lesson_type='planned'
        and p.status='pending_makeup' and p.voided_at is null
        and p.id<>'8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
        and public.school_resolve_r1d_e_c_lesson_student_month(p.id)
          between '2026-01' and '2026-08'
        and public.school_get_lesson_credit_raw_remaining_hours(p.id)>0
        and not exists(select 1
          from public.school_student_settlement_lesson_variance_claims claim
          where claim.claim_status='active'
            and claim.source_type='unused_planned_credit_v1'
            and claim.source_planned_lesson_id=p.id))
  ) or exists(
    (select p.id from public.school_lesson_records p
      where p.app_type='school' and p.lesson_type='planned'
        and p.status='pending_makeup' and p.voided_at is null
        and p.id<>'8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
        and public.school_resolve_r1d_e_c_lesson_student_month(p.id)
          between '2026-01' and '2026-08'
        and public.school_get_lesson_credit_raw_remaining_hours(p.id)>0
        and not exists(select 1
          from public.school_student_settlement_lesson_variance_claims claim
          where claim.claim_status='active'
            and claim.source_type='unused_planned_credit_v1'
            and claim.source_planned_lesson_id=p.id))
    except
    (select source.id from public.school_list_open_lesson_credit_sources(
      '2026-01','2026-08','2026-08') source)
  ) then
    raise exception 'PHASE2I_A_REHEARSAL_NON_P002_SOURCE_DELTA';
  end if;
  select public.school_preview_student_settlement_adjustment_dialog(
    'a7b163a0-201e-4867-9b94-372343356a80',
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-07',
    'separate_makeup_and_overage_v1',null,null,null,'carry_final_balance',null)
    into v_preview;
  if coalesce((v_preview#>>'{preview,registered_source_count}')::integer,-1)<>0
     or coalesce((v_preview#>>'{preview,registered_pending_hours}')::numeric,-1)<>0
     or coalesce((v_preview#>>'{preview,registered_pending_amount_jpy}')::numeric,-1)<>0 then
    raise exception 'PHASE2I_A_REHEARSAL_PREVIEW_VARIANCE_NOT_REMOVED: %',v_preview;
  end if;
  if md5((select to_jsonb(x)::text from public.school_lesson_records x
      where x.id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'))
       <>'686cbf3a566160bf0de0e30abbdaafa5'
     or (select count(*) from public.school_lesson_records)<>771
     or (select count(*) from public.school_student_monthly_settlements)<>18
     or (select count(*) from public.school_student_tuition_bills)<>22
     or (select count(*) from public.school_income_records)<>56 then
    raise exception 'PHASE2I_A_REHEARSAL_EXISTING_ROW_DRIFT';
  end if;
  if to_regclass('public.school_lesson_clearances') is not null
     or to_regclass('public.school_lesson_clearance_details') is not null
     or exists(select 1 from pg_proc procedure
       where procedure.pronamespace='public'::regnamespace
         and procedure.proname~'package.*(consume|reserve)|(consume|reserve).*package') then
    raise exception 'PHASE2I_A_REHEARSAL_FORBIDDEN_OBJECT';
  end if;
end
$assert_rehearsal$;

set local role authenticated;
select set_config('request.jwt.claim.sub','25331ae9-3412-48b9-bdc3-e516caeaeba4',true);
select * from public.school_list_student_package_credit_lots(
  'a7b163a0-201e-4867-9b94-372343356a80');
select public.school_get_lesson_credit_remaining_hours(
  '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9') authenticated_p002_remaining;
select count(*) authenticated_p002_balance_rows
from public.school_list_student_lesson_credit_balances(
  'a7b163a0-201e-4867-9b94-372343356a80');
reset role;
rollback;
