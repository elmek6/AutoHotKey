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
        try {
            if (this.gui && !this.isDestroyed) {
                this.gui.Show()
                WinActivate(this.gui.hwnd)
                return
            }
        }
        this.previousState := gState.getClipHandler()
        gState.setClipHandler(gState.clipStatusEnum.memSlot)

        this.slots := []
        this.currentSlotIndex := 1
        this.currentHistoryIndex := 1
        this.gui := ""
        this.slotsLV := ""
        this.historyLV := ""
        this.ignoreSameValue := ""
        this.middlePasteCheck := ""
        this.clipHistory := []
        this.isDestroyed := false

        this.clipTypeEnum := {
            copy: true,
            paste: false,
        }
        this.activeViewerEnum := {
            slots: true,
            history: false
        }
        this.clipType := this.clipTypeEnum.copy
        this.activeList := this.activeViewerEnum.slots
        OnClipboardChange(this.clipboardWatcher.Bind(this))

        fullHistory := gClipHist.getHistory()
        count := Min(10, fullHistory.Length)
        this.clipHistory := []
        Loop count {
            idx := fullHistory.Length - A_Index + 1
            this.clipHistory.Push(fullHistory[idx])
        }

        this._createGui()
        this.gui.Show("x10 y10 w450 h620")
        this.changeHotKeyMode(true)
    }

    _createGui() {
        try {
            this.gui := Gui("+AlwaysOnTop +ToolWindow +MinimizeBox", "💾 Hafıza Slotları")
            this.gui.OnEvent("Close", (*) => this._destroy())
            this.gui.OnEvent("Escape", (*) => this._destroy())
            this.gui.SetFont("s9", "Segoe UI")

            this.gui.Add("Text", "x10 y10 w430 Center", "🔹 F1-F10: Kısa=Slot Yapıştır | Uzun=History Paste | Çift=Kopyala 🔹")

            this.ignoreSameValue := this.gui.Add("CheckBox", "x10 y35 w210 h30", "Veri tekrarını kabul et")

            clearBtn := this.gui.Add("Button", "x230 y35 w210 h30", "🗑️ Slotları Temizle")
            clearBtn.OnEvent("Click", (*) => this._clearSlots())

            this.middlePasteCheck := this.gui.Add("CheckBox", "x10 y75 w350 h20 Checked1", "Orta basım: Aktif slotu yapıştır (Middle Paste)")

            this.slotsHeader := this.gui.Add("Text", "x10 y105 w430 h25 Center BackgroundTrans", "📦 Memory Slots")
            this.slotsHeader.SetFont("Bold")
            this.slotsHeader.OnEvent("Click", (*) => (this._selectSlot(this.currentSlotIndex)))

            this.slotsLV := this.gui.Add("ListView", "x10 y130 w430 h220 +HScroll -Multi +LV0x10", ["Slot", "İçerik"])
            this.slotsLV.ModifyCol(1, 60)
            this.slotsLV.ModifyCol(2, 350)
            this.slotsLV.OnEvent("Click", (*) => this._onSlotClick())
            this.slotsLV.OnEvent("DoubleClick", (*) => this._onSlotDoubleClick())

            Loop singleMemorySlots.MAX_SLOTS {
                idx := Format("{:02}", A_Index)
                this.slotsLV.Add("", "f" idx, "-")
            }

            this.historyHeader := this.gui.Add("Text", "x10 y360 w430 h25 Center BackgroundTrans", "📋 Clipboard Geçmişi")
            this.historyHeader.SetFont("Bold")
            this.historyHeader.OnEvent("Click", (*) => (this._selectHistory(this.currentHistoryIndex)))

            this.historyLV := this.gui.Add("ListView", "x10 y390 w430 h220 +HScroll -Multi +LV0x10", ["#", "İçerik"])
            this.historyLV.ModifyCol(1, 60)
            this.historyLV.ModifyCol(2, 350)
            this.historyLV.OnEvent("Click", (*) => this._onHistoryClick())
            this.historyLV.OnEvent("DoubleClick", (*) => this._onHistoryDoubleClick())
            this._populateHistory()
            this._activeViewerBackground()
        } catch as err {
            gErrHandler.handleError("GUI oluşturma hatası", err)
        }
    }

    changeHotKeyMode(sw) {
        mode := sw ? "On" : "Off"
        CreateHotkeyHandler(idx) {
            return (*) => this._handleFKey(idx)
        }

        Loop 10 {
            try Hotkey("F" A_Index, sw ? CreateHotkeyHandler(A_Index) : "", mode)
        }
    }

    _populateHistory() {
        this.historyLV.Delete()
        if (this.clipHistory.Length = 0) {
            this.historyLV.Add("", "", "(Geçmiş boş)")
            return
        }
        Loop this.clipHistory.Length {
            preview := this._makePreview(this.clipHistory[A_Index])
            this.historyLV.Add("", "#" . A_Index, preview)
        }
    }

    _makePreview(content) {
        preview := StrReplace(StrReplace(content, "`r`n", " "), "`n", " ")
        preview := RegExReplace(preview, "\s+", " ")
        preview := Trim(preview)
        if (StrLen(preview) > 60) {
            preview := SubStr(preview, 1, 60) . "..."
        }
        return preview ? preview : "(Boş)"
    }

    _onSlotClick() {
        row := this.slotsLV.GetNext(0)
        if (row) {
            this.currentSlotIndex := row
            this.clipType := this.clipTypeEnum.paste
            this.activeList := this.activeViewerEnum.slots
            this.historyLV.Modify(0, "-Select")
            this.slotsLV.Modify(row, "Select Focus Vis")
            this._activeViewerBackground()
        }
    }

    _onSlotDoubleClick() {
        row := this.slotsLV.GetNext(0)
        if (!row || row > this.slots.Length || this.slots[row] == "") {
            OutPutDebug("⚠️ Slot boş!")
            return
        }
        content := this.slots[row]
        A_Clipboard := content
        ClipWait(0.5)
        ShowTip(content, TipType.Paste, 700)
    }

    _onHistoryClick() {
        row := this.historyLV.GetNext(0)
        if (row) {
            this.currentHistoryIndex := row
            this.clipType := this.clipTypeEnum.paste
            this.activeList := this.activeViewerEnum.history
            this.slotsLV.Modify(0, "-Select")
            this.historyLV.Modify(row, "Select Focus Vis")
            this._activeViewerBackground()
        }
    }

    _onHistoryDoubleClick() {
        row := this.historyLV.GetNext(0)
        if (!row || row > this.clipHistory.Length) {
            return
        }
        content := this.clipHistory[row]
        if (content == "") {
            OutPutDebug("⚠️ Seçili item boş!")
            return
        }
        A_Clipboard := content
        ClipWait(0.5)
        ShowTip(content, TipType.Paste, 700)
    }

    _isClipInSlots(clipValue) {
        if (this.ignoreSameValue.Value) {
            return false
        }

        for item in this.slots {
            if (item == clipValue) {
                return true
            }
        }
        return false
    }

    clipboardWatcher(type) {
        if (gState.getClipHandler() != gState.clipStatusEnum.memSlot) {
            return
        }

        newClip := A_Clipboard
        if (newClip = "" || this._isClipInSlots(newClip)) {
            return
        }

        if (this.clipType == this.clipTypeEnum.copy) {
            this._autoFillSlot(newClip)
        }

    }

    _autoFillSlot(newClip) {
        ; İlk kopyalama yapıldığında slotlar seçili olur
        if (this.activeList == this.activeViewerEnum.history) {
            this.activeList := this.activeViewerEnum.slots
        }

        if (this.slots.Length == singleMemorySlots.MAX_SLOTS) {
            place := 1
        } else {
            place := this.slots.Length + 1
        }

        if (place > this.slots.Length) {
            this.slots.Push(newClip)
        } else {
            this.slots[place] := newClip
        }

        this._updateSlotDisplay(place, newClip)
        this._selectSlot(place)
        preview := this._makePreview(newClip)
        ShowTip(preview, TipType.Info, 1000)
        return
    }


    _updateSlotDisplay(slotNum, content) {
        if (slotNum < 1 || slotNum > singleMemorySlots.MAX_SLOTS) {
            return
        }
        preview := this._makePreview(content)
        this.slotsLV.Modify(slotNum, "", "F" . slotNum . "..", preview)
    }

    _selectSlot(slotNum) {
        if (slotNum < 1 || slotNum > singleMemorySlots.MAX_SLOTS) {
            return
        }
        this.slotsLV.Modify(0, "-Select")
        this.historyLV.Modify(0, "-Select")
        this.slotsLV.Modify(slotNum, "Select Focus Vis")
        this.activeList := this.activeViewerEnum.slots
        this.clipType := this.clipTypeEnum.copy
        this.currentSlotIndex := slotNum
        this._activeViewerBackground()
    }

    _selectHistory(histNum) {
        if (histNum < 1 || histNum > this.clipHistory.Length) {
            return
        }
        this.slotsLV.Modify(0, "-Select")
        this.historyLV.Modify(0, "-Select")
        this.historyLV.Modify(histNum, "Select Focus Vis")
        this.activeList := this.activeViewerEnum.history
        this.currentHistoryIndex := histNum
        this._activeViewerBackground()
    }

    _activeViewerBackground() {
        if (this.activeList == this.activeViewerEnum.slots) {
            this.slotsHeader.Opt("Background0x2196F3 cWhite")
            this.historyHeader.Opt("Background0x808080 cWhite")
        } else {
            this.slotsHeader.Opt("Background0x808080 cWhite")
            this.historyHeader.Opt("Background0x4CAF50 cWhite")
        }
    }

    smartPaste(middlePressed := false) {
        if (gState.getClipHandler() != gState.clipStatusEnum.memSlot) {
            return
        }

        if (middlePressed && !this.middlePasteCheck.Value) {
            return
        }

        if (!middlePressed) {
            if (this.activeList == this.activeViewerEnum.slots) {
                this._pasteFromSlot()
            } else {
                this._pasteFromHistory()
            }
            return
        }

        ; Middle paste yapıldı clipType paste moduna geç
        if (this.clipType == this.clipTypeEnum.copy) {
            this.clipType := this.clipTypeEnum.paste
            ; ilk basimsa listeyi bastan al
            if (this.activeList == this.activeViewerEnum.slots && this.slots.Length == this.currentSlotIndex) {
                this.currentSlotIndex := 1
                this._selectSlot(this.currentSlotIndex)
                return
            }
        }


        if (this.activeList == this.activeViewerEnum.slots) {
            this._pasteFromSlot()
            this.currentSlotIndex++
            if (this.currentSlotIndex > this.slots.Length) {
                this.currentSlotIndex := 1
            }
            this._selectSlot(this.currentSlotIndex)
        } else {
            this._pasteFromHistory()
            this.currentHistoryIndex++
            if (this.currentHistoryIndex > this.clipHistory.Length) {
                this.currentHistoryIndex := 1
            }
            this._selectHistory(this.currentHistoryIndex)
        }

    }

    _pasteFromSlot() {
        if (this.currentSlotIndex > this.slots.Length || this.slots[this.currentSlotIndex] == "") {
            ShowTip("⚠️ Slot " . this.currentSlotIndex . " boş!", TipType.Warning, 800)
            return
        }

        A_Clipboard := this.slots[this.currentSlotIndex]
        ClipWait(0.2)
        SendInput("^v")
    }

    _pasteFromHistory() {
        if (this.currentHistoryIndex > this.clipHistory.Length) {
            ShowTip("⚠️ History boş!", TipType.Warning, 800)
            return
        }

        content := this.clipHistory[this.currentHistoryIndex]
        A_Clipboard := content
        ClipWait(0.2)
        SendInput("^v")
    }

    _clearSlots() {
        this.slots := []
        this.currentSlotIndex := 1
        Loop singleMemorySlots.MAX_SLOTS {
            this.slotsLV.Modify(A_Index, "", "F" . A_Index . "..", "(Boş)")
        }
    }

    _destroy() {
        this.isDestroyed := true
        this.changeHotKeyMode(false)

        gState.setClipHandler(this.previousState)

        if (this.gui) {
            this.gui.Destroy()
            this.gui := ""
        }
        singleMemorySlots.instance := ""
    }
}