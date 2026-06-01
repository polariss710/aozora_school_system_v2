import { supabase } from "../supabase-client.js";

const WAGE_RULE_COLUMNS = [
  "id",
  "teacher_id",
  "student_id",
  "subject_id",
  "business_entity_id",
  "settlement_type",
  "hourly_rate_jpy",
  "hourly_rate_cny",
  "exchange_rate",
  "transport_fee_jpy",
  "classroom_fee_jpy",
  "is_active",
  "note",
  "created_at",
  "updated_at",
].join(",");

export async function fetchWageRules() {
  const { data, error } = await supabase
    .from("school_teacher_wage_rules")
    .select(WAGE_RULE_COLUMNS)
    .order("created_at", { ascending: false });

  if (error) {
    throw error;
  }

  return data || [];
}

export async function fetchWageRuleLookups() {
  const [teachersResult, studentsResult, subjectsResult, businessEntitiesResult] = await Promise.all([
    supabase
      .from("school_teachers")
      .select("id,name,display_name,department,status")
      .eq("app_type", "school")
      .order("display_name", { ascending: true })
      .order("name", { ascending: true }),
    supabase
      .from("school_students")
      .select("id,name,display_name,student_code,status")
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
      .select("id,name,is_active")
      .order("name", { ascending: true }),
  ]);

  if (teachersResult.error) {
    throw teachersResult.error;
  }

  if (studentsResult.error) {
    throw studentsResult.error;
  }

  if (subjectsResult.error) {
    throw subjectsResult.error;
  }

  if (businessEntitiesResult.error) {
    throw businessEntitiesResult.error;
  }

  return {
    teachers: teachersResult.data || [],
    students: studentsResult.data || [],
    subjects: subjectsResult.data || [],
    businessEntities: businessEntitiesResult.data || [],
  };
}
