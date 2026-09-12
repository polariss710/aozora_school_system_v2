import { requireGlobalSession } from "./auth-guard.js?v=v10-5-65-20260913-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  window.location.replace(new URL("./index.html", window.location.href).href);
});
