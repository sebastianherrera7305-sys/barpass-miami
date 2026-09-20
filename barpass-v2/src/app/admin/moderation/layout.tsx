import type { Metadata } from "next";

/**
 * Internal tool: keep it out of search results. This is a soft measure —
 * the real gate is the server-side moderator check — but a queue of
 * reported photos has no business being crawlable even as a login screen.
 */
export const metadata: Metadata = {
  title: "Moderation",
  robots: { index: false, follow: false, nocache: true },
};

export default function ModerationLayout({ children }: { children: React.ReactNode }) {
  return children;
}
