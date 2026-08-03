-- P0-F reader exclusion and canonical planned-void router.
\set ON_ERROR_STOP on
begin;
set local lock_timeout='8s';
set local statement_timeout='240s';

do $open_credit_reader$
declare v_definition text; v_replaced text;
begin
  select pg_get_functiondef(
    'public.school_list_open_lesson_credit_sources(text,text,text)'::regprocedure
  ) into v_definition;
  if position('school_student_settlement_lesson_variance_claims' in v_definition)>0
     or position('WHERE s.remaining_hours>0' in v_definition)=0 then
    raise exception 'P0F_OPEN_CREDIT_READER_SOURCE_DRIFT';
  end if;
  v_replaced:=replace(v_definition,'WHERE s.remaining_hours>0',
    $sql$WHERE s.remaining_hours>0
    and not exists (
      select 1
      from public.school_student_settlement_lesson_variance_claims c
      where c.claim_status='active'
        and c.source_type='unused_planned_credit_v1'
        and c.source_planned_lesson_id=s.id
    )$sql$);
  execute v_replaced;
end
$open_credit_reader$;

alter function public.school_void_planned_lesson(uuid,timestamptz,text)
  rename to school_void_planned_lesson_p0f_legacy;

create function public.school_void_planned_lesson(
  p_lesson_id uuid,p_expected_updated_at timestamptz,p_void_reason text
)
returns table(lesson_id uuid,lesson_type text,status text,voided_at timestamptz,
  void_reason text,updated_at timestamptz)
language plpgsql security definer set search_path=pg_catalog,public
as $function$
begin
  if exists(
    select 1
    from public.school_student_tuition_bill_lessons bl
    join public.school_student_tuition_generation_revisions r
      on r.tuition_bill_id=bl.tuition_bill_id
    where bl.planned_lesson_id=p_lesson_id and r.lifecycle_status='voided'
  ) then
    return query select *
    from public.school_void_planned_lesson_after_tuition_void(
      p_lesson_id,p_expected_updated_at,p_void_reason,
      'CONFIRM VOID PLANNED LESSON AFTER TUITION VOID'
    );
  else
    return query select *
    from public.school_void_planned_lesson_p0f_legacy(
      p_lesson_id,p_expected_updated_at,p_void_reason
    );
  end if;
end
$function$;

revoke all on function public.school_void_planned_lesson_p0f_legacy(uuid,timestamptz,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_void_planned_lesson(uuid,timestamptz,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_void_planned_lesson(uuid,timestamptz,text)
  to anon,authenticated,service_role;
revoke all on function public.school_list_open_lesson_credit_sources(text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_open_lesson_credit_sources(text,text,text)
  to anon,authenticated,service_role;

comment on function public.school_void_planned_lesson(uuid,timestamptz,text) is
  'P0-F canonical router. A planned lesson with voided tuition history must pass the stronger all-downstream RPC; fresh/error-only lessons retain the existing soft-void contract.';
comment on function public.school_list_open_lesson_credit_sources(text,text,text) is
  'P0-F reader: pending_makeup requires positive DB remaining hours and no active unused-credit financial claim.';
commit;
