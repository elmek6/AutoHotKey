#Include <array_filter>
class singleClipSlot {
    static instance := ""
    static getInstance() {
        if (!singleClipSlot.instance) {
            singleClipSlot.instance := singleClipSlot()
        }
        return singleClipSlot.instance
    }
    __New() {
        if (singleClipSlot.instance) {
            throw Error("ClipSlot zaten oluşturulmuş! getInstance kullan.")
        }
        this.slots := []
        Loop 10 {
            this.slots.Push(Map("name", "Slot " . A_Index, "content", ""))
        }
        this.loadSlots()
    }
    getName(pos) {
        return this.slots[pos]["name"] ? this.slots[pos]["name"] : "Slot " . pos
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
        content := StrReplace(content, "`r`n", " ") ; removes enter
        display := SubStr(content, 1, maxLength)
        if (StrLen(content) > maxLength) {
            display .= "..."
        }
        return display
    }
    saveSlots() {
        try {
            local jsonData := jsongo.Stringify(this.slots)
            local file := FileOpen(AppConst.FILES_DIR . "slots.json", "w", "UTF-8")
            if (!file) {
                throw
            }
            file.Write(jsonData)
            file.Close()
            return true
        } catch as err {
            gErrHandler.handleError("Slot kaydetme başarısız: " . err.Message, err)
            return false
        }
    }
    loadSlots() {
        if !FileExist(AppConst.FILES_DIR . "slots.json") {
            this.initializeEmptySlots()
            return false
        }
        try {
            local file := FileOpen(AppConst.FILES_DIR . "slots.json", "r", "UTF-8")
            if (!file) {
                throw
            }
            local data := file.Read()
            file.Close()
            local loadedData := jsongo.Parse(data)
            this.slots := []
            Loop 10 {
                if (A_Index <= loadedData.Length && loadedData[A_Index].Has("name") && loadedData[A_Index].Has("content")) {
                    this.slots.Push(Map(
                        "name", loadedData[A_Index]["name"],
                        "content", loadedData[A_Index]["content"]
                    ))
                } else {
                    this.slots.Push(Map("name", "Slot " . A_Index, "content", ""))
                }
            }
            return true
        } catch as err {
            gErrHandler.handleError("Slot yükleme başarısız: " . err.Message)
            this.initializeEmptySlots()
            return false
        }
    }
    initializeEmptySlots() { ;*
        this.slots := []
        Loop 10 {
            this.slots.Push(Map("name", "Slot " . A_Index, "content", ""))
        }
    }
    promptAndSaveSlot(slotNumber) {
        local temp := A_Clipboard
        Send("^c")
        Sleep(50)
        try {
            ClipWait(1)
            if (A_Clipboard == "") {
                throw
            }
            local content := A_Clipboard
            local preview := StrReplace(SubStr(content, 1, 500), "`n", " ")
            if (StrLen(content) > 500) {
                preview .= "............................."
            }
            local oldName := this.getName(slotNumber)
            local title := "Save slot " . slotNumber
            local input := InputBox(preview, title, , oldName)
            if (input.Result == "OK" && input.Value != "") {
                this.storeToSlot(slotNumber, content, input.Value)
                this.showMessage("Slot " . slotNumber . " : " . input.Value)
                this.showClipboardPreview()
                return true
            } else {
                this.showMessage("iptal edildi.")
                return false
            }
        } catch as err {
            gErrHandler.handleError("Slot kaydetme/adlandırma başarısız", err)
            return false
        } finally {
            A_Clipboard := temp
        }
    }
    storeToSlot(slotNumber, content, name) {
        try {
            this.setContent(slotNumber, content)
            this.setName(slotNumber, name)
            this.saveSlots()
            return true
        } catch as err {
            gErrHandler.handleError("storeToSlot! Slot kaydetme başarısız: ", err)
            return false
        }
    }
    loadFromSlot(slotNumber) {
        try {
            A_Clipboard := this.getContent(slotNumber)
            ClipWait(1)
            if (A_Clipboard == "") {
                throw
            }
            Sleep(20)
            if (gState.isActiveClass("Qt5QWindowIcon")) { ;ilerde appprofile alınabilir
                SendText(A_Clipboard)
            } else {
                SendInput("^v")
            }
            return true
        } catch as err {
            gErrHandler.handleError("loadFromSlot! Slot yükleme başarısız: " . err.Message)
            return false
        }
    }
    buildSlotMenu() {
        local slotMenu := Menu()
        slotMenu.Add("Search in slots", (*) => this.showSlotsSearch())
        slotMenu.Add()
        Loop 9 {
            local preview := this.getSlotPreview(A_Index)
            local displayName := this.getName(A_Index)
            slotMenu.Add(displayName . " (" . A_Index . "): " . preview,
                ((num) => (*) => this.loadFromSlot(num))(A_Index))
        }
        slotMenu.Add(this.getName(10) . " (" . 10 . "): " . "[x]",
            (*) => this.loadFromSlot(10))
        return slotMenu
    }
    buildSaveSlotMenu() {
        local saveSlotMenu := Menu()
        Loop 10 {
            local preview := this.getSlotPreview(A_Index)
            local displayName := this.getName(A_Index)
            saveSlotMenu.Add(displayName . " (" . A_Index . "): " . preview,
                ((num) => (*) => this.promptAndSaveSlot(num))(A_Index))
        }
        return saveSlotMenu
    }
    getSlotsPreviewText() {
        previews := []
        Loop 9 {
            local preview := StrReplace(this.getSlotPreview(A_Index, 100), "`n", " ")
            local displayName := this.getName(A_Index)
            previews.Push(displayName . " (" . A_Index . "): " . preview)
        }
        previews.Push(displayName . " (" . 0 . "): " . "[x]")
        return previews
    }
    showSlotsSearch() {
        local slotsArray := []
        Loop 9 {
            if (StrLen(this.getContent(A_Index)) > 0) {
                slotsArray.Push(Map(
                    "slotNumber", A_Index,
                    "name", this.getName(A_Index),
                    "content", this.getContent(A_Index)
                ))
            }
        }
        if (slotsArray.Length == 0) {
            this.showMessage("Slotlar boş!")
            return
        }
        ArrayFilter.getInstance().Show(slotsArray, "Slotlarda Arama")
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
            gErrHandler.handleError("Komut çalıştırma başarısız: " . err.Message)
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
    __Delete() {
        if (gState.getShouldSaveOnExit) {
            this.saveSlots()
        }
    }
}