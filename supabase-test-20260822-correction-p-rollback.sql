-- Correction-P School isolated PostgreSQL 17 matrix. Retains nothing.

begin;

insert into auth.users(id) values ('25331ae9-3412-48b9-bdc3-e516caeaeba4');
insert into public.school_app_memberships(
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values (
  '25331ae9-3412-48b9-bdc3-e516caeaeba4','admin',true,
  '25331ae9-3412-48b9-bdc3-e516caeaeba4','25331ae9-3412-48b9-bdc3-e516caeaeba4','Correction-P fixture'
);

insert into public.school_expense_records(
  id,expense_date,year_month,expense_category,description,currency,amount,
  amount_jpy,amount_cny,status,source_type,cash_creation_event_id,created_by_user_id,
  cash_request_id,cash_request_status,cash_transaction_id,cash_requested_at,
  cash_synced_at,cash_request_event_id,cash_request_attempt_no,
  cash_payment_amount,cash_payment_currency,cash_payment_note
) values (
  'ed23a346-2ba5-47fb-a496-4c4ba781ec86','2026-08-13','2026-08','classroom',
  '教室租金','JPY',202991,202991,0,'paid','manual_cash',
  'c0de0000-0000-4000-8000-00000000c001','25331ae9-3412-48b9-bdc3-e516caeaeba4',
  'ea5a7ce2-1b7a-44f3-8db7-22bb73c963bc','approved',
  '01e910b8-bf54-486c-a13a-597ca9dbf684',statement_timestamp(),statement_timestamp(),
  'fa3aad38-5886-4154-a7d4-8c8331fb71fe',1,202991,'JPY','Correction-P target'
);

insert into public.school_expense_cash_attempts(
  id,expense_id,attempt_no,payment_route,request_type,request_event_id,
  idempotency_key,cash_request_id,cash_transaction_id,cash_funding_account_id,
  original_amount,original_currency,charge_date,attempt_status,submitted_at,
  approved_at,version,payment_amount,payment_currency
) values (
  'b6c8a4ca-0a27-4e4c-aae3-7498d0c18cd5','ed23a346-2ba5-47fb-a496-4c4ba781ec86',1,
  'immediate_account','expense_paid','fa3aad38-5886-4154-a7d4-8c8331fb71fe',
  'aozora_school:school_expense_records:ed23a346-2ba5-47fb-a496-4c4ba781ec86:expense_paid:attempt:1',
  'ea5a7ce2-1b7a-44f3-8db7-22bb73c963bc','01e910b8-bf54-486c-a13a-597ca9dbf684',
  'b06f29c4-67cd-4d55-b39c-7cff0eab99a1',202991,'JPY','2026-08-13',
  'approved_immediate',statement_timestamp(),statement_timestamp(),3,202991,'JPY'
);

do $acl$
begin
  if has_table_privilege('service_role','public.school_expense_cash_corrections','INSERT,UPDATE,DELETE')
     or has_function_privilege('public','public.school_finalize_expense_cash_correction_p(uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,numeric,text,date,text,uuid,text,text,text,text,uuid,jsonb)','EXECUTE')
     or has_function_privilege('anon','public.school_finalize_expense_cash_correction_p(uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,numeric,text,date,text,uuid,text,text,text,text,uuid,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','public.school_finalize_expense_cash_correction_p(uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,numeric,text,date,text,uuid,text,text,text,text,uuid,jsonb)','EXECUTE')
     or not has_function_privilege('service_role','public.school_finalize_expense_cash_correction_p(uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,numeric,text,date,text,uuid,text,text,text,text,uuid,jsonb)','EXECUTE') then
    raise exception 'SCHOOL_CORRECTION_P_ACL_INVALID';
  end if;
end;
$acl$;

select set_config('request.jwt.claim.role','service_role',true);
select set_config('request.jwt.claim.sub','25331ae9-3412-48b9-bdc3-e516caeaeba4',true);

create temp table correction_p_school_test_control(step text not null) on commit drop;
create or replace function pg_temp.correction_p_school_test_raise()
returns trigger language plpgsql as $$
begin
  raise exception using errcode='P0001',message='CORRECTION_P_SCHOOL_TEST_TRIGGER_FAILURE';
end;
$$;

do $source$
declare s jsonb;
begin
  s:=public.school_get_expense_cash_correction_source_v1(
    'ed23a346-2ba5-47fb-a496-4c4ba781ec86','b6c8a4ca-0a27-4e4c-aae3-7498d0c18cd5',
    '25331ae9-3412-48b9-bdc3-e516caeaeba4');
  if not coalesce((s->>'ok')::boolean,false)
     or s->>'original_home_request_id'<>'ea5a7ce2-1b7a-44f3-8db7-22bb73c963bc'
     or s->>'original_home_transaction_id'<>'01e910b8-bf54-486c-a13a-597ca9dbf684'
     or (s->>'amount')::numeric<>202991 or s->>'currency'<>'JPY'
     or s->>'charge_date'<>'2026-08-13' or s->>'school_fingerprint'!~'^[0-9a-f]{64}$' then
    raise exception 'SCHOOL_CORRECTION_P_SOURCE_INVALID:%',s;
  end if;
end;
$source$;

do $finalize$
declare
  sf text:=(select request_payload_fingerprint from public.school_expense_cash_attempts where id='b6c8a4ca-0a27-4e4c-aae3-7498d0c18cd5');
  h jsonb;
  r jsonb;
  step text;
  before_expense text:=(select md5(to_jsonb(e)::text) from public.school_expense_records e where id='ed23a346-2ba5-47fb-a496-4c4ba781ec86');
  before_attempt text:=(select md5(to_jsonb(a)::text) from public.school_expense_cash_attempts a where id='b6c8a4ca-0a27-4e4c-aae3-7498d0c18cd5');
  before_profit text:=md5(public.school_get_profit_summary_schoolwide_v1('2026-08','2026-08')::text);
begin
  h:=jsonb_build_object(
    'ok',true,'status','prepared','correction_id','c0de0000-0000-4000-8000-000000000101',
    'operation_id','c0de0000-0000-4000-8000-000000000001',
    'original_home_request_id','ea5a7ce2-1b7a-44f3-8db7-22bb73c963bc',
    'original_home_transaction_id','01e910b8-bf54-486c-a13a-597ca9dbf684',
    'balance_effect_id','c0de0000-0000-4000-8000-000000000102',
    'replacement_request_id','c0de0000-0000-4000-8000-000000000103',
    'replacement_fixed_item_id','c0de0000-0000-4000-8000-000000000104',
    'replacement_projection_id','c0de0000-0000-4000-8000-000000000105',
    'school_expense_id','ed23a346-2ba5-47fb-a496-4c4ba781ec86',
    'school_attempt_id','b6c8a4ca-0a27-4e4c-aae3-7498d0c18cd5',
    'amount',202991,'currency','JPY','original_effective_date','2026-08-13',
    'accounting_scope','school','external_event_id','fa3aad38-5886-4154-a7d4-8c8331fb71fe',
    'original_idempotency_key','aozora_school:school_expense_records:ed23a346-2ba5-47fb-a496-4c4ba781ec86:expense_paid:attempt:1',
    'school_fingerprint',sf,'home_payload_hash',repeat('b',32),
    'replacement_fingerprint',repeat('c',64),'actor_id','25331ae9-3412-48b9-bdc3-e516caeaeba4');

  r:=public.school_finalize_expense_cash_correction_p(
    'c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000101',
    'ea5a7ce2-1b7a-44f3-8db7-22bb73c963bc','01e910b8-bf54-486c-a13a-597ca9dbf684',
    'c0de0000-0000-4000-8000-000000000102','c0de0000-0000-4000-8000-000000000103',
    'c0de0000-0000-4000-8000-000000000104','c0de0000-0000-4000-8000-000000000105',
    'ed23a346-2ba5-47fb-a496-4c4ba781ec86','b6c8a4ca-0a27-4e4c-aae3-7498d0c18cd5',
    202991,'JPY','2026-08-13','school','fa3aad38-5886-4154-a7d4-8c8331fb71fe',
    'aozora_school:school_expense_records:ed23a346-2ba5-47fb-a496-4c4ba781ec86:expense_paid:attempt:1',
    sf,repeat('b',32),repeat('c',64),'25331ae9-3412-48b9-bdc3-e516caeaeba4',
    jsonb_set(h,'{amount}','202990'::jsonb));
  if r->>'code'<>'SCHOOL_CORRECTION_P_FINALIZE_INPUT_INVALID'
     or exists(select 1 from public.school_expense_cash_corrections) then
    raise exception 'SCHOOL_CORRECTION_P_HOME_SNAPSHOT_MISMATCH_NOT_BLOCKED:%',r;
  end if;

  foreach step in array array['before_insert','after_insert'] loop
    execute format(
      'create trigger correction_p_school_test_failure %s insert on public.school_expense_cash_corrections for each row execute function pg_temp.correction_p_school_test_raise()',
      case step when 'before_insert' then 'before' else 'after' end
    );
    begin
      perform public.school_finalize_expense_cash_correction_p(
      'c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000101',
      'ea5a7ce2-1b7a-44f3-8db7-22bb73c963bc','01e910b8-bf54-486c-a13a-597ca9dbf684',
      'c0de0000-0000-4000-8000-000000000102','c0de0000-0000-4000-8000-000000000103',
      'c0de0000-0000-4000-8000-000000000104','c0de0000-0000-4000-8000-000000000105',
      'ed23a346-2ba5-47fb-a496-4c4ba781ec86','b6c8a4ca-0a27-4e4c-aae3-7498d0c18cd5',
      202991,'JPY','2026-08-13','school','fa3aad38-5886-4154-a7d4-8c8331fb71fe',
      'aozora_school:school_expense_records:ed23a346-2ba5-47fb-a496-4c4ba781ec86:expense_paid:attempt:1',
        sf,repeat('b',32),repeat('c',64),'25331ae9-3412-48b9-bdc3-e516caeaeba4',h);
      raise exception 'SCHOOL_CORRECTION_P_FAILURE_INJECTION_MISSED:%',step;
    exception when others then
      if sqlerrm like 'SCHOOL_CORRECTION_P_FAILURE_INJECTION_MISSED:%' then raise; end if;
    end;
    drop trigger correction_p_school_test_failure
      on public.school_expense_cash_corrections;
    if exists(select 1 from public.school_expense_cash_corrections) then
      raise exception 'SCHOOL_CORRECTION_P_FAILURE_LEFT_EVIDENCE:%',step;
    end if;
  end loop;

  r:=public.school_finalize_expense_cash_correction_p(
    'c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000101',
    'ea5a7ce2-1b7a-44f3-8db7-22bb73c963bc','01e910b8-bf54-486c-a13a-597ca9dbf684',
    'c0de0000-0000-4000-8000-000000000102','c0de0000-0000-4000-8000-000000000103',
    'c0de0000-0000-4000-8000-000000000104','c0de0000-0000-4000-8000-000000000105',
    'ed23a346-2ba5-47fb-a496-4c4ba781ec86','b6c8a4ca-0a27-4e4c-aae3-7498d0c18cd5',
    202991,'JPY','2026-08-13','school','fa3aad38-5886-4154-a7d4-8c8331fb71fe',
    'aozora_school:school_expense_records:ed23a346-2ba5-47fb-a496-4c4ba781ec86:expense_paid:attempt:1',
    sf,repeat('b',32),repeat('c',64),'25331ae9-3412-48b9-bdc3-e516caeaeba4',h);
  if not coalesce((r->>'ok')::boolean,false) or r->>'school_evidence_fingerprint'!~'^[0-9a-f]{64}$' then
    raise exception 'SCHOOL_CORRECTION_P_FINALIZE_INVALID:%',r;
  end if;
  if not coalesce((public.school_finalize_expense_cash_correction_p(
    'c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000101',
    'ea5a7ce2-1b7a-44f3-8db7-22bb73c963bc','01e910b8-bf54-486c-a13a-597ca9dbf684',
    'c0de0000-0000-4000-8000-000000000102','c0de0000-0000-4000-8000-000000000103',
    'c0de0000-0000-4000-8000-000000000104','c0de0000-0000-4000-8000-000000000105',
    'ed23a346-2ba5-47fb-a496-4c4ba781ec86','b6c8a4ca-0a27-4e4c-aae3-7498d0c18cd5',
    202991,'JPY','2026-08-13','school','fa3aad38-5886-4154-a7d4-8c8331fb71fe',
    'aozora_school:school_expense_records:ed23a346-2ba5-47fb-a496-4c4ba781ec86:expense_paid:attempt:1',
    sf,repeat('b',32),repeat('c',64),'25331ae9-3412-48b9-bdc3-e516caeaeba4',h)->>'idempotent')::boolean,false) then
    raise exception 'SCHOOL_CORRECTION_P_REPLAY_INVALID';
  end if;

  r:=public.school_finalize_expense_cash_correction_p(
    'c0de0000-0000-4000-8000-000000000001','c0de0000-0000-4000-8000-000000000101',
    'ea5a7ce2-1b7a-44f3-8db7-22bb73c963bc','01e910b8-bf54-486c-a13a-597ca9dbf684',
    'c0de0000-0000-4000-8000-000000000102','c0de0000-0000-4000-8000-000000000103',
    'c0de0000-0000-4000-8000-000000000104','c0de0000-0000-4000-8000-000000000105',
    'ed23a346-2ba5-47fb-a496-4c4ba781ec86','b6c8a4ca-0a27-4e4c-aae3-7498d0c18cd5',
    202990,'JPY','2026-08-13','school','fa3aad38-5886-4154-a7d4-8c8331fb71fe',
    'aozora_school:school_expense_records:ed23a346-2ba5-47fb-a496-4c4ba781ec86:expense_paid:attempt:1',
    sf,repeat('b',32),repeat('c',64),'25331ae9-3412-48b9-bdc3-e516caeaeba4',
    jsonb_set(h,'{amount}','202990'::jsonb));
  if r->>'code'<>'SCHOOL_CORRECTION_P_TERMINAL_CONFLICT'
     or (select count(*) from public.school_expense_cash_corrections)<>1
     or (select md5(to_jsonb(e)::text) from public.school_expense_records e where id='ed23a346-2ba5-47fb-a496-4c4ba781ec86')<>before_expense
     or (select md5(to_jsonb(a)::text) from public.school_expense_cash_attempts a where id='b6c8a4ca-0a27-4e4c-aae3-7498d0c18cd5')<>before_attempt
     or md5(public.school_get_profit_summary_schoolwide_v1('2026-08','2026-08')::text)<>before_profit
     or (select count(*) from public.school_account_transactions)<>0 then
    raise exception 'SCHOOL_CORRECTION_P_CONFLICT_OR_NO_MUTATION_INVALID:%',r;
  end if;
end;
$finalize$;

do $immutable$
declare denied int:=0;
begin
  begin update public.school_expense_cash_corrections set amount=1;
  exception when sqlstate '42501' then denied:=denied+1; end;
  begin delete from public.school_expense_cash_corrections;
  exception when sqlstate '42501' then denied:=denied+1; end;
  begin update public.school_expense_cash_attempts set attempt_status='approved_fixed';
  exception when others then denied:=denied+1; end;
  if denied<>3
     or (select status from public.school_expense_records where id='ed23a346-2ba5-47fb-a496-4c4ba781ec86')<>'paid'
     or (select attempt_status from public.school_expense_cash_attempts where id='b6c8a4ca-0a27-4e4c-aae3-7498d0c18cd5')<>'approved_immediate' then
    raise exception 'SCHOOL_CORRECTION_P_IMMUTABILITY_INVALID';
  end if;
end;
$immutable$;

rollback;
