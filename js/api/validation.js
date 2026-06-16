const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function requireUuid(value, fieldName) {
  const text = String(value || "").trim();
  if (!UUID_RE.test(text)) {
    throw new Error(`${fieldName} is not a valid UUID`);
  }

  return text;
}
