class singleMemorySlot {
    static instance := ""

    static getInstance() {
        if (!singleMemorySlot.instance) {
            singleMemorySlot.instance := singleMemorySlot()
        }
        return singleMemorySlot.instance
    }

    __New() {
        if (singleMemorySlot.instance) {
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
        this.previousState := State.Clipboard.getMode()
        State.Clipboard.setMemSlots()

        this.slots := Array()
        Loop 10 {
            this.slots.Push("")
        }
        this.currentSlotIndex := 1
        this.currentHistoryIndex := 1
        this.gui := ""
        this.slotLV := ""
        this.historyLV := ""
        this.ignoreSameValue := ""
        this.middlePasteCheck := ""
        this.clipHistory := []
        this.isDestroyed := false
        this.activeViewerEnum := {
            slots: true,
            history: false
        }
        ; this.jumpPasteIndex := false belki mod degisince copyden paste bu sekilde alinabilir
        ; ama 10 astiysa ne yapmak lazim o da düsünülmeli
        this.activeList := this.activeViewerEnum.slots
        this.ignoreNextClip := false
        OnClipboardChange(this.clipboardWatcher.Bind(this))

        fullHistory := App.ClipHist.getHistory()
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
            this.gui.Add("Text", "x10 y10 w430 Center", "🔹 F1-F10: Kısa=Slot Yapıştır | Uzun=History Paste | Çift=Slota Kaydet 🔹")

            this.ignoreSameValue := this.gui.Add("CheckBox", "x10 y35 w210 h30", "Veri tekrarını kabul et")

            clearBtn := this.gui.Add("Button", "x230 y35 w210 h30", "🗑️ Slotları Temizle")
            clearBtn.OnEvent("Click", (*) => this._clearSlots())

            this.middlePasteCheck := this.gui.Add("CheckBox", "x10 y75 w350 h20 Checked1", "Orta basım: Aktif slotu yapıştır (Middle Paste)")

            this.slotsHeader := this.gui.Add("Text", "x10 y105 w430 h25 Center BackgroundTrans", "📦 Memory Slots")
            this.slotsHeader.SetFont("Bold")
            this.slotsHeader.OnEvent("Click", (*) => (this._selectSlotViewer(this.currentSlotIndex)))

            this.slotLV := this.gui.Add("ListView", "x10 y130 w430 h220 +HScroll -Multi +LV0x10", ["Slot", "İçerik"])
            this.slotLV.ModifyCol(1, 60)
            this.slotLV.ModifyCol(2, 350)
            this.slotLV.OnEvent("Click", (*) => this._onSlotClick())
            this.slotLV.OnEvent("DoubleClick", (*) => this._onSlotDoubleClick())

            Loop 10 {
                this.slotLV.Add("", A_Index, "")
            }

            this.historyHeader := this.gui.Add("Text", "x10 y360 w430 h25 Center BackgroundTrans", "📋 Clipboard Geçmişi")
            this.historyHeader.SetFont("Bold")
            this.historyHeader.OnEvent("Click", (*) => (this._selectHistoryViewer(this.currentHistoryIndex)))

            this.historyLV := this.gui.Add("ListView", "x10 y390 w430 h220 +HScroll -Multi +LV0x10", ["#", "İçerik"])
            this.historyLV.ModifyCol(1, 60)
            this.historyLV.ModifyCol(2, 350)
            this.historyLV.OnEvent("Click", (*) => this._onHistoryClick())
            this.historyLV.OnEvent("DoubleClick", (*) => this._onHistoryDoubleClick())
            this._populateHistory()
            this._activeViewerBackground()
        } catch as err {
            App.ErrHandler.handleError("GUI oluşturma hatası", err)
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

    ; detectPressType - Return versiyonu
    ; Returns: 1 (short), 2 (long), 4 (double)
    detectPressType(key := "", short := 300, gap := 100) {
        if (key = "") {
            key := SubStr(A_ThisHotkey, -1)
        }

        result := KeyWait(key, "T" (short / 1000))
        if (result) {
            ; Short süre içinde bırakıldı -> Kısa basım, double kontrolü yap
            result := KeyWait(key, "D T" (gap / 1000))
            if (result) {
                ; Gap süresi içinde tekrar basıldı -> Double press
                KeyWait(key)
                return 4
            } else {
                ; Gap süresi geçti, ikinci basım olmadı -> Short press
                return 1
            }
        }

        ; Short timeout oldu, uzun basıldı -> Long press
        KeyWait(key)
        SoundBeep(600, 100)
        return 2
    }
    ; F tuşu handler'ı – senin verdiğin detectPressType ile
    _handleFKey(index) {
        type := this.detectPressType("F" index, 300, 100)
        switch type {
            case 1: this.pasteFromSlot(index), this._selectSlotViewer(index)
            case 2: this._pasteFromHistory(index), this._selectHistoryViewer(index)
            case 4: this._saveToSlot(index)
        }
    }

    ; Kısa basım: o slotu yapıştır
    pasteFromSlot(index) {
        if (index > this.slotsLength || this.slots[index] == "") {
            ShowTip("⚠️ Slot " . index . " boş!", TipType.Warning, 800)
            return
        }
        this.ignoreNextClip := true
        A_Clipboard := this.slots[index]
        ClipWait(0.2)
        SendInput("^v")
        ShowTip(this.slots[index], TipType.Paste, 800)
    }

    ; Uzun basım: o history'yi yapıştır
    _pasteFromHistory(index) {
        if (index > this.clipHistory.Length) {
            ShowTip("⚠️ History " . index . " yok!", TipType.Warning, 800)
            return
        }
        this.ignoreNextClip := true
        A_Clipboard := this.clipHistory[index]
        ClipWait(0.2)
        SendInput("^v")
        ShowTip(this.clipHistory[index], TipType.Paste, 800)
    }

    ; Çift basım: clipboard'ı o slota kaydet
    _saveToSlot(index) {
        SendInput("^c")
        ClipWait(0.2)
        if (A_Clipboard == "") {
            return
        }
        this.slots[index] := A_Clipboard
        this._updateSlotDisplay(index, A_Clipboard)
        this._selectSlotViewer(index)
    }

    _populateHistory() {
        this.historyLV.Delete()
        if (this.clipHistory.Length = 0) {
            this.historyLV.Add("", "", "(Geçmiş boş)")
            return
        }
        Loop this.clipHistory.Length {
            preview := this._makePreview(this.clipHistory[A_Index])

            idx := Format("{:02}", A_Index)
            this.historyLV.Add("", "F" . idx . "...", preview)
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
        row := this.slotLV.GetNext(0)
        if (row) {
            this.currentSlotIndex := row
            this.activeList := this.activeViewerEnum.slots
            this.historyLV.Modify(0, "-Select")
            this.slotLV.Modify(row, "Select Focus Vis")
            this._activeViewerBackground()
        }
    }

    _onSlotDoubleClick() {
        row := this.slotLV.GetNext(0)
        if (!row || row > this.slotsLength || this.slots[row] == "") {
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
            this.activeList := this.activeViewerEnum.history
            this.slotLV.Modify(0, "-Select")
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
        if (!State.Clipboard.isMemSlots) {
            return
        }

        ;ignore clip marked as paste
        if (this.ignoreNextClip) {
            this.ignoreNextClip := false
            return
        }

        newClip := A_Clipboard
        if (newClip = "" || this._isClipInSlots(newClip)) {
            return
        }

        this._autoFillSlot(newClip)

    }

    _autoFillSlot(newClip) {
        ; İlk kopyalama yapıldığında slotlar seçili olur
        if (this.slotsLength < 10) {
            this.currentSlotIndex := this.slotsLength + 1
        } else {
            this.currentSlotIndex := 1
        }
        this.slots[this.currentSlotIndex] := newClip
        this._updateSlotDisplay(this.currentSlotIndex, newClip)
        this._selectSlotViewer(this.currentSlotIndex)
        ShowTip(newClip, TipType.Info, 1000)
        return
    }

    slotsLength {
        get {
            count := 10
            while (count >= 1 && this.slots[count] = "")
                count--
            return count
        }
    }

    _updateSlotDisplay(slotNum, content) {
        preview := this._makePreview(content)
        idx := Format("{:02}", slotNum)
        this.slotLV.Modify(slotNum, "", "F" . idx, preview)
    }

    _selectSlotViewer(slotNum) {
        this.slotLV.Modify(0, "-Select")
        this.historyLV.Modify(0, "-Select")
        this.slotLV.Modify(slotNum, "Select Focus Vis")
        this.activeList := this.activeViewerEnum.slots
        this.currentSlotIndex := slotNum
        this._activeViewerBackground()
    }

    _selectHistoryViewer(histNum) {
        this.slotLV.Modify(0, "-Select")
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
        if (!State.Clipboard.isMemSlots()) {
            return
        }

        if (middlePressed && !this.middlePasteCheck.Value) {
            return
        }

        if (!middlePressed) {
            if (this.activeList == this.activeViewerEnum.slots) {
                this.pasteFromSlot(this.currentSlotIndex)
            } else {
                this._pasteFromHistory(this.currentHistoryIndex)
            }
            return
        }


        if (this.activeList == this.activeViewerEnum.slots) {
            this.pasteFromSlot(this.currentSlotIndex)
            if (this.currentSlotIndex < this.slotsLength) {
                this.currentSlotIndex++
            } else {
                this.currentSlotIndex := 1
            }
            this._selectSlotViewer(this.currentSlotIndex)
        } else {
            this._pasteFromHistory(this.currentHistoryIndex)
            this.currentHistoryIndex++
            if (this.currentHistoryIndex > this.clipHistory.Length) {
                this.currentHistoryIndex := 1
            }
            this._selectHistoryViewer(this.currentHistoryIndex)
        }

    }

    _clearSlots() {
        this.currentSlotIndex := 1
        this.activeList := this.activeViewerEnum.slots
        Loop 10 {
            this.slots[A_Index] := ""
            this.slotLV.Modify(A_Index, "", "F" . A_Index . "..", "")
        }
    }

    _destroy() {
        this.isDestroyed := true
        this.changeHotKeyMode(false)
        State.Clipboard.setMode(this.previousState)
        if (this.gui) {
            this.gui.Destroy()
            this.gui := ""
        }
        singleMemorySlot.instance := ""
    }
}