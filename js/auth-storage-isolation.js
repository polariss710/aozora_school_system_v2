export const V2_AUTH_STORAGE_KEY = "aozora-school-v2-auth-v1";
export const LEGACY_AUTH_STORAGE_KEY = "sb-xlcdqvlfzspcxdoidsrr-auth-token";

const LEGACY_USER_KEY = `${LEGACY_AUTH_STORAGE_KEY}-user`;
const LEGACY_CODE_VERIFIER_KEY = `${LEGACY_AUTH_STORAGE_KEY}-code-verifier`;
const LEGACY_FLOW_INDEX_KEY = `${LEGACY_AUTH_STORAGE_KEY}-flows-code-verifier`;
const FLOW_ID_PATTERN = /^[0-9a-f]{32}$/i;

export function removeLegacyAuthStorage(storage) {
  assertStorageContract(storage);

  const legacyFlowIds = parseLegacyFlowIds(storage.getItem(LEGACY_FLOW_INDEX_KEY));
  const exactKeys = [
    LEGACY_AUTH_STORAGE_KEY,
    LEGACY_USER_KEY,
    LEGACY_CODE_VERIFIER_KEY,
    LEGACY_FLOW_INDEX_KEY,
    ...legacyFlowIds.map(
      (flowId) => `${LEGACY_AUTH_STORAGE_KEY}-flow-${flowId}-code-verifier`
    ),
  ];

  for (const key of exactKeys) storage.removeItem(key);
  for (const key of exactKeys) {
    if (storage.getItem(key) !== null) {
      throw new Error("legacy_auth_storage_cleanup_failed");
    }
  }

  return { removedKeyCount: exactKeys.length };
}

function assertStorageContract(storage) {
  if (
    !storage ||
    typeof storage.getItem !== "function" ||
    typeof storage.removeItem !== "function"
  ) {
    throw new Error("auth_storage_unavailable");
  }
}

function parseLegacyFlowIds(rawValue) {
  if (rawValue === null) return [];

  let parsed;
  try {
    parsed = JSON.parse(rawValue);
  } catch (_error) {
    throw new Error("legacy_auth_flow_index_invalid");
  }
  if (!Array.isArray(parsed) || parsed.some((flowId) => !FLOW_ID_PATTERN.test(flowId))) {
    throw new Error("legacy_auth_flow_index_invalid");
  }
  return [...new Set(parsed)];
}
