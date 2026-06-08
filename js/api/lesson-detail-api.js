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
  "created_at",
  "updated_at",
  "planned_lesson_id",
  "unit_price",
  "lesson_fee",
  "import_batch_id",
  "import_source",
  "imported_at",
  "lesson_count",
  "actual_minutes",
  "teacher_settlement_month",
].join(",");

const SETTLEMENT_COLUMNS = [
  "id",
  "student_id",
  "year_month",
  "business_entity_id",
  "planned_lesson_fee_jpy",
  "planned_lesson_fee_cny",
  "actual_lesson_fee_jpy",
  "actual_lesson_fee_cny",
  "received_jpy",
  "received_cny",
  "received_equivalent_cny",
  "carryover_amount_cny",
  "settlement_status",
  "locked_at",
  "created_at",
  "updated_at",
].join(",");

const WAGE_DETAIL_COLUMNS = [
  "id",
  "lock_id",
  "lesson_record_id",
  "lesson_date",
  "start_time",
  "end_time",
  "student_id",
  "student_name",
  "subject_id",
  "subject_name",
  "business_entity_id",
  "business_name",
  "pay_hours",
  "lesson_wage_jpy",
  "lesson_wage_cny",
  "transport_fee_jpy",
  "classroom_fee_jpy",
  "total_jpy",
  "total_cny",
  "settlement_type",
  "exchange_rate",
  "is_no_wage",
  "status",
  "lesson_content",
  "created_at",
].join(",");

const WAGE_LOCK_COLUMNS = [
  "id",
  "settlement_month",
  "teacher_id",
  "teacher_name",
  "business_entity_id",
  "business_name",
  "settlement_type",
  "exchange_rate",
  "total_minutes",
  "pay_hours",
  "lesson_wage_jpy",
  "lesson_wage_cny",
  "fee_jpy",
  "total_jpy",
  "total_cny",
  "lesson_count",
  "status",
  "locked_at",
  "voided_at",
  "created_at",
  "updated_at",
].join(",");

export async function fetchLessonDetailPage(lessonId) {
  const lesson = await fetchLesson(lessonId);

  const [lookups, sourceChain, settlements, wageReferences] = await Promise.all([
    fetchLessonDetailLookups(),
    fetchLessonSourceChain(lesson),
    fetchSettlementReferences(lesson),
    fetchWageReferences(lesson.id),
  ]);

  return {
    lesson,
    lookups,
    sourceChain,
    settlements,
    wageReferences,
  };
}

async function fetchLesson(lessonId) {
  const { data, error } = await supabase
    .from("school_lesson_records")
    .select(LESSON_COLUMNS)
    .eq("id", lessonId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  if (!data) {
    throw new Error("没有找到对应的课时记录。");
  }

  return data;
}

async function fetchLessonSourceChain(lesson) {
  const results = await Promise.all([
    lesson.planned_lesson_id ? fetchLessonById(lesson.planned_lesson_id) : Promise.resolve(null),
    fetchLessonsByPlannedId(lesson.id),
    lesson.planned_lesson_id ? fetchLessonsByPlannedId(lesson.planned_lesson_id) : Promise.resolve([]),
  ]);

  const [plannedLesson, referencesToCurrent, samePlannedReferences] = results;
  const rows = [
    { relation: "当前课时", lesson },
  ];

  if (plannedLesson) {
    rows.push({ relation: "原 planned 课时", lesson: plannedLesson });
  }

  for (const row of referencesToCurrent) {
    rows.push({ relation: "引用当前课时", lesson: row });
  }

  for (const row of samePlannedReferences) {
    rows.push({ relation: row.id === lesson.id ? "当前课时" : "同 planned 链路", lesson: row });
  }

  return dedupeLessonChain(rows);
}

async function fetchLessonById(lessonId) {
  const { data, error } = await supabase
    .from("school_lesson_records")
    .select(LESSON_COLUMNS)
    .eq("id", lessonId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  return data || null;
}

async function fetchLessonsByPlannedId(plannedLessonId) {
  const { data, error } = await supabase
    .from("school_lesson_records")
    .select(LESSON_COLUMNS)
    .eq("planned_lesson_id", plannedLessonId)
    .order("lesson_date", { ascending: true })
    .order("start_time", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

function dedupeLessonChain(rows) {
  const seen = new Set();
  const deduped = [];

  for (const row of rows) {
    if (!row.lesson?.id || seen.has(`${row.relation}:${row.lesson.id}`)) {
      continue;
    }
    seen.add(`${row.relation}:${row.lesson.id}`);
    deduped.push(row);
  }

  return deduped;
}

async function fetchSettlementReferences(lesson) {
  const { data, error } = await supabase
    .from("school_student_monthly_settlements")
    .select(SETTLEMENT_COLUMNS)
    .eq("student_id", lesson.student_id)
    .eq("year_month", lesson.year_month)
    .eq("business_entity_id", lesson.business_entity_id)
    .order("locked_at", { ascending: false })
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchWageReferences(lessonId) {
  const { data, error } = await supabase
    .from("school_teacher_wage_lock_details")
    .select(WAGE_DETAIL_COLUMNS)
    .eq("lesson_record_id", lessonId)
    .order("lesson_date", { ascending: true })
    .order("start_time", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    throw error;
  }

  const details = data || [];
  const lockIds = Array.from(new Set(details.map((row) => row.lock_id).filter(Boolean)));
  const locks = lockIds.length ? await fetchWageLocks(lockIds) : [];
  const locksById = new Map(locks.map((row) => [row.id, row]));

  return details.map((detail) => ({
    detail,
    wageLock: locksById.get(detail.lock_id) || null,
  }));
}

async function fetchWageLocks(lockIds) {
  const { data, error } = await supabase
    .from("school_teacher_wage_locks")
    .select(WAGE_LOCK_COLUMNS)
    .in("id", lockIds)
    .order("settlement_month", { ascending: false })
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data || [];
}

async function fetchLessonDetailLookups() {
  const [studentsResult, teachersResult, subjectsResult, businessEntitiesResult] = await Promise.all([
    supabase
      .from("school_students")
      .select("id,student_code,name,display_name,status")
      .eq("app_type", "school")
      .order("display_name", { ascending: true })
      .order("name", { ascending: true }),
    supabase
      .from("school_teachers")
      .select("id,teacher_code,name,display_name,status")
      .eq("app_type", "school")
      .order("display_name", { ascending: true })
      .order("name", { ascending: true }),
    supabase
      .from("school_subjects")
      .select("id,name,category,primary_category,is_active")
      .order("sort_order", { ascending: true })
      .order("name", { ascending: true }),
    supabase
      .from("school_business_entities")
      .select("id,code,name,entity_type,is_active")
      .order("name", { ascending: true }),
  ]);

  if (studentsResult.error) throw studentsResult.error;
  if (teachersResult.error) throw teachersResult.error;
  if (subjectsResult.error) throw subjectsResult.error;
  if (businessEntitiesResult.error) throw businessEntitiesResult.error;

  return {
    students: studentsResult.data || [],
    teachers: teachersResult.data || [],
    subjects: subjectsResult.data || [],
    businessEntities: businessEntitiesResult.data || [],
  };
}
