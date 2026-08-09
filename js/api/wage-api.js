import { supabase } from "../supabase-client.js";
import { fetchStudentMonthCandidates } from "./student-status-api.js?v=phase-b4-remaining-20260807-1";

const WAGE_LOCK_COLUMNS = [
  "id",
  "teacher_id",
  "teacher_name",
  "settlement_month",
  "business_entity_id",
  "business_name",
  "settlement_type",
  "exchange_rate",
  "lesson_count",
  "total_minutes",
  "pay_hours",
  "fee_jpy",
  "lesson_wage_jpy",
  "lesson_wage_cny",
  "total_jpy",
  "total_cny",
  "status",
  "locked_at",
  "voided_at",
  "void_reason",
  "voided_by",
  "void_source",
].join(",");

const PAYMENT_REQUEST_COLUMNS = [
  "id",
  "source_id",
  "request_month",
  "status",
  "amount",
  "currency",
  "paid_at",
  "created_at",
  "updated_at",
].join(",");

const EXPENSE_RECORD_COLUMNS = [
  "id",
  "status",
  "cancelled_at",
  "source_type",
  "source_id",
  "app_type",
  "cash_request_id",
  "cash_request_status",
  "cash_transaction_id",
  "created_at",
  "updated_at",
].join(",");

const WAGE_DETAIL_FEE_COLUMNS = [
  "lock_id",
  "transport_fee_jpy",
  "classroom_fee_jpy",
].join(",");

const WAGE_CANDIDATE_LESSON_COLUMNS = [
  "id",
  "lesson_type",
  "status",
  "lesson_date",
  "start_time",
  "end_time",
  "teacher_settlement_month",
  "student_settlement_month",
  "year_month",
  "teacher_id",
  "student_id",
  "subject_id",
  "business_entity_id",
  "duration_hours",
  "actual_minutes",
  "is_billable",
  "lesson_content",
  "note",
].join(",");

export async function fetchWageLocks(month) {
  const { data, error } = await supabase
    .from("school_teacher_wage_locks")
    .select(WAGE_LOCK_COLUMNS)
    .eq("settlement_month", month);

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchWageCandidateLessons(month) {
  const [teacherMonthResult, fallbackMonthResult, preflightResult] = await Promise.all([
    supabase
      .from("school_lesson_records")
      .select(WAGE_CANDIDATE_LESSON_COLUMNS)
      .eq("app_type", "school")
      .eq("lesson_type", "actual")
      .in("status", ["completed", "makeup_completed"])
      .is("voided_at", null)
      .eq("teacher_settlement_month", month)
      .order("lesson_date", { ascending: true })
      .order("start_time", { ascending: true }),
    supabase
      .from("school_lesson_records")
      .select(WAGE_CANDIDATE_LESSON_COLUMNS)
      .eq("app_type", "school")
      .eq("lesson_type", "actual")
      .in("status", ["completed", "makeup_completed"])
      .is("voided_at", null)
      .is("teacher_settlement_month", null)
      .eq("year_month", month)
      .order("lesson_date", { ascending: true })
      .order("start_time", { ascending: true }),
    supabase.rpc("school_get_teacher_monthly_wage_generation_preflight", {
      p_year_month: month,
      p_teacher_id: null,
      p_business_entity_id: null,
    }),
  ]);

  if (teacherMonthResult.error) {
    throw teacherMonthResult.error;
  }
  if (fallbackMonthResult.error) {
    throw fallbackMonthResult.error;
  }
  if (preflightResult.error) {
    throw preflightResult.error;
  }

  const rowsById = new Map();
  for (const row of [...(teacherMonthResult.data || []), ...(fallbackMonthResult.data || [])]) {
    rowsById.set(row.id, row);
  }

  const rows = (await Promise.all(
    Array.from(rowsById.values()).map(attachAuthoritativeStudentMonth)
  )).sort(sortCandidateLessons);
  if (!rows.length) {
    return [];
  }

  const [detailBlockerResult, wageLockBlockerResult] = await Promise.all([
    supabase
      .from("school_teacher_wage_lock_details")
      .select("lesson_record_id,lock_id")
      .in("lesson_record_id", rows.map((row) => row.id)),
    supabase
      .from("school_teacher_wage_locks")
      .select("teacher_id,business_entity_id")
      .eq("settlement_month", month)
      .eq("status", "locked"),
  ]);

  if (detailBlockerResult.error) {
    throw detailBlockerResult.error;
  }
  if (wageLockBlockerResult.error) {
    throw wageLockBlockerResult.error;
  }

  const detailLocksByLessonId = new Map();
  for (const row of detailBlockerResult.data || []) {
    if (!detailLocksByLessonId.has(row.lesson_record_id)) {
      detailLocksByLessonId.set(row.lesson_record_id, []);
    }
    detailLocksByLessonId.get(row.lesson_record_id).push(row.lock_id);
  }
  const lockedTeacherBusinessKeys = new Set(
    (wageLockBlockerResult.data || []).map((row) => teacherBusinessKey(row.teacher_id, row.business_entity_id))
  );
  const prerequisiteByLessonId = wagePrerequisiteFactsByLessonId(preflightResult.data);

  return rows.map((row) => {
    const prerequisite = prerequisiteByLessonId.get(row.id);
    if (!prerequisite) {
      throw new Error(`WAGE_PREFLIGHT_CANDIDATE_COVERAGE_MISMATCH:${row.id}`);
    }
    return {
      ...row,
      wageDetailBlocked: detailLocksByLessonId.has(row.id),
      wageDetailLockIds: detailLocksByLessonId.get(row.id) || [],
      wageMonthBlocked: lockedTeacherBusinessKeys.has(teacherBusinessKey(row.teacher_id, row.business_entity_id)),
      wagePrerequisiteSatisfied: prerequisite.prerequisite_satisfied === true,
      wagePrerequisiteStatus: prerequisite.prerequisite_status || "",
      wagePrerequisiteBlockerCode: prerequisite.blocker_code || "",
      wagePrerequisiteBlockerDetail: prerequisite.blocker_detail || "",
      wagePrerequisiteSourceType: prerequisite.effective_source_type || "",
      wagePrerequisiteSourceId: prerequisite.effective_source_id || "",
      wageSettlementType: prerequisite.settlement_type || "",
      wageNoWage: prerequisite.is_no_wage === true,
    };
  });
}

function wagePrerequisiteFactsByLessonId(preflight) {
  const rows = Array.isArray(preflight?.candidate_prerequisites)
    ? preflight.candidate_prerequisites
    : [];
  return new Map(rows.map((row) => [row.lesson_record_id, row]));
}

export async function fetchWageDetailFeeSummaries(wageLockIds) {
  const lockIds = Array.from(new Set((wageLockIds || []).filter(Boolean)));
  if (!lockIds.length) {
    return new Map();
  }

  const { data, error } = await supabase
    .from("school_teacher_wage_lock_details")
    .select(WAGE_DETAIL_FEE_COLUMNS)
    .in("lock_id", lockIds);

  if (error) {
    throw error;
  }

  const summaryByLockId = new Map();
  for (const row of data || []) {
    const current = summaryByLockId.get(row.lock_id) || {
      transportFeeJpy: 0,
      classroomFeeJpy: 0,
    };

    current.transportFeeJpy += Number(row.transport_fee_jpy || 0);
    current.classroomFeeJpy += Number(row.classroom_fee_jpy || 0);
    summaryByLockId.set(row.lock_id, current);
  }

  return summaryByLockId;
}

export async function fetchWagePaymentRequests(month) {
  const { data, error } = await supabase
    .from("school_payment_requests")
    .select(PAYMENT_REQUEST_COLUMNS)
    .eq("source_type", "teacher_wage")
    .eq("request_month", month)
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchWageExpenseRecords(month) {
  const { data, error } = await supabase
    .from("school_expense_records")
    .select(EXPENSE_RECORD_COLUMNS)
    .eq("app_type", "school")
    .eq("source_type", "teacher_wage")
    .eq("year_month", month)
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchWageTeachers() {
  const { data, error } = await supabase
    .from("school_teachers")
    .select("id,name,display_name,status,default_business_entity_id")
    .eq("app_type", "school")
    .order("display_name", { ascending: true })
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchWageStudents(studentIds) {
  const ids = Array.from(new Set((studentIds || []).filter(Boolean)));
  if (!ids.length) {
    return [];
  }

  const { data, error } = await supabase
    .from("school_students")
    .select("id,student_code,name,display_name")
    .eq("app_type", "school")
    .in("id", ids)
    .order("display_name", { ascending: true })
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchWageStudentMonthCandidates({
  month,
  includeInactive = false,
  selectedStudentId = null,
}) {
  return fetchStudentMonthCandidates({ month, includeInactive, selectedStudentId });
}

export async function fetchWageLockStudentMemberships(wageLockIds) {
  const lockIds = Array.from(new Set((wageLockIds || []).filter(Boolean)));
  const studentIdsByLockId = new Map();
  if (!lockIds.length) {
    return studentIdsByLockId;
  }

  const { data, error } = await supabase
    .from("school_teacher_wage_lock_details")
    .select("lock_id,student_id")
    .in("lock_id", lockIds);

  if (error) {
    throw error;
  }

  for (const row of data || []) {
    if (!row.lock_id || !row.student_id) {
      continue;
    }
    if (!studentIdsByLockId.has(row.lock_id)) {
      studentIdsByLockId.set(row.lock_id, new Set());
    }
    studentIdsByLockId.get(row.lock_id).add(row.student_id);
  }

  return studentIdsByLockId;
}

export async function fetchWageSubjects() {
  const { data, error } = await supabase
    .from("school_subjects")
    .select("id,name,category,primary_category,is_active")
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchWageBusinessEntities() {
  const { data, error } = await supabase
    .from("school_business_entities")
    .select("id,name,is_active")
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function generateTeacherMonthlyWage({ yearMonth, teacherId = null, businessEntityId = null }) {
  const { data, error } = await supabase.rpc("school_generate_teacher_monthly_wage", {
    p_year_month: yearMonth,
    p_teacher_id: teacherId || null,
    p_business_entity_id: businessEntityId || null,
  });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function createTeacherWageExpenseRecord({
  wageLockId,
  note = null,
}) {
  const { data, error } = await supabase.rpc("school_create_teacher_wage_expense_record", {
    p_wage_lock_id: wageLockId,
    p_note: note || null,
  });

  if (error) {
    throw error;
  }

  return data?.[0] || null;
}

function sortCandidateLessons(left, right) {
  const dateCompare = String(left.lesson_date || "").localeCompare(String(right.lesson_date || ""));
  if (dateCompare !== 0) return dateCompare;

  const timeCompare = String(left.start_time || "").localeCompare(String(right.start_time || ""));
  if (timeCompare !== 0) return timeCompare;

  return String(left.id || "").localeCompare(String(right.id || ""));
}

function teacherBusinessKey(teacherId, businessEntityId) {
  return `${teacherId || ""}::${businessEntityId || ""}`;
}

async function attachAuthoritativeStudentMonth(row) {
  const { data, error } = await supabase.rpc(
    "school_resolve_lesson_student_month_authoritative",
    { p_lesson_id: row.id }
  );
  if (error) {
    throw error;
  }
  return {
    ...row,
    authoritative_student_month: String(data || ""),
  };
}
