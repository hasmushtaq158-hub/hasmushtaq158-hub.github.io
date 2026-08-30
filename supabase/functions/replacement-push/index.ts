import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const cors = {"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, apikey, content-type"};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {status, headers:{...cors,"Content-Type":"application/json"}});

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", {headers:cors});
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const publicKey = Deno.env.get("VAPID_PUBLIC_KEY")!;
    const privateKey = Deno.env.get("VAPID_PRIVATE_KEY")!;
    if (!publicKey || !privateKey) return json({error:"PUSH_NOT_CONFIGURED"}, 500);

    const authorization = request.headers.get("Authorization") || "";
    const userClient = createClient(url, anon, {global:{headers:{Authorization:authorization}}});
    const {data:{user}} = await userClient.auth.getUser();
    if (!user) return json({error:"UNAUTHORIZED"}, 401);

    const admin = createClient(url, service);
    const {action, request_id} = await request.json();
    const {data: replacement, error} = await admin.from("replacement_requests")
      .select("id,status,day_id,attraction_id,requester_id,replacement_worker_id,due_at")
      .eq("id", Number(request_id)).single();
    if (error || !replacement) return json({error:"REQUEST_NOT_FOUND"}, 404);

    const {data: caller} = await admin.from("profiles").select("role,active").eq("id",user.id).single();
    const isManager = caller?.role === "manager" && caller?.active;
    const isRequester = replacement.requester_id === user.id;
    const isSubstitute = replacement.replacement_worker_id === user.id;
    if (action === "requested" && !isRequester) return json({error:"NOT_ALLOWED"},403);
    if (action === "accepted" && !isSubstitute) return json({error:"NOT_ALLOWED"},403);
    if (action === "extended" && !isManager) return json({error:"NOT_ALLOWED"},403);
    if (action === "ended" && !isManager && !isRequester && !isSubstitute) return json({error:"NOT_ALLOWED"},403);

    const [{data: attractionRow},{data: requesterRow}] = await Promise.all([
      admin.from("attractions").select("name").eq("id",replacement.attraction_id).single(),
      admin.from("profiles").select("display_name").eq("id",replacement.requester_id).single()
    ]);
    const attraction = attractionRow?.name || "Аттракцион";
    const requesterName = requesterRow?.display_name || "Сотрудник";
    let recipients: string[] = [];
    let title = "Замена";
    let body = "Откройте приложение";
    if (action === "requested") {
      recipients = [replacement.replacement_worker_id];
      title = "Новый запрос замены";
      body = `${requesterName} просит замену · ${attraction}`;
    } else if (action === "accepted") {
      recipients = [replacement.requester_id];
      title = "Замена принята";
      body = `Можно отойти. Вернитесь не позднее чем через 15 минут · ${attraction}`;
    } else if (action === "extended") {
      recipients = [replacement.requester_id,replacement.replacement_worker_id];
      title = "Время замены продлено";
      body = `Новое время возвращения: ${new Date(replacement.due_at).toLocaleTimeString("ru-RU",{timeZone:"Europe/Samara",hour:"2-digit",minute:"2-digit"})}`;
    } else if (action === "ended") {
      recipients = [replacement.requester_id,replacement.replacement_worker_id];
      title = "Замена завершена";
      body = attraction;
    }

    webpush.setVapidDetails("mailto:hasmushtaq158@gmail.com", publicKey, privateKey);
    const {data: subscriptions} = await admin.from("worker_push_subscriptions").select("id,endpoint,p256dh,auth").in("worker_id",[...new Set(recipients)]).eq("active",true);
    let sent = 0;
    for (const subscription of subscriptions || []) {
      try {
        await webpush.sendNotification({endpoint:subscription.endpoint,keys:{p256dh:subscription.p256dh,auth:subscription.auth}},JSON.stringify({title,body,url:"./worker.html",tag:`replacement-${replacement.id}`}));
        sent++;
      } catch (pushError) {
        const status = Number(pushError?.statusCode || 0);
        if (status === 404 || status === 410) await admin.from("worker_push_subscriptions").update({active:false,updated_at:new Date().toISOString()}).eq("id",subscription.id);
      }
    }
    return json({ok:true,sent});
  } catch (error) {
    return json({error:String(error?.message || error)},500);
  }
});
