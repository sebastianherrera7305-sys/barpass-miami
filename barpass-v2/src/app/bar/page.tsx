"use client";

import dynamic from "next/dynamic";

/**
 * La barra no se renderiza en el servidor: su primer render depende de lo que
 * esta tablet tenga guardado en localStorage (el local y su secreto), y un
 * HTML del servidor que no puede saberlo sólo produce un parpadeo de la
 * pantalla de configuración sobre una tablet ya configurada.
 */
const BarScreen = dynamic(
  () => import("@/features/tabs/components/bar-screen").then((m) => m.BarScreen),
  { ssr: false, loading: () => <main className="h-dvh" /> },
);

export default function BarPage() {
  return <BarScreen />;
}
