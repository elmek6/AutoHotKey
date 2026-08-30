# Incognito hızlandırma — YAPILDI (2026-08-22)

> Bu dosya artık plan değil, **kayıt**. Ne yapıldı, hangi ölçüm neyi çürüttü,
> neye dokunulmamalı. Yeni bir oturuma bağlam olarak verilebilir.

İlgili dosyalar:

- `Lib/incognito.ahk` — modül (enable/disable, katmanlar, kademe, badge, audit)
- `Lib/trace_store.ahk` — depo altyapısı (`TraceStore`, `RegStore`,
  `RegDeltaStore`, `FileGlobStore`, `PolicyGuard`)

Üç katmanlı strateji **değişmedi**: 1) `PolicyGuard` ile önle, 2) jump list
dosyalarını kilitle, 3) snapshot/restore.

---

## Sonuç

| | Önce | Sonra (core) | Sonra (derin) |
|---|---|---|---|
| ENABLE | 3313 ms | **31–219 ms** | 78–94 ms |
| DISABLE | 328 ms | **15–188 ms** | 15–16 ms |
| Arka plan takılması | 2250 ms | **0** | 0 |
| Kapsam | 18 depo | 6 depo | 18 depo |

Ölçüm: aynı makinede 4 ayrı koşum, her koşumda ısınma turu + 3 tur.
`Files\incognito_perf.log` (`this.perfLog := true`, kapatmak için tek satır).

---

## ⚠️ ÖNCE BUNU OKU — `"w-"` KİLİT MODUNU DENEME

Bu dosyanın eski sürümü "kilit modu olarak `w-` de ölç, orijinal proje
`FileAccess.Write` kullanıyor" diyordu. **Bu öneri yıkıcı ve denenirken 49
gerçek jump list dosyası sıfırlandı** (36 AutomaticDestinations + 13
CustomDestinations, ~1,15 MB; geri alınamadı, VSS kapalı).

Sebep: C#'ta `FileAccess.Write` dosyayı truncate etmez, **AHK'da `"w"` eder**.
Kilitlemek için açmak, kilitlemek istediğin veriyi silmek demek.

Ölçülen gerçek (49 dosya, 3'er tur, ısınmış):

| mod | dışarıdan YAZ | OKU | SİL | süre |
|---|---|---|---|---|
| `rw-` | engellendi | engellendi | engellendi | ~0 ms |
| `w-` | engellendi | engellendi | engellendi | ~0 ms · **DOSYAYI SIFIRLAR** |
| `r-` | engellendi | engellendi | engellendi | ~0 ms |
| `rw` (tiresiz) | GEÇTİ | geçti | GEÇTİ | — |

Dışlamayı sağlayan şey erişim modu değil **paylaşım modu** (`-` =
`dwShareMode=0`). Üçü de eşit koruyor, aralarında ölçülebilir süre farkı yok.
Kod artık `"r-"` kullanıyor: hiç yazmayacağımız dosyalar için yazma erişimi
istemek gereksiz ve salt-okunur öznitelikli dosyada açılışı da engelliyordu.

---

## Planın çürüyen iki iddiası

**1. "`lockAllExisting` 2000 ms, en büyük kalem" — ÇÜRÜK.**
Isınmış durumda 49 dosyanın tamamı **~0 ms**. 2000 ms soğuk önbellek /
ilk-dokunuşta AV taraması artefaktıydı, kalıcı maliyet değil. Kilitleme yine de
reg export'larla örtüşecek şekilde sıraya alındı (bedava), ama parçalama
(`SetTimer` ile turlara bölme) **yapılmadı** — olmayan bir sorunu çözecekti.

**2. "Baseline sayımı 2250 ms" — abartılı.**
Gerçek script donması ~690 ms (14 reg deposu 171 ms + `ShellBags_UsrClass`
tek başına ~515 ms). Kalan ~540 ms, tur başına `SetTimer(-30)` gecikmesiydi;
yani duvar saati, donma değil. Yine de tamamen kaldırıldı.

**Doğrulanan:** süreç başlatma maliyeti. Her `Run` bizim thread'imizde ~17 ms
(14 depo = 235 ms); tek `cmd.exe` 16 ms. Tek komuta alındı.

---

## Yapılan işler

### 1. Kademe: `core` / `deep` — asıl kaldıraç

Depolar `tier` alanı kazandı (`TraceStore.__New(name, tier := "core")`).

- **core (6 depo, varsayılan AÇIK)** — DOSYA ADI taşıyanlar. Açtığın ya da
  kaydettiğin bir `.jpg`/`.mp4`'ün adı buraya düşer:
  `RecentDocs`, `OpenSavePidlMRU`, `LastVisitedPidlMRU`, `RecentLnk`,
  `JumpListAuto`, `JumpListCustom`.
- **deep (12 depo, varsayılan KAPALI)** — klasör gezinme ve program çalıştırma
  izleri; dosya adı tutmazlar: `ShellBagMRU_UsrClass` (2,75 MB — tek başına en
  ağır), `ShellBags_UsrClass`, `ShellBags`, `ShellBagMRU`, `UserAssist`,
  `FeatureUsage`, `MUICache`, `CIDSizeMRU`, `FirstFolder`, `WordWheelQuery`,
  `TypedPaths`, `RunMRU`.

Rozet penceresinde **"Derin izler"** kutusu; seçim `Files\incognito.ini`'ye
yazılıyor. Incognito AÇIKKEN işaretlenirse yedek O AN alınır (o ana kadarki
derin izler kapsam dışı kalır, kutunun tooltip'i bunu söylüyor); kaldırılırsa
o depolar oturumdan düşer, gözcüleri kapanır, yedekleri atılır.

`cleanNow()` kademeye BAKMAZ — `allStores` üzerinden gider. "Her şeyi sil"
açık bir kullanıcı eylemi, kapsamı daraltmanın anlamı yok.

**Eşli depolar aynı kademede olmak ZORUNDA.** `this.coupled` grubunun ikisi de
`deep`. Ayırırsan `RegDeltaStore` kardeşi olmadan çalışır ve sessizce sızdırır
(NodeSlots bitmap'i kardeşinde; ayrıntı `trace_store.ahk`'da).

### 2. `RecentLnk` yedeği tek dosyalık pakete alındı — −330 ms

`Recent\*.lnk`'te 156 dosya var ama toplamı 152 KB. Maliyet veri hacminden
değil **dosya adedinden** geliyordu. Adil kıyas (dönüşümlü, 3'er tur):

| | snapshot | sonraki enable'ın temizliği | toplam |
|---|---|---|---|
| klasör kopyası (eski) | 229 ms | 167 ms | **396 ms** |
| tek paket (`.pack`) | 51 ms | 15 ms | **67 ms** |

Referans: 156 kaynağı açıp okumak 31 ms. Yani maliyet **yazma** tarafındaydı
(156 dosya yaratmak), okuma değil.

> Kıyas sırası önemli: ilk ölçümde paket soğuk, klasör sıcak koştuğu için
> paket YAVAŞ görünmüştü (250 vs 203 ms). Dönüşümlü ölçünce tablo tersine
> döndü. Bu tuzağa tekrar düşme.

Biçim `trace_store.ahk` `FileGlobStore._pack` başlığında. Zaman damgaları
`FileSetTime` ile geri konuyor (`FileCopy` bunu kendiliğinden koruyordu, ham
yazma korumaz — damganın "şimdi" kalması başlı başına bir iz).
`cleanNow()`'un kalıcı yedeği hâlâ düz klasör kopyası (`archive()`), çünkü
orada hız değil elle karıştırılabilirlik önemli.

### 3. Reg export'lar tek `cmd.exe`'de — −220 ms

`RegStore.prepareExport()` komutu metin döndürüyor, `_launchRegBatch` hepsini
`&` ile zincirleyip tek süreçte başlatıyor. Aynı pid tüm depolara veriliyor;
ilk bekleyiş süreci kapattığı için sonrakiler anında dönüyor.

**Tırnaklama:** `cmd /c "a & b"` biçiminde **dış tırnak yok**. cmd dış tırnağı
soyup yeniden ayrıştırırken `Local Settings` gibi boşluklu anahtar yollarındaki
iç tırnaklar bozuluyor. Dış tırnaksız biçim doğrulandı (7 depo, boşluklu
yollarla, 0 eksik yedek). Komut 7500 karakteri aşarsa depo depo başlatmaya
düşüyor.

### 4. Export beklemesi kritik yoldan çıktı

`enable()` export'ları başlatıp **beklemeden** dönüyor. Yarış penceresi
açılmıyor: export'lar aynı anda başlıyor, tek değişen bizim beklerken oturup
oturmadığımız; gözcüler de zaten export'tan ÖNCE kurulu.

Bitişi `_watchTick` **yoklayarak** tamamlıyor (`_finishSnapshot(false)` —
`ProcessExist` ile bakar, koşuyorsa hiç bloklamadan çıkar). Yedeğe DOKUNAN her
yol (`disable`, `audit`, `setDeepMode`, `cleanNow`) beklemeli sürümü çağırıp
tamamlanmayı garanti ediyor.

> **`SetTimer(..., -1)` KULLANMA.** Denendi: AHK ilk 15 ms'den sonra thread'i
> bölüyor, timer `enable()` daha dönmeden ateşleniyor ve bekleme kritik yola
> geri giriyor — ölçümde 62 ms yerine 843 ms.

### 5. Taban sayımı yedekten türetiliyor — arka plan takılması sıfır

`_baselineTick`/`_baselineIdx`/`_baselineReady`/`_baselineTimer` tamamen
kaldırıldı. Yerine `TraceStore.baselineCount(root)`:

- `RegStore` → `.reg` dosyasını say. `count()` = `Loop Reg "KVR"` = kökün
  ALTINDAKİLER; export kök için de `[...]` satırı yazdığından anahtar
  sayısından **1 düşülüyor**. `StrReplace` ile satır başı sayımı (`\n[`,
  `\n"`, `\n@=`) — 7 depoda `Loop Reg` ile **birebir** tuttuğu doğrulandı
  (9953 kayıtlık BagMRU dahil).
- `RegDeltaStore` → `-1` (kayıt sayısı anlamsız) + kendi `auditLine()`'ı:
  "oturumda kaç yeni kayıt doğdu".
- `FileGlobStore` → paket başlığındaki `u32`.

Maliyet `enable()`'dan `audit()`'e taşındı: 0 ms / 125–812 ms. Kullanıcı
"🔍 Denetle"ye bastığında zaten beklemeyi göze almış.

### 6. `.absent` sözleşmesi sertleştirildi — sessiz veri kaybı kapandı

`RegStore.endSnapshot`, `.reg` yoksa `.absent` yazıyordu. Bu iki AYRI durumu
karıştırıyordu: (a) anahtar gerçekten yok, (b) reg.exe patladı / zaman
aşımına uğradı. (b) durumunda restore, yıllardır duran DOLU bir anahtarı
"oturumda doğmuş" sanıp **komple siliyordu**. Artık `.absent` yalnız
`_keyExists()` false dönerse yazılıyor. (Doğrulandı: hayalet anahtara işaret
konuyor, export'u atlanan gerçek anahtara konmuyor.)

### 7. Küçük kalemler

- `SESSION` işareti artık yedeğin **başında** yazılıyor. Sonda yazılırken,
  export ortasındaki bir çökme "yedek yok" gibi görünüyor, kurtarma
  sunulmadığı için `POLICY.tsv` hiç okunmuyor ve `Start_TrackDocs` kalıcı
  kapalı takılıyordu.
- Rozet GUI'si (47 ms) ve `SoundBeep` (78 ms) `enable()`'dan sonraya alındı
  (`_afterEnable`).
- `FileGlobStore.restore` birebir aynı dosyayı yazmıyor (boyut+damga
  karşılaştırması) → değişiklik yokken 0 ms.

---

## Doğrulama altyapısı

Betikler `test/incognito/` altında (klasörün kendi `README.md`'si var).
`test/` gitignore'da, repoyu kirletmiyorlar. Ne doğruluyorlar:

- `verify.ahk` — `.reg` sayımı vs `Loop Reg` (7 depo), toplu cmd tırnaklaması,
  `.absent` sertleştirmesi, `FileGlobStore` paket round-trip (gerçek `.lnk`
  üzerinde, zaman damgası dahil), `tier` varsayılanları, `RegDeltaStore`
  denetim satırı.
- `bench.ahk` — paket vs klasör kopyası, dönüşümlü adil kıyas.
- `e2e/e2e.ahk` — gerçek `enable()`/`disable()` döngüsü, `App`/`State`/
  `TipType`/`ShowTip`/`jsongo` stub'larıyla. `A_ScriptDir` orası olduğu için
  `snapDir`, `optFile` ve perf log kullanıcının `Files\` klasörüne dokunmuyor.

### Kurallar (bunlara uy)

- **Sözdizimi doğrulaması sadece PowerShell'den.** Bash tool AHK argümanlarını
  bozuyor (`/validate` → MSYS yol dönüşümü), sessizce "temiz" görünür:
  ```powershell
  $exe='C:\Program Files\AutoHotkey\AutoHotkey64.exe'
  $psi=New-Object Diagnostics.ProcessStartInfo -Property @{
    FileName=$exe; Arguments="/ErrorStdOut /validate `"$f`"";
    RedirectStandardOutput=$true; RedirectStandardError=$true; UseShellExecute=$false }
  $p=[Diagnostics.Process]::Start($psi)
  if($p.WaitForExit(25000)){ $p.ExitCode; $p.StandardError.ReadToEnd() } else { $p.Kill() }
  ```
  Doğrulanacak dosya `AutoHotkey.ahk` — lib modülleri tek başına yüklenmez.
- **v2.1-alpha tuzakları:** çıplak ternary statement sözdizimi hatası;
  atanmamış global'e atıf LOAD hatası; `if (...)` + parantezsiz `try` sonrası
  `else` hata verir; **auto-execute bölümünde `local` bildirimi geçersiz**
  (yalnız fonksiyon içinde); çift tırnaklı dizede `\"` yok, `""` var.
- **`this.coupled` listesini bozma** (bkz. Kademe).
- **Zamanlama kıyaslarını DÖNÜŞÜMLÜ yap.** Tek geçişte ölçmek sıcak/soğuk
  önbellek yüzünden tabloyu tersine çevirebiliyor (bkz. paket kıyası).

---

## Kalan iş

1. **`this.perfLog := true` hâlâ AÇIK** (`incognito.ahk` `__New`). Kullanıcı
   kendi tarafında iyileşmeyi görebilsin diye bırakıldı; kapatmak tek satır.
2. **Derin kademede export hâlâ sırayla koşuyor** — tek `cmd.exe` içinde
   ardışık. `start /b` ile paralelleştirmek ölçümde 828 → 360 ms veriyordu
   (14 depo). Ama `start /b` hemen döndüğü için `ProcessWaitClose` işe
   yaramaz; tamamlanmayı anlamak için sentinel dosya ya da yoklama gerekir.
   Şu an bu bekleme zaten kritik yolun dışında (madde 4), o yüzden acil değil.
3. **Thumbcache — modülün en büyük açığı, hâlâ açık.** Explorer'da
   önizlediğin her görselin küçük resmi `thumbcache_*.db`'de kalıyor ve
   **dosya silinse bile duruyor** (bu makinede ~1,1 GB). Dosyaları Explorer
   açık tuttuğu için ne kilitlenebiliyor ne silinebiliyor.
   **Test edilecek soru:** `DisableThumbnailCache`
   (`HKCU\...\Explorer\Advanced`) ve/veya `NoThumbnailCache`
   (`HKCU\...\Policies\Explorer`) DWORD=1, **Explorer yeniden başlatılmadan**
   etkili oluyor mu?
   1. `thumbcache_*.db` boyut + `LastWriteTime` not et
   2. Değeri yaz
   3. Daha önce açılmamış, görsel dolu bir klasör aç
   4. db büyüdü mü / damga değişti mi bak
   5. Değeri geri al

   **Etkiliyse:** `PolicyGuard`'a ekle — maliyet sıfır, iz hiç oluşmuyor.
   Yan etki: incognito açıkken Explorer'da küçük resim yerine simge.
   **Etkili değilse:** Explorer'ı toggle başına yeniden başlatmak gerekir
   (açık pencereler kapanır) — kullanıcının kararı, tek başına yapılmasın.

   Görsel/video izleri bu kullanıcının **asıl derdi** olduğu için bu madde
   kademe işinden daha önemli olabilir.
4. **`clip_hist.ahk:100` — incognito açıkken metinler hâlâ kaydediliyor.**
   `App.Incognito.isActive()` kontrolü yalnız `processImage()` içinde,
   `processClipboard()` içinde yok. Tek satır. (`TODO.md` P0)
