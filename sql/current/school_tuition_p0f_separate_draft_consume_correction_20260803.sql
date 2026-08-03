-- P0-F lifecycle correction: an explicitly saved separate-mode draft is also
-- consumed by lock, while creating no variance claim.
\set ON_ERROR_STOP on
begin;
do $correction$
declare v_definition text; v_replaced text;
  v_old text:=$old$    perform set_config('school.p0f_claim_writer','off',true);
  elsif tg_op='UPDATE' and old.settlement_status='locked'$old$;
  v_new text:=$new$    perform set_config('school.p0f_claim_writer','off',true);
  elsif new.settlement_status='locked'
        and (tg_op='INSERT' or old.settlement_status is distinct from 'locked') then
    perform set_config('school.p0f_draft_writer','on',true);
    update public.school_student_settlement_source_treatment_drafts d
    set status='consumed',settlement_id=new.id,consumed_at=now(),updated_at=now(),updated_by=current_user
    where d.student_id=new.student_id and d.business_entity_id=new.business_entity_id
      and d.year_month=new.year_month and d.status='active';
    perform set_config('school.p0f_draft_writer','off',true);
  elsif tg_op='UPDATE' and old.settlement_status='locked'$new$;
begin
  select pg_get_functiondef('public.school_tuition_p0f_settlement_after()'::regprocedure)
  into v_definition;
  if position(v_old in v_definition)=0
     or position('an explicitly saved separate-mode draft' in v_definition)>0 then
    raise exception 'P0F_SEPARATE_DRAFT_CONSUME_SOURCE_DRIFT';
  end if;
  v_replaced:=replace(v_definition,v_old,v_new);
  execute v_replaced;
end
$correction$;
comment on function public.school_tuition_p0f_settlement_after() is
  'P0-F lock creates claims only for net mode; every explicit treatment draft, including separate mode, is consumed. Unlock releases active claims without deletion.';
revoke all on function public.school_tuition_p0f_settlement_after()
  from public,anon,authenticated,service_role;
commit;
