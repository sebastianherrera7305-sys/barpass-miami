import type { Metadata } from "next";
import { UserRound, Heart, Trophy, Bell } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

export const metadata: Metadata = { title: "Profile" };

/**
 * Profile placeholder — Supabase Auth wires in here.
 * Favorites, BPX rewards and notification preferences all live behind
 * this screen; each ships as its own feature module.
 */
export default function ProfilePage() {
  return (
    <div className="mx-auto max-w-2xl px-6 pt-12">
      <div className="text-center">
        <span className="mx-auto grid h-20 w-20 place-items-center rounded-full border border-border-strong bg-surface">
          <UserRound className="h-8 w-8 text-text-tertiary" />
        </span>
        <h1 className="mt-4 text-2xl font-black tracking-tight">
          Your BarPass
        </h1>
        <p className="mt-1 text-sm text-text-secondary">
          Sign in to save favorites, earn rewards and get your plans
          everywhere.
        </p>
      </div>

      <div className="mt-10 space-y-3">
        {[
          {
            icon: Heart,
            title: "Favorites",
            desc: "Save venues and build your personal map",
          },
          {
            icon: Trophy,
            title: "BPX Rewards",
            desc: "Earn points for check-ins, reviews and referrals",
          },
          {
            icon: Bell,
            title: "Night alerts",
            desc: "Know when your spots are trending or free entry",
          },
        ].map(({ icon: Icon, title, desc }) => (
          <Card
            key={title}
            className="flex items-center justify-between px-5 py-4"
          >
            <div className="flex items-center gap-4">
              <Icon className="h-5 w-5 text-amber-brand" />
              <div>
                <p className="text-sm font-bold">{title}</p>
                <p className="text-xs text-text-tertiary">{desc}</p>
              </div>
            </div>
            <Badge>Soon</Badge>
          </Card>
        ))}
      </div>
    </div>
  );
}
