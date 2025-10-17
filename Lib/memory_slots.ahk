class MemorySlotsManager {
    static instance := ""

    static getInstance() {
        if (!MemorySlotsManager.instance) {
            MemorySlotsManager.instance := MemorySlotsManager()
        }
        return MemorySlotsManager.instance
    }

    __New() {
        if (MemorySlotsManager.instance) {
            throw Error("MemorySlotsManager zaten oluşturulmuş! getInstance kullan.")
        }

        this.autoFillFromHistory := false  ; Clipboard değişikliklerinde otomatik slot doldurma
        this.slots := []
        Loop 10 {
            this.slots.Push("")
        }

        ; GUI kontrol referansları
        this.slotControls := []
        this.gui := ""
        this.listBox := ""
        this.toggleBtn := ""  ; Yeni: Toggle butonu referansı için

        ; Clipboard history
        this.clipHistory := []
        this.clipListenerActive := false
        this.lastClipContent := ""  ; Tekrar kaydı önlemek için

        this.isDestroyed := false
        this.savedHwnd := 0  ; HWND'yi sakla, GUI yokken kullan
        this.ignoreNextClipChange := false  ; Yeni: Paste sırasında listener'ı blokla
    }

    start(autoFill) {
        this.autoFillFromHistory := autoFill
        this._createGui()
        this._setupHotkeys()
        this.gui.Show("x10 y10 w420 h520")
        this._startClipListener()
    }

    _createGui() {
        try {
            this.gui := Gui("+AlwaysOnTop +ToolWindow +MinimizeBox", "💾 Hafıza Slotları")
            this.gui.OnEvent("Close", (*) => this._destroy())
            this.gui.OnEvent("Escape", (*) => this._destroy())
            this.gui.SetFont("s9", "Segoe UI")

            this.gui.Add("Text", "x10 y10 w400 Center", "🔹 F1-F10: Kısa=Slot Yapıştır | Uzun=History Paste 🔹")

            ; Yeni: Auto-Fill toggle butonu, copy butonunun yanına
            this.toggleBtn := this.gui.Add("Button", "x10 y25 w200 h30", this.autoFillFromHistory ? "🟢 Auto-Fill: Aktif" : "🔴 Auto-Fill: Pasif")
            this.toggleBtn.OnEvent("Click", (*) => this._toggleAutoFill())

            copyBtn := this.gui.Add("Button", "x220 y25 w190 h30", "💾 Slot'a Kopyala")
            copyBtn.OnEvent("Click", (*) => this._copyToSlotPrompt())

            Loop 10 {
                slotNum := A_Index
                yPos := 60 + (A_Index - 1) * 26
                fKey := "F" . slotNum

                textCtrl := this.gui.Add("Text", "x10 y" . yPos . " w400 h22 Border",
                    fKey . " [Slot " . slotNum . "]: (Boş)")
                textCtrl.SetFont("s8", "Consolas")
                this.slotControls.Push(textCtrl)
            }

            ; Clipboard History bölümü geri eklendi
            this.gui.Add("Text", "x10 y320 w400 Center",
                "📋 Clipboard Geçmişi (Çift Tık: Kopyala)")

            this.listBox := this.gui.Add("ListBox", "x10 y345 w400 h160")
            this.listBox.OnEvent("DoubleClick", (*) => this._showHistoryDetail())  ; Çift tık: Direkt copy
            ; Transparan ayarı             ; WinSetTransparent(220, this.gui.hwnd)

        } catch as err {
            errHandler.handleError("GUI oluşturma hatası", err)
        }
    }

    ; Yeni: Auto-Fill toggle butonu tıklama olayı
    _toggleAutoFill() {
        this.autoFillFromHistory := !this.autoFillFromHistory
        statusText := this.autoFillFromHistory ? "🟢 Auto-Fill: Aktif" : "🔴 Auto-Fill: Pasif"
        if (this.toggleBtn) {
            this.toggleBtn.Text := statusText  ; Buton metnini güncelle
        }
        this._showTooltip(this.autoFillFromHistory ? "🟢 Auto-Fill aktif" : "🔴 Auto-Fill pasif", 800)
    }

    _setupHotkeys() {
        Loop 10 {
            num := A_Index
            ; Her lambda için num'u explicit capture et (loop son değeri sorunu önler)
            capturedCallback := ((fixedNum) => (*) => this._handleSlotPress(fixedNum))(num)
            Hotkey("F" . num, capturedCallback, "On")
        }
    }

    _handleSlotPress(slotNum) {
        ; Pencere açıkken çalış (ama global hotkey, her yerden)
        if (!WinExist("ahk_id " . (this.savedHwnd ? this.savedHwnd : this.gui.hwnd))) {
            return
        }

        ; Yeni: Tuş basımı sırasında listener'ı bir kez blokla (paste için)
        this.ignoreNextClipChange := true

        this._tapOrHold(
            () => this._pasteSlot(slotNum),        ; Kısa: Slot yapıştır
            () => this._copyToSlot(slotNum),       ; Orta: Slot'a kopyala (prompt'suz)
            () => this._pasteFromHistory(slotNum), ; Uzun: History'den paste
            300,   ; Short threshold (ms)
            800,   ; Medium threshold (ms)
            1500   ; Long threshold (ms)
        )

        ; İşlem sonrası flag'i reset et (serbest bırak)
        this.ignoreNextClipChange := false
    }

    ; Kısa basma: Slottan yapıştır
    _pasteSlot(slotNum) {
        if (this.slots[slotNum] == "") {
            ; Yeni: Boş slot'ta otomatik kopyala (prompt'suz)
            this._copyToSlot(slotNum)
            this._showTooltip("⚠️ Slot " . slotNum . " boştu, otomatik kopyalandı", 1500)
            return  ; Paste'i atla, copy tamamlandı
        }

        ; Eski paste mantığı (slot doluysa)
        savedClip := A_Clipboard
        A_Clipboard := this.slots[slotNum]

        if (ClipWait(0.5)) {
            Send("^v")
            this._showTooltip("✅ Slot " . slotNum . " yapıştırıldı", 1000)
        } else {
            this._showTooltip("❌ Yapıştırma başarısız!")
        }

        Sleep(100)
        A_Clipboard := savedClip
    }

    ; Yeni: Uzun basma: History'den o numaralı item'ı paste
    _pasteFromHistory(slotNum) {
        if (this.clipHistory.Length < slotNum) {
            this._showTooltip("⚠️ History'de " . slotNum . ". item yok!")
            return
        }
        realIdx := this.clipHistory.Length - slotNum + 1  ; En yeni üstte
        content := this.clipHistory[realIdx]
        if (content == "") {
            this._showTooltip("⚠️ History " . slotNum . " boş!")
            return
        }
        savedClip := A_Clipboard
        A_Clipboard := content
        if (ClipWait(0.5)) {
            Send("^v")
            this._showTooltip("✅ History " . slotNum . " yapıştırıldı", 1000)
            ; Çakışma önleme: Ana script için kısa ignore set et
        } else {
            this._showTooltip("❌ History yapıştırma başarısız!")
        }
        Sleep(100)
        A_Clipboard := savedClip
    }

    ; Orta basma: Slot'a kopyala (prompt'suz)
    _copyToSlot(slotNum) {
        savedClip := A_Clipboard
        Send("^c")
        ClipWait(0.5)
        if (A_Clipboard != "") {
            this.slots[slotNum] := A_Clipboard
            this._updateSlotPreview(slotNum, A_Clipboard)
            this._showTooltip("✅ Slot " . slotNum . " kopyalandı", 1000)
        } else {
            this._showTooltip("❌ Kopyalama başarısız!")
        }
        Sleep(100)
        A_Clipboard := savedClip
    }

    ; Prompt'lu kopyala (manuel buton için) – v2 syntax düzeltildi
    _copyToSlotPrompt() {
        local slotNumInput := ""  ; Local tanımla ve başlat
        InputBox(&slotNumInput, "Hangi slota kopyala? (1-10)", "Slot Numarası")
        if (slotNumInput == "" || !IsInteger(slotNumInput) || slotNumInput < 1 || slotNumInput > 10) {
            this._showTooltip("❌ Geçersiz slot numarası!")
            return
        }
        slotNum := Integer(slotNumInput)
        this._copyToSlot(slotNum)
    }

    ; Slot preview'ini güncelle
    _updateSlotPreview(slotNum, content) {
        if (slotNum < 1 || slotNum > 10) {
            return
        }
        fKey := "F" . slotNum
        if (content == "") {
            preview := "(Boş)"
        } else {
            preview := StrReplace(SubStr(content, 1, 45), "`n", " ")
            preview := RegExReplace(preview, "\s+", " ")  ; Çoklu boşlukları tek yap
            preview := Trim(preview)
            if (StrLen(preview) > 45) {
                preview := SubStr(preview, 1, 45) . "..."
            }
        }

        this.slotControls[slotNum].Text := fKey . " [Slot " . slotNum . "]: " . preview
    }

    ; Clipboard dinleyici başlat
    _startClipListener() {
        if (!this.clipListenerActive) {
            OnClipboardChange(this._onClipChange.Bind(this))
            this.clipListenerActive := true
            this.lastClipContent := A_Clipboard
            ; Yeni: HWND'yi sakla (GUI destroy'da hwnd kaybolmasın)
            if (this.gui && this.gui.hwnd) {
                this.savedHwnd := this.gui.hwnd
            }
        }
    }

    ; Clipboard değiştiğinde
    _onClipChange(clipType) {
        if (this.isDestroyed) {
            return
        }

        ; Yeni: Tuş basımı sırasında ignore flag'i kontrol et
        if (this.ignoreNextClipChange) {
            this.ignoreNextClipChange := false  ; Flag'i tüket ve reset et
            return
        }

        ; Çakışma guard'ı (F20 vb. için)
        if (clipType != 1 || !WinExist("ahk_id " . (this.savedHwnd ? this.savedHwnd : this.gui.hwnd))) {
            return
        }
        static ignoreUntil := 0
        if (A_TickCount < ignoreUntil) {
            return
        }

        newClip := A_Clipboard

        if (newClip == "" || newClip == this.lastClipContent) {
            return
        }

        this.lastClipContent := newClip
        this.clipHistory.Push(newClip)

        if (this.clipHistory.Length > 50) {
            this.clipHistory.RemoveAt(1)
        }

        ; Yeni: autoFillFromHistory aktifse, boş slotu otomatik doldur
        if (this.autoFillFromHistory) {
            this._autoFillEmptySlot(newClip)
        }

        this._refreshHistoryList()  ; Listbox güncelle
    }

    ; Yeni metod: Boş slotu otomatik doldur (sırayla 1'den başlayarak)
    _autoFillEmptySlot(newClip) {
        foundEmpty := false
        Loop 10 {
            if (this.slots[A_Index] == "") {
                this.slots[A_Index] := newClip
                this._updateSlotPreview(A_Index, newClip)  ; GUI'yi güncelle
                this._showTooltip("✅ Slot " . A_Index . " otomatik dolduruldu (" . StrLen(newClip) . " karakter)", 1000)
                foundEmpty := true
                break
            }
        }
        if (!foundEmpty) {
            ; Opsiyonel: Tüm slotlar doluysa en eskisini overwrite et (veya uyarı ver)
            this._showTooltip("⚠️ Tüm slotlar dolu, overwrite yapılmadı.", 800)
            ; Alternatif: this.slots[1] := newClip  ; En eskini ez
        }
    }

    ; History listesini yenile
    _refreshHistoryList() {
        this.listBox.Delete()

        ; En yeni üstte göster
        Loop this.clipHistory.Length {
            idx := this.clipHistory.Length - A_Index + 1
            content := this.clipHistory[idx]

            ; Önizleme oluştur
            preview := StrReplace(StrReplace(content, "`r`n", " "), "`n", " ")
            preview := RegExReplace(preview, "\s+", " ")
            preview := Trim(preview)

            if (StrLen(preview) > 60) {
                preview := SubStr(preview, 1, 60) . "..."
            }

            ; Güvenli Add: Array olarak wrap et (string concatenation hatası için)
            this.listBox.Add(["#" . A_Index . ": " . preview])
        }
    }

    ; History detay penceresi
    _showHistoryDetail() {
        sel := this.listBox.Value
        if (!sel || sel < 1 || sel > this.clipHistory.Length) {
            return
        }

        ; Liste tersinden seçim yap (en yeni üstte)
        realIdx := this.clipHistory.Length - sel + 1
        content := this.clipHistory[realIdx]

        if (content == "") {
            this._showTooltip("⚠️ Seçili item boş!")
            return
        }

        A_Clipboard := content
        ClipWait(0.5)
        this._showTooltip("✅ #" . sel . " clipboard'a kopyalandı (" . StrLen(content) . " karakter)", 1500)
    }

    ; Tooltip yardımcı fonksiyon
    _showTooltip(msg, duration := 1200) {
        ToolTip(msg, , , 1)
        SetTimer(() => ToolTip(), -duration)
    }

    _tapOrHold(shortFn, mediumFn, longFn, shortTime, mediumTime, longTime) {
        startTime := A_TickCount
        key := A_ThisHotkey

        ; Bip sayacı (orta: 1 bip, uzun: 2 bip)
        beepDoneMedium := false
        beepDoneLong := false

        ; Tuş basılı kaldığı sürece bekle
        while (GetKeyState(key, "P")) {
            elapsed := A_TickCount - startTime

            ; Orta eşiğine ulaşınca bir kez bip
            if (elapsed >= mediumTime && !beepDoneMedium) {
                SoundBeep(800, 80)
                beepDoneMedium := true
            }

            ; Uzun eşiğine ulaşınca ikinci bip
            if (elapsed >= longTime && !beepDoneLong) {
                SoundBeep(600, 100)
                beepDoneLong := true
            }

            Sleep(20)  ; Responsive kal
        }

        ; Tuş bırakıldığında süreye göre karar ver
        elapsed := A_TickCount - startTime

        if (elapsed < shortTime) {
            shortFn.Call()  ; Kısa: Paste slot
        } else if (elapsed < mediumTime) {
            mediumFn.Call()  ; Orta: Copy to slot
        } else {
            longFn.Call()   ; Uzun: Paste from history
        }
    }

    ; Temizlik
    _destroy() {
        ; Yeni: Önce flag set et (callback'ler için)
        this.isDestroyed := true

        ; Hotkey'leri kapat
        Loop 10 {
            try {
                Hotkey("F" . A_Index, "Off")
            }
        }

        ; Clipboard listener'ı durdur (önce kapat, sonra flag zaten set)
        if (this.clipListenerActive) {
            OnClipboardChange(this._onClipChange.Bind(this), 0)
            this.clipListenerActive := false
        }

        ; Yeni: Array'leri temizle, dangling referansları önle
        this.slotControls := []
        this.savedHwnd := 0  ; HWND'yi sıfırla

        ; GUI'yi yok et
        if (this.gui) {
            this.gui.Destroy()
            this.gui := ""  ; Referansı temizle
        }

        ; Singleton'ı sıfırla
        MemorySlotsManager.instance := ""
    }
}