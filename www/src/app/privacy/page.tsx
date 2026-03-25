import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy Policy — Token Wise",
  description:
    "Privacy Policy for Token Wise, the macOS AI token usage tracker.",
};

export default function Privacy() {
  return (
    <main className="min-h-screen bg-gray-50 text-gray-800">
      <div className="max-w-3xl mx-auto px-6 py-16">
        <Link
          href="/"
          className="text-blue-600 hover:text-blue-800 text-sm mb-8 inline-block"
        >
          &larr; Back to Home
        </Link>

        <h1 className="text-3xl font-bold mb-2">Privacy Policy</h1>
        <p className="text-sm text-gray-500 mb-10">
          Last updated: March 25, 2026
        </p>

        <div className="space-y-8 leading-relaxed">
          <section>
            <h2 className="text-xl font-semibold mb-3">Overview</h2>
            <p>
              Token Wise is designed with privacy as a core principle. The App
              operates entirely offline on your Mac — no data is collected,
              transmitted, or stored on external servers.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-3">
              1. Information We Collect
            </h2>
            <p>
              <strong>We do not collect any personal information.</strong> Token
              Wise runs entirely on your local machine. Specifically:
            </p>
            <ul className="list-disc list-inside mt-2 space-y-1">
              <li>No account creation or sign-up is required</li>
              <li>No personal data is collected or transmitted</li>
              <li>No analytics or telemetry data is sent</li>
              <li>No cookies or tracking technologies are used</li>
              <li>
                No usage data leaves your device
              </li>
            </ul>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-3">
              2. Data Stored Locally
            </h2>
            <p>
              The App stores the following data locally on your Mac to provide
              its functionality:
            </p>
            <ul className="list-disc list-inside mt-2 space-y-1">
              <li>
                AI API request metadata (token counts, model names, timestamps)
              </li>
              <li>Cost calculations based on provider pricing</li>
              <li>Project and session grouping information</li>
              <li>Your app preferences and settings</li>
            </ul>
            <p className="mt-2">
              All this data is stored in a local database on your device and is
              never transmitted to any external server.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-3">
              3. Third-Party Services
            </h2>
            <p>
              Token Wise does not integrate with any third-party analytics,
              advertising, or tracking services. The App does not share your
              data with any third parties.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-3">4. Data Security</h2>
            <p>
              Since all data remains on your local machine, your data is
              protected by your macOS system security, including FileVault
              encryption if enabled. We recommend keeping your operating system
              up to date.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-3">5. Data Deletion</h2>
            <p>
              You can delete all data stored by Token Wise at any time by
              uninstalling the App or by deleting its local data directory. No
              data remains on any external server because none was ever sent.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-3">
              6. Children&apos;s Privacy
            </h2>
            <p>
              Token Wise does not collect any personal information from anyone,
              including children under the age of 13.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-3">
              7. Changes to This Policy
            </h2>
            <p>
              We may update this Privacy Policy from time to time. Any changes
              will be posted on this page with a revised effective date. Your
              continued use of the App after changes constitutes acceptance of
              the updated policy.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold mb-3">8. Contact Us</h2>
            <p>
              If you have questions about this Privacy Policy, please contact us
              at{" "}
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
          <Link
            href="/terms-of-use"
            className="text-blue-600 hover:text-blue-800"
          >
            Terms of Use
          </Link>
        </div>
      </div>
    </main>
  );
}
