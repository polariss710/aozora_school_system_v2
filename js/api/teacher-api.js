import { supabase } from "../supabase-client.js";

const TEACHER_COLUMNS = [
  "id",
  "teacher_code",
  "name",
  "kana_name",
  "display_name",
  "department",
  "default_hourly_rate",
  "default_currency",
  "default_payment_currency",
  "default_business_entity_id",
  "default_payment_method",
  "status",
  "note",
  "app_type",
  "created_at",
  "updated_at",
].join(",");

export async function fetchTeachers(filters) {
  let query = supabase
    .from("school_teachers")
    .select(TEACHER_COLUMNS)
    .eq("app_type", "school")
    .order("display_name", { ascending: true })
    .order("name", { ascending: true });

  query = applyTeacherFilters(query, filters);

  const { data, error } = await query;
  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchTeacherFilterOptions() {
  const { data, error } = await supabase
    .from("school_teachers")
    .select("status,department,default_business_entity_id")
    .eq("app_type", "school");

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchBusinessEntitiesForTeachers() {
  const { data, error } = await supabase
    .from("school_business_entities")
    .select("id,name,is_active")
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}

function applyTeacherFilters(query, filters) {
  if (filters.status) {
    query = query.eq("status", filters.status);
  }

  if (filters.department) {
    query = query.eq("department", filters.department);
  }

  if (filters.businessEntityId === "__unset__") {
    query = query.is("default_business_entity_id", null);
  } else if (filters.businessEntityId) {
    query = query.eq("default_business_entity_id", filters.businessEntityId);
  }

  return query;
}
