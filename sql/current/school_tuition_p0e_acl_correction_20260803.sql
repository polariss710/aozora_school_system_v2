-- P0-E deployed ACL correction: service_role is read-only on append-only evidence table.
\set ON_ERROR_STOP on
\pset pager off
begin;
revoke insert,update,delete,truncate,references,trigger
  on table public.school_student_tuition_generation_revision_adjustments from service_role;
grant select on table public.school_student_tuition_generation_revision_adjustments to service_role;
commit;
