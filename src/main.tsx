import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import { UpdateBanner } from "./UpdateBanner";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
    <UpdateBanner />
  </React.StrictMode>,
);
