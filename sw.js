const CACHE='genz-store-v3';
const FILES=['./','./index.html','./store.html','./admin.html','./manager.html','./styles.css','./common.js','./config.js','./manifest.webmanifest','./config.js','./vendor/supabase.js'];
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(FILES)).then(()=>self.skipWaiting())));
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',event=>{
 const req=event.request;if(req.method!=='GET')return;
 const url=new URL(req.url);if(url.origin!==self.location.origin)return;
 if(url.pathname.endsWith('/config.js')){event.respondWith(fetch(new Request(req,{cache:'no-store'})).then(response=>{const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(req,copy));return response;}).catch(()=>caches.match(req)));return;}
 if(req.mode==='navigate'){
  event.respondWith(fetch(req).then(response=>{const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(req,copy));return response;}).catch(()=>caches.match(req).then(hit=>hit||caches.match('./index.html'))));
  return;
 }
 event.respondWith(caches.match(req).then(hit=>hit||fetch(req).then(response=>{if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(req,copy));}return response;})));
});
