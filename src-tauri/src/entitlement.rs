use serde::Serialize;

use crate::storekit;
use crate::trial;

#[derive(Debug, Serialize, Clone)]
pub struct AppEntitlement {
    pub state: String, // "welcome" | "trial" | "expired" | "paid"
    pub trial_days_remaining: f64,
}

#[tauri::command]
pub async fn fetch_products() -> Result<Vec<storekit::ProductInfo>, String> {
    storekit::fetch_products()
}

#[tauri::command]
pub async fn purchase(product_id: String) -> Result<storekit::PurchaseResult, String> {
    storekit::purchase(&product_id)
}

#[tauri::command]
pub async fn check_entitlements() -> Result<storekit::EntitlementStatus, String> {
    storekit::check_entitlements()
}

#[tauri::command]
pub async fn restore_purchases() -> Result<storekit::EntitlementStatus, String> {
    storekit::restore_purchases()
}

#[tauri::command]
pub async fn start_trial() -> trial::TrialStatus {
    trial::start_trial()
}

#[tauri::command]
pub async fn get_app_entitlement() -> AppEntitlement {
    // Check StoreKit entitlements first
    if let Ok(ent) = storekit::check_entitlements() {
        if ent.has_pro.unwrap_or(false) {
            return AppEntitlement {
                state: "paid".to_string(),
                trial_days_remaining: 0.0,
            };
        }
    }

    // Fall back to trial status
    let trial = trial::get_trial_status();
    if trial.active {
        AppEntitlement {
            state: "trial".to_string(),
            trial_days_remaining: trial.days_remaining,
        }
    } else if trial.expired {
        AppEntitlement {
            state: "expired".to_string(),
            trial_days_remaining: 0.0,
        }
    } else {
        AppEntitlement {
            state: "welcome".to_string(),
            trial_days_remaining: 0.0,
        }
    }
}
