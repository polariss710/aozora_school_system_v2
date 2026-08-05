-- Read-only third-session lock proof. Supply numeric session_a_pid and session_b_pid via psql -v.
\set ON_ERROR_STOP on
\pset pager off

begin read only;
select clock_timestamp() observed_at,
       a.pid,a.state,a.xact_start,a.query_start,a.wait_event_type,a.wait_event,
       pg_blocking_pids(a.pid) blocking_pids,
       left(a.query,180) query
from pg_stat_activity a
where a.pid in (:session_a_pid::integer,:session_b_pid::integer)
order by a.pid;

select l.pid,l.locktype,l.mode,l.granted,l.relation::regclass relation,
       l.page,l.tuple,l.transactionid,l.virtualxid
from pg_locks l
where l.pid in (:session_a_pid::integer,:session_b_pid::integer)
order by l.pid,l.granted,l.locktype,l.mode,l.relation;

select :session_a_pid::integer session_a_pid,
       :session_b_pid::integer session_b_pid,
       pg_blocking_pids(:session_b_pid::integer) session_b_blockers,
       1/case when exists (
         select 1 from pg_stat_activity a
         where a.pid=:session_b_pid::integer
           and a.state='active'
           and a.wait_event_type='Lock'
           and :session_a_pid::integer=any(pg_blocking_pids(a.pid))
       ) and exists (
         select 1 from pg_locks l
         where l.pid=:session_b_pid::integer and not l.granted
       ) then 1 else 0 end lock_wait_assertion;
rollback;

select 'STUDENT_STATUS_CONCURRENCY_REAL_LOCK_WAIT_OBSERVED' result;
