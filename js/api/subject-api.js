import { supabase } from "../supabase-client.js";

const SUBJECT_COLUMNS = [
  "id",
  "name",
  "category",
  "color",
  "sort_order",
  "is_active",
  "note",
  "created_at",
  "updated_at",
  "primary_category",
  "tertiary_category",
].join(",");

export async function fetchSubjects() {
  const { data, error } = await supabase
    .from("school_subjects")
    .select(SUBJECT_COLUMNS)
    .order("sort_order", { ascending: true })
    .order("created_at", { ascending: true })
    .order("name", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}
