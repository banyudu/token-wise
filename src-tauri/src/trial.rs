use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

const TRIAL_DURATION_DAYS: i64 = 3;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct TrialData {
    pub started_at: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct TrialStatus {
    pub active: bool,
    pub started: bool,
    pub days_remaining: f64,
    pub expired: bool,
}

fn trial_file_path() -> PathBuf {
    let app_dir = dirs::data_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("com.banyudu.token-wise");
    fs::create_dir_all(&app_dir).ok();
    app_dir.join("trial.json")
}

fn read_trial_data() -> Option<TrialData> {
    let path = trial_file_path();
    let content = fs::read_to_string(path).ok()?;
    serde_json::from_str(&content).ok()
}

pub fn start_trial() -> TrialStatus {
    // Don't restart if already started
    if let Some(data) = read_trial_data() {
        return compute_status(&data);
    }

    let data = TrialData {
        started_at: Utc::now().to_rfc3339(),
    };

    let path = trial_file_path();
    if let Ok(json) = serde_json::to_string_pretty(&data) {
        fs::write(path, json).ok();
    }

    compute_status(&data)
}

pub fn get_trial_status() -> TrialStatus {
    match read_trial_data() {
        Some(data) => compute_status(&data),
        None => TrialStatus {
            active: false,
            started: false,
            days_remaining: 0.0,
            expired: false,
        },
    }
}

fn compute_status(data: &TrialData) -> TrialStatus {
    let started_at = DateTime::parse_from_rfc3339(&data.started_at)
        .map(|dt| dt.with_timezone(&Utc))
        .unwrap_or_else(|_| Utc::now());

    let expires_at = started_at + Duration::days(TRIAL_DURATION_DAYS);
    let now = Utc::now();
    let remaining = expires_at - now;
    let days_remaining = remaining.num_seconds() as f64 / 86400.0;

    if days_remaining > 0.0 {
        TrialStatus {
            active: true,
            started: true,
            days_remaining,
            expired: false,
        }
    } else {
        TrialStatus {
            active: false,
            started: true,
            days_remaining: 0.0,
            expired: true,
        }
    }
}
