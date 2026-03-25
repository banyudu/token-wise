import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Terms of Use — Token Wise",
  description: "Terms of Use for Token Wise, the macOS AI token usage tracker.",
};

export default function TermsOfUse() {
  return (
    <main className="min-h-screen bg-gray-50 text-gray-800">
      <div className="max-w-3xl mx-auto px-6 py-16">
        <Link
          href="/"
          className="text-blue-600 hover:text-blue-800 text-sm mb-8 inline-block"
        >
          &larr; Back to Home
        </Link>

        <h1 className="text-3xl font-bold mb-2">Terms of Use</h1>
        <p className="text-sm text-gray-500 mb-10">
          Last updated: March 25, 2026
        </p>

        <div className="space-y-8 leading-relaxed">
          <section>
            <h2 className="text-xl font-semibold mb-3">
              1. Acceptance of Terms
            </h2>
            <p>
              By downloading, installing, or using Token Wise (&quot;the
              App&quot;), you agree to be bound by these Terms of Use. If you do
              not agree to these terms, do not use the App.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-3">
              2. Description of Service
            </h2>
            <p>
              Token Wise is a macOS desktop application that tracks AI token
              usage and costs locally on your device. The App monitors API
              requests made by supported AI tools and provides analytics on
              token consumption and associated costs.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-3">3. License</h2>
            <p>
              We grant you a limited, non-exclusive, non-transferable,
              revocable license to use the App for personal or commercial
              purposes, subject to these Terms. You may not reverse engineer,
              decompile, or disassemble the App, except to the extent permitted
              by applicable law.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-3">4. User Conduct</h2>
            <p>You agree not to:</p>
            <ul className="list-disc list-inside mt-2 space-y-1">
              <li>Use the App for any unlawful purpose</li>
              <li>
                Attempt to interfere with or disrupt the App&apos;s
                functionality
              </li>
              <li>
                Redistribute, sublicense, or resell the App without
                authorization
              </li>
              <li>Remove or alter any proprietary notices in the App</li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-3">
              5. Intellectual Property
            </h2>
            <p>
              All rights, title, and interest in and to the App, including all
              intellectual property rights, are and will remain the exclusive
              property of Token Wise and its licensors.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-3">
              6. Disclaimer of Warranties
            </h2>
            <p>
              The App is provided &quot;as is&quot; and &quot;as
              available&quot; without warranties of any kind, either express or
              implied. We do not warrant that the App will be uninterrupted,
              error-free, or free of harmful components. Cost and token
              calculations are estimates and may not reflect exact billing from
              AI providers.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-3">
              7. Limitation of Liability
            </h2>
            <p>
              To the maximum extent permitted by law, Token Wise and its
              developers shall not be liable for any indirect, incidental,
              special, consequential, or punitive damages, or any loss of
              profits or revenues, whether incurred directly or indirectly,
              arising from your use of the App.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-3">8. Changes to Terms</h2>
            <p>
              We reserve the right to modify these Terms at any time. Updated
              terms will be posted on this page with a revised date. Your
              continued use of the App after changes constitutes acceptance of
              the new terms.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-3">
              9. Contact Information
            </h2>
            <p>
              If you have questions about these Terms, please contact us at{" "}
              <a
                href="mailto:nickyudu@gmail.com"
                className="text-blue-600 hover:text-blue-800 underline"
              >
                nickyudu@gmail.com
              </a>
              .
            </p>
          </section>
        </div>

        <div className="mt-12 pt-8 border-t border-gray-200 text-sm text-gray-500">
          <Link href="/privacy" className="text-blue-600 hover:text-blue-800">
            Privacy Policy
          </Link>
        </div>
      </div>
    </main>
  );
}
