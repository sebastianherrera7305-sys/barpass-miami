"use client";

import type { OwnerVenue } from "./types";

/**
 * "This is your venue as BarPass shows it." The first thing a bar owner opens
 * the dashboard for, and the thing that decides whether they trust the rest.
 *
 * Nothing on this panel is editable: `venues` has a public SELECT policy and
 * NO owner write policy, so an edit form here would silently do nothing. What
 * it does instead is show exactly what we hold, name what we're missing, and
 * say where corrections go. A blank is shown as a blank — never as a plausible
 * guess (the fabricated `music_genres` incident is why this rule exists).
 */
export function ListingPanel({ venue }: { venue: OwnerVenue }) {
  const missing = missingFields(venue);

  return (
    <section className="flex flex-col gap-4 rounded-xl border border-white/10 bg-white/5 p-4">
      <header className="flex items-start gap-4">
        {venue.imageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={venue.imageUrl}
            alt={`${venue.name} as shown in BarPass`}
            className="h-20 w-20 rounded-lg object-cover"
          />
        ) : (
          <div className="flex h-20 w-20 items-center justify-center rounded-lg border border-dashed border-white/20 text-center text-[10px] text-white/40">
            No photo
          </div>
        )}
        <div className="min-w-0">
          <h2 className="text-lg font-bold text-white">{venue.name}</h2>
          <p className="text-sm text-white/50">
            {venue.type.replace(/_/g, " ")}
            {venue.neighborhood ? ` · ${venue.neighborhood}` : ""}
            {venue.city ? ` · ${venue.city}` : ""}
          </p>
          {venue.address && <p className="text-sm text-white/40">{venue.address}</p>}
        </div>
      </header>

      {!venue.visibility.listed && (
        <p className="rounded-lg border border-red-400/40 bg-red-400/10 p-3 text-sm text-red-200">
          <strong>Not currently shown in BarPass.</strong> {venue.visibility.reason} If that&apos;s
          wrong, reply to your BarPass contact — it is a one-line fix on our side.
        </p>
      )}

      <div className="grid gap-3 sm:grid-cols-2">
        <Fact label="Phone" value={venue.phone} />
        <Fact label="Website" value={venue.website} />
        <Fact label="Instagram" value={venue.instagramHandle} />
        <Fact label="Age policy" value={venue.agePolicy} />
        <Fact label="Dress code" value={venue.dressCode} />
        <Fact label="Parking" value={venue.parking} />
        <Fact
          label="Cover"
          value={
            venue.coverMen === null && venue.coverWomen === null
              ? null
              : `men ${fmtMoney(venue.coverMen)} · women ${fmtMoney(venue.coverWomen)}`
          }
        />
        <Fact label="Typical spend" value={venue.avgSpend === null ? null : `$${venue.avgSpend}`} />
        <Fact label="Happy hour until" value={venue.happyHourUntil} />
        <Fact label="Music" value={venue.musicGenres.length ? venue.musicGenres.join(", ") : null} />
      </div>

      <HoursTable venue={venue} />
      <DrinksList venue={venue} />

      {missing.length > 0 && (
        <p className="text-xs text-white/40">
          BarPass has no data for: {missing.join(", ")}. We leave these blank rather than guess —
          send us the real values and they go in.
        </p>
      )}
      {venue.googleSyncedAt && (
        <p className="text-xs text-white/30">
          Google data last refreshed {new Date(venue.googleSyncedAt).toLocaleDateString()}.
        </p>
      )}
    </section>
  );
}

function HoursTable({ venue }: { venue: OwnerVenue }) {
  if (!venue.hours) {
    return (
      <div>
        <h3 className="mb-1 text-sm font-bold text-white/70">Hours</h3>
        <p className="text-sm text-white/40">
          {venue.openTime && venue.closeTime
            ? `We only hold one pair of times for you — ${venue.openTime} to ${venue.closeTime}, applied to every day. Send us your real weekly hours.`
            : "We have no hours for you. The app can't show you as open until we do."}
        </p>
      </div>
    );
  }
  return (
    <div>
      <h3 className="mb-1 text-sm font-bold text-white/70">Hours BarPass shows</h3>
      <ul className="grid gap-1 sm:grid-cols-2">
        {venue.hours.map((d) => (
          <li key={d.day} className="flex justify-between text-sm">
            <span className="text-white/50">{d.label}</span>
            <span className={d.closed ? "text-white/30" : "text-white"}>
              {d.closed
                ? "Closed"
                : d.periods.map((p) => `${p.open}–${p.close}`).join(", ")}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}

function DrinksList({ venue }: { venue: OwnerVenue }) {
  return (
    <div>
      <h3 className="mb-1 text-sm font-bold text-white/70">Drink prices BarPass shows</h3>
      {venue.drinks.length === 0 ? (
        <p className="text-sm text-white/40">
          None. Nothing is shown rather than a made-up price — send a menu link and we&apos;ll read
          it off that.
        </p>
      ) : (
        <>
          <ul className="space-y-1">
            {venue.drinks.map((d) => (
              <li key={d.name} className="flex justify-between text-sm">
                <span className="text-white/70">
                  {d.emoji} {d.name}
                </span>
                <span className="text-white">${d.price}</span>
              </li>
            ))}
          </ul>
          {venue.drinksSource && (
            <p className="mt-1 text-xs text-white/30">
              Source: {venue.drinksSource.url ?? "on file"}
              {venue.drinksSource.date ? ` (${venue.drinksSource.date})` : ""}
            </p>
          )}
        </>
      )}
    </div>
  );
}

function Fact({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="text-sm">
      <p className="text-xs text-white/40">{label}</p>
      <p className={value ? "text-white" : "text-white/30"}>{value ?? "Not on file"}</p>
    </div>
  );
}

function fmtMoney(v: number | null): string {
  return v === null ? "—" : `$${v}`;
}

function missingFields(venue: OwnerVenue): string[] {
  const out: string[] = [];
  if (!venue.imageUrl) out.push("photo");
  if (!venue.hours) out.push("weekly hours");
  if (!venue.phone) out.push("phone");
  if (!venue.website) out.push("website");
  if (venue.drinks.length === 0) out.push("drink prices");
  if (venue.avgSpend === null) out.push("typical spend");
  return out;
}
