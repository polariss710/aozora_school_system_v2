-- School V2 tuition P0-B2: DB-authoritative settlement adjustment modes.
-- Status: VERIFIED AND DEPLOYED 2026-08-03; rollback/redeploy proven.
-- Usage: psql -v p0b2_migration_commit=0|1 -f this_file.sql
-- Business rows are never updated by this migration.
\set ON_ERROR_STOP on
\pset pager off
\if :{?p0b2_migration_commit}
\else
  \set p0b2_migration_commit 0
\endif

begin;
set local lock_timeout = '8s';
set local statement_timeout = '240s';

do $preflight$
declare
  v_bad text;
begin
  select string_agg(signature || '=' || actual_md5, ', ' order by signature)
  into v_bad
  from (
    select expected.signature,
      md5(pg_get_functiondef(expected.signature::regprocedure)) as actual_md5,
      expected.expected_md5, expected.rollback_md5
    from (values
      ('public.school_get_student_monthly_settlement_preview(uuid,text)',
       '1ddcfdd0344ba0ea3cf06d12058796ba',
       'b6751ba08f335db16d09c95a141dc25c'),
      ('public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)',
       'f8b33842d6dbaa3cbdeca20236146c82',
       'e5771971c46837d00ea8996ae068a80b'),
      ('public.school_lock_student_monthly_settlement(uuid,text,text)',
       'efaa26100bc5cbd2e61be63e7eaa46ef',
       '8458c5c219ce2c396c3ff1a63e026940'),
      ('public.school_relock_student_monthly_settlement(uuid,text)',
       '38efb4f3170f39359ca67ba23ac1ccae',
       '14bee6bd525664a80f88c66f73784ee8')
    ) expected(signature, expected_md5, rollback_md5)
  ) checked
  where actual_md5 not in (expected_md5, rollback_md5);
  if v_bad is not null then
    raise exception 'P0B2_PRODUCTION_FUNCTION_DRIFT: %', v_bad;
  end if;

  if exists (
    select 1 from public.school_student_settlement_adjustment_drafts
    where adjustment_source is null
       or adjustment_source not in (
         'carry_final_balance', 'clear_balance', 'manual_adjustment'
       )
  ) or exists (
    select 1 from public.school_student_settlement_adjustments
    where adjustment_source is null
       or adjustment_source not in (
         'carry_final_balance', 'clear_balance', 'manual_adjustment'
       )
  ) then
    raise exception 'P0B2_EXISTING_ADJUSTMENT_MODE_INVALID';
  end if;

  if exists (
    select settlement_id
    from public.school_student_settlement_adjustments
    group by settlement_id
    having count(*) > 1
  ) then
    raise exception 'P0B2_EXISTING_POSTED_ADJUSTMENT_DUPLICATE';
  end if;
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'school_tuition_p0b2_%'
  ) or exists (
    select 1 from pg_trigger
    where not tgisinternal and tgname like 'school_tuition_p0b2_%'
  ) then
    raise exception 'P0B2_OBJECT_ALREADY_EXISTS';
  end if;
end
$preflight$;

create temporary table tuition_p0b2_business_baseline(
  object_name text primary key, row_count bigint not null,
  full_hash text not null
) on commit drop;

insert into tuition_p0b2_business_baseline
select 'settlement',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_monthly_settlements t
union all select 'draft',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustment_drafts t
union all select 'adjustment',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_adjustments t
union all select 'carryover',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_settlement_carryovers t
union all select 'lesson',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_lesson_records t
union all select 'bill',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bills t
union all select 'identity',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_billing_identities t
union all select 'bill_lesson',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_student_tuition_bill_lessons t
union all select 'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_income_records t
union all select 'cash_linkage',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),'')) from public.school_personal_cash_income_linkage_events t;

alter table public.school_student_settlement_adjustment_drafts
  add constraint school_student_settlement_adjustment_drafts_mode_chk
  check (adjustment_source in (
    'carry_final_balance', 'clear_balance', 'manual_adjustment'
  )) not valid;
alter table public.school_student_settlement_adjustment_drafts
  validate constraint school_student_settlement_adjustment_drafts_mode_chk;

alter table public.school_student_settlement_adjustments
  add constraint school_student_settlement_adjustments_mode_chk
  check (adjustment_source in (
    'carry_final_balance', 'clear_balance', 'manual_adjustment'
  )) not valid;
alter table public.school_student_settlement_adjustments
  validate constraint school_student_settlement_adjustments_mode_chk;

create unique index school_student_settlement_adjustments_settlement_uidx
  on public.school_student_settlement_adjustments(settlement_id);

create or replace function public.school_tuition_p0b2_resolve_adjustment(
  p_adjustment_mode text,
  p_explicit_user_amount_cny numeric,
  p_authoritative_system_difference_cny numeric
)
returns table (
  adjustment_mode text,
  authoritative_system_difference_cny numeric,
  resolved_adjustment_amount_cny numeric,
  resolved_carryover_cny numeric
)
language plpgsql
immutable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_system_difference numeric;
  v_adjustment numeric;
begin
  if p_adjustment_mode is null
     or p_adjustment_mode not in (
       'carry_final_balance', 'clear_balance', 'manual_adjustment'
     ) then
    raise exception 'SETTLEMENT_ADJUSTMENT_MODE_INVALID';
  end if;

  if p_authoritative_system_difference_cny is null
     or p_authoritative_system_difference_cny::text in (
       'NaN', 'Infinity', '-Infinity'
     ) then
    raise exception 'SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH';
  end if;
  v_system_difference := round(p_authoritative_system_difference_cny, 2);

  if p_adjustment_mode in ('carry_final_balance', 'clear_balance') then
    if p_explicit_user_amount_cny is not null then
      raise exception 'SETTLEMENT_ADJUSTMENT_AMOUNT_FORBIDDEN_FOR_MODE';
    end if;
    if p_adjustment_mode = 'carry_final_balance' then
      v_adjustment := 0.00;
    else
      v_adjustment := -v_system_difference;
    end if;
  else
    if p_explicit_user_amount_cny is null then
      raise exception 'SETTLEMENT_MANUAL_ADJUSTMENT_AMOUNT_REQUIRED';
    end if;
    if p_explicit_user_amount_cny::text in ('NaN', 'Infinity', '-Infinity') then
      raise exception 'SETTLEMENT_MANUAL_ADJUSTMENT_AMOUNT_INVALID';
    end if;
    v_adjustment := round(p_explicit_user_amount_cny, 2);
  end if;

  return query select
    p_adjustment_mode,
    v_system_difference,
    v_adjustment,
    round(v_system_difference + v_adjustment, 2);
end
$function$;

comment on function public.school_tuition_p0b2_resolve_adjustment(text,numeric,numeric) is
  'Owner-only P0-B2 mode resolver. carry_final_balance resolves to 0 adjustment, clear_balance to the exact inverse of the locked DB system difference, and manual_adjustment to the rounded explicit user amount.';

create or replace function public.school_tuition_p0b2_guard_draft_row()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_business_entity_id uuid;
  v_system_difference numeric;
  v_resolution record;
  v_settlement public.school_student_monthly_settlements%rowtype;
  v_posted public.school_student_settlement_adjustments%rowtype;
begin
  if tg_op = 'DELETE' then
    return old;
  end if;

  if new.app_type <> 'school'
     or new.adjustment_source not in (
       'carry_final_balance', 'clear_balance', 'manual_adjustment'
     ) then
    raise exception 'SETTLEMENT_ADJUSTMENT_MODE_INVALID';
  end if;

  if new.status = 'active' then
    if new.settlement_id is not null or new.consumed_at is not null then
      raise exception 'SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH';
    end if;
    select s.business_entity_id into v_business_entity_id
    from public.school_students s
    where s.id = new.student_id and s.app_type = 'school';
    if not found or v_business_entity_id is null
       or new.business_entity_id is distinct from v_business_entity_id then
      raise exception 'SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH';
    end if;
    perform public.school_tuition_p0a_lock_settlement_mutation_scope(
      new.student_id, v_business_entity_id, new.year_month
    );
    perform public.school_assert_tuition_settlement_month_mutable(
      new.student_id, new.year_month
    );
    select summary.final_due_cny into strict v_system_difference
    from public.school_get_student_monthly_settlement_summary(
      new.student_id, new.year_month
    ) summary;
    select * into strict v_resolution
    from public.school_tuition_p0b2_resolve_adjustment(
      new.adjustment_source,
      case when new.adjustment_source = 'manual_adjustment'
        then new.adjustment_amount_cny else null end,
      v_system_difference
    );
    if new.adjustment_amount_cny is distinct from
       v_resolution.resolved_adjustment_amount_cny then
      raise exception 'SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH';
    end if;
  elsif new.status = 'consumed' then
    if new.settlement_id is null or new.consumed_at is null then
      raise exception 'SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH';
    end if;
    select * into strict v_settlement
    from public.school_student_monthly_settlements
    where id = new.settlement_id;
    select * into strict v_posted
    from public.school_student_settlement_adjustments
    where settlement_id = new.settlement_id;
    if new.student_id is distinct from v_settlement.student_id
       or new.year_month is distinct from v_settlement.year_month
       or new.business_entity_id is distinct from v_settlement.business_entity_id
       or new.adjustment_source is distinct from v_posted.adjustment_source
       or new.adjustment_amount_cny is distinct from v_posted.adjustment_amount_cny
       or new.adjustment_reason is distinct from v_posted.adjustment_reason
       or new.note is distinct from v_posted.note then
      raise exception 'SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH';
    end if;
  else
    raise exception 'SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH';
  end if;
  return new;
end
$function$;

create or replace function public.school_tuition_p0b2_guard_posted_adjustment()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_settlement public.school_student_monthly_settlements%rowtype;
  v_resolution record;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    raise exception 'SETTLEMENT_POSTED_ADJUSTMENT_IMMUTABLE';
  end if;
  if new.status <> 'posted' or new.app_type <> 'school' then
    raise exception 'SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH';
  end if;
  select * into strict v_settlement
  from public.school_student_monthly_settlements
  where id = new.settlement_id;
  if v_settlement.settlement_status <> 'locked'
     or new.student_id is distinct from v_settlement.student_id
     or new.year_month is distinct from v_settlement.year_month
     or new.business_entity_id is distinct from v_settlement.business_entity_id then
    raise exception 'SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH';
  end if;
  select * into strict v_resolution
  from public.school_tuition_p0b2_resolve_adjustment(
    new.adjustment_source,
    case when new.adjustment_source = 'manual_adjustment'
      then new.adjustment_amount_cny else null end,
    v_settlement.system_difference_cny
  );
  if new.adjustment_amount_cny is distinct from
       v_resolution.resolved_adjustment_amount_cny
     or v_settlement.adjustment_amount_cny is distinct from
       v_resolution.resolved_adjustment_amount_cny
     or v_settlement.carryover_amount_cny is distinct from
       v_resolution.resolved_carryover_cny then
    raise exception 'SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH';
  end if;
  return new;
end
$function$;

create or replace function public.school_tuition_p0b2_guard_settlement_resolution()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_posted public.school_student_settlement_adjustments%rowtype;
  v_posted_count integer;
  v_resolution record;
begin
  if new.settlement_status <> 'locked' then
    return null;
  end if;
  if new.system_difference_cny is null
     or new.adjustment_amount_cny is null
     or new.carryover_amount_cny is null then
    raise exception 'SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH';
  end if;
  select count(*) into v_posted_count
  from public.school_student_settlement_adjustments
  where settlement_id = new.id;
  if v_posted_count > 1 then
    raise exception 'SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH';
  elsif v_posted_count = 1 then
    select * into strict v_posted
    from public.school_student_settlement_adjustments
    where settlement_id = new.id;
    select * into strict v_resolution
    from public.school_tuition_p0b2_resolve_adjustment(
      v_posted.adjustment_source,
      case when v_posted.adjustment_source = 'manual_adjustment'
        then v_posted.adjustment_amount_cny else null end,
      new.system_difference_cny
    );
  else
    select * into strict v_resolution
    from public.school_tuition_p0b2_resolve_adjustment(
      'carry_final_balance', null, new.system_difference_cny
    );
  end if;
  if new.adjustment_amount_cny is distinct from
       v_resolution.resolved_adjustment_amount_cny
     or new.carryover_amount_cny is distinct from
       v_resolution.resolved_carryover_cny then
    raise exception 'SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH';
  end if;
  return null;
end
$function$;

create trigger school_tuition_p0b2_draft_resolution
before insert or update on public.school_student_settlement_adjustment_drafts
for each row execute function public.school_tuition_p0b2_guard_draft_row();

create trigger school_tuition_p0b2_posted_resolution
before insert or update or delete on public.school_student_settlement_adjustments
for each row execute function public.school_tuition_p0b2_guard_posted_adjustment();

create constraint trigger school_tuition_p0b2_settlement_resolution
after insert or update on public.school_student_monthly_settlements
deferrable initially deferred
for each row execute function public.school_tuition_p0b2_guard_settlement_resolution();

create or replace function public.school_get_student_monthly_settlement_preview(
  p_student_id uuid,
  p_year_month text
)
returns table (
  student_id uuid, year_month text, business_entity_id uuid,
  exchange_rate numeric, carryover_cny numeric, planned_hours numeric,
  actual_hours numeric, planned_fee_jpy numeric, planned_fee_cny numeric,
  planned_total_cny numeric, actual_fee_jpy numeric, actual_fee_cny numeric,
  received_jpy numeric, received_cny numeric, received_equivalent_cny numeric,
  final_due_cny numeric, adjustment_amount_cny numeric,
  adjustment_source text, adjustment_reason text, adjustment_note text,
  locked_carryover_cny numeric, draft_id uuid, draft_status text,
  draft_updated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_year_month text := nullif(trim(coalesce(p_year_month, '')), '');
  v_business_entity_id uuid;
  v_summary record;
  v_draft public.school_student_settlement_adjustment_drafts%rowtype;
  v_resolution record;
begin
  if p_student_id is null or v_year_month is null
     or v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'SETTLEMENT_ADJUSTMENT_SCOPE_INVALID';
  end if;
  select s.business_entity_id into v_business_entity_id
  from public.school_students s
  where s.id = p_student_id and s.app_type = 'school';
  if not found or v_business_entity_id is null then
    raise exception 'SETTLEMENT_ADJUSTMENT_SCOPE_INVALID';
  end if;
  perform public.school_tuition_p0a_lock_settlement_mutation_scope(
    p_student_id, v_business_entity_id, v_year_month
  );
  select * into strict v_summary
  from public.school_get_student_monthly_settlement_summary(
    p_student_id, v_year_month
  );
  select * into v_draft
  from public.school_student_settlement_adjustment_drafts d
  where d.student_id = p_student_id and d.year_month = v_year_month
    and d.app_type = 'school' and d.status = 'active'
  order by d.updated_at desc, d.created_at desc
  limit 1;
  if found then
    select * into strict v_resolution
    from public.school_tuition_p0b2_resolve_adjustment(
      v_draft.adjustment_source,
      case when v_draft.adjustment_source = 'manual_adjustment'
        then v_draft.adjustment_amount_cny else null end,
      v_summary.final_due_cny
    );
  else
    select * into strict v_resolution
    from public.school_tuition_p0b2_resolve_adjustment(
      'carry_final_balance', null, v_summary.final_due_cny
    );
  end if;
  return query select
    v_summary.student_id, v_summary.year_month, v_business_entity_id,
    v_summary.exchange_rate, v_summary.carryover_cny,
    v_summary.planned_hours, v_summary.actual_hours,
    v_summary.planned_fee_jpy, v_summary.planned_fee_cny,
    v_summary.planned_total_cny, v_summary.actual_fee_jpy,
    v_summary.actual_fee_cny, v_summary.received_jpy,
    v_summary.received_cny, v_summary.received_equivalent_cny,
    v_resolution.authoritative_system_difference_cny,
    v_resolution.resolved_adjustment_amount_cny,
    case when v_draft.id is null then null else v_draft.adjustment_source end,
    case when v_draft.id is null then null else v_draft.adjustment_reason end,
    case when v_draft.id is null then null else v_draft.note end,
    v_resolution.resolved_carryover_cny,
    v_draft.id, v_draft.status, v_draft.updated_at;
end
$function$;

create or replace function public.school_set_student_monthly_settlement_draft_adjustment(
  p_student_id uuid,
  p_year_month text,
  p_adjustment_amount_cny numeric,
  p_adjustment_source text default 'manual_adjustment',
  p_adjustment_reason text default null,
  p_note text default null
)
returns table (
  student_id uuid, year_month text, business_entity_id uuid,
  exchange_rate numeric, carryover_cny numeric, planned_hours numeric,
  actual_hours numeric, planned_fee_jpy numeric, planned_fee_cny numeric,
  planned_total_cny numeric, actual_fee_jpy numeric, actual_fee_cny numeric,
  received_jpy numeric, received_cny numeric, received_equivalent_cny numeric,
  final_due_cny numeric, adjustment_amount_cny numeric,
  adjustment_source text, adjustment_reason text, adjustment_note text,
  locked_carryover_cny numeric, draft_id uuid, draft_status text,
  draft_updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_year_month text := nullif(trim(coalesce(p_year_month, '')), '');
  v_reason text := nullif(trim(coalesce(p_adjustment_reason, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_business_entity_id uuid;
  v_existing_status text;
  v_system_difference numeric;
  v_resolution record;
  v_now timestamptz := now();
begin
  if p_student_id is null or v_year_month is null
     or v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'SETTLEMENT_ADJUSTMENT_SCOPE_INVALID';
  end if;
  if v_reason is null then
    raise exception 'SETTLEMENT_ADJUSTMENT_REASON_REQUIRED';
  end if;
  select s.business_entity_id into v_business_entity_id
  from public.school_students s
  where s.id = p_student_id and s.app_type = 'school';
  if not found or v_business_entity_id is null then
    raise exception 'SETTLEMENT_ADJUSTMENT_SCOPE_INVALID';
  end if;
  perform public.school_tuition_p0a_lock_settlement_mutation_scope(
    p_student_id, v_business_entity_id, v_year_month
  );
  perform public.school_assert_tuition_settlement_month_mutable(
    p_student_id, v_year_month
  );
  select m.settlement_status into v_existing_status
  from public.school_student_monthly_settlements m
  where m.student_id = p_student_id and m.year_month = v_year_month;
  if found and coalesce(v_existing_status, '') <> 'unlocked' then
    raise exception 'SETTLEMENT_ADJUSTMENT_LOCKED_READ_ONLY';
  end if;
  perform public.school_assert_student_monthly_settlement_no_wage_blocker(
    p_student_id, v_year_month, '保存学生月度结算差额调整'
  );
  if not exists (
    select 1
    from public.school_list_r1d_e_c_student_month_lessons(
      p_student_id, v_year_month
    ) resolved
    join public.school_lesson_records l on l.id = resolved.lesson_id
    where not (l.lesson_type = 'planned' and l.voided_at is not null)
  ) and not exists (
    select 1 from public.school_income_records i
    where i.app_type = 'school' and i.student_id = p_student_id
      and coalesce(i.settlement_month, i.year_month) = v_year_month
      and i.income_category = 'tuition' and i.status = 'received'
      and coalesce(i.include_in_student_settlement, true) = true
  ) then
    raise exception 'SETTLEMENT_ADJUSTMENT_SOURCE_FACTS_EMPTY';
  end if;
  select summary.final_due_cny into strict v_system_difference
  from public.school_get_student_monthly_settlement_summary(
    p_student_id, v_year_month
  ) summary;
  select * into strict v_resolution
  from public.school_tuition_p0b2_resolve_adjustment(
    p_adjustment_source, p_adjustment_amount_cny, v_system_difference
  );
  insert into public.school_student_settlement_adjustment_drafts (
    student_id, year_month, business_entity_id, adjustment_amount_cny,
    adjustment_source, adjustment_reason, note, status, settlement_id,
    app_type, created_by, updated_by, consumed_at, created_at, updated_at
  ) values (
    p_student_id, v_year_month, v_business_entity_id,
    v_resolution.resolved_adjustment_amount_cny,
    v_resolution.adjustment_mode, v_reason, v_note, 'active', null,
    'school', current_user, current_user, null, v_now, v_now
  ) on conflict on constraint
    school_student_settlement_adjustment_drafts_student_month_key
  do update set
    business_entity_id = excluded.business_entity_id,
    adjustment_amount_cny = excluded.adjustment_amount_cny,
    adjustment_source = excluded.adjustment_source,
    adjustment_reason = excluded.adjustment_reason,
    note = excluded.note, status = 'active', settlement_id = null,
    updated_by = current_user, consumed_at = null, updated_at = v_now;
  return query select *
  from public.school_get_student_monthly_settlement_preview(
    p_student_id, v_year_month
  );
end
$function$;

-- Lock and relock use the same P0-A operation/table lock and then consume the
-- DB-resolved preview. Before posting, carry/clear are re-resolved against the
-- latest system difference and the draft resolved amount is refreshed.
create or replace function public.school_lock_student_monthly_settlement(
  p_student_id uuid, p_year_month text, p_note text default null
)
returns table (
  settlement_id uuid, student_id uuid, year_month text,
  business_entity_id uuid, preset_exchange_rate numeric,
  planned_lesson_fee_jpy numeric, planned_lesson_fee_cny numeric,
  actual_lesson_fee_jpy numeric, actual_lesson_fee_cny numeric,
  previous_balance_cny numeric, received_jpy numeric, received_cny numeric,
  received_equivalent_cny numeric, system_difference_cny numeric,
  adjustment_amount_cny numeric, carryover_amount_cny numeric,
  settlement_status text, locked_at timestamptz, note text,
  created_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_year_month text := nullif(trim(coalesce(p_year_month, '')), '');
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_now timestamptz := now();
  v_preview record;
  v_overage record;
  v_settlement_id uuid;
  v_adjustment_reason text;
  v_business_entity_id uuid;
begin
  if p_student_id is null or v_year_month is null
     or v_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'SETTLEMENT_ADJUSTMENT_SCOPE_INVALID';
  end if;
  select s.business_entity_id into v_business_entity_id
  from public.school_students s
  where s.id = p_student_id and s.app_type = 'school';
  if not found or v_business_entity_id is null then
    raise exception 'SETTLEMENT_ADJUSTMENT_SCOPE_INVALID';
  end if;
  perform public.school_tuition_p0a_lock_settlement_mutation_scope(
    p_student_id, v_business_entity_id, v_year_month
  );
  if exists (
    select 1 from public.school_student_monthly_settlements m
    where m.student_id = p_student_id and m.year_month = v_year_month
  ) then
    raise exception '该学生月份已存在结算快照，不能重复锁定。';
  end if;
  lock table public.school_lesson_records in share mode;
  lock table public.school_teacher_wage_lock_details in share mode;
  perform public.school_assert_student_monthly_settlement_no_wage_blocker(
    p_student_id, v_year_month, '锁定学生月度结算'
  );
  if not exists (
    select 1 from public.school_list_r1d_e_c_student_month_lessons(
      p_student_id, v_year_month
    ) resolved
    join public.school_lesson_records l on l.id = resolved.lesson_id
    where not (l.lesson_type = 'planned' and l.voided_at is not null)
  ) and not exists (
    select 1 from public.school_income_records i
    where i.app_type = 'school' and i.student_id = p_student_id
      and coalesce(i.settlement_month, i.year_month) = v_year_month
      and i.income_category = 'tuition' and i.status = 'received'
      and coalesce(i.include_in_student_settlement, true) = true
  ) then
    raise exception '该学生月份没有可结算的课时或学费收入，不能锁定。';
  end if;
  select * into strict v_preview
  from public.school_get_student_monthly_settlement_preview(
    p_student_id, v_year_month
  );
  select * into strict v_overage
  from public.school_get_student_duration_overage_aggregate(
    p_student_id, v_year_month
  );
  if v_overage.aggregation_basis <> 'live_s1_b_actual_aggregate'
     or v_overage.duration_overage_fee_cny is distinct from round(
       v_overage.duration_overage_fee_jpy
       * coalesce(v_preview.exchange_rate, 0), 2
     ) then
    raise exception 'S1_C_LOCK_OVERAGE_AGGREGATE_DRIFT';
  end if;
  if v_preview.draft_id is not null then
    update public.school_student_settlement_adjustment_drafts d
    set adjustment_amount_cny = v_preview.adjustment_amount_cny,
        updated_by = current_user, updated_at = v_now
    where d.id = v_preview.draft_id and d.status = 'active';
    if not found then
      raise exception 'SETTLEMENT_ADJUSTMENT_RESOLUTION_MISMATCH';
    end if;
    v_adjustment_reason := format(
      '%s: %s (%s)', v_preview.adjustment_source,
      v_preview.adjustment_reason, v_preview.adjustment_amount_cny
    );
  end if;
  set constraints school_tuition_p0b2_settlement_resolution deferred;
  insert into public.school_student_monthly_settlements (
    student_id, year_month, business_entity_id, preset_exchange_rate,
    planned_lesson_fee_jpy, planned_lesson_fee_cny,
    actual_lesson_fee_jpy, actual_lesson_fee_cny, previous_balance_cny,
    received_jpy, received_cny, received_equivalent_cny,
    system_difference_cny, adjustment_amount_cny, adjustment_reason,
    carryover_amount_cny, settlement_status, locked_at, note,
    created_at, updated_at, duration_overage_minutes,
    duration_overage_fee_jpy, duration_overage_fee_cny,
    duration_overage_actual_count, duration_overage_policy_version,
    duration_overage_source
  ) values (
    p_student_id, v_year_month, v_preview.business_entity_id,
    coalesce(v_preview.exchange_rate, 0),
    coalesce(v_preview.planned_fee_jpy, 0),
    coalesce(v_preview.planned_fee_cny, 0),
    coalesce(v_preview.actual_fee_jpy, 0),
    coalesce(v_preview.actual_fee_cny, 0),
    coalesce(v_preview.carryover_cny, 0),
    coalesce(v_preview.received_jpy, 0),
    coalesce(v_preview.received_cny, 0),
    coalesce(v_preview.received_equivalent_cny, 0),
    v_preview.final_due_cny, v_preview.adjustment_amount_cny,
    v_adjustment_reason, v_preview.locked_carryover_cny,
    'locked', v_now, v_note, v_now, v_now,
    v_overage.duration_overage_minutes,
    v_overage.duration_overage_fee_jpy,
    v_overage.duration_overage_fee_cny,
    v_overage.duration_overage_actual_count,
    'student_duration_overage_v1', 'monthly_settlement_lock'
  ) returning id into v_settlement_id;
  if v_preview.draft_id is not null then
    insert into public.school_student_settlement_adjustments (
      settlement_id, student_id, year_month, business_entity_id,
      adjustment_amount_cny, adjustment_source, adjustment_reason, note,
      status, app_type, created_at, updated_at
    ) values (
      v_settlement_id, p_student_id, v_year_month,
      v_preview.business_entity_id, v_preview.adjustment_amount_cny,
      v_preview.adjustment_source, v_preview.adjustment_reason,
      v_preview.adjustment_note, 'posted', 'school', v_now, v_now
    );
    update public.school_student_settlement_adjustment_drafts d
    set status = 'consumed', settlement_id = v_settlement_id,
        consumed_at = v_now, updated_by = current_user, updated_at = v_now
    where d.id = v_preview.draft_id;
  end if;
  set constraints school_tuition_p0b2_settlement_resolution immediate;
  return query select
    m.id, m.student_id, m.year_month, m.business_entity_id,
    m.preset_exchange_rate, m.planned_lesson_fee_jpy,
    m.planned_lesson_fee_cny, m.actual_lesson_fee_jpy,
    m.actual_lesson_fee_cny, m.previous_balance_cny,
    m.received_jpy, m.received_cny, m.received_equivalent_cny,
    m.system_difference_cny, m.adjustment_amount_cny,
    m.carryover_amount_cny, m.settlement_status, m.locked_at,
    m.note, m.created_at, m.updated_at
  from public.school_student_monthly_settlements m
  where m.id = v_settlement_id;
end
$function$;

create or replace function public.school_relock_student_monthly_settlement(
  p_settlement_id uuid, p_note text default null
)
returns table (
  settlement_id uuid, student_id uuid, year_month text,
  business_entity_id uuid, preset_exchange_rate numeric,
  planned_lesson_fee_jpy numeric, planned_lesson_fee_cny numeric,
  actual_lesson_fee_jpy numeric, actual_lesson_fee_cny numeric,
  previous_balance_cny numeric, received_jpy numeric, received_cny numeric,
  received_equivalent_cny numeric, system_difference_cny numeric,
  adjustment_amount_cny numeric, carryover_amount_cny numeric,
  settlement_status text, locked_at timestamptz, unlocked_at timestamptz,
  unlock_reason text, note text, created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_settlement public.school_student_monthly_settlements%rowtype;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_now timestamptz := now();
  v_preview record;
  v_overage record;
  v_adjustment_reason text;
begin
  if p_settlement_id is null then
    raise exception '请选择要重新锁定的学生月度结算。';
  end if;
  select * into v_settlement
  from public.school_student_monthly_settlements
  where id = p_settlement_id;
  if not found or v_settlement.business_entity_id is null then
    raise exception '没有找到对应的学生月度结算。';
  end if;
  perform public.school_tuition_p0a_lock_settlement_mutation_scope(
    v_settlement.student_id, v_settlement.business_entity_id,
    v_settlement.year_month
  );
  select * into strict v_settlement
  from public.school_student_monthly_settlements
  where id = p_settlement_id for update;
  perform public.school_assert_tuition_settlement_mutable(v_settlement.id);
  if coalesce(v_settlement.settlement_status, '') <> 'unlocked' then
    raise exception '只有已撤销锁定的学生月度结算可以重新锁定。';
  end if;
  if exists (
    select 1 from public.school_legacy_settlement_snapshot_basis_evidence e
    where e.settlement_snapshot_id = v_settlement.id
  ) then
    raise exception 'R1D_E_C_LEGACY_LOCKED_SNAPSHOT_IMMUTABLE';
  end if;
  if exists (
    select 1 from public.school_student_settlement_adjustments a
    where a.settlement_id = v_settlement.id and a.status = 'posted'
  ) then
    raise exception '该结算已有差额调整记录，不能通过重新锁定重算快照。';
  end if;
  if exists (
    select 1 from public.school_student_settlement_carryovers c
    where c.source_settlement_id = v_settlement.id
      and coalesce(c.status, 'active') = 'active'
  ) then
    raise exception '该结算已生成有效结转，不能重新锁定。';
  end if;
  if not exists (
    select 1 from public.school_list_r1d_e_c_student_month_lessons(
      v_settlement.student_id, v_settlement.year_month
    ) resolved
    join public.school_lesson_records l on l.id = resolved.lesson_id
    where not (l.lesson_type = 'planned' and l.voided_at is not null)
  ) and not exists (
    select 1 from public.school_income_records i
    where i.app_type = 'school'
      and i.student_id = v_settlement.student_id
      and coalesce(i.settlement_month, i.year_month) = v_settlement.year_month
      and i.income_category = 'tuition' and i.status = 'received'
      and coalesce(i.include_in_student_settlement, true) = true
  ) then
    raise exception '该学生月份没有可结算的课时或学费收入，不能重新锁定。';
  end if;
  lock table public.school_lesson_records in share mode;
  lock table public.school_teacher_wage_lock_details in share mode;
  perform public.school_assert_student_monthly_settlement_no_wage_blocker(
    v_settlement.student_id, v_settlement.year_month,
    '重新锁定学生月度结算'
  );
  select * into strict v_preview
  from public.school_get_student_monthly_settlement_preview(
    v_settlement.student_id, v_settlement.year_month
  );
  select * into strict v_overage
  from public.school_get_student_duration_overage_aggregate(
    v_settlement.student_id, v_settlement.year_month
  );
  if v_overage.aggregation_basis <> 'live_s1_b_actual_aggregate'
     or v_overage.duration_overage_fee_cny is distinct from round(
       v_overage.duration_overage_fee_jpy
       * coalesce(v_preview.exchange_rate, 0), 2
     ) then
    raise exception 'S1_C_RELOCK_OVERAGE_AGGREGATE_DRIFT';
  end if;
  if v_preview.draft_id is not null then
    update public.school_student_settlement_adjustment_drafts d
    set adjustment_amount_cny = v_preview.adjustment_amount_cny,
        updated_by = current_user, updated_at = v_now
    where d.id = v_preview.draft_id and d.status = 'active';
    v_adjustment_reason := format(
      '%s: %s (%s)', v_preview.adjustment_source,
      v_preview.adjustment_reason, v_preview.adjustment_amount_cny
    );
  end if;
  set constraints school_tuition_p0b2_settlement_resolution deferred;
  update public.school_student_monthly_settlements m set
    business_entity_id = v_preview.business_entity_id,
    preset_exchange_rate = coalesce(v_preview.exchange_rate, 0),
    planned_lesson_fee_jpy = coalesce(v_preview.planned_fee_jpy, 0),
    planned_lesson_fee_cny = coalesce(v_preview.planned_fee_cny, 0),
    actual_lesson_fee_jpy = coalesce(v_preview.actual_fee_jpy, 0),
    actual_lesson_fee_cny = coalesce(v_preview.actual_fee_cny, 0),
    previous_balance_cny = coalesce(v_preview.carryover_cny, 0),
    received_jpy = coalesce(v_preview.received_jpy, 0),
    received_cny = coalesce(v_preview.received_cny, 0),
    received_equivalent_cny = coalesce(v_preview.received_equivalent_cny, 0),
    system_difference_cny = v_preview.final_due_cny,
    adjustment_amount_cny = v_preview.adjustment_amount_cny,
    adjustment_reason = v_adjustment_reason,
    carryover_amount_cny = v_preview.locked_carryover_cny,
    duration_overage_minutes = v_overage.duration_overage_minutes,
    duration_overage_fee_jpy = v_overage.duration_overage_fee_jpy,
    duration_overage_fee_cny = v_overage.duration_overage_fee_cny,
    duration_overage_actual_count = v_overage.duration_overage_actual_count,
    duration_overage_policy_version = 'student_duration_overage_v1',
    duration_overage_source = 'monthly_settlement_lock',
    settlement_status = 'locked', locked_at = v_now,
    note = v_note, updated_at = v_now
  where m.id = v_settlement.id;
  if v_preview.draft_id is not null then
    insert into public.school_student_settlement_adjustments (
      settlement_id, student_id, year_month, business_entity_id,
      adjustment_amount_cny, adjustment_source, adjustment_reason, note,
      status, app_type, created_at, updated_at
    ) values (
      v_settlement.id, v_settlement.student_id, v_settlement.year_month,
      v_preview.business_entity_id, v_preview.adjustment_amount_cny,
      v_preview.adjustment_source, v_preview.adjustment_reason,
      v_preview.adjustment_note, 'posted', 'school', v_now, v_now
    );
    update public.school_student_settlement_adjustment_drafts d
    set status = 'consumed', settlement_id = v_settlement.id,
        consumed_at = v_now, updated_by = current_user, updated_at = v_now
    where d.id = v_preview.draft_id;
  end if;
  set constraints school_tuition_p0b2_settlement_resolution immediate;
  return query select
    m.id, m.student_id, m.year_month, m.business_entity_id,
    m.preset_exchange_rate, m.planned_lesson_fee_jpy,
    m.planned_lesson_fee_cny, m.actual_lesson_fee_jpy,
    m.actual_lesson_fee_cny, m.previous_balance_cny,
    m.received_jpy, m.received_cny, m.received_equivalent_cny,
    m.system_difference_cny, m.adjustment_amount_cny,
    m.carryover_amount_cny, m.settlement_status, m.locked_at,
    m.unlocked_at, m.unlock_reason, m.note, m.created_at, m.updated_at
  from public.school_student_monthly_settlements m
  where m.id = v_settlement.id;
end
$function$;

alter function public.school_get_student_monthly_settlement_preview(uuid,text)
  security definer set search_path = pg_catalog, public;
alter function public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text)
  security definer set search_path = pg_catalog, public;
alter function public.school_lock_student_monthly_settlement(uuid,text,text)
  security definer set search_path = pg_catalog, public;
alter function public.school_relock_student_monthly_settlement(uuid,text)
  security definer set search_path = pg_catalog, public;

revoke all on function public.school_tuition_p0b2_resolve_adjustment(text,numeric,numeric) from public, anon, authenticated, service_role;
revoke all on function public.school_tuition_p0b2_guard_draft_row() from public, anon, authenticated, service_role;
revoke all on function public.school_tuition_p0b2_guard_posted_adjustment() from public, anon, authenticated, service_role;
revoke all on function public.school_tuition_p0b2_guard_settlement_resolution() from public, anon, authenticated, service_role;

revoke all on function public.school_get_student_monthly_settlement_preview(uuid,text) from public, anon, authenticated, service_role;
grant execute on function public.school_get_student_monthly_settlement_preview(uuid,text) to anon, authenticated, service_role;
revoke all on function public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text) from public, anon, authenticated, service_role;
grant execute on function public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text) to anon, authenticated, service_role;
revoke all on function public.school_lock_student_monthly_settlement(uuid,text,text) from public, anon, authenticated, service_role;
grant execute on function public.school_lock_student_monthly_settlement(uuid,text,text) to anon, authenticated, service_role;
revoke all on function public.school_relock_student_monthly_settlement(uuid,text) from public, anon, authenticated, service_role;
grant execute on function public.school_relock_student_monthly_settlement(uuid,text) to anon, authenticated, service_role;
revoke all on function public.school_apply_student_monthly_settlement_adjustment(uuid,numeric,text,text,text) from public, anon, authenticated, service_role;

comment on function public.school_get_student_monthly_settlement_preview(uuid,text) is
  'P0-B2 DB-authoritative preview. Uses the shared P0-A operation lock and re-resolves active carry/clear/manual drafts against the current system difference without persisting preview facts.';
comment on function public.school_set_student_monthly_settlement_draft_adjustment(uuid,text,numeric,text,text,text) is
  'P0-B2 formal draft writer. carry_final_balance and clear_balance require NULL client amount; manual_adjustment requires explicit user amount. DB resolves adjustment and carry preview under the shared operation lock.';
comment on function public.school_lock_student_monthly_settlement(uuid,text,text) is
  'P0-B2 settlement lock. Under the P0-A shared lock, recomputes current system difference, re-resolves the draft mode, freezes settlement amounts, posts one mode-preserving adjustment audit row, and consumes the draft atomically.';
comment on function public.school_relock_student_monthly_settlement(uuid,text) is
  'P0-B2 same-row relock for eligible unconsumed/unlocked settlements. Recomputes current facts and re-resolves any active mode draft under the P0-A shared lock.';

do $verify$
declare
  v_row record;
  v_current_count bigint;
  v_current_hash text;
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'school_student_settlement_adjustment_drafts_mode_chk'
      and convalidated
  ) or not exists (
    select 1 from pg_constraint
    where conname = 'school_student_settlement_adjustments_mode_chk'
      and convalidated
  ) then
    raise exception 'P0B2_MODE_CONSTRAINT_MISSING';
  end if;
  if (select count(*) from pg_trigger
      where not tgisinternal and tgname like 'school_tuition_p0b2_%') <> 3 then
    raise exception 'P0B2_TRIGGER_COUNT_INVALID';
  end if;
  if has_function_privilege('anon',
       'public.school_tuition_p0b2_resolve_adjustment(text,numeric,numeric)',
       'EXECUTE')
     or has_function_privilege('authenticated',
       'public.school_apply_student_monthly_settlement_adjustment(uuid,numeric,text,text,text)',
       'EXECUTE') then
    raise exception 'P0B2_EXECUTE_ACL_INVALID';
  end if;
  for v_row in select * from tuition_p0b2_business_baseline loop
    execute format(
      'select count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'''' order by t.id::text),'''')) from public.%I t',
      case v_row.object_name
        when 'settlement' then 'school_student_monthly_settlements'
        when 'draft' then 'school_student_settlement_adjustment_drafts'
        when 'adjustment' then 'school_student_settlement_adjustments'
        when 'carryover' then 'school_student_settlement_carryovers'
        when 'lesson' then 'school_lesson_records'
        when 'bill' then 'school_student_tuition_bills'
        when 'identity' then 'school_student_tuition_billing_identities'
        when 'bill_lesson' then 'school_student_tuition_bill_lessons'
        when 'income' then 'school_income_records'
        when 'cash_linkage' then 'school_personal_cash_income_linkage_events'
      end
    ) into v_current_count,v_current_hash;
    if v_current_count<>v_row.row_count or v_current_hash<>v_row.full_hash then
      raise exception 'P0B2_MIGRATION_BUSINESS_DATA_DRIFT: %',v_row.object_name;
    end if;
  end loop;
end
$verify$;

\if :p0b2_migration_commit
  commit;
  \echo 'P0B2_MIGRATION_COMMITTED'
\else
  rollback;
  \echo 'P0B2_MIGRATION_ROLLED_BACK'
\endif
