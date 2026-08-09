-- Rehearse the read-only preflight extension and role boundary, then restore the deployed definition.
\set ON_ERROR_STOP on
begin;
\ir school_wage_candidate_effective_display_reader_20260809.sql

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"25331ae9-3412-48b9-bdc3-e516caeaeba4","role":"authenticated"}',true);

do $assert$
declare
  v jsonb;
  v_aug jsonb;
begin
  v := public.school_get_teacher_monthly_wage_generation_preflight(
    '2026-07', null, '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
  );
  if jsonb_array_length(v->'candidate_prerequisites') <> 56
     or (select count(distinct x->>'lesson_record_id') from jsonb_array_elements(v->'candidate_prerequisites') x) <> 56
     or (select count(*) from jsonb_array_elements(v->'candidate_prerequisites') x where (x->>'prerequisite_satisfied')::boolean) <> 56
     or (select count(*) from jsonb_array_elements(v->'candidate_prerequisites') x where x->>'prerequisite_status'='no_wage_not_required') <> 11
     or (v->'summary'->>'blocker_count')::integer <> 0
     or (v->'summary'->>'existing_wage_detail_count')::integer <> 56 then
    raise exception 'WAGE_EFFECTIVE_DISPLAY_REHEARSAL_FACT_FAILED';
  end if;
  v_aug := public.school_get_teacher_monthly_wage_generation_preflight('2026-08',null,null);
  if (v_aug->'summary'->>'blocker_count')::integer <= 0
     or (select count(*) from jsonb_array_elements(v_aug->'candidate_prerequisites') x where not (x->>'prerequisite_satisfied')::boolean)
        <> (v_aug->'summary'->>'blocker_count')::integer then
    raise exception 'WAGE_EFFECTIVE_DISPLAY_REHEARSAL_REAL_BLOCKER_FAILED';
  end if;
end
$assert$;

reset role;
set local role anon;
do $assert$
begin
  perform public.school_get_teacher_monthly_wage_generation_preflight('2026-07',null,null);
  raise exception 'WAGE_EFFECTIVE_DISPLAY_ANON_UNEXPECTED_ACCESS';
exception when insufficient_privilege then null;
end
$assert$;

reset role;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"99090000-0000-4000-8000-000000000099","role":"authenticated"}',true);
do $assert$
begin
  perform public.school_get_teacher_monthly_wage_generation_preflight('2026-07',null,null);
  raise exception 'WAGE_EFFECTIVE_DISPLAY_NO_MEMBERSHIP_UNEXPECTED_ACCESS';
exception when others then
  if sqlerrm not like '%P0G1_ACTIVE_ADMIN_REQUIRED%'
     and sqlerrm not like '%ACCESS_FORBIDDEN%' then raise; end if;
end
$assert$;

reset role;
rollback;
