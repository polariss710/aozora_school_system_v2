-- Read-only postdeploy verification for the locked-carry ordinary Reissue correction
-- and the authorized Peng/Li rate-correction operations.
\set ON_ERROR_STOP on
\pset pager off

do $verify$
declare
  v_bill uuid;
begin
  if position('s.settlement_status=''locked''' in pg_get_functiondef(
       'public.school_reissue_atomic_student_tuition_generation_local(uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text)'::regprocedure))=0
     or position('round(coalesce(s.carryover_amount_cny,0),2)' in pg_get_functiondef(
       'public.school_reissue_atomic_student_tuition_generation_local(uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text)'::regprocedure))=0
     or not has_function_privilege('service_role',
       'public.school_reissue_atomic_student_tuition_generation_local(uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text)','EXECUTE')
     or has_function_privilege('anon',
       'public.school_reissue_atomic_student_tuition_generation_local(uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text)','EXECUTE')
     or has_function_privilege('authenticated',
       'public.school_reissue_atomic_student_tuition_generation_local(uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,text)','EXECUTE') then
    raise exception 'LOCKED_CARRY_REISSUE_FUNCTION_OR_ACL_INVALID';
  end if;
  if exists(
    select 1 from public.school_student_tuition_generation_revisions
    where lifecycle_status='active' group by generation_identity_id having count(*)<>1
  ) then raise exception 'ACTIVE_REVISION_CARDINALITY_INVALID'; end if;
  if exists(
    select 1
    from public.school_student_tuition_generation_revisions r
    join public.school_student_tuition_bills b on b.id=r.tuition_bill_id
    where r.lifecycle_status='active' and b.previous_settlement_id is not null
    group by b.previous_settlement_id having count(*)<>1
  ) then raise exception 'ACTIVE_CARRYOVER_CLAIM_CARDINALITY_INVALID'; end if;

  select b.id into strict v_bill
  from public.school_student_tuition_generation_revisions r
  join public.school_student_tuition_bills b on b.id=r.tuition_bill_id
  join public.school_income_records i on i.id=b.income_record_id
  where r.id='f7bbd000-9753-4f00-9d3a-d8705ee8d5e9'
    and r.revision_no=3 and r.previous_revision_id='49e530ee-d190-45e2-8f2f-24b16713b194'
    and r.lifecycle_status='active' and b.id='a5cac133-36ee-4324-9c67-f95eadf62200'
    and b.status='income_created' and b.bill_amount_jpy=204000
    and b.billing_exchange_rate=0.043 and b.previous_carryover_cny=-624.75
    and b.previous_settlement_id='6ec3b815-5540-44bd-88ee-9e30a5284770'
    and b.billing_amount_cny=8147.25
    and i.id='648e264d-3435-43f1-a797-cf1394011f65' and i.status='pending';
  perform public.school_validate_tuition_identity_for_bill(v_bill);
  perform public.school_validate_tuition_bill_income_for_bill(v_bill);
  perform public.school_validate_tuition_bill_lessons_for_bill(v_bill);
  perform public.school_validate_tuition_generation_revision_for_bill(v_bill);
  perform public.school_validate_tuition_generation_revision_adjustment_for_bill(v_bill);

  select b.id into strict v_bill
  from public.school_student_tuition_generation_revisions r
  join public.school_student_tuition_bills b on b.id=r.tuition_bill_id
  join public.school_income_records i on i.id=b.income_record_id
  where r.id='f7150ce5-fb77-4b7f-99f8-207bfbbced91'
    and r.revision_no=3 and r.previous_revision_id='8002e02c-a556-4161-bf01-6532f0eae0dd'
    and r.lifecycle_status='active' and b.id='66a1f276-2756-466f-b709-b8ca29063fd9'
    and b.status='income_created' and b.bill_amount_jpy=220000
    and b.billing_exchange_rate=0.042 and b.previous_carryover_cny=0
    and b.previous_settlement_id is null and b.billing_amount_cny=9240
    and i.id='efd670bc-8dba-4926-82c4-2d194281a609' and i.status='pending';
  perform public.school_validate_tuition_identity_for_bill(v_bill);
  perform public.school_validate_tuition_bill_income_for_bill(v_bill);
  perform public.school_validate_tuition_bill_lessons_for_bill(v_bill);
  perform public.school_validate_tuition_generation_revision_for_bill(v_bill);
  perform public.school_validate_tuition_generation_revision_adjustment_for_bill(v_bill);

  if (select count(*) from public.school_student_tuition_generation_revision_adjustments a
      join public.school_student_tuition_generation_identities g on g.id=a.generation_identity_id
      where g.student_id in ('eb705aad-de4d-45e6-a391-42dcdd89aeda','a7b163a0-201e-4867-9b94-372343356a80'))<>0
     or (select count(*) from public.school_student_monthly_settlements
         where student_id='a7b163a0-201e-4867-9b94-372343356a80' and year_month='2026-07')<>0
     or not exists(select 1 from public.school_student_monthly_settlements
                   where id='6ec3b815-5540-44bd-88ee-9e30a5284770'
                     and settlement_status='locked' and carryover_amount_cny=-624.75)
     or exists(select 1 from public.school_students
               where id='d0d00000-0000-4000-8000-00000000a001') then
    raise exception 'SETTLEMENT_ADJUSTMENT_OR_FIXTURE_POSTDEPLOY_INVALID';
  end if;
  if exists(
    select 1
    from public.school_lesson_records l
    join public.school_student_tuition_bill_lessons bl on bl.planned_lesson_id=l.id
    join public.school_student_tuition_generation_revisions r on r.tuition_bill_id=bl.tuition_bill_id
    where r.lifecycle_status='active' and l.id=any(array[
      '6f22f125-4bd3-4278-8265-b04f39b3e8c2','d4d261bb-5b6b-4ab5-8dc8-7a2c7d6ca5dc','8edaeefc-9295-4da5-83a2-5f38e4beda8d',
      '40b45df8-6ed3-4ccd-9ffd-25fb06de18fe','f71185d0-92d0-4d73-8b0e-ea5c56ea7c49','0667c085-73ae-495e-ad05-e29ae98ca5cb',
      '538ee794-8185-4d42-ac48-a44a7ce8cca6','61e9b683-9bff-4c30-9174-a4ad3463f430','6ce1da2f-0621-4ceb-ace4-b9994ef21fb1'
    ]::uuid[])
  ) then raise exception 'VOIDED_LESSON_ACTIVE_RELATION_INVALID'; end if;
  if (select jsonb_object_agg(feature_key,state) from public.school_feature_gates
      where feature_key like 'student_tuition_%')
       is distinct from '{"student_tuition_preview":"enabled","student_tuition_generate":"blocked","student_tuition_cash_submit":"blocked"}'::jsonb then
    raise exception 'TUITION_GATE_INVALID';
  end if;
end;
$verify$;

select 'LOCKED_CARRY_ORDINARY_REISSUE_POSTDEPLOY_PASS' result;
