import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Token Wise — Track Your AI Token Usage & Costs",
  description:
    "A native macOS app that tracks your AI token usage and costs across Claude, GPT, and more. AI-powered savings analysis via your own claude/codex CLI. Completely offline, privacy-first.",
  openGraph: {
    title: "Token Wise — Track Your AI Token Usage & Costs",
    description:
      "A native macOS app that tracks your AI token usage and costs across Claude, GPT, and more. AI-powered savings analysis via your own claude/codex CLI.",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="scroll-smooth">
      <body className="antialiased">
        {children}
      </body>
    </html>
  );
}
