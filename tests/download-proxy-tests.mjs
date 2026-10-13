import test from 'node:test';
import assert from 'node:assert/strict';
import { createProxy, vietnamDay } from '../download-proxy/worker.mjs';

const filename = 'pool/com.chou.googlemaps.vietmap_0.1.22_iphoneos-arm64.deb';
const upstream = 'https://bechou0410.github.io/gmaphud/';
function harness({ status = 200, headers = {}, dbError = false } = {}) {
  const calls = [], writes = [], pending = [];
  const bytes = new Uint8Array([0, 255, 10, 13, 42]);
  const worker = createProxy(async (url, options) => {
    calls.push({ url, options });
    return new Response(status === 304 ? null : bytes, { status, headers });
  }, () => new Date('2026-10-13T18:00:00Z'));
  const env = { DB: { prepare: sql => ({ bind: (...values) => ({ run: async () => {
    if (dbError) throw new Error('quota');
    writes.push({ sql, values });
  } }) }) } };
  return { worker, calls, writes, pending, bytes, env, ctx: { waitUntil: p => pending.push(p) } };
}

test('checks availability then redirects; counts asynchronously by Vietnam date', async () => {
  const h = harness({ headers: { ETag: 'immutable', 'Content-Length': '5' } });
  const response = await h.worker.fetch(new Request('https://proxy.test/' + filename), h.env, h.ctx);
  assert.equal(response.status, 307);
  assert.equal(response.headers.get('Location'), upstream + filename);
  await Promise.all(h.pending);
  assert.deepEqual(h.writes[0].values, ['2026-10-14', '0.1.22', 'iphoneos-arm64']);
  assert.equal(h.calls[0].url, upstream + filename);
  assert.equal(h.calls[0].options.method, 'HEAD');
  assert.equal(h.calls[0].options.headers.get('Accept-Encoding'), 'identity');
});

test('HEAD, indexes, missing files, conditional hits and resumed ranges do not count', async () => {
  for (const [method, path, status, headers] of [
    ['GET', 'Packages.xz', 200, {}],
    ['GET', filename, 404, {}], ['GET', filename, 304, {}],
  ]) {
    const h = harness({ status });
    await h.worker.fetch(new Request('https://proxy.test/' + path, { method, headers }), h.env, h.ctx);
    await Promise.all(h.pending);
    assert.equal(h.writes.length, 0);
    assert.equal(h.calls[0].options.method, path === filename ? 'HEAD' : method);
  }
});

test('preserves conditional headers but strips credentials and query parameters', async () => {
  const h = harness();
  await h.worker.fetch(new Request('https://proxy.test/' + filename + '?token=private', {
    headers: { 'If-None-Match': 'tag',
      'If-Modified-Since': 'date', Authorization: 'private', Cookie: 'private' },
  }), h.env, h.ctx);
  await Promise.all(h.pending);
  assert.equal(h.writes.length, 1);
  assert.equal(h.calls[0].options.headers.get('If-None-Match'), 'tag');
  assert.equal(h.calls[0].options.headers.get('If-Modified-Since'), 'date');
  assert.equal(h.calls[0].options.headers.get('Authorization'), null);
  assert.equal(h.calls[0].options.headers.get('Cookie'), null);
  assert.equal(h.calls[0].url, upstream + filename);
});

test('HEAD and all ranges redirect without an upstream request or count', async () => {
  for (const [method, headers] of [['HEAD', {}], ['GET', { Range: 'bytes=0-' }],
    ['GET', { Range: 'bytes=1024-2047', 'If-Range': 'etag' }]]) {
    const h = harness();
    const response = await h.worker.fetch(new Request('https://proxy.test/' + filename, { method, headers }), h.env, h.ctx);
    assert.equal(response.status, 307);
    assert.equal(response.headers.get('Location'), upstream + filename);
    assert.equal(h.calls.length, 0);
    assert.equal(h.pending.length, 0);
  }
});

test('D1 failure or missing binding cannot block a download', async () => {
  for (const missing of [false, true]) {
    const h = harness({ dbError: true });
    const response = await h.worker.fetch(new Request('https://proxy.test/' + filename), missing ? {} : h.env, h.ctx);
    await Promise.all(h.pending);
    assert.equal(response.status, 307);
    assert.equal(response.headers.get('Location'), upstream + filename);
  }
});

test('origin network/5xx errors redirect to the exact original file', async () => {
  for (const fetcher of [async () => { throw new Error('network'); }, async () => new Response(null, { status: 503 })]) {
    const response = await createProxy(fetcher).fetch(new Request('https://proxy.test/' + filename), {}, {});
    assert.equal(response.status, 307);
    assert.equal(response.headers.get('Location'), upstream + filename);
    assert.equal(response.headers.get('Cache-Control'), 'no-store');
  }
});

test('rejects writes and encoded paths before contacting the fixed origin', async () => {
  const h = harness();
  assert.equal((await h.worker.fetch(new Request('https://proxy.test/', { method: 'POST' }), h.env, h.ctx)).status, 405);
  assert.equal((await h.worker.fetch(new Request('https://proxy.test/%2f%2fevil.test'), h.env, h.ctx)).status, 400);
  assert.equal(h.calls.length, 0);
  assert.equal(vietnamDay(new Date('2026-10-13T16:59:59Z')), '2026-10-13');
});

test('landing page preserves primary and fallback source links', async () => {
  const worker = createProxy(async () => new Response(
    '<a href="sileo://source/https://gmaphud.caidat.app/">Add</a><a href="' + upstream + '">Fallback</a>',
    { headers: { 'Content-Type': 'text/html', ETag: 'old' } },
  ));
  const response = await worker.fetch(new Request('https://proxy.test/'), {}, {});
  const html = await response.text();
  assert.ok(html.includes('sileo://source/https://gmaphud.caidat.app/'));
  assert.ok(html.includes('href="' + upstream + '"'));
  assert.equal(response.headers.get('etag'), 'old');
});
