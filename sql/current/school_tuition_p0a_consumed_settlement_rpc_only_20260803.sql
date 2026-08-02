-- School V2 tuition finance P0-A: consumed settlement immutability,
-- shared operation locks, and RPC-only settlement tables, 2026-08-03.
-- Required psql variable: p0a_migration_commit=0 rehearsal or 1 deploy.
\set ON_ERROR_STOP on
\pset pager off

\if :{?p0a_migration_commit}
\else
  \echo 'P0A_MIGRATION_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

begin;
set local lock_timeout = '10s';
set local statement_timeout = '240s';

do $preflight$
declare
  v_signature text;
  v_expected_md5 text;
begin
  if (select count(*) from public.school_feature_gates
      where (feature_key='student_tuition_preview' and state='enabled')
         or (feature_key='student_tuition_generate' and state='blocked')
         or (feature_key='student_tuition_cash_submit' and state='blocked')) <> 3 then
    raise exception 'TUITION_P0A_GATE_NOT_BLOCKED';
  end if;

  for v_signature,v_expected_md5 in
    select * from (values
      ('public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)','b88f6d960d920c10b914fe8e58cf38cb'),
      ('public.school_lock_student_monthly_settlement(uuid,text,text)','523058b631837025101d558668ce10c8'),
      ('public.school_unlock_student_monthly_settlement(uuid,text)','dfeaa0243b27999724cc06bd1f1efbb6'),
      ('public.school_relock_student_monthly_settlement(uuid,text)','5b313cc696057a4a1f960ed8f1b50124'),
      ('public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)','a4fd7617aecb7b59176172c7320bf349'),
      ('public.school_apply_student_monthly_settlement_adjustment(uuid,numeric,text,text,text)','6ed088bb9fd021903ca897053fa8645a')
    ) expected(signature,definition_md5)
  loop
    if md5(pg_get_functiondef(v_signature::regprocedure)) <> v_expected_md5 then
      raise exception 'TUITION_P0A_FUNCTION_BASELINE_DRIFT: %',v_signature;
    end if;
  end loop;
end
$preflight$;

create temporary table tuition_p0a_business_baseline(
  object_name text primary key,row_count bigint not null,full_hash text not null
) on commit drop;

insert into tuition_p0a_business_baseline
select 'settlement',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_student_monthly_settlements t
union all select 'draft',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_student_settlement_adjustment_drafts t
union all select 'adjustment',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_student_settlement_adjustments t
union all select 'carryover',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_student_settlement_carryovers t
union all select 'bill',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_student_tuition_bills t
union all select 'identity',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_student_tuition_billing_identities t
union all select 'bill_lesson',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_student_tuition_bill_lessons t
union all select 'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_income_records t
union all select 'cash_linkage',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))
from public.school_personal_cash_income_linkage_events t;

create or replace function public.school_tuition_p0a_consumed_bill_id(
  p_settlement_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=pg_catalog,public
as $function$
  select bill.id
  from public.school_student_tuition_billing_identities identity_row
  join public.school_student_tuition_bills bill
    on bill.id=identity_row.canonical_bill_id
  where bill.previous_settlement_id=p_settlement_id
    and bill.app_type='school'
    and bill.status in ('draft','income_created')
    and bill.billing_role='canonical_charge'
    and identity_row.student_id=bill.student_id
    and identity_row.billing_month=bill.billing_month
    and identity_row.source in ('atomic_charge','historical_backfill')
  order by bill.id
  limit 1
$function$;

create or replace function public.school_assert_tuition_settlement_mutable(
  p_settlement_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_bill_id uuid;
begin
  if p_settlement_id is null then return; end if;
  v_bill_id:=public.school_tuition_p0a_consumed_bill_id(p_settlement_id);
  if v_bill_id is not null then
    raise exception using
      errcode='P0001',
      message=format(
        'TUITION_CONSUMED_SETTLEMENT_IMMUTABLE: settlement %s 已被 active tuition bill %s 消费；历史 settlement 不得重开，后续纠错应使用 forward adjustment。本阶段不实现 forward adjustment UI。',
        p_settlement_id,v_bill_id
      );
  end if;
end
$function$;

create or replace function public.school_assert_tuition_settlement_month_mutable(
  p_student_id uuid,p_year_month text
)
returns void
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_settlement_id uuid;
begin
  select settlement.id into v_settlement_id
  from public.school_student_monthly_settlements settlement
  where settlement.student_id=p_student_id
    and settlement.year_month=p_year_month
  order by settlement.id
  limit 1;
  perform public.school_assert_tuition_settlement_mutable(v_settlement_id);
end
$function$;

create or replace function public.school_tuition_p0a_lock_generate_scope(
  p_student_id uuid,p_business_entity_id uuid,p_year_months text[]
)
returns void
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_month text;
  v_previous_lock_timeout text:=current_setting('lock_timeout');
begin
  if p_student_id is null or p_business_entity_id is null
     or coalesce(cardinality(p_year_months),0)=0 then
    raise exception 'TUITION_P0A_LOCK_SCOPE_INVALID';
  end if;
  perform set_config('lock_timeout','8s',true);
  begin
    for v_month in
      select distinct month_value
      from unnest(p_year_months) month_value
      where month_value ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
      order by month_value
    loop
      perform pg_advisory_xact_lock(hashtextextended(concat_ws('|',
        'student_tuition_operation_v1',p_student_id::text,
        p_business_entity_id::text,v_month),0));
    end loop;
    lock table public.school_lesson_records in share mode;
    lock table public.school_student_monthly_settlements in share mode;
    lock table public.school_student_settlement_carryovers in share mode;
    lock table public.school_student_settlement_adjustment_drafts in share mode;
    lock table public.school_student_settlement_adjustments in share mode;
  exception when lock_not_available or deadlock_detected then
    perform set_config('lock_timeout',v_previous_lock_timeout,true);
    raise exception using errcode='55P03',
      message='TUITION_P0A_SOURCE_BUSY: 学费生成或月结数据正在更新，请稍后重新预览。';
  end;
  perform set_config('lock_timeout',v_previous_lock_timeout,true);
end
$function$;

create or replace function public.school_tuition_p0a_lock_settlement_mutation_scope(
  p_student_id uuid,p_business_entity_id uuid,p_year_month text
)
returns void
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_previous_lock_timeout text:=current_setting('lock_timeout');
begin
  if p_student_id is null or p_business_entity_id is null
     or p_year_month is null
     or p_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'TUITION_P0A_LOCK_SCOPE_INVALID';
  end if;
  perform set_config('lock_timeout','8s',true);
  begin
    perform pg_advisory_xact_lock(hashtextextended(concat_ws('|',
      'student_tuition_operation_v1',p_student_id::text,
      p_business_entity_id::text,p_year_month),0));
    lock table public.school_lesson_records in share mode;
    lock table public.school_student_monthly_settlements in share row exclusive mode;
    lock table public.school_student_settlement_carryovers in share row exclusive mode;
    lock table public.school_student_settlement_adjustment_drafts in share row exclusive mode;
    lock table public.school_student_settlement_adjustments in share row exclusive mode;
  exception when lock_not_available or deadlock_detected then
    perform set_config('lock_timeout',v_previous_lock_timeout,true);
    raise exception using errcode='55P03',
      message='TUITION_P0A_SOURCE_BUSY: 学费生成或月结数据正在更新，请稍后重试。';
  end;
  perform set_config('lock_timeout',v_previous_lock_timeout,true);
end
$function$;

create or replace function public.school_guard_tuition_consumed_settlement_row()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
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

create or replace function public.school_guard_tuition_consumed_settlement_child()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_row jsonb;
  v_settlement_id uuid;
begin
  for v_row in
    select row_value from (values
      (case when tg_op<>'INSERT' then to_jsonb(old) end),
      (case when tg_op<>'DELETE' then to_jsonb(new) end)
    ) rows(row_value) where row_value is not null
  loop
    if tg_table_name='school_student_settlement_adjustment_drafts' then
      v_settlement_id:=nullif(v_row->>'settlement_id','')::uuid;
      perform public.school_assert_tuition_settlement_mutable(v_settlement_id);
      perform public.school_assert_tuition_settlement_month_mutable(
        nullif(v_row->>'student_id','')::uuid,v_row->>'year_month');
    elsif tg_table_name='school_student_settlement_adjustments' then
      perform public.school_assert_tuition_settlement_mutable(
        nullif(v_row->>'settlement_id','')::uuid);
    elsif tg_table_name='school_student_settlement_carryovers' then
      v_settlement_id:=nullif(v_row->>'source_settlement_id','')::uuid;
      perform public.school_assert_tuition_settlement_mutable(v_settlement_id);
      perform public.school_assert_tuition_settlement_month_mutable(
        nullif(v_row->>'student_id','')::uuid,v_row->>'from_year_month');
    else
      raise exception 'TUITION_P0A_CHILD_GUARD_TABLE_INVALID: %',tg_table_name;
    end if;
  end loop;
  if tg_op='DELETE' then return old; end if;
  return new;
end
$function$;

create trigger school_tuition_consumed_settlement_immutable
before update or delete on public.school_student_monthly_settlements
for each row execute function public.school_guard_tuition_consumed_settlement_row();

create trigger school_tuition_consumed_draft_immutable
before insert or update or delete on public.school_student_settlement_adjustment_drafts
for each row execute function public.school_guard_tuition_consumed_settlement_child();

create trigger school_tuition_consumed_adjustment_immutable
before insert or update or delete on public.school_student_settlement_adjustments
for each row execute function public.school_guard_tuition_consumed_settlement_child();

create trigger school_tuition_consumed_carryover_immutable
before insert or update or delete on public.school_student_settlement_carryovers
for each row execute function public.school_guard_tuition_consumed_settlement_child();

do $patch_writers$
declare
  v_def text;
  v_new text;
  v_old text;
  v_replacement text;
begin
  v_def:=pg_get_functiondef('public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure);
  v_old:=$old$  FOR v_lock_month IN SELECT unnest(ARRAY[v_previous_month,btrim(p_billing_month)]) ORDER BY 1 LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(concat_ws('|',
      'student_tuition_operation_v1',p_student_id::text,
      v_student_initial.business_entity_id::text,v_lock_month),0));
  END LOOP;$old$;
  v_replacement:=$new$  PERFORM public.school_tuition_p0a_lock_generate_scope(
    p_student_id,v_student_initial.business_entity_id,
    ARRAY[v_previous_month,btrim(p_billing_month)]
  );$new$;
  v_new:=replace(v_def,v_old,v_replacement);
  if v_new=v_def then raise exception 'TUITION_P0A_ATOMIC_LOCK_PATCH_MISSING'; end if;
  v_new:=replace(v_new,
    '    LOCK TABLE public.school_student_settlement_adjustment_drafts IN SHARE MODE;',
    '    LOCK TABLE public.school_student_settlement_adjustment_drafts IN SHARE MODE;'||chr(10)||
    '    LOCK TABLE public.school_student_settlement_adjustments IN SHARE MODE;');
  if position('school_tuition_p0a_lock_generate_scope' in v_new)=0
     or position('school_student_settlement_adjustments IN SHARE MODE' in v_new)=0 then
    raise exception 'TUITION_P0A_ATOMIC_PATCH_INCOMPLETE';
  end if;
  execute v_new;

  v_def:=pg_get_functiondef('public.school_lock_student_monthly_settlement(uuid,text,text)'::regprocedure);
  v_new:=replace(v_def,'  v_adjustment_reason text;'||chr(10)||'BEGIN',
    '  v_adjustment_reason text;'||chr(10)||'  v_business_entity_id uuid;'||chr(10)||'BEGIN');
  v_old:=$old$  IF EXISTS (
    SELECT 1 FROM public.school_student_monthly_settlements m$old$;
  v_replacement:=$new$  SELECT student.business_entity_id INTO v_business_entity_id
  FROM public.school_students student
  WHERE student.id=p_student_id AND student.app_type='school';
  IF NOT FOUND OR v_business_entity_id IS NULL THEN
    RAISE EXCEPTION '学生不存在、业务类型不符或缺少默认业务归属，不能锁定结算。';
  END IF;
  PERFORM public.school_tuition_p0a_lock_settlement_mutation_scope(
    p_student_id,v_business_entity_id,v_year_month);

  IF EXISTS (
    SELECT 1 FROM public.school_student_monthly_settlements m$new$;
  v_new:=replace(v_new,v_old,v_replacement);
  if v_new=v_def or position('school_tuition_p0a_lock_settlement_mutation_scope' in v_new)=0 then
    raise exception 'TUITION_P0A_LOCK_WRITER_PATCH_MISSING';
  end if;
  execute v_new;

  v_def:=pg_get_functiondef('public.school_unlock_student_monthly_settlement(uuid,text)'::regprocedure);
  v_old:=$old$  SELECT * INTO v_settlement
  FROM public.school_student_monthly_settlements
  WHERE id=p_settlement_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '没有找到对应的学生月度结算。'; END IF;$old$;
  v_replacement:=$new$  SELECT * INTO v_settlement
  FROM public.school_student_monthly_settlements
  WHERE id=p_settlement_id;
  IF NOT FOUND THEN RAISE EXCEPTION '没有找到对应的学生月度结算。'; END IF;
  IF v_settlement.business_entity_id IS NULL THEN
    RAISE EXCEPTION '结算缺少业务归属，无法取得P0-A共享锁。';
  END IF;
  PERFORM public.school_tuition_p0a_lock_settlement_mutation_scope(
    v_settlement.student_id,v_settlement.business_entity_id,v_settlement.year_month);
  SELECT * INTO STRICT v_settlement
  FROM public.school_student_monthly_settlements
  WHERE id=p_settlement_id FOR UPDATE;
  PERFORM public.school_assert_tuition_settlement_mutable(v_settlement.id);$new$;
  v_new:=replace(v_def,v_old,v_replacement);
  if v_new=v_def or position('school_assert_tuition_settlement_mutable' in v_new)=0 then
    raise exception 'TUITION_P0A_UNLOCK_WRITER_PATCH_MISSING';
  end if;
  execute v_new;

  v_def:=pg_get_functiondef('public.school_relock_student_monthly_settlement(uuid,text)'::regprocedure);
  v_old:=$old$  SELECT * INTO v_settlement
  FROM public.school_student_monthly_settlements
  WHERE id = p_settlement_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION '没有找到对应的学生月度结算。';
  END IF;$old$;
  v_replacement:=$new$  SELECT * INTO v_settlement
  FROM public.school_student_monthly_settlements
  WHERE id = p_settlement_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION '没有找到对应的学生月度结算。';
  END IF;
  IF v_settlement.business_entity_id IS NULL THEN
    RAISE EXCEPTION '结算缺少业务归属，无法取得P0-A共享锁。';
  END IF;
  PERFORM public.school_tuition_p0a_lock_settlement_mutation_scope(
    v_settlement.student_id,v_settlement.business_entity_id,v_settlement.year_month);
  SELECT * INTO STRICT v_settlement
  FROM public.school_student_monthly_settlements
  WHERE id = p_settlement_id FOR UPDATE;
  PERFORM public.school_assert_tuition_settlement_mutable(v_settlement.id);$new$;
  v_new:=replace(v_def,v_old,v_replacement);
  if v_new=v_def or position('school_assert_tuition_settlement_mutable' in v_new)=0 then
    raise exception 'TUITION_P0A_RELOCK_WRITER_PATCH_MISSING';
  end if;
  execute v_new;

  v_def:=pg_get_functiondef('public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)'::regprocedure);
  v_old:=$old$  IF v_business_entity_id IS NULL THEN
    RAISE EXCEPTION '学生缺少默认业务归属，不能记录差额调整。';
  END IF;

  SELECT m.settlement_status INTO v_existing_status$old$;
  v_replacement:=$new$  IF v_business_entity_id IS NULL THEN
    RAISE EXCEPTION '学生缺少默认业务归属，不能记录差额调整。';
  END IF;
  PERFORM public.school_tuition_p0a_lock_settlement_mutation_scope(
    p_student_id,v_business_entity_id,v_year_month);
  PERFORM public.school_assert_tuition_settlement_month_mutable(
    p_student_id,v_year_month);

  SELECT m.settlement_status INTO v_existing_status$new$;
  v_new:=replace(v_def,v_old,v_replacement);
  if v_new=v_def or position('school_assert_tuition_settlement_month_mutable' in v_new)=0 then
    raise exception 'TUITION_P0A_DRAFT_WRITER_PATCH_MISSING';
  end if;
  execute v_new;
end
$patch_writers$;

alter function public.school_lock_student_monthly_settlement(uuid,text,text)
  set search_path to pg_catalog,public;
alter function public.school_unlock_student_monthly_settlement(uuid,text)
  set search_path to pg_catalog,public;
alter function public.school_relock_student_monthly_settlement(uuid,text)
  set search_path to pg_catalog,public;
alter function public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)
  set search_path to pg_catalog,public;
alter function public.school_apply_student_monthly_settlement_adjustment(uuid,numeric,text,text,text)
  set search_path to pg_catalog,public;

comment on function public.school_tuition_p0a_consumed_bill_id(uuid) is
  'P0-A sole consumed-settlement resolver: current canonical identity plus active canonical bill previous_settlement_id.';
comment on function public.school_assert_tuition_settlement_mutable(uuid) is
  'P0-A fail-closed guard. Consumed settlement history is immutable; correction is forward-only.';
comment on function public.school_tuition_p0a_lock_generate_scope(uuid,uuid,text[]) is
  'P0-A generate lock order: sorted student/entity/month advisory keys, lesson, settlement, carryover, draft, posted adjustment.';
comment on function public.school_tuition_p0a_lock_settlement_mutation_scope(uuid,uuid,text) is
  'P0-A settlement mutation lock order matching Atomic Generate with stronger mutation table modes.';

drop policy if exists "school settlements insert for app users"
  on public.school_student_monthly_settlements;
drop policy if exists "school settlements update for app users"
  on public.school_student_monthly_settlements;
drop policy if exists "school settlements delete for app users"
  on public.school_student_monthly_settlements;
drop policy if exists school_student_settlement_carryovers_insert_all_app_roles
  on public.school_student_settlement_carryovers;
drop policy if exists school_student_settlement_carryovers_update_all_app_roles
  on public.school_student_settlement_carryovers;
drop policy if exists school_student_settlement_carryovers_delete_all_app_roles
  on public.school_student_settlement_carryovers;

alter table public.school_student_settlement_adjustment_drafts enable row level security;
alter table public.school_student_settlement_adjustments enable row level security;

create policy school_student_settlement_adjustment_drafts_select_app_roles
on public.school_student_settlement_adjustment_drafts
for select to anon,authenticated using (true);
create policy school_student_settlement_adjustments_select_app_roles
on public.school_student_settlement_adjustments
for select to anon,authenticated using (true);

revoke all on table public.school_student_monthly_settlements
  from public,anon,authenticated,service_role;
revoke all on table public.school_student_settlement_adjustment_drafts
  from public,anon,authenticated,service_role;
revoke all on table public.school_student_settlement_adjustments
  from public,anon,authenticated,service_role;
revoke all on table public.school_student_settlement_carryovers
  from public,anon,authenticated,service_role;

grant select on table public.school_student_monthly_settlements
  to anon,authenticated,service_role;
grant select on table public.school_student_settlement_adjustment_drafts
  to anon,authenticated,service_role;
grant select on table public.school_student_settlement_adjustments
  to anon,authenticated,service_role;
grant select on table public.school_student_settlement_carryovers
  to anon,authenticated,service_role;

revoke all on function public.school_tuition_p0a_consumed_bill_id(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.school_assert_tuition_settlement_mutable(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.school_assert_tuition_settlement_month_mutable(uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_tuition_p0a_lock_generate_scope(uuid,uuid,text[])
  from public,anon,authenticated,service_role;
revoke all on function public.school_tuition_p0a_lock_settlement_mutation_scope(uuid,uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_guard_tuition_consumed_settlement_row()
  from public,anon,authenticated,service_role;
revoke all on function public.school_guard_tuition_consumed_settlement_child()
  from public,anon,authenticated,service_role;

revoke all on function public.school_lock_student_monthly_settlement(uuid,text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_unlock_student_monthly_settlement(uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_relock_student_monthly_settlement(uuid,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.school_apply_student_monthly_settlement_adjustment(uuid,numeric,text,text,text)
  from public,anon,authenticated,service_role;

grant execute on function public.school_lock_student_monthly_settlement(uuid,text,text)
  to anon,authenticated,service_role;
grant execute on function public.school_unlock_student_monthly_settlement(uuid,text)
  to anon,authenticated,service_role;
grant execute on function public.school_relock_student_monthly_settlement(uuid,text)
  to anon,authenticated,service_role;
grant execute on function public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)
  to anon,authenticated,service_role;
grant execute on function public.school_apply_student_monthly_settlement_adjustment(uuid,numeric,text,text,text)
  to anon,authenticated,service_role;

do $postflight$
declare
  v_definition text;
begin
  v_definition:=pg_get_functiondef('public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure);
  if position('school_tuition_p0a_lock_generate_scope' in v_definition)=0
     or position('school_student_settlement_adjustments IN SHARE MODE' in v_definition)=0 then
    raise exception 'TUITION_P0A_ATOMIC_LOCK_POSTFLIGHT_FAILED';
  end if;
  if position('school_tuition_p0a_lock_settlement_mutation_scope' in
       pg_get_functiondef('public.school_lock_student_monthly_settlement(uuid,text,text)'::regprocedure))=0
     or position('school_assert_tuition_settlement_mutable' in
       pg_get_functiondef('public.school_unlock_student_monthly_settlement(uuid,text)'::regprocedure))=0
     or position('school_assert_tuition_settlement_mutable' in
       pg_get_functiondef('public.school_relock_student_monthly_settlement(uuid,text)'::regprocedure))=0
     or position('school_assert_tuition_settlement_month_mutable' in
       pg_get_functiondef('public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)'::regprocedure))=0 then
    raise exception 'TUITION_P0A_SETTLEMENT_WRITER_POSTFLIGHT_FAILED';
  end if;
  if has_table_privilege('anon','public.school_student_monthly_settlements','INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('authenticated','public.school_student_monthly_settlements','INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('service_role','public.school_student_monthly_settlements','INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('anon','public.school_student_settlement_adjustment_drafts','INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('authenticated','public.school_student_settlement_adjustment_drafts','INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('service_role','public.school_student_settlement_adjustment_drafts','INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('anon','public.school_student_settlement_adjustments','INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('authenticated','public.school_student_settlement_adjustments','INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('service_role','public.school_student_settlement_adjustments','INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('anon','public.school_student_settlement_carryovers','INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('authenticated','public.school_student_settlement_carryovers','INSERT,UPDATE,DELETE,TRUNCATE')
     or has_table_privilege('service_role','public.school_student_settlement_carryovers','INSERT,UPDATE,DELETE,TRUNCATE') then
    raise exception 'TUITION_P0A_DIRECT_DML_PRIVILEGE_REMAINS';
  end if;
  if exists (
    select 1
    from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
    where p.oid in (
      'public.school_unlock_student_monthly_settlement(uuid,text)'::regprocedure,
      'public.school_relock_student_monthly_settlement(uuid,text)'::regprocedure,
      'public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)'::regprocedure
    ) and acl.grantee=0 and acl.privilege_type='EXECUTE'
  ) then
    raise exception 'TUITION_P0A_PUBLIC_EXECUTE_REMAINS';
  end if;
end
$postflight$;

do $business_zero_drift$
declare
  v_row record;
  v_current_count bigint;
  v_current_hash text;
begin
  for v_row in select * from tuition_p0a_business_baseline loop
    execute format('select count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'''' order by t.id::text),'''')) from public.%I t',
      case v_row.object_name
        when 'settlement' then 'school_student_monthly_settlements'
        when 'draft' then 'school_student_settlement_adjustment_drafts'
        when 'adjustment' then 'school_student_settlement_adjustments'
        when 'carryover' then 'school_student_settlement_carryovers'
        when 'bill' then 'school_student_tuition_bills'
        when 'identity' then 'school_student_tuition_billing_identities'
        when 'bill_lesson' then 'school_student_tuition_bill_lessons'
        when 'income' then 'school_income_records'
        when 'cash_linkage' then 'school_personal_cash_income_linkage_events'
      end)
    into v_current_count,v_current_hash;
    if v_current_count<>v_row.row_count or v_current_hash<>v_row.full_hash then
      raise exception 'TUITION_P0A_BUSINESS_DATA_DRIFT: %',v_row.object_name;
    end if;
  end loop;
end
$business_zero_drift$;

select p.oid::regprocedure::text as signature,md5(pg_get_functiondef(p.oid)) as definition_md5
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'school_generate_student_tuition_bill_atomic_core',
  'school_lock_student_monthly_settlement',
  'school_unlock_student_monthly_settlement',
  'school_relock_student_monthly_settlement',
  'school_set_student_monthly_settlement_draft_adjustment',
  'school_tuition_p0a_consumed_bill_id',
  'school_assert_tuition_settlement_mutable',
  'school_tuition_p0a_lock_generate_scope',
  'school_tuition_p0a_lock_settlement_mutation_scope'
) and p.prokind='f'
order by signature;

\if :p0a_migration_commit
  commit;
  \echo 'TUITION_P0A_MIGRATION_COMMITTED'
\else
  rollback;
  \echo 'TUITION_P0A_MIGRATION_REHEARSAL_ROLLED_BACK'
\endif
