const CACHE="park-manager-v3";
const CORE=["./","./index.html","./manager-manifest.webmanifest","./manager-icon.svg","./DejaVuSans.ttf"];
self.addEventListener("install",event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(CORE)).then(()=>self.skipWaiting())));
self.addEventListener("activate",event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim())));
self.addEventListener("fetch",event=>{
  if(event.request.method!=="GET")return;
  event.respondWith(fetch(event.request).then(response=>{
    const copy=response.clone();
    caches.open(CACHE).then(cache=>cache.put(event.request,copy));
    return response;
  }).catch(()=>caches.match(event.request).then(cached=>cached||caches.match("./index.html"))));
});
self.addEventListener("push",event=>{
  let data={title:"Билеты парка",body:"Новое событие требует внимания",url:"./"};
  try{data={...data,...event.data.json()}}catch{}
  event.waitUntil(self.registration.showNotification(data.title,{body:data.body,icon:"./manager-icon.svg",badge:"./manager-icon.svg",tag:data.tag||"park-manager",data:{url:data.url||"./"}}));
});
self.addEventListener("notificationclick",event=>{
  event.notification.close();
  event.waitUntil(clients.matchAll({type:"window",includeUncontrolled:true}).then(list=>{
    const target=event.notification.data?.url||"./";
    for(const client of list){if("focus" in client){client.navigate(target);return client.focus()}}
    return clients.openWindow(target);
  }));
});
