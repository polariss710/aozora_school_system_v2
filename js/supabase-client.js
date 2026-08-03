import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SUPABASE_CONFIG } from "./config.js?v=v2.111.0-supabase-auth-client-init-20260614";

const normalizedConfig = normalizeSupabaseConfig(SUPABASE_CONFIG);

const isConfigured = Boolean(
  normalizedConfig.url &&
    normalizedConfig.anonKey &&
    normalizedConfig.url !== "YOUR_SUPABASE_URL" &&
    normalizedConfig.anonKey !== "YOUR_SUPABASE_ANON_KEY"
);

const clientUrl = isConfigured ? normalizedConfig.url : "https://placeholder.supabase.co";
const clientKey = isConfigured ? normalizedConfig.anonKey : "placeholder-anon-key";

export function hasSupabaseConfig() {
  return isConfigured;
}

export const supabase = createClient(clientUrl, clientKey, {
  auth: {
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
  global: {
    headers: {
      apikey: clientKey,
    },
  },
});

function normalizeSupabaseConfig(config) {
  return {
    url: String(config?.url || config?.supabaseUrl || "").trim(),
    anonKey: String(
      config?.anonKey ||
        config?.anon_key ||
        config?.publishableKey ||
        config?.publishable_key ||
        ""
    ).trim(),
  };
}
