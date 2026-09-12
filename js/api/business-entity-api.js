import { supabase } from "../supabase-client.js?v=v10-5-65-20260913-1";

const BUSINESS_ENTITY_COLUMNS = [
  "id",
  "code",
  "name",
  "entity_type",
  "default_currency",
  "is_company_report",
  "is_active",
  "note",
  "created_at",
  "updated_at",
].join(",");

export async function fetchBusinessEntities() {
  const { data, error } = await supabase
    .from("school_business_entities")
    .select(BUSINESS_ENTITY_COLUMNS)
    .order("name", { ascending: true })
    .order("code", { ascending: true });

  if (error) {
    throw error;
  }

  return data || [];
}
