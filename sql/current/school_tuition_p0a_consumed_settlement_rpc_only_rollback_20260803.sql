-- Exact rollback for School V2 tuition P0-A, 2026-08-03.
-- Required psql variable: p0a_rollback_commit=0 rehearsal or 1 authorized rollback.
-- No CASCADE, no business-row DML, and no broad object removal.
\set ON_ERROR_STOP on
\pset pager off

\if :{?p0a_rollback_commit}
\else
  \echo 'P0A_ROLLBACK_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';

do $preflight$
declare
  v_signature text;
  v_expected_md5 text;
begin
  for v_signature,v_expected_md5 in
    select * from (values
      ('public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)','3e3414b996faf773c5dbc073bc6973b7'),
      ('public.school_lock_student_monthly_settlement(uuid,text,text)','efaa26100bc5cbd2e61be63e7eaa46ef'),
      ('public.school_unlock_student_monthly_settlement(uuid,text)','653356cc5c9c75b584d0d5cc5104397f'),
      ('public.school_relock_student_monthly_settlement(uuid,text)','38efb4f3170f39359ca67ba23ac1ccae'),
      ('public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)','f8b33842d6dbaa3cbdeca20236146c82')
    ) expected(signature,definition_md5)
  loop
    if md5(pg_get_functiondef(v_signature::regprocedure))<>v_expected_md5 then
      raise exception 'TUITION_P0A_ROLLBACK_BASELINE_DRIFT: %',v_signature;
    end if;
  end loop;
end
$preflight$;

create temporary table tuition_p0a_rollback_business_baseline(
  object_name text primary key,row_count bigint not null,full_hash text not null
) on commit drop;

insert into tuition_p0a_rollback_business_baseline
select 'settlement',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_monthly_settlements t
union all select 'draft',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustment_drafts t
union all select 'adjustment',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustments t
union all select 'carryover',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_carryovers t
union all select 'bill',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bills t
union all select 'identity',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_billing_identities t
union all select 'bill_lesson',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bill_lessons t
union all select 'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_income_records t
union all select 'cash_linkage',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_personal_cash_income_linkage_events t;

do $restore_writers$
declare
  v_def text;
  v_new text;
  v_old text;
  v_replacement text;
begin
  v_def:=pg_get_functiondef('public.school_generate_student_tuition_bill_atomic_core(uuid,text,numeric,text,text,text)'::regprocedure);
  v_old:=$old$  PERFORM public.school_tuition_p0a_lock_generate_scope(
    p_student_id,v_student_initial.business_entity_id,
    ARRAY[v_previous_month,btrim(p_billing_month)]
  );$old$;
  v_replacement:=$new$  FOR v_lock_month IN SELECT unnest(ARRAY[v_previous_month,btrim(p_billing_month)]) ORDER BY 1 LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(concat_ws('|',
      'student_tuition_operation_v1',p_student_id::text,
      v_student_initial.business_entity_id::text,v_lock_month),0));
  END LOOP;$new$;
  v_new:=replace(v_def,v_old,v_replacement);
  v_new:=replace(v_new,
    '    LOCK TABLE public.school_student_settlement_adjustment_drafts IN SHARE MODE;'||chr(10)||
    '    LOCK TABLE public.school_student_settlement_adjustments IN SHARE MODE;',
    '    LOCK TABLE public.school_student_settlement_adjustment_drafts IN SHARE MODE;');
  if v_new=v_def or position('school_tuition_p0a_lock_generate_scope' in v_new)>0 then
    raise exception 'TUITION_P0A_ROLLBACK_ATOMIC_PATCH_FAILED';
  end if;
  execute v_new;

  v_def:=pg_get_functiondef('public.school_lock_student_monthly_settlement(uuid,text,text)'::regprocedure);
  v_new:=replace(v_def,'  v_adjustment_reason text;'||chr(10)||'  v_business_entity_id uuid;'||chr(10)||'BEGIN',
    '  v_adjustment_reason text;'||chr(10)||'BEGIN');
  v_old:=$old$  SELECT student.business_entity_id INTO v_business_entity_id
  FROM public.school_students student
  WHERE student.id=p_student_id AND student.app_type='school';
  IF NOT FOUND OR v_business_entity_id IS NULL THEN
    RAISE EXCEPTION '学生不存在、业务类型不符或缺少默认业务归属，不能锁定结算。';
  END IF;
  PERFORM public.school_tuition_p0a_lock_settlement_mutation_scope(
    p_student_id,v_business_entity_id,v_year_month);

  IF EXISTS (
    SELECT 1 FROM public.school_student_monthly_settlements m$old$;
  v_replacement:=$new$  IF EXISTS (
    SELECT 1 FROM public.school_student_monthly_settlements m$new$;
  v_new:=replace(v_new,v_old,v_replacement);
  if position('school_tuition_p0a_lock_settlement_mutation_scope' in v_new)>0 then
    raise exception 'TUITION_P0A_ROLLBACK_LOCK_PATCH_FAILED';
  end if;
  execute v_new;

  v_def:=pg_get_functiondef('public.school_unlock_student_monthly_settlement(uuid,text)'::regprocedure);
  v_old:=$old$  SELECT * INTO v_settlement
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
  PERFORM public.school_assert_tuition_settlement_mutable(v_settlement.id);$old$;
  v_replacement:=$new$  SELECT * INTO v_settlement
  FROM public.school_student_monthly_settlements
  WHERE id=p_settlement_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '没有找到对应的学生月度结算。'; END IF;$new$;
  v_new:=replace(v_def,v_old,v_replacement);
  if position('school_assert_tuition_settlement_mutable' in v_new)>0 then
    raise exception 'TUITION_P0A_ROLLBACK_UNLOCK_PATCH_FAILED';
  end if;
  execute v_new;

  v_def:=pg_get_functiondef('public.school_relock_student_monthly_settlement(uuid,text)'::regprocedure);
  v_old:=$old$  SELECT * INTO v_settlement
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
  PERFORM public.school_assert_tuition_settlement_mutable(v_settlement.id);$old$;
  v_replacement:=$new$  SELECT * INTO v_settlement
  FROM public.school_student_monthly_settlements
  WHERE id = p_settlement_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION '没有找到对应的学生月度结算。';
  END IF;$new$;
  v_new:=replace(v_def,v_old,v_replacement);
  if position('school_assert_tuition_settlement_mutable' in v_new)>0 then
    raise exception 'TUITION_P0A_ROLLBACK_RELOCK_PATCH_FAILED';
  end if;
  execute v_new;

  v_def:=pg_get_functiondef('public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)'::regprocedure);
  v_old:=$old$  IF v_business_entity_id IS NULL THEN
    RAISE EXCEPTION '学生缺少默认业务归属，不能记录差额调整。';
  END IF;
  PERFORM public.school_tuition_p0a_lock_settlement_mutation_scope(
    p_student_id,v_business_entity_id,v_year_month);
  PERFORM public.school_assert_tuition_settlement_month_mutable(
    p_student_id,v_year_month);

  SELECT m.settlement_status INTO v_existing_status$old$;
  v_replacement:=$new$  IF v_business_entity_id IS NULL THEN
    RAISE EXCEPTION '学生缺少默认业务归属，不能记录差额调整。';
  END IF;

  SELECT m.settlement_status INTO v_existing_status$new$;
  v_new:=replace(v_def,v_old,v_replacement);
  if position('school_assert_tuition_settlement_month_mutable' in v_new)>0 then
    raise exception 'TUITION_P0A_ROLLBACK_DRAFT_PATCH_FAILED';
  end if;
  execute v_new;
end
$restore_writers$;

alter function public.school_lock_student_monthly_settlement(uuid,text,text)
  set search_path to public;
alter function public.school_unlock_student_monthly_settlement(uuid,text)
  set search_path to public;
alter function public.school_relock_student_monthly_settlement(uuid,text)
  set search_path to public;
alter function public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)
  set search_path to public;
alter function public.school_apply_student_monthly_settlement_adjustment(uuid,numeric,text,text,text)
  set search_path to public;

drop trigger school_tuition_consumed_settlement_immutable
  on public.school_student_monthly_settlements;
drop trigger school_tuition_consumed_draft_immutable
  on public.school_student_settlement_adjustment_drafts;
drop trigger school_tuition_consumed_adjustment_immutable
  on public.school_student_settlement_adjustments;
drop trigger school_tuition_consumed_carryover_immutable
  on public.school_student_settlement_carryovers;

drop policy school_student_settlement_adjustment_drafts_select_app_roles
  on public.school_student_settlement_adjustment_drafts;
drop policy school_student_settlement_adjustments_select_app_roles
  on public.school_student_settlement_adjustments;

alter table public.school_student_settlement_adjustment_drafts disable row level security;
alter table public.school_student_settlement_adjustments disable row level security;

create policy "school settlements insert for app users"
on public.school_student_monthly_settlements for insert
to anon,authenticated with check (true);
create policy "school settlements update for app users"
on public.school_student_monthly_settlements for update
to anon,authenticated using (true) with check (true);
create policy "school settlements delete for app users"
on public.school_student_monthly_settlements for delete
to anon,authenticated using (true);
create policy school_student_settlement_carryovers_insert_all_app_roles
on public.school_student_settlement_carryovers for insert
to anon,authenticated with check (true);
create policy school_student_settlement_carryovers_update_all_app_roles
on public.school_student_settlement_carryovers for update
to anon,authenticated using (true) with check (true);
create policy school_student_settlement_carryovers_delete_all_app_roles
on public.school_student_settlement_carryovers for delete
to anon,authenticated using (true);

grant all on table public.school_student_monthly_settlements
  to anon,authenticated,service_role;
grant all on table public.school_student_settlement_adjustment_drafts
  to anon,authenticated,service_role;
grant all on table public.school_student_settlement_adjustments
  to anon,authenticated,service_role;
grant all on table public.school_student_settlement_carryovers
  to anon,authenticated,service_role;

grant execute on function public.school_lock_student_monthly_settlement(uuid,text,text)
  to public,anon,authenticated,service_role;
grant execute on function public.school_unlock_student_monthly_settlement(uuid,text)
  to public,anon,authenticated,service_role;
grant execute on function public.school_relock_student_monthly_settlement(uuid,text)
  to public,anon,authenticated,service_role;
grant execute on function public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)
  to public,anon,authenticated,service_role;
grant execute on function public.school_apply_student_monthly_settlement_adjustment(uuid,numeric,text,text,text)
  to public,anon,authenticated,service_role;

drop function public.school_guard_tuition_consumed_settlement_row();
drop function public.school_guard_tuition_consumed_settlement_child();
drop function public.school_tuition_p0a_lock_generate_scope(uuid,uuid,text[]);
drop function public.school_tuition_p0a_lock_settlement_mutation_scope(uuid,uuid,text);
drop function public.school_assert_tuition_settlement_month_mutable(uuid,text);
drop function public.school_assert_tuition_settlement_mutable(uuid);
drop function public.school_tuition_p0a_consumed_bill_id(uuid);

do $verify$
declare
  v_signature text;
  v_expected_md5 text;
begin
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
    if md5(pg_get_functiondef(v_signature::regprocedure))<>v_expected_md5 then
      raise exception 'TUITION_P0A_ROLLBACK_DEFINITION_FAILED: %',v_signature;
    end if;
  end loop;
end
$verify$;

do $business_zero_drift$
declare
  v_row record;
  v_current_count bigint;
  v_current_hash text;
begin
  for v_row in select * from tuition_p0a_rollback_business_baseline loop
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
      raise exception 'TUITION_P0A_ROLLBACK_BUSINESS_DATA_DRIFT: %',v_row.object_name;
    end if;
  end loop;
end
$business_zero_drift$;

\if :p0a_rollback_commit
  commit;
  \echo 'TUITION_P0A_ROLLBACK_COMMITTED'
\else
  rollback;
  \echo 'TUITION_P0A_ROLLBACK_REHEARSAL_ROLLED_BACK'
\endif
