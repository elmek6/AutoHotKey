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
        this.currentHistoryIndex := 1
        this.gui := ""
        this.slotsLV := ""
        this.historyLV := ""
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
        this.activeViewerEnum := {
            slots: true,
            history: false
        }
        this.clipType := this.clipTypeEnum.copy
        this.activeList := this.activeViewerEnum.history
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
    }

    _createGui() {
        try {
            this.gui := Gui("+AlwaysOnTop +ToolWindow +MinimizeBox", "💾 Hafıza Slotları")
            this.gui.OnEvent("Close", (*) => this._destroy())
            this.gui.OnEvent("Escape", (*) => this._destroy())
            this.gui.SetFont("s9", "Segoe UI")

            this.gui.Add("Text", "x10 y10 w430 Center", "🔹 F1-F10: Kısa=Slot Yapıştır | Uzun=History Paste 🔹")

            this.toggleBtn := this.gui.Add("Button", "x10 y35 w210 h30", this.clipType ? "🟢 Smart Mode: Aktif (Copy)" : "🔴 Smart Mode: Pasif")
            this.toggleBtn.OnEvent("Click", (*) => this._toggleSmartMode())

            clearBtn := this.gui.Add("Button", "x230 y35 w210 h30", "🗑️ Slotları Temizle")
            clearBtn.OnEvent("Click", (*) => this._clearSlots())

            this.middlePasteCheck := this.gui.Add("CheckBox", "x10 y75 w350 h20 Checked1", "Orta basım: Aktif slotu yapıştır (Middle Paste)")
            this.middlePasteCheck.OnEvent("Click", (*) => this._showTooltip(this.middlePasteCheck.Value ? "🖱️ Orta basım → Yapıştır aktif" : "🖱️ Orta basım → Devre dışı", 1000))

            slotsHeader := this.gui.Add("Text", "x10 y105 w430 h25 Center BackgroundTrans", "📦 Memory Slots")
            slotsHeader.SetFont("Bold")
            slotsHeader.Opt("Background0x2196F3 cWhite")

            this.slotsLV := this.gui.Add("ListView", "x10 y130 w430 h220 +HScroll -Multi +LV0x10", ["Slot", "İçerik"])
            this.slotsLV.ModifyCol(1, 60)
            this.slotsLV.ModifyCol(2, 350)
            this.slotsLV.OnEvent("Click", (*) => this._onSlotClick())
            this.slotsLV.OnEvent("DoubleClick", (*) => this._onSlotDoubleClick())

            Loop singleMemorySlots.MAX_SLOTS {
                idx := Format("{:02}", A_Index)
                this.slotsLV.Add("", "f" idx, "-")
            }


            historyHeader := this.gui.Add("Text", "x10 y360 w430 h25 Center BackgroundTrans", "📋 Clipboard Geçmişi")
            historyHeader.SetFont("Bold")
            historyHeader.Opt("Background0x4CAF50 cWhite")

            this.historyLV := this.gui.Add("ListView", "x10 y390 w430 h220 +HScroll -Multi +LV0x10", ["#", "İçerik"])
            this.historyLV.ModifyCol(1, 60)
            this.historyLV.ModifyCol(2, 350)
            this.historyLV.OnEvent("Click", (*) => this._onHistoryClick())
            this.historyLV.OnEvent("DoubleClick", (*) => this._onHistoryDoubleClick())

            this._populateHistory()
            if (this.clipHistory.Length > 0) {
                this.historyLV.Modify(1, "Select Focus Vis")
            }

            this.savedHwnd := this.gui.hwnd
        } catch as err {
            gErrHandler.handleError("GUI oluşturma hatası", err)
        }
    }

    _populateHistory() {
        this.historyLV.Delete()
        if (this.clipHistory.Length = 0) {
            this.historyLV.Add("", "", "(Geçmiş boş)")
            return
        }
        Loop this.clipHistory.Length {
            idx := this.clipHistory.Length - A_Index + 1
            content := this.clipHistory[idx]
            preview := this._makePreview(content)
            this.historyLV.Add("", "F" . A_Index . "..", preview)
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

    _toggleSmartMode() {
        this.clipType := !this.clipType
        if (this.clipType) {
            this.toggleBtn.Text := "🟢 Smart Mode: Aktif (Copy)"
            this._showTooltip("📥 Copy modu aktif: Yeni kopyalamalar slotlara dolacak", 1200)
        } else {
            this.toggleBtn.Text := "🔴 Smart Mode: Pasif"
            this._showTooltip("⏸️ Smart mode kapandı", 1000)
        }
    }

    _onSlotClick() {
        sel := this.slotsLV.GetNext(0)
        if (sel) {
            this.currentSlotIndex := sel
            this.activeList := "slots"
            this.clipType := this.clipTypeEnum.paste
            this.activeList := this.activeViewerEnum.slots
            this.historyLV.Modify(0, "-Select")
            this.slotsLV.Modify(sel, "Select Focus Vis")
        }
    }

    _onSlotDoubleClick() {
        sel := this.slotsLV.GetNext(0)
        if (!sel || sel > this.slots.Length || this.slots[sel] == "") {
            this._showTooltip("⚠️ Slot boş!", 800)
            return
        }
        content := this.slots[sel]
        A_Clipboard := content
        ClipWait(0.5)
        this._showTooltip(content, 700)
    }

    _onHistoryClick() {
        sel := this.historyLV.GetNext(0)
        if (sel) {
            this.currentHistoryIndex := sel
            this.activeList := "history"
            this.clipType := this.clipTypeEnum.paste
            this.activeList := this.activeViewerEnum.history
            this.slotsLV.Modify(0, "-Select")
            this.historyLV.Modify(sel, "Select Focus Vis")
        }
    }

    _onHistoryDoubleClick() {
        sel := this.historyLV.GetNext(0)
        if (!sel || sel > this.clipHistory.Length) {
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
        this._showTooltip(content, 700)
    }

    clipboardWatcher(type) {
        if (gState.getClipHandler() != gState.clipStatusEnum.memSlot) {
            return
        }


        if (this.clipType == this.clipTypeEnum.paste) {
            ;eger slotta olmayan birsey clipboard'a düstüyse bunu yine solata ekle
            if (this.activeList == this.activeViewerEnum.slots)
                for item in this.slots {
                    if (item != A_Clipboard) {
                        OutputDebug("NEW A_Clipboard: " . A_Clipboard . "`r`n")
                        this.clipType := this.clipTypeEnum.copy
                        break
                    }
                }
            return
            ;OutputDebug("clipboardWatcher: type: " . type . ", slots.Length: " . this.slots.Length . "A_Clipboard: " . A_Clipboard . "`r`n")
        }

        newClip := A_Clipboard
        if (newClip = "" || newClip = this.lastClipContent) {
            return
        }

        if (this.clipType == this.clipTypeEnum.copy) {
            this._autoFillSlot(newClip)
        }

        this.lastClipContent := newClip
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
        this._showTooltip(preview, 1000)
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
        this.currentSlotIndex := slotNum
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
    }

    smartPaste(middlePressed := false) {
        if (gState.getClipHandler() != gState.clipStatusEnum.memSlot) {
            return
        }

        if (middlePressed && !this.middlePasteCheck.Value) {
            return
        }

        if (!middlePressed) {
            this._pasteFromSlot()
            return
        }

        ; Middle paste yapıldı clipType paste moduna geç
        this.clipType := this.clipTypeEnum.paste

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
            this._showTooltip("⚠️ Slot " . this.currentSlotIndex . " boş!", 800)
            return
        }

        A_Clipboard := this.slots[this.currentSlotIndex]
        ClipWait(0.2)
        SendInput("^v")
    }

    _pasteFromHistory() {
        if (this.currentHistoryIndex > this.clipHistory.Length) {
            this._showTooltip("⚠️ History boş!", 800)
            return
        }

        realIdx := this.clipHistory.Length - this.currentHistoryIndex + 1
        content := this.clipHistory[realIdx]
        A_Clipboard := content
        ClipWait(0.2)
        SendInput("^v")
    }

    _showTooltip(msg, duration := 1200) {
        ToolTip(msg, , , 1)
        SetTimer(() => ToolTip(), -duration)
    }

    _clearSlots() {
        this.slots := []
        this.currentSlotIndex := 1
        Loop singleMemorySlots.MAX_SLOTS {
            this.slotsLV.Modify(A_Index, "", "F" . A_Index . "..", "(Boş)")
        }
        this._showTooltip("🗑️ Slotlar temizlendi, index sıfırlandı", 1000)
    }

    _destroy() {
        this.isDestroyed := true

        gState.setClipHandler(this.previousState)

        this.savedHwnd := 0
        if (this.gui) {
            this.gui.Destroy()
            this.gui := ""
        }
        singleMemorySlots.instance := ""
    }
}