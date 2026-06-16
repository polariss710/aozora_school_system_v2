export async function buildFunctionError(error, data, fallbackMessage) {
  const responseDetails = await readFunctionErrorResponse(error?.context);
  const dataDetails = extractFunctionErrorDetails(data);
  const errorDetails = extractFunctionErrorDetails(error);
  const details = responseDetails || dataDetails || errorDetails;
  const prefix = String(fallbackMessage || "Edge Function 调用失败。").replace(/[。:：]+$/, "");

  return new Error(details ? `${prefix}：${details}` : `${prefix}：Edge Function returned a non-2xx status code`);
}

async function readFunctionErrorResponse(context) {
  if (!context || context.bodyUsed) {
    return "";
  }

  try {
    const contentType = context.headers?.get?.("content-type") || "";
    if (contentType.includes("application/json")) {
      return extractFunctionErrorDetails(await context.json());
    }

    if (typeof context.text === "function") {
      return truncateErrorText(await context.text());
    }
  } catch (_error) {
    return "";
  }

  return "";
}

function extractFunctionErrorDetails(value) {
  if (!value) {
    return "";
  }

  if (typeof value === "string") {
    return truncateErrorText(value);
  }

  const preferred = value.message || value.details || value.error_description || value.error;
  if (preferred) {
    return extractFunctionErrorDetails(preferred);
  }

  if (typeof value === "object") {
    try {
      return truncateErrorText(JSON.stringify(value));
    } catch (_error) {
      return "";
    }
  }

  return truncateErrorText(String(value));
}

function truncateErrorText(value) {
  const text = String(value || "").trim();
  if (text.length <= 500) {
    return text;
  }

  return `${text.slice(0, 497)}...`;
}
