-- School V2 Phase 2I-A: exact P002 package-credit production isolation.
-- Default is rehearsal mode: leaves the transaction open for caller assertions.
\set ON_ERROR_STOP on
\if :{?phase2i_a_commit}
\else
  \set phase2i_a_commit 0
\endif
\if :{?phase2i_a_expected_p002_md5}
\else
  \set phase2i_a_expected_p002_md5 686cbf3a566160bf0de0e30abbdaafa5
\endif
\if :{?phase2i_a_expected_raw_md5}
\else
  \set phase2i_a_expected_raw_md5 f5da14743858f89d37f17ba2646ab092
\endif
\if :{?phase2i_a_expected_remaining_md5}
\else
  \set phase2i_a_expected_remaining_md5 2111a62f998abeeb6933b47fc5c512aa
\endif
\if :{?phase2i_a_expected_balance_md5}
\else
  \set phase2i_a_expected_balance_md5 81823a464f235e72a439867a2c4d395a
\endif
\if :{?phase2i_a_expected_open_md5}
\else
  \set phase2i_a_expected_open_md5 3b45f8f09d4d63a952ca5ec42f7214d7
\endif
\if :{?phase2i_a_expected_p0f_md5}
\else
  \set phase2i_a_expected_p0f_md5 4859d04189893b1dfdecc6a3d66df192
\endif
\if :{?phase2i_a_expected_writer_md5}
\else
  \set phase2i_a_expected_writer_md5 3434e8ece09ec210511aec8b8eb1960f
\endif

begin;

select set_config('phase2i.expected_p002_md5', :'phase2i_a_expected_p002_md5', true),
  set_config('phase2i.expected_raw_md5', :'phase2i_a_expected_raw_md5', true),
  set_config('phase2i.expected_remaining_md5', :'phase2i_a_expected_remaining_md5', true),
  set_config('phase2i.expected_balance_md5', :'phase2i_a_expected_balance_md5', true),
  set_config('phase2i.expected_open_md5', :'phase2i_a_expected_open_md5', true),
  set_config('phase2i.expected_p0f_md5', :'phase2i_a_expected_p0f_md5', true),
  set_config('phase2i.expected_writer_md5', :'phase2i_a_expected_writer_md5', true);

select pg_advisory_xact_lock(hashtextextended(
  'school_phase2i_a_p002_package_isolation_20260817',0
));

do $preflight$
declare
  v_lesson public.school_lesson_records%rowtype;
begin
  if to_regclass('public.school_student_package_credit_lots') is not null
     or to_regprocedure('public.school_list_student_package_credit_lots(uuid)') is not null
     or to_regprocedure('public.school_is_active_package_credit_origin(uuid)') is not null
     or to_regprocedure('public.school_create_lesson_credit_makeup_actual_phase2i_a_legacy(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)') is not null then
    raise exception 'PHASE2I_A_PACKAGE_OBJECT_ALREADY_EXISTS';
  end if;
  if to_regclass('public.school_lesson_clearances') is not null
     or to_regclass('public.school_lesson_clearance_details') is not null
     or to_regprocedure(
       'public.school_create_lesson_clearance(text,uuid,uuid,integer,date,text,text,text,text,text)'
     ) is not null then
    raise exception 'PHASE2I_A_CLEARANCE_OBJECT_CONFLICT';
  end if;
  if md5(pg_get_functiondef(
       'public.school_get_lesson_credit_raw_remaining_hours(uuid)'::regprocedure
     ))<>current_setting('phase2i.expected_raw_md5')
     or md5(pg_get_functiondef(
       'public.school_get_lesson_credit_remaining_hours(uuid)'::regprocedure
     ))<>current_setting('phase2i.expected_remaining_md5')
     or md5(pg_get_functiondef(
       'public.school_list_student_lesson_credit_balances(uuid)'::regprocedure
     ))<>current_setting('phase2i.expected_balance_md5')
     or md5(pg_get_functiondef(
       'public.school_list_open_lesson_credit_sources(text,text,text)'::regprocedure
     ))<>current_setting('phase2i.expected_open_md5')
     or md5(pg_get_functiondef(
       'public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)'::regprocedure
     ))<>current_setting('phase2i.expected_p0f_md5')
     or md5(pg_get_functiondef(
       'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
     ))<>current_setting('phase2i.expected_writer_md5') then
    raise exception 'PHASE2I_A_FUNCTION_DEFINITION_DRIFT';
  end if;
  select * into strict v_lesson from public.school_lesson_records lesson
  where lesson.id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9' for update;
  if md5(to_jsonb(v_lesson)::text)<>current_setting('phase2i.expected_p002_md5')
     or v_lesson.app_type<>'school'
     or v_lesson.lesson_type<>'planned'
     or v_lesson.status<>'pending_makeup'
     or v_lesson.student_id<>'a7b163a0-201e-4867-9b94-372343356a80'
     or v_lesson.business_entity_id<>'2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
     or v_lesson.duration_hours<>20
     or v_lesson.unit_price<>13000
     or v_lesson.lesson_fee<>260000
     or v_lesson.student_settlement_month<>'2026-07'
     or v_lesson.voided_at is not null then
    raise exception 'PHASE2I_A_P002_FACT_DRIFT';
  end if;
  if (select count(*) from public.school_student_tuition_bill_lessons relation
      where relation.planned_lesson_id=v_lesson.id
        and relation.id='de834352-7387-f856-e8ee-213b7419210d'
        and relation.tuition_bill_id='07a02092-9503-47d1-9000-106f7e3de7e5')<>1
     or (select count(*) from public.school_student_tuition_generation_revisions revision
      where revision.id='96000000-0000-4000-8000-202608031004'
        and revision.tuition_bill_id='07a02092-9503-47d1-9000-106f7e3de7e5')<>1
     or (select count(*) from public.school_income_records income
      where income.id='91756564-c48d-4a1d-b6bc-88a041660e46'
        and income.tuition_bill_id='07a02092-9503-47d1-9000-106f7e3de7e5')<>1
     or (select count(*) from public.school_personal_cash_income_linkage_events linkage
      where linkage.id='9de972ff-8e66-470a-8b05-e430ef51562f'
        and linkage.income_record_id='91756564-c48d-4a1d-b6bc-88a041660e46'
        and linkage.cash_request_id='a0bee5be-761b-4bc0-a666-411f033e1eba'
        and linkage.cash_transaction_id='f500dbe4-07a9-4a4d-ac99-e68592a8af6a')<>1 then
    raise exception 'PHASE2I_A_P002_FINANCIAL_EVIDENCE_DRIFT';
  end if;
  if exists(
    select 1 from public.school_student_settlement_lesson_variance_claims claim
    where claim.claim_status='active'
      and claim.source_planned_lesson_id=v_lesson.id
  ) or exists(
    select 1 from public.school_lesson_records actual_row
    where actual_row.planned_lesson_id=v_lesson.id and actual_row.voided_at is null
  ) then
    raise exception 'PHASE2I_A_P002_ACTIVE_CONSUMER_CONFLICT';
  end if;
end
$preflight$;

create table public.school_student_package_credit_lots(
  id uuid primary key,
  origin_planned_lesson_id uuid not null
    references public.school_lesson_records(id) on delete restrict,
  student_id uuid not null references public.school_students(id) on delete restrict,
  business_entity_id uuid not null
    references public.school_business_entities(id) on delete restrict,
  initial_minutes integer not null,
  consumed_minutes integer not null default 0,
  remaining_minutes integer generated always as (
    initial_minutes-consumed_minutes
  ) stored,
  unit_price_jpy numeric not null,
  total_price_jpy numeric not null,
  student_billing_month text not null,
  tuition_bill_id uuid not null
    references public.school_student_tuition_bills(id) on delete restrict,
  tuition_revision_id uuid not null
    references public.school_student_tuition_generation_revisions(id) on delete restrict,
  income_record_id uuid not null
    references public.school_income_records(id) on delete restrict,
  cash_linkage_event_id uuid not null
    references public.school_personal_cash_income_linkage_events(id) on delete restrict,
  cash_request_id_snapshot uuid not null,
  cash_transaction_id_snapshot uuid not null,
  status text not null,
  classification_reason text not null check(btrim(classification_reason)<>''),
  origin_lesson_row_md5 text not null check(
    origin_lesson_row_md5~'^[0-9a-f]{32}$'
  ),
  evidence_manifest_sha256 text not null check(
    evidence_manifest_sha256~'^[0-9a-f]{64}$'
  ),
  classified_by text not null check(btrim(classified_by)<>''),
  created_at timestamptz not null default transaction_timestamp(),
  constraint school_package_credit_lots_phase2i_a_exact_p002_chk check(
    id='2a000000-0000-4000-8000-202608170002'
    and origin_planned_lesson_id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'
    and student_id='a7b163a0-201e-4867-9b94-372343356a80'
    and business_entity_id='2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
    and initial_minutes=1200 and consumed_minutes=0
    and unit_price_jpy=13000 and total_price_jpy=260000
    and student_billing_month='2026-07' and status='active'
    and tuition_bill_id='07a02092-9503-47d1-9000-106f7e3de7e5'
    and tuition_revision_id='96000000-0000-4000-8000-202608031004'
    and income_record_id='91756564-c48d-4a1d-b6bc-88a041660e46'
    and cash_linkage_event_id='9de972ff-8e66-470a-8b05-e430ef51562f'
    and cash_request_id_snapshot='a0bee5be-761b-4bc0-a666-411f033e1eba'
    and cash_transaction_id_snapshot='f500dbe4-07a9-4a4d-ac99-e68592a8af6a'
    and origin_lesson_row_md5=:'phase2i_a_expected_p002_md5'
    and classified_by='business_owner_phase2i_a_20260817'
  )
);
alter table public.school_student_package_credit_lots owner to postgres;
create unique index school_package_credit_lots_active_origin_uidx
  on public.school_student_package_credit_lots(origin_planned_lesson_id)
  where status='active';
create index school_package_credit_lots_student_idx
  on public.school_student_package_credit_lots(
    student_id,business_entity_id,status,created_at,id
  );
alter table public.school_student_package_credit_lots enable row level security;
revoke all on public.school_student_package_credit_lots
  from public,anon,authenticated,service_role;

create function public.school_prevent_package_credit_lot_mutation()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public as $function$
begin
  raise exception using errcode='55000',message='LESSON_PACKAGE_LOT_APPEND_ONLY';
end
$function$;
create trigger school_package_credit_lots_append_only
before update or delete on public.school_student_package_credit_lots
for each row execute function public.school_prevent_package_credit_lot_mutation();
create trigger school_package_credit_lots_truncate_guard
before truncate on public.school_student_package_credit_lots
for each statement execute function public.school_prevent_package_credit_lot_mutation();

create function public.school_is_active_package_credit_origin(
  p_planned_lesson_id uuid
) returns boolean language sql stable security definer
set search_path=pg_catalog,public as $function$
  select exists(
    select 1 from public.school_student_package_credit_lots lot
    where lot.origin_planned_lesson_id=p_planned_lesson_id
      and lot.status='active'
  )
$function$;

create function public.school_list_student_package_credit_lots(
  p_student_id uuid default null
) returns table(
  package_lot_id uuid,origin_planned_lesson_id uuid,student_id uuid,
  business_entity_id uuid,initial_minutes integer,consumed_minutes integer,
  remaining_minutes integer,unit_price_jpy numeric,total_price_jpy numeric,
  student_billing_month text,status text,classification_reason text,
  created_at timestamptz
) language plpgsql stable security definer
set search_path=pg_catalog,public as $function$
declare
  v_actor uuid:=auth.uid();
  v_role text;
  v_active boolean;
begin
  if v_actor is null then
    raise exception using errcode='42501',message='PACKAGE_READER_AUTH_REQUIRED';
  end if;
  select membership.role,membership.is_active into v_role,v_active
  from public.school_app_memberships membership
  where membership.user_id=v_actor;
  if not found then
    raise exception using errcode='42501',message='PACKAGE_READER_MEMBERSHIP_REQUIRED';
  end if;
  if v_active is distinct from true then
    raise exception using errcode='42501',message='PACKAGE_READER_ACTIVE_MEMBERSHIP_REQUIRED';
  end if;
  if v_role not in ('admin','operator','read_only') then
    raise exception using errcode='42501',message='PACKAGE_READER_ROLE_REQUIRED';
  end if;
  return query
  select lot.id,lot.origin_planned_lesson_id,lot.student_id,
    lot.business_entity_id,lot.initial_minutes,lot.consumed_minutes,
    lot.remaining_minutes,lot.unit_price_jpy,lot.total_price_jpy,
    lot.student_billing_month,lot.status,lot.classification_reason,lot.created_at
  from public.school_student_package_credit_lots lot
  where lot.status='active'
    and (p_student_id is null or lot.student_id=p_student_id)
  order by lot.student_id,lot.created_at,lot.id;
end
$function$;

create or replace function public.school_get_lesson_credit_raw_remaining_hours(
  p_planned_lesson_id uuid
) returns numeric language sql stable security definer
set search_path=pg_catalog,public as $function$
  select case when public.school_is_active_package_credit_origin(p.id) then 0
    else p.duration_hours-coalesce(sum(a.duration_hours) filter(
      where a.lesson_type='actual'
        and a.status in ('completed','makeup_completed')
        and a.voided_at is null
    ),0) end
  from public.school_lesson_records p
  left join public.school_lesson_records a on a.planned_lesson_id=p.id
  where p.id=p_planned_lesson_id and p.app_type='school'
    and p.lesson_type='planned'
  group by p.id,p.duration_hours
$function$;

create or replace function public.school_get_lesson_credit_remaining_hours(
  p_planned_lesson_id uuid
) returns numeric language sql stable security definer
set search_path=pg_catalog,public as $function$
  select case when public.school_is_active_package_credit_origin(p.id) then 0
    else greatest(
      coalesce(p.duration_hours,0)-coalesce(sum(a.duration_hours) filter(
        where a.lesson_type='actual'
          and a.status in ('completed','makeup_completed')
      ),0),0
    )::numeric end
  from public.school_lesson_records p
  left join public.school_lesson_records a
    on a.planned_lesson_id=p.id and a.app_type='school'
  where p.id=p_planned_lesson_id and p.app_type='school'
    and p.lesson_type='planned'
  group by p.id,p.duration_hours
$function$;

create or replace function public.school_list_student_lesson_credit_balances(
  p_student_id uuid default null
) returns table(
  student_id uuid,business_entity_id uuid,open_source_count bigint,
  open_credit_hours numeric,oldest_credit_date date
) language sql stable security definer
set search_path=pg_catalog,public as $function$
  with credit_sources as(
    select p.id,p.student_id,p.business_entity_id,p.lesson_date,
      greatest(public.school_get_lesson_credit_raw_remaining_hours(p.id),0)
        remaining_hours
    from public.school_lesson_records p
    where p.app_type='school' and p.lesson_type='planned'
      and p.status='pending_makeup' and p.voided_at is null
      and (p_student_id is null or p.student_id=p_student_id)
      and not public.school_is_active_package_credit_origin(p.id)
      and not exists(
        select 1 from public.school_student_settlement_lesson_variance_claims claim
        where claim.claim_status='active'
          and claim.source_type='unused_planned_credit_v1'
          and claim.source_planned_lesson_id=p.id
      )
  )
  select source.student_id,source.business_entity_id,
    count(*) filter(where source.remaining_hours>0)::bigint,
    coalesce(sum(source.remaining_hours) filter(where source.remaining_hours>0),0)::numeric,
    min(source.lesson_date) filter(where source.remaining_hours>0)
  from credit_sources source where source.student_id is not null
  group by source.student_id,source.business_entity_id
$function$;

create or replace function public.school_list_open_lesson_credit_sources(
  p_from_month text,p_to_month text,p_target_month text
) returns table(
  id uuid,lesson_date date,year_month text,student_id uuid,teacher_id uuid,
  subject_id uuid,business_entity_id uuid,start_time text,end_time text,
  duration_hours numeric,lesson_content text,note text,lesson_count integer,
  unit_price numeric,lesson_delivery_mode text,lesson_venue text,
  remaining_hours numeric
) language sql stable security definer
set search_path=pg_catalog,public as $function$
  with args as(
    select nullif(trim(coalesce(p_from_month,'')),'') from_month,
      nullif(trim(coalesce(p_to_month,'')),'') to_month,
      nullif(trim(coalesce(p_target_month,'')),'') target_month
  ),sources as(
    select p.id,p.lesson_date,
      public.school_resolve_r1d_e_c_lesson_student_month(p.id) source_month,
      p.student_id,p.teacher_id,p.subject_id,p.business_entity_id,p.start_time,
      p.end_time,p.duration_hours,p.lesson_content,p.note,p.lesson_count,
      p.unit_price,p.lesson_delivery_mode,p.lesson_venue,
      greatest(public.school_get_lesson_credit_raw_remaining_hours(p.id),0)
        remaining_hours
    from public.school_lesson_records p cross join args input
    where p.app_type='school' and p.lesson_type='planned'
      and p.status='pending_makeup' and p.voided_at is null
      and input.from_month~'^\d{4}-(0[1-9]|1[0-2])$'
      and input.to_month~'^\d{4}-(0[1-9]|1[0-2])$'
      and input.target_month~'^\d{4}-(0[1-9]|1[0-2])$'
      and input.from_month<=input.to_month and input.to_month<=input.target_month
      and public.school_resolve_r1d_e_c_lesson_student_month(p.id)
        between input.from_month and input.to_month
      and public.school_resolve_r1d_e_c_lesson_student_month(p.id)<=input.target_month
      and not public.school_is_active_package_credit_origin(p.id)
  )
  select source.id,source.lesson_date,source.source_month,source.student_id,
    source.teacher_id,source.subject_id,source.business_entity_id,
    source.start_time,source.end_time,source.duration_hours,source.lesson_content,
    source.note,source.lesson_count,source.unit_price,source.lesson_delivery_mode,
    source.lesson_venue,source.remaining_hours
  from sources source
  where source.remaining_hours>0 and not exists(
    select 1 from public.school_student_settlement_lesson_variance_claims claim
    where claim.claim_status='active'
      and claim.source_type='unused_planned_credit_v1'
      and claim.source_planned_lesson_id=source.id
  )
  order by source.source_month,source.lesson_date,
    source.lesson_count nulls last,source.start_time nulls last,source.id
$function$;

create or replace function public.school_tuition_p0f_source_lines(
  p_student_id uuid,p_business_entity_id uuid,p_year_month text,
  p_settlement_exchange_rate numeric,p_include_active_claimed boolean default false
) returns table(
  source_type text,source_planned_lesson_id uuid,source_actual_lesson_id uuid,
  source_hours numeric,source_amount_jpy numeric,source_amount_cny numeric,
  line_manifest_sha256 text
) language sql stable security definer
set search_path=pg_catalog,public as $function$
  with unused_sources as(
    select 'unused_planned_credit_v1'::text source_type,
      p.id source_planned_lesson_id,null::uuid source_actual_lesson_id,
      -public.school_get_lesson_credit_remaining_hours(p.id)::numeric source_hours,
      -round(coalesce(p.base_lesson_fee_jpy,p.lesson_fee,
        p.unit_price*p.duration_hours,0)
        * public.school_get_lesson_credit_remaining_hours(p.id)
        /nullif(p.duration_hours,0),2)::numeric source_amount_jpy
    from public.school_lesson_records p
    where p.app_type='school' and p.lesson_type='planned'
      and p.status='pending_makeup' and p.voided_at is null
      and p.student_id=p_student_id and p.business_entity_id=p_business_entity_id
      and public.school_resolve_r1d_e_c_lesson_student_month(p.id)=p_year_month
      and p.duration_hours>0
      and coalesce(p.base_lesson_fee_jpy,p.lesson_fee,
        p.unit_price*p.duration_hours,0)>=0
      and not public.school_is_active_package_credit_origin(p.id)
      and public.school_get_lesson_credit_remaining_hours(p.id)>0
      and (p_include_active_claimed or not exists(
        select 1 from public.school_student_settlement_lesson_variance_claims c
        where c.claim_status='active'
          and c.source_type='unused_planned_credit_v1'
          and c.source_planned_lesson_id=p.id
      ))
  ),overage_sources as(
    select 'actual_duration_overage_charge_v1'::text source_type,
      a.planned_lesson_id source_planned_lesson_id,a.id source_actual_lesson_id,
      round(a.student_duration_overage_minutes::numeric/60,6)::numeric source_hours,
      round(a.student_duration_overage_fee_jpy,2)::numeric source_amount_jpy
    from public.school_lesson_records a
    where a.app_type='school' and a.lesson_type='actual'
      and a.status='completed' and a.is_billable is true and a.voided_at is null
      and a.student_id=p_student_id and a.business_entity_id=p_business_entity_id
      and a.student_settlement_month=p_year_month
      and a.student_duration_overage_policy_version='student_duration_overage_v1'
      and a.student_duration_overage_source='ordinary_actual_rpc'
      and a.student_duration_overage_minutes>0
      and a.student_duration_overage_fee_jpy>0
      and (p_include_active_claimed or not exists(
        select 1 from public.school_student_settlement_lesson_variance_claims c
        where c.claim_status='active'
          and c.source_type='actual_duration_overage_charge_v1'
          and c.source_actual_lesson_id=a.id
      ))
  ),lines as(
    select * from unused_sources union all select * from overage_sources
  ),converted as(
    select line.*,
      round(line.source_amount_jpy*p_settlement_exchange_rate,2)::numeric
        source_amount_cny from lines line
  )
  select converted.source_type,converted.source_planned_lesson_id,
    converted.source_actual_lesson_id,converted.source_hours,
    converted.source_amount_jpy,converted.source_amount_cny,
    encode(extensions.digest(concat_ws('|','lesson_variance_financial_netting_v1',
      converted.source_type,coalesce(converted.source_planned_lesson_id::text,''),
      coalesce(converted.source_actual_lesson_id::text,''),
      converted.source_hours::text,converted.source_amount_jpy::text,
      converted.source_amount_cny::text,
      to_char(p_settlement_exchange_rate,'FM999999990.000000')),
      'sha256'),'hex')::text
  from converted order by converted.source_type,
    converted.source_planned_lesson_id,converted.source_actual_lesson_id
$function$;

alter function public.school_create_lesson_credit_makeup_actual(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) rename to school_create_lesson_credit_makeup_actual_phase2i_a_legacy;
revoke all on function public.school_create_lesson_credit_makeup_actual_phase2i_a_legacy(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) from public,anon,authenticated,service_role;

create function public.school_create_lesson_credit_makeup_actual(
  p_planned_lesson_id uuid,p_lesson_date date,p_teacher_id uuid,p_subject_id uuid,
  p_start_time text,p_end_time text,p_duration_hours numeric,p_lesson_content text,
  p_note text default null,p_lesson_count integer default null,
  p_lesson_delivery_mode text default null,p_lesson_venue text default null
) returns setof public.school_lesson_records language plpgsql security definer
set search_path=pg_catalog,public as $function$
begin
  perform public.school_assert_active_lesson_writer();
  if public.school_is_active_package_credit_origin(p_planned_lesson_id) then
    raise exception using errcode='22023',
      message='LESSON_PACKAGE_SOURCE_NOT_MAKEUP_CREDIT';
  end if;
  return query
  select * from public.school_create_lesson_credit_makeup_actual_phase2i_a_legacy(
    p_planned_lesson_id,p_lesson_date,p_teacher_id,p_subject_id,p_start_time,
    p_end_time,p_duration_hours,p_lesson_content,p_note,p_lesson_count,
    p_lesson_delivery_mode,p_lesson_venue
  );
end
$function$;

create function public.school_guard_package_credit_actual_insert()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public as $function$
begin
  if new.app_type='school' and new.lesson_type='actual'
     and new.planned_lesson_id is not null and new.voided_at is null
     and public.school_is_active_package_credit_origin(new.planned_lesson_id) then
    raise exception using errcode='22023',
      message='LESSON_PACKAGE_SOURCE_NOT_MAKEUP_CREDIT';
  end if;
  return new;
end
$function$;
create trigger school_package_credit_actual_insert_guard
before insert or update on public.school_lesson_records
for each row execute function public.school_guard_package_credit_actual_insert();

revoke all on function public.school_prevent_package_credit_lot_mutation()
  from public,anon,authenticated,service_role;
revoke all on function public.school_guard_package_credit_actual_insert()
  from public,anon,authenticated,service_role;
revoke all on function public.school_is_active_package_credit_origin(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.school_list_student_package_credit_lots(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_student_package_credit_lots(uuid)
  to authenticated;
revoke all on function public.school_get_lesson_credit_raw_remaining_hours(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.school_get_lesson_credit_remaining_hours(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.school_get_lesson_credit_remaining_hours(uuid)
  to anon,authenticated,service_role;
revoke all on function public.school_list_student_lesson_credit_balances(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_student_lesson_credit_balances(uuid)
  to anon,authenticated,service_role;
revoke all on function public.school_list_open_lesson_credit_sources(text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_open_lesson_credit_sources(text,text,text)
  to anon,authenticated,service_role;
revoke all on function public.school_tuition_p0f_source_lines(
  uuid,uuid,text,numeric,boolean
) from public,anon,authenticated,service_role;
revoke all on function public.school_create_lesson_credit_makeup_actual(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) from public,anon,authenticated,service_role;
grant execute on function public.school_create_lesson_credit_makeup_actual(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) to authenticated;

insert into public.school_student_package_credit_lots(
  id,origin_planned_lesson_id,student_id,business_entity_id,
  initial_minutes,consumed_minutes,unit_price_jpy,total_price_jpy,
  student_billing_month,tuition_bill_id,tuition_revision_id,income_record_id,
  cash_linkage_event_id,cash_request_id_snapshot,cash_transaction_id_snapshot,
  status,classification_reason,origin_lesson_row_md5,
  evidence_manifest_sha256,classified_by
)
select
  '2a000000-0000-4000-8000-202608170002',lesson.id,lesson.student_id,
  lesson.business_entity_id,1200,0,13000,260000,'2026-07',
  '07a02092-9503-47d1-9000-106f7e3de7e5',
  '96000000-0000-4000-8000-202608031004',
  '91756564-c48d-4a1d-b6bc-88a041660e46',
  '9de972ff-8e66-470a-8b05-e430ef51562f',
  'a0bee5be-761b-4bc0-a666-411f033e1eba',
  'f500dbe4-07a9-4a4d-ac99-e68592a8af6a','active',
  'P002 is purchased package credit, not ordinary makeup credit.',
  md5(to_jsonb(lesson)::text),
  encode(extensions.digest(concat_ws('|',
    'school_package_credit_lot_phase2i_a_v1',lesson.id::text,
    lesson.student_id::text,lesson.business_entity_id::text,'1200','0',
    '13000','260000','2026-07','07a02092-9503-47d1-9000-106f7e3de7e5',
    '96000000-0000-4000-8000-202608031004',
    '91756564-c48d-4a1d-b6bc-88a041660e46',
    '9de972ff-8e66-470a-8b05-e430ef51562f',
    'a0bee5be-761b-4bc0-a666-411f033e1eba',
    'f500dbe4-07a9-4a4d-ac99-e68592a8af6a',md5(to_jsonb(lesson)::text)
  ),'sha256'),'hex'),'business_owner_phase2i_a_20260817'
from public.school_lesson_records lesson
where lesson.id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9';

comment on table public.school_student_package_credit_lots is
  'Phase 2I-A append-only package classification. P002 remains an immutable lesson/billing fact; no package consumption is enabled.';
comment on function public.school_list_student_package_credit_lots(uuid) is
  'Canonical active-membership package balance reader. Phase 2I-A balance is integer minutes and P002 consumed minutes remain zero.';
comment on function public.school_create_lesson_credit_makeup_actual(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) is 'Phase 2I-A compatibility wrapper. Preserves the current makeup writer and rejects active package origins before delegation.';

\if :phase2i_a_commit
  commit;
\endif
