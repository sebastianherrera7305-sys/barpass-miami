import Link from "next/link";
import { CONTACT_LAST_UPDATED, SUPPORT_EMAIL, supportMailto } from "./support";

/**
 * The public contact page — App Review Guideline 1.2 asks for published
 * contact information, and App Store Connect asks for a Support URL.
 *
 * THREE RULES THIS PAGE IS BUILT AROUND
 * 1. A reviewer opens it from a link, logged out, possibly on a bad
 *    connection. So: a server component, no "use client", no fetch, no
 *    state. Everything below renders as HTML with JavaScript turned off.
 * 2. Every claim about what happens after a report is checked against
 *    `supabase/media_moderation.sql`, not against what would sound good.
 *    The one thing this page must never do is publish a response time
 *    nobody is on call to honour — see §4.
 * 3. Same layout, type scale and tone as `legal/terms` and
 *    `legal/privacy`, including the local `Section` helper, so the three
 *    read as one document set.
 */
export const metadata = {
  // The root layout's title template appends " · BarPass", so the product
  // name is not repeated here the way the legal pages repeat it.
  title: "Contact & content reports",
  description:
    "How to report a photo, a video or a person on BarPass, what happens after you report, and how to reach a human.",
};

const REPORT_SUBJECT = "Content report";
const REPORT_BODY =
  "Which venue:\nWhich night (date, roughly what time):\nWhat the photo or video shows:\nAre you in it? (yes / no):";

export default function ContactPage() {
  return (
    <main className="mx-auto max-w-2xl px-6 py-16 text-white/80">
      <h1 className="text-2xl font-bold text-white">Contact &amp; content reports</h1>
      <p className="mt-2 text-sm text-white/40">Last updated: {CONTACT_LAST_UPDATED}</p>

      <p className="mt-6 text-sm leading-relaxed text-white/70">
        BarPass lets people post photos and videos from inside a venue, and those posts are public
        inside the app. This page is how you get one taken down, how you reach a person, and what
        actually happens after you report something. You do not need a BarPass account to use it.
      </p>

      <p className="mt-6 rounded-lg border border-white/10 bg-white/[0.03] p-4 text-sm leading-relaxed">
        <strong className="text-white">Write to us:</strong>{" "}
        <a className="text-amber-400 underline" href={supportMailto("BarPass")}>
          {SUPPORT_EMAIL}
        </a>
        <br />
        One address for reports, venues, press, privacy and everything else. One person reads it.
      </p>

      <Section title="1. Report a photo or video from the app">
        This is the fastest way, because it reaches the content itself rather than a description of
        it.
        <ul className="mt-2 list-disc space-y-2 pl-5">
          <li>Open the story, then tap <strong className="text-white">•••</strong> at the top of
            the screen, next to the close button.</li>
          <li>Choose <strong className="text-white">Report</strong> and pick the reason: someone is
            in it who did not agree to be, sexual content, a minor, violence, hate, harassment,
            something illegal, spam, wrong venue, or other.</li>
          <li>There is no free-text box, on purpose. The category is what lets us act on a report
            without reading a note written to whoever reviews it.</li>
        </ul>
        <p className="mt-2">
          You never need to know who posted it. The app does not show that, and we do not ask you
          for it.
        </p>
      </Section>

      <Section title="2. Report by email — no account, and for photos of you">
        If you do not have the app, cannot open it, or the photo is of{" "}
        <strong className="text-white">you</strong>, write to{" "}
        <a
          className="text-amber-400 underline"
          href={supportMailto(REPORT_SUBJECT, REPORT_BODY)}
        >
          {SUPPORT_EMAIL}
        </a>{" "}
        with the subject <strong className="text-white">{REPORT_SUBJECT}</strong>.
        <p className="mt-2">Tell us, as best you can:</p>
        <ul className="mt-2 list-disc space-y-2 pl-5">
          <li>which venue, and which night;</li>
          <li>what the photo or video shows;</li>
          <li>whether you are the person in it;</li>
          <li>a screenshot or a link, if you have one.</li>
        </ul>
        <p className="mt-2">
          &quot;I am in this and I did not agree to it&quot; is a complete reason. You do not have to
          justify it, and it is treated as one of the most serious categories we have.
        </p>
      </Section>

      <Section title="3. What happens after you report">
        <ul className="list-disc space-y-2 pl-5">
          <li>The most serious categories — a person who did not consent, sexual content, anything
            involving a minor — take the content down <strong className="text-white">immediately</strong>,
            before any person has looked at it. The rest come down once enough separate people
            report them.</li>
          <li>Taking it down is not deleting it. The file is kept out of sight so that a person can
            then decide: remove it for good, or put it back if the report was wrong.</li>
          <li>Being reported is not by itself a punishment for whoever posted it. Only a human
            decision does anything lasting to an account.</li>
          <li>Reports a human judges to be wrong stop counting, so this cannot be used to take down
            someone&apos;s photo on demand.</li>
          <li>We can remove any content and suspend or permanently terminate the account that
            posted it. See the <Link className="text-amber-400 underline" href="/legal/terms">Terms of Service</Link>.</li>
        </ul>
      </Section>

      <Section title="4. How fast — honestly">
        The automatic part above does not wait for us: it happens the moment the report is filed,
        at any hour.
        <p className="mt-2">
          The human part is one small team. Today nothing alerts a person when a report arrives —
          no page, no push — so a report sits in the review queue until someone opens it. That is
          the truth, and it is why there is no response time promised on this page:{" "}
          <strong className="text-white">
            we are not publishing a deadline we are not yet staffed to meet.
          </strong>{" "}
          When a report can reach a person the moment it is filed, this paragraph will say so, with
          a number.
        </p>
        <p className="mt-2">
          Email to the address above is read by a person, not a bot, and answered in the order it
          arrives.
        </p>
      </Section>

      <Section title="5. If someone is in danger">
        Nothing on this page is monitored in real time, and BarPass is not an emergency service. If
        someone is in immediate danger, call <strong className="text-white">911</strong> in the
        United States, or your local emergency number.
        <p className="mt-2">
          Content that sexually exploits a minor is removed and reported to the National Center for
          Missing &amp; Exploited Children and to law enforcement.
        </p>
      </Section>

      <Section title="6. Not seeing someone again">
        The same <strong className="text-white">•••</strong> menu in the story viewer has{" "}
        <em>do not show me anything from whoever posted this</em>. It takes effect immediately,
        covers everything that person has posted and will post, and they are not told.
        <p className="mt-2">
          It is reversible. If you cannot find the option to undo it in your version of the app,
          email us and we will clear it for you.
        </p>
      </Section>

      <Section title="7. Venues">
        There is no self-serve sign-up for venue owners — we link venue accounts by hand. Write to{" "}
        <a
          className="text-amber-400 underline"
          href={supportMailto("Venue", "Venue name:\nAddress:\nYour role at the venue:")}
        >
          {SUPPORT_EMAIL}
        </a>{" "}
        from an address the venue actually uses, with the venue name and address, and tell us what
        you need:
        <ul className="mt-2 list-disc space-y-2 pl-5">
          <li>access to the venue dashboard;</li>
          <li>a correction to your listing — hours, address, photos, anything wrong;</li>
          <li>a photo or video taken at your venue that you want removed;</li>
          <li>to not be listed at all.</li>
        </ul>
      </Section>

      <Section title="8. Press, partnerships, everything else">
        Same address:{" "}
        <a className="text-amber-400 underline" href={supportMailto("Press")}>
          {SUPPORT_EMAIL}
        </a>
        . We would rather answer one mailbox slowly than four badly.
      </Section>

      <Section title="9. Privacy, your data, and the legal documents">
        A copy of your data, a correction, or deleting your account and its data: same address, and
        we will tell you what is kept and why.
        <p className="mt-2">
          <Link className="text-amber-400 underline" href="/legal/terms">Terms of Service</Link>
          {" · "}
          <Link className="text-amber-400 underline" href="/legal/privacy">Privacy Policy</Link>
        </p>
        <p className="mt-2 text-white/50">
          BarPass is operated from Miami, Florida, United States. Our Terms are governed by Florida
          law.
        </p>
      </Section>
    </main>
  );
}

/** Same helper, same classes, as `legal/terms` and `legal/privacy`. */
function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mt-8">
      <h2 className="text-lg font-semibold text-white">{title}</h2>
      <div className="mt-2 text-sm leading-relaxed text-white/70">{children}</div>
    </section>
  );
}
