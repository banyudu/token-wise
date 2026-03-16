export interface ProductInfo {
  id: string;
  displayName: string;
  description: string;
  displayPrice: string;
  price: number;
  type?: "auto_renewable" | "non_consumable";
}

export interface PurchaseResult {
  ok: boolean;
  status?: string;
  error?: string;
}

export interface EntitlementStatus {
  ok: boolean;
  has_annual?: boolean;
  has_lifetime?: boolean;
  annual_expires?: string;
  error?: string;
}

export interface TrialStatus {
  active: boolean;
  started: boolean;
  days_remaining: number;
  expired: boolean;
}

export type AppState = "welcome" | "trial" | "expired" | "paid";

export interface AppEntitlement {
  state: AppState;
  trial_days_remaining: number;
  purchase_type?: "annual" | "lifetime";
  annual_expires?: string;
}
