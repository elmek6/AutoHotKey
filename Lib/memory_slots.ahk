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

        ; Slot verilerini başlat
        this.slots := []
        Loop 10 {
            this.slots.Push("")
        }

        ; GUI kontrol referansları
        this.slotControls := []
        this.gui := ""
        this.listBox := ""

        ; Clipboard history
        this.clipHistory := []
        this.clipListenerActive := false
        this.lastClipContent := ""  ; Tekrar kaydı önlemek için

        this.isDestroyed := false
        this.savedHwnd := 0  ; HWND'yi sakla, GUI yokken kullan
    }
    start() {
        ; TODO belkide F1 kisa basic bossa copy doluysa paste, F1 uzun basic slotu bosalt??
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
            copyBtn := this.gui.Add("Button", "x10 y25 w400 h30", "💾 Slot'a Kopyala")
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

        this._tapOrHold(
            () => this._pasteSlot(slotNum),        ; Kısa: Slot yapıştır
            () => this._copyToSlot(slotNum),       ; Orta: Slot'a kopyala (prompt'suz)
            () => this._pasteFromHistory(slotNum), ; Uzun: History'den paste
            300,   ; Short threshold (ms)
            800,   ; Medium threshold (ms)
            1500   ; Long threshold (ms)
        )
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
            ignoreUntil := A_TickCount + 200  ; 200ms ignore
        } else {
            this._showTooltip("❌ History paste başarısız!")
        }
        Sleep(100)
        A_Clipboard := savedClip
    }

    ; Eski copyToSlot'u buton için ayırdım (prompt ile slot seç)
    _copyToSlotPrompt() {
        input := InputBox("Hangi slota kopyala? (1-10)", "Slot Seç", , "1")
        if (input.Result != "OK" || !IsInteger(input.Value) || input.Value < 1 || input.Value > 10) {
            this._showTooltip("❌ Geçersiz slot!")
            return
        }
        slotNum := input.Value
        this._copyToSlot(slotNum)  ; Prompt'suz, varsayılan isim
    }

    ; Uzun basma için eski copy (şimdi butonla)
    _copyToSlot(slotNum) {
        ; Orta basma: Seçili text'i kopyala
        Send("^c")
        ClipWait(0.5)  ; Clipboard bekle
        Sleep(50)      ; Stabilite için

        if (A_Clipboard == "") {
            this._showTooltip("⚠️ Clipboard boş!")
            return
        }

        content := A_Clipboard
        fKey := "F" . slotNum

        ; İsim prompt'unu atla (varsayılan kullan)
        slotName := "Slot " . slotNum

        this.slots[slotNum] := content

        ; Preview oluştur
        preview := content
        preview := StrReplace(StrReplace(preview, "`r`n", " "), "`n", " ")
        preview := StrReplace(preview, "`t", " ")
        preview := RegExReplace(preview, "\s+", " ")
        preview := Trim(preview)

        if (StrLen(preview) > 45) {
            preview := SubStr(preview, 1, 45) . "..."
        }

        this.slotControls[slotNum].Text := fKey . " [Slot " . slotNum . "]: " . preview
        this._showTooltip("✅ Slot " . slotNum . " kaydedildi: " . slotName, 1000)
    }

    ; Slot görünümünü güncelle
    _updateSlotDisplay(slotNum) {
        content := this.slots[slotNum]
        fKey := "F" . slotNum

        if (content == "") {
            preview := "(Boş)"
        } else {
            ; Tek satır yap ve kısalt
            preview := StrReplace(StrReplace(content, "`r`n", " "), "`n", " ")
            preview := StrReplace(preview, "`t", " ")
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

        this._refreshHistoryList()  ; Listbox güncelle
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