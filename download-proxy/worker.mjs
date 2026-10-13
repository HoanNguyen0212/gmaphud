const ORIGIN = "https://bechou0410.github.io/gmaphud/";
const PACKAGE = /^pool\/com\.chou\.googlemaps\.vietmap_([0-9][A-Za-z0-9.+~-]*)_(iphoneos-arm64|iphoneos-arm)\.deb$/;
const UPSERT = `INSERT INTO download_counts (day, version, architecture, requests)
  VALUES (?, ?, ?, 1)
  ON CONFLICT(day, version, architecture) DO UPDATE SET requests = requests + 1`;

export function vietnamDay(now) {
  return new Date(now.getTime() + 7 * 3600 * 1000).toISOString().slice(0, 10);
}

export function createProxy(fetchOrigin = fetch, clock = () => new Date()) {
  return {
    async fetch(request, env, ctx) {
      // Only GET/HEAD are needed by the flat APT source. Never forward credentials.
      if (!['GET', 'HEAD'].includes(request.method)) {
        return new Response(null, { status: 405, headers: { Allow: 'GET, HEAD' } });
      }
      const path = new URL(request.url).pathname.slice(1);
      if (/%|\\|(^|\/)\.{1,2}(\/|$)/.test(path)) {
        return new Response(null, { status: 400 });
      }
      const upstream = new URL(ORIGIN + path);
      // Stable package lengths/ranges must refer to the original archive bytes.
      const headers = new Headers({ 'Accept-Encoding': 'identity' });
      for (const name of ['Range', 'If-Range', 'If-None-Match', 'If-Modified-Since']) {
        if (request.headers.has(name)) headers.set(name, request.headers.get(name));
      }
      const fallback = () => new Response(null, {
        status: 307,
        headers: { Location: upstream.href, 'Cache-Control': 'no-store' },
      });
      // Cloudflare may negotiate compression upstream. Byte ranges and HEAD
      // must go directly to Pages so resume offsets/archive sizes stay exact.
      if (request.method === 'HEAD' || request.headers.has('Range')) return fallback();
      const match = PACKAGE.exec(path);
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 3000);
      let response;
      try {
        response = await fetchOrigin(upstream.href, {
          method: match ? 'HEAD' : request.method, headers, redirect: 'manual', signal: controller.signal,
        });
      } catch {
        return fallback();
      } finally {
        clearTimeout(timeout);
      }
      if (response.status >= 500) {
        response.body?.cancel().catch(() => {});
        return fallback();
      }
      const countable = request.method === 'GET' && match && response.status === 200;
      if (countable && env.DB) {
        // A detached aggregate write never delays or rejects the download redirect.
        const write = Promise.resolve().then(() => env.DB.prepare(UPSERT)
          .bind(vietnamDay(clock()), match[1], match[2]).run()).catch(() => {});
        ctx.waitUntil(write);
      }
      if (countable) {
        response.body?.cancel().catch(() => {});
        return fallback();
      }
      return response;
    },
  };
}

export default createProxy();
