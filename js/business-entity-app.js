import { requireGlobalSession } from "./auth-guard.js?v=operator-settlement-draft-20260911-3";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  window.location.replace(new URL("./index.html", window.location.href).href);
});
