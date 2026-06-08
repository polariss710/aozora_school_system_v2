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
  "import_batch_id",
  "import_source",
  "imported_at",
  "lesson_count",
  "actual_minutes",
  "teacher_settlement_month",
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

export async function fetchLessonRecords(yearMonth) {
  const { data, error } = await supabase
    .from("school_lesson_records")
    .select(LESSON_COLUMNS)
    .eq("app_type", "school")
    .eq("year_month", yearMonth)
    .order("lesson_date", { ascending: true })
    .order("start_time", { ascending: true });

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

function nullSafeEqual(left, right) {
  return (left || null) === (right || null);
}

export async function fetchLessonStudents() {
  const { data, error } = await supabase
    .from("school_students")
    .select("id,name,display_name,status")
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
    .select("id,name,is_active")
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function createPlannedLessonRecord(payload) {
  const { data, error } = await supabase.rpc("school_create_planned_lesson_record", {
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
  const { data, error } = await supabase.rpc("school_import_lesson_records_batch", {
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

export async function updateLessonRecordGuarded(payload) {
  const { data, error } = await supabase.rpc("school_update_lesson_record_guarded", {
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
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("课时编辑失败：RPC 没有返回结果。");
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
    throw error;
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
  const { data, error } = await supabase.rpc("school_create_makeup_completed_actual_lesson_from_planned", {
    p_planned_lesson_id: payload.plannedLessonId,
    p_lesson_date: payload.lessonDate,
    p_start_time: payload.startTime || null,
    p_end_time: payload.endTime || null,
    p_duration_hours: payload.durationHours,
    p_unit_price: payload.unitPrice,
    p_lesson_fee: payload.lessonFee,
    p_is_billable: payload.isBillable,
    p_lesson_count: payload.lessonCount,
    p_lesson_content: payload.lessonContent || null,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("补课完成课时生成失败：RPC 没有返回结果。");
  }

  return result;
}
