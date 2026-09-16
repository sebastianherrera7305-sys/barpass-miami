"use client";

import { createClient } from "@/lib/supabase/client";
import { isSupabaseConfigured } from "@/lib/supabase/config";

/** Un ítem de la carta del local, tal como lo lee la tablet. */
export type MenuItem = {
  id: string;
  name: string;
  price: number | null;
  category: string;
};

/**
 * La carta del local, con la anon key. `venue_menu_items` es público de sólo
 * lectura a propósito (supabase/venue_menu_items.sql): una carta colgada en la
 * web del local no es un secreto, y leerla acá evita mandar el service role a
 * una tablet que vive sobre la barra.
 */
export async function fetchVenueMenu(venueId: string): Promise<MenuItem[]> {
  if (!isSupabaseConfigured()) return [];
  const supabase = createClient();
  const { data, error } = await supabase
    .from("venue_menu_items")
    .select("id,name,price,category")
    .eq("venue_id", venueId)
    .order("category", { ascending: true })
    .order("name", { ascending: true })
    .limit(500);
  if (error) throw new Error(error.message);
  return (data ?? []) as MenuItem[];
}
