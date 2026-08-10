import { requireGlobalSession } from "./auth-guard.js?v=p1-b2b-auth-storage-20260810-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  window.location.replace(new URL("./index.html", window.location.href).href);
});
