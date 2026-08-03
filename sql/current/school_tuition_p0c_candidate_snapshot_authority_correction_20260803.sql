\set ON_ERROR_STOP on
begin;
do $patch$
declare v_definition text;
begin
  v_definition:=pg_get_functiondef(
    'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure);
  v_definition:=replace(v_definition,
    'FROM public.school_student_tuition_bills bill',
    'FROM public.school_student_tuition_bills bill
     JOIN public.school_student_tuition_generation_revisions active_revision
       ON active_revision.tuition_bill_id=bill.id
      AND active_revision.lifecycle_status=''active''');
  if position('active_revision.lifecycle_status=''active''' in v_definition)=0 then
    raise exception 'TUITION_ACTIVE_SNAPSHOT_READER_PATCH_FAILED';
  end if;
  execute v_definition;
end;
$patch$;
commit;
