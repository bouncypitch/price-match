// Price Match key server (Cloudflare Worker).
//
// The iPhone app sends its searches here instead of to SerpApi directly.
// This Worker checks the app's token, allows only the searches the app uses,
// adds the secret SerpApi key, and caches results for 15 minutes so the same
// item scanned on several phones doesn't use extra searches.
//
// Secrets (set with `npx wrangler secret put NAME`):
//   SERPAPI_KEY  your SerpApi key
//   APP_TOKEN    shared token compiled into the app (Config/Secrets.xcconfig)

// Each SerpApi engine the app uses, and the query parameters it may pass through.
const ALLOWED = {
  home_depot: ["q"],
  walmart: ["query"],
  amazon: ["k", "amazon_domain"],
  google_shopping: ["q", "gl", "hl", "location"],
  google_immersive_product: ["page_token"],
};

const CACHE_SECONDS = 15 * 60;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return json({ ok: true });
    }
    if (url.pathname !== "/search" || request.method !== "GET") {
      return json({ error: "Not found" }, 404);
    }

    if (!env.APP_TOKEN || request.headers.get("X-App-Token") !== env.APP_TOKEN) {
      return json({ error: "Unauthorized" }, 401);
    }
    if (!env.SERPAPI_KEY) {
      return json({ error: "Server is missing its SerpApi key" }, 500);
    }

    // Per-connection limit (configured in wrangler.jsonc). One scan is about 5 searches.
    if (env.LIMITER) {
      const { success } = await env.LIMITER.limit({ key: request.headers.get("CF-Connecting-IP") ?? "unknown" });
      if (!success) {
        return json({ error: "Too many searches. Please wait a minute." }, 429);
      }
    }

    const engine = url.searchParams.get("engine");
    const allowedParams = ALLOWED[engine];
    if (!allowedParams) {
      return json({ error: "Unsupported search" }, 400);
    }

    const upstream = new URL("https://serpapi.com/search.json");
    upstream.searchParams.set("engine", engine);
    for (const name of allowedParams) {
      const value = url.searchParams.get(name);
      if (value !== null && value.length <= 500) {
        upstream.searchParams.set(name, value);
      }
    }

    // Cache successful answers at Cloudflare's edge; the cache key never leaves Cloudflare.
    const cacheKey = new Request(upstream.toString(), { method: "GET" });
    const cache = caches.default;
    const cached = await cache.match(cacheKey);
    if (cached) {
      return withHeader(cached, "X-Cache", "HIT");
    }

    upstream.searchParams.set("api_key", env.SERPAPI_KEY);
    let response;
    try {
      response = await fetch(upstream.toString(), { headers: { Accept: "application/json" } });
    } catch {
      return json({ error: "Price service unreachable" }, 502);
    }

    const body = await response.text();
    const result = new Response(body, {
      status: response.status,
      headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": `max-age=${CACHE_SECONDS}` },
    });
    if (response.ok) {
      await cache.put(cacheKey, result.clone());
    }
    return withHeader(result, "X-Cache", "MISS");
  },
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

function withHeader(response, name, value) {
  const copy = new Response(response.body, response);
  copy.headers.set(name, value);
  return copy;
}
