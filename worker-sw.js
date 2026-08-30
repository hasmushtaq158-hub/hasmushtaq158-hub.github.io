const CACHE="park-worker-shell-v2";
const SHELL=["./worker.html","./worker-manifest.webmanifest"];
self.addEventListener("install",event=>{event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(SHELL)).then(()=>self.skipWaiting()))});
self.addEventListener("activate",event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim()))});
self.addEventListener("fetch",event=>{
  if(event.request.method!=="GET")return;
  const url=new URL(event.request.url);
  if(url.origin!==location.origin)return;
  if(event.request.mode==="navigate"){
    event.respondWith(fetch(event.request).then(response=>{const copy=response.clone();caches.open(CACHE).then(cache=>cache.put("./worker.html",copy));return response}).catch(()=>caches.match("./worker.html")));
    return;
  }
  event.respondWith(caches.match(event.request).then(cached=>cached||fetch(event.request)));
});
self.addEventListener("push",event=>{
  let data={};
  try{data=event.data?.json()||{}}catch{data={body:event.data?.text()||"Новое уведомление"}}
  event.waitUntil(self.registration.showNotification(data.title||"Билеты парка",{body:data.body||"Откройте приложение",icon:data.icon||undefined,badge:data.badge||undefined,data:{url:data.url||"./worker.html"},tag:data.tag||"park-worker",renotify:true}));
});
self.addEventListener("notificationclick",event=>{
  event.notification.close();
  const target=new URL(event.notification.data?.url||"./worker.html",self.location.origin).href;
  event.waitUntil(clients.matchAll({type:"window",includeUncontrolled:true}).then(list=>{const open=list.find(client=>client.url.startsWith(self.location.origin));if(open){open.navigate(target);return open.focus()}return clients.openWindow(target)}));
});
