-- Production read-only postdeploy assertions for wage candidate effective display.
\set ON_ERROR_STOP on
begin transaction isolation level repeatable read read only;

do $assert$
declare
  v jsonb;
  v_aug jsonb;
begin
  if not has_function_privilege('authenticated','public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)','EXECUTE')
     or has_function_privilege('anon','public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)','EXECUTE')
     or has_function_privilege('service_role','public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)','EXECUTE')
     or exists (
       select 1
       from pg_proc p
       cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
       where p.oid='public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)'::regprocedure
         and a.grantee=0 and a.privilege_type='EXECUTE'
     ) then
    raise exception 'WAGE_EFFECTIVE_DISPLAY_POSTDEPLOY_ACL_FAILED';
  end if;
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.oid='public.school_get_teacher_monthly_wage_generation_preflight(text,uuid,uuid)'::regprocedure
      and p.prosecdef and p.provolatile='s'
      and p.proconfig @> array['search_path=pg_catalog, public']
  ) then
    raise exception 'WAGE_EFFECTIVE_DISPLAY_POSTDEPLOY_FUNCTION_SECURITY_FAILED';
  end if;

  perform set_config('request.jwt.claims','{"sub":"25331ae9-3412-48b9-bdc3-e516caeaeba4","role":"authenticated"}',true);
  v := public.school_get_teacher_monthly_wage_generation_preflight(
    '2026-07', null, '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
  );
  if jsonb_array_length(v->'candidate_prerequisites') <> 56
     or (select count(distinct x->>'lesson_record_id') from jsonb_array_elements(v->'candidate_prerequisites') x) <> 56
     or (select count(*) from jsonb_array_elements(v->'candidate_prerequisites') x where (x->>'prerequisite_satisfied')::boolean) <> 56
     or (select count(*) from jsonb_array_elements(v->'candidate_prerequisites') x where x->>'prerequisite_status'='no_wage_not_required') <> 11
     or (v->'summary'->>'blocker_count')::integer <> 0
     or (v->'summary'->>'active_wage_lock_count')::integer <> 8
     or (v->'summary'->>'existing_wage_detail_count')::integer <> 56
     or (v->'summary'->>'conditional_pay_hours')::numeric <> 90.5
     or (v->'summary'->>'conditional_amount_jpy')::numeric <> 410750 then
    raise exception 'WAGE_EFFECTIVE_DISPLAY_POSTDEPLOY_FACT_FAILED';
  end if;
  v_aug := public.school_get_teacher_monthly_wage_generation_preflight('2026-08',null,null);
  if (v_aug->'summary'->>'blocker_count')::integer <= 0
     or (select count(*) from jsonb_array_elements(v_aug->'candidate_prerequisites') x where not (x->>'prerequisite_satisfied')::boolean)
        <> (v_aug->'summary'->>'blocker_count')::integer then
    raise exception 'WAGE_EFFECTIVE_DISPLAY_POSTDEPLOY_REAL_BLOCKER_FAILED';
  end if;
  if (select count(*) from public.school_teacher_wage_locks where settlement_month='2026-07' and status='locked' and voided_at is null) <> 8
     or (select count(*) from public.school_teacher_wage_lock_details d join public.school_teacher_wage_locks w on w.id=d.lock_id where w.settlement_month='2026-07' and w.status='locked' and w.voided_at is null) <> 56
     or (select coalesce(sum(total_jpy),0) from public.school_teacher_wage_locks where settlement_month='2026-07' and status='locked' and voided_at is null) <> 410750
     or (select count(*) from public.school_student_monthly_settlement_historical_completion_evidence) <> 4 then
    raise exception 'WAGE_EFFECTIVE_DISPLAY_POSTDEPLOY_INVARIANT_FAILED';
  end if;
end
$assert$;

select feature_key,state
from public.school_feature_gates
where feature_key in ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit')
order by feature_key;

rollback;
