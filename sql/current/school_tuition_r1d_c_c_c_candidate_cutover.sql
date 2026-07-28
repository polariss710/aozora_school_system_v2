-- School V2 tuition P0 R1D-C-C-C: candidate attribution cutover.
-- Required psql variable: r1d_c_c_c_commit=0 for rollback rehearsal or 1 for deployment.
-- Replaces only the service-role candidate reader. No lesson/evidence/business DML.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r1d_c_c_c_commit}
\else
  \echo 'R1D_C_C_C_COMMIT_VARIABLE_REQUIRED'
  \quit
\endif

begin;

create function pg_temp.r1d_c_c_c_school_business_fingerprint()
returns jsonb
language sql
stable
set search_path = pg_catalog, public
as $fingerprint$
  select jsonb_build_object(
    'lesson',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_lesson_records t),
    'bill',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_student_tuition_bills t),
    'income',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_income_records t),
    'identity',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_student_tuition_billing_identities t),
    'relation',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_student_tuition_bill_lessons t),
    'migration_batch',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_business_entity_migration_batches t),
    'migration_item',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_business_entity_migration_items t),
    'settlement',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_student_monthly_settlements t),
    'settlement_adjustment',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_student_settlement_adjustments t),
    'student_payment',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_student_payments t),
    'account_transaction',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_account_transactions t),
    'cash_linkage',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_personal_cash_income_linkage_events t),
    'wage_lock',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_teacher_wage_locks t),
    'wage_detail',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_teacher_wage_lock_details t),
    'gate',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.feature_key),''))) from public.school_feature_gates t),
    'override',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_tuition_billing_attribution_override_audit t),
    'historical_exclusion',(select jsonb_build_array(count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text),''))) from public.school_student_tuition_historical_lesson_exclusions t)
  );
$fingerprint$;

create temporary table r1d_c_c_c_school_business_before
on commit drop
as select pg_temp.r1d_c_c_c_school_business_fingerprint() as fingerprint;

create temporary table r1d_c_c_c_old_candidate_set (
  planned_lesson_id uuid primary key
) on commit drop;

insert into r1d_c_c_c_old_candidate_set(planned_lesson_id)
select distinct candidate.planned_lesson_id
from public.school_students student
join (
  select distinct student_id,year_month
  from public.school_lesson_records
  where app_type='school' and lesson_type='planned'
) scope on scope.student_id=student.id
cross join lateral public.school_list_student_tuition_candidates(
  student.id,student.business_entity_id,scope.year_month,false
) candidate
where candidate.candidate_status='candidate';

do $preflight$
begin
  if md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '1d9149f6e3ff02305d0963f81af9f0b9' then
    raise exception 'R1D_C_C_C_CANDIDATE_FUNCTION_DRIFT';
  end if;

  if md5(pg_get_functiondef(
       'public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure
     )) <> 'ea71010c17f880ee61092bb8e01ea920'
     or md5(pg_get_functiondef(
       'public.school_classify_student_tuition_candidate(boolean,boolean,text[],boolean,boolean,text,text,timestamptz,boolean,boolean)'::regprocedure
     )) <> '759738bc62c558b5d29e2078b06ea297' then
    raise exception 'R1D_C_C_C_CALLER_OR_CLASSIFIER_DRIFT';
  end if;

  if (select count(*) from pg_temp.r1d_c_c_c_old_candidate_set) <> 160
     or (select count(*) from public.school_lesson_records) <> 626
     or (select count(*) from public.school_lesson_records where lesson_type='planned') <> 397
     or (select count(*) from public.school_lesson_records where lesson_type='actual') <> 229
     or (select count(*) from public.school_lesson_records where billing_month is not null) <> 118
     or (select count(*) from public.school_lesson_records where billing_week_start_date is not null) <> 118
     or (select count(*) from public.school_lesson_records where student_settlement_month is not null) <> 118
     or (select count(*) from public.school_lesson_records where billing_month_source is not null) <> 118
     or (select count(*) from public.school_lesson_records where billing_month_decided_at is not null) <> 118
     or (select count(*) from public.school_lesson_records where scheduled_lesson_date is not null) <> 0 then
    raise exception 'R1D_C_C_C_LESSON_OR_OLD_CANDIDATE_BASELINE_DRIFT';
  end if;

  if (select count(*) from public.school_student_tuition_historical_lesson_exclusions) <> 42
     or (select md5(string_agg(md5(to_jsonb(t)::text),'' order by t.id::text))
         from public.school_student_tuition_historical_lesson_exclusions t)
        <> '680b6e5aaa718569aee4c36fe1cdc058'
     or (select md5(string_agg(t.lesson_old31_hash,'' order by t.planned_lesson_id::text))
         from public.school_student_tuition_historical_lesson_exclusions t)
        <> 'dc6cd4ad206cc09ed5c02dfe6da5462b'
     or (select md5(string_agg(t.evidence_hash,'' order by t.planned_lesson_id::text))
         from public.school_student_tuition_historical_lesson_exclusions t)
        <> 'dc2546bff536942650db58e437d37f0e' then
    raise exception 'R1D_C_C_C_FIXED_42_EVIDENCE_DRIFT';
  end if;

  if (select count(*) from public.school_business_entity_migration_items
      where batch_id in (
        'c1000000-0000-4000-8000-202607279999'::uuid,
        'c1000000-0000-4000-8000-202607289999'::uuid
      )) <> 118
     or (select count(*) from public.school_lesson_records lesson
         where lesson.billing_month is not null
           and (lesson.lesson_type<>'planned'
             or lesson.billing_month_source not in (
               'approved_r1c_a_manifest','approved_r1c_c_b_manifest'
             )
             or lesson.billing_month_decided_at is null
             or lesson.student_settlement_month is distinct from lesson.billing_month
             or not public.school_is_valid_tuition_billing_period(
               lesson.billing_month,lesson.billing_week_start_date
             ))) <> 0
     or (select count(*)
         from public.school_lesson_records lesson
         join public.school_student_tuition_historical_lesson_exclusions exclusion
           on exclusion.planned_lesson_id=lesson.id
         where lesson.billing_month is not null) <> 0 then
    raise exception 'R1D_C_C_C_FIXED_118_ATTRIBUTION_DRIFT';
  end if;

  if (select count(*) from public.school_lesson_records lesson
      where lesson.lesson_type='planned'
        and lesson.status='pending_makeup'
        and lesson.student_id in (
          '881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,
          'eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid
        )
        and lesson.year_month in ('2026-05','2026-06')) <> 6
     or (select count(*) from public.school_lesson_records lesson
         join public.school_student_tuition_historical_lesson_exclusions exclusion
           on exclusion.planned_lesson_id=lesson.id
         where lesson.status='pending_makeup') <> 0 then
    raise exception 'R1D_C_C_C_PENDING_MAKEUP_SCOPE_DRIFT';
  end if;

  if not exists (select 1 from public.school_feature_gates
                 where feature_key='student_tuition_preview'
                   and state='validation_preview_only')
     or not exists (select 1 from public.school_feature_gates
                    where feature_key='student_tuition_generate' and state='blocked')
     or not exists (select 1 from public.school_feature_gates
                    where feature_key='student_tuition_cash_submit' and state='blocked') then
    raise exception 'R1D_C_C_C_R0_PREFLIGHT_DRIFT';
  end if;
end;
$preflight$;

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
as $function$
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
      ) as evidence_conflict,
      exclusion.planned_lesson_id is not null as has_historical_paid_exclusion
    from public.school_lesson_records lesson
    left join relation_evidence relation
      on relation.planned_lesson_id = lesson.id
    left join snapshot_evidence snapshot
      on snapshot.planned_lesson_id = lesson.id
    left join public.school_student_tuition_historical_lesson_exclusions exclusion
      on exclusion.planned_lesson_id = lesson.id
    where lesson.student_id = p_student_id
      and lesson.billing_month = v_billing_month
  ),
  classified as (
    select
      evidence.*,
      case
        when evidence.app_type is distinct from 'school'
          or evidence.business_entity_id is distinct from p_business_entity_id
          then 'scope_mismatch'
        when evidence.has_historical_paid_exclusion
          then 'historical_paid_exclusion'
        else public.school_classify_student_tuition_candidate(
          true,
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
            and evidence.billing_month = v_billing_month
            and evidence.billing_week_start_date is not null
            and public.school_is_valid_tuition_billing_period(
              evidence.billing_month,evidence.billing_week_start_date
            )
            and evidence.student_settlement_month = evidence.billing_month
            and evidence.billing_month_source in (
              'approved_r1c_a_manifest','approved_r1c_c_b_manifest'
            )
            and evidence.billing_month_decided_at is not null
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
        )
      end as reason_code
    from evidence_rows evidence
  )
  select
    classified.id,
    classified.student_id,
    classified.business_entity_id,
    classified.billing_month,
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
      'has_historical_paid_exclusion',
      'reason_code'
    ]::text[])::text)
  from classified
  where coalesce(p_include_excluded, false)
     or classified.reason_code = 'candidate'
  order by classified.billing_week_start_date,classified.lesson_date,classified.id;
end;
$function$;

comment on function public.school_list_student_tuition_candidates(uuid, uuid, text, boolean) is
  'R1D-C-C-C service-role audit surface. Scope is explicit billing_month/business_entity_id; valid ISO billing pair, matching student settlement month, approved source and decided_at are mandatory. Immutable historical-paid evidence and all normalized/JSON billing evidence remain fail-closed exclusions. No legacy year_month/date fallback.';

revoke all on function public.school_list_student_tuition_candidates(uuid, uuid, text, boolean)
  from public, anon, authenticated, service_role;

grant execute on function public.school_list_student_tuition_candidates(uuid, uuid, text, boolean)
  to service_role;

create temporary table r1d_c_c_c_new_candidate_set (
  planned_lesson_id uuid primary key
) on commit drop;

insert into r1d_c_c_c_new_candidate_set(planned_lesson_id)
select distinct candidate.planned_lesson_id
from (
  select distinct student_id,business_entity_id,billing_month
  from public.school_lesson_records
  where app_type='school'
    and lesson_type='planned'
    and billing_month is not null
) scope
cross join lateral public.school_list_student_tuition_candidates(
  scope.student_id,scope.business_entity_id,scope.billing_month,false
) candidate
where candidate.candidate_status='candidate';

do $cutover_assertions$
begin
  if md5(pg_get_functiondef(
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
     )) <> '8981a2ce07abf8c28231bfaf05451368' then
    raise exception 'R1D_C_C_C_NEW_CANDIDATE_DEFINITION_DRIFT';
  end if;

  if (select count(*) from pg_temp.r1d_c_c_c_new_candidate_set) <> 118
     or (select count(*) from pg_temp.r1d_c_c_c_old_candidate_set old_set
         left join pg_temp.r1d_c_c_c_new_candidate_set new_set using(planned_lesson_id)
         where new_set.planned_lesson_id is null) <> 42
     or (select count(*) from pg_temp.r1d_c_c_c_new_candidate_set new_set
         left join pg_temp.r1d_c_c_c_old_candidate_set old_set using(planned_lesson_id)
         where old_set.planned_lesson_id is null) <> 0 then
    raise exception 'R1D_C_C_C_160_TO_118_SET_ASSERTION_FAILED';
  end if;

  if (select count(*)
      from pg_temp.r1d_c_c_c_old_candidate_set old_set
      left join pg_temp.r1d_c_c_c_new_candidate_set new_set using(planned_lesson_id)
      left join public.school_student_tuition_historical_lesson_exclusions exclusion
        using(planned_lesson_id)
      where new_set.planned_lesson_id is null
        and exclusion.planned_lesson_id is null) <> 0
     or (select count(*)
         from public.school_student_tuition_historical_lesson_exclusions exclusion
         left join pg_temp.r1d_c_c_c_old_candidate_set old_set using(planned_lesson_id)
         left join pg_temp.r1d_c_c_c_new_candidate_set new_set using(planned_lesson_id)
         where old_set.planned_lesson_id is null
            or new_set.planned_lesson_id is not null) <> 0 then
    raise exception 'R1D_C_C_C_FIXED_42_SET_ASSERTION_FAILED';
  end if;

  if (select count(*)
      from pg_temp.r1d_c_c_c_new_candidate_set candidate
      full join (
        select lesson_record_id as planned_lesson_id
        from public.school_business_entity_migration_items
        where batch_id in (
          'c1000000-0000-4000-8000-202607279999'::uuid,
          'c1000000-0000-4000-8000-202607289999'::uuid
        )
      ) approved using(planned_lesson_id)
      where candidate.planned_lesson_id is null
         or approved.planned_lesson_id is null) <> 0 then
    raise exception 'R1D_C_C_C_FIXED_118_SET_ASSERTION_FAILED';
  end if;

  if (select fingerprint from pg_temp.r1d_c_c_c_school_business_before)
       is distinct from pg_temp.r1d_c_c_c_school_business_fingerprint() then
    raise exception 'R1D_C_C_C_BUSINESS_DATA_CHANGED_DURING_CUTOVER';
  end if;

  if md5(pg_get_functiondef(
       'public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure
     )) <> 'ea71010c17f880ee61092bb8e01ea920'
     or md5(pg_get_functiondef(
       'public.school_classify_student_tuition_candidate(boolean,boolean,text[],boolean,boolean,text,text,timestamptz,boolean,boolean)'::regprocedure
     )) <> '759738bc62c558b5d29e2078b06ea297'
     or not has_function_privilege(
       'service_role',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)',
       'EXECUTE'
     ) then
    raise exception 'R1D_C_C_C_CONTRACT_OR_PERMISSION_CHANGED';
  end if;
end;
$cutover_assertions$;

select md5(pg_get_functiondef(
         'public.school_list_student_tuition_candidates(uuid,uuid,text,boolean)'::regprocedure
       )) as candidate_definition_hash_after_cutover,
       (select count(*) from pg_temp.r1d_c_c_c_old_candidate_set) as old_candidate_rows,
       (select count(*) from pg_temp.r1d_c_c_c_new_candidate_set) as new_candidate_rows;

\if :r1d_c_c_c_commit
\else
do $rollback_negative_tests$
declare
  v_target_id constant uuid := '23d4b46b-eb1c-48b7-8001-d208ce14f08d'::uuid;
  v_fixed_exclusion_id constant uuid := '495c035a-68f7-42a1-b2a9-28b89ee01d6b'::uuid;
  v_reason text;
  v_rejected boolean;
begin
  -- Even if an approved historical lesson later receives complete-looking new
  -- attribution, immutable exclusion evidence remains authoritative.
  update public.school_lesson_records
  set billing_month='2026-05',
      billing_week_start_date='2026-05-25'::date,
      student_settlement_month='2026-05',
      billing_month_source='approved_r1c_a_manifest',
      billing_month_decided_at='2026-07-28 12:00:00+00'::timestamptz
  where id=v_fixed_exclusion_id;

  select exclusion_reason into v_reason
  from public.school_list_student_tuition_candidates(
    '881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
    '2026-05',true
  )
  where planned_lesson_id=v_fixed_exclusion_id;

  if v_reason is distinct from 'historical_paid_exclusion' then
    raise exception 'R1D_C_C_C_NEGATIVE_FIXED_EXCLUSION_FAILED: %',v_reason;
  end if;

  -- Missing evidence is simulated only as a rejected delete attempt; the
  -- immutable production row is never actually removed.
  v_rejected := false;
  begin
    delete from public.school_student_tuition_historical_lesson_exclusions
    where planned_lesson_id=v_fixed_exclusion_id;
  exception when others then
    if sqlerrm not like 'TUITION_HISTORICAL_LESSON_EXCLUSION_IMMUTABLE%' then raise; end if;
    v_rejected := true;
  end;
  if not v_rejected then raise exception 'R1D_C_C_C_NEGATIVE_EVIDENCE_DELETE_NOT_REJECTED'; end if;

  -- A nullable student settlement month is DB-compatible during transition,
  -- but is not candidate-compatible.
  update public.school_lesson_records
  set student_settlement_month=null
  where id=v_target_id;
  select exclusion_reason into v_reason
  from public.school_list_student_tuition_candidates(
    '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
    '2026-08',true
  ) where planned_lesson_id=v_target_id;
  if v_reason is distinct from 'invalid_or_incomplete_data' then
    raise exception 'R1D_C_C_C_NEGATIVE_MISSING_SETTLEMENT_FAILED: %',v_reason;
  end if;
  update public.school_lesson_records
  set student_settlement_month='2026-08'
  where id=v_target_id;

  -- Illegal month/week storage is rejected by R1D-B checks before candidate.
  v_rejected := false;
  begin
    update public.school_lesson_records
    set billing_week_start_date='2026-08-04'::date
    where id=v_target_id;
  exception when check_violation then v_rejected := true;
  end;
  if not v_rejected then raise exception 'R1D_C_C_C_NEGATIVE_INVALID_PERIOD_NOT_REJECTED'; end if;

  -- Source without decided_at is rejected by R1D-B source metadata check.
  v_rejected := false;
  begin
    update public.school_lesson_records
    set billing_month_decided_at=null
    where id=v_target_id;
  exception when check_violation then v_rejected := true;
  end;
  if not v_rejected then raise exception 'R1D_C_C_C_NEGATIVE_SOURCE_WITHOUT_DECISION_NOT_REJECTED'; end if;

  -- A syntactically valid but unapproved source remains stored only inside the
  -- rollback transaction and must be excluded by the candidate reader.
  update public.school_lesson_records
  set billing_month_source='rollback_unapproved_source'
  where id=v_target_id;
  select exclusion_reason into v_reason
  from public.school_list_student_tuition_candidates(
    '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
    '2026-08',true
  ) where planned_lesson_id=v_target_id;
  if v_reason is distinct from 'invalid_or_incomplete_data' then
    raise exception 'R1D_C_C_C_NEGATIVE_UNAPPROVED_SOURCE_FAILED: %',v_reason;
  end if;
  update public.school_lesson_records
  set billing_month_source='approved_r1c_a_manifest'
  where id=v_target_id;

  -- Scheduled date is deliberately independent from billing attribution.
  update public.school_lesson_records
  set scheduled_lesson_date='2099-12-31'::date
  where id=v_target_id;
  if not exists (
    select 1 from public.school_list_student_tuition_candidates(
      '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
      '2026-08',false
    ) where planned_lesson_id=v_target_id and candidate_status='candidate'
  ) then
    raise exception 'R1D_C_C_C_NEGATIVE_SCHEDULED_DATE_AFFECTED_CANDIDATE';
  end if;
  update public.school_lesson_records set scheduled_lesson_date=null where id=v_target_id;

  -- Old month/date changes cannot give a lesson without new attribution a
  -- candidate scope. This update is rollback-only and the row remains protected
  -- by fixed historical evidence as an additional independent defense.
  update public.school_lesson_records
  set billing_month=null,
      billing_week_start_date=null,
      student_settlement_month=null,
      billing_month_source=null,
      billing_month_decided_at=null,
      year_month='2099-12',
      lesson_date='2099-12-31'::date
  where id=v_fixed_exclusion_id;
  if exists (
    select 1 from public.school_list_student_tuition_candidates(
      '881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,
      '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,
      '2099-12',false
    ) where planned_lesson_id=v_fixed_exclusion_id
  ) then
    raise exception 'R1D_C_C_C_NEGATIVE_LEGACY_FIELDS_REOPENED_CANDIDATE';
  end if;

  if (select count(*) from public.school_lesson_records lesson
      where lesson.lesson_type='planned'
        and lesson.status='pending_makeup'
        and lesson.student_id in (
          '881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,
          'eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid
        )
        and lesson.year_month in ('2026-05','2026-06')) <> 6 then
    raise exception 'R1D_C_C_C_NEGATIVE_PENDING_MAKEUP_CHANGED';
  end if;
end;
$rollback_negative_tests$;

-- All write entry probes must still reject before any business write.
\ir school_tuition_r1b_r0_entry_probes.sql
\endif

\if :r1d_c_c_c_commit
  commit;
\else
  rollback;
\endif
