-- School V2 manual Cash pending-expense creation identity and creator audit.
-- Status: reviewed source; deploy only through the phase deployment wrapper.
-- Historical rows remain NULL and are not backfilled.

alter table public.school_expense_records
  add column if not exists cash_creation_event_id uuid,
  add column if not exists created_by_user_id uuid;

do $block$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid='public.school_expense_records'::regclass
      and conname='school_expense_records_created_by_user_id_fkey'
  ) then
    alter table public.school_expense_records
      add constraint school_expense_records_created_by_user_id_fkey
      foreign key (created_by_user_id) references auth.users(id);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid='public.school_expense_records'::regclass
      and conname='school_expense_records_manual_creation_audit_check'
  ) then
    alter table public.school_expense_records
      add constraint school_expense_records_manual_creation_audit_check
      check (
        source_type not in ('manual_school','manual_cash')
        or (
          created_by_user_id is not null
          and (
            (
              source_type='manual_school'
              and cash_creation_event_id is null
              and account_id is not null
            )
            or (
              source_type='manual_cash'
              and cash_creation_event_id is not null
              and account_id is null
              and payment_method is null
            )
          )
        )
      );
  end if;
end;
$block$;

create unique index if not exists school_expense_records_cash_creation_event_uniq
  on public.school_expense_records(cash_creation_event_id)
  where cash_creation_event_id is not null;

create unique index if not exists school_expense_records_cash_request_event_uniq
  on public.school_expense_records(cash_request_event_id)
  where cash_request_event_id is not null;

create unique index if not exists school_expense_records_cash_request_uniq
  on public.school_expense_records(cash_request_id)
  where cash_request_id is not null;

create unique index if not exists school_expense_records_cash_transaction_uniq
  on public.school_expense_records(cash_transaction_id)
  where cash_transaction_id is not null;

comment on column public.school_expense_records.cash_creation_event_id is
  'Immutable client request UUID for one manual Cash pending-expense creation action. NULL for legacy, teacher-wage, and direct School-paid rows.';
comment on column public.school_expense_records.created_by_user_id is
  'Immutable DB-authoritative auth.uid creator audit. Same UUID is the school_app_memberships primary identity. Historical rows remain NULL.';
