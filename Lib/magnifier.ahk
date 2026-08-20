; ════════════════════════════════════════════════════════════════════════
;  magnifier.ahk — Windows Magnifier'ı açık tutup yalnız kademesini değiştir
; ────────────────────────────────────────────────────────────────────────
;  TASARIM KARARI (önce yanlış yoldan gidildi, notu duruyor):
;
;  1. Win+= / Win+Esc  : her toggle'da magnifier.exe'yi açıp kapatıyordu.
;     Pahalı; ekranda araç çubuğu bırakıyor. ELENDİ.
;  2. Magnification API (MagSetFullscreenTransform) ile kendi büyütmemiz:
;     geçiş anında oluyordu ama API fareyi İZLEMİYOR — takip, kenar
;     davranışı ve çok monitör mantığını elle yazmak gerekti. Her seferinde
;     yeni bir kenar durumu çıktı (soldaki monitör negatif X'te kalıyor,
;     ekran geçişinde zıplama, sanal masaüstü tek yüzey...). Windows'un
;     yaptığı işi taklit etmek kırılgandı. ELENDİ.
;  3. BU: magnifier.exe bir kez açılır ve AÇIK KALIR; toggle yalnız zoom
;     kademesini değiştirir. Açılış/kapanış maliyeti yok, fare takibi +
;     kenar davranışı + çok monitör tamamen Windows'un. Bizde koordinat
;     hesabı yok.
;
;  ÖLÇÜM (2026-08-16, Win10 19045): magnifier çalışırken Win+= gönderildiğinde
;  HKCU\...\ScreenMagnifier\Magnification ANINDA güncelleniyor (0 ms sonraki
;  okuma bile yeni değeri veriyor). Bu yüzden durum için ayrı bir bayrak
;  tutmuyoruz — tek doğru kaynak registry. Kullanıcı büyütmeyi kendi
;  klavyesiyle değiştirse bile senkron kalırız.
;
;  Zoom adımı kullanıcının ayarı (Ayarlar → Erişilebilirlik → Büyüteç →
;  "Yakınlaştırma artışı"). Bu makinede %100, yani tek vuruş 100 → 200.
;  Bu yüzden %100'e dönüş tek Send değil, hedefe varana kadar döngü.
; ════════════════════════════════════════════════════════════════════════

class singleMagnifier {
    static instance := ""

    static getInstance() {
        if (!singleMagnifier.instance) {
            singleMagnifier.instance := singleMagnifier()
        }
        return singleMagnifier.instance
    }

    __New() {
        if (singleMagnifier.instance) {
            throw Error("singleMagnifier zaten oluşturuldu! getInstance kullan.")
        }
        this.regKey := "HKCU\Software\Microsoft\ScreenMagnifier"
        this.zoomLevel := 200        ; toggle'ın çıktığı seviye (yüzde)
        ; Ardışık zoom tuşları arasındaki zorunlu boşluk. ÖLÇÜLDÜ (3 kademe
        ; gönderip kaçının işlendiğine bakarak): 0/50ms → 1/3, 100ms → 2/3,
        ; 150ms ve üstü → 3/3. 180 = güvenlik payıyla eşik üstü.
        this.stepGap := 180
    }

    ; ── Durum ───────────────────────────────────────────────────────────
    ; Yüzde olarak şu anki büyütme; magnifier kapalıysa 100.
    level() {
        if (!ProcessExist("Magnify.exe"))
            return 100
        try {
            return RegRead(this.regKey, "Magnification", 100)
        } catch {
            return 100
        }
    }

    isZoomed() => this.level() > 100

    ; ── Aç / Kapa ───────────────────────────────────────────────────────
    ; NOT: v2.1-alpha'da çıplak ternary-statement syntax error verir — if/else.
    toggle() {
        if (this.isZoomed())
            this.reset()
        else
            this.zoomTo(this.zoomLevel)
    }

    ; Hedef yüzdeye çık/in. Adım boyutu kullanıcı ayarına bağlı olduğu için
    ; kademeleri tek tek gönderip her seferinde registry'den doğruluyoruz;
    ; sonsuz döngüye karşı hem tur sınırı hem "değer değişmedi" kontrolü var.
    zoomTo(target) {
        if (!this._ensureRunning())
            return false
        local first := true
        loop 12 {
            local cur := this.level()
            if (cur == target)
                return true
            ; Ardışık tuşlar için zorunlu boşluk (ölçüm: <150ms yutuluyor).
            ; Yalnız 2. ve sonraki kademeye uygulanır — tek kademelik normal
            ; toggle bundan etkilenmez.
            if (!first)
                Sleep this.stepGap
            first := false
            if (cur < target)
                Send("#{NumpadAdd}")
            else
                Send("#{NumpadSub}")
            if (!this._waitChange(cur))    ; tuş işlenmedi ya da sınıra dayandık
                return false
        }
        return false
    }

    ; Registry değeri değişene kadar bekle. SABİT uyku YETMİYOR: art arda hızlı
    ; gönderilen tuşlarda magnifier ikinciyi ~40ms içinde işlemeyebiliyor ve
    ; "değişmedi" görünüp döngü erken kesiliyordu (300 → 200'de takılma hatası).
    ; Tek tuş gönderildiğinde güncelleme yine anlık; bu yoklama yalnız yavaş
    ; durumda bekliyor, normalde ilk turda dönüyor.
    _waitChange(before, timeoutMs := 400) {
        local t := A_TickCount
        while (A_TickCount - t < timeoutMs) {
            Sleep 20
            if (this.level() != before)
                return true
        }
        return false
    }

    ; %100'e dön (magnifier açık kalır). Panik tuşundan da çağrılır.
    reset() {
        if (ProcessExist("Magnify.exe"))
            this.zoomTo(100)
    }

    ; Magnifier'ı tamamen kapat — istersen menüden bağlarsın.
    close() {
        this.reset()
        try ProcessClose("Magnify.exe")
    }

    ; ── İç işler ────────────────────────────────────────────────────────
    ; Magnifier'ı ilk kullanımda başlatır, sonra açık bırakır. Script
    ; açılışında değil ilk toggle'da başlatıyoruz: hiç kullanmayan oturumda
    ; boşuna çalışmasın. Bedeli oturumdaki İLK toggle'ın yavaş olması.
    _ensureRunning() {
        if (ProcessExist("Magnify.exe"))
            return true
        try Run("Magnify.exe")
        catch as e {
            try App.ErrHandler.handleError("magnifier baslatilamadi: " e.Message)
            return false
        }
        ; Hazır olmasını bekle — erken gönderilen tuş yutuluyor.
        loop 30 {
            Sleep 100
            if (ProcessExist("Magnify.exe") && this._running())
                return true
        }
        return ProcessExist("Magnify.exe") ? true : false
    }

    _running() {
        try {
            return RegRead(this.regKey, "RunningState", 0) == 1
        } catch {
            return false
        }
    }
}
