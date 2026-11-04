import React from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import Emergency from "./Emergency";
import "./styles.css";
createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    {new URLSearchParams(location.search).has("legacy") ? <App /> : <Emergency />}
  </React.StrictMode>,
);
if (import.meta.env.PROD && "serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    void navigator.serviceWorker.register("/sw.js").catch(() => {
      /* IndexedDB persistence remains available without asset caching. */
    });
  });
}
