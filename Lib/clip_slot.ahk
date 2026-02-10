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
        this.groups := Map()  ; Key: groupName (string), Value: grup Map'i
        this.defaultGroupName := ""
        this.allGroupNames := []
        this.loadSlots()
        if (this.groups.Count == 0) {
            this.initializeDefaultGroups()
        }
    }
    initializeDefaultGroups() {
        this.groups[""] := Map("groupName", "", "values", [])
        Loop 10 {
            this.groups[""]["values"].Push(Map("name", "Slot " . A_Index, "content", ""))
        }
        this.saveSlots()
    }
    getGroupsName() {
        this.allGroupNames := []
        for name in this.groups {
            if (name != "") {
                this.allGroupNames.Push(name)
            }
        }
        return this.allGroupNames
    }
    setDefaultGroup(newName) {
        try {
            if (newName != "" && !this.groups.Has(newName)) {
                throw Error("Grup bulunamadı: " . newName)
            }
            local fullData := this.readFullJson()
            fullData["defaultGroupName"] := newName
            local jsonStr := jsongo.Stringify(fullData)
            local file := FileOpen(Path.Slot, "w", "UTF-8")
            if (!file) {
                throw
            }
            file.Write(jsonStr)
            file.Close()
            this.loadSlots()
            return true
        } catch as err {
            App.ErrHandler.backupOnError("ClipSlot.setDefaultGroup!", Path.Slot)
            return false
        }
    }
    addGroup(newGroupName) {
        if (newGroupName == "" || this.groups.Has(newGroupName)) {
            return
        }
        local newGroup := Map("groupName", newGroupName, "values", [])
        Loop 10 {
            newGroup["values"].Push(Map("name", "Slot " . A_Index, "content", ""))
        }

        this.groups[newGroupName] := newGroup
        this.saveSlots()
    }
    getName(groupName := this.defaultGroupName, slotIndex) {
        if (!this.groups.Has(groupName)) {
            return ""
        }
        values := this.groups[groupName]["values"]
        return (slotIndex >= 1 && slotIndex <= values.Length) ? values[slotIndex]["name"] : ""
    }
    setName(groupName := this.defaultGroupName, slotIndex, newName) {
        if (!this.groups.Has(groupName)) {
            return
        }
        values := this.groups[groupName]["values"]
        while (slotIndex > values.Length) {
            values.Push(Map("name", "Slot " . (values.Length + 1), "content", ""))
        }
        values[slotIndex]["name"] := newName
    }
    getContent(groupName := this.defaultGroupName, slotIndex) {
        if (!this.groups.Has(groupName)) {
            return ""
        }
        values := this.groups[groupName]["values"]
        return (slotIndex <= values.Length) ? values[slotIndex]["content"] : ""
    }
    setContent(groupName := this.defaultGroupName, slotIndex, newContent) {
        if (!this.groups.Has(groupName)) {
            return
        }
        values := this.groups[groupName]["values"]
        while (slotIndex > values.Length) {
            values.Push(Map("name", "Slot " . (values.Length + 1), "content", ""))
        }
        values[slotIndex]["content"] := newContent
    }
    getSlotPreview(groupName := this.defaultGroupName, slotIndex, maxLength := 200) {
        if (groupName == "" && slotIndex == 10) {
            return "***"
        }
        content := Trim(this.getContent(groupName, slotIndex))
        if (content == "") {
            return "(Boş)"
        }
        content := StrReplace(content, "`r`n", " ")
        display := SubStr(content, 1, maxLength)
        if (StrLen(content) > maxLength) {
            display .= "..."
        }
        return display
    }
    saveSlots() {
        try {
            local fullData := this.readFullJson()
            ; Map'ten array'e dönüştür (JSON için)
            local groupsArray := []
            if (this.groups.Has("")) {
                groupsArray.Push(this.groups[""])
            }
            for groupName, group in this.groups {
                if (groupName != "") {
                    groupsArray.Push(group)
                }
            }
            fullData["groups"] := groupsArray
            fullData["defaultGroupName"] := this.defaultGroupName
            local jsonStr := jsongo.Stringify(fullData)
            local file := FileOpen(Path.Slot, "w", "UTF-8")
            if (!file) {
                throw
            }
            file.Write(jsonStr)
            file.Close()
            return true
        } catch as err {
            App.ErrHandler.backupOnError("ClipSlot.saveSlots!", Path.Slot)
            return false
        }
    }
    readFullJson() {
        if !FileExist(Path.Slot) {
            return Map("defaultGroupName", "", "groups", [])
        }
        try {
            local file := FileOpen(Path.Slot, "r", "UTF-8")
            if (!file) {
                throw
            }
            local data := file.Read()
            file.Close()
            return jsongo.Parse(data)
        } catch as err {
            App.ErrHandler.backupOnError("ClipSlot.readFullJson!", Path.Slot)
            App.ErrHandler.handleError("readFullJson! JSON okunamadı: " . err.Message, err)
            return Map("defaultGroupName", "", "groups", [])
        }
    }
    loadSlots() {
        if !FileExist(Path.Slot) {
            return false
        }
        try {
            local fullData := this.readFullJson()
            this.defaultGroupName := fullData["defaultGroupName"]
            this.groups := Map()
            for group in fullData["groups"] {
                this.groups[group["groupName"]] := group
            }
            return true
        } catch as err {
            App.ErrHandler.handleError("loadSlots! Slot yükleme başarısız: " . err.Message, err)
            return false
        }
    }
    showQuickSlotsMenu() {
        qm := Menu()

        add(groupName) {
            local preview := this.getContent(groupName, A_Index)
            preview := StrReplace(SubStr(preview, 1, 50), "`n", " ")
            if (StrLen(preview) > 50)
                preview .= "..."
            qm.Add(A_Index ": " preview, ((g, idx) => (*) => this.loadFromSlot(g, idx))(groupName, A_Index))
        }

        Loop 9 {
            add("")
        }
        if (this.defaultGroupName != "")
        {
            qm.Add()
            Loop 10 {
                add(this.defaultGroupName)
            }
        }
        qm.Show()
    }
    buildLoadSlotMenu() {
        local loadSlotMenu := Menu()
        loadSlotMenu.Add("Search in slots", (*) => this.showSlotsSearch())
        loadSlotMenu.Add()

        local defaultName := ""
        Loop 10 {
            local preview := this.getSlotPreview(defaultName, A_Index)
            local displayName := this.getName(defaultName, A_Index) || "Slot " . A_Index
            loadSlotMenu.Add(displayName . " (" . A_Index . "): " . preview,
                ((idx) => (*) => this.loadFromSlot(defaultName, idx))(A_Index))
        }

        if (this.groups.Count > 1 && this.defaultGroupName != "") {
            loadSlotMenu.Add()
            local selectedName := this.defaultGroupName
            if (this.groups.Has(selectedName)) {
                Loop 10 {
                    local preview := this.getSlotPreview(selectedName, A_Index)
                    local displayName := this.getName(selectedName, A_Index) || "Slot " . A_Index
                    loadSlotMenu.Add("Tab " . displayName . " (" . A_Index . "): " . preview,
                        ((idx) => (*) => this.loadFromSlot(selectedName, idx))(A_Index))
                }
            }
        }
        loadSlotMenu.Add()
        loadSlotMenu.Add("Grup seç", this.buildGroupMenu())
        return loadSlotMenu
    }
    buildSaveSlotMenu() {
        local saveSlotMenu := Menu()
        local defaultName := ""
        Loop 10 {
            local preview := this.getSlotPreview(defaultName, A_Index)
            local displayName := this.getName(defaultName, A_Index) || "Slot " . A_Index
            saveSlotMenu.Add(displayName . " (" . A_Index . "): " . preview,
                ((idx) => (*) => this.promptAndSaveSlot(defaultName, idx))(A_Index))
        }
        saveSlotMenu.Add()

        if (this.groups.Count > 1 && this.defaultGroupName != "") {
            local selectedName := this.defaultGroupName
            if (this.groups.Has(selectedName)) {
                Loop 10 {
                    local preview := this.getSlotPreview(selectedName, A_Index)
                    local displayName := this.getName(selectedName, A_Index) || "Slot " . A_Index
                    saveSlotMenu.Add("Tab " . displayName . " (" . A_Index . "): " . preview,
                        ((idx) => (*) => this.promptAndSaveSlot(selectedName, idx))(A_Index))
                }
            }
        }
        saveSlotMenu.Add()
        saveSlotMenu.Add("Yeni grup ekle", (*) => this.promptNewGroup())
        return saveSlotMenu
    }
    showSlotsSearch(groupName := "") {
        local slotsArray := []
        local values := this.groups[groupName]["values"]
        Loop Min(9, values.Length) {
            if (StrLen(this.getContent(groupName, A_Index)) > 0) {
                slotsArray.Push(Map(
                    "slotNumber", A_Index,
                    "name", this.getName(groupName, A_Index),
                    "content", this.getContent(groupName, A_Index)
                ))
            }
        }
        if (slotsArray.Length == 0) {
            ShowTip("Slotlar boş!", TipType.Warning, 1000)
            return
        }
        ArrayFilter.getInstance().Show(slotsArray, "Slotlarda Arama")
    }
    promptAndSaveSlot(groupName := this.defaultGroupName, slotIndex) {
        try {
            local content := A_Clipboard

            if (content == "") {
                ShowTip("! Clipboard Empty, Not Saved !", TipType.Warning, 1000)
                return false
            }

            local preview := StrReplace(SubStr(content, 1, 500), "`n", " ")
            if (StrLen(content) > 500) {
                preview .= "............................."
            }

            local oldName := this.getName(groupName, slotIndex)
            local title := "Save to " . (groupName == "" ? "" : groupName " ") . "Slot " . slotIndex
            local input := InputBox(preview, title, , oldName)

            if (input.Result == "OK") {
                local newName := Trim(input.Value)
                if (newName == "") {
                    newName := "Slot " . slotIndex
                }
                this.setContent(groupName, slotIndex, content)
                this.setName(groupName, slotIndex, newName)
                this.saveSlots()
                ShowTip(A_Clipboard, TipType.Info)
                return true
            } else {
                ShowTip("İptal edildi.", TipType.Info, 700)
                return false
            }
        } catch as err {
            App.ErrHandler.handleError("promptAndSaveSlot! Slot kaydetme başarısız: " . err.Message, err)
            return false
        }
    }
    loadFromSlot(groupName, slotIndex) {
        try {
            if (groupName == "" || !this.groups.Has(groupName)) {
                groupName := ""  ; Base grup
            }
            if (!this.groups.Has(groupName)) {
                throw Error("Grup bulunamadı: " . groupName)
            }
            A_Clipboard := this.getContent(groupName, slotIndex)
            ClipWait(0.2)
            if (A_Clipboard == "") {
                ShowTip("Slot boş! Grup: " . App.ClipSlot.defaultGroupName, TipType.Warning, 2000)
            }
            Sleep(20)
            if (State.Window.isClass("Qt5QWindowIcon")) {
                SendText(A_Clipboard)
            } else {
                SendInput("^v")
            }
            return true
        } catch as err {
            App.ErrHandler.handleError("loadFromSlot! Komut çalıştırma başarısız: " . err.Message, err)
            return false
        }
    }

    promptNewGroup() {
        local input := InputBox("What is new group name?")
        if (input.Result == "OK" && Trim(input.Value) != "") {
            this.addGroup(Trim(input.Value))
            this.setDefaultGroup(Trim(input.Value))
            ShowTip("Grup oluşturuldu ve seçildi.", TipType.Success, 800)
        }
    }
    buildGroupMenu() {
        local groupMenu := Menu()
        local allGroups := this.getGroupsName()
        for name in allGroups {
            if (name != "") {
                groupMenu.Add(name, ((n) => (*) => this.setDefaultGroup(n))(name))
            }
        }
        groupMenu.Add()
        groupMenu.Add("Only default slots", (*) => this.setDefaultGroup(""))
        return groupMenu
    }
    __Delete() {
        if (State.Script.getShouldSaveOnExit()) {
            this.saveSlots()
        }
    }
}