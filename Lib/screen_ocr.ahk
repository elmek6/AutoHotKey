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
;    içinden sürüklenip taşınabilir. Panel seçimin YANINA (sağda/solda hangisi
;    genişse) açılır: metin (seçilebilir, düzenlenebilir), altında dil,
;    kolon biçimi, ayraç, ölçek, gri tonlama, kolon eşiği ve Kopyala.
;    TÜM AYARLAR BURADA — menüde ayar yok, orada yalnız eylemler var. Her
;    değişiklik sonucu anında üstteki kutuda gösterir; ölçek/gri yeniden OCR
;    yapar (ekranı tekrar ÇEKMEDEN, cache'li bitmap üzerinden), biçim/ayraç/
;    kolon eşiği ise OCR bile gerektirmez (cache'li Result yeniden dizilir).
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
    ; Panel ile seçili alan arasındaki boşluk (px).
    static PANEL_GAP := 16

    ; "Kolonlu (ayraçlı)" biçiminde hücreleri birleştiren karakter için hazır
    ; seçenekler. Panelde DÜZENLENEBİLİR bir ComboBox olarak sunuluyor: listeden
    ; seçilebilir ya da doğrudan yazılabilir (ör. " | ", "\t", " — ").
    ; label = kullanıcıya görünen ad, v = gerçek metin.
    ; DİKKAT: etiketlerde BOŞLUK + ";" dizisi kullanılamaz. Bu dizi çok satırlı
    ; ifadenin devam satırlarında string içinde bile YORUM başlangıcı sayılıyor
    ; ve yükleme anında `Missing "` hatası veriyor — sembol bu yüzden başa alındı.
    static SEPS := [
        { label: "Tab",              v: "`t" },
        { label: ",  Virgül",        v: ","  },
        { label: ".  Nokta",         v: "."  },
        { label: ";  Noktalı virgül", v: ";" },
        { label: ":  İki nokta",     v: ":"  },
        { label: "|  Boru",          v: "|"  },
        { label: "-  Tire",          v: "-"  },
        { label: "Boşluk",           v: " "  }
    ]

    ; Ayraç kutusundaki "listede yok, elle gireceğim" satırı.
    static SEP_CUSTOM := "Özel..."

    ; Kolon ayracı sayılacak en küçük boş dikey şerit. Çok küçük → kelime araları
    ; kolon sanılır; çok büyük → kolonlar birleşir. Panelde düzenlenebilir kutu,
    ; listede olmayan bir sayı da yazılabilir.
    static GUTTERS := ["Otomatik", "20px", "40px", "80px", "150px"]

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
        this.txtBox := 0, this.langBox := 0, this.modeBox := 0
        this.sepBox := 0, this.scaleBox := 0, this.grayChk := 0, this.gutterBox := 0
        this.advChk := 0, this.advCtrls := [], this.baseBottom := 0, this.advBottom := 0
        this.layout := [], this.txtH := 0, this.txtW := 0   ; dinamik yerleşim
        this.baseCH := 0, this.advCH := 0, this.extraH := 0
        this.advanced := false  ; gelişmiş satır açık mı (oturumlar arası hatırlanır)
        this.session := false
        this.rect    := 0
        this.shot    := 0       ; yakalanan HBITMAP sarmalayıcısı (kendi __Delete'i var)
        this.lastRes := 0       ; cache'li OCR.Result — kolon biçimi değişimi bunu kullanır
        this.langs   := []      ; panel DDL'inin sırasıyla eşleşen dil kodları
        this.lang    := ""      ; "" → kütüphanenin varsayılanı (ilk kurulu dil)
        this.scale   := 2       ; OCR öncesi büyütme; 96 DPI'da 8-9pt UI fontları sınırda
        this.grayscale := true  ; ClearType alt-piksel izini temizler
        this.gutter  := 0       ; kolon ayracı eşiği (px); 0 = otomatik
        this.sep     := "`t"    ; "Kolonlu (ayraçlı)" biçiminde hücre ayracı
        this.panelPlaced := false   ; panel bu oturumda bir kez yerleştirildi mi
        this.lastMs  := 0
        ; Hotkey/OnMessage kayıt VE kaldırma AYNI nesneyle yapılmalı — her
        ; seferinde yeni ObjBindMethod üretmek kaldırmayı sessizce başarısız
        ; kılıp handler biriktiriyor (array_filter ve clip_image_dialog dersi).
        this.cursorBound     := ObjBindMethod(this, "_onSetCursor")
        this.canvasIfBound   := (*) => this._isOverCanvas()
        this.canvasClickBound := (*) => this._onCanvasClick()
        this.sessionIfBound   := (*) => this.session
        this.cancelBound      := (*) => this._closeSession()
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
        return this._finish(out.text, mode == "plain" ? "" : out.info)
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

    ; ── Ayraç ────────────────────────────────────────────────────────────────
    ;
    ; Ayraç YALNIZCA "Kolonlu (ayraçlı)" biçiminde kullanılır: aynı satırın
    ; hücreleri bununla birleştirilir. Excel/Sheets için TAB, CSV için virgül,
    ; okunur çıktı için " | " tipik. Panelde düzenlenebilir ComboBox var —
    ; listeden seçmek de elle yazmak da mümkün.

    ; Elle giriş kutusu; panelin ayraç kutusundaki "Özel..." satırı buraya gelir.
    ; Kaçış dizileri çözülür — ters bölü + t/n/s sırasıyla TAB, satır sonu ve
    ; boşluk olur; görünmez karakterler ancak böyle yazılabiliyor.
    _askSep() {
        local ib := InputBox("Hücre ayracı olarak kullanılacak metin.`n"
                           . "Kaçışlar: \t = TAB, \n = satır sonu, \s = boşluk",
                             "OCR ayracı", "w360 h150", this._sepEscape(this.sep))
        if (ib.Result != "OK" || ib.Value == "") {
            ; Vazgeçildi: kutuda "Özel..." yazılı kalmasın, eski ayraca dön.
            if (this.sepBox)
                try this.sepBox.Text := this._sepLabel(this.sep)
            return
        }
        this.sep := this._sepUnescape(ib.Value)
        if (this.sepBox)
            try this.sepBox.Text := this._sepLabel(this.sep)
        this._applyLayout()
    }

    ; Ayracın kullanıcıya gösterilecek adı. Hazır seçeneklerden biriyse etiketi,
    ; değilse kaçışlanmış hali (görünmez karakter "boş" görünmesin diye).
    _sepLabel(v) {
        for s in singleScreenOcr.SEPS {
            if (s.v == v)
                return s.label
        }
        return "«" this._sepEscape(v) "»"
    }

    _sepEscape(v) {
        v := StrReplace(v, "\", "\\")
        v := StrReplace(v, "`t", "\t")
        v := StrReplace(v, "`r`n", "\n")
        v := StrReplace(v, "`n", "\n")
        return v
    }

    _sepUnescape(v) {
        ; \\ önce korunur, sonra geri konur — yoksa "\\t" yanlışlıkla TAB olur.
        v := StrReplace(v, "\\", "`f")
        v := StrReplace(v, "\t", "`t")
        v := StrReplace(v, "\n", "`n")
        v := StrReplace(v, "\s", " ")
        return StrReplace(v, "`f", "\")
    }

    ; ComboBox'a yazılan/seçilen metni gerçek ayraca çevirir: önce hazır
    ; etiketlerle eşleştirilir, eşleşmezse yazılan metnin kendisi kullanılır.
    _sepFromText(txt) {
        for s in singleScreenOcr.SEPS {
            if (txt == s.label)
                return s.v
        }
        if (SubStr(txt, 1, 1) == "«" && SubStr(txt, -1) == "»")
            txt := SubStr(txt, 2, StrLen(txt) - 2)
        return this._sepUnescape(txt)
    }

    ; Sistemde OCR yeteneği KURULU dillerin listesi. Boşsa dil paketi yok demektir.
    ; Kurulum (admin PowerShell):
    ;   Get-WindowsCapability -Online -Name "Language.OCR*"
    ;   Add-WindowsCapability -Online -Name "Language.OCR~~~tr-TR~0.0.1.0"
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

    ; res.Text KULLANILMAZ — ölçüm: 11 satırlık dikey bir menü OCR'landığında
    ; motor satırları DOĞRU ayırıyor (res.Lines.Length = 11) ama WinRT'nin
    ; OcrResult.Text özelliği satırları BOŞLUKLA birleştiriyor: içinde sıfır
    ; satır sonu var. Sonuç "Repository GUI Clipboard history win Clipboard
    ; history ..." diye tek satır — ekranda alt alta duran şeyler yan yana
    ; görünüyor. Doğrusu res.Lines'ı tek tek gezip `n ile birleştirmek.
    _plainText(res) {
        local out := ""
        for ln in res.Lines
            out .= ln.Text "`n"
        return Trim(out, " `t`r`n")
    }

    _layout(res, mode) {
        local plain := this._plainText(res)
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
        if (mode == "table") {
            return { text: this._tableText(rows, splits, nCol, this.sep)
                   , info: "ayraç " this._sepLabel(this.sep) " · " suffix }
        }
        return { text: this._columnsText(rows, splits, nCol), info: "kolon · " suffix }
    }

    ; Satırlar hizalı, hücreler seçilen ayraçla → TAB ise Excel'e doğrudan
    ; yapıştırılır, virgül ise CSV olur.
    _tableText(rows, splits, nCol, sep) {
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
                line .= (A_Index == 1 ? "" : sep) cells[A_Index]
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
        this.panelPlaced := false
        this.rect := r
        this._buildPanel()
        this._drawChrome()
        this.panel.Show()
        ; Show sonrası: yükseklik gerçek pencere ölçüsünden hesaplanıyor,
        ; _placePanel de o yüksekliğe göre yer seçsin.
        this._setAdvanced(this.advanced)
        ; Taban ölçünün altına inilmesin: alt satırlar kırpılmasın.
        local pw := 0, ph := 0
        this.panel.GetPos(, , &pw, &ph)
        this.panel.Opt("+MinSize" pw "x" ph)
        this._placePanel()
        ; Fare etkileşimi: clip_image_dialog'daki deyim — kriter SABİT bir
        ; fonksiyon nesnesi. "ahk_id <hwnd>" kullanılsaydı her oturumda yeni
        ; hotkey varyantı kaydedilir ve varyantlar birikirdi.
        HotIf(this.canvasIfBound)
        Hotkey("~LButton", this.canvasClickBound, "On")
        HotIf()
        ; Panel odakta değilken de kapanabilsin: Gui'nin Escape olayı yalnız
        ; pencere ETKİNKEN çalışır, oysa tuvale tıkladıktan sonra odak orada
        ; olmuyor. Kriter this.session — oturum dışında tuşlar hiç kancalanmıyor.
        HotIf(this.sessionIfBound)
        Hotkey("Escape", this.cancelBound, "On")
        Hotkey("MButton", this.cancelBound, "On")
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
        try {
            HotIf(this.sessionIfBound)
            Hotkey("Escape", "Off")
            Hotkey("MButton", "Off")
            HotIf()
        }
        try OnMessage(0x20, this.cursorBound, 0)
        for g in [this.band, this.grips, this.panel] {
            if (g)
                try g.Destroy()
        }
        this.band := 0, this.grips := 0, this.panel := 0
        this.txtBox := 0, this.langBox := 0, this.modeBox := 0
        this.sepBox := 0, this.scaleBox := 0, this.grayChk := 0, this.gutterBox := 0
        this.advChk := 0, this.advCtrls := [], this.layout := [], this.txtW := 0
        this.panelPlaced := false
        this.shot := 0       ; sarmalayıcının __Delete'i HBITMAP+DC'yi bırakır
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

        ; Başlık durum satırı olarak kullanılıyor (_setStatus), ayrı bir metin
        ; kontrolü yok — panelde bir satır yer kazanıyor.
        this.panel := Gui("+AlwaysOnTop +ToolWindow +Resize", "OCR")
        this.panel.MarginX := 14, this.panel.MarginY := 14
        this.panel.SetFont("s10", "Segoe UI")
        ; Düzenlenebilir: OCR l/1/I ve 0/O karıştırır, elle düzeltmek yeniden
        ; taramaktan hızlı. Seçim varsa Kopyala YALNIZ seçimi alır.
        ; +HScroll kelime kaydırmayı kapatır: OCR satırları sarılmayıp yana kayar,
        ; böylece kaynaktaki satır yapısı korunur.
        this.txtBox := this.panel.AddEdit("w520 r14 +VScroll +HScroll Multi")

        this.panel.SetFont("s9")
        this.panel.AddText("xm y+16 w140 h18", "Dil")
        this.panel.AddText("x+14 yp w210 h18", "Biçim")
        this.panel.AddText("x+14 yp w140 h18", "Ayraç")

        ; LİSTE, dropdown DEĞİL: tek tıkla seçiliyor, ayrıca açık bir DDL listesi
        ; (ComboLBox) ayrı üst düzey pencere olduğu için ~LButton kancamızla
        ; çakışıp seçimi iptal ediyordu.
        this.langBox := this.panel.AddListBox("xm y+6 w140 r4 Choose" chosen, this.langs)
        this.modeBox := this.panel.AddListBox("x+14 yp w210 r4 Choose1",
                            ["Düz metin", "Kolonlu (sırayla)", "Kolonlu (ayraçlı)"])
        local sepLabels := []
        for s in singleScreenOcr.SEPS
            sepLabels.Push(s.label)
        sepLabels.Push(singleScreenOcr.SEP_CUSTOM)
        this.sepBox := this.panel.AddComboBox("x+14 yp w140", sepLabels)
        this.sepBox.Text := this._sepLabel(this.sep)

        ; y+N BİR ÖNCEKİ kontrolün altına hizalar; sıradaki son kontrol tek
        ; satırlık ayraç kutusu olduğu için düğme listelerin ÜSTÜNE biniyordu.
        ; Bu yüzden y, listenin dibinden açıkça hesaplanıyor.
        local lbY := 0, lbH := 0
        this.langBox.GetPos(, &lbY, , &lbH)
        this.panel.SetFont("s10")
        local btn := this.panel.AddButton("xm y" (lbY + lbH + 20) " w400 h40 Default", "Kopyala")
        btn.OnEvent("Click", (*) => this._copy())

        this.panel.SetFont("s9")
        this.advChk := this.panel.AddCheckBox("x+18 yp+11 h20" (this.advanced ? " Checked" : ""), "Gelişmiş")
        this.advChk.OnEvent("Click", (*) => this._setAdvanced(this.advChk.Value ? true : false))

        ; Gelişmiş satır EN ALTTA: gizlenince altında taşınacak kontrol kalmıyor,
        ; pencere yalnız kısalıyor. +0x200 = SS_CENTERIMAGE (dikey hizalama).
        local btnY := 0, btnH := 0
        btn.GetPos(, &btnY, , &btnH)
        this.baseBottom := btnY + btnH
        local ay := this.baseBottom + 16
        local lblScale := this.panel.AddText("xm y" ay " h24 +0x200", "Ölçek")
        this.scaleBox := this.panel.AddDDL("x+8 yp w64 Choose" this.scale, ["x1", "x2", "x3", "x4"])
        this.grayChk := this.panel.AddCheckBox("x+28 yp+3 h20" (this.grayscale ? " Checked" : ""), "Gri tonlama")
        local lblGutter := this.panel.AddText("x+28 yp-3 h24 +0x200", "Kolon eşiği")
        this.gutterBox := this.panel.AddComboBox("x+8 yp w110", singleScreenOcr.GUTTERS)
        this.gutterBox.Text := this._gutterLabel(this.gutter)
        this.advCtrls := [lblScale, this.scaleBox, this.grayChk, lblGutter, this.gutterBox]
        this.advBottom := ay + 24
        for c in this.advCtrls
            c.Visible := this.advanced

        ; Dil/ölçek/gri → yeniden OCR (ekran tekrar ÇEKİLMEZ, this.shot duruyor).
        ; Biçim/ayraç/kolon eşiği → yalnız yeniden dizme, OCR yok.
        this.langBox.OnEvent("Change", (*) => this._onLangChange())
        this.modeBox.OnEvent("Change", (*) => this._onModeChange())
        this.sepBox.OnEvent("Change", (*) => this._onSepChange())
        this.scaleBox.OnEvent("Change", (*) => this._onScaleChange())
        this.grayChk.OnEvent("Click", (*) => this._onGrayChange())
        this.gutterBox.OnEvent("Change", (*) => this._onGutterChange())
        this.panel.OnEvent("Escape", (*) => this._closeSession())
        this.panel.OnEvent("Close", (*) => this._closeSession())
        this.panel.OnEvent("Size", (*) => this._onResize())
        this._captureLayout()
    }

    ; ── Dinamik yerleşim ─────────────────────────────────────────────
    ; Büyüyen alanın TAMAMINI metin kutusu alır; alt satırlar ölçüsü değişmeden
    ; aşağı kayar. Saklanan tek şey her kontrolün TABAN y'si.
    _captureLayout() {
        local y := 0, h := 0
        this.txtBox.GetPos(, , , &h)
        this.txtH := h
        this.txtW := 0                       ; yeni panel → ilk Size mutlaka uygulansın
        this.layout := []
        for hwnd, c in this.panel {
            if (c == this.txtBox)
                continue
            c.GetPos(, &y)
            this.layout.Push({ c: c, y: y })
        }
        ; İki taban yükseklik: gelişmiş satır kapalı / açık.
        this.baseCH := this.baseBottom + this.panel.MarginY
        this.advCH  := this.advBottom + this.panel.MarginY
    }

    ; Size olayının w/h parametreleri KULLANILMIYOR: DPI %100 dışındayken ham
    ; piksel gelip Move'un Gui birimiyle karışıyorlar. GetClientPos doğru birim.
    _onResize() {
        if (!this.panel || !this.layout.Length)
            return
        local cw := 0, ch := 0
        try this.panel.GetClientPos(, , &cw, &ch)
        catch
            return
        if (cw <= 0 || ch <= 0)              ; simge durumu
            return
        ; extraH = taban boydan SAPMA. Gelişmiş satır açılıp kapandıkça taban
        ; değişiyor, kullanıcının verdiği fazlalık korunuyor (_setAdvanced okuyor).
        local extra := Max(0, ch - (this.advanced ? this.advCH : this.baseCH))
        local tw := cw - this.panel.MarginX * 2
        if (extra == this.extraH && tw == this.txtW)   ; sürüklerken yinelenen olay
            return
        this.extraH := extra, this.txtW := tw
        try this.txtBox.Move(, , tw, this.txtH + extra)
        for it in this.layout
            try it.c.Move(, it.y + extra)
        try this.txtBox.Redraw()             ; büyüyen bölge kirli kalmasın
    }

    ; YERLEŞİM: önce YAN taraflar. Panel yüksek ama dar; ekranın üstü/altı
    ; genelde dar kaldığı için panel seçime yapışıyor ya da ekran dışına
    ; taşıyordu. Sağda ve solda kalan boşluktan GENİŞ olanı seçiliyor, panel
    ; oraya seçimle dikey ortalanarak konuyor. İki yan da sığmıyorsa eski
    ; davranışa (alt, olmazsa üst) düşülüyor.
    ;
    ; Sanal ekran değil, seçimin bulunduğu monitörün ÇALIŞMA ALANI kullanılıyor:
    ; panel görev çubuğunun altında kalmıyor ve komşu monitöre kaçmıyor.
    ;
    ; ÖLÇÜM VE TAŞIMA WinGetPos/WinMove İLE. Gui.GetPos/Gui.Move DPI ÖLÇEKLİ
    ; (mantıksal) koordinat verir ve bekler; this.rect ise ekranın FİZİKSEL
    ; pikselleri. %100 dışı bir ölçekte ikisi karışınca panel yanlış tarafa
    ; düşüyordu — solda yer yokken sola açılmasının sebebi buydu. Win* ailesi
    ; her zaman fiziksel koordinat kullanır, böylece ikisi aynı birime gelir.
    ;
    ; BİR KEZ yerleştiriliyor: ilk açılıştaki karar korunur; seçim taşınıp
    ; boyutlandıkça panel oradan oraya ZIPLAMAZ (force ile yeniden hesaplanır).
    _placePanel(force := false) {
        if (!this.panel || (this.panelPlaced && !force))
            return
        local pw := 0, ph := 0
        try WinGetPos(, , &pw, &ph, this.panel.Hwnd)
        catch
            return
        local r := this.rect
        local gap := singleScreenOcr.PANEL_GAP
        local wl := 0, wt := 0, wr := 0, wb := 0
        this._workArea(r.x + r.w // 2, r.y + r.h // 2, &wl, &wt, &wr, &wb)

        local spaceR := wr - (r.x + r.w) - gap
        local spaceL := (r.x - gap) - wl
        local px := 0, py := 0
        if (spaceR >= pw && spaceR >= spaceL) {
            px := r.x + r.w + gap
            py := r.y + (r.h - ph) // 2
        } else if (spaceL >= pw) {
            px := r.x - gap - pw
            py := r.y + (r.h - ph) // 2
        } else {
            px := r.x
            py := r.y + r.h + gap
            if (py + ph > wb)
                py := r.y - ph - gap
        }
        ; Kıstırma: sol/üst kenar her zaman görünür kalsın (panel çalışma
        ; alanından büyükse Max sonda olduğu için o kenar kazanır).
        WinMove(Max(Min(px, wr - pw), wl), Max(Min(py, wb - ph), wt), , , this.panel.Hwnd)
        this.panelPlaced := true
    }

    ; (x, y) noktasını içeren monitörün çalışma alanı. Bulunamazsa birincil.
    _workArea(x, y, &l, &t, &r, &b) {
        loop MonitorGetCount() {
            local ml := 0, mt := 0, mr := 0, mb := 0
            try MonitorGet(A_Index, &ml, &mt, &mr, &mb)
            catch
                continue
            if (x >= ml && x < mr && y >= mt && y < mb) {
                MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
                return
            }
        }
        MonitorGetWorkArea(, &l, &t, &r, &b)
    }

    ; Panel seçili alanı örtüyor mu? Örtüyorsa yakalamadan önce gizlenmeli.
    _panelOverlaps() {
        if (!this.panel)
            return false
        local px := 0, py := 0, pw := 0, ph := 0
        ; Gui.GetPos DEĞİL: o DPI ölçekli koordinat verir, this.rect ise
        ; fiziksel piksel. Karışırsa örtüşme yanlış hesaplanır ve panel
        ; yakalama sırasında gizlenmeyip görüntünün içine karışır.
        try WinGetPos(&px, &py, &pw, &ph, this.panel.Hwnd)
        catch
            return false
        local r := this.rect
        return !(px > r.x + r.w || px + pw < r.x || py > r.y + r.h || py + ph < r.y)
    }

    ; Biçim "Kolonlu (ayraçlı)" yapıldığında ayraç kutusunun listesini KENDİLİĞİNDEN
    ; açıyoruz — "hangi ayraç?" sorusu böyle soruluyor: kullanıcı ya listeden
    ; seçer ya da kutuya yazar. Diğer biçimlerde ayraç kullanılmıyor.
    _onModeChange() {
        this._applyLayout()
        if (this._modeKey() != "table" || !this.sepBox)
            return
        try {
            this.sepBox.Focus()
            SendMessage(0x014F, 1, 0, this.sepBox.Hwnd)     ; CB_SHOWDROPDOWN
        }
    }

    _onSepChange() {
        if (!this.sepBox)
            return
        ; "Özel..." bir ayraç değil, bir KOMUT: kutuya doğrudan yazmak da
        ; mümkün ama kaçışları (\t, \n, \s) ancak bu kutucuk anlatabiliyor.
        if (this.sepBox.Text == singleScreenOcr.SEP_CUSTOM) {
            this._askSep()
            return
        }
        local v := this._sepFromText(this.sepBox.Text)
        if (v == "")
            return          ; kutu boşaltıldı; kullanıcı hâlâ yazıyor olabilir
        this.sep := v
        ; Ayraç seçen kullanıcı zaten ayraçlı çıktı istiyor — biçimi oraya al.
        if (this.modeBox && this.modeBox.Value != 3)
            try this.modeBox.Value := 3
        this._applyLayout()
    }

    ; Gelişmiş satırı aç/kapa. Yükseklik, kontrollerin kendi koordinatlarından
    ; hesaplanıyor: ikisi de Gui birimleri, DPI karışıklığı doğmuyor.
    _setAdvanced(show) {
        this.advanced := show
        if (!this.panel)
            return
        for c in this.advCtrls
            try c.Visible := show
        local wh := 0, ch := 0
        this.panel.GetPos(, , , &wh)
        this.panel.GetClientPos(, , , &ch)
        ; Kullanıcının elle verdiği fazlalık korunuyor; Move'un tetiklediği Size
        ; olayı yerleşimi kendisi tazeliyor.
        local want := (show ? this.advCH : this.baseCH) + this.extraH
        this.panel.Move(, , , (wh - ch) + want)
    }

    _onScaleChange() {
        local v := this.scaleBox.Value
        if (v < 1 || v > 4)
            return
        this.scale := v
        this._reOcr()
    }

    _onGrayChange() {
        this.grayscale := this.grayChk.Value ? true : false
        this._reOcr()
    }

    _onGutterChange() {
        local v := this._gutterFromText(this.gutterBox.Text)
        if (v < 0)
            return          ; anlamsız giriş; kullanıcı hâlâ yazıyor olabilir
        this.gutter := v
        this._applyLayout()
    }

    _gutterLabel(v) {
        return (v == 0) ? "Otomatik" : v "px"
    }

    ; Kutudaki metinden piksel değeri. 0 = otomatik, -1 = anlaşılmadı.
    ; "80px", "80 px", "80" hepsi kabul; sayı yoksa kullanıcı yazmayı
    ; sürdürüyordur, sessizce yok sayılır.
    _gutterFromText(txt) {
        txt := Trim(txt)
        if (txt == "" || InStr(txt, "Oto") == 1)
            return 0
        local m := 0
        if (!RegExMatch(txt, "\d+", &m))
            return -1
        return Integer(m[0])
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
        this._setStatus("okunuyor...")
        try {
            local t := A_TickCount
            this.lastRes := OCR.FromBitmap(this.shot, this._opts())
            this.lastMs := A_TickCount - t
        } catch as err {
            App.ErrHandler.handleError("ScreenOcr._reOcr: " err.Message, err)
            this._setStatus("⚠ " err.Message)
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
        ; Dil, biçim, ölçek zaten panelde görünüyor — başlıkta yalnız ekranda
        ; okunamayanlar: boyut, süre, uzunluk. Uyarı varsa (kolon ayracı yok
        ; gibi) o da eklenir; başka türlü hiçbir yerde görünmezdi.
        local s := this.rect.w "x" this.rect.h " " this.lastMs "ms " StrLen(out.text) "len"
        if (InStr(out.info, "⚠"))
            s .= " · " out.info
        this._setStatus(s)
    }

    _setStatus(s) {
        if (this.panel)
            try this.panel.Title := "OCR: " s
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
        ; KENDİ sürecimizin diğer pencereleri (panel, açık ComboBox listesi,
        ; ShowTip balonu, menü) asla tuval değildir. Tek tek hwnd karşılaştırmak
        ; yerine süreç kimliğine bakmak, sonradan eklenen her pencere için de
        ; doğru çalışır — ayraç ComboBox'ının listesi bu sayede seçimi iptal etmiyor.
        if (this._isOwnWindow(hw))
            return false
        return this._hitTest(mx, my) != ""
    }

    _isOwnWindow(hwnd) {
        static self := DllCall("GetCurrentProcessId", "UInt")
        local pid := 0
        try DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
        catch
            return false
        return pid == self
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
        ; Panel burada TAŞINMIYOR. Seçim her ayarlandığında yeniden
        ; yerleştirilince pencere sağdan sola zıplıyor ve kullanıcının koyduğu
        ; yer bozuluyordu; ilk açılıştaki karar geçerli kalır.
        if (moved)
            this._refreshCapture()
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
                if (this._cancelPressed())
                    return 0
                Sleep(10)
            }
            MouseGetPos(&x1, &y1)

            ; 2) Sürükle — clip_image_dialog._dragPan ile aynı deyim
            while (GetKeyState("LButton", "P")) {
                ; Sürükleme başladıktan SONRA da vazgeçilebilir.
                if (this._cancelPressed())
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

    ; Seçimden vazgeçme: Escape, SAĞ tuş veya ORTA tuş. Üçü de fiziksel tuş
    ; durumundan okunuyor (örtü NA, odak almıyor; mesaj beklemenin anlamı yok).
    _cancelPressed() {
        return GetKeyState("Escape", "P") || GetKeyState("RButton", "P")
            || GetKeyState("MButton", "P")
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

    __Delete() {
        this._closeSession()
        this._closeOverlay()
    }
}
