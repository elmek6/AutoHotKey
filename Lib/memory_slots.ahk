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
    }

    start() {
        this.previousState := gState.getClipHandler()
        gState.setClipHandler(gState.clipStatusEnum.memSlot)

        this.slots := []
        Loop 10 {
            this.slots.Push("")
        }

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

            Loop 10 {
                slotNum := A_Index
                yPos := 90 + (A_Index - 1) * 26
                fKey := "F" . slotNum

                textCtrl := this.gui.Add("Text", "x10 y" . yPos . " w400 h22 Border",
                    fKey . " [Slot " . slotNum . "]: (Boş)")
                textCtrl.SetFont("s8", "Consolas")
                this.slotControls.Push(textCtrl)
            }

            this.gui.Add("Text", "x10 y350 w400 Center", "📋 Clipboard Geçmişi (Çift Tık: Kopyala)")
            this.listBox := this.gui.Add("ListBox", "x10 y375 w400 h160")
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
        ; middleFn := this.middlePasteCheck.Value
        ;     ? (*) => this.smartPaste()  ; Checked ise orta basım smartPaste
        ;     : (*) => {}                 ; Unchecked ise hiçbir şey yapma

        this._tapOrHold(
            () => this.smartPaste(),                    ; Kısa: Smart paste
            ; middleFn,                                   ; Orta: checkbox'a göre copyToSlot
            () => this._pasteFromHistory(slotNum),      ; Uzun: History'den paste
            300,   ; Short threshold
            ; 800,   ; Medium threshold
            1500   ; Long threshold
        )
    }

    ; Observer'dan gelen clipboard değişikliği
    clipboardWatcher(type) {
        ; OutputDebug("Clipboard tetiklendi! İkinci açılışta mı?")
        if (gState.getClipHandler() != gState.clipStatusEnum.memSlot) {
            return
        }

        if (this.clipType == this.clipTypeEnum.paste) {
            return ; eger yapistirma modundaysa
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
        if (this.currentSlotIndex < 1 || this.currentSlotIndex > this.slots.Length) {
            this.currentSlotIndex := 1
        }
        if (this.slots[this.currentSlotIndex] == "") {
            this.slots[this.currentSlotIndex] := newClip
            this._updateSlotPreview(this.currentSlotIndex, newClip)
            this._showTooltip("✅ Slot " . this.currentSlotIndex . " otomatik dolduruldu (" . StrLen(newClip) . " karakter)", 1000)
            this.currentSlotIndex++
            if (this.currentSlotIndex > this.slots.Length) {
                this.currentSlotIndex := 1
            }
        } else {
            this._showTooltip("⚠️ Slot " . this.currentSlotIndex . " dolu, bir sonrakine geçiliyor", 800)
            this.currentSlotIndex++
            if (this.currentSlotIndex > this.slots.Length) {
                this._showTooltip("⚠️ Tüm slotlar dolu", 800)
                this.currentSlotIndex := 1
            }
        }
    }

    smartPaste(middlePressed := false) {
        ;duruma göre ya disardan kontrol et ya da burdan simdilik her iksinde de
        if (gState.getClipHandler() != gState.clipStatusEnum.memSlot) {
            return
        }

        switch this.clipType {
            case this.clipTypeEnum.copy:
                if (middlePressed && this.middlePasteCheck.Value) {
                    this.clipType := this.clipTypeEnum.paste                    
                    this.currentSlotIndex := 1
                }
            case this.clipTypeEnum.paste:
                if (middlePressed) {
                    this.currentSlotIndex++
                    if (this.currentSlotIndex > this.slots.Length) {
                        this.currentSlotIndex := 1
                    }
                }


        }
        A_Clipboard := this.slots[this.currentSlotIndex]
        ClipWait(0.2)
        SendInput("^v")
        ; OutputDebug("Slot " . this.currentSlotIndex . " yapıştırıldı." . A_Clipboard)

        if (this.currentSlotIndex > this.slots.Length) {
            this.currentSlotIndex := 1
        }
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

    _tapOrHold(shortFn, mediumFn, longFn, shortTime := 300, mediumTime := 800, longTime := 1500) {
        startTime := A_TickCount
        key := A_ThisHotkey
        beepMedium := false
        beepLong := false
        while GetKeyState(key, "P") {
            elapsed := A_TickCount - startTime
            if (elapsed >= mediumTime && !beepMedium) {
                SoundBeep(800, 80)
                beepMedium := true
            }
            if (elapsed >= longTime && !beepLong) {
                SoundBeep(600, 100)
                beepLong := true
            }
            Sleep(20)
        }
        elapsed := A_TickCount - startTime
        if (elapsed < shortTime)
            shortFn.Call()
        else if (elapsed < mediumTime)
            mediumFn.Call()
        else
            longFn.Call()
    }

    _clearSlots() {
        this.slots := []
        Loop 10 {
            this.slots.Push("")
        }
        this.currentSlotIndex := 1
        Loop 10 {
            this._updateSlotPreview(A_Index, "")
        }
        this._showTooltip("🗑️ Slotlar temizlendi, index sıfırlandı", 1000)
    }

    _destroy() {
        this.isDestroyed := true
        Loop 10 {
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