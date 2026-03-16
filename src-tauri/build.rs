use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    tauri_build::build();

    // Only compile Swift StoreKit bridge on macOS
    if env::var("CARGO_CFG_TARGET_OS").unwrap_or_default() != "macos" {
        return;
    }

    let swift_plugin_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap())
        .join("swift-plugin");

    let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_else(|_| "arm64".to_string());
    let swift_arch = match target_arch.as_str() {
        "aarch64" => "arm64",
        "x86_64" => "x86_64",
        other => other,
    };

    let build_dir = swift_plugin_dir.join(".build");

    // Build Swift package in release mode
    let status = Command::new("swift")
        .args([
            "build",
            "-c", "release",
            "--arch", swift_arch,
            "--package-path",
        ])
        .arg(&swift_plugin_dir)
        .status()
        .expect("Failed to run swift build. Is Xcode installed?");

    if !status.success() {
        panic!("Swift build failed");
    }

    // Find the static library
    let lib_search_path = build_dir
        .join(format!("{}-apple-macosx", swift_arch))
        .join("release");

    // Tell Cargo where to find the Swift static library
    println!("cargo:rustc-link-search=native={}", lib_search_path.display());
    println!("cargo:rustc-link-lib=static=StoreKitBridge");

    // Link required Apple frameworks
    println!("cargo:rustc-link-lib=framework=StoreKit");
    println!("cargo:rustc-link-lib=framework=Foundation");

    // Link Swift runtime libraries
    let swift_toolchain_output = Command::new("xcrun")
        .args(["--show-sdk-path"])
        .output()
        .expect("Failed to run xcrun");
    let sdk_path = String::from_utf8_lossy(&swift_toolchain_output.stdout)
        .trim()
        .to_string();

    // Swift runtime lib paths
    let swift_lib_dir = format!("{}/usr/lib/swift", sdk_path);
    println!("cargo:rustc-link-search=native={}", swift_lib_dir);

    // Also need the toolchain swift libs (for swift concurrency runtime etc.)
    let toolchain_output = Command::new("xcrun")
        .args(["--toolchain", "default", "--find", "swift"])
        .output()
        .expect("Failed to find swift toolchain");
    let swift_bin = String::from_utf8_lossy(&toolchain_output.stdout)
        .trim()
        .to_string();
    if let Some(toolchain_dir) = PathBuf::from(&swift_bin).parent().and_then(|p| p.parent()) {
        let toolchain_lib = toolchain_dir.join("lib").join("swift").join("macosx");
        println!("cargo:rustc-link-search=native={}", toolchain_lib.display());
        // Add rpath so the dynamic linker can find Swift runtime dylibs at runtime
        println!("cargo:rustc-link-arg=-Wl,-rpath,{}", toolchain_lib.display());
    }

    // Also add rpath to the OS Swift support libraries
    println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");

    // Fix @rpath/libswift_Concurrency.dylib → absolute path
    // The Swift static lib links concurrency as @rpath, but it lives in /usr/lib/swift
    println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");

    // Rerun if Swift sources change
    println!("cargo:rerun-if-changed=swift-plugin/Sources/");
    println!("cargo:rerun-if-changed=swift-plugin/Package.swift");
}
