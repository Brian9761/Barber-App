// npm run dev: serves the API on http://localhost:3000 with the production code
// (real pg pool, Stripe, Blob, Google/Yelp), reading .env.local if present.
// A stand-in for `vercel dev` that needs no Vercel login.
import { existsSync } from 'node:fs';
import { createServer } from 'node:http';
import { Readable } from 'node:stream';
import { createApp } from '../src/app.js';
import { productionDeps } from '../src/production.js';

if (existsSync('.env.local')) process.loadEnvFile('.env.local');

const app = createApp(productionDeps());
const port = Number(process.env.PORT) || 3000;

createServer(async (req, res) => {
  try {
    const headers = new Headers();
    for (const [name, value] of Object.entries(req.headers)) {
      if (Array.isArray(value)) value.forEach((v) => headers.append(name, v));
      else if (value !== undefined) headers.set(name, value);
    }
    // What Vercel's edge sets; @vercel/functions' ipAddress() reads it.
    headers.set('x-real-ip', req.socket.remoteAddress ?? '127.0.0.1');
    const hasBody = req.method !== 'GET' && req.method !== 'HEAD';
    const request = new Request(`http://${req.headers.host ?? `localhost:${port}`}${req.url ?? '/'}`, {
      method: req.method ?? 'GET',
      headers,
      body: hasBody ? (Readable.toWeb(req) as ReadableStream) : null,
      ...(hasBody ? { duplex: 'half' } : {}),
    } as RequestInit);
    const response = await app.fetch(request);
    res.writeHead(response.status, Object.fromEntries(response.headers));
    res.end(Buffer.from(await response.arrayBuffer()));
  } catch (error) {
    console.error(error);
    res.writeHead(500).end();
  }
}).listen(port, () => console.log(`Izzy Clipz API on http://localhost:${port}/api/health`));
