import { useEffect } from "react";
import { motion } from "framer-motion";
import type { ProductInfo } from "../types/entitlement";

interface PaywallProps {
  products: ProductInfo[];
  onFetchProducts: () => void;
  onPurchase: (productId: string) => void;
  onRestore: () => void;
  purchasing: boolean;
}

export function Paywall({ products, onFetchProducts, onPurchase, onRestore, purchasing }: PaywallProps) {
  useEffect(() => {
    onFetchProducts();
  }, [onFetchProducts]);

  const pro = products.find((p) => p.id.includes("pro"));

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      className="flex items-center justify-center min-h-screen bg-white"
    >
      <div className="text-center max-w-lg px-6">
        <motion.div
          initial={{ scale: 0.8, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.1 }}
          className="mb-8"
        >
          <img src="/icon.png" alt="Token Wise" className="w-20 h-20 mx-auto mb-2 drop-shadow-lg" />
          <h1 className="text-2xl font-bold text-gray-900 mb-2">Your trial has ended</h1>
          <p className="text-gray-500">
            Unlock Token Wise forever with a single purchase.
          </p>
        </motion.div>

        <motion.div
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.3 }}
          className="space-y-3"
        >
          {pro && (
            <button
              onClick={() => onPurchase(pro.id)}
              disabled={purchasing}
              className="w-full py-4 px-6 bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-white font-semibold rounded-xl transition-colors"
            >
              <div className="text-lg">{pro.displayName}</div>
              <div className="text-indigo-200 text-sm">{pro.displayPrice} — one-time purchase</div>
            </button>
          )}

          {products.length === 0 && (
            <div className="text-gray-400 py-4">
              {purchasing ? "Loading..." : "Unable to load products. Check your connection."}
            </div>
          )}

          <button
            onClick={onRestore}
            disabled={purchasing}
            className="text-indigo-600 hover:text-indigo-500 text-sm underline underline-offset-2 disabled:opacity-50 mt-4"
          >
            {purchasing ? "Restoring..." : "Restore Purchases"}
          </button>
        </motion.div>
      </div>
    </motion.div>
  );
}
