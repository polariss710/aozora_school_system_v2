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
const root = mkdtempSync(join(tmpdir(), "school-phase2c-d2-a2-"));
const data = join(root, "data");
const socket = join(root, "socket");
const port = String(57700 + (process.pid % 200));

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
function file(path, variables = {}) {
  const vars = Object.entries(variables).flatMap(([key, value]) => ["-v", `${key}=${value}`]);
  return run(psqlBin, psqlArgs([...vars, "-f", join(repo, path)]), { timeout: 60000 });
}
function scalar(sql) {
  return run(psqlBin, psqlArgs(["-At", "-c", sql])).trim();
}

let started = false;
try {
  run(initdb, ["-D", data, "--no-locale", "--encoding=UTF8", "--auth=trust"]);
  run("mkdir", [socket]);
  run(pgCtl, ["-D", data, "-o", `-F -p ${port} -k ${socket} -c listen_addresses=''`, "-w", "start"], { stdio: "ignore" });
  started = true;

  file("sql/tests/school_phase2c_c_r2_clearance_candidate_readers_local_bootstrap_20260817.sql");
  file("sql/current/school_phase2c_c_r2_clearance_candidate_readers_migration_20260817.sql", {
    PHASE2C_C_R2_SKIP_PRODUCTION_MD5: "1",
  });
  const migration = file("sql/current/school_phase2c_d2_a2_pending_operational_date_reader_v3_migration_20260818.sql", {
    PHASE2C_D2_A2_SKIP_PRODUCTION_MD5: "1",
  });
  assert.match(migration, /COMMIT/);
  const contract = file("sql/tests/school_phase2c_d2_a2_pending_operational_date_reader_v3_local_20260818.sql");
  assert.match(contract, /passed_assertions=5/);
  const roles = file("sql/tests/school_phase2c_d2_a2_pending_operational_date_reader_v3_role_matrix_local_20260818.sql");
  assert.match(roles, /PHASE2C_D2_A2_ROLE_MATRIX_PASS/);

  assert.equal(scalar("select count(*) from school_lesson_clearances"), "2");
  file("sql/current/school_phase2c_d2_a2_pending_operational_date_reader_v3_exact_rollback_20260818.sql", {
    PHASE2C_D2_A2_SKIP_PRODUCTION_MD5: "1",
  });
  assert.equal(scalar("select to_regprocedure('school_list_lesson_clearance_pending_balances_v3(uuid,boolean)') is null"), "t");
  assert.notEqual(scalar("select to_regprocedure('school_list_lesson_clearance_pending_balances_v2(uuid,boolean)') is null"), "t");
  assert.equal(scalar("select count(*) from school_lesson_clearances"), "2");
  console.log("SCHOOL_PHASE2C_D2_A2_PENDING_OPERATIONAL_DATE_LOCAL_POSTGRES_PASS");
} finally {
  if (started) spawnSync(pgCtl, ["-D", data, "-m", "immediate", "-w", "stop"], { stdio: "ignore" });
  rmSync(root, { recursive: true, force: true });
}
