interface TrialBannerProps {
  daysRemaining: number;
}

export function TrialBanner({ daysRemaining }: TrialBannerProps) {
  const days = Math.ceil(daysRemaining);
  const label = days === 1 ? "1 day" : `${days} days`;
  const urgent = days <= 1;

  return (
    <div
      className={`fixed top-0 left-0 right-0 z-50 text-center py-1.5 text-sm font-medium ${
        urgent
          ? "bg-amber-600/90 text-white"
          : "bg-indigo-600/90 text-white"
      }`}
    >
      Trial: {label} remaining
    </div>
  );
}
