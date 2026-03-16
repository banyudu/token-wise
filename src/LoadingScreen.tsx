import { motion } from "framer-motion";
import type { Easing } from "framer-motion";

const ease: Easing = "easeInOut";
const easeOut: Easing = "easeOut";

const colors = ["#1a3a5c", "#c8d83e", "#27ae60", "#4a90d9"];

export function LoadingScreen({ message = "Loading your data..." }: { message?: string }) {
  return (
    <main className="flex flex-col justify-center items-center min-h-screen gap-8 select-none">
      <div className="relative flex items-center justify-center">
        {/* Pulse rings */}
        {[0, 1].map((i) => (
          <motion.div
            key={i}
            className="absolute rounded-full border-2 border-[#4a90d9]"
            style={{ width: 120, height: 120 }}
            initial={{ scale: 0.8, opacity: 0.6 }}
            animate={{
              scale: [0.8, 1.4, 0.8],
              opacity: [0.6, 0, 0.6],
            }}
            transition={{ duration: 2, repeat: Infinity, ease, delay: i * 0.8 }}
          />
        ))}

        {/* Owl icon */}
        <motion.img
          src="/icon.png"
          alt="Token Wise"
          className="w-20 h-20 relative z-10 drop-shadow-lg"
          initial={{ scale: 0.8, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ duration: 0.6, ease: easeOut }}
        />
      </div>

      {/* Animated bars — sequential fill, then all reset */}
      <div className="flex gap-1.5 items-center h-3">
        {colors.map((color, i) => {
          const step = 0.4;
          const n = colors.length;
          const fillStart = i * step;
          const fillEnd = fillStart + step;
          const holdEnd = n * step + 0.3;
          const total = holdEnd + 0.01;

          return (
            <motion.div
              key={i}
              className="h-2 w-8 rounded-full origin-left"
              style={{ backgroundColor: color }}
              initial={{ scaleX: 0 }}
              animate={{ scaleX: [0, 0, 1, 1, 0] }}
              transition={{
                duration: total,
                times: [
                  0,
                  fillStart / total,
                  fillEnd / total,
                  holdEnd / total,
                  1,
                ],
                repeat: Infinity,
                ease: "linear",
              }}
            />
          );
        })}
      </div>

      {/* Text */}
      <motion.p
        className="text-sm text-[var(--color-muted)] font-medium tracking-wide"
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.4, duration: 0.5 }}
      >
        {message}
      </motion.p>
    </main>
  );
}
