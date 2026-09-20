export const metadata = { title: "Privacy Policy — BarPass" };

export default function PrivacyPolicyPage() {
  return (
    <main className="mx-auto max-w-2xl px-6 py-16 text-white/80">
      <h1 className="text-2xl font-bold text-white">Privacy Policy</h1>
      <p className="mt-2 text-sm text-white/40">Last updated: September 20, 2026</p>

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
          <li><strong>Photos you keep to yourself:</strong> a QR pass you save, or a profile picture you
            set.</li>
          <li><strong>Photos and videos you post at a venue:</strong> the file, the venue, the time, and
            the account that posted it. These are public — section 3 explains exactly who can see them
            and for how long.</li>
          <li><strong>Reports you file:</strong> if you report a photo or video, we store which content
            you reported, the reason you picked from our list, and your account. There is no free-text
            field.</li>
          <li><strong>Music listening data (optional):</strong> if you connect Apple Music or Spotify for
            Music Intelligence features, your top artists/genres are processed on your device to build
            your Hype Score. This data is not uploaded to our servers.</li>
        </ul>
      </Section>

      <Section title="3. Photos and videos you post">
        <p>
          This is the part of BarPass with the most consequence for you, so it is spelled out rather
          than summarized.
        </p>
        <ul className="mt-2 list-disc space-y-2 pl-5">
          <li><strong>They are public.</strong> Anyone using the app can see what you post, including
            people who have no BarPass account and are not signed in. The file itself is served from a
            public address, so anyone who has that link can open it, in the app or outside it. Post
            accordingly.</li>
          <li><strong>Your name is not attached.</strong> We never show who posted a photo or video. A
            viewer sees the content, and a number that groups one person&apos;s posts inside one venue on
            one night — that number restarts every night and cannot be traced back to you.</li>
          <li><strong>We do store who posted it.</strong> Your account is linked to what you post in our
            database, where no other user and no app can read it. We keep that link so we can act on
            reports, remove content that breaks our Terms, and stop an account that keeps breaking them.
            Without it, a reported photo would be a photo nobody is accountable for.</li>
          <li><strong>How long they stay.</strong> A post is shown as a story until 6:00 AM local time at
            the venue — the end of the night it belongs to. After that it stops being a story, but it
            stays in that venue&apos;s photo archive in the app, with no end date. Nothing deletes it
            automatically.</li>
          <li><strong>If it is reported.</strong> Anyone signed in can report a photo or video from the
            story viewer. Reports
            are readable only by BarPass — the person who posted is never told who reported them, and
            reporters are never told who posted. Content reported for the most serious reasons is hidden
            from everyone the moment it is reported; the rest is hidden once enough people report it, or
            when we review it.</li>
          <li><strong>If it is removed.</strong> Removed content stops being shown in the app and its
            file stops being served. We keep an internal record of what was removed, who posted it, and
            why, so that our Terms can be enforced against an account that does it again.</li>
          <li><strong>Taking something down.</strong> Write to{" "}
            <a className="text-amber-400 underline" href="mailto:support@barpass.app">support@barpass.app</a>{" "}
            to have a photo or video removed — whether you posted it or you appear in it. Content you
            posted is not removed automatically when you delete your account.</li>
        </ul>
      </Section>

      <Section title="4. How we use your information">
        To operate your account, process payments, show relevant venues and events, validate passes at
        the door, moderate what people post, and improve the app. We do not sell your personal data to
        third parties.
      </Section>

      <Section title="5. Who we share data with">
        <ul className="list-disc space-y-2 pl-5">
          <li><strong>Supabase</strong> — hosts our database, our authentication, and the photo and video
            files people post. Posted files sit in a public bucket, which is what makes them reachable by
            anyone with the link (section 3).</li>
          <li><strong>Stripe</strong> — processes card payments (PCI-compliant; we never see full card numbers).</li>
          <li><strong>Google Places</strong> — supplies venue data (hours, photos, ratings) we display.</li>
          <li><strong>Apple Music / Spotify</strong> — only if you connect them, for Music Intelligence.</li>
          <li>Venue staff, at the door, see only what&apos;s needed to validate your pass: name of pass,
            quantity, and venue — never your payment details.</li>
          <li>Law enforcement, when the law requires it. Content that appears to sexually exploit a minor
            is reported to the National Center for Missing &amp; Exploited Children and to law
            enforcement.</li>
        </ul>
      </Section>

      <Section title="6. Your rights">
        You can request a copy of your data, ask us to correct it, or delete your account and associated
        data at any time by contacting us at the email below. Deleting your account removes your profile
        and favorites; completed orders are retained as required for financial recordkeeping, and photos
        and videos you posted stay up unless you ask us to remove them (section 3).
      </Section>

      <Section title="7. Data retention">
        We keep account data while your account is active, and order/pass records for as long as
        required for accounting and dispute resolution, typically up to 7 years. Photos and videos you
        post stay in the venue&apos;s archive with no end date unless you or we remove them. Reports and
        our record of moderation decisions are kept for as long as we need them to enforce our Terms.
      </Section>

      <Section title="8. Age requirement">
        BarPass is intended for users 21 years of age or older. We verify date of birth at signup and do
        not knowingly collect data from anyone under 21.
      </Section>

      <Section title="9. Changes to this policy">
        We&apos;ll update the &quot;Last updated&quot; date above whenever this policy changes materially, and
        notify you in-app for significant changes.
      </Section>

      <Section title="10. Contact">
        Questions about this policy, or a photo or video you want taken down:{" "}
        <a className="text-amber-400 underline" href="mailto:support@barpass.app">support@barpass.app</a>
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
