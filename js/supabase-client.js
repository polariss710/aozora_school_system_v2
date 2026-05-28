import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SUPABASE_CONFIG } from "./config.js";

const isConfigured = Boolean(
  SUPABASE_CONFIG.url &&
    SUPABASE_CONFIG.anonKey &&
    SUPABASE_CONFIG.url !== "YOUR_SUPABASE_URL" &&
    SUPABASE_CONFIG.anonKey !== "YOUR_SUPABASE_ANON_KEY"
);

export function hasSupabaseConfig() {
  return isConfigured;
}

export const supabase = createClient(
  isConfigured ? SUPABASE_CONFIG.url : "https://placeholder.supabase.co",
  isConfigured ? SUPABASE_CONFIG.anonKey : "placeholder-anon-key"
);
