-- School V2 manual Cash pending-expense backend read-only postdeploy.
\set ON_ERROR_STOP on
\pset pager off

begin read only;

do $verify$
declare
  v_create regprocedure :=
    'public.school_create_pending_cash_expense_record_v1(uuid,date,uuid,text,text,text,numeric,text,numeric,boolean,text,text,uuid,uuid,text)'::regprocedure;
  v_paid regprocedure :=
    'public.school_create_expense_record(date,uuid,uuid,text,text,text,numeric,numeric,text,boolean,text,text,text,uuid,uuid,text)'::regprocedure;
  v_prepare regprocedure :=
    'public.school_request_cash_expense_payment_confirmation(uuid,uuid,uuid,text,text,numeric,text,text,numeric,text)'::regprocedure;
begin
  if (
    select count(*) from information_schema.columns
    where table_schema='public' and table_name='school_expense_records'
      and column_name in ('cash_creation_event_id','created_by_user_id')
      and is_nullable='YES' and data_type='uuid'
  )<>2 then
    raise exception 'P0_PENDING_CASH_COLUMNS_INVALID';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.school_expense_records'::regclass
      and conname='school_expense_records_created_by_user_id_fkey'
      and contype='f'
  ) or not exists (
    select 1 from pg_constraint
    where conrelid='public.school_expense_records'::regclass
      and conname='school_expense_records_manual_creation_audit_check'
      and contype='c'
  ) then
    raise exception 'P0_PENDING_CASH_CONSTRAINTS_INVALID';
  end if;

  if (
    select count(*) from pg_indexes
    where schemaname='public' and tablename='school_expense_records'
      and indexname in (
        'school_expense_records_cash_creation_event_uniq',
        'school_expense_records_cash_request_event_uniq',
        'school_expense_records_cash_request_uniq',
        'school_expense_records_cash_transaction_uniq'
      ) and indexdef like 'CREATE UNIQUE INDEX%'
  )<>4 then
    raise exception 'P0_PENDING_CASH_UNIQUE_INDEXES_INVALID';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid='public.school_expense_records'::regclass
      and tgname='school_guard_expense_creation_audit_immutable_v1'
      and tgenabled='O' and not tgisinternal
  ) then
    raise exception 'P0_PENDING_CASH_IMMUTABILITY_TRIGGER_INVALID';
  end if;

  if has_function_privilege('anon',v_create,'EXECUTE')
     or not has_function_privilege('authenticated',v_create,'EXECUTE')
     or has_function_privilege('service_role',v_create,'EXECUTE')
     or not has_function_privilege('service_role',v_prepare,'EXECUTE')
     or has_function_privilege('authenticated',v_prepare,'EXECUTE') then
    raise exception 'P0_PENDING_CASH_RPC_ACL_INVALID';
  end if;

  if exists (
    select 1 from pg_proc p
    where p.oid in (v_create::oid,v_paid::oid,v_prepare::oid)
      and (not p.prosecdef or not p.proconfig @> array['search_path=pg_catalog, public'])
  ) then
    raise exception 'P0_PENDING_CASH_RPC_SECURITY_INVALID';
  end if;

  if pg_get_functiondef(v_create::oid) not like '%school_require_current_app_admin()%'
     or pg_get_functiondef(v_create::oid) not like '%pg_advisory_xact_lock%'
     or pg_get_functiondef(v_create::oid) not like '%P0_PENDING_CASH_EXPENSE_IDENTITY_PAYLOAD_CONFLICT%'
     or pg_get_functiondef(v_paid::oid) not like '%''manual_school''%'
     or pg_get_functiondef(v_paid::oid) not like '%created_by_user_id%'
     or pg_get_functiondef(v_prepare::oid) not like '%P0_EXPENSE_CASH_REQUEST_SOURCE_NOT_ALLOWED%' then
    raise exception 'P0_PENDING_CASH_RPC_DEFINITION_INVALID';
  end if;

  if exists (
    select 1 from public.school_expense_records
    where source_type not in ('manual_school','manual_cash')
      and (cash_creation_event_id is not null or created_by_user_id is not null)
  ) then
    raise exception 'P0_PENDING_CASH_HISTORICAL_AUDIT_FIELDS_CHANGED';
  end if;

  if (select count(*) from public.school_expense_records)<>46
     or (select count(*) from public.school_expense_records where source_type='teacher_wage')<>17
     or (select count(*) from public.school_expense_records where source_type is null)<>29
     or md5((select string_agg(
       md5((to_jsonb(e)-'cash_creation_event_id'-'created_by_user_id')::text),
       '' order by e.id
     ) from public.school_expense_records e))<>'1a55bca9448e7549399f0a4abca99ac8' then
    raise exception 'P0_PENDING_CASH_HISTORICAL_FINGERPRINT_DRIFT';
  end if;
end;
$verify$;

select feature_key,state,release_version
from public.school_feature_gates
where feature_key in ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit')
order by feature_key;

select count(*) as expense_count,
       count(*) filter(where source_type='teacher_wage') as teacher_wage_count,
       count(*) filter(where source_type is null) as legacy_null_source_count,
       count(*) filter(where source_type='manual_school') as manual_school_count,
       count(*) filter(where source_type='manual_cash') as manual_cash_count,
       count(*) filter(where cash_creation_event_id is not null) as creation_event_count,
       count(*) filter(where created_by_user_id is not null) as creator_audit_count
from public.school_expense_records;

select md5(string_agg(
  md5((to_jsonb(e)-'cash_creation_event_id'-'created_by_user_id')::text),'' order by e.id
)) as school_expense_records_pre_schema_shape_md5
from public.school_expense_records e;

select p.oid::regprocedure::text as signature,p.prosecdef,p.proconfig,p.proacl,
       md5(pg_get_functiondef(p.oid)) as definition_md5
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'school_create_pending_cash_expense_record_v1',
  'school_create_expense_record',
  'school_request_cash_expense_payment_confirmation',
  'school_guard_expense_creation_audit_immutable_v1'
)
order by p.oid::regprocedure::text;

commit;
