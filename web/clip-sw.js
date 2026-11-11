'use strict';
// Plays a chat video as it is fetched (WebClipStream in the app).
//
// A chat video is decrypted in the page, a chunk at a time, and must never
// reach a disk or a cache. A <video> can only read a URL, though, and a blob:
// URL needs the whole file first. So the page points the <video> at
// __rift_clip/<token>, and this worker answers each request the player makes
// for it, ranges included, by asking the page that made the request for the
// bytes, over a MessageChannel:
//
//   worker -> page   {riftClip: token}, with the channel's port
//   page   -> worker {length, type}, or {gone: true}
//   worker -> page   {read: offset, max: n}
//   page   -> worker {bytes: ArrayBuffer}, at most n, or {failed: why}
//   worker -> page   {done: true}
//
// The body is pulled, one read at a time, only as fast as the player reads
// it, so a paused video fetches no more. Only the page that holds a token can
// answer for it; any other gets a 404.
//
// Everything else the page fetches goes past this worker untouched.

const PREFIX = '__rift_clip/';

// The most one read asks the page for: a sealed chunk.
const MAX_READ = 1 << 20;

// How long the page may take to answer before the request fails.
const PATIENCE_MS = 30000;

self.addEventListener('install', (event) => {
  self.skipWaiting();
  // Where the browser can be told so, the app's own requests skip this
  // worker, which then never has to start for them.
  if (event.addRoutes) {
    const clips = new URL(PREFIX, self.registration.scope).pathname + '*';
    event.waitUntil(
      event
        .addRoutes({
          condition: { not: { urlPattern: { pathname: clips } } },
          source: 'network',
        })
        .catch(() => {}),
    );
  }
});

// In control of the pages already open, so the first video plays streamed.
self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

// The page says it still has a video open, so the worker is not stopped
// under a paused one.
self.addEventListener('message', () => {});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;
  const at = url.pathname.indexOf('/' + PREFIX);
  if (at < 0) return;
  const token = url.pathname.slice(at + 1 + PREFIX.length);
  event.respondWith(serve(event, token));
});

async function serve(event, token) {
  const client = event.clientId ? await self.clients.get(event.clientId) : null;
  if (!client) return new Response(null, { status: 404 });
  const page = new Page(client, token);
  let opened;
  try {
    opened = await page.ask(null);
  } catch (_) {
    page.close();
    return new Response(null, { status: 404 });
  }
  if (!opened || typeof opened.length !== 'number') {
    page.close();
    return new Response(null, { status: 404 });
  }
  const length = opened.length;
  const range = parseRange(event.request.headers.get('range'), length);
  if (range === null) {
    page.close();
    return new Response(null, {
      status: 416,
      headers: { 'Content-Range': `bytes */${length}` },
    });
  }
  const { start, end, partial } = range;
  const headers = {
    'Accept-Ranges': 'bytes',
    'Cache-Control': 'no-store',
    'Content-Length': String(end - start + 1),
  };
  if (opened.type) headers['Content-Type'] = opened.type;
  if (partial) headers['Content-Range'] = `bytes ${start}-${end}/${length}`;
  let next = start;
  const body = new ReadableStream({
    async pull(controller) {
      if (next > end) {
        page.close();
        controller.close();
        return;
      }
      let answer;
      try {
        answer = await page.ask({
          read: next,
          max: Math.min(end - next + 1, MAX_READ),
        });
      } catch (e) {
        page.close();
        controller.error(e);
        return;
      }
      const bytes = answer && answer.bytes;
      if (!bytes || bytes.byteLength === 0) {
        page.close();
        controller.error(new Error((answer && answer.failed) || 'No bytes'));
        return;
      }
      controller.enqueue(new Uint8Array(bytes));
      next += bytes.byteLength;
      if (next > end) {
        page.close();
        controller.close();
      }
    },
    cancel() {
      page.close();
    },
  });
  return new Response(body, { status: partial ? 206 : 200, headers });
}

// The bytes a Range header asks for, as the first and last offsets; the whole
// file when it asks for none or for something this does not read; null when
// it asks for nothing the file has.
function parseRange(header, length) {
  const whole = { start: 0, end: length - 1, partial: false };
  const asked = /^bytes=(\d*)-(\d*)$/.exec((header || '').trim());
  if (!asked || (asked[1] === '' && asked[2] === '')) return whole;
  let start;
  let end;
  if (asked[1] === '') {
    // The last n bytes.
    start = Math.max(0, length - Number(asked[2]));
    end = length - 1;
  } else {
    start = Number(asked[1]);
    end = asked[2] === '' ? length - 1 : Math.min(Number(asked[2]), length - 1);
  }
  if (start >= length || start > end) return null;
  return { start, end, partial: true };
}

// One request's conversation with the page, one question at a time: the
// stream asks for its next read only once the last has landed.
class Page {
  constructor(client, token) {
    this.client = client;
    this.token = token;
    this.channel = null;
    this.waiting = null;
  }

  // Null opens the conversation, and the answer is the file's length.
  ask(message) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.waiting = null;
        reject(new Error('The page did not answer'));
      }, PATIENCE_MS);
      this.waiting = (data) => {
        clearTimeout(timer);
        this.waiting = null;
        resolve(data);
      };
      if (message === null) {
        this.channel = new MessageChannel();
        this.channel.port1.onmessage = (e) => this.waiting && this.waiting(e.data);
        this.client.postMessage({ riftClip: this.token }, [this.channel.port2]);
      } else {
        this.channel.port1.postMessage(message);
      }
    });
  }

  close() {
    if (!this.channel) return;
    try {
      this.channel.port1.postMessage({ done: true });
    } catch (_) {}
    this.channel.port1.close();
    this.channel = null;
  }
}
