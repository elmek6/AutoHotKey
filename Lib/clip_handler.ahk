#Include <array_filter>

class ClipSlot {
    __New() {
        this.slots := []
        ; artik 1-13 slotlarini kullaniyoruz
        Loop 13 {
            this.slots.Push(Map("name", "Slot " (A_Index), "content", ""))
        }
    }

    getName(pos) {
        return this.slots[pos]["name"] ? this.slots[pos]["name"] : "Slot " pos
    }

    setName(pos, newName) {
        this.slots[pos]["name"] := newName
    }

    getContent(pos) {
        return this.slots[pos]["content"]
    }

    setContent(pos, newContent) {
        this.slots[pos]["content"] := newContent
    }

    clearContent(pos) {
        this.slots[pos]["content"] := ""
    }

    getSlotPreview(pos, maxLength := 200) {
        content := Trim(this.getContent(pos))
        if (content == "") {
            return "(Boş)"
        }
        content := StrReplace(content, "`r`n", "") ; removes enter
        display := SubStr(content, 1, maxLength)
        if (StrLen(content) > maxLength) {
            display .= "..."
        }
        return display
    }

    saveSlots() {
        try {
            local jsonData := Jxon_Dump(&this.slots) ;&this.slots sekinde yaz v2.1 ile daha iyi hafiza yönetimi
            if !DirExist(AppConst.FILES_DIR) {
                DirCreate(AppConst.FILES_DIR)
            }
            local file := FileOpen(AppConst.FILES_DIR "slots.json", "w", "UTF-8")
            if (!file) {
                throw Error("slots.json yazılamadı")
            }
            file.Write(jsonData)
            file.Close()
            return true
        } catch as err {
            errHandler.handleError("Slot kaydetme başarısız: " err.Message " (Jxon_Dump hatası?)", err)
            return false
        }
    }

    loadSlots() {
        if !FileExist(AppConst.FILES_DIR "slots.json") {
            this.slots := []
            Loop 13 {
                this.slots.Push(Map("name", "Slot " (A_Index), "content", ""))
            }
            return false
        }
        try {
            local file := FileOpen(AppConst.FILES_DIR "slots.json", "r", "UTF-8")
            if (!file) {
                throw Error("slots.json okunamadı")
            }
            local data := file.Read()
            file.Close()
            local loadedData := Jxon_Load(&data)
            this.slots := []
            Loop 13 {
                if (A_Index <= loadedData.Length && loadedData[A_Index].Has("name") && loadedData[A_Index].Has("content")) {
                    this.slots.Push(Map(
                        "name", loadedData[A_Index]["name"],
                        "content", loadedData[A_Index]["content"]
                    ))
                } else {
                    this.slots.Push(Map("name", "Slot " (A_Index), "content", ""))
                }
            }
            return true
        } catch as err {
            errHandler.handleError("Slot yükleme başarısız: " err.Message)
            this.slots := []
            Loop 13 {
                this.slots.Push(Map("name", "Slot " (A_Index), "content", ""))
            }
            return false
        }
    }
}

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
        this.slotManager := ClipSlot()
        this.history := []
        this.maxHistory := maxHistory
        this.maxClipSize := maxClipSize
        this.lastClip := ""
        this.clipLength := 0

        OnClipboardChange(this.clipboardWatcher.Bind(this))

        if !DirExist(AppConst.FILES_DIR) {
            DirCreate(AppConst.FILES_DIR)
        }
        this.slotManager.loadSlots()
        this.loadHistory()
    }

    promptAndSaveSlot(slotNumber) {
        local temp := A_Clipboard
        Send("^c")
        Sleep(50)
        try {
            ClipWait(1)
            if (A_Clipboard == "") {
                throw Error("Kopyalama başarısız: Pano boş.")
            }
            local content := A_Clipboard
            local preview := StrReplace(SubStr(content, 1, 500), "`n", " ")
            if (StrLen(content) > 500) {
                preview .= "............................."
            }
            local oldName := this.slotManager.getName(slotNumber)
            local title := "Save slot " slotNumber
            local input := InputBox(preview, title, , oldName)
            if (input.Result == "OK" && input.Value != "") {
                this.storeToSlot(slotNumber, content, input.Value)
                this.showMessage("Slot " slotNumber " : " input.Value)
                this.showClipboardPreview()
                return true
            } else {
                this.showMessage("iptal edildi.")
                return false
            }
        } catch as err {
            errHandler.handleError("Slot kaydetme/adlandırma başarısız", err)
            return false
        } finally {
            A_Clipboard := temp
        }
    }

    storeToSlot(slotNumber, content, name) {
        try {
            this.slotManager.setContent(slotNumber, content)
            this.slotManager.setName(slotNumber, name)
            this.slotManager.saveSlots()
            return true
        } catch as err {
            errHandler.handleError("Slot kaydetme başarısız: ", err)
            return false
        }
    }


    loadFromSlot(slotNumber) {
        try {
            A_Clipboard := this.slotManager.getContent(slotNumber)
            ClipWait(1)
            if (A_Clipboard == "") {
                throw Error("Pano yükleme başarısız.")
            }
            Sleep(20)
            if (state.isActiveClass("Qt5QWindowIcon")) { ;ilerde appprofile alinabilir
                SendText(A_Clipboard)
            } else {
                SendInput("^v")
            }
            return true
        } catch as err {
            errHandler.handleError("Slot yükleme başarısız: " err.Message)
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
            errHandler.handleError("History yükleme başarısız: " err.Message)
            return false
        } finally {
            OnClipboardChange(this.clipboardWatcher, 1)
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

    saveHistory() {
        try {
            local jsonData := Jxon_Dump(&this.history)
            local file := FileOpen(AppConst.FILE_CLIPBOARD, "w", "UTF-8")
            if (!file) {
                throw Error("clipboards.json yazılamadı")
            }
            file.Write(jsonData)
            file.Close()
            return true
        } catch as err {
            errHandler.handleError("History kaydetme başarısız: " err.Message, err)
            return false
        }
    }

    loadHistory() {
        if !FileExist(AppConst.FILE_CLIPBOARD) {
            return false
        }
        try {
            local file := FileOpen(AppConst.FILE_CLIPBOARD, "r", "UTF-8")
            if (!file) {
                throw Error("clipboards.json okunamadı")
            }
            local data := file.Read()
            file.Close()
            this.history := Jxon_Load(&data)
            this.clipLength := this.history.Length
            if (this.clipLength > 0) {
                this.lastClip := this.history[this.clipLength]
            }
            return true
        } catch as err {
            errHandler.handleError("History yükleme başarısız: " err.Message)
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

    buildSlotMenu() {
        local slotMenu := Menu()
        slotMenu.Add("Search in slots", (*) => this.showSlotsSearch())
        slotMenu.Add()
        Loop 12 {
            local preview := this.slotManager.getSlotPreview(A_Index)
            local displayName := this.slotManager.getName(A_Index)
            slotMenu.Add(displayName " (" A_Index "): " preview,
                ((num) => (*) => this.loadFromSlot(num))(A_Index))
        }
        slotMenu.Add(this.slotManager.getName(13) " (" 13 "): " "[x]",
            (*) => this.loadFromSlot(13))
        return slotMenu
    }

    getSlotsPreviewText() {
        previews := []
        Loop 12 {
            local preview := StrReplace(this.slotManager.getSlotPreview(A_Index, 100), "`n", " ")
            local displayName := this.slotManager.getName(A_Index)
            previews.Push(displayName " (" A_Index "): " preview)
        }
        previews.Push(displayName " (" 0 "): " "[x]")
        return previews
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
            previewList.Push("Clip " A_Index ": " display)
        }
        return previewList
    }

    buildHistoryMenu() {
        local historyMenu := Menu()
        historyMenu.Add("Clipboard history win", (*) => SetTimer(() => Send("#v"), -20))
        historyMenu.Add("Search on history", (*) => this.showHistorySearch())
        historyMenu.Add()

        Loop this.history.Length {
            local index := this.history.Length - A_Index + 1
            local text := this.history[index]
            local menuIndex := A_Index
            this._addClipToMenu(historyMenu, "Clip " menuIndex ": ", text)
        }

        historyMenu.Add()
        historyMenu.Add("Clear history", this.clearHistory.Bind(this))
        return historyMenu
    }

    buildSaveSlotMenu() {
        local saveSlotMenu := Menu()
        Loop 13 {
            local preview := this.slotManager.getSlotPreview(A_Index)
            local displayName := this.slotManager.getName(A_Index)
            saveSlotMenu.Add(displayName " (" A_Index "): " preview,
                ((num) => (*) => this.promptAndSaveSlot(num))(A_Index))
        }
        return saveSlotMenu
    }

    _addClipToMenu(menu, prefix, text) {
        local display := SubStr(text, 1, 100)
        if (StrLen(text) > 100)
            display .= "..."
        menu.Add(prefix . display, (*) => (A_Clipboard := text, Send("^v")))
    }

    press(commands) {
        try {
            if (commands is Array) {
                for cmd in commands {
                    if (InStr(cmd, "{Sleep")) {
                        local sleepTime := RegExReplace(cmd, ".*{Sleep (\d+)}.*", "$1")
                        Sleep(sleepTime)
                    } else {
                        Send(cmd)
                    }
                }
            } else {
                Send(commands)
            }
        } catch as err {
            errHandler.handleError("Komut çalıştırma başarısız: " err.Message)
        }
    }

    __Delete() {
        if (state.getShouldSaveOnExit) {
            this.saveHistory()
            this.slotManager.saveSlots()
        }
    }

    showHistorySearch() {
        if (this.history.Length == 0) {
            this.showMessage("Geçmiş boş!")
            return
        }
        ArrayFilter.getInstance().Show(this.history, "Clipboard History Search")
    }

    ; showSlotsSearch() {
    ;     local slotsArray := []
    ;     Loop 13 {
    ;         if (StrLen(this.slotManager.getContent(A_Index)) > 0)
    ;             slotsArray.Push(this.slotManager.getContent(A_Index))
    ;     }
    ;     if (slotsArray.Length == 0) {
    ;         this.showMessage("Slotlar boş!")
    ;         return
    ;     }
    ;     ArrayFilter.getInstance().Show(slotsArray, "Slotlarda Arama")
    ; }

    showSlotsSearch() {
        local slotsArray := []
        Loop 12 {
            if (StrLen(this.slotManager.getContent(A_Index)) > 0) {
                slotsArray.Push(Map(
                    "slotNumber", A_Index,
                    "name", this.slotManager.getName(A_Index),
                    "content", this.slotManager.getContent(A_Index)
                ))
            }
        }
        if (slotsArray.Length == 0) {
            this.showMessage("Slotlar boş!")
            return
        }
        ArrayFilter.getInstance().Show(slotsArray, "Slotlarda Arama")
    }
}