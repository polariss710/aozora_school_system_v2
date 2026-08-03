\set ON_ERROR_STOP on
-- Exact object rollback for school_tuition_p0d_final_closure_20260803.sql.
-- No business rows are changed.
begin;

drop trigger school_tuition_consumed_settlement_immutable
  on public.school_student_monthly_settlements;

create or replace function public.school_assert_tuition_settlement_mutable(
  p_settlement_id uuid
) returns void
language plpgsql stable security definer set search_path=pg_catalog,public
as $function$
declare v_bill_id uuid;
begin
  if p_settlement_id is null then return; end if;
  v_bill_id:=public.school_tuition_p0a_consumed_bill_id(p_settlement_id);
  if v_bill_id is not null then
    raise exception using errcode='P0001',message=format(
      'TUITION_CONSUMED_SETTLEMENT_IMMUTABLE: settlement %s 已被 active tuition bill %s 消费；历史 settlement 不得重开，后续纠错应使用 forward adjustment。本阶段不实现 forward adjustment UI。',
      p_settlement_id,v_bill_id
    );
  end if;
end
$function$;

create or replace function public.school_assert_tuition_settlement_month_mutable(
  p_student_id uuid,p_year_month text
) returns void
language plpgsql stable security definer set search_path=pg_catalog,public
as $function$
declare v_settlement_id uuid;
begin
  select settlement.id into v_settlement_id
  from public.school_student_monthly_settlements settlement
  where settlement.student_id=p_student_id and settlement.year_month=p_year_month
  order by settlement.id limit 1;
  perform public.school_assert_tuition_settlement_mutable(v_settlement_id);
end
$function$;

create or replace function public.school_guard_tuition_consumed_settlement_row()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
begin
  perform public.school_assert_tuition_settlement_mutable(old.id);
  if tg_op='UPDATE' then
    perform public.school_assert_tuition_settlement_mutable(new.id);
    return new;
  end if;
  return old;
end
$function$;

create trigger school_tuition_consumed_settlement_immutable
before update or delete on public.school_student_monthly_settlements
for each row execute function public.school_guard_tuition_consumed_settlement_row();

create or replace function public.school_guard_tuition_identity_or_lesson_immutable()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
begin
  if tg_op='DELETE' and session_user='postgres' then
    if current_setting('tuition.p0c_fixture_cleanup',true)
         ='codex-test atomic-void-reissue-p0c-20260803'
       and ((tg_table_name='school_student_tuition_billing_identities'
             and old.id='c0c00000-0000-4000-8000-000000002001'::uuid)
         or (tg_table_name='school_student_tuition_bill_lessons'
             and old.id in ('c0c00000-0000-4000-8000-000000005001'::uuid,
                            'c0c00000-0000-4000-8000-000000005002'::uuid))) then return old; end if;
    if current_setting('tuition.p0d_fixture_cleanup',true)
         ='codex-test tuition-p0d-e2e-readiness-20260803'
       and ((tg_table_name='school_student_tuition_billing_identities'
             and old.id='d0d00000-0000-4000-8000-000000002001'::uuid)
         or (tg_table_name='school_student_tuition_bill_lessons'
             and old.id in ('d0d00000-0000-4000-8000-000000005001'::uuid,
                            'd0d00000-0000-4000-8000-000000005002'::uuid))) then return old; end if;
  end if;
  raise exception 'TUITION_IMMUTABLE_ROW: % rows cannot be updated or deleted.',tg_table_name;
end
$function$;

revoke all on function public.school_assert_tuition_settlement_mutable(uuid),
  public.school_assert_tuition_settlement_month_mutable(uuid,text),
  public.school_guard_tuition_consumed_settlement_row(),
  public.school_guard_tuition_identity_or_lesson_immutable()
  from public,anon,authenticated,service_role;

drop function public.school_assert_active_tuition_previous_period_claim(uuid,uuid,text);
commit;
\echo 'P0D_FINAL_CLOSURE_OBJECTS_ROLLED_BACK'
