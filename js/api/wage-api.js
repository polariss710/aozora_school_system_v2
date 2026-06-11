import { supabase } from "../supabase-client.js";

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

const STUDENT_SETTLEMENT_COLUMNS = [
  "id",
  "student_id",
  "year_month",
  "business_entity_id",
  "settlement_status",
  "locked_at",
  "unlocked_at",
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
  const [teacherMonthResult, fallbackMonthResult] = await Promise.all([
    supabase
      .from("school_lesson_records")
      .select(WAGE_CANDIDATE_LESSON_COLUMNS)
      .eq("app_type", "school")
      .eq("lesson_type", "actual")
      .in("status", ["completed", "makeup_completed"])
      .eq("teacher_settlement_month", month)
      .order("lesson_date", { ascending: true })
      .order("start_time", { ascending: true }),
    supabase
      .from("school_lesson_records")
      .select(WAGE_CANDIDATE_LESSON_COLUMNS)
      .eq("app_type", "school")
      .eq("lesson_type", "actual")
      .in("status", ["completed", "makeup_completed"])
      .is("teacher_settlement_month", null)
      .eq("year_month", month)
      .order("lesson_date", { ascending: true })
      .order("start_time", { ascending: true }),
  ]);

  if (teacherMonthResult.error) {
    throw teacherMonthResult.error;
  }
  if (fallbackMonthResult.error) {
    throw fallbackMonthResult.error;
  }

  const rowsById = new Map();
  for (const row of [...(teacherMonthResult.data || []), ...(fallbackMonthResult.data || [])]) {
    rowsById.set(row.id, row);
  }

  const rows = Array.from(rowsById.values()).sort(sortCandidateLessons);
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
  const studentSettlementInfoByCandidateKey = await fetchStudentSettlementInfoByCandidateKey(rows);

  return rows.map((row) => ({
    ...row,
    wageDetailBlocked: detailLocksByLessonId.has(row.id),
    wageDetailLockIds: detailLocksByLessonId.get(row.id) || [],
    wageMonthBlocked: lockedTeacherBusinessKeys.has(teacherBusinessKey(row.teacher_id, row.business_entity_id)),
    ...(studentSettlementInfoByCandidateKey.get(studentSettlementCandidateKey(row)) || {}),
  }));
}

async function fetchStudentSettlementInfoByCandidateKey(rows) {
  const studentIds = Array.from(new Set(rows.map((row) => row.student_id).filter(Boolean)));
  const yearMonths = Array.from(new Set(rows.map((row) => row.year_month).filter(Boolean)));
  const resultByCandidateKey = new Map();

  if (!studentIds.length || !yearMonths.length) {
    return resultByCandidateKey;
  }

  const { data, error } = await supabase
    .from("school_student_monthly_settlements")
    .select(STUDENT_SETTLEMENT_COLUMNS)
    .in("student_id", studentIds)
    .in("year_month", yearMonths);

  if (error) {
    throw error;
  }

  const exactByKey = new Map();
  const monthByKey = new Map();
  for (const row of data || []) {
    exactByKey.set(studentSettlementCandidateKey(row), row);
    const monthKey = studentSettlementMonthKey(row.student_id, row.year_month);
    if (!monthByKey.has(monthKey)) {
      monthByKey.set(monthKey, []);
    }
    monthByKey.get(monthKey).push(row);
  }

  for (const row of rows) {
    const exact = exactByKey.get(studentSettlementCandidateKey(row)) || null;
    const monthSettlements = monthByKey.get(studentSettlementMonthKey(row.student_id, row.year_month)) || [];
    const fallback = exact || monthSettlements[0] || null;
    resultByCandidateKey.set(studentSettlementCandidateKey(row), {
      studentSettlementId: exact?.id || "",
      studentSettlementStatus: exact?.settlement_status || "",
      studentSettlementLockedAt: exact?.locked_at || "",
      studentSettlementUnlockedAt: exact?.unlocked_at || "",
      studentSettlementBusinessEntityId: fallback?.business_entity_id || "",
      studentSettlementMatchedBusiness: Boolean(exact),
      studentSettlementOtherBusinessCount: exact ? 0 : monthSettlements.length,
    });
  }

  return resultByCandidateKey;
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

export async function fetchWageStudents() {
  const { data, error } = await supabase
    .from("school_students")
    .select("id,student_code,name,display_name,status")
    .eq("app_type", "school")
    .order("display_name", { ascending: true })
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
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

export async function generateTeacherMonthlyWage({ yearMonth, teacherId = null }) {
  const { data, error } = await supabase.rpc("school_generate_teacher_monthly_wage", {
    p_year_month: yearMonth,
    p_teacher_id: teacherId || null,
  });

  if (error) {
    throw error;
  }

  return data || [];
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

function studentSettlementCandidateKey(row) {
  return `${row.student_id || ""}::${row.year_month || ""}::${row.business_entity_id || ""}`;
}

function studentSettlementMonthKey(studentId, yearMonth) {
  return `${studentId || ""}::${yearMonth || ""}`;
}
