-- School V2 Phase BE-UI production deploy. DDL/ACL only; business DML = 0.
\set ON_ERROR_STOP on
\pset pager off

begin;
\ir school_business_entity_ui_closure_core_20260806.sql
commit;
