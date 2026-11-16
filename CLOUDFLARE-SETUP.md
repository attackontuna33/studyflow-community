# StudyFlow tek görüntülemelik fotoğraf servisi

Bu Worker fotoğrafları Supabase Storage'a değil Cloudflare R2'ye yükler. Alıcı başına tek görüntüleme hakkı Cloudflare D1'de tutulur. Fotoğraflar en geç 24 saat sonra silinir.

## Cloudflare kurulumu

1. Cloudflare hesabında Workers & Pages bölümünden yeni bir Worker oluştur ve GitHub deposu `attackontuna33/studyflow-community` ile bağla.
2. Root directory boş (depo kökü) kalsın.
3. Build/deploy komutu olarak şunu kullan:
   `npx wrangler deploy && npx wrangler d1 migrations apply studyflow-chat-media --remote`
4. Build tamamlanınca Worker'ın `workers.dev` adresini kopyala.
5. Worker Settings > Variables bölümünde `SUPABASE_URL` ve `SUPABASE_ANON_KEY` değerlerinin Wrangler yapılandırmasından geldiğini kontrol et.
6. Worker Settings > Triggers bölümünde `*/15 * * * *` Cron Trigger bulunduğunu kontrol et. Bu görev süresi dolan fotoğrafları temizler.
7. Worker adresini StudyFlow yapılandırmasına eklemek için geliştiriciye ilet. `supabase-config.js` içindeki `STUDYFLOW_MEDIA_API` alanı bu adresle doldurulacak.

Wrangler yapılandırması R2 bucket ve D1 veritabanını otomatik oluşturacak şekilde hazırlanmıştır. D1 migration dosyası `worker/migrations/0001_create_photos.sql` konumundadır.

## Sınırlar

- JPG, PNG ve WebP; en fazla 8 MB.
- Fotoğraf her onaylı arkadaşa ayrı ayrı bir kez açılır.
- Son alıcı görüntülediğinde R2 nesnesi ve D1 kayıtları silinir.
- Açılmayan fotoğraflar en geç 24 saatte silinir.
- Tek görüntüleme, ekran görüntüsü veya başka cihazla fotoğraf çekilmesini engelleyemez.
