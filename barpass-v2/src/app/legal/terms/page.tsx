export const metadata = { title: "Terms of Service — BarPass" };

export default function TermsOfServicePage() {
  return (
    <main className="mx-auto max-w-2xl px-6 py-16 text-white/80">
      <h1 className="text-2xl font-bold text-white">Terms of Service</h1>
      <p className="mt-2 text-sm text-white/40">Last updated: September 20, 2026</p>

      <Section title="1. Acceptance">
        By creating a BarPass account or using the app, you agree to these terms. If you don&apos;t agree,
        don&apos;t use BarPass.
      </Section>

      <Section title="2. Eligibility — 21+">
        BarPass is for users 21 years of age or older only. By using the app you confirm you meet this
        requirement. We verify date of birth at signup; providing false information to bypass this is a
        violation of these terms and may result in account termination.
      </Section>

      <Section title="3. What BarPass provides">
        BarPass lets you discover Miami venues, purchase Skip the Line passes, reserve VIP tables, buy
        event tickets, and order drinks. Skip the Line passes grant <strong>priority</strong> entry
        consideration — they are not a guarantee of entry. Venues retain the right to refuse entry per
        their own policies (capacity, dress code, ID verification, intoxication, etc.), independent of
        BarPass.
      </Section>

      <Section title="4. Payments &amp; refunds">
        <ul className="list-disc space-y-2 pl-5">
          <li>Payments are processed by Stripe. By purchasing, you authorize the charge shown at checkout.</li>
          <li>Skip the Line passes, tickets, and table deposits are generally non-refundable once
            issued, except where required by law or at the venue&apos;s discretion.</li>
          <li>If a venue is closed or an event is cancelled, we&apos;ll refund the affected purchase.</li>
          <li>Passes and tickets expire at the time shown in the app and cannot be redeemed after
            expiration.</li>
        </ul>
      </Section>

      <Section title="5. Your account">
        You&apos;re responsible for keeping your login credentials secure and for all activity under your
        account. Tell us immediately if you suspect unauthorized access.
      </Section>

      <Section title="6. Prohibited conduct">
        <ul className="list-disc space-y-2 pl-5">
          <li>Reselling, screenshotting-and-sharing, or duplicating passes to gain unauthorized entry.</li>
          <li>Providing false age or identity information.</li>
          <li>Using the app to harass venues, staff, or other users.</li>
          <li>Posting photos or videos that break the content rules in section 7.</li>
          <li>Attempting to reverse-engineer, scrape, or interfere with BarPass&apos;s systems.</li>
        </ul>
        Violating these may result in suspension or termination of your account without refund.
      </Section>

      <Section title="7. Content you post">
        <p>
          BarPass lets you post photos and videos from inside a venue. They are{" "}
          <strong>public</strong>: anyone using the app can see them, including people who are not
          signed in. You keep what you post and you are responsible for it. By posting, you confirm you
          have the right to post it and you grant BarPass permission to show it in the app — as a story
          for the night it was posted, and in that venue&apos;s photo archive afterwards.
        </p>

        <p className="mt-3">
          <strong>There is zero tolerance for objectionable content and abusive users.</strong> Do not
          post:
        </p>
        <ul className="mt-2 list-disc space-y-2 pl-5">
          <li>Nudity, sexual content, or sexually suggestive content involving any person.</li>
          <li>Content that depicts or promotes violence, self-harm, or illegal activity.</li>
          <li>Hate speech, harassment, threats, or content that targets a person or group.</li>
          <li>Any content showing a minor, and any content that sexualizes a minor in any way.</li>
          <li>A person who asked you not to post them, or content posted to expose, locate, or
            humiliate someone.</li>
        </ul>

        <p className="mt-3">
          Anyone can report a photo or video from the story viewer, and you can stop seeing everything
          posted by whoever put it there. Content reported for the most serious reasons — someone
          appearing without their consent, sexual content, or a minor — is hidden from everyone the
          moment it is reported, before anyone reviews it.{" "}
          <strong>We review every report and act on it within 24 hours.</strong> We may remove any
          content and suspend or permanently terminate the account that posted it, without notice and
          without refunding wallet balance or unused passes. Content that appears to sexually exploit a
          minor is reported to the National Center for Missing &amp; Exploited Children and to law
          enforcement, as US law requires.
        </p>

        <p className="mt-3">
          Posting is a condition, not a right: by posting you accept these rules, and if you don&apos;t
          accept them, don&apos;t post. To report content or an account from outside the app, write to{" "}
          <a className="text-amber-400 underline" href="mailto:support@barpass.app">support@barpass.app</a>.
        </p>
      </Section>

      <Section title="8. Limitation of liability">
        BarPass connects you with independently-operated venues. We are not responsible for the conduct,
        safety, service quality, or policies of any venue. To the maximum extent permitted by law,
        BarPass is not liable for indirect, incidental, or consequential damages arising from your use of
        the app or a venue visit.
      </Section>

      <Section title="9. Termination">
        You can delete your account at any time. We may suspend or terminate accounts that violate these
        terms.
      </Section>

      <Section title="10. Governing law">
        These terms are governed by the laws of the State of Florida, United States, without regard to
        conflict-of-law principles.
      </Section>

      <Section title="11. Changes">
        We may update these terms from time to time. Continued use of BarPass after changes take effect
        constitutes acceptance of the updated terms.
      </Section>

      <Section title="12. Contact">
        Questions about these terms: <a className="text-amber-400 underline" href="mailto:support@barpass.app">support@barpass.app</a>
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
