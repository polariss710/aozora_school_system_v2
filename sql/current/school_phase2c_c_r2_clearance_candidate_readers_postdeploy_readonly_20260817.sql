-- Phase 2C-C-R2 production postdeploy acceptance. Reader calls only.
\set ON_ERROR_STOP on
\pset pager off
begin transaction read only;

do $catalog$
declare v_signature regprocedure;
begin
  foreach v_signature in array array[
    'public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean)'::regprocedure,
    'public.school_list_lesson_clearance_available_overages_v2(uuid,boolean)'::regprocedure,
    'public.school_list_student_package_credit_lots_v2(uuid)'::regprocedure,
    'public.school_list_cross_month_makeup_projection_v2(uuid,text)'::regprocedure,
    'public.school_get_lesson_clearance_dashboard_summary_v1(uuid)'::regprocedure
  ] loop
    if exists(select 1 from pg_proc function_row where function_row.oid=v_signature
      and (pg_get_userbyid(function_row.proowner)<>'postgres'
        or not function_row.prosecdef or function_row.provolatile<>'s'
        or function_row.proconfig is distinct from array['search_path=pg_catalog, public'])) then
      raise exception 'PHASE2C_C_R2_POSTDEPLOY_SECURITY_INVALID:%',v_signature;
    end if;
    if not has_function_privilege('authenticated',v_signature,'EXECUTE')
       or has_function_privilege('anon',v_signature,'EXECUTE')
       or has_function_privilege('service_role',v_signature,'EXECUTE') then
      raise exception 'PHASE2C_C_R2_POSTDEPLOY_ACL_INVALID:%',v_signature;
    end if;
  end loop;
  if md5(pg_get_functiondef(
      'public.school_list_lesson_clearance_pending_balances(uuid,boolean)'::regprocedure
    ))<>'59dcc6bdbc72488c5f0f25dfcdd7b7bc'
     or md5(pg_get_functiondef(
      'public.school_list_lesson_clearance_available_overages(uuid,boolean)'::regprocedure
    ))<>'c7c1c5c2c9e2e36a2587476b063a192e'
     or md5(pg_get_functiondef(
      'public.school_list_student_package_credit_lots(uuid)'::regprocedure
    ))<>'ed3645856732070335827b4329dfecf0'
     or md5(pg_get_functiondef(
      'public.school_list_cross_month_makeup_projection(uuid,text)'::regprocedure
    ))<>'9008b9e1bf2c42953ce05cb2ae343517'
     or md5(pg_get_functiondef(
      'public.school_preview_lesson_clearance_v2(uuid,text,uuid,uuid,integer,date,text,text,text,text)'::regprocedure
    ))<>'ffeab2952a86c3c40d39cd3a5c806e19'
     or md5(pg_get_functiondef(
      'public.school_list_lesson_clearance_history_v2(uuid)'::regprocedure
    ))<>'0f0068b523ca6c1c142b6ae55b41bc4d'
     or md5(pg_get_functiondef(
      'public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)'::regprocedure
    ))<>'f3706ef036a48de97a187c5e0d4e8e40'
     or md5(pg_get_functiondef(
      'public.school_reverse_lesson_clearance(uuid,date,text,text)'::regprocedure
    ))<>'07aefc153a1b2f9f2faacbf28f29447f' then
    raise exception 'PHASE2C_C_R2_POSTDEPLOY_DEPENDENCY_DRIFT';
  end if;
end
$catalog$;

select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub',(select membership.user_id
    from public.school_app_memberships membership
    where membership.is_active and membership.role='admin'
    order by membership.created_at,membership.user_id limit 1),
    'role','authenticated')::text,true
);

do $payload$
declare
  v_pending jsonb;
  v_overage jsonb;
  v_package jsonb;
  v_cross jsonb;
  v_summary jsonb;
  v_item jsonb;
begin
  v_pending:=public.school_list_lesson_clearance_pending_balances_v2(null,false);
  v_overage:=public.school_list_lesson_clearance_available_overages_v2(null,false);
  v_package:=public.school_list_student_package_credit_lots_v2(null);
  v_cross:=public.school_list_cross_month_makeup_projection_v2(null,null);
  v_summary:=public.school_get_lesson_clearance_dashboard_summary_v1(null);

  if v_pending->>'contract_version'<>'lesson_clearance_pending_balances_v2'
     or (v_pending->'summary'->>'source_count')::int<>21
     or (v_pending->'summary'->>'remaining_minutes')::int<>2400
     or jsonb_array_length(v_pending->'items')<>21 then
    raise exception 'PHASE2C_C_R2_POSTDEPLOY_PENDING_BASELINE_INVALID:%',v_pending->'summary';
  end if;
  for v_item in select value from jsonb_array_elements(v_pending->'items') loop
    if not v_item ?& array[
      'pending_source_planned_id','student_id','student_display_name',
      'business_entity_id','business_entity_display_name','teacher_id',
      'teacher_display_name','subject_id','subject_display_name',
      'source_lesson_date','source_year_month','initial_credit_minutes',
      'makeup_consumed_minutes','clearance_allocated_minutes',
      'clearance_reversed_minutes','active_claimed_minutes','remaining_minutes',
      'currently_allocatable_minutes','unit_price_jpy','initial_amount_jpy',
      'remaining_amount_jpy','active_claimed','is_locked','can_be_candidate',
      'candidate_blocker_code','evidence_status','source_row_md5',
      'credit_origin_sort_at','credit_origin_sort_source','fifo_rank',
      'balance_matches_writer_helper'
    ] or not (v_item->>'balance_matches_writer_helper')::boolean then
      raise exception 'PHASE2C_C_R2_POSTDEPLOY_PENDING_FIELD_INVALID:%',v_item;
    end if;
    if v_item->>'package_classification'<>'ordinary_makeup_credit' then
      raise exception 'PHASE2C_C_R2_POSTDEPLOY_PACKAGE_LEAK:%',v_item;
    end if;
  end loop;

  if v_overage->>'contract_version'<>'lesson_clearance_available_overages_v2'
     or (v_overage->'summary'->>'source_count')::int<>4
     or (v_overage->'summary'->>'available_minutes')::int<>135
     or jsonb_array_length(v_overage->'items')<>4 then
    raise exception 'PHASE2C_C_R2_POSTDEPLOY_OVERAGE_BASELINE_INVALID:%',v_overage->'summary';
  end if;
  for v_item in select value from jsonb_array_elements(v_overage->'items') loop
    if not v_item ?& array[
      'overtime_source_actual_id','linked_planned_lesson_id','student_id',
      'student_display_name','business_entity_id','business_entity_display_name',
      'teacher_id','teacher_display_name','subject_id','subject_display_name',
      'actual_lesson_date','actual_start_time','actual_end_time',
      'student_settlement_month','teacher_wage_month','overage_policy_version',
      'overage_source','frozen_overtime_minutes','active_claimed_minutes',
      'clearance_allocated_minutes','clearance_reversed_minutes',
      'available_minutes','currently_allocatable_minutes','unit_price_jpy',
      'frozen_amount_jpy','available_amount_jpy','active_claimed','is_locked',
      'can_be_candidate','candidate_blocker_code','evidence_status',
      'source_row_md5','display_rank','balance_matches_writer_helper'
    ] or not (v_item->>'balance_matches_writer_helper')::boolean then
      raise exception 'PHASE2C_C_R2_POSTDEPLOY_OVERAGE_FIELD_INVALID:%',v_item;
    end if;
  end loop;

  if v_package->>'contract_version'<>'student_package_credit_lots_v2'
     or (v_package->'summary'->>'lot_count')::int<>1
     or (v_package->'summary'->>'initial_minutes')::int<>1200
     or (v_package->'summary'->>'consumed_minutes')::int<>0
     or (v_package->'summary'->>'remaining_minutes')::int<>1200 then
    raise exception 'PHASE2C_C_R2_POSTDEPLOY_PACKAGE_BASELINE_INVALID:%',v_package;
  end if;
  v_item:=v_package->'items'->0;
  if v_item->>'package_business_type'<>'package_credit'
     or v_item->>'package_display_label'<>'套餐余额'
     or (v_item->>'can_consume')::boolean or (v_item->>'can_reserve')::boolean
     or not (v_item->>'read_only')::boolean then
    raise exception 'PHASE2C_C_R2_POSTDEPLOY_PACKAGE_CAPABILITY_INVALID:%',v_item;
  end if;

  if v_cross->>'contract_version'<>'cross_month_makeup_projection_v2'
     or (v_cross->'summary'->>'distinct_actual_count')::int<>16
     or jsonb_array_length(v_cross->'items')<>16
     or exists(select 1 from jsonb_array_elements(v_cross->'items') item
       group by item->>'actual_lesson_id' having count(*)>1) then
    raise exception 'PHASE2C_C_R2_POSTDEPLOY_CROSS_IDENTITY_INVALID:%',v_cross->'summary';
  end if;
  for v_item in select value from jsonb_array_elements(v_cross->'items') loop
    if not v_item ?& array[
      'actual_lesson_id','source_planned_lesson_id','student_id',
      'student_display_name','business_entity_id','business_entity_display_name',
      'source_month','actual_month','source_lesson_date','actual_lesson_date',
      'actual_start_time','actual_end_time','actual_minutes',
      'source_teacher_id','source_teacher_display_name','actual_teacher_id',
      'actual_teacher_display_name','source_subject_id','source_subject_display_name',
      'actual_subject_id','actual_subject_display_name','student_settlement_month',
      'teacher_wage_month','status','source_view_year_month',
      'source_view_lesson_id','actual_view_year_month','actual_view_lesson_id',
      'view_mode','evidence_status','source_row_md5','actual_row_md5'
    ] or v_item->>'actual_lesson_id'<>v_item->>'actual_view_lesson_id' then
      raise exception 'PHASE2C_C_R2_POSTDEPLOY_CROSS_FIELD_INVALID:%',v_item;
    end if;
  end loop;

  if (v_summary->>'pending_source_count')::int<>21
     or (v_summary->>'pending_remaining_minutes')::int<>2400
     or (v_summary->>'overage_source_count')::int<>4
     or (v_summary->>'available_overtime_minutes')::int<>135
     or (v_summary->>'package_lot_count')::int<>1
     or (v_summary->>'package_remaining_minutes')::int<>1200
     or (v_summary->>'history_count')::int<>0 then
    raise exception 'PHASE2C_C_R2_POSTDEPLOY_SUMMARY_INVALID:%',v_summary;
  end if;
  if exists(select 1 from public.school_lesson_clearances)
     or exists(select 1 from public.school_lesson_clearance_details) then
    raise exception 'PHASE2C_C_R2_POSTDEPLOY_CLEARANCE_ROWS_CHANGED';
  end if;
end
$payload$;

select p.oid::regprocedure signature,md5(pg_get_functiondef(p.oid)) definition_md5,
  pg_get_userbyid(p.proowner) owner,p.prosecdef security_definer,p.proconfig,p.proacl
from pg_proc p where p.oid in (
  'public.school_list_lesson_clearance_pending_balances_v2(uuid,boolean)'::regprocedure,
  'public.school_list_lesson_clearance_available_overages_v2(uuid,boolean)'::regprocedure,
  'public.school_list_student_package_credit_lots_v2(uuid)'::regprocedure,
  'public.school_list_cross_month_makeup_projection_v2(uuid,text)'::regprocedure,
  'public.school_get_lesson_clearance_dashboard_summary_v1(uuid)'::regprocedure
) order by 1;

select jsonb_pretty(public.school_list_lesson_clearance_pending_balances_v2(
  null,false)->'items'->0) pending_json_sample;
select jsonb_pretty(public.school_list_lesson_clearance_available_overages_v2(
  null,false)->'items'->0) overage_json_sample;
select jsonb_pretty(public.school_list_student_package_credit_lots_v2(
  null)->'items'->0) package_json_sample;
select jsonb_pretty(public.school_list_cross_month_makeup_projection_v2(
  null,null)->'items'->0) cross_month_json_sample;
select jsonb_pretty(public.school_get_lesson_clearance_dashboard_summary_v1(
  null)) dashboard_summary;

explain (analyze,buffers,summary,format text)
select public.school_list_lesson_clearance_pending_balances_v2(null,false);
explain (analyze,buffers,summary,format text)
select public.school_list_lesson_clearance_available_overages_v2(null,false);
explain (analyze,buffers,summary,format text)
select public.school_list_cross_month_makeup_projection_v2(null,null);

rollback;
