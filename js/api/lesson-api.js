import { supabase } from "../supabase-client.js";

const LESSON_COLUMNS = [
  "id",
  "lesson_type",
  "lesson_date",
  "year_month",
  "student_id",
  "teacher_id",
  "subject_id",
  "business_entity_id",
  "start_time",
  "end_time",
  "duration_hours",
  "lesson_content",
  "status",
  "is_billable",
  "note",
  "app_type",
  "planned_lesson_id",
  "unit_price",
  "lesson_fee",
  "base_lesson_fee_jpy",
  "aircon_charge_status",
  "aircon_unit_price_jpy_snapshot",
  "aircon_billable_hours_snapshot",
  "aircon_fee_jpy",
  "aircon_calculated_at",
  "fee_calculation_version",
  "fee_block_reason_code",
  "fee_components_frozen_at",
  "lesson_total_fee_jpy",
  "import_batch_id",
  "import_source",
  "imported_at",
  "lesson_count",
  "actual_minutes",
  "billing_month",
  "billing_week_start_date",
  "student_settlement_month",
  "teacher_settlement_month",
  "student_duration_overage_minutes",
  "student_duration_overage_fee_jpy",
  "student_duration_overage_policy_version",
  "student_duration_overage_source",
  "student_duration_overage_decided_at",
  "lesson_delivery_mode",
  "lesson_venue",
  "voided_at",
  "void_reason",
  "created_at",
  "updated_at",
].join(",");

const IMPORT_PRECHECK_SETTLEMENT_COLUMNS = [
  "id",
  "student_id",
  "year_month",
  "business_entity_id",
  "settlement_status",
  "locked_at",
].join(",");

const IMPORT_PRECHECK_WAGE_LOCK_COLUMNS = [
  "id",
  "teacher_id",
  "business_entity_id",
  "settlement_month",
  "status",
  "locked_at",
].join(",");

export async function fetchLessonRecords(yearMonth, options = {}) {
  let query = supabase
    .from("school_lesson_records")
    .select(LESSON_COLUMNS)
    .eq("app_type", "school")
    .eq("year_month", yearMonth);

  if (options.weekStart) {
    const weekEnd = addDaysToDateValue(options.weekStart, 7);
    if (!weekEnd) {
      throw new Error("周筛选日期无效。");
    }
    query = query
      .gte("lesson_date", options.weekStart)
      .lt("lesson_date", weekEnd);
  }

  if (options.status === "voided") {
    query = query
      .eq("lesson_type", "planned")
      .not("voided_at", "is", null);
  } else {
    query = query.or("lesson_type.neq.planned,voided_at.is.null");
  }

  const { data, error } = await query
    .order("lesson_date", { ascending: true })
    .order("lesson_count", { ascending: true, nullsFirst: false })
    .order("start_time", { ascending: true, nullsFirst: false })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchLessonManagementStats(filters = {}) {
  const { data, error } = await supabase.rpc("school_get_lesson_management_stats_filtered", {
    p_year_month: filters.month || null,
    p_student_id: filters.studentId || null,
    p_teacher_id: filters.teacherId || null,
    p_subject_id: filters.subjectId || null,
    p_lesson_type: filters.lessonType || null,
    p_status: filters.status || null,
    p_business_entity_id: filters.businessEntityId || null,
    p_is_billable: parseBillableFilter(filters.isBillable),
    p_keyword: filters.keyword || null,
    p_week_start: filters.weekStart || null,
  });

  if (error) {
    throw error;
  }

  return Array.isArray(data) ? data[0] : data;
}

export async function fetchStudentLessonPdfExport({ studentId, yearMonth, mode } = {}) {
  const normalizedMonth = normalizeYearMonth(yearMonth);
  const normalizedMode = mode === "planned" ? "planned" : "actual";
  if (!studentId || !normalizedMonth) {
    return {
      rows: [],
      plannedRows: [],
      actualRows: [],
      stats: null,
    };
  }

  const [plannedRows, actualRows, stats] = await Promise.all([
    fetchStudentLessonPdfRows({ studentId, yearMonth: normalizedMonth, lessonType: "planned" }),
    normalizedMode === "actual"
      ? fetchStudentLessonPdfRows({ studentId, yearMonth: normalizedMonth, lessonType: "actual" })
      : Promise.resolve([]),
    fetchLessonManagementStats({
      month: normalizedMonth,
      studentId,
    }),
  ]);

  return {
    rows: normalizedMode === "planned" ? plannedRows : actualRows,
    plannedRows,
    actualRows,
    stats,
  };
}

async function fetchStudentLessonPdfRows({ studentId, yearMonth, lessonType }) {
  let query = supabase
    .from("school_lesson_records")
    .select(LESSON_COLUMNS)
    .eq("app_type", "school")
    .eq("student_id", studentId)
    .eq("year_month", yearMonth)
    .eq("lesson_type", lessonType);

  if (lessonType === "planned") {
    query = query.is("voided_at", null);
  }

  const { data, error } = await query
    .order("lesson_date", { ascending: true })
    .order("lesson_count", { ascending: true, nullsFirst: false })
    .order("start_time", { ascending: true, nullsFirst: false })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchLessonImportPlannedReferences(plannedIds) {
  const ids = normalizeIdList(plannedIds);
  if (!ids.length) {
    return {
      plannedLessons: [],
      linkedActuals: [],
    };
  }

  const [plannedLessons, linkedActuals] = await Promise.all([
    fetchLessonsByIds(ids),
    fetchActualLessonsByPlannedIds(ids),
  ]);

  return {
    plannedLessons,
    linkedActuals,
  };
}

export async function fetchLessonImportLockPrecheck(targets) {
  const studentSettlementTargets = Array.isArray(targets?.studentSettlementTargets)
    ? targets.studentSettlementTargets
    : [];
  const teacherWageTargets = Array.isArray(targets?.teacherWageTargets)
    ? targets.teacherWageTargets
    : [];

  const [lockedStudentSettlements, lockedTeacherWageLocks] = await Promise.all([
    fetchLockedStudentSettlements(studentSettlementTargets),
    fetchLockedTeacherWageLocks(teacherWageTargets),
  ]);

  return {
    lockedStudentSettlements,
    lockedTeacherWageLocks,
  };
}

export async function fetchOpenMakeupSourceLessons({ fromMonth, toMonth, targetMonth } = {}) {
  const normalizedFrom = normalizeYearMonth(fromMonth);
  const normalizedTo = normalizeYearMonth(toMonth);
  const normalizedTarget = normalizeYearMonth(targetMonth);
  if (!normalizedFrom || !normalizedTo || !normalizedTarget || normalizedFrom > normalizedTo) {
    return [];
  }

  const { data, error } = await supabase.rpc("school_list_open_lesson_credit_sources", {
    p_from_month: normalizedFrom,
    p_to_month: normalizedTo,
    p_target_month: normalizedTarget,
  });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchStudentLessonCreditBalances(studentId = null) {
  const { data, error } = await supabase.rpc("school_list_student_lesson_credit_balances", {
    p_student_id: studentId || null,
  });
  if (error) throw error;
  return data || [];
}

export async function fetchLessonCreditSummary({ studentId = null, businessEntityId = null } = {}) {
  const { data, error } = await supabase.rpc("school_get_lesson_credit_summary", {
    p_student_id: studentId || null,
    p_business_entity_id: businessEntityId || null,
  });
  if (error) throw error;
  return Array.isArray(data) ? data[0] : data;
}

export async function fetchWeeklyLessonOperations(weekStart) {
  if (!weekStart) throw new Error("请选择周一日期。");
  const { data, error } = await supabase.rpc("school_get_weekly_lesson_operations", {
    p_week_start: weekStart,
  });
  if (error) throw error;
  return data || [];
}

export async function fetchCrossMonthMakeupReferences(yearMonth, records = []) {
  const normalizedMonth = normalizeYearMonth(yearMonth);
  if (!normalizedMonth || !Array.isArray(records) || !records.length) {
    return {
      sourceMonthActuals: [],
      targetMonthSources: [],
    };
  }

  const plannedIds = normalizeIdList(
    records
      .filter((row) => row.lesson_type === "planned")
      .map((row) => row.id)
  );
  const targetActualSourceIds = normalizeIdList(
    records
      .filter((row) => row.lesson_type === "actual" && row.status === "makeup_completed")
      .map((row) => row.planned_lesson_id)
  );

  const [sourceMonthActuals, targetMonthSources] = await Promise.all([
    plannedIds.length ? fetchActualLessonsByPlannedIds(plannedIds) : Promise.resolve([]),
    targetActualSourceIds.length ? fetchLessonsByIds(targetActualSourceIds) : Promise.resolve([]),
  ]);

  return {
    sourceMonthActuals: sourceMonthActuals.filter((row) => (
      row.status === "makeup_completed"
      && row.year_month !== normalizedMonth
    )),
    targetMonthSources: targetMonthSources.filter((row) => (
      row.lesson_type === "planned"
      && row.status === "pending_makeup"
      && row.year_month !== normalizedMonth
    )),
  };
}

async function fetchLessonsByIds(ids) {
  const { data, error } = await supabase
    .from("school_lesson_records")
    .select(LESSON_COLUMNS)
    .eq("app_type", "school")
    .in("id", ids);

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchActualLessonsByPlannedIds(plannedIds) {
  const { data, error } = await supabase
    .from("school_lesson_records")
    .select(LESSON_COLUMNS)
    .eq("app_type", "school")
    .eq("lesson_type", "actual")
    .in("planned_lesson_id", plannedIds);

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchLockedStudentSettlements(targets) {
  const studentIds = normalizeIdList(targets.map((target) => target.studentId));
  const yearMonths = uniqueTextList(targets.map((target) => target.yearMonth));
  if (!studentIds.length || !yearMonths.length) {
    return [];
  }

  const { data, error } = await supabase
    .from("school_student_monthly_settlements")
    .select(IMPORT_PRECHECK_SETTLEMENT_COLUMNS)
    .in("student_id", studentIds)
    .in("year_month", yearMonths)
    .eq("settlement_status", "locked");

  if (error) {
    throw error;
  }

  return (data || []).filter((row) => (
    targets.some((target) => (
      row.student_id === target.studentId
      && row.year_month === target.yearMonth
      && nullSafeEqual(row.business_entity_id, target.businessEntityId)
    ))
  ));
}

async function fetchLockedTeacherWageLocks(targets) {
  const teacherIds = normalizeIdList(targets.map((target) => target.teacherId));
  const settlementMonths = uniqueTextList(targets.map((target) => target.settlementMonth));
  if (!teacherIds.length || !settlementMonths.length) {
    return [];
  }

  const { data, error } = await supabase
    .from("school_teacher_wage_locks")
    .select(IMPORT_PRECHECK_WAGE_LOCK_COLUMNS)
    .in("teacher_id", teacherIds)
    .in("settlement_month", settlementMonths)
    .eq("status", "locked");

  if (error) {
    throw error;
  }

  return (data || []).filter((row) => (
    targets.some((target) => (
      row.teacher_id === target.teacherId
      && row.settlement_month === target.settlementMonth
      && nullSafeEqual(row.business_entity_id, target.businessEntityId)
    ))
  ));
}

function normalizeIdList(values) {
  return Array.from(new Set(
    (values || [])
      .map((value) => String(value || "").trim())
      .filter(Boolean)
  ));
}

function uniqueTextList(values) {
  return normalizeIdList(values);
}

function normalizeYearMonth(value) {
  const text = String(value || "").trim();
  return /^\d{4}-(0[1-9]|1[0-2])$/.test(text) ? text : "";
}

function addDaysToDateValue(value, days) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(value || ""))) return "";
  const date = new Date(`${value}T00:00:00`);
  if (Number.isNaN(date.getTime())) return "";
  date.setDate(date.getDate() + days);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function parseBillableFilter(value) {
  if (value === true || value === "true") {
    return true;
  }
  if (value === false || value === "false") {
    return false;
  }
  return null;
}

function nullSafeEqual(left, right) {
  return (left || null) === (right || null);
}

export async function fetchLessonStudents() {
  const { data, error } = await supabase
    .from("school_students")
    .select("id,name,display_name,status,business_entity_id")
    .eq("app_type", "school")
    .order("display_name", { ascending: true })
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchLessonTeachers() {
  const { data, error } = await supabase
    .from("school_teachers")
    .select("id,name,display_name,status")
    .eq("app_type", "school")
    .order("display_name", { ascending: true })
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchLessonSubjects() {
  const { data, error } = await supabase
    .from("school_subjects")
    .select("id,name,category,is_active")
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchLessonBusinessEntities() {
  const { data, error } = await supabase
    .from("school_business_entities")
    .select("id,code,name,is_active")
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function createPlannedLessonRecord(payload) {
  const { data, error } = await supabase.rpc("school_create_planned_lesson_record_with_venue", {
    p_lesson_date: payload.lessonDate,
    p_student_id: payload.studentId,
    p_teacher_id: payload.teacherId,
    p_subject_id: payload.subjectId,
    p_business_entity_id: payload.businessEntityId,
    p_start_time: payload.startTime || null,
    p_end_time: payload.endTime || null,
    p_duration_hours: payload.durationHours,
    p_unit_price: payload.unitPrice,
    p_lesson_fee: payload.lessonFee,
    p_status: payload.status,
    p_lesson_count: payload.lessonCount,
    p_lesson_content: payload.lessonContent || null,
    p_note: payload.note || null,
    p_lesson_delivery_mode: payload.lessonDeliveryMode || null,
    p_lesson_venue: payload.lessonVenue || null,
    p_aircon_rate_jpy_per_hour: payload.airconRateJpyPerHour,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("预定课时新增失败：RPC 没有返回结果。");
  }

  return result;
}

export async function importPlannedLessonRecordsBatch(payload) {
  const { data, error } = await supabase.rpc("school_import_lesson_records_batch_with_venue", {
    p_import_batch_id: payload.importBatchId,
    p_source_file_name: payload.sourceFileName,
    p_source_file_hash: payload.sourceFileHash,
    p_rows: payload.rows,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  return Array.isArray(data) ? data : [];
}

export async function generatePlannedLessonRecordsBatch(payload) {
  const { data, error } = await supabase.rpc("school_generate_planned_lessons_batch_with_venue", {
    p_generation_id: payload.generationId,
    p_student_id: payload.studentId,
    p_business_entity_id: payload.businessEntityId,
    p_start_date: payload.startDate,
    p_end_date: payload.endDate,
    p_patterns: payload.patterns,
    p_excluded_occurrences: payload.excludedOccurrences || [],
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  return Array.isArray(data) ? data : [];
}

export async function updateLessonRecordGuarded(payload) {
  const args = {
    p_lesson_id: payload.lessonId,
    p_expected_updated_at: payload.expectedUpdatedAt,
    p_lesson_date: payload.lessonDate,
    p_student_id: payload.studentId,
    p_teacher_id: payload.teacherId,
    p_subject_id: payload.subjectId,
    p_business_entity_id: payload.businessEntityId,
    p_start_time: payload.startTime || null,
    p_end_time: payload.endTime || null,
    p_duration_hours: payload.durationHours,
    p_unit_price: payload.unitPrice,
    p_lesson_fee: payload.lessonFee,
    p_status: payload.status,
    p_is_billable: payload.isBillable,
    p_lesson_count: payload.lessonCount,
    p_lesson_content: payload.lessonContent || null,
    p_note: payload.note || null,
    p_lesson_delivery_mode: payload.lessonDeliveryMode || null,
    p_lesson_venue: payload.lessonVenue || null,
  };
  if (payload.lessonType === "planned" && Number.isInteger(payload.airconRateJpyPerHour)) {
    args.p_aircon_rate_jpy_per_hour = payload.airconRateJpyPerHour;
  }
  const { data, error } = await supabase.rpc(
    "school_update_lesson_record_guarded_with_venue",
    args
  );

  if (error) {
    throw normalizeLessonMutationError(error);
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("课时编辑失败：RPC 没有返回结果。");
  }

  return result;
}

export async function voidPlannedLesson(payload) {
  const { data, error } = await supabase.rpc("school_void_planned_lesson", {
    p_lesson_id: payload.lessonId,
    p_expected_updated_at: payload.expectedUpdatedAt,
    p_void_reason: payload.voidReason,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("预定课时作废失败：RPC 没有返回结果。");
  }

  return result;
}

export async function deleteFreshPlannedLesson(payload) {
  const { data, error } = await supabase.rpc("school_delete_fresh_planned_lesson", {
    p_lesson_id: payload.lessonId,
    p_expected_updated_at: payload.expectedUpdatedAt,
    p_confirm_delete: payload.confirmDelete === true,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("预定课时删除失败：RPC 没有返回结果。");
  }

  return result;
}

export async function createActualLessonFromPlanned(payload) {
  const { data, error } = await supabase.rpc("school_create_actual_lesson_from_planned", {
    p_planned_lesson_id: payload.plannedLessonId,
    p_lesson_date: payload.lessonDate,
    p_start_time: payload.startTime || null,
    p_end_time: payload.endTime || null,
    p_duration_hours: payload.durationHours,
    p_unit_price: payload.unitPrice,
    p_lesson_fee: payload.lessonFee,
    p_lesson_count: payload.lessonCount,
    p_lesson_content: payload.lessonContent || null,
    p_note: payload.note || null,
  });

  if (error) {
    throw normalizeLessonMutationError(error);
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("实际课时生成失败：RPC 没有返回结果。");
  }

  return result;
}

export async function createCancelledActualLessonFromPlanned(payload) {
  const { data, error } = await supabase.rpc("school_create_cancelled_actual_lesson_from_planned", {
    p_planned_lesson_id: payload.plannedLessonId,
    p_lesson_date: payload.lessonDate,
    p_start_time: payload.startTime || null,
    p_end_time: payload.endTime || null,
    p_duration_hours: payload.durationHours,
    p_unit_price: payload.unitPrice,
    p_lesson_count: payload.lessonCount,
    p_lesson_content: payload.lessonContent || null,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("取消课时生成失败：RPC 没有返回结果。");
  }

  return result;
}

export async function createMakeupCompletedActualLessonFromPlanned(payload) {
  const { data, error } = await supabase.rpc("school_create_lesson_credit_makeup_actual", {
    p_planned_lesson_id: payload.plannedLessonId,
    p_lesson_date: payload.lessonDate,
    p_teacher_id: payload.teacherId || null,
    p_subject_id: payload.subjectId || null,
    p_start_time: payload.startTime || null,
    p_end_time: payload.endTime || null,
    p_duration_hours: payload.durationHours,
    p_lesson_count: payload.lessonCount,
    p_lesson_content: payload.lessonContent || null,
    p_note: payload.note || null,
    p_lesson_delivery_mode: payload.lessonDeliveryMode || null,
    p_lesson_venue: payload.lessonVenue || null,
  });

  if (error) {
    throw normalizeLessonMutationError(error);
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("补课完成课时生成失败：RPC 没有返回结果。");
  }

  return result;
}

export async function createCrossMonthMakeupCompletedActualFromPlanned(payload) {
  return createMakeupCompletedActualLessonFromPlanned(payload);
}

export async function createPartialCompletedActualFromPlanned(payload) {
  const { data, error } = await supabase.rpc("school_create_partial_completed_actual_from_planned", {
    p_planned_lesson_id: payload.plannedLessonId,
    p_lesson_date: payload.lessonDate,
    p_start_time: payload.startTime || null,
    p_end_time: payload.endTime || null,
    p_duration_hours: payload.durationHours,
    p_lesson_content: payload.lessonContent || null,
    p_note: payload.note || null,
  });
  if (error) throw normalizeLessonMutationError(error);
  const result = Array.isArray(data) ? data[0] : data;
  if (!result) throw new Error("部分完成实际课时生成失败：RPC 没有返回结果。");
  return result;
}

function normalizeLessonMutationError(error) {
  const message = String(error?.message || error || "");
  if (message.includes("FUTURE_ACTUAL_COMPLETION_FORBIDDEN")) {
    return new Error("实际完成日期不能晚于东京当前业务日期。（FUTURE_ACTUAL_COMPLETION_FORBIDDEN）");
  }
  return error;
}
