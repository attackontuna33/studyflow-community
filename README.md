# STUDYFLOW Community

Arkadaşlarınla birlikte kullanabileceğin, kullanıcı adı/şifre girişi, kişisel çalışma kronometresi, arkadaşlık istekleri, çevrimiçi durumu ve çalışma serileri içeren statik web uygulaması.

## GitHub deposuna yükleme

1. GitHub'da yeni bir repository oluştur (ör. `studyflow-community`).
2. ZIP içeriğini bilgisayarında çıkar.
3. Aşağıdaki dosyaları repository'nin kök dizinine yükle:
   - `index.html`
   - `supabase-config.js`
   - `supabase-config.example.js`
   - `schema.sql`
   - `README.md`
   - `.nojekyll`
4. Commit et ve GitHub'a gönder.

## Supabase kurulumu

1. [Supabase](https://supabase.com/dashboard) üzerinde bir proje oluştur.
2. SQL Editor'da `schema.sql` dosyasının tamamını çalıştır.
3. Authentication → Providers → Email altında **Confirm email** ayarını kapat.
4. Project Settings → API bölümünden Project URL ile **publishable** veya eski **anon** anahtarı al.
5. `supabase-config.js` dosyasını aç ve aşağıdaki iki alanı kendi değerlerinle değiştir:

```js
window.STUDYFLOW_SUPABASE_URL = "https://proje-kimligin.supabase.co";
window.STUDYFLOW_SUPABASE_ANON_KEY = "sb_publishable_..."; // veya anon key
```

**Güvenlik:** Bu statik uygulamada publishable/anon anahtar tarayıcıya gönderilir; bu normaldir. `service_role` veya `secret` anahtarını hiçbir zaman HTML/JS dosyasına, GitHub'a ya da istemci tarafına koyma. Veritabanı erişimi Row Level Security (RLS) ile korunur.

## GitHub Pages ile yayınlama

1. Repository → **Settings → Pages** bölümünü aç.
2. **Build and deployment → Source** alanında **GitHub Actions** seç.
3. `main` dalına gönderdiğin her commit `.github/workflows/pages.yml` iş akışını tetikler.
4. Repository → **Actions** bölümünden dağıtımın tamamlandığını kontrol et.
5. Settings → Pages altında oluşan GitHub Pages adresini aç. İlk yayın birkaç dakika sürebilir.

Bu proje derleme adımı gerektirmeyen statik HTML/CSS/JS uygulamasıdır; GitHub Pages üzerinde doğrudan yayınlanabilir. Supabase CDN bağlantısı ve Supabase projesi için internet bağlantısı gerekir.

## Kullanıcı adıyla giriş hakkında

Kullanıcı adı, Supabase Auth'un e-posta/şifre akışıyla uyumlu olması için dahili olarak `kullaniciadi@studyflow.invalid` biçimine dönüştürülür. Bu gerçek bir e-posta adresi değildir. Bu nedenle bu ilk sürümde e-posta doğrulama ve parola sıfırlama bulunmaz. Güçlü ve benzersiz şifreler kullanın.

## Özellikler

- Kullanıcı adı + şifre ile kayıt ve giriş
- Kişisel çalışma kronometresi ve oturum kaydı
- Türkiye yerel gününe göre günlük toplam süre
- 30 dakika çalışma eşiğiyle günlük seri
- Arkadaşlık isteği gönderme ve kabul etme
- Onaylı arkadaşların toplam çalışma süresi, serisi ve çevrimiçi/çevrimdışı durumu
- Haftalık çalışma ve seri sıralaması
- Supabase RLS ile kullanıcı bazlı erişim kontrolü

## Çevrimiçi durumu

Tarayıcı 30 saniyede bir varlık sinyali gönderir. Son sinyalin üzerinden 90 saniyeden fazla geçtiyse kullanıcı çevrimdışı gösterilir. Tarayıcı kapandığında durum anında değil, zaman aşımı sonrasında çevrimdışı olur.

## Kontrol listesi

- [ ] Supabase SQL şeması çalıştırıldı.
- [ ] Email confirmation kapatıldı.
- [ ] `supabase-config.js` proje bilgileriyle dolduruldu.
- [ ] GitHub Pages etkinleştirildi.
- [ ] İki test hesabı oluşturuldu.
- [ ] Arkadaşlık isteği gönderme/kabul etme test edildi.
- [ ] Çalışma oturumu kaydı ve günlük seri kontrol edildi.
