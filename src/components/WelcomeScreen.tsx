import { motion } from "framer-motion";

interface WelcomeScreenProps {
  onStartTrial: () => void;
  onRestore: () => void;
  purchasing: boolean;
}

export function WelcomeScreen({ onStartTrial, onRestore, purchasing }: WelcomeScreenProps) {
  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      className="flex items-center justify-center min-h-screen bg-white"
    >
      <div className="text-center max-w-md px-6">
        <motion.div
          initial={{ scale: 0.8, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ delay: 0.1 }}
          className="mb-8"
        >
          <img src="/icon.png" alt="Token Wise" className="w-20 h-20 mx-auto mb-2 drop-shadow-lg" />
          <h1 className="text-3xl font-bold text-gray-900 mb-2">Token Wise</h1>
          <p className="text-gray-500 text-lg">
            Track your AI token usage and costs — completely offline.
          </p>
        </motion.div>

        <motion.div
          initial={{ y: 20, opacity: 0 }}
          animate={{ y: 0, opacity: 1 }}
          transition={{ delay: 0.3 }}
          className="space-y-4"
        >
          <button
            onClick={onStartTrial}
            disabled={purchasing}
            className="w-full py-3 px-6 bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-white font-semibold rounded-xl transition-colors text-lg"
          >
            Start 3-Day Free Trial
          </button>

          <p className="text-gray-400 text-sm">
            No account needed. Full access for 3 days.
          </p>

          <button
            onClick={onRestore}
            disabled={purchasing}
            className="text-indigo-600 hover:text-indigo-500 text-sm underline underline-offset-2 disabled:opacity-50"
          >
            {purchasing ? "Restoring..." : "Already purchased? Restore"}
          </button>
        </motion.div>
      </div>
    </motion.div>
  );
}
