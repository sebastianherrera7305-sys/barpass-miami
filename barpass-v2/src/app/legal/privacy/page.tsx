export const metadata = { title: "Privacy Policy — BarPass" };

export default function PrivacyPolicyPage() {
  return (
    <main className="mx-auto max-w-2xl px-6 py-16 text-white/80">
      <h1 className="text-2xl font-bold text-white">Privacy Policy</h1>
      <p className="mt-2 text-sm text-white/40">Last updated: July 14, 2026</p>

      <Section title="1. Who we are">
        BarPass (&quot;we&quot;, &quot;our&quot;, &quot;the app&quot;) is a nightlife access app for Miami — Skip the Line
        passes, VIP tables, event tickets, and drink ordering. This policy explains what we collect,
        why, and what choices you have.
      </Section>

      <Section title="2. Information we collect">
        <ul className="list-disc space-y-2 pl-5">
          <li><strong>Account info:</strong> email and display name, to create and secure your account.</li>
          <li><strong>Date of birth:</strong> collected once to verify you&apos;re 21+. We store only the
            date, never re-ask, and never share it.</li>
          <li><strong>Location:</strong> used to show venues near you. Never sold, never linked to your
            identity in storage.</li>
          <li><strong>Payment info:</strong> card numbers are sent directly to Stripe, our payment
            processor — they never touch our servers. We store the transaction result (amount, last 4
            digits, status), not the card itself.</li>
          <li><strong>Orders &amp; passes:</strong> what you buy, the venue, quantity, and whether a pass
            has been redeemed at the door.</li>
          <li><strong>Photos:</strong> only if you choose to save a QR pass or set a profile picture.</li>
          <li><strong>Music listening data (optional):</strong> if you connect Apple Music or Spotify for
            Music Intelligence features, your top artists/genres are processed on your device to build
            your Hype Score. This data is not uploaded to our servers.</li>
        </ul>
      </Section>

      <Section title="3. How we use your information">
        To operate your account, process payments, show relevant venues and events, validate passes at
        the door, and improve the app. We do not sell your personal data to third parties.
      </Section>

      <Section title="4. Who we share data with">
        <ul className="list-disc space-y-2 pl-5">
          <li><strong>Supabase</strong> — hosts our database and authentication.</li>
          <li><strong>Stripe</strong> — processes card payments (PCI-compliant; we never see full card numbers).</li>
          <li><strong>Google Places</strong> — supplies venue data (hours, photos, ratings) we display.</li>
          <li><strong>Apple Music / Spotify</strong> — only if you connect them, for Music Intelligence.</li>
          <li>Venue staff, at the door, see only what&apos;s needed to validate your pass: name of pass,
            quantity, and venue — never your payment details.</li>
        </ul>
      </Section>

      <Section title="5. Your rights">
        You can request a copy of your data, ask us to correct it, or delete your account and associated
        data at any time by contacting us at the email below. Deleting your account removes your profile
        and favorites; completed orders are retained as required for financial recordkeeping.
      </Section>

      <Section title="6. Data retention">
        We keep account data while your account is active, and order/pass records for as long as
        required for accounting and dispute resolution, typically up to 7 years.
      </Section>

      <Section title="7. Age requirement">
        BarPass is intended for users 21 years of age or older. We verify date of birth at signup and do
        not knowingly collect data from anyone under 21.
      </Section>

      <Section title="8. Changes to this policy">
        We&apos;ll update the &quot;Last updated&quot; date above whenever this policy changes materially, and
        notify you in-app for significant changes.
      </Section>

      <Section title="9. Contact">
        Questions about this policy: <a className="text-amber-400 underline" href="mailto:privacy@barpass.app">privacy@barpass.app</a>
      </Section>
    </main>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mt-8">
      <h2 className="text-lg font-semibold text-white">{title}</h2>
      <div className="mt-2 text-sm leading-relaxed text-white/70">{children}</div>
    </section>
  );
}
