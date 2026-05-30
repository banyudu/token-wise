import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

/**
 * Listens for the Rust `update-ready` event (emitted only by Developer ID /
 * direct-distribution builds after a new version is downloaded and staged) and
 * offers a one-click relaunch. Renders nothing unless built with
 * VITE_ENABLE_UPDATER, so the App Store build never shows it.
 */
export function UpdateBanner() {
  const [version, setVersion] = useState<string | null>(null);

  useEffect(() => {
    if (!import.meta.env.VITE_ENABLE_UPDATER) return;
    const unlisten = listen<string>("update-ready", (event) => {
      setVersion(event.payload);
    });
    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  if (!version) return null;

  return (
    <div
      style={{
        position: "fixed",
        bottom: 16,
        right: 16,
        zIndex: 9999,
        display: "flex",
        alignItems: "center",
        gap: 12,
        padding: "10px 14px",
        borderRadius: 10,
        background: "rgba(20, 20, 22, 0.92)",
        color: "#fff",
        boxShadow: "0 6px 24px rgba(0, 0, 0, 0.35)",
        fontSize: 13,
      }}
    >
      <span>
        Version {version} downloaded.
      </span>
      <button
        onClick={() => invoke("restart_app")}
        style={{
          padding: "5px 10px",
          borderRadius: 6,
          border: "none",
          background: "#4f8cff",
          color: "#fff",
          cursor: "pointer",
          fontSize: 13,
        }}
      >
        Restart to update
      </button>
    </div>
  );
}
