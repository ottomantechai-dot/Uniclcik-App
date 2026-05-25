/**
 * POST /functions/v1/prettify-item
 * Body: { "crop_storage_path": "{user_id}/crops/{id}.jpg", "category": "shoes", "item_name": "..." }
 * (Alternativa: crop_url pública del mismo bucket.)
 *
 * Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GEMINI_API_KEY
 * Opcional: GEMINI_IMAGE_MODEL (default gemini-2.5-flash-image-preview)
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { encodeBase64 } from "https://deno.land/std@0.224.0/encoding/base64.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

/** Misma semántica que en `detect-items`: prefijo usuario insensible a mayúsculas. */
function pathBelongsToUser(pathRaw: string, userIdRaw: string): boolean {
  const path = pathRaw.replace(/^\/+/, "").trim().toLowerCase();
  const uid = userIdRaw.replace(/^\/+/, "").trim().toLowerCase();
  return path.startsWith(uid + "/");
}

function prettifyPrompt(category: string, itemName: string): string {
  return `Transform this clothing item photo into a professional e-commerce product shot.

REQUIREMENTS:
- Pure white background (#FFFFFF), seamless, no shadows on background.
- Soft, even studio lighting from front-top.
- Subtle natural drop shadow directly beneath the item for grounding (max 15% opacity).
- Item centered, facing camera, fully visible with ~8% padding margin.
- Remove any body parts, mannequins, hangers, or other items.
- Preserve original colors, texture, pattern, and material with 100% fidelity.
- Do NOT add logos, labels, or text that weren't in the original.
- Output dimensions: 1024x1024 square, high resolution.
- Style reference: Zara / Uniqlo / Net-a-Porter product photography.

Item category: ${category}
Item description: ${itemName}

Output: a single clean product photo, nothing else.`;
}

function storagePathFromMaybeUrl(cropUrl: string | undefined): string | null {
  if (!cropUrl?.trim()) return null;
  try {
    const u = new URL(cropUrl.trim());
    const mark = "/object/public/closet-images/";
    const i = u.pathname.indexOf(mark);
    if (i === -1) return null;
    return decodeURIComponent(u.pathname.slice(i + mark.length));
  } catch {
    return null;
  }
}

function extractImageBytesFromGeminiPayload(j: Record<string, unknown>): Uint8Array | null {
  const cands = j["candidates"] as Record<string, unknown>[] | undefined;
  const parts = (cands?.[0]?.content as Record<string, unknown> | undefined)?.[
    "parts"
  ] as Record<string, unknown>[] | undefined;
  if (!parts) return null;
  for (const p of parts) {
    const id = p["inlineData"] as Record<string, unknown> | undefined;
    const id2 = p["inline_data"] as Record<string, unknown> | undefined;
    const blob = id ?? id2;
    const data = blob?.["data"] as string | undefined;
    if (data) {
      const bin = atob(data);
      const out = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
      return out;
    }
  }
  return null;
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
        JSON.stringify({ error: "Faltan secrets." }),
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
      crop_storage_path?: string;
      crop_url?: string;
      category?: string;
      item_name?: string;
    };

    let path = (payload.crop_storage_path ?? "").trim();
    if (!path) {
      path = storagePathFromMaybeUrl(payload.crop_url) ?? "";
    }
    if (!path || path.includes("..") || !pathBelongsToUser(path, userId)) {
      return new Response(JSON.stringify({ error: "crop path inválido" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const category = (payload.category ?? "accessories").slice(0, 80);
    const itemName = (payload.item_name ?? "item").slice(0, 200);

    const { data: fileData, error: dlErr } = await admin.storage
      .from("closet-images")
      .download(path);
    if (dlErr || !fileData) {
      return new Response(JSON.stringify({ error: "No se pudo descargar el crop" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const bytes = new Uint8Array(await fileData.arrayBuffer());
    const mimeType = path.toLowerCase().endsWith(".png")
      ? "image/png"
      : "image/jpeg";
    const b64 = encodeBase64(bytes);

    const model =
      Deno.env.get("GEMINI_IMAGE_MODEL") ?? "gemini-2.5-flash-image-preview";
    const gemUrl =
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
    const body = {
      contents: [{
        parts: [
          { inlineData: { mimeType, data: b64 } },
          { text: prettifyPrompt(category, itemName) },
        ],
      }],
      generationConfig: { temperature: 0.2 },
    };

    const res = await fetch(gemUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const t = await res.text();
      return new Response(
        JSON.stringify({ error: `Gemini ${res.status}`, detail: t.slice(0, 400) }),
        { status: 422, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    const j = await res.json() as Record<string, unknown>;
    const outBytes = extractImageBytesFromGeminiPayload(j);
    if (!outBytes?.length) {
      return new Response(JSON.stringify({ error: "Gemini no devolvió imagen" }), {
        status: 422,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const outId = crypto.randomUUID();
    const outPath = `${String(userId).toLowerCase()}/prettified/${outId}.jpg`;
    const { error: upErr } = await admin.storage
      .from("closet-images")
      .upload(outPath, outBytes, {
        contentType: "image/jpeg",
        upsert: false,
      });
    if (upErr) {
      return new Response(JSON.stringify({ error: upErr.message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const { data: pub } = admin.storage.from("closet-images").getPublicUrl(outPath);

    return new Response(
      JSON.stringify({ prettified_image_url: pub.publicUrl }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
