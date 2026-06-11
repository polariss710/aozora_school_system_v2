-- Physically delete one cancelled teacher_wage payment request.
--
-- Target:
--   c8280c86-15f9-410b-b9ac-3588b780b3b0
--
-- Usage:
--   Rollback test:
--     psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -v cleanup_commit=false -f school_delete_payment_request_c8280c86_20260612.sql
--   Commit:
--     psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -v cleanup_commit=true -f school_delete_payment_request_c8280c86_20260612.sql
--
-- Safety:
-- - Deletes only this exact payment request id.
-- - Requires source_type = teacher_wage and status = cancelled.
-- - Requires no paid expense, no paid/reversal transaction, no account.
-- - Requires no reissue/replacement references from other payment requests.

\if :{?cleanup_commit}
\else
\set cleanup_commit false
\endif

\echo cleanup_commit=:cleanup_commit

begin;

create temp table target_payment_request as
select *
from school_payment_requests
where id = 'c8280c86-15f9-410b-b9ac-3588b780b3b0';

\echo target_before_delete
select
  id,
  source_type,
  source_id,
  request_month,
  payee_name,
  business_name,
  currency,
  amount,
  status,
  paid_expense_id,
  paid_account_transaction_id,
  account_id,
  note
from target_payment_request;

do $$
declare
  target_count integer;
begin
  select count(*) into target_count from target_payment_request;
  if target_count <> 1 then
    raise exception 'expected exactly one target payment request, found %', target_count;
  end if;

  if exists (
    select 1
    from target_payment_request
    where source_type <> 'teacher_wage'
       or status <> 'cancelled'
       or paid_expense_id is not null
       or paid_account_transaction_id is not null
       or reversal_transaction_id is not null
       or account_id is not null
  ) then
    raise exception 'target payment request is not a deletable cancelled unpaid teacher_wage request';
  end if;

  if exists (
    select 1
    from school_payment_requests pr
    where pr.id <> 'c8280c86-15f9-410b-b9ac-3588b780b3b0'
      and (
        pr.reissued_from_payment_request_id = 'c8280c86-15f9-410b-b9ac-3588b780b3b0'
        or pr.replacement_payment_request_id = 'c8280c86-15f9-410b-b9ac-3588b780b3b0'
      )
  ) then
    raise exception 'target payment request is referenced by a reissue/replacement chain';
  end if;

  if exists (
    select 1
    from school_account_transactions tx
    where tx.related_table = 'school_payment_requests'
      and tx.related_id = 'c8280c86-15f9-410b-b9ac-3588b780b3b0'
  ) then
    raise exception 'target payment request has account transaction references';
  end if;
end $$;

with deleted as (
  delete from school_payment_requests
  where id = 'c8280c86-15f9-410b-b9ac-3588b780b3b0'
  returning id
)
select 'deleted_count' as check_name, count(*) as count
from deleted;

\echo post_delete_checks
select 'target_remaining' as check_name, count(*) as count
from school_payment_requests
where id = 'c8280c86-15f9-410b-b9ac-3588b780b3b0'
union all
select 'reissue_references_remaining', count(*)
from school_payment_requests
where reissued_from_payment_request_id = 'c8280c86-15f9-410b-b9ac-3588b780b3b0'
   or replacement_payment_request_id = 'c8280c86-15f9-410b-b9ac-3588b780b3b0'
union all
select 'account_tx_references_remaining', count(*)
from school_account_transactions
where related_table = 'school_payment_requests'
  and related_id = 'c8280c86-15f9-410b-b9ac-3588b780b3b0';

\if :cleanup_commit
commit;
\echo payment request delete committed
\else
rollback;
\echo payment request delete rolled back
\endif
