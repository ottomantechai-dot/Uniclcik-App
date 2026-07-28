/**
 * Authenticated marketplace gateway for the iOS app.
 *
 * Keeps provider credentials on the server and exposes only allow-listed,
 * read-only market-data operations.
 *
 * Required secrets:
 *   SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 *   KICKSDB_API_KEY
 *   EBAY_CLIENT_ID
 *   EBAY_CLIENT_SECRET
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const KICKS_BASE_URL = "https://api.kicks.dev/v3";
const EBAY_OAUTH_URL = "https://api.ebay.com/identity/v1/oauth2/token";
const EBAY_BROWSE_URL =
  "https://api.ebay.com/buy/browse/v1/item_summary/search";
const EBAY_SCOPE = "https://api.ebay.com/oauth/api_scope";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const jsonHeaders = {
  ...corsHeaders,
  "Content-Type": "application/json; charset=utf-8",
};

type KicksPlatform = "stockx" | "goat";
type EbayProfile = "sneakers" | "cards";
type GatewayPayload = {
  operation?: string;
  platform?: string;
  query?: string;
  limit?: number;
  product_key?: string;
  slug?: string;
  shop?: string;
  product_id?: string;
  profile?: string;
};

type CacheEntry = { expiresAt: number; value: unknown };
const responseCache = new Map<string, CacheEntry>();
const requestWindows = new Map<string, number[]>();

let ebayToken: { value: string; expiresAt: number } | null = null;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function cleanText(value: unknown, maxLength: number): string {
  return typeof value === "string"
    ? value.trim().replace(/\s+/g, " ").slice(0, maxLength)
    : "";
}

function boundedLimit(value: unknown, fallback: number, max: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  return Math.max(1, Math.min(max, Math.trunc(value)));
}

function kicksPlatform(value: unknown): KicksPlatform | null {
  return value === "stockx" || value === "goat" ? value : null;
}

function cacheGet<T>(key: string): T | null {
  const hit = responseCache.get(key);
  if (!hit) return null;
  if (hit.expiresAt <= Date.now()) {
    responseCache.delete(key);
    return null;
  }
  return hit.value as T;
}

function cacheSet(key: string, value: unknown, ttlMs: number): void {
  if (responseCache.size > 250) {
    const oldest = responseCache.keys().next().value;
    if (oldest) responseCache.delete(oldest);
  }
  responseCache.set(key, { value, expiresAt: Date.now() + ttlMs });
}

function checkRateLimit(userId: string): boolean {
  const now = Date.now();
  const start = now - 60_000;
  const recent = (requestWindows.get(userId) ?? []).filter((t) => t > start);
  if (recent.length >= 45) {
    requestWindows.set(userId, recent);
    return false;
  }
  recent.push(now);
  requestWindows.set(userId, recent);
  return true;
}

async function fetchJSON(
  url: URL,
  init: RequestInit,
  provider: string,
): Promise<Record<string, unknown>> {
  const response = await fetch(url, {
    ...init,
    signal: AbortSignal.timeout(15_000),
  });
  const text = await response.text();
  let parsed: Record<string, unknown> = {};
  if (text) {
    try {
      parsed = JSON.parse(text) as Record<string, unknown>;
    } catch {
      parsed = { raw: text.slice(0, 500) };
    }
  }
  if (!response.ok) {
    const detail = typeof parsed["message"] === "string"
      ? parsed["message"]
      : typeof parsed["error"] === "string"
      ? parsed["error"]
      : text.slice(0, 240);
    throw new Error(`${provider} HTTP ${response.status}: ${detail}`);
  }
  return parsed;
}

async function kicksRequest(path: string): Promise<Record<string, unknown>> {
  const key = Deno.env.get("KICKSDB_API_KEY");
  if (!key) throw new Error("KicksDB no está configurado en el servidor.");
  const url = new URL(`${KICKS_BASE_URL}${path}`);
  return await fetchJSON(
    url,
    {
      headers: {
        "Authorization": `Bearer ${key}`,
        "Accept": "application/json",
      },
    },
    "KicksDB",
  );
}

async function kicksSearch(payload: GatewayPayload): Promise<unknown> {
  const platform = kicksPlatform(payload.platform);
  const query = cleanText(payload.query, 180);
  if (!platform || query.length < 2) {
    throw new Error("Plataforma o búsqueda inválida.");
  }
  const limit = boundedLimit(payload.limit, 20, 50);
  const cacheKey = `ks:${platform}:${limit}:${query.toLowerCase()}`;
  const cached = cacheGet<unknown>(cacheKey);
  if (cached) return cached;

  const params = new URLSearchParams({
    limit: String(limit),
    query,
  });
  const result = await kicksRequest(
    `/${platform}/products?${params.toString()}`,
  );
  const data = Array.isArray(result["data"]) ? result["data"] : [];
  cacheSet(cacheKey, data, 2 * 60_000);
  return data;
}

async function kicksDetail(payload: GatewayPayload): Promise<unknown> {
  const platform = kicksPlatform(payload.platform);
  const productKey = cleanText(payload.product_key, 200);
  if (!platform || !productKey || productKey.includes("/")) {
    throw new Error("Producto o plataforma inválida.");
  }
  const cacheKey = `kd:${platform}:${productKey}`;
  const cached = cacheGet<unknown>(cacheKey);
  if (cached) return cached;

  const variants = platform === "stockx" ? "?display%5Bvariants%5D=true" : "";
  const result = await kicksRequest(
    `/${platform}/products/${encodeURIComponent(productKey)}${variants}`,
  );
  const data = result["data"] ?? null;
  cacheSet(cacheKey, data, 2 * 60_000);
  return data;
}

async function kicksUnified(payload: GatewayPayload): Promise<unknown> {
  const slug = cleanText(payload.slug, 200);
  const shop = cleanText(payload.shop, 60).toLowerCase();
  if (!slug || slug.includes("/") || !shop) {
    throw new Error("Slug o tienda inválida.");
  }
  const cacheKey = `ku:${slug}:${shop}`;
  const cached = cacheGet<unknown>(cacheKey);
  if (cached) return cached;

  const result = await kicksRequest(
    `/unified/products/${encodeURIComponent(slug)}`,
  );
  const entries = Array.isArray(result["data"])
    ? result["data"] as Record<string, unknown>[]
    : [];
  const candidates = entries.filter((entry) =>
    String(entry["shop_name"] ?? "").toLowerCase() === shop &&
    entry["prices"] && typeof entry["prices"] === "object"
  );
  const best = candidates.sort((a, b) =>
    Object.keys((b["prices"] ?? {}) as object).length -
    Object.keys((a["prices"] ?? {}) as object).length
  )[0];
  const prices = (best?.["prices"] ?? {}) as Record<string, unknown>;
  const normalized = Object.fromEntries(
    Object.entries(prices)
      .map(([size, price]) => [size, Number(price)] as const)
      .filter(([, price]) => Number.isFinite(price) && price > 0),
  );
  cacheSet(cacheKey, normalized, 2 * 60_000);
  return normalized;
}

async function kicksDailySales(payload: GatewayPayload): Promise<unknown> {
  const platform = kicksPlatform(payload.platform);
  const productId = cleanText(payload.product_id, 200);
  if (!platform || !productId || productId.includes("/")) {
    throw new Error("Producto o plataforma inválida.");
  }
  const cacheKey = `kds:${platform}:${productId}`;
  const cached = cacheGet<unknown>(cacheKey);
  if (cached) return cached;

  const result = await kicksRequest(
    `/${platform}/products/${encodeURIComponent(productId)}/sales/daily`,
  );
  const data = Array.isArray(result["data"]) ? result["data"] : [];
  cacheSet(cacheKey, data, 10 * 60_000);
  return data;
}

async function ebayAccessToken(): Promise<string> {
  if (ebayToken && ebayToken.expiresAt > Date.now()) return ebayToken.value;
  const clientId = Deno.env.get("EBAY_CLIENT_ID");
  const clientSecret = Deno.env.get("EBAY_CLIENT_SECRET");
  if (!clientId || !clientSecret) {
    throw new Error("eBay no está configurado en el servidor.");
  }

  const credentials = btoa(`${clientId}:${clientSecret}`);
  const body = new URLSearchParams({
    grant_type: "client_credentials",
    scope: EBAY_SCOPE,
  });
  const response = await fetchJSON(
    new URL(EBAY_OAUTH_URL),
    {
      method: "POST",
      headers: {
        "Authorization": `Basic ${credentials}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body,
    },
    "eBay OAuth",
  );
  const value = typeof response["access_token"] === "string"
    ? response["access_token"]
    : "";
  const expiresIn = Number(response["expires_in"] ?? 7200);
  if (!value) throw new Error("eBay OAuth no devolvió access_token.");
  ebayToken = {
    value,
    expiresAt: Date.now() + Math.max(30, expiresIn - 60) * 1000,
  };
  return value;
}

async function ebaySearch(payload: GatewayPayload): Promise<unknown> {
  const query = cleanText(payload.query, 180);
  if (query.length < 2) throw new Error("Búsqueda eBay inválida.");
  const limit = boundedLimit(payload.limit, 30, 100);
  const profile: EbayProfile = payload.profile === "cards" ? "cards" : "sneakers";
  const cacheKey = `eb:${profile}:${limit}:${query.toLowerCase()}`;
  const cached = cacheGet<unknown>(cacheKey);
  if (cached) return cached;

  const token = await ebayAccessToken();
  const filter = profile === "sneakers"
    ? [
      "conditions:{NEW}",
      "qualifiedPrograms:{AUTHENTICITY_GUARANTEE}",
      "deliveryCountry:US",
      "deliveryPostalCode:33101",
    ].join(",")
    : "deliveryCountry:US,priceCurrency:USD";

  const url = new URL(EBAY_BROWSE_URL);
  url.searchParams.set("q", query);
  url.searchParams.set("limit", String(limit));
  url.searchParams.set("filter", filter);
  url.searchParams.set("sort", "price");

  const result = await fetchJSON(
    url,
    {
      headers: {
        "Authorization": `Bearer ${token}`,
        "X-EBAY-C-MARKETPLACE-ID": "EBAY_US",
        "Accept": "application/json",
      },
    },
    "eBay Browse",
  );

  const summaries = Array.isArray(result["itemSummaries"])
    ? result["itemSummaries"] as Record<string, unknown>[]
    : [];
  const normalized = summaries.map((item) => {
    const price = (item["price"] ?? {}) as Record<string, unknown>;
    const aspects = Array.isArray(item["localizedAspects"])
      ? item["localizedAspects"] as Record<string, unknown>[]
      : [];
    return {
      id: String(item["itemId"] ?? ""),
      title: String(item["title"] ?? query),
      price: Number(price["value"] ?? 0),
      currency: String(price["currency"] ?? "USD"),
      url: typeof item["itemWebUrl"] === "string"
        ? item["itemWebUrl"]
        : null,
      aspects: aspects.map((aspect) => ({
        name: String(aspect["name"] ?? ""),
        value: String(aspect["value"] ?? ""),
      })),
    };
  }).filter((item) => Number.isFinite(item.price) && item.price > 0);

  cacheSet(cacheKey, normalized, 2 * 60_000);
  return normalized;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceKey) {
      return json({ error: "Supabase no está configurado." }, 500);
    }

    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ")) {
      return json({ error: "Unauthorized" }, 401);
    }
    const jwt = auth.slice("Bearer ".length);
    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await admin.auth.getUser(jwt);
    const userId = data?.user?.id;
    if (error || !userId) {
      return json({ error: "Sesión inválida." }, 401);
    }
    if (!checkRateLimit(userId)) {
      return json({ error: "Demasiadas consultas. Inténtalo en un minuto." }, 429);
    }

    const payload = await req.json() as GatewayPayload;
    const operation = cleanText(payload.operation, 40);

    if (operation === "status") {
      const kicks = Boolean(Deno.env.get("KICKSDB_API_KEY"));
      const ebay = Boolean(
        Deno.env.get("EBAY_CLIENT_ID") && Deno.env.get("EBAY_CLIENT_SECRET"),
      );
      return json({
        ok: true,
        data: {
          kicksdb: kicks,
          ebay,
          stockx: kicks,
          goat: kicks,
          flightclub: kicks,
        },
      });
    }

    let result: unknown;
    switch (operation) {
      case "kicks_search":
        result = await kicksSearch(payload);
        break;
      case "kicks_detail":
        result = await kicksDetail(payload);
        break;
      case "kicks_unified":
        result = await kicksUnified(payload);
        break;
      case "kicks_daily_sales":
        result = await kicksDailySales(payload);
        break;
      case "ebay_search":
        result = await ebaySearch(payload);
        break;
      default:
        return json({ error: "Operación no permitida." }, 400);
    }
    return json({ ok: true, data: result });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const notConfigured = message.includes("no está configurado");
    return json(
      { ok: false, error: message.slice(0, 500) },
      notConfigured ? 503 : 502,
    );
  }
});
