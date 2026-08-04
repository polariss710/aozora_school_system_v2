-- Postdeploy amendment after the phase 2 closure verification.
-- Closes old-overload search paths and the remaining service-role direct table DML.
\set ON_ERROR_STOP on
\pset pager off

begin;

alter function public.school_update_expense_record(
  uuid,date,uuid,uuid,text,text,text,numeric,numeric,text,text,text,text,text
) set search_path = pg_catalog, public;
alter function public.school_update_teacher_wage_rule_config(
  uuid,text,numeric,numeric,numeric,numeric,numeric,boolean,text
) set search_path = pg_catalog, public;

revoke insert,update,delete,truncate,references,trigger on table
  public.school_expense_records,
  public.school_accounts,
  public.school_account_transactions,
  public.school_teacher_wage_detail_adjustments
from service_role;

commit;
