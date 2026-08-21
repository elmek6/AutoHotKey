#Include <OCR>
; ═══════════════════════════════════════════════════════════
; singleScreenOcr — Ekrandan alan seçip içindeki metni okur.
; Win11 Snipping Tool'un "Metin işlemleri" özelliğinin karşılığı.
; Sonuç PANOYA gider, ayrıca hiçbir yere kaydedilmez.
;
; MOTOR: Windows.Media.Ocr (UWP). Win10 build 10240'tan beri sistemde gömülü,
; ÇEVRİMDIŞI çalışır, ek kurulum ve lisans yok. Sarmalayıcı Descolada/OCR
; (MIT) — Lib/OCR.ahk, upstream'den olduğu gibi alındı, DEĞİŞTİRİLMEDİ:
;   https://github.com/Descolada/OCR
;
; ── İKİ AKIŞ ────────────────────────────────────────────────
; 1) snipInteractive()  (F13+o, ana akış)
;    Seç → alan ekranda KALIR, kenarlarından büyütülüp küçültülebilir,
;    içinden sürüklenip taşınabilir. Altında panel: metin (seçilebilir,
;    düzenlenebilir), solda dil, ortada kolon biçimi, sağda Kopyala.
; 2) snip(mode)  (menüden "Hızlı")
;    Seç → oku → panoya. Pencere yok. Tek atışlık kullanım için.
;
; ── EKRAN YAKALAMA: NEDEN TEK ÇEKİM ─────────────────────────
; Panelde dil/ölçek değiştirilince yeniden OCR gerekiyor. Her seferinde
; ekranı yeniden çekseydik, çerçeve+tutamaçları gizle → bir kare bekle →
; çek → geri göster döngüsü yaşanır, ekran titrerdi. Bunun yerine dikdörtgen
; DEĞİŞTİĞİNDE bir kez OCR.CreateHBitmap ile çekilip this.shot'ta tutuluyor;
; dil/ölçek değişimi bu bitmap üzerinden OCR.FromBitmap ile yeniden okunuyor,
; kolon biçimi değişimi ise hiç OCR bile gerektirmiyor (cache'li Result).
;
; ── ÖRTÜ (dim) NEDEN SADECE 1. FAZDA ────────────────────────
; İlk sürükleme sırasında tüm sanal ekranı kaplayan yarı saydam örtü var;
; tıklamaları yutuyor, alttaki uygulamaya kaza tıklaması gitmiyor. Ayarlama
; fazında örtü KAPATILIYOR: hem ekranı normal görüyorsun hem de yakalama
; öncesi gizlenecek pencere sayısı ikiye iniyor (çerçeve + tutamaçlar).
; Yakalamadan önce bunları gizleyip bir kare beklemek ŞART — yoksa kırmızı
; çerçeve görüntünün içine karışır ve OCR onu da okumaya çalışır.
;
; DİKKAT: OCR.ahk'nin static __New()'i YÜKLENME ANINDA WinRT sınıf
; fabrikalarını (OcrEngineStatics dahil) kuruyor. Yani #Include etmenin
; script açılışına bir maliyeti var — ilk snip()'te değil, açılışta ödenir.
; ═══════════════════════════════════════════════════════════
class singleScreenOcr {
    static instance := ""

    ; Bundan küçük seçim "yanlışlıkla tıkladım" sayılır, sessizce iptal.
    static MIN_SIZE := 8
    ; Çerçeve/tutamaç gizlendikten sonra DWM'in temiz kareyi çizme süresi.
    static SETTLE_MS := 70
    ; Örtü koyuluğu (0-255). Düşük tutuluyor: kullanıcı ne seçtiğini görmeli.
    static DIM_ALPHA := 90
    ; Kenar yakalama toleransı (px) ve tutamaç karesinin yarı boyu.
    static GRAB_TOL := 8
    static GRIP_HALF := 5
    ; Tutamaçlar bu boyutun altında üst üste binip birbirini yiyor (tek-çift
    ; dolgu kuralı) — küçük seçimde yalnız çerçeve gösteriliyor.
    static GRIP_MIN := 44

    static getInstance() {
        if (!singleScreenOcr.instance)
            singleScreenOcr.instance := singleScreenOcr()
        return singleScreenOcr.instance
    }

    __New() {
        if (singleScreenOcr.instance)
            throw Error("ScreenOcr zaten oluşturulmuş! getInstance kullan.")
        this.overlay := 0
        this.band    := 0       ; seçim çerçevesi (halka)
        this.grips   := 0       ; 8 tutamaç karesi
        this.panel   := 0       ; sonuç paneli
        this.txtBox := 0, this.langBox := 0, this.modeBox := 0, this.statusTxt := 0
        this.session := false
        this.rect    := 0
        this.shot    := 0       ; yakalanan HBITMAP sarmalayıcısı (kendi __Delete'i var)
        this.lastRes := 0       ; cache'li OCR.Result — kolon biçimi değişimi bunu kullanır
        this.langs   := []      ; panel DDL'inin sırasıyla eşleşen dil kodları
        this.lang    := ""      ; "" → kütüphanenin varsayılanı (ilk kurulu dil)
        this.scale   := 2       ; OCR öncesi büyütme; 96 DPI'da 8-9pt UI fontları sınırda
        this.grayscale := true  ; ClearType alt-piksel izini temizler
        this.gutter  := 0       ; kolon ayracı eşiği (px); 0 = otomatik
        this.lastMs  := 0
        ; Hotkey/OnMessage kayıt VE kaldırma AYNI nesneyle yapılmalı — her
        ; seferinde yeni ObjBindMethod üretmek kaldırmayı sessizce başarısız
        ; kılıp handler biriktiriyor (array_filter ve clip_image_dialog dersi).
        this.cursorBound     := ObjBindMethod(this, "_onSetCursor")
        this.canvasIfBound   := (*) => this._isOverCanvas()
        this.canvasClickBound := (*) => this._onCanvasClick()
    }

    ; ── Genel API ────────────────────────────────────────────────────────────

    ; ANA AKIŞ: seç → ayarla → panelden al.
    snipInteractive() {
        if (this.session)
            this._closeSession()
        local r := this._selectRect()
        if (!r)
            return
        this._openSession(r)
    }

    ; HIZLI AKIŞ: seç → oku → panoya. Pencere yok.
    ; mode: "plain" | "columns" | "table"
    snip(mode := "plain") {
        local r := this._selectRect()
        if (!r)
            return ""
        ; Örtü kapandı; ekranın temiz halini yakalayabilmek için bir kare bekle.
        Sleep(singleScreenOcr.SETTLE_MS)
        local res := this._ocrRect(r.x, r.y, r.w, r.h)
        if (!res)
            return ""
        local out := this._layout(res, mode)
        return this._finish(out.text, out.info)
    }

    ; Aktif pencerenin tamamını oku. Örtü/seçim yok, tek çağrı.
    ; FromWindow PrintWindow kullanıyor → pencere kısmen örtülü olsa da okunur.
    readWindow(mode := "plain") {
        local res := 0
        this._ensureLang()
        try {
            local t := A_TickCount
            res := OCR.FromWindow("A", this._opts())
            this.lastMs := A_TickCount - t
        } catch as err {
            App.ErrHandler.handleError("ScreenOcr.readWindow: " err.Message, err)
            ShowTip("OCR hatası: " err.Message, TipType.Error, 2500)
            return ""
        }
        local out := this._layout(res, mode)
        return this._finish(out.text, out.info)
    }

    ; ── Menü ─────────────────────────────────────────────────────────────────

    ; F13 menüsüne alt menü olarak takılıyor. Her açılışta yeniden kuruluyor,
    ; bu yüzden işaretler (Check) her zaman güncel.
    buildMenu() {
        local m := Menu()
        m.Add("Alan seç ve oku (pencereli)`tF13+o", (*) => this.snipInteractive())
        m.Add()
        m.Add("Hızlı — düz metin", (*) => this.snip("plain"))
        m.Add("Hızlı — kolonlu (sırayla)", (*) => this.snip("columns"))
        m.Add("Hızlı — tablo (TAB ayraçlı)", (*) => this.snip("table"))
        m.Add("Aktif pencereyi oku", (*) => this.readWindow())
        m.Add()

        local sub := Menu()
        for s in [1, 2, 3, 4] {
            ; IIFE ile döngü değişkenini yakala (kod tabanındaki ortak deyim)
            sub.Add("x" s, ((v) => (*) => this._setScale(v))(s))
            if (s == this.scale)
                sub.Check("x" s)
        }
        m.Add("Ölçek (OCR öncesi büyütme)", sub)

        m.Add("Gri tonlama", (*) => this._toggleGray())
        if (this.grayscale)
            m.Check("Gri tonlama")

        m.Add("Kolon boşluk eşiği", this._buildGutterMenu())
        this._ensureLang()
        m.Add("Dil: " (this.lang == "" ? "yok!" : this.lang), this._buildLangMenu())
        return m
    }

    ; Kolon ayracı sayılacak en küçük boş dikey şerit.
    ; Çok küçük → kelime araları kolon sanılır. Çok büyük → kolonlar birleşir.
    _buildGutterMenu() {
        local m := Menu()
        m.Add("Otomatik (satır yüksekliği x1.5)", (*) => this._setGutter(0))
        if (this.gutter == 0)
            m.Check("Otomatik (satır yüksekliği x1.5)")
        m.Add()
        for g in [20, 40, 80, 150] {
            m.Add(g "px", ((v) => (*) => this._setGutter(v))(g))
            if (g == this.gutter)
                m.Check(g "px")
        }
        return m
    }

    ; Sistemde OCR yeteneği KURULU dillerin listesi. Boşsa dil paketi yok demektir.
    ; Kurulum (admin PowerShell):
    ;   Get-WindowsCapability -Online -Name "Language.OCR*"
    ;   Add-WindowsCapability -Online -Name "Language.OCR~~~tr-TR~0.0.1.0"
    _buildLangMenu() {
        local m := Menu()
        local langs := this.availableLanguages()
        if (langs.Length == 0) {
            m.Add("Kurulu OCR dili bulunamadı!", (*) => 0)
            return m
        }
        for code in langs {
            m.Add(code, ((c) => (*) => this._setLang(c))(code))
            if (code == this.lang)
                m.Check(code)
        }
        return m
    }

    ; Arayüzde "(varsayılan)" diye MUĞLAK bir giriş göstermiyoruz.
    ; Kütüphanenin varsayılanı TryCreateFromUserProfileLanguages, yani Windows'un
    ; kullanıcı profili dillerinden KENDİ seçtiği motor — hangisini seçtiğini geri
    ; vermiyor, dolayısıyla kullanıcıya gösterilecek bir karşılığı yok. Onun yerine
    ; sistem yerel ayarına en yakın KURULU dili seçip kodunu açıkça gösteriyoruz.
    _ensureLang() {
        if (this.lang != "")
            return
        local avail := this.availableLanguages()
        if (avail.Length == 0)
            return
        local loc := this._systemLocale()
        for code in avail {
            if (code = loc) {
                this.lang := code
                return
            }
        }
        if (loc != "") {
            for code in avail {
                if (SubStr(code, 1, 2) = SubStr(loc, 1, 2)) {
                    this.lang := code
                    return
                }
            }
        }
        this.lang := avail[1]
    }

    ; Windows kullanıcı yerel ayarı, ör. "tr-TR". Alınamazsa "".
    _systemLocale() {
        local buf := Buffer(85 * 2, 0)
        local n := DllCall("GetUserDefaultLocaleName", "Ptr", buf, "Int", 85)
        return n ? StrGet(buf, "UTF-16") : ""
    }

    ; Kurulu OCR dilleri (BCP-47 etiketleri). Hata durumunda boş dizi.
    availableLanguages() {
        local out := []
        try {
            for line in StrSplit(OCR.GetAvailableLanguages(), "`n", " `t`r") {
                if (line != "")
                    out.Push(line)
            }
        } catch as err {
            App.ErrHandler.handleError("ScreenOcr.availableLanguages: " err.Message, err, true)
        }
        return out
    }

    getStatsInfo() {
        local langs := this.availableLanguages()
        return ["OCR: " langs.Length " dil kurulu"
              . (this.lastMs > 0 ? ", son okuma " this.lastMs " ms" : "")]
    }

    ; ── OCR çağrısı ──────────────────────────────────────────────────────────

    _opts() {
        local o := { scale: this.scale, grayscale: this.grayscale ? 1 : 0 }
        if (this.lang != "")
            o.lang := this.lang
        return o
    }

    ; Hızlı akış: ekrandan doğrudan. OCR.Result | hata durumunda 0.
    ; Metin DEĞİL nesne dönüyor: kolon/tablo düzeni için Words[] koordinatları lazım.
    _ocrRect(x, y, w, h) {
        this._ensureLang()
        try {
            local t := A_TickCount
            local res := OCR.FromRect(x, y, w, h, this._opts())
            this.lastMs := A_TickCount - t
            return res
        } catch as err {
            App.ErrHandler.handleError("ScreenOcr._ocrRect: " err.Message, err)
            ShowTip("OCR hatası: " err.Message, TipType.Error, 2500)
            return 0
        }
    }

    ; ── Düzen (kolon / tablo) ────────────────────────────────────────────────
    ;
    ; NEDEN GEREKLİ: Windows.Media.Ocr SATIR bazlı çalışır ve iki kolonlu bir
    ; düzende iki kolonun aynı yükseklikteki kelimelerini TEK Line içinde
    ; birleştirir. res.Text bu yüzden "sol hücre  sağ hücre  sol hücre  sağ
    ; hücre" diye karışık çıkar. Motorun kolon kavramı YOK — bizim eklememiz gerek.
    ;
    ; YÖNTEM: kelimelerin x aralıkları birleştirilir; aralarında kalan yeterince
    ; geniş BOŞ dikey şeritler (gutter) kolon ayracıdır. Piksel histogramı yerine
    ; aralık birleştirme — O(n log n), büyük dizi ayırmıyor.
    ;
    ; SINIRI: gerçekten hizalı kolonlar gerekir. Sarmalanmış (wrap) paragraf
    ; metninde ayraç bulunamaz ve düz metne düşer — bu doğru davranış, durum
    ; satırında "kolon ayracı yok" diye söylenir.

    _layout(res, mode) {
        local plain := Trim(res.Text, " `t`r`n")
        if (mode == "plain")
            return { text: plain, info: "düz metin" }

        local ws := []
        for w in res.Words {
            local wt := Trim(w.Text, " `t`r`n")
            if (wt != "")
                ws.Push({ x: w.x, w: w.w, cx: w.x + w.w // 2, cy: w.y + w.h // 2, h: w.h, t: wt })
        }
        if (ws.Length == 0)
            return { text: plain, info: "kelime yok" }

        local medH := this._median(ws, "h")
        local gutterMin := (this.gutter > 0) ? this.gutter : Max(16, Round(medH * 1.5))
        local splits := this._findColumnSplits(ws, gutterMin)
        if (splits.Length == 0)
            return { text: plain, info: "⚠ kolon ayracı yok (eşik " gutterMin "px) → düz metin" }

        OCR.SortArray(ws, "N", "cy")
        ; Satır eşiği: aynı satırdaki kelimelerin y-merkezleri karakter
        ; yüksekliğinin yarısından fazla oynamaz.
        local rows := this._groupRows(ws, Max(4, medH // 2))
        for row in rows
            OCR.SortArray(row, "N", "cx")

        local nCol := splits.Length + 1
        local suffix := nCol " kolon × " rows.Length " satır · eşik " gutterMin "px"
        if (mode == "table")
            return { text: this._tableText(rows, splits, nCol), info: "tablo · " suffix }
        return { text: this._columnsText(rows, splits, nCol), info: "kolon · " suffix }
    }

    ; Satırlar hizalı, hücreler TAB ayraçlı → Excel'e doğrudan yapıştırılır.
    _tableText(rows, splits, nCol) {
        local out := ""
        for row in rows {
            local cells := []
            loop nCol
                cells.Push("")
            for it in row {
                local ci := this._colIndex(it.cx, splits)
                cells[ci] .= (cells[ci] == "" ? "" : " ") it.t
            }
            local line := ""
            loop nCol
                line .= (A_Index == 1 ? "" : "`t") cells[A_Index]
            if (Trim(line, " `t") != "")
                out .= line "`n"
        }
        return RTrim(out, "`n")
    }

    ; Kolonlar SIRAYLA alt alta, aralarında boş satır → iki sütunlu makale/form
    ; düzeninde doğru okuma sırası.
    _columnsText(rows, splits, nCol) {
        local out := ""
        loop nCol {
            local ci := A_Index
            local block := ""
            for row in rows {
                local line := ""
                for it in row {
                    if (this._colIndex(it.cx, splits) == ci)
                        line .= (line == "" ? "" : " ") it.t
                }
                if (line != "")
                    block .= line "`n"
            }
            if (block != "")
                out .= (out == "" ? "" : "`n") RTrim(block, "`n") "`n"
        }
        return RTrim(out, "`n")
    }

    ; Kelimelerin x aralıklarını birleştirip aralarındaki geniş boşlukların
    ; ORTASINI bölme noktası olarak döndürür. Boş dizi = tek kolon.
    _findColumnSplits(ws, gutterMin) {
        if (ws.Length == 0)
            return []
        local iv := []
        for it in ws
            iv.Push({ a: it.x, b: it.x + it.w })
        OCR.SortArray(iv, "N", "a")

        local merged := [], cur := { a: iv[1].a, b: iv[1].b }
        loop iv.Length - 1 {
            local r := iv[A_Index + 1]
            if (r.a <= cur.b) {
                if (r.b > cur.b)
                    cur.b := r.b
            } else {
                merged.Push(cur)
                cur := { a: r.a, b: r.b }
            }
        }
        merged.Push(cur)

        local splits := []
        loop merged.Length - 1 {
            local gap := merged[A_Index + 1].a - merged[A_Index].b
            if (gap >= gutterMin)
                splits.Push(merged[A_Index].b + gap // 2)
        }
        return splits
    }

    ; cy'ye göre SIRALANMIŞ kelimeleri satırlara böler.
    _groupRows(ws, rowEps) {
        local rows := [], cur := [], baseCy := 0
        for it in ws {
            if (cur.Length == 0) {
                cur.Push(it)
                baseCy := it.cy
                continue
            }
            if (Abs(it.cy - baseCy) > rowEps) {
                rows.Push(cur)
                cur := [it]
                baseCy := it.cy
            } else {
                cur.Push(it)
            }
        }
        if (cur.Length > 0)
            rows.Push(cur)
        return rows
    }

    ; Merkez x hangi kolona düşüyor (1 tabanlı).
    _colIndex(cx, splits) {
        local i := 1
        for s in splits {
            if (cx < s)
                return i
            i += 1
        }
        return i
    }

    _median(items, key) {
        if (items.Length == 0)
            return 0
        local vals := []
        for it in items
            vals.Push(it.%key%)
        OCR.SortArray(vals, "N")
        return vals[(vals.Length + 1) // 2]
    }

    ; ── Oturum (pencereli akış) ──────────────────────────────────────────────

    _openSession(r) {
        this.session := true
        this.rect := r
        this._buildPanel()
        this._drawChrome()
        this.panel.Show()
        this._placePanel()
        ; Fare etkileşimi: clip_image_dialog'daki deyim — kriter SABİT bir
        ; fonksiyon nesnesi. "ahk_id <hwnd>" kullanılsaydı her oturumda yeni
        ; hotkey varyantı kaydedilir ve varyantlar birikirdi.
        HotIf(this.canvasIfBound)
        Hotkey("~LButton", this.canvasClickBound, "On")
        HotIf()
        OnMessage(0x20, this.cursorBound)
        this._refreshCapture()
    }

    _closeSession() {
        this.session := false
        try {
            HotIf(this.canvasIfBound)
            Hotkey("~LButton", "Off")
            HotIf()
        }
        try OnMessage(0x20, this.cursorBound, 0)
        for g in [this.band, this.grips, this.panel] {
            if (g)
                try g.Destroy()
        }
        this.band := 0, this.grips := 0, this.panel := 0
        this.txtBox := 0, this.langBox := 0, this.modeBox := 0, this.statusTxt := 0
        this.shot := 0        ; sarmalayıcının __Delete'i HBITMAP+DC'yi bırakır
        this.lastRes := 0
    }

    ; ── Panel ────────────────────────────────────────────────────────────────

    _buildPanel() {
        this._ensureLang()
        this.langs := this.availableLanguages()
        local chosen := 1
        for code in this.langs {
            if (code == this.lang)
                chosen := A_Index
        }

        this.panel := Gui("+AlwaysOnTop +ToolWindow +Resize", "OCR — seçili alan")
        this.panel.MarginX := 8, this.panel.MarginY := 8
        this.panel.SetFont("s10", "Segoe UI")
        ; Düzenlenebilir bırakıldı: OCR l/1/I ve 0/O karıştırır, elle düzeltmek
        ; yeniden taramaktan hızlı. Seçim yapılırsa Kopyala YALNIZ seçimi alır.
        this.txtBox := this.panel.AddEdit("w660 r12 +VScroll Multi")

        this.panel.SetFont("s8 c505050")
        this.statusTxt := this.panel.AddText("xm y+4 w660 h16", "okunuyor...")
        this.panel.SetFont("s10")

        this.panel.SetFont("s9")
        this.panel.AddText("xm y+8 w150 h16", "Dil")
        this.panel.AddText("x+8 yp w230 h16", "Biçim")
        ; LİSTE, dropdown DEĞİL. İki sebep:
        ;  1) Tek tıkla seçim — aç / seç / kapan turu yok.
        ;  2) Açık bir DropDownList'in listesi (ComboLBox) AYRI bir ÜST DÜZEY
        ;     penceredir. ~LButton kancamız oradaki tıklamayı "tuvale tıklandı"
        ;     sanıp seçimi iptal ediyordu; seçim de bu yüzden commit olmuyor,
        ;     biçim hep "Düz metin"e geri dönüyordu. Liste alt kontrol, sorun yok.
        this.langBox := this.panel.AddListBox("xm y+2 w150 r4 Choose" chosen, this.langs)
        this.modeBox := this.panel.AddListBox("x+8 yp w230 r4 Choose1",
                            ["Düz metin", "Kolonlu (sırayla)", "Tablo (TAB ayraçlı)"])
        this.panel.AddButton("x+12 yp w120 h36 Default", "Kopyala").OnEvent("Click", (*) => this._copy())

        ; Dil değişince yeniden OCR gerekir ama EKRANI TEKRAR ÇEKMEYE GEREK YOK
        ; (this.shot duruyor). Kolon biçimi ise OCR bile gerektirmez.
        this.langBox.OnEvent("Change", (*) => this._onLangChange())
        this.modeBox.OnEvent("Change", (*) => this._applyLayout())
        this.panel.OnEvent("Escape", (*) => this._closeSession())
        this.panel.OnEvent("Close", (*) => this._closeSession())
    }

    ; Seçilen alanın altına yerleştir; altta yer yoksa üstüne al.
    _placePanel() {
        if (!this.panel)
            return
        local pw := 0, ph := 0
        this.panel.GetPos(, , &pw, &ph)
        local vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
        local px := this.rect.x
        local py := this.rect.y + this.rect.h + 16
        if (py + ph > vy + vh)
            py := this.rect.y - ph - 16
        if (py < vy)
            py := vy
        if (px + pw > vx + vw)
            px := vx + vw - pw
        if (px < vx)
            px := vx
        this.panel.Move(px, py)
    }

    ; Panel seçili alanı örtüyor mu? Örtüyorsa yakalamadan önce gizlenmeli.
    _panelOverlaps() {
        if (!this.panel)
            return false
        local px := 0, py := 0, pw := 0, ph := 0
        try this.panel.GetPos(&px, &py, &pw, &ph)
        catch
            return false
        local r := this.rect
        return !(px > r.x + r.w || px + pw < r.x || py > r.y + r.h || py + ph < r.y)
    }

    _onLangChange() {
        local i := this.langBox.Value
        if (i < 1 || i > this.langs.Length)
            return
        this.lang := this.langs[i]
        this._reOcr()
    }

    _modeKey() {
        local i := this.modeBox ? this.modeBox.Value : 1
        if (i == 2)
            return "columns"
        if (i == 3)
            return "table"
        return "plain"
    }

    ; Dikdörtgen değişti → ekranı yeniden çek + oku.
    _refreshCapture() {
        if (!this.session)
            return
        this._setStatus("yakalanıyor...")
        this.shot := this._capture()
        if (!this.shot) {
            this._setStatus("⚠ ekran yakalanamadı")
            return
        }
        this._reOcr()
    }

    ; this.shot üzerinden yeniden oku (dil/ölçek değişimi burayı kullanır).
    _reOcr() {
        if (!this.session || !this.shot)
            return
        try {
            local t := A_TickCount
            this.lastRes := OCR.FromBitmap(this.shot, this._opts())
            this.lastMs := A_TickCount - t
        } catch as err {
            App.ErrHandler.handleError("ScreenOcr._reOcr: " err.Message, err)
            this._setStatus("⚠ OCR hatası: " err.Message)
            return
        }
        this._applyLayout()
    }

    ; Yalnız biçimlendirme — OCR tekrarlanmaz, cache'li Result kullanılır.
    _applyLayout() {
        if (!this.session || !this.lastRes || !this.txtBox)
            return
        local out := this._layout(this.lastRes, this._modeKey())
        this.txtBox.Value := out.text
        this._setStatus(this.rect.w "×" this.rect.h " px · " this.lang " · " this.lastMs " ms · "
                      . StrLen(out.text) " karakter · " out.info
                      . " · ölçek x" this.scale (this.grayscale ? " · gri" : ""))
    }

    _setStatus(s) {
        if (this.statusTxt)
            try this.statusTxt.Value := s
    }

    ; Edit'te seçili parça varsa YALNIZ onu, yoksa metnin tamamını kopyala.
    ; Seçim için WM_COPY kullanılıyor: kontrol panoya kendisi yazdığı için
    ; Edit'in CRLF'i ile AHK'nin LF'i arasındaki ofset farkı derdi hiç doğmuyor.
    _copy() {
        if (!this.txtBox)
            return
        local a := Buffer(4, 0), b := Buffer(4, 0)
        SendMessage(0xB0, a, b, this.txtBox.Hwnd)          ; EM_GETSEL
        local hasSel := NumGet(b, 0, "UInt") > NumGet(a, 0, "UInt")
        if (hasSel) {
            SendMessage(0x0301, 0, 0, this.txtBox.Hwnd)    ; WM_COPY
            ShowTip("Seçili kısım kopyalandı", TipType.Copy, 1000)
        } else {
            A_Clipboard := this.txtBox.Value
            ShowTip(this.txtBox.Value, TipType.Copy, 2000)
        }
        this._closeSession()
    }

    ; ── Çerçeve + tutamaçlar ─────────────────────────────────────────────────
    ;
    ; BÖLGELER GDI İLE KURULUYOR. Önce WinSetRegion'un nokta listesi
    ; kullanılıyordu; AHK o listeyi TEK BİR POLİGON olarak yorumluyor. Halka
    ; için sorun çıkmıyor (dış çerçeve + iç çerçeve), ama 8 AYRIK tutamaç
    ; karesi verilince kareleri birbirine bağlayıp ekranda dev ÜÇGENLER
    ; çiziyordu. CreateRectRgn + CombineRgn(RGN_OR) ayrık dikdörtgenlerin
    ; birleşimini kesin veriyor; çerçeve de 4 çubuk olarak aynı yoldan çiziliyor.

    ; SetWindowRgn bölgenin SAHİPLİĞİNİ DEVRALIR → burada DeleteObject ETMİYORUZ.
    ; (clip_image_dialog'daki HBITMAP sahipliği kuralının aynısı.)
    _setRegion(g, rects) {
        local total := DllCall("gdi32\CreateRectRgn", "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr")
        if (!total)
            return
        for r in rects {
            local one := DllCall("gdi32\CreateRectRgn", "Int", r[1], "Int", r[2], "Int", r[3], "Int", r[4], "Ptr")
            if (!one)
                continue
            DllCall("gdi32\CombineRgn", "Ptr", total, "Ptr", total, "Ptr", one, "Int", 2)   ; RGN_OR
            DllCall("gdi32\DeleteObject", "Ptr", one)
        }
        DllCall("SetWindowRgn", "Ptr", g.Hwnd, "Ptr", total, "Int", true)
    }

    _drawChrome() {
        if (!this.rect)
            return
        local r := this.rect
        this._drawSelection(r.x, r.y, r.w, r.h, 3, true)
    }

    _hideChrome(alsoPanel := false) {
        if (this.band)
            try this.band.Hide()
        if (this.grips)
            try this.grips.Hide()
        if (alsoPanel && this.panel)
            try this.panel.Hide()
    }

    _showChrome(alsoPanel := false) {
        this._drawChrome()
        if (alsoPanel && this.panel)
            try this.panel.Show("NoActivate")
    }

    ; Çerçeve: 4 çubuk (üst / alt / sol / sağ), seçim kenarının dışına taşacak
    ; şekilde. Pencere her iki yönde pad kadar büyük, böylece tutamaçlar da sığar.
    _drawSelection(x, y, w, h, d, showGrips) {
        local pad := singleScreenOcr.GRIP_HALF + 1
        if (!this.band) {
            ; +E0x08000000 = WS_EX_NOACTIVATE — tıklama odağı çalmasın
            this.band := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000")
            this.band.BackColor := "FF3B30"
        }
        this._setRegion(this.band, [
            [pad - d, pad - d, pad + w + d, pad],              ; üst
            [pad - d, pad + h, pad + w + d, pad + h + d],      ; alt
            [pad - d, pad - d, pad,         pad + h + d],      ; sol
            [pad + w, pad - d, pad + w + d, pad + h + d]       ; sağ
        ])
        this.band.Show("NA x" (x - pad) " y" (y - pad) " w" (w + pad * 2) " h" (h + pad * 2))
        if (showGrips) {
            this._drawGrips(x, y, w, h, pad)
            return
        }
        if (this.grips)
            try this.grips.Hide()
    }

    ; 8 tutamaç karesi, kenar orta noktaları ve köşeler üzerinde.
    _drawGrips(x, y, w, h, pad) {
        local hs := singleScreenOcr.GRIP_HALF
        if (w < singleScreenOcr.GRIP_MIN || h < singleScreenOcr.GRIP_MIN) {
            if (this.grips)
                try this.grips.Hide()
            return
        }
        if (!this.grips) {
            this.grips := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000")
            this.grips.BackColor := "FFFFFF"
        }
        local sq := []
        local i := 0
        for cx in [pad, pad + w // 2, pad + w] {
            i += 1
            local j := 0
            for cy in [pad, pad + h // 2, pad + h] {
                j += 1
                if (i == 2 && j == 2)   ; orta nokta tutamaç değil
                    continue
                sq.Push([cx - hs, cy - hs, cx + hs, cy + hs])
            }
        }
        this._setRegion(this.grips, sq)
        this.grips.Show("NA x" (x - pad) " y" (y - pad) " w" (w + pad * 2) " h" (h + pad * 2))
    }

    ; ── Fare etkileşimi (ayarlama fazı) ──────────────────────────────────────

    ; ~LButton hotkey kriteri. KURAL: yalnızca çerçeve/tutamaç penceresine ya da
    ; seçili alanın ayarlama bölgesine tıklandıysa tıklamayı devral.
    ;
    ; Eskiden "panel DEĞİLSE devral" deniyordu — kara liste. Açık bir dropdown'ın
    ; listesi (ComboLBox) AYRI bir üst düzey pencere olduğu için oradaki tıklama
    ; da devralınıyor, hit-test boş dönüyor ve seçim iptal ediliyordu; seçim
    ; commit olmadığı için biçim de hep "Düz metin"e geri dönüyordu. Beyaz liste
    ; bu sınıf hatanın tamamını kapatır (tooltip, menü, IME penceresi vb.).
    _isOverCanvas() {
        if (!this.session || !this.rect)
            return false
        local mx := 0, my := 0, hw := 0
        try MouseGetPos(&mx, &my, &hw)
        catch
            return false
        if (this._isChromeHwnd(hw))
            return true
        if (this.panel) {
            try {
                if (hw == this.panel.Hwnd)
                    return false
            }
        }
        return this._hitTest(mx, my) != ""
    }

    _onCanvasClick() {
        if (!this.session || !this.rect)
            return
        CoordMode("Mouse", "Screen")
        local mx := 0, my := 0
        MouseGetPos(&mx, &my)
        local zone := this._hitTest(mx, my)
        if (zone == "") {
            return                    ; ayarlama bölgesi dışı — dokunma
        }
        local r0 := { x: this.rect.x, y: this.rect.y, w: this.rect.w, h: this.rect.h }
        local sx := mx, sy := my
        local moved := false
        while (GetKeyState("LButton", "P")) {
            MouseGetPos(&mx, &my)
            local dx := mx - sx, dy := my - sy
            if (Abs(dx) > 1 || Abs(dy) > 1)
                moved := true
            this._applyDrag(zone, r0, dx, dy)
            this._drawChrome()
            Sleep(16)
        }
        if (moved) {
            this._placePanel()
            this._refreshCapture()
        }
    }

    ; Tutulan kenara göre dikdörtgeni güncelle. Kullanıcı karşı kenarı geçerse
    ; koordinatlar takas edilir (negatif genişlik oluşmaz), sonra alt sınıra kıstırılır.
    _applyDrag(zone, r0, dx, dy) {
        local x1 := r0.x, y1 := r0.y, x2 := r0.x + r0.w, y2 := r0.y + r0.h
        local tmp := 0
        if (zone == "move") {
            x1 += dx, x2 += dx, y1 += dy, y2 += dy
        } else {
            if (InStr(zone, "w"))
                x1 += dx
            if (InStr(zone, "e"))
                x2 += dx
            if (InStr(zone, "n"))
                y1 += dy
            if (InStr(zone, "s"))
                y2 += dy
        }
        if (x2 < x1) {
            tmp := x1, x1 := x2, x2 := tmp
        }
        if (y2 < y1) {
            tmp := y1, y1 := y2, y2 := tmp
        }
        local mn := singleScreenOcr.MIN_SIZE
        if (x2 - x1 < mn)
            x2 := x1 + mn
        if (y2 - y1 < mn)
            y2 := y1 + mn
        this.rect := { x: x1, y: y1, w: x2 - x1, h: y2 - y1 }
    }

    ; Fare hangi bölgede: "nw","n","ne","w","e","sw","s","se","move" veya "".
    _hitTest(mx, my) {
        local r := this.rect
        local t := singleScreenOcr.GRAB_TOL
        if (mx < r.x - t || mx > r.x + r.w + t || my < r.y - t || my > r.y + r.h + t)
            return ""
        local nl := Abs(mx - r.x) <= t
        local nr := Abs(mx - (r.x + r.w)) <= t
        local nt := Abs(my - r.y) <= t
        local nb := Abs(my - (r.y + r.h)) <= t
        if (nt && nl)
            return "nw"
        if (nt && nr)
            return "ne"
        if (nb && nl)
            return "sw"
        if (nb && nr)
            return "se"
        if (nt)
            return "n"
        if (nb)
            return "s"
        if (nl)
            return "w"
        if (nr)
            return "e"
        return "move"
    }

    ; Dışarı tıklanınca sıfırdan seçim. Sol tuş zaten BASILI olduğu için
    ; _selectRect'in "basılmasını bekle" döngüsü anında geçer ve sürükleme
    ; kullanıcının tıkladığı noktadan başlar — kesintisiz hissettirir.
    ; NOT: eskiden burada bir _reselect() vardı — seçili alanın DIŞINA tıklayınca
    ; sıfırdan seçim başlatıyordu. Kaldırıldı: panelde bir şeye tıklamak (özellikle
    ; açık dropdown listesi) yanlışlıkla oraya düşüp seçimi iptal ediyordu.
    ; Yeniden seçmek için F13+o yeter.

    ; ── Ekran yakalama ───────────────────────────────────────────────────────

    ; Çerçeveyi (ve gerekiyorsa paneli) gizle → bir kare bekle → bölgeyi çek.
    ; Gizlemeden çekersen kırmızı çerçeve görüntüye karışır ve OCR onu okur.
    _capture() {
        local hidePanel := this._panelOverlaps()
        this._hideChrome(hidePanel)
        Sleep(singleScreenOcr.SETTLE_MS)
        local shot := 0
        try {
            shot := OCR.CreateHBitmap(this.rect.x, this.rect.y, this.rect.w, this.rect.h)
        } catch as err {
            App.ErrHandler.handleError("ScreenOcr._capture: " err.Message, err)
            shot := 0
        }
        this._showChrome(hidePanel)
        return shot
    }

    ; ── İlk alan seçimi (1. faz) ─────────────────────────────────────────────

    ; Ekranda dikdörtgen seçtirir. Dönen: {x,y,w,h} veya iptal/çok küçükse 0.
    _selectRect() {
        ; Auto-execute'ta zaten Screen; yine de bu thread için açıkça sabitle.
        CoordMode("Mouse", "Screen")
        ; SANAL ekran metrikleri — A_ScreenWidth DEĞİL, yoksa ikinci monitörde
        ; seçim yapılamaz. 76..79 = SM_XVIRTUALSCREEN..SM_CYVIRTUALSCREEN
        local vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
        local x1 := 0, y1 := 0, x2 := 0, y2 := 0

        try {
            ; +E0x80000 = WS_EX_LAYERED (WinSetTransparent için şart)
            this.overlay := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x80000")
            this.overlay.BackColor := "101010"
            ; NA (NoActivate): odağı çalmıyoruz. Tıklamayı yine de örtü yutar
            ; (katmanlı ama tıklama-geçirgen değil); sürüklemeyi fiziksel tuş
            ; durumundan okuduğumuz için pencerenin mesaj almasına gerek yok.
            this.overlay.Show("NA x" vx " y" vy " w" vw " h" vh)
            WinSetTransparent(singleScreenOcr.DIM_ALPHA, this.overlay.Hwnd)
            OnMessage(0x20, this.cursorBound)   ; WM_SETCURSOR → artı imleç

            ; 1) Sol tuşa basılmasını bekle
            while (!GetKeyState("LButton", "P")) {
                if (GetKeyState("Escape", "P") || GetKeyState("RButton", "P"))
                    return 0
                Sleep(10)
            }
            MouseGetPos(&x1, &y1)

            ; 2) Sürükle — clip_image_dialog._dragPan ile aynı deyim
            while (GetKeyState("LButton", "P")) {
                if (GetKeyState("Escape", "P"))
                    return 0
                MouseGetPos(&x2, &y2)
                this._drawSelection(Min(x1, x2), Min(y1, y2), Abs(x2 - x1), Abs(y2 - y1), 2, false)
                Sleep(16)
            }
            MouseGetPos(&x2, &y2)
        } catch as err {
            App.ErrHandler.handleError("ScreenOcr._selectRect: " err.Message, err)
            return 0
        } finally {
            this._closeOverlay()
        }

        local w := Abs(x2 - x1), h := Abs(y2 - y1)
        if (w < singleScreenOcr.MIN_SIZE || h < singleScreenOcr.MIN_SIZE)
            return 0
        return { x: Min(x1, x2), y: Min(y1, y2), w: w, h: h }
    }

    ; Örtüyü kapat. Çerçeve/tutamaçlar oturum devam ediyorsa YAŞAR — bu yüzden
    ; burada yalnız örtü yok ediliyor, oturum yoksa çerçeve de kapatılıyor.
    _closeOverlay() {
        try OnMessage(0x20, this.cursorBound, 0)
        if (this.overlay) {
            try this.overlay.Destroy()
            this.overlay := 0
        }
        if (this.session) {
            OnMessage(0x20, this.cursorBound)   ; oturum imleçleri için geri tak
            return
        }
        if (this.band) {
            try this.band.Destroy()
            this.band := 0
        }
        if (this.grips) {
            try this.grips.Destroy()
            this.grips := 0
        }
    }

    ; ── İmleç ────────────────────────────────────────────────────────────────

    ; WM_SETCURSOR. Örtünün üstünde artı; oturumda çerçeve/tutamaç üstünde
    ; bölgeye göre boyutlandırma imleci.
    ; SetSystemCursor KULLANMIYORUZ: o sistem genelinde kalıcı değiştirir,
    ; script çökerse imleç bozuk kalır ve kullanıcı elle düzeltmek zorunda kalır.
    _onSetCursor(wParam, lParam, msg, hwnd) {
        static cache := Map()
        local want := 0
        try {
            if (this.overlay && hwnd == this.overlay.Hwnd)
                want := 32515                       ; IDC_CROSS
            else if (this.session && this._isChromeHwnd(hwnd))
                want := this._zoneCursor()
        } catch {
            return
        }
        if (!want)
            return
        if (!cache.Has(want))
            cache[want] := DllCall("LoadCursor", "Ptr", 0, "Ptr", want, "Ptr")
        DllCall("SetCursor", "Ptr", cache[want])
        return true
    }

    _isChromeHwnd(hwnd) {
        try {
            if (this.band && hwnd == this.band.Hwnd)
                return true
            if (this.grips && hwnd == this.grips.Hwnd)
                return true
        }
        return false
    }

    _zoneCursor() {
        CoordMode("Mouse", "Screen")
        local mx := 0, my := 0
        MouseGetPos(&mx, &my)
        local z := this._hitTest(mx, my)
        if (z == "nw" || z == "se")
            return 32642                            ; IDC_SIZENWSE
        if (z == "ne" || z == "sw")
            return 32643                            ; IDC_SIZENESW
        if (z == "w" || z == "e")
            return 32644                            ; IDC_SIZEWE
        if (z == "n" || z == "s")
            return 32645                            ; IDC_SIZENS
        if (z == "move")
            return 32646                            ; IDC_SIZEALL
        return 32515
    }

    ; ── Sonuç (hızlı akış) ───────────────────────────────────────────────────

    ; info yalnız tooltip'te görünür, PANOYA GİTMEZ.
    _finish(text, info := "") {
        if (text == "") {
            ShowTip("OCR: metin bulunamadı", TipType.Warning, 1200)
            return ""
        }
        A_Clipboard := text
        ShowTip((info == "" ? "" : info "`n────────`n") text, TipType.Copy, 3000)
        return text
    }

    _setScale(v) {
        this.scale := v
        ShowTip("OCR ölçeği: x" v, TipType.Info, 700)
        this._reOcr()
    }

    _toggleGray() {
        this.grayscale := !this.grayscale
        ShowTip("Gri tonlama: " (this.grayscale ? "açık" : "kapalı"), TipType.Info, 700)
        this._reOcr()
    }

    _setGutter(v) {
        this.gutter := v
        ShowTip("Kolon eşiği: " (v == 0 ? "otomatik" : v "px"), TipType.Info, 700)
        this._applyLayout()
    }

    _setLang(code) {
        this.lang := code
        ShowTip("OCR dili: " code, TipType.Info, 700)
        ; Panel açıkken menüden dil değiştirilirse liste de senkron kalsın
        if (this.langBox) {
            for c in this.langs {
                if (c == code)
                    try this.langBox.Value := A_Index
            }
        }
        this._reOcr()
    }

    __Delete() {
        this._closeSession()
        this._closeOverlay()
    }
}
