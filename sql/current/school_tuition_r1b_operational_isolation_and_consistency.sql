-- School V2 tuition P0 R1B: operational isolation and permanent consistency guards.
-- This file creates views, functions, and triggers only. It does not backfill business rows.
-- Required psql variable: r1b_schema_commit=0 for rollback validation or 1 for deployment.

\set ON_ERROR_STOP on

begin;

create or replace view public.school_operational_income_records
with (security_invoker = true)
as
select i.*
from public.school_income_records i
where i.status <> 'incident_quarantined'
  and i.operational_excluded is not true;

comment on view public.school_operational_income_records is
  'Normal School income read surface. Permanently excludes quarantined or operationally excluded incidents.';

revoke all on table public.school_operational_income_records
  from public, anon, authenticated, service_role;
grant select on table public.school_operational_income_records
  to anon, authenticated, service_role;

create or replace view public.school_incident_income_records
with (security_invoker = true)
as
select i.*
from public.school_income_records i
where i.status = 'incident_quarantined'
  and i.operational_excluded is true;

comment on view public.school_incident_income_records is
  'Service-role-only immutable incident audit surface. Never use for normal operations, Cash, receipts, or statistics.';

revoke all on table public.school_incident_income_records
  from public, anon, authenticated, service_role;
grant select on table public.school_incident_income_records
  to service_role;

alter policy school_allow_all_income_records
on public.school_income_records
using (
  status <> 'incident_quarantined'
  and operational_excluded is not true
)
with check (
  status <> 'incident_quarantined'
  and operational_excluded is not true
);

comment on policy school_allow_all_income_records
on public.school_income_records is
  'R1B normal client policy. anon/authenticated cannot read or write quarantined/operationally excluded incident income; service_role audit access remains separate.';

create or replace function public.school_guard_incident_tuition_bill_immutable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.billing_role = 'incident_duplicate' then
    raise exception 'TUITION_INCIDENT_BILL_IMMUTABLE: incident tuition bills cannot be updated or deleted.';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.school_guard_incident_tuition_bill_immutable()
  from public, anon, authenticated;

create or replace function public.school_guard_incident_income_downstream_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_income_id uuid;
  v_is_incident boolean;
begin
  if tg_table_name = 'school_personal_cash_income_linkage_events' then
    v_income_id := coalesce(
      case when tg_op <> 'DELETE' then new.income_record_id end,
      case when tg_op <> 'INSERT' then old.income_record_id end
    );
  elsif tg_table_name = 'school_account_transactions' then
    if coalesce(
      case when tg_op <> 'DELETE' then new.related_table end,
      case when tg_op <> 'INSERT' then old.related_table end,
      ''
    ) <> 'school_income_records' then
      if tg_op = 'DELETE' then return old; end if;
      return new;
    end if;
    v_income_id := coalesce(
      case when tg_op <> 'DELETE' then new.related_id end,
      case when tg_op <> 'INSERT' then old.related_id end
    );
  else
    raise exception 'TUITION_INCIDENT_GUARD_MISCONFIGURED: unsupported table %.', tg_table_name;
  end if;

  select (
    i.status = 'incident_quarantined'
    or i.operational_excluded
    or i.cash_submission_blocked
  )
  into v_is_incident
  from public.school_income_records i
  where i.id = v_income_id;

  if coalesce(v_is_incident, false) then
    raise exception 'TUITION_INCIDENT_DOWNSTREAM_BLOCKED: quarantined income % cannot enter Cash or School account transactions.', v_income_id;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function public.school_guard_incident_income_downstream_write()
  from public, anon, authenticated;

create or replace function public.school_validate_tuition_identity_for_bill(
  p_bill_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bill public.school_student_tuition_bills%rowtype;
  v_identity_count integer := 0;
  v_matching_identity_count integer := 0;
begin
  if p_bill_id is null then
    return;
  end if;

  select * into v_bill
  from public.school_student_tuition_bills b
  where b.id = p_bill_id;

  if not found then
    return;
  end if;

  select
    count(*)::integer,
    count(*) filter (
      where identity_row.student_id = v_bill.student_id
        and identity_row.billing_month = v_bill.billing_month
    )::integer
  into v_identity_count, v_matching_identity_count
  from public.school_student_tuition_billing_identities identity_row
  where identity_row.canonical_bill_id = v_bill.id;

  if v_bill.billing_role = 'canonical_charge'
     and (v_identity_count <> 1 or v_matching_identity_count <> 1) then
    raise exception 'TUITION_IDENTITY_MISMATCH: canonical bill % must have exactly one matching student/month identity.', v_bill.id;
  end if;

  if v_bill.billing_role is distinct from 'canonical_charge'
     and v_identity_count <> 0 then
    raise exception 'TUITION_IDENTITY_MISMATCH: noncanonical bill % must not have a billing identity.', v_bill.id;
  end if;

  return;
end;
$$;

create or replace function public.school_assert_tuition_identity_consistency()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bill_ids uuid[] := '{}'::uuid[];
  v_bill_id uuid;
begin
  if tg_table_name = 'school_student_tuition_billing_identities' then
    if tg_op <> 'INSERT' then
      v_bill_ids := array_append(v_bill_ids, old.canonical_bill_id);
    end if;
    if tg_op <> 'DELETE' then
      v_bill_ids := array_append(v_bill_ids, new.canonical_bill_id);
    end if;
  else
    if tg_op <> 'INSERT' then
      v_bill_ids := array_append(v_bill_ids, old.id);
    end if;
    if tg_op <> 'DELETE' then
      v_bill_ids := array_append(v_bill_ids, new.id);
    end if;
  end if;

  for v_bill_id in
    select distinct affected.bill_id
    from unnest(v_bill_ids) as affected(bill_id)
    where affected.bill_id is not null
  loop
    perform public.school_validate_tuition_identity_for_bill(v_bill_id);
  end loop;

  return null;
end;
$$;

create or replace function public.school_validate_tuition_bill_income_for_bill(
  p_bill_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bill public.school_student_tuition_bills%rowtype;
  v_income public.school_income_records%rowtype;
  v_related_income_count integer := 0;
begin
  if p_bill_id is null then
    return;
  end if;

  select * into v_bill
  from public.school_student_tuition_bills b
  where b.id = p_bill_id;

  if not found then
    return;
  end if;

  select * into v_income
  from public.school_income_records i
  where i.id = v_bill.income_record_id;

  select count(*)::integer into v_related_income_count
  from public.school_income_records i
  where i.id = v_bill.income_record_id
     or (
       i.source_type = 'student_tuition_bill'
       and (i.source_id = v_bill.id or i.tuition_bill_id = v_bill.id)
     );

  if v_income.id is null
     or v_bill.income_record_id is distinct from v_income.id
     or v_income.source_type is distinct from 'student_tuition_bill'
     or v_income.source_id is distinct from v_bill.id
     or v_income.tuition_bill_id is distinct from v_bill.id
     or v_related_income_count <> 1 then
    raise exception 'TUITION_BILL_INCOME_MISMATCH: bill % and income % must be an exact deferred 1:1 pair.', v_bill.id, v_bill.income_record_id;
  end if;

  return;
end;
$$;

create or replace function public.school_assert_tuition_bill_income_consistency()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bill_ids uuid[] := '{}'::uuid[];
  v_income_ids uuid[] := '{}'::uuid[];
  v_bill_id uuid;
begin
  if tg_table_name = 'school_student_tuition_bills' then
    if tg_op <> 'INSERT' then
      v_bill_ids := array_append(v_bill_ids, old.id);
      v_income_ids := array_append(v_income_ids, old.income_record_id);
    end if;
    if tg_op <> 'DELETE' then
      v_bill_ids := array_append(v_bill_ids, new.id);
      v_income_ids := array_append(v_income_ids, new.income_record_id);
    end if;
  else
    if tg_op <> 'INSERT' then
      v_income_ids := array_append(v_income_ids, old.id);
      v_bill_ids := array_append(v_bill_ids, old.tuition_bill_id);
      if old.source_type = 'student_tuition_bill' then
        v_bill_ids := array_append(v_bill_ids, old.source_id);
      end if;
    end if;
    if tg_op <> 'DELETE' then
      v_income_ids := array_append(v_income_ids, new.id);
      v_bill_ids := array_append(v_bill_ids, new.tuition_bill_id);
      if new.source_type = 'student_tuition_bill' then
        v_bill_ids := array_append(v_bill_ids, new.source_id);
      end if;
    end if;
  end if;

  select v_bill_ids || coalesce(array_agg(distinct b.id), '{}'::uuid[])
  into v_bill_ids
  from public.school_student_tuition_bills b
  where b.income_record_id = any(v_income_ids);

  for v_bill_id in
    select distinct affected.bill_id
    from unnest(v_bill_ids) as affected(bill_id)
    where affected.bill_id is not null
  loop
    perform public.school_validate_tuition_bill_income_for_bill(v_bill_id);
  end loop;

  return null;
end;
$$;

create or replace function public.school_validate_tuition_bill_lessons_for_bill(
  p_bill_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bill public.school_student_tuition_bills%rowtype;
  v_count integer;
  v_hours numeric;
  v_fee numeric;
  v_bad_rows integer;
begin
  if p_bill_id is null then
    return;
  end if;

  select * into v_bill
  from public.school_student_tuition_bills b
  where b.id = p_bill_id;

  if not found or v_bill.billing_role is null then
    return;
  end if;

  select
    count(*)::integer,
    coalesce(sum(rel.duration_hours_snapshot), 0),
    coalesce(sum(rel.lesson_fee_jpy_snapshot), 0),
    count(*) filter (
      where rel.relation_role is distinct from v_bill.billing_role
         or rel.student_id_snapshot is distinct from v_bill.student_id
         or rel.business_entity_id_snapshot is distinct from v_bill.business_entity_id
         or rel.billing_month_snapshot is distinct from v_bill.billing_month
         or rel.week_start_date_snapshot is not null
         or rel.scheduled_lesson_date_snapshot is not null
         or rel.attribution_confidence is distinct from 'medium'
         or rel.snapshot_source is distinct from 'bill_json_exact_id_plus_current_source_fields_aggregate_verified'
         or rel.line_no > jsonb_array_length(coalesce(v_bill.source_snapshot -> 'planned_lesson_ids', '[]'::jsonb))
         or (v_bill.source_snapshot -> 'planned_lesson_ids' ->> (rel.line_no - 1))::uuid is distinct from rel.planned_lesson_id
    )::integer
  into v_count, v_hours, v_fee, v_bad_rows
  from public.school_student_tuition_bill_lessons rel
  where rel.tuition_bill_id = v_bill.id;

  if v_bill.billing_role in ('incident_duplicate', 'legacy_cancelled') and exists (
    select 1
    from public.school_student_tuition_bill_lessons rel
    where rel.tuition_bill_id = v_bill.id
      and not exists (
        select 1
        from public.school_student_tuition_bill_lessons canonical
        where canonical.planned_lesson_id = rel.planned_lesson_id
          and canonical.relation_role = 'canonical_charge'
      )
  ) then
    raise exception 'TUITION_NONCANONICAL_LESSON_WITHOUT_CANONICAL: bill % contains an unconsumed lesson.', v_bill.id;
  end if;

  if v_count is distinct from v_bill.planned_lesson_count
     or v_hours is distinct from v_bill.planned_lesson_hours
     or v_fee is distinct from v_bill.planned_lesson_fee_jpy
     or v_fee is distinct from v_bill.bill_amount_jpy
     or v_bad_rows <> 0 then
    raise exception 'TUITION_BILL_LESSON_MISMATCH: normalized lessons do not match frozen bill %.', v_bill.id;
  end if;

  return;
end;
$$;

create or replace function public.school_assert_tuition_bill_lesson_consistency()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bill_ids uuid[] := '{}'::uuid[];
  v_bill_id uuid;
begin
  if tg_table_name = 'school_student_tuition_bill_lessons' then
    if tg_op <> 'INSERT' then
      v_bill_ids := array_append(v_bill_ids, old.tuition_bill_id);
    end if;
    if tg_op <> 'DELETE' then
      v_bill_ids := array_append(v_bill_ids, new.tuition_bill_id);
    end if;
  else
    if tg_op <> 'INSERT' then
      v_bill_ids := array_append(v_bill_ids, old.id);
    end if;
    if tg_op <> 'DELETE' then
      v_bill_ids := array_append(v_bill_ids, new.id);
    end if;
  end if;

  for v_bill_id in
    select distinct affected.bill_id
    from unnest(v_bill_ids) as affected(bill_id)
    where affected.bill_id is not null
  loop
    perform public.school_validate_tuition_bill_lessons_for_bill(v_bill_id);
  end loop;

  return null;
end;
$$;

revoke all on function public.school_validate_tuition_identity_for_bill(uuid)
  from public, anon, authenticated;
revoke all on function public.school_assert_tuition_identity_consistency()
  from public, anon, authenticated;
revoke all on function public.school_validate_tuition_bill_income_for_bill(uuid)
  from public, anon, authenticated;
revoke all on function public.school_assert_tuition_bill_income_consistency()
  from public, anon, authenticated;
revoke all on function public.school_validate_tuition_bill_lessons_for_bill(uuid)
  from public, anon, authenticated;
revoke all on function public.school_assert_tuition_bill_lesson_consistency()
  from public, anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.school_student_tuition_bills'::regclass
      and tgname = 'school_incident_tuition_bill_immutable'
      and not tgisinternal
  ) then
    create trigger school_incident_tuition_bill_immutable
    before update or delete on public.school_student_tuition_bills
    for each row execute function public.school_guard_incident_tuition_bill_immutable();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.school_personal_cash_income_linkage_events'::regclass
      and tgname = 'school_incident_income_cash_linkage_guard'
      and not tgisinternal
  ) then
    create trigger school_incident_income_cash_linkage_guard
    before insert or update on public.school_personal_cash_income_linkage_events
    for each row execute function public.school_guard_incident_income_downstream_write();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.school_account_transactions'::regclass
      and tgname = 'school_incident_income_account_transaction_guard'
      and not tgisinternal
  ) then
    create trigger school_incident_income_account_transaction_guard
    before insert or update on public.school_account_transactions
    for each row execute function public.school_guard_incident_income_downstream_write();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.school_student_tuition_billing_identities'::regclass
      and tgname = 'school_tuition_identity_consistency'
      and not tgisinternal
  ) then
    create constraint trigger school_tuition_identity_consistency
    after insert or update or delete on public.school_student_tuition_billing_identities
    deferrable initially deferred
    for each row execute function public.school_assert_tuition_identity_consistency();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.school_student_tuition_bills'::regclass
      and tgname = 'school_tuition_bill_identity_consistency'
      and not tgisinternal
  ) then
    create constraint trigger school_tuition_bill_identity_consistency
    after insert or update or delete on public.school_student_tuition_bills
    deferrable initially deferred
    for each row execute function public.school_assert_tuition_identity_consistency();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.school_student_tuition_bills'::regclass
      and tgname = 'school_tuition_bill_income_consistency'
      and not tgisinternal
  ) then
    create constraint trigger school_tuition_bill_income_consistency
    after insert or update or delete on public.school_student_tuition_bills
    deferrable initially deferred
    for each row execute function public.school_assert_tuition_bill_income_consistency();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.school_income_records'::regclass
      and tgname = 'school_tuition_income_bill_consistency'
      and not tgisinternal
  ) then
    create constraint trigger school_tuition_income_bill_consistency
    after insert or update or delete on public.school_income_records
    deferrable initially deferred
    for each row execute function public.school_assert_tuition_bill_income_consistency();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.school_student_tuition_bills'::regclass
      and tgname = 'school_tuition_bill_lesson_consistency'
      and not tgisinternal
  ) then
    create constraint trigger school_tuition_bill_lesson_consistency
    after insert or update or delete on public.school_student_tuition_bills
    deferrable initially deferred
    for each row execute function public.school_assert_tuition_bill_lesson_consistency();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.school_student_tuition_bill_lessons'::regclass
      and tgname = 'school_tuition_bill_lesson_row_consistency'
      and not tgisinternal
  ) then
    create constraint trigger school_tuition_bill_lesson_row_consistency
    after insert or update or delete on public.school_student_tuition_bill_lessons
    deferrable initially deferred
    for each row execute function public.school_assert_tuition_bill_lesson_consistency();
  end if;
end;
$$;

\if :r1b_schema_commit
  commit;
\else
  rollback;
\endif
