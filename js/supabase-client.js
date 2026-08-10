import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SUPABASE_CONFIG } from "./config.js?v=v2.111.0-supabase-auth-client-init-20260614";
import {
  removeLegacyAuthStorage,
  V2_AUTH_STORAGE_KEY,
} from "./auth-storage-isolation.js?v=p1-b2b-auth-storage-20260810-1";

const normalizedConfig = normalizeSupabaseConfig(SUPABASE_CONFIG);

let authStorageReady = false;
try {
  removeLegacyAuthStorage(window.localStorage);
  authStorageReady = true;
} catch (_error) {
  // Fail closed: never create a production client if exact legacy cleanup fails.
}

const isConfigured = Boolean(
  authStorageReady &&
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
    storageKey: V2_AUTH_STORAGE_KEY,
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
