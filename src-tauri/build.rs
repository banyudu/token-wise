fn main() {
    // The macOS security-scoped bookmark + folder-picker bridge (src/grants.m).
    // Compiled with ARC and linked against the system frameworks. Only the App
    // Store (sandboxed) build actually exercises it; non-sandboxed builds fall
    // back to reading the home directory directly — but we still compile it on
    // every macOS target so a single binary works in both contexts.
    #[cfg(target_os = "macos")]
    {
        cc::Build::new()
            .file("src/grants.m")
            .flag("-fobjc-arc")
            .compile("tw_grants");
        println!("cargo:rustc-link-lib=framework=Foundation");
        println!("cargo:rustc-link-lib=framework=AppKit");
        println!("cargo:rerun-if-changed=src/grants.m");
    }

    tauri_build::build();
}
