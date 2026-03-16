import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import { EntitlementGate } from "./components/EntitlementGate";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <EntitlementGate>
      <App />
    </EntitlementGate>
  </React.StrictMode>,
);
