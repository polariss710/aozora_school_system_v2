-- School V2: locked billing-month non-billing makeup boundary and the exact
-- Sun Chenfeng 2026-08-11 correction writer.
-- Business-model expansion declaration: see
-- docs/school-v2-locked-billing-month-makeup-sun-chenfeng-correction-20260816.md.
-- No table/column/status is created or changed. This file changes three
-- existing function definitions and adds one exact, one-shot correction RPC.
\set ON_ERROR_STOP on
\pset pager off

\if :{?sun_chenfeng_caller_transaction}
\else
begin;
set local lock_timeout='10s';
set local statement_timeout='240s';
\endif

do $preflight$
begin
  if md5(pg_get_functiondef(
       'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
     ))<>'e6de3be6719e88c7da9b451e40f3b7c7'
     or md5(pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure
     ))<>'60e380b560b0682dd78aa97139382d65'
     or md5(pg_get_functiondef(
       'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure
     ))<>'73ac1abeebb6ce82870f9e0f8240629b'
     or to_regprocedure(
       'public.school_correct_sun_chenfeng_20260811_makeup_v1(timestamp with time zone,timestamp with time zone,text,text)'
     ) is not null then
    raise exception 'SUN_CHENFENG_CORRECTION_FUNCTION_PREFLIGHT_DRIFT';
  end if;

  if (select count(*) from public.school_lesson_records l
      where l.id='8b737b58-cd14-42c5-afd2-34730dcef963'::uuid
        and md5(to_jsonb(l)::text)='07296184e3ffaf443f89109e2b54d9b9')<>1
     or (select count(*) from public.school_lesson_records l
         where l.id='c8e6cf21-850c-4700-af9e-7ebf3c2a577d'::uuid
           and md5(to_jsonb(l)::text)='1086af5afd9a91d3a6a03b2d5b9cc458')<>1
     or (select count(*) from public.school_lesson_records l
         where l.id='6722e5a8-d7a1-453a-93a8-9cbaab227378'::uuid
           and md5(to_jsonb(l)::text)='94050771268fa97cda680affb81e9364')<>1 then
    raise exception 'SUN_CHENFENG_CORRECTION_TARGET_PREFLIGHT_DRIFT';
  end if;

  if (select count(*) from public.school_teacher_wage_locks w
      where w.teacher_id='edaf30da-1315-4455-99d1-ead1b7147662'::uuid
        and w.business_entity_id='2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
        and w.settlement_month='2026-08'
        and w.status='locked')<>0 then
    raise exception 'SUN_CHENFENG_CORRECTION_AUGUST_WAGE_LOCKED';
  end if;
end;
$preflight$;

-- Preserve every canonical writer contract and remove only the over-broad
-- student-settlement lock rejection. The inserted row is still forced to
-- makeup_completed/non-billable/fee zero by this writer and table triggers.
do $patch_makeup_writer$
declare
  v_definition text;
  v_old_date text:=$old$  p_lesson_date:=coalesce(p_lesson_date,v_planned.lesson_date);
  if p_lesson_date is null then
    raise exception using errcode='22023',message='LESSON_TIME_DATE_REQUIRED';
  end if;$old$;
  v_new_date text:=$new$  p_lesson_date:=coalesce(p_lesson_date,v_planned.lesson_date);
  if p_lesson_date is null then
    raise exception using errcode='22023',message='LESSON_TIME_DATE_REQUIRED';
  end if;
  if p_lesson_date<v_planned.lesson_date then
    raise exception using errcode='22023',message='LESSON_MAKEUP_DATE_BEFORE_SOURCE';
  end if;$new$;
  v_old_lock text:=$old$  if exists(select 1 from public.school_student_monthly_settlements s
    where s.student_id=v_planned.student_id and s.year_month=v_student_settlement_month
      and s.business_entity_id is not distinct from v_planned.business_entity_id
      and s.settlement_status='locked') then
    raise exception using errcode='P0001',message='LESSON_MAKEUP_STUDENT_SETTLEMENT_LOCKED';
  end if;
$old$;
  v_new_lock text:=$new$  -- A locked source billing month freezes money, not a later fee-zero
  -- fulfilment. The table trigger independently enforces the same distinction.
$new$;
begin
  select pg_get_functiondef(
    'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
  ) into strict v_definition;
  if md5(v_definition)<>'e6de3be6719e88c7da9b451e40f3b7c7'
     or position(v_old_date in v_definition)=0
     or position(v_old_lock in v_definition)=0 then
    raise exception 'SUN_CHENFENG_MAKEUP_PATCH_SOURCE_DRIFT';
  end if;
  v_definition:=replace(v_definition,v_old_date,v_new_date);
  v_definition:=replace(v_definition,v_old_lock,v_new_lock);
  execute v_definition;
end;
$patch_makeup_writer$;

-- Table-level invariant: direct/future writers cannot bypass the fee-zero
-- distinction. Existing Li/Wu exact-correction behavior is preserved byte for
-- byte in its branch.
create or replace function public.school_enforce_r1d_e_b2_actual_attribution()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_source public.school_lesson_records%rowtype;
  v_evidence public.school_legacy_actual_settlement_evidence%rowtype;
  v_student_month text;
  v_old_teacher_month text;
  v_new_teacher_month text;
  v_has_legacy_evidence boolean;
  v_is_exact_correction boolean:=false;
  v_is_locked_nonbilling_makeup boolean:=false;
  v_is_sun_exact_cancel boolean:=false;
  v_is_sun_exact_void boolean:=false;
begin
  if tg_op='INSERT' then
    if new.lesson_type<>'actual' then return new; end if;
    if new.app_type<>'school' then
      raise exception 'R1D_E_B2_NON_SCHOOL_ACTUAL_REJECTED';
    end if;
    select p.* into v_source from public.school_lesson_records p
    where p.id=new.planned_lesson_id;
    if not found or v_source.status not in ('planned','pending_makeup') then
      raise exception 'R1D_E_B2_ACTUAL_SOURCE_STATUS_INVALID';
    end if;
    v_student_month:=public.school_resolve_r1d_e_b2_actual_student_month(
      new.planned_lesson_id);
    if new.student_id is distinct from v_source.student_id
       or new.business_entity_id is distinct from v_source.business_entity_id then
      raise exception 'R1D_E_B2_ACTUAL_SOURCE_STUDENT_ENTITY_MISMATCH';
    end if;
    if num_nonnulls(new.billing_month,new.billing_week_start_date,
         new.billing_month_source,new.billing_month_decided_at)<>0 then
      raise exception 'R1D_E_B2_ACTUAL_BILLING_BUNDLE_FORBIDDEN';
    end if;
    if new.status='makeup_completed'
       and new.lesson_date<v_source.lesson_date then
      raise exception using errcode='22023',
        message='LESSON_MAKEUP_DATE_BEFORE_SOURCE';
    end if;

    new.student_settlement_month:=v_student_month;
    new.year_month:=v_student_month;
    new.teacher_settlement_month:=to_char(new.lesson_date,'YYYY-MM');

    v_is_locked_nonbilling_makeup:=
      v_source.status='pending_makeup'
      and new.status='makeup_completed'
      and new.is_billable is false
      and new.lesson_fee=0
      and new.lesson_date>=v_source.lesson_date;

    v_is_sun_exact_cancel:=
      current_setting('app.sun_chenfeng_exact_correction_context',true)
        ='sun_chenfeng_20260811_makeup_v1_20260816'
      and current_setting('app.sun_chenfeng_exact_correction_action',true)
        ='void_cancel_makeup'
      and current_setting('app.sun_chenfeng_exact_correction_actor',true)=auth.uid()::text
      and auth.uid()='25331ae9-3412-48b9-bdc3-e516caeaeba4'::uuid
      and exists(select 1 from public.school_app_memberships m
        where m.user_id=auth.uid() and m.role='admin' and m.is_active)
      and v_source.id='8b737b58-cd14-42c5-afd2-34730dcef963'::uuid
      and new.status='cancelled' and new.is_billable is false
      and new.lesson_fee=0 and new.actual_minutes=0
      and new.lesson_date='2026-08-01'::date
      and new.start_time='13:00' and new.end_time='15:00'
      and new.duration_hours=2
      and new.teacher_id='edaf30da-1315-4455-99d1-ead1b7147662'::uuid
      and new.subject_id='14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid;

    if exists(select 1 from public.school_student_monthly_settlements s
      where s.student_id=new.student_id
        and s.business_entity_id is not distinct from new.business_entity_id
        and s.year_month=v_student_month and s.settlement_status='locked')
      and not v_is_locked_nonbilling_makeup
      and not v_is_sun_exact_cancel then
      raise exception 'R1D_E_B2_STUDENT_SETTLEMENT_LOCKED';
    end if;
    if exists(select 1 from public.school_teacher_wage_locks w
      where w.teacher_id=new.teacher_id
        and w.business_entity_id is not distinct from new.business_entity_id
        and w.settlement_month=new.teacher_settlement_month
        and w.status='locked') then
      raise exception 'R1D_E_B2_TEACHER_WAGE_MONTH_LOCKED';
    end if;
    return new;
  end if;

  select exists(select 1 from public.school_legacy_actual_settlement_evidence e
    where e.actual_lesson_id=old.id) into v_has_legacy_evidence;

  if old.lesson_type='actual' or v_has_legacy_evidence then
    if old.lesson_type is distinct from 'actual'
       or old.app_type is distinct from 'school'
       or new.lesson_type is distinct from 'actual'
       or new.app_type is distinct from 'school' then
      raise exception 'R1D_E_B2_ACTUAL_TYPE_OR_APP_IMMUTABLE';
    end if;
  else
    if new.lesson_type<>'actual' then return new; end if;
    raise exception 'R1D_E_B2_PLANNED_TO_ACTUAL_UPDATE_REJECTED';
  end if;

  if old.lesson_type<>'actual' or old.app_type<>'school'
     or new.planned_lesson_id is distinct from old.planned_lesson_id
     or new.student_id is distinct from old.student_id
     or new.business_entity_id is distinct from old.business_entity_id then
    raise exception 'R1D_E_B2_ACTUAL_SOURCE_STUDENT_ENTITY_IMMUTABLE';
  end if;

  select e.* into v_evidence
  from public.school_legacy_actual_settlement_evidence e
  where e.actual_lesson_id=old.id;

  v_is_exact_correction:=
    current_setting('app.school_lesson_exact_correction_context',true)
      ='li_wu_2026_09_11_test_lessons_void_v1_20260806'
    and current_setting('app.school_lesson_exact_correction_manifest',true)
      ='e2bc9f4380f5bf5a95ff0341ae47183b'
    and current_setting('app.school_lesson_exact_correction_action',true)
      ='exact_void_correction'
    and current_setting('app.school_lesson_exact_correction_actor',true)=auth.uid()::text
    and exists(select 1 from public.school_app_memberships m
      where m.user_id=auth.uid() and m.role='admin' and m.is_active)
    and old.id=any(array[
      'e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid,
      'b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid,
      'dc06b98c-360f-4661-a294-52ecb82830a7'::uuid,
      'c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid])
    and md5(to_jsonb(old)::text)=case old.id
      when 'e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid then '68a2e384c0da181bbc514899899e1bf1'
      when 'b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid then '97667b2d7b8bd485e7571c7ca12306d8'
      when 'dc06b98c-360f-4661-a294-52ecb82830a7'::uuid then 'b111085217eff6410f34895722068117'
      when 'c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid then '34ecb1210e1c65d2e35f0b8165b97d06'
    end
    and old.voided_at is null and old.void_reason is null
    and new.voided_at is not null
    and new.void_reason=
      '业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。'
    and (to_jsonb(new)-array['voided_at','void_reason','updated_at'])
        is not distinct from
        (to_jsonb(old)-array['voided_at','void_reason','updated_at']);

  v_is_sun_exact_void:=
    current_setting('app.sun_chenfeng_exact_correction_context',true)
      ='sun_chenfeng_20260811_makeup_v1_20260816'
    and current_setting('app.sun_chenfeng_exact_correction_action',true)
      ='void_cancel_makeup'
    and current_setting('app.sun_chenfeng_exact_correction_actor',true)=auth.uid()::text
    and auth.uid()='25331ae9-3412-48b9-bdc3-e516caeaeba4'::uuid
    and exists(select 1 from public.school_app_memberships m
      where m.user_id=auth.uid() and m.role='admin' and m.is_active)
    and old.id='c8e6cf21-850c-4700-af9e-7ebf3c2a577d'::uuid
    and md5(to_jsonb(old)::text)='1086af5afd9a91d3a6a03b2d5b9cc458'
    and old.voided_at is null and old.void_reason is null
    and new.voided_at is not null
    and new.void_reason=
      '孙陈锋2026-08-01实际缺课；纠正错误ordinary actual并转待补，2026-08-11由田宇辰完成非计费补课；actor_user_id=25331ae9-3412-48b9-bdc3-e516caeaeba4'
    and (to_jsonb(new)-array['voided_at','void_reason','updated_at'])
        is not distinct from
        (to_jsonb(old)-array['voided_at','void_reason','updated_at']);

  if found then
    if not v_is_exact_correction and (
       old.student_settlement_month is not null or new.student_settlement_month is not null
       or new.planned_lesson_id is distinct from v_evidence.source_planned_lesson_id
       or new.student_id is distinct from v_evidence.student_id_snapshot
       or new.business_entity_id is distinct from v_evidence.business_entity_id_snapshot
       or new.teacher_id is distinct from v_evidence.teacher_id_snapshot
       or new.subject_id is distinct from v_evidence.subject_id_snapshot
       or new.year_month is distinct from v_evidence.legacy_year_month
       or new.teacher_settlement_month is distinct from v_evidence.teacher_settlement_month_snapshot
       or new.lesson_date is distinct from v_evidence.lesson_date_snapshot
       or md5(concat_ws('|',new.id::text,new.planned_lesson_id::text,
          new.student_id::text,new.business_entity_id::text,
          coalesce(new.teacher_id::text,'<NULL>'),coalesce(new.subject_id::text,'<NULL>'),
          new.year_month,new.teacher_settlement_month,new.lesson_date::text,
          new.lesson_type,new.app_type)) is distinct from v_evidence.actual_identity_md5
    ) then raise exception 'R1D_E_B2_LEGACY_ACTUAL_ATTRIBUTION_IMMUTABLE'; end if;
    if not v_is_exact_correction and
       (to_jsonb(new)-array['note','lesson_content','lesson_delivery_mode','lesson_venue','updated_at'])
       is distinct from
       (to_jsonb(old)-array['note','lesson_content','lesson_delivery_mode','lesson_venue','updated_at']) then
      raise exception 'R1D_E_B2_LEGACY_ACTUAL_ONLY_NONATTRIBUTION_CONTENT_EDIT_ALLOWED';
    end if;
    v_student_month:=v_evidence.legacy_year_month;
    v_old_teacher_month:=v_evidence.teacher_settlement_month_snapshot;
    v_new_teacher_month:=v_old_teacher_month;
  else
    if old.student_settlement_month is null
       or new.student_settlement_month is distinct from old.student_settlement_month
       or num_nonnulls(new.billing_month,new.billing_week_start_date,
            new.billing_month_source,new.billing_month_decided_at)<>0 then
      raise exception 'R1D_E_B2_CANONICAL_ACTUAL_STUDENT_MONTH_IMMUTABLE';
    end if;
    v_student_month:=public.school_resolve_r1d_e_b2_actual_student_month(old.planned_lesson_id);
    if v_student_month is distinct from old.student_settlement_month then
      raise exception 'R1D_E_B2_CANONICAL_ACTUAL_SOURCE_MONTH_DRIFT';
    end if;
    new.year_month:=old.student_settlement_month;
    new.teacher_settlement_month:=to_char(new.lesson_date,'YYYY-MM');
    v_old_teacher_month:=old.teacher_settlement_month;
    v_new_teacher_month:=new.teacher_settlement_month;
  end if;

  if exists(select 1 from public.school_student_monthly_settlements s
    where s.student_id=old.student_id
      and s.business_entity_id is not distinct from old.business_entity_id
      and s.year_month=v_student_month and s.settlement_status='locked')
    and not v_is_sun_exact_void then
    raise exception 'R1D_E_B2_STUDENT_SETTLEMENT_LOCKED';
  end if;
  if exists(select 1 from public.school_teacher_wage_lock_details d
    join public.school_teacher_wage_locks w on w.id=d.lock_id
    where d.lesson_record_id=old.id and w.status='locked' and w.voided_at is null) then
    raise exception 'R1D_E_B2_ACTIVE_WAGE_DETAIL_LOCKED';
  end if;
  if exists(select 1 from public.school_teacher_wage_locks w
       where w.teacher_id=old.teacher_id
         and w.business_entity_id is not distinct from old.business_entity_id
         and w.settlement_month=v_old_teacher_month and w.status='locked')
     or exists(select 1 from public.school_teacher_wage_locks w
       where w.teacher_id=new.teacher_id
         and w.business_entity_id is not distinct from new.business_entity_id
         and w.settlement_month=v_new_teacher_month and w.status='locked') then
    raise exception 'R1D_E_B2_TEACHER_WAGE_MONTH_LOCKED';
  end if;
  return new;
end
$function$;

-- The generic cancellation contract remains locked. This branch can only run
-- inside the exact writer after the exact wrong actual has been soft-voided.
do $patch_cancel_writer$
declare
  v_definition text;
  v_old_decl text:='  v_student_business_entity_id uuid;';
  v_new_decl text:=$new$  v_student_business_entity_id uuid;
  v_is_exact_correction boolean:=false;$new$;
  v_old_context text:=$old$  if v_planned.voided_at is not null then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_SOURCE_VOIDED';
  end if;

  if exists ($old$;
  v_new_context text:=$new$  if v_planned.voided_at is not null then
    raise exception using errcode='22023', message='LESSON_CANCELLATION_SOURCE_VOIDED';
  end if;

  v_is_exact_correction:=
    current_setting('app.sun_chenfeng_exact_correction_context',true)
      ='sun_chenfeng_20260811_makeup_v1_20260816'
    and current_setting('app.sun_chenfeng_exact_correction_action',true)
      ='void_cancel_makeup'
    and current_setting('app.sun_chenfeng_exact_correction_actor',true)=v_actor::text
    and v_actor='25331ae9-3412-48b9-bdc3-e516caeaeba4'::uuid
    and v_membership_role='admin' and v_membership_active
    and v_planned.id='8b737b58-cd14-42c5-afd2-34730dcef963'::uuid
    and md5(to_jsonb(v_planned)::text)='07296184e3ffaf443f89109e2b54d9b9'
    and exists(select 1 from public.school_lesson_records a
      where a.id='c8e6cf21-850c-4700-af9e-7ebf3c2a577d'::uuid
        and a.planned_lesson_id=v_planned.id
        and a.voided_at is not null
        and a.void_reason=
          '孙陈锋2026-08-01实际缺课；纠正错误ordinary actual并转待补，2026-08-11由田宇辰完成非计费补课；actor_user_id=25331ae9-3412-48b9-bdc3-e516caeaeba4'
        and md5((to_jsonb(a)-array['voided_at','void_reason','updated_at'])::text)
          ='7f323ee2df53e2e990bd22e71534acb6');

  if exists ($new$;
  v_old_link text:=$old$      and actual.planned_lesson_id = v_planned.id
  ) then$old$;
  v_new_link text:=$new$      and actual.planned_lesson_id = v_planned.id
      and actual.voided_at is null
  ) then$new$;
  v_old_financial text:=$old$  if exists (
    select 1
    from public.school_student_monthly_settlements settlement
    where settlement.student_id = v_planned.student_id
      and settlement.year_month = v_student_settlement_month
      and settlement.business_entity_id is not distinct from v_planned.business_entity_id
      and public.school_tuition_p0a_consumed_bill_id(settlement.id) is not null
  ) then$old$;
  v_new_financial text:=$new$  if not v_is_exact_correction and exists (
    select 1
    from public.school_student_monthly_settlements settlement
    where settlement.student_id = v_planned.student_id
      and settlement.year_month = v_student_settlement_month
      and settlement.business_entity_id is not distinct from v_planned.business_entity_id
      and public.school_tuition_p0a_consumed_bill_id(settlement.id) is not null
  ) then$new$;
  v_old_locked text:=$old$  if exists (
    select 1
    from public.school_student_monthly_settlements settlement
    where settlement.student_id = v_planned.student_id
      and settlement.year_month = v_student_settlement_month
      and settlement.business_entity_id is not distinct from v_planned.business_entity_id
      and settlement.settlement_status = 'locked'
  ) then$old$;
  v_new_locked text:=$new$  if not v_is_exact_correction and exists (
    select 1
    from public.school_student_monthly_settlements settlement
    where settlement.student_id = v_planned.student_id
      and settlement.year_month = v_student_settlement_month
      and settlement.business_entity_id is not distinct from v_planned.business_entity_id
      and settlement.settlement_status = 'locked'
  ) then$new$;
begin
  select pg_get_functiondef(
    'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure
  ) into strict v_definition;
  if md5(v_definition)<>'73ac1abeebb6ce82870f9e0f8240629b'
     or position(v_old_decl in v_definition)=0
     or position(v_old_context in v_definition)=0
     or position(v_old_link in v_definition)=0
     or position(v_old_financial in v_definition)=0
     or position(v_old_locked in v_definition)=0 then
    raise exception 'SUN_CHENFENG_CANCEL_PATCH_SOURCE_DRIFT';
  end if;
  v_definition:=replace(v_definition,v_old_decl,v_new_decl);
  v_definition:=replace(v_definition,v_old_context,v_new_context);
  v_definition:=replace(v_definition,v_old_link,v_new_link);
  v_definition:=replace(v_definition,v_old_financial,v_new_financial);
  v_definition:=replace(v_definition,v_old_locked,v_new_locked);
  execute v_definition;
end;
$patch_cancel_writer$;

create or replace function public.school_correct_sun_chenfeng_20260811_makeup_v1(
  p_expected_planned_updated_at timestamptz,
  p_expected_actual_updated_at timestamptz,
  p_reason text,
  p_confirmation text
)
returns table(
  planned_lesson_id uuid,
  voided_actual_id uuid,
  cancelled_actual_id uuid,
  makeup_actual_id uuid,
  actor_user_id uuid,
  remaining_makeup_hours numeric,
  teacher_settlement_month text,
  lesson_wage_jpy numeric,
  message text
)
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_actor uuid;
  v_planned public.school_lesson_records%rowtype;
  v_wrong public.school_lesson_records%rowtype;
  v_cancelled_id uuid;
  v_makeup_id uuid;
  v_reason constant text:=
    '孙陈锋2026-08-01实际缺课；纠正错误ordinary actual并转待补，2026-08-11由田宇辰完成非计费补课；actor_user_id=25331ae9-3412-48b9-bdc3-e516caeaeba4';
  v_note text;
  v_candidate_count integer;
  v_candidate_wage numeric;
  v_new_wage numeric;
begin
  v_actor:=public.school_require_current_app_admin();
  if v_actor is distinct from '25331ae9-3412-48b9-bdc3-e516caeaeba4'::uuid then
    raise exception using errcode='42501',message='SUN_CHENFENG_CORRECTION_ACTOR_MISMATCH';
  end if;
  if p_confirmation is distinct from 'CORRECT_SUN_CHENFENG_20260811_MAKEUP'
     or p_reason is distinct from v_reason then
    raise exception using errcode='22023',message='SUN_CHENFENG_CORRECTION_CONFIRMATION_MISMATCH';
  end if;
  if p_expected_planned_updated_at is distinct from
       '2026-08-01 14:02:23.647108+00'::timestamptz
     or p_expected_actual_updated_at is distinct from
       '2026-07-31 15:51:01.478823+00'::timestamptz then
    raise exception using errcode='40001',message='SUN_CHENFENG_CORRECTION_EXPECTED_VERSION_MISMATCH';
  end if;

  perform public.school_tuition_p0b1_lock_existing_lesson_scope(
    '8b737b58-cd14-42c5-afd2-34730dcef963'::uuid);
  select l.* into strict v_planned from public.school_lesson_records l
  where l.id='8b737b58-cd14-42c5-afd2-34730dcef963'::uuid for update;
  select l.* into strict v_wrong from public.school_lesson_records l
  where l.id='c8e6cf21-850c-4700-af9e-7ebf3c2a577d'::uuid for update;

  if v_planned.updated_at is distinct from p_expected_planned_updated_at
     or v_wrong.updated_at is distinct from p_expected_actual_updated_at
     or md5(to_jsonb(v_planned)::text)<>'07296184e3ffaf443f89109e2b54d9b9'
     or md5(to_jsonb(v_wrong)::text)<>'1086af5afd9a91d3a6a03b2d5b9cc458'
     or v_planned.id is distinct from v_wrong.planned_lesson_id
     or v_planned.lesson_date<>'2026-08-01'::date
     or v_planned.start_time<>'13:00' or v_planned.end_time<>'15:00'
     or v_planned.duration_hours<>2 or v_planned.lesson_fee<>17000
     or v_planned.student_settlement_month<>'2026-07'
     or v_planned.student_id<>'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid
     or v_planned.teacher_id<>'edaf30da-1315-4455-99d1-ead1b7147662'::uuid
     or v_planned.subject_id<>'14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid
     or v_planned.business_entity_id<>'2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid
     or v_planned.status<>'planned' or v_planned.voided_at is not null
     or v_wrong.status<>'completed' or v_wrong.is_billable is not true
     or v_wrong.lesson_fee<>17000 or v_wrong.actual_minutes<>120
     or v_wrong.voided_at is not null then
    raise exception using errcode='55000',message='SUN_CHENFENG_CORRECTION_TARGET_DRIFT';
  end if;

  perform 1 from public.school_student_monthly_settlements s
  where s.id='5e0a23ff-0e1e-48c6-9866-5fc335b3e42d'::uuid for share;
  perform 1 from public.school_student_tuition_bills b
  where b.id='2a9f1c25-a060-461e-ae10-b02295dec381'::uuid for share;
  perform 1 from public.school_student_tuition_generation_revisions r
  where r.id='96000000-0000-4000-8000-202608031005'::uuid for share;
  perform 1 from public.school_income_records i
  where i.id='468ab75b-312e-4ba0-8d8d-8ae2f6ace00e'::uuid for share;
  perform 1 from public.school_personal_cash_income_linkage_events e
  where e.id='43256fb6-3f6e-41f7-9802-1d1c42a3f2c5'::uuid for share;

  if (select md5(to_jsonb(s)::text) from public.school_student_monthly_settlements s
      where s.id='5e0a23ff-0e1e-48c6-9866-5fc335b3e42d'::uuid)
       is distinct from 'c96670560d491a82b552b32492cd1a55'
     or (select md5(to_jsonb(b)::text) from public.school_student_tuition_bills b
      where b.id='2a9f1c25-a060-461e-ae10-b02295dec381'::uuid)
       is distinct from 'e6f0b5df93101ea1c9f07c9c7aea0e07'
     or (select md5(to_jsonb(bl)::text) from public.school_student_tuition_bill_lessons bl
      where bl.id='ac2caa48-aaeb-c039-19ac-3b3779beb3bf'::uuid)
       is distinct from '355b2c378a9f2d20d03facfbbbe24079'
     or (select md5(to_jsonb(r)::text) from public.school_student_tuition_generation_revisions r
      where r.id='96000000-0000-4000-8000-202608031005'::uuid)
       is distinct from 'cf30373f4e86abe1568c8516ae0c4a7c'
     or (select md5(to_jsonb(i)::text) from public.school_income_records i
      where i.id='468ab75b-312e-4ba0-8d8d-8ae2f6ace00e'::uuid)
       is distinct from '88cd48e56ce1b8637625d0b6b2a22993'
     or (select md5(to_jsonb(e)::text) from public.school_personal_cash_income_linkage_events e
      where e.id='43256fb6-3f6e-41f7-9802-1d1c42a3f2c5'::uuid)
       is distinct from '8ce313f76c78e838d23425ce74801983' then
    raise exception using errcode='55000',message='SUN_CHENFENG_CORRECTION_FINANCE_DRIFT';
  end if;

  if (select count(*) from public.school_lesson_records a
      where a.planned_lesson_id=v_planned.id and a.voided_at is null)<>1
     or public.school_get_lesson_credit_remaining_hours(v_planned.id)<>0
     or (select md5(to_jsonb(l)::text) from public.school_lesson_records l
       where l.id='6722e5a8-d7a1-453a-93a8-9cbaab227378'::uuid)
        is distinct from '94050771268fa97cda680affb81e9364'
     or public.school_get_lesson_credit_remaining_hours(
       '6722e5a8-d7a1-453a-93a8-9cbaab227378'::uuid)<>2
     or exists(select 1 from public.school_teacher_wage_locks w
       where w.teacher_id=v_planned.teacher_id
         and w.business_entity_id=v_planned.business_entity_id
         and w.settlement_month='2026-08' and w.status='locked')
     or exists(select 1 from public.school_teacher_wage_lock_details d
       where d.lesson_record_id=v_wrong.id) then
    raise exception using errcode='55000',message='SUN_CHENFENG_CORRECTION_DOWNSTREAM_DRIFT';
  end if;

  perform set_config('app.sun_chenfeng_exact_correction_context',
    'sun_chenfeng_20260811_makeup_v1_20260816',true);
  perform set_config('app.sun_chenfeng_exact_correction_action','void_cancel_makeup',true);
  perform set_config('app.sun_chenfeng_exact_correction_actor',v_actor::text,true);

  update public.school_lesson_records l
  set voided_at=transaction_timestamp(),void_reason=v_reason
  where l.id=v_wrong.id
    and l.updated_at=p_expected_actual_updated_at
    and md5(to_jsonb(l)::text)='1086af5afd9a91d3a6a03b2d5b9cc458';
  if not found then
    raise exception using errcode='40001',message='SUN_CHENFENG_CORRECTION_VOID_CONFLICT';
  end if;

  v_note:=format('孙陈锋2026-08-01缺课转待补；correction_batch=sun_chenfeng_20260811_makeup_v1_20260816;actor=%s',v_actor);
  select c.lesson_id into strict v_cancelled_id
  from public.school_create_cancelled_actual_lesson_from_planned(
    v_planned.id,'2026-08-01','13:00','15:00',2,8500,1,'EJU物理',v_note
  ) c;

  select m.id into strict v_makeup_id
  from public.school_create_lesson_credit_makeup_actual(
    v_planned.id,'2026-08-11',v_planned.teacher_id,v_planned.subject_id,
    '13:00','15:00',2,'简谐+万有引力',
    format('孙陈锋2026-08-11非计费补课；source=%s;actor=%s',v_planned.id,v_actor),
    1,'onsite','Regus办公室'
  ) m;

  if (select count(*) from public.school_lesson_records a
      where a.planned_lesson_id=v_planned.id and a.voided_at is null)<>2
     or not exists(select 1 from public.school_lesson_records a
       where a.id=v_cancelled_id and a.status='cancelled'
         and a.lesson_date='2026-08-01' and a.start_time='13:00' and a.end_time='15:00'
         and a.actual_minutes=0 and not a.is_billable and a.lesson_fee=0
         and a.student_settlement_month='2026-07' and a.teacher_settlement_month='2026-08')
     or not exists(select 1 from public.school_lesson_records a
       where a.id=v_makeup_id and a.status='makeup_completed'
         and a.lesson_date='2026-08-11' and a.start_time='13:00' and a.end_time='15:00'
         and a.actual_minutes=120 and not a.is_billable and a.lesson_fee=0
         and a.lesson_content='简谐+万有引力'
         and a.student_settlement_month='2026-07' and a.teacher_settlement_month='2026-08')
     or public.school_get_lesson_credit_remaining_hours(v_planned.id)<>0
     or (select md5(to_jsonb(l)::text) from public.school_lesson_records l
       where l.id='6722e5a8-d7a1-453a-93a8-9cbaab227378'::uuid)
        is distinct from '94050771268fa97cda680affb81e9364' then
    raise exception using errcode='55000',message='SUN_CHENFENG_CORRECTION_POSTWRITE_INVARIANT_FAILED';
  end if;

  select count(*),coalesce(sum(c.lesson_wage_jpy),0),
         max(c.lesson_wage_jpy) filter(where c.lesson_record_id=v_makeup_id)
  into v_candidate_count,v_candidate_wage,v_new_wage
  from public.school_get_teacher_monthly_wage_generation_candidate_facts(
    '2026-08',v_planned.teacher_id,v_planned.business_entity_id
  ) c;
  if v_candidate_count<>5 or v_candidate_wage<>40000 or v_new_wage<>8000
     or exists(select 1 from public.school_get_teacher_monthly_wage_generation_candidate_facts(
       '2026-08',v_planned.teacher_id,v_planned.business_entity_id) c
       where c.lesson_record_id=v_wrong.id) then
    raise exception using errcode='55000',message='SUN_CHENFENG_CORRECTION_WAGE_DUPLICATION';
  end if;

  if (select md5(to_jsonb(s)::text) from public.school_student_monthly_settlements s
      where s.id='5e0a23ff-0e1e-48c6-9866-5fc335b3e42d'::uuid)
       is distinct from 'c96670560d491a82b552b32492cd1a55'
     or (select md5(to_jsonb(b)::text) from public.school_student_tuition_bills b
      where b.id='2a9f1c25-a060-461e-ae10-b02295dec381'::uuid)
       is distinct from 'e6f0b5df93101ea1c9f07c9c7aea0e07'
     or (select md5(to_jsonb(r)::text) from public.school_student_tuition_generation_revisions r
      where r.id='96000000-0000-4000-8000-202608031005'::uuid)
       is distinct from 'cf30373f4e86abe1568c8516ae0c4a7c'
     or (select md5(to_jsonb(i)::text) from public.school_income_records i
      where i.id='468ab75b-312e-4ba0-8d8d-8ae2f6ace00e'::uuid)
       is distinct from '88cd48e56ce1b8637625d0b6b2a22993'
     or (select md5(to_jsonb(e)::text) from public.school_personal_cash_income_linkage_events e
      where e.id='43256fb6-3f6e-41f7-9802-1d1c42a3f2c5'::uuid)
       is distinct from '8ce313f76c78e838d23425ce74801983' then
    raise exception using errcode='55000',message='SUN_CHENFENG_CORRECTION_FINANCE_CHANGED';
  end if;

  return query select v_planned.id,v_wrong.id,v_cancelled_id,v_makeup_id,
    v_actor,0::numeric,'2026-08'::text,v_new_wage,
    'SUN_CHENFENG_20260811_MAKEUP_CORRECTION_COMPLETED'::text;
end
$function$;

revoke all on function public.school_correct_sun_chenfeng_20260811_makeup_v1(
  timestamptz,timestamptz,text,text
) from public,anon,authenticated,service_role;

comment on function public.school_correct_sun_chenfeng_20260811_makeup_v1(
  timestamptz,timestamptz,text,text
) is
  'Owner-only exact one-shot correction for planned 8b737b58 and wrong actual c8e6cf21 only. Soft-voids the wrong actual, delegates absence/pending_makeup and fee-zero 2026-08-11 fulfilment to canonical writers, and pins all tuition/Cash-link/wage invariants.';

revoke all on function public.school_enforce_r1d_e_b2_actual_attribution()
  from public,anon,authenticated,service_role;
revoke all on function public.school_create_lesson_credit_makeup_actual(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) from public,anon,authenticated,service_role;
grant execute on function public.school_create_lesson_credit_makeup_actual(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) to authenticated;
revoke all on function public.school_create_cancelled_actual_lesson_from_planned(
  uuid,date,text,text,numeric,numeric,integer,text,text
) from public,anon,authenticated,service_role;
grant execute on function public.school_create_cancelled_actual_lesson_from_planned(
  uuid,date,text,text,numeric,numeric,integer,text,text
) to authenticated;

notify pgrst,'reload schema';
\if :{?sun_chenfeng_caller_transaction}
select 'LOCKED_BILLING_MONTH_NONBILLING_MAKEUP_APPLIED_IN_CALLER_TRANSACTION' result;
\elif :{?sun_chenfeng_rehearsal}
rollback;
select 'LOCKED_BILLING_MONTH_NONBILLING_MAKEUP_REHEARSAL_ROLLED_BACK' result;
\else
commit;
select 'LOCKED_BILLING_MONTH_NONBILLING_MAKEUP_AND_EXACT_CORRECTION_DEPLOYED' result;
\endif
