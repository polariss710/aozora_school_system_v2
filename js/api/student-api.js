import { supabase } from "../supabase-client.js?v=p1-b2b-auth-storage-20260810-1";

const STUDENT_COLUMNS = [
  "id",
  "student_code",
  "name",
  "display_name",
  "wechat",
  "phone",
  "business_entity_id",
  "target_schools",
  "entrance_date",
  "status",
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
    .select("status,course_track")
    .eq("app_type", "school");

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchBusinessEntitiesForStudents() {
  const { data, error } = await supabase
    .from("school_business_entities")
    .select("id,code,name,is_active")
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function updateStudentProfile(payload) {
  const { data, error } = await supabase.rpc("school_update_student_profile_v2", {
    p_student_id: payload.studentId,
    p_name: payload.name,
    p_default_business_entity_id: payload.defaultBusinessEntityId || null,
    p_course_track: payload.courseTrack || null,
    p_preset_exchange_rate: payload.presetExchangeRate,
    p_wechat: payload.wechat || null,
    p_phone: payload.phone || null,
    p_entrance_date: payload.entranceDate || null,
    p_target_schools: payload.targetSchools || null,
    p_note: payload.note || null,
    p_expected_updated_at: payload.expectedUpdatedAt || null,
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

export async function createStudentProfile(payload) {
  const { data, error } = await supabase.rpc("school_create_student_profile_v2", {
    p_name: payload.name || null,
    p_default_business_entity_id: payload.defaultBusinessEntityId || null,
    p_course_track: payload.courseTrack || null,
    p_preset_exchange_rate: payload.presetExchangeRate,
    p_wechat: payload.wechat || null,
    p_phone: payload.phone || null,
    p_entrance_date: payload.entranceDate || null,
    p_target_schools: payload.targetSchools || null,
    p_note: payload.note || null,
  });

  if (error) {
    throw error;
  }

  const result = Array.isArray(data) ? data[0] : data;
  if (!result) {
    throw new Error("学生新增失败：RPC 没有返回结果。");
  }

  return result;
}

function applyStudentFilters(query, filters) {
  if (filters.courseTrack) {
    query = query.eq("course_track", filters.courseTrack);
  }

  return query;
}
