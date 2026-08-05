-- Phase B3 production deploy wrapper. Function/helper/comment/ACL definitions only.
\set ON_ERROR_STOP on
\pset pager off

begin;
\ir school_student_status_phase_b3_writer_authority_core_20260806.sql
commit;
