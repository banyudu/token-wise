// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // Best-effort: expose the bundled CLI on PATH if it isn't already.
    token_wise_lib::path_install::ensure_cli_on_path();

    let args: Vec<String> = std::env::args().collect();
    if args.len() > 1 && token_wise_lib::cli::is_cli_arg(&args[1]) {
        std::process::exit(token_wise_lib::cli::run());
    }
    token_wise_lib::run()
}
