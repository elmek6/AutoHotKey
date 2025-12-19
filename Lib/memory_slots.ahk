class singleMemorySlots {
    static instance := ""
    static MAX_SLOTS := 10

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
    }

    start() {
        this.previousState := gState.getClipHandler()
        gState.setClipHandler(gState.clipStatusEnum.memSlot)

        this.slots := []
        this.currentSlotIndex := 1
        this.slotControls := []
        this.gui := ""
        this.listBox := ""
        this.toggleBtn := ""
        this.middlePasteCheck := ""
        this.clipHistory := []
        this.lastClipContent := ""
        this.isDestroyed := false
        this.savedHwnd := 0
        this.clipTypeEnum := {
            copy: true,
            paste: false,
        }
        this.clipType := this.clipTypeEnum.copy
        OnClipboardChange(this.clipboardWatcher.Bind(this))

        this._createGui()
        ; this._setupHotkeys()
        this.gui.Show("x10 y10 w420 h520")
    }

    _createGui() {
        try {
            this.gui := Gui("+AlwaysOnTop +ToolWindow +MinimizeBox", "💾 Hafıza Slotları")
            this.gui.OnEvent("Close", (*) => this._destroy())
            this.gui.OnEvent("Escape", (*) => this._destroy())
            this.gui.SetFont("s9", "Segoe UI")

            this.gui.Add("Text", "x10 y10 w400 Center", "🔹 F1-F10: Kısa=Slot Yapıştır | Uzun=History Paste 🔹")

            ; Toggle butonu: clipType'a göre renk ve yazı
            this.toggleBtn := this.gui.Add("Button", "x10 y25 w200 h30", this.clipType ? "🟢 Smart Mode: Aktif (Copy)" : "🔴 Smart Mode: Pasif")
            this.toggleBtn.OnEvent("Click", (*) => this._toggleSmartMode())

            ; Temizle butonu
            clearBtn := this.gui.Add("Button", "x220 y25 w190 h30", "🗑️ Slotları Temizle")
            clearBtn.OnEvent("Click", (*) => this._clearSlots())

            ; Middle paste checkbox
            this.middlePasteCheck := this.gui.Add("CheckBox", "x10 y60 w300 h20 Checked1", "Orta basım: Aktif slotu yapıştır (Middle Paste)")
            this.middlePasteCheck.OnEvent("Click", (*) => this._showTooltip(this.middlePasteCheck.Value ? "🖱️ Orta basım → Yapıştır aktif" : "🖱️ Orta basım → Devre dışı", 1000))

            Loop singleMemorySlots.MAX_SLOTS {
                slotNum := A_Index
                yPos := 90 + (A_Index - 1) * 26
                fKey := "F" . slotNum

                textCtrl := this.gui.Add("Text", "x10 y" . yPos . " w400 h22 Border",
                    fKey . " [Slot " . slotNum . "]: (Boş)")
                textCtrl.SetFont("s8", "Consolas")
                this.slotControls.Push(textCtrl)
            }

            historyYPos := 90 + singleMemorySlots.MAX_SLOTS * 26 + 10
            this.gui.Add("Text", "x10 y" . historyYPos . " w400 Center", "📋 Clipboard Geçmişi (Çift Tık: Kopyala)")
            listBoxYPos := historyYPos + 25
            this.listBox := this.gui.Add("ListBox", "x10 y" . listBoxYPos . " w400 h160")
            this.listBox.OnEvent("DoubleClick", (*) => this._showHistoryDetail())

            this.savedHwnd := this.gui.hwnd
        } catch as err {
            gErrHandler.handleError("GUI oluşturma hatası", err)
        }
    }

    _toggleSmartMode() {
        this.clipType := !this.clipType  ; Copy <-> Paste arası geçiş
        if (this.clipType) {
            this.toggleBtn.Text := "🟢 Smart Mode: Aktif (Copy)"
            this._showTooltip("📥 Copy modu aktif: Yeni kopyalamalar slotlara dolacak", 1200)
        } else {
            this.toggleBtn.Text := "🔴 Smart Mode: Pasif"
            this._showTooltip("⏸️ Smart mode kapandı", 1000)
        }
    }

    _setupHotkeys() {
        Loop singleMemorySlots.MAX_SLOTS {
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

        this._tapOrHold(
            () => this.smartPaste(),
            () => this._pasteFromHistory(slotNum),
            300,
            1500
        )
    }

    ; Observer'dan gelen clipboard değişikliği
    clipboardWatcher(type) {
        ; OutputDebug("Clipboard tetiklendi! İkinci açılışta mı?")
        if (gState.getClipHandler() != gState.clipStatusEnum.memSlot) {
            return
        }

        if (this.clipType == this.clipTypeEnum.paste) {
            return
        }

        newClip := A_Clipboard
        if (newClip = "" || newClip = this.lastClipContent) {
            return
        }

        if (this.clipType == this.clipTypeEnum.copy) {
            this._autoFillSlot(newClip)
        }

        this.clipHistory.Push(newClip)
        this.lastClipContent := newClip
        this._refreshHistoryList()
    }

    _autoFillSlot(newClip) {
        ; Eğer currentSlotIndex geçersizse, başa al
        if (this.currentSlotIndex < 1) {
            this.currentSlotIndex := 1
        }

        ; Eğer array'in sonundaysak ve limit aşılmadıysa, yeni slot ekle
        if (this.currentSlotIndex > this.slots.Length) {
            if (this.slots.Length < singleMemorySlots.MAX_SLOTS) {
                this.slots.Push(newClip)
                this._updateSlotPreview(this.currentSlotIndex, newClip)
                this._showTooltip("✅ Slot " . this.currentSlotIndex . " otomatik dolduruldu (" . StrLen(newClip) . " karakter)", 1000)
                this.currentSlotIndex++
                return
            } else {
                ; Limit doldu, başa dön
                this._showTooltip("⚠️ Tüm slotlar dolu", 800)
                this.currentSlotIndex := 1
            }
        }

        ; Mevcut slot boşsa doldur
        if (this.slots[this.currentSlotIndex] == "") {
            this.slots[this.currentSlotIndex] := newClip
            this._updateSlotPreview(this.currentSlotIndex, newClip)
            this._showTooltip("✅ Slot " . this.currentSlotIndex . " otomatik dolduruldu (" . StrLen(newClip) . " karakter)", 1000)
            this.currentSlotIndex++
            return
        }

        ; Slot dolu, bir sonrakine geç
        this._showTooltip("⚠️ Slot " . this.currentSlotIndex . " dolu, bir sonrakine geçiliyor", 800)
        this.currentSlotIndex++
        
        ; Sınır kontrolü
        if (this.currentSlotIndex > singleMemorySlots.MAX_SLOTS) {
            this.currentSlotIndex := 1
        }
    }

    smartPaste(middlePressed := false) {
        ;duruma göre ya disardan kontrol et ya da burdan simdilik her iksinde de
        if (gState.getClipHandler() != gState.clipStatusEnum.memSlot) {
            return
        }

        if (middlePressed) {
            switch this.clipType {
                case this.clipTypeEnum.copy:
                    if (this.middlePasteCheck.Value) {
                        this.clipType := this.clipTypeEnum.paste
                        this.currentSlotIndex := 1
                    }
                case this.clipTypeEnum.paste:
                    this.currentSlotIndex++
                    if (this.currentSlotIndex > this.slots.Length) {
                        this.currentSlotIndex := 1
                    }
            }
        }

        if (this.currentSlotIndex > this.slots.Length || this.slots[this.currentSlotIndex] == "") {
            this._showTooltip("⚠️ Slot " . this.currentSlotIndex . " boş!", 800)
            return
        }

        A_Clipboard := this.slots[this.currentSlotIndex]
        ClipWait(0.2)
        SendInput("^v")
    }

    _pasteFromHistory(slotNum) {
        historyIndex := slotNum
        if (historyIndex < 1 || historyIndex > this.clipHistory.Length) {
            this._showTooltip("⚠️ History'de o kadar eski yok!", 1000)
            return
        }

        realIdx := this.clipHistory.Length - historyIndex + 1
        content := this.clipHistory[realIdx]
        A_Clipboard := content
        ClipWait(0.2)
        SendInput("^v")
        this._showTooltip("📜 History #" . historyIndex . " yapıştırıldı", 800)
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
        if (slotNum < 1 || slotNum > singleMemorySlots.MAX_SLOTS) {
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

    _tapOrHold(shortFn, longFn, shortTime := 300, longTime := 1500) {
        startTime := A_TickCount
        key := A_ThisHotkey
        beepLong := false
        while GetKeyState(key, "P") {
            elapsed := A_TickCount - startTime
            if (elapsed >= longTime && !beepLong) {
                SoundBeep(600, 100)
                beepLong := true
            }
            Sleep(20)
        }
        elapsed := A_TickCount - startTime
        if (elapsed < shortTime)
            shortFn.Call()
        else
            longFn.Call()
    }

    _clearSlots() {
        this.slots := []
        this.currentSlotIndex := 1
        Loop singleMemorySlots.MAX_SLOTS {
            this._updateSlotPreview(A_Index, "")
        }
        this._showTooltip("🗑️ Slotlar temizlendi, index sıfırlandı", 1000)
    }

    _destroy() {
        this.isDestroyed := true
        Loop singleMemorySlots.MAX_SLOTS {
            try {
                Hotkey("F" . A_Index, "Off")
            }
        }

        gState.setClipHandler(this.previousState)

        this.slotControls := []
        this.savedHwnd := 0
        if (this.gui) {
            this.gui.Destroy()
            this.gui := ""
        }
        singleMemorySlots.instance := ""
    }
}