import { useCallback, useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { AppEntitlement, ProductInfo } from "../types/entitlement";

export function useEntitlement() {
  const [entitlement, setEntitlement] = useState<AppEntitlement | null>(null);
  const [products, setProducts] = useState<ProductInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [purchasing, setPurchasing] = useState(false);

  const refresh = useCallback(async () => {
    try {
      const ent = await invoke<AppEntitlement>("get_app_entitlement");
      setEntitlement(ent);
    } catch (e) {
      console.error("Failed to get entitlement:", e);
      // Default to welcome on error
      setEntitlement({
        state: "welcome",
        trial_days_remaining: 0,
      });
    }
  }, []);

  useEffect(() => {
    refresh().then(() => setLoading(false));
  }, [refresh]);

  const fetchProducts = useCallback(async () => {
    try {
      const prods = await invoke<ProductInfo[]>("fetch_products");
      setProducts(prods);
    } catch (e) {
      console.error("Failed to fetch products:", e);
    }
  }, []);

  const startTrial = useCallback(async () => {
    await invoke("start_trial");
    await refresh();
  }, [refresh]);

  const purchase = useCallback(
    async (productId: string) => {
      setPurchasing(true);
      try {
        await invoke("purchase", { productId });
        await refresh();
      } finally {
        setPurchasing(false);
      }
    },
    [refresh],
  );

  const restorePurchases = useCallback(async () => {
    setPurchasing(true);
    try {
      await invoke("restore_purchases");
      await refresh();
    } finally {
      setPurchasing(false);
    }
  }, [refresh]);

  return {
    entitlement,
    products,
    loading,
    purchasing,
    fetchProducts,
    startTrial,
    purchase,
    restorePurchases,
    refresh,
  };
}
