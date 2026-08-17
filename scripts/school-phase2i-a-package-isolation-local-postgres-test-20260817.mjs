import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const pgBin = "/opt/homebrew/Cellar/postgresql@17/17.10/bin";
const initdb = join(pgBin, "initdb");
const pgCtl = join(pgBin, "pg_ctl");
const psqlBin = join(pgBin, "psql");
const repo = resolve(import.meta.dirname, "..");
const root = mkdtempSync(join(tmpdir(), "school-phase2i-a-"));
const data = join(root, "data");
const socket = join(root, "socket");
const port = String(56000 + (process.pid % 700));

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: "utf8", ...options });
  if (result.status !== 0) {
    throw new Error(`${command} failed\n${result.stdout || ""}\n${result.stderr || ""}`);
  }
  return result.stdout;
}
function psqlArgs(extra = []) {
  return ["-X", "-h", socket, "-p", port, "-d", "postgres", "-v", "ON_ERROR_STOP=1", ...extra];
}
function scalar(sql) {
  return run(psqlBin, psqlArgs(["-At", "-c", sql])).trim();
}
function file(path, variables = {}) {
  const vars = Object.entries(variables).flatMap(([key, value]) => ["-v", `${key}=${value}`]);
  return run(psqlBin, psqlArgs([...vars, "-f", join(repo, path)]), { timeout: 30000 });
}

let started = false;
try {
  run(initdb, ["-D", data, "--no-locale", "--encoding=UTF8", "--auth=trust"]);
  run("mkdir", [socket]);
  run(pgCtl, ["-D", data, "-o", `-F -p ${port} -k ${socket} -c listen_addresses=''`, "-w", "start"], { stdio: "ignore" });
  started = true;

  file("sql/tests/school_phase2i_a_p002_package_isolation_local_bootstrap_20260817.sql");
  const p002 = scalar("select md5(to_jsonb(x)::text) from school_lesson_records x where id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'");
  const signatures = {
    phase2i_a_expected_p002_md5: p002,
    phase2i_a_expected_raw_md5: scalar("select md5(pg_get_functiondef('school_get_lesson_credit_raw_remaining_hours(uuid)'::regprocedure))"),
    phase2i_a_expected_remaining_md5: scalar("select md5(pg_get_functiondef('school_get_lesson_credit_remaining_hours(uuid)'::regprocedure))"),
    phase2i_a_expected_balance_md5: scalar("select md5(pg_get_functiondef('school_list_student_lesson_credit_balances(uuid)'::regprocedure))"),
    phase2i_a_expected_open_md5: scalar("select md5(pg_get_functiondef('school_list_open_lesson_credit_sources(text,text,text)'::regprocedure))"),
    phase2i_a_expected_p0f_md5: scalar("select md5(pg_get_functiondef('school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)'::regprocedure))"),
    phase2i_a_expected_writer_md5: scalar("select md5(pg_get_functiondef('school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure))"),
    phase2i_a_commit: "1",
  };
  const migrationOutput = file("sql/current/school_phase2i_a_p002_package_isolation_migration_20260817.sql", signatures);
  assert.match(migrationOutput, /COMMIT/);
  const contractOutput = file("sql/tests/school_phase2i_a_p002_package_isolation_contract_local_20260817.sql");
  assert.match(contractOutput, /passed_assertions[\s\S]*24/);

  file("sql/current/school_phase2i_a_p002_package_isolation_exact_rollback_20260817.sql", {
    phase2i_a_expected_p002_md5: p002,
    phase2i_a_expected_writer_md5: signatures.phase2i_a_expected_writer_md5,
    phase2i_a_rollback_commit: "1",
  });
  assert.equal(scalar("select to_regclass('public.school_student_package_credit_lots') is null"), "t");
  assert.equal(scalar("select md5(to_jsonb(x)::text) from school_lesson_records x where id='8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9'"), p002);
  assert.equal(scalar("select md5(pg_get_functiondef('school_get_lesson_credit_raw_remaining_hours(uuid)'::regprocedure))"), "f5da14743858f89d37f17ba2646ab092");
  console.log("SCHOOL_PHASE2I_A_PACKAGE_ISOLATION_LOCAL_POSTGRES_PASS");
} finally {
  if (started) spawnSync(pgCtl, ["-D", data, "-m", "immediate", "-w", "stop"], { stdio: "ignore" });
  rmSync(root, { recursive: true, force: true });
}
