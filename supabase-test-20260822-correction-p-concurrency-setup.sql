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

commit;
