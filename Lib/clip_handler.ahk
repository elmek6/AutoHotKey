#Include <array_filter>

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

        if !DirExist(AppConst.FILES_DIR) {
            DirCreate(AppConst.FILES_DIR)
        }
        this.loadSlotsFromJson()
        this.loadHistory()
    }

    saveToSlot(slotNumber) {
        local temp := A_Clipboard
        Send("^c")
        Sleep(50)
        try {
            ClipWait(1)  ;1 saniye timeout
            if (A_Clipboard == "") {
                throw Error("Kopyalama başarısız: Pano boş.")
            }
            this.slots[slotNumber] := A_Clipboard
            this.saveSlots()
            this.showClipboardPreview()
        } catch as err {
            A_Clipboard := temp
            return false
        }
        A_Clipboard := temp
        return true
    }

    loadFromSlot(slotNumber) {
        try {
            if (!this.slots.Has(slotNumber)) {
                throw Error("Slot " slotNumber " boş!")
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
            return false
        }
    }

    loadFromHistory(index) {
        try {
            OnClipboardChange(this.clipboardWatcher.Bind(this))  ;persist
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
        content := StrReplace(content, "`r`n", "") ;removes enter
        display := SubStr(content, 1, maxLength)
        if (StrLen(content) > maxLength) {
            display .= "..."
        }
        return display
    }

    hasSlot(slotNumber) {
        return this.slots.Has(slotNumber)
    }

    clearSlot(slotNumber) {
        try {
            if (this.slots.Has(slotNumber)) {
                this.slots.Delete(slotNumber)
                this.saveSlots()
                return true
            }
            return false
        } catch as err {
            errHandler.handleError("Slot silme başarısız: " err.Message)
            return false
        }
    }

    clipboardWatcher(Type) {
        if (Type != 1) {
            return
        }
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

    clearHistory(*) {    ; Buradaki (*) fonksiyona gelen tüm parametreleri yoksaymasını sağlar
        choice := MsgBox("Pano geçmişi silinsin mi?", "Onay", "YesNo")
        if (choice = "Yes") {
            this.history := []
            this.clipLength := 0
            this.lastClip := ""
            this.showMessage("Pano geçmişi temizlendi.")
        }
    }

    saveSlots() {
        try {
            data := Jxon_Dump(this.slots)
            file := FileOpen(AppConst.FILES_DIR "slots.json", "w", "UTF-8")
            if !file {
                throw Error("slots.json açılamadı")
            }
            file.Write(data)
            file.Close()
            return true
        } catch {
            return false
        }
    }

    loadSlotsFromJson() {
        if !FileExist(AppConst.FILES_DIR "slots.json")
            return false
        try {
            file := FileOpen(AppConst.FILES_DIR "slots.json", "r", "UTF-8")
            if !file {
                throw Error("slots.json açılmadı")
            }
            data := file.Read()
            file.Close()
            loadedData := Jxon_Load(&data)
            this.slots := Map()
            for k, v in loadedData {
                integerKey := Integer(k)  ; Key'leri integer'a çevir
                this.slots[integerKey] := v
            }
            return true
        } catch {
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
        } catch {
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
        } catch {
            return false
        }
    }

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

    getHistoryPreviewList() {
        if (this.history.Length = 0) {
            return ["(Boş)"]
        }
        previewList := []
        Loop 9 {
            index := this.history.Length - A_Index + 1
            if (index <= 0)
                break
            text := this.history[index]
            display := StrReplace(SubStr(text, 1, 100), "`n", " ")
            if (StrLen(text) > 100)
                display .= "..."
            previewList.Push("Clip " A_Index ": " display)
        }
        return previewList
    }

    getSlotsPreviewText() {
        previewText := ""
        for slotNumber in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] {
            preview := StrReplace(this.getSlotPreview(slotNumber, 100), "`n", " ")
            previewText .= "Slot " slotNumber ": " preview "`n"
        }
        return Trim(previewText, "`n")
    }

    buildHistoryMenu() {
        historyMenu := Menu()
        historyMenu.Add("Clipboard history win", (*) => SetTimer(() => Send("#v"), -20))
        historyMenu.Add("Search on history", (*) => this.showHistorySearch())
        historyMenu.Add()

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
        slotMenu.Add("Search in slots", (*) => this.showSlotsSearch())
        slotMenu.Add()
        if (this.hasSlot(0)) {
            slotMenu.Add("Slot 0: [x]", (*) => this.loadFromSlot(0))
        }
        for slotNumber in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] {
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
        for slotNumber in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] {
            preview := this.getSlotPreview(slotNumber)
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
        }
    }

    __Delete() {
        if (state.getShouldSaveOnExit) {
            this.saveHistory()
            this.saveSlots()
        }
    }

    showHistorySearch() {
        if (this.history.Length == 0) {
            this.showMessage("Geçmiş boş!")
            return
        }
        ArrayFilter.getInstance().Show(this.history, "Clipboard History Search")
    }

    showSlotsSearch() {
        slotsArray := []
        for slotNumber in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] {
            if (this.hasSlot(slotNumber)) {
                slotsArray.Push(this.getSlotContent(slotNumber))
            }
        }
        if (slotsArray.Length == 0) {
            this.showMessage("Slotlar boş!")
            return
        }
        ArrayFilter.getInstance().Show(slotsArray, "Slotlarda Arama")
    }
}