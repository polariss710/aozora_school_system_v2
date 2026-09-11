import { requireGlobalSession } from "./auth-guard.js?v=operator-income-access-20260911-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  window.location.replace(new URL("./index.html", window.location.href).href);
});
