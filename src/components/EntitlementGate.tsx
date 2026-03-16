import type { ReactNode } from "react";
import { useEntitlement } from "../hooks/useEntitlement";
import { WelcomeScreen } from "./WelcomeScreen";
import { Paywall } from "./Paywall";
import { TrialBanner } from "./TrialBanner";
import { LoadingScreen } from "../LoadingScreen";

interface EntitlementGateProps {
  children: ReactNode;
}

export function EntitlementGate({ children }: EntitlementGateProps) {
  const {
    entitlement,
    products,
    loading,
    purchasing,
    fetchProducts,
    startTrial,
    purchase,
    restorePurchases,
  } = useEntitlement();

  if (loading || !entitlement) {
    return <LoadingScreen />;
  }

  switch (entitlement.state) {
    case "welcome":
      return (
        <WelcomeScreen
          onStartTrial={startTrial}
          onRestore={restorePurchases}
          purchasing={purchasing}
        />
      );

    case "trial":
      return (
        <>
          <TrialBanner daysRemaining={entitlement.trial_days_remaining} />
          <div className="pt-8">{children}</div>
        </>
      );

    case "expired":
      return (
        <Paywall
          products={products}
          onFetchProducts={fetchProducts}
          onPurchase={purchase}
          onRestore={restorePurchases}
          purchasing={purchasing}
        />
      );

    case "paid":
      return <>{children}</>;

    default:
      return <>{children}</>;
  }
}
