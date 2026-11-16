const MAX_BYTES = 8 * 1024 * 1024;
const ALLOWED = new Set(["image/jpeg", "image/png", "image/webp"]);
const corsHeaders = {
  "Access-Control-Allow-Origin": "https://attackontuna33.github.io",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Authorization,Content-Type",
  "Vary": "Origin"
};
function json(data, status=200) {
  return new Response(JSON.stringify(data), {status, headers:{...corsHeaders,"Content-Type":"application/json; charset=utf-8","Cache-Control":"no-store"}});
}
function uuid(){ return crypto.randomUUID(); }
async function authenticate(request, env) {
  const auth = request.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) throw new Error("Oturum doğrulanamadı.");
  const response = await fetch(env.SUPABASE_URL.replace(/\/$/,"") + "/auth/v1/user", {
    headers: {"apikey":env.SUPABASE_ANON_KEY,"Authorization":auth}
  });
  if (!response.ok) throw new Error("Oturum geçersiz veya süresi dolmuş.");
  const user = await response.json();
  if (!user?.id) throw new Error("Kullanıcı bulunamadı.");
  return {id:user.id, authorization:auth};
}
async function getFriends(user, env) {
  const url = new URL(env.SUPABASE_URL.replace(/\/$/,"") + "/rest/v1/friendships");
  url.searchParams.set("select","user_a,user_b");
  url.searchParams.set("or", "(user_a.eq."+user.id+",user_b.eq."+user.id+")");
  const response = await fetch(url, {headers:{"apikey":env.SUPABASE_ANON_KEY,"Authorization":user.authorization}});
  if (!response.ok) throw new Error("Arkadaş listesi doğrulanamadı.");
  const rows = await response.json();
  return [...new Set(rows.map(row => row.user_a === user.id ? row.user_b : row.user_a))];
}
async function listPhotos(user, env) {
  const rows = await env.DB.prepare(
    "SELECT p.id,p.sender_id,p.created_at,p.expires_at,r.viewed_at,(SELECT COUNT(*) FROM photo_recipients x WHERE x.photo_id=p.id) AS total_recipients,(SELECT COUNT(*) FROM photo_recipients x WHERE x.photo_id=p.id AND x.viewed_at IS NOT NULL) AS viewed_count FROM photos p LEFT JOIN photo_recipients r ON r.photo_id=p.id AND r.user_id=? WHERE (r.user_id=? OR p.sender_id=?) AND p.expires_at>? ORDER BY p.created_at ASC"
  ).bind(user.id,user.id,user.id,Date.now()).all();
  return json({photos:rows.results || []});
}
async function uploadPhoto(request,user,env) {
  const form = await request.formData();
  const file = form.get("photo");
  if (!(file instanceof File)) return json({error:"Fotoğraf seçilmedi."},400);
  if (!ALLOWED.has(file.type)) return json({error:"Yalnızca JPG, PNG veya WebP fotoğrafları gönderilebilir."},415);
  if (file.size < 1 || file.size > MAX_BYTES) return json({error:"Fotoğraf en fazla 8 MB olabilir."},413);
  const recipients = await getFriends(user,env);
  if (!recipients.length) return json({error:"Fotoğraf göndermek için önce en az bir arkadaş eklemelisin."},400);
  const id=uuid(), key="one-view/"+id, now=Date.now(), expires=now+24*60*60*1000;
  await env.PHOTOS.put(key, await file.arrayBuffer(), {httpMetadata:{contentType:file.type,cacheControl:"no-store"}});
  try {
    const statements=[
      env.DB.prepare("INSERT INTO photos(id,sender_id,object_key,mime_type,size_bytes,created_at,expires_at) VALUES(?,?,?,?,?,?,?)").bind(id,user.id,key,file.type,file.size,now,expires),
      ...recipients.map(recipient => env.DB.prepare("INSERT INTO photo_recipients(photo_id,user_id) VALUES(?,?)").bind(id,recipient))
    ];
    await env.DB.batch(statements);
  } catch(e) {
    await env.PHOTOS.delete(key);
    throw e;
  }
  return json({ok:true,id,expires_at:expires},201);
}
async function viewPhoto(id,user,env) {
  const row=await env.DB.prepare("SELECT p.object_key,p.mime_type,p.expires_at,r.viewed_at FROM photos p JOIN photo_recipients r ON r.photo_id=p.id WHERE p.id=? AND r.user_id=?").bind(id,user.id).first();
  if(!row) return json({error:"Bu fotoğraf sana gönderilmemiş."},404);
  if(row.expires_at<=Date.now()) return json({error:"Fotoğrafın 24 saatlik süresi dolmuş."},410);
  if(row.viewed_at) return json({error:"Bu fotoğrafı daha önce görüntüledin."},410);
  const object=await env.PHOTOS.get(row.object_key);
  if(!object) return json({error:"Fotoğraf artık mevcut değil."},410);
  const bytes=await object.arrayBuffer();
  const claim=await env.DB.prepare("UPDATE photo_recipients SET viewed_at=? WHERE photo_id=? AND user_id=? AND viewed_at IS NULL").bind(Date.now(),id,user.id).run();
  if(claim.meta.changes!==1) return json({error:"Bu fotoğraf zaten görüntülendi."},410);
  const pending=await env.DB.prepare("SELECT COUNT(*) AS n FROM photo_recipients WHERE photo_id=? AND viewed_at IS NULL").bind(id).first();
  if(Number(pending.n)===0) {
    await env.PHOTOS.delete(row.object_key);
    await env.DB.prepare("DELETE FROM photos WHERE id=?").bind(id).run();
  }
  return new Response(bytes,{status:200,headers:{...corsHeaders,"Content-Type":row.mime_type,"Cache-Control":"no-store, no-cache, must-revalidate","Pragma":"no-cache","X-Content-Type-Options":"nosniff"}});
}
export default {
  async fetch(request,env) {
    if(request.method==="OPTIONS") return new Response(null,{headers:corsHeaders});
    const url=new URL(request.url);
    try {
      if(!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) return json({error:"Worker yapılandırması eksik."},503);
      const user=await authenticate(request,env);
      if(request.method==="GET" && url.pathname==="/photos") return await listPhotos(user,env);
      if(request.method==="POST" && url.pathname==="/photos") return await uploadPhoto(request,user,env);
      const match=url.pathname.match(/^\/photos\/([0-9a-f-]+)\/view$/i);
      if(request.method==="POST" && match) return await viewPhoto(match[1],user,env);
      return json({error:"Adres bulunamadı."},404);
    } catch(error) {
      return json({error:error.message || "Beklenmeyen hata."},400);
    }
  },
  async scheduled(controller,env) {
    const expired=await env.DB.prepare("SELECT id,object_key FROM photos WHERE expires_at<=?").bind(Date.now()).all();
    for(const row of expired.results||[]) await env.PHOTOS.delete(row.object_key);
    await env.DB.prepare("DELETE FROM photos WHERE expires_at<=?").bind(Date.now()).run();
  }
};
