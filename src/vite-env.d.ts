/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Set at build time for Developer ID / direct-distribution builds to enable
   *  the in-app self-update prompt. Unset (App Store build) → updater UI is inert. */
  readonly VITE_ENABLE_UPDATER?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
