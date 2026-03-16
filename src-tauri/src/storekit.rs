use serde::{Deserialize, Serialize};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

// FFI declarations for Swift StoreKit bridge
extern "C" {
    fn storekit_fetch_products() -> *mut c_char;
    fn storekit_purchase(product_id: *const c_char) -> *mut c_char;
    fn storekit_check_entitlements() -> *mut c_char;
    fn storekit_restore_purchases() -> *mut c_char;
    fn storekit_free_string(ptr: *mut c_char);
}

fn call_swift(ptr: *mut c_char) -> String {
    unsafe {
        let cstr = CStr::from_ptr(ptr);
        let result = cstr.to_string_lossy().into_owned();
        storekit_free_string(ptr);
        result
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ProductInfo {
    pub id: String,
    #[serde(rename = "displayName")]
    pub display_name: String,
    pub description: String,
    #[serde(rename = "displayPrice")]
    pub display_price: String,
    pub price: f64,
    #[serde(rename = "type")]
    pub product_type: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct FetchProductsResponse {
    ok: bool,
    products: Option<Vec<ProductInfo>>,
    error: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PurchaseResult {
    pub ok: bool,
    pub status: Option<String>,
    pub error: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EntitlementStatus {
    pub ok: bool,
    pub has_pro: Option<bool>,
    pub error: Option<String>,
}

pub fn fetch_products() -> Result<Vec<ProductInfo>, String> {
    let json = call_swift(unsafe { storekit_fetch_products() });
    let resp: FetchProductsResponse =
        serde_json::from_str(&json).map_err(|e| format!("Parse error: {}", e))?;
    if resp.ok {
        Ok(resp.products.unwrap_or_default())
    } else {
        Err(resp.error.unwrap_or_else(|| "Unknown error".to_string()))
    }
}

pub fn purchase(product_id: &str) -> Result<PurchaseResult, String> {
    let c_id = CString::new(product_id).map_err(|e| e.to_string())?;
    let json = call_swift(unsafe { storekit_purchase(c_id.as_ptr()) });
    serde_json::from_str(&json).map_err(|e| format!("Parse error: {}", e))
}

pub fn check_entitlements() -> Result<EntitlementStatus, String> {
    let json = call_swift(unsafe { storekit_check_entitlements() });
    serde_json::from_str(&json).map_err(|e| format!("Parse error: {}", e))
}

pub fn restore_purchases() -> Result<EntitlementStatus, String> {
    let json = call_swift(unsafe { storekit_restore_purchases() });
    serde_json::from_str(&json).map_err(|e| format!("Parse error: {}", e))
}
