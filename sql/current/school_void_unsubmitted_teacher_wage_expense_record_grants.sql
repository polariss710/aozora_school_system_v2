-- school_void_unsubmitted_teacher_wage_expense_record_grants.sql
-- Purpose: Ensure the interactive teacher_wage unsubmitted expense void RPC is
-- callable only through authenticated active-admin guarded flow.
-- Version: v10.3.14 grant teacher wage expense void rpc

revoke all on function public.school_void_unsubmitted_teacher_wage_expense_record(uuid, text)
  from public, anon, authenticated, service_role;

grant execute on function public.school_void_unsubmitted_teacher_wage_expense_record(uuid, text)
  to authenticated;
