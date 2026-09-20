"use client";

import { useCallback, useSyncExternalStore } from "react";

/**
 * Whether previews render blurred, remembered per browser.
 *
 * A moderator opens this page dozens of times and should not be ambushed by
 * the worst thing anyone posted last night every single time. The blur is a
 * shield they control, not a hiding of evidence — one tap reveals any
 * single item, and the default is off because the job is to look.
 *
 * useSyncExternalStore rather than useState + useEffect: localStorage is an
 * external store that does not exist during the server render, and reading
 * it from an effect is both a hydration mismatch and a cascading render
 * (react-hooks/set-state-in-effect, which this project enforces).
 * getServerSnapshot answers "not blurred" for the prerender, which is safe
 * because no media is on screen until the queue has loaded, long after
 * hydration.
 */

const KEY = "bp_moderation_blur";
const listeners = new Set<() => void>();

// Private mode and blocked site data make localStorage throw. Falling back
// to memory keeps the toggle working for the session instead of silently
// doing nothing when someone clicks it.
let memoryValue = false;
let storageUsable = true;

function subscribe(onChange: () => void): () => void {
  listeners.add(onChange);
  return () => {
    listeners.delete(onChange);
  };
}

function getSnapshot(): boolean {
  if (!storageUsable) return memoryValue;
  try {
    return window.localStorage.getItem(KEY) === "1";
  } catch {
    storageUsable = false;
    return memoryValue;
  }
}

function getServerSnapshot(): boolean {
  return false;
}

export function useBlurPreference(): [boolean, () => void] {
  const blurred = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);

  const toggle = useCallback(() => {
    const next = !blurred;
    memoryValue = next;
    try {
      window.localStorage.setItem(KEY, next ? "1" : "0");
    } catch {
      storageUsable = false;
    }
    for (const listener of listeners) listener();
  }, [blurred]);

  return [blurred, toggle];
}
