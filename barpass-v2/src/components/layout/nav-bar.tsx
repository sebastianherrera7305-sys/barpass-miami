"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Flame, Map, Sparkles, User } from "lucide-react";
import { cn } from "@/lib/utils";

const NAV_ITEMS = [
  { href: "/", label: "Tonight", icon: Flame },
  { href: "/map", label: "Map", icon: Map },
  { href: "/concierge", label: "Concierge", icon: Sparkles },
  { href: "/profile", label: "Me", icon: User },
] as const;

/**
 * App-wide navigation.
 * Bottom tab bar on mobile (thumb-first, like the iOS app),
 * top bar on desktop.
 */
export function NavBar() {
  const pathname = usePathname();

  return (
    <>
      {/* Desktop top bar */}
      <header className="sticky top-0 z-50 hidden border-b border-border-subtle bg-black/80 backdrop-blur-xl md:block">
        <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-6">
          <Link href="/" className="text-lg font-black tracking-tight">
            Bar<span className="text-amber-brand">Pass</span>
          </Link>
          <nav className="flex items-center gap-1">
            {NAV_ITEMS.map(({ href, label, icon: Icon }) => {
              const active =
                href === "/" ? pathname === "/" : pathname.startsWith(href);
              return (
                <Link
                  key={href}
                  href={href}
                  className={cn(
                    "flex items-center gap-2 rounded-full px-4 py-2 text-sm font-medium transition-colors",
                    active
                      ? "bg-amber-brand/10 text-amber-brand"
                      : "text-text-secondary hover:text-white",
                  )}
                >
                  <Icon className="h-4 w-4" />
                  {label}
                </Link>
              );
            })}
          </nav>
        </div>
      </header>

      {/* Mobile bottom tab bar */}
      <nav className="fixed inset-x-0 bottom-0 z-50 border-t border-border-subtle bg-black/85 backdrop-blur-xl md:hidden">
        <div className="flex items-center justify-around pb-[env(safe-area-inset-bottom)] pt-2">
          {NAV_ITEMS.map(({ href, label, icon: Icon }) => {
            const active =
              href === "/" ? pathname === "/" : pathname.startsWith(href);
            return (
              <Link
                key={href}
                href={href}
                className={cn(
                  "flex flex-col items-center gap-1 px-4 pb-2 text-[10px] font-semibold",
                  active ? "text-amber-brand" : "text-text-tertiary",
                )}
              >
                <Icon className="h-5 w-5" />
                {label}
              </Link>
            );
          })}
        </div>
      </nav>
    </>
  );
}
