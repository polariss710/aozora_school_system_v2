-- Runtime ACL/RLS tests against the fixed synthetic P0-B2 fixture.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local role anon;
select draft_id,adjustment_source,adjustment_amount_cny,locked_carryover_cny
from public.school_set_student_monthly_settlement_draft_adjustment(
  'b1b10000-0000-4000-8000-00000000a100','2020-06',null,
  'clear_balance','codex-test P0-B2 anon','codex-test P0-B2 role runtime');
rollback;

begin;
set local role authenticated;
select draft_id,adjustment_source,adjustment_amount_cny,locked_carryover_cny
from public.school_set_student_monthly_settlement_draft_adjustment(
  'b1b10000-0000-4000-8000-00000000a100','2020-06',1.235,
  'manual_adjustment','codex-test P0-B2 authenticated','codex-test P0-B2 role runtime');
rollback;

begin;
set local role service_role;
select draft_id,adjustment_source,adjustment_amount_cny,locked_carryover_cny
from public.school_set_student_monthly_settlement_draft_adjustment(
  'b1b10000-0000-4000-8000-00000000a100','2020-06',null,
  'carry_final_balance','codex-test P0-B2 service','codex-test P0-B2 role runtime');
rollback;

do $acl$
declare
  v_role text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if not has_function_privilege(v_role,
      'public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)','EXECUTE')
       or not has_function_privilege(v_role,
      'public.school_get_student_monthly_settlement_preview(uuid,text)','EXECUTE')
       or has_function_privilege(v_role,
      'public.school_apply_student_monthly_settlement_adjustment(uuid,numeric,text,text,text)','EXECUTE')
       or has_function_privilege(v_role,
      'public.school_tuition_p0b2_resolve_adjustment(text,numeric,numeric)','EXECUTE') then
      raise exception 'P0B2_RUNTIME_FUNCTION_ACL_FAILED: %',v_role;
    end if;
  end loop;
end
$acl$;

-- Direct table writes must fail for every application role.
\set ON_ERROR_STOP off
begin; set local role anon;
insert into public.school_student_settlement_adjustment_drafts(note)
values('codex-test P0-B2 direct anon'); rollback;
begin; set local role authenticated;
update public.school_student_settlement_adjustment_drafts set note='x'
where student_id='b1b10000-0000-4000-8000-00000000a100'; rollback;
begin; set local role service_role;
delete from public.school_student_settlement_adjustment_drafts
where student_id='b1b10000-0000-4000-8000-00000000a100'; rollback;
\set ON_ERROR_STOP on

do $residue$
begin
  if exists (
    select 1 from public.school_student_settlement_adjustment_drafts
    where note like 'codex-test P0-B2 direct%'
  ) then raise exception 'P0B2_RUNTIME_ACL_RESIDUE'; end if;
end
$residue$;
select 'P0B2_ACL_RUNTIME_TESTS_PASSED' result;
