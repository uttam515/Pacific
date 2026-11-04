import { readdir, readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
const assets = (await readdir("dist/assets")).map((x) => "/assets/" + x);
const digest = createHash("sha256")
  .update(await readFile("dist/index.html"))
  .digest("hex")
  .slice(0, 12);
await writeFile(
  "dist/sw.js",
  `const CACHE='offgrid-${digest}';const ASSETS=${JSON.stringify(["/", "/index.html", "/favicon.svg", ...assets])};
self.addEventListener('install',e=>e.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS))));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('offgrid-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(e.request.method!=='GET'||u.origin!==self.location.origin)return;if(e.request.mode==='navigate'&&!u.pathname.startsWith('/api/'))e.respondWith(fetch(e.request).catch(()=>caches.match('/index.html')));else if(ASSETS.includes(u.pathname))e.respondWith(caches.match(e.request).then(c=>c||fetch(e.request)));});`,
);
