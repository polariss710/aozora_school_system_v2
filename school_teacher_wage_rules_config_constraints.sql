-- school_teacher_wage_rules_config_constraints.sql
-- Purpose: Add narrow safety constraints for editable teacher wage rule config fields.
-- Status: EXECUTED ON SUPABASE. Verified during wage-rule config edit phase.
-- Version: v2.42.0-wage-rule-config-edit-20260606
--
-- Scope:
-- - Constrain settlement_type to currently verified values.
-- - Constrain editable numeric rate/fee fields to non-negative values.
-- - Does not modify wage locks, wage lock details, payment requests, expenses,
--   accounts, or account transactions.
-- - Does not recalculate historical wages.

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'school_teacher_wage_rules_settlement_type_check'
      and conrelid = 'public.school_teacher_wage_rules'::regclass
  ) then
    alter table public.school_teacher_wage_rules
      add constraint school_teacher_wage_rules_settlement_type_check
      check (settlement_type in ('jpy_hourly', 'no_wage'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'school_teacher_wage_rules_nonnegative_amounts_check'
      and conrelid = 'public.school_teacher_wage_rules'::regclass
  ) then
    alter table public.school_teacher_wage_rules
      add constraint school_teacher_wage_rules_nonnegative_amounts_check
      check (
        hourly_rate_jpy >= 0
        and hourly_rate_cny >= 0
        and exchange_rate >= 0
        and transport_fee_jpy >= 0
        and classroom_fee_jpy >= 0
      );
  end if;
end;
$$;

comment on constraint school_teacher_wage_rules_settlement_type_check
on public.school_teacher_wage_rules is
  'Limits teacher wage rule settlement_type to supported future-lock rule configuration values.';

comment on constraint school_teacher_wage_rules_nonnegative_amounts_check
on public.school_teacher_wage_rules is
  'Ensures editable teacher wage rule rate, exchange rate, and fee fields are non-negative.';
