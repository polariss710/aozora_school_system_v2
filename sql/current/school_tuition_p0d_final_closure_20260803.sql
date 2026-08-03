\set ON_ERROR_STOP on
-- P0-D final closure: active previous-period claim includes zero carryover,
-- while any historically consumed settlement remains permanently immutable.
-- Also narrows committed synthetic cleanup to the fixed d0d student/generation scope.

begin;
set local lock_timeout='8s';
set local statement_timeout='240s';

create temporary table p0d_final_before as
select 'settlement' kind,count(*) row_count,
  md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) row_hash
from public.school_student_monthly_settlements t
union all select 'draft',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_student_settlement_adjustment_drafts t
union all select 'adjustment',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_student_settlement_adjustments t
union all select 'carryover',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_student_settlement_carryovers t;

create or replace function public.school_assert_active_tuition_previous_period_claim(
  p_student_id uuid,
  p_business_entity_id uuid,
  p_year_month text
) returns void
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_bill_id uuid;
begin
  if p_student_id is null or p_business_entity_id is null
     or p_year_month is null
     or p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_SCOPE_INVALID';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(concat_ws('|',
    'student_tuition_operation_v1',p_student_id::text,
    p_business_entity_id::text,p_year_month),0));

  select bill.id into v_bill_id
  from public.school_student_tuition_generation_revisions revision
  join public.school_student_tuition_generation_identities generation
    on generation.id=revision.generation_identity_id
  join public.school_student_tuition_bills bill
    on bill.id=revision.tuition_bill_id
  where revision.lifecycle_status='active'
    and generation.student_id=p_student_id
    and generation.business_entity_id=p_business_entity_id
    and bill.student_id=p_student_id
    and bill.business_entity_id=p_business_entity_id
    and bill.previous_settlement_month=p_year_month
    and bill.app_type='school'
    and bill.billing_role='canonical_charge'
  order by revision.created_at,revision.id
  limit 1;

  if v_bill_id is not null then
    raise exception using errcode='P0001',message=format(
      'TUITION_ACTIVE_PREVIOUS_PERIOD_CLAIM_IMMUTABLE: student %s entity %s period %s is frozen by active tuition bill %s, including zero carryover.',
      p_student_id,p_business_entity_id,p_year_month,v_bill_id
    );
  end if;
end
$function$;
revoke all on function public.school_assert_active_tuition_previous_period_claim(uuid,uuid,text)
  from public,anon,authenticated,service_role;

create or replace function public.school_assert_tuition_settlement_mutable(
  p_settlement_id uuid
) returns void
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_bill_id uuid;
  v_settlement public.school_student_monthly_settlements%rowtype;
begin
  if p_settlement_id is null then return; end if;
  v_bill_id:=public.school_tuition_p0a_consumed_bill_id(p_settlement_id);
  if v_bill_id is not null then
    raise exception using errcode='P0001',message=format(
      'TUITION_CONSUMED_SETTLEMENT_IMMUTABLE: settlement %s was consumed by tuition bill %s; historical settlement remains permanently immutable and correction requires a forward adjustment.',
      p_settlement_id,v_bill_id
    );
  end if;
  select * into v_settlement
  from public.school_student_monthly_settlements
  where id=p_settlement_id;
  if found then
    perform public.school_assert_active_tuition_previous_period_claim(
      v_settlement.student_id,v_settlement.business_entity_id,v_settlement.year_month
    );
  end if;
end
$function$;
revoke all on function public.school_assert_tuition_settlement_mutable(uuid)
  from public,anon,authenticated,service_role;

create or replace function public.school_assert_tuition_settlement_month_mutable(
  p_student_id uuid,p_year_month text
) returns void
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_settlement_id uuid;
  v_business_entity_id uuid;
begin
  select settlement.id,settlement.business_entity_id
  into v_settlement_id,v_business_entity_id
  from public.school_student_monthly_settlements settlement
  where settlement.student_id=p_student_id
    and settlement.year_month=p_year_month
  order by settlement.id
  limit 1;
  if v_settlement_id is not null then
    perform public.school_assert_tuition_settlement_mutable(v_settlement_id);
    return;
  end if;
  select student.business_entity_id into v_business_entity_id
  from public.school_students student
  where student.id=p_student_id and student.app_type='school';
  if v_business_entity_id is not null then
    perform public.school_assert_active_tuition_previous_period_claim(
      p_student_id,v_business_entity_id,p_year_month
    );
  end if;
end
$function$;
revoke all on function public.school_assert_tuition_settlement_month_mutable(uuid,text)
  from public,anon,authenticated,service_role;

create or replace function public.school_guard_tuition_consumed_settlement_row()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
begin
  if tg_op='INSERT' then
    perform public.school_assert_active_tuition_previous_period_claim(
      new.student_id,new.business_entity_id,new.year_month
    );
    return new;
  end if;
  perform public.school_assert_tuition_settlement_mutable(old.id);
  if tg_op='UPDATE' then
    perform public.school_assert_active_tuition_previous_period_claim(
      new.student_id,new.business_entity_id,new.year_month
    );
    return new;
  end if;
  return old;
end
$function$;
revoke all on function public.school_guard_tuition_consumed_settlement_row()
  from public,anon,authenticated,service_role;

drop trigger school_tuition_consumed_settlement_immutable
  on public.school_student_monthly_settlements;
create trigger school_tuition_consumed_settlement_immutable
before insert or update or delete on public.school_student_monthly_settlements
for each row execute function public.school_guard_tuition_consumed_settlement_row();

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

comment on function public.school_assert_active_tuition_previous_period_claim(uuid,uuid,text) is
  'P0-D Rule A: an active tuition revision freezes its previous-period settlement scope even when carryover is zero and previous_settlement_id is null; the shared operation lock serializes settlement writers.';
comment on function public.school_assert_tuition_settlement_mutable(uuid) is
  'Rule B first: any historically consumed settlement is permanently immutable. Otherwise Rule A blocks mutation while an active tuition revision claims the settlement period.';

do $no_business_row_drift$
declare r record;
begin
  for r in
    select b.kind,b.row_count,b.row_hash,
           a.row_count after_count,a.row_hash after_hash
    from p0d_final_before b
    join (
      select 'settlement' kind,count(*) row_count,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) row_hash from public.school_student_monthly_settlements t
      union all select 'draft',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustment_drafts t
      union all select 'adjustment',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustments t
      union all select 'carryover',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_carryovers t
    ) a using(kind)
  loop
    if r.row_count<>r.after_count or r.row_hash is distinct from r.after_hash then
      raise exception 'P0D_FINAL_BUSINESS_ROW_DRIFT: %',r.kind;
    end if;
  end loop;
end
$no_business_row_drift$;

commit;
\echo 'P0D_FINAL_CLOSURE_DEPLOYED'
