#Include <clip_image_store>
; ═══════════════════════════════════════════════════════════
; singleClipImageDialog — Pano görsel geçmişi önizleme penceresi.
;
; Sol: 64x64 thumb'lı liste (diskten ham okunur, decode YOK) + butonlar
; Sağ: seçili kaydın önizlemesi. Görsel kutuya sığıyorsa 1:1 gösterilir,
;      sığmıyorsa sığdırılır; tekerlekle zoom, sürükleyerek kaydırma.
;
; Kullanım (klavye kısayolu yok, her şey buton veya fare):
;   ↑/↓ veya tık      gez            Ctrl/Shift + tık  çoklu seçim
;   Çift tık          panoya al      Tekerlek          zoom
;   Sol tuş sürükle   kaydır         Esc               kapat
;
; HBITMAP sahipliği: Picture kontrolüne "HBITMAP:*" ile atanan handle'ın
; sahipliğini KONTROL DEVRALIR ve eskisini kendi siler. Bu yüzden atadığımız
; handle'ları BİZ DeleteObject ETMEYİZ — çift serbest bırakma önizlemeyi
; boş bırakıyordu. Bizim sildiğimiz tek handle: ImageList'e eklenen thumb'lar.
; ═══════════════════════════════════════════════════════════
class singleClipImageDialog {
    static instance := ""

    static PREVIEW_W := 620
    static PREVIEW_H := 520
    static LIST_W    := 430
    static BTN_H     := 26
    static ZOOM_STEP := 1.25
    static ZOOM_MAX  := 8.0
    static ZOOM_MIN  := 0.05

    static getInstance() {
        if (!singleClipImageDialog.instance)
            singleClipImageDialog.instance := singleClipImageDialog()
        return singleClipImageDialog.instance
    }

    __New() {
        if (singleClipImageDialog.instance)
            throw Error("ClipImageDialog zaten oluşturulmuş! getInstance kullan.")
        this.gui := 0, this.lv := 0, this.pic := 0, this.info := 0, this.stats := 0
        this.hIL := 0
        this.items := []
        this.curRow := 0
        this.curBitmap := 0    ; çözülmüş pBitmap (zoom/pan kaynağı)
        this.srcW := 0, this.srcH := 0
        this.zoom := 1.0, this.fitZoom := 1.0
        ; Önizleme kutusunun GÜNCEL ölçüsü — zoom/pan/fit hesaplarının hepsi
        ; PREVIEW_W/H yerine bunu okur (_createGui kurar, _onResize tazeler).
        this.picW := 0, this.picH := 0
        this.layout := []      ; taban y'ler — alt satırlar bununla aşağı kayar
        this.baseCW := 0, this.baseCH := 0
        this.panX := 0, this.panY := 0
        this.pendingRow := 0
        this.selectBound := (*) => this._select(this.pendingRow)   ; tek referans → timer coalescing
        ; Hotkey kriteri ve işleyicileri SABİT nesneler olarak burada üretiliyor;
        ; neden olduğu _build içinde anlatılıyor (hotkey varyantı birikmesi).
        this.hotIfBound     := (*) => (this.gui && WinActive("ahk_id " this.gui.Hwnd)) ? true : false
        this.wheelUpBound   := (*) => this._wheel(1)
        this.wheelDownBound := (*) => this._wheel(-1)
        this.dragBound      := (*) => this._dragPan()
    }

    ; ── Açılış ───────────────────────────────────────────────────────────────

    show() {
        try {
            if (this.gui)
                this.close()
            this.items := App.ClipImages.loadThumbs()
            if (this.items.Length == 0) {
                ; Pencere açılmıyor; özeti hiç olmazsa tip'te göster
                ShowTip("Görsel geçmişi boş!`n" App.ClipImages.getStatsInfo()[1], TipType.Warning, 1500)
                return
            }
            this._build()
            this._fill()
            this._refreshStats()
            this.gui.Show()
            this._captureLayout()
            ; Modify(...,"Select") zaten ItemSelect'i tetikler → _select(1) oradan gelir.
            ; Ayrıca burada _select çağırmak önizlemeyi ikinci kez kurup bozuyordu.
            this.lv.Modify(1, "Select Focus")
        } catch as err {
            App.ErrHandler.handleError("ClipImageDialog.show: " err.Message, err)
        }
    }

    _build() {
        local W  := singleClipImageDialog.LIST_W
        local PW := singleClipImageDialog.PREVIEW_W
        local PH := singleClipImageDialog.PREVIEW_H
        this.picW := PW, this.picH := PH   ; her açılış taban ölçüyle başlıyor
        local BH := singleClipImageDialog.BTN_H
        local btnY := PH + 16
        local infoY := btnY + BH + 8
        local statsY := infoY + 36

        this.gui := Gui("+Resize", "Pano Görselleri")
        this.gui.MarginX := 8, this.gui.MarginY := 8

        ; -Multi YOK → Ctrl/Shift ile çoklu seçim (toplu silme için)
        this.lv := this.gui.Add("ListView", "x8 y8 w" W " h" PH " +LV0x10000",
                                ["Son kullanım", "Boyut", "KB", "×", "İlk kayıt"])
        this.pic := this.gui.Add("Picture", "x" (W + 16) " y8 w" PW " h" PH " +Border")

        local bx := 8
        for def in [["Panoya Al",  (*) => this._copyOnly(), 82],
                    ["Sil",        (*) => this._deleteSelected(), 60],
                    ["1:1 | fit",  (*) => this._toggleFit(), 72],
                    ["PNG Kaydet", (*) => this._export(), 84],
                    ["Kapat",      (*) => this.close(), 58]] {
            this.gui.Add("Button", "x" bx " y" btnY " w" def[3] " h" BH, def[1]).OnEvent("Click", def[2])
            bx += def[3] + 4
        }

        this.info := this.gui.Add("Text", "x8 y" infoY " w" (W + PW + 8) " h34")
        ; Depo geneli özet — açılışta ve silmeden sonra tazelenir. Seçim/zoom ile
        ; DEĞİŞMEZ, bu yüzden _updateInfo'dan ayrı: eskiden her render karesinde
        ; (sürükleme sırasında saniyede ~60 kez) 500 slot taranıyordu.
        this.gui.SetFont("s8 c505050")
        this.stats := this.gui.Add("Text", "x8 y" statsY " w" (W + PW + 8) " h30")
        this.gui.SetFont()

        this.hIL := DllCall("comctl32\ImageList_Create", "Int", GdipMini.THUMB_SIZE,
                            "Int", GdipMini.THUMB_SIZE, "UInt", 0x20,   ; ILC_COLOR32
                            "Int", this.items.Length, "Int", 16, "Ptr")
        this.lv.SetImageList(this.hIL, 1)

        ; Shift ile 20 satır seçilince 20 kez PNG çözmeyelim — son seçim kazansın
        this.lv.OnEvent("ItemSelect", (lv, row, sel) => sel ? this._selectDeferred(row) : 0)
        this.lv.OnEvent("DoubleClick", (lv, row) => this._copyOnly())
        this.gui.OnEvent("Escape", (*) => this.close())
        this.gui.OnEvent("Close", (*) => this.close())
        this.gui.OnEvent("Size", (*) => this._onResize())

        ; Sadece fare — klavye kısayolu kaydetmiyoruz.
        ; Kriter olarak SABİT bir fonksiyon nesnesi kullanılıyor. Eskiden
        ; HotIfWinActive("ahk_id " hwnd) idi: pencere her açılışta yeni hwnd aldığı
        ; için AHK her seferinde YENİ bir hotkey varyantı kaydediyordu. Kapanışta
        ; "Off" edilseler de kayıtlı kalıyorlardı — pencereyi yeterince çok açan
        ; kullanıcı hotkey tavanına dayanırdı. Aynı nesne = tek varyant.
        HotIf(this.hotIfBound)
        Hotkey("~WheelUp",   this.wheelUpBound, "On")
        Hotkey("~WheelDown", this.wheelDownBound, "On")
        Hotkey("~LButton",   this.dragBound, "On")
        HotIf()
    }

    _fill() {
        this.lv.Delete()
        this.lv.Opt("-Redraw")
        for item in this.items {
            local hbm := GdipMini.thumbToHbitmap(item["thumb"])
            local iconIdx := -1
            if (hbm) {
                ; ImageList kendi kopyasını alır → bizim handle'ı hemen bırakıyoruz
                iconIdx := DllCall("comctl32\ImageList_Add", "Ptr", this.hIL, "Ptr", hbm, "Ptr", 0, "Int")
                DllCall("gdi32\DeleteObject", "Ptr", hbm)
            }
            this.lv.Add("Icon" (iconIdx + 1),
                        this._formatTs(item["ts"]),
                        item["w"] "x" item["h"],
                        Round(item["datSize"] / 1024),
                        item["count"] > 1 ? item["count"] : "",
                        this._formatTs(item["createdTs"]))
        }
        Loop 5
            this.lv.ModifyCol(A_Index, "AutoHdr")
        this.lv.Opt("+Redraw")
    }

    ; ── Seçim ve önizleme ────────────────────────────────────────────────────

    ; Tek referanslı timer → hızlı ardışık seçimler tek çağrıda birleşir
    _selectDeferred(row) {
        this.pendingRow := row
        SetTimer(this.selectBound, -80)
    }

    _select(row) {
        if (row < 1 || row > this.items.Length)
            return
        this.curRow := row
        local item := this.items[row]

        this._releaseBitmap()
        local png := App.ClipImages.loadPng(item["slot"])
        if (!png) {
            this.info.Value := "Görsel okunamadı (slot " item["slot"] ")"
            return
        }
        this.curBitmap := GdipMini.bitmapFromPng(png, png.Size)
        if (!this.curBitmap) {
            this.info.Value := "PNG çözülemedi (slot " item["slot"] ")"
            return
        }
        GdipMini.imageSize(this.curBitmap, &w, &h)
        this.srcW := w, this.srcH := h
        this._resetView()
    }

    ; ── Dinamik yerleşim ─────────────────────────────────────────────
    ; Fazla ENi önizleme alır, fazla BOYu liste + önizleme birlikte alır; alt
    ; satırlar ölçüsü değişmeden kayar. Liste GENİŞLEMEZ (sütunları sabit).
    _captureLayout() {
        local pw := 0, ph := 0, y := 0
        this.gui.GetPos(, , &pw, &ph)
        this.gui.Opt("+MinSize" pw "x" ph)      ; tabanın altına inilmesin
        this.gui.GetClientPos(, , &pw, &ph)
        this.baseCW := pw, this.baseCH := ph
        this.layout := []
        for hwnd, c in this.gui {
            if (c == this.lv || c == this.pic)
                continue
            c.GetPos(, &y)
            this.layout.Push({ c: c, y: y })
        }
    }

    ; Size olayının w/h parametreleri KULLANILMIYOR: DPI %100 dışındayken ham
    ; piksel gelip Move'un Gui birimiyle karışıyorlar. GetClientPos doğru birim.
    _onResize() {
        if (!this.gui || !this.layout.Length)
            return
        local cw := 0, ch := 0
        try this.gui.GetClientPos(, , &cw, &ch)
        catch
            return
        if (cw <= 0 || ch <= 0)                 ; simge durumu
            return
        local dw := Max(0, cw - this.baseCW), dh := Max(0, ch - this.baseCH)
        local nw := singleClipImageDialog.PREVIEW_W + dw
        local nh := singleClipImageDialog.PREVIEW_H + dh
        if (nw == this.picW && nh == this.picH)   ; sürükleme sırasında yinelenen olay
            return
        ; Sığdırılmış görünümdeysek yeni kutuya göre yeniden sığdırılır; elle
        ; zoom yapılmışsa o oran korunur, yalnız kaydırma sınırları tazelenir.
        local wasFit := Abs(this.zoom - this.fitZoom) < 0.001
        this.picW := nw, this.picH := nh
        try this.lv.Move(, , , this.picH)
        try this.pic.Move(, , this.picW, this.picH)
        for it in this.layout
            try it.c.Move(, it.y + dh)
        if (wasFit)
            this._resetView()                   ; _setZoom → _center → _render
        else
            this._render()
    }

    ; Seçim değişince varsayılan görünüm: kutudan küçükse 1:1, büyükse sığdır.
    _resetView() {
        if (!this.curBitmap)
            return
        local PW := this.picW, PH := this.picH
        this.fitZoom := Min(PW / this.srcW, PH / this.srcH, 1.0)
        this._setZoom(this.fitZoom)
    }

    ; "1:1 | fit" butonu — iki işlevli: gerçek piksel ↔ kutuya sığdır.
    ; 1:1'de değilsek 1:1'e, zaten 1:1'deysek sığdırmaya geçer. Büyük görsellerde
    ; ilk basış her zaman 1:1 olur (seçim sığdırılmış halde geliyor).
    ; Not: fit BÜYÜTMEZ (fitZoom en fazla 1.0) — kutudan küçük görsellerde iki
    ; durum çakışır ve buton görünürde bir şey yapmaz, bu kasıtlı.
    _toggleFit() {
        if (!this.curBitmap)
            return
        this._setZoom(this._isOneToOne() ? this.fitZoom : 1.0)
    }

    _isOneToOne() {
        return Abs(this.zoom - 1.0) < 0.001
    }

    _setZoom(z) {
        this.zoom := z
        this._center()
        this._render()
    }

    _center() {
        local PW := this.picW, PH := this.picH
        this.panX := (PW - this.srcW * this.zoom) / 2
        this.panY := (PH - this.srcH * this.zoom) / 2
    }

    _render() {
        if (!this.curBitmap)
            return
        local PW := this.picW, PH := this.picH
        this._clampPan()
        local hbm := GdipMini.renderView(this.curBitmap, PW, PH,
                        Round(this.panX), Round(this.panY),
                        Max(1, Round(this.srcW * this.zoom)), Max(1, Round(this.srcH * this.zoom)))
        if (hbm)
            this.pic.Value := "HBITMAP:*" hbm   ; sahiplik kontrole geçer, silmiyoruz
        this._updateInfo()
    }

    ; Görsel kutudan büyükse boşluk açılmasın; küçükse ortada kalsın.
    _clampPan() {
        local PW := this.picW, PH := this.picH
        local dw := this.srcW * this.zoom, dh := this.srcH * this.zoom
        this.panX := (dw <= PW) ? (PW - dw) / 2 : Min(0, Max(PW - dw, this.panX))
        this.panY := (dh <= PH) ? (PH - dh) / 2 : Min(0, Max(PH - dh, this.panY))
    }

    _updateInfo() {
        if (this.curRow < 1 || this.curRow > this.items.Length)
            return
        local item := this.items[this.curRow]
        this.info.Value := "#" item["id"] "  ·  " item["w"] "x" item["h"] " " item["bpp"] "bpp"
                        . "  ·  " singleClipImageStore.fmtSize(item["datSize"])
                        . "  ·  %" Round(this.zoom * 100)
                        . (item["count"] > 1 ? "  ·  " item["count"] " kez kopyalandı" : "")
    }

    ; Depo geneli özet: kaç görsel, ne kadar yer, ring/index doluluğu, dosya boyutları.
    _refreshStats() {
        if (!this.stats)
            return
        local s := App.ClipImages.getStats()
        local fmt := (b) => singleClipImageStore.fmtSize(b)
        local ringPct := Round(s["ringUsed"] * 100 / s["ringMax"])
        local idxPct  := Round(s["count"] * 100 / s["maxCount"])
        this.stats.Value :=
            "📦 " s["count"] "/" s["maxCount"] " görsel (index %" idxPct ")"
          . "   ·   veri " fmt(s["liveBytes"])
          . "   ·   " s["copies"] " kopyalama"
          . (s["oldestTs"] ? "   ·   en eski " this._formatTs(s["oldestTs"]) : "")
          . (s["newestTs"] ? "   ·   son " this._formatTs(s["newestTs"]) : "")
          . "`n💾 ring %" ringPct " (" fmt(s["ringUsed"]) "/" fmt(s["ringMax"]) ")"
          . "   ·   geri kazanılabilir " fmt(s["deadBytes"])
          . "   ·   diskte " fmt(s["datBytes"]) " + index " fmt(s["idxBytes"])
    }

    ; ── Zoom / pan ───────────────────────────────────────────────────────────

    ; Fare imlecinin altındaki nokta sabit kalacak şekilde yakınlaştır.
    _wheel(dir) {
        local mx := 0, my := 0
        if (!this.curBitmap || !this._mouseOverPic(&mx, &my))
            return
        local old := this.zoom
        local next := dir > 0 ? old * singleClipImageDialog.ZOOM_STEP
                              : old / singleClipImageDialog.ZOOM_STEP
        next := Min(singleClipImageDialog.ZOOM_MAX, Max(singleClipImageDialog.ZOOM_MIN, next))
        if (next == old)
            return
        this.panX := mx - (mx - this.panX) * (next / old)
        this.panY := my - (my - this.panY) * (next / old)
        this.zoom := next
        this._render()
    }

    ; Sol tuşla sürükleyerek kaydırma. ~LButton olduğu için diğer LButton
    ; işleyicileri (HotMouse) etkilenmez.
    _dragPan() {
        local mx := 0, my := 0
        if (!this.curBitmap || !this._mouseOverPic(&mx, &my))
            return
        local startX := mx, startY := my
        local baseX := this.panX, baseY := this.panY
        while (GetKeyState("LButton", "P")) {
            if (!this._mouseOverPic(&mx, &my, false))
                break
            local dx := mx - startX, dy := my - startY
            if (Abs(dx) > 1 || Abs(dy) > 1) {
                this.panX := baseX + dx
                this.panY := baseY + dy
                this._render()
            }
            Sleep(16)
        }
    }

    ; Fare, önizleme kutusunun içinde mi? mx/my kutu köşesine göre koordinat.
    _mouseOverPic(&mx, &my, requireInside := true) {
        local prev := A_CoordModeMouse
        CoordMode("Mouse", "Window")
        local wx := 0, wy := 0
        MouseGetPos(&wx, &wy)
        CoordMode("Mouse", prev)
        local px := 0, py := 0, pw := 0, ph := 0
        this.pic.GetPos(&px, &py, &pw, &ph)
        mx := wx - px, my := wy - py
        if (!requireInside)
            return true
        return (mx >= 0 && my >= 0 && mx < pw && my < ph)
    }

    ; ── Eylemler ─────────────────────────────────────────────────────────────

    ; Panoya koy — pencere açık kalır, yapıştırmayı kullanıcı yapar
    _copyOnly() {
        local row := this.lv.GetNext(0)
        if (row < 1)
            return
        App.ClipHist.ignoreNextChange := true
        if (App.ClipImages.toClipboard(this.items[row]["slot"]))
            ShowTip("Panoya kopyalandı", TipType.Success, 900)
        else
            ShowTip("Panoya konulamadı!", TipType.Warning, 1200)
    }

    ; Seçili satır numaraları (Ctrl/Shift ile çoklu seçim), ARTAN sırada.
    _selectedRows() {
        local rows := [], row := 0
        while (row := this.lv.GetNext(row))
            rows.Push(row)
        return rows
    }

    ; Geri alma arayüzden kaldırıldığı için toplu silmede onay soruyoruz.
    ; Tekli silme hızlı kalsın diye onaysız (istenirse buraya da eklenebilir).
    _deleteSelected() {
        local rows := this._selectedRows()
        if (rows.Length == 0)
            return
        if (rows.Length > 1) {
            if (MsgBox(rows.Length " görsel silinecek.`nEmin misiniz?", "Toplu silme", "YesNo Icon!") != "Yes")
                return
        }
        local slots := []
        for row in rows
            slots.Push(this.items[row]["slot"])
        local n := App.ClipImages.deleteMany(slots)
        if (n == 0)
            return
        ; Satırları AZALAN sırada çıkar — küçükten silersek sonraki indeksler kayar
        local i := rows.Length
        while (i >= 1) {
            this.items.RemoveAt(rows[i])
            this.lv.Delete(rows[i])
            i -= 1
        }
        if (this.items.Length == 0) {
            this.close()
            ShowTip("Görsel geçmişi boşaldı.", TipType.Info, 1200)
            return
        }
        this._refreshStats()
        local next := Min(rows[1], this.items.Length)
        this.lv.Modify(next, "Select Focus")
        ShowTip(n " görsel silindi", TipType.Info, 1200)
    }

    _export() {
        local row := this.lv.GetNext(0)
        if (row < 1)
            return
        local item := this.items[row]
        local target := FileSelect("S16", "clip_" item["id"] ".png", "PNG olarak kaydet", "PNG (*.png)")
        if (target == "")
            return
        if (SubStr(target, -4) != ".png")   ; InStr her yerde arıyordu ("a.png.bak" geçiyordu)
            target .= ".png"
        if (App.ClipImages.exportTo(item["slot"], target))
            ShowTip("Kaydedildi: " target, TipType.Success, 1500)
        else
            ShowTip("Kaydedilemedi!", TipType.Warning, 1500)
    }

    ; ── Kapanış ──────────────────────────────────────────────────────────────

    close() {
        SetTimer(this.selectBound, 0)   ; kapanıştan sonra ateşlenecek seçim kalmasın
        try {
            HotIf(this.hotIfBound)
            for key in ["~WheelUp", "~WheelDown", "~LButton"]
                Hotkey(key, "Off")
            HotIf()
        }
        this._releaseBitmap()
        if (this.hIL) {
            DllCall("comctl32\ImageList_Destroy", "Ptr", this.hIL)
            this.hIL := 0
        }
        if (this.gui) {
            this.gui.Destroy()   ; Picture'a atanmış HBITMAP'i kontrol kendi siler
            this.gui := 0
        }
        ; Yok edilmiş kontrollere ait referansları da bırak — _refreshStats gibi
        ; geç çağrılar ölü kontrole yazmaya çalışmasın
        this.lv := 0, this.pic := 0, this.info := 0, this.stats := 0
        this.items := [], this.curRow := 0
    }

    _releaseBitmap() {
        if (this.curBitmap) {
            GdipMini.releaseBitmap(this.curBitmap)
            this.curBitmap := 0
        }
    }

    _formatTs(tsMs) {
        local ahkTime := DateAdd("19700101000000", tsMs // 1000, "S")
        return SubStr(ahkTime, 7, 2) "-" SubStr(ahkTime, 5, 2) " "
             . SubStr(ahkTime, 9, 2) ":" SubStr(ahkTime, 11, 2)
    }
}
