-- school_student_tuition_bill_preview_rpc.sql
-- Purpose:
-- - Read-only preview for student tuition bill generation.
-- - Mirrors the DB/RPC authoritative tuition bill calculation without creating
--   or updating tuition bills, income records, Cash requests, settlements,
--   lessons, account transactions, or balances.
-- - R0 requires the authoritative preview gate to be exactly
--   validation_preview_only; missing/unreadable/unexpected gate state rejects.
-- - R1C-B makes normalized bill-lesson rows and compatible bill snapshots
--   permanent fail-closed exclusions before mutable lesson state is considered.

create or replace function public.school_classify_student_tuition_candidate(
  p_scope_matches boolean,
  p_has_normalized_relation boolean,
  p_relation_roles text[],
  p_has_snapshot_evidence boolean,
  p_bill_evidence_conflict boolean,
  p_lesson_type text,
  p_status text,
  p_voided_at timestamptz,
  p_is_billable boolean,
  p_has_required_fields boolean
)
returns text
language plpgsql
immutable
set search_path = public
as $$
begin
  if p_scope_matches is distinct from true then
    return 'scope_mismatch';
  end if;

  -- Historical billing evidence takes priority over mutable operational fields.
  if p_bill_evidence_conflict is true then
    return 'bill_snapshot_conflict';
  end if;

  if p_has_normalized_relation is true then
    if 'canonical_charge' = any(coalesce(p_relation_roles, '{}'::text[])) then
      return 'already_canonical_charged';
    elsif 'incident_duplicate' = any(coalesce(p_relation_roles, '{}'::text[])) then
      return 'incident_history';
    elsif 'legacy_cancelled' = any(coalesce(p_relation_roles, '{}'::text[])) then
      return 'legacy_history';
    end if;

    -- Future formal relation roles remain fail-closed without code changes.
    return 'existing_bill_lesson_history';
  end if;

  if p_has_snapshot_evidence is true then
    return 'bill_snapshot_conflict';
  end if;

  if p_voided_at is not null
     or p_lesson_type is distinct from 'planned'
     or p_status is distinct from 'planned' then
    return 'voided_or_inactive';
  end if;

  if p_is_billable is distinct from true then
    return 'non_billable';
  end if;

  if p_has_required_fields is distinct from true then
    return 'invalid_or_incomplete_data';
  end if;

  return 'candidate';
end;
$$;

comment on function public.school_classify_student_tuition_candidate(
  boolean, boolean, text[], boolean, boolean, text, text, timestamptz, boolean, boolean
) is
  'R1C-B internal deterministic candidate classifier. Billing evidence is evaluated before mutable lesson state; no income status can reopen billed lessons.';

revoke all on function public.school_classify_student_tuition_candidate(
  boolean, boolean, text[], boolean, boolean, text, text, timestamptz, boolean, boolean
) from public, anon, authenticated, service_role;

grant execute on function public.school_classify_student_tuition_candidate(
  boolean, boolean, text[], boolean, boolean, text, text, timestamptz, boolean, boolean
) to service_role;

create or replace function public.school_list_student_tuition_candidates(
  p_student_id uuid,
  p_business_entity_id uuid,
  p_billing_month text,
  p_include_excluded boolean default false
)
returns table (
  planned_lesson_id uuid,
  student_id uuid,
  business_entity_id uuid,
  candidate_billing_month text,
  lesson_date date,
  year_month text,
  teacher_id uuid,
  subject_id uuid,
  lesson_count integer,
  duration_hours numeric,
  unit_price numeric,
  lesson_fee numeric,
  candidate_status text,
  exclusion_reason text,
  has_normalized_bill_relation boolean,
  relation_roles text[],
  associated_bill_ids uuid[],
  associated_billing_identity_ids uuid[],
  has_bill_snapshot_evidence boolean,
  snapshot_bill_ids uuid[],
  bill_evidence_conflict boolean,
  complete_row_hash text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_billing_month text := nullif(trim(coalesce(p_billing_month, '')), '');
begin
  if p_student_id is null then
    raise exception 'R1C_B_STUDENT_REQUIRED';
  end if;

  if p_business_entity_id is null then
    raise exception 'R1C_B_BUSINESS_ENTITY_REQUIRED';
  end if;

  if v_billing_month is null
     or v_billing_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'R1C_B_BILLING_MONTH_INVALID';
  end if;

  -- A malformed legacy snapshot means absence of billing evidence cannot be
  -- proven safely. Reject the whole request instead of using fuzzy matching.
  if exists (
    select 1
    from public.school_student_tuition_bills bill
    where bill.source_snapshot is null
       or not (bill.source_snapshot ? 'planned_lesson_ids')
       or jsonb_typeof(bill.source_snapshot -> 'planned_lesson_ids') <> 'array'
  ) then
    raise exception 'R1C_B_BILL_SNAPSHOT_FORMAT_UNSAFE';
  end if;

  if exists (
    select 1
    from public.school_student_tuition_bills bill
    cross join lateral jsonb_array_elements_text(
      bill.source_snapshot -> 'planned_lesson_ids'
    ) snapshot_lesson(lesson_id_text)
    where snapshot_lesson.lesson_id_text
      !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ) then
    raise exception 'R1C_B_BILL_SNAPSHOT_LESSON_ID_UNSAFE';
  end if;

  if exists (
    select 1
    from public.school_student_tuition_bills bill
    cross join lateral jsonb_array_elements_text(
      bill.source_snapshot -> 'planned_lesson_ids'
    ) snapshot_lesson(lesson_id_text)
    group by bill.id, snapshot_lesson.lesson_id_text
    having count(*) <> 1
  ) then
    raise exception 'R1C_B_BILL_SNAPSHOT_DUPLICATE_LESSON_ID';
  end if;

  return query
  with snapshot_rows as (
    select
      bill.id as bill_id,
      snapshot_lesson.lesson_id_text::uuid as planned_lesson_id,
      snapshot_lesson.line_no::integer as line_no
    from public.school_student_tuition_bills bill
    cross join lateral jsonb_array_elements_text(
      bill.source_snapshot -> 'planned_lesson_ids'
    ) with ordinality snapshot_lesson(lesson_id_text, line_no)
  ),
  relation_evidence as (
    select
      relation.planned_lesson_id,
      array_agg(distinct relation.relation_role order by relation.relation_role) as relation_roles,
      array_agg(distinct relation.tuition_bill_id order by relation.tuition_bill_id) as bill_ids,
      coalesce(
        array_agg(distinct identity.id order by identity.id)
          filter (where identity.id is not null),
        '{}'::uuid[]
      ) as identity_ids,
      bool_or(
        snapshot.bill_id is null
        or snapshot.line_no is distinct from relation.line_no
      ) as relation_snapshot_mismatch
    from public.school_student_tuition_bill_lessons relation
    left join snapshot_rows snapshot
      on snapshot.bill_id = relation.tuition_bill_id
     and snapshot.planned_lesson_id = relation.planned_lesson_id
    left join public.school_student_tuition_billing_identities identity
      on identity.canonical_bill_id = relation.tuition_bill_id
    group by relation.planned_lesson_id
  ),
  snapshot_evidence as (
    select
      snapshot.planned_lesson_id,
      array_agg(distinct snapshot.bill_id order by snapshot.bill_id) as bill_ids
    from snapshot_rows snapshot
    group by snapshot.planned_lesson_id
  ),
  evidence_rows as (
    select
      lesson.*,
      relation.planned_lesson_id is not null as has_relation,
      coalesce(relation.relation_roles, '{}'::text[]) as normalized_relation_roles,
      coalesce(relation.bill_ids, '{}'::uuid[]) as normalized_bill_ids,
      coalesce(relation.identity_ids, '{}'::uuid[]) as billing_identity_ids,
      snapshot.planned_lesson_id is not null as has_snapshot,
      coalesce(snapshot.bill_ids, '{}'::uuid[]) as historical_snapshot_bill_ids,
      (
        coalesce(relation.relation_snapshot_mismatch, false)
        or coalesce(relation.bill_ids, '{}'::uuid[])
           is distinct from coalesce(snapshot.bill_ids, '{}'::uuid[])
      ) as evidence_conflict
    from public.school_lesson_records lesson
    left join relation_evidence relation
      on relation.planned_lesson_id = lesson.id
    left join snapshot_evidence snapshot
      on snapshot.planned_lesson_id = lesson.id
    where lesson.student_id = p_student_id
      and lesson.year_month = v_billing_month
  ),
  classified as (
    select
      evidence.*,
      public.school_classify_student_tuition_candidate(
        evidence.app_type = 'school'
          and evidence.business_entity_id = p_business_entity_id,
        evidence.has_relation,
        evidence.normalized_relation_roles,
        evidence.has_snapshot,
        evidence.evidence_conflict,
        evidence.lesson_type,
        evidence.status,
        evidence.voided_at,
        evidence.is_billable,
        evidence.student_id is not null
          and evidence.business_entity_id is not null
          and evidence.lesson_date is not null
          and evidence.teacher_id is not null
          and evidence.subject_id is not null
          and evidence.lesson_count is not null
          and evidence.lesson_count > 0
          and evidence.duration_hours > 0
          and evidence.unit_price is not null
          and evidence.unit_price > 0
          and evidence.lesson_fee is not null
          and evidence.lesson_fee > 0
          and evidence.created_at is not null
          and evidence.updated_at is not null
      ) as reason_code
    from evidence_rows evidence
  )
  select
    classified.id,
    classified.student_id,
    classified.business_entity_id,
    v_billing_month,
    classified.lesson_date,
    classified.year_month,
    classified.teacher_id,
    classified.subject_id,
    classified.lesson_count,
    classified.duration_hours,
    classified.unit_price,
    classified.lesson_fee,
    case when classified.reason_code = 'candidate' then 'candidate' else 'excluded' end,
    case when classified.reason_code = 'candidate' then null else classified.reason_code end,
    classified.has_relation,
    classified.normalized_relation_roles,
    classified.normalized_bill_ids,
    classified.billing_identity_ids,
    classified.has_snapshot,
    classified.historical_snapshot_bill_ids,
    classified.evidence_conflict,
    md5((to_jsonb(classified) - array[
      'has_relation',
      'normalized_relation_roles',
      'normalized_bill_ids',
      'billing_identity_ids',
      'has_snapshot',
      'historical_snapshot_bill_ids',
      'evidence_conflict',
      'reason_code'
    ]::text[])::text)
  from classified
  where coalesce(p_include_excluded, false)
     or classified.reason_code = 'candidate'
  order by classified.lesson_date, classified.id;
end;
$$;

comment on function public.school_list_student_tuition_candidates(uuid, uuid, text, boolean) is
  'R1C-B service-role audit surface for DB-authoritative tuition candidates. Normal mode returns candidates only; include_excluded discloses structured historical and validation reasons for controlled review.';

revoke all on function public.school_list_student_tuition_candidates(uuid, uuid, text, boolean)
  from public, anon, authenticated, service_role;

grant execute on function public.school_list_student_tuition_candidates(uuid, uuid, text, boolean)
  to service_role;

create or replace function public.school_preview_student_tuition_bill(
  p_student_id uuid,
  p_billing_month text,
  p_billing_exchange_rate numeric
)
returns table (
  student_id uuid,
  business_entity_id uuid,
  billing_month text,
  previous_settlement_month text,
  previous_settlement_id uuid,
  previous_carryover_cny numeric,
  planned_lesson_count integer,
  planned_lesson_hours numeric,
  planned_lesson_fee_jpy numeric,
  bill_amount_jpy numeric,
  currency text,
  billing_exchange_rate numeric,
  billing_amount_cny numeric,
  billing_amount_currency text,
  existing_tuition_bill_id uuid,
  existing_tuition_bill_status text,
  existing_income_record_id uuid,
  existing_income_status text,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student public.school_students%rowtype;
  v_billing_month text := nullif(trim(coalesce(p_billing_month, '')), '');
  v_billing_exchange_rate numeric := p_billing_exchange_rate;
  v_previous_month text;
  v_previous_settlement public.school_student_monthly_settlements%rowtype;
  v_existing public.school_student_tuition_bills%rowtype;
  v_existing_income public.school_income_records%rowtype;
  v_planned_count integer;
  v_planned_hours numeric;
  v_planned_fee_jpy numeric;
  v_previous_carryover_cny numeric;
  v_billing_amount_cny numeric;
  v_existing_found boolean := false;
  v_existing_income_status text := null;
  v_message text := 'tuition bill preview';
begin
  perform public.school_require_feature_gate_state(
    'student_tuition_preview',
    'validation_preview_only',
    'TUITION_PREVIEW_BLOCKED',
    '学费预览 gate 不可用，已按 fail-closed 拒绝。'
  );

  if p_student_id is null then
    raise exception '请选择学生。';
  end if;

  if v_billing_month is null or v_billing_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception '学费月份格式无效，请使用 YYYY-MM。';
  end if;

  if v_billing_exchange_rate is null or v_billing_exchange_rate <= 0 then
    raise exception '通知汇率必须大于 0。';
  end if;

  select *
    into v_student
    from public.school_students s
   where s.id = p_student_id
     and s.app_type = 'school';

  if not found then
    raise exception '学生无效或不属于 School。';
  end if;

  if coalesce(v_student.status, '') in ('inactive', 'disabled', 'archived') then
    raise exception '学生已停用，不能生成学费应收。';
  end if;

  if v_student.business_entity_id is null then
    raise exception '学生缺少默认业务归属，不能生成学费应收。';
  end if;

  if exists (
    select 1
      from public.school_student_monthly_settlements s
     where s.student_id = p_student_id
       and s.business_entity_id = v_student.business_entity_id
       and s.year_month = v_billing_month
       and s.settlement_status = 'locked'
  ) then
    raise exception '目标学生月度结算已锁定，不能生成新的学费应收。';
  end if;

  v_previous_month := to_char(
    (to_date(v_billing_month || '-01', 'YYYY-MM-DD') - interval '1 month')::date,
    'YYYY-MM'
  );

  select *
    into v_previous_settlement
    from public.school_student_monthly_settlements s
   where s.student_id = p_student_id
     and s.business_entity_id = v_student.business_entity_id
     and s.year_month = v_previous_month
     and s.settlement_status = 'locked'
   order by s.locked_at desc nulls last, s.updated_at desc nulls last, s.created_at desc nulls last
   limit 1;

  select
    count(*)::integer,
    coalesce(sum(candidate.duration_hours), 0)::numeric,
    coalesce(sum(candidate.lesson_fee), 0)::numeric
  into
    v_planned_count,
    v_planned_hours,
    v_planned_fee_jpy
  from public.school_list_student_tuition_candidates(
    p_student_id,
    v_student.business_entity_id,
    v_billing_month,
    false
  ) candidate;

  if coalesce(v_planned_count, 0) <= 0 then
    raise exception '该学生月份没有可生成学费应收的正式预定课时。';
  end if;

  if coalesce(v_planned_fee_jpy, 0) <= 0 then
    raise exception '该学生月份预定课时费为 0，不能生成学费应收。';
  end if;

  v_previous_carryover_cny := round(coalesce(v_previous_settlement.carryover_amount_cny, 0), 2);
  v_billing_amount_cny := round(v_planned_fee_jpy * v_billing_exchange_rate + v_previous_carryover_cny, 2);

  if v_billing_amount_cny <= 0 then
    raise exception '通知金额计算失败。';
  end if;

  select *
    into v_existing
    from public.school_student_tuition_bills b
   where b.student_id = p_student_id
     and b.business_entity_id = v_student.business_entity_id
     and b.billing_month = v_billing_month
     and b.status in ('draft', 'income_created')
   order by b.updated_at desc nulls last, b.created_at desc nulls last
   limit 1;

  v_existing_found := found;

  if v_existing_found and v_existing.status = 'income_created' then
    select *
      into v_existing_income
      from public.school_income_records i
     where i.id = v_existing.income_record_id
       and i.app_type = 'school';

    if found then
      v_existing_income_status := v_existing_income.status;
    end if;

    if not found or (v_existing_income.status <> 'cancelled' and v_existing_income.cancelled_at is null) then
      raise exception '该学生月份已生成收入记录，不能重复生成学费应收。';
    end if;

    v_message := 'existing income-created tuition bill has cancelled income; regenerate is allowed';
  elsif v_existing_found and v_existing.status = 'draft' then
    v_message := 'existing draft tuition bill will be recalculated';
  end if;

  return query
  select
    v_student.id,
    v_student.business_entity_id,
    v_billing_month,
    v_previous_month,
    v_previous_settlement.id,
    v_previous_carryover_cny,
    v_planned_count,
    v_planned_hours,
    v_planned_fee_jpy,
    v_planned_fee_jpy,
    'JPY'::text,
    v_billing_exchange_rate,
    v_billing_amount_cny,
    'CNY'::text,
    case when v_existing_found then v_existing.id else null end,
    case when v_existing_found then v_existing.status else null end,
    case when v_existing_found then v_existing.income_record_id else null end,
    v_existing_income_status,
    v_message;
end;
$$;

comment on function public.school_preview_student_tuition_bill(uuid, text, numeric) is
  'R1C-B DB-authoritative R0 validation_preview_only preview. Aggregates candidate-only rows after permanent normalized/JSON billing-evidence exclusion and writes no business data.';

revoke all on function public.school_preview_student_tuition_bill(uuid, text, numeric)
  from public, anon, authenticated;

grant execute on function public.school_preview_student_tuition_bill(uuid, text, numeric)
  to authenticated, service_role;
