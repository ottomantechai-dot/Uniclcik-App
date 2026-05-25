/**
 * POST /functions/v1/detect-items
 * Body: { "image_storage_path": "{user_uuid}/outfits/{filename}.jpg" }
 * JWT requerido. Descarga desde bucket closet-images, llama Gemini, recorta crops y los sube.
 *
 * Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GEMINI_API_KEY
 * Opcional: GEMINI_DETECT_MODEL (default gemini-2.5-flash)
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { encodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";
import { Image } from "https://deno.land/x/imagescript@1.2.17/mod.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const DETECT_PROMPT = `You are an expert fashion catalog AI. Analyze the provided outfit photo and identify EVERY distinct wearable item visible (shirts, t-shirts, blouses, jackets, blazers, coats, sweaters, dresses, jumpsuits, pants, jeans, skirts, shorts, shoes, sneakers, boots, ties, belts, hats, bags, watches, scarves, sunglasses).

For each item, return STRICT JSON in this exact format:
{
  "items": [
    {
      "name": "Short descriptive product name in English, max 6 words (e.g. 'Black Silk Tie with Pattern')",
      "category": "one of: tops | dresses_jumpsuits | pants_skirts | coats | shoes | accessories | bags | underwear",
      "bounding_box": { "x_min": 0.0, "y_min": 0.0, "x_max": 1.0, "y_max": 1.0 },
      "dominant_color": "hex color",
      "material_guess": "leather | cotton | denim | silk | wool | synthetic | unknown"
    }
  ]
}

Rules:
- Coordinates are normalized 0.0–1.0 relative to image dimensions.
- Bounding box must tightly enclose ONLY the visible portion of the garment.
- Skip skin, hair, background objects, props.
- Do not invent items not visible.
- Return ONLY the JSON, no markdown, no commentary.`;

type BBox = { x_min: number; y_min: number; x_max: number; y_max: number };
type GeminiItem = {
  name: string;
  category: string;
  bounding_box: BBox;
  dominant_color?: string;
  material_guess?: string;
};

function stripCodeFences(s: string): string {
  let t = s.trim();
  if (t.startsWith("```")) {
    t = t.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/m, "").trim();
  }
  return t;
}

/** iOS usa `uuid.uuidString.lowercased()` pero `auth()` puede devolver el UUID mezclando mayúsculas. */
function pathBelongsToUser(pathRaw: string, userIdRaw: string): boolean {
  const path = pathRaw.replace(/^\/+/, "").trim().toLowerCase();
  const uid = userIdRaw.replace(/^\/+/, "").trim().toLowerCase();
  return path.startsWith(uid + "/");
}

/** Une todo el texto usable de Gemini (útiles modelos «thinking» o varias parts). */
function extractGeminiTextPayload(j: unknown): string {
  const root = j as Record<string, unknown>;
  const feedback = root["promptFeedback"] as Record<string, unknown> | undefined;
  if (feedback?.["blockReason"]) {
    throw new Error(`Contenido bloqueado: ${String(feedback["blockReason"])}`);
  }
  const cands = root["candidates"] as Record<string, unknown>[] | undefined;
  if (!cands?.length) {
    const err = JSON.stringify(root).slice(0, 900);
    throw new Error(`Sin candidatos de Gemini (${err})`);
  }
  const cand0 = cands[0] ?? {};
  if (String(cand0["finishReason"] ?? "").includes("SAFETY")) {
    throw new Error("Gemini SAFETY finishReason");
  }
  const parts = (cand0["content"] as Record<string, unknown> | undefined)?.[
    "parts"
  ] as Record<string, unknown>[] | undefined;
  if (!parts?.length) throw new Error("Respuesta Gemini sin parts");
  let text = "";
  for (const p of parts) {
    const t = p["text"];
    if (typeof t === "string") text += t;
  }
  text = text.trim();
  if (!text) throw new Error("Gemini no devolvió texto parseable para JSON");
  return text;
}

async function geminiDetectJson(
  apiKey: string,
  model: string,
  mimeType: string,
  base64: string,
): Promise<{ items: GeminiItem[] }> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
  // REST oficial acepta `inline_data`; `inlineData` evita inconsistencias entre runtimes.
  const buildBody = (withThinkingBudgetZero: boolean) => ({
    contents: [{
      role: "user",
      parts: [
        { inlineData: { mimeType, data: base64 } },
        { text: DETECT_PROMPT },
      ],
    }],
    generationConfig: {
      temperature: 0.15,
      responseMimeType: "application/json",
      ...(withThinkingBudgetZero ? { thinkingConfig: { thinkingBudget: 0 } } : {}),
    },
  });

  async function requestOnce(withThinkingBudgetZero: boolean) {
    let res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(buildBody(withThinkingBudgetZero)),
    });
    if (!res.ok && withThinkingBudgetZero) {
      // Algunos modelos/versiones rechazan thinkingConfig; repetir sin él.
      res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(buildBody(false)),
      });
    }
    return res;
  }

  let res = await requestOnce(true);
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Gemini HTTP ${res.status}: ${errText.slice(0, 500)}`);
  }
  const j = await res.json();
  const rawText = extractGeminiTextPayload(j);
  let parsed: { items?: GeminiItem[] };
  try {
    parsed = JSON.parse(stripCodeFences(rawText)) as { items?: GeminiItem[] };
  } catch (e) {
    throw new Error(
      `JSON inválido de Gemini: ${String(e)} | fragmento=${rawText.slice(0, 400)}`,
    );
  }
  if (!parsed || typeof parsed !== "object") {
    throw new Error("Respuesta Gemini no es objeto JSON");
  }
  const itemsArr = parsed.items;
  return {
    items: Array.isArray(itemsArr)
      ? (itemsArr as GeminiItem[])
      : [],
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const apiKey = Deno.env.get("GEMINI_API_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!apiKey || !supabaseUrl || !serviceKey) {
      return new Response(
        JSON.stringify({ error: "Faltan secrets (GEMINI_API_KEY / Supabase)." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const jwt = auth.slice("Bearer ".length);

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
    if (userErr || !userData?.user?.id) {
      return new Response(JSON.stringify({ error: "Sesión inválida" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const userId = userData.user.id;

    const payload = await req.json() as {
      image_storage_path?: string;
    };
    const path = (payload.image_storage_path ?? "").trim();
    if (!path || path.includes("..")) {
      return new Response(
        JSON.stringify({
          ok: false,
          items: [],
          error: "image_storage_path inválido",
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    if (!pathBelongsToUser(path, userId)) {
      return new Response(
        JSON.stringify({
          ok: false,
          items: [],
          error: "La ruta no pertenece a tu usuario.",
          detail:
            `userIdSesion=${userId} pathPrefijoEsperado (minúsculas)=${path.split("/")[0]?.toLowerCase()}`,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { data: fileData, error: dlErr } = await admin.storage
      .from("closet-images")
      .download(path);
    if (dlErr || !fileData) {
      return new Response(
        JSON.stringify({
          ok: false,
          items: [],
          error: "No se pudo descargar la imagen",
          detail: dlErr?.message ?? "storage",
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    const bytes = new Uint8Array(await fileData.arrayBuffer());

    let img: InstanceType<typeof Image>;
    try {
      img = await Image.decode(bytes);
    } catch {
      return new Response(
        JSON.stringify({
          ok: false,
          items: [],
          error: "Formato de imagen no soportado",
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const mimeType = path.toLowerCase().endsWith(".png")
      ? "image/png"
      : "image/jpeg";
    const b64 = encodeBase64(bytes);

    const model = Deno.env.get("GEMINI_DETECT_MODEL") ?? "gemini-2.5-flash";
    let detected: { items: GeminiItem[] };
    try {
      detected = await geminiDetectJson(apiKey, model, mimeType, b64);
    } catch (e) {
      return new Response(
        JSON.stringify({
          ok: false,
          items: [],
          error: "No pudimos analizar la imagen.",
          detail: String(e),
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const rawItems = Array.isArray(detected.items) ? detected.items : [];
    const iw = img.width;
    const ih = img.height;
    const outItems: Record<string, unknown>[] = [];
    const cropUploadFailures: string[] = [];

    for (let i = 0; i < rawItems.length; i++) {
      const it = rawItems[i];
      const name = String(it?.name ?? "Item").slice(0, 200);
      const category = String(it?.category ?? "accessories").toLowerCase();
      const bbox = it?.bounding_box as BBox | undefined;
      let x0 = 0, y0 = 0, w = iw, h = ih;
      if (
        bbox &&
        bbox.x_min < bbox.x_max &&
        bbox.y_min < bbox.y_max &&
        bbox.x_min >= 0 &&
        bbox.y_min >= 0
      ) {
        x0 = Math.max(0, Math.floor(bbox.x_min * iw));
        y0 = Math.max(0, Math.floor(bbox.y_min * ih));
        const x1 = Math.min(iw, Math.ceil(bbox.x_max * iw));
        const y1 = Math.min(ih, Math.ceil(bbox.y_max * ih));
        w = Math.max(1, x1 - x0);
        h = Math.max(1, y1 - y0);
      }

      let cropBuf: Uint8Array;
      try {
        const cropped = img.crop(x0, y0, w, h);
        cropBuf = await cropped.encodeJPEG(90);
      } catch (_e) {
        cropBuf = await img.encodeJPEG(90);
      }

      const cropId = crypto.randomUUID();
      const cropPath = `${userId}/crops/${cropId}.jpg`;

      const { error: upErr } = await admin.storage
        .from("closet-images")
        .upload(cropPath, cropBuf, {
          contentType: "image/jpeg",
          upsert: false,
        });
      if (upErr) {
        console.error(upErr);
        continue;
      }

      const { data: pub } = admin.storage.from("closet-images").getPublicUrl(cropPath);
      outItems.push({
        id: cropId,
        name,
        category,
        original_crop_url: pub.publicUrl,
        bounding_box: bbox ?? { x_min: 0, y_min: 0, x_max: 1, y_max: 1 },
      });
    }

    if (outItems.length === 0 && rawItems.length > 0) {
      return new Response(
        JSON.stringify({
          ok: false,
          items: [],
          error:
            "La IA encontró prendas pero no pudimos guardar los recortes en Storage.",
          detail: cropUploadFailures.slice(0, 5).join(" | ") || "sin detalle",
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify({ ok: true, items: outItems }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
