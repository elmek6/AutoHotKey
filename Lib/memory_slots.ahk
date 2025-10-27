class singleMemorySlots {
    static instance := ""

    static getInstance() {
        if (!singleMemorySlots.instance) {
            singleMemorySlots.instance := singleMemorySlots()
        }
        return singleMemorySlots.instance
    }

    __New() {
        if (singleMemorySlots.instance) {
            throw Error("MemorySlotsManager zaten oluşturulmuş! getInstance kullan.")
        }

        this.slots := []
        Loop 10 {
            this.slots.Push("")
        }

        ; GUI kontrol referansları
        this.slotControls := []
        this.gui := ""
        this.listBox := ""
        this.toggleBtn := ""  ; Toggle butonu referansı

        ; Clipboard history
        this.clipHistory := []
        this.lastClipContent := ""  ; Tekrar kaydı önlemek için
        this.isDestroyed := false
        this.savedHwnd := 0  ; HWND'yi sakla
        this.ignoreNextClipChange := false  ; Paste sırasında listener'ı blokla
    }

    start() {
        gState.setAutoClip(1)
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

            ; Smart mode toggle butonu
            this.toggleBtn := this.gui.Add("Button", "x10 y25 w200 h30", gState.getAutoClip() ? "🟢 Smart Mode: Aktif" : "🔴 Smart Mode: Pasif")
            this.toggleBtn.OnEvent("Click", (*) => this._toggleSmartClip())

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

            this.gui.Add("Text", "x10 y320 w400 Center", "📋 Clipboard Geçmişi (Çift Tık: Kopyala)")
            this.listBox := this.gui.Add("ListBox", "x10 y345 w400 h160")
            this.listBox.OnEvent("DoubleClick", (*) => this._showHistoryDetail())
        } catch as err {
            gErrHandler.handleError("GUI oluşturma hatası", err)
        }
    }

    _toggleSmartClip() {
        if (gState.getAutoClip() == 0) {
            gState.setAutoClip(1)  ; Smart copy aktif
            this.toggleBtn.Text := "🟢 Smart Mode: Aktif"
            this._showTooltip("🟢 Smart Copy aktif", 800)
        } else {
            gState.setAutoClip(0)  ; Smart mode kapat
            gState.setSmartClipIndex(0)  ; Index sıfırla
            this.toggleBtn.Text := "🔴 Smart Mode: Pasif"
            this._showTooltip("🔴 Smart Mode pasif", 800)
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
        if (!WinExist("ahk_id " . (this.savedHwnd ? this.savedHwnd : this.gui.hwnd))) {
            return
        }

        this.ignoreNextClipChange := true
        this._tapOrHold(
            () => this.smartPaste(),        ; Kısa: Smart paste
            () => this._copyToSlot(slotNum),       ; Orta: Slot'a kopyala
            () => this._pasteFromHistory(slotNum), ; Uzun: History'den paste
            300,   ; Short threshold
            800,   ; Medium threshold
            1500   ; Long threshold
        )
        this.ignoreNextClipChange := false
    }

    smartCopy() {
        if (gState.getAutoClip() == 0 || gState.getAutoClip() == 2) {
            Send("^c")
            return
        }
        slotIndex := gState.getSmartClipIndex()
        if (slotIndex < 1 || slotIndex > this.slots.Length) {
            slotIndex := 1  ; Hata koruması: Index sınır dışıysa sıfırla
            gState.setSmartClipIndex(1)
        }
        else
            this._copyToSlot(slotIndex)
        gState.setSmartClipIndex(slotIndex + 1)
    }

    smartPaste() {
        switch gState.getAutoClip() {
            ; case -1: ignore cl
            case 0:
                Send("^v")
            case 1:
                gState.setAutoClip(2)  ; Paste moduna geç
                gState.setSmartClipIndex(1)
                this._pasteSlot(1)
            case 2:
                slotIndex := gState.getSmartClipIndex()
                if (slotIndex < 1 || slotIndex > this.slots.Length) {
                    slotIndex := 1  ; Hata koruması
                    gState.setSmartClipIndex(1)
                }
                if (this.slots[slotIndex] == "") {
                    gState.setAutoClip(2)  ; Slotlar bitti, history'ye geç
                    this._pasteFromHistory(slotIndex)
                } else {
                    this._pasteSlot(slotIndex)
                    gState.setSmartClipIndex(slotIndex + 1)
                }
        }
    }

    _pasteSlot(slotNum) {
        if (slotNum < 1 || slotNum > this.slots.Length) {
            this._showTooltip("⚠️ Geçersiz slot: " . slotNum, 1500)
            return
        }
        if (this.slots[slotNum] == "") {
            this._showTooltip("⚠️ Slot " . slotNum . " boş", 1500)
            return
        }

        savedClip := A_Clipboard
        A_Clipboard := this.slots[slotNum]
        if (ClipWait(0.5)) {
            Send("^v")
            this._showTooltip("✅ Slot " . slotNum . " yapıştırıldı", 1000)
        } else {
            this._showTooltip("❌ Yapıştırma başarısız!", 1000)
        }
        Sleep(100)
        A_Clipboard := savedClip
    }

    ; Orta basma: Slot'a kopyala (prompt'suz)
    _copyToSlot(slotNum) {
        if (slotNum < 1 || slotNum > this.slots.Length) {
            this._showTooltip("⚠️ Geçersiz slot: " . slotNum, 1500)
            return
        }
        savedClip := A_Clipboard
        Send("^c")
        Sleep(50)
        if (ClipWait(0.5) && A_Clipboard != "") {
            this.slots[slotNum] := A_Clipboard
            this._updateSlotPreview(slotNum, A_Clipboard)
            this._showTooltip("✅ Slot " . slotNum . " kopyalandı (" . StrLen(A_Clipboard) . " karakter)", 1000)
        } else {
            this._showTooltip("❌ Kopyalama başarısız!", 1000)
        }
        A_Clipboard := savedClip
    }

    _pasteFromHistory(slotNum) {
        if (this.clipHistory.Length < slotNum || slotNum < 1) {
            this._showTooltip("⚠️ History'de " . slotNum . ". item yok!", 1500)
            return
        }
        realIdx := this.clipHistory.Length - slotNum + 1
        savedClip := A_Clipboard
        A_Clipboard := this.clipHistory[realIdx]
        if (ClipWait(0.5)) {
            Send("^v")
            this._showTooltip("✅ History #" . slotNum . " yapıştırıldı", 1000)
        } else {
            this._showTooltip("❌ Yapıştırma başarısız!", 1000)
        }
        Sleep(100)
        A_Clipboard := savedClip
    }

    _copyToSlotPrompt() {
        savedClip := A_Clipboard
        Send("^c")
        Sleep(50)
        try {
            if (!ClipWait(0.5) || A_Clipboard == "") {
                throw Error("Kopyalama başarısız")
            }
            content := A_Clipboard
            input := InputBox("Slot numarası (1-10):", "Slot'a Kopyala", , "1")
            if (input.Result == "OK" && input.Value != "") {
                slotNum := Integer(input.Value)
                if (slotNum >= 1 && slotNum <= this.slots.Length) {
                    this.slots[slotNum] := content
                    this._updateSlotPreview(slotNum, content)
                    this._showTooltip("✅ Slot " . slotNum . " kopyalandı", 1000)
                } else {
                    this._showTooltip("⚠️ Geçersiz slot numarası", 1500)
                }
            }
        } catch as err {
            gErrHandler.handleError("Kopyalama hatası", err)
        }
        A_Clipboard := savedClip
    }

    _startClipListener() {
        if (gState.getAutoClip() == -1) {
            return
        }
        OnClipboardChange(this._onClipChange.Bind(this))
        if (this.gui && this.gui.hwnd) {
            this.savedHwnd := this.gui.hwnd
        }
    }

    _onClipChange(clipType) {
        if (this.isDestroyed) {
            return
        }

        if (clipType != 1 || !WinExist("ahk_id " . (this.savedHwnd ? this.savedHwnd : this.gui.hwnd))) {
            return
        }
        if (gState.getAutoClip() == 1 || gState.getAutoClip() == 2 || gState.getAutoClip() == -1) {
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
        if (gState.getAutoClip() == 1) {
            this._autoFillEmptySlot(newClip)
        }
        this._refreshHistoryList()
    }

    _autoFillEmptySlot(newClip) {
        slotIndex := gState.getSmartClipIndex()
        if (slotIndex < 1 || slotIndex > this.slots.Length) {
            slotIndex := 1
            gState.setSmartClipIndex(1)
        }
        if (this.slots[slotIndex] == "") {
            this.slots[slotIndex] := newClip
            this._updateSlotPreview(slotIndex, newClip)
            this._showTooltip("✅ Slot " . slotIndex . " otomatik dolduruldu (" . StrLen(newClip) . " karakter)", 1000)
            gState.setSmartClipIndex(slotIndex + 1)
        } else {
            this._showTooltip("⚠️ Slot " . slotIndex . " dolu, bir sonrakine geçiliyor", 800)
            gState.setSmartClipIndex(slotIndex + 1)
            if (slotIndex >= this.slots.Length) {
                this._showTooltip("⚠️ Tüm slotlar dolu", 800)
                gState.setSmartClipIndex(1)
            }
        }
    }

    _refreshHistoryList() {
        this.listBox.Delete()
        Loop this.clipHistory.Length {
            idx := this.clipHistory.Length - A_Index + 1
            content := this.clipHistory[idx]
            preview := StrReplace(StrReplace(content, "`r`n", " "), "`n", " ")
            preview := RegExReplace(preview, "\s+", " ")
            preview := Trim(preview)
            if (StrLen(preview) > 60) {
                preview := SubStr(preview, 1, 60) . "..."
            }
            this.listBox.Add(["#" . A_Index . ": " . preview])
        }
    }

    _showHistoryDetail() {
        sel := this.listBox.Value
        if (!sel || sel < 1 || sel > this.clipHistory.Length) {
            return
        }
        realIdx := this.clipHistory.Length - sel + 1
        content := this.clipHistory[realIdx]
        if (content == "") {
            this._showTooltip("⚠️ Seçili item boş!", 1500)
            return
        }
        A_Clipboard := content
        ClipWait(0.5)
        this._showTooltip("✅ #" . sel . " clipboard'a kopyalandı (" . StrLen(content) . " karakter)", 1500)
    }

    _showTooltip(msg, duration := 1200) {
        ToolTip(msg, , , 1)
        SetTimer(() => ToolTip(), -duration)
    }

    _updateSlotPreview(slotNum, content) {
        if (slotNum < 1 || slotNum > this.slots.Length) {
            return
        }
        preview := StrReplace(StrReplace(content, "`r`n", " "), "`n", " ")
        preview := RegExReplace(preview, "\s+", " ")
        preview := Trim(preview)
        if (StrLen(preview) > 60) {
            preview := SubStr(preview, 1, 60) . "..."
        }
        this.slotControls[slotNum].Text := "F" . slotNum . " [Slot " . slotNum . "]: " . (preview ? preview : "(Boş)")
    }

    _tapOrHold(shortFn, mediumFn, longFn, shortTime, mediumTime, longTime) {
        startTime := A_TickCount
        key := A_ThisHotkey
        beepDoneMedium := false
        beepDoneLong := false
        while (GetKeyState(key, "P")) {
            elapsed := A_TickCount - startTime
            if (elapsed >= mediumTime && !beepDoneMedium) {
                SoundBeep(800, 80)
                beepDoneMedium := true
            }
            if (elapsed >= longTime && !beepDoneLong) {
                SoundBeep(600, 100)
                beepDoneLong := true
            }
            Sleep(20)
        }
        elapsed := A_TickCount - startTime
        if (elapsed < shortTime) {
            shortFn.Call()
        } else if (elapsed < mediumTime) {
            mediumFn.Call()
        } else {
            longFn.Call()
        }
    }

    _destroy() {
        this.isDestroyed := true
        Loop 10 {
            try {
                Hotkey("F" . A_Index, "Off")
            }
        }

        ; destroy clipboard listener
        OnClipboardChange(this._onClipChange.Bind(this), 0)


        this.slotControls := []
        this.savedHwnd := 0
        gState.setAutoClip(0)  ; Smart mode sıfırla
        gState.setSmartClipIndex(0)  ; Index sıfırla
        if (this.gui) {
            this.gui.Destroy()
            this.gui := ""
        }
        singleMemorySlots.instance := ""
    }
}
/*
; ... Mevcut kod korunuyor ...
#HotIf (gState.getAutoClip() > 0)
^c::gMemSlots.smartCopy()
^x::gMemSlots.smartCopy()  ; Cut yerine copy, farklılaşabilir
^v::gMemSlots.smartPaste()
#HotIf
*/
