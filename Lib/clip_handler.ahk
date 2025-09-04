class ClipboardManager {
    static instance := ""

    static getInstance(maxHistory := 20, maxClipSize := 100000) {
        if (!ClipboardManager.instance) {
            ClipboardManager.instance := ClipboardManager(maxHistory, maxClipSize)
        }
        return ClipboardManager.instance
    }

    __New(maxHistory, maxClipSize) {
        if (ClipboardManager.instance) {
            throw Error("ClipboardManager zaten oluşturulmuş! getInstance kullan.")
        }
        this.slots := Map()
        this.history := []
        this.maxHistory := maxHistory
        this.maxClipSize := maxClipSize
        this.lastClip := ""
        this.clipLength := 0

        OnClipboardChange(this.clipboardWatcher.Bind(this))

        this.loadSlots()
        this.loadHistory()
    }

    ; ===== SLOT YÖNETİMİ =====
    saveToSlot(slotNumber) {
        local temp := A_Clipboard
        Send("^c")
        Sleep(50)
        try {
            ClipWait(1) ;1 saniye timeout
            if (A_Clipboard == "") {
                throw Error("Kopyalama başarısız: Pano boş.")
            }
            this.slots[slotNumber] := A_Clipboard
            this.saveSlotToFile(slotNumber, A_Clipboard)
            this.showClipboardPreview()
        } catch as err {
            this.showMessage("Kopyalama başarısız: " err.Message)
            A_Clipboard := temp
            return false
        }
        A_Clipboard := temp
        return true
    }

    loadFromSlot(slotNumber) {
        try {
            if (!this.slots.Has(slotNumber)) {
                if (!this.loadSlotFromFile(slotNumber)) {
                    throw Error("Slot " slotNumber " boş!")
                }
            }
            A_Clipboard := this.slots[slotNumber]
            ClipWait(1)
            if (A_Clipboard == "") {
                throw Error("Pano yükleme başarısız.")
            }
            Sleep(50)
            Send("^v")
            return true
        } catch as err {
            this.showMessage(err.Message)
            return false
        }
    }

    loadFromHistory(index) {
        try {
            OnClipboardChange(this.clipboardWatcher.Bind(this)) ;persist
            actualIndex := this.history.Length - index + 1
            if (actualIndex > 0 && actualIndex <= this.history.Length) {
                A_Clipboard := this.history[actualIndex]
                ClipWait(1)
                Sleep(50)
                Send("^v")
                return true
            } else {
                throw Error("Geçmişte " index " numaralı kayıt yok.")
            }
        } catch as err {
            this.showMessage(err.Message)
            return false
        } finally {
            OnClipboardChange(this.clipboardWatcher, 1)
        }
    }

    getSlotContent(slotNumber) {
        return this.slots.Has(slotNumber) ? this.slots[slotNumber] : ""
    }

    getSlotPreview(slotNumber, maxLength := 200) {
        content := this.getSlotContent(slotNumber)
        if (content == "") {
            return "(Boş)"
        }
        content := StrReplace(content, "`r`n", "") ; Remove newlines from content
        display := SubStr(content, 1, maxLength)
        if (StrLen(content) > maxLength) {
            display .= "..."
        }
        return display
    }

    hasSlot(slotNumber) {
        return this.slots.Has(slotNumber) || FileExist(slotNumber ".bin")
    }

    clearSlot(slotNumber) {
        try {
            if (this.slots.Has(slotNumber)) {
                this.slots.Delete(slotNumber)
            }
            if (FileExist(slotNumber ".bin")) {
                FileDelete(slotNumber ".bin")
            }
            return true
        } catch {
            this.showMessage("Slot silme başarısız: " slotNumber)
            return false
        }
    }

    ; ===== HISTORY YÖNETİMİ =====
    clipboardWatcher(Type) {
        if (Type != 1) ; sadece text
            return
        local text := A_Clipboard
        if (StrLen(text) = 0)
            return
        if (StrLen(text) > this.maxClipSize)
            return
        if (text = this.lastClip)
            return
        this.addToHistory(text)
    }

    addToHistory(text) {
        this.history.Push(text)
        if (this.history.Length > this.maxHistory) {
            this.history.RemoveAt(1)
        }
        this.clipLength := this.history.Length
        this.lastClip := text
    }

    getHistory() {
        return this.history
    }

    getHistoryItem(index) {
        return (index > 0 && index <= this.history.Length) ? this.history[index] : ""
    }

    clearHistory(*) { ; Buradaki (*) fonksiyona gelen tüm parametreleri yoksaymasını sağlar
        choice := MsgBox("Pano geçmişi silinsin mi?", "Onay", "YesNo")
        if (choice = "Yes") {
            this.history := []
            this.clipLength := 0
            this.lastClip := ""
            this.showMessage("Pano geçmişi temizlendi.")
        }
    }

    ; ===== DOSYA İŞLEMLERİ =====
    saveSlotToFile(slotNumber, content) {
        local fileName := AppConst.FILES_DIR slotNumber ".bin"
        try {
            file := FileOpen(fileName, "w", "UTF-8")
            if !file {
                throw Error("Dosya açılamadı: " fileName)
            }
            file.Write(content)
            file.Close()
            return true
        } catch as err {
            this.showMessage("Dosya yazma hatası: " err.Message)
            return false
        }
    }

    loadSlotFromFile(slotNumber) {
        local fileName := AppConst.FILES_DIR slotNumber ".bin"
        if !FileExist(fileName) {
            return false
        }
        try {
            file := FileOpen(fileName, "r", "UTF-8")
            if !file {
                throw Error("Dosya açılamadı: " fileName)
            }
            local data := file.Read()
            file.Close()
            if (data != "") {
                this.slots[slotNumber] := data
                return true
            }
            return false
        } catch as err {
            this.showMessage("Dosya okuma hatası: " err.Message)
            return false
        }
    }

    saveHistory() {
        try {
            data := Jxon_Dump(this.history)
            file := FileOpen(AppConst.FILE_CLIPBOARD, "w", "UTF-8")
            if !file {
                throw Error("clipHist.json açılamadı")
            }
            file.Write(data)
            file.Close()
            return true
        } catch as err {
            this.showMessage("Geçmiş kaydetme hatası: " err.Message)
            return false
        }
    }

    loadHistory() {
        if !FileExist(AppConst.FILE_CLIPBOARD)
            return false
        try {
            file := FileOpen(AppConst.FILE_CLIPBOARD, "r", "UTF-8")
            if !file {
                throw Error("clipHist.json açılamadı")
            }
            data := file.Read()
            file.Close()
            this.history := Jxon_Load(&data)
            this.clipLength := this.history.Length
            if (this.clipLength > 0)
                this.lastClip := this.history[this.clipLength]
            return true
        } catch as err {
            this.showMessage("Geçmiş yükleme hatası: " err.Message)
            return false
        }
    }

    loadSlots() {
        for slotNumber in [0, 1, 2, 3, 4, 5, 6] {
            this.loadSlotFromFile(slotNumber)
        }
    }

    ; ===== UI İŞLEMLERİ =====
    showClipboardPreview() {
        if (StrLen(A_Clipboard) > 8000) {
            ToolTip(SubStr(A_Clipboard, 1, 8000) . "`n[..................]")
            SetTimer(() => ToolTip(), -800)
        } else {
            ToolTip(A_Clipboard)
            SetTimer(() => ToolTip(), -800)
        }
    }

    showMessage(message, duration := 2000) {
        ToolTip(message)
        SetTimer(() => ToolTip(), -duration)
    }

    ; ===== ÖNİZLEME METİNLERİ =====
    getHistoryPreviewText() {
        if (this.history.Length = 0) {
            return previewText . "(Boş)"
        }

        Loop 9 { ; Sadece ilk 9'u göster
            index := this.history.Length - A_Index + 1
            if (index <= 0)
                break

            text := this.history[index]
            display := StrReplace(SubStr(text, 1, 100), "`n", " ")
            if (StrLen(text) > 100)
                display .= "..."

            previewText .= "Clip " A_Index ": " display "`n"
        }
        return Trim(previewText, "`n")
    }

    getSlotsPreviewText() {
        for slotNumber in [1, 2, 3, 4, 5, 6] {
            preview := StrReplace(this.getSlotPreview(slotNumber, 100), "`n", " ")
            previewText .= "Slot " slotNumber ": " preview "`n"
        }
        return Trim(previewText, "`n")
    }


    ; ===== MENU BUILDERS =====
    buildHistoryMenu() {
        historyMenu := Menu()
        historyMenu.Add("Clipboard history win", (*) => SetTimer(() => Send("#v"), -20))
        historyMenu.Add("Search on history", (*) => SetTimer(() => Send("#v"), -20))
        historyMenu.Add()

        ; En yeniden en eskiye doğru listele
        Loop this.history.Length {
            index := this.history.Length - A_Index + 1
            text := this.history[index]
            menuIndex := A_Index
            this._addClipToMenu(historyMenu, "Clip " menuIndex ": ", text)
        }

        historyMenu.Add()
        historyMenu.Add("Clear history", this.clearHistory.Bind(this))
        return historyMenu
    }

    buildSlotMenu() {
        slotMenu := Menu()
        if (this.hasSlot(0)) {
            slotMenu.Add("Slot 0: [x]", (*) => this.loadFromSlot(0))
        }
        for slotNumber in [1, 2, 3, 4, 5, 6] {
            preview := this.getSlotPreview(slotNumber)
            if (this.hasSlot(slotNumber)) {
                slotMenu.Add("Slot " slotNumber ": " preview,
                           ((num) => (*) => this.loadFromSlot(num))(slotNumber))
            } else {
                slotMenu.Add("Slot " slotNumber ": " preview,
                           (*) => this.showMessage("Slot " slotNumber " boş!"))
            }
        }
        return slotMenu
    }

    buildSaveSlotMenu() {
        saveSlotMenu := Menu()
        for slotNumber in [0, 1, 2, 3, 4, 5, 6] {
            preview := this.getSlotPreview(slotNumber)
            if (preview == "(Boş)") {
                preview := "(empty)"
            }
            saveSlotMenu.Add("Slot " slotNumber ": " preview,
                           ((num) => (*) => this.saveToSlot(num))(slotNumber))
        }
        return saveSlotMenu
    }

    _addClipToMenu(menu, prefix, text) {
        display := SubStr(text, 1, 100)
        if (StrLen(text) > 100)
            display .= "..."
        menu.Add(prefix . display, (*) => (A_Clipboard := text, Send("^v")))
    }

    ; ===== GENERIC SENDER =====
    press(commands) {
        try {
            if (commands is Array) {
                for cmd in commands {
                    if (InStr(cmd, "{Sleep")) {
                        sleepTime := RegExReplace(cmd, ".*{Sleep (\d+)}.*", "$1")
                        Sleep(sleepTime)
                    } else {
                        Send(cmd)
                    }
                }
            } else {
                Send(commands)
            }
        } catch as err {
            this.showMessage("Komut gönderme hatası: " err.Message)
        }
    }

    ; ===== destructor in AHK =====
    __Delete() {
        this.saveHistory()
    }
}