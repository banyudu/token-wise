import Image from "next/image";

const features = [
  {
    icon: (
      <svg className="w-7 h-7" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 013 19.875v-6.75zM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V8.625zM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V4.125z" />
      </svg>
    ),
    title: "Cost Dashboard",
    description:
      "See daily, weekly, and monthly spending with rich charts. Break down costs by project, session, and model.",
  },
  {
    icon: (
      <svg className="w-7 h-7" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z" />
      </svg>
    ),
    title: "100% Offline & Private",
    description:
      "All data stays on your Mac. No accounts, no cloud sync, no telemetry. Your usage data never leaves your machine.",
  },
  {
    icon: (
      <svg className="w-7 h-7" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09zM18.259 8.715L18 9.75l-.259-1.035a3.375 3.375 0 00-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 002.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 002.455 2.456L21.75 6l-1.036.259a3.375 3.375 0 00-2.455 2.456z" />
      </svg>
    ),
    title: "Multi-Model Support",
    description:
      "Track tokens across Claude Opus, Sonnet, Haiku, GPT-4.1, GPT-5.2, and more. Switch pricing models on the fly.",
  },
  {
    icon: (
      <svg className="w-7 h-7" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125" />
      </svg>
    ),
    title: "Cache Savings Detector",
    description:
      "Pinpoint wasted cache writes, prefix invalidations, and large CLAUDE.md blocks loaded but never referenced. See the dollar amount you could reclaim per session.",
  },
  {
    icon: (
      <svg className="w-7 h-7" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M2.25 12.75V12A2.25 2.25 0 014.5 9.75h15A2.25 2.25 0 0121.75 12v.75m-8.69-6.44l-2.12-2.12a1.5 1.5 0 00-1.061-.44H4.5A2.25 2.25 0 002.25 6v12a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9a2.25 2.25 0 00-2.25-2.25h-5.379a1.5 1.5 0 01-1.06-.44z" />
      </svg>
    ),
    title: "Per-Project Breakdown",
    description:
      "See exactly how much each project costs. Compare spending across repos and track your top sessions.",
  },
  {
    icon: (
      <svg className="w-7 h-7" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={1.5}>
        <path strokeLinecap="round" strokeLinejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" />
      </svg>
    ),
    title: "Session Deep Dive",
    description:
      "Explore individual sessions turn-by-turn. See token usage, context growth, and content analysis for each conversation.",
  },
];

const pricingModels = [
  { name: "Opus 4", input: "$15.00", output: "$75.00" },
  { name: "Sonnet 4", input: "$3.00", output: "$15.00" },
  { name: "Haiku 3.5", input: "$0.80", output: "$4.00" },
  { name: "GPT-5.4", input: "$2.50", output: "$10.00" },
  { name: "GPT-5.2", input: "$1.25", output: "$5.00" },
  { name: "GPT-4.1", input: "$2.00", output: "$8.00" },
];

export default function Home() {
  return (
    <div className="min-h-screen">
      {/* Nav */}
      <nav className="fixed top-0 inset-x-0 z-50 bg-white/80 dark:bg-[#0a0a0a]/80 backdrop-blur-md border-b border-neutral-200 dark:border-neutral-800">
        <div className="max-w-6xl mx-auto flex items-center justify-between px-6 h-16">
          <div className="flex items-center gap-3">
            <Image src="/icon.png" alt="Token Wise" width={32} height={32} />
            <span className="font-semibold text-lg">Token Wise</span>
          </div>
          <div className="hidden sm:flex items-center gap-8 text-sm text-neutral-600 dark:text-neutral-400">
            <a href="#features" className="hover:text-foreground transition-colors">Features</a>
            <a href="#pricing" className="hover:text-foreground transition-colors">Pricing</a>
            <a href="#models" className="hover:text-foreground transition-colors">Models</a>
          </div>
          <a
            href="https://apps.apple.com/us/app/token-wise/id6760606980?mt=12"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 bg-neutral-900 dark:bg-white dark:text-neutral-900 text-white text-sm font-medium px-4 py-2 rounded-full hover:opacity-90 transition-opacity"
          >
            <svg className="w-4 h-4" viewBox="0 0 24 24" fill="currentColor">
              <path d="M18.71 19.5C17.88 20.74 17 21.95 15.66 21.97C14.32 21.99 13.89 21.18 12.37 21.18C10.84 21.18 10.37 21.95 9.1 21.99C7.79 22.03 6.8 20.68 5.96 19.47C4.25 16.56 2.93 11.3 4.7 7.72C5.57 5.94 7.36 4.86 9.28 4.84C10.56 4.82 11.78 5.7 12.57 5.7C13.36 5.7 14.85 4.63 16.4 4.8C17.06 4.83 18.88 5.09 20.06 6.82C19.96 6.88 17.62 8.26 17.65 11.11C17.68 14.53 20.59 15.64 20.62 15.66C20.59 15.73 20.14 17.29 18.71 19.5ZM13 3.5C13.73 2.67 14.94 2.04 15.94 2C16.07 3.17 15.58 4.35 14.89 5.14C14.2 5.96 13.07 6.63 11.95 6.55C11.8 5.39 12.38 4.2 13 3.5Z"/>
            </svg>
            Download
          </a>
        </div>
      </nav>

      {/* Hero */}
      <section className="pt-32 pb-20 px-6">
        <div className="max-w-4xl mx-auto text-center">
          <div className="animate-fade-in-up">
            <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-lime/10 text-teal dark:text-lime text-sm font-medium mb-8">
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              Available on the Mac App Store
            </div>
          </div>
          <h1 className="text-5xl sm:text-7xl font-bold tracking-tight mb-6 animate-fade-in-up">
            Know what your{" "}
            <span className="bg-gradient-to-r from-teal to-lime bg-clip-text text-transparent">
              AI tokens
            </span>{" "}
            cost
          </h1>
          <p className="text-lg sm:text-xl text-neutral-600 dark:text-neutral-400 max-w-2xl mx-auto mb-10 animate-fade-in-up-delay-1">
            Token Wise is a native macOS app that tracks your AI token usage and
            costs across Claude, GPT, and more. Completely offline. Privacy-first.
          </p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4 animate-fade-in-up-delay-2">
            <a
              href="https://apps.apple.com/us/app/token-wise/id6760606980?mt=12"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-3 bg-neutral-900 dark:bg-white dark:text-neutral-900 text-white font-semibold px-8 py-4 rounded-2xl hover:opacity-90 transition-opacity text-lg"
            >
              <svg className="w-6 h-6" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.71 19.5C17.88 20.74 17 21.95 15.66 21.97C14.32 21.99 13.89 21.18 12.37 21.18C10.84 21.18 10.37 21.95 9.1 21.99C7.79 22.03 6.8 20.68 5.96 19.47C4.25 16.56 2.93 11.3 4.7 7.72C5.57 5.94 7.36 4.86 9.28 4.84C10.56 4.82 11.78 5.7 12.57 5.7C13.36 5.7 14.85 4.63 16.4 4.8C17.06 4.83 18.88 5.09 20.06 6.82C19.96 6.88 17.62 8.26 17.65 11.11C17.68 14.53 20.59 15.64 20.62 15.66C20.59 15.73 20.14 17.29 18.71 19.5ZM13 3.5C13.73 2.67 14.94 2.04 15.94 2C16.07 3.17 15.58 4.35 14.89 5.14C14.2 5.96 13.07 6.63 11.95 6.55C11.8 5.39 12.38 4.2 13 3.5Z"/>
              </svg>
              Download for Mac
            </a>
            <a
              href="#features"
              className="inline-flex items-center gap-2 text-neutral-600 dark:text-neutral-400 hover:text-foreground font-medium px-8 py-4 rounded-2xl border border-neutral-200 dark:border-neutral-800 hover:border-neutral-400 dark:hover:border-neutral-600 transition-colors"
            >
              Learn more
              <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M19.5 13.5L12 21m0 0l-7.5-7.5M12 21V3" />
              </svg>
            </a>
          </div>
        </div>

        {/* Hero visual — app mockup */}
        <div className="max-w-5xl mx-auto mt-16 animate-fade-in-up-delay-3">
          <div className="relative rounded-2xl overflow-hidden border border-neutral-200 dark:border-neutral-800 bg-neutral-100 dark:bg-neutral-900 shadow-2xl">
            {/* Window chrome */}
            <div className="flex items-center gap-2 px-4 py-3 bg-neutral-200/60 dark:bg-neutral-800/60">
              <div className="w-3 h-3 rounded-full bg-red-400" />
              <div className="w-3 h-3 rounded-full bg-yellow-400" />
              <div className="w-3 h-3 rounded-full bg-green-400" />
              <span className="ml-3 text-xs text-neutral-500 font-medium">Token Wise</span>
            </div>
            {/* Simulated dashboard */}
            <div className="p-6 sm:p-10 space-y-6">
              {/* Top metrics row */}
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
                {[
                  { label: "Total Spent", value: "$142.38", sub: "30 days" },
                  { label: "Sessions", value: "247", sub: "across 12 projects" },
                  { label: "Tokens Used", value: "48.2M", sub: "input + output" },
                  { label: "Cache Hit Rate", value: "73.2%", sub: "saving $89.50" },
                ].map((m) => (
                  <div key={m.label} className="bg-white dark:bg-neutral-800 rounded-xl p-4 border border-neutral-200 dark:border-neutral-700">
                    <div className="text-xs text-neutral-500 mb-1">{m.label}</div>
                    <div className="text-2xl font-bold text-foreground">{m.value}</div>
                    <div className="text-xs text-neutral-400 mt-1">{m.sub}</div>
                  </div>
                ))}
              </div>
              {/* Chart placeholder */}
              <div className="bg-white dark:bg-neutral-800 rounded-xl p-6 border border-neutral-200 dark:border-neutral-700">
                <div className="text-sm font-medium text-neutral-500 mb-4">Daily Cost</div>
                <div className="flex items-end gap-1.5 h-32">
                  {[35, 52, 28, 65, 42, 78, 55, 38, 90, 62, 48, 72, 85, 45, 58, 92, 40, 68, 75, 50, 82, 60, 95, 55, 70, 88, 42, 65].map(
                    (h, i) => (
                      <div
                        key={i}
                        className="flex-1 rounded-t-sm bg-gradient-to-t from-teal to-lime opacity-80"
                        style={{ height: `${h}%` }}
                      />
                    )
                  )}
                </div>
              </div>
              {/* Session list preview */}
              <div className="bg-white dark:bg-neutral-800 rounded-xl border border-neutral-200 dark:border-neutral-700 overflow-hidden">
                <div className="text-sm font-medium text-neutral-500 px-4 pt-4 pb-2">Top Sessions</div>
                {[
                  { project: "api-gateway", cost: "$8.42", tokens: "2.1M", cache: "81%" },
                  { project: "web-dashboard", cost: "$5.17", tokens: "1.4M", cache: "68%" },
                  { project: "ml-pipeline", cost: "$3.95", tokens: "980K", cache: "72%" },
                ].map((s) => (
                  <div key={s.project} className="flex items-center justify-between px-4 py-3 border-t border-neutral-100 dark:border-neutral-700/50">
                    <div>
                      <span className="font-mono text-sm">{s.project}</span>
                    </div>
                    <div className="flex items-center gap-6 text-sm text-neutral-500">
                      <span>{s.tokens} tokens</span>
                      <span>{s.cache} cache</span>
                      <span className="font-semibold text-foreground">{s.cost}</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Features */}
      <section id="features" className="py-24 px-6 bg-neutral-50 dark:bg-neutral-900/50">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">
              Everything you need to track AI costs
            </h2>
            <p className="text-neutral-600 dark:text-neutral-400 max-w-xl mx-auto">
              Built for developers who use AI coding assistants daily and want to understand where their tokens go.
            </p>
          </div>
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-6">
            {features.map((f) => (
              <div
                key={f.title}
                className="bg-white dark:bg-neutral-800/50 rounded-2xl p-6 border border-neutral-200 dark:border-neutral-800 hover:border-teal/30 hover:shadow-lg transition-all duration-300"
              >
                <div className="w-12 h-12 rounded-xl bg-teal/10 text-teal flex items-center justify-center mb-4">
                  {f.icon}
                </div>
                <h3 className="text-lg font-semibold mb-2">{f.title}</h3>
                <p className="text-neutral-600 dark:text-neutral-400 text-sm leading-relaxed">
                  {f.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Pricing */}
      <section id="pricing" className="py-24 px-6">
        <div className="max-w-3xl mx-auto text-center">
          <h2 className="text-3xl sm:text-4xl font-bold mb-4">Free to use</h2>
          <p className="text-neutral-600 dark:text-neutral-400 mb-12">
            No subscriptions. No accounts. No hidden fees.
          </p>
          <div className="bg-white dark:bg-neutral-800/50 rounded-3xl border border-neutral-200 dark:border-neutral-800 p-8 sm:p-12 relative overflow-hidden">
            <div className="absolute top-0 right-0 w-64 h-64 bg-gradient-to-bl from-lime/10 to-transparent rounded-full -translate-y-1/2 translate-x-1/2" />
            <div className="relative">
              <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-lime/10 text-teal dark:text-lime text-sm font-medium mb-6">
                Free download
              </div>
              <div className="flex items-baseline justify-center gap-2 mb-2">
                <span className="text-5xl sm:text-6xl font-bold">Free</span>
              </div>
              <p className="text-neutral-500 mb-8">
                All features included. No upgrades, no add-ons.
              </p>
              <ul className="text-left max-w-sm mx-auto space-y-3 mb-10">
                {[
                  "Full cost dashboard & analytics",
                  "All AI models supported",
                  "Per-project cost breakdown",
                  "Session deep-dive with turn analysis",
                  "Cache hit rate analytics",
                  "Cache savings detector (wasted writes, invalidations, unreferenced context)",
                  "100% offline — your data stays local",
                  "All future updates included",
                ].map((item) => (
                  <li key={item} className="flex items-start gap-3 text-sm">
                    <svg className="w-5 h-5 text-lime shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                    <span>{item}</span>
                  </li>
                ))}
              </ul>
              <a
                href="https://apps.apple.com/us/app/token-wise/id6760606980?mt=12"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-3 bg-neutral-900 dark:bg-white dark:text-neutral-900 text-white font-semibold px-8 py-4 rounded-2xl hover:opacity-90 transition-opacity text-lg"
              >
                <svg className="w-6 h-6" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M18.71 19.5C17.88 20.74 17 21.95 15.66 21.97C14.32 21.99 13.89 21.18 12.37 21.18C10.84 21.18 10.37 21.95 9.1 21.99C7.79 22.03 6.8 20.68 5.96 19.47C4.25 16.56 2.93 11.3 4.7 7.72C5.57 5.94 7.36 4.86 9.28 4.84C10.56 4.82 11.78 5.7 12.57 5.7C13.36 5.7 14.85 4.63 16.4 4.8C17.06 4.83 18.88 5.09 20.06 6.82C19.96 6.88 17.62 8.26 17.65 11.11C17.68 14.53 20.59 15.64 20.62 15.66C20.59 15.73 20.14 17.29 18.71 19.5ZM13 3.5C13.73 2.67 14.94 2.04 15.94 2C16.07 3.17 15.58 4.35 14.89 5.14C14.2 5.96 13.07 6.63 11.95 6.55C11.8 5.39 12.38 4.2 13 3.5Z"/>
                </svg>
                Get on the App Store
              </a>
            </div>
          </div>
        </div>
      </section>

      {/* Supported Models */}
      <section id="models" className="py-24 px-6 bg-neutral-50 dark:bg-neutral-900/50">
        <div className="max-w-4xl mx-auto">
          <div className="text-center mb-12">
            <h2 className="text-3xl sm:text-4xl font-bold mb-4">Supported models</h2>
            <p className="text-neutral-600 dark:text-neutral-400">
              Built-in pricing for all major AI models. Costs calculated per million tokens.
            </p>
          </div>
          <div className="bg-white dark:bg-neutral-800/50 rounded-2xl border border-neutral-200 dark:border-neutral-800 overflow-hidden">
            <div className="grid grid-cols-3 px-6 py-3 text-xs font-medium text-neutral-500 uppercase tracking-wide border-b border-neutral-200 dark:border-neutral-700">
              <span>Model</span>
              <span className="text-right">Input / 1M tokens</span>
              <span className="text-right">Output / 1M tokens</span>
            </div>
            {pricingModels.map((m, i) => (
              <div
                key={m.name}
                className={`grid grid-cols-3 px-6 py-4 text-sm ${
                  i < pricingModels.length - 1 ? "border-b border-neutral-100 dark:border-neutral-700/50" : ""
                }`}
              >
                <span className="font-medium">{m.name}</span>
                <span className="text-right font-mono text-neutral-600 dark:text-neutral-400">{m.input}</span>
                <span className="text-right font-mono text-neutral-600 dark:text-neutral-400">{m.output}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="py-24 px-6">
        <div className="max-w-3xl mx-auto text-center">
          <Image
            src="/icon.png"
            alt="Token Wise"
            width={64}
            height={64}
            className="mx-auto mb-6 animate-float"
          />
          <h2 className="text-3xl sm:text-4xl font-bold mb-4">
            Start tracking your AI costs today
          </h2>
          <p className="text-neutral-600 dark:text-neutral-400 mb-8">
            Free download. No account required.
          </p>
          <a
            href="https://apps.apple.com/us/app/token-wise/id6760606980?mt=12"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-3 bg-neutral-900 dark:bg-white dark:text-neutral-900 text-white font-semibold px-8 py-4 rounded-2xl hover:opacity-90 transition-opacity text-lg"
          >
            <svg className="w-6 h-6" viewBox="0 0 24 24" fill="currentColor">
              <path d="M18.71 19.5C17.88 20.74 17 21.95 15.66 21.97C14.32 21.99 13.89 21.18 12.37 21.18C10.84 21.18 10.37 21.95 9.1 21.99C7.79 22.03 6.8 20.68 5.96 19.47C4.25 16.56 2.93 11.3 4.7 7.72C5.57 5.94 7.36 4.86 9.28 4.84C10.56 4.82 11.78 5.7 12.57 5.7C13.36 5.7 14.85 4.63 16.4 4.8C17.06 4.83 18.88 5.09 20.06 6.82C19.96 6.88 17.62 8.26 17.65 11.11C17.68 14.53 20.59 15.64 20.62 15.66C20.59 15.73 20.14 17.29 18.71 19.5ZM13 3.5C13.73 2.67 14.94 2.04 15.94 2C16.07 3.17 15.58 4.35 14.89 5.14C14.2 5.96 13.07 6.63 11.95 6.55C11.8 5.39 12.38 4.2 13 3.5Z"/>
            </svg>
            Download for Mac
          </a>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-neutral-200 dark:border-neutral-800 py-8 px-6">
        <div className="max-w-6xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4 text-sm text-neutral-500">
          <div className="flex items-center gap-2">
            <Image src="/icon.png" alt="Token Wise" width={20} height={20} />
            <span>&copy; {new Date().getFullYear()} Token Wise</span>
          </div>
          <div className="flex items-center gap-6">
            <a href="https://github.com/banyudu/token-wise" target="_blank" rel="noopener noreferrer" className="hover:text-foreground transition-colors">
              GitHub
            </a>
          </div>
        </div>
      </footer>
    </div>
  );
}
