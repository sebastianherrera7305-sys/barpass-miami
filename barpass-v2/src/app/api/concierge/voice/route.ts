import { NextResponse } from "next/server";

/**
 * Voice-to-text para Remy — recibe un audio del cliente (m4a / mp3 / wav /
 * cualquier formato que Whisper acepte) y devuelve el transcript. El
 * cliente después manda ese transcript al endpoint normal /api/concierge
 * como prompt del usuario.
 *
 * Modelo: `whisper-large-v3-turbo` — en Groq corre en <1s para audios
 * cortos (≤30s), suficiente para "oye Remy, qué hay bueno esta noche".
 * El modelo auto-detecta idioma (es/en/pt/más de 90) — por eso no
 * forzamos `language` en el request, dejamos que lo infiera.
 *
 * Owner Build 142, 2026-10-28: "lo podemos hacer hablar como ChatGPT
 * para que la gente lo convierta en su agente de salidas" — voz es el
 * primer paso para que Remy deje de ser un form y empiece a ser un
 * asistente de verdad.
 */

export const dynamic = "force-dynamic";
export const maxDuration = 30;

const GROQ_TRANSCRIBE_URL = "https://api.groq.com/openai/v1/audio/transcriptions";
// Groq catalog verificado contra console.groq.com/the-models (2026-10-28):
// la cuenta tiene whisper-large-v3 y whisper-large-v3-turbo. Turbo es ~4×
// más rápido con la misma precisión práctica para chat corto.
const WHISPER_MODEL = "whisper-large-v3-turbo";

export async function POST(request: Request) {
  if (!process.env.GROQ_API_KEY) {
    return NextResponse.json(
      { error: "voice_not_configured", detail: "GROQ_API_KEY no está seteada en el servidor." },
      { status: 503 },
    );
  }

  let incoming: FormData;
  try {
    incoming = await request.formData();
  } catch {
    return NextResponse.json(
      { error: "bad_request", detail: "Se esperaba multipart/form-data con el campo 'file'." },
      { status: 400 },
    );
  }

  const file = incoming.get("file");
  if (!(file instanceof Blob)) {
    return NextResponse.json(
      { error: "missing_file", detail: "Falta el campo 'file' con el audio." },
      { status: 400 },
    );
  }

  // Groq Whisper admite hasta 25MB. Un audio m4a de 30s pesa ~250KB, así
  // que el límite es muy generoso para voz de chat. Rechazamos arriba de
  // 25MB con un error claro en vez de dejar que Groq devuelva 413.
  if (file.size > 25 * 1024 * 1024) {
    return NextResponse.json(
      { error: "audio_too_large", detail: "El audio supera los 25MB. Grabá menos de 30s." },
      { status: 413 },
    );
  }

  const upstream = new FormData();
  // Groq necesita que el archivo tenga nombre con extensión para inferir el
  // mime type; usamos el nombre que mandó el cliente o un fallback .m4a.
  const filename = (file instanceof File && file.name) || "audio.m4a";
  upstream.append("file", file, filename);
  upstream.append("model", WHISPER_MODEL);
  // response_format=text devuelve sólo el string plano — más chico que el
  // JSON con metadata que no usamos; parseo del lado nuestro es trivial.
  upstream.append("response_format", "text");

  const started = Date.now();
  let r: Response;
  try {
    r = await fetch(GROQ_TRANSCRIBE_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${process.env.GROQ_API_KEY}`,
      },
      body: upstream,
      // maxDuration es 30s; cortamos antes para devolver un error limpio.
      signal: AbortSignal.timeout(25_000),
    });
  } catch (err) {
    console.error("Concierge voice upstream error", err);
    return NextResponse.json(
      { error: "transcribe_unreachable", detail: "No se pudo contactar al servicio de transcripción." },
      { status: 502 },
    );
  }

  if (!r.ok) {
    const detail = await r.text().catch(() => "");
    console.error(`Concierge voice failed: HTTP ${r.status}`, detail.slice(0, 500));
    return NextResponse.json(
      { error: "transcribe_failed", status: r.status, detail: detail.slice(0, 500) },
      { status: 500 },
    );
  }

  const text = (await r.text()).trim();
  const latencyMs = Date.now() - started;

  return NextResponse.json(
    { text, latencyMs, model: WHISPER_MODEL },
    {
      headers: {
        // Reusa el patrón del endpoint principal: provider + latency en
        // headers para medir con un curl sin tocar código.
        "X-BP-Provider": "groq",
        "X-BP-Model": WHISPER_MODEL,
        "X-BP-Latency-Ms": String(latencyMs),
      },
    },
  );
}
