import { requireGlobalSession } from "./auth-guard.js?v=chain-consistency-20260911-2";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  window.location.replace(new URL("./index.html", window.location.href).href);
});
