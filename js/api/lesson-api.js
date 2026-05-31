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
  "import_source",
  "lesson_count",
  "actual_minutes",
  "teacher_settlement_month",
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
