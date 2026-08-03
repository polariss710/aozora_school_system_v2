-- P0-E deployed-function correction: idempotent Reissue must take the same shared advisory locks.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';
do $patch$
declare v_definition text; v_anchor text; v_replacement text;
begin
  v_definition:=pg_get_functiondef(
    'public.school_reissue_atomic_student_tuition_generation_p0e_local(uuid,uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,uuid,numeric,text,numeric,text,numeric,text,text)'::regprocedure);
  if position('P0E shared lock entry' in v_definition)>0 then
    return;
  end if;
  v_anchor:='select r.* into v_active from public.school_student_tuition_generation_revisions r';
  v_replacement:='null; -- P0E shared lock entry
  perform public.school_lock_student_tuition_operation(p_student_id,p_business_entity_id,
    (to_date(p_billing_month||''-01'',''YYYY-MM-DD'')-interval ''1 month'')::date);
  perform public.school_lock_student_tuition_operation(p_student_id,p_business_entity_id,
    to_date(p_billing_month||''-01'',''YYYY-MM-DD''));
  '||v_anchor;
  v_definition:=replace(v_definition,v_anchor,v_replacement);
  if position('P0E shared lock entry' in v_definition)=0 then
    raise exception 'TUITION_P0E_SHARED_LOCK_PATCH_FAILED';
  end if;
  execute v_definition;
end;
$patch$;
commit;
