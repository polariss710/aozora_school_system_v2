-- School V2 tuition P0 R1A: nullable income -> tuition bill reference.
-- Existing rows remain NULL. The partial unique index is safe before backfill.

begin;

alter table public.school_income_records
  add column if not exists tuition_bill_id uuid;

alter table public.school_income_records
  drop constraint if exists school_income_records_tuition_bill_id_fkey;

alter table public.school_income_records
  add constraint school_income_records_tuition_bill_id_fkey
    foreign key (tuition_bill_id)
    references public.school_student_tuition_bills(id)
    on delete restrict;

create unique index if not exists school_income_records_tuition_bill_id_key
  on public.school_income_records (tuition_bill_id)
  where tuition_bill_id is not null;

comment on column public.school_income_records.tuition_bill_id is
  'Nullable reverse reference prepared in R1A. Historical rows remain NULL until a reviewed 9/9 backfill.';

commit;
