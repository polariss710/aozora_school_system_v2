import { supabase } from "../supabase-client.js";

const STUDENT_COLUMNS = [
  "id",
  "student_code",
  "name",
  "display_name",
  "kana_name",
  "business_entity_id",
  "target_type",
  "target_schools",
  "entrance_date",
  "status",
  "default_currency",
  "course_track",
  "preset_exchange_rate",
  "note",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

export async function fetchStudents(filters) {
  let query = supabase
    .from("school_students")
    .select(STUDENT_COLUMNS)
    .eq("app_type", "school")
    .order("display_name", { ascending: true })
    .order("name", { ascending: true });

  query = applyStudentFilters(query, filters);

  const { data, error } = await query;
  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchStudentFilterOptions() {
  const { data, error } = await supabase
    .from("school_students")
    .select("status,course_track,target_type,business_entity_id,default_currency")
    .eq("app_type", "school");

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchBusinessEntitiesForStudents() {
  const { data, error } = await supabase
    .from("school_business_entities")
    .select("id,name,is_active")
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function updateStudentProfile(payload) {
  const { data, error } = await supabase.rpc("school_update_student_profile", {
    p_student_id: payload.studentId,
    p_display_name: payload.displayName,
    p_status: payload.status,
    p_course_track: payload.courseTrack || null,
    p_target_type: payload.targetType || null,
    p_default_business_entity_id: payload.defaultBusinessEntityId || null,
    p_default_currency: payload.defaultCurrency || null,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("学生基础信息更新失败：RPC 没有返回结果。");
  }

  return result;
}

function applyStudentFilters(query, filters) {
  if (filters.status) {
    query = query.eq("status", filters.status);
  }

  if (filters.courseTrack) {
    query = query.eq("course_track", filters.courseTrack);
  }

  if (filters.targetType === "__unset__") {
    query = query.or("target_type.is.null,target_type.eq.");
  } else if (filters.targetType) {
    query = query.eq("target_type", filters.targetType);
  }

  if (filters.businessEntityId === "__unset__") {
    query = query.is("business_entity_id", null);
  } else if (filters.businessEntityId) {
    query = query.eq("business_entity_id", filters.businessEntityId);
  }

  if (filters.defaultCurrency) {
    query = query.eq("default_currency", filters.defaultCurrency);
  }

  return query;
}
