-- school_void_unsubmitted_teacher_wage_expense_record_grants.sql
-- Purpose: Ensure the teacher_wage unsubmitted expense void RPC is callable by
-- authenticated School users and service-role backend flows.
-- Version: v10.3.14 grant teacher wage expense void rpc

revoke all on function public.school_void_unsubmitted_teacher_wage_expense_record(uuid, text)
  from public, anon;

grant execute on function public.school_void_unsubmitted_teacher_wage_expense_record(uuid, text)
  to authenticated, service_role;
