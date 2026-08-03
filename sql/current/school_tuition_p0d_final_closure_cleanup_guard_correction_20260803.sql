\set ON_ERROR_STOP on
-- Correct the shared two-table P0-D fixture cleanup trigger to use generic JSON
-- field access. Scope remains the fixed d0d student/planned-lesson namespace.
begin;
create or replace function public.school_guard_tuition_identity_or_lesson_immutable()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare
  v_old jsonb:=to_jsonb(old);
begin
  if tg_op='DELETE' and session_user='postgres' then
    if current_setting('tuition.p0c_fixture_cleanup',true)
         ='codex-test atomic-void-reissue-p0c-20260803'
       and ((tg_table_name='school_student_tuition_billing_identities'
             and old.id='c0c00000-0000-4000-8000-000000002001'::uuid)
         or (tg_table_name='school_student_tuition_bill_lessons'
             and old.id in ('c0c00000-0000-4000-8000-000000005001'::uuid,
                            'c0c00000-0000-4000-8000-000000005002'::uuid))) then
      return old;
    end if;
    if current_setting('tuition.p0d_fixture_cleanup',true)
         ='codex-test tuition-p0d-e2e-readiness-20260803'
       and ((tg_table_name='school_student_tuition_billing_identities'
             and nullif(v_old->>'student_id','')::uuid
               ='d0d00000-0000-4000-8000-00000000a001'::uuid)
         or (tg_table_name='school_student_tuition_bill_lessons'
             and nullif(v_old->>'planned_lesson_id','')::uuid in (
               'd0d00000-0000-4000-8000-000000001101'::uuid,
               'd0d00000-0000-4000-8000-000000001102'::uuid))) then
      return old;
    end if;
  end if;
  raise exception 'TUITION_IMMUTABLE_ROW: % rows cannot be updated or deleted.',tg_table_name;
end
$function$;
revoke all on function public.school_guard_tuition_identity_or_lesson_immutable()
  from public,anon,authenticated,service_role;
commit;
\echo 'P0D_FINAL_CLEANUP_GUARD_CORRECTED'
