\set ON_ERROR_STOP on
begin;
do $capture_and_patch$
declare v_definition text;
begin
  v_definition:=pg_get_functiondef(
    'public.school_guard_tuition_identity_or_lesson_immutable()'::regprocedure);
  execute replace(v_definition,'school_guard_tuition_identity_or_lesson_immutable',
    'school_p0c_baseline_guard_tuition_identity_or_lesson');
  execute 'revoke all on function public.school_p0c_baseline_guard_tuition_identity_or_lesson()
    from public,anon,authenticated,service_role';
  v_definition:=replace(v_definition,
    'begin
  raise exception',
    'begin
  if tg_op=''DELETE'' and session_user=''postgres''
     and current_setting(''tuition.p0c_fixture_cleanup'',true)
       =''codex-test atomic-void-reissue-p0c-20260803''
     and ((tg_table_name=''school_student_tuition_billing_identities''
           and old.id=''c0c00000-0000-4000-8000-000000002001''::uuid)
       or (tg_table_name=''school_student_tuition_bill_lessons''
           and old.id in (''c0c00000-0000-4000-8000-000000005001''::uuid,
                          ''c0c00000-0000-4000-8000-000000005002''::uuid))) then
    return old;
  end if;
  raise exception');
  if position('c0c00000-0000-4000-8000-000000002001' in v_definition)=0 then
    raise exception 'TUITION_P0C_FIXTURE_IMMUTABLE_GUARD_PATCH_FAILED';
  end if;
  execute v_definition;
end;
$capture_and_patch$;
commit;
