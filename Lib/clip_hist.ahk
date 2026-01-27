class singleClipHist {
    static instance := ""
    static getInstance(maxHistory, maxClipSize) {
        if (!singleClipHist.instance) {
            singleClipHist.instance := singleClipHist(maxHistory, maxClipSize)
        }
        return singleClipHist.instance
    }
    __New(maxHistory, maxClipSize) {
        if (singleClipHist.instance) {
            throw Error("ClipHist zaten oluşturulmuş! getInstance kullan.")
        }
        this.history := []
        this.maxHistory := maxHistory
        this.maxClipSize := maxClipSize
        this.lastClip := ""
        this.clipLength := 0
        this.autoSaveEvery := 100
        State.Clipboard.setHistory()
        OnClipboardChange(this.clipboardWatcher.Bind(this))
        this.loadHistory()
    }
    clipboardWatcher(Type) {
        if (!State.Clipboard.isHistory()) {
            return
        }
        if (Type == 0) {
            ; OutputDebug ("Clipboard boşaltıldı !!!! degisik bir hata!")
            return
        }
        If (Type == 2) {
            ShowTip("⛵")
            return
        }
        local text := A_Clipboard
        ShowTip(text, TipType.Copy)

        if (StrLen(text) = 0)
            return
        if (StrLen(text) > this.maxClipSize)
            return
        if (text = this.lastClip)
            return
        this.addToHistory(text)
    }
    addToHistory(text) {
        Loop this.history.Length {
            if (this.history[A_Index] == text) {
                this.history.RemoveAt(A_Index)
                break
            }
        }
        this.history.Push(text)
        if (this.history.Length > this.maxHistory) {
            this.history.RemoveAt(1)
        }
        this.clipLength := this.history.Length
        this.lastClip := text

        if (this.autoSaveEvery <= 0) {
            this.autoSaveEvery := 100
            this.saveHistory()
            ; OutputDebug("Autosave yapıldı. Sayaç sıfırlandı.")
        } else {
            ; OutputDebug("Autosave sayacı: " . this.autoSaveEvery)
        }
    }
    getHistory() {
        return this.history
    }
    getHistoryItem(index) {
        return (index > 0 && index <= this.history.Length) ? this.history[index] : ""
    }
    clearHistory() {    ; Buradaki () fonksiyona gelen tüm parametreleri yoksaymasını sağlar
        choice := MsgBox("Pano geçmişi silinsin mi?", "Onay", "YesNo")
        if (choice = "Yes") {
            this.history := []
            this.clipLength := 0
            this.lastClip := ""
            ShowTip("Pano geçmişi temizlendi.", TipType.Info, 1500)
        }
    }
    loadFromHistory(index) {
        try {
            actualIndex := this.history.Length - index + 1
            if (actualIndex > 0 && actualIndex <= this.history.Length) {
                this.ignoreNextChange := true
                A_Clipboard := this.history[actualIndex]
                ClipWait(0.1)
                Send("^v")
                return true
            } else {
                throw Error("Geçmişte " . index . " numaralı kayıt yok.")
            }
        } catch as err {
            App.ErrHandler.handleError("loadFromHistory! History yükleme başarısız: " . err.Message)
            return false
        }
    }
    saveHistory() {
        try {
            local jsonData := jsongo.Stringify(this.history)
            local file := FileOpen(Path.Clipboard, "w", "UTF-8")
            if (!file) {
                throw Error(Path.Clipboard . " yazılamadı")
            }
            file.Write(jsonData)
            file.Close()
            return true
        } catch as err {
            App.ErrHandler.backupOnError("ClipHist.saveHistory!", Path.Clipboard)
            return false
        }
    }
    loadHistory() {
        if !FileExist(Path.Clipboard) {
            return false
        }
        try {
            local file := FileOpen(Path.Clipboard, "r", "UTF-8")
            if (!file) {
                throw Error("clipboards.json okunamadı")
            }
            local data := file.Read()
            file.Close()
            this.history := jsongo.Parse(data)
            this.clipLength := this.history.Length
            if (this.clipLength > 0) {
                this.lastClip := this.history[this.clipLength]
            }
            return true
        } catch as err {
            App.ErrHandler.handleError("History yükleme başarısız: " . err.Message)
            return false
        }
    }

    buildHistoryMenu() {
        local historyMenu := Menu()
        historyMenu.Add("Search on history", (*) => this.showHistorySearch())
        historyMenu.Add()
        Loop Min(30, this.history.Length) { ; this.history.Length {
            local index := this.history.Length - A_Index + 1
            local text := this.history[index]
            local menuIndex := A_Index
            this._addClipToMenu(historyMenu, "Clip " . menuIndex . ": ", text)
        }
        historyMenu.Add()
        historyMenu.Add("Clear history", this.clearHistory.Bind(this))
        return historyMenu
    }

    getHistoryPreviewList() {
        if (this.history.Length = 0) {
            return ["(Boş)"]
        }
        local previewList := []
        Loop 9 {
            local index := this.history.Length - A_Index + 1
            if (index <= 0)
                break
            local text := this.history[index]
            local display := StrReplace(SubStr(text, 1, 100), "`n", " ")
            if (StrLen(text) > 100)
                display .= "..."
            previewList.Push("Clip " . A_Index . ": " . display)
        }
        return previewList
    }
    showHistorySearch() {
        if (this.history.Length == 0) {
            ShowTip("Geçmiş boş!", TipType.Warning, 1500)
            return
        }
        ; History dizisini ters sırada Map formatına dönüştür
        ; (en yeni en üstte görünsün)
        local historyArray := []
        Loop this.history.Length {
            local reverseIndex := this.history.Length - A_Index + 1
            historyArray.Push(Map(
                "slotNumber", A_Index,
                "name", "Clip " . A_Index,
                "content", this.history[reverseIndex]
            ))
        }
        ArrayFilter.getInstance().Show(historyArray, "Clipboard History Search")
    }
    _addClipToMenu(menu, prefix, text) {
        local display := SubStr(text, 1, 60)
        if (StrLen(text) > 60)
            display .= "..."
        menu.Add(prefix . display, (*) => (A_Clipboard := text, Send("^v")))
    }
    press(commands) {
        try {
            if (commands is Array) {
                for cmd in commands {
                    if (InStr(cmd, "{Sleep")) {
                        local sleepTime := RegExReplace(cmd, ".{Sleep (\d+)}.", "$1")
                        Sleep(sleepTime)
                    } else {
                        Send(cmd)
                    }
                }
            } else {
                Send(commands)
            }
        } catch as err {
            App.ErrHandler.handleError("Komut çalıştırma başarısız: " . err.Message)
        }
    }
    showClipboardPreview() {
        ShowTip(A_Clipboard, TipType.Info)
    }

    __Delete() {
        if (State.Script.getShouldSaveOnExit) {
            this.saveHistory()
        }
    }
}